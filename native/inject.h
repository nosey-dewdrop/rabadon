// inject.h — R4. The history the agent cannot see, put where it will read it.
//
// WHY THIS FILE EXISTS
// R1 recorded the moves, R2 and R3 learned to see the patterns in them, and
// both stopped there: a signal reached the ledger and nobody who could act on
// it ever read it. That is complaint 2 in the plan — "it catches things but it
// does not solve them, and the cost goes up". The agent is not the wrong party
// to fix its own error; it is simply the one party that cannot see the history
// that would tell it how. So the history goes into its context on the front of
// its next tool call, through PreToolUse additionalContext, and the repair is
// written by the model the user is already paying for.
//
// LAW 6 — NO SECOND MODEL CALL, AND A HARD CHARACTER BUDGET.
// Every sentence below is assembled from the move ring and the ledger. Nothing
// here forks, dials out, or asks anything. And every character injected is
// charged to the user's own session, so MAX_CHARS is an edge, not a target:
// build() clips and never returns more.
//
// LAW 2 — FILE, NEVER A LINE.
// On SWE-bench Verified file-level localisation is the dominant factor and
// line-level context raises noise and frequently LOWERS the score. Naming a
// line is not merely useless, it is an active harm. scrub() strips every form a
// line number takes out of the FINAL assembled string rather than out of each
// input, because the inputs include a shell command and an error line that
// nobody in this file controls.
//
// LAW 3 — THE CONTRAST IS THE VALUABLE SENTENCE.
// ContrastRepair's measured result: given a passing/failing PAIR the model
// finds the root cause markedly better than it does from the failure alone. The
// move record already holds that pair — one move left the suite green, a later
// one did not — so the most valuable half of this text costs nothing to
// produce.
//
// INFORMATION, NOT ADVICE. There is no sentence here telling the agent what to
// do. It knows how to fix code; what it does not know is what already failed.
#pragma once

#include <string>
#include <vector>
#include <cstdlib>
#include "moves.h"

namespace rbinject {

using std::string;

// Law 6, as a number. 400 characters is the plan's budget and the counter (R6)
// charges the session for what is spent here, so this is enforced by clipping
// rather than by hoping the template stays short.
static const size_t MAX_CHARS = 400;

// The plan: the same signal NAME injects at most twice in one session. The
// third occurrence is a ledger line and, from R5 on, the trigger for the repair
// arm — a supervisor that says the same paragraph every turn is one the
// operator learns to skim, and every repetition is billed.
static const int CAP_PER_SIGNAL = 2;

inline bool enabled() {
  const char* v = getenv("RABADON_INJECT");
  return !(v && v[0] == '0' && v[1] == '\0');
}

// WHICH SIGNALS ARE ALLOWED TO SPEAK. The three levels of R4, in one function:
//   certain -> blocks, and never reaches here.
//   likely  -> injects. EXACTLY the four the plan promoted: semantic repeat,
//              oscillation, root migration, and the
//              red->green-where-only-the-test-side-moved subset.
//   weak    -> ledger only; the agent never sees it. Two rules live here.
//              scope_drift is known to be the weakest in signals.h: it counts
//              directories, and an honest refactor touches many. `repeat` is
//              here because the plan did not promote it and a level is not
//              something an implementation gets to hand out — the same command
//              run three times is often a watcher, a flaky suite, or a human
//              re-reading output, and its false positive rate has never been
//              measured. It moves up when R2's spool says it may.
//
// green_redefined is split by its own `why`, not by its name: the "edited while
// the suite was red" arm is the deterministic subset that the gate BLOCKS, so
// injecting it as well would say the same thing twice, once as a refusal and
// once as a paragraph.
inline bool speaks(const string& name, const string& why) {
  if (name == "oscillation" || name == "root_migration" ||
      name == "semantic_repeat") return true;
  if (name == "green_redefined")
    return why.find("only the test side") != string::npos;
  // KOSU v9 §5 tetik yamasi
  if (name == "repeat") return why.find("same failure") != string::npos;
  return false;
}

// ---------------------------------------------------------------------------
// scrub — Law 2, applied to the finished string.
//
// Removes every shape a line reference takes: `file.js:120`, `:120:5`,
// `line 44`, `L44`. It runs LAST, over the whole assembled text, because the
// error line and the shell command inside it are somebody else's bytes. The
// attempt number survives (`attempt 3` has no colon and is not the word
// "line"), and it must: Law 3 asks for it by name.
inline string scrub(const string& in) {
  string out;
  out.reserve(in.size());
  for (size_t i = 0; i < in.size();) {
    // :123  or  :123:4
    if (in[i] == ':' && i + 1 < in.size() && rbmoves::is_dig(in[i + 1])) {
      i++;
      while (i < in.size() && (rbmoves::is_dig(in[i]) || in[i] == ':')) i++;
      continue;
    }
    // "line 44" / "Line 44"
    if ((in[i] == 'l' || in[i] == 'L') && i + 4 <= in.size() && in.compare(i + 1, 3, "ine") == 0) {
      size_t j = i + 4;
      while (j < in.size() && (in[j] == ' ' || in[j] == '#')) j++;
      if (j < in.size() && rbmoves::is_dig(in[j]) && j > i + 4) {
        while (j < in.size() && rbmoves::is_dig(in[j])) j++;
        i = j;
        continue;
      }
    }
    // bare L44
    if (in[i] == 'L' && i + 1 < in.size() && rbmoves::is_dig(in[i + 1]) &&
        (i == 0 || !isalnum((unsigned char)in[i - 1]))) {
      size_t j = i + 1;
      while (j < in.size() && rbmoves::is_dig(in[j])) j++;
      if (j >= in.size() || !isalnum((unsigned char)in[j])) { i = j; continue; }
    }
    out += in[i++];
  }
  return rbmoves::squeeze(out);
}

// characters, not bytes — the budget the counter charges is a character budget,
// and one non-ASCII word must not be able to blow through it by accident.
inline size_t nchars(const string& s) {
  size_t n = 0;
  for (size_t i = 0; i < s.size(); i++)
    if (((unsigned char)s[i] & 0xC0) != 0x80) n++;
  return n;
}

// utf8-safe clip: cutting inside a multi-byte character would put half a rune
// into the context window, and the budget is counted in characters anyway.
inline string clip_chars(const string& s, size_t maxChars) {
  size_t chars = 0, i = 0;
  while (i < s.size()) {
    const unsigned char c = (unsigned char)s[i];
    const size_t step = c < 0x80 ? 1 : (c >> 5) == 0x6 ? 2 : (c >> 4) == 0xE ? 3 : (c >> 3) == 0x1E ? 4 : 1;
    if (chars + 1 > maxChars) break;
    i += step; chars++;
  }
  return s.substr(0, i);
}

// THE READABLE FORM OF err_sig. err_sig is a hash — it answers "is this the
// same error" and it cannot be shown to anybody. The first line of the output
// that looks like an error is what a human would quote, so it is what the agent
// gets, with the scratch paths and the project root taken off it first (the
// same masking moves.h hashes through, so what is shown matches what was
// bucketed).
inline string readable_error(const string& out, const string& root) {
  size_t i = 0;
  while (i < out.size()) {
    size_t e = out.find('\n', i);
    if (e == string::npos) e = out.size();
    const string line = out.substr(i, e - i);
    i = e + 1;
    if (!rbmoves::error_line(line)) continue;
    return clip_chars(rbmoves::squeeze(rbmoves::mask_scratch(rbmoves::relativise(line, root))), 120);
  }
  return string();
}

// ---------------------------------------------------------------------------
struct Ctx {
  string signal;      // the detector that spoke
  string why;         // its one clause, already written for the ledger
  int    attempt = 0; // how many moves this pattern is made of
  string file;        // the file last edited — Law 2's half that is required
  string err;         // readable_error(), may be empty
  string greenCmd;    // the newest move after which the suite was green
  string redCmd;      // the newest move after which it was not
  bool   redIsSuite = false;  // was that move a suite run, or just a failure
};

// The order of the sentences is the order they are worth: what this is, where
// it is, what broke, the contrast, and the detector's own clause last — because
// if the 400-character clip ever bites, the clause is the sentence the agent
// can most afford to lose.
inline string build(const Ctx& c) {
  string s = "rabadon: attempt " + std::to_string(c.attempt) + " on the same failure.";
  if (!c.file.empty()) s += " The file last edited is " + c.file + ".";
  if (!c.err.empty())  s += " The previous attempt ended with: " + c.err + ".";
  if (!c.greenCmd.empty() && !c.redCmd.empty())
    s += " Contrast: after `" + c.greenCmd + "` the suite was green; after `" + c.redCmd +
         (c.redIsSuite ? "` it was red." : "` it failed with that error.");
  else if (!c.greenCmd.empty())
    s += " Contrast: after `" + c.greenCmd + "` the suite was green, and nothing has been green since.";
  else if (!c.redCmd.empty())
    s += " Contrast: no green move is on record this session; after `" + c.redCmd + "` it failed.";
  if (!c.why.empty()) s += " Signal " + c.signal + ": " + c.why + ".";
  return clip_chars(scrub(s), MAX_CHARS);
}

} // namespace rbinject
