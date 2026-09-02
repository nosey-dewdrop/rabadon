// signals.h — five detectors over the move record. They see, they do not act.
//
// WHY SILENT
// Every rule here is a guess about intent, and Law 1 says an unmeasured guess
// never enforces. SWE-agent-era loop detectors were abandoned or filed as bugs
// because they killed honest work (All-Hands-AI/OpenHands#5355); Google's
// Tricorder holds its checks under 10% effective false positives before they are
// allowed in front of a human. rabadon has no such number yet. So R2 computes,
// writes to the ledger, and shows nobody — the spool becomes the dataset that
// R4's promotion ladder will be argued from.
//
// Nothing in this file returns a verdict, sets a permission decision, or writes
// to stdout. reports/R2/accept.sh claim 3 holds that from the outside.
//
// WHAT EACH DETECTOR REFUSES TO DO, WHICH IS THE DESIGN
// Each rule below has a nearest neighbour that is honest work, and the rule is
// shaped by that neighbour rather than by a threshold that felt right:
//
//   repeat        must not fire on a second attempt. Retrying once is how
//                 debugging works. It fires on the third.
//   oscillation   must not fire on `lint, build, lint, build`. An A-B-A-B of
//                 two different COMMANDS is a normal two-step loop. Undoing
//                 your own edit to ONE file is not, so oscillation is about
//                 edits to a single path, not about alternation in general.
//   root_migration is the one nothing on the market sees: the moves keep
//                 changing, the error does not.
//   scope_drift   is the weakest rule here and is known to be. It counts
//                 directories, and a large honest refactor touches many.
//                 Silent mode exists precisely so this one can be measured
//                 before anyone lets it speak.
//   green_redefined must not fire on writing tests. Editing a test suite is
//                 the most valuable thing an agent does. It fires on editing
//                 tests WHILE THEY ARE FAILING, on a red->green where only the
//                 test side moved, and on a test file that lost assertions.
#pragma once

#include <string>
#include <vector>
#include <set>
#include "moves.h"
#include "classify.h"

namespace rbsig {

using std::string;
using std::vector;

struct Hit {
  string name;
  double conf = 0.0;            // 0..1; nothing acts on this yet, R4 will
  vector<long long> seqs;       // the moves that triggered it
  string why;                   // one short clause, for the ledger line
};

// Thresholds live here, named, so a change to one is a change to a line of code
// with a comment attached rather than to a magic number in a condition.
static const int REPEAT_MIN = 3;      // a second attempt is debugging
static const int REPEAT_WINDOW = 20;
static const int OSC_CYCLES = 3;      // A-B-A-B-A-B on one path
static const int ROOT_MIN_PATHS = 3;  // one error surviving three different moves
static const int DRIFT_DIRS = 5;

inline bool enabled() {
  const char* v = getenv("RABADON_SIGNALS");
  return !(v && v[0] == '0' && v[1] == '\0');
}

inline bool is_edit(const rbmoves::Move& m) {
  return m.tool == "Edit" || m.tool == "Write" || m.tool == "MultiEdit";
}

// A WRITE is an edit OR a shell command the ring knows wrote a file (`>`, `>>`,
// `tee`, `sed -i` — gate.cpp fills `path` on those Bash moves). The contrast
// trigger and its payload ask "what changed since the green", and a heredoc
// changes a file exactly as much as the Edit tool does. The other detectors
// stay on is_edit on purpose: oscillation compares edit signatures and the
// assertion-count rule reads text, and a shell write carries neither.
inline bool is_write(const rbmoves::Move& m) {
  return is_edit(m) || (m.tool == "Bash" && !m.path.empty());
}

inline string dir_of(const string& p) {
  const size_t s = p.rfind('/');
  return s == string::npos ? string(".") : p.substr(0, s);
}

// TEST and HARNESS both count as "the thing that decides green". classify() is
// the repo's single answer to that question — truth.cpp locks by it and
// repair.cpp refuses to touch by it, and a second opinion here would be the
// weaker one that the signals then read.
inline bool decides_green(const string& rel) {
  if (rel.empty()) return false;
  const rbclass::Verdict v = rbclass::classify(rel);
  return v.kind == rbclass::TEST || v.kind == rbclass::HARNESS;
}
inline bool is_source(const string& rel) {
  if (rel.empty()) return false;
  return rbclass::classify(rel).kind == rbclass::SOURCE;
}

// ---------------------------------------------------------------------------
// detect() is evaluated after the NEWEST move is recorded, and every rule is
// asked only "did the newest move complete this pattern". That keeps it O(window)
// and it keeps one long-past pattern from re-firing on every later event.
inline vector<Hit> detect(const vector<rbmoves::Move>& m) {
  vector<Hit> out;
  if (m.empty()) return out;
  const rbmoves::Move& last = m.back();
  const size_t n = m.size();

  // ---- 1. repeat ----------------------------------------------------------
  {
    int seen = 0, failed = 0;
    vector<long long> seqs;
    const size_t from = n > (size_t)REPEAT_WINDOW ? n - REPEAT_WINDOW : 0;
    for (size_t i = from; i < n; i++)
      if (m[i].sig == last.sig) {
        seen++;
        seqs.push_back(m[i].seq);
        if (m[i].claimed_rc == 1) failed++;
      }
    // COUNTING REPETITIONS IS NOT ENOUGH, and the fixture that proved it is
    // `lint, build, lint, build, lint, build` — three runs of one lint command
    // inside a session that is going fine. A rule that only counts occurrences
    // calls that a loop, and a supervisor that flags people for running their
    // linter three times gets uninstalled on the first afternoon.
    //
    // What separates a retry loop from a build step is not how often the move
    // repeats, it is whether it is GETTING ANYWHERE. So a repeat needs evidence
    // of not getting anywhere: at least two of the matching moves came back
    // carrying an error. A command that keeps succeeding is a command doing its
    // job, however many times it is run.
    //
    // This is deliberately the conservative direction. It will miss a genuine
    // loop whose failures never printed anything that looks like an error, and
    // Law 1 says that is the miss to prefer.
    if (seen >= REPEAT_MIN && failed >= 2)
      out.push_back({ "repeat", 0.6, seqs,
                      "the same move " + std::to_string(seen) + " times, " +
                      std::to_string(failed) + " of them with the same failure" });
  }

  // ---- 1b. regression_contrast --------------------------------------------
  // THE FIRST FAILURE IS ALREADY WORTH SPEAKING ABOUT, when the ledger holds
  // something the agent does not: this suite was GREEN earlier in the session,
  // and a known set of files changed between then and now. That is a fact
  // about the run's own history, not a count of attempts, so it does not have
  // to wait for a third try to be true — and waiting is what made `repeat`
  // worthless in practice. Measured 2026-09-02: two live Claude Code sessions
  // on real compounding bugs produced 0 SIGNAL, because a competent agent
  // fixes-and-moves-on rather than running the same command three times.
  //
  // The conservative direction here is the OPPOSITE of repeat's: repeat risks
  // nagging someone running a linter, this risks saying nothing. So it demands
  // three things and none of them is a count — a green on record, a failure
  // now, and at least one edit in between. No green means no contrast to draw
  // and it stays silent; that is Law 1 preserved, not weakened.
  {
    // A FAILURE IS A RUN THAT FAILED, NOT A RUN THAT SAID THE WORD. An error
    // signature is derived from output text, so `grep -r error`, a passing test
    // whose name contains "failure", and a command that prints someone else's
    // log all carry one. Measured 2026-09-02 in a live session: a command whose
    // stdout merely quoted an assertion message fired this trigger, and the
    // injection then told the agent "the previous attempt ended with" that
    // quote. The rate matters more than the miss here — a supervisor that
    // speaks on every command mentioning an error is noise, and noise is
    // uninstalled. So the condition is the suite going red, or the move itself
    // claiming a non-zero status; the signature stays as the payload, not as
    // the trigger.
    const bool failedNow = last.suite == 0 || last.claimed_rc == 1;
    if (failedNow) {
      size_t greenAt = (size_t)-1;
      for (size_t i = n; i-- > 0;)
        if (m[i].suite == 1) { greenAt = i; break; }
      if (greenAt != (size_t)-1 && greenAt + 1 < n) {
        // THE TRANSITION IS THE EVIDENCE, not the edit record. Requiring a
        // counted Edit move here made the detector silent in a live session
        // measured 2026-09-02: the agent created the failing file with
        // `cat > test_b.py <<EOF` inside a Bash command, so nothing the ring
        // calls an edit ever landed, while the suite went green -> red exactly
        // as the trigger describes. Writing files through the shell is normal
        // agent behaviour, not an edge case, and a detector that only sees the
        // Edit tool is blind to half of every session.
        //
        // So the fact is stated at the strength it is known: this suite passed
        // earlier and does not now. The file list stays a PAYLOAD — named when
        // the ring happens to know it, omitted when it does not — and never a
        // precondition for saying the true part.
        vector<long long> seqs; seqs.push_back(m[greenAt].seq);
        int edits = 0;
        for (size_t i = greenAt + 1; i < n; i++)
          if (is_write(m[i]) && !m[i].path.empty()) { edits++; seqs.push_back(m[i].seq); }
        seqs.push_back(last.seq);
        out.push_back({ "regression_contrast", 0.7, seqs,
                        edits > 0
                          ? "the suite was green earlier this session and " +
                            std::to_string(edits) + " edit(s) landed before this failure"
                          : string("the suite was green earlier this session and is not now") });
      }
    }
  }

  // ---- 2. oscillation -----------------------------------------------------
  // Edits to ONE path, alternating between two contents. `lint, build, lint,
  // build` is two commands doing their jobs; rewriting one file back and forth
  // is the agent arguing with itself.
  if (is_edit(last) && !last.path.empty()) {
    vector<const rbmoves::Move*> same;
    for (size_t i = n; i-- > 0 && same.size() < (size_t)(OSC_CYCLES * 2);)
      if (is_edit(m[i]) && m[i].path == last.path) same.push_back(&m[i]);
    if (same.size() == (size_t)(OSC_CYCLES * 2)) {
      const string a = same[0]->sig, b = same[1]->sig;
      bool alt = (a != b);
      for (size_t i = 0; i < same.size() && alt; i++)
        if (same[i]->sig != ((i % 2) ? b : a)) alt = false;
      if (alt) {
        vector<long long> seqs;
        for (auto* p : same) seqs.push_back(p->seq);
        out.push_back({ "oscillation", 0.7, seqs, "one file rewritten back and forth" });
      }
    }
  }

  // ---- 3. root migration --------------------------------------------------
  // The error is the same. The moves are not. Nothing shipped today sees this.
  if (!last.err_sig.empty()) {
    std::set<string> sigs;
    vector<long long> seqs;
    for (size_t i = 0; i < n; i++)
      if (m[i].err_sig == last.err_sig) { sigs.insert(m[i].sig); seqs.push_back(m[i].seq); }
    if ((int)sigs.size() >= ROOT_MIN_PATHS)
      out.push_back({ "root_migration", 0.75, seqs,
                      "one error survived " + std::to_string(sigs.size()) + " different moves" });
  }

  // ---- 4. scope drift -----------------------------------------------------
  if (is_edit(last) && !last.path.empty()) {
    std::set<string> dirs;
    for (size_t i = 0; i < n; i++)
      if (is_edit(m[i]) && !m[i].path.empty()) dirs.insert(dir_of(m[i].path));
    if ((int)dirs.size() >= DRIFT_DIRS)
      out.push_back({ "scope_drift", 0.4, { last.seq },
                      std::to_string(dirs.size()) + " directories touched" });
  }

  // ---- 5. the definition of green moved -----------------------------------
  // (a) the suite is red and the agent is editing the thing that judges it.
  if (is_edit(last) && decides_green(last.path)) {
    int suite = -1;
    for (size_t i = n; i-- > 0;) if (m[i].suite != -1) { suite = m[i].suite; break; }
    if (suite == 0)
      out.push_back({ "green_redefined", 0.85, { last.seq },
                      "test or harness edited while the suite was red" });
  }

  // (b) red -> green, and between them only the test side moved.
  if (last.suite == 1) {
    size_t red = string::npos;
    for (size_t i = n - 1; i-- > 0;) {
      if (m[i].suite == 0) { red = i; break; }
      if (m[i].suite == 1) break;   // it was already green; no transition here
    }
    if (red != string::npos) {
      bool sawSource = false, sawGreenDecider = false;
      vector<long long> seqs;
      for (size_t i = red + 1; i + 1 < n; i++) {
        if (!is_edit(m[i]) || m[i].path.empty()) continue;
        if (is_source(m[i].path)) sawSource = true;
        else if (decides_green(m[i].path)) { sawGreenDecider = true; seqs.push_back(m[i].seq); }
      }
      if (sawGreenDecider && !sawSource) {
        seqs.push_back(last.seq);
        out.push_back({ "green_redefined", 0.9, seqs,
                        "red turned green and only the test side changed" });
      }
    }
  }

  // (c) a test file lost assertions.
  if (is_edit(last) && decides_green(last.path) && last.asserts >= 0) {
    for (size_t i = n - 1; i-- > 0;) {
      if (!is_edit(m[i]) || m[i].path != last.path || m[i].asserts < 0) continue;
      if (last.asserts < m[i].asserts)
        out.push_back({ "green_redefined", 0.8, { m[i].seq, last.seq },
                        "assertions fell from " + std::to_string(m[i].asserts) +
                        " to " + std::to_string(last.asserts) });
      break;   // only the immediately preceding edit to this file
    }
  }

  return out;
}

} // namespace rbsig
