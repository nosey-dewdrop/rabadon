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

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <dirent.h>
#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include "sha256.h"
#include "chain.h"   // the ledger's one writer: chained line + .head sidecar
#include "cli_help.h"

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

// ---------- isolation anchors: content that survives the copy still pointing home ----------
// Every verdict this binary prints rests on one assumption: the check that runs
// in the copy READS the copy. A file holding an absolute path back into the
// original tree breaks that assumption without a word. `pip install -e .` writes
// exactly such a path into a .pth in site-packages; the venv is copied with
// everything else, and the copy's interpreter imports the user's tree. Measured
// here before this code existed: the proposer fixed the work copy, the work
// copy imported the ORIGINAL, and repair said "the proposed fix did NOT turn the
// check green" — safe, blind, and the reason was false. The other polarity is
// worse: the same anchor lets the check go green on code the patch never carried.
//
// So this is a precondition, not a repair outcome: exit 3, like "no runnable
// check", and nothing reaches the ledger. Two tiers, in this order, because they
// differ in how certain they are:
//   AUTOMATIC — a runtime follows these with no help from the check command:
//     *.pth / __editable__* / *.egg-link inside a site-packages (dist-packages)
//     directory, pyvenv.cfg keys other than the informational `command =`, and
//     any symlink whose target is absolute and lands inside the tree (`npm link`).
//   INVOKED — a bin/ (or Scripts/) shim whose shebang names the original
//     interpreter. Every venv that ships pip has three of these, so firing on
//     them unconditionally would refuse nearly every python project; this tier
//     counts only when the check command itself names the file.
// The two decoys that must NEVER fire on their own are load-bearing, not
// hypothetical: pyvenv.cfg records `command = ... /original/.venv` in every venv
// ever created, and pip's console scripts always carry an absolute shebang.
// And there is no cap on how many entries are walked — repair already shipped
// one silent cap (the hash-lock list stopped at 32) and a foreign repo sailed
// through as VERIFIED because of it.
struct Anchor { string rel, why; };

// `root` used as a path, not as the prefix of a longer sibling name:
// /w/proj matches "/w/proj/src" and a bare "/w/proj", never "/w/project".
static bool refs_path(const string& hay, const string& root) {
  size_t p = 0;
  while ((p = hay.find(root, p)) != string::npos) {
    size_t e = p + root.size();
    char c = e < hay.size() ? hay[e] : '\0';
    if (!(isalnum((unsigned char)c) || c == '-' || c == '_' || c == '.')) return true;
    p = e;
  }
  return false;
}

static string read_head(const string& p, size_t n) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  string buf(n, '\0');
  f.read(&buf[0], (std::streamsize)n);
  buf.resize((size_t)f.gcount());
  return buf;
}

// pyvenv.cfg's `command =` line is a receipt of how the venv was made, not a
// path anything resolves through. It names the original directory in every
// copied venv, so reading it as an anchor would refuse every python project.
static bool pyvenv_anchor(const string& body, const string& root, string* key_out) {
  std::istringstream is(body);
  string ln;
  while (std::getline(is, ln)) {
    size_t eq = ln.find('=');
    if (eq == string::npos) continue;
    string key = ln.substr(0, eq);
    while (!key.empty() && isspace((unsigned char)key.back())) key.pop_back();
    while (!key.empty() && isspace((unsigned char)key.front())) key.erase(key.begin());
    if (key == "command") continue;
    if (refs_path(ln, root)) { *key_out = key; return true; }
  }
  return false;
}

static bool ends_with(const string& s, const char* suf) {
  size_t n = strlen(suf);
  return s.size() > n && s.compare(s.size() - n, n, suf) == 0;
}

static void scan_anchors(const string& absDir, const string& root, const string& rel,
                         bool inSitePackages, const string& cmd,
                         std::vector<Anchor>& automatic, std::vector<Anchor>& invoked) {
  DIR* d = opendir(absDir.c_str());
  if (!d) return;
  string pdir = absDir.substr(absDir.rfind('/') + 1);
  struct dirent* e;
  while ((e = readdir(d)) != nullptr) {
    const string name = e->d_name;
    if (name == "." || name == "..") continue;
    if (name == ".git" || name == ".rabadon" || name == ".hg" || name == ".svn") continue;
    const string full = absDir + "/" + name;
    const string r = rel.empty() ? name : rel + "/" + name;
    struct stat st;
    if (lstat(full.c_str(), &st) != 0) continue;
    if (S_ISLNK(st.st_mode)) {
      char tgt[4096];
      ssize_t n = readlink(full.c_str(), tgt, sizeof tgt - 1);
      if (n > 0) {
        tgt[n] = '\0';
        const string t = tgt;
        // absolute targets OUTSIDE the tree (a venv's system interpreter) are
        // shared infrastructure and copy fine; only a link back INTO the tree
        // turns the copy into a window onto the original.
        if (t[0] == '/' && refs_path(t, root)) automatic.push_back({r, "symlink -> " + t});
      }
      continue;  // never followed: the walk stays inside the tree
    }
    if (S_ISDIR(st.st_mode)) {
      scan_anchors(full, root, r,
                   inSitePackages || name == "site-packages" || name == "dist-packages",
                   cmd, automatic, invoked);
      continue;
    }
    if (!S_ISREG(st.st_mode)) continue;
    if (inSitePackages &&
        (ends_with(name, ".pth") || ends_with(name, ".egg-link") ||
         name.compare(0, 12, "__editable__") == 0)) {
      // a .pth is only honoured inside site-packages; anywhere else it is inert
      if (refs_path(read_head(full, 1 << 16), root))
        automatic.push_back({r, "import path config pointing into the original tree (editable install?)"});
      continue;
    }
    if (name == "pyvenv.cfg") {
      string key;
      if (pyvenv_anchor(read_head(full, 8192), root, &key))
        automatic.push_back({r, "`" + key + " =` points into the original tree"});
      continue;
    }
    if (pdir == "bin" || pdir == "sbin" || pdir == "Scripts" || pdir == ".bin") {
      if (cmd.find(r) == string::npos) continue;  // the check never names it
      if (refs_path(read_head(full, 8192), root))
        invoked.push_back({r, "your check runs this, and it points into the original tree"});
    }
  }
  closedir(d);
}

static const char* kHelp =
  "rabadon-repair — caught, then actually fixed, then proven.\n"
  "The proposer works in an ISOLATED COPY of the repo. The SAME check that caught\n"
  "the break re-runs there, and the patch is held only if the check goes green\n"
  "with every test file byte-identical (hash-locked). A fix that buys green by\n"
  "editing or skipping a test is refused, and the refusal is recorded.\n"
  "\n"
  "usage: rabadon-repair [dir] [--cmd \"<check command>\"] [--timeout <sec>]\n"
  "\n"
  "  [dir]              the project to repair (default: the current directory).\n"
  "  --cmd \"<command>\"  the check to run. omitted: rabadon-truth discovers the\n"
  "                     strongest runnable check this repo already has.\n"
  "  --timeout <sec>    proposer budget in seconds (default 240).\n"
  "  -h, --help         this screen.\n"
  "\n"
  "exit: 0 a patch was held · non-zero nothing was held (the tree is untouched).\n"
  "\n"
  "example:\n"
  "  rabadon-repair ~/src/express --cmd \"npx mocha --reporter dot\"\n";

int main(int argc, char** argv) {
  rb_help(argc, argv, kHelp);

  string dir = ".";
  string cmd;
  int proposerTimeout = 240, checkTimeout = 600;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--cmd" && i + 1 < argc) cmd = argv[++i];
    else if (a == "--timeout" && i + 1 < argc) proposerTimeout = atoi(argv[++i]);
    // `-h` used to reach the check discovery and exit 3, "no runnable check
    // found" — a verdict about your repo, printed in answer to a help request.
    else if (rb_is_flag(a.c_str())) rb_unknown_flag("rabadon-repair", a.c_str());
    else dir = a;
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
  printf("  RED (exit %d)%s — caught.\n",
         before.exit_code, before.timed_out ? " [timed out]" : "");

  // ---- 2b. is the isolation real? measured BEFORE the copy, the proposer and
  // the ledger, because none of those three mean anything if it is not. ----
  {
    std::vector<Anchor> automatic, invoked;
    scan_anchors(dir, dir, "", false, cmd, automatic, invoked);
    auto byPath = [](const Anchor& a, const Anchor& b) { return a.rel < b.rel; };
    std::sort(automatic.begin(), automatic.end(), byPath);
    std::sort(invoked.begin(), invoked.end(), byPath);
    std::vector<Anchor> found = automatic;
    found.insert(found.end(), invoked.begin(), invoked.end());
    if (!found.empty()) {
      fprintf(stderr, "rabadon repair: your check resolves outside the isolated copy — nothing was attempted.\n");
      const size_t kShow = 6;
      for (size_t i = 0; i < found.size() && i < kShow; i++)
        fprintf(stderr, "  %s — %s\n", found[i].rel.c_str(), found[i].why.c_str());
      if (found.size() > kShow)
        fprintf(stderr, "  … and %zu more\n", found.size() - kShow);
      fprintf(stderr,
        "  repair copies this repo to /tmp and re-runs your check THERE. Those paths still point into\n"
        "  %s, so the copy would grade YOUR tree: red would blame the proposal for a bug it never saw,\n"
        "  and green would be bought with code the held patch does not contain. Neither is a verdict.\n"
        "  make the check self-contained inside a copied tree, then run repair again, e.g.\n"
        "      rabadon repair --cmd \"PYTHONPATH=src python3 -m pytest\"\n"
        "      rabadon repair --cmd \"python3 -m venv .venv-rb && .venv-rb/bin/pip install -q -e . && .venv-rb/bin/python -m pytest\"\n",
        dir.c_str());
      return 3;
    }
  }
  printf("  proposing a fix in an isolated copy…\n");

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
