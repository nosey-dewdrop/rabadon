// drill.h — ONE definition of "this spool line is rabadon's own noise".
//
// rabadon's brand claim is that it never counts its own self-tests as catches.
// That claim is only worth the surface with the loosest reading of it, so the
// four rules live here once and both readers of the spool call the same code:
//
//   rabadon-stats   the local number, read by the operator who knows what a
//                   drill is;
//   rabadon-export  OTLP spans pushed OFF the machine into a shared Jaeger /
//                   Grafana / Langfuse, where a refusal renders red and nobody
//                   can tell a bench run from a production catch.
//
// export used to apply rule 1 alone, as a raw substring match, and shipped the
// other three shapes as ERROR spans — on this machine, 7 events dropped out of
// 3,495 the local number excluded. A second copy of a predicate is a copy that
// drifts; the honest surface has to be the one that leaves the house.
//
// The four rules (all of them exclude; none of them is sufficient alone):
//   1. the emit tag        "drill":true written by the emitter itself;
//   2. session-id markers  fleet-N / doctor-N / drill-N anywhere on the line;
//   3. the self pipe       rabadon's own bench/demo/test pipes;
//   4. window association  an untagged event inside the same pipe within
//                          kRbDrillWindowMs of a marker event is drill fallout.
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

// The per-event facts rules 1-4 need. Callers fill this from their own parse.
struct RbDrillEv {
  bool has_pipe = false;
  std::string pipe;
  double ts = 0;
  bool tag = false;     // rule 1, rb_drill_tag(line)
  bool marker = false;  // rule 2, rb_drill_marker(line)
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
  return drill;
}

#endif
