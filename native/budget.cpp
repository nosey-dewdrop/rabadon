// rabadon-budget — set the deterministic ceiling. Native, C++17, zero deps.
//
// This binary only WRITES the cap; the gate ENFORCES it. On every tool call
// rabadon-gate measures this session's real cumulative usage from the
// transcript (all four token classes) and halts the run BEFORE it burns past
// the cap. rabadon does not show the cost — it stops at it.
//
// Why native (not a line in bin/rabadon.mjs): rabadon's own promise swears the
// engine is C++, not JS — and its own gate refuses .mjs edits to enforce that.
// A new capability lives here, in native/, or it does not ship. The cap is a
// tiny file, but writing it is part of the product, so it is part of the motor.
//
//   rabadon-budget                 show the current cap for the cwd
//   rabadon-budget 200k            token cap (also: 200000, 2m, "500 tokens")
//   rabadon-budget 5usd            dollar cap (also: 5$)
//   rabadon-budget off             clear the cap (also: clear, none)
//   rabadon-budget <spec> <dir>    target a project other than the cwd
//
// The cap lands in <dir>/.rabadon/budget.json — {"tokens":N} | {"usd":X} — the
// exact shape the gate reads with get_double(braw,"tokens"/"usd").

#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

using std::string;

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return "";
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

// basename of a path, no trailing slash
static string base_name(string p) {
  while (p.size() > 1 && p.back() == '/') p.pop_back();
  size_t s = p.rfind('/');
  return s == string::npos ? p : p.substr(s + 1);
}

// digits grouped in threes: 200000 -> "200,000"
static string group(long long n) {
  string s = std::to_string(n < 0 ? -n : n), out;
  int c = 0;
  for (size_t i = s.size(); i > 0; i--) {
    out += s[i - 1];
    if (++c % 3 == 0 && i > 1) out += ',';
  }
  if (n < 0) out += '-';
  string r(out.rbegin(), out.rend());
  return r;
}

// dollars, minimal decimals: 5.0 -> "5", 2.5 -> "2.5", 2.50 -> "2.5"
static string fmt_usd(double v) {
  if (v == std::floor(v) && std::fabs(v) < 1e15) return std::to_string((long long)v);
  char b[64];
  snprintf(b, sizeof b, "%g", v);
  return string(b);
}

// read one numeric field out of a small budget.json ({"tokens":N} | {"usd":X})
static double field(const string& j, const string& key) {
  const string pat = "\"" + key + "\"";
  size_t k = j.find(pat);
  if (k == string::npos) return 0;
  size_t colon = j.find(':', k + pat.size());
  if (colon == string::npos) return 0;
  return atof(j.c_str() + colon + 1);
}

int main(int argc, char** argv) {
  if (argc > 1 && string(argv[1]) == "--version") { printf("rabadon-budget 0.1.0\n"); return 0; }

  char cwdbuf[4096];
  string cwd = getcwd(cwdbuf, sizeof cwdbuf) ? cwdbuf : ".";
  string spec;
  if (argc > 1) spec = argv[1];
  if (argc > 2) cwd = argv[2];          // optional explicit project dir
  while (cwd.size() > 1 && cwd.back() == '/') cwd.pop_back();

  const string rdir = cwd + "/.rabadon";
  const string file = rdir + "/budget.json";
  const string project = base_name(cwd);

  // trim + lowercase the spec
  {
    size_t a = spec.find_first_not_of(" \t\r\n");
    size_t b = spec.find_last_not_of(" \t\r\n");
    spec = (a == string::npos) ? "" : spec.substr(a, b - a + 1);
  }
  string low; for (char c : spec) low += (char)tolower((unsigned char)c);

  // ---- show ----
  if (spec.empty()) {
    const string j = read_file(file);
    long long tok = (long long)field(j, "tokens");
    double usd = field(j, "usd");
    if (j.empty() || (tok <= 0 && usd <= 0)) {
      printf("rabadon budget: no cap set for %s.\n"
             "  set one: `rabadon-budget 200k` (tokens) or `rabadon-budget 5usd` (dollars).\n",
             project.c_str());
      return 0;
    }
    string parts;
    if (tok > 0) parts += group(tok) + " tokens";
    if (usd > 0) { if (!parts.empty()) parts += " and "; parts += "$" + fmt_usd(usd); }
    printf("rabadon budget for %s: %s.\n"
           "  the gate halts the run before it burns past this. `rabadon-budget off` to clear.\n",
           project.c_str(), parts.c_str());
    return 0;
  }

  // ---- clear ----
  if (low == "off" || low == "clear" || low == "none") {
    remove(file.c_str());
    printf("rabadon budget: cap cleared for %s — no ceiling.\n", project.c_str());
    return 0;
  }

  // ---- parse <number><unit> ----
  // strip thousands separators, split leading number from the unit suffix
  string clean; for (char c : low) if (c != ',') clean += c;
  size_t i = 0;
  string num;
  while (i < clean.size() && (isdigit((unsigned char)clean[i]) || clean[i] == '.')) num += clean[i++];
  string unit = clean.substr(i);
  { size_t a = unit.find_first_not_of(" \t"); unit = (a == string::npos) ? "" : unit.substr(a); }

  if (num.empty() || num == ".") {
    fprintf(stderr, "rabadon budget: didn't understand \"%s\". use `200000`, `200k`, `5usd`, or `off`.\n", spec.c_str());
    return 1;
  }
  double n = atof(num.c_str());

  bool isUsd = (unit == "usd" || unit == "$");
  string json, desc;
  if (isUsd) {
    if (n <= 0) { fprintf(stderr, "rabadon budget: the cap must be positive.\n"); return 1; }
    json = "{\n  \"usd\": " + fmt_usd(n) + "\n}\n";
    desc = "$" + fmt_usd(n);
  } else if (unit.empty() || unit == "k" || unit == "m" || unit == "tok" || unit == "tokens") {
    if (unit == "k") n *= 1e3; else if (unit == "m") n *= 1e6;
    long long toks = (long long)llround(n);
    if (toks <= 0) { fprintf(stderr, "rabadon budget: the cap must be positive.\n"); return 1; }
    json = "{\n  \"tokens\": " + std::to_string(toks) + "\n}\n";
    desc = group(toks) + " tokens";
  } else {
    fprintf(stderr, "rabadon budget: unknown unit \"%s\". use `k`, `m`, `usd`, `$`, or a bare token count.\n", unit.c_str());
    return 1;
  }

  mkdir(rdir.c_str(), 0755);
  { std::ofstream f(file, std::ios::trunc); if (!f) { fprintf(stderr, "rabadon budget: cannot write %s\n", file.c_str()); return 1; } f << json; }

  printf("rabadon budget: cap set to %s for %s.\n"
         "  the gate now measures this session's real usage on every tool call "
         "and halts the run before it burns past %s.\n",
         desc.c_str(), project.c_str(), desc.c_str());
  return 0;
}
