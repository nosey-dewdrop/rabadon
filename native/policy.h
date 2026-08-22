// policy.h — R5. Consent as a POLICY, set once, not a question every time.
//
// WHY THIS IS NOT A PROMPT
// A tool that asks before every action is a tool whose question gets answered
// "yes" without being read, and a yes nobody read is not consent. So the repair
// arm's permission is decided once, by `rabadon init`, and written down where a
// human can go and change it:
//
//     $RABADON_DIR/config.json   {"repair": {"mode": "...", "check": "..."}}
//
// WHY RABADON HOME AND NOT THE PROJECT. .rabadon/guard.json is the PROJECT's
// rule file: what this repo forbids. "may rabadon spend my money on a model
// call while I am asleep" is not a fact about a repo, it is a fact about the
// operator and their machine, and it must not change when they clone a repo
// that happens to ship a config.
//
// THE THREE MODES, and the reason each exists:
//   ask           the default. One line at signal time, and the arm runs only
//                 after `rabadon repair --approve`. Costs nothing until a human
//                 says so, which is why it is what an unconfigured install gets.
//   auto-propose  for unattended runs. Runs WITHOUT asking and NEVER touches
//                 the user's tree — the patch is held at
//                 .rabadon/repair-<ts>.patch and applied later, by hand.
//   off           the arm is not there. Signals still reach the ledger.
//
// AN UNREADABLE POLICY IS `off`, NOT A GUESS. A typo in the mode string is the
// one case where the safe direction is obvious: a value nobody can read must
// never be resolved into permission to spend the user's money. It is refused
// out loud on stderr rather than silently, because a silently-disabled arm is
// indistinguishable from an arm that never triggered.
#pragma once

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <sys/stat.h>

namespace rbpolicy {

using std::string;

// the three legal values, as constants rather than as literals scattered
// through two binaries
static const char* MODE_ASK = "ask";
static const char* MODE_AUTO = "auto-propose";
static const char* MODE_OFF = "off";

inline string home() {
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) return rd;
  const char* h = getenv("HOME");
  return string((h && h[0]) ? h : ".") + "/.rabadon";
}

inline string config_path() { return home() + "/config.json"; }

// The same crude, dependency-free string extraction repair.cpp already uses for
// truth's JSON, scoped to the object named by `obj` so a "mode" belonging to
// some other section can never answer this question.
inline string field_in(const string& s, const string& obj, const string& key) {
  const string opat = "\"" + obj + "\"";
  size_t o = s.find(opat);
  if (o == string::npos) return "";
  const string kpat = "\"" + key + "\"";
  size_t k = s.find(kpat, o);
  if (k == string::npos) return "";
  size_t i = s.find(':', k + kpat.size());
  if (i == string::npos) return "";
  i++;
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) i++;
  if (i >= s.size() || s[i] != '"') return "";
  i++;
  string out;
  while (i < s.size()) {
    const char c = s[i];
    if (c == '\\' && i + 1 < s.size()) {
      const char e = s[i + 1];
      if (e == 'n') out += '\n'; else if (e == 't') out += '\t'; else if (e == 'r') out += '\r';
      else out += e;
      i += 2; continue;
    }
    if (c == '"') return out;
    out += c; i++;
  }
  return "";
}

struct Repair {
  string mode = MODE_ASK;   // what an unconfigured install gets: never spends
  string check;             // the deterministic check the arm re-runs, if named
  bool   configured = false;
};

inline Repair repair() {
  Repair r;
  std::ifstream f(config_path(), std::ios::binary);
  if (!f) return r;                       // no policy written yet -> ask
  std::ostringstream ss; ss << f.rdbuf();
  const string body = ss.str();
  const string m = field_in(body, "repair", "mode");
  r.check = field_in(body, "repair", "check");
  if (m.empty()) return r;                // section present, mode absent -> ask
  r.configured = true;
  if (m == MODE_ASK || m == MODE_AUTO || m == MODE_OFF) { r.mode = m; return r; }
  fprintf(stderr,
          "rabadon: repair.mode is \"%s\", which is not one of ask | auto-propose | off"
          " (%s). The repair arm is OFF until that reads as one of the three —"
          " a policy nobody can parse is not permission to spend.\n",
          m.c_str(), config_path().c_str());
  r.mode = MODE_OFF;
  return r;
}

} // namespace rbpolicy
