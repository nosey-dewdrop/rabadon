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
#include <set>
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
#include "rules.h"   // guard.json rule parsing + matching — shared with `rabadon exec`
#include "hookev.h"  // ONE place that turns any agent's event into rabadon's event
#include "testout.h" // did the runner execute any tests — shared with `rabadon net`
#include "version.h" // one version string, lockstep with package.json
#include <sys/file.h>
#include "cli_help.h"

using std::string;

// Supervision mode, resolved once per invocation. WATCH is not a crippled
// ENFORCE: every rule runs and every verdict is recorded, the only difference
// is that the action is allowed to proceed. See the three-state block in main().
enum { MODE_SILENT = 0, MODE_WATCH = 1, MODE_ENFORCE = 2 };
static int g_mode = MODE_SILENT;
// Which agent sent this event. Set once from hookev.h, read only where a
// refusal has to be SPOKEN, because that is the one thing the agents disagree
// about: the laws are identical, the way you tell the agent "no" is not.
static rbhook::Dialect g_dialect = rbhook::DIALECT_UNKNOWN;
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

// utf8_clip lives in chain.h now, beside the ledger's one writer — it was
// defined here, five call sites used it, and the seven that kept a raw substr
// wrote the corrupt day this comment used to describe.
using rbchain::utf8_clip;

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return "";
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

static bool file_exists(const string& p) { struct stat st; return stat(p.c_str(), &st) == 0; }

// stat() collapses two different answers into one false: "the flag is not
// there" and "I am not allowed to look". The first is a user who never ran
// `rabadon on`. The second is a supervisor that has lost sight of its own
// switch, and reading that as watch mode is how an installed, enabled gate
// goes quiet. Measured 5 August: an unset HOME, a RABADON_DIR pointing at a
// regular file, a home at mode 000, and a home on a read-only volume each
// produced exit 0 with zero bytes on stdout for `rm -rf`, which from the
// user's seat is indistinguishable from "rabadon looked and it was fine".
// Every storage failure in the same run fell closed, including a genuinely
// full disk. The ledger was hard and the switch was not.
enum FlagState { FLAG_PRESENT, FLAG_ABSENT, FLAG_UNKNOWN };
static FlagState flag_state(const string& p) {
  struct stat st;
  errno = 0;
  if (stat(p.c_str(), &st) == 0) return FLAG_PRESENT;
  return errno == ENOENT ? FLAG_ABSENT : FLAG_UNKNOWN;
}

// The home is an answer only if somebody named it. With neither RABADON_DIR
// nor HOME set, "./.rabadon" is a guess about whatever directory the agent
// happens to be standing in.
static bool rabadon_home_known() {
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) return true;
  const char* h = getenv("HOME");
  return h && h[0];
}

// Three rules answer to the operator alone: disabled[] in guard.json does not
// switch them off, and the refusal must not offer a door that is welded shut.
// They are named here rather than at the decision site because the refusal
// printer needs the same answer. See the sealing note above the promise block.
static bool sealed_rule(const string& id) {
  return id == "promise-tamper" || id == "promise-anti-path" || id == "guard-weaken";
}

// The rabadon home: RABADON_DIR when set (test isolation, multi-tenant), else
// $HOME/.rabadon. ONE rule for the mode flags AND the spool — a split home
// means `rabadon on` and the ledger disagree about which machine they live on.
// ONE definition, in pathres.h, because baseline.h must refuse a delete aimed
// at this directory and a law that computes the path itself can disagree with
// the program that uses it.
static string rabadon_home() { return rbpath::rabadon_dir(); }

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

// ---------- which model answers, when one is asked at all ----------
// The two model names below were compiled in: the drift judge always spoke to
// claude-haiku-4-5 by literal, and the incident brain always took whatever the
// account defaults to. That is a supervisor picking someone else's vendor. Both
// are env now, both default to exactly what was hard-coded, so this change moves
// no behaviour on its own — it only makes the choice sayable from outside.
// RABADON_MODEL is deliberately NOT reused: loop.cpp and llm-proposer.sh own it
// as the per-tier proposer model, the gate inherits the session's environment,
// and one name for two jobs would silently send the judge to the wrong model.
static string env_or(const char* name, const char* fallback) {
  const char* v = getenv(name);
  return (v && *v) ? string(v) : string(fallback);
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

// ---------- where this session's guard lives ----------
// It was `cwd + "/.rabadon/guard.json"`: the exact directory the session is
// standing in, with no walk toward the project root. So a session started at the
// project root got the project's rules and a session started one directory down
// got none of them. Measured in a real repository on 3 August, from its `engine`
// subdirectory, with four rules loaded at the root and zero loaded there:
//
//   git add <a copyrighted never-push directory>   ALLOWED
//   git add -A                                     ALLOWED
//   ctest --test-dir build -N                      ALLOWED
//   wrangler deploy                                ALLOWED
//
// Three of those four were written by the engine itself after real incidents, so
// each one is a thing that had already happened once and was free to happen
// again one `cd` away from where the rule was authored. An agent works in `src/`
// far more often than at the root, so this was the ordinary condition and not an
// edge of it. The compiled baseline was never affected because it resolves paths
// per segment; the guard was the last layer reading a single directory, and it
// is the layer the operator writes their own rules into.
//
// The walk goes UP from cwd and STOPS AT THE PROJECT ROOT. Stopping matters as
// much as walking: a guard found above the repository would apply one project's
// private rules to another project's work, which is a worse failure than the one
// being repaired. The nearest guard wins, so a nested `.rabadon/` still governs
// its own subtree.
static string guard_path_for(const string& cwd) {
  string root = rbpath::project_root(cwd);
  // project_root() falls back to cwd itself when nothing above holds a `.git`,
  // so in a directory that is not inside any repository the bound and the start
  // were the same place and the walk never took a step. The home directory is
  // the bound there: a guard above HOME is not this operator's project.
  {
    const char* h = getenv("HOME");
    const string home = h ? rbpath::resolve_real(string(h)) : string();
    const string here = rbpath::resolve_real(rbpath::lexical_abs(cwd, "/"));
    if (root == here && !home.empty() && here.size() > home.size() &&
        here.compare(0, home.size(), home) == 0 && here[home.size()] == '/')
      root = home;
  }
  string p = rbpath::resolve_real(rbpath::lexical_abs(cwd, "/"));
  for (;;) {
    struct stat st;
    const string cand = p + "/.rabadon/guard.json";
    if (stat(cand.c_str(), &st) == 0 && S_ISREG(st.st_mode)) return cand;
    if (p == root || p.size() <= 1) break;
    const size_t slash = p.rfind('/');
    if (slash == string::npos || slash == 0) break;
    const string up = p.substr(0, slash);
    // never climb past the project. if the root is not an ancestor of where we
    // are, the walk has already left the tree and has to stop here.
    if (up.size() < root.size()) break;
    p = up;
  }
  // nothing found: name the session's own directory, so a later write creates
  // the guard where the session is rather than somewhere it did not choose.
  return cwd + "/.rabadon/guard.json";
}

// ---------- ledger lines written before the session emitter exists ----------
// `--on`, `--off` and `--wrong` all answer in the argv block at the top of
// main, before there is a cwd, a run id or a project. They still belong on the
// chain: a mode change is the most consequential thing anyone does to this
// tool, and a wrong refusal is the number the whole product is judged on. Both
// go through rbchain::append like every other line, so `rabadon audit` covers
// them and neither can be edited without the audit naming the break.
static string ledger_line(const string& ev, const string& extraJson) {
  const string rdir = rabadon_home();
  mkdir(rdir.c_str(), 0755);
  mkdir((rdir + "/spool").c_str(), 0755);
  char day[16];
  { time_t t = time(nullptr); struct tm tmv; gmtime_r(&t, &tmv); strftime(day, 16, "%Y-%m-%d", &tmv); }
  const char* who = getenv("USER");
  string body = "{\"v\":1,\"seq\":1,\"ts\":" + std::to_string(now_ms()) +
    ",\"run\":\"cli-" + std::to_string(getpid()) + "\",\"pipe\":\"" +
    json_escape(string(who ? who : "cli")) + ":cli\",\"ev\":\"" + ev + "\"" +
    (extraJson.empty() ? "" : "," + extraJson);
  // rbchain::append takes an OPEN body: it appends `,"prev":"..."}` itself, so
  // closing the object here produced two JSON documents on one line and a chain
  // the audit correctly called broken.
  return rbchain::append(rdir + "/spool/" + string(day) + ".jsonl", body);
}

// SUPERVISION THAT WENT AWAY WITHOUT SAYING SO.
//
// `rabadon --off` writes a MODE line, and that was taken to mean mode changes
// are on the chain. They are not. The switch IS a file, `<rabadon home>/enabled`,
// and `rm` on that file is the same change with none of the record: measured in
// an isolated lab, enforce refused `git push --force origin main` with exit 2,
// the file was removed with rm, the identical command returned exit 0, and the
// MODE count on the ledger went from 1 to 1. The comment at the toggle already
// says supervision going away is the most consequential thing anybody does to
// this tool. It was still the one thing that could happen silently.
//
// So the mode is not trusted to announce itself: it is COMPARED, on every hook
// invocation, against the last mode this machine recorded. A difference with no
// MODE line between them is written down as one, marked out-of-band, naming both
// ends. This does not stop the removal — an operator who owns the disk owns the
// switch, and pretending otherwise would be the lie this tool exists to refuse —
// it makes the removal leave a mark on the same hash-chained ledger as the
// refusals it silenced.
//
// The marker file lives beside the switch and is written only when the mode
// actually differs, so the hot path pays one small read and nothing else.
static void note_mode(const string& now) {
  const string rdir = rabadon_home();
  const string markPath = rdir + "/mode.last";
  string was;
  { std::ifstream f(markPath); if (f) std::getline(f, was); }
  while (!was.empty() && (was.back() == '\n' || was.back() == '\r' || was.back() == ' '))
    was.pop_back();
  if (was == now) return;
  // A machine that has never recorded a mode is not a machine whose supervision
  // changed. Recording the first observation as a transition would put a fake
  // MODE line on every fresh install.
  if (!was.empty())
    ledger_line("MODE", "\"from\":\"" + json_escape(was) + "\",\"to\":\"" +
                        json_escape(now) + "\",\"outOfBand\":true");
  mkdir(rdir.c_str(), 0755);
  std::ofstream f(markPath, std::ios::trunc);
  if (f) f << now << "\n";
}

struct Emitter {
  string spoolPath, sockPath, runId, pipe;
  // Who this event belongs to. Both answers were already in the gate's hands
  // on every invocation and neither one reached the disk.
  //
  // `call` is Claude Code's tool_use_id, which arrives on both the PreToolUse
  // and the PostToolUse hook for one tool call. Every hook invocation is its
  // own process, so `run` is unique per EVENT and correlates nothing —
  // measured on the live spool, 75.126 events carried 75.126 distinct run ids,
  // zero reuse. STEP_START and STEP_OK are the two ends of one tool call and
  // nothing written down said so. Pairing them by "the next OK in the same
  // pipe" closes 58,5% of the starts and joins unrelated work in 17,6% of even
  // those, giving a p99 of 15,5 minutes and one pair five days wide. Duration
  // is not missing from this ledger, it is unjoinable, and this id is the join.
  //
  // `sess` is the session id. `pipe` is spelled "<project>:session" and is not
  // one — it is the directory, so every session and every subagent that has
  // ever run in stitchu/ shares a single pipe spanning 214 hours across nine
  // days. rabadon-export turns a pipe into a TRACE id, which means a trace is
  // currently the entire history of a folder.
  string call, sess;
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
      // Absent rather than empty. A hook that carries no tool_use_id (Stop,
      // SessionStart) is not part of a tool call, and writing "" would make
      // every one of them look like members of the same nameless call.
      (call.empty() ? "" : ",\"call\":\"" + json_escape(call) + "\"") +
      (sess.empty() ? "" : ",\"sess\":\"" + json_escape(sess) + "\"") +
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

// ---------- did anything in this project change since the last check? ----------
//
// The hole this closes. The check used to be started by exactly one thing: a
// PostToolUse event whose tool was Edit, Write or MultiEdit. So an agent that
// edited through the shell — `sed -i`, a heredoc, `>`, `cp`, `patch`, `git
// checkout`, a codegen script — broke the project and rabadon never ran
// anything. Worse, `rabadon run -- <agent>` exists precisely for agents with no
// edit tool at all; for every one of those, supervision was zero. The contract
// said "after every edit to code" and meant "after every edit made with a tool
// I recognise", which is not the same sentence.
//
// Asking the filesystem instead of the tool name is what makes the answer agent
// -independent: a file is newer than the last verdict, or it is not. No dialect
// knows better than the mtime.
//
// COST IS THE WHOLE DESIGN. The walk exits at the FIRST file newer than the
// last check, which is the case that matters — something just changed, so the
// answer arrives after a handful of stats. The expensive direction is proving a
// negative on a large tree, so it is capped: past `cap` entries the walk stops
// and says it did not finish. A capped walk returns false — rabadon does not
// start a suite on a maybe — and the caller SAYS so rather than letting the
// user believe a check happened.
static bool tree_changed_since(const string& dir, long long sinceMs, int cap, bool* capped) {
  *capped = false;
  int seen = 0;
  std::vector<string> stack{dir};
  while (!stack.empty()) {
    const string cur = stack.back(); stack.pop_back();
    DIR* d = opendir(cur.c_str());
    if (!d) continue;
    while (struct dirent* ent = readdir(d)) {
      const string n = ent->d_name;
      if (n == "." || n == "..") continue;
      // dot-directories (.git, .rabadon, .venv), dependency and output trees:
      // churn that is not the user's source. .rabadon especially — the gate
      // writes there on every event, so counting it would make every command
      // look like an edit and every command start a suite.
      if (n[0] == '.' || n == "node_modules" || n == "target" ||
          n == "vendor" || n == "dist" || n == "build" || n == "__pycache__") continue;
      if (++seen > cap) { *capped = true; closedir(d); return false; }
      const string p = cur + "/" + n;
      struct stat st;
      if (lstat(p.c_str(), &st) != 0) continue;
      if (S_ISDIR(st.st_mode)) { stack.push_back(p); continue; }
      if (!S_ISREG(st.st_mode)) continue;
      if ((long long)st.st_mtime * 1000 > sinceMs) { closedir(d); return true; }
    }
    closedir(d);
  }
  return false;
}

// ---------- THE CONTRACT ----------
//
// The complaint this answers, in the user's words: "it catches nothing, it
// repairs nothing, and if it did repair I have no idea on what grounds, and I
// have no idea when it would fire." Every one of those is the same missing
// thing — the supervisor never SAID what it was going to do. It only ever
// became knowable by an incident happening.
//
// So: at the start of every session, before anything is judged, rabadon states
// its terms. What it will run, when it will run it, what happens if that comes
// back red, what it will not do, and where it is blind. Read once, it should be
// possible to predict every intervention rabadon will make for the rest of the
// session. That predictability IS the product; a guardrail that surprises you
// is a guardrail you turn off.
//
// The hardest rule here is the silence rule: if rabadon cannot protect this
// project, the contract has to SAY so and say what would fix it. A tool that
// finds nothing to run and then says nothing is indistinguishable, from the
// outside, from a tool that is working.
static string contract_block(const string& cwd, const string& truthJson,
                             bool enforce, bool repairOn, bool cursorDialect,
                             const string& guardRaw) {
  const int level = (int)get_num(truthJson, "level");
  const string run = get_str(truthJson, "run");
  const string why = get_str(truthJson, "why");
  std::ostringstream o;
  o << "rabadon: here is what I will do in this project.\n";

  if (level == 0 || run.empty()) {
    // The honest failure. Not a warning buried in a log — the first line of the
    // contract, because a session that starts here is a session rabadon cannot
    // vouch for and the user has to know that in second one, not on day three.
    o << "  check      : NONE FOUND — I cannot check this project, so I cannot catch\n"
      << "               anything here. Tell me what to run, and I will:\n"
      << "                 put  \"check\": \"<the command that tells you it works>\"\n"
      << "                 in   " << cwd << "/.rabadon/guard.json\n";
  } else {
    const string kind = get_str(truthJson, "kind");
    const char* strength = kind == "declared" ? "the command YOU declared — I did not guess it"
                         : level >= 3 ? "your own test suite"
                         : level == 2 ? "the build/typecheck — weaker than a suite"
                                      : "a syntax check only — WEAK evidence";
    o << "  check      : " << run << "\n"
      << "               (" << strength << "; found via " << (why.empty() ? "discovery" : why) << ")\n";
  }

  // `rabadon run` owns the agent's PATH and nothing else. It can refuse a
  // program before it runs; it gets no event AFTER an action, so nothing there
  // starts the project's check and nothing stops the agent on a red one. Said
  // here, inside the one contract, rather than as a correction printed under it
  // — a block that promises a stop and is then contradicted three lines later
  // is worse than either sentence alone.
  const char* runEnv = getenv("RABADON_RUN");
  const bool postHookless = runEnv && string(runEnv) == "1";

  if (postHookless) {
    o << "  when       : NEVER on my own. This agent gives me no signal after an action,\n"
      << "               so I cannot run that check and I will NOT stop you on a red one.\n"
      << "               What I do here: refuse forbidden programs BEFORE they run.\n";
  } else if (!enforce) {
    // watch mode spends nothing on the user's machine, which also means it
    // stops nothing. Saying "after every edit" here would be a lie.
    o << "  when       : NEVER — this project is in watch mode. I record what I would\n"
      << "               have stopped and run nothing. `rabadon on` to enforce.\n";
  } else if (level == 0 || run.empty()) {
    o << "  when       : nothing to run.\n";
  } else {
    o << "  when       : after any action that changed a file in this project — an edit\n"
      << "               tool or a shell command, I ask the filesystem, not the tool name.\n"
      << "               It runs in the background; you never wait for it.\n";
  }

  if (enforce && level > 0 && !run.empty() && !postHookless)
    o << "  if it goes red: your next action does not start. Not a warning — a refusal,\n"
      << "               repeated for as long as it stays red.\n"
      << "               STILL ALLOWED while red: reading anything, editing anything,\n"
      << "               and re-running that check. A pass clears it immediately.\n";

  o << "  repair     : "
    << (repairOn
        ? "on — I may propose a patch in an isolated copy. Your tree is never edited.\n"
        : "OFF. Turning it on spends money on YOUR account (it calls a model),\n"
          "               so I will not do it behind your back. Turn on: RABADON_JUDGE=1\n");

  {
    const string praw = read_file(cwd + "/.rabadon/promise.json");
    const auto areas = parse_str_array(praw, "areas");
    if (!areas.empty()) {
      o << "  scope      : ";
      for (size_t i = 0; i < areas.size() && i < 6; i++) o << (i ? ", " : "") << areas[i];
      if (areas.size() > 6) o << ", +" << (areas.size() - 6) << " more";
      o << "\n               (work outside this and I say something)\n";
    } else {
      o << "  scope      : not set — every path in this project is fair game.\n";
    }
  }

  {
    // Where the supervision has holes. Naming them is not a weakness of the
    // product; a user who knows the hole works around it, a user who does not
    // trusts a coverage that was never there.
    std::vector<string> blind;
    if (cursorDialect)
      blind.push_back("Cursor has no pre-edit hook: I see file edits AFTER they land, not before");
    blind.push_back("an agent that calls a program by absolute path (/usr/bin/git) walks past me");
    if (guardRaw.empty())
      blind.push_back("no .rabadon/guard.json here, so no command is denied — I only watch");
    o << "  blind spots:\n";
    for (const auto& b : blind) o << "               - " << b << "\n";
  }
  return o.str();
}

// ---------- session state: one file per session, ONE writer each ----------
//
// Everything a session is promised for the length of the session lived in one
// shared map inside <project>/.rabadon/state.json, and the loader kept the last
// four entries:
//
//     if (sessions.size() > 4) sessions.erase(sessions.begin(), sessions.end() - 4);
//
// On 3 August seven sessions ran at once, one main and six agents. The main
// session's record was evicted, so `promise-off-target` — whose own refusal
// text reads "fires once per session" — fired three times, and the latch that
// was supposed to make that sentence true went with it. Twelve concurrent
// writers left four records behind and eight silently gone: every writer read
// the whole file, rewrote the whole file, and the last one to finish won.
//
// A cap plus last-writer-wins is not a corner case for this program. Fanning
// out across agents is what it is FOR, and the thing supervising a fan-out
// cannot degrade the moment the fan-out is wider than four, least of all
// silently. So a session's own state is now its own file:
//
//     <project>/.rabadon/sessions/<key>.json
//
// which removes the cap, the eviction and the contention in one move, because
// two sessions no longer write the same bytes. It is written tmp+rename, so a
// reader never sees half of one.
//
// WHAT STAYS SHARED, AND WHY EACH ONE.
// state.json keeps only the facts that are about the TREE rather than about a
// session, and the split is the same one lastTestPass/lastTestVerified already
// made a layer up:
//   lastCodeEdit          any session's edit changes the tree for all of them
//   lastTestVerified      rabadon forked the suite and read exit 0 itself
//   lastTestVerifiedFail  rabadon forked the suite and read a non-zero exit
//   lastNetTs/Verdict     the always-on net, one watcher per project
//   lastDiagAt/lastDiagSig  a rate limit on an expensive call about the tree
// and lastTestPass / lastTestFail / lastTestRun move INTO the session, because
// they are stamped from watching a Bash result go past — a claim by one session
// about a run that session did. Sharing them is what produced the second half
// of this incident: lastTestFail written at 02:18 by one session, lastTestPass
// left at 00:48, and a session born hours later told "tests are RED" with its
// own suite green in front of it. Twice, both filed as `rabadon wrong
// stale-net-verdict`. A red one session merely watched is not evidence another
// session may act on; a red rabadon RAN is, and that one is shared.
//
// The shared file is still written by everyone, so it is written as a MERGE
// rather than as a replace: re-read, take the later of each timestamp, keep the
// string that belongs to the newer stamp. No lock, and correct for monotonic
// data, which is all that is left in there.
//
// BOUNDED BY TIME, NOT BY COUNT. Removing the cap is not a fix if it becomes
// unbounded growth on a machine that runs this all day, and "keep the newest N"
// is the very rule that lost the main session. Session files age out: anything
// untouched for SESSION_TTL_MS is deleted, swept at most once every ten minutes
// per project so the sweep is not on the hot path.

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

// how long a session file survives without being touched. A Claude Code
// session that has said nothing for a day is over; its record is the only
// thing still holding disk.
static const long long SESSION_TTL_MS = 24LL * 60 * 60 * 1000;
static const long long SESSION_SWEEP_EVERY_MS = 10LL * 60 * 1000;

// write, then move into place. A reader that arrives mid-write gets the whole
// previous file rather than half of the new one, which matters more here than
// usual: every one of these files is read by a process that did not write it.
static bool write_atomic(const string& path, const string& body) {
  const string tmp = path + ".tmp." + std::to_string(getpid());
  { std::ofstream f(tmp, std::ios::trunc); if (!f) return false; f << body; }
  if (rename(tmp.c_str(), path.c_str()) != 0) { unlink(tmp.c_str()); return false; }
  return true;
}

// The session id becomes a FILENAME, which it never was before, so two things
// that did not matter now do.
//
// It was truncated to 16 characters. For the harness's own uuids that is
// harmless — the 61 distinct ids on this machine collide 0 times at 16, and
// two random uuids agreeing on 16 hex characters is not something to plan for.
// But `sid` is whatever the caller put in the event, the fleet and drill
// prefixes are deliberately shaped, and a collision here is not a wrong answer,
// it is two sessions sharing one record, which is the bug this whole file is
// about. So the readable prefix is kept for anyone looking in the directory and
// a hash of the WHOLE id is appended, and the collision question stops being a
// question.
//
// And a filename built from untrusted text is a path. `../../etc/x` as a
// session id would have written outside the project. Everything outside
// [A-Za-z0-9._-] is replaced before it is used.
static string session_key(const string& sid) {
  const string s = sid.empty() ? string("default") : sid;
  string safe;
  for (size_t i = 0; i < s.size() && safe.size() < 16; i++) {
    const char c = s[i];
    safe += (isalnum((unsigned char)c) || c == '-' || c == '_' || c == '.') ? c : '_';
  }
  if (safe.empty() || safe == "." || safe == "..") safe = "s";
  return safe + "-" + rbsha::hex(s).substr(0, 12);
}

struct Sess {
  string goalPrompt; long long goalTs = 0;
  std::vector<string> touchedDirs; bool fanoutWarned = false;
  string lastCmd; long long lastCmdTs = 0; int cmdRepeat = 1;
  int actionCount = 0, offTarget = 0, driftChallenged = 0, walkCapWarned = 0;
  std::vector<std::pair<long long, string>> recent;
  std::vector<string> recentEv;
  long long tsOffset = 0, tokensOut = 0, tokensIn = 0;
  // stamped from WATCHING this session's own Bash result go past. The post hook
  // never receives an exit code — tool_response is a string the session
  // produced — so this is a claim, and it is the claim of the thing being
  // checked. It belongs to the session that made it and to nobody else.
  long long lastTestPass = 0, lastTestFail = 0, lastTestRun = 0;
};

struct State {
  string path;      // <project>/.rabadon/state.json — the shared facts
  string sessDir;   // <project>/.rabadon/sessions   — one file per session
  string sessKey;   // the file this process owns in there
  string legacyKey; // the sid16 this session had inside the old shared map
  long long lastCodeEdit = 0, lastDiagAt = 0;
  // rabadon RAN the suite and read the real exit code itself — the push gate's
  // own fork, or the always-on net's. This is the only test result one session
  // may act on because another session produced it, and it is shared for
  // exactly that reason. Before the verified/watched split, `go test -run
  // TestNothingMatchesThis ./...` printed `ok vac 0.142s [no tests to run]`,
  // exited 0, refreshed the stamp, and the next push went out over a red suite.
  long long lastTestVerified = 0;
  long long lastTestVerifiedFail = 0;
  string lastDiagSig;
  // the always-on net: the timestamp of the last verdict we have already acted
  // on, and what that verdict was. Both are needed to spot the TRANSITION —
  // "it is red" is noise if it was red an hour ago; "it just turned red" is the
  // catch the whole product exists for.
  long long lastNetTs = 0;
  string lastNetVerdict;
  Sess sess;                 // this process's own session, its own file
  bool sessLoaded = false;

  string sess_path() const { return sessDir + "/" + sessKey + ".json"; }

  Sess& session() { return sess; }

  // ---- the shared file -----------------------------------------------------
  void load_shared(const string& j) {
    if (j.empty()) return;
    lastCodeEdit = get_num(j, "lastCodeEdit");
    lastTestVerified = get_num(j, "lastTestVerified");
    lastTestVerifiedFail = get_num(j, "lastTestVerifiedFail");
    lastDiagAt   = get_num(j, "lastDiagAt");
    lastDiagSig  = get_str(j, "lastDiagSig");
    lastNetTs    = get_num(j, "lastNetTs");
    lastNetVerdict = get_str(j, "lastNetVerdict");
  }

  static void read_sess(const string& obj, Sess& s) {
    s.goalPrompt = get_str(obj, "goalPrompt");
    s.goalTs = get_num(obj, "goalTs");
    s.touchedDirs = parse_str_array(obj, "touchedDirs");
    s.fanoutWarned = get_bool(obj, "fanoutWarned");
    s.lastCmd = get_str(obj, "lastCmd");
    s.lastCmdTs = get_num(obj, "lastCmdTs");
    s.cmdRepeat = (int)get_num(obj, "cmdRepeat"); if (s.cmdRepeat < 1) s.cmdRepeat = 1;
    s.actionCount = (int)get_num(obj, "actionCount");
    s.offTarget = (int)get_num(obj, "offTarget");
    s.walkCapWarned = (int)get_num(obj, "walkCapWarned");
    s.driftChallenged = (int)get_num(obj, "driftChallenged");
    for (const auto& r : parse_obj_array(obj, "recent"))
      s.recent.push_back({ get_num(r, "t"), get_str(r, "s") });
    s.recentEv = parse_str_array(obj, "recentEv");
    s.tsOffset = get_num(obj, "tsOffset");
    s.tokensOut = get_num(obj, "tokensOut");
    s.tokensIn = get_num(obj, "tokensIn");
    s.lastTestPass = get_num(obj, "lastTestPass");
    s.lastTestFail = get_num(obj, "lastTestFail");
    s.lastTestRun  = get_num(obj, "lastTestRun");
  }

  static string write_sess(const Sess& s) {
    std::ostringstream o;
    o << "{\"goalPrompt\":\"" << json_escape(s.goalPrompt) << "\",\"goalTs\":" << s.goalTs
      << ",\"touchedDirs\":[";
    for (size_t i = 0; i < s.touchedDirs.size(); i++)
      o << (i ? "," : "") << "\"" << json_escape(s.touchedDirs[i]) << "\"";
    o << "],\"fanoutWarned\":" << (s.fanoutWarned ? "true" : "false")
      << ",\"lastCmd\":\"" << json_escape(s.lastCmd) << "\",\"lastCmdTs\":" << s.lastCmdTs
      << ",\"cmdRepeat\":" << s.cmdRepeat << ",\"actionCount\":" << s.actionCount
      << ",\"offTarget\":" << s.offTarget << ",\"driftChallenged\":" << s.driftChallenged
      << ",\"walkCapWarned\":" << s.walkCapWarned
      << ",\"lastTestPass\":" << s.lastTestPass << ",\"lastTestFail\":" << s.lastTestFail
      << ",\"lastTestRun\":" << s.lastTestRun
      << ",\"recent\":[";
    for (size_t i = 0; i < s.recent.size(); i++)
      o << (i ? "," : "") << "{\"t\":" << s.recent[i].first << ",\"s\":\"" << json_escape(s.recent[i].second) << "\"}";
    o << "],\"recentEv\":[";
    for (size_t i = 0; i < s.recentEv.size(); i++)
      o << (i ? "," : "") << "\"" << json_escape(s.recentEv[i]) << "\"";
    o << "],\"tsOffset\":" << s.tsOffset << ",\"tokensOut\":" << s.tokensOut
      << ",\"tokensIn\":" << s.tokensIn << "}";
    return o.str();
  }

  // Sessions that are still recorded inside state.json from before the split.
  // Read for as long as they exist so nobody's counter resets at upgrade; never
  // written back, so the map drains rather than lingering.
  void migrate_from_shared(const string& j, const string& sid16) {
    size_t sp = j.find("\"sessions\"");
    if (sp == string::npos) return;
    const string smap = take_obj(j, j.find(':', sp + 10));
    for (size_t i = 1; i + 1 < smap.size();) {
      size_t q = smap.find('"', i);
      if (q == string::npos) break;
      string key;
      size_t q2 = q + 1;
      for (; q2 < smap.size(); q2++) { if (smap[q2] == '\\') { q2++; continue; } if (smap[q2] == '"') break; key += smap[q2]; }
      size_t colon = smap.find(':', q2);
      if (colon == string::npos) break;
      size_t objAt = smap.find('{', colon);
      const string obj = take_obj(smap, colon);
      if (obj.empty() || objAt == string::npos) break;
      if (key == sid16) { read_sess(obj, sess); return; }
      i = objAt + obj.size();
    }
  }

  // Anything untouched for a day goes. By TIME: "keep the newest N" is the rule
  // that evicted the main session of a seven-way fan-out, and putting it back
  // with a bigger N would only move the number the failure starts at. Swept at
  // most once every ten minutes, tracked by the mtime of a marker, so 400 events
  // in a row do not each walk the directory.
  void sweep() const {
    const string marker = sessDir + "/.swept";
    struct stat st;
    const long long now = now_ms();
    if (stat(marker.c_str(), &st) == 0 &&
        now - (long long)st.st_mtime * 1000 < SESSION_SWEEP_EVERY_MS) return;
    { std::ofstream f(marker, std::ios::trunc); if (f) f << now; }
    DIR* d = opendir(sessDir.c_str());
    if (!d) return;
    struct dirent* e;
    while ((e = readdir(d))) {
      const string n = e->d_name;
      if (n.size() < 6 || n.compare(n.size() - 5, 5, ".json") != 0) continue;
      const string p = sessDir + "/" + n;
      if (stat(p.c_str(), &st) != 0) continue;
      if (now - (long long)st.st_mtime * 1000 > SESSION_TTL_MS) unlink(p.c_str());
    }
    closedir(d);
  }

  void load() {
    const string j = read_file(path);
    load_shared(j);
    const string sj = read_file(sess_path());
    if (!sj.empty()) { read_sess(sj, sess); sessLoaded = true; }
    else migrate_from_shared(j, legacyKey);
    sweep();
  }

  void save() {
    mkdir(sessDir.c_str(), 0755);
    write_atomic(sess_path(), write_sess(sess));

    // The shared file still has many writers, so it is merged rather than
    // replaced: re-read it, keep the later of every stamp, and let each string
    // travel with the stamp that owns it. Everything left in here is monotonic,
    // which is what makes a merge correct without a lock — and a lock is what
    // this file must not need, because it is written on every single hook event
    // in every session at once.
    const string cur = read_file(path);
    long long fCodeEdit = get_num(cur, "lastCodeEdit");
    long long fVerified = get_num(cur, "lastTestVerified");
    long long fVerFail  = get_num(cur, "lastTestVerifiedFail");
    long long fDiagAt   = get_num(cur, "lastDiagAt");
    string    fDiagSig  = get_str(cur, "lastDiagSig");
    long long fNetTs    = get_num(cur, "lastNetTs");
    string    fNetVerd  = get_str(cur, "lastNetVerdict");

    if (lastDiagAt >= fDiagAt) { fDiagAt = lastDiagAt; fDiagSig = lastDiagSig; }
    if (lastNetTs  >= fNetTs)  { fNetTs  = lastNetTs;  fNetVerd = lastNetVerdict; }
    if (lastCodeEdit > fCodeEdit) fCodeEdit = lastCodeEdit;
    if (lastTestVerified > fVerified) fVerified = lastTestVerified;
    if (lastTestVerifiedFail > fVerFail) fVerFail = lastTestVerifiedFail;

    std::ostringstream o;
    o << "{\"lastCodeEdit\":" << fCodeEdit
      << ",\"lastTestVerified\":" << fVerified
      << ",\"lastTestVerifiedFail\":" << fVerFail
      << ",\"lastDiagAt\":" << fDiagAt
      << ",\"lastNetTs\":" << fNetTs
      << ",\"lastNetVerdict\":\"" << json_escape(fNetVerd) << "\""
      << ",\"lastDiagSig\":\"" << json_escape(fDiagSig) << "\"}";
    write_atomic(path, o.str());

    lastCodeEdit = fCodeEdit; lastTestVerified = fVerified;
    lastTestVerifiedFail = fVerFail; lastDiagAt = fDiagAt; lastDiagSig = fDiagSig;
    lastNetTs = fNetTs; lastNetVerdict = fNetVerd;
  }

  // ---- "are the tests red", asked once and answered the same way everywhere --
  //
  // A red this session watched go past is this session's business. A red
  // rabadon RAN is everyone's, until somebody produces a newer verified green.
  // What is gone is the third case: another session's watched red reaching this
  // one. lastTestFail sat at 02:18 and lastTestPass at 00:48 while a session
  // born at 04:00 was told its own green suite was red, twice, both recorded
  // with `rabadon wrong stale-net-verdict`.
  long long red_since() const {
    const long long mine = (sess.lastTestFail > sess.lastTestPass) ? sess.lastTestFail : 0;
    const long long shared = (lastTestVerifiedFail > lastTestVerified &&
                              lastTestVerifiedFail > sess.lastTestPass)
                             ? lastTestVerifiedFail : 0;
    return mine > shared ? mine : shared;
  }
  bool tests_red() const { return red_since() > 0; }
  long long green_at() const {
    return sess.lastTestPass > lastTestVerified ? sess.lastTestPass : lastTestVerified;
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
    // bash, not sh, and the reason is a whole class of repositories. A project
    // that activates a toolchain before testing sources a script written for
    // bash: hermit, nvm and asdf all define functions with a hyphen in the name,
    // which POSIX sh rejects outright. Measured on aaif-goose/goose, whose test
    // command opens `source bin/activate-hermit`: under sh the script died on
    // line 68 with `deactivate-hermit': not a valid identifier, cargo never ran,
    // and the gate blocked a green tree while reporting that the tests failed.
    // execlp only returns when the exec failed, so sh stays as the fallback for
    // images that ship no bash.
    execlp("bash", "bash", "-c", cmd.c_str(), (char*)nullptr);
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

using rbtestout::ran_no_tests;

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
    << "  \"newRule\": { \"id\": \"kebab-id\", \"deny\": \"<JS regex over bash commands>\", \"why\": \"<one line>\", \"catches\": [\"<the exact command that would have been refused>\"], \"allow\": [\"<a real command this must NOT refuse>\"] } | { \"id\": \"kebab-id\", \"match\": \"<JS regex over file paths>\", \"why\": \"<one line>\", \"catches\": [\"<the exact path that would have been protected>\"], \"allow\": [\"<a real path this must NOT protect>\"] } | null }\n"
    << "newRule: ONLY if this class of mistake could have been caught BEFORE it happened by blocking a command or an edit; otherwise null. Prefer null over a rule that could block legitimate work.\n"
    << "catches is REQUIRED and it is checked. Write the literal command or path this rule would have refused, and rabadon runs it through your own pattern with the same matcher the gate uses before installing anything. A rule whose pattern cannot refuse its own example is not installed, because a rule that reads correctly and refuses nothing is worse than no rule: it is a law everyone believes in.\n"
    << "A deny pattern never sees the raw line. rabadon splits on ; && || | first and matches ONE segment at a time, with quotes and the whitespace inside them removed. So `a && b` arrives as two separate surfaces and a pattern spanning both can never match. A match pattern is offered the path as it arrived, which is ABSOLUTE, and the path relative to the project root.\n\n"
    << "## session goal\n" << goal << "\n"
    << "## last moves\n";
  for (const auto& r : recentBullets) p << "- " << r << "\n";
  p << "## the test command\n" << cmd << "\n"
    << "## failing output (tail)\n" << failOutputTail << "\n";
  const string raw = run_claude(p.str(), 90, env_or("RABADON_DIAGNOSE_MODEL", ""), 4 * 1024 * 1024);
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
// bounded `claude -p --model $RABADON_JUDGE_MODEL`, 30s / 1MB. Fail-open.
// Default is claude-haiku-4-5, the name that used to be compiled in here.
struct Verdict { bool ok = false; bool onTrack = true; string anchor; };
static Verdict driftJudge(const string& goal, const std::vector<string>& recentBullets) {
  std::ostringstream p;
  p << "You are rabadon, supervising a coding session. Verdict only, JSON only, no fences:\n"
    << "{ \"onTrack\": true|false, \"anchor\": \"<if off track: ONE sentence steering the work back to the goal; else empty>\" }\n"
    << "Judge conservatively: refactors, tests, and setup that SERVE the goal are on-track. Only flag work that belongs to a different task.\n"
    << "## the session goal\n" << goal << "\n"
    << "## the last moves\n";
  for (const auto& r : recentBullets) p << "- " << r << "\n";
  const string raw = run_claude(p.str(), 30, env_or("RABADON_JUDGE_MODEL", "claude-haiku-4-5"), 1024 * 1024);
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
                                        "--on", "--off", "--toggle", "--status", "--silent", "--wrong"};
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
    // ...and every rule object must actually BE a rule. The top-level walk
    // above stops at depth 1, so it catches "protectedPathz" and is blind one
    // level down — inside the rule object, where the author is typing. A rule
    // written {"id":..., "denies":..., "why":...} is valid JSON, carries an id
    // and a why, and reads as enforced; parse_rules drops it for having no
    // pattern and the gate allows the command. Measured before this check:
    // gate exit 0 on `npx wrangler deploy`, lint "is valid", exit 0. Same for a
    // rule with no pattern key at all. That is this command's own stated
    // failure mode ("the gate would OBSERVE where the author meant it to
    // BLOCK") surviving one nesting level deeper than the check that ended it.
    //
    // Legal beside the pattern: `why`/`id` (the schema, docs/guard.md),
    // `authoredBy`+`incidentAt` (rules born from an incident, below) and
    // `source` (`rabadon pack import`). Those are keys rabadon writes itself —
    // reject them and rabadon's output fails rabadon's own linter. The other
    // section's pattern key is deliberately NOT legal: a `match` inside bash[]
    // is inert, and reading as enforced while matching nothing is the bug.
    auto lint_rule_objects = [&](const char* section, const char* patKey) {
      // `wrongAt`/`wrongWhy` are the other half of `authoredBy`/`incidentAt`.
      // A rule born from an incident already carries the day it was born; a rule
      // that has refused something it should not have has to carry that too, on
      // the rule, where the next author reads it — the ledger records the event
      // and nobody opening guard.json sees the ledger.
      static const char* kRuleKeys[] = {"id", "why", "authoredBy", "incidentAt", "source",
                                        "allow", "catches", "wrongAt", "wrongWhy"};
      int idx = -1;
      for (const string& obj : rbrules::parse_rule_objects(g, section)) {
        idx++;
        const string id = rbrules::get_str(obj, "id");
        // an id-less broken rule still has to be findable in the file
        const string named = id.empty() ? string(section) + "[" + std::to_string(idx) + "]" : id;
        bool hasPattern = false;
        for (const string& key : rbrules::rule_object_keys(obj)) {
          if (key == patKey) { hasPattern = true; continue; }
          bool ok = false;
          for (const char* k : kRuleKeys) if (key == k) ok = true;
          if (!ok) {
            fprintf(stderr, "rabadon lint: rule \"%s\" in %s has unknown key \"%s\" (typo for \"%s\"? the gate ignores it)\n",
                    named.c_str(), section, key.c_str(), patKey);
            problems++;
          }
        }
        // present-but-empty counts as absent: parse_rules drops an empty
        // pattern too, so the key being there is not the rule existing.
        if (hasPattern && rbrules::get_str(obj, patKey).empty()) hasPattern = false;
        if (!hasPattern) {
          fprintf(stderr, "rabadon lint: rule \"%s\" in %s has no \"%s\" pattern — it matches nothing, the gate skips it\n",
                  named.c_str(), section, patKey);
          problems++;
        }
      }
    };
    // Everything above asks whether a rule CAN fire. Nothing asked whether it
    // can ever hold its fire, and that is the half that broke in the field: an
    // authored `semantic-commit-required` denied every commit including the
    // `fix:` ones it existed to permit, because an optional quote let its
    // negative lookahead pass on the quote character instead of the message.
    // lint called that guard valid, because the rule compiled and it fired.
    //
    // A rule that refuses everything is as broken as one that matches nothing,
    // and it is worse to live with: the first blocks real work every day, the
    // second only fails when the danger finally arrives. So a rule carries
    // `allow`, the commands it must NOT match, and they are run against its own
    // pattern through the same matcher the gate uses. A rule with no twin is
    // reported but not failed yet — no guard in the wild has them until the
    // author writes them.
    auto lint_allow_twins = [&](const char* section, const char* patKey) {
      int missing = 0, total = 0;
      const bool isCommand = string(section) == "bash";
      for (const string& obj : rbrules::parse_rule_objects(g, section)) {
        total++;
        const string id = rbrules::get_str(obj, "id");
        const string pat = rbrules::get_str(obj, patKey);
        if (pat.empty()) continue;  // already reported above
        const std::vector<string> allow = rbrules::get_str_array(obj, "allow");
        if (allow.empty()) { missing++; continue; }
        for (const string& example : allow) {
          const bool refused = isCommand ? rbrules::rx_test_cmd(pat, example)
                                         : rbrules::rx_test(pat, example);
          if (refused) {
            fprintf(stderr, "rabadon lint: rule \"%s\" refuses its own allow example — %s\n",
                    id.c_str(), example.c_str());
            problems++;
          }
        }
      }
      if (missing) {
        fprintf(stderr, "rabadon lint: %d of %d rule(s) in %s carry no \"allow\" example — nothing proves they let real work through\n",
                missing, total, section);
      }
    };
    // And the half neither of those covers. `allow` proves a rule is not too
    // WIDE. Nothing proved it was not too NARROW, because the schema had no way
    // for an author to say what the rule exists to stop.
    //
    // Measured on 3 August: every guard rule on this machine, 430 of them, was
    // driven through the real gate with a command its own pattern was written to
    // refuse. 16 refused nothing, in any repository, ever, and all 16 linted
    // clean. Three had been authored by the engine itself after real incidents,
    // so each named something that had already happened once and was free to
    // happen again. The two mechanisms behind fourteen and two of them are
    // invisible in the pattern: a protectedPaths rule authored relative is
    // compared against a spelling no event carries, and a bash pattern that
    // spells a pipe is asking for a character the parser removed before any rule
    // was consulted. An author cannot be expected to know either.
    //
    // What an author CAN write is the thing the rule is for. So a rule carries
    // `catches` beside `allow`, and lint runs it through the rule's own pattern
    // with the gate's own matcher — rx_test_cmd for a command, which segments
    // the line exactly as judging does, and rx_test for a path, which is offered
    // both the arriving spelling and the project-relative one. A rule that
    // cannot cut its own example is dead, and it is said at author time rather
    // than on the night the danger arrives.
    auto lint_deny_twins = [&](const char* section, const char* patKey) {
      int missing = 0, total = 0;
      const bool isCommand = string(section) == "bash";
      for (const string& obj : rbrules::parse_rule_objects(g, section)) {
        total++;
        const string id = rbrules::get_str(obj, "id");
        const string pat = rbrules::get_str(obj, patKey);
        if (pat.empty()) continue;  // already reported above
        const std::vector<string> catches = rbrules::get_str_array(obj, "catches");
        if (catches.empty()) { missing++; continue; }
        for (const string& example : catches) {
          const bool refused = isCommand ? rbrules::rx_test_cmd(pat, example)
                                         : rbrules::rx_test(pat, example);
          if (!refused) {
            fprintf(stderr, "rabadon lint: rule \"%s\" cannot refuse the thing it was written for — %s\n",
                    id.c_str(), example.c_str());
            fprintf(stderr, "              the rule is dead: it compiles, it reads correctly, and no %s reaches it\n",
                    isCommand ? "command" : "path");
            problems++;
          }
        }
      }
      if (missing) {
        fprintf(stderr, "rabadon lint: %d of %d rule(s) in %s carry no \"catches\" example — nothing proves they can still refuse anything\n",
                missing, total, section);
      }
    };
    lint_rules("bash", "deny");
    lint_rules("protectedPaths", "match");
    lint_rule_objects("bash", "deny");
    lint_rule_objects("protectedPaths", "match");
    lint_allow_twins("bash", "deny");
    lint_allow_twins("protectedPaths", "match");
    lint_deny_twins("bash", "deny");
    lint_deny_twins("protectedPaths", "match");
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
    // ONE colour for the whole lamp. The star used to run two steps ahead of
    // the word, as a pilot light, and that idea reads fine in a comment and
    // wrong on a screen: at every sampled moment the mark and the name are two
    // different colours, so it looks mismatched rather than alive. The breath
    // is the part that carries "this can act on you right now" and it survives.
    // The mark just breathes with the word it belongs to.
    snprintf(lamp, sizeof lamp, "\033[38;5;%dm* rabadon\033[0m", RAMP[ph]);
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
  if (argc > 1 && string(argv[1]) == "--wrong") {
    // A REFUSAL THAT WAS WRONG. The standing rule when the gate refuses
    // something it should not have is: do not add the rule to disabled[], do
    // not route around it, write it down and fix the rule. There was nowhere to
    // write it down. Three happened on 3 August and all three ended up as prose
    // in a report, which means the one number this product is actually judged
    // on lived outside the ledger.
    //
    // Anybody can publish how many commands they refused. That number means
    // nothing on its own; it means something beside the count of refusals that
    // were wrong, and only a ledger that carries both can be asked for the
    // second one. So it goes on the same chain as the first.
    if (argc < 4 || !argv[2][0] || !argv[3][0]) {
      fprintf(stderr,
        "usage: rabadon wrong <rule-id> \"why it was wrong\"\n"
        "\n"
        "Records a refusal that should not have happened, on the same hash-chained\n"
        "ledger as the refusal itself. A rule id with no reason is a complaint and\n"
        "not a record, so the reason is required.\n");
      return 2;
    }
    string why = argv[3];
    for (int i = 4; i < argc; i++) why += string(" ") + argv[i];
    ledger_line("WRONG_REFUSAL",
                "\"rule\":\"" + json_escape(string(argv[2])) + "\",\"why\":\"" +
                json_escape(why) + "\"");
    printf("rabadon: recorded a wrong refusal by %s.\n"
           "  It is on the ledger next to the refusals, which is the only place a\n"
           "  false-positive count can be read from instead of asserted.\n"
           "  Now fix the rule -- disabled[] is not the answer to a rule that is wrong.\n",
           argv[2]);
    return 0;
  }

  if (argc > 1) {
    string a1 = argv[1];
    if (a1 == "--on" || a1 == "--off" || a1 == "--toggle" || a1 == "--status" || a1 == "--silent") {
      const string rhome = rabadon_home();
      mkdir(rhome.c_str(), 0755);
      const string flag = rhome + "/enabled";
      const string mute = rhome + "/silent";
      bool on = file_exists(flag), silent = file_exists(mute);
      if (a1 == "--toggle") a1 = on ? "--off" : "--on";
      // WHAT THE MODE WAS, BEFORE IT IS CHANGED. On 3 August at 02:25 a session
      // ran `rabadon off` and the machine was unguarded from that moment on,
      // while four other sessions kept working underneath it with no way to
      // know. It was reconstructable afterwards only because the TEXT of the
      // command happened to land in a step record, which is an accident of a
      // different feature. Supervision going away is the most consequential
      // thing anybody does to this tool and it was the one action that was not
      // an event.
      const string was = silent ? "silent" : (on ? "enforce" : "watch");
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
      // --status asks and changes nothing, so it writes nothing. A mode line
      // that also appears when somebody merely LOOKS makes the count useless.
      {
        const string now = silent ? "silent" : (on ? "enforce" : "watch");
        if (a1 != "--status" && now != was)
          ledger_line("MODE", "\"from\":\"" + was + "\",\"to\":\"" + now + "\"");
        // The CLI just said what it did, so the comparison marker moves with it.
        // Without this the next hook run would read the change as out-of-band and
        // report the same transition twice, once honestly and once as an
        // accusation. --status changes nothing and therefore records nothing.
        if (a1 != "--status") {
          std::ofstream mf(rhome + "/mode.last", std::ios::trunc);
          if (mf) mf << now << "\n";
        }
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

  // ONE parse, for every agent. Which editor sent this is decided in hookev.h
  // and nowhere else; everything below reads E. The five separate readings of
  // Claude Code's field names that used to live in this function are the reason
  // a second agent was a day of work instead of one function.
  const rbhook::HookEvent E = rbhook::parse(raw);
  g_dialect = E.dialect;
  const string hook = E.hook;
  string cwd = E.cwd;
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
  // ENFORCE the arbiter acts: refuse, stop, repair.
  const char* offEnv = getenv("RABADON_OFF");
  const string rhome = rabadon_home();
  if ((offEnv && string(offEnv) == "1") || file_exists(cwd + "/.rabadon/off")
      || file_exists(rhome + "/silent")) return 0;
  // WATCH is a decision the user made by not turning the gate on. It is not a
  // place to land when the switch cannot be read at all, because the whole
  // promise is that nothing dangerous passes silently. An unreadable switch
  // enforces and says so; a switch that is simply absent still watches.
  const FlagState homeFlag = flag_state(rhome + "/enabled");
  const bool blind = !rabadon_home_known() || homeFlag == FLAG_UNKNOWN;
  g_mode = (homeFlag == FLAG_PRESENT || file_exists(cwd + "/.rabadon/on") || blind)
             ? MODE_ENFORCE : MODE_WATCH;
  if (blind && homeFlag != FLAG_PRESENT)
    fprintf(stderr, "rabadon: cannot read its own switch at %s — enforcing rather than allowing\n",
            rhome.c_str());
  // The mode this run resolved to, against the mode this machine last recorded.
  // A switch removed with rm instead of `rabadon off` lands here, and lands on
  // the ledger. See note_mode.
  note_mode(mode_tag());

  // PostToolUse is native now (S3): test analysis, incident diagnosis,
  // re-anchor — the LLM stays off the hot path (bounded `claude -p`).
  if (hook != "PreToolUse" && hook != "PostToolUse" && hook != "UserPromptSubmit" &&
      hook != "SessionStart" && hook != "Stop") return 0;

  const string toolName = E.toolName;
  const string command = E.command;
  string filePath = E.filePath;
  const string sid = E.sessionId;
  const string toolUseId = E.toolUseId;

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
  // Dialects that normalise the output in hookev.h hand it over directly; only
  // Claude Code's string-or-object shape needs the walk below.
  string toolResponse = E.toolResponse;
  if (toolResponse.empty()) {
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
  em.call = toolUseId;   // read at the top of main and, until now, used only to dedupe twin deliveries
  em.sess = sid;
  em.drill = sid.rfind("fleet-", 0) == 0 || sid.rfind("doctor-", 0) == 0 || sid.rfind("drill-", 0) == 0;
  { const char* de = getenv("RABADON_DRILL"); if (de && strcmp(de, "1") == 0) em.drill = true; }
  em.open_sock();

  // one state file, one owner. the old parallel state-native-*.txt store is
  // retired — removed on sight so no stale twin survives the migration.
  mkdir((cwd + "/.rabadon").c_str(), 0755);
  const string sidLegacy = sid.empty() ? "default" : sid.substr(0, 16);
  unlink((cwd + "/.rabadon/state-native-" + sidLegacy + ".txt").c_str());
  State stt;
  stt.path = cwd + "/.rabadon/state.json";
  stt.sessDir = cwd + "/.rabadon/sessions";
  stt.sessKey = session_key(sid);
  stt.legacyKey = sidLegacy;
  stt.load();
  Sess& ss = stt.session();

  // twin-delivery dedupe (same law as the node gate): tool events carry a
  // unique tool_use_id; non-tool events (Stop/SessionStart/prompt) dedupe on
  // a 2s time bucket, which only ever collides with a genuine twin.
  //
  // A TIME BUCKET IS NOT AN IDENTITY, AND FOR TOOL EVENTS IT WAS A SILENT
  // SKIP. The condition used to read `hook != "PreToolUse"`, which sent
  // PostToolUse — a tool event — down the bucket branch whenever the agent
  // sent no tool_use_id. Two genuinely different edits landing in the same
  // two seconds then produced ONE supervised event: the second returned 0
  // here, before the branch that starts the project's own check, so no check
  // ran and a red base could never clear itself. Measured, 3 runs each, two
  // edits 300ms apart: same bucket -> the suite ran 1 time and the verdict
  // stayed red; across a boundary -> it ran 2 times and went green. The
  // recovery half of Promise 2 was failing on exactly this.
  //
  // The bucket also never did its own job for tool events: a genuine twin
  // delivered 1ms apart across a boundary lands in two buckets and passes
  // through. So this is not a protection being traded away — it is a
  // heuristic that dropped real events and caught duplicates by luck.
  //
  // A tool event with no tool_use_id has NO identity available, so it is not
  // deduped: a doubled check costs one suite run (and net.cpp's single-flight
  // already collapses concurrent ones), while a dropped one costs the catch.
  {
    const bool toolEvent = (hook == "PreToolUse" || hook == "PostToolUse");
    string key;
    if (!toolUseId.empty()) key = hook + ":" + toolUseId;
    else if (!toolEvent) key = hook + ":" + std::to_string(now_ms() / 2000);
    if (!key.empty()) {
      for (const auto& id : ss.recentEv) if (id == key) return 0;
      ss.recentEv.push_back(key);
      if (ss.recentEv.size() > 12) ss.recentEv.erase(ss.recentEv.begin(), ss.recentEv.end() - 12);
    }
  }

  // one resolution, used by the reader, the re-reader and the writer below.
  // reading one file and authoring into another is how the engine ends up
  // writing rules that nothing ever loads.
  const string guardPath = guard_path_for(cwd);
  const string guardRaw = read_file(guardPath);
  const auto disabled = parse_disabled(guardRaw);

  // ---------- is a model allowed to answer at all? DEFAULT: NO ----------
  // This used to be opt-OUT. Installing rabadon signed you up for two `claude
  // -p` calls on your own account, from inside a hook, that nothing announced:
  // the drift judge every 12th action, and the incident brain the moment your
  // suite went red — 30 and 90 seconds of wall clock with the agent stopped
  // dead, waiting. The refusals themselves are cheap and always were: measured
  // over this machine's whole ledger, 2,789 refusal texts total 410,342
  // characters, a median of 68 each. The cost was never the gate. It was the
  // gate quietly hiring a second model.
  //
  // What survives the flip is the part that was never a model's opinion:
  // rabadon-drift measures against .rabadon/promise.json and writes the same
  // goal-drift verdict with no LLM at all (drift.cpp, installed on Stop by
  // hooks/install.mjs), and a red suite still terminates the turn with exit 2.
  // Nothing that refuses gets weaker; only the paid second opinion is now asked
  // for rather than assumed.
  //
  // Backwards compatible in the only direction anyone has used: RABADON_JUDGE=0
  // meant off and still means off. Two ways to say yes — the env for a shell,
  // and "judge": true in .rabadon/guard.json for a project that wants it every
  // session. guardRaw is already in memory three lines up, so asking costs
  // nothing.
  const char* judgeEnv = getenv("RABADON_JUDGE");
  const bool llmOn = judgeEnv ? (string(judgeEnv) == "1")
                              : (guardRaw.find("\"judge\"") != string::npos &&
                                 rx_test("\"judge\"\\s*:\\s*true", guardRaw));
  const bool judgeOff = !llmOn;

  // ---------- the net's verdict, read on EVERY event ----------
  //
  // This used to live inside the PostToolUse branch, and that placement was the
  // whole of the "it catches nothing" complaint. The check runs detached and
  // lands in net.json whenever it lands; if only PostToolUse reads it, a red
  // that arrived while the agent was thinking is not seen until AFTER the next
  // action has already run. The supervisor was always one action behind the
  // damage it existed to prevent.
  //
  // Reading here — before any branch — means the verdict is applied at the
  // first event that follows it, and the most valuable of those is PreToolUse:
  // the moment before the next action, which is the only moment at which
  // stopping it is still worth anything. The detached run is untouched; nothing
  // waits for a suite. What changed is when the ANSWER is allowed to matter.
  //
  // netEdgeRed is the green->red transition, hoisted out so PostToolUse can
  // still report the edge with its failing output. netRed is the standing
  // condition, which is what PreToolUse acts on.
  bool netEdgeRed = false, netRed = false;
  string netTail, netKind; int netLevel = 0;
  {
    const string netRaw = read_file(cwd + "/.rabadon/net.json");
    const long long netTs = get_num(netRaw, "ts");
    if (!netRaw.empty()) {
      const string verdict = get_str(netRaw, "verdict");
      netTail  = get_str(netRaw, "tail");
      netKind  = get_str(netRaw, "kind");
      netLevel = (int)get_num(netRaw, "level");
      if (netTs > stt.lastNetTs) {
        const string prev = stt.lastNetVerdict;
        stt.lastNetTs = netTs;
        stt.lastNetVerdict = verdict;
        // lastTestRun:0 is what "the net has never run anything" was measured
        // on. From here it is the truth: the net ran, at this instant.
        ss.lastTestRun = netTs;
        // the net FORKED the suite and read its real exit code (net.cpp), so a
        // net green is verification in the same sense the push gate's own run
        // is — and it counts, otherwise every push would re-run a suite rabadon
        // watched go green a minute ago. An empty run never arrives as "green";
        // net.cpp calls that inconclusive. Verified, therefore SHARED: this is
        // the one kind of test result another session is allowed to act on.
        if (verdict == "green") {
          ss.lastTestPass = netTs; ss.lastTestFail = 0; stt.lastTestVerified = netTs;
        } else if (verdict == "red") {
          ss.lastTestFail = netTs; stt.lastTestVerifiedFail = netTs;
        }
        stt.save();
        netEdgeRed = (verdict == "red" && prev != "red");
      }
      // INCONCLUSIVE IS NOT RED, and this is the line that decides whether the
      // product is usable. A suite that timed out, a runner that is not
      // installed, a run that executed no tests — net.cpp records all three as
      // inconclusive, and treating any of them as red would wedge a session on
      // evidence nobody has. A false stop is how a guardrail gets uninstalled.
      netRed = (verdict == "red");
    }
  }

  // ---------- PostToolUse: observe + track session state ----------
  // The action already ran; exit 2 here is FEEDBACK to the agent, not a block.
  // lastCodeEdit / lastTest* are TOP-LEVEL state (Pre reads them); the drift
  // trackers are per-session. The LLM (diagnose / re-anchor) is bounded and
  // off the hot path — a missing/slow claude fails open to the deterministic
  // verdict.
  if (hook == "PostToolUse") {
    const long long now = now_ms();

    // ---------- THE ALWAYS-ON NET ----------
    // The agent just touched code. Start the project's own check in a DETACHED
    // child and return immediately: a hook that waits for a test suite freezes
    // the editor for as long as the suite takes, which is how a supervisor
    // becomes the thing people uninstall. The verdict lands in .rabadon/net.json
    // and is read on the next hook event — one call of latency, zero stall.
    //
    // THIS RUNS BEFORE ANY REPORTING, and that ordering is a bug fix, not a
    // preference. It used to live below the green->red report, which returns
    // early — so the edit that FIXED the breakage never started a check, the
    // verdict stayed red, and the refusal it caused could only be cleared by
    // making a second, pointless edit. The supervisor had made its own red
    // un-clearable. Nothing that reports may sit in front of the thing that
    // re-measures.
    //
    // ENFORCE ONLY. In watch mode rabadon spends not one cycle of the user's
    // machine on their repo; watch observes what the agent did, nothing more.
    // Turning it on is the moment you accept the cost of being supervised.
    bool wantCheck = false, walkCapped = false;
    if (toolName == "Edit" || toolName == "Write" || toolName == "MultiEdit") {
      // isCode: guard.codePaths present ? ANY match : true.
      bool isCodeEdit = true;
      if (!guardRaw.empty() && guardRaw.find("\"codePaths\"") != string::npos) {
        isCodeEdit = false;
        for (const auto& pat : parse_str_array(guardRaw, "codePaths"))
          if (rx_test(pat, filePath)) { isCodeEdit = true; break; }
      }
      wantCheck = isCodeEdit;
    } else if (g_mode == MODE_ENFORCE) {
      // EVERY OTHER TOOL, asked of the filesystem rather than of the tool name.
      // A shell command that wrote a file is an edit; an agent with no edit tool
      // makes ALL of its edits this way. Bounded, and the bound is spoken about
      // below rather than hidden.
      int cap = 20000;
      { const char* c = getenv("RABADON_WALK_CAP"); if (c && *c) cap = atoi(c); }
      wantCheck = tree_changed_since(cwd, stt.lastNetTs, cap, &walkCapped);
    }

    if (wantCheck && g_mode == MODE_ENFORCE) {
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
    // A tree too large to scan is the one case where rabadon cannot tell
    // whether an edit happened. Failing quietly here would be the worst
    // outcome of all — the user keeps their belief in a check that stopped
    // running — so the miss is announced, once per session, and lands on the
    // ledger where it can be read back.
    if (walkCapped && !ss.walkCapWarned) {
      ss.walkCapWarned = 1;
      em.emit("CHECK_SKIPPED", "\"step\":\"net\",\"why\":\"tree too large to scan for changes\"");
      fprintf(stderr,
        "rabadon: this tree is too large for me to tell whether that command changed a file,\n"
        "so I did NOT run the check. Edits made with the edit tool are still checked.\n"
        "Raise the bound with RABADON_WALK_CAP=<entries> if you want the scan anyway.\n");
    }

    // ---------- the net's verdict from the PREVIOUS tool call ----------
    // What matters is not "the suite is red" — it is the TRANSITION. Step 3.254
    // is the moment something that was green stopped being green while the run
    // kept going. A standing red reported on every call is noise the agent
    // learns to ignore; the EDGE, reported once with the failing output, is a
    // correction it can act on.
    if (netEdgeRed) {
      string tail = netTail;
      if (tail.size() > 700) tail = tail.substr(tail.size() - 700);
      const char* strength = netLevel == 3 ? "your own test suite"
                           : netLevel == 2 ? "the build/typecheck"
                                           : "a syntax check (weak evidence)";
      em.emit("CHECK_FAIL", "\"step\":\"net\",\"mode\":\"" + string(mode_tag()) +
              "\",\"level\":" + std::to_string(netLevel) + ",\"kind\":\"" + json_escape(netKind) +
              "\",\"fails\":[{\"check\":\"net-turned-red\",\"why\":\"" +
              json_escape(utf8_clip(tail, 600)) + "\"}]");
      fprintf(stderr,
        "rabadon: this project just went GREEN -> RED, caught by %s.\n"
        "It happened on your last edit — this is not a pre-existing failure.\n"
        "%s\n"
        "Fix this before continuing: I will refuse anything that is not the fix.\n",
        strength, tail.c_str());
      // PostToolUse exit 2 is FEEDBACK to the agent, not a block — the
      // correction re-enters the run as an instruction. The BLOCK is at
      // PreToolUse on the next action, which is where a refusal still costs the
      // damage nothing.
      return refuse_code();
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
        const string judgeModel = env_or("RABADON_JUDGE_MODEL", "claude-haiku-4-5");
        const long long t0 = now_ms();
        Verdict v = driftJudge(ss.goalPrompt, bullets);
        // A supervisor that spends the operator's money has to say so in the
        // same ledger it judges them with. Wall-clock and the model name, no
        // USD: `claude -p --output-format text` prints no usage, so the tokens
        // are not known here and a number invented at this line would be the
        // exact failure this repository keeps writing about. Cost arrives from
        // the transcript, in `rabadon lens`, where it is measured.
        em.emit("LLM_CALL", "\"purpose\":\"drift\",\"model\":\"" + json_escape(judgeModel) +
                            "\",\"ms\":" + std::to_string(now_ms() - t0) +
                            ",\"ok\":" + (v.ok ? "true" : "false"));
        if (v.ok && !v.onTrack && !v.anchor.empty()) {
          em.emit("CHECK_FAIL", "\"step\":\"goal\",\"fails\":[{\"check\":\"goal-drift\",\"why\":\"" +
            json_escape(utf8_clip(v.anchor, 200)) + "\"}]");
          fprintf(stderr, "rabadon re-anchor: the session goal is \"%s\". %s\n",
            utf8_clip(ss.goalPrompt, 120).c_str(), v.anchor.c_str());
          return refuse_code();
        }
        // null / onTrack / no anchor / judge unavailable -> fall through
      }

      const string base = filePath.substr(filePath.rfind('/') + 1);
      em.emit("STEP_OK", "\"step\":\"edited: " + json_escape(base) + "\"");
      return 0;
    }

    if (toolName == "Bash") {
      // A tool_response that arrives as an OBJECT is kept as the raw JSON text,
      // so every newline in it is still the two characters backslash and n. The
      // verdict is then read off JSON source rather than off the run's output,
      // and a word boundary that exists in the output does not exist in the
      // source: in `...passed\n3 failed...` the `3` is preceded by the letter n,
      // so a pattern anchored at a boundary before the count never sees it.
      // Un-escaped once, here, so every reader below judges the text the suite
      // actually printed.
      const string out = toolResponse.size() > 1 && toolResponse[0] == '{'
                       ? json_unescape(toolResponse) : toolResponse;
      bool isTest;
      if (!guardRaw.empty() && guardRaw.find("\"testCommand\"") != string::npos)
        isTest = rx_test(get_str(guardRaw, "testCommand"), command);
      else
        isTest = rx_test("ctest|--test|npm test", command);

      if (!isTest) {
        em.emit("STEP_OK", "\"step\":\"ran: " + json_escape(utf8_clip(command, 80)) + "\"");
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

      // "the pattern did not match" and "the suite failed" are different
      // sentences, and reading the first as the second is a measured lie. On
      // 3 August at 14:24:28 this repo's own `make test` exited 0 with 2942 ok
      // lines and zero failing assertions, and lastTestFail was stamped at that
      // second — because the run was `make test > /tmp/log 2>&1` and the only
      // text reaching the hook was `EXIT=0`. That verdict is not cosmetic: it
      // is written into .rabadon/handoff.md, and the next session is told the
      // red IS the open front. A false red costs a session chasing nothing.
      //
      // So a red needs evidence of its own, not merely the absence of a green.
      // The vocabulary is deliberately wider than the word "fail", because a
      // suite that really died does not always own it — make prints `*** Error
      // 1`, a crash prints `Segmentation fault`, python prints a traceback.
      //
      // A ZERO count is not evidence that anything failed, and rabadon caught
      // this in its own output while the fix was being written: the line a
      // PASSING suite prints, "test verdict: 8 ok, 0 fail", carries the word.
      // Reading the word instead of the number put a green summary straight
      // back into a red verdict. Both orders occur, count-first and word-first,
      // so both are neutralised before the vocabulary is consulted.
      string evid = out;
      bool declaredZeroFailures = false;
      try {
        static const std::regex zeroCount(
            "\\b0+\\s*(fail(ed|ure|ures|s|ing)?|errors?)\\b|"
            "\\b(fail(ed|ure|ures|s|ing)?|errors?)\\s*[:= ]\\s*0+\\b",
            std::regex::ECMAScript | std::regex::icase);
        declaredZeroFailures = std::regex_search(out, zeroCount);
        evid = std::regex_replace(out, zeroCount, " ");
      } catch (...) { evid = out; }
      // The vocabulary is split in two, and the split is what a wrong refusal on
      // 3 August paid for. A CRASH STRING is a thing that happened: `*** Error`,
      // a segfault, a panic, a traceback, `not ok`. A bare failure WORD is a
      // thing that was said, and the thing saying it is not always the suite.
      const bool hardFailure = rx_test(
          "\\*\\*\\*|\\bnot ok\\b|\\bpanic:|\\btraceback\\b|"
          "\\bsegmentation fault\\b|\\baborted\\b|\\bkilled\\b", evid);
      const bool softFailure = rx_test(
          "\\bfail(ed|ure|ures|s|ing)?\\b|\\berrors?\\b|\\bassert(ion)?\\b|"
          "\\bexception\\b|\\btimed out\\b", evid);
      // A NON-ZERO count is the strongest evidence in the output and outranks
      // everything, including a stated exit code, because `make test | tail`
      // exits with tail's status and reports a failure it did not carry.
      //
      // Runners write counts in two orders and reading one as the other invents
      // failures. `2 failed, 5 passed` puts the number first; `pass 17  fail 0`
      // puts it last, and there the number in front of the word `fail` belongs
      // to `pass`. Reading that line number-first turns a suite that passed 17
      // and failed 0 into 17 failures. So the order is decided by the output
      // itself: if any counter in it is written word-first, every counter in it
      // is read word-first.
      const bool wordFirstCounts =
          rx_test("\\b(pass(ed|es)?|ok|tests?|total)\\s*[:= ]\\s*[0-9]+", out);
      const bool countedFailure =
          rx_test("\\b(fail(ed|ure|ures|s|ing)?|errors?)\\s*[:= ]\\s*[1-9][0-9]*\\b", out) ||
          (!wordFirstCounts &&
           rx_test("\\b[1-9][0-9]*\\s*(fail(ed|ure|ures|s|ing)?|errors?)\\b", out));
      // and a run that states its own exit status has said the one thing the
      // post hook never gets to see for itself. This repo already answers
      // UNKNOWN to a bare `EXIT=0`, because a redirected run proves nothing
      // either way. It reached RED for the same output the moment any failure
      // word was standing next to it — and on 3 August that word came from a
      // line a fixture prints ON PURPOSE, `FAIL testsuite [node --test]`, while
      // proving it can detect a red downstream suite. `make test` had exited 0,
      // the summary said `pass 17  fail 0`, and the session was told its own
      // green suite was red. Recorded as `rabadon wrong test-run`.
      const bool statedExitZero = rx_test("\\b[A-Z_]*EXIT[A-Z_]*\\s*=\\s*0\\b", out);
      // A SUITE THAT COUNTED ITS OWN FAILURES AND FOUND NONE outranks any loose
      // failure word later in the same output, for the same reason a stated exit
      // 0 does: one is a measurement the runner made, the other is a word that
      // appeared. This cost a wrong refusal today. `redbase_test.sh` finished
      // `26 ok, 0 fail` and was called RED, because one of the things it proves
      // is named "carries the real failing output" — the word `failing`, inside
      // the NAME of a passing assertion. The zero-count was already being
      // stripped from the evidence; it just was not allowed to answer.
      //
      // hardFailure still wins. A segfault next to `0 failed` means the runner
      // never got to the end, and the count is describing a run that died.
      const bool sawFailure =
          countedFailure || hardFailure ||
          (!statedExitZero && !declaredZeroFailures && softFailure);

      // A CRASH STRING CANCELS THE GREEN. `passed` is decided from the counts,
      // and the counts describe the tests the runner got through — not the
      // runner. `Segmentation fault` followed by `0 failed` satisfied the green
      // phrase list and was reported GREEN, which is the one direction this
      // repo treats as worse than being wrong loudly: a false green is a check
      // that has quietly stopped checking. A run that died before it finished
      // counting has not passed, whatever its last line says.
      if (passed && hardFailure) passed = false;

      // This session watched this run go past, so this session is who the
      // verdict is about. It is not written where another session can read it:
      // a red one agent saw in its own terminal used to arrive at an agent that
      // had never run anything, hours later, with its own suite green.
      ss.lastTestRun = now;
      if (passed) { ss.lastTestPass = now; ss.lastTestFail = 0; }
      else if (sawFailure) ss.lastTestFail = now;
      stt.save();

      if (passed) {
        em.emit("STEP_OK", "\"step\":\"tests: GREEN\"");
        return 0;
      }

      if (!sawFailure) {
        // Not green, not red. The same third answer net.cpp gives a timeout —
        // and it is said out loud rather than folded into either one, because
        // an unreadable result that silently means "red" is how the handoff
        // started lying.
        em.emit("TEST_EVIDENCE_MISSING",
                "\"step\":\"tests\",\"cmd\":\"" + json_escape(utf8_clip(command, 80)) +
                "\",\"bytes\":" + std::to_string(out.size()));
        fprintf(stderr,
          "rabadon: that test command left no readable result (%zu bytes), so the suite was "
          "neither passed nor failed here.\n"
          "The verdict is unchanged, not set to RED. If the output went to a file, rabadon "
          "cannot read it — let the suite print, or let `rabadon net` run it.\n",
          out.size());
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
        failSig = utf8_clip(failSig, 300);
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
        const long long diagT0 = now_ms();
        Diag diag = diagnose(goal, bullets, command, failTail);
        // Same contract as the drift judge above: the ledger records that money
        // was spent and how long the session waited for it, never a made-up USD.
        em.emit("LLM_CALL", "\"purpose\":\"diagnose\",\"model\":\"" +
                            json_escape(env_or("RABADON_DIAGNOSE_MODEL", "(account default)")) +
                            "\",\"ms\":" + std::to_string(now_ms() - diagT0) +
                            ",\"ok\":" + (diag.ok ? "true" : "false"));
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
            // COMPILING IS NOT FIRING, and this is the path where the difference
            // was paid for. Of the 16 rules on this machine that could not refuse
            // anything in any repository, three were authored right here, after
            // real incidents — so each named something that had already happened
            // once and was free to happen again, and the session that authored it
            // was told a new gate was installed.
            //
            // The proposal now has to name what it would have refused, and the
            // example is driven through the proposal's own pattern with the
            // matcher the gate uses. No example, or an example the pattern cannot
            // catch, and nothing is written. A rule that reads correctly and
            // refuses nothing is worse than no rule: it is a law everyone
            // believes in.
            bool provenLive = false;
            string deadExample;
            if (target && compiles) {
              const bool isCmd = string(target) == "bash";
              std::vector<string> examples;
              if (JVal* cv = diag.newRule.get("catches")) {
                if (cv->t == JVal::ARR) {
                  for (auto& e : cv->arr) {
                    if (e.t == JVal::STR) examples.push_back(json_unescape(e.str));
                  }
                } else if (cv->t == JVal::STR) {
                  examples.push_back(json_unescape(cv->str));
                }
              }
              if (examples.empty()) deadExample = "(none proposed)";
              for (const string& ex : examples) {
                if (isCmd ? rbrules::rx_test_cmd(patUnescaped, ex) : rbrules::rx_test(patUnescaped, ex))
                  provenLive = true;
                else if (deadExample.empty()) deadExample = ex;
              }
            }
            if (target && compiles && !provenLive) {
              em.emit("REPAIR_FAIL", "\"step\":\"new gate\",\"attempt\":1,\"repair_kind\":\"rule\",\"why\":\"proposed rule cannot refuse its own example\"");
              advice += "  a rule was proposed and NOT installed: its pattern cannot refuse " +
                        deadExample + "\n";
            }
            if (target && compiles && provenLive) {
              const string fresh = read_file(guardPath);
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
                  const string gpath = guardPath;
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
      // Say what is switched off, once per incident, by name. A capability that
      // disappears without a word reads as a product that got worse; the same
      // capability behind a named flag reads as a choice the operator now owns.
      // Only on the first red of an incident — sameIncident already dedupes the
      // diagnosis, and a footer on every red would become noise inside a minute.
      fprintf(stderr, "rabadon: tests are RED.%s\n",
        advice.empty() ? " Fix the failure before moving on." : advice.c_str());
      if (judgeOff && !sameIncident)
        fprintf(stderr, "  (no model was called: rabadon does not spend on your account unless asked. "
                        "RABADON_JUDGE=1, or \"judge\": true in .rabadon/guard.json, buys a diagnosis here.)\n");
      return refuse_code();
    }

    // any other tool: no event, no state mutation — but the twin-dedupe key we
    // appended above must persist so a twin delivery dedupes.
    stt.save();
    return 0;
  }

  // ---------- UserPromptSubmit: pin the session's goal ----------
  if (hook == "UserPromptSubmit") {
    const string prompt = E.prompt;
    // root fix for goal poisoning: the gate's own recursive prompts (the
    // diagnose/judge children run `claude -p` from inside a hook) must
    // never be mistaken for the builder's goal
    const bool recursive = prompt.rfind("You are rabadon", 0) == 0;
    if (!recursive && !prompt.empty() &&
        (ss.goalPrompt.empty() || now_ms() - ss.goalTs > 6LL * 3600 * 1000)) {
      ss.goalPrompt = utf8_clip(prompt, 400);
      ss.goalTs = now_ms();
      // a new goal resets the drift trackers — a new task may live elsewhere
      ss.touchedDirs.clear();
      ss.fanoutWarned = false;
      em.emit("RUN_START", "\"steps\":[\"goal: " + json_escape(utf8_clip(ss.goalPrompt, 100)) + "\"],\"bound\":{}");
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
    // ---------- the contract ----------
    // Discovery runs HERE and only here: rabadon-truth is deterministic and
    // costs ~100ms once per session, and the alternative — describing a check
    // rabadon has not actually located — is the kind of confident wrong answer
    // this whole binary exists to refuse. If the helper is missing or slow the
    // block still prints, with the NONE FOUND arm, which is the truth in that
    // case too.
    {
      string truthJson;
      const string tbin = self_dir() + "/rabadon-truth";
      if (file_exists(tbin)) {
        const string tcmd = "\"" + tbin + "\" \"" + cwd + "\" --json 2>/dev/null";
        if (FILE* p = popen(tcmd.c_str(), "r")) {
          char buf[8192]; size_t n;
          while ((n = fread(buf, 1, sizeof buf, p)) > 0) truthJson.append(buf, n);
          pclose(p);
        }
      }
      const string block = contract_block(cwd, truthJson, g_mode == MODE_ENFORCE,
                                          llmOn, g_dialect == rbhook::DIALECT_CURSOR,
                                          guardRaw);
      // stdout: on Claude Code and Cursor a SessionStart hook's stdout becomes
      // session context, so the agent reads its own terms too — it is a
      // contract with both parties, not a banner at the user.
      fwrite(block.data(), 1, block.size(), stdout);
      const string runCmd = get_str(truthJson, "run");
      em.emit("CONTRACT", "\"check\":\"" + json_escape(runCmd) +
              "\",\"level\":" + std::to_string((int)get_num(truthJson, "level")) +
              ",\"mode\":\"" + string(mode_tag()) +
              "\",\"repair\":" + (llmOn ? "true" : "false"));
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
    const string tp = E.transcriptPath;
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
          caught.push_back(utf8_clip(d, 90));
        }
        ls = le + 1;
      }
      if (caught.size() > 6) caught.erase(caught.begin(), caught.end() - 6);
    }
    const string tests = stt.tests_red()
      ? ("RED (since " + hhmmss(stt.red_since()) + ")")
      : stt.green_at() ? ("green (last pass " + hhmmss(stt.green_at()) + ")")
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
      // the override line has to be true. A sealed rule cannot be answered by
      // adding it to disabled[], and printing that as the way out taught the
      // session to try exactly the edit the seal exists to refuse.
      const string override_line = sealed_rule(ruleId)
        ? "(this rule is sealed: disabled[] does not switch it off. Only the operator, editing "
          ".rabadon/promise.json or .rabadon/guard.json by hand, can change what it protects.)"
        : "(user override: add \"" + ruleId + "\" to disabled[] in .rabadon/guard.json, or "
          "`rabadon off` to pause supervision)";
      const string msg = "rabadon BLOCKED this action.\nRule: " + ruleId + " — " + why + "\n" +
                         detail + "\nAdjust the approach instead of retrying the same action.\n" +
                         override_line + "\n";
      // The verdict is identical for every agent. Only the channel differs, and
      // that is the whole of what porting a guardrail costs. Cursor treats exit
      // 2 as a block by itself, but what it SHOWS the operator and hands back to
      // the model is the permission object on stdout — so a refusal that only
      // wrote stderr would stop the command and tell nobody why, which is most
      // of what a refusal is for.
      if (g_dialect == rbhook::DIALECT_CURSOR) {
        printf("{\"permission\":\"deny\",\"user_message\":\"%s\",\"agent_message\":\"%s\"}\n",
               json_escape("rabadon: " + ruleId + " — " + why).c_str(),
               json_escape(msg).c_str());
        fflush(stdout);
      }
      fprintf(stderr, "%s", msg.c_str());
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
        const string tp = E.transcriptPath;
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
    // A deny rule matches what the shell will RUN, not every byte the command
    // carries — a force-push quoted inside a commit message is a sentence, and
    // refusing it blocked real work 11 times in the watch-mode ledger
    // (rules.h -> cmdtext.h). When the line cannot be parsed the old whole-line
    // match decides instead; that is the safe direction, but it is not allowed
    // to be silent, so it lands in the ledger.
    //
    // And a deny rule that is about a PATH is decided by where the path lands,
    // not by how it is spelled: `rm -rf /tmp/build` is machine scratch to the
    // compiled law and "outside the project" to a hand-written regex, and that
    // one disagreement is 9 of the 20 refusals in the precision fixture
    // (rules.h -> pathres.h). Both layers read the same resolver, off the same
    // parse, from the same resolved cwd — parsing or resolving twice here is
    // how the two answers came apart in the first place.
    //
    // This site used to be a hand-written second copy of rbrules::judge_command,
    // kept apart from it only so the parse would still be in scope for the two
    // diagnostics below. rules.h says in as many words that a caller who
    // re-implements half of it is how exec became a bypass, and the caller doing
    // it was this one, in the binary that paragraph was written for. The two
    // answers happened to agree; nothing held them there. judge_command hands
    // the parse back now, so the gate asks the shared verdict exactly the way
    // sandbox does, and native/gate_bench.sh replays all 34 fixture cases
    // through this binary and through that call and refuses to print a
    // measurement unless every verdict still matches.
    rbtext::Parsed parsed;
    const rbrules::Verdict verdict = rbrules::judge_command(guardRaw, command, cwd, &parsed);
    if (parsed.degraded)
      em.emit("PARSE_DEGRADED", "\"why\":\"" + json_escape(parsed.why) +
              "\",\"fallback\":\"whole-line match\",\"cmd\":\"" +
              json_escape(utf8_clip(command, 160)) + "\"");
    // Where reading ONE command line stops. `echo '<text>' | sh` is decided
    // here because the text is in the line; `curl <url> | sh` is not, and no
    // amount of parsing will put it there. Allowing it is the right call — the
    // alternative refuses every install script on the internet — but an allow
    // that leaves no trace is indistinguishable from a gap nobody found yet, so
    // the boundary is named in the ledger every time it is reached. Rare on
    // purpose: only a shell that is definitely reading a program it was never
    // handed lands here, not every pipe.
    for (size_t li = 0; li < parsed.limits.size(); li++)
      em.emit("PARSE_LIMIT", "\"limit\":\"" + json_escape(parsed.limits[li]) +
              "\",\"cmd\":\"" + json_escape(utf8_clip(command, 160)) + "\"");
    if (verdict.refused) block(verdict.id, verdict.why, verdict.detail);
  }

  if (!guardRaw.empty()) {
    if (toolName == "Bash" && !command.empty()) {
      // push gate: rabadon RUNS the project's own suite here and opens the gate
      // on the REAL result — telling is a warning, solving is the product. This
      // was the last thing that delegated to node; it is native now.
      if (rx_test_cmd("\\bgit\\s+push\\b", command) && !rx_test("--dry-run", command) &&
          // lastTestVerified, not lastTestPass. The skip is only earned by a
          // green rabadon ran and read the exit code of itself; a green it
          // merely watched go past in a tool result is the claim of the thing
          // being checked, and taking it here is what let a push out over a red
          // suite after one command that ran no tests.
          guardRaw.find("\"pushGate\"") != string::npos && stt.lastCodeEdit > stt.lastTestVerified) {
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
        const bool vacuous = ran_no_tests(out);
        const bool green = (code == 0) && (passPat.empty() ? true : rx_test(passPat, out)) && !vacuous;
        if (green) {
          // rabadon ran this and read the exit code, so the result is evidence
          // rather than a claim, and evidence about the tree is shared: the next
          // push may skip the re-run even from a different session, but only
          // until somebody edits the tree, because lastCodeEdit is shared too
          // and any session's edit moves it past this stamp.
          ss.lastTestPass = now_ms(); ss.lastTestFail = 0; ss.lastTestRun = now_ms();
          stt.lastTestVerified = now_ms();
          em.emit("REPAIR_OK", "\"step\":\"push-gate\",\"attempt\":1,\"repair_kind\":\"testrun\"");
          // fall through: the push is now legitimately allowed
        } else if (vacuous) {
          em.emit("REPAIR_FAIL", "\"step\":\"push-gate\",\"attempt\":1,\"repair_kind\":\"testrun\",\"why\":\"ran no tests\"");
          block("push-gate", why, "rabadon ran the tests itself (" + runCmd + ") — it exited 0 and RAN NO TESTS.\n" +
            (out.size() > 400 ? out.substr(out.size() - 400) : out) +
            "An empty run is not a green run. Point pushGate.run at a command that executes the suite.");
        } else {
          em.emit("REPAIR_FAIL", "\"step\":\"push-gate\",\"attempt\":1,\"repair_kind\":\"testrun\",\"why\":\"tests not green\"");
          // rabadon ran it and read a non-zero exit. That is a red every session
          // in this tree may act on, unlike one a session merely watched.
          ss.lastTestFail = now_ms(); ss.lastTestRun = now_ms();
          stt.lastTestVerifiedFail = now_ms();
          stt.save();
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
      // A protectedPaths pattern is authored the way a person names a file in
      // their own repository, anchored and relative: `^.github/workflows/x.yml$`.
      // The event never carries that string. Measured across 865 transcripts,
      // 12,948 Edit/Write calls arrived with an ABSOLUTE file_path and 180 with
      // a `~/` one; project-relative arrived zero times. So an anchored relative
      // rule was matching against a spelling that has never once been sent, and
      // 14 of the 16 dead rules on this machine are that one mistake. The ones
      // that survived had been written `(^|/)` or `^(?:.*/)?` by hand, which is
      // a spelling convention doing the work a matcher should do.
      //
      // Both spellings are offered to the rule now: the path as it arrived, and
      // the path relative to the project the guard governs. Offering both rather
      // than replacing one keeps every rule that already fires firing.
      if (!filePath.empty()) {
        static const string kGuardTail = "/.rabadon/guard.json";
        const string groot =
            guardPath.size() > kGuardTail.size() &&
            guardPath.compare(guardPath.size() - kGuardTail.size(), kGuardTail.size(), kGuardTail) == 0
                ? guardPath.substr(0, guardPath.size() - kGuardTail.size())
                : string();
        // The guard path is resolved through symlinks and the event's file_path
        // is not, and on macOS /var is a symlink to /private/var and /tmp to
        // /private/tmp. So the prefix comparison failed on exactly the paths a
        // temp fixture uses, and the rule stayed dead while the fix looked like
        // it worked everywhere else. Both spellings are tried.
        string relPath;
        if (!groot.empty()) {
          if (filePath.rfind(groot + "/", 0) == 0) {
            relPath = filePath.substr(groot.size() + 1);
          } else {
            const string realFile = rbpath::resolve_real(rbpath::lexical_abs(filePath, cwd));
            if (realFile.rfind(groot + "/", 0) == 0)
              relPath = realFile.substr(groot.size() + 1);
          }
        }
        for (const auto& r : parse_rules(guardRaw, "protectedPaths", "match", disabled))
          if (rx_test(r.pattern, filePath) || (!relPath.empty() && rx_test(r.pattern, relPath)))
            block(r.id, r.why, "protected file: " + filePath);
      }
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

  // THREE RULES ARE SEALED: disabled[] does not switch them off. Measured in
  // this repository on 2 August 2026 — .rabadon/guard.json carried
  //
  //   "disabled": ["promise-anti-path", "promise-tamper"],
  //   "generatedBy": "rabadon rework session, override of stale promise rules
  //                   authorized by damla 2026-07-31"
  //
  // A supervised session had put the two rules protecting the goal contract on
  // the list of rules it does not have to obey, citing a permission the
  // operator gave about something else. promise.json is not tracked by git, so
  // no trail was left either, and rabadon-drift answered "on the star" for
  // eight days while measuring against a promise the drifter could rewrite.
  //
  // A door anything inside can close is not a door. These three describe the
  // integrity of the contract itself and answer only to the operator editing
  // the files by hand, which does not come through this hook.
  //
  // promise-off-target is deliberately NOT sealed. It is a challenge that
  // fires once per session and then lets the session past; sealing a nag buys
  // no integrity and costs real work, and drift stays on the ledger regardless.
  auto ruleOff = [&](const char* id) {
    if (sealed_rule(id)) return false;
    for (const auto& d : disabled) if (d == id) return true;
    return false;
  };

  // ---------- red base: the check is failing, so the run does not continue ----------
  //
  // The four complaints that produced this file were "it catches nothing, it
  // repairs nothing, on what grounds is unknown, when is unknown". This is the
  // first one. rabadon HAD the red — net.cpp ran the project's own check and
  // wrote the verdict — and did nothing with it except print a sentence, once,
  // on the transition, after the fact. The agent read the sentence and kept
  // going. A supervisor whose strongest move is a suggestion is not supervision.
  //
  // The rule: while the project's own check is red, the next action does not
  // start. Not "is warned about" — does not start. And not once, on the edge:
  // EVERY action, for as long as the red stands, because a red that stops
  // complaining after the first refusal is a red the agent can wait out.
  //
  // WHAT IS STILL ALLOWED, and why the carve-out is this shape. A stop with no
  // way out is a wedge, and a wedged session ends with rabadon uninstalled, so
  // the fix path stays wide open: reading anything, editing anything, and
  // re-running the check. That is the complete set of moves needed to go from
  // red to green, and it is also the exact set that CANNOT build on the broken
  // base — a read commits nothing, an edit is the repair, and the check is what
  // clears the refusal. Everything else — a commit, a push, an install, a
  // deploy, spawning a sub-agent, moving on to the next feature — is work
  // stacked on a base that is known to be broken, and every minute of it is
  // paid for twice.
  //
  // The escape hatch is not a flag: it is running the check and seeing it pass.
  // That matters for a flaky suite, which is the one input that could turn this
  // law into the thing that kills the product. A flaky red clears itself the
  // moment the check is re-run, and re-running the check is never refused.
  if (netRed && hook == "PreToolUse" && !ruleOff("red-base")) {
    // the check command this project is judged by — the same string the
    // contract printed at session start, so "run the check" is unambiguous.
    const string checkCmd = get_str(read_file(cwd + "/.rabadon/net.json"), "cmd");
    bool isFixPath = false;
    // reads and edits: the two halves of repairing something.
    if (toolName == "Read" || toolName == "Grep" || toolName == "Glob" ||
        toolName == "LS" || toolName == "NotebookRead" || toolName == "TodoWrite" ||
        toolName == "Edit" || toolName == "Write" || toolName == "MultiEdit" ||
        toolName == "NotebookEdit")
      isFixPath = true;
    // and re-running the check itself, which is the ONLY way out of this
    // refusal and therefore the one match that must not be pedantic. The first
    // version compared the whole string: the check discovered as
    // `npm test --silent` meant an agent that ran `npm test` — the same suite,
    // the obvious thing to type — was refused, and the escape hatch was shut
    // from the inside. That is the wedge this rule was written to avoid, built
    // into the rule itself.
    //
    // So the match is on the check's IDENTITY, not its spelling: the runner and
    // what it runs, flags dropped. `npm test --silent` becomes {npm, test}, and
    // `npm test`, `npm run test`, `cd sub && npm test` all carry both words.
    // `npm install left-pad` carries only one and is still refused, which is
    // the line that matters — installing a dependency is not fixing a failure.
    // Flags are skipped when picking the two words, or `python3 -m pytest -q`
    // would be identified by `-m`, which identifies nothing.
    if (!isFixPath && !checkCmd.empty() && !command.empty()) {
      std::vector<string> words;
      for (size_t i = 0; i < checkCmd.size() && words.size() < 2; ) {
        while (i < checkCmd.size() && isspace((unsigned char)checkCmd[i])) i++;
        size_t j = i;
        while (j < checkCmd.size() && !isspace((unsigned char)checkCmd[j])) j++;
        const string w = checkCmd.substr(i, j - i);
        i = j;
        if (w.empty() || w[0] == '-') continue;   // a flag names nothing
        words.push_back(w);
      }
      bool all = !words.empty();
      for (const auto& w : words) if (command.find(w) == string::npos) all = false;
      if (all) isFixPath = true;
    }

    if (!isFixPath) {
      string tail = netTail;
      if (tail.size() > 400) tail = tail.substr(tail.size() - 400);
      block("red-base",
            "this project's own check is failing, so anything that is not the fix builds on a broken base",
            "the check that is red: " + (checkCmd.empty() ? string("(the project check)") : checkCmd) +
            "\n" + tail +
            "\nread and edit freely, and re-run that check — a pass clears this immediately.");
    }
  }

  // ---------- guard-weaken: strengthen your own guard, never cut it ----------
  // Sealing the promise rules alone would move the hole one file over: the
  // session could still edit .rabadon/guard.json and put them back into
  // disabled[]. So the guard file carries an invariant that needs no list of
  // protected ids — a session may ADD to what supervises it and may never
  // remove a rule or name one in disabled[]. Adding is ordinary work (the
  // repair loop authors incident rules into this same file) and goes through
  // untouched. The two directions are told apart by comparing the ids and the
  // disabled[] set before and after, not by trusting a description of the edit.
  if (isEditTool && !filePath.empty() && rx_test("\\.rabadon/guard\\.json$", filePath)) {
    const string before = read_file(filePath);
    if (!before.empty()) {
      string after; bool known = false;
      if (toolName == "Write") {
        after = E.content;
        known = true;
      } else if (toolName == "Edit") {
        const string oldS = E.oldString;
        const string newS = E.newString;
        const size_t at = oldS.empty() ? string::npos : before.find(oldS);
        if (at != string::npos) { after = before; after.replace(at, oldS.size(), newS); known = true; }
      }
      // MultiEdit, NotebookEdit, or an Edit whose old_string is not in the file
      // leave the result unknowable from the tool call. The guard is the one
      // file where "I could not tell" has to mean no: an unverifiable rewrite
      // of the rules is exactly the edit this law is about.
      if (!known)
        block("guard-weaken",
              "an edit to the guard must be provably a strengthening, and this one cannot be checked",
              toolName + " on " + filePath + " — rewrite the whole file with Write so before and after can be compared");
      { JParser p(after); JVal v = p.parse();
        if (!p.ok || v.t != JVal::OBJ)
          block("guard-weaken", "a guard that does not parse enforces nothing, which is the strongest weakening there is",
                "the proposed " + filePath + " is not valid JSON"); }
      // every "id": "..." in the file, disabled ones included. parse_rules
      // filters by disabled[], which would hide the very rule being cut.
      auto ids = [](const string& s) {
        std::set<string> out;
        static const std::regex re("\"id\"\\s*:\\s*\"([^\"]*)\"", std::regex::ECMAScript);
        for (auto it = std::sregex_iterator(s.begin(), s.end(), re); it != std::sregex_iterator(); ++it)
          out.insert((*it)[1].str());
        return out;
      };
      const std::set<string> idsBefore = ids(before), idsAfter = ids(after);
      for (const auto& id : idsBefore)
        if (!idsAfter.count(id))
          block("guard-weaken", "the session may add rules to its own guard and may not remove one",
                "rule '" + id + "' disappears from " + filePath);
      const auto disBefore = parse_disabled(before), disAfter = parse_disabled(after);
      for (const auto& d : disAfter) {
        bool had = false;
        for (const auto& b : disBefore) if (b == d) { had = true; break; }
        if (!had)
          block("guard-weaken", "the session may not switch off a rule that watches it",
                "'" + d + "' is added to disabled[] in " + filePath);
      }
    }
  }

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
    if (stt.tests_red()) {
      bool isTest = false;
      if (guardRaw.find("\"testPaths\"") != string::npos) {
        for (const auto& pat : parse_str_array(guardRaw, "testPaths"))
          if (rx_test(pat, filePath)) { isTest = true; break; }
      } else isTest = rx_test("test", filePath);
      if (isTest) {
        const string oldS = E.oldString;
        string newS = E.newString;
        if (newS.empty()) newS = E.content;
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
        "looping on: " + utf8_clip(command, 120));
  }

  // the trail: a diagnosis needs to know WHERE the session is, not just that
  // it crashed — same law as the node gate's remember()
  string label = toolName == "Bash" ? ("bash: " + utf8_clip(command, 80)) : (toolName + ": " + filePath.substr(filePath.rfind('/') + 1));
  ss.recent.push_back({ now_ms(), utf8_clip(label, 120) });
  if (ss.recent.size() > 30) ss.recent.erase(ss.recent.begin(), ss.recent.end() - 30);
  ss.actionCount++;
  em.emit("STEP_START", "\"step\":\"" + json_escape(label) + "\"");
  stt.save();
  return 0;
}
