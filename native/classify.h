// classify.h — is this path source, test, harness, or neither. (C++17)
//
// WHY THIS FILE EXISTS
// Two callers need the same answer and each had grown its own copy: truth.cpp
// decides what to LOCK, repair.cpp decides what a proposal may not TOUCH. A
// wrong answer here is silent — if a test file is read as source, a repair is
// allowed to edit the very thing that judges it, and the green it buys means
// nothing. A false green is worse than a false red, and two copies of a
// heuristic drift until one of them is wrong.
//
// Every rule below came out of a repository that broke it, and the comments say
// which one. That history is the value here — the rules read like arbitrary
// string matching until you know redis, date-fns and discourse are in them.
//
// classify() returns the RULE that decided, not just the verdict. A caller that
// is about to revert a file on the strength of a fallback guess has to be able
// to say so in its receipt, because "I assumed this was source" and "I know this
// is source" are different claims and only one of them is a proof.
#ifndef RB_CLASSIFY_H
#define RB_CLASSIFY_H

#include <cstring>
#include <string>
#include <vector>

namespace rbclass {

using std::string;

enum Kind {
  SOURCE,    // code a behaviour change lives in
  TEST,      // the suite. Locked by repair, never editable by a proposal.
  HARNESS,   // decides WHICH tests run (package.json, pytest.ini, jest.config)
  DOC,       // prose
  ARTIFACT,  // binary or generated
  UNKNOWN,   // classified by nothing; a caller must not silently assume
};

struct Verdict {
  Kind kind = UNKNOWN;
  string rule;        // which rule decided, verbatim, for the receipt
  bool assumed = false;  // true when a fallback decided rather than a convention
};

inline const char* kind_name(Kind k) {
  switch (k) {
    case SOURCE: return "SOURCE";
    case TEST: return "TEST";
    case HARNESS: return "HARNESS";
    case DOC: return "DOC";
    case ARTIFACT: return "ARTIFACT";
    default: return "UNKNOWN";
  }
}

// ---------- pieces ----------

inline string ext_of(const string& n) {
  size_t d = n.rfind('.');
  return d == string::npos ? string() : n.substr(d);
}

inline string base_of(const string& rel) {
  size_t s = rel.rfind('/');
  return s == string::npos ? rel : rel.substr(s + 1);
}

inline string dir_of(const string& rel) {
  size_t s = rel.rfind('/');
  return s == string::npos ? string() : rel.substr(0, s);
}

// Directories no walk should enter. Union of the two lists that existed: the
// truth.cpp one also skipped every dotted directory, the repair.cpp one named
// .tox/.pytest_cache/.mypy_cache/.gradle explicitly and did not skip dotfiles
// wholesale. Keeping BOTH behaviours: named junk, plus any dotted directory.
inline bool skip_dir(const string& n) {
  static const char* junk[] = {
      "node_modules", ".git", ".rabadon", "build", "dist", ".next", "venv",
      ".venv", "env", "__pycache__", "target", "vendor", "Pods", "DerivedData",
      "coverage", ".cache", ".tox", ".pytest_cache", ".mypy_cache",
      "site-packages", ".gradle"};
  for (const char* j : junk) if (n == j) return true;
  return n.size() > 1 && n[0] == '.';
}

inline bool is_artifact_ext(const string& e) {
  static const char* a[] = {
      ".lock", ".min.js", ".map", ".so", ".dylib", ".dll", ".a", ".o", ".class",
      ".jar", ".wasm", ".pyc", ".pyo", ".rdb", ".zip", ".gz", ".tgz", ".tar",
      ".bz2", ".xz", ".7z", ".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf",
      ".mp4", ".mov", ".mp3", ".wav", ".woff", ".woff2", ".ttf", ".eot", ".otf"};
  for (const char* x : a) if (e == x) return true;
  return false;
}

inline bool is_doc_ext(const string& e) {
  static const char* d[] = {".md", ".markdown", ".rst", ".adoc", ".txt"};
  for (const char* x : d) if (e == x) return true;
  return false;
}

inline bool harness_prefix(const string& n, const char* p) {
  size_t k = strlen(p);
  return n.size() >= k && n.compare(0, k, p) == 0;
}

// `relDir` is the directory holding the file, "" at the project root.
inline bool harness_file(const string& name, const string& relDir) {
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
  // pytest and node families were each proved by running the real binary against
  // a real suite that really went green for the cheat. These were not: maven on
  // this machine cannot resolve surefire offline, and there is no go toolchain
  // on it at all. The entries are here because the mechanism is the same one the
  // proved families use, which is an argument, not a measurement.
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

// Is this a file the suite could plausibly be made of at all? Runs for EVERY
// file whatever language it is written in. It used to sit behind a language
// check, which meant the location rule below never ran for a language nobody
// had listed: redis locked 255 files that way and not one of them was a redis
// test — they were C headers named test_hooks.h from deps/jemalloc, a vendored
// dependency, while the 229 .tcl files that ARE the suite fell through.
inline bool can_be_a_check(const string& name, const string& e) {
  (void)name;
  if (is_artifact_ext(e)) return false;
  if (is_doc_ext(e)) return false;
  return true;
}

// The name/location conventions that make a file part of the suite. `rule` is
// filled with the one that fired.
inline bool looks_test(const string& rel, const string& name, const string& e,
                       string* rule) {
  auto hit = [&](const char* r) { if (rule) *rule = r; return true; };
  if (name.rfind("test_", 0) == 0) return hit("name:test_*");
  if (name.find("_test.") != string::npos) return hit("name:*_test.*");
  if (name.find(".test.") != string::npos) return hit("name:*.test.*");
  if (name.find(".spec.") != string::npos) return hit("name:*.spec.*");
  // `_spec.` is rspec's whole convention and it was not here. discourse names
  // 3373 files that way and matched on neither the name nor the path, because
  // `spec/` was not a test directory either.
  if (name.find("_spec.") != string::npos) return hit("name:*_spec.*");
  if (rel.rfind("test/", 0) == 0 || rel.find("/test/") != string::npos)
    return hit("path:test/");
  if (rel.rfind("tests/", 0) == 0 || rel.find("/tests/") != string::npos)
    return hit("path:tests/");
  if (rel.rfind("spec/", 0) == 0 || rel.find("/spec/") != string::npos)
    return hit("path:spec/");
  if (rel.find("__tests__/") != string::npos) return hit("path:__tests__/");
  if (rel.find("__test__/") != string::npos) return hit("path:__test__/");
  (void)e;
  return false;
}

// The stem fallback, kept separate because it is a GUESS and callers have to be
// able to say so. date-fns names every one of its 253 test files `test.ts` and
// puts it beside the function it tests (src/addDays/test.ts): no pattern above
// sees a single one. Comparing the whole stem rather than searching for the
// word is what keeps `contest.ts` and a directory called `latest` out.
//
// `tests` is deliberately NOT here. A module called tests.py is ordinarily
// source, and jinja's is: treating it as a suite would refuse a fix to the
// language's own test functions as if it were tampering with a suite.
inline bool stem_is_test_candidate(const string& name, const string& e) {
  const string stem = e.empty() ? name : name.substr(0, name.size() - e.size());
  return stem == "test" || stem == "spec";
}

// Files that hold source AND suite in the same bytes. Reverting the source half
// of one of these takes the test with it, so a counterfactual built on it means
// nothing — the caller must refuse rather than guess.
inline bool may_be_mixed(const string& e) {
  return e == ".rs" ||          // #[cfg(test)] mod tests
         e == ".py";            // doctests live in the docstring of the function
}

// ---------- the one answer ----------

inline Verdict classify(const string& rel) {
  Verdict v;
  const string name = base_of(rel);
  const string e = ext_of(name);
  const string d = dir_of(rel);

  if (harness_file(name, d)) { v.kind = HARNESS; v.rule = "harness:" + name; return v; }
  if (is_artifact_ext(e))    { v.kind = ARTIFACT; v.rule = "ext:artifact"; return v; }
  if (is_doc_ext(e))         { v.kind = DOC; v.rule = "ext:document"; return v; }

  string rule;
  if (looks_test(rel, name, e, &rule)) { v.kind = TEST; v.rule = rule; return v; }
  if (stem_is_test_candidate(name, e)) {
    v.kind = TEST; v.rule = "stem:test-or-spec"; v.assumed = true; return v;
  }
  v.kind = SOURCE;
  v.rule = "default:not-a-test";
  v.assumed = true;   // nothing POSITIVELY said source; it is what is left over
  return v;
}

} // namespace rbclass

#endif
