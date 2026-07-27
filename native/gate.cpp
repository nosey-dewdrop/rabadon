// rabadon-gate — the native hot path.
//
// One binary, zero dependencies, C++17. Reads one Claude Code hook event as
// JSON on stdin, gives its verdict via exit code (0 allow, 2 refuse), appends
// the evidence to the spool, and best-effort pushes it to a live watcher over
// the unix socket. The deterministic PreToolUse path lives here entirely; the
// cold paths (PostToolUse test analysis, diagnosis, push-gate suite runs,
// session bookkeeping) are delegated to the Node gate, which keeps its full
// behavior. Contract: SPEC.md §1 — any error in the gate itself fails OPEN.
//
// Why native: this process runs on EVERY tool call of a session. A node
// process pays its runtime startup each time; this binary answers in
// microseconds-to-low-milliseconds, measured by native/bench.mjs and
// published, not claimed.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <regex>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <csignal>
#include <cerrno>

using std::string;

// ---------- tiny JSON field extraction (enough for hook payloads) ----------
// We need a handful of known string fields. Values are JSON-escaped; we
// unescape the common sequences. Anything unparseable -> empty -> fail open.

static string json_unescape(const string& s) {
  string out;
  out.reserve(s.size());
  for (size_t i = 0; i < s.size(); i++) {
    if (s[i] == '\\' && i + 1 < s.size()) {
      char c = s[++i];
      switch (c) {
        case 'n': out += '\n'; break;
        case 't': out += '\t'; break;
        case 'r': out += '\r'; break;
        case '"': out += '"'; break;
        case '\\': out += '\\'; break;
        case '/': out += '/'; break;
        case 'u': i += 4; out += '?'; break; // rules never need exact unicode
        default: out += c;
      }
    } else out += s[i];
  }
  return out;
}

// find "key" : "value" starting at `from`; returns unescaped value
static string get_str(const string& j, const string& key, size_t from = 0) {
  const string pat = "\"" + key + "\"";
  size_t k = j.find(pat, from);
  if (k == string::npos) return "";
  size_t colon = j.find(':', k + pat.size());
  if (colon == string::npos) return "";
  size_t q = j.find('"', colon);
  // make sure only whitespace sits between ':' and the opening quote
  for (size_t i = colon + 1; i < q && i < j.size(); i++)
    if (!isspace((unsigned char)j[i])) return "";
  if (q == string::npos) return "";
  string raw;
  for (size_t i = q + 1; i < j.size(); i++) {
    if (j[i] == '\\' && i + 1 < j.size()) { raw += j[i]; raw += j[i + 1]; i++; continue; }
    if (j[i] == '"') break;
    raw += j[i];
  }
  return json_unescape(raw);
}

static long long get_num(const string& j, const string& key) {
  const string pat = "\"" + key + "\"";
  size_t k = j.find(pat);
  if (k == string::npos) return 0;
  size_t colon = j.find(':', k + pat.size());
  if (colon == string::npos) return 0;
  return atoll(j.c_str() + colon + 1);
}

static string json_escape(const string& s) {
  string out;
  for (char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if ((unsigned char)c < 0x20) { char b[8]; snprintf(b, 8, "\\u%04x", c); out += b; }
        else out += c;
    }
  }
  return out;
}

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return "";
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

static bool file_exists(const string& p) { struct stat st; return stat(p.c_str(), &st) == 0; }

static long long now_ms() {
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static string iso8601_now() {
  char iso[32]; time_t t = time(nullptr); struct tm tmv; gmtime_r(&t, &tmv);
  strftime(iso, 32, "%Y-%m-%dT%H:%M:%SZ", &tmv);
  return string(iso);
}

// ---------- bounded claude subprocess (the incident brain / drift judge) ----------
// fork/exec `claude -p --output-format text [--model M]`, write the prompt to
// the child's stdin, read its stdout with a wall-clock deadline, SIGKILL on
// timeout. RABADON_OFF=1 is set in the CHILD env — the child itself fires this
// very gate (it runs `claude`), and without the flag the supervisor would
// supervise itself into a recursion. Returns "" on timeout/failure -> the
// caller treats it as "no verdict", the deterministic path still runs.
static string run_claude(const string& prompt, int timeoutSec, const string& model, size_t maxBytes) {
  int inPipe[2], outPipe[2];
  if (pipe(inPipe) != 0) return "";
  if (pipe(outPipe) != 0) { close(inPipe[0]); close(inPipe[1]); return ""; }

  pid_t pid = fork();
  if (pid < 0) { close(inPipe[0]); close(inPipe[1]); close(outPipe[0]); close(outPipe[1]); return ""; }

  if (pid == 0) {
    // child: stdin <- inPipe read end, stdout -> outPipe write end
    dup2(inPipe[0], STDIN_FILENO);
    dup2(outPipe[1], STDOUT_FILENO);
    // silence the child's stderr so it never mixes into the hook's own feedback
    int devnull = open("/dev/null", O_WRONLY);
    if (devnull >= 0) dup2(devnull, STDERR_FILENO);
    close(inPipe[0]); close(inPipe[1]);
    close(outPipe[0]); close(outPipe[1]);
    // the recursion root-fix: the child's own gate must exit 0 immediately
    setenv("RABADON_OFF", "1", 1);
    std::vector<char*> argv;
    argv.push_back(const_cast<char*>("claude"));
    argv.push_back(const_cast<char*>("-p"));
    argv.push_back(const_cast<char*>("--output-format"));
    argv.push_back(const_cast<char*>("text"));
    if (!model.empty()) {
      argv.push_back(const_cast<char*>("--model"));
      argv.push_back(const_cast<char*>(model.c_str()));
    }
    argv.push_back(nullptr);
    execvp("claude", argv.data());
    _exit(127); // exec failed -> parent reads EOF, treats as no verdict
  }

  // parent
  close(inPipe[0]);
  close(outPipe[1]);
  // feed the prompt, then close so the child sees EOF on stdin
  { size_t off = 0; while (off < prompt.size()) {
      ssize_t w = write(inPipe[1], prompt.data() + off, prompt.size() - off);
      if (w <= 0) break; off += (size_t)w;
  } }
  close(inPipe[1]);

  fcntl(outPipe[0], F_SETFL, O_NONBLOCK);
  string out;
  const long long deadline = now_ms() + (long long)timeoutSec * 1000;
  bool killed = false;
  for (;;) {
    char buf[8192];
    ssize_t r = read(outPipe[0], buf, sizeof(buf));
    if (r > 0) {
      if (out.size() < maxBytes) out.append(buf, (size_t)std::min((size_t)r, maxBytes - out.size()));
      continue;
    }
    if (r == 0) break; // EOF: child closed stdout
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      if (now_ms() > deadline) { kill(pid, SIGKILL); killed = true; break; }
      // reap-if-done check without blocking
      int st; pid_t w = waitpid(pid, &st, WNOHANG);
      if (w == pid) { // child gone; drain any last bytes then break
        for (;;) { ssize_t r2 = read(outPipe[0], buf, sizeof(buf));
          if (r2 <= 0) break;
          if (out.size() < maxBytes) out.append(buf, (size_t)std::min((size_t)r2, maxBytes - out.size())); }
        close(outPipe[0]);
        // trim + report
        size_t a = out.find_first_not_of(" \t\r\n");
        size_t b = out.find_last_not_of(" \t\r\n");
        return a == string::npos ? "" : out.substr(a, b - a + 1);
      }
      struct timespec nap{0, 5 * 1000 * 1000}; nanosleep(&nap, nullptr); // 5ms
      continue;
    }
    break; // real read error
  }
  close(outPipe[0]);
  int st; waitpid(pid, &st, 0);
  if (killed) return "";
  if (WIFEXITED(st) && WEXITSTATUS(st) != 0) return ""; // nonzero exit -> no verdict
  if (WIFSIGNALED(st)) return "";
  size_t a = out.find_first_not_of(" \t\r\n");
  size_t b = out.find_last_not_of(" \t\r\n");
  return a == string::npos ? "" : out.substr(a, b - a + 1);
}

// strip a leading/trailing ```json ... ``` fence (mirrors the JS regex
// /^```(?:json)?\s*|\s*```$/g) then hand the body to the get_* helpers
static string strip_fences(const string& s) {
  string t = s;
  size_t a = t.find_first_not_of(" \t\r\n");
  if (a != string::npos) t = t.substr(a);
  if (t.rfind("```", 0) == 0) {
    t = t.substr(3);
    if (t.rfind("json", 0) == 0) t = t.substr(4);
    size_t nb = t.find_first_not_of(" \t\r\n");
    if (nb != string::npos) t = t.substr(nb);
  }
  size_t e = t.find_last_not_of(" \t\r\n");
  if (e != string::npos) t = t.substr(0, e + 1);
  if (t.size() >= 3 && t.compare(t.size() - 3, 3, "```") == 0) {
    t = t.substr(0, t.size() - 3);
    size_t e2 = t.find_last_not_of(" \t\r\n");
    if (e2 != string::npos) t = t.substr(0, e2 + 1);
  }
  return t;
}

// ---------- generic JSON value (only for incident rule authoring) ----------
// A minimal, order-preserving JSON model used solely to re-read guard.json,
// splice one incident rule into an array, and pretty-print it back exactly as
// JSON.stringify(obj,null,2) would. NOT used on the hot path.
struct JVal {
  enum T { OBJ, ARR, STR, NUM, BOOL, NUL } t = NUL;
  std::vector<std::pair<string, JVal>> obj; // insertion-ordered
  std::vector<JVal> arr;
  string str;       // for STR (unescaped) and NUM (verbatim token)
  bool b = false;

  JVal* get(const string& key) { for (auto& kv : obj) if (kv.first == key) return &kv.second; return nullptr; }
};

struct JParser {
  const string& s; size_t i = 0; bool ok = true;
  explicit JParser(const string& src) : s(src) {}
  void ws() { while (i < s.size() && (s[i]==' '||s[i]=='\t'||s[i]=='\n'||s[i]=='\r')) i++; }
  JVal parse() { ws(); JVal v = value(); ws(); return v; }
  JVal value() {
    ws();
    if (i >= s.size()) { ok = false; return {}; }
    char c = s[i];
    if (c == '{') return object();
    if (c == '[') return array();
    if (c == '"') { JVal v; v.t = JVal::STR; v.str = str(); return v; }
    if (c == 't') { if (s.compare(i,4,"true")==0){i+=4; JVal v; v.t=JVal::BOOL; v.b=true; return v;} ok=false; return {}; }
    if (c == 'f') { if (s.compare(i,5,"false")==0){i+=5; JVal v; v.t=JVal::BOOL; v.b=false; return v;} ok=false; return {}; }
    if (c == 'n') { if (s.compare(i,4,"null")==0){i+=4; JVal v; v.t=JVal::NUL; return v;} ok=false; return {}; }
    return number();
  }
  string str() {
    string out; i++; // opening quote
    while (i < s.size()) {
      char c = s[i++];
      if (c == '\\' && i < s.size()) { out += c; out += s[i++]; continue; } // keep escapes verbatim
      if (c == '"') return out;
      out += c;
    }
    ok = false; return out;
  }
  JVal number() {
    size_t a = i;
    while (i < s.size() && (isdigit((unsigned char)s[i]) || s[i]=='-'||s[i]=='+'||s[i]=='.'||s[i]=='e'||s[i]=='E')) i++;
    if (i == a) { ok = false; return {}; }
    JVal v; v.t = JVal::NUM; v.str = s.substr(a, i - a); return v;
  }
  JVal object() {
    JVal v; v.t = JVal::OBJ; i++; ws();
    if (i < s.size() && s[i] == '}') { i++; return v; }
    while (i < s.size()) {
      ws(); if (i>=s.size()||s[i]!='"'){ok=false;break;}
      string key = str(); ws();
      if (i>=s.size()||s[i]!=':'){ok=false;break;} i++;
      JVal val = value(); if (!ok) break;
      v.obj.push_back({key, val}); ws();
      if (i<s.size() && s[i]==',') { i++; continue; }
      if (i<s.size() && s[i]=='}') { i++; return v; }
      ok = false; break;
    }
    ok = false; return v;
  }
  JVal array() {
    JVal v; v.t = JVal::ARR; i++; ws();
    if (i < s.size() && s[i] == ']') { i++; return v; }
    while (i < s.size()) {
      JVal e = value(); if (!ok) break;
      v.arr.push_back(e); ws();
      if (i<s.size() && s[i]==',') { i++; continue; }
      if (i<s.size() && s[i]==']') { i++; return v; }
      ok = false; break;
    }
    ok = false; return v;
  }
};

// pretty-print with 2-space indent, matching JSON.stringify(v,null,2)
static void jval_print(const JVal& v, string& out, int indent) {
  const string pad(indent * 2, ' ');
  const string pad2((indent + 1) * 2, ' ');
  switch (v.t) {
    case JVal::NUL: out += "null"; break;
    case JVal::BOOL: out += v.b ? "true" : "false"; break;
    case JVal::NUM: out += v.str; break;
    case JVal::STR: out += "\""; out += v.str; out += "\""; break; // str holds already-escaped body
    case JVal::ARR:
      if (v.arr.empty()) { out += "[]"; break; }
      out += "[\n";
      for (size_t k = 0; k < v.arr.size(); k++) {
        out += pad2; jval_print(v.arr[k], out, indent + 1);
        out += (k + 1 < v.arr.size()) ? ",\n" : "\n";
      }
      out += pad; out += "]";
      break;
    case JVal::OBJ:
      if (v.obj.empty()) { out += "{}"; break; }
      out += "{\n";
      for (size_t k = 0; k < v.obj.size(); k++) {
        out += pad2; out += "\""; out += v.obj[k].first; out += "\": ";
        jval_print(v.obj[k].second, out, indent + 1);
        out += (k + 1 < v.obj.size()) ? ",\n" : "\n";
      }
      out += pad; out += "}";
      break;
  }
}

// build a STR leaf whose printed form is a JSON string of `raw`
static JVal jstr(const string& raw) { JVal v; v.t = JVal::STR; v.str = json_escape(raw); return v; }

// ---------- spool + socket emit ----------

struct Emitter {
  string spoolPath, sockPath, runId, pipe;
  bool drill;
  int seq = 0;
  int sockFd = -1;

  void open_sock() {
    sockFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockFd < 0) return;
    fcntl(sockFd, F_SETFL, O_NONBLOCK);
    struct sockaddr_un addr; memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sockPath.c_str(), sizeof(addr.sun_path) - 1);
    if (connect(sockFd, (struct sockaddr*)&addr, sizeof(addr)) < 0 && errno != EINPROGRESS) {
      close(sockFd); sockFd = -1;
    }
  }

  void emit(const string& ev, const string& extraJson) {
    string line = "{\"v\":1,\"seq\":" + std::to_string(++seq) +
      ",\"ts\":" + std::to_string(now_ms()) +
      ",\"run\":\"" + runId + "\",\"pipe\":\"" + json_escape(pipe) + "\",\"ev\":\"" + ev + "\"" +
      (extraJson.empty() ? "" : "," + extraJson) +
      (drill ? ",\"drill\":true" : "") + "}\n";
    std::ofstream f(spoolPath, std::ios::app);
    if (f) f << line;
    if (sockFd >= 0) { ssize_t r = write(sockFd, line.c_str(), line.size()); (void)r; }
  }

  ~Emitter() { if (sockFd >= 0) close(sockFd); }
};

// ---------- rules ----------

struct Rule { string id, pattern, why; };

static std::vector<Rule> parse_rules(const string& guard, const string& section, const string& patKey, const std::vector<string>& disabled) {
  std::vector<Rule> rules;
  size_t sec = guard.find("\"" + section + "\"");
  if (sec == string::npos) return rules;
  size_t arrStart = guard.find('[', sec);
  if (arrStart == string::npos) return rules;
  // walk objects in the array (depth-tracking, strings skipped)
  int depth = 0; size_t objStart = 0;
  for (size_t i = arrStart; i < guard.size(); i++) {
    char c = guard[i];
    if (c == '"') { // skip string
      for (i++; i < guard.size(); i++) { if (guard[i] == '\\') i++; else if (guard[i] == '"') break; }
      continue;
    }
    if (c == '{') { if (depth == 1) objStart = i; depth++; }
    else if (c == '}') {
      depth--;
      if (depth == 1) {
        string obj = guard.substr(objStart, i - objStart + 1);
        Rule r{ get_str(obj, "id"), get_str(obj, patKey), get_str(obj, "why") };
        bool off = false;
        for (const auto& d : disabled) if (d == r.id) off = true;
        if (!r.pattern.empty() && !off) rules.push_back(r);
      }
    }
    else if (c == '[') depth++;
    else if (c == ']') { depth--; if (depth == 0) break; }
  }
  return rules;
}

static std::vector<string> parse_disabled(const string& guard) {
  std::vector<string> out;
  size_t sec = guard.find("\"disabled\"");
  if (sec == string::npos) return out;
  size_t a = guard.find('[', sec), b = guard.find(']', a);
  if (a == string::npos || b == string::npos) return out;
  string body = guard.substr(a, b - a);
  size_t p = 0;
  while ((p = body.find('"', p)) != string::npos) {
    size_t q = body.find('"', p + 1);
    if (q == string::npos) break;
    out.push_back(body.substr(p + 1, q - p - 1));
    p = q + 1;
  }
  return out;
}

static bool rx_test(const string& pattern, const string& text) {
  try {
    std::regex re(pattern, std::regex::ECMAScript | std::regex::icase);
    return std::regex_search(text, re);
  } catch (...) { return false; } // a broken rule must not take the gate down
}

// plain ["a","b"] string array under `key` (regex escapes preserved)
static std::vector<string> parse_str_array(const string& j, const string& key) {
  std::vector<string> out;
  size_t sec = j.find("\"" + key + "\"");
  if (sec == string::npos) return out;
  size_t a = j.find('[', sec), b = j.find(']', a);
  if (a == string::npos || b == string::npos) return out;
  string body = j.substr(a, b - a);
  size_t p = 0;
  while ((p = body.find('"', p)) != string::npos) {
    size_t q = p + 1; string pat;
    for (; q < body.size(); q++) {
      if (body[q] == '\\' && q + 1 < body.size()) { pat += body[q]; pat += body[q + 1]; q++; }
      else if (body[q] == '"') break;
      else pat += body[q];
    }
    out.push_back(json_unescape(pat));
    p = q + 1;
  }
  return out;
}

// ---------- session state: .rabadon/state.json, ONE owner ----------
// Fixed schema, shared with the (retiring) node cold paths:
//   { lastCodeEdit, lastTestPass, lastTestFail, lastTestRun,
//     lastDiagAt, lastDiagSig,
//     sessions: { "<sid16>": { goalPrompt, goalTs, touchedDirs[],
//        fanoutWarned, lastCmd, lastCmdTs, cmdRepeat, actionCount,
//        offTarget, driftChallenged, recent:[{t,s}], recentEv[],
//        tsOffset, tokensOut, tokensIn } } }
// The writer serializes ONLY this schema — which is itself the root fix for
// the stray top-level "s" key: the old JS writer serialized its session
// alias next to the sessions map, doubling every session on every save.

// the balanced {...} object starting at the first '{' at/after `from`
static string take_obj(const string& j, size_t from) {
  size_t a = j.find('{', from);
  if (a == string::npos) return "";
  int depth = 0;
  for (size_t i = a; i < j.size(); i++) {
    char c = j[i];
    if (c == '"') { for (i++; i < j.size(); i++) { if (j[i] == '\\') i++; else if (j[i] == '"') break; } continue; }
    if (c == '{') depth++;
    else if (c == '}') { depth--; if (!depth) return j.substr(a, i - a + 1); }
  }
  return "";
}

static bool get_bool(const string& j, const string& key) {
  const string pat = "\"" + key + "\"";
  size_t k = j.find(pat);
  if (k == string::npos) return false;
  size_t colon = j.find(':', k + pat.size());
  if (colon == string::npos) return false;
  size_t i = colon + 1;
  while (i < j.size() && isspace((unsigned char)j[i])) i++;
  return j.compare(i, 4, "true") == 0;
}

// raw {..} object substrings of the array under `key`
static std::vector<string> parse_obj_array(const string& j, const string& key) {
  std::vector<string> out;
  size_t sec = j.find("\"" + key + "\"");
  if (sec == string::npos) return out;
  size_t arr = j.find('[', sec);
  if (arr == string::npos) return out;
  int depth = 0; size_t objStart = 0;
  for (size_t i = arr; i < j.size(); i++) {
    char c = j[i];
    if (c == '"') { for (i++; i < j.size(); i++) { if (j[i] == '\\') i++; else if (j[i] == '"') break; } continue; }
    if (c == '{') { if (depth == 1) objStart = i; depth++; }
    else if (c == '}') { depth--; if (depth == 1) out.push_back(j.substr(objStart, i - objStart + 1)); }
    else if (c == '[') depth++;
    else if (c == ']') { depth--; if (!depth) break; }
  }
  return out;
}

struct Sess {
  string goalPrompt; long long goalTs = 0;
  std::vector<string> touchedDirs; bool fanoutWarned = false;
  string lastCmd; long long lastCmdTs = 0; int cmdRepeat = 1;
  int actionCount = 0, offTarget = 0, driftChallenged = 0;
  std::vector<std::pair<long long, string>> recent;
  std::vector<string> recentEv;
  long long tsOffset = 0, tokensOut = 0, tokensIn = 0;
};

struct State {
  string path;
  long long lastCodeEdit = 0, lastTestPass = 0, lastTestFail = 0, lastTestRun = 0, lastDiagAt = 0;
  string lastDiagSig;
  std::vector<std::pair<string, Sess>> sessions; // insertion-ordered, max 4

  Sess& session(const string& sid) {
    for (auto& kv : sessions) if (kv.first == sid) return kv.second;
    sessions.push_back({ sid, Sess{} });
    if (sessions.size() > 4) sessions.erase(sessions.begin(), sessions.end() - 4);
    return sessions.back().second;
  }

  void load() {
    const string j = read_file(path);
    if (j.empty()) return;
    lastCodeEdit = get_num(j, "lastCodeEdit");
    lastTestPass = get_num(j, "lastTestPass");
    lastTestFail = get_num(j, "lastTestFail");
    lastTestRun  = get_num(j, "lastTestRun");
    lastDiagAt   = get_num(j, "lastDiagAt");
    lastDiagSig  = get_str(j, "lastDiagSig");
    size_t sp = j.find("\"sessions\"");
    if (sp == string::npos) return;
    const string smap = take_obj(j, j.find(':', sp + 10));
    for (size_t i = 1; i + 1 < smap.size();) {
      size_t q = smap.find('"', i);
      if (q == string::npos) break;
      string sid;
      size_t q2 = q + 1;
      for (; q2 < smap.size(); q2++) { if (smap[q2] == '\\') { q2++; continue; } if (smap[q2] == '"') break; sid += smap[q2]; }
      size_t colon = smap.find(':', q2);
      if (colon == string::npos) break;
      size_t objAt = smap.find('{', colon);
      const string obj = take_obj(smap, colon);
      if (obj.empty() || objAt == string::npos) break;
      Sess s;
      s.goalPrompt = get_str(obj, "goalPrompt");
      s.goalTs = get_num(obj, "goalTs");
      s.touchedDirs = parse_str_array(obj, "touchedDirs");
      s.fanoutWarned = get_bool(obj, "fanoutWarned");
      s.lastCmd = get_str(obj, "lastCmd");
      s.lastCmdTs = get_num(obj, "lastCmdTs");
      s.cmdRepeat = (int)get_num(obj, "cmdRepeat"); if (s.cmdRepeat < 1) s.cmdRepeat = 1;
      s.actionCount = (int)get_num(obj, "actionCount");
      s.offTarget = (int)get_num(obj, "offTarget");
      s.driftChallenged = (int)get_num(obj, "driftChallenged");
      for (const auto& r : parse_obj_array(obj, "recent"))
        s.recent.push_back({ get_num(r, "t"), get_str(r, "s") });
      s.recentEv = parse_str_array(obj, "recentEv");
      s.tsOffset = get_num(obj, "tsOffset");
      s.tokensOut = get_num(obj, "tokensOut");
      s.tokensIn = get_num(obj, "tokensIn");
      sessions.push_back({ sid, s });
      i = objAt + obj.size();
    }
    if (sessions.size() > 4) sessions.erase(sessions.begin(), sessions.end() - 4);
  }

  void save() {
    std::ostringstream o;
    o << "{\"lastCodeEdit\":" << lastCodeEdit << ",\"lastTestPass\":" << lastTestPass
      << ",\"lastTestFail\":" << lastTestFail << ",\"lastTestRun\":" << lastTestRun
      << ",\"lastDiagAt\":" << lastDiagAt
      << ",\"lastDiagSig\":\"" << json_escape(lastDiagSig) << "\",\"sessions\":{";
    bool firstS = true;
    for (const auto& kv : sessions) {
      const Sess& s = kv.second;
      if (!firstS) o << ",";
      firstS = false;
      o << "\"" << json_escape(kv.first) << "\":{"
        << "\"goalPrompt\":\"" << json_escape(s.goalPrompt) << "\",\"goalTs\":" << s.goalTs
        << ",\"touchedDirs\":[";
      for (size_t i = 0; i < s.touchedDirs.size(); i++)
        o << (i ? "," : "") << "\"" << json_escape(s.touchedDirs[i]) << "\"";
      o << "],\"fanoutWarned\":" << (s.fanoutWarned ? "true" : "false")
        << ",\"lastCmd\":\"" << json_escape(s.lastCmd) << "\",\"lastCmdTs\":" << s.lastCmdTs
        << ",\"cmdRepeat\":" << s.cmdRepeat << ",\"actionCount\":" << s.actionCount
        << ",\"offTarget\":" << s.offTarget << ",\"driftChallenged\":" << s.driftChallenged
        << ",\"recent\":[";
      for (size_t i = 0; i < s.recent.size(); i++)
        o << (i ? "," : "") << "{\"t\":" << s.recent[i].first << ",\"s\":\"" << json_escape(s.recent[i].second) << "\"}";
      o << "],\"recentEv\":[";
      for (size_t i = 0; i < s.recentEv.size(); i++)
        o << (i ? "," : "") << "\"" << json_escape(s.recentEv[i]) << "\"";
      o << "],\"tsOffset\":" << s.tsOffset << ",\"tokensOut\":" << s.tokensOut
        << ",\"tokensIn\":" << s.tokensIn << "}";
    }
    o << "}}";
    std::ofstream f(path, std::ios::trunc);
    if (f) f << o.str();
  }
};

// ---------- delegation to the node gate (cold paths) ----------

static int delegate_to_node(const string& gateMjs, const string& raw) {
  FILE* p = popen(("node '" + gateMjs + "'").c_str(), "w");
  if (!p) return 0; // node missing -> fail open
  fwrite(raw.data(), 1, raw.size(), p);
  int st = pclose(p);
  if (st == -1) return 0;
  return WIFEXITED(st) ? WEXITSTATUS(st) : 0;
}

// ---------- the incident brain (opus-class) ----------
// bounded `claude -p`, 90s / 4MB. Returns a parsed verdict or {ok=false}.
struct Diag {
  bool ok = false;
  string where, cause, fix;
  bool hasRule = false; JVal newRule; // the raw model object, verbatim fields
};
static Diag diagnose(const string& goal, const std::vector<string>& recentBullets,
                     const string& cmd, const string& failOutputTail) {
  std::ostringstream p;
  p << "You are rabadon, a reliability runtime supervising a live coding session. The test suite just went RED.\n"
    << "Diagnose from the evidence and return ONLY a JSON object, no fences, no prose:\n"
    << "{ \"where\": \"<which step/gate of the work this belongs to, one short phrase>\",\n"
    << "  \"cause\": \"<root cause in one sentence, from the evidence — never invent>\",\n"
    << "  \"fix\": \"<the concrete next action to fix it, one sentence>\",\n"
    << "  \"newRule\": { \"id\": \"kebab-id\", \"deny\": \"<JS regex over bash commands>\", \"why\": \"<one line>\" } | { \"id\": \"kebab-id\", \"match\": \"<JS regex over file paths>\", \"why\": \"<one line>\" } | null }\n"
    << "newRule: ONLY if this class of mistake could have been caught BEFORE it happened by blocking a command or an edit; otherwise null. Prefer null over a rule that could block legitimate work.\n\n"
    << "## session goal\n" << goal << "\n"
    << "## last moves\n";
  for (const auto& r : recentBullets) p << "- " << r << "\n";
  p << "## the test command\n" << cmd << "\n"
    << "## failing output (tail)\n" << failOutputTail << "\n";
  const string raw = run_claude(p.str(), 90, "", 4 * 1024 * 1024);
  if (raw.empty()) return {};
  const string body = strip_fences(raw);
  JParser jp(body); JVal v = jp.parse();
  if (!jp.ok || v.t != JVal::OBJ) return {};
  Diag d; d.ok = true;
  d.where = get_str(body, "where");
  d.cause = get_str(body, "cause");
  d.fix   = get_str(body, "fix");
  if (JVal* nr = v.get("newRule")) {
    if (nr->t == JVal::OBJ) { d.hasRule = true; d.newRule = *nr; }
  }
  return d;
}

// ---------- the fast drift judge (haiku-class) ----------
// bounded `claude -p --model claude-haiku-4-5`, 30s / 1MB. Fail-open.
struct Verdict { bool ok = false; bool onTrack = true; string anchor; };
static Verdict driftJudge(const string& goal, const std::vector<string>& recentBullets) {
  std::ostringstream p;
  p << "You are rabadon, supervising a coding session. Verdict only, JSON only, no fences:\n"
    << "{ \"onTrack\": true|false, \"anchor\": \"<if off track: ONE sentence steering the work back to the goal; else empty>\" }\n"
    << "Judge conservatively: refactors, tests, and setup that SERVE the goal are on-track. Only flag work that belongs to a different task.\n"
    << "## the session goal\n" << goal << "\n"
    << "## the last moves\n";
  for (const auto& r : recentBullets) p << "- " << r << "\n";
  const string raw = run_claude(p.str(), 30, "claude-haiku-4-5", 1024 * 1024);
  if (raw.empty()) return {};
  const string body = strip_fences(raw);
  JParser jp(body); JVal v = jp.parse();
  if (!jp.ok || v.t != JVal::OBJ) return {};
  Verdict vd; vd.ok = true;
  vd.onTrack = get_bool(body, "onTrack");
  vd.anchor = get_str(body, "anchor");
  return vd;
}

int main(int argc, char** argv) {
  // --version for install sanity checks
  if (argc > 1 && string(argv[1]) == "--version") { printf("rabadon-gate 0.1.0\n"); return 0; }

  string raw;
  { char buf[65536]; size_t n; while ((n = fread(buf, 1, sizeof(buf), stdin)) > 0) raw.append(buf, n); }
  if (raw.empty()) return 0;

  const string hook = get_str(raw, "hook_event_name");
  string cwd = get_str(raw, "cwd");
  if (cwd.empty()) { const char* c = getenv("PWD"); cwd = c ? c : "."; }

  // escape hatches first — off is off, instantly
  const char* offEnv = getenv("RABADON_OFF");
  if ((offEnv && string(offEnv) == "1") || file_exists(cwd + "/.rabadon/off")) return 0;

  // resolve our home (…/native/rabadon-gate -> repo root)
  string self = argv[0];
  size_t slash = self.rfind('/');
  string root = slash == string::npos ? "." : self.substr(0, slash) + "/..";
  const string gateMjs = root + "/hooks/gate.mjs";

  // PostToolUse is native now (S3): test analysis, incident diagnosis,
  // re-anchor — the LLM stays off the hot path (bounded `claude -p`).
  if (hook != "PreToolUse" && hook != "PostToolUse" && hook != "UserPromptSubmit" &&
      hook != "SessionStart" && hook != "Stop") return 0;

  const string toolName = get_str(raw, "tool_name");
  size_t ti = raw.find("\"tool_input\"");
  const string command = ti == string::npos ? "" : get_str(raw, "command", ti);
  string filePath = ti == string::npos ? "" : get_str(raw, "file_path", ti);
  if (filePath.empty() && ti != string::npos) filePath = get_str(raw, "notebook_path", ti);
  const string sid = get_str(raw, "session_id");
  const string toolUseId = get_str(raw, "tool_use_id");

  // PostToolUse test analysis reads the command's output. tool_response is
  // either a string OR an object; mirror the JS EXACTLY:
  //   out = (string ? value : JSON.stringify(value||'')).replace(/\\r?\\n/g,'\n')
  // The .replace regex is /\\r?\\n/ — a literal backslash, optional 'r', and a
  // real NEWLINE character. JSON.stringify never emits real newline chars (it
  // escapes them to the two chars '\' 'n'), so on the object path the replace
  // is a NO-OP: `out` keeps the JSON text VERBATIM, literal \n and all. The
  // `fail(ed|ures): N` / green-phrase regexes then run over that verbatim text
  // — de-escaping here would silently change which lines the boundary anchors
  // see (it flipped "Failures: 0" from GREEN to RED in an early port). For the
  // string path, JSON.parse already turned \n into real newlines and the
  // replace stays a no-op, so get_str's unescaped value matches node.
  string toolResponse;
  {
    size_t tr = raw.find("\"tool_response\"");
    if (tr != string::npos) {
      size_t colon = raw.find(':', tr + 15);
      if (colon != string::npos) {
        size_t j = colon + 1;
        while (j < raw.size() && isspace((unsigned char)raw[j])) j++;
        if (j < raw.size() && raw[j] == '"') {
          toolResponse = get_str(raw, "tool_response", tr); // JSON string value, unescaped
        } else if (j < raw.size() && (raw[j] == '{' || raw[j] == '[')) {
          // the raw {..}/[..] text verbatim — this IS JSON.stringify's output
          // for compact stdin, which is what the gate receives
          int depth = 0; size_t a = j;
          for (size_t k = j; k < raw.size(); k++) {
            char c = raw[k];
            if (c == '"') { for (k++; k < raw.size(); k++) { if (raw[k]=='\\') k++; else if (raw[k]=='"') break; } continue; }
            if (c=='['||c=='{') depth++;
            else if (c==']'||c=='}') { depth--; if (!depth) { toolResponse = raw.substr(a, k - a + 1); break; } }
          }
        }
      }
    }
  }

  // rabadon home (spool/socket) — env override mirrors core/bus.mjs
  const char* rd = getenv("RABADON_DIR");
  const char* home = getenv("HOME");
  const string rdir = rd ? rd : (string(home ? home : ".") + "/.rabadon");
  mkdir(rdir.c_str(), 0755);
  mkdir((rdir + "/spool").c_str(), 0755);

  // project name = basename(cwd)
  size_t cs = cwd.rfind('/');
  const string project = cs == string::npos ? cwd : cwd.substr(cs + 1);

  char day[16]; { time_t t = time(nullptr); struct tm tmv; gmtime_r(&t, &tmv); strftime(day, 16, "%Y-%m-%d", &tmv); }

  Emitter em;
  em.spoolPath = rdir + "/spool/" + day + ".jsonl";
  em.sockPath = rdir + "/rabadon.sock";
  em.pipe = project + ":session";
  em.runId = "ng-" + std::to_string(now_ms() % 100000000) + "-" + std::to_string(getpid());
  em.drill = sid.rfind("fleet-", 0) == 0 || sid.rfind("doctor-", 0) == 0;
  em.open_sock();

  // one state file, one owner. the old parallel state-native-*.txt store is
  // retired — removed on sight so no stale twin survives the migration.
  mkdir((cwd + "/.rabadon").c_str(), 0755);
  const string sidKey = sid.empty() ? "default" : sid.substr(0, 16);
  unlink((cwd + "/.rabadon/state-native-" + sidKey + ".txt").c_str());
  State stt;
  stt.path = cwd + "/.rabadon/state.json";
  stt.load();
  Sess& ss = stt.session(sidKey);

  // twin-delivery dedupe (same law as the node gate): tool events carry a
  // unique tool_use_id; non-tool events (Stop/SessionStart/prompt) dedupe on
  // a 2s time bucket, which only ever collides with a genuine twin.
  {
    string key;
    if (!toolUseId.empty()) key = hook + ":" + toolUseId;
    else if (hook != "PreToolUse") key = hook + ":" + std::to_string(now_ms() / 2000);
    if (!key.empty()) {
      for (const auto& id : ss.recentEv) if (id == key) return 0;
      ss.recentEv.push_back(key);
      if (ss.recentEv.size() > 12) ss.recentEv.erase(ss.recentEv.begin(), ss.recentEv.end() - 12);
    }
  }

  const string guardRaw = read_file(cwd + "/.rabadon/guard.json");
  const auto disabled = parse_disabled(guardRaw);

  const char* judgeEnv = getenv("RABADON_JUDGE");
  const bool judgeOff = judgeEnv && string(judgeEnv) == "0";

  // ---------- PostToolUse: observe + track session state ----------
  // The action already ran; exit 2 here is FEEDBACK to the agent, not a block.
  // lastCodeEdit / lastTest* are TOP-LEVEL state (Pre reads them); the drift
  // trackers are per-session. The LLM (diagnose / re-anchor) is bounded and
  // off the hot path — a missing/slow claude fails open to the deterministic
  // verdict.
  if (hook == "PostToolUse") {
    const long long now = now_ms();

    if (toolName == "Edit" || toolName == "Write" || toolName == "MultiEdit") {
      // isCode: guard.codePaths present ? ANY match : true. Set BEFORE the
      // fan-out / re-anchor early-exits so a fed-back edit still records.
      bool isCode = true;
      if (!guardRaw.empty() && guardRaw.find("\"codePaths\"") != string::npos) {
        isCode = false;
        for (const auto& pat : parse_str_array(guardRaw, "codePaths"))
          if (rx_test(pat, filePath)) { isCode = true; break; }
      }
      if (isCode) stt.lastCodeEdit = now;

      // scope fan-out: rel = path.relative(cwd,file); top = first segment when
      // the file is inside cwd. touchedDirs is an order-preserving Set. Fires
      // once per session (fanoutWarned latch) at the 5th distinct top dir.
      string rel;
      {
        string base = cwd;
        if (!base.empty() && base.back() != '/') base += '/';
        if (filePath.rfind(base, 0) == 0) rel = filePath.substr(base.size());
        else rel = "../"; // outside cwd -> path.relative would start with '..'
      }
      bool inside = rel.rfind("..", 0) != 0;
      if (inside && !rel.empty()) {
        string top = rel;
        size_t sl = rel.find('/');
        if (sl != string::npos) top = rel.substr(0, sl);
        if (!top.empty()) {
          bool seen = false;
          for (const auto& d : ss.touchedDirs) if (d == top) { seen = true; break; }
          if (!seen) ss.touchedDirs.push_back(top);
          if (ss.touchedDirs.size() >= 5 && !ss.fanoutWarned) {
            ss.fanoutWarned = true;
            string joined;
            for (size_t k = 0; k < ss.touchedDirs.size(); k++)
              joined += (k ? ", " : "") + ss.touchedDirs[k];
            const string N = std::to_string(ss.touchedDirs.size());
            stt.save(); // lastCodeEdit + touchedDirs + fanoutWarned persisted
            em.emit("CHECK_FAIL", "\"step\":\"scope\",\"fails\":[{\"check\":\"scope-fanout\",\"why\":\"" +
              json_escape("session has now edited files in " + N + " top-level dirs: " + joined) + "\"}]");
            fprintf(stderr,
              "rabadon: scope fan-out — this session has edited files across %s top-level directories (%s). "
              "If the task really spans all of them, say so and continue; otherwise rein the change back to the area the task started in.\n",
              N.c_str(), joined.c_str());
            return 2;
          }
        }
      }
      stt.save();

      // active re-anchor: every 12th action, a fast judge compares last moves
      // vs the goal. actionCount is READ here (incremented only by Pre) — the
      // matching Pre already bumped it. Skipped with RABADON_JUDGE=0. Fail-open.
      if (!judgeOff && !ss.goalPrompt.empty() && ss.actionCount > 0 && ss.actionCount % 12 == 0) {
        std::vector<string> bullets;
        size_t from = ss.recent.size() > 12 ? ss.recent.size() - 12 : 0;
        for (size_t k = from; k < ss.recent.size(); k++) bullets.push_back(ss.recent[k].second);
        Verdict v = driftJudge(ss.goalPrompt, bullets);
        if (v.ok && !v.onTrack && !v.anchor.empty()) {
          em.emit("CHECK_FAIL", "\"step\":\"goal\",\"fails\":[{\"check\":\"goal-drift\",\"why\":\"" +
            json_escape(v.anchor.substr(0, 200)) + "\"}]");
          fprintf(stderr, "rabadon re-anchor: the session goal is \"%s\". %s\n",
            ss.goalPrompt.substr(0, 120).c_str(), v.anchor.c_str());
          return 2;
        }
        // null / onTrack / no anchor / judge unavailable -> fall through
      }

      const string base = filePath.substr(filePath.rfind('/') + 1);
      em.emit("STEP_OK", "\"step\":\"edited: " + json_escape(base) + "\"");
      return 0;
    }

    if (toolName == "Bash") {
      const string& out = toolResponse;
      bool isTest;
      if (!guardRaw.empty() && guardRaw.find("\"testCommand\"") != string::npos)
        isTest = rx_test(get_str(guardRaw, "testCommand"), command);
      else
        isTest = rx_test("ctest|--test|npm test", command);

      if (!isTest) {
        em.emit("STEP_OK", "\"step\":\"ran: " + json_escape(command.substr(0, 80)) + "\"");
        stt.save();
        return 0;
      }

      // measured green/red — never a keyword sighting. Prefer testPassPattern;
      // else if a "fail(ed|ures): N" count exists, green iff N==0; else fall
      // back to explicit green phrases. ("fail 0" in a green run is GREEN.)
      bool passed;
      if (!guardRaw.empty() && guardRaw.find("\"testPassPattern\"") != string::npos) {
        passed = rx_test(get_str(guardRaw, "testPassPattern"), out);
      } else {
        std::smatch m;
        std::regex fc("\\bfail(?:ed|ures)?\\s*[:= ]\\s*(\\d+)", std::regex::ECMAScript | std::regex::icase);
        if (std::regex_search(out, m, fc)) passed = (atoll(m[1].str().c_str()) == 0);
        else passed = rx_test("100% tests passed|0 failed|all tests passed", out);
      }

      stt.lastTestRun = now;
      if (passed) { stt.lastTestPass = now; stt.lastTestFail = 0; }
      else stt.lastTestFail = now;
      stt.save();

      if (passed) {
        em.emit("STEP_OK", "\"step\":\"tests: GREEN\"");
        return 0;
      }

      // RED — the incident loop.
      em.emit("CHECK_FAIL", "\"step\":\"tests\",\"fails\":[{\"check\":\"test-run\",\"why\":\"test run is RED\"}]");
      string advice;
      // failSig = out lines matching /fail/i joined by '|' sliced to 300
      string failSig;
      {
        size_t ls = 0;
        while (ls < out.size()) {
          size_t le = out.find('\n', ls);
          if (le == string::npos) le = out.size();
          const string line = out.substr(ls, le - ls);
          if (rx_test("fail", line)) { if (!failSig.empty()) failSig += "|"; failSig += line; }
          ls = le + 1;
        }
        if (failSig.size() > 300) failSig = failSig.substr(0, 300);
      }
      const bool sameIncident = stt.lastDiagSig == failSig && (now - stt.lastDiagAt) < 15LL * 60000;

      if (!judgeOff && !sameIncident) {
        stt.lastDiagSig = failSig; stt.lastDiagAt = now; stt.save();
        em.emit("REPAIR_START", "\"step\":\"diagnose\",\"attempt\":1,\"fixing\":[\"red-tests\"]");
        std::vector<string> bullets;
        size_t from = ss.recent.size() > 15 ? ss.recent.size() - 15 : 0;
        for (size_t k = from; k < ss.recent.size(); k++) bullets.push_back(ss.recent[k].second);
        const string goal = ss.goalPrompt.empty() ? "(no goal captured)" : ss.goalPrompt;
        const string failTail = out.size() > 4000 ? out.substr(out.size() - 4000) : out;
        Diag diag = diagnose(goal, bullets, command, failTail);
        if (!diag.ok) {
          em.emit("REPAIR_FAIL", "\"step\":\"diagnose\",\"attempt\":1,\"why\":\"diagnosis unavailable\"");
        } else {
          advice = "\nrabadon diagnosis:\n  where: " + diag.where +
                   "\n  cause: " + diag.cause + "\n  fix:   " + diag.fix + "\n";
          if (diag.hasRule && !guardRaw.empty()) {
            // validate the rule regex compiles; install into bash (deny) or
            // protectedPaths (match); re-read guard.json FRESH; id-dedup;
            // append {...newRule, authoredBy:'incident', incidentAt:ISO}.
            JVal* denyV = diag.newRule.get("deny");
            JVal* matchV = diag.newRule.get("match");
            string patRaw, patUnescaped;
            const char* target = nullptr;
            if (denyV && denyV->t == JVal::STR) { patRaw = denyV->str; target = "bash"; }
            else if (matchV && matchV->t == JVal::STR) { patRaw = matchV->str; target = "protectedPaths"; }
            // the rule's regex is JSON-escaped in patRaw; unescape for compile test
            if (target) patUnescaped = json_unescape(patRaw);
            bool compiles = false;
            if (target) { try { std::regex re(patUnescaped, std::regex::ECMAScript | std::regex::icase); compiles = true; (void)re; } catch (...) { compiles = false; } }
            if (target && compiles) {
              const string fresh = read_file(cwd + "/.rabadon/guard.json");
              JParser gp(fresh); JVal g = gp.parse();
              if (gp.ok && g.t == JVal::OBJ) {
                JVal* idV = diag.newRule.get("id");
                const string ruleId = idV && idV->t == JVal::STR ? json_unescape(idV->str) : "";
                JVal* arr = g.get(target);
                bool exists = false;
                if (arr && arr->t == JVal::ARR) {
                  for (auto& e : arr->arr) {
                    JVal* eid = e.get("id");
                    if (eid && eid->t == JVal::STR && json_unescape(eid->str) == ruleId) { exists = true; break; }
                  }
                }
                if (!exists) {
                  // build the rule object = the model's newRule fields verbatim
                  // + authoredBy + incidentAt, in that order
                  JVal rule = diag.newRule;
                  rule.obj.push_back({ "authoredBy", jstr("incident") });
                  rule.obj.push_back({ "incidentAt", jstr(iso8601_now()) });
                  if (!arr) { g.obj.push_back({ target, JVal{} }); arr = &g.obj.back().second; arr->t = JVal::ARR; }
                  else if (arr->t != JVal::ARR) { arr->t = JVal::ARR; arr->arr.clear(); }
                  arr->arr.push_back(rule);
                  string pretty; jval_print(g, pretty, 0); pretty += "\n";
                  // atomic write: temp + rename so the law can never corrupt
                  const string gpath = cwd + "/.rabadon/guard.json";
                  const string tmp = gpath + ".tmp";
                  { std::ofstream tf(tmp, std::ios::trunc); if (tf) tf << pretty; }
                  rename(tmp.c_str(), gpath.c_str());
                  em.emit("REPAIR_OK", "\"step\":\"new gate: " + json_escape(ruleId) + "\",\"attempt\":1");
                  advice += "  new gate installed: " + ruleId + " — this class of break is now caught BEFORE it happens.\n";
                }
              }
            }
          }
        }
      }
      fprintf(stderr, "rabadon: tests are RED.%s\n",
        advice.empty() ? " Fix the failure before moving on." : advice.c_str());
      return 2;
    }

    // any other tool: no event, no state mutation — but the twin-dedupe key we
    // appended above must persist so a twin delivery dedupes.
    stt.save();
    return 0;
  }

  // ---------- UserPromptSubmit: pin the session's goal ----------
  if (hook == "UserPromptSubmit") {
    const string prompt = get_str(raw, "prompt");
    // root fix for goal poisoning: the gate's own recursive prompts (the
    // diagnose/judge children run `claude -p` from inside a hook) must
    // never be mistaken for the builder's goal
    const bool recursive = prompt.rfind("You are rabadon", 0) == 0;
    if (!recursive && !prompt.empty() &&
        (ss.goalPrompt.empty() || now_ms() - ss.goalTs > 6LL * 3600 * 1000)) {
      ss.goalPrompt = prompt.substr(0, 400);
      ss.goalTs = now_ms();
      // a new goal resets the drift trackers — a new task may live elsewhere
      ss.touchedDirs.clear();
      ss.fanoutWarned = false;
      em.emit("RUN_START", "\"steps\":[\"goal: " + json_escape(ss.goalPrompt.substr(0, 100)) + "\"],\"bound\":{}");
    }
    stt.save();
    return 0;
  }

  // ---------- SessionStart: reset + devridaim injection ----------
  if (hook == "SessionStart") {
    ss.touchedDirs.clear(); ss.fanoutWarned = false;
    ss.cmdRepeat = 0; ss.lastCmd.clear(); ss.actionCount = 0;
    stt.save();
    // a fresh-enough handoff becomes session context via stdout — the new
    // session opens already knowing where the last one stood
    const string hpath = cwd + "/.rabadon/handoff.md";
    struct stat hst;
    if (stat(hpath.c_str(), &hst) == 0 && time(nullptr) - hst.st_mtime < 7 * 86400) {
      const string h = read_file(hpath);
      fwrite(h.data(), 1, h.size(), stdout);
    }
    const size_t nb = parse_rules(guardRaw, "bash", "deny", disabled).size();
    const size_t np = parse_rules(guardRaw, "protectedPaths", "match", disabled).size();
    const string steps = guardRaw.empty() ? "NO GUARD (observe only)"
      : ("guard: " + std::to_string(nb) + " bash + " + std::to_string(np) + " path rules");
    const string bound = guardRaw.empty() ? "{\"loopStop\":3,\"fanout\":5}"
      : string("{\"pushGate\":") + (guardRaw.find("\"pushGate\"") != string::npos ? "true" : "false") + ",\"loopStop\":3,\"fanout\":5}";
    em.emit("RUN_START", "\"steps\":[\"" + json_escape(steps) + "\"],\"bound\":" + bound);
    return 0;
  }

  // ---------- Stop: token ledger + devridaim handoff ----------
  if (hook == "Stop") {
    // token ledger — REAL usage from the transcript, read incrementally from
    // the last byte offset, never the whole file twice
    const string tp = get_str(raw, "transcript_path");
    struct stat tst;
    if (!tp.empty() && stat(tp.c_str(), &tst) == 0) {
      const long long size = tst.st_size;
      const long long from = (ss.tsOffset > 0 && ss.tsOffset <= size) ? ss.tsOffset : 0;
      if (size > from) {
        std::ifstream f(tp, std::ios::binary);
        f.seekg(from);
        string win((size_t)(size - from), '\0');
        f.read(&win[0], size - from);
        long long inTok = 0, outTok = 0;
        size_t ls = 0;
        while (ls < win.size()) {
          size_t le = win.find('\n', ls);
          if (le == string::npos) le = win.size();
          const string line = win.substr(ls, le - ls);
          size_t u = line.find("\"usage\":");
          if (u != string::npos) {
            size_t o = line.find("\"output_tokens\":", u);
            if (o != string::npos) {
              outTok += atoll(line.c_str() + o + 16);
              size_t i2 = line.find("\"input_tokens\":", u);
              if (i2 != string::npos) inTok += atoll(line.c_str() + i2 + 15);
            }
          }
          ls = le + 1;
        }
        ss.tsOffset = size;
        ss.tokensOut += outTok;
        ss.tokensIn += inTok;
        em.emit("STEP_OK", "\"step\":\"tokens this session: " + std::to_string(ss.tokensOut) +
          " out / " + std::to_string(ss.tokensIn) + " in\",\"tokens\":" + std::to_string(ss.tokensOut));
      }
    }

    // devridaim — distill the session into .rabadon/handoff.md so the NEXT
    // session (tomorrow, after a crash, after compact) starts where this one
    // stood. Deterministic, from the trail — no model, no cost.
    auto hhmmss = [](long long ms) {
      time_t t = (time_t)(ms / 1000); struct tm tmv; localtime_r(&t, &tmv);
      char b[16]; strftime(b, 16, "%H:%M:%S", &tmv); return string(b);
    };
    std::vector<string> caught;
    {
      const string spool = read_file(em.spoolPath);
      const string pipeTag = "\"" + project + ":session\"";
      size_t ls = 0;
      while (ls < spool.size()) {
        size_t le = spool.find('\n', ls);
        if (le == string::npos) le = spool.size();
        const string line = spool.substr(ls, le - ls);
        if (line.find(pipeTag) != string::npos &&
            line.find("\"ev\":\"STOP\"") != string::npos &&
            line.find("\"reason\":\"BLOCKED\"") != string::npos) {
          string d = get_str(line, "detail");
          size_t nl = d.find('\n');
          if (nl != string::npos) d = d.substr(0, nl);
          caught.push_back(d.substr(0, 90));
        }
        ls = le + 1;
      }
      if (caught.size() > 6) caught.erase(caught.begin(), caught.end() - 6);
    }
    const string tests = stt.lastTestFail > stt.lastTestPass
      ? ("RED (since " + hhmmss(stt.lastTestFail) + ")")
      : stt.lastTestPass ? ("green (last pass " + hhmmss(stt.lastTestPass) + ")")
      : string("not run this cycle");
    std::ostringstream ho;
    {
      char iso[32]; time_t t = time(nullptr); struct tm tmv; gmtime_r(&t, &tmv);
      strftime(iso, 32, "%Y-%m-%dT%H:%M:%SZ", &tmv);
      ho << "# rabadon devridaim — " << project << "\nupdated: " << iso << "\n\n";
    }
    ho << "## goal (as captured from the session)\n"
       << (ss.goalPrompt.empty() ? "(no goal captured)" : ss.goalPrompt) << "\n\n";
    ho << "## tests\n" << tests << "\n\n";
    ho << "## caught today (blocked before happening)\n";
    if (caught.empty()) ho << "- none\n";
    else for (const auto& c : caught) ho << "- " << c << "\n";
    ho << "\n## last moves\n";
    if (ss.recent.empty()) ho << "- (none recorded)\n";
    else {
      size_t from8 = ss.recent.size() > 8 ? ss.recent.size() - 8 : 0;
      for (size_t i = from8; i < ss.recent.size(); i++) ho << "- " << ss.recent[i].second << "\n";
    }
    ho << "\n## for the next session\n"
       << "- if tests are RED above: that is the open front — start there.\n"
       << "- the guard is law (.rabadon/guard.json); rules born from incidents carry authoredBy: incident.\n";
    { std::ofstream hf(cwd + "/.rabadon/handoff.md", std::ios::trunc); if (hf) hf << ho.str(); }
    stt.save();
    em.emit("RUN_DONE", "\"verdict\":\"SESSION_TURN_DONE\",\"tokens\":0,\"depth\":0");
    return 0;
  }

  auto block = [&](const string& ruleId, const string& why, const string& detail) {
    em.emit("CHECK_FAIL", "\"step\":\"" + json_escape(toolName) + "\",\"fails\":[{\"check\":\"" + json_escape(ruleId) + "\",\"why\":\"" + json_escape(detail + " — " + why) + "\"}]");
    em.emit("STOP", "\"reason\":\"BLOCKED\",\"detail\":\"" + json_escape(detail) + "\"");
    stt.save();
    fprintf(stderr,
      "rabadon BLOCKED this action.\nRule: %s — %s\n%s\nAdjust the approach instead of retrying the same action.\n"
      "(user override: add \"%s\" to disabled[] in .rabadon/guard.json, or `rabadon off` to pause supervision)\n",
      ruleId.c_str(), why.c_str(), detail.c_str(), ruleId.c_str());
    exit(2);
  };

  if (!guardRaw.empty()) {
    if (toolName == "Bash" && !command.empty()) {
      for (const auto& r : parse_rules(guardRaw, "bash", "deny", disabled))
        if (rx_test(r.pattern, command))
          block(r.id, r.why, "command matched deny rule: " + command.substr(0, 160));
      // push gate needs to RUN the suite — that is node's cold path. Delegate
      // WITHOUT saving: node does its own bookkeeping on this event, and a
      // pre-saved dedupe key or loop counter would double every count.
      if (rx_test("\\bgit\\s+push\\b", command) && !rx_test("--dry-run", command) && guardRaw.find("\"pushGate\"") != string::npos)
        return delegate_to_node(gateMjs, raw);
    }
    if (toolName == "Edit" || toolName == "Write" || toolName == "MultiEdit" || toolName == "NotebookEdit") {
      for (const auto& r : parse_rules(guardRaw, "protectedPaths", "match", disabled))
        if (!filePath.empty() && rx_test(r.pattern, filePath))
          block(r.id, r.why, "protected file: " + filePath);
    }
  }

  // ---------- promise: the goal contract enforced IN the session ----------
  // .rabadon/promise.json declares the project's north star (drift.cpp
  // measures it at session end). The gate refuses the betrayal at the moment
  // it is attempted: an edit landing on an anti-path is blocked, and edits
  // creeping outside the promised areas are challenged once per session.
  // No promise, or a broken one -> nothing to enforce (fail open).
  const bool isEditTool = toolName == "Edit" || toolName == "Write" ||
                          toolName == "MultiEdit" || toolName == "NotebookEdit";
  auto ruleOff = [&](const char* id) {
    for (const auto& d : disabled) if (d == id) return true;
    return false;
  };
  if (isEditTool && !filePath.empty()) {
    // the promise is authored by the user; a supervised session rewriting it
    // to escape the gate is the exact gaming this binary exists to refuse
    if (rx_test("\\.rabadon/promise\\.json$", filePath) && !ruleOff("promise-tamper"))
      block("promise-tamper", "the goal contract is authored by the user, not by the supervised session",
        "attempt to edit the promise itself: " + filePath);
    const string praw = read_file(cwd + "/.rabadon/promise.json");
    const string star = get_str(praw, "north_star");
    if (!star.empty()) {
      string rel = filePath.rfind(cwd + "/", 0) == 0 ? filePath.substr(cwd.size() + 1) : filePath;
      bool onAnti = false; string antiPat;
      for (const auto& a : parse_str_array(praw, "anti_paths"))
        if (rx_test(a, rel)) { onAnti = true; antiPat = a; break; }
      if (onAnti && !ruleOff("promise-anti-path"))
        block("promise-anti-path", "the promise swore off this ground: " + star,
          rel + " matches anti-path '" + antiPat + "'");
      const auto areas = parse_str_array(praw, "areas");
      bool onArea = false;
      for (const auto& a : areas) if (rx_test(a, rel)) { onArea = true; break; }
      if (!areas.empty() && !onArea && !onAnti) {
        ss.offTarget++;
        if (ss.offTarget >= 5 && !ss.driftChallenged && !ruleOff("promise-off-target")) {
          ss.driftChallenged = 1;
          block("promise-off-target",
            "5 edits this session landed outside the promised areas — the session is drifting from its star",
            "star: " + star + " — latest off-target file: " + rel +
            " (fires once per session; if this work is intended, update .rabadon/promise.json areas)");
        }
      }
    }
  }

  // test-tamper: suite red + a test-file edit that weakens it
  if ((toolName == "Edit" || toolName == "Write" || toolName == "MultiEdit") && !filePath.empty()) {
    if (stt.lastTestFail > stt.lastTestPass) {
      bool isTest = false;
      if (guardRaw.find("\"testPaths\"") != string::npos) {
        for (const auto& pat : parse_str_array(guardRaw, "testPaths"))
          if (rx_test(pat, filePath)) { isTest = true; break; }
      } else isTest = rx_test("test", filePath);
      if (isTest) {
        const string oldS = ti == string::npos ? "" : get_str(raw, "old_string", ti);
        string newS = ti == string::npos ? "" : get_str(raw, "new_string", ti);
        if (newS.empty() && ti != string::npos) newS = get_str(raw, "content", ti);
        const string SKIP = "\\b(it|test|describe)\\.(skip|todo)\\b|\\bxit\\(|\\bxdescribe\\(|DISABLED_|GTEST_SKIP|@unittest\\.skip|pytest\\.mark\\.skip";
        auto countAsserts = [](const string& s) {
          static const std::regex re("\\b(assert|expect|require)(\\.\\w+)?\\s*\\(|\\b(EXPECT_|ASSERT_|assert_eq)\\w*!?\\s*\\(", std::regex::ECMAScript);
          return (int)std::distance(std::sregex_iterator(s.begin(), s.end(), re), std::sregex_iterator());
        };
        bool addsSkip = rx_test(SKIP, newS) && !rx_test(SKIP, oldS);
        bool dropsAsserts = !oldS.empty() && countAsserts(newS) < countAsserts(oldS);
        if (addsSkip || dropsAsserts)
          block("test-tamper", "tests are RED and this edit weakens the test instead of fixing the code",
            string(addsSkip ? "a skip marker is being added to " : "assertions are being removed from ") + filePath + " while the suite is red");
      }
    }
  }

  // loop-stop: same non-read-only command, 3rd time, no code edit in between
  if (toolName == "Bash" && !command.empty() &&
      !rx_test("^(git\\s+(status|diff|log|show|branch)|ls|cat|head|tail|grep|rg|find|pwd|wc|echo|which|node\\s+--check)\\b", command)) {
    bool editedBetween = stt.lastCodeEdit > ss.lastCmdTs;
    if (ss.lastCmd == command && !editedBetween) ss.cmdRepeat++;
    else ss.cmdRepeat = 1;
    ss.lastCmd = command;
    ss.lastCmdTs = now_ms();
    if (ss.cmdRepeat >= 3)
      block("loop-stop", "the same command has now run 3x with no code change in between — a loop, not progress",
        "looping on: " + command.substr(0, 120));
  }

  // the trail: a diagnosis needs to know WHERE the session is, not just that
  // it crashed — same law as the node gate's remember()
  string label = toolName == "Bash" ? ("bash: " + command.substr(0, 80)) : (toolName + ": " + filePath.substr(filePath.rfind('/') + 1));
  ss.recent.push_back({ now_ms(), label.substr(0, 120) });
  if (ss.recent.size() > 30) ss.recent.erase(ss.recent.begin(), ss.recent.end() - 30);
  ss.actionCount++;
  em.emit("STEP_START", "\"step\":\"" + json_escape(label) + "\"");
  stt.save();
  return 0;
}
