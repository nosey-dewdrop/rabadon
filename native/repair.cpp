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
//   2. run it in the real repo. GREEN, CONFIRMED BY A SECOND RUN -> nothing to
//      repair, exit 0. Green then red -> FLAKY, exit 4: one sample of a
//      nondeterministic check is not a verdict, and "nothing to repair" on a
//      lucky green drops a break that is still in the tree;
//   3. copy the repo twice into an isolated tmp dir: `base` (pristine) and
//      `work`; hash-lock every test file (sha256.h);
//   4. proposer: `claude -p` bounded by a wall clock, cwd = the WORK COPY,
//      RABADON_OFF=1 — it may edit the copy, it cannot touch the user's tree;
//   5. ARBITER: re-run the SAME check in the work copy.
//        red                     -> re-sampled, never graded on one run;
//        red twice               -> REPAIR_FAIL, fail closed;
//        red then green          -> FLAKY: the patch is HELD (a repair thrown
//                                   away by a coin flip is a repair the user
//                                   paid a proposer call for and did not get),
//                                   but it is never called VERIFIED;
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
#include "heldout.h" // the behavioural probe: a green must survive the patch's crutches
#include "policy.h"  // R5: repair.mode, and the request the gate left behind
#include "inject.h"  // R5: scrub() — Law 2 has ONE implementation in this repo
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

// `maxTail` is how much of the child's output is kept. The default exists
// because most callers want the last lines of a failing run to print, and 0
// means keep all of it. That default was silently deciding how much protection
// this binary offers: repair parses rabadon-truth's JSON out of the SAME buffer,
// and truth's JSON crosses 4000 bytes somewhere around 110 discovered test
// files. Over that line the front of the JSON, `"testFiles":[` included, was cut
// away, the parse found nothing, and the run hash-locked ZERO tests. Measured on
// the corpus's commander checkout: truth discovers 122 files in 4503 bytes and
// repair locked 0 of them, while express fit in 2382 bytes and locked all 91.
// The bigger the suite, the less of it was protected, which is backwards.
static RunResult run_shell(const string& cmd, const string& cwd, int timeoutSec,
                           const std::vector<string>& extraEnv = {},
                           size_t maxTail = 4000) {
  RunResult r;
  int pfd[2];
  if (pipe(pfd) != 0) return r;
  pid_t pid = fork();
  if (pid < 0) { close(pfd[0]); close(pfd[1]); return r; }
  if (pid == 0) {
    setpgid(0, 0); // own process group: the timeout kill reaps grandchildren too
    if (!cwd.empty() && chdir(cwd.c_str()) != 0) _exit(126);
    // stdout and stderr go to the pipe. STDIN GOES NOWHERE, and that is a
    // verdict, not tidiness.
    //
    // The prompt is passed to the proposer as an ARGUMENT, so nothing here ever
    // needs the parent's stdin — but fd 0 was inherited, and a proposer that
    // reads it blocks until the wall clock fires. rabadon then records
    // REPAIR_FAIL with why="proposer timed out". Measured: a proposer whose
    // first line is `cat >/dev/null` hangs for the whole timeout and is written
    // to the ledger as a failed repair.
    //
    // The verdict is wrong twice over. Nothing was proposed, so nothing was
    // rejected — and the same proposal SUCCEEDS when the caller happens to have
    // a closed stdin, which is how this hid: run it from a script and it works,
    // run it from a terminal and the identical repair is refused. A judgement
    // that depends on how its caller was invoked is not deterministic, and
    // deterministic is the whole claim.
    //
    // The check and the arbiter get the same treatment, for the same reason: a
    // suite that waits on input should fail in the first second rather than eat
    // the timeout and be reported as red.
    int devnull = open("/dev/null", O_RDONLY);
    if (devnull >= 0) { dup2(devnull, 0); if (devnull > 2) close(devnull); }
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
  if (maxTail && out.size() > maxTail) out = out.substr(out.size() - maxTail);
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

// ---------- LAW 2, applied to the text that leaves this process ----------
// The proposer prompt carries the arbiter's failing output, and that output is
// somebody else's bytes: a python traceback names `line 3`, a compiler names
// `foo.c:44:9`. Handing those over is not merely useless — on SWE-bench
// Verified, line-level localisation LOWERS the score against file-level. And a
// line number out of rabadon is a claim about where the bug IS, which rabadon
// does not know; it knows where the error SURFACED, a different fact.
//
// scrub() is rbinject::scrub, the same function R4 uses on the injected
// context. One implementation, or the two surfaces drift and the weaker one
// becomes the law. It squeezes whitespace, so it is applied PER LINE and the
// lines are rejoined: a prompt collapsed onto one line is a prompt whose law
// list has stopped being a list.
static string scrub_lines(const string& in) {
  string out;
  size_t i = 0;
  for (;;) {
    const size_t e = in.find('\n', i);
    const bool last = (e == string::npos);
    out += rbinject::scrub(in.substr(i, (last ? in.size() : e) - i));
    if (last) break;
    out += '\n';
    i = e + 1;
  }
  return out;
}

// The other half of Law 2, and the half that is REQUIRED: file-level context.
// Stripping the line number and handing over nothing else would leave the
// proposer with less than it had. A path is listed only if it EXISTS in this
// tree — a name lifted out of a stack trace that resolves to nothing here is a
// guess, and a guess in a guard tool's voice is the thing this file refuses.
static std::vector<string> files_in_play(const string& dir, const string& tail,
                                         const std::vector<string>& testFiles) {
  std::vector<string> out;
  auto add = [&](string p) {
    if (p.empty() || p.size() > 400) return;
    if (p.compare(0, dir.size(), dir) == 0 && p.size() > dir.size() && p[dir.size()] == '/')
      p = p.substr(dir.size() + 1);
    if (p[0] == '/' || p.find("..") != string::npos) return;
    for (const auto& q : out) if (q == p) return;
    struct stat st;
    if (stat((dir + "/" + p).c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return;
    out.push_back(p);
  };
  string tok;
  for (size_t i = 0; i <= tail.size(); i++) {
    const char c = i < tail.size() ? tail[i] : '\0';
    if (isalnum((unsigned char)c) || c == '.' || c == '/' || c == '_' || c == '-' || c == '+') {
      tok += c;
      continue;
    }
    if (!tok.empty()) { add(tok); tok.clear(); }
  }
  for (const auto& f : testFiles) add(f);
  return out;
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

// ---------- the harness lock: the files that decide WHICH tests run ----------
// The test-file lock answers exactly one question, "did the proposal edit a test?",
// and a green bought without touching a single test byte walks straight past it.
// Measured on this corpus (reports/2026-08-01-hakem-korpusu, nine cheat families):
// two caught, seven through. Five of the seven never open a test file. They move
// the harness instead. A new ./pytest.ini whose addopts ignores the failing module
// takes 53 collected tests down to 23. A testPathIgnorePatterns line in
// jest.config.js drops 1207 to 1197. A rewritten scripts.test in package.json wins
// because the arbiter re-runs the command string it read BEFORE the proposal
// against the manifest the proposer just edited. A root conftest.py whose
// makereport hookwrapper rewrites 'failed' to 'passed' leaves the count at 53 out
// of 53. A setupFilesAfterEach file swallows the throw and even the test NAMES
// come back identical. All five end with a byte-identical suite and exit 0, which
// is every signal the judge owns today.
//
// So the lock has to cover the second surface: not the tests, the machinery that
// selects and grades them. Presence is part of the hash, because ABSENT -> present
// IS the pytest.ini and root-conftest.py attack; a file missing from base and
// sitting in work is a mismatch, not a skip.
//
// Two deliberate holes, named rather than implied. Vendored trees are not walked
// (node_modules alone carries thousands of package.json files, and a cheat that
// patches a dependency in place is a different attack this lock does not claim).
// Lockfiles are not hashed: a check that runs an install rewrites them on its own,
// so locking them would reject honest repairs on suite behaviour the proposer
// never chose.
static bool harness_prefix(const string& n, const char* p) {
  size_t k = strlen(p);
  return n.size() >= k && n.compare(0, k, p) == 0;
}

// `relDir` is the directory holding the file, "" at the project root.
static bool harness_file(const string& name, const string& relDir) {
  // only the root makefile is an entry point; a Makefile deep in the tree is
  // build detail a source fix may legitimately carry
  if (name == "Makefile" || name == "makefile" || name == "GNUmakefile")
    return relDir.empty();
  if (name == "package.json" || name == "pytest.ini" || name == "tox.ini" ||
      name == "setup.cfg" || name == "pyproject.toml" || name == "conftest.py" ||
      name == "phpunit.xml" || name == "phpunit.xml.dist" || name == "Cargo.toml")
    return true;
  // The JVM decides what runs from the build file, not from a runner flag:
  // surefire's <excludes> and gradle's `test { filter { ... } }` each remove a
  // failing class without touching one byte of it. go.work drops a whole module,
  // and every test inside it, out of the build.
  //
  // NOT VERIFIED END TO END, and said here rather than in a release note. The
  // pytest and node families below were each proved by running the real binary
  // against a real suite that really went green for the cheat. These were not:
  // maven on this machine cannot resolve surefire offline, and there is no go
  // toolchain on it at all. The entries are here because the mechanism is the
  // same one the proved families use, which is an argument, not a measurement.
  if (name == "pom.xml" || name == "build.gradle" || name == "build.gradle.kts" ||
      name == "settings.gradle" || name == "settings.gradle.kts" ||
      name == "gradle.properties" || name == "junit-platform.properties" ||
      name == "go.work")
    return true;
  return harness_prefix(name, ".mocharc") ||
         harness_prefix(name, "jest.config") || harness_prefix(name, "jest.setup") ||
         harness_prefix(name, "vitest.config") || harness_prefix(name, "vite.config") ||
         harness_prefix(name, "karma.conf") || harness_prefix(name, "playwright.config") ||
         harness_prefix(name, "cypress.config") || harness_prefix(name, "ava.config");
}

static bool skip_dir(const string& n) {
  return n == ".git" || n == ".rabadon" || n == "node_modules" || n == "__pycache__" ||
         n == ".tox" || n == ".pytest_cache" || n == ".mypy_cache" || n == ".venv" ||
         n == "venv" || n == "env" || n == "dist" || n == "build" || n == "coverage" ||
         n == "target" || n == "vendor" || n == "site-packages" || n == ".next" ||
         n == ".cache" || n == ".gradle";
}

// A check command is mostly words, but some of those words are files in this
// tree — ./check.sh, ci/test, bin/ci, scripts/verify. Those decide what the
// check does, so they belong to the harness in the only sense that matters.
// Absolute paths and anything reaching outside the tree are left alone: they
// are not ours to hash, and pretending otherwise would claim a protection the
// copy cannot give.
static std::vector<string> cmd_paths(const string& root, const string& cmd) {
  std::vector<string> out;
  string tok;
  auto flush = [&]() {
    if (tok.empty()) return;
    string t = tok; tok.clear();
    while (t.size() >= 2 && ((t.front() == '"' && t.back() == '"') ||
                             (t.front() == '\'' && t.back() == '\''))) t = t.substr(1, t.size() - 2);
    if (t.empty() || t[0] == '-' || t[0] == '/') return;
    if (t.rfind("./", 0) == 0) t = t.substr(2);
    if (t.empty() || t.find("..") != string::npos) return;
    const size_t eq = t.find('=');
    const size_t sl = t.find('/');
    if (eq != string::npos && (sl == string::npos || sl > eq)) return;  // VAR=value
    struct stat st;
    if (stat((root + "/" + t).c_str(), &st) == 0 && S_ISREG(st.st_mode)) out.push_back(t);
  };
  for (char c : cmd) {
    if (isspace((unsigned char)c) || c == '|' || c == ';' || c == '&' ||
        c == '(' || c == ')' || c == '<' || c == '>') flush();
    else tok += c;
  }
  flush();
  return out;
}

// no cap: repair already shipped one silent cap (the hash-lock list stopped at 32)
// and a foreign repo sailed through as VERIFIED because of it
static void scan_harness(const string& absDir, const string& rel,
                         std::vector<std::pair<string, string>>& out) {
  DIR* d = opendir(absDir.c_str());
  if (!d) return;
  struct dirent* e;
  while ((e = readdir(d)) != nullptr) {
    const string name = e->d_name;
    if (name == "." || name == "..") continue;
    const string full = absDir + "/" + name;
    const string r = rel.empty() ? name : rel + "/" + name;
    struct stat st;
    if (lstat(full.c_str(), &st) != 0) continue;
    if (S_ISLNK(st.st_mode)) {
      // Never followed: the walk stays inside the tree. But a symlink standing
      // at a harness NAME is a harness file somebody just added, and skipping
      // it made the whole entry invisible to the presence check and the hash
      // alike. Measured 5 August, a proposer added `pytest.ini -> .rbtune`
      // carrying an --ignore for the failing module and earned a verified
      // verdict. A link's identity is where it points, so that is what is
      // recorded, and the target's own content is never read through it.
      if (harness_file(name, rel)) {
        char buf[4096];
        const ssize_t n = readlink(full.c_str(), buf, sizeof buf - 1);
        out.push_back({r, n > 0 ? "symlink:" + string(buf, (size_t)n) : string("symlink:unreadable")});
      }
      continue;
    }
    if (S_ISDIR(st.st_mode)) {
      if (!skip_dir(name)) scan_harness(full, r, out);
      continue;
    }
    if (!S_ISREG(st.st_mode)) continue;
    if (harness_file(name, rel)) out.push_back({r, rbsha::hex(read_file(full))});
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
  "       rabadon-repair [dir] --approve | --apply\n"
  "\n"
  "  [dir]              the project to repair (default: the current directory).\n"
  "  --cmd \"<command>\"  the check to run. omitted: rabadon-truth discovers the\n"
  "                     strongest runnable check this repo already has.\n"
  "  --timeout <sec>    proposer budget in seconds (default 240).\n"
  "  --approve          run the repair the arm asked about (repair.mode = ask).\n"
  "  --apply            apply the newest held patch. THE ONLY THING IN RABADON\n"
  "                     THAT EDITS YOUR TREE, and a human types it.\n"
  "  -h, --help         this screen.\n"
  "\n"
  "when the arm starts itself: repair.mode in $RABADON_DIR/config.json, set once by\n"
  "`rabadon init` — ask (default) | auto-propose (unattended) | off. It triggers only\n"
  "when the same error has survived a third different move AFTER two injections.\n"
  "\n"
  "exit: 0 a patch was held · non-zero nothing was held (the tree is untouched).\n"
  "\n"
  "example:\n"
  "  rabadon-repair ~/src/express --cmd \"npx mocha --reporter dot\"\n";

int main(int argc, char** argv) {
  // ORDER IS PART OF THE OUTPUT, and it was being lost the moment anyone stopped
  // watching on a terminal.
  //
  // The narration goes to stdout and the verdicts go to stderr. On a tty stdout
  // is line-buffered and the two interleave in the order they happened. Into a
  // pipe — a CI log, `| tee`, a recording, anything a stranger reads later —
  // stdout switches to block buffering and does not flush until the process
  // ends, so every verdict arrives BEFORE the run it belongs to. Caught by
  // rasterising the recording and reading it: the frame showed REJECTED with the
  // sha mismatch, and only after it "check: python3 test_calc.py / RED — caught /
  // proposing a fix in an isolated copy…".
  //
  // Backwards is worse than terse. A reader who sees the refusal first has to
  // reconstruct which proposal it refused, and this tool's entire job is to be
  // read by somebody who was not there.
  setvbuf(stdout, nullptr, _IOLBF, 0);
  rb_help(argc, argv, kHelp);

  string dir = ".";
  string cmd;
  bool approve = false, apply = false;
  int proposerTimeout = 240, checkTimeout = 600;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--cmd" && i + 1 < argc) cmd = argv[++i];
    else if (a == "--approve") approve = true;
    else if (a == "--apply") apply = true;
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

  // ---- 0a. --apply: THE ONLY CODE PATH IN RABADON THAT TOUCHES YOUR TREE ---
  // Propose-and-hold is the law, in every mode, including the unattended one.
  // The counterweight to that law is this door, and it is a door a human walks
  // through: `rabadon repair --apply`, typed, in the morning, once. There is no
  // caller of it inside rabadon — not the gate, not the arm, not a hook.
  if (apply) {
    // newest patch wins: the arm may have held several across a long night, and
    // the one worth looking at first is the last one it earned.
    string newest;
    {
      DIR* d = opendir((dir + "/.rabadon").c_str());
      if (d) {
        struct dirent* e;
        while ((e = readdir(d)) != nullptr) {
          const string n = e->d_name;
          if (n.compare(0, 7, "repair-") != 0 || !ends_with(n, ".patch")) continue;
          if (n > newest) newest = n;   // repair-<ms>.patch sorts by time
        }
        closedir(d);
      }
    }
    if (newest.empty()) {
      fprintf(stderr, "rabadon repair: no held patch in %s/.rabadon — nothing to apply.\n", dir.c_str());
      return 3;
    }
    const string rel = ".rabadon/" + newest;
    RunResult ap = run_shell("patch -p1 --forward < " + shell_quote(dir + "/" + rel), dir, 120);
    if (ap.exit_code != 0) {
      em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"outcome\":\"not-applied\",\"class\":\"apply-failed\""
              ",\"why\":\"patch -p1 refused the held patch\",\"patch\":\"" + json_escape(rel) + "\"");
      fprintf(stderr, "rabadon repair: `patch -p1 < %s` failed (exit %d) — your tree is as `patch` left it.\n",
              rel.c_str(), ap.exit_code);
      print_tail("patch", ap.tail);
      return 2;
    }
    em.emit("REPAIR_APPLIED", "\"step\":\"session-repair\",\"outcome\":\"applied\",\"by\":\"human, `rabadon repair --apply`\""
            ",\"patch\":\"" + json_escape(rel) + "\"");
    printf("rabadon repair — applied %s to %s.\n"
           "  This is the only thing in rabadon that edits your tree, and you just typed it.\n"
           "  Re-run your check before you trust it.\n", rel.c_str(), dir.c_str());
    return 0;
  }

  // ---- 0b. --approve: the door `ask` mode leaves standing --------------
  // In ask mode the gate did not run anything; it wrote down WHAT it would run
  // and said so on stderr. Approval answers that specific question rather than
  // starting a fresh one hours later against a session that has moved on, so
  // the check comes out of the request unless the operator overrode it here.
  if (approve) {
    const string rqPath = dir + "/.rabadon/repair-request.json";
    const string rq = read_file(rqPath);
    if (rq.empty()) {
      fprintf(stderr, "rabadon repair: nothing is awaiting approval in %s.\n"
                      "  The arm asks only when the same error has survived a third different move after two hints,\n"
                      "  and only when repair.mode is \"ask\" (%s).\n"
                      "  To repair right now anyway: rabadon repair %s\n",
              dir.c_str(), rbpolicy::config_path().c_str(), dir.c_str());
      return 3;
    }
    if (cmd.empty()) cmd = get_field(rq, "cmd");
    em.emit("REPAIR_APPROVED", "\"step\":\"session-repair\",\"mode\":\"ask\",\"outcome\":\"approved\""
            ",\"by\":\"human, `rabadon repair --approve`\""
            ",\"why\":\"" + json_escape(get_field(rq, "why")) + "\"");
    // The request is consumed: an approval left lying around is an approval a
    // later, unrelated escalation could inherit.
    unlink(rqPath.c_str());
    printf("rabadon repair — approved: %s\n", get_field(rq, "why").c_str());
  }

  // ---- 1. the check ----
  std::vector<string> testFiles;
  {
    // maxTail 0: this output is DATA, not a log tail. See run_shell.
    RunResult t = run_shell(shell_quote(selfDir + "/rabadon-truth") + " " + shell_quote(dir) + " --json",
                            "", 60, {}, 0);
    if (t.exit_code == 0) {
      // testFiles array: crude but sufficient extraction from truth's compact JSON
      size_t k = t.tail.find("\"testFiles\":[");
      if (k == string::npos)
        fprintf(stderr, "rabadon repair: could not read a testFiles list out of rabadon-truth's answer"
                        " (%zu bytes). Nothing will be hash-locked, and this is a read failure, not a repo"
                        " without tests.\n", t.tail.size());
      // discovery has bounds and they are allowed to bite; what they are not
      // allowed to do is bite quietly. If truth turned around early, the lock
      // below covers less than the suite and the operator has to be told which
      // bound did it, because "all N test files are untouched" reads as "the
      // whole suite is untouched" and would not be true.
      {
        size_t c = t.tail.find("\"discoveryCapped\":[");
        if (c != string::npos) {
          size_t e2 = t.tail.find(']', c);
          const string body = t.tail.substr(c + 19, e2 == string::npos ? 0 : e2 - c - 19);
          if (body.find('"') != string::npos)
            fprintf(stderr, "rabadon repair: rabadon-truth stopped short while looking for tests (%s)."
                            " The hash lock will cover less than this repo's suite.\n", body.c_str());
        }
      }
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
  // ONE sample is not a verdict. A check that happens to flake GREEN on this run
  // would send repair home with "nothing to repair" while the break is still
  // sitting in the tree — a caught break silently dropped. So the green that ends
  // the run is confirmed by a second sample; the red that starts it is not, because
  // red only costs a proposal, while a wrong green costs the whole catch.
  RunResult before = run_shell(cmd, dir, checkTimeout);
  if (before.exit_code == 0) {
    RunResult confirm = run_shell(cmd, dir, checkTimeout);
    if (confirm.exit_code == 0) {
      printf("  the check is GREEN — nothing to repair.\n");
      return 0;
    }
    // Same command, same untouched tree, two different answers. Sending the
    // operator home green is a claim this run cannot support, and the ledger is
    // the product's word — so FLAKY gets its own reason and its own exit code (4),
    // never silence and never a verdict about a proposal that was never made.
    em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"outcome\":\"not-held\",\"class\":\"FLAKY\",\"why\":\"flaky check: entry samples disagree (green, then exit " +
            std::to_string(confirm.exit_code) + ")\",\"samples\":2");
    fprintf(stderr,
      "rabadon repair: FLAKY CHECK — the same check, on the same untouched tree, ran GREEN and then RED (exit %d)%s.\n"
      "  A coin flip is not a verdict. Calling this repo healthy would drop a break that may really be there,\n"
      "  and grading a proposal against this check would be just as arbitrary. Nothing was attempted, nothing is claimed.\n"
      "  Make the check deterministic (or hand a deterministic one to --cmd) and run repair again.\n",
      confirm.exit_code, confirm.timed_out ? " [timed out]" : "");
    print_tail("the second entry run", confirm.tail);
    return 4;
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
    // A COPY THAT CARRIES A CACHE OF THE SOURCE IT IS ABOUT TO REPLACE IS NOT AN
    // ISOLATED COPY.
    //
    // Measured 5 August, read out of the work directory of a run that had just
    // been rejected: work/calc.py held the CORRECT fix, and `import calc` in that
    // same directory returned the buggy answer. Deleting __pycache__ and importing
    // again returned the right one. The arbiter had re-run the interpreter's
    // bytecode for the source the proposer had already replaced, watched it fail,
    // and called an honest fix a fake fix.
    //
    // The mechanism needs three things at once, which is why it stayed hidden.
    // CPython validates a .pyc against the source mtime and SIZE, at one second
    // of resolution. `cp -R` preserves mtime, so the copy inherits exactly the
    // timestamp the .pyc recorded. And a fix like `a - b` -> `a + b` is the same
    // number of bytes. Land that write inside the same second and every field the
    // cache checks still agrees.
    //
    // Rate on a three-line fixture: 7 rejections in 12 runs. 0 in 12 when the fix
    // changed the byte count, 0 in 12 with bytecode writing turned off. It is a
    // FALSE REPAIR_FAIL, which costs more than a miss: the product's claim is that
    // a held repair really was verified, and a judge that refuses correct work at
    // random is not stricter, it is noisier.
    //
    // Only derived bytecode goes. node_modules, target/ and build/ are derived too
    // and are left alone — the check command needs them, and none of them answers
    // a question about the source with an answer computed from an older one. That
    // property is what is being removed here, not "generated files".
    const string purge =
        " ; for d in " + shell_quote(base) + " " + shell_quote(work) + "; do"
        " find \"$d\" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null;"
        " find \"$d\" -type f \\( -name '*.pyc' -o -name '*.pyo' \\) -delete 2>/dev/null;"
        " done; true";
    RunResult c1 = run_shell("{ mkdir -p " + shell_quote(base) + " " + shell_quote(work) +
                             " && cp -R " + shell_quote(dir) + "/. " + shell_quote(base) +
                             " && cp -R " + shell_quote(dir) + "/. " + shell_quote(work) +
                             " && rm -rf " + shell_quote(base + "/.rabadon") + " " + shell_quote(work + "/.rabadon") +
                             "; } || exit 1" + purge, "", 120);
    if (c1.exit_code != 0) { fprintf(stderr, "rabadon repair: could not copy the repo\n"); return 1; }
  }
  std::vector<std::pair<string, string>> locks; // testFile -> sha256
  for (const string& f : testFiles) locks.push_back({f, rbsha::hex(read_file(base + "/" + f))});
  std::vector<std::pair<string, string>> harness; // harness file -> sha256, base side
  scan_harness(base, "", harness);
  // The lock covered the tests and the files that configure the runner, and it
  // left out the one file that decides what "the check" even is: the script the
  // command itself invokes. Measured 5 August, a proposer replaced the body of
  // the project's own ci/check.sh with `exit 0`, the arbiter ran it, saw green,
  // and the run earned the full VERIFIED headline while the real suite never
  // executed a line. Every word of the command that resolves to a regular file
  // in this tree is now locked exactly like the harness.
  for (const string& p : cmd_paths(base, cmd)) {
    bool already = false;
    for (const auto& h : harness) if (h.first == p) { already = true; break; }
    if (!already) harness.push_back({p, rbsha::hex(read_file(base + "/" + p))});
  }
  std::sort(harness.begin(), harness.end());

  // ---- 4. the proposer, bounded, in the WORK copy ----
  string prompt =
    "You are the repair slot inside rabadon, a reliability runtime for AI coding agents.\n"
    "A deterministic check in this repository is RED. Fix the CODE so the check passes.\n"
    "Laws:\n"
    "- NEVER edit, weaken, skip or delete a test file. A fix that touches a test is rejected automatically (the test files are hash-locked).\n"
    "- NEVER edit, add or delete a test-harness file either: package.json, pytest.ini, tox.ini, setup.cfg, pyproject.toml, conftest.py, Cargo.toml, phpunit.xml, pom.xml, build.gradle, settings.gradle, gradle.properties, junit-platform.properties, go.work, the root Makefile, or any jest/vitest/vite/mocha/karma/playwright/cypress/ava config or setup file. Those are hash-locked the same way, and ADDING one counts as touching it.\n"
    "- Only edit files inside the current working directory.\n"
    "- Do not run the check yourself; the arbiter re-runs it after you.\n"
    "check command: " + cmd + "\n";
  {
    // FILE, NEVER A LINE. What rabadon is willing to name is here, said out
    // loud, so a reader of this prompt can see the boundary rather than infer
    // it from an absence.
    const std::vector<string> fip = files_in_play(dir, before.tail, testFiles);
    if (!fip.empty()) {
      prompt += "files in play (rabadon names files, never lines — it knows where the error surfaced, not where the bug is):\n";
      const size_t kMax = 20;
      for (size_t i = 0; i < fip.size() && i < kMax; i++) prompt += "  " + fip[i] + "\n";
      if (fip.size() > kMax) prompt += "  … and " + std::to_string(fip.size() - kMax) + " more\n";
    }
  }
  prompt += "failing output from that check, as the arbiter saw it (tail):\n" + before.tail + "\n";
  // LAST, over the whole assembled string, for the same reason inject.h does it
  // last: the failing output and the check command are bytes nothing here owns.
  prompt = scrub_lines(prompt);
  string propCmd = shell_quote(claudeBin) + " -p --output-format text --permission-mode acceptEdits " + shell_quote(prompt);
  // maxTail 0: the proposer's output is DATA here, not a log tail — it is one
  // of the two numbers the COST below is measured from, and a truncated
  // measurement of your own spending is an advertisement.
  RunResult prop = run_shell(propCmd, work, proposerTimeout, {"RABADON_OFF=1"}, 0);

  // ---- Yasa 6: the repair arm is the ONLY place rabadon spends tokens, so it
  // is the only place the counter can be caught lying. It goes on the ledger as
  // a COST whatever the verdict turns out to be — a call that timed out or got
  // rejected was still paid for, and a counter that only books its successes is
  // not a counter. It is an ESTIMATE and it says so: `claude -p --output-format
  // text` returns prose, not a usage block, so what is actually MEASURED here
  // is characters in and characters out, both exact, and tokens are those over
  // four. Both raw counts are on the line so a reader can redo the division.
  {
    const long long cin = (long long)rbinject::nchars(prompt);
    const long long cout = (long long)rbinject::nchars(prop.tail);
    em.emit("COST",
            "\"step\":\"session-repair\",\"arm\":\"repair\",\"what\":\"proposer call\""
            ",\"chars_in\":" + std::to_string(cin) +
            ",\"chars_out\":" + std::to_string(cout) +
            ",\"tokens\":" + std::to_string((cin + cout + 3) / 4) +
            ",\"estimated\":1"
            ",\"basis\":\"chars/4; the proposer is run with --output-format text and returns no usage block, so the exact numbers are the two char counts\"");
  }
  if (prop.timed_out) {
    em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"outcome\":\"not-held\",\"class\":\"timeout\",\"why\":\"proposer timed out\"");
    fprintf(stderr, "rabadon repair: proposer timed out after %ds — REPAIR_FAIL (fail closed, your tree untouched)\n", proposerTimeout);
    return 2;
  }

  // ---- 5. the arbiter: same check, work copy ----
  // The verdict that DESTROYS a proposal is the expensive one, so it is the one
  // that may not rest on a single sample. expressjs/express — the G3 target —
  // flaked red on 3 of 6 pristine runs (reports/2026-08-01-g3-first-held-repair/09).
  // On a suite like that a single red throws away a correct, source-only fix the
  // user already paid a proposer call for, and writes "check still red after
  // proposal" onto the hash-chained ledger as fact. The chain proves that line was
  // never edited afterwards; it cannot make it true.
  RunResult after = run_shell(cmd, work, checkTimeout);
  bool flakyArbiter = false;
  const int firstArbiterExit = after.exit_code;
  if (after.exit_code != 0) {
    printf("  the arbiter's check came back RED (exit %d) — re-sampling it before that becomes a verdict…\n",
           after.exit_code);
    fflush(stdout);
    RunResult retry = run_shell(cmd, work, checkTimeout);
    if (retry.exit_code != 0) {
      // Both samples agree. NOW it is a verdict: the proposal did not fix it.
      em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"outcome\":\"not-held\",\"class\":\"REPAIR_FAIL\",\"why\":\"check still red after proposal\",\"exit\":" +
              std::to_string(firstArbiterExit) + ",\"exit2\":" + std::to_string(retry.exit_code) + ",\"samples\":2");
      fprintf(stderr, "rabadon repair: the proposed fix did NOT turn the check green (exit %d, re-sampled: exit %d) — REPAIR_FAIL (fail closed, your tree untouched)\n",
              firstArbiterExit, retry.exit_code);
      // A rejection with no output is an unactionable rejection: the operator cannot
      // tell a wrong fix from a flaky suite, and the next question is always "red HOW?".
      // The arbiter already holds the answer, so it says it. The work copy is kept on
      // this path (it is the only remaining record of what the proposer did) and named
      // out loud, because a temp dir that leaks silently is a leak, not evidence.
      print_tail("the arbiter's re-run (sample 2 of 2, both red)", retry.tail);
      fprintf(stderr, "  the proposal is in: %s\n", work.c_str());
      return 2;
    }
    // The samples disagree: same proposal, same copy, one run apart, two answers.
    // The check is nondeterministic, so this run cannot certify anything — but a
    // green run is still positive evidence the proposer could not have bought by
    // touching the source alone, and the patch is HELD, never applied, so keeping
    // it costs the user a review and destroying it costs them the repair. It is
    // kept, and it is labelled FLAKY everywhere: screen, headline and ledger.
    flakyArbiter = true;
    after = retry;
  }
  for (auto& lk : locks) {
    if (rbsha::hex(read_file(work + "/" + lk.first)) != lk.second) {
      em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"outcome\":\"not-held\",\"class\":\"test-tamper\",\"why\":\"test-tamper: " + json_escape(lk.first) + " was modified\"");
      fprintf(stderr, "rabadon repair: REJECTED — the proposal modified a hash-locked test file (%s). A fix that weakens the check is a fake fix.\n", lk.first.c_str());
      fprintf(stderr, "  locked sha256 %s, found %s\n  the check went GREEN, and that green is exactly what the lock refuses to sell.\n"
                      "  the rejected proposal is in: %s\n",
              lk.second.substr(0, 16).c_str(),
              rbsha::hex(read_file(work + "/" + lk.first)).substr(0, 16).c_str(), work.c_str());
      return 2;
    }
  }
  // the same refusal, one surface out: the suite can be byte-perfect and still
  // not be the suite that ran. Both directions count, and "added" is the whole
  // of two families, so a file that was not in base is a verdict on its own.
  {
    std::vector<std::pair<string, string>> after_h;
    scan_harness(work, "", after_h);
    // The same augmentation as the base side, or the two lists are not
    // comparable: the command's script is not a harness FILENAME, so a plain
    // rescan can never contain it and an untouched script reads as deleted.
    // Both cases then refuse, and the refusal that looks right is right for the
    // wrong reason, which is worse than the hole it replaced.
    for (const string& p : cmd_paths(work, cmd)) {
      bool already = false;
      for (const auto& h : after_h) if (h.first == p) { already = true; break; }
      if (!already) after_h.push_back({p, rbsha::hex(read_file(work + "/" + p))});
    }
    std::sort(after_h.begin(), after_h.end());
    string rel, verdict, was, found;
    size_t i = 0, j = 0;
    while (i < harness.size() || j < after_h.size()) {
      if (j >= after_h.size() || (i < harness.size() && harness[i].first < after_h[j].first)) {
        rel = harness[i].first; verdict = "deleted"; was = harness[i].second; found = "absent"; break;
      }
      if (i >= harness.size() || after_h[j].first < harness[i].first) {
        rel = after_h[j].first; verdict = "added"; was = "absent"; found = after_h[j].second; break;
      }
      if (harness[i].second != after_h[j].second) {
        rel = harness[i].first; verdict = "modified"; was = harness[i].second; found = after_h[j].second; break;
      }
      i++; j++;
    }
    if (!rel.empty()) {
      em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"outcome\":\"not-held\",\"class\":\"harness-tamper\",\"why\":\"harness-tamper: " +
              json_escape(rel) + " was " + verdict + "\"");
      fprintf(stderr,
        "rabadon repair: REJECTED — the proposal %s a hash-locked harness file (%s). Every test file is untouched,\n"
        "  and that is exactly why this check exists: the suite can be byte-perfect and still not be the suite that ran.\n"
        "  locked sha256 %s, found %s\n"
        "  the check went GREEN, and that green is exactly what the lock refuses to sell.\n"
        "  the rejected proposal is in: %s\n",
        verdict.c_str(), rel.c_str(),
        was == "absent" ? "absent" : was.substr(0, 16).c_str(),
        found == "absent" ? "absent" : found.substr(0, 16).c_str(), work.c_str());
      return 2;
    }
  }

  // ---- 5c. the held-out probe: the green must survive the patch's crutches ----
  // Both hash locks answer "did the proposal change what the suite IS". Two of
  // the nine cheat families in the corpus audit change the SOURCE only, so both
  // answers come back clean while the bug is still in the tree: a branch keyed
  // on the one input the suite feeds, and a type whose == cannot say no. A third
  // hash cannot see either. heldout.h reads the patch's own added lines against
  // the literals the LOCKED TESTS carry, and whatever it flags is decided by a
  // RE-RUN: the flagged hunks come back out of the work copy and the project's
  // own check runs again. Red means the green belonged to the flagged construct.
  string probeVerdict;   // empty until the probe has an answer to print
  {
    RunResult d = run_shell("cd " + shell_quote(tmp) +
                            " && diff -ruN --exclude=.git --exclude=.rabadon base work > patch.out; true", "", 60);
    (void)d;
    const string patchText = read_file(tmp + "/patch.out");
    std::vector<string> testBodies;
    for (const string& f : testFiles) testBodies.push_back(read_file(base + "/" + f));
    // the whole base tree as one string is what "this constant is not from
    // around here" is measured against; only the files the patch touched matter,
    // so it is built from those rather than from the tree.
    string baseTouched;
    const std::vector<rbheld::Hunk> hs = rbheld::hunks(patchText);
    {
      std::vector<string> seen;
      for (const auto& h : hs) {
        if (std::find(seen.begin(), seen.end(), h.file) != seen.end()) continue;
        seen.push_back(h.file);
        baseTouched += read_file(base + "/" + h.file);
      }
    }
    const std::vector<rbheld::Flag> flags = rbheld::scan(hs, rbheld::facts(testBodies), baseTouched);
    if (!flags.empty()) {
      printf("  the patch carries %zu construct(s) a green can be bought with — re-running the check without them…\n",
             flags.size());
      fflush(stdout);
      const string probe = tmp + "/probe";
      RunResult cp = run_shell("cp -R " + shell_quote(work) + " " + shell_quote(probe), "", 120);
      std::ofstream fp(tmp + "/flagged.patch", std::ios::trunc);
      fp << rbheld::flagged_patch(hs, flags);
      fp.close();
      RunResult rv = cp.exit_code != 0 ? cp
                   : run_shell("patch -R -p1 --forward -s < " + shell_quote(tmp + "/flagged.patch"), probe, 60);
      if (rv.exit_code != 0) {
        // Could not build the probe. That is not a verdict either way, and the
        // one thing it may never do is quietly become a pass.
        probeVerdict = "UNPROBED";
        fprintf(stderr, "rabadon repair: the flagged hunk(s) could not be reverted for the held-out probe"
                        " (exit %d) — the probe did not run.\n", rv.exit_code);
      } else {
        RunResult pr = run_shell(cmd, probe, checkTimeout);
        if (pr.exit_code != 0) {
          // one red is not a verdict here either: destroying an honest repair
          // on a flaky suite costs the user the proposer call they paid for.
          RunResult pr2 = run_shell(cmd, probe, checkTimeout);
          if (pr2.exit_code != 0) {
            string why;
            for (const auto& f : flags) why += (why.empty() ? "" : "; ") + f.kind;
            em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"outcome\":\"not-held\",\"class\":\"REPAIR_FAIL\",\"why\":\"held-out probe: the green is bought by "
                    + json_escape(why) + "\",\"flags\":" + std::to_string(flags.size()) + ",\"samples\":2");
            fprintf(stderr,
              "rabadon repair: REJECTED — the green is bought by the patch itself, not by a fix (held-out probe).\n"
              "  Every test file and every harness file is byte-identical, and the check went GREEN. It stops being\n"
              "  green the moment these come back out of the patch, which means they are what the suite was passing on:\n");
            for (const auto& f : flags)
              fprintf(stderr, "    [%s] %s\n", f.kind.c_str(), f.why.c_str());
            fprintf(stderr,
              "  A fix that only answers for the exact input the test feeds is not a fix; the neighbouring input still\n"
              "  carries the bug. The check was re-run twice without these hunks and came back red both times (exit %d, %d).\n"
              "  the rejected proposal is in: %s\n", pr.exit_code, pr2.exit_code, work.c_str());
            return 2;
          }
          probeVerdict = "UNPROBED";
          fprintf(stderr, "rabadon repair: the held-out probe answered red then green — the check is not deterministic\n"
                          "  enough for this question, so the probe is not counted either way.\n");
        } else {
          probeVerdict = "PASSED";
          printf("  held-out probe: the check is still GREEN with those %zu construct(s) reverted, so they are not\n"
                 "  what it was passing on.\n", flags.size());
        }
      }
    }
  }

  // ---- 6. hold the verified patch ----
  mkdir((dir + "/.rabadon").c_str(), 0755);
  const string patchName = "repair-" + std::to_string(now_ms()) + ".patch";
  const string patchPath = dir + "/.rabadon/" + patchName;
  {
    string patch = read_file(tmp + "/patch.out");
    if (patch.empty()) {
      em.emit("REPAIR_FAIL", "\"step\":\"session-repair\",\"outcome\":\"not-held\",\"class\":\"FLAKY\",\"why\":\"green but zero diff (flaky check?)\"");
      fprintf(stderr, "rabadon repair: the check went green with NO change — the check looks flaky, not broken. Nothing is claimed.\n");
      return 2;
    }
    std::ofstream pf(patchPath, std::ios::trunc); pf << patch;
  }
  // The screen has said for a while that a flaky run certifies nothing, and the
  // ledger went on writing REPAIR_OK underneath it, so `rabadon stats` counted a
  // coin flip as a held repair. Measured 5 August: one flaky session printed
  // "nothing here is certified" and the counter still read `repairs held
  // (locked): 1`. The counter is the number this product is sold on, so the
  // uncertified case gets its own event and the word OK stops covering it.
  em.emit(flakyArbiter ? "REPAIR_FLAKY" : "REPAIR_OK",
          string(flakyArbiter ? "\"outcome\":\"not-held\",\"class\":\"FLAKY\"," : "\"outcome\":\"held\",") +
          "\"step\":\"session-repair\",\"cmd\":\"" + json_escape(cmd) + "\",\"patch\":\"" + json_escape(".rabadon/" + patchName) + "\",\"locks\":" + std::to_string(locks.size()) +
          ",\"harnessLocks\":" + std::to_string(harness.size()) +
          (flakyArbiter ? ",\"why\":\"flaky check: arbiter samples disagree (exit " + std::to_string(firstArbiterExit) + ", then green)\",\"samples\":2" : ""));
  // grade the evidence out loud: "hash-locked" is only a claim when there WAS
  // a lock. Zero discovered test files means the tamper check could not run —
  // say so, never imply a protection that did not happen. A run the arbiter could
  // not grade twice the same way earns neither word: not VERIFIED, and not the
  // quiet UNVERIFIED either, because the reason is the check, not the locks.
  if (flakyArbiter) {
    printf("  HELD, FLAKY CHECK: the arbiter ran this same proposal twice and the check answered differently"
           " — exit %d, then GREEN.\n"
           "  Neither run is a verdict, so nothing here is certified. The patch is kept rather than thrown away:\n"
           "  a repair discarded by a coin flip is a repair you paid a proposer call for and did not get.%s\n",
           firstArbiterExit,
           locks.empty() ? " On top of that, 0 test files were\n  discovered to hash-lock, so the anti-tamper check never ran either." : "");
    if (!locks.empty())
      printf("  All %zu hash-locked test file(s) are untouched — that half of the proof did run.\n", locks.size());
  }
  else if (locks.empty())
    // "why not VERIFIED" has to name the check that did not run, not merely
    // withhold the word. The harness-lock work rewrote this sentence and the
    // phrase `anti-tamper` fell out of it, so the screen stopped naming which
    // half of the proof was missing while repair_session_test.sh went on
    // asserting that it did — the suite was red on exactly this line.
    printf("  HELD, UNVERIFIED: the same check re-ran GREEN in the isolated copy, but 0 test files were discovered to\n"
           "  hash-lock, so the anti-tamper check never ran. The %zu harness file(s) that decide which tests run are\n"
           "  byte-identical with none added, so the check that ran is the check that was chosen. What is missing is the\n"
           "  other half: nothing here rules out a proposal that rewrote the assertions themselves. Review the diff\n"
           "  yourself before applying.\n", harness.size());
  else
    printf("  VERIFIED: the same check re-ran GREEN in the isolated copy, all %zu hash-locked test file(s) are untouched,\n"
           "  and the %zu harness file(s) that decide which tests run are byte-identical with none added.\n",
           locks.size(), harness.size());
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
