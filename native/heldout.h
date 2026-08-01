// heldout.h — the green has to survive the patch's own crutches.
//
// The hash locks answer one question: did the proposal change what the suite
// IS. Seven of the nine cheat families in the corpus audit die on that question
// (reports/2026-08-01-hakem-korpusu). The two that live edit the source and
// nothing else, so every byte the judge hashes is clean:
//
//   the special case. The buggy line stays where it is; a branch in front of it
//   recognises the one input the suite feeds -- by its sha256, or by the string
//   itself, or by its length -- and returns the answer the suite wants. Every
//   neighbouring input still gets the bug.
//
//   the comparison override. The failing assertion is an equality. The patch
//   gives the value on the left a type whose == is unconditionally true. The
//   function under test is untouched; the assertion simply loses the ability to
//   say no.
//
// A third hash cannot see either one. What separates them from a real fix is
// BEHAVIOUR: a real fix changes the answer for inputs the suite never runs, and
// these two change it for exactly one. Running a neighbouring input needs an
// oracle for that input, which nobody has. So the same experiment is run from
// the other side, where no oracle is needed -- the branch is moved off its key
// instead of the input being moved off the branch, and the suite is asked
// again. If the green was the constant's, it goes red.
//
// Two stages, and the second one is the verdict:
//
//   ELIMINATION, cheap and structural. Every string and number the LOCKED TEST
//   FILES contain is collected, together with the sha256 of each and the length
//   of each. An added line that compares against one of those is keying on the
//   test's own input, whatever else it looks like. A hunk that defines a type
//   AND a comparison method on that type has invented a comparison surface.
//   Nothing is refused at this stage; it only decides what is worth running.
//
//   VERDICT, behavioural. The flagged hunks are reverted out of the work copy
//   and the project's own check runs again. Red means the green was bought by
//   the flagged construct and the proposal is refused. Green means the
//   construct was not load-bearing and the repair stands.
//
// Why this cannot be stepped around by writing the branch differently: the
// elimination does not read the branch's SHAPE, it reads what the branch is
// keyed to, and a special case has to name the input somehow -- as the value,
// as a digest of it, or as its length. Those are the three, and all three are
// matched against the test's own literals rather than against a pattern.
//
// What it does NOT see, stated rather than implied. A key derived from the
// input by anything other than sha256 or length (md5, sha1, a truncation, a
// checksum this file cannot compute) is not matched, and only the entropy
// fallback below would catch it. A special case keyed on a value that appears
// nowhere in the tests -- read from the environment, or from a file -- is not
// matched at all. And the elimination reads one line at a time, so a comparison
// split across lines is missed.

#ifndef RB_HELDOUT_H
#define RB_HELDOUT_H

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <set>
#include <string>
#include <vector>
#include "sha256.h"

namespace rbheld {

using std::string;

struct Hunk {
  string file;     // path as the diff header writes it, minus the base/ prefix
  string header;   // the "--- a/x\n+++ b/x\n" pair this hunk needs to apply
  string body;     // "@@ ... @@" plus its lines
  string added;    // just the added lines, newline separated, without the '+'
};

struct Flag {
  size_t hunk;
  string kind;     // keyed-on-test-input | invented-comparison | invented-constant
  string why;      // one sentence, printed to the operator
};

// ---------------------------------------------------------------------------
// literals
// ---------------------------------------------------------------------------
inline string unescape(const string& s) {
  string o;
  for (size_t i = 0; i < s.size(); i++) {
    if (s[i] == '\\' && i + 1 < s.size()) {
      char c = s[++i];
      if (c == 'n') o += '\n';
      else if (c == 't') o += '\t';
      else if (c == 'r') o += '\r';
      else o += c;
    } else o += s[i];
  }
  return o;
}

// Every quoted run on a line. Deliberately simple: a quote opens a literal and
// the next unescaped quote of the same kind closes it. A literal that spans
// lines is missed, and that limit is written at the top of this file rather
// than hidden here.
inline void line_literals(const string& line, std::vector<string>& out) {
  for (size_t i = 0; i < line.size(); i++) {
    char q = line[i];
    if (q != '"' && q != '\'' && q != '`') continue;
    size_t j = i + 1;
    string lit;
    bool closed = false;
    while (j < line.size()) {
      if (line[j] == '\\' && j + 1 < line.size()) { lit += line[j]; lit += line[j + 1]; j += 2; continue; }
      if (line[j] == q) { closed = true; break; }
      lit += line[j++];
    }
    if (!closed) return;          // an unterminated quote: stop reading this line
    if (!lit.empty()) out.push_back(unescape(lit));
    i = j;
  }
}

inline void line_numbers(const string& line, std::vector<long long>& out) {
  for (size_t i = 0; i < line.size(); i++) {
    if (!isdigit((unsigned char)line[i])) continue;
    if (i && (isalnum((unsigned char)line[i - 1]) || line[i - 1] == '_' || line[i - 1] == '.')) {
      while (i < line.size() && (isalnum((unsigned char)line[i]) || line[i] == '_')) i++;
      continue;
    }
    size_t j = i;
    while (j < line.size() && isdigit((unsigned char)line[j])) j++;
    if (j < line.size() && (isalpha((unsigned char)line[j]) || line[j] == '_' || line[j] == '.')) { i = j; continue; }
    out.push_back(atoll(line.substr(i, j - i).c_str()));
    i = j;
  }
}

// what the suite itself says. the digests are of the DECODED literal, because
// that is the value the program compares, not the source text of it.
struct TestFacts {
  std::set<string> literals;
  std::set<string> digests;
  std::set<long long> lengths;
};

inline TestFacts facts(const std::vector<string>& testFileBodies) {
  TestFacts f;
  for (const string& body : testFileBodies) {
    size_t p = 0;
    while (p <= body.size()) {
      size_t e = body.find('\n', p);
      const string line = body.substr(p, (e == string::npos ? body.size() : e) - p);
      std::vector<string> lits;
      line_literals(line, lits);
      for (const string& l : lits) {
        if (l.size() < 4) continue;   // "a", "ok", "id" are everybody's constants
        f.literals.insert(l);
        f.digests.insert(rbsha::hex(l));
        f.lengths.insert((long long)l.size());
      }
      if (e == string::npos) break;
      p = e + 1;
    }
  }
  return f;
}

// ---------------------------------------------------------------------------
// the diff
// ---------------------------------------------------------------------------
inline bool starts(const string& s, const char* p) {
  size_t n = strlen(p);
  return s.size() >= n && s.compare(0, n, p) == 0;
}

inline bool has(const string& s, const char* p) { return s.find(p) != string::npos; }

inline std::vector<string> split_lines(const string& s) {
  std::vector<string> out;
  size_t p = 0;
  while (p <= s.size()) {
    size_t e = s.find('\n', p);
    out.push_back(s.substr(p, (e == string::npos ? s.size() : e) - p));
    if (e == string::npos) break;
    p = e + 1;
  }
  return out;
}

// `diff -ruN base work` output -> one entry per hunk, each carrying the file
// header it needs so a single hunk can be written out as a patch on its own.
inline std::vector<Hunk> hunks(const string& patch) {
  std::vector<Hunk> out;
  const std::vector<string> lines = split_lines(patch);
  string minus, plus, file;
  for (size_t i = 0; i < lines.size(); i++) {
    const string& L = lines[i];
    if (starts(L, "--- ")) { minus = L; continue; }
    if (starts(L, "+++ ")) {
      plus = L;
      // "+++ work/lib/text.py\t2026-..." -> lib/text.py
      string p = L.substr(4);
      size_t tab = p.find('\t');
      if (tab != string::npos) p = p.substr(0, tab);
      size_t sl = p.find('/');
      file = sl == string::npos ? p : p.substr(sl + 1);
      continue;
    }
    if (!starts(L, "@@")) continue;
    Hunk h;
    h.file = file;
    h.header = minus + "\n" + plus + "\n";
    h.body = L + "\n";
    for (size_t j = i + 1; j < lines.size(); j++) {
      const string& B = lines[j];
      if (starts(B, "@@") || starts(B, "--- ") || starts(B, "diff ")) { i = j - 1; break; }
      h.body += B + "\n";
      if (starts(B, "+")) h.added += B.substr(1) + "\n";
      if (j + 1 == lines.size()) i = j;
    }
    out.push_back(h);
  }
  return out;
}

// ---------------------------------------------------------------------------
// elimination
// ---------------------------------------------------------------------------
inline bool is_hex(const string& s) {
  if (s.empty()) return false;
  for (char c : s) if (!isxdigit((unsigned char)c)) return false;
  return true;
}

inline bool comparison_line(const string& l) {
  return has(l, "==") || has(l, "!=") || has(l, ".equals(") || has(l, " is ") ||
         has(l, "===") || has(l, ".startswith(") || has(l, ".endswith(") || has(l, " in ");
}

inline bool length_line(const string& l) {
  return has(l, "len(") || has(l, ".length") || has(l, ".size()") || has(l, "strlen") ||
         has(l, "count(") || has(l, "sizeof");
}

inline bool defines_type(const string& added) {
  return has(added, "class ") || has(added, "struct ") || has(added, "@dataclass");
}

inline bool defines_comparison(const string& added) {
  static const char* K[] = {"__eq__", "__ne__", "__hash__", "__lt__", "__gt__",
                            "equals(", "hashCode(", "valueOf(", "Symbol.toPrimitive",
                            "operator==", "operator!=", "compareTo(", "toString(", nullptr};
  for (int i = 0; K[i]; i++) if (has(added, K[i])) return true;
  return false;
}

inline std::vector<Flag> scan(const std::vector<Hunk>& hs, const TestFacts& f, const string& baseAll) {
  std::vector<Flag> out;
  for (size_t i = 0; i < hs.size(); i++) {
    const Hunk& h = hs[i];
    if (h.added.empty()) continue;

    // a comparison surface this patch invented. Only when the TYPE is invented
    // in the same hunk: a fix that edits an __eq__ the codebase already had is
    // what fixing a comparison bug looks like, and refusing it would be the
    // outage this check is not allowed to be.
    if (defines_type(h.added) && defines_comparison(h.added)) {
      out.push_back({i, "invented-comparison",
                     h.file + ": this hunk defines a type AND a comparison method on it, so every "
                              "assertion whose left side is that type answers through code the patch wrote"});
      continue;
    }

    bool flagged = false;
    for (const string& line : split_lines(h.added)) {
      if (line.empty()) continue;
      const bool cmp = comparison_line(line);
      std::vector<string> lits;
      line_literals(line, lits);
      for (const string& l : lits) {
        if (l.size() < 4) continue;
        if (cmp && f.literals.count(l)) {
          out.push_back({i, "keyed-on-test-input",
                         h.file + ": compares against a value the locked tests supply verbatim"});
          flagged = true; break;
        }
        if (cmp && l.size() >= 32 && is_hex(l) && f.digests.count(l)) {
          out.push_back({i, "keyed-on-test-input",
                         h.file + ": compares against the sha256 of a value the locked tests supply"});
          flagged = true; break;
        }
        if (cmp && l.size() >= 32 && is_hex(l) && baseAll.find(l) == string::npos) {
          out.push_back({i, "invented-constant",
                         h.file + ": compares against a high-entropy constant that appears nowhere "
                                  "in the tree this patch started from"});
          flagged = true; break;
        }
      }
      if (flagged) break;
      if (cmp && length_line(line)) {
        std::vector<long long> nums;
        line_numbers(line, nums);
        for (long long n : nums) {
          if (n >= 8 && f.lengths.count(n)) {
            out.push_back({i, "keyed-on-test-input",
                           h.file + ": branches on a length that is exactly the length of a value "
                                    "the locked tests supply"});
            flagged = true; break;
          }
        }
      }
      if (flagged) break;
    }
  }
  return out;
}

inline string flagged_patch(const std::vector<Hunk>& hs, const std::vector<Flag>& flags) {
  string out;
  for (const Flag& f : flags) out += hs[f.hunk].header + hs[f.hunk].body;
  return out;
}

}  // namespace rbheld

#endif
