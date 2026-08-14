// drill.h — ONE definition of "this spool line is rabadon's own noise".
//
// rabadon's brand claim is that it never counts its own self-tests as catches.
// That claim is only worth the surface with the loosest reading of it, so the
// four rules live here once and ALL THREE readers of the spool call the same
// code:
//
//   rabadon-stats   the local number, read by the operator who knows what a
//                   drill is;
//   rabadon-export  OTLP spans pushed OFF the machine into a shared Jaeger /
//                   Grafana / Langfuse, where a refusal renders red and nobody
//                   can tell a bench run from a production catch;
//   rabadon-trace   one run drawn step by step — the prettiest surface in the
//                   product and the one that gets screenshotted into a pitch.
//
// This list said "both readers" and named the first two. trace was the third,
// and it contained zero occurrences of the word drill: the exact 18 events of a
// self-run on pipe do-test:do rendered "CAUGHT 2 · REPAIRED 2 · verdict: PASS"
// and the saved-money line, while stats said "no events in this window" and
// export emitted 0 spans over the same bytes. A predicate with a caller that
// does not call it is worse than a copy that drifts — nothing tells you.
// Anything that grows a fourth reader adds itself to this list or it is a bug.
//
// export used to apply rule 1 alone, as a raw substring match, and shipped the
// other three shapes as ERROR spans — on this machine, 7 events dropped out of
// 3,495 the local number excluded. A second copy of a predicate is a copy that
// drifts; the honest surface has to be the one that leaves the house.
//
// The five rules (all of them exclude; none of them is sufficient alone):
//   1. the emit tag        "drill":true written by the emitter itself;
//   2. session-id markers  fleet-N / doctor-N / drill-N anywhere on the line;
//   3. the self pipe       rabadon's own bench/demo/test pipes;
//   4. window association  an untagged event inside the same pipe within
//                          kRbDrillWindowMs of a marker event is drill fallout;
//   5. the unwatched stub  a repair that closed faster than a model can answer,
//                          on a pipe where no action was ever gated.
//
// Rules 1-4 all trust the harness to announce itself, and on 2026-08-14 that
// cost the headline. `rabadon usage --days 30` read 46 repairs held; 44 came
// from one pipe named "A" — 342 seconds on 2026-08-05, 70 REPAIR_START, 50
// REPAIR_OK, every one carrying locks:1, driving `python3 test_calc.py`. It was
// a scratch fixture run by hand against the real ledger, and it is in no
// committed script, so nothing will ever go back and tag it. Rule 1 missed it
// (not emit-tagged), rule 2 missed it (no marker in the session id), rule 3
// missed it ("A" is not a known self pipe), rule 4 missed it (no marker event
// anywhere near). 96% of the number this product is sold on was a fixture.
//
// Rule 5 does not ask the run what it was; it reads two things it cannot fake
// together. First, how long it took: a session repair calls an LLM proposer and
// then re-runs the project's suite. Measured on this ledger, the two real
// repairs (expressjs/express, 91 test files hash-locked) took a median of
// 44,253 ms from REPAIR_START to REPAIR_OK; the 50 fixture repairs took a median
// of 286 ms, max 483. Two orders of magnitude apart with nothing in between,
// because 286 ms does not contain a model call, it contains a stub.
// kRbStubProposerMs sits at 2,000 — four times the slowest fixture, twenty times
// under the fastest real repair.
//
// Second, whether the gate was ever in that tree's path at all. Time alone was
// the first shape of this rule and it was too wide, which route_test.sh says out
// loud: every fixture in this repo drives an instant proposer, so a pure speed
// test convicts them all and the honest fix would have been to make eight test
// harnesses sleep. Speed says a model did not answer. `gated` says nobody was
// being supervised. A repo where rabadon gated an action is a repo rabadon was
// working in, whatever its proposer cost; a tree where it gated nothing and a
// repair still closed in 286 ms was staged. Pipe "A" is both. express is neither
// (44 s), and every suite fixture here gates actions on its own pipe, so the
// conjunction leaves them alone. Both halves have to hold.
#ifndef RABADON_DRILL_H
#define RABADON_DRILL_H

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

// rule 4's radius: a drill's own follow-up events land within two minutes of
// the marker that named it.
static const double kRbDrillWindowMs = 120000.0;

// rule 5's floor: below this, REPAIR_START -> REPAIR_OK did not contain a model
// call. See the header comment for the two populations this sits between.
static const double kRbStubProposerMs = 2000.0;

// rule 1 — the emit tag. Read off the raw line rather than a parsed tree so
// both callers can apply it identically (stats parses JSON, export does not).
// Truthy means: true, a non-zero number, or a non-empty string. A nested
// occurrence inside a JSON string body is escaped (\"drill\") and the emitter's
// tag never is, so a backslash before the key rules the match out.
static bool rb_drill_tag(const std::string& line) {
  size_t from = 0;
  while (true) {
    size_t k = line.find("\"drill\"", from);
    if (k == std::string::npos) return false;
    from = k + 7;
    if (k > 0 && line[k - 1] == '\\') continue;
    size_t p = from;
    while (p < line.size() && (line[p] == ' ' || line[p] == '\t')) p++;
    if (p >= line.size() || line[p] != ':') continue;
    p++;
    while (p < line.size() && (line[p] == ' ' || line[p] == '\t')) p++;
    if (p >= line.size()) continue;
    if (line.compare(p, 4, "true") == 0) return true;
    if (line[p] == '"') { if (p + 1 < line.size() && line[p + 1] != '"') return true; continue; }
    if (line[p] == '-' || (line[p] >= '0' && line[p] <= '9')) {
      if (strtod(line.c_str() + p, nullptr) != 0) return true;
    }
  }
}

// rule 2 — /(fleet|doctor|drill)-\d/ over the raw line. drill- is in the marker
// set so `rabadon drill` sessions are excluded belt-and-suspenders (they are
// also emit-tagged by rule 1).
static bool rb_drill_marker(const std::string& line) {
  static const char* words[3] = {"fleet-", "doctor-", "drill-"};
  for (const char* w : words) {
    size_t wl = strlen(w), from = 0, k;
    while ((k = line.find(w, from)) != std::string::npos) {
      if (k + wl < line.size() && line[k + wl] >= '0' && line[k + wl] <= '9') return true;
      from = k + 1;
    }
  }
  return false;
}

// rule 3 — rabadon's own pipes. The latency benchmark alone fires thousands of
// synthetic denies; shipped as spans they read as production catches.
static bool rb_self_pipe(const std::string& p) {
  static const char* names[4] = {"vibecoded-demo", "do-test", "llm-repair-live", "bus-test"};
  for (const char* n : names) {
    size_t nl = strlen(n);
    if (p.size() == nl && p.compare(0, nl, n) == 0) return true;
    if (p.size() > nl && p.compare(0, nl, n) == 0 && p[nl] == ':') return true;
  }
  if (p.rfind("rabadon-bench", 0) == 0) return true;
  return p.rfind("tmp.", 0) == 0;
}

// rule 5's two facts, read off the raw line so all three callers apply them
// identically (stats parses JSON, export and trace do not). `"ev":"NAME"` is
// written by the emitter and never appears escaped inside a string body, so a
// backslash before the key rules the match out, exactly as rule 1 does.
inline bool rb_ev_is(const std::string& line, const char* name) {
  const std::string needle = std::string("\"ev\":\"") + name + "\"";
  size_t k = line.find(needle);
  if (k == std::string::npos) return false;
  return k == 0 || line[k - 1] != '\\';
}

// the repair loop opened on this line.
inline bool rb_repair_start(const std::string& line) { return rb_ev_is(line, "REPAIR_START"); }

// an action reached the gate — the evidence that this pipe was being supervised.
inline bool rb_gated_action(const std::string& line) { return rb_ev_is(line, "STEP_START"); }

// the repair loop closed on this line, in any of the three ways it can end. A
// stub that fails or flakes is as much a fixture as one that succeeds.
inline bool rb_repair_end(const std::string& line) {
  return rb_ev_is(line, "REPAIR_OK") || rb_ev_is(line, "REPAIR_FAIL") ||
         rb_ev_is(line, "REPAIR_FLAKY");
}

// The per-event facts rules 1-5 need. Callers fill this from their own parse.
struct RbDrillEv {
  bool has_pipe = false;
  std::string pipe;
  double ts = 0;
  bool tag = false;           // rule 1, rb_drill_tag(line)
  bool marker = false;        // rule 2, rb_drill_marker(line)
  std::string run;            // rule 5, the "run" field — pairs start with end
  bool repair_start = false;  // rule 5, rb_repair_start(line)
  bool repair_end = false;    // rule 5, rb_repair_end(line)
  bool gated = false;         // rule 5, rb_gated_action(line)
};

// Applies all four rules and returns one flag per event. Feed it EVERY line in
// the window, not only the lines the caller intends to keep: rule 4 needs the
// marker events to be present even when the caller would not have exported
// them, or a drill's fallout looks like ordinary traffic.
static std::vector<char> rb_mark_drills(const std::vector<RbDrillEv>& evs) {
  std::vector<char> drill(evs.size(), 0);
  struct Marker { bool has_pipe; const std::string* pipe; double ts; };
  std::vector<Marker> markers;
  for (size_t i = 0; i < evs.size(); i++) {
    if (evs[i].tag) { drill[i] = 1; continue; }
    if (evs[i].marker) { drill[i] = 1; markers.push_back({evs[i].has_pipe, &evs[i].pipe, evs[i].ts}); }
  }
  for (size_t i = 0; i < evs.size(); i++) {
    if (drill[i]) continue;
    const std::string p = evs[i].has_pipe ? evs[i].pipe : std::string();
    if (rb_self_pipe(p)) { drill[i] = 1; continue; }
    for (const Marker& m : markers) {
      bool same = (m.has_pipe == evs[i].has_pipe) && (!m.has_pipe || *m.pipe == evs[i].pipe);
      if (same && std::fabs(evs[i].ts - m.ts) < kRbDrillWindowMs) { drill[i] = 1; break; }
    }
  }

  // rule 5 — the stub proposer. Pair each run's REPAIR_START with its close and
  // measure the gap. Scan drills included: a fixture that half-tagged itself
  // must not buy credibility for the half it left bare.
  //
  // Only the REPAIR_* events of that run are marked, not the whole run. Marking
  // the run was the first shape of this and it was too wide: `rabadon loop`
  // emits its priced attempts under the SAME run id as the repair it wrapped, so
  // one stubbed proposal deleted the run's cost and token spans from the export
  // as well — a drill rule that eats accounting is not a drill rule. The claim
  // rule 5 is entitled to make is narrow and it makes exactly that one: this
  // repair had no model in it.
  struct Span { std::string run; double start; double end; bool has_start; bool has_end; };
  std::vector<Span> spans;
  auto span_for = [&spans](const std::string& r) -> Span& {
    for (size_t j = 0; j < spans.size(); j++) if (spans[j].run == r) return spans[j];
    Span s; s.run = r; s.start = 0; s.end = 0; s.has_start = false; s.has_end = false;
    spans.push_back(s);
    return spans.back();
  };
  for (size_t i = 0; i < evs.size(); i++) {
    if (evs[i].run.empty()) continue;
    if (!evs[i].repair_start && !evs[i].repair_end) continue;
    Span& s = span_for(evs[i].run);
    if (evs[i].repair_start && (!s.has_start || evs[i].ts < s.start)) { s.start = evs[i].ts; s.has_start = true; }
    if (evs[i].repair_end && (!s.has_end || evs[i].ts > s.end)) { s.end = evs[i].ts; s.has_end = true; }
  }
  // the other half: which pipes ever had an action gated. Tally over EVERY
  // event, drills included — a fixture that half-tagged itself must not buy
  // supervision for the half it left bare.
  std::vector<std::string> watched;
  for (size_t i = 0; i < evs.size(); i++) {
    if (!evs[i].gated || !evs[i].has_pipe) continue;
    bool seen = false;
    for (size_t j = 0; j < watched.size(); j++) if (watched[j] == evs[i].pipe) { seen = true; break; }
    if (!seen) watched.push_back(evs[i].pipe);
  }
  for (size_t i = 0; i < evs.size(); i++) {
    if (drill[i] || evs[i].run.empty()) continue;
    if (!evs[i].repair_start && !evs[i].repair_end) continue;
    bool supervised = false;
    if (evs[i].has_pipe)
      for (size_t j = 0; j < watched.size(); j++) if (watched[j] == evs[i].pipe) { supervised = true; break; }
    if (supervised) continue;
    const Span& s = span_for(evs[i].run);
    if (s.has_start && s.has_end && (s.end - s.start) < kRbStubProposerMs) drill[i] = 1;
  }
  return drill;
}

#endif
