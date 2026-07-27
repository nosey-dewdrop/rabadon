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

// ---------- native session state (simple key=value file) ----------

struct NativeState {
  string path;
  string lastCmd; long long lastCmdTs = 0; int cmdRepeat = 1;
  int offTarget = 0; int driftChallenged = 0;
  std::vector<string> recentIds;

  void load() {
    std::ifstream f(path);
    string line;
    while (std::getline(f, line)) {
      size_t eq = line.find('=');
      if (eq == string::npos) continue;
      string k = line.substr(0, eq), v = line.substr(eq + 1);
      if (k == "lastCmd") lastCmd = v;
      else if (k == "lastCmdTs") lastCmdTs = atoll(v.c_str());
      else if (k == "cmdRepeat") cmdRepeat = atoi(v.c_str());
      else if (k == "offTarget") offTarget = atoi(v.c_str());
      else if (k == "driftChallenged") driftChallenged = atoi(v.c_str());
      else if (k == "id") recentIds.push_back(v);
    }
  }
  void save() {
    std::ofstream f(path, std::ios::trunc);
    if (!f) return;
    f << "lastCmd=" << lastCmd << "\nlastCmdTs=" << lastCmdTs << "\ncmdRepeat=" << cmdRepeat << "\n";
    f << "offTarget=" << offTarget << "\ndriftChallenged=" << driftChallenged << "\n";
    size_t from = recentIds.size() > 16 ? recentIds.size() - 16 : 0;
    for (size_t i = from; i < recentIds.size(); i++) f << "id=" << recentIds[i] << "\n";
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

  // twin-delivery dedupe on tool_use_id (same law as the node gate)
  mkdir((cwd + "/.rabadon").c_str(), 0755);
  NativeState st;
  st.path = cwd + "/.rabadon/state-native-" + (sid.empty() ? "default" : sid.substr(0, 16)) + ".txt";
  st.load();
  if (!toolUseId.empty()) {
    const string key = "PreToolUse:" + toolUseId;
    for (const auto& id : st.recentIds) if (id == key) return 0;
    st.recentIds.push_back(key);
  }

  const string guardRaw = read_file(cwd + "/.rabadon/guard.json");
  const auto disabled = parse_disabled(guardRaw);

  auto block = [&](const string& ruleId, const string& why, const string& detail) {
    em.emit("CHECK_FAIL", "\"step\":\"" + json_escape(toolName) + "\",\"fails\":[{\"check\":\"" + json_escape(ruleId) + "\",\"why\":\"" + json_escape(detail + " — " + why) + "\"}]");
    em.emit("STOP", "\"reason\":\"BLOCKED\",\"detail\":\"" + json_escape(detail) + "\"");
    st.save();
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
      // push gate needs to RUN the suite — that is node's cold path, delegate
      if (rx_test("\\bgit\\s+push\\b", command) && !rx_test("--dry-run", command) && guardRaw.find("\"pushGate\"") != string::npos) {
        st.save();
        return delegate_to_node(gateMjs, raw);
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
        st.offTarget++;
        if (st.offTarget >= 5 && !st.driftChallenged && !ruleOff("promise-off-target")) {
          st.driftChallenged = 1;
          block("promise-off-target",
            "5 edits this session landed outside the promised areas — the session is drifting from its star",
            "star: " + star + " — latest off-target file: " + rel +
            " (fires once per session; if this work is intended, update .rabadon/promise.json areas)");
        }
      }
    }
  }

  // test-tamper: suite red (node state) + a test-file edit that weakens it
  if ((toolName == "Edit" || toolName == "Write" || toolName == "MultiEdit") && !filePath.empty()) {
    const string nodeState = read_file(cwd + "/.rabadon/state.json");
    long long lastFail = get_num(nodeState, "lastTestFail");
    long long lastPass = get_num(nodeState, "lastTestPass");
    if (lastFail > lastPass) {
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
    long long lastCodeEdit = get_num(read_file(cwd + "/.rabadon/state.json"), "lastCodeEdit");
    bool editedBetween = lastCodeEdit > st.lastCmdTs;
    if (st.lastCmd == command && !editedBetween) st.cmdRepeat++;
    else st.cmdRepeat = 1;
    st.lastCmd = command;
    st.lastCmdTs = now_ms();
    if (st.cmdRepeat >= 3)
      block("loop-stop", "the same command has now run 3x with no code change in between — a loop, not progress",
        "looping on: " + command.substr(0, 120));
  }

  string label = toolName == "Bash" ? ("bash: " + command.substr(0, 80)) : (toolName + ": " + filePath.substr(filePath.rfind('/') + 1));
  em.emit("STEP_START", "\"step\":\"" + json_escape(label) + "\"");
  st.save();
  return 0;
}
