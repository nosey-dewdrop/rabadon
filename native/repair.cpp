// rabadon-repair — the session-level repair loop, REAL (C++17, zero deps).
//
// The claim this binary earns: "caught → proposed → RE-VERIFIED". HANDOFF §6.1
// defined the proof and forbade shortcuts:
//   a repair counts ONLY when the same deterministic check that caught the
//   problem runs again and turns green; unmeasured = unproven = never counted.
// Green is only HALF the proof. The other half is that the proposal did not buy
// that green by weakening the check — which is what the hash locks witness. So
// the word VERIFIED is earned by the tamper check RUNNING, not by the re-run
// going green: with zero discovered test files nothing was held, and this binary
// must then say HELD, UNVERIFIED. The headline and the ledger's "locks" field
// are the same statement; they are never allowed to disagree.
//
// Flow (propose-and-hold — rabadon NEVER silently edits the user's tree):
//   1. find the project's strongest deterministic check: --cmd flag, else the
//      net's last RED verdict (.rabadon/net.json), else rabadon-truth --json;
//   2. run it in the real repo. GREEN -> nothing to repair, exit 0;
//   3. copy the repo twice into an isolated tmp dir: `base` (pristine) and
//      `work`; hash-lock every test file (sha256.h);
//   4. proposer: `claude -p` bounded by a wall clock, cwd = the WORK COPY,
//      RABADON_OFF=1 — it may edit the copy, it cannot touch the user's tree;
//   5. ARBITER: re-run the SAME check in the work copy.
//        red                     -> REPAIR_FAIL, fail closed;
//        green but a test file's
//        hash changed            -> REPAIR_FAIL (test-tamper: a fix that
//                                   weakens the check is a fake fix);
//        green, tests untouched  -> REPAIR_OK: the diff base->work is written
//                                   to .rabadon/repair-<ts>.patch and HELD.
//   6. the human applies it: `patch -p1 < .rabadon/repair-<ts>.patch`.
//
// Every event lands on the hash-chained spool (same protocol as the gate:
// prev = sha256 of the previous line, flock + .head sidecar). `rabadon audit`
// is the referee that the two writers never drift.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include "sha256.h"
#include "chain.h"   // the ledger's one writer: chained line + .head sidecar

using std::string;

static long long now_ms() {
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

static string json_escape(const string& s) {
  string out;
  for (unsigned char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); out += b; }
        else out += (char)c;
    }
  }
  return out;
}

static string get_field(const string& s, const string& key) {
  string pat = "\"" + key + "\":\"";
  size_t k = s.find(pat);
  if (k == string::npos) return "";
  size_t i = k + pat.size();
  string out;
  while (i < s.size()) {
    char c = s[i];
    if (c == '\\' && i + 1 < s.size()) {
      char e = s[i + 1];
      if (e == 'n') out += '\n'; else if (e == 't') out += '\t'; else if (e == 'r') out += '\r';
      else out += e;
      i += 2; continue;
    }
    if (c == '"') return out;
    out += c; i++;
  }
  return "";
}

// ---------- chained spool emitter (the gate's twin — audit is the referee) ----------
struct Emitter {
  string spoolPath, pipe, runId;
  int seq = 0;
  void emit(const string& ev, const string& extraJson) {
    string body = "{\"v\":1,\"seq\":" + std::to_string(++seq) +
      ",\"ts\":" + std::to_string(now_ms()) +
      ",\"run\":\"" + runId + "\",\"pipe\":\"" + json_escape(pipe) + "\",\"ev\":\"" + ev + "\"" +
      (extraJson.empty() ? "" : "," + extraJson);
    rbchain::append(spoolPath, body);
  }
};

// ---------- bounded shell run: /bin/sh -c, wall-clock cap, output tail ----------
struct RunResult { int exit_code = -1; bool timed_out = false; string tail; };

static RunResult run_shell(const string& cmd, const string& cwd, int timeoutSec,
                           const std::vector<string>& extraEnv = {}) {
  RunResult r;
  int pfd[2];
  if (pipe(pfd) != 0) return r;
  pid_t pid = fork();
  if (pid < 0) { close(pfd[0]); close(pfd[1]); return r; }
  if (pid == 0) {
    setpgid(0, 0); // own process group: the timeout kill reaps grandchildren too
    if (!cwd.empty() && chdir(cwd.c_str()) != 0) _exit(126);
    dup2(pfd[1], 1); dup2(pfd[1], 2);
    close(pfd[0]); close(pfd[1]);
    for (const string& e : extraEnv) { putenv(strdup(e.c_str())); }
    execl("/bin/sh", "sh", "-c", cmd.c_str(), (char*)nullptr);
    _exit(127);
  }
  close(pfd[1]);
  fcntl(pfd[0], F_SETFL, O_NONBLOCK);
  const long long deadline = now_ms() + (long long)timeoutSec * 1000;
  string out;
  int status = 0;
  bool done = false;
  while (!done) {
    char buf[4096];
    ssize_t n;
    while ((n = read(pfd[0], buf, sizeof buf)) > 0) out.append(buf, (size_t)n);
    pid_t w = waitpid(pid, &status, WNOHANG);
    if (w == pid) done = true;
    else if (now_ms() > deadline) {
      kill(-pid, SIGKILL);
      waitpid(pid, &status, 0);
      r.timed_out = true;
      done = true;
    } else usleep(20000);
  }
  // drain what's left
  { char buf[4096]; ssize_t n; while ((n = read(pfd[0], buf, sizeof buf)) > 0) out.append(buf, (size_t)n); }
  close(pfd[0]);
  r.exit_code = r.timed_out ? 124 : (WIFEXITED(status) ? WEXITSTATUS(status) : 128);
  if (out.size() > 4000) out = out.substr(out.size() - 4000);
  r.tail = out;
  return r;
}

// A failure the operator cannot read is a failure they cannot act on. Every
// fail-closed path prints the last lines of the run that produced the verdict.
static void print_tail(const string& what, const string& tail) {
  if (tail.empty()) { fprintf(stderr, "  %s printed nothing.\n", what.c_str()); return; }
  const size_t keep = 1200;
  const string t = tail.size() > keep ? tail.substr(tail.size() - keep) : tail;
  fprintf(stderr, "  --- %s, last %zu bytes ---\n", what.c_str(), t.size());
  fprintf(stderr, "%s\n  --- end ---\n", t.c_str());
}

static string shell_quote(const string& s) {
  string out = "'";
  for (char c : s) { if (c == '\'') out += "'\\''"; else out += c; }
  return out + "'";
}

int main(int argc, char** argv) {
  string dir = ".";
  string cmd;
  int proposerTimeout = 240, checkTimeout = 600;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--cmd" && i + 1 < argc) cmd = argv[++i];
    else if (a == "--timeout" && i + 1 < argc) proposerTimeout = atoi(argv[++i]);
    else if (a == "--help") {
      printf("usage: rabadon-repair [dir] [--cmd \"<check command>\"] [--timeout <sec>]\n"
             "caught -> claude -p proposes in an ISOLATED COPY -> the same check re-runs -> green+untouched tests = a held patch.\n");
      return 0;
    }
    else if (a[0] != '-') dir = a;
  }
  {
    char rp[4096];
    if (realpath(dir.c_str(), rp)) dir = rp;
  }
  size_t sl = dir.rfind('/');
  const string project = sl == string::npos ? dir : dir.substr(sl + 1);

  // self-locate siblings (argv[0] like the gate)
  string selfDir = ".";
  {
    string a0 = argv[0];
    size_t k = a0.rfind('/');
    if (k != string::npos) selfDir = a0.substr(0, k);
  }

  // rabadon home for the spool
  string rdir;
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) rdir = rd;
  else {
    const char* h = getenv("HOME");
    string home = (h && h[0]) ? h : ".";
    rdir = home + "/.rabadon";
  }
  mkdir(rdir.c_str(), 0755);
  mkdir((rdir + "/spool").c_str(), 0755);
  char day[16]; { time_t t = time(nullptr); struct tm tmv; gmtime_r(&t, &tmv); strftime(day, 16, "%Y-%m-%d", &tmv); }
  Emitter em;
  em.spoolPath = rdir + "/spool/" + string(day) + ".jsonl";
  em.pipe = project + ":session";
  em.runId = "rp-" + std::to_string(now_ms() % 100000000) + "-" + std::to_string(getpid());

  // ---- 1. the check ----
  std::vector<string> testFiles;
  {
    RunResult t = run_shell(shell_quote(selfDir + "/rabadon-truth") + " " + shell_quote(dir) + " --json", "", 60);
    if (t.exit_code == 0) {
      // testFiles array: crude but sufficient extraction from truth's compact JSON
      size_t k = t.tail.find("\"testFiles\":[");
      if (k != string::npos) {
        size_t i = k + 13;
        while (i < t.tail.size() && t.tail[i] != ']') {
          if (t.tail[i] == '"') {
            size_t e = t.tail.find('"', i + 1);
            if (e == string::npos) break;
            testFiles.push_back(t.tail.substr(i + 1, e - i - 1));
            i = e + 1;
          } else i++;
        }
      }
      if (cmd.empty()) {
        string kind = get_field(t.tail, "kind");
        if (kind != "none") cmd = get_field(t.tail, "run");
      }
    }
  }
  if (cmd.empty()) {
    // the net's last verdict knows the front
    string net = read_file(dir + "/.rabadon/net.json");
    if (!net.empty()) cmd = get_field(net, "cmd");
  }
  if (cmd.empty()) {
    fprintf(stderr, "rabadon repair: no runnable check found (no test suite, no net verdict) — pass one: rabadon repair --cmd \"npm test\"\n");
    return 3;
  }

  printf("rabadon repair — %s\n  check: %s\n", project.c_str(), cmd.c_str());

  // proposer availability FIRST — an attempt that cannot start is not an
  // attempt, and it must never reach the ledger
  const char* cbEnv = getenv("RABADON_CLAUDE_BIN");
  const string claudeBin = (cbEnv && cbEnv[0]) ? cbEnv : "claude";
  {
    RunResult which = run_shell("command -v " + shell_quote(claudeBin), "", 10);
    if (which.exit_code != 0) {
      fprintf(stderr, "rabadon repair: proposer unavailable (%s not found) — install Claude Code or set RABADON_CLAUDE_BIN\n", claudeBin.c_str());
      return 3;
    }
  }

  // ---- 2. run it for real ----
  RunResult before = run_shell(cmd, dir, checkTimeout);
  if (before.exit_code == 0) {
    printf("  the check is GREEN — nothing to repair.\n");
    return 0;
  }
  printf("  RED (exit %d)%s — caught. proposing a fix in an isolated copy…\n",
         before.exit_code, before.timed_out ? " [timed out]" : "");

  em.emit("REPAIR_START", "\"step\":\"session-repair\",\"cmd\":\"" + json_escape(cmd) + "\"");

  // ---- 3. isolated copies + test-file hash locks ----
  char tmpl[] = "/tmp/rabadon-repair.XXXXXX";
  char* tp = mkdtemp(tmpl);
  if (!tp) { fprintf(stderr, "rabadon repair: mkdtemp failed\n"); return 1; }
  const string tmp = tp;
  const string base = tmp + "/base", work = tmp + "/work";
  {
    RunResult c1 = run_shell("mkdir -p " + shell_quote(base) + " " + shell_quote(work) +
                             " && cp -R " + shell_quote(dir) + "/. " + shell_quote(base) +
                             " && cp -R " + shell_quote(dir) + "/. " + shell_quote(work) +
                             " && rm -rf " + shell_quote(base + "/.rabadon") + " " + shell_quote(work + "/.rabadon"), "", 120);
    if (c1.exit_code != 0) { fprintf(stderr, "rabadon repair: could not copy the repo\n"); return 1; }
  }
  std::vector<std::pair<string, string>> locks; // testFile -> sha256
  for (const string& f : testFiles) locks.push_back({f, rbsha::hex(read_file(base + "/" + f))});

  // ---- 4. the proposer, bounded, in the WORK copy ----
  string prompt =
    "You are the repair slot inside rabadon, a reliability runtime for AI coding agents.\n"
    "A deterministic check in this repository is RED. Fix the CODE so the check passes.\n"
    "Laws:\n"
    "- NEVER edit, weaken, skip or delete a test file. A fix that touches a test is rejected automatically (the test files are hash-locked).\n"
    "- Only edit files inside the current working directory.\n"
    "- Do not run the check yourself; the arbiter re-runs it after you.\n"
    "check command: " + cmd + "\n"
    "failing output (tail):\n" + before.tail + "\n";
  string propCmd = shell_quote(claudeBin) + " -p --output-format text --permission-mode acceptEdits " + shell_quote(prompt);
  RunResult prop = run_shell(propCmd, work, proposerTimeout, {"RABADON_OFF=1"});
  if (prop.timed_out) {
    em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"why\":\"proposer timed out\"");
    fprintf(stderr, "rabadon repair: proposer timed out after %ds — REPAIR_FAIL (fail closed, your tree untouched)\n", proposerTimeout);
    return 2;
  }

  // ---- 5. the arbiter: same check, work copy ----
  RunResult after = run_shell(cmd, work, checkTimeout);
  if (after.exit_code != 0) {
    em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"why\":\"check still red after proposal\",\"exit\":" +
            std::to_string(after.exit_code));
    fprintf(stderr, "rabadon repair: the proposed fix did NOT turn the check green (exit %d) — REPAIR_FAIL (fail closed, your tree untouched)\n", after.exit_code);
    // A rejection with no output is an unactionable rejection: the operator cannot
    // tell a wrong fix from a flaky suite, and the next question is always "red HOW?".
    // The arbiter already holds the answer, so it says it. The work copy is kept on
    // this path (it is the only remaining record of what the proposer did) and named
    // out loud, because a temp dir that leaks silently is a leak, not evidence.
    print_tail("the arbiter's re-run", after.tail);
    fprintf(stderr, "  the proposal is in: %s\n", work.c_str());
    return 2;
  }
  for (auto& lk : locks) {
    if (rbsha::hex(read_file(work + "/" + lk.first)) != lk.second) {
      em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"why\":\"test-tamper: " + json_escape(lk.first) + " was modified\"");
      fprintf(stderr, "rabadon repair: REJECTED — the proposal modified a hash-locked test file (%s). A fix that weakens the check is a fake fix.\n", lk.first.c_str());
      fprintf(stderr, "  locked sha256 %s, found %s\n  the check went GREEN, and that green is exactly what the lock refuses to sell.\n"
                      "  the rejected proposal is in: %s\n",
              lk.second.substr(0, 16).c_str(),
              rbsha::hex(read_file(work + "/" + lk.first)).substr(0, 16).c_str(), work.c_str());
      return 2;
    }
  }

  // ---- 6. hold the verified patch ----
  mkdir((dir + "/.rabadon").c_str(), 0755);
  const string patchName = "repair-" + std::to_string(now_ms()) + ".patch";
  const string patchPath = dir + "/.rabadon/" + patchName;
  {
    // -p1-applicable: headers read base/<f> and work/<f>
    RunResult d = run_shell("cd " + shell_quote(tmp) + " && diff -ruN --exclude=.git --exclude=.rabadon base work > patch.out; true", "", 60);
    (void)d;
    string patch = read_file(tmp + "/patch.out");
    if (patch.empty()) {
      em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"why\":\"green but zero diff (flaky check?)\"");
      fprintf(stderr, "rabadon repair: the check went green with NO change — the check looks flaky, not broken. Nothing is claimed.\n");
      return 2;
    }
    std::ofstream pf(patchPath, std::ios::trunc); pf << patch;
  }
  em.emit("REPAIR_OK", "\"step\":\"session-repair\",\"cmd\":\"" + json_escape(cmd) + "\",\"patch\":\"" + json_escape(".rabadon/" + patchName) + "\",\"locks\":" + std::to_string(locks.size()));
  // grade the evidence out loud: "hash-locked" is only a claim when there WAS
  // a lock. Zero discovered test files means the tamper check could not run —
  // say so, never imply a protection that did not happen.
  if (locks.empty())
    printf("  HELD, UNVERIFIED: the same check re-ran GREEN in the isolated copy, but 0 test files were discovered to hash-lock.\n"
           "  The anti-tamper check never ran — nothing here rules out a fix that simply weakened the check that caught the bug. Review the diff yourself before applying.\n");
  else
    printf("  VERIFIED: the same check re-ran GREEN in the isolated copy and all %zu hash-locked test file(s) are untouched.\n", locks.size());
  printf(
    "  the fix is HELD, not applied — review and apply it yourself:\n"
    "      cd %s\n"
    "      patch -p1 < .rabadon/%s\n"
    "      %s\n"
    "  ledger: REPAIR_OK recorded (counts in `rabadon usage`).\n",
    dir.c_str(), patchName.c_str(), cmd.c_str());
  RunResult rm = run_shell("rm -rf " + shell_quote(tmp), "", 30); (void)rm;
  return 0;
}
