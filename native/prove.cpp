// prove.cpp — did this change actually cause anything?  (C++17)
//
// THE QUESTION
// An agent says it fixed something. The evidence offered is that the tests pass.
// Tests passing is not evidence. The agent may have written a test that passes
// either way, weakened one that already existed, or fixed nothing at all because
// no test ever ran that code. Every one of those has been measured in the wild:
// SpecBench 2025 found models saturate the suite they can see and lose 28 points
// on a holdout they cannot, and "Building to the Test" found agents deleting the
// failing test instead of repairing the code underneath it.
//
// The missing half of the evidence is the RED.
//
//   Take the change. Put back the source it touched, and ONLY the source.
//   Leave every test exactly where the change left it. Run the project's own
//   check again. If it does not go red, the change proved nothing.
//
// That is the whole idea, and its value is that it needs no oracle. Deciding
// whether a fix is correct requires knowing the right answer for inputs the
// suite never runs, which nobody has. Deciding whether a fix is LOAD-BEARING
// only requires running the suite twice, and the second run is one the change's
// author never got to influence.
//
// WHAT THIS DOES NOT CLAIM, and it is the first line of every report:
// PROVEN does not mean correct. If the suite encodes the wrong behaviour, a
// change that satisfies it is still PROVEN. This measures whether the change
// causes the green, not whether the green is right. A tool that blurs those two
// is the thing it was built to refuse.
//
// THREE TREES
//   post     the change applied            expected GREEN
//   counter  post, minus the SOURCE half   expected RED     <- the proof
//   pre      post, minus the change        expected GREEN   (control)
//
// `pre` exists to catch the case where the suite was already red before anyone
// touched anything, which would make `counter`'s red meaningless.
//
// EVERY UNCERTAIN OUTCOME GETS ITS OWN WORD. "I could not prove this" must never
// render as "this is fine", the same rule `rabadon audit` follows when it exits
// 2 for UNVERIFIABLE rather than folding it into INTACT.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include "classify.h"
#include "cli_help.h"

using std::string;
using std::vector;

// ---------- small helpers ----------

static string read_stream(FILE* f) {
  string out; char buf[65536]; size_t n;
  while ((n = fread(buf, 1, sizeof buf, f)) > 0) out.append(buf, n);
  return out;
}

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return "";
  std::ostringstream ss; ss << f.rdbuf(); return ss.str();
}

static bool write_file(const string& p, const string& s) {
  std::ofstream f(p, std::ios::binary);
  if (!f) return false;
  f << s; return true;
}

// run a command in `cwd`, capture combined output, return exit code
static int run(const string& cmd, const string& cwd, string* out, int timeoutSec) {
  string full = "cd " + cwd + " 2>/dev/null && " + cmd + " 2>&1";
  if (timeoutSec > 0) {
    // No GNU timeout on macOS, so the watchdog is a subshell. It MUST have its
    // stdout closed: popen() reads until every writer lets go of the pipe, and a
    // watchdog that inherits stdout is a writer. Leave it open and the read
    // blocks for the whole timeout even after the real command has exited —
    // which is not a hang in the command, it is a hang in the harness, and it
    // looks identical from outside.
    full = "( " + full + " ) & p=$!; ( sleep " + std::to_string(timeoutSec) +
           "; kill -9 $p 2>/dev/null ) >/dev/null 2>&1 & w=$!; "
           "wait $p 2>/dev/null; rc=$?; kill -9 $w 2>/dev/null; exit $rc";
  }
  FILE* p = popen(full.c_str(), "r");
  if (!p) { if (out) *out = "popen failed"; return 127; }
  string o = read_stream(p);
  int st = pclose(p);
  if (out) *out = o;
  return WIFEXITED(st) ? WEXITSTATUS(st) : 1;
}

static bool have(const string& prog) {
  string o; return run("command -v " + prog + " >/dev/null", "/", &o, 10) == 0;
}

// ---------- the diff, split by what each file IS ----------
//
// A unified diff is a sequence of per-file sections that each begin with
// `diff --git`. Splitting there rather than at hunk level is deliberate: a file
// that holds source and suite in the same bytes cannot be cut in half without
// guessing, and a guess is not a proof. Those files are refused by name.

struct FileSection {
  string path;              // the b/ path
  string text;              // the whole section, verbatim
  rbclass::Verdict cls;
};

static string section_path(const string& header) {
  // `diff --git a/x b/x` -> x   (the b side, which is where the file ends up)
  size_t b = header.find(" b/");
  if (b == string::npos) return "";
  string p = header.substr(b + 3);
  size_t nl = p.find('\n');
  if (nl != string::npos) p = p.substr(0, nl);
  while (!p.empty() && (p.back() == '\r' || p.back() == ' ')) p.pop_back();
  return p;
}

static vector<FileSection> split_diff(const string& diff) {
  vector<FileSection> out;
  size_t i = 0;
  while (i < diff.size()) {
    size_t start = diff.find("diff --git ", i);
    if (start == string::npos) break;
    size_t next = diff.find("\ndiff --git ", start + 1);
    size_t end = next == string::npos ? diff.size() : next + 1;
    FileSection fs;
    fs.text = diff.substr(start, end - start);
    fs.path = section_path(fs.text);
    if (!fs.path.empty()) {
      fs.cls = rbclass::classify(fs.path);
      out.push_back(fs);
    }
    i = end;
  }
  return out;
}

// ---------- verdicts ----------

struct Result {
  string verdict;
  string why;
  int exitCode = 2;
};

static const char* kHelp =
  "rabadon-prove — did this change actually cause anything?\n"
  "\n"
  "Puts back the SOURCE half of a change, leaves every test where the change\n"
  "left it, and runs the project's own check again. A change whose removal does\n"
  "not turn the suite red proved nothing, whatever its tests say.\n"
  "\n"
  "usage:\n"
  "  rabadon prove [--dir D] [--patch <file|->] [--cmd \"<check>\"]\n"
  "                [--samples N] [--timeout N] [--keep]\n"
  "\n"
  "  --dir D      the project (default: cwd)\n"
  "  --patch F    a unified diff; `-` reads stdin. Omitted: `git diff HEAD`.\n"
  "  --cmd C      the check to run. Omitted: whatever rabadon-truth finds.\n"
  "  --samples N  runs per tree (default 2). One sample cannot see a flake.\n"
  "  --timeout N  seconds per check run (default 600)\n"
  "  --keep       leave the three trees on disk and print where they are\n"
  "  -h, --help   this screen\n"
  "\n"
  "verdicts:\n"
  "  PROVEN                  removing the source turned the check red\n"
  "  PROVEN_WITH_TEST_EDIT   same, but the change also edited an existing test\n"
  "  TEST_PASSES_BOTH_WAYS   the change added tests that pass without it\n"
  "  NO_COUNTERFACTUAL       the check stayed green without the change\n"
  "  MIXED_FILE_UNPROVABLE   source and suite share a file; cannot cut cleanly\n"
  "  NO_TRUTH                nothing in this repo can go red\n"
  "  FLAKY_CHECK             samples disagreed; a coin flip is not a verdict\n"
  "\n"
  "exit: 0 proven · 1 shown false · 2 unprovable · 3 usage/env · 4 flaky\n"
  "\n"
  "PROVEN does not mean correct. If the suite encodes the wrong behaviour, a\n"
  "change that satisfies it is still PROVEN. This measures whether the change\n"
  "causes the green, not whether the green is right.\n";

int main(int argc, char** argv) {
  rb_help(argc, argv, kHelp);

  string dir = ".", patchArg, cmd;
  int samples = 2, timeoutSec = 600;
  bool keep = false;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--dir" && i + 1 < argc) dir = argv[++i];
    else if (a == "--patch" && i + 1 < argc) patchArg = argv[++i];
    else if (a == "--cmd" && i + 1 < argc) cmd = argv[++i];
    else if (a == "--samples" && i + 1 < argc) samples = atoi(argv[++i]);
    else if (a == "--timeout" && i + 1 < argc) timeoutSec = atoi(argv[++i]);
    else if (a == "--keep") keep = true;
    else rb_unknown_flag("rabadon-prove", a.c_str());
  }
  if (samples < 1) samples = 1;

  { char wd[4096]; if (dir == "." && getcwd(wd, sizeof wd)) dir = wd; }
  if (!have("patch")) {
    fprintf(stderr, "rabadon prove: `patch` is not on PATH; it is how a change is put back.\n");
    return 3;
  }

  // ---------- the change ----------
  string diff;
  if (patchArg == "-") diff = read_stream(stdin);
  else if (!patchArg.empty()) diff = read_file(patchArg);
  else {
    string o;
    if (run("git diff HEAD", dir, &o, 60) != 0) {
      fprintf(stderr, "rabadon prove: no --patch given and `git diff HEAD` failed in %s\n", dir.c_str());
      return 3;
    }
    diff = o;
  }
  if (diff.find("diff --git ") == string::npos) {
    fprintf(stderr, "rabadon prove: the input carries no `diff --git` sections — nothing to take apart.\n");
    return 3;
  }

  vector<FileSection> secs = split_diff(diff);
  if (secs.empty()) { fprintf(stderr, "rabadon prove: no files in the diff.\n"); return 3; }

  // ---------- what is this change made of ----------
  string sourcePatch, fullPatch;
  int nSource = 0, nTest = 0, nHarness = 0, nOther = 0, nAssumed = 0;
  vector<string> mixed, testsEdited;
  for (const auto& s : secs) {
    fullPatch += s.text;
    switch (s.cls.kind) {
      case rbclass::SOURCE: {
        // A change to a language whose tests can live inside the source file
        // cannot be cut apart on a file boundary. Guessing which hunks are the
        // test half would make the counterfactual meaningless, so it is refused.
        const string e = rbclass::ext_of(s.path);
        if (rbclass::may_be_mixed(e) &&
            (s.text.find("#[cfg(test)]") != string::npos ||
             s.text.find("#[test]") != string::npos ||
             s.text.find("\n+    >>> ") != string::npos))
          mixed.push_back(s.path);
        sourcePatch += s.text; nSource++;
        if (s.cls.assumed) nAssumed++;
        break;
      }
      case rbclass::TEST:
        nTest++;
        // an existing test the change rewrote is a different claim from a new
        // test it added; the caller has to be told which one this is
        if (s.text.find("\nnew file mode ") == string::npos) testsEdited.push_back(s.path);
        break;
      case rbclass::HARNESS: nHarness++; break;
      default: nOther++; break;
    }
  }

  printf("rabadon prove — %s\n", dir.c_str());
  printf("  the claim: putting back the source half of this change turns this repo's own check red.\n");
  printf("  NOT the claim: that the change is correct.\n\n");
  printf("  change: %d source, %d test, %d harness, %d other\n", nSource, nTest, nHarness, nOther);

  if (!mixed.empty()) {
    printf("\n  verdict: MIXED_FILE_UNPROVABLE\n");
    for (const auto& m : mixed)
      printf("    %s holds source and suite in the same file; cutting it apart would be a guess\n", m.c_str());
    return 2;
  }
  if (nSource == 0) {
    printf("\n  verdict: NO_COUNTERFACTUAL (no source in this change)\n");
    printf("    nothing here claims a behaviour, so there is nothing to put back.\n");
    return 2;
  }

  // ---------- the check ----------
  if (cmd.empty()) {
    string self = argv[0];
    size_t sl = self.rfind('/');
    string truthBin = (sl == string::npos ? string(".") : self.substr(0, sl)) + "/rabadon-truth";
    string o;
    if (run("'" + truthBin + "' '" + dir + "' --json", "/", &o, 120) == 0) {
      size_t k = o.find("\"run\":\"");
      if (k != string::npos) {
        size_t s = k + 7, e = o.find('"', s);
        if (e != string::npos) cmd = o.substr(s, e - s);
      }
    }
  }
  if (cmd.empty()) {
    printf("\n  verdict: NO_TRUTH\n");
    printf("    nothing in this repository can be run that could go red, so nothing\n");
    printf("    can be proved about this change here.\n");
    return 2;
  }
  printf("  check : %s\n", cmd.c_str());

  // ---------- three trees ----------
  char tmpl[] = "/tmp/rabadon-prove-XXXXXX";
  const char* work = mkdtemp(tmpl);
  if (!work) { perror("rabadon prove: mkdtemp"); return 3; }
  const string post = string(work) + "/post";
  const string counter = string(work) + "/counter";
  const string pre = string(work) + "/pre";

  // A stale derived artifact is how twelve runs produced seven wrong REDs once
  // already: a .pyc newer than its source keeps executing the old code. They go.
  auto clone = [&](const string& dst) {
    string o;
    run("cp -R '" + dir + "' '" + dst + "'", "/", &o, 300);
    run("rm -rf .git .rabadon; find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null; "
        "find . -name '*.pyc' -delete 2>/dev/null; true", dst, &o, 120);
  };
  clone(post);

  const string spFile = string(work) + "/source-revert.patch";
  const string fpFile = string(work) + "/full-revert.patch";
  write_file(spFile, sourcePatch);
  write_file(fpFile, fullPatch);

  // Which side is the working tree on? Asked, never assumed: a reverse-apply
  // that only half-lands would silently make the counterfactual meaningless.
  string o;
  const bool treeIsPost =
      run("patch -R -p1 --dry-run --forward -s < '" + fpFile + "'", post, &o, 120) == 0;
  if (!treeIsPost) {
    if (run("patch -p1 --dry-run --forward -s < '" + fpFile + "'", post, &o, 120) != 0) {
      printf("\n  verdict: UNPROBED\n    this diff does not apply to %s in either direction.\n", dir.c_str());
      if (!keep) run("rm -rf '" + string(work) + "'", "/", &o, 60);
      return 3;
    }
    if (run("patch -p1 --forward -s < '" + fpFile + "'", post, &o, 120) != 0) {
      printf("\n  verdict: UNPROBED\n    the change would not apply cleanly.\n");
      if (!keep) run("rm -rf '" + string(work) + "'", "/", &o, 60);
      return 3;
    }
  }

  // counter and pre are cut from POST, not from the original tree, so all three
  // differ only by the patch levels below and never by anything the clone did.
  run("cp -R '" + post + "' '" + counter + "'", "/", &o, 300);
  run("cp -R '" + post + "' '" + pre + "'", "/", &o, 300);

  if (run("patch -R -p1 --forward -s < '" + spFile + "'", counter, &o, 120) != 0) {
    printf("\n  verdict: UNPROBED\n    the source half would not come back out cleanly.\n");
    if (!keep) run("rm -rf '" + string(work) + "'", "/", &o, 60);
    return 3;
  }
  run("patch -R -p1 --forward -s < '" + fpFile + "'", pre, &o, 120);

  // ---------- run ----------
  auto sample = [&](const string& tree, const char* label) {
    vector<int> codes;
    for (int i = 0; i < samples; i++) {
      string out;
      int rc = run(cmd, tree, &out, timeoutSec);
      codes.push_back(rc);
      write_file(string(work) + "/" + label + "." + std::to_string(i) + ".log", out);
    }
    return codes;
  };
  auto agree = [](const vector<int>& c) {
    for (size_t i = 1; i < c.size(); i++) if ((c[i] == 0) != (c[0] == 0)) return false;
    return true;
  };

  printf("\n  running the check on three trees, %d sample(s) each...\n", samples);
  vector<int> cPost = sample(post, "post");
  vector<int> cCounter = sample(counter, "counter");
  vector<int> cPre = sample(pre, "pre");

  auto show = [](const char* n, const vector<int>& c) {
    printf("    %-8s", n);
    for (int x : c) printf(" exit=%d", x);
    printf("%s\n", c[0] == 0 ? "   GREEN" : "   RED");
  };
  printf("\n");
  show("post", cPost); show("counter", cCounter); show("pre", cPre);

  Result r;
  if (!agree(cPost) || !agree(cCounter) || !agree(cPre)) {
    r.verdict = "FLAKY_CHECK";
    r.why = "the samples disagreed. A coin flip is not a verdict, so this is neither proof nor accusation.";
    r.exitCode = 4;
  } else if (cPost[0] != 0) {
    r.verdict = "NO_COUNTERFACTUAL";
    r.why = "the check is RED with the change applied, so there is no green for the change to explain.";
    r.exitCode = 2;
  } else if (cCounter[0] != 0) {
    if (!testsEdited.empty()) {
      r.verdict = "PROVEN_WITH_TEST_EDIT";
      r.why = "putting the source back turns the check red — but the change also rewrote an existing "
              "test, so part of the test that distinguishes it was written by the same change.";
    } else {
      r.verdict = "PROVEN";
      r.why = "putting the source back turns the check red. The green is caused by this change.";
    }
    r.exitCode = 0;
    if (cPre[0] != 0)
      r.why += " (the pre-change tree is also red, so the check was already failing before any of this.)";
  } else if (nTest > 0) {
    r.verdict = "TEST_PASSES_BOTH_WAYS";
    r.why = "the change ships tests, and those tests pass with the source put back. The change's own "
            "tests do not test the change.";
    r.exitCode = 1;
  } else {
    r.verdict = "NO_COUNTERFACTUAL";
    r.why = "the check stays green with the source put back, and the change adds no test. Either it is "
            "not covered, or it changed nothing the suite can see. These are not told apart here.";
    r.exitCode = 2;
  }

  printf("\n  verdict: %s\n    %s\n", r.verdict.c_str(), r.why.c_str());
  if (nAssumed)
    printf("    %d file(s) were called source by elimination rather than by a rule that names them.\n", nAssumed);
  if (!testsEdited.empty()) {
    printf("    existing tests rewritten by this change:\n");
    for (const auto& t : testsEdited) printf("      %s\n", t.c_str());
  }
  if (keep) printf("\n  trees kept: %s\n", work);
  else run("rm -rf '" + string(work) + "'", "/", &o, 60);
  return r.exitCode;
}
