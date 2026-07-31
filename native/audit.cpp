// rabadon-audit — verify the hash-chained ledger (C++17, zero deps).
//
// The gate writes every spool event with prev = SHA-256 of the previous event
// line in the same day file (sha256.h, one shared implementation). This tool
// re-walks the chain and answers ONE question deterministically: has the
// ledger been edited after the fact?
//
//   - a line whose prev does not match the hash of the last chained line
//     before it = a BROKEN link, named by file and line number;
//   - lines without prev (legacy JS writers, serve ingest, pre-chain history)
//     are UNCHAINED: tolerated, counted, reported — never silently trusted;
//   - the .head sidecar, when present, must equal the hash of the last
//     chained line (a truncated file cannot hide);
//   - --replay renders the verified timeline event by event, chain mark per
//     line — the "what happened" answer with the tamper check inline.
//
// Exit 0 = every chained link intact. Exit 1 = at least one broken link.

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <dirent.h>
#include <pwd.h>
#include <sys/stat.h>
#include <unistd.h>
#include "sha256.h"

using std::string;

static double now_ms() {
  const char* t = getenv("RABADON_NOW");
  if (t && t[0]) { double v = strtod(t, nullptr); if (v > 0) return v; }
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  return (double)((long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static string read_file(const string& p) {
  struct stat st;
  if (stat(p.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return string();
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

// extract a top-level "key":"value" string field from a compact JSON line
static string get_field(const string& line, const string& key) {
  string pat = "\"" + key + "\":\"";
  size_t k = line.find(pat);
  if (k == string::npos) return "";
  size_t a = k + pat.size(), i = a;
  string out;
  while (i < line.size()) {
    char c = line[i];
    if (c == '\\' && i + 1 < line.size()) { out += c; out += line[i + 1]; i += 2; continue; }
    if (c == '"') return out;
    out += c; i++;
  }
  return "";
}

static double get_num(const string& line, const string& key) {
  string pat = "\"" + key + "\":";
  size_t k = line.find(pat);
  if (k == string::npos) return 0;
  return strtod(line.c_str() + k + pat.size(), nullptr);
}

static string local_stamp(double ms) {
  time_t t = (time_t)(ms / 1000.0);
  struct tm tmv; localtime_r(&t, &tmv);
  char buf[24]; strftime(buf, sizeof buf, "%Y-%m-%d %H:%M:%S", &tmv);
  return string(buf);
}

int main(int argc, char** argv) {
  double days = 7;
  bool replay = false;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--days") == 0 && i + 1 < argc) { double v = strtod(argv[++i], nullptr); if (v > 0) days = v; }
    else if (strcmp(argv[i], "--replay") == 0) replay = true;
  }

  string rdir;
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) rdir = rd;
  else {
    const char* h = getenv("HOME");
    string home = (h && h[0]) ? h : "";
    if (home.empty()) { struct passwd* pw = getpwuid(getuid()); if (pw && pw->pw_dir) home = pw->pw_dir; }
    rdir = home + "/.rabadon";
  }
  string spool = rdir + "/spool";

  const double cutoff = now_ms() - days * 86400000.0;

  std::vector<string> files;
  if (DIR* d = opendir(spool.c_str())) {
    while (struct dirent* ent = readdir(d)) {
      string n = ent->d_name;
      if (n.size() >= 6 && n.compare(n.size() - 6, 6, ".jsonl") == 0) files.push_back(n);
    }
    closedir(d);
  }
  std::sort(files.begin(), files.end());

  printf("rabadon audit — ledger integrity · %s\n\n", spool.c_str());
  if (files.empty()) {
    printf("  no spool files. the ledger is empty — nothing to verify yet.\n");
    return 0;
  }

  long long totalChained = 0, totalUnchained = 0, totalBreaks = 0;
  for (const string& f : files) {
    string body = read_file(spool + "/" + f);
    if (body.empty()) continue;

    string last = "genesis";     // hash of the last CHAINED line seen
    long long chained = 0, unchained = 0;
    long long firstBreakLine = 0;
    string breakNote;
    long long lineNo = 0;
    bool inWindow = false;

    size_t pos = 0;
    while (pos < body.size()) {
      size_t nl = body.find('\n', pos);
      string line = body.substr(pos, (nl == string::npos ? body.size() : nl) - pos);
      pos = (nl == string::npos) ? body.size() : nl + 1;
      lineNo++;
      if (line.empty()) continue;
      double ts = get_num(line, "ts");
      if (ts >= cutoff) inWindow = true;

      string prev = get_field(line, "prev");
      if (prev.empty()) { unchained++; continue; }
      if (prev != last && firstBreakLine == 0) {
        firstBreakLine = lineNo;
        breakNote = "prev=" + prev.substr(0, 12) + "… expected=" +
                    (last == "genesis" ? last : last.substr(0, 12) + "…");
      }
      last = rbsha::hex(line);
      chained++;

      if (replay && ts >= cutoff) {
        string ev = get_field(line, "ev");
        string pipe = get_field(line, "pipe");
        string what = get_field(line, "step");
        if (what.empty()) what = get_field(line, "detail");
        if (what.size() > 90) { what.resize(89); what += "…"; }
        printf("  %s %s  %-24s %-12s %s\n",
               (firstBreakLine && lineNo >= firstBreakLine) ? "✗" : "✓",
               local_stamp(ts).c_str(), pipe.c_str(), ev.c_str(), what.c_str());
      }
    }

    if (!inWindow && firstBreakLine == 0 && !replay) continue; // old file, intact: keep the report short

    // head sidecar: the hash of the last chained line cannot have been
    // truncated away
    string head = read_file(spool + "/" + f + ".head");
    while (!head.empty() && (head.back() == '\n' || head.back() == '\r')) head.pop_back();
    string headNote;
    if (!head.empty() && chained > 0 && head != last) {
      if (firstBreakLine == 0) { firstBreakLine = lineNo; breakNote = "head sidecar does not match the last chained line (truncation?)"; }
      headNote = " · head MISMATCH";
    }

    printf("  %-22s %6lld chained · %lld unchained%s", f.c_str(), chained, unchained,
           unchained ? " (legacy/JS writers)" : "");
    if (firstBreakLine) { printf(" · chain BROKEN at line %lld (%s)%s\n", firstBreakLine, breakNote.c_str(), headNote.c_str()); totalBreaks++; }
    else printf(" · chain OK\n");
    totalChained += chained; totalUnchained += unchained;
  }

  printf("\n");
  if (totalBreaks == 0) {
    printf("  verdict: INTACT — %lld chained event(s) verified", totalChained);
    if (totalUnchained) printf(" (%lld unchained line(s) tolerated, reported above)", totalUnchained);
    printf("\n");
    return 0;
  }
  printf("  verdict: TAMPER-EVIDENT BREAK in %lld file(s) — the ledger was edited, truncated, or reordered after emit\n", totalBreaks);
  return 1;
}
