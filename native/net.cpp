// rabadon-net — the always-on net actually RUNS. C++17, zero deps, no LLM.
//
// The vision this exists for: a ten-step autonomous run, and the damage is not
// at a gate — it is at step 3.254, a place nobody thought to put a gate. The
// answer is not "put a gate everywhere". It is: after the agent touches code,
// run the truths the project ALREADY has, and notice the moment green becomes
// red. Steps 4 through 10 then never run on a broken base, and the bill for
// those steps is never paid.
//
// Measured on this machine before this file existed: .rabadon/state.json read
// lastTestRun:0 after a full working session. The net has never run anything.
// This is the file that changes that.
//
// Two design constraints, both of them hard:
//
//   NEVER STALL THE AGENT. A Claude Code hook is a short-lived process; running
//   a test suite inside it would freeze the editor for as long as the suite
//   takes. So the gate SPAWNS this binary detached and returns immediately; the
//   result lands in .rabadon/net.json and the NEXT hook event reads it. Latency
//   is one tool call, and the agent never waits.
//
//   NEVER CLAIM GREEN YOU DID NOT SEE. A run that exceeds its wall clock is
//   recorded as INCONCLUSIVE — not green. A missing checker (no node, no
//   pytest) is INCONCLUSIVE. Only exit 0, observed, is green. Fail-closed is
//   what makes the ledger worth reading.
//
// Usage: rabadon-net <dir> [--cap-ms N] [--print]
//   writes <dir>/.rabadon/net.json  {ts, level, kind, cmd, verdict, exit, dur_ms, tail}
//   verdict: "green" | "red" | "inconclusive"
//   exit 0 always (a supervisor that crashes the supervised run is worse than useless)

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <fstream>
#include <sstream>
#include <ctime>
#include <csignal>
#include <cerrno>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include "cli_help.h"

using std::string;

static long long now_ms() {
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return "";
  std::stringstream ss; ss << f.rdbuf(); return ss.str();
}

static string json_escape(const string& s) {
  string o;
  for (unsigned char c : s) {
    switch (c) {
      case '"': o += "\\\""; break;
      case '\\': o += "\\\\"; break;
      case '\n': o += "\\n"; break;
      case '\r': o += "\\r"; break;
      case '\t': o += "\\t"; break;
      default: if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); o += b; } else o += (char)c;
    }
  }
  return o;
}
static string str_field(const string& j, const char* key) {
  const string pat = string("\"") + key + "\":\"";
  size_t p = j.find(pat);
  if (p == string::npos) return "";
  p += pat.size();
  string o;
  for (size_t i = p; i < j.size(); i++) {
    if (j[i] == '\\' && i + 1 < j.size()) { char n = j[++i]; o += (n == 'n') ? '\n' : (n == 't') ? '\t' : n; continue; }
    if (j[i] == '"') break;
    o += j[i];
  }
  return o;
}
static long long num_field(const string& j, const char* key) {
  const string pat = string("\"") + key + "\":";
  size_t p = j.find(pat);
  if (p == string::npos) return 0;
  return atoll(j.c_str() + p + pat.size());
}

// Write via a temp file + rename, so a reader never sees a half-written result.
// The gate reads this on every tool call; a torn read would make the net report
// a verdict that was never reached.
static void write_atomic(const string& path, const string& body) {
  const string tmp = path + ".tmp";
  int fd = open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) return;
  const char* p = body.data(); size_t left = body.size();
  while (left) { ssize_t w = write(fd, p, left); if (w <= 0) break; p += w; left -= (size_t)w; }
  fsync(fd);
  close(fd);
  rename(tmp.c_str(), path.c_str());
}

static const char* kHelp =
  "rabadon-net — the always-on safety net for one project.\n"
  "Runs the strongest check this repo already has (rabadon-truth picks the rung)\n"
  "and writes the verdict to <dir>/.rabadon/net.json. Single-flight: one check per\n"
  "project at a time, so a burst of edits cannot start a suite per edit.\n"
  "\n"
  "usage: rabadon-net [dir] [--cap-ms N] [--print]\n"
  "\n"
  "  [dir]        the project to check (default: the current directory).\n"
  "  --cap-ms N   give up after N milliseconds (default 120000).\n"
  "  --print      print the verdict as well as writing it.\n"
  "  -h, --help   this screen.\n"
  "\n"
  "environment:\n"
  "  RABADON_NET_CAP_MS   overrides --cap-ms.\n"
  "\n"
  "example:\n"
  "  rabadon-net ~/src/myrepo --print\n";

int main(int argc, char** argv) {
  rb_help(argc, argv, kHelp);

  string dir = ".";
  long long capMs = 120000;      // two minutes: past that the answer is not worth the machine
  bool printOut = false;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--cap-ms" && i + 1 < argc) capMs = atoll(argv[++i]);
    else if (a == "--print") printOut = true;
    // `-h` was unknown, so it became the DIRECTORY: the net went looking for a
    // repo called "-h" and reported on it.
    else if (rb_is_flag(a.c_str())) rb_unknown_flag("rabadon-net", a.c_str());
    else dir = a;
  }
  while (dir.size() > 1 && dir.back() == '/') dir.pop_back();
  { const char* env = getenv("RABADON_NET_CAP_MS"); if (env && *env) capMs = atoll(env); }

  const string rdir = dir + "/.rabadon";
  mkdir(rdir.c_str(), 0755);
  const string outPath  = rdir + "/net.json";
  const string lockPath = rdir + "/net.lock";

  // ---- single flight ------------------------------------------------------
  // One check per project at a time. Without this, a burst of edits starts a
  // suite per edit and the machine is the thing that breaks — the exact story
  // that gets a tool uninstalled on day two.
  int lockFd = open(lockPath.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0644);
  if (lockFd < 0) {
    // a lock exists: is its owner alive, or did a previous run die holding it?
    const string held = read_file(lockPath);
    long long pid = atoll(held.c_str());
    long long startedAt = num_field(held, "at");
    bool stale = (pid > 0 && kill((pid_t)pid, 0) != 0 && errno == ESRCH);
    if (!stale && startedAt > 0 && now_ms() - startedAt > capMs * 3) stale = true;
    if (!stale) return 0;                       // a healthy run is already in flight
    unlink(lockPath.c_str());
    lockFd = open(lockPath.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0644);
    if (lockFd < 0) return 0;
  }
  {
    char b[128];
    int n = snprintf(b, sizeof b, "%d {\"at\":%lld}\n", (int)getpid(), now_ms());
    ssize_t ignored = write(lockFd, b, (size_t)n); (void)ignored;
    close(lockFd);
  }

  // ---- what does this repo know how to check? -----------------------------
  // rabadon-truth lives next to this binary and answers deterministically.
  string self = argv[0];
  size_t sl = self.rfind('/');
  const string bindir = (sl == string::npos) ? string(".") : self.substr(0, sl);
  string truthJson;
  {
    const string cmd = "\"" + bindir + "/rabadon-truth\" \"" + dir + "\" --json 2>/dev/null";
    FILE* p = popen(cmd.c_str(), "r");
    if (p) { char buf[4096]; size_t n; while ((n = fread(buf, 1, sizeof buf, p)) > 0) truthJson.append(buf, n); pclose(p); }
  }
  const int level  = (int)num_field(truthJson, "level");
  const string kind = str_field(truthJson, "kind");
  const string cmd  = str_field(truthJson, "run");

  auto finish = [&](const string& verdict, int rc, long long dur, const string& tail) {
    std::ostringstream o;
    o << "{\"ts\":" << now_ms()
      << ",\"level\":" << level
      << ",\"kind\":\"" << json_escape(kind) << "\""
      << ",\"cmd\":\"" << json_escape(cmd) << "\""
      << ",\"verdict\":\"" << verdict << "\""
      << ",\"exit\":" << rc
      << ",\"dur_ms\":" << dur
      << ",\"tail\":\"" << json_escape(tail) << "\"}\n";
    write_atomic(outPath, o.str());
    unlink(lockPath.c_str());
    if (printOut) fputs(o.str().c_str(), stdout);
  };

  if (level == 0 || cmd.empty()) {
    // Nothing runnable. Say it plainly and spend nothing. A repo with no truth
    // is a repo rabadon cannot vouch for, and pretending otherwise is the one
    // thing that would make every other number untrustworthy.
    finish("inconclusive", -1, 0, "no runnable check found in this project");
    return 0;
  }

  // ---- run it, bounded ----------------------------------------------------
  const string outFile = rdir + "/net.out";
  const string shell = "cd \"" + dir + "\" && (" + cmd + ") > \"" + outFile + "\" 2>&1";
  const long long t0 = now_ms();

  pid_t child = fork();
  if (child < 0) { finish("inconclusive", -1, 0, "could not fork a checker"); return 0; }
  if (child == 0) {
    setsid();                                   // its own group: we kill the whole tree
    execl("/bin/sh", "sh", "-c", shell.c_str(), (char*)nullptr);
    _exit(127);
  }

  int status = 0;
  bool timedOut = false;
  for (;;) {
    pid_t r = waitpid(child, &status, WNOHANG);
    if (r == child) break;
    if (r < 0) { if (errno == EINTR) continue; status = -1; break; }
    if (now_ms() - t0 > capMs) {
      kill(-child, SIGKILL);                    // the group, not just the shell
      waitpid(child, &status, 0);
      timedOut = true;
      break;
    }
    struct timespec ts { 0, 50 * 1000 * 1000 }; // 50ms
    nanosleep(&ts, nullptr);
  }

  const long long dur = now_ms() - t0;
  string tail = read_file(outFile);
  if (tail.size() > 1200) tail = tail.substr(tail.size() - 1200);
  unlink(outFile.c_str());

  if (timedOut) {
    // Not green. Not red. The honest third answer — and the reason a slow suite
    // degrades supervision instead of corrupting it.
    finish("inconclusive", -1, dur, "check exceeded its " + std::to_string(capMs) + "ms budget: " + tail);
    return 0;
  }
  const int rc = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
  if (rc == 127) { finish("inconclusive", rc, dur, "the checker is not installed here: " + tail); return 0; }
  finish(rc == 0 ? "green" : "red", rc, dur, tail);
  return 0;
}
