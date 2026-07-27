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
#include <unistd.h>
#include <fcntl.h>

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

  // cold paths keep the full node behavior (test analysis, diagnosis, ledger)
  if (hook != "PreToolUse") return delegate_to_node(gateMjs, raw);

  const string toolName = get_str(raw, "tool_name");
  size_t ti = raw.find("\"tool_input\"");
  const string command = ti == string::npos ? "" : get_str(raw, "command", ti);
  string filePath = ti == string::npos ? "" : get_str(raw, "file_path", ti);
  if (filePath.empty() && ti != string::npos) filePath = get_str(raw, "notebook_path", ti);
  const string sid = get_str(raw, "session_id");
  const string toolUseId = get_str(raw, "tool_use_id");

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

  // twin-delivery dedupe on tool_use_id (same law as the node gate)
  if (!toolUseId.empty()) {
    const string key = "PreToolUse:" + toolUseId;
    for (const auto& id : ss.recentEv) if (id == key) return 0;
    ss.recentEv.push_back(key);
    if (ss.recentEv.size() > 12) ss.recentEv.erase(ss.recentEv.begin(), ss.recentEv.end() - 12);
  }

  const string guardRaw = read_file(cwd + "/.rabadon/guard.json");
  const auto disabled = parse_disabled(guardRaw);

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
