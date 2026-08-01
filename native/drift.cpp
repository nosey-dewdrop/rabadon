// rabadon-drift — the measured direction check. C++17, zero deps.
//
// The launch promise's fourth pain: "somewhere along the way, the pipeline
// loses its own purpose." The old JS judge for this NEVER fired in 1691 real
// events — it ran only when a 12-multiple action happened to be an edit, and
// it judged against a garbage "goal" scraped from the session's first prompt.
//
// This is the honest rebuild. A project declares its north star ONCE, in
// .rabadon/promise.json (machine-readable). At session end this binary MEASURES
// how far the session's real work — the files git says changed, the commands
// the spool recorded — drifted from that star, and says so OUT LOUD. No model
// is asked to have an opinion: every number here is counted, not judged. An LLM
// may later phrase the verdict, but the verdict itself survives with the model
// removed. That is the difference between this and a log.
//
// Contract: never blocks (exit 0 on-track, 3 on drift — an advisory signal),
// and any error in the check itself fails OPEN (silent, exit 0). It also writes
// one CHECK_FAIL{check:"goal-drift"} to the spool on drift, so the ledger and
// the dashboard finally carry the event they never had.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <regex>
#include <string>
#include <vector>
#include <set>
#include <fstream>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>
#include "cli_help.h"
#include "version.h" // one version string, lockstep with package.json

using std::string;
using std::vector;

// ---------- tiny helpers (self-contained; the gate has its own copy) ----------

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return "";
  std::stringstream ss; ss << f.rdbuf(); return ss.str();
}

static string run_cmd(const string& cmd) {
  string out; char buf[4096];
  FILE* p = popen(cmd.c_str(), "r");
  if (!p) return "";
  size_t n; while ((n = fread(buf, 1, sizeof(buf), p)) > 0) out.append(buf, n);
  pclose(p);
  return out;
}

static long long now_ms() {
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static string json_escape(const string& s) {
  string o; o.reserve(s.size() + 8);
  for (char c : s) {
    switch (c) {
      case '"': o += "\\\""; break;
      case '\\': o += "\\\\"; break;
      case '\n': o += "\\n"; break;
      case '\r': o += "\\r"; break;
      case '\t': o += "\\t"; break;
      default: o += c;
    }
  }
  return o;
}

static string to_lower(string s) { for (char& c : s) c = (char)tolower((unsigned char)c); return s; }

// pull "key":"value" (first occurrence), unescaping the common sequences
static string json_str(const string& j, const string& key) {
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
    if (ch == '\\' && i + 1 < j.size()) {
      char n = j[++i];
      out += (n == 'n') ? '\n' : (n == 't') ? '\t' : n;
    } else if (ch == '"') break;
    else out += ch;
  }
  return out;
}

static long long json_num(const string& j, const string& key) {
  const string pat = "\"" + key + "\"";
  size_t k = j.find(pat);
  if (k == string::npos) return 0;
  size_t c = j.find(':', k + pat.size());
  if (c == string::npos) return 0;
  return atoll(j.c_str() + c + 1);
}

// max value across ALL occurrences of `key` — the state file holds several
// sessions; "this session" is the most recent one, not the first in the map.
static long long json_num_max(const string& j, const string& key) {
  const string pat = "\"" + key + "\"";
  long long best = 0; size_t from = 0;
  while (true) {
    size_t k = j.find(pat, from);
    if (k == string::npos) break;
    size_t c = j.find(':', k + pat.size());
    if (c == string::npos) break;
    long long v = atoll(j.c_str() + c + 1);
    if (v > best) best = v;
    from = c + 1;
  }
  return best;
}

// the goalPrompt sitting closest AFTER the given goalTs value (same session)
static string goal_for_ts(const string& j, long long ts) {
  if (ts <= 0) return json_str(j, "goalPrompt");
  const string tsPat = "\"goalTs\":" + std::to_string(ts);
  size_t k = j.find(tsPat);
  if (k == string::npos) return json_str(j, "goalPrompt");
  // goalPrompt is written just before goalTs in the same object; search back a bit
  size_t start = k > 400 ? k - 400 : 0;
  string window = j.substr(start, (k - start) + 40);
  string g = json_str(window, "goalPrompt");
  return g.empty() ? json_str(j, "goalPrompt") : g;
}

// pull a JSON array of strings for `key`
static vector<string> json_str_array(const string& j, const string& key) {
  vector<string> out;
  const string pat = "\"" + key + "\"";
  size_t k = j.find(pat);
  if (k == string::npos) return out;
  size_t a = j.find('[', k);
  if (a == string::npos) return out;
  size_t b = j.find(']', a);
  if (b == string::npos) return out;
  string body = j.substr(a + 1, b - a - 1);
  size_t p = 0;
  while ((p = body.find('"', p)) != string::npos) {
    string v;
    size_t i = p + 1;
    for (; i < body.size(); i++) {
      if (body[i] == '\\' && i + 1 < body.size()) { v += body[++i]; }
      else if (body[i] == '"') break;
      else v += body[i];
    }
    if (!v.empty()) out.push_back(v);
    p = i + 1;
  }
  return out;
}

static bool rx(const string& pattern, const string& text) {
  try {
    std::regex re(pattern, std::regex::ECMAScript | std::regex::icase);
    return std::regex_search(text, re);
  } catch (...) { return false; }
}

// tokenize into lowercased word set (>=3 chars), for goal/north-star overlap
static std::set<string> word_set(const string& s) {
  std::set<string> out;
  string cur;
  for (char c : s) {
    if (isalnum((unsigned char)c) || c == '+' || c == '#') cur += (char)tolower((unsigned char)c);
    else { if (cur.size() >= 3) out.insert(cur); cur.clear(); }
  }
  if (cur.size() >= 3) out.insert(cur);
  return out;
}

// ---------- the check ----------

struct Promise {
  string north_star;
  vector<string> areas;        // path regexes: on-target work location
  vector<string> anti_paths;   // path regexes: work that betrays the star
  vector<string> keywords;     // north-star vocabulary (coverage measured)
  vector<string> off_keywords; // drift/bikeshed vocabulary (presence measured)
  bool ok() const { return !north_star.empty(); }
};

static const char* kHelp =
  "rabadon-drift — is this session still working on what it said it would?\n"
  "Compares what the run touched against <dir>/.rabadon/promise.json (north_star,\n"
  "areas, anti_paths, keywords) and speaks only when the work has wandered.\n"
  "Advisory: it fails OPEN on anything missing and never blocks.\n"
  "\n"
  "usage: rabadon-drift [dir] [--quiet-ok]\n"
  "\n"
  "  [dir]        the project to judge (default: the current directory).\n"
  "  --quiet-ok   say nothing while on track. this is the default as a hook.\n"
  "  --version    print the version.\n"
  "  -h, --help   this screen.\n"
  "\n"
  "As a Stop hook Claude Code pipes the event JSON on stdin and drift reads cwd\n"
  "from it; it stays silent unless rabadon is enabled (~/.rabadon/enabled, or a\n"
  "per-project <dir>/.rabadon/on).\n"
  "\n"
  "example:\n"
  "  rabadon-drift ~/src/myrepo\n";

int main(int argc, char** argv) {
  // `rabadon-drift --help` used to exit 0 having printed NOTHING — zero bytes,
  // which is indistinguishable from a healthy silent hook.
  rb_help(argc, argv, kHelp);

  string dir;
  bool quietOnTrack = false;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    // version.h, never a literal: this line said 0.1.0 while every manifest
    // in the repo said 0.2.0.
    if (a == "--version") { printf("rabadon-drift " RABADON_VERSION "\n"); return 0; }
    else if (a == "--quiet-ok") quietOnTrack = true;
    // An unknown flag is NAMED but never fatal. This binary runs as a Stop hook,
    // where a non-zero exit means BLOCK — refusing here would let one typo in a
    // settings.json hook line wedge every session. So: say so, fail OPEN.
    else if (a[0] == '-') {
      fprintf(stderr, "rabadon-drift: unknown option \"%s\" — run `rabadon-drift --help`\n", a.c_str());
      return 0;
    }
    else dir = a;
  }
  // as a Stop hook, Claude Code pipes the event JSON (with cwd) on stdin; as a
  // CLI, a dir argument is given. Prefer the explicit arg, else read the hook.
  if (dir.empty() && !isatty(0)) {
    string raw; char buf[8192]; size_t n;
    while ((n = fread(buf, 1, sizeof(buf), stdin)) > 0) raw.append(buf, n);
    dir = json_str(raw, "cwd");
    quietOnTrack = true; // a hook stays quiet when on-track; it only speaks on drift
    // off switches, same law as the gate
    const char* off = getenv("RABADON_OFF");
    if ((off && string(off) == "1")) return 0;
    if (!dir.empty()) { struct stat sb; if (stat((dir + string("/.rabadon/off")).c_str(), &sb) == 0) return 0; }
    // DEFAULT-OFF: as a Stop hook, drift speaks only when rabadon is enabled
    // (global ~/.rabadon/enabled or per-project cwd/.rabadon/on). Same law as the gate.
    {
      const char* rdh = getenv("RABADON_DIR"); const char* h = getenv("HOME"); struct stat sb;
      const string rhome = (rdh && rdh[0]) ? string(rdh) : string(h ? h : ".") + "/.rabadon";
      bool enabled = stat((rhome + "/enabled").c_str(), &sb) == 0;
      if (!enabled && !dir.empty() && stat((dir + "/.rabadon/on").c_str(), &sb) == 0) enabled = true;
      if (!enabled) return 0;
    }
  }
  if (dir.empty()) dir = ".";
  if (!dir.empty() && dir.back() == '/') dir.pop_back();

  // fail OPEN on anything missing — an advisory that never gets in the way
  const string praw = read_file(dir + "/.rabadon/promise.json");
  Promise pr;
  pr.north_star  = json_str(praw, "north_star");
  pr.areas       = json_str_array(praw, "areas");
  pr.anti_paths  = json_str_array(praw, "anti_paths");
  pr.keywords    = json_str_array(praw, "keywords");
  pr.off_keywords= json_str_array(praw, "off_keywords");
  if (!pr.ok()) {
    if (!quietOnTrack)
      fprintf(stderr,
        "rabadon drift: no north star set for this project.\n"
        "Write .rabadon/promise.json — the one thing this project is FOR — and the\n"
        "engine will measure every session against it at the end. Example:\n"
        "  { \"north_star\": \"...\", \"areas\": [\"src/\"], \"anti_paths\": [\"\\\\.tmp$\"],\n"
        "    \"keywords\": [\"...\"], \"off_keywords\": [\"...\"] }\n");
    return 0;
  }

  // project + spool home
  string project = dir;
  size_t s = project.rfind('/');
  if (s != string::npos) project = project.substr(s + 1);
  if (project == "." || project.empty()) project = run_cmd("basename \"$(pwd)\" 2>/dev/null");
  { while (!project.empty() && (project.back() == '\n' || project.back() == ' ')) project.pop_back(); }

  const char* rd = getenv("RABADON_DIR");
  const char* home = getenv("HOME");
  const string rdir = rd ? rd : (string(home ? home : ".") + "/.rabadon");

  // session start = the goal timestamp the node gate captured, else 6h ago
  const string nodeState = read_file(dir + "/.rabadon/state.json");
  long long goalTs = json_num_max(nodeState, "goalTs");
  string goalPrompt = goal_for_ts(nodeState, goalTs);
  // rabadon's own diagnose/judge prompts leak into goal capture via hook
  // recursion; they are not a real goal, so don't measure overlap against them.
  if (goalPrompt.rfind("You are rabadon", 0) == 0) goalPrompt = "";
  long long sessionStart = goalTs > 0 ? goalTs : (now_ms() - 6LL * 3600 * 1000);
  time_t startSec = (time_t)(sessionStart / 1000);
  char sinceIso[32]; { struct tm tmv; localtime_r(&startSec, &tmv); strftime(sinceIso, sizeof(sinceIso), "%Y-%m-%dT%H:%M:%S", &tmv); }

  // -------- the changed files this session (git = full paths, accurate) --------
  // uncommitted (tracked + untracked) UNION committed since session start
  std::set<string> changed;
  {
    // -uall lists untracked FILES individually; without it git collapses an
    // untracked directory to its name and a forbidden .mjs inside it hides.
    string porcelain = run_cmd("git -C \"" + dir + "\" status --porcelain=v1 -uall 2>/dev/null");
    std::istringstream is(porcelain);
    string line;
    while (std::getline(is, line)) {
      if (line.size() < 4) continue;
      string p = line.substr(3);
      // rename "old -> new": keep the new path
      size_t arrow = p.find(" -> ");
      if (arrow != string::npos) p = p.substr(arrow + 4);
      if (!p.empty()) changed.insert(p);
    }
    string committed = run_cmd("git -C \"" + dir + "\" log --since=\"" + sinceIso +
                               "\" --name-only --pretty=format: 2>/dev/null");
    std::istringstream ic(committed);
    while (std::getline(ic, line)) if (!line.empty()) changed.insert(line);
  }

  auto matchesAny = [](const vector<string>& pats, const string& text) {
    for (const auto& p : pats) if (rx(p, text)) return true;
    return false;
  };

  int total = 0, onTarget = 0, antiHits = 0;
  vector<string> onList, offList, antiList;
  for (const auto& f : changed) {
    total++;
    bool on = pr.areas.empty() ? false : matchesAny(pr.areas, f);
    bool anti = matchesAny(pr.anti_paths, f);
    if (anti) { antiHits++; antiList.push_back(f); }
    if (on && !anti) { onTarget++; onList.push_back(f); }
    else if (!on) offList.push_back(f);
  }

  // -------- session commands from the spool (this project's window) --------
  string cmdsBlob;
  {
    // UTC: the file this READS is the file the gate WRITES, and the gate names
    // it with gmtime. Asking for the local name meant that east of Greenwich
    // after midnight this opened a file that did not exist, cmdsBlob came back
    // empty, and the vocabulary check below scored a session that had run the
    // right commands as though it had run none (measured: 1/1 present -> 0/1).
    char day[16]; { time_t t = time(nullptr); struct tm tmv; gmtime_r(&t, &tmv); strftime(day, 16, "%Y-%m-%d", &tmv); }
    for (const string& d : { string(day) }) {
      std::ifstream f(rdir + "/spool/" + d + ".jsonl");
      string line;
      while (std::getline(f, line)) {
        if (line.find("\"" + project + ":session\"") == string::npos &&
            line.find("\"" + project + ":") == string::npos) continue;
        if (json_num(line, "ts") < sessionStart) continue;
        string step = json_str(line, "step");
        if (!step.empty()) { cmdsBlob += step; cmdsBlob += "\n"; }
      }
    }
  }

  // -------- measured signals --------
  const string haystack = to_lower(cmdsBlob + "\n" + goalPrompt + "\n" + [&]{
      string j; for (auto& f : changed) { j += f; j += " "; } return j; }());

  int kwFound = 0; vector<string> kwHit, kwMiss;
  for (const auto& k : pr.keywords) {
    if (haystack.find(to_lower(k)) != string::npos) { kwFound++; kwHit.push_back(k); }
    else kwMiss.push_back(k);
  }
  int offFound = 0; vector<string> offHit;
  for (const auto& k : pr.off_keywords)
    if (haystack.find(to_lower(k)) != string::npos) { offFound++; offHit.push_back(k); }

  // goal vs north-star token overlap (did we even open it for the right thing?)
  auto gset = word_set(goalPrompt), nset = word_set(pr.north_star);
  int overlap = 0; for (const auto& w : gset) if (nset.count(w)) overlap++;

  double areaHit = total ? (double)onTarget / total : 1.0;

  // -------- verdict (measured, not judged) --------
  // drift when the work left its area, or touched forbidden ground, or the
  // session's own stated goal shares nothing with the star while off-vocab shows up.
  bool drift = false; vector<string> reasons;
  if (total > 0 && areaHit < 0.5) { drift = true; char b[128]; snprintf(b, sizeof b, "%d of %d changed files are off the north star (%.0f%% on-target)", total - onTarget, total, areaHit * 100); reasons.push_back(b); }
  if (antiHits > 0) { drift = true; string a = "touched ground you swore off: "; for (size_t i = 0; i < antiList.size() && i < 4; i++) a += antiList[i] + (i + 1 < antiList.size() && i < 3 ? ", " : ""); reasons.push_back(a); }
  if (!pr.keywords.empty() && kwFound == 0 && total > 0) { drift = true; reasons.push_back("not one of the north-star keywords appears in this session's work"); }
  if (offFound > 0 && areaHit < 0.6) { drift = true; string o = "bikeshed vocabulary present ("; for (size_t i = 0; i < offHit.size(); i++) o += offHit[i] + (i + 1 < offHit.size() ? ", " : ""); o += ") while work sat off-target"; reasons.push_back(o); }
  if (!goalPrompt.empty() && !nset.empty() && overlap == 0 && total > 0) reasons.push_back("the goal this session opened with shares no words with the north star");

  // -------- speak, out loud --------
  FILE* o = drift ? stderr : stdout;
  if (drift || !quietOnTrack) {
    fprintf(o, "\n  rabadon — direction check (session end)\n");
    fprintf(o, "  north star: %s\n", pr.north_star.c_str());
    fprintf(o, "  this session: %d changed file(s) — %d on-target, %d off, %d against the star\n", total, onTarget, (int)offList.size(), antiHits);
    if (!pr.keywords.empty()) {
      fprintf(o, "  north-star vocabulary: %d/%d present", kwFound, (int)pr.keywords.size());
      if (!kwMiss.empty()) { fprintf(o, " (missing: "); for (size_t i = 0; i < kwMiss.size() && i < 5; i++) fprintf(o, "%s%s", kwMiss[i].c_str(), i + 1 < kwMiss.size() && i < 4 ? ", " : ""); fprintf(o, ")"); }
      fprintf(o, "\n");
    }
    if (drift) {
      fprintf(o, "  VERDICT: DRIFT\n");
      for (const auto& r : reasons) fprintf(o, "    - %s\n", r.c_str());
      fprintf(o, "  Does this session still serve what you said this project is for? If yes, say so and continue; if not, this is the hour it happened.\n\n");
    } else {
      fprintf(o, "  VERDICT: on the star.\n\n");
    }
  }

  // -------- write the event the ledger never had --------
  if (drift) {
    mkdir((rdir + "/spool").c_str(), 0755);
    // UTC, same one name as every other writer of this file.
    char day[16]; { time_t t = time(nullptr); struct tm tmv; gmtime_r(&t, &tmv); strftime(day, 16, "%Y-%m-%d", &tmv); }
    std::ofstream sp(rdir + "/spool/" + string(day) + ".jsonl", std::ios::app);
    string why = reasons.empty() ? "off the north star" : reasons[0];
    sp << "{\"v\":1,\"ts\":" << now_ms() << ",\"pipe\":\"" << json_escape(project)
       << ":session\",\"ev\":\"CHECK_FAIL\",\"step\":\"direction\",\"fails\":[{\"check\":\"goal-drift\",\"why\":\""
       << json_escape(why) << "\"}]}\n";
  }

  return drift ? 3 : 0;
}
