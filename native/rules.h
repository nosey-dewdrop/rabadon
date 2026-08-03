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
#include <fstream>
#include <regex>
#include <sstream>
#include <string>
#include <vector>

#include "baseline.h"
#include "cmdtext.h"

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

// The string array stored under `key` inside one object's raw text. Written for
// a rule's `allow` twins, the commands that rule must NOT match: a rule refusing
// everything is as broken as one that fires at nothing, and only the second was
// ever checked.
inline std::vector<string> get_str_array(const string& j, const string& key) {
  std::vector<string> out;
  const size_t k = j.find("\"" + key + "\"");
  if (k == string::npos) return out;
  const size_t a = j.find('[', k);
  if (a == string::npos) return out;
  const size_t b = j.find(']', a);
  if (b == string::npos) return out;
  size_t p = a + 1;
  while (p < b) {
    const size_t s = j.find('"', p);
    if (s == string::npos || s > b) break;
    string val;
    size_t e = s + 1;
    for (; e < j.size() && j[e] != '"'; e++) {
      if (j[e] == '\\' && e + 1 < j.size()) { val += j[e]; val += j[e + 1]; e++; }
      else val += j[e];
    }
    out.push_back(json_unescape(val));
    p = e + 1;
  }
  return out;
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

// A user rule is judged PER EXECUTABLE SURFACE of the command, and each surface
// is tried both as written and with git's global options stripped.
//
// Segments, because a rule that matched the whole line refused ordinary work:
// four of the five guards written for the wild repos blocked
// `npm test && git push origin feature/x` — a `-f` in one command matching a
// `git push` in another. A false refusal costs more than a missed one; it is
// the thing that makes people turn the gate off.
//
// Surfaces and not raw slices, because segmenting alone still read DATA as
// code. `git commit -m "...an agent wrote git push --force"` was refused as a
// force-push: the whole force-push lived inside one quoted argument, in one
// segment, and the rule could not tell a command from a sentence about one.
// cmdtext.h answers only "what will actually run" — heredoc bodies, quoted
// data and comments are out, chained commands / subshells / `bash -c` strings
// are in. 11 of the ledger's 22 false refusals were this one mistake.
//
// Stripped, because agents write `git -C /path push --force` and
// `git --exec-path=/x push --force`, and every `git\s+push` rule slides right
// past them (both caught live, 31.07). The walk is structural now — every
// leading option, not a hand-kept list (baseline.h).
inline bool rx_test_any(const string& pattern, const std::vector<string>& texts) {
  for (const string& seg : texts) {
    if (rx_test(pattern, seg)) return true;
    const string norm = rbbase::strip_git_globals(seg);
    if (norm != seg && rx_test(pattern, norm)) return true;
  }
  return false;
}

// The texts a deny rule is allowed to see. A command this header cannot parse
// is judged the OLD way — the whole line, one segment at a time — because
// failing toward more refusals is the safe direction. The caller is expected to
// record that it happened (gate.cpp emits PARSE_DEGRADED); a silent fallback
// would hide the one case where the new matcher is not the one deciding.
// A rule that SPELLS A PIPE is asking about something a segment cannot contain.
//
// The surfaces above are one per segment, and cmdtext.h splits on `; && || |`,
// so a pipe character is never present in any of them. A pattern like
//
//   ctest[^|]*\|\s*tail\s+-(n\s*)?[12]\b
//
// therefore cannot fire, in any repository, ever. Sixteen rules on one machine
// were dead and two of these were among them, both authored by the engine itself
// after a real incident: `no-exit-code-after-pipe` (an `echo exit=$?` after a
// pipe reports the last stage's status, so a red suite reads as exit=0) and
// `no-reverse-patch-onto-head`. Each named a thing that had already gone wrong
// once and was free to go wrong again.
//
// The whole line is offered as an extra surface ONLY when the pattern names a
// pipe explicitly, escaped or inside a character class. A bare `|` in a regex is
// alternation and means nothing about pipes. Handing every rule the whole line
// would widen every anchored pattern at once, and a rule that starts refusing
// work it was never written about costs more than a rule that never fires.
inline bool pattern_names_a_pipe(const string& pat) {
  // A NEGATED class is the opposite of naming one. `[^&|;]*` is the single most
  // common fragment in a real guard -- it means "stay inside this segment" --
  // and reading it as "this rule is about pipes" handed the whole raw line to
  // every rule carrying it. The first build did exactly that, and the allow-twin
  // suite caught it one command later: on the raw line a quote satisfied a
  // negative lookahead and a repaired rule started refusing its own allow
  // example. A widening that makes rules refuse honest work is worse than the
  // narrowness it was meant to repair.
  bool inClass = false, negated = false;
  for (size_t i = 0; i < pat.size(); i++) {
    if (pat[i] == '\\') {
      if (i + 1 < pat.size() && pat[i + 1] == '|') return true;
      i++;
      continue;
    }
    if (pat[i] == '[' && !inClass) {
      inClass = true;
      negated = (i + 1 < pat.size() && pat[i + 1] == '^');
    } else if (pat[i] == ']' && inClass) {
      inClass = false;
    } else if (pat[i] == '|' && inClass && !negated) {
      return true;
    }
  }
  return false;
}

inline std::vector<string> texts_of(const rbtext::Parsed& p, const string& cmd) {
  if (p.degraded) return rbtext::raw_segments(cmd);
  std::vector<string> texts;
  for (size_t i = 0; i < p.segs.size(); i++)
    if (!p.segs[i].surface.empty()) texts.push_back(p.segs[i].surface);
  return texts;
}

inline std::vector<string> match_texts(const string& cmd, bool* degraded = nullptr,
                                       string* why = nullptr) {
  const rbtext::Parsed p = rbtext::parse(cmd);
  if (degraded) *degraded = p.degraded;
  if (why) *why = p.why;
  return texts_of(p, cmd);
}

inline bool rx_test_cmd(const string& pattern, const string& cmd) {
  std::vector<string> texts = match_texts(cmd);
  if (pattern_names_a_pipe(pattern)) texts.push_back(cmd);
  return rx_test_any(pattern, texts);
}

// ---------- a deny rule about a PATH is decided by where the path lands ------
// The rule a project writes for itself is a regex, and the most common one by
// far is "no recursive delete outside my tree", spelled as an exclusion around
// the project's own absolute path:
//
//   "deny": "rm\\s+(-\\w*[rf]\\w*\\s+)+(/(?!Users/u/work/proj1)\\S*|~\\S*|\\$HOME\\S*)"
//
// That rule is right about what it wants and blind about what it is looking at.
// It reads the SPELLING, so `/tmp/proj1-build` is "a path that is not the
// project" and the agent that created that directory ninety seconds earlier
// cannot remove it. Nine of the twenty refusals in native/precision_fixture.jsonl
// are this one rule, all nine on the machine's own scratch — while the compiled
// law sitting underneath resolved the very same target and allowed it. One
// question, two answers: the thing cmdtext.h ended for COMMANDS, still open for
// PATHS.
//
// So the rule keeps its pattern, its id and its anchor, and gains the one thing
// it never had: the destination. When a rule that talks about paths matches a
// DELETE and pathres.h says every target of that delete lands in the machine's
// temp area, the text match was answering a different question, and the rule
// does not fire on that segment.
//
// This can only ever SUPPRESS, and only on that one shape:
//   - the pattern must name a filesystem location at all
//   - the segment must be a delete command — the only place "which path" is the
//     entire content of the rule
//   - EVERY target must come back CONTAINED. An unresolved `$`, a brace
//     expansion too wide to compute, one target landing anywhere else: any of
//     them and the refusal stands, because failing toward a refusal is the safe
//     direction and a rule the resolver cannot read is a rule it must not
//     overrule.
// A project that anchored a rule to its own tree still has that rule. A delete
// inside some OTHER project is not disposable, is not suppressed, and is still
// refused under the project's own rule id.
inline bool pattern_names_a_path(const string& p) {
  return p.find('/') != string::npos || p.find('~') != string::npos ||
         p.find("$HOME") != string::npos || p.find("$TMPDIR") != string::npos;
}

inline bool all_targets_disposable(const rbtext::Seg& sg, const string& cwd) {
  const rbpath::Delete d = rbpath::delete_of(sg.words);
  if (!d.isDelete || d.targets.empty()) return false;
  for (size_t i = 0; i < d.targets.size(); i++)
    if (rbpath::land_of(d.targets[i], cwd, string()).where != rbpath::CONTAINED) return false;
  return true;
}

// One rule against one whole command, segment by segment — because the
// suppression above has to be decided where the delete actually is, and
// because a segment is judged in the directory it really runs in (the `cd`
// walk both layers now share, rbpath::segment_cwds).
inline bool rule_refuses(const string& pattern, const rbtext::Parsed& p, const string& cmd,
                         const string& cwd) {
  // a line the parser could not read is judged the OLD way, whole segments of
  // raw text: no words, so no targets, so nothing to resolve.
  if (p.degraded) return rx_test_any(pattern, rbtext::raw_segments(cmd));
  // a pattern that spells a pipe is asking about the whole line, and no segment
  // can ever contain one. see pattern_names_a_pipe for why this is offered only
  // to the rules that ask for it.
  if (pattern_names_a_pipe(pattern)) {
    const std::vector<string> whole(1, cmd);
    if (rx_test_any(pattern, whole)) return true;
  }
  const bool pathRule = pattern_names_a_path(pattern);
  const std::vector<string> cwds = rbpath::segment_cwds(p, cwd);
  for (size_t i = 0; i < p.segs.size(); i++) {
    if (p.segs[i].surface.empty()) continue;
    const std::vector<string> one(1, p.segs[i].surface);
    if (!rx_test_any(pattern, one)) continue;
    if (pathRule && all_targets_disposable(p.segs[i], cwds[i])) continue;
    return true;
  }
  return false;
}

// ---------- the whole verdict, in one call ----------
// Everything that can refuse a Bash command before it runs: the project's own
// deny rules first (so a refusal carries THEIR id and THEIR reason), then the
// three laws compiled into the binary as the floor underneath. Callers that
// skip this and re-implement half of it are how exec came to be a bypass.
struct Verdict { bool refused = false; string id, why, detail; };

// `parsedOut`, when given, hands back the ONE parse both layers were judged on.
// It exists because the gate needs that parse's own diagnostics (a line it could
// not read, a limit it reached) for the ledger, and used to get them by
// re-implementing this function inline — which is exactly the caller the
// paragraph above warns about, sitting in the binary the paragraph was written
// for. native/gate_bench.sh holds the two together from now on: it replays the
// precision fixture through the shipped gate binary and through this call, and
// refuses to print a timing unless all 34 verdicts agree.
inline Verdict judge_command(const string& guard, const string& cmd, const string& cwd,
                             rbtext::Parsed* parsedOut = nullptr) {
  Verdict v;
  if (cmd.empty()) return v;
  const std::vector<string> disabled = parse_disabled(guard);
  // parsed ONCE for every rule AND for both layers: the gate has a 2.3ms budget,
  // the surface walk is O(len) not O(len × rules), and — the reason this header
  // exists — a second walk is a second answer to the same question.
  const rbtext::Parsed parsed = rbtext::parse(cmd);
  if (parsedOut) *parsedOut = parsed;
  // resolved once, and the SAME cwd both layers judge against: a rule that is
  // about a path cannot be given a different starting directory than the law
  // underneath it without the two disagreeing again.
  const string realCwd = rbpath::resolve_real(rbpath::lexical_abs(cwd, "/"));
  if (!guard.empty()) {
    for (const auto& r : parse_rules(guard, "bash", "deny", disabled)) {
      if (rule_refuses(r.pattern, parsed, cmd, realCwd)) {
        v.refused = true; v.id = r.id; v.why = r.why;
        v.detail = "command matched deny rule: " + cmd.substr(0, 160);
        return v;
      }
    }
  }
  // ---------- the guards the LINE reaches, not the one the session sits in ----
  // The pass above judges the session's own guard, loaded once from cwd. That
  // was the whole of it, and it meant a session started in $HOME — which is how
  // an agent working across several repositories runs all day — loaded no rules
  // at all. The owner's rules were not overridden or disabled, they were absent,
  // and only the compiled-in floor was left. Measured on 2 August: `cd <project>
  // && git commit -m "note: x"` and `git -C <project> commit ...` both walked
  // past a rule that refuses them when the session happens to stand there.
  //
  // The baseline laws never had this hole because they follow the shell.
  // segment_cwds() already computes where each half of the line runs and
  // git_repo_knobs() already reads which repository `git -C` points at. Only
  // the guard loader was still asking once, at the top, about one directory.
  //
  // ADDITIVE AND ONLY ADDITIVE. A guard found beside a segment may REFUSE that
  // segment and can never permit one: its disabled[] is not read here, so
  // walking into a directory cannot switch a law off. guard.json is a file
  // inside a tree that the agent may write to, and guard-weaken governs the
  // session's own guard, not one it wanders into. A reachable guard that could
  // waive rules would be this same hole spelled backwards.
  //
  // The owner still overrides: disabled[] in the guard at `cwd` is read by the
  // pass above and by the laws below, because that one the operator opted into
  // by standing there.
  if (!parsed.degraded) {
    const std::vector<string> cwds = rbpath::segment_cwds(parsed, realCwd);
    const string ownRoot = rbpath::project_root(realCwd);
    std::vector<string> seenRoots;
    for (size_t i = 0; i < parsed.segs.size(); i++) {
      if (parsed.segs[i].surface.empty()) continue;
      // where this segment really acts: the directory it runs in, and for git,
      // the repository the line points it at (`-C`, --git-dir, GIT_DIR=)
      string dir = cwds[i];
      const std::vector<rbtext::Word>& t = parsed.segs[i].words;
      const size_t ci = rbtext::command_index(t);
      if (ci < t.size() && rbtext::name_is(rbtext::base_of(t[ci].text), "git")) {
        size_t sub = 0;
        if (rbtext::git_subcommand(t, ci, sub)) {
          std::vector<string> chdirs; string gitDirOpt;
          if (rbtext::git_repo_knobs(t, ci, sub, chdirs, gitDirOpt))
            for (size_t k = 0; k < chdirs.size(); k++)
              dir = rbpath::lexical_abs(chdirs[k], dir);
        }
      }
      const string root = rbpath::project_root(rbpath::resolve_real(dir));
      if (root.empty() || root == ownRoot) continue;   // already judged above
      bool already = false;
      for (size_t k = 0; k < seenRoots.size(); k++) if (seenRoots[k] == root) already = true;
      if (already) continue;
      seenRoots.push_back(root);
      string reached;
      { std::ifstream gf((root + "/.rabadon/guard.json").c_str(), std::ios::binary);
        if (!gf) continue;
        std::ostringstream ss; ss << gf.rdbuf(); reached = ss.str(); }
      if (reached.empty()) continue;
      const std::vector<string> none;
      for (const auto& r : parse_rules(reached, "bash", "deny", none)) {
        const std::vector<string> one(1, parsed.segs[i].surface);
        if (!rx_test_any(r.pattern, one)) continue;
        if (pattern_names_a_path(r.pattern) && all_targets_disposable(parsed.segs[i], cwds[i])) continue;
        v.refused = true; v.id = r.id; v.why = r.why;
        v.detail = "command matched deny rule of the project it reaches into (" + root +
                   "): " + cmd.substr(0, 160);
        return v;
      }
    }
  }

  rbbase::Hit bh;
  if (rbbase::check_parsed(parsed, cwd, disabled, bh)) {
    v.refused = true; v.id = bh.id; v.why = bh.why; v.detail = bh.detail;
  }
  return v;
}

} // namespace rbrules
