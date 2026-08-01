// rules.h — ONE implementation of "does this command break the project's law".
//
// This used to live only inside gate.cpp, and `rabadon exec` grew its own,
// smaller idea of the same question: it compiled protectedPaths and network
// into a kernel policy and never read the bash deny rules at all. So the gate
// refused a command and exec ran the identical string to completion, which
// made exec a documented way around the gate rather than the harder boundary
// it is sold as. A rule engine that exists twice will diverge twice; the fix
// is that it exists once and both callers link it.
//
// Two things are deliberately NOT here: the emit/ledger side (chain.h owns
// that) and the three compiled-in laws (baseline.h owns those). This header is
// only the project's OWN guard.json rules and how they are matched.
#pragma once

#include <cctype>
#include <regex>
#include <string>
#include <vector>

#include "baseline.h"

namespace rbrules {

using std::string;

// ---------- the minimum JSON reach used to read a rule object ----------
// guard.json is small, flat and machine-written; a scanning reader keeps the
// gate free of a parser dependency on the hot path (2.3ms budget, BENCHMARK.md).
// Byte-identical to the gate's original, on purpose. A deny pattern is a regex
// carried through JSON, so `\\b` must survive as the two characters a regex
// word-boundary needs; "fixing" this to emit a 0x08 backspace would silently
// change what every existing rule matches.
inline string json_unescape(const string& s) {
  string out;
  out.reserve(s.size());
  for (size_t i = 0; i < s.size(); i++) {
    if (s[i] == '\\' && i + 1 < s.size()) {
      char c = s[++i];
      switch (c) {
        case 'n': out += '\n'; break;
        case 't': out += '\t'; break;
        case 'r': out += '\r'; break;
        case '"': out += '"'; break;
        case '\\': out += '\\'; break;
        case '/': out += '/'; break;
        case 'u': i += 4; out += '?'; break; // rules never need exact unicode
        default: out += c;
      }
    } else out += s[i];
  }
  return out;
}

inline string get_str(const string& j, const string& key, size_t from = 0) {
  const string pat = "\"" + key + "\"";
  size_t k = j.find(pat, from);
  if (k == string::npos) return "";
  size_t colon = j.find(':', k + pat.size());
  if (colon == string::npos) return "";
  size_t q = j.find('"', colon);
  // make sure only whitespace sits between ':' and the opening quote
  for (size_t i = colon + 1; i < q && i < j.size(); i++)
    if (!isspace((unsigned char)j[i])) return "";
  if (q == string::npos) return "";
  string raw;
  for (size_t i = q + 1; i < j.size(); i++) {
    if (j[i] == '\\' && i + 1 < j.size()) { raw += j[i]; raw += j[i + 1]; i++; continue; }
    if (j[i] == '"') break;
    raw += j[i];
  }
  return json_unescape(raw);
}

// ---------- rules ----------

struct Rule { string id, pattern, why; };

inline std::vector<string> parse_disabled(const string& guard) {
  std::vector<string> out;
  size_t sec = guard.find("\"disabled\"");
  if (sec == string::npos) return out;
  size_t a = guard.find('[', sec), b = guard.find(']', a);
  if (a == string::npos || b == string::npos) return out;
  string body = guard.substr(a, b - a);
  size_t p = 0;
  while ((p = body.find('"', p)) != string::npos) {
    size_t q = body.find('"', p + 1);
    if (q == string::npos) break;
    out.push_back(body.substr(p + 1, q - p - 1));
    p = q + 1;
  }
  return out;
}

// The raw text of every object in a section's array — INCLUDING the ones
// parse_rules is about to throw away.
//
// parse_rules keeps a rule only if its pattern key is present and non-empty.
// That is right for enforcement: a rule with no pattern can match nothing, and
// the gate must not crash on a half-written guard. But it drops those rules
// SILENTLY, which is precisely how a one-letter typo ("denies" for "deny")
// becomes an inert rule that still reads as law. lint's whole job is to see
// what enforcement discards, so it needs the objects before the filter — and it
// has to be THIS walker, not a second copy of it, or the two will disagree
// about what a rule even is (the divergence this header exists to end).
inline std::vector<string> parse_rule_objects(const string& guard, const string& section) {
  std::vector<string> objs;
  size_t sec = guard.find("\"" + section + "\"");
  if (sec == string::npos) return objs;
  size_t arrStart = guard.find('[', sec);
  if (arrStart == string::npos) return objs;
  // walk objects in the array (depth-tracking, strings skipped)
  int depth = 0; size_t objStart = 0;
  for (size_t i = arrStart; i < guard.size(); i++) {
    char c = guard[i];
    if (c == '"') { // skip string
      for (i++; i < guard.size(); i++) { if (guard[i] == '\\') i++; else if (guard[i] == '"') break; }
      continue;
    }
    if (c == '{') { if (depth == 1) objStart = i; depth++; }
    else if (c == '}') { depth--; if (depth == 1) objs.push_back(guard.substr(objStart, i - objStart + 1)); }
    else if (c == '[') depth++;
    else if (c == ']') { depth--; if (depth == 0) break; }
  }
  return objs;
}

// The keys declared directly ON one rule object. Nested objects and arrays are
// skipped by depth, so a key sitting inside some nested value is never mistaken
// for a field of the rule itself.
inline std::vector<string> rule_object_keys(const string& obj) {
  std::vector<string> keys;
  int depth = 0;
  for (size_t i = 0; i < obj.size(); i++) {
    char c = obj[i];
    if (c == '"') {
      string key;
      for (i++; i < obj.size(); i++) { if (obj[i] == '\\') i++; else if (obj[i] == '"') break; else key += obj[i]; }
      size_t j = i + 1;
      while (j < obj.size() && isspace((unsigned char)obj[j])) j++;
      // a quoted run followed by ':' is a key; anything else is a value, and
      // skipping it here is what keeps values from being read as field names
      if (depth == 1 && j < obj.size() && obj[j] == ':') keys.push_back(key);
      continue;
    }
    if (c == '{' || c == '[') depth++;
    else if (c == '}' || c == ']') depth--;
  }
  return keys;
}

inline std::vector<Rule> parse_rules(const string& guard, const string& section,
                                     const string& patKey, const std::vector<string>& disabled) {
  std::vector<Rule> rules;
  for (const string& obj : parse_rule_objects(guard, section)) {
    Rule r{ get_str(obj, "id"), get_str(obj, patKey), get_str(obj, "why") };
    bool off = false;
    for (const auto& d : disabled) if (d == r.id) off = true;
    if (!r.pattern.empty() && !off) rules.push_back(r);
  }
  return rules;
}

inline bool rx_test(const string& pattern, const string& text) {
  try {
    std::regex re(pattern, std::regex::ECMAScript | std::regex::icase);
    return std::regex_search(text, re);
  } catch (...) { return false; } // a broken rule must not take the gate down
}

// A user rule is judged PER SEGMENT of the command, and each segment is tried
// both as written and with git's global options stripped.
//
// Segments, because a rule that matched the whole line refused ordinary work:
// four of the five guards written for the wild repos blocked
// `npm test && git push origin feature/x` — a `-f` in one command matching a
// `git push` in another. A false refusal costs more than a missed one; it is
// the thing that makes people turn the gate off.
//
// Stripped, because agents write `git -C /path push --force` and
// `git --exec-path=/x push --force`, and every `git\s+push` rule slides right
// past them (both caught live, 31.07). The walk is structural now — every
// leading option, not a hand-kept list (baseline.h).
inline bool rx_test_cmd(const string& pattern, const string& cmd) {
  for (const string& seg : rbbase::raw_segments(cmd)) {
    if (rx_test(pattern, seg)) return true;
    const string norm = rbbase::strip_git_globals(seg);
    if (norm != seg && rx_test(pattern, norm)) return true;
  }
  return false;
}

// ---------- the whole verdict, in one call ----------
// Everything that can refuse a Bash command before it runs: the project's own
// deny rules first (so a refusal carries THEIR id and THEIR reason), then the
// three laws compiled into the binary as the floor underneath. Callers that
// skip this and re-implement half of it are how exec came to be a bypass.
struct Verdict { bool refused = false; string id, why, detail; };

inline Verdict judge_command(const string& guard, const string& cmd, const string& cwd) {
  Verdict v;
  if (cmd.empty()) return v;
  const std::vector<string> disabled = parse_disabled(guard);
  if (!guard.empty()) {
    for (const auto& r : parse_rules(guard, "bash", "deny", disabled)) {
      if (rx_test_cmd(r.pattern, cmd)) {
        v.refused = true; v.id = r.id; v.why = r.why;
        v.detail = "command matched deny rule: " + cmd.substr(0, 160);
        return v;
      }
    }
  }
  rbbase::Hit bh;
  if (rbbase::check(cmd, cwd, disabled, bh)) {
    v.refused = true; v.id = bh.id; v.why = bh.why; v.detail = bh.detail;
  }
  return v;
}

} // namespace rbrules
