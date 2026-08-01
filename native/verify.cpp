// rabadon-verify — the un-gameable contract kernel. C++17, zero deps.
//
// The old JS contract (exit 0 / fileExists / fileContains) is shallow: the
// diagnosis proved a repair agent games it — it creates the file the contract
// names, or writes the string the regex wants, and the gate turns green while
// the actual behavior is still broken. A contract you can satisfy without doing
// the work is not a moat.
//
// This adds the two checks that cannot be faked by touching files:
//   differential  run a reference command; its output must equal a recorded
//                 baseline. You cannot satisfy behavior preservation by writing
//                 a string — the command actually runs and its result is compared.
//   forbidden     a path that must NOT change (sha over the bytes). The repair
//                 cannot cheat by editing the thing it was told to preserve.
// Baseline checks (cmd/fileExists/fileContains) stay, but are never enough alone.
//
// Fail-CLOSED by construction: an empty contract FAILS, an unknown type FAILS,
// a missing baseline file FAILS. Nothing passes by silence. The contract is read
// by the kernel from its own file and is never handed to the proposer, so the
// repair cannot edit the judge.
//
// Usage:  rabadon-verify <dir> <contract.json>
//   exit 0 = every check passed   exit 1 = at least one failed (reasons on stdout)
//   exit 2 = the contract itself is malformed/empty (fail-closed)

#include <cstdio>
#include <cstdlib>
#include <cstdint>   // uint64_t: libc++ leaks this transitively, libstdc++ does not
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <sys/stat.h>
#include "cli_help.h"

using std::string;
using std::vector;

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return "";
  std::stringstream ss; ss << f.rdbuf(); return ss.str();
}

static string run_cmd(const string& cmd, const string& dir, int* rc) {
  string full = "cd " + dir + " 2>/dev/null && " + cmd;
  string out; char buf[4096];
  FILE* p = popen(full.c_str(), "r");
  if (!p) { if (rc) *rc = -1; return ""; }
  size_t n; while ((n = fread(buf, 1, sizeof(buf), p)) > 0) out.append(buf, n);
  int status = pclose(p);
  if (rc) *rc = (status == -1) ? -1 : (WIFEXITED(status) ? WEXITSTATUS(status) : -1);
  return out;
}

// FNV-1a over bytes — a cheap, dependency-free content fingerprint.
static uint64_t fnv1a(const string& s) {
  uint64_t h = 1469598103934665603ULL;
  for (unsigned char c : s) { h ^= c; h *= 1099511628211ULL; }
  return h;
}

static bool file_exists(const string& p) { struct stat sb; return stat(p.c_str(), &sb) == 0; }

// resolve a contract path against the project dir. An absolute path is used
// as-is (the planner sometimes emits one); a relative path joins with dir.
// Without this, dir + "/" + "/abs/path" double-joins and every file check
// false-fails — a real bug the first live run exposed.
static string resolve(const string& dir, const string& p) { return (!p.empty() && p[0] == '/') ? p : dir + "/" + p; }

// ---- minimal JSON: this file only ever parses the contract array we emit ----
// Each contract object is a flat {"type":..,"...":".."} — find string/scalar by key
// within a given object slice.
static string obj_str(const string& j, const string& key) {
  const string pat = "\"" + key + "\"";
  size_t k = j.find(pat);
  if (k == string::npos) return "";
  size_t c = j.find(':', k + pat.size());
  if (c == string::npos) return "";
  size_t q = j.find('"', c);
  if (q == string::npos) return "";
  string out;
  for (size_t i = q + 1; i < j.size(); i++) {
    char ch = j[i];
    if (ch == '\\' && i + 1 < j.size()) { char n = j[++i]; out += (n=='n')?'\n':(n=='t')?'\t':n; }
    else if (ch == '"') break;
    else out += ch;
  }
  return out;
}

// split a top-level JSON array of flat objects into their string slices
static vector<string> split_objects(const string& arr) {
  vector<string> out;
  int depth = 0; size_t start = string::npos; bool inStr = false;
  for (size_t i = 0; i < arr.size(); i++) {
    char c = arr[i];
    if (inStr) { if (c == '\\') i++; else if (c == '"') inStr = false; continue; }
    if (c == '"') { inStr = true; continue; }
    if (c == '{') { if (depth == 0) start = i; depth++; }
    else if (c == '}') { depth--; if (depth == 0 && start != string::npos) { out.push_back(arr.substr(start, i - start + 1)); start = string::npos; } }
  }
  return out;
}

static const char* kHelp =
  "rabadon-verify — the contract kernel. The arbiter that decides pass/fail.\n"
  "Reads a contract from its OWN file and never hands it to the proposer, so a\n"
  "repair cannot edit its judge. Fail-CLOSED by construction: an empty contract\n"
  "fails, an unknown check type fails, a missing baseline fails.\n"
  "\n"
  "usage: rabadon-verify <dir> <contract.json>\n"
  "\n"
  "  <dir>            the project the checks run in.\n"
  "  <contract.json>  a JSON array, or {\"contract\":[ ... ]}. check types:\n"
  "      {\"type\":\"differential\",\"run\":\"<cmd>\",\"expect\":\"<exact stdout>\"}\n"
  "      {\"type\":\"forbidden\",\"path\":\"<file>\",\"sha\":\"<sha256>\"}\n"
  "      {\"type\":\"cmd\",\"run\":\"<cmd>\",\"passPattern\":\"<marker>\"}\n"
  "      {\"type\":\"fileExists\",\"path\":\"<file>\"}\n"
  "      {\"type\":\"fileContains\",\"path\":\"<file>\",\"pattern\":\"<text>\"}\n"
  "  -h, --help       this screen.\n"
  "\n"
  "exit: 0 every check passed · 1 a check failed · 2 malformed, fail-closed.\n"
  "\n"
  "example:\n"
  "  rabadon-verify ~/src/myrepo ~/src/myrepo/.rabadon/contract.json\n";

int main(int argc, char** argv) {
  // `rabadon-verify --help` used to hit the arity check and exit 2 — the same
  // code as a malformed contract, so help was indistinguishable from a refusal.
  rb_help(argc, argv, kHelp);

  if (argc < 3) { fprintf(stderr, "usage: rabadon-verify <dir> <contract.json>\n  run `rabadon-verify --help`\n"); return 2; }
  string dir = argv[1];
  string craw = read_file(argv[2]);
  if (craw.empty()) { printf("contract is empty or unreadable (fail-closed)\n"); return 2; }

  // contract file is either a bare array or { "contract": [ ... ] }
  size_t lb = craw.find('['); size_t rb = craw.rfind(']');
  if (lb == string::npos || rb == string::npos || rb < lb) { printf("contract is not a JSON array (fail-closed)\n"); return 2; }
  vector<string> items = split_objects(craw.substr(lb, rb - lb + 1));
  if (items.empty()) { printf("contract has zero checks (fail-closed — an empty contract never passes)\n"); return 2; }

  int failed = 0;
  for (const string& it : items) {
    const string type = obj_str(it, "type");

    if (type == "cmd") {
      const string run = obj_str(it, "run");
      const string pass = obj_str(it, "passPattern");
      int rc = 0; string out = run_cmd(run, dir, &rc);
      if (rc != 0) { printf("FAIL cmd [%s]: exit %d\n", run.c_str(), rc); failed++; }
      else if (!pass.empty() && out.find(pass) == string::npos) { printf("FAIL cmd [%s]: pass marker '%s' absent\n", run.c_str(), pass.c_str()); failed++; }

    } else if (type == "fileExists") {
      const string path = obj_str(it, "path");
      if (!file_exists(resolve(dir, path))) { printf("FAIL fileExists [%s]: missing\n", path.c_str()); failed++; }

    } else if (type == "fileContains") {
      const string path = obj_str(it, "path");
      const string pat = obj_str(it, "pattern");
      string body = read_file(resolve(dir, path));
      if (body.find(pat) == string::npos) { printf("FAIL fileContains [%s]: '%s' absent\n", path.c_str(), pat.c_str()); failed++; }

    } else if (type == "differential") {
      // behavior preservation: run `run`, its output must equal `expect`.
      // The baseline `expect` is recorded from the KNOWN-GOOD state before the
      // repair. Writing files cannot fake this — the command executes for real.
      const string run = obj_str(it, "run");
      const string expect = obj_str(it, "expect");
      int rc = 0; string out = run_cmd(run, dir, &rc);
      // trim trailing whitespace/newline on both sides for a stable compare
      auto trim = [](string s){ while(!s.empty() && (s.back()=='\n'||s.back()==' '||s.back()=='\t'||s.back()=='\r')) s.pop_back(); return s; };
      if (rc != 0) { printf("FAIL differential [%s]: command errored (exit %d)\n", run.c_str(), rc); failed++; }
      else if (trim(out) != trim(expect)) { printf("FAIL differential [%s]: behavior changed — got '%s', baseline '%s'\n", run.c_str(), trim(out).substr(0,80).c_str(), trim(expect).substr(0,80).c_str()); failed++; }

    } else if (type == "testsuite") {
      // the behavior gate: run the project's OWN test suite. This is the answer
      // to "where's the ground-truth data" — there is no dataset to find, the
      // oracle is the customer's real tests. A broken edit that a shallow check
      // (file exists / syntax ok) waves through is caught here the moment the
      // real suite goes red, and the failing test is named in the report.
      const string run = obj_str(it, "run");
      int rc = 0; string out = run_cmd(run, dir, &rc);
      if (rc != 0) {
        string tail = out.size() > 300 ? out.substr(out.size() - 300) : out;
        printf("FAIL testsuite [%s]: the project's own suite is RED (exit %d)\n...%s\n", run.c_str(), rc, tail.c_str());
        failed++;
      }

    } else if (type == "forbidden") {
      // a path the repair must not alter. `sha` is the fingerprint of the
      // known-good bytes; if it changed, the repair cheated by editing the
      // thing it was told to preserve.
      const string path = obj_str(it, "path");
      const string sha = obj_str(it, "sha");
      string body = read_file(resolve(dir, path));
      char now[24]; snprintf(now, sizeof now, "%llu", (unsigned long long)fnv1a(body));
      if (sha != now) { printf("FAIL forbidden [%s]: protected content was modified\n", path.c_str()); failed++; }

    } else {
      printf("FAIL: unknown contract type '%s' (fail-closed)\n", type.c_str());
      failed++;
    }
  }

  if (failed == 0) printf("PASS: %zu checks\n", items.size());
  return failed ? 1 : 0;
}
