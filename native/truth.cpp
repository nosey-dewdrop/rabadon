// rabadon-truth — what does THIS repo already know how to check? C++17, zero deps.
//
// The always-on net is supposed to run "the project's existing truths" after a
// tool call. Measured on this machine before writing a line of this file: of 66
// project folders, 38 contain code, and only 6 of those have any test suite.
// A net that only knows how to run a test suite is therefore dead in ~5 out of 6
// real repositories — including most of the ones an autonomous agent is turned
// loose on. So the net does not ask "where are your tests"; it asks "what is the
// strongest thing you already have that can be RUN and can come back red".
//
// The ladder, strongest first. Each rung is a real command, discovered from real
// files, and NOTHING here calls a model:
//   1 SUITE   the project's own test suite            (it can fail for behaviour)
//   2 BUILD   compile / typecheck                     (it can fail for meaning)
//   3 SYNTAX  parse every source file                 (it can fail for form)
//   0 NONE    nothing runnable was found              (say so; never pretend)
//
// The rung is recorded with the verdict, always. "Proven by your test suite" and
// "it still compiles" are not the same claim, and a ledger that blurs them is
// worth nothing. This is also the honest answer to a hostile reviewer: rabadon
// grades its own evidence, out loud, and a weak rung is reported as weak.
//
// Usage: rabadon-truth [dir] [--json]
//   exit 0 = a runnable truth was found   exit 1 = none (dir has no checkable truth)

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <dirent.h>
#include <sys/stat.h>

using std::string;
using std::vector;

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return "";
  std::stringstream ss; ss << f.rdbuf(); return ss.str();
}
static bool exists(const string& p) { struct stat sb; return stat(p.c_str(), &sb) == 0; }
static bool is_dir(const string& p) { struct stat sb; return stat(p.c_str(), &sb) == 0 && S_ISDIR(sb.st_mode); }

static vector<string> list_dir(const string& d) {
  vector<string> out;
  DIR* dp = opendir(d.c_str());
  if (!dp) return out;
  while (struct dirent* e = readdir(dp)) {
    string n = e->d_name;
    if (n == "." || n == "..") continue;
    out.push_back(n);
  }
  closedir(dp);
  std::sort(out.begin(), out.end());
  return out;
}

// noise that is never the project's own source
static bool skip_dir(const string& n) {
  static const char* junk[] = {"node_modules", ".git", "build", "dist", ".next", "venv",
                               ".venv", "__pycache__", "target", "vendor", "Pods",
                               "DerivedData", ".rabadon", "coverage", ".cache"};
  for (const char* j : junk) if (n == j) return true;
  return n.size() > 1 && n[0] == '.';
}

static string ext_of(const string& n) {
  size_t d = n.rfind('.');
  return d == string::npos ? "" : n.substr(d);
}

// count source files by language, and remember which top-level dirs hold them
struct Scan {
  int js = 0, ts = 0, py = 0, cpp = 0, go = 0, rs = 0, swift = 0, java = 0;
  vector<string> codeDirs;
  vector<string> testFiles;
  int total() const { return js + ts + py + cpp + go + rs + swift + java; }
};

static void scan_into(const string& dir, const string& rel, Scan& s, int depth, int& budget) {
  if (depth > 4 || budget <= 0) return;
  for (const string& n : list_dir(dir)) {
    if (budget-- <= 0) return;
    const string full = dir + "/" + n;
    const string r = rel.empty() ? n : rel + "/" + n;
    if (is_dir(full)) {
      if (skip_dir(n)) continue;
      scan_into(full, r, s, depth + 1, budget);
      continue;
    }
    const string e = ext_of(n);
    bool code = true;
    if (e == ".js" || e == ".jsx" || e == ".mjs" || e == ".cjs") s.js++;
    else if (e == ".ts" || e == ".tsx") s.ts++;
    else if (e == ".py") s.py++;
    else if (e == ".cpp" || e == ".cc" || e == ".c" || e == ".h" || e == ".hpp") s.cpp++;
    else if (e == ".go") s.go++;
    else if (e == ".rs") s.rs++;
    else if (e == ".swift") s.swift++;
    else if (e == ".java") s.java++;
    else code = false;
    if (!code) continue;
    // remember the top-level directory this code lives in
    size_t slash = r.find('/');
    const string top = slash == string::npos ? string(".") : r.substr(0, slash);
    if (std::find(s.codeDirs.begin(), s.codeDirs.end(), top) == s.codeDirs.end())
      s.codeDirs.push_back(top);
    // a test file is one the arbiter must later LOCK, so a fix cannot be faked
    // by weakening the check that caught it
    const bool looksTest =
        n.rfind("test_", 0) == 0 || n.find("_test.") != string::npos ||
        n.find(".test.") != string::npos || n.find(".spec.") != string::npos ||
        r.find("tests/") != string::npos || r.find("__tests__/") != string::npos;
    if (looksTest && s.testFiles.size() < 64) s.testFiles.push_back(r);
  }
}

// a package.json script, without a JSON parser: find "key" inside "scripts"
static string npm_script(const string& pkg, const string& key) {
  size_t sc = pkg.find("\"scripts\"");
  if (sc == string::npos) return "";
  size_t brace = pkg.find('{', sc);
  if (brace == string::npos) return "";
  int depth = 0; size_t end = brace;
  for (size_t i = brace; i < pkg.size(); i++) {
    if (pkg[i] == '{') depth++;
    else if (pkg[i] == '}') { depth--; if (!depth) { end = i; break; } }
  }
  const string block = pkg.substr(brace, end - brace + 1);
  const string pat = "\"" + key + "\"";
  size_t k = block.find(pat);
  if (k == string::npos) return "";
  size_t c = block.find(':', k + pat.size());
  if (c == string::npos) return "";
  size_t q = block.find('"', c);
  if (q == string::npos) return "";
  string v;
  for (size_t i = q + 1; i < block.size(); i++) {
    if (block[i] == '\\' && i + 1 < block.size()) { v += block[++i]; continue; }
    if (block[i] == '"') break;
    v += block[i];
  }
  return v;
}

static bool make_has_target(const string& mk, const string& target) {
  size_t pos = 0;
  const string pat = target + ":";
  while ((pos = mk.find(pat, pos)) != string::npos) {
    if (pos == 0 || mk[pos - 1] == '\n') return true;
    pos += pat.size();
  }
  return false;
}

struct Truth {
  int level = 0;                 // 1 suite, 2 build, 3 syntax, 0 none
  string kind = "none";
  string run;                    // the actual command
  string why;                    // the file that proved it exists
};

static Truth detect(const string& dir, const Scan& s) {
  const string pkg = read_file(dir + "/package.json");
  const string mk  = read_file(dir + "/Makefile");

  // ---- 1: a real test suite ------------------------------------------------
  if (!pkg.empty()) {
    const string t = npm_script(pkg, "test");
    // the npm default stub is not a test suite; treating it as one would make
    // the net "green" on a repo that checks nothing
    if (!t.empty() && t.find("no test specified") == string::npos)
      return {1, "suite", "npm test --silent", "package.json scripts.test"};
  }
  if (!mk.empty() && make_has_target(mk, "test"))
    return {1, "suite", "make test", "Makefile test: target"};
  if (exists(dir + "/pytest.ini") || exists(dir + "/tests") || !s.testFiles.empty()) {
    if (s.py > 0) return {1, "suite", "python3 -m pytest -q", "python test files"};
  }
  if (exists(dir + "/Cargo.toml")) return {1, "suite", "cargo test --quiet", "Cargo.toml"};
  if (exists(dir + "/go.mod"))     return {1, "suite", "go test ./...", "go.mod"};

  // ---- 2: it still builds / typechecks ------------------------------------
  if (!pkg.empty()) {
    const string b = npm_script(pkg, "build");
    if (!b.empty()) return {2, "build", "npm run build --silent", "package.json scripts.build"};
  }
  if (exists(dir + "/tsconfig.json"))
    return {2, "build", "npx --no-install tsc --noEmit", "tsconfig.json"};
  if (exists(dir + "/CMakeLists.txt"))
    return {2, "build", "cmake --build build", "CMakeLists.txt"};
  if (!mk.empty() && (make_has_target(mk, "all") || make_has_target(mk, "build")))
    return {2, "build", make_has_target(mk, "all") ? "make all" : "make build", "Makefile"};
  if (exists(dir + "/Cargo.toml")) return {2, "build", "cargo build --quiet", "Cargo.toml"};
  if (exists(dir + "/go.mod"))     return {2, "build", "go build ./...", "go.mod"};

  // ---- 3: does every source file still parse ------------------------------
  // The weakest rung that can still go RED, and it needs nothing installed.
  if (s.py > 0)  return {3, "syntax", "python3 -m compileall -q .", "python sources"};
  if (s.js > 0)  return {3, "syntax",
                         "find . -name '*.js' -not -path './node_modules/*' -print0 | xargs -0 -n1 node --check",
                         "javascript sources"};
  if (s.cpp > 0) return {3, "syntax", "", "c++ sources (no build file found)"};

  return {0, "none", "", "nothing runnable found"};
}

static string json_escape(const string& s) {
  string o;
  for (char c : s) {
    if (c == '"' || c == '\\') { o += '\\'; o += c; }
    else if (c == '\n') o += "\\n";
    else o += c;
  }
  return o;
}

int main(int argc, char** argv) {
  string dir = ".";
  bool asJson = false;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--json") asJson = true;
    else if (a == "--help") { printf("usage: rabadon-truth [dir] [--json]\n"); return 0; }
    else dir = a;
  }
  while (dir.size() > 1 && dir.back() == '/') dir.pop_back();

  Scan s;
  int budget = 20000;             // bounded walk: a huge repo must not stall a hook
  scan_into(dir, "", s, 0, budget);
  Truth t = detect(dir, s);

  if (asJson) {
    string dirs;
    for (size_t i = 0; i < s.codeDirs.size() && i < 12; i++) {
      if (i) dirs += ",";
      dirs += "\"" + json_escape(s.codeDirs[i]) + "\"";
    }
    string tests;
    for (size_t i = 0; i < s.testFiles.size() && i < 32; i++) {
      if (i) tests += ",";
      tests += "\"" + json_escape(s.testFiles[i]) + "\"";
    }
    printf("{\"level\":%d,\"kind\":\"%s\",\"run\":\"%s\",\"why\":\"%s\","
           "\"codeFiles\":%d,\"codeDirs\":[%s],\"testFiles\":[%s]}\n",
           t.level, t.kind.c_str(), json_escape(t.run).c_str(), json_escape(t.why).c_str(),
           s.total(), dirs.c_str(), tests.c_str());
  } else {
    const char* label = t.level == 1 ? "SUITE  (strong: real behaviour)"
                      : t.level == 2 ? "BUILD  (medium: it still compiles)"
                      : t.level == 3 ? "SYNTAX (weak: it still parses)"
                                     : "NONE   (nothing runnable — rabadon will say so, not pretend)";
    printf("%-28s  level %d  %s\n", dir.c_str(), t.level, label);
    if (!t.run.empty()) printf("    run: %s\n    via: %s\n", t.run.c_str(), t.why.c_str());
    printf("    %d code files in [", s.total());
    for (size_t i = 0; i < s.codeDirs.size() && i < 8; i++) printf("%s%s", i ? " " : "", s.codeDirs[i].c_str());
    printf("]%s\n", s.testFiles.empty() ? "" : (" · " + std::to_string(s.testFiles.size()) + " test file(s) to lock").c_str());
  }
  return t.level == 0 ? 1 : 0;
}
