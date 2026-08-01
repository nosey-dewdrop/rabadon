// lens.cpp — rabadon-lens: the SEEING half.
//
// Claude Code writes every session to ~/.claude/projects/<cwd>/<sessionId>.jsonl.
// That transcript is already on disk, deterministic, zero LLM — the moat. lens
// reads it and prints, per session: project, model, tokens (in / out / cache),
// $cost, tool calls, wall-clock duration. Langfuse's trace view, local, for the
// money you already spent. The token/dollar meter is usage.h — the SAME meter
// the budget gate uses, so the ledger and the cap can never disagree.
//
// One binary, zero deps, C++17. Source resolution: a path argument wins, else
// $RABADON_LENS_DIR if non-empty, else $HOME/.claude/projects. A path may be a
// single .jsonl file (one session) or a directory (its .jsonl plus the .jsonl
// in each immediate subdirectory — the real projects/<cwd>/<id>.jsonl layout).
// --days N filters to sessions last active within N days (default 7). Any error
// is non-fatal: an unreadable source is simply zero sessions.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cctype>
#include <ctime>
#include <string>
#include <vector>
#include <algorithm>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>

#include "usage.h"
#include "cli_help.h"

using std::string;
using std::vector;

// ---------- file / path helpers ----------
static string read_file(const string& path) {
  FILE* f = fopen(path.c_str(), "rb");
  if (!f) return "";
  string out;
  char buf[65536];
  size_t n;
  while ((n = fread(buf, 1, sizeof buf, f)) > 0) out.append(buf, n);
  fclose(f);
  return out;
}
static bool ends_with(const string& s, const char* suf) {
  size_t n = strlen(suf);
  return s.size() >= n && s.compare(s.size() - n, n, suf) == 0;
}
static string basename_of(const string& p) {
  size_t e = p.size();
  while (e > 0 && p[e - 1] == '/') e--;            // trailing slashes
  size_t s = p.rfind('/', e ? e - 1 : 0);
  s = (s == string::npos) ? 0 : s + 1;
  return p.substr(s, e - s);
}
static string stem_of(const string& file) {           // "id.jsonl" -> "id"
  string b = basename_of(file);
  if (ends_with(b, ".jsonl")) b = b.substr(0, b.size() - 6);
  return b;
}

// ISO8601 -> epoch ms. "2026-07-28T17:49:49.822Z"; tz is always Z (UTC) in the
// transcript, so timegm keeps a within-session difference exact. -1 = no stamp.
static double iso_to_ms(const string& iso) {
  int Y, Mo, D, h, mi, s;
  if (sscanf(iso.c_str(), "%d-%d-%dT%d:%d:%d", &Y, &Mo, &D, &h, &mi, &s) != 6) return -1;
  struct tm tmv;
  memset(&tmv, 0, sizeof tmv);
  tmv.tm_year = Y - 1900; tmv.tm_mon = Mo - 1; tmv.tm_mday = D;
  tmv.tm_hour = h; tmv.tm_min = mi; tmv.tm_sec = s;
  double ms = (double)timegm(&tmv) * 1000.0;
  size_t dot = iso.find('.');
  if (dot != string::npos) ms += atof(iso.c_str() + dot) * 1000.0;   // ".822" -> 822ms
  return ms;
}

// value of a "key":"value" string field on one line (first occurrence)
static string find_str(const string& line, const char* key) {
  size_t p = line.find(key);
  if (p == string::npos) return "";
  p += strlen(key);
  size_t e = line.find('"', p);
  return e == string::npos ? "" : line.substr(p, e - p);
}

// ---------- one session ----------
struct Session {
  string id, project, model;
  Usage usage;
  long long tools = 0;
  double firstTs = -1, lastTs = -1;
};

static Session read_session(const string& file) {
  Session s;
  s.id = stem_of(file);
  const string body = read_file(file);
  s.usage = sum_usage(body);           // the meter — identical to the gate's
  s.model = last_model(body);

  size_t ls = 0;
  while (ls < body.size()) {
    size_t le = body.find('\n', ls);
    if (le == string::npos) le = body.size();
    const string line = body.substr(ls, le - ls);
    ls = le + 1;
    if (line.empty()) continue;

    // wall-clock span: first .. last timestamp on ANY line
    string ts = find_str(line, "\"timestamp\":\"");
    if (!ts.empty()) {
      double ms = iso_to_ms(ts);
      if (ms >= 0) {
        if (s.firstTs < 0 || ms < s.firstTs) s.firstTs = ms;
        if (ms > s.lastTs) s.lastTs = ms;
      }
    }
    // project from the working directory (first line that carries cwd)
    if (s.project.empty()) {
      string cwd = find_str(line, "\"cwd\":\"");
      if (!cwd.empty()) s.project = basename_of(cwd);
    }
    // tool calls: tool_use blocks live inside "type":"assistant" content lines
    if (line.find("\"type\":\"assistant\"") != string::npos) {
      size_t q = 0;
      while ((q = line.find("\"type\":\"tool_use\"", q)) != string::npos) { s.tools++; q += 1; }
    }
  }
  if (s.project.empty()) s.project = "?";
  return s;
}

// ---------- formatting ----------
static string short_model(const string& m) {
  if (m.empty()) return "?";
  string s = m;
  const string pre = "claude-";
  if (s.compare(0, pre.size(), pre) == 0) s = s.substr(pre.size());      // claude-opus-4-8 -> opus-4-8
  size_t br = s.find('[');
  if (br != string::npos) s = s.substr(0, br);                           // drop "[1m]"
  size_t dash = s.rfind('-');                                            // drop a trailing -YYYYMMDD date
  if (dash != string::npos && dash + 1 < s.size()) {
    bool alldig = true;
    for (size_t i = dash + 1; i < s.size(); i++) if (!isdigit((unsigned char)s[i])) { alldig = false; break; }
    if (alldig && s.size() - dash - 1 >= 6) s = s.substr(0, dash);       // haiku-4-5-20251001 -> haiku-4-5
  }
  return s;
}
static string fmt_dur(double firstMs, double lastMs) {
  if (firstMs < 0 || lastMs < 0 || lastMs < firstMs) return "?";
  long long sec = (long long)((lastMs - firstMs) / 1000.0 + 0.5);
  long long h = sec / 3600; sec %= 3600;
  long long m = sec / 60;   sec %= 60;
  char b[32];
  if (h > 0)      snprintf(b, sizeof b, "%lldh%02lldm", h, m);
  else if (m > 0) snprintf(b, sizeof b, "%lldm%02llds", m, sec);
  else            snprintf(b, sizeof b, "%llds", sec);
  return b;
}

// ---------- source discovery ----------
static void collect_jsonl(const string& dir, vector<string>& out) {
  DIR* d = opendir(dir.c_str());
  if (!d) return;
  while (struct dirent* ent = readdir(d)) {
    string n = ent->d_name;
    if (ends_with(n, ".jsonl")) out.push_back(dir + "/" + n);
  }
  closedir(d);
}

static const char* kHelp =
  "rabadon-lens — sessions, tokens and cost read straight off Claude Code's own\n"
  "transcripts. Zero instrumentation: the files are already on disk, the metering\n"
  "is byte-exact, and no model is called to produce any number here.\n"
  "\n"
  "usage: rabadon-lens [transcript.jsonl | dir] [--days N]\n"
  "\n"
  "  [transcript.jsonl | dir]  a transcript, or a directory of them.\n"
  "                            omitted: $RABADON_LENS_DIR, else ~/.claude/projects.\n"
  "  --days N                  window to report (default 7).\n"
  "  -h, --help                this screen.\n"
  "\n"
  "example:\n"
  "  rabadon-lens --days 30\n";

int main(int argc, char** argv) {
  rb_help(argc, argv, kHelp);

  // --days (default 7; unparseable or 0 -> 7). first path-like arg = source.
  double days = 7;
  string source;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--days") == 0) {
      if (i + 1 < argc) {
        char* end = nullptr;
        double v = strtod(argv[i + 1], &end);
        if (end != argv[i + 1] && v != 0) days = v;
        i++;
      }
    // a flag this binary does not know must not become the SOURCE PATH. it did:
    // `rabadon-lens --help` printed a real report headed "source: --help", which
    // reads like the flag was honoured and a filter applied.
    } else if (rb_is_flag(argv[i])) {
      rb_unknown_flag("rabadon-lens", argv[i]);
    } else if (source.empty()) {
      source = argv[i];
    }
  }
  if (source.empty()) {
    const char* env = getenv("RABADON_LENS_DIR");
    if (env && env[0]) source = env;
  }
  if (source.empty()) {
    const char* h = getenv("HOME");
    string home = (h && h[0]) ? h : "";
    if (home.empty()) { struct passwd* pw = getpwuid(getuid()); if (pw && pw->pw_dir) home = pw->pw_dir; }
    while (home.size() > 1 && home.back() == '/') home.pop_back();
    source = home + "/.claude/projects";
  }

  // gather transcript files: a single .jsonl, or a dir's .jsonl + one level of
  // subdirs (projects/<cwd>/<id>.jsonl and a flat fixture dir both work).
  vector<string> files;
  struct stat st;
  if (stat(source.c_str(), &st) == 0 && S_ISREG(st.st_mode)) {
    if (ends_with(source, ".jsonl")) files.push_back(source);
  } else {
    collect_jsonl(source, files);
    if (DIR* d = opendir(source.c_str())) {
      while (struct dirent* ent = readdir(d)) {
        string n = ent->d_name;
        if (n == "." || n == "..") continue;
        string sub = source + "/" + n;
        struct stat ss;
        if (stat(sub.c_str(), &ss) == 0 && S_ISDIR(ss.st_mode)) collect_jsonl(sub, files);
      }
      closedir(d);
    }
  }
  std::sort(files.begin(), files.end());

  const double cutoff = (double)time(nullptr) * 1000.0 - days * 86400000.0;

  vector<Session> sessions;
  for (const string& f : files) {
    Session s = read_session(f);
    if (s.lastTs < cutoff) continue;                 // outside the window (or no stamp)
    if (s.usage.tokens() == 0 && s.tools == 0) continue; // empty/degenerate transcript
    sessions.push_back(std::move(s));
  }
  // most recent first, ties stable by first-encounter (sorted filename) order
  std::stable_sort(sessions.begin(), sessions.end(),
                   [](const Session& a, const Session& b) { return a.lastTs > b.lastTs; });

  // ---------- print ----------
  string out;
  char line[512];
  snprintf(line, sizeof line, "rabadon lens — last %g day(s), source: %s\n\n", days, source.c_str());
  out += line;

  snprintf(line, sizeof line, "  %-8s %-16s %-13s %10s %10s %13s %13s %10s %6s  %s\n",
           "SESSION", "PROJECT", "MODEL", "IN", "OUT", "CACHE", "TOKENS", "$COST", "TOOLS", "DUR");
  out += line;

  long long totTok = 0, totTools = 0;
  double totUsd = 0; bool anyUnpriced = false;

  if (sessions.empty()) out += "  (no sessions in the last " + std::to_string((long long)days) + " day(s))\n";

  for (const Session& s : sessions) {
    Rate r;
    string cost;
    if (model_rate(s.model, r)) {
      double usd = usd_cost(s.usage, r);
      totUsd += usd;
      char c[32]; snprintf(c, sizeof c, "$%.4f", usd);
      cost = c;
    } else { cost = "?"; anyUnpriced = true; }

    long long cache = s.usage.cacheCreate + s.usage.cacheRead;
    string id8 = s.id.size() > 8 ? s.id.substr(0, 8) : s.id;
    string dur = fmt_dur(s.firstTs, s.lastTs);

    snprintf(line, sizeof line,
             "  %-8.8s %-16.16s %-13.13s %10lld %10lld %13lld %13lld %10s %6lld  %s\n",
             id8.c_str(), s.project.c_str(), short_model(s.model).c_str(),
             s.usage.in, s.usage.out, cache, s.usage.tokens(), cost.c_str(), s.tools, dur.c_str());
    out += line;

    totTok += s.usage.tokens();
    totTools += s.tools;
  }

  if (!sessions.empty()) {
    out += "\n";
    char tot[256];
    if (anyUnpriced)
      snprintf(tot, sizeof tot, "  TOTAL  %zu session(s) · %lld tokens · $%.4f+ (some models unpriced) · %lld tool calls\n",
               sessions.size(), totTok, totUsd, totTools);
    else
      snprintf(tot, sizeof tot, "  TOTAL  %zu session(s) · %lld tokens · $%.4f · %lld tool calls\n",
               sessions.size(), totTok, totUsd, totTools);
    out += tot;
  }

  fwrite(out.data(), 1, out.size(), stdout);
  return 0;
}
