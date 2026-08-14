// rabadon-export — the ledger as OpenTelemetry, so any backend can render it
// (C++17, zero deps).
//
// rabadon's spool is honest but private. This binary speaks the standard:
// OTLP/JSON traces following the OpenTelemetry GenAI semantic conventions, so
// a rabadon session drops straight into Jaeger, Grafana Tempo, Honeycomb, or
// Langfuse's OTLP endpoint — no rabadon-specific viewer required. Observation
// is a solved, standardized problem; rabadon's edge is enforcement, so here it
// EXPORTS instead of reinventing a dashboard.
//
// Mapping:
//   - one TRACE per SESSION (traceId = 128-bit hash of the session id the hook
//     was handed). This used to key off `pipe`, which is spelled
//     "<project>:session" and is NOT one — it is the directory. 227 pipes cover
//     nine days of this machine and stitchu:session alone spans 214.1 hours:
//     every session and every subagent that has ever run in that folder wrote
//     into one trace, 24,056 spans deep. No viewer renders that as anything.
//     A line with no session id still falls back to its pipe and a line with
//     neither to the file it was read from, and the span says which of the
//     three it got (rabadon.export.trace_basis) — a trace that is a folder's
//     whole history must not pass for a session;
//   - one SPAN per event — EVERY event, spanId = 64-bit hash of run+seq+ts;
//   - one tool call is ONE row. STEP_START and STEP_OK are the two ends of a
//     single Claude Code tool call and both carry its tool_use_id as `call`, so
//     the OK becomes the interval [START.ts, OK.ts] and the START becomes its
//     CHILD (parentSpanId) instead of a second top-level row. Neither is
//     dropped: nothing in SPEC §2 lets this reader delete an event, and the
//     nesting is what a viewer needs to draw one row per call anyway;
//     SPEC §2's ten `ev` values keep their shaping; anything else (a verb a
//     stranger's agent invented, or a line with no `ev`) renders generically
//     with its own fields carried as rabadon.<key> attributes, because §2 says
//     unknown `ev` values are rendered generically and never dropped. The only
//     event that stays home is a drill;
//   - a catch/refusal sets span status = ERROR with the rule as the message —
//     so a refused action is red in any trace viewer, which is exactly why the
//     drill rules here (drill.h, shared with rabadon-stats) have to be the same
//     four the local number uses: this is the surface strangers read. The rule
//     is read from BOTH shapes the ledger actually has: the top-level "rule"
//     key, which only STOP and WOULD_BLOCK carry (gate.cpp:1842, :1862), and
//     fails[].check, which is where every CHECK_FAIL puts it (gate.cpp:1837,
//     and the net/scope/goal/tests/budget checks at :1375 :1457 :1478 :1581
//     :1896). This reader knew the STOP shape only, so a refusal went out red
//     with the literal word CHECK_FAIL as its message and no rule anywhere on
//     the span — the one thing a stranger's collector is looking at. rabadon
//     -stats has read fails[0].check as "the rule that fired" the whole time
//     (stats.cpp:574), so the two readers described the same refusal
//     differently;
//   - attributes: rabadon.ev, rabadon.rule, rabadon.detail, and the GenAI
//     conventions gen_ai.system / gen_ai.request.model / gen_ai.usage.* where
//     token counts exist. Those counts are read under THE KEYS THE SHIPPED
//     BINARIES WRITE — see the token block below; this reader used to name
//     keys nothing in the repo emits, and shipped 0 gen_ai attributes over a
//     ledger of 1366 token-bearing events. Every field the exporter does NOT
//     map rides along as rabadon.<key>, on EVERY event — this used to happen
//     only for unrecognised verbs, and `step`, the field that says what the
//     agent actually ran, is written on all ten of SPEC §2's verbs and was
//     exported for none of them: a STEP_START/STEP_OK pair left the machine
//     carrying its own name and nothing about the command;
//   - the accounting. Every other reader of the spool answers to a count; this
//     one never did. Measured 3 August 2026: 80,690 lines in, 77,084 spans
//     out, exit 0, empty stderr — the gap is drills, which is correct, and no
//     number in the program could have said so. The books are now closed on
//     stderr (stdout stays the document): lines read, spans out, every discard
//     classified. Two different facts used to share one bare `continue`,
//     because rbjson::get_num returns 0 for absent, mistyped AND unparseable
//     and 0 is never >= a cutoff in 2026:
//       * ts older than the window -> held back, counted, named;
//       * no readable ts           -> SHIPPED, rabadon.export.dated="no",
//                                     placed at the day its file is named for.
//                                     A line the reader cannot date is not a
//                                     line from last year;
//       * unparseable JSON         -> SHIPPED as an UNREADABLE span, red, with
//                                     the byte offset the walk stopped at, the
//                                     fields that were readable before it, and
//                                     the head of the raw line. Where the
//                                     damage sat used to decide the outcome:
//                                     before `ts` the line vanished, after it
//                                     the line shipped nameless with an empty
//                                     pipe into the trace id of the literal
//                                     string "?";
//   - one document, one encoding. jesc() passed every byte >= 0x80 through
//     untouched, so ONE invalid UTF-8 byte in ONE field made the entire
//     payload invalid JSON (RFC 8259 §8.1) and a collector rejects all 77,084
//     spans, not the one line. 65 lines of the live spool carry invalid UTF-8
//     today, 59 of them in `step` — harmless only for as long as `step` was
//     never exported, which stopped being true two bullets ago. Bytes that are
//     not UTF-8 leave as U+FFFD, and the lines that carried them are counted
//     and reported.
//
//   rabadon export --otlp [--days N]   -> OTLP/JSON on stdout
//   POST it:  rabadon export --otlp | curl -s localhost:4318/v1/traces \
//               -H 'content-type: application/json' --data-binary @-

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>
#include <dirent.h>
#include <pwd.h>
#include <sys/stat.h>
#include <unistd.h>
#include "cli_help.h"
#include "drill.h"
#include "jsonl.h"

using std::string;
using std::vector;

static double now_ms() {
  const char* t = getenv("RABADON_NOW");
  if (t && t[0]) { double v = strtod(t, nullptr); if (v > 0) return v; }
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  long long ms = (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
  return (double)ms;
}

static string read_file(const string& p) {
  struct stat st;
  if (stat(p.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return string();
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

// Read the line AS JSON (jsonl.h), not as the bytes rabadon's own printf emits.
// The old readers matched the literal `"key":"`, so a spool written by a stock
// serializer (`"ev": "STOP"`) yielded an empty `ev` for every line, no line
// matched the exportable set, and the exporter shipped ZERO spans while
// claiming the standard. rabadon's own G3 evidence ledger,
// reports/2026-08-01-g3-first-held-repair/04-ledger-events.jsonl, is in that
// format: 10 real events, 0 spans. An exporter that only speaks its own
// emitter's whitespace is not the agent-agnostic surface SPEC Part II promises.
//
// One walk per line, not one per field. rbjson::find_field restarts at byte 0
// for every key and answers only "here is the value, or nothing" — it cannot
// say WHY there was nothing, and "absent", "mistyped" and "the line is torn in
// half" are three different facts that a reader owes an operator separately.
// So: walk the object once, keep the depth-1 fields in document order, and
// record where the walk stopped when it could not finish. Fields read before
// the damage are kept — a truncated line still knows its own `run`.
//
// Depth-1 strictness only: rbjson::skip_value matches braces and skips string
// literals, so damage INSIDE a nested value is not detected here. That is the
// same boundary jsonl.h draws and it is the boundary that matters for this
// reader, whose answers all live at depth 1.
struct RbField { string key, val; bool is_string = false; };
struct RbLine {
  bool is_object = false;   // starts with '{'
  bool complete = false;    // ...and the walk reached its closing '}'
  size_t stop = 0;          // byte offset the walk gave up at
  const char* why = "";     // in words, for the span that carries the damage
  vector<RbField> f;
};

static RbLine parse_line(const string& s) {
  RbLine r;
  size_t i = rbjson::skip_ws(s, 0);
  if (i >= s.size() || s[i] != '{') { r.stop = i; r.why = "not a JSON object"; return r; }
  r.is_object = true;
  i = rbjson::skip_ws(s, i + 1);
  if (i < s.size() && s[i] == '}') { r.complete = true; r.stop = i + 1; }
  while (!r.complete && i < s.size()) {
    RbField fl;
    size_t n = rbjson::scan_string(s, i, &fl.key);
    if (n == string::npos) { r.stop = i; r.why = "key is not a closed string"; return r; }
    i = rbjson::skip_ws(s, n);
    if (i >= s.size() || s[i] != ':') { r.stop = i; r.why = "no ':' after key"; return r; }
    i = rbjson::skip_ws(s, i + 1);
    size_t vs = i;
    n = rbjson::skip_value(s, i);
    if (n == string::npos) { r.stop = i; r.why = "value is truncated or malformed"; return r; }
    fl.is_string = (vs < s.size() && s[vs] == '"');
    if (fl.is_string) rbjson::scan_string(s, vs, &fl.val);
    else fl.val = s.substr(vs, n - vs);
    r.f.push_back(std::move(fl));
    i = rbjson::skip_ws(s, n);
    if (i < s.size() && s[i] == '}') { r.complete = true; r.stop = i + 1; break; }
    if (i >= s.size()) { r.stop = i; r.why = "the object never closes"; return r; }
    if (s[i] != ',') { r.stop = i; r.why = "no ',' between fields"; return r; }
    i = rbjson::skip_ws(s, i + 1);
  }
  if (!r.complete) { r.stop = i; r.why = "the object never closes"; return r; }
  size_t t = rbjson::skip_ws(s, r.stop);
  if (t != s.size()) { r.complete = false; r.stop = t; r.why = "trailing bytes after the closing brace"; }
  return r;
}

// jsonl.h's rule, kept byte for byte: the first occurrence of a key at depth 1
// is the answer, and a value of the wrong type reads as absent.
static bool is_jnum(const string& v) {
  if (v.empty()) return false;
  char c = v[0];
  return c == '-' || c == '+' || c == '.' || (c >= '0' && c <= '9');
}

// A non-string value rides along as its own JSON text, so two producers that
// mean the same thing have to export the same bytes: string literals verbatim,
// insignificant whitespace dropped. Without this a stock serializer's
// `"fails": [{"check": "x"}]` and rabadon's own `"fails":[{"check":"x"}]`
// become two different attribute values for one identical fact — the same
// emitter-fingerprinting jsonl.h exists to end, one level down.
static string jmin(const string& v) {
  string o;
  o.reserve(v.size());
  for (size_t i = 0; i < v.size();) {
    char c = v[i];
    if (c == '"') {
      size_t n = rbjson::scan_string(v, i, nullptr);
      if (n == string::npos) { o.append(v, i, v.size() - i); break; }
      o.append(v, i, n - i); i = n; continue;
    }
    if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { i++; continue; }
    o += c; i++;
  }
  return o;
}

// The refusal ledger's OTHER shape. `rule` at the top level exists on STOP and
// WOULD_BLOCK; a CHECK_FAIL puts the rule that fired in fails[].check with the
// evidence in fails[].why, which is what rabadon-stats reads (stats.cpp:574).
// Every check is named, not just the first — a line that failed three rules
// says three rules, and stats' "first one wins" is a display choice, not the
// record.
static void rule_from_fails(const string& arr, string& rule, string& why) {
  size_t i = rbjson::skip_ws(arr, 0);
  if (i >= arr.size() || arr[i] != '[') return;
  i = rbjson::skip_ws(arr, i + 1);
  while (i < arr.size() && arr[i] != ']') {
    size_t n = rbjson::skip_value(arr, i);
    if (n == string::npos) return;
    if (arr[i] == '{') {
      string obj = arr.substr(i, n - i);
      string c = rbjson::get_str(obj, "check");
      if (!c.empty()) {
        if (!rule.empty()) rule += ",";
        rule += c;
        if (why.empty()) why = rbjson::get_str(obj, "why");
      }
    }
    i = rbjson::skip_ws(arr, n);
    if (i < arr.size() && arr[i] == ',') { i = rbjson::skip_ws(arr, i + 1); continue; }
    break;
  }
}

// Midnight UTC of the day a spool file is named for, in ms. The spool is one
// file per day (YYYY-MM-DD.jsonl), so the file name is real evidence about
// when a line inside it happened — the only evidence left when the line's own
// `ts` cannot be read. days_from_civil rather than timegm/mktime: the answer
// must not move with the operator's TZ.
static bool file_day_ms(const string& fn, double& out) {
  if (fn.size() < 10) return false;
  for (int i = 0; i < 10; i++) {
    char c = fn[i];
    bool digit = c >= '0' && c <= '9';
    if ((i == 4 || i == 7) ? c != '-' : !digit) return false;
  }
  int y = atoi(fn.substr(0, 4).c_str()), m = atoi(fn.substr(5, 2).c_str()), d = atoi(fn.substr(8, 2).c_str());
  if (m < 1 || m > 12 || d < 1 || d > 31) return false;
  y -= m <= 2;
  int era = (y >= 0 ? y : y - 399) / 400;
  unsigned yoe = (unsigned)(y - era * 400);
  unsigned doy = (unsigned)((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1);
  unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  long long days = (long long)era * 146097 + (long long)doe - 719468;
  out = (double)days * 86400000.0;
  return true;
}

// FNV-1a 64-bit; two of them (salted) make a stable 128-bit trace id
static uint64_t fnv(const string& s, uint64_t seed) {
  uint64_t h = seed;
  for (unsigned char c : s) { h ^= c; h *= 1099511628211ULL; }
  return h;
}
static string hex64(uint64_t v) { char b[17]; snprintf(b, sizeof b, "%016llx", (unsigned long long)v); return b; }
static string trace_id(const string& seed) { return hex64(fnv(seed, 1469598103934665603ULL)) + hex64(fnv(seed, 1099511628211ULL)); }
static string span_id(const string& s) { return hex64(fnv(s, 0xcbf29ce484222325ULL)); }

// Length of the well-formed UTF-8 sequence starting at i, or 0 when the bytes
// there are not one. RFC 3629: no overlongs (C0/C1, E0 80, F0 80), no
// surrogates (ED A0..BF), nothing above U+10FFFF (F5..FF).
static size_t utf8_seq(const string& s, size_t i) {
  unsigned char c = (unsigned char)s[i];
  if (c < 0x80) return 1;
  size_t n; unsigned lo = 0x80, hi = 0xBF;
  if (c >= 0xC2 && c <= 0xDF) n = 1;
  else if (c == 0xE0) { n = 2; lo = 0xA0; }
  else if (c >= 0xE1 && c <= 0xEC) n = 2;
  else if (c == 0xED) { n = 2; hi = 0x9F; }
  else if (c >= 0xEE && c <= 0xEF) n = 2;
  else if (c == 0xF0) { n = 3; lo = 0x90; }
  else if (c >= 0xF1 && c <= 0xF3) n = 3;
  else if (c == 0xF4) { n = 3; hi = 0x8F; }
  else return 0;
  if (i + n >= s.size()) return 0;   // the sequence runs off the end of the string
  for (size_t k = 1; k <= n; k++) {
    unsigned char d = (unsigned char)s[i + k];
    unsigned a = (k == 1) ? lo : 0x80, b = (k == 1) ? hi : 0xBF;
    if (d < a || d > b) return 0;
  }
  return n + 1;
}

static bool has_bad_utf8(const string& s) {
  for (size_t i = 0; i < s.size();) {
    size_t n = utf8_seq(s, i);
    if (n == 0) return true;
    i += n;
  }
  return false;
}

// The export is ONE JSON document, so ONE byte decides whether ANY of it can be
// read. This escaped control characters and passed every byte >= 0x80 through
// untouched — correct only while every producer's bytes happen to be UTF-8.
// RFC 8259 §8.1 requires the text to be Unicode; a lone 0xC3 from a truncated
// write, a latin-1 filename, or a binary blob in a `step` string makes the
// whole payload undecodable and a collector drops every span in it. So the
// escaper is now the encoding boundary: valid sequences pass through as they
// are, anything that is not UTF-8 leaves as U+FFFD (escaped, so the output is
// pure ASCII either way). One damaged field costs its own bytes and nothing
// else's. The lines this happens to are counted and reported on stderr — a
// substitution nobody is told about is the same silence as a dropped line.
static string jesc(const string& s) {
  string o;
  o.reserve(s.size());
  for (size_t i = 0; i < s.size();) {
    unsigned char c = (unsigned char)s[i];
    if (c >= 0x80) {
      size_t n = utf8_seq(s, i);
      if (n == 0) { o += "\\ufffd"; i++; }
      else { o.append(s, i, n); i += n; }
      continue;
    }
    switch (c) {
      case '"': o += "\\\""; break;
      case '\\': o += "\\\\"; break;
      case '\n': o += "\\n"; break;
      case '\r': o += "\\r"; break;
      case '\t': o += "\\t"; break;
      default: if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); o += b; } else o += (char)c;
    }
    i++;
  }
  return o;
}
// Milliseconds to nanoseconds, in integers, because this multiplication does
// not fit in the type it used to be done in. A millisecond epoch is ~1.79e12;
// times 1e6 that is ~1.79e18, and a double holds consecutive integers only up
// to 2^53 (~9.0e15). Past there the product is rounded to the nearest
// REPRESENTABLE double, so `"%.0f"` printed a number the ledger never said:
// measured on a real spool line, ts 1785841746341 left as ...340999936, 64ns
// short. Every timestamp this exporter ever shipped was wrong by up to ~128ns.
// Nothing downstream noticed because span ordering survives it — the gap is a
// millionth of the millisecond that separates two events — but the document
// claims to be the ledger, and a document that quietly rewrites the last nine
// digits of every timestamp is not the ledger.
//
// The whole millisecond goes through as an integer; a sub-millisecond fraction
// (which no rabadon producer writes, but a stranger's serializer may) is
// carried separately, where it is small enough for a double to be exact.
static string nanos(double ms) {
  if (!(ms > 0)) return "0";
  long long whole = (long long)ms;
  double frac = ms - (double)whole;
  long long n = whole * 1000000LL + (long long)(frac * 1e6 + 0.5);
  return std::to_string(n);
}
static string attr_str(const string& k, const string& v) { return "{\"key\":\"" + jesc(k) + "\",\"value\":{\"stringValue\":\"" + jesc(v) + "\"}}"; }
static string attr_int(const string& k, long long v) { return "{\"key\":\"" + k + "\",\"value\":{\"intValue\":\"" + std::to_string(v) + "\"}}"; }
// Money is booked in micro-dollars (integer, exact). It leaves as both: the
// integer, and a USD double for a viewer that wants to sum it. %.6f is lossless
// for a micro-dollar count — the double is a rendering, never the record.
static string attr_dbl(const string& k, double v) { char b[40]; snprintf(b, sizeof b, "%.6f", v); return "{\"key\":\"" + k + "\",\"value\":{\"doubleValue\":" + b + "}}"; }

struct Ev {
  double ts = 0, seq = 0;
  string pipe, run, ev, rule, detail, model;
  // Who this line belongs to, both answers written by gate.cpp's Emitter.
  //   `sess` is the session id -> the TRACE this line joins.
  //   `call` is Claude Code's tool_use_id, the same value on the PreToolUse and
  //          the PostToolUse hook of one tool call -> the two ends of one span.
  // `run` cannot do either job: every hook invocation is its own process, and
  // 75,126 live events carried 75,126 distinct run ids with zero reuse.
  // Neither field is listed in is_mapped_field, deliberately — this reader
  // CONSUMES them (into a trace id and an interval) but does not own them, and
  // a join a stranger cannot re-derive from the same document is a claim. They
  // ride along as rabadon.call / rabadon.sess like any other unmapped key, so
  // the pairing this file does can be checked by hand against the ledger.
  string call, sess;
  long long tin = 0, tout = 0, usd_e6 = 0;
  // How long the thing this line reports actually took. The ledger writes its
  // `ts` when the event is APPENDED, which for every producer of dur_ms is
  // after the work returned — loop.cpp calls attempt_metrics() on the proposer
  // that just finished, net.cpp's finish() stamps now_ms() with the elapsed
  // time beside it. So the line describes the interval [ts - dur_ms, ts], and
  // the span it becomes is that interval rather than its final instant.
  long long dur_ms = 0;
  string extra;
  // what the READER knows about the line, as opposed to what the line says
  string src;              // "<file>:<lineno>", so a damaged line can be found
  string file;             // the trace a pipeless line falls back to
  bool dated = true;       // the line carried a readable ts of its own
  bool readable = true;    // the walk reached the closing brace
  string why, raw;         // when it did not: where it stopped, and the bytes
};

// SPEC §2 fixes ten `ev` values and adds the MUST that unknown ones render
// generically and are never dropped. There used to be a predicate here that
// told the two apart, because an unrecognised verb was the ONLY event whose
// own fields were carried along. That was the bug in section 4 of
// export_drop_test: `step` — the field that says what the agent ran — is
// written by all ten of the known verbs, and being known is exactly what made
// it invisible. Every event now carries every field this exporter does not map,
// so there is no shaping difference left for a predicate to decide, and a
// predicate with no consumer is the drift drill.h warns about.

// Everything this exporter already maps to a span field or a named attribute.
// The rest of the line is what "unknown fields MUST be preserved" is about.
static bool is_mapped_field(const string& k) {
  static const char* v[] = {"v", "ts", "seq", "run", "pipe", "ev", "rule", "detail", "tokensIn", "tokensOut"};
  for (const char* w : v) if (k == w) return true;
  return false;
}

// A mapped key whose value is the WRONG TYPE reads as absent — jsonl.h's rule,
// and the right one — but it was then dropped from the export as well, on the
// grounds that it was "mapped". `"ts":"1785599999000"` is precisely the line
// that leaves undated, and the one thing its span could not say was why. So a
// mapped key rides along as rabadon.<key> whenever the mapper did not take it.
static bool mapper_took(const string& k, bool is_string, const string& val) {
  bool num = !is_string && is_jnum(val);
  if (k == "ts" || k == "seq" || k == "tokensIn" || k == "tokensOut") return num;
  if (k == "run" || k == "pipe" || k == "ev" || k == "rule" || k == "detail") return is_string;
  return true;   // "v" is the ledger's schema version and is exported by nobody
}

static const char* kHelp =
  "rabadon-export — the ledger in OTLP/JSON on stdout, GenAI semantic conventions.\n"
  "Reads the local spool and emits spans any OpenTelemetry collector accepts, so\n"
  "rabadon runs land next to the rest of your traces. A priced event carries\n"
  "gen_ai.system, gen_ai.request.model, gen_ai.usage.input_tokens and\n"
  "gen_ai.usage.output_tokens, plus the cost as rabadon.usd_e6 (exact\n"
  "micro-dollars) and rabadon.cost_usd — OTel's GenAI conventions derive money\n"
  "from token counts and define no cost attribute, so rabadon names its own.\n"
  "Those keys are read off what the shipped binaries write, not off names only\n"
  "the reader knew.\n"
  "\n"
  "One trace per SESSION, and one row per TOOL CALL: a STEP_START and the\n"
  "STEP_OK that closes it carry the same tool_use_id, so the OK spans the\n"
  "interval between them and the START hangs under it. Neither is dropped.\n"
  "A line written before the gate recorded those ids keys its trace off the\n"
  "pipe instead — which is a DIRECTORY, not a session — and every span says\n"
  "which it got in rabadon.export.trace_basis.\n"
  "\n"
  "Drills never leave the\n"
  "machine, by the same four rules `rabadon usage` excludes them with: the emit\n"
  "tag, a fleet/doctor/drill session id, rabadon's own bench and demo pipes, and\n"
  "events inside a drill's 2-minute window. The count you read here and the count\n"
  "you read locally are the same count.\n"
  "\n"
  "usage: rabadon-export --otlp [--days N]\n"
  "\n"
  "  --otlp      emit OTLP/JSON. required — it is the only format today.\n"
  "  --days N    how far back to read (default 7).\n"
  "  -h, --help  this screen.\n"
  "\n"
  "environment:\n"
  "  RABADON_DIR   where the spool lives (default ~/.rabadon).\n"
  "\n"
  "example:\n"
  "  rabadon-export --otlp --days 1 | curl -s -X POST -H 'content-type: application/json' \\\n"
  "      --data-binary @- http://localhost:4318/v1/traces\n";

int main(int argc, char** argv) {
  rb_help(argc, argv, kHelp);

  double days = 7;
  bool otlp = false;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--days") == 0 && i + 1 < argc) { double v = strtod(argv[++i], nullptr); if (v > 0) days = v; }
    else if (strcmp(argv[i], "--otlp") == 0) otlp = true;
    // an unrecognised word used to be ignored, so `-h` fell through to the
    // format check and came back "pass --otlp" with exit 2.
    else rb_unknown_flag("rabadon-export", argv[i]);
  }
  if (!otlp) { fprintf(stderr, "rabadon export: pass --otlp (the only format today)\n  run `rabadon-export --help`\n"); return 2; }

  string rdir;
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) rdir = rd;
  else { const char* h = getenv("HOME"); string home = (h && h[0]) ? h : "."; rdir = home + "/.rabadon"; }
  string spool = rdir + "/spool";
  const double cutoff = now_ms() - days * 86400000.0;

  vector<string> files;
  if (DIR* d = opendir(spool.c_str())) {
    while (struct dirent* ent = readdir(d)) { string n = ent->d_name; if (n.size() >= 6 && n.compare(n.size() - 6, 6, ".jsonl") == 0) files.push_back(n); }
    closedir(d);
  }
  std::sort(files.begin(), files.end());

  // Two passes over the same window. The first classifies EVERY in-window line
  // with the shared drill rules (drill.h) — every line, because rule 4 reads a
  // marker off events this exporter would never have shipped, and a drill's
  // fallout must not look like ordinary traffic just because the marker was a
  // heartbeat. The second keeps the non-drill ones — ALL of them.
  //
  // There used to be a third filter here: a hardcoded eight-name allow-list
  // (`kept[]`) that silently discarded anything else. It cost two of SPEC §2's
  // OWN ten values — STEP_OK and REPAIR_START, both emitted by rabadon's own
  // gate.cpp / repair.cpp / loop.cpp — so the G3 proof ledger
  // (reports/2026-08-01-g3-first-held-repair/04-ledger-events.jsonl: 5
  // REPAIR_START, 2 REPAIR_OK, 3 REPAIR_FAIL) exported as 5 spans: repairs
  // that finish without ever starting, and every successful step invisible.
  // Spans here are point-in-time (start == end), so a START is not folded into
  // its OK; it was simply gone. And it broke the §2 MUST outright — "unknown
  // `ev` values MUST be rendered generically, never dropped" — which is what
  // makes Part II's agent-agnostic promise false for any producer that adds a
  // verb. The only thing that may keep an event home is a drill.
  //
  // The window filter was two lines and both discards were the same bare
  // `continue`:
  //
  //     double ts = get_num(line, "ts");
  //     if (!(ts >= cutoff)) continue;
  //
  // rbjson::get_num answers 0 for absent, mistyped AND unparseable, and 0 is
  // never >= a cutoff in 2026 — so "this line is older than the window" and "I
  // could not read this line" left by the same silent door. Worse, WHERE the
  // damage sat decided which way it went wrong: find_field walks keys left to
  // right and stops at the first structural error, so damage before `ts` meant
  // the line vanished and damage after `ts` meant the line shipped with every
  // later field blank. The live spool never showed the first case only because
  // the shipped emitters happen to put `ts` third — a property of one
  // emitter's key order, and Part II exists so a stranger's serializer can
  // order keys however it likes.
  //
  // Now: read the line once, and let it fall into exactly one of three states.
  //   dated + in window   -> a span, as before;
  //   dated + out         -> held back, counted as out-of-window;
  //   undated             -> a span, marked, placed at the day its file names,
  //                          and held back only if that whole day is older
  //                          than the window (the file name is the only
  //                          evidence about a line that will not say when it
  //                          happened; guessing "now" would import an ancient
  //                          spool into today, guessing "1970" would drop it).
  // Unreadable is orthogonal: it says whether the line could be parsed, not
  // whether it belongs in the window, and a line can be both undated and
  // unreadable.
  vector<RbDrillEv> classify;   // one per line that will be considered
  vector<Ev> parsed;            // the payload, same indexing
  long long n_read = 0, n_files = 0, n_old_ts = 0, n_old_file = 0;
  long long n_undated = 0, n_unreadable = 0, n_badutf8 = 0;
  for (const string& f : files) {
    string body = read_file(spool + "/" + f);
    double dayMs = 0;
    bool haveDay = file_day_ms(f, dayMs);
    n_files++;
    size_t pos = 0;
    long long lineno = 0;
    while (pos < body.size()) {
      size_t nl = body.find('\n', pos);
      string line = body.substr(pos, (nl == string::npos ? body.size() : nl) - pos);
      pos = (nl == string::npos) ? body.size() : nl + 1;
      lineno++;
      if (line.empty()) continue;   // a blank line is not an event and never was
      n_read++;
      if (has_bad_utf8(line)) n_badutf8++;

      RbLine lp = parse_line(line);
      Ev e;
      e.file = f;
      e.src = f + ":" + std::to_string(lineno);
      e.readable = lp.is_object && lp.complete;
      if (!e.readable) {
        e.why = string(lp.why) + " at byte " + std::to_string((long long)lp.stop);
        e.raw = line.size() > 160 ? line.substr(0, 160) + "…" : line;
      }

      // one pass over the depth-1 fields: the mapped ones by name, everything
      // else carried along as rabadon.<key>. First occurrence wins and a value
      // of the wrong type reads as absent — jsonl.h's rule, kept identical, so
      // the two readers cannot disagree about what a line says.
      bool gTs = false, gSeq = false, gPipe = false, gRun = false, gEv = false, gRule = false;
      bool gDetail = false, gModel = false, gIn = false, gOut = false, gTin = false;
      bool gTout = false, gTok = false, gUsd = false, gDur = false, gCall = false, gSess = false;
      double ts = 0; bool tsOk = false;
      long long v_in = 0, v_out = 0, v_tin = 0, v_tout = 0, v_tok = 0;
      string failsRaw;
      auto num = [](const RbField& fl) { return strtod(fl.val.c_str(), nullptr); };
      for (const RbField& fl : lp.f) {
        const string& k = fl.key;
        if (k == "ts") { if (!gTs) { gTs = true; if (!fl.is_string && is_jnum(fl.val)) { ts = num(fl); tsOk = true; } } }
        else if (k == "seq") { if (!gSeq) { gSeq = true; if (!fl.is_string && is_jnum(fl.val)) e.seq = num(fl); } }
        else if (k == "pipe") { if (!gPipe) { gPipe = true; if (fl.is_string) e.pipe = fl.val; } }
        else if (k == "run") { if (!gRun) { gRun = true; if (fl.is_string) e.run = fl.val; } }
        else if (k == "ev") { if (!gEv) { gEv = true; if (fl.is_string) e.ev = fl.val; } }
        else if (k == "rule") { if (!gRule) { gRule = true; if (fl.is_string) e.rule = fl.val; } }
        else if (k == "detail") { if (!gDetail) { gDetail = true; if (fl.is_string) e.detail = fl.val; } }
        else if (k == "model") { if (!gModel) { gModel = true; if (fl.is_string) e.model = fl.val; } }
        else if (k == "in") { if (!gIn) { gIn = true; if (!fl.is_string && is_jnum(fl.val)) v_in = (long long)num(fl); } }
        else if (k == "out") { if (!gOut) { gOut = true; if (!fl.is_string && is_jnum(fl.val)) v_out = (long long)num(fl); } }
        else if (k == "tokensIn") { if (!gTin) { gTin = true; if (!fl.is_string && is_jnum(fl.val)) v_tin = (long long)num(fl); } }
        else if (k == "tokensOut") { if (!gTout) { gTout = true; if (!fl.is_string && is_jnum(fl.val)) v_tout = (long long)num(fl); } }
        else if (k == "tokens") { if (!gTok) { gTok = true; if (!fl.is_string && is_jnum(fl.val)) v_tok = (long long)num(fl); } }
        else if (k == "usd_e6") { if (!gUsd) { gUsd = true; if (!fl.is_string && is_jnum(fl.val)) e.usd_e6 = (long long)num(fl); } }
        else if (k == "dur_ms") { if (!gDur) { gDur = true; if (!fl.is_string && is_jnum(fl.val)) e.dur_ms = (long long)num(fl); } }
        else if (k == "call") { if (!gCall) { gCall = true; if (fl.is_string) e.call = fl.val; } }
        else if (k == "sess") { if (!gSess) { gSess = true; if (fl.is_string) e.sess = fl.val; } }
        if (k == "fails" && failsRaw.empty() && !fl.is_string) failsRaw = fl.val;
      }

      // the window, and the three states
      if (tsOk) {
        e.ts = ts; e.dated = true;
        if (!(ts >= cutoff)) { n_old_ts++; continue; }
      } else {
        e.dated = false;
        e.ts = haveDay ? dayMs : 0;
        // the whole day the file is named for is behind the window: the line
        // cannot be in it either, whatever its own ts would have said.
        if (haveDay && dayMs + 86400000.0 < cutoff) { n_old_file++; continue; }
        n_undated++;
      }
      if (!e.readable) n_unreadable++;

      // Token accounting, read under the keys PRODUCERS WRITE.
      //
      // This line used to read "tokensIn"/"tokensOut" and nothing else. Those
      // two names are real — but they live in .rabadon/state.json, the gate's
      // private session record, and no emitter has ever put them on a spool
      // line. What the shipped binaries write:
      //
      //   loop.cpp:217  "tokens":<in+out+cache>, "in":<n>, "out":<n>,
      //                 "usd_e6":<n>, "dur_ms":<n>, "model":"<id>"
      //   gate.cpp:1499 "tokens":<n> alone, on the Stop ledger STEP_OK, and
      //                 that value is the session's cumulative tokensOut
      //                 (the input count exists only inside the prose of the
      //                 same event's "step" string, so it cannot be exported).
      //
      // Measured on this machine before the fix: 1366 spool lines carry a
      // "tokens" key, 0 carry "tokensIn". Every span that left the machine had
      // exactly two attributes, rabadon.ev and rabadon.pipe, while README and
      // --help both advertised GenAI semconv token attributes. The suite was
      // green because export_test.sh hand-wrote its fixture in the READER's key
      // names — SPEC Part II §2's "a verifier whose true predicate is 'these
      // bytes came from me'", one layer up.
      //
      // Precedence: the explicit split wins; the state.json names are still
      // accepted for a third-party producer that mirrors them; the bare
      // "tokens" is taken as output ONLY when neither split is present, which
      // is exactly the gate's shape and exactly what its value means.
      e.tin = v_in; e.tout = v_out;
      if (e.tin <= 0) e.tin = v_tin;
      if (e.tout <= 0) e.tout = v_tout;
      if (e.tin <= 0 && e.tout <= 0) e.tout = v_tok;

      // The refusal's rule, from whichever shape the producer used. A
      // CHECK_FAIL has no top-level "rule" — it has fails[] — so this used to
      // leave the machine as a red span whose message was the word CHECK_FAIL
      // and whose rule attribute did not exist.
      if (e.rule.empty() && !failsRaw.empty()) {
        string why;
        rule_from_fails(failsRaw, e.rule, why);
        if (e.detail.empty()) e.detail = why;
      }

      // SPEC §2, the other MUST: unknown fields are preserved. A struct can
      // only carry what it was compiled to know, so enumerate the line and hand
      // every unmapped key over as rabadon.<key>. Non-string values go across
      // as their own (minified) JSON text — a reader that does not know the
      // field has no business guessing its type.
      for (const RbField& fl : lp.f) {
        if (fl.key.empty()) continue;
        if (is_mapped_field(fl.key) && mapper_took(fl.key, fl.is_string, fl.val)) continue;
        // the one true duplicate: usd_e6 leaves as an exact integer attribute
        // under this very name, and OTLP attribute keys are a map. Emitting it
        // twice, once as intValue and once as stringValue, lets the collector
        // pick. Every other raw field stays, deliberately — see export_test.sh
        // arm 5: an unknown producer's "out" may not mean tokens at all.
        if (fl.key == "usd_e6" && e.usd_e6 > 0) continue;
        if (!e.extra.empty()) e.extra += ",";
        e.extra += attr_str("rabadon." + fl.key, fl.is_string ? fl.val : jmin(fl.val));
      }

      RbDrillEv c;
      c.has_pipe = !e.pipe.empty();
      c.pipe = e.pipe; c.ts = e.ts;
      c.tag = rb_drill_tag(line);
      c.marker = rb_drill_marker(line);
      c.run = e.run;                            // rule 5
      c.repair_start = rb_repair_start(line);   // rule 5
      c.repair_end = rb_repair_end(line);       // rule 5
      c.gated = rb_gated_action(line);          // rule 5
      classify.push_back(std::move(c));
      parsed.push_back(std::move(e));
    }
  }

  // drills never leave the machine — all four rules, the same ones `rabadon
  // usage` counts with, so the two surfaces cannot tell different stories.
  vector<char> isDrill = rb_mark_drills(classify);
  vector<Ev> events;
  for (size_t i = 0; i < parsed.size(); i++) {
    if (isDrill[i]) continue;
    events.push_back(std::move(parsed[i]));
  }
  std::stable_sort(events.begin(), events.end(), [](const Ev& a, const Ev& b) { return a.ts != b.ts ? a.ts < b.ts : a.seq < b.seq; });

  // ---- identity, once, for every event: which trace it joins and what its
  // span id is. Both used to be computed inside the emit loop, which is fine
  // for a document where no span refers to another one. A parent link is a
  // reference, so the ids have to exist before the first span is written.
  //
  // The trace ladder, in order: the SESSION id the hook was handed; failing
  // that the pipe, which is a directory and says so on the span; failing that
  // the file the line was read from, which is at least a real place a human can
  // open. The session seed is namespaced so a session id and a pipe that happen
  // to spell the same string cannot land in the same trace.
  vector<string> tids(events.size()), sids(events.size());
  long long n_tr_sess = 0, n_tr_pipe = 0, n_tr_file = 0;
  {
    std::map<string, char> seenTrace;
    for (size_t i = 0; i < events.size(); i++) {
      const Ev& e = events[i];
      string seed;
      if (!e.sess.empty()) seed = "rabadon:sess:" + e.sess;
      else if (!e.pipe.empty()) seed = e.pipe;
      else seed = "rabadon:no-pipe:" + e.file;
      tids[i] = trace_id(seed);
      if (!seenTrace.count(tids[i])) {
        seenTrace[tids[i]] = 1;
        if (!e.sess.empty()) n_tr_sess++; else if (!e.pipe.empty()) n_tr_pipe++; else n_tr_file++;
      }
      // run+seq+ts identifies an event only while the line is readable enough
      // to have them. A torn line has neither, and three torn lines in a row
      // would have collided on one span id (OTLP: a span id is unique within a
      // trace), so the source position — which IS unique — completes the seed.
      sids[i] = span_id(e.run.empty()
        ? e.src + ":" + std::to_string((long long)e.seq) + ":" + std::to_string((long long)e.ts)
        : e.run + ":" + std::to_string((long long)e.seq) + ":" + std::to_string((long long)e.ts));
    }
  }

  // ---- the join. STEP_START and STEP_OK are the two ends of ONE tool call and
  // the ledger never said so: `run` is per-process, `seq` is 95.6% the literal
  // 1, and `prev` is a write-order chain that crosses pipes. Pairing on "the
  // next OK in the same pipe" closed 58.5% of the starts, joined unrelated work
  // in 17.6% of even those, and produced a p99 of 15.5 minutes and one pair
  // five days wide. `call` is the tool_use_id both hooks are handed, so this is
  // the identity itself rather than a heuristic over it.
  //
  // The OK carries the interval and the START becomes its child. Dropping the
  // START would have been the cheaper way to get one row per call, and this
  // exporter is not allowed to buy anything with a deleted event — SPEC §2 has
  // no clause for it, and the START is the only line that says the gate ADMITTED
  // the call, which for a product whose subject is refusal is the half a reader
  // came for. parentSpanId costs nothing and says more: a viewer nests the
  // point inside the interval, so the top level is one row per call anyway.
  //
  // Four refusals, the same standard the dur_ms widening is held to — a wrong
  // interval is worse than an honest point:
  //   - either end undated: an undated line's ts is the day its FILE is named
  //     for, so pairing on it would invent an interval out of a filename;
  //   - the OK older than the START: that is not an interval;
  //   - the two in different traces: OTLP says a parent and its child share a
  //     trace id, and a link across traces is a dangling reference;
  //   - a missing counterpart: an open START and an orphan OK both stay points.
  // First occurrence wins on each side, so a twin delivery that reached the
  // disk cannot widen a call by however long the duplicate took to arrive.
  struct CallPair { long long start = -1, ok = -1; };
  vector<long long> pairStart(events.size(), -1), pairEnd(events.size(), -1);
  long long n_paired = 0, n_ok = 0, n_ok_nocall = 0;
  {
    std::map<string, CallPair> calls;
    for (size_t i = 0; i < events.size(); i++) {
      const Ev& e = events[i];
      if (e.ev == "STEP_OK") { n_ok++; if (e.call.empty()) n_ok_nocall++; }
      if (e.call.empty()) continue;
      if (e.ev == "STEP_START") { CallPair& p = calls[e.call]; if (p.start < 0) p.start = (long long)i; }
      else if (e.ev == "STEP_OK") { CallPair& p = calls[e.call]; if (p.ok < 0) p.ok = (long long)i; }
    }
    for (const auto& kv : calls) {
      long long a = kv.second.start, b = kv.second.ok;
      if (a < 0 || b < 0) continue;
      if (!events[a].dated || !events[b].dated) continue;
      if (events[b].ts < events[a].ts) continue;
      if (tids[a] != tids[b]) continue;
      pairStart[b] = a; pairEnd[a] = b; n_paired++;
    }
  }

  string out = "{\"resourceSpans\":[{\"resource\":{\"attributes\":[" + attr_str("service.name", "rabadon") + "," + attr_str("telemetry.sdk.name", "rabadon-export") + "]},\"scopeSpans\":[{\"scope\":{\"name\":\"rabadon\"},\"spans\":[";
  bool firstSpan = true;
  for (size_t i = 0; i < events.size(); i++) {
    const Ev& e = events[i];
    // A line with no `ev` at all is not in the vocabulary and not outside it
    // either — but it is still something that happened, and dropping it is the
    // silence this exporter just stopped committing. It ships under a name a
    // human can see in a trace list instead of the blank row an empty name
    // renders as; its fields ride along like any other unrecognised event.
    //
    // rabadon.ev carries that same name. It is the ledger's `ev` whenever the
    // line has one, and the reader's own word for the line when it does not,
    // because a span with an empty name AND an empty pipe is an anonymous row:
    // nothing to search for, nothing to group by, no way back to the bytes it
    // came from. Two of those shipped out of eighteen lines in
    // export_drop_test's fixture, into the trace id of the literal string "?".
    string evName = e.ev.empty() ? (e.readable ? "UNKNOWN" : "UNREADABLE") : e.ev;
    const string& tid = tids[i];
    const string& sid = sids[i];
    bool isCatch = (e.ev == "STOP" || e.ev == "CHECK_FAIL" || e.ev == "WOULD_BLOCK" || e.ev == "REPAIR_FAIL");
    string name = evName;
    if (!e.rule.empty()) name += ":" + e.rule;
    string attrs = attr_str("rabadon.ev", evName);
    if (!e.rule.empty()) attrs += "," + attr_str("rabadon.rule", e.rule);
    if (!e.detail.empty()) attrs += "," + attr_str("rabadon.detail", e.detail);
    attrs += "," + attr_str("rabadon.pipe", e.pipe);
    attrs += "," + attr_str("rabadon.export.source", e.src);
    // What this span's TRACE actually is. "session" is the thing the word trace
    // means to whoever opens the viewer; the other two are fallbacks and the
    // reader is entitled to know it got one. Said on every span rather than
    // only where it degrades, because "the attribute is missing" is not a
    // statement a stranger can read, and the whole 86,881-line spool on this
    // machine predates the session id: every one of those spans says "pipe",
    // which is the honest label for a trace that is a folder's entire history.
    attrs += "," + attr_str("rabadon.export.trace_basis",
      !e.sess.empty() ? "session" : (!e.pipe.empty() ? "pipe" : "file"));
    if (!e.dated) {
      // said on the span, not only in the summary: whoever queries this trace
      // by time is entitled to know the time is the file's, not the line's.
      attrs += "," + attr_str("rabadon.export.dated", "no");
      attrs += "," + attr_str("rabadon.export.ts_basis", "the day this spool file is named for — the line carries no readable ts");
    }
    if (!e.readable) {
      attrs += "," + attr_str("rabadon.export.unreadable", e.why);
      attrs += "," + attr_str("rabadon.export.raw", e.raw);
    }
    if (e.tin > 0 || e.tout > 0 || e.usd_e6 > 0) {
      attrs += "," + attr_str("gen_ai.system", "anthropic");
      if (!e.model.empty()) attrs += "," + attr_str("gen_ai.request.model", e.model);
      if (e.tin > 0) attrs += "," + attr_int("gen_ai.usage.input_tokens", e.tin);
      if (e.tout > 0) attrs += "," + attr_int("gen_ai.usage.output_tokens", e.tout);
      // Cost stays in rabadon's own namespace. OpenTelemetry's GenAI
      // conventions define token counts and expect a backend to derive money
      // from them; there is no gen_ai.usage.cost, so inventing one would be
      // squatting a namespace rabadon does not own. The one number the product
      // model actually sells still has to leave the machine — it leaves named
      // honestly, exact integer first.
      if (e.usd_e6 > 0) {
        attrs += "," + attr_int("rabadon.usd_e6", e.usd_e6);
        attrs += "," + attr_dbl("rabadon.cost_usd", (double)e.usd_e6 / 1e6);
      }
    }
    if (!e.extra.empty()) attrs += "," + e.extra;
    // A line the reader could not parse is an error about the LEDGER, and it
    // renders red for the same reason a refusal does: the person looking at
    // this trace is the only one who can go fix the producer that wrote it.
    string status;
    if (isCatch) status = ",\"status\":{\"code\":2,\"message\":\"" + jesc(e.rule.empty() ? e.ev : e.rule) + "\"}";
    else if (!e.readable) status = ",\"status\":{\"code\":2,\"message\":\"" + jesc("unreadable ledger line: " + e.why) + "\"}";
    // A span is an interval, and rabadon knew the interval all along. Every
    // span this exporter ever shipped had start == end, so a whole rabadon run
    // rendered in a trace viewer as a row of zero-width marks: the one thing a
    // person opens a trace to see, which of these steps was slow, was the one
    // thing the document could not answer. loop.cpp has written dur_ms beside
    // the token count since the proposer sidecar landed and nothing read it.
    //
    // The direction is measured, not assumed. `ts` is stamped by the appender
    // (Emitter::ev, and net.cpp's finish()), and both stamp it after the work
    // returns with the elapsed time in hand, so the line's instant is the END
    // of its interval and the span runs [ts - dur_ms, ts]. Getting this
    // backwards would have put every span in the future.
    //
    // Three refusals, because a wrong interval is worse than an honest point:
    // a duration longer than the epoch instant it is subtracted from is not a
    // duration, a negative one is not either, and an UNDATED line's ts is the
    // day its file is named for rather than a moment, so widening it would
    // invent an interval out of a filename. Those stay point-in-time and still
    // carry the raw dur_ms as an attribute, like every unmapped field.
    //
    // A matched START/OK pair OUTRANKS dur_ms when a line somehow has both.
    // The pair is two instants this ledger stamped itself, on one clock, both
    // on disk and both re-derivable by anyone holding the same bytes; dur_ms is
    // a number the producer wrote about its own runtime. Where they disagree,
    // the document should say what the ledger recorded.
    double t_end = e.ts, t_start = e.ts;
    string basis;
    if (pairStart[i] >= 0) { t_start = events[pairStart[i]].ts; basis = "pair"; }
    else if (e.dur_ms > 0 && e.dated && (double)e.dur_ms <= e.ts) { t_start = e.ts - (double)e.dur_ms; basis = "dur_ms"; }
    // Where the width came from, whenever a rule widened it, so nobody has to
    // guess whether a duration was measured or self-reported. A point needs no
    // explanation and gets no attribute.
    if (!basis.empty()) attrs += "," + attr_str("rabadon.span.basis", basis);
    if (pairStart[i] >= 0) attrs += "," + attr_str("rabadon.span.start_source", events[pairStart[i]].src);
    // The START of a matched call hangs under its OK. Written only when the
    // pair passed every refusal above, so this id always names a span that is
    // in this document and in this trace.
    string parent;
    if (pairEnd[i] >= 0) parent = ",\"parentSpanId\":\"" + sids[pairEnd[i]] + "\"";
    string span = string("{\"traceId\":\"") + tid + "\",\"spanId\":\"" + sid + "\"" + parent +
      ",\"name\":\"" + jesc(name) + "\",\"kind\":1,\"startTimeUnixNano\":\"" + nanos(t_start) +
      "\",\"endTimeUnixNano\":\"" + nanos(t_end) + "\",\"attributes\":[" + attrs + "]" + status + "}";
    if (!firstSpan) out += ",";
    out += span; firstSpan = false;
  }
  out += "]}]}]}\n";
  fwrite(out.data(), 1, out.size(), stdout);

  // Close the books, on stderr, where they cannot corrupt the document on
  // stdout. Three surfaces read this spool and the other two have always
  // answered to a count; this one exited 0 over 80,690 lines and 77,084 spans
  // and said nothing at all, so the 3,606-line gap was only reconstructable by
  // someone who had already read this file. Every line read lands in exactly
  // one bucket, and the arithmetic is printed so it can be checked rather than
  // trusted.
  {
    long long shipped = (long long)events.size();
    long long drills = (long long)parsed.size() - shipped;
    string m = "rabadon export: " + std::to_string(n_read) + " line(s) read from " +
               std::to_string(n_files) + " spool file(s), " + std::to_string(shipped) + " span(s) out\n";
    m += "  held back: " + std::to_string(n_old_ts + n_old_file) + " outside the " +
         (days == (double)(long long)days ? std::to_string((long long)days) : std::to_string(days)) +
         "-day window";
    if (n_old_file) m += " (" + std::to_string(n_old_file) + " of them by file date, having no readable ts)";
    m += ", " + std::to_string(drills) + " drill event(s)\n";
    // The two numbers that decide whether this document is readable at all: how
    // many traces it is cut into, and how many tool calls have a width. Both
    // were silent while one folder's nine days shipped as a single 24,056-span
    // trace and every span in it was zero-width.
    m += "  traces: " + std::to_string(n_tr_sess + n_tr_pipe + n_tr_file) +
         " (" + std::to_string(n_tr_sess) + " keyed by session id, " +
         std::to_string(n_tr_pipe) + " by pipe name, " + std::to_string(n_tr_file) + " by file)\n";
    m += "  tool calls: " + std::to_string(n_paired) + " joined start->ok by call id";
    if (n_ok_nocall)
      m += ", " + std::to_string(n_ok_nocall) + " of " + std::to_string(n_ok) +
           " STEP_OK carry no call id and stay points (the gate began writing it 4 August 2026)";
    m += "\n";
    if (n_unreadable || n_undated || n_badutf8) {
      m += "  shipped, and damaged:";
      string parts;
      if (n_unreadable) parts += " " + std::to_string(n_unreadable) + " unreadable (span name UNREADABLE, rabadon.export.unreadable says where),";
      if (n_undated) parts += " " + std::to_string(n_undated) + " with no readable ts (dated from the file name),";
      if (n_badutf8) parts += " " + std::to_string(n_badutf8) + " carrying invalid UTF-8 (those bytes leave as U+FFFD),";
      if (!parts.empty()) parts.erase(parts.size() - 1);
      m += parts + "\n";
    }
    // the check, not the claim: read == shipped + held back, or the counter is
    // lying and the operator hears about it from the counter itself.
    long long booked = shipped + drills + n_old_ts + n_old_file;
    if (booked != n_read)
      m += "  WARNING: the accounting does not reconcile — " + std::to_string(n_read) +
           " read but " + std::to_string(booked) + " booked. This is a bug in rabadon-export.\n";
    fwrite(m.data(), 1, m.size(), stderr);
  }
  return 0;
}
