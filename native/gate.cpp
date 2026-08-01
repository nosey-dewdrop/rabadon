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
#include <dirent.h>

#include "usage.h"   // the shared token/cost meter (budget cap here + rabadon-lens)
#include "sha256.h"  // the hash-chained spool (emitter here + rabadon-audit)
#include "chain.h"    // the ledger's one writer: chained line + .head sidecar
#include "baseline.h" // the three laws that hold with no guard.json at all
#include "rules.h"    // guard.json rule parsing + matching — shared with `rabadon exec`
#include "version.h" // one version string, lockstep with package.json
#include <sys/file.h>
#include "cli_help.h"

using std::string;

// Supervision mode, resolved once per invocation. WATCH is not a crippled
// ENFORCE: every rule runs and every verdict is recorded, the only difference
// is that the action is allowed to proceed. See the three-state block in main().
enum { MODE_SILENT = 0, MODE_WATCH = 1, MODE_ENFORCE = 2 };
static int g_mode = MODE_SILENT;
// argv[0], so the gate can find its sibling binaries (rabadon-net) wherever the
// install lives — a symlinked /opt/homebrew/bin must not break the net.
static string g_self;
static string self_dir() { size_t s = g_self.rfind('/'); return s == string::npos ? string(".") : g_self.substr(0, s); }
// The exit code a refusal turns into. Claude Code reads 2 as "blocked"; in watch
// mode the same refusal is recorded and then waved through with 0.
static int refuse_code() { return g_mode == MODE_ENFORCE ? 2 : 0; }
static const char* mode_tag() { return g_mode == MODE_ENFORCE ? "enforce" : "watch"; }

// ---------- tiny JSON field extraction (enough for hook payloads) ----------
// We need a handful of known string fields. Values are JSON-escaped; we
// unescape the common sequences. Anything unparseable -> empty -> fail open.

// Both of these now live in rules.h so the gate and `rabadon exec` read a
// rule object the same way. Thin forwards keep the ~50 call sites below
// untouched while there is exactly one implementation to audit.
static string json_unescape(const string& s) { return rbrules::json_unescape(s); }

static string get_str(const string& j, const string& key, size_t from = 0) {
  return rbrules::get_str(j, key, from);
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

// The rabadon home: RABADON_DIR when set (test isolation, multi-tenant), else
// $HOME/.rabadon. ONE rule for the mode flags AND the spool — a split home
// means `rabadon on` and the ledger disagree about which machine they live on.
static string rabadon_home() {
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) return string(rd);
  const char* h = getenv("HOME");
  return string(h ? h : ".") + "/.rabadon";
}

static long long now_ms() {
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static string iso8601_now() {
  char iso[32]; time_t t = time(nullptr); struct tm tmv; gmtime_r(&t, &tmv);
  strftime(iso, 32, "%Y-%m-%dT%H:%M:%SZ", &tmv);
  return string(iso);
}

// fractional number field (usd caps are dollars, not integers)
static double get_double(const string& j, const string& key) {
  const string pat = "\"" + key + "\"";
  size_t k = j.find(pat);
  if (k == string::npos) return 0;
  size_t colon = j.find(':', k + pat.size());
  if (colon == string::npos) return 0;
  return atof(j.c_str() + colon + 1);
}

// ---------- the budget meter ----------
// Usage / sum_usage / Rate / model_rate / usd_cost / last_model now live in
// usage.h so the budget cap (below) and `rabadon lens` read this session's REAL
// usage the SAME way — one meter, not two. See usage.h for the disambiguation
// and the 571M-token byte-exact proof.

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
    string body = "{\"v\":1,\"seq\":" + std::to_string(++seq) +
      ",\"ts\":" + std::to_string(now_ms()) +
      ",\"run\":\"" + runId + "\",\"pipe\":\"" + json_escape(pipe) + "\",\"ev\":\"" + ev + "\"" +
      (extraJson.empty() ? "" : "," + extraJson) +
      (drill ? ",\"drill\":true" : "");
    // hash-chained ledger: every event carries prev = SHA-256 of the previous
    // event line in this day file and the .head sidecar commits the last hash
    // AND the line count, so the spool is TAMPER-EVIDENT — edit, drop, truncate
    // or re-stitch any line and `rabadon audit` names the break. One writer for
    // all three binaries: chain.h.
    string line = rbchain::append(spoolPath, body);
    if (sockFd >= 0) { ssize_t r = write(sockFd, line.c_str(), line.size()); (void)r; }
  }

  ~Emitter() { if (sockFd >= 0) close(sockFd); }
};

// ---------- rules ----------

// The rule engine itself is rules.h. `rabadon exec` compiles the same header,
// so a command the gate refuses cannot be a command exec runs.
using Rule = rbrules::Rule;
using rbrules::parse_rules;
using rbrules::parse_disabled;
using rbrules::rx_test;
using rbrules::rx_test_cmd;

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
  // the always-on net: the timestamp of the last verdict we have already acted
  // on, and what that verdict was. Both are needed to spot the TRANSITION —
  // "it is red" is noise if it was red an hour ago; "it just turned red" is the
  // catch the whole product exists for.
  long long lastNetTs = 0;
  string lastNetVerdict;
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
    lastNetTs    = get_num(j, "lastNetTs");
    lastNetVerdict = get_str(j, "lastNetVerdict");
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
      << ",\"lastNetTs\":" << lastNetTs
      << ",\"lastNetVerdict\":\"" << json_escape(lastNetVerdict) << "\""
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

// ---------- run the project's own suite (the push gate) ----------
// A bounded shell child, stdout+stderr captured, SIGKILL on timeout. The push
// gate uses this to RUN the project's real test command and decide on the REAL
// result — telling is a warning, solving is the product. *exitCode = -1 on
// timeout/spawn failure. This is the last thing that used to need node; the
// gate binary now depends on nothing but a shell.
static string run_shell(const string& cmd, int timeoutSec, size_t maxBytes, int* exitCode) {
  *exitCode = -1;
  int outPipe[2];
  if (pipe(outPipe) != 0) return "";
  pid_t pid = fork();
  if (pid < 0) { close(outPipe[0]); close(outPipe[1]); return ""; }
  if (pid == 0) {
    dup2(outPipe[1], STDOUT_FILENO);
    dup2(outPipe[1], STDERR_FILENO);
    int devnull = open("/dev/null", O_RDONLY);
    if (devnull >= 0) dup2(devnull, STDIN_FILENO);
    close(outPipe[0]); close(outPipe[1]);
    setenv("RABADON_OFF", "1", 1); // the suite run is work, not a supervised action
    execlp("sh", "sh", "-c", cmd.c_str(), (char*)nullptr);
    _exit(127);
  }
  close(outPipe[1]);
  fcntl(outPipe[0], F_SETFL, O_NONBLOCK);
  string out;
  const long long deadline = now_ms() + (long long)timeoutSec * 1000;
  bool killed = false;
  for (;;) {
    char buf[8192];
    ssize_t r = read(outPipe[0], buf, sizeof(buf));
    if (r > 0) { if (out.size() < maxBytes) out.append(buf, (size_t)std::min((size_t)r, maxBytes - out.size())); continue; }
    if (r == 0) break;
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      if (now_ms() > deadline) { kill(pid, SIGKILL); killed = true; break; }
      int st; pid_t w = waitpid(pid, &st, WNOHANG);
      if (w == pid) {
        for (;;) { ssize_t r2 = read(outPipe[0], buf, sizeof(buf)); if (r2 <= 0) break;
          if (out.size() < maxBytes) out.append(buf, (size_t)std::min((size_t)r2, maxBytes - out.size())); }
        close(outPipe[0]);
        if (WIFEXITED(st)) *exitCode = WEXITSTATUS(st);
        return out;
      }
      struct timespec nap{0, 5 * 1000 * 1000}; nanosleep(&nap, nullptr);
      continue;
    }
    break;
  }
  close(outPipe[0]);
  int st; waitpid(pid, &st, 0);
  if (killed) { *exitCode = -1; return out; }
  if (WIFEXITED(st)) *exitCode = WEXITSTATUS(st);
  return out;
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

static const char* kHelp =
  "rabadon-gate — the arbiter. Refuses a dangerous tool call BEFORE it is run.\n"
  "As a PreToolUse hook Claude Code pipes the tool event on stdin and this decides\n"
  "allow or block against <project>/.rabadon/guard.json; it also enforces the\n"
  "budget cap by measuring the session's real cumulative usage on every call.\n"
  "\n"
  "usage: rabadon-gate [--status|--on|--off|--toggle|--silent]\n"
  "       rabadon-gate --lint [dir]\n"
  "       rabadon-gate --statusline\n"
  "       rabadon-gate --version\n"
  "\n"
  "  --status     print the mode and the file it was read from. changes nothing.\n"
  "  --on         ON: the arbiter acts — refuses, repairs, proves.\n"
  "  --off        WATCH: records what it WOULD have caught, touches nothing.\n"
  "  --silent     dormant everywhere, records nothing.\n"
  "  --toggle     flip between ON and WATCH.\n"
  "  --lint [dir] compile every guard.json pattern and flag unknown keys, so a\n"
  "               typo'd rule is caught at author time, not by a deny that never\n"
  "               fired. exit 1 with the list if anything is wrong.\n"
  "  --statusline the one-line status for Claude Code's statusline hook.\n"
  "  -h, --help   this screen.\n"
  "\n"
  "With no arguments and an event on stdin, this IS the hook.\n"
  "\n"
  "example:\n"
  "  rabadon-gate --lint ~/src/myrepo\n";

int main(int argc, char** argv) {
  g_self = argv[0];
  // SECURITY, fail-CLOSED: the gate emits its verdict over a unix socket to any
  // live watcher BEFORE it reaches exit(2). If the watcher's end is closed, a
  // raw write() would raise SIGPIPE and KILL this process mid-block — and Claude
  // Code treats a signal-killed PreToolUse hook as ALLOW, so a dangerous command
  // would slip through exactly when someone was watching. Ignore SIGPIPE so a
  // dead watcher can never turn a block into an allow (write just returns EPIPE,
  // which emit already discards). This is the whole point of the gate.
  signal(SIGPIPE, SIG_IGN);

  // `rabadon-gate --help` used to fall through to hook mode, read an empty
  // stdin, fail open and exit 0 having printed NOTHING. Zero bytes and a clean
  // exit code is exactly what a working hook looks like, so the binary that
  // enforces everything was the one that answered nothing.
  rb_help(argc, argv, kHelp);

  // A flag this gate does not know is NAMED, then IGNORED.
  //   named   — swallowing it is how a mistyped `--stauts` fell through to hook
  //             mode, read an empty stdin, failed open and printed zero bytes.
  //             Exit 0 and no output is exactly what a healthy hook looks like.
  //   ignored — this binary IS a PreToolUse hook, where a non-zero exit means
  //             BLOCK. Refusing here would let one typo in a settings.json hook
  //             line wedge every tool call on the machine. Fail OPEN, always.
  if (argc > 1 && argv[1][0] == '-' && argv[1][1] != '\0') {
    static const char* kKnownFlags[] = {"--version", "--lint", "--statusline",
                                        "--on", "--off", "--toggle", "--status", "--silent"};
    bool recognised = false;
    for (const char* k : kKnownFlags) if (strcmp(argv[1], k) == 0) recognised = true;
    if (!recognised) {
      fprintf(stderr, "rabadon-gate: unknown option \"%s\" — run `rabadon-gate --help`\n", argv[1]);
      return 0;
    }
  }

  // --version for install sanity checks
  if (argc > 1 && string(argv[1]) == "--version") { printf("rabadon-gate " RABADON_VERSION "\n"); return 0; }

  // --lint [dir] — validate a guard.json before it is trusted. A typo'd key
  // ("protectedPath" for "protectedPaths") or an uncompilable regex used to be
  // swallowed silently: the gate would OBSERVE where the author meant it to
  // BLOCK. Lint compiles every pattern and flags unknown top-level keys, exit
  // 1 with the list — so a broken guard is caught at author time, not by a
  // deny that never fired.
  if (argc > 1 && string(argv[1]) == "--lint") {
    string dir = argc > 2 ? argv[2] : ".";
    string path = dir + "/.rabadon/guard.json";
    string g = read_file(path);
    if (g.empty()) { fprintf(stderr, "rabadon lint: no guard at %s\n", path.c_str()); return 1; }
    int problems = 0;
    // unknown top-level keys (catches protectedPath/bashRules/etc typos)
    static const char* known[] = {"project", "bash", "protectedPaths", "codePaths", "testPaths",
                                   "testCommand", "testPassPattern", "network", "disabled",
                                   "generatedBy", "authoredBy", "pushGate", "evidence"};
    { size_t i = 0; int depth = 0;
      while (i < g.size()) {
        char c = g[i];
        if (c == '"') {
          size_t s = i + 1; string key;
          for (i++; i < g.size(); i++) { if (g[i] == '\\') i++; else if (g[i] == '"') break; else key += g[i]; }
          i++;
          size_t j = i; while (j < g.size() && isspace((unsigned char)g[j])) j++;
          if (depth == 1 && j < g.size() && g[j] == ':') {
            bool ok = false; for (const char* k : known) if (key == k) ok = true;
            if (!ok) { fprintf(stderr, "rabadon lint: unknown top-level key \"%s\" (typo? ignored by the gate)\n", key.c_str()); problems++; }
          }
          (void)s; continue;
        }
        if (c == '{' || c == '[') depth++;
        else if (c == '}' || c == ']') depth--;
        i++;
      }
    }
    // every deny/match pattern must compile
    auto lint_rules = [&](const char* section, const char* patKey) {
      std::vector<std::string> empty;
      for (const auto& r : parse_rules(g, section, patKey, empty)) {
        try { std::regex re(r.pattern); (void)re; }
        catch (const std::exception& e) {
          fprintf(stderr, "rabadon lint: rule \"%s\" has an uncompilable %s regex: %s\n", r.id.c_str(), patKey, e.what());
          problems++;
        }
      }
    };
    lint_rules("bash", "deny");
    lint_rules("protectedPaths", "match");
    if (problems == 0) { printf("rabadon lint: %s is valid.\n", path.c_str()); return 0; }
    fprintf(stderr, "rabadon lint: %d problem(s) — fix them or the gate silently ignores those rules.\n", problems);
    return 1;
  }

  // --statusline — the glanceable lamp for the Claude Code status bar. It reads
  // the SAME source of truth as the gate (~/.rabadon/enabled), so the bar can
  // never lie about state: lit lilac ● when supervising, dark gray ○ + "off" when
  // dormant. Read-only, one stat, fast. (The old JS statusline read a different
  // off-switch and stayed lit even when the gate was dormant — that mismatch is
  // exactly why the lamp couldn't be trusted.)
  if (argc > 1 && string(argv[1]) == "--statusline") {
    string in; { char b[8192]; size_t n; while ((n = fread(b, 1, sizeof b, stdin)) > 0) in.append(b, n); }
    string dir = get_str(in, "current_dir"); if (dir.empty()) dir = get_str(in, "cwd");
    if (dir.empty()) { const char* p = getenv("PWD"); dir = p ? p : "."; }
    string model = get_str(in, "display_name");
    size_t sl = dir.rfind('/'); string project = (sl == string::npos) ? dir : dir.substr(sl + 1);
    const string rhome = rabadon_home();
    const char* off = getenv("RABADON_OFF");
    bool hardOff = (off && string(off) == "1") || file_exists(dir + "/.rabadon/off")
                   || file_exists(rhome + "/silent");
    bool on = !hardOff && (file_exists(rhome + "/enabled") || file_exists(dir + "/.rabadon/on"));
    bool watching = !hardOff && !on;
    const string GRAY = "\033[38;5;245m", R = "\033[0m";

    // The ON lamp BREATHES. Claude Code spawns this process fresh for every
    // render and keeps no state, so the phase has to be a pure function of the
    // wall clock. Measured on this host (Claude Code 2.1.172): the status line
    // is event-driven with a 300ms trailing debounce and NO timer unless the
    // user sets statusLine.refreshInterval (floor: 1 second). Sampling is
    // therefore irregular, and at best ~0.8 frames/sec.
    //
    // That measurement is the reason this is a brightness pulse and not a
    // highlight sweeping across the letters: a moving crest sampled at
    // irregular moments reads as a light that TELEPORTS (letter 2, then 7,
    // then 3). Brightness carries no positional expectation — sampled at any
    // moment it simply reads as alive. OFF stays dead and static, because a
    // dormant supervisor must look dormant.
    static const int RAMP[] = { 97, 104, 141, 183, 189, 183, 141, 104 };
    const int STEPS = 8, STEP_MS = 750;           // one full breath = 6 seconds
    long long nowms; { struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
                       nowms = (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000; }
    // test hook: pin the clock so the breath is a deterministic, assertable
    // sequence instead of "whatever millisecond the test ran in".
    { const char* fake = getenv("RABADON_LAMP_MS"); if (fake && *fake) nowms = atoll(fake); }
    int ph = (int)((nowms / STEP_MS) % STEPS);
    char lamp[80];
    snprintf(lamp, sizeof lamp, "\033[38;5;%dm*\033[38;5;%dm rabadon\033[0m",
             RAMP[(ph + 2) % STEPS],   // the star runs ahead: a pilot light
             RAMP[ph]);
    // Three states, three readings, and the breath means one specific thing:
    // rabadon can act on you right now. WATCH is deliberately still — awake and
    // recording, but with its hands behind its back. SILENT is grey and says so.
    const string DIM_LILAC = "\033[38;5;97m";
    string seg = on       ? string(lamp)
               : watching ? (DIM_LILAC + "* rabadon watch" + R)
                          : (GRAY + "* rabadon off" + R);
    printf("%s%s%s%s%s  %s\n", GRAY.c_str(), model.c_str(), model.empty() ? "" : " · ",
           project.c_str(), R.c_str(), seg.c_str());
    return 0;
  }

  // the deterministic switch. Two files, three states, and the gate reads the
  // real ones — so a skill or an alias never has to "pretend" a state.
  //   ~/.rabadon/enabled -> ENFORCE (the arbiter acts)
  //   neither file       -> WATCH   (records everything, blocks nothing)
  //   ~/.rabadon/silent  -> SILENT  (truly dormant; also RABADON_OFF=1 per process
  //                                  and .rabadon/off per project)
  // `rabadon` toggles ENFORCE <-> WATCH, because that is the switch a user flips
  // daily. Going fully dark is deliberate and separate: `rabadon silent`.
  if (argc > 1) {
    string a1 = argv[1];
    if (a1 == "--on" || a1 == "--off" || a1 == "--toggle" || a1 == "--status" || a1 == "--silent") {
      const string rhome = rabadon_home();
      mkdir(rhome.c_str(), 0755);
      const string flag = rhome + "/enabled";
      const string mute = rhome + "/silent";
      bool on = file_exists(flag), silent = file_exists(mute);
      if (a1 == "--toggle") a1 = on ? "--off" : "--on";
      if (a1 == "--on") {
        unlink(mute.c_str()); silent = false;
        std::ofstream f(flag, std::ios::trunc); f << "on\n"; on = true;
      } else if (a1 == "--off") {
        unlink(flag.c_str()); on = false;
        unlink(mute.c_str()); silent = false;
      } else if (a1 == "--silent") {
        unlink(flag.c_str()); on = false;
        std::ofstream f(mute, std::ios::trunc); f << "silent\n"; silent = true;
      }
      printf("rabadon: %s\n",
             silent ? "SILENT — dormant everywhere, records nothing (`rabadon off` to watch again)"
                    : on ? "ON — the arbiter acts: refuses, repairs, proves"
                         : "WATCH — recording what it WOULD have caught, touching nothing (`rabadon on` to act)");
      // Name the file the state was read from. A user who cannot see WHERE the
      // mode lives cannot tell an unset switch from a broken install, and this
      // exact confusion cost a benchmark that spent weeks timing a gate in the
      // wrong mode because RABADON_DIR had moved the flag out from under it.
      if (a1 == "--status")
        printf("  read from: %s (%s)\n",
               silent ? mute.c_str() : flag.c_str(),
               silent ? "present"
                      : on ? "present" : "absent — no file means WATCH");
      return 0;
    }
  }

  string raw;
  { char buf[65536]; size_t n; while ((n = fread(buf, 1, sizeof(buf), stdin)) > 0) raw.append(buf, n); }
  if (raw.empty()) return 0;

  const string hook = get_str(raw, "hook_event_name");
  string cwd = get_str(raw, "cwd");
  if (cwd.empty()) { const char* c = getenv("PWD"); cwd = c ? c : "."; }

  // ---------- THREE STATES, and the middle one is the whole adoption ramp -----
  // SILENT  nothing runs. RABADON_OFF=1 (the recursion guard every child
  //         `claude -p` inherits — without it the supervisor supervises itself)
  //         or .rabadon/off in the project. This must stay absolutely dead.
  // WATCH   records everything, blocks nothing. Every rule is still evaluated,
  //         and a rule that WOULD have stopped the action is written to the
  //         ledger as WOULD_BLOCK — so a week of watching produces the only
  //         honest sales artifact there is: "here are the 14 things I would
  //         have caught, in your repo, on your work." Nobody hands a new tool
  //         write access to their codebase on day one; this is how the door
  //         opens. It is a free tier by construction, never the product.
  // ENFORCE the arbiter acts: refuse, repair, prove.
  const char* offEnv = getenv("RABADON_OFF");
  const string rhome = rabadon_home();
  if ((offEnv && string(offEnv) == "1") || file_exists(cwd + "/.rabadon/off")
      || file_exists(rhome + "/silent")) return 0;
  g_mode = (file_exists(rhome + "/enabled") || file_exists(cwd + "/.rabadon/on"))
             ? MODE_ENFORCE : MODE_WATCH;

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
  const string rdir = rabadon_home();
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
  em.drill = sid.rfind("fleet-", 0) == 0 || sid.rfind("doctor-", 0) == 0 || sid.rfind("drill-", 0) == 0;
  { const char* de = getenv("RABADON_DRILL"); if (de && strcmp(de, "1") == 0) em.drill = true; }
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

    // ---------- the net's verdict from the PREVIOUS tool call ----------
    // What matters is not "the suite is red" — it is the TRANSITION. Step 3.254
    // is the moment something that was green stopped being green while the run
    // kept going. A standing red reported on every call is noise the agent
    // learns to ignore; the EDGE, reported once with the failing output, is a
    // correction it can act on.
    {
      const string netRaw = read_file(cwd + "/.rabadon/net.json");
      const long long netTs = get_num(netRaw, "ts");
      if (!netRaw.empty() && netTs > stt.lastNetTs) {
        const string verdict = get_str(netRaw, "verdict");
        const string kindStr = get_str(netRaw, "kind");
        const int lvl        = (int)get_num(netRaw, "level");
        const string prev    = stt.lastNetVerdict;
        stt.lastNetTs = netTs;
        stt.lastNetVerdict = verdict;
        // lastTestRun:0 is what "the net has never run anything" was measured
        // on. From here it is the truth: the net ran, at this instant.
        stt.lastTestRun = netTs;
        if (verdict == "green")    stt.lastTestPass = netTs;
        else if (verdict == "red") stt.lastTestFail = netTs;
        stt.save();

        if (verdict == "red" && prev != "red") {
          string tail = get_str(netRaw, "tail");
          if (tail.size() > 700) tail = tail.substr(tail.size() - 700);
          const char* strength = lvl == 1 ? "your own test suite"
                               : lvl == 2 ? "the build/typecheck"
                                          : "a syntax check (weak evidence)";
          em.emit("CHECK_FAIL", "\"step\":\"net\",\"mode\":\"" + string(mode_tag()) +
                  "\",\"level\":" + std::to_string(lvl) + ",\"kind\":\"" + json_escape(kindStr) +
                  "\",\"fails\":[{\"check\":\"net-turned-red\",\"why\":\"" +
                  json_escape(tail.substr(0, 600)) + "\"}]");
          fprintf(stderr,
            "rabadon: this project just went GREEN -> RED, caught by %s.\n"
            "It happened on your last edit — this is not a pre-existing failure.\n"
            "%s\n"
            "Fix this before continuing: every step from here builds on a broken base.\n",
            strength, tail.c_str());
          // PostToolUse exit 2 is FEEDBACK to the agent, not a block — the
          // correction re-enters the run as an instruction.
          return refuse_code();
        }
      }
    }

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

      // ---------- THE ALWAYS-ON NET ----------
      // The agent just touched code. Start the project's own check in a DETACHED
      // child and return immediately: a hook that waits for a test suite freezes
      // the editor for as long as the suite takes, which is how a supervisor
      // becomes the thing people uninstall. The verdict lands in .rabadon/net.json
      // and is read on the next tool call — one call of latency, zero stall.
      //
      // ENFORCE ONLY. In watch mode rabadon spends not one cycle of the user's
      // machine on their repo; watch observes what the agent did, nothing more.
      // Turning it on is the moment you accept the cost of being supervised.
      if (isCode && g_mode == MODE_ENFORCE) {
        const string netBin = self_dir() + "/rabadon-net";
        if (file_exists(netBin)) {
          pid_t k = fork();
          if (k == 0) {
            setsid();
            int devnull = open("/dev/null", O_RDWR);
            if (devnull >= 0) { dup2(devnull, 0); dup2(devnull, 1); dup2(devnull, 2); }
            // argv[0] must carry the FULL path: rabadon-net locates its sibling
            // rabadon-truth from it, and a bare name makes it look in the
            // supervised project instead of the install directory.
            execl(netBin.c_str(), netBin.c_str(), cwd.c_str(), (char*)nullptr);
            _exit(127);
          }
          // do not wait: the child outlives this hook on purpose
        }
      }

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
            return refuse_code();
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
          return refuse_code();
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
        em.emit("REPAIR_START", "\"step\":\"diagnose\",\"attempt\":1,\"repair_kind\":\"diagnosis\",\"fixing\":[\"red-tests\"]");
        std::vector<string> bullets;
        size_t from = ss.recent.size() > 15 ? ss.recent.size() - 15 : 0;
        for (size_t k = from; k < ss.recent.size(); k++) bullets.push_back(ss.recent[k].second);
        const string goal = ss.goalPrompt.empty() ? "(no goal captured)" : ss.goalPrompt;
        const string failTail = out.size() > 4000 ? out.substr(out.size() - 4000) : out;
        Diag diag = diagnose(goal, bullets, command, failTail);
        if (!diag.ok) {
          em.emit("REPAIR_FAIL", "\"step\":\"diagnose\",\"attempt\":1,\"repair_kind\":\"diagnosis\",\"why\":\"diagnosis unavailable\"");
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
                  em.emit("REPAIR_OK", "\"step\":\"new gate: " + json_escape(ruleId) + "\",\"attempt\":1,\"repair_kind\":\"rule\"");
                  advice += "  new gate installed: " + ruleId + " — this class of break is now caught BEFORE it happens.\n";
                }
              }
            }
          }
        }
      }
      fprintf(stderr, "rabadon: tests are RED.%s\n",
        advice.empty() ? " Fix the failure before moving on." : advice.c_str());
      return refuse_code();
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
    // spool retention: once per session, drop day files and their .head
    // sidecars older than RABADON_SPOOL_DAYS (default 30). The chain is per
    // day-file, so pruning whole files never breaks `rabadon audit`; `rabadon
    // usage --days N` already filters, so history you still query is untouched.
    {
      long long keepDays = 30;
      const char* sd = getenv("RABADON_SPOOL_DAYS");
      if (sd && sd[0]) { long long v = atoll(sd); if (v > 0) keepDays = v; }
      const time_t cutoff = time(nullptr) - keepDays * 86400;
      const string spoolDir = rdir + "/spool";
      if (DIR* d = opendir(spoolDir.c_str())) {
        while (struct dirent* ent = readdir(d)) {
          string n = ent->d_name;
          bool jsonl = n.size() >= 6 && n.compare(n.size() - 6, 6, ".jsonl") == 0;
          if (!jsonl) continue;
          const string fp = spoolDir + "/" + n;
          struct stat fst;
          if (stat(fp.c_str(), &fst) == 0 && fst.st_mtime < cutoff) {
            unlink(fp.c_str());
            unlink((fp + ".head").c_str());
          }
        }
        closedir(d);
      }
      // stray legacy state-native-*.txt twins: gone after 7 days
      const time_t stateCut = time(nullptr) - 7 * 86400;
      if (DIR* d = opendir(rdir.c_str())) {
        while (struct dirent* ent = readdir(d)) {
          string n = ent->d_name;
          if (n.rfind("state-native-", 0) != 0) continue;
          const string fp = rdir + "/" + n;
          struct stat fst;
          if (stat(fp.c_str(), &fst) == 0 && fst.st_mtime < stateCut) unlink(fp.c_str());
        }
        closedir(d);
      }
    }
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
        Usage u = sum_usage(win); // the shared meter (Stop ledger tracks in/out)
        ss.tsOffset = size;
        ss.tokensOut += u.out;
        ss.tokensIn += u.in;
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
    em.emit("CHECK_FAIL", "\"step\":\"" + json_escape(toolName) + "\",\"mode\":\"" + mode_tag() +
            "\",\"fails\":[{\"check\":\"" + json_escape(ruleId) + "\",\"why\":\"" + json_escape(detail + " — " + why) + "\"}]");
    if (g_mode == MODE_ENFORCE) {
      // rule + sid ride on the STOP so the ledger can group refusals by RULE
      // without joining back to the CHECK_FAIL (legacy events still join by run)
      em.emit("STOP", "\"reason\":\"BLOCKED\",\"rule\":\"" + json_escape(ruleId) +
              "\",\"sid\":\"" + json_escape(sid) + "\",\"detail\":\"" + json_escape(detail) + "\"");
      stt.save();
      fprintf(stderr,
        "rabadon BLOCKED this action.\nRule: %s — %s\n%s\nAdjust the approach instead of retrying the same action.\n"
        "(user override: add \"%s\" to disabled[] in .rabadon/guard.json, or `rabadon off` to pause supervision)\n",
        ruleId.c_str(), why.c_str(), detail.c_str(), ruleId.c_str());
      exit(2);
    }
    // WATCH: the verdict is real and it is recorded — it is simply not enforced.
    // WOULD_BLOCK is the event a week of watching turns into "here is what I
    // would have stopped in your repo", which is the only demo that convinces
    // someone to hand over write access.
    em.emit("WOULD_BLOCK", "\"reason\":\"" + json_escape(ruleId) + "\",\"rule\":\"" + json_escape(ruleId) +
            "\",\"sid\":\"" + json_escape(sid) + "\",\"detail\":\"" + json_escape(detail) + "\"");
    stt.save();
    fprintf(stderr,
      "rabadon (watch) would have blocked this.\nRule: %s — %s\n%s\n"
      "Nothing was stopped. `rabadon on` makes this a real refusal.\n",
      ruleId.c_str(), why.c_str(), detail.c_str());
    exit(0);
  };

  // ---------- budget cap: the deterministic halt-before-burn ----------
  // .rabadon/budget.json is the user's ceiling — {"tokens":N} and/or {"usd":X}.
  // On EVERY tool call, rabadon measures this session's REAL cumulative usage
  // from the transcript (all four token classes) and, the moment the ceiling is
  // reached, REFUSES the next tool before it runs — the run halts without
  // burning past the cap. Not "show the cost": stop at it. When no budget.json
  // exists the whole check is one read of an empty string -> skipped; the meter
  // is opt-in (a set cap is a session you explicitly want fenced, so paying a
  // full transcript read per tool call there is the right trade). Override:
  // add "budget-cap" to disabled[] in guard.json, or `rabadon budget off`.
  {
    const string braw = read_file(cwd + "/.rabadon/budget.json");
    bool budgetOff = false;
    for (const auto& d : disabled) if (d == "budget-cap") budgetOff = true;
    if (!braw.empty() && !budgetOff) {
      const long long capTok = (long long)get_double(braw, "tokens");
      const double capUsd = get_double(braw, "usd");
      if (capTok > 0 || capUsd > 0) {
        const string tp = get_str(raw, "transcript_path");
        struct stat tst;
        if (!tp.empty() && stat(tp.c_str(), &tst) == 0) {
          const string all = read_file(tp);
          const Usage u = sum_usage(all);
          auto halt = [&](const string& capStr, const string& spent) {
            em.emit("CHECK_FAIL", "\"step\":\"budget\",\"fails\":[{\"check\":\"budget-cap\",\"why\":\"" +
              json_escape(capStr + " reached — " + spent) + "\"}]");
            em.emit("STOP", "\"reason\":\"BLOCKED\",\"rule\":\"budget-cap\",\"sid\":\"" + json_escape(sid) +
              "\",\"detail\":\"" + json_escape("budget cap " + capStr + " — " + spent) + "\"");
            stt.save();
            fprintf(stderr,
              "rabadon: budget cap %s reached — run halted before burn\n"
              "  this session: %s (measured from the transcript, all token classes).\n"
              "  raise it (`rabadon budget <n>`), clear it (`rabadon budget off`), "
              "or add \"budget-cap\" to disabled[] in .rabadon/guard.json.\n",
              capStr.c_str(), spent.c_str());
            exit(refuse_code());
          };
          if (capTok > 0 && u.tokens() >= capTok)
            halt(std::to_string(capTok) + " tokens",
                 "spent " + std::to_string(u.tokens()) + " tokens");
          if (capUsd > 0) {
            Rate r;
            if (model_rate(last_model(all), r)) {
              const double spentUsd = usd_cost(u, r);
              if (spentUsd >= capUsd) {
                char cap[48], sp[48];
                snprintf(cap, sizeof cap, "$%g", capUsd);
                snprintf(sp, sizeof sp, "spent $%.4f", spentUsd);
                halt(cap, sp);
              }
            }
          }
        }
      }
    }
  }

  // ---------- the project's own law first, then the floor nobody configures ----
  // The user's rules run first so a refusal carries THEIR rule id and THEIR
  // reason. The baseline is the backstop underneath: three laws compiled into
  // the binary that hold in a repo with no guard.json at all, because
  // `npm i -g rabadon` promised a gate that refuses the force-push and until
  // now a fresh install refused nothing. guard.json extends this floor;
  // disabled[] can remove any of the three by id.
  if (toolName == "Bash" && !command.empty()) {
    if (!guardRaw.empty())
      for (const auto& r : parse_rules(guardRaw, "bash", "deny", disabled))
        if (rx_test_cmd(r.pattern, command))
          block(r.id, r.why, "command matched deny rule: " + command.substr(0, 160));
    rbbase::Hit bh;
    if (rbbase::check(command, cwd, disabled, bh)) block(bh.id, bh.why, bh.detail);
  }

  if (!guardRaw.empty()) {
    if (toolName == "Bash" && !command.empty()) {
      // push gate: rabadon RUNS the project's own suite here and opens the gate
      // on the REAL result — telling is a warning, solving is the product. This
      // was the last thing that delegated to node; it is native now.
      if (rx_test_cmd("\\bgit\\s+push\\b", command) && !rx_test("--dry-run", command) &&
          guardRaw.find("\"pushGate\"") != string::npos && stt.lastCodeEdit > stt.lastTestPass) {
        size_t pg = guardRaw.find("\"pushGate\"");
        const string pgObj = take_obj(guardRaw, guardRaw.find(':', pg));
        const string runCmd = get_str(pgObj, "run");
        const string pgWhy = get_str(pgObj, "why");
        const string why = pgWhy.empty() ? "tests must be green before push" : pgWhy;
        long long tsec = get_num(pgObj, "timeoutSec"); if (tsec <= 0) tsec = 900;
        const string passPat = get_str(guardRaw, "testPassPattern");
        if (runCmd.empty())
          block("push-gate", why, "code was edited after the last passing test run — run the test suite first");
        em.emit("REPAIR_START", "\"step\":\"push-gate\",\"attempt\":1,\"repair_kind\":\"testrun\",\"fixing\":[\"tests-not-green\"]");
        int code = -1;
        const string out = run_shell(runCmd, (int)tsec, 16 * 1024 * 1024, &code);
        const bool green = (code == 0) && (passPat.empty() ? true : rx_test(passPat, out));
        if (green) {
          stt.lastTestPass = now_ms(); stt.lastTestRun = now_ms();
          em.emit("REPAIR_OK", "\"step\":\"push-gate\",\"attempt\":1,\"repair_kind\":\"testrun\"");
          // fall through: the push is now legitimately allowed
        } else {
          em.emit("REPAIR_FAIL", "\"step\":\"push-gate\",\"attempt\":1,\"repair_kind\":\"testrun\",\"why\":\"tests not green\"");
          string fails; {
            std::istringstream is(out); string ln; std::vector<string> keep;
            while (std::getline(is, ln)) if (rx_test("fail|error|\\*\\*\\*|tests passed", ln)) keep.push_back(ln);
            size_t from = keep.size() > 15 ? keep.size() - 15 : 0;
            for (size_t i = from; i < keep.size(); i++) fails += keep[i] + "\n";
          }
          if (fails.empty()) fails = out.size() > 800 ? out.substr(out.size() - 800) : out;
          block("push-gate", why, "rabadon ran the tests itself (" + runCmd + ") — NOT GREEN.\n" + fails +
            "Fix the failure; rabadon will re-run the suite on your next push attempt.");
        }
      }
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
