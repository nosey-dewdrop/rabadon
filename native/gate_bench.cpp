// gate_bench — how long it takes to JUDGE one command, measured in process.
//
// The site carried "42.0µs to judge one command" and named a file that did not
// exist. There was no micro benchmark in this repository at all: the only real
// measurement was native/bench.py, which times the whole hook — fork, exec,
// read the event off stdin, load state, judge, write the ledger line, exit —
// and answers a different question (3.35ms native against 108ms for the node
// gate it replaced). Both numbers are worth having and they are not the same
// number, so this file measures the one that was being claimed.
//
// What is timed is rbrules::judge_command, the single call that holds the whole
// verdict: the project's deny rules first, then the three laws compiled into
// the binary underneath them. That is the same call the gate makes, and
// native/gate_bench.sh proves it by replaying the precision fixture through the
// real rabadon-gate binary and refusing to print a number unless all 34
// verdicts match. A fast judge that answers differently from the shipped one is
// not a measurement of anything.
//
// Nothing here is warmed up out of honesty: judge_command resolves the cwd
// through realpath and the push law reads .git/HEAD and walks refs, so it pays
// for filesystem work on every call. Those are costs the gate really pays, so
// they are inside the number rather than optimised out of the benchmark.

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>
#include "rules.h"

using std::string;

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

// the fixture is fed in base64 so a command carrying a tab, a quote or a
// newline arrives byte-identical to what the gate is handed
static string b64_decode(const string& in) {
  static const string T = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::vector<int> rev(256, -1);
  for (int i = 0; i < 64; i++) rev[(unsigned char)T[i]] = i;
  string out;
  int val = 0, bits = -8;
  for (unsigned char c : in) {
    if (rev[c] == -1) continue;
    val = (val << 6) + rev[c];
    bits += 6;
    if (bits >= 0) { out += (char)((val >> bits) & 0xFF); bits -= 8; }
  }
  return out;
}

struct Case { string id, guard, cmd; };

int main(int argc, char** argv) {
  string root;
  int runs = 200;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--runs" && i + 1 < argc) runs = atoi(argv[++i]);
    else root = a;
  }
  if (root.empty()) {
    fprintf(stderr, "usage: gate_bench <fixture-root> [--runs N] < cases.tsv\n"
                    "  cases.tsv: id<TAB>guardname<TAB>base64(command)\n");
    return 2;
  }
  if (runs < 1) runs = 1;

  std::vector<Case> cases;
  {
    string line;
    while (std::getline(std::cin, line)) {
      if (line.empty()) continue;
      size_t a = line.find('\t');
      if (a == string::npos) continue;
      size_t b = line.find('\t', a + 1);
      if (b == string::npos) continue;
      cases.push_back({line.substr(0, a), line.substr(a + 1, b - a - 1),
                       b64_decode(line.substr(b + 1))});
    }
  }
  if (cases.empty()) { fprintf(stderr, "gate_bench: no cases on stdin\n"); return 2; }

  std::map<string, string> guards;   // guard dir name -> guard.json body ("" = none)
  for (const Case& c : cases)
    if (!guards.count(c.guard))
      guards[c.guard] = read_file(root + "/" + c.guard + "/.rabadon/guard.json");

  std::vector<double> perCaseNs;
  perCaseNs.reserve(cases.size());
  printf("# id\tverdict\trule\tmedian_ns\truns\n");
  for (const Case& c : cases) {
    const string& guard = guards[c.guard];
    const string cwd = root + "/" + c.guard;
    rbrules::Verdict v;
    std::vector<double> samples;
    samples.reserve((size_t)runs);
    for (int i = 0; i < runs; i++) {
      auto t0 = std::chrono::steady_clock::now();
      v = rbrules::judge_command(guard, c.cmd, cwd);
      auto t1 = std::chrono::steady_clock::now();
      samples.push_back((double)std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count());
    }
    std::sort(samples.begin(), samples.end());
    const double med = samples[samples.size() / 2];
    perCaseNs.push_back(med);
    printf("%s\t%s\t%s\t%.0f\t%d\n", c.id.c_str(), v.refused ? "BLOCK" : "ALLOW",
           v.refused ? v.id.c_str() : "-", med, runs);
  }

  std::vector<double> s = perCaseNs;
  std::sort(s.begin(), s.end());
  const double med = s[s.size() / 2];
  const double p95 = s[(size_t)((double)(s.size() - 1) * 0.95)];
  const double lo = s.front(), hi = s.back();
  double sum = 0; for (double x : s) sum += x;
  printf("# cases\t%zu\n", s.size());
  printf("# median_us\t%.1f\n", med / 1000.0);
  printf("# p95_us\t%.1f\n", p95 / 1000.0);
  printf("# min_us\t%.1f\n", lo / 1000.0);
  printf("# max_us\t%.1f\n", hi / 1000.0);
  printf("# mean_us\t%.1f\n", (sum / (double)s.size()) / 1000.0);
  return 0;
}
