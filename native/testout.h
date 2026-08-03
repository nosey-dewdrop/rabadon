// testout.h — reading what a test runner actually did, not whether it succeeded.
//
// Exit 0 answers "did the command succeed". The gate is asking something else:
// did any test run. A suite filtered down to nothing succeeds loudly, and that
// is how a push went out over a red suite on 3 August — one command that
// matched no tests refreshed the green stamp.
//
// Both of these strings were produced by running the tool, not quoted from
// memory, which matters because the shape decided the implementation:
//
//   go test -run TestNothingMatchesThis ./...   ok  vac  0.142s [no tests to run]   exit 0
//   pytest, in a directory with nothing in it   no tests ran in 0.00s
//
// go is the reason a substring search is the wrong answer. `go test ./...`
// prints `?  pkg  [no test files]` for every package that has no tests, right
// beside the real green lines, on a run that is completely healthy. Refusing
// that push forever costs more than the hole it closes. So a marker only counts
// when nothing else in the output shows a test running.
#pragma once
#include <string>
#include <sstream>
#include <regex>

namespace rbtestout {

using std::string;

// The whole run executed zero tests. Give this the FULL output — deciding it on
// a tail can cut away the evidence that something ran and turn a green run into
// a refusal.
inline bool ran_no_tests(const string& out) {
  static const char* marker[] = {
      "no tests to run", "no test files", "no tests ran", "no tests were run",
      "no tests found", "collected 0 items", "ran 0 tests", "executed 0 tests",
      "0 examples,", "0 tests, 0 assertions"};
  bool sawMarker = false;
  for (const char* m : marker) if (out.find(m) != string::npos) { sawMarker = true; break; }
  if (!sawMarker) return false;
  std::istringstream is(out);
  string ln;
  while (std::getline(is, ln)) {
    // this package ran nothing; another one on a later line still might
    if (ln.find("no tests to run") != string::npos || ln.find("no test files") != string::npos)
      continue;
    if (ln.rfind("ok", 0) == 0 || ln.rfind("PASS", 0) == 0) return false;
  }
  // any count above zero: "1 passed", "15 examples", "42 tests", "3 specs"
  try {
    static const std::regex counted(
        "\\b[1-9][0-9]*\\s+(tests?|examples?|assertions?|specs?|cases?|passed|passing)\\b",
        std::regex::ECMAScript | std::regex::icase);
    if (std::regex_search(out, counted)) return false;
  } catch (...) { return false; }  // never refuse a push because a regex threw
  return true;
}

}  // namespace rbtestout
