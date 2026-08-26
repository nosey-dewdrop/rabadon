// rabadon-stats — the catch ledger, native (C++17, zero deps).
//
// This is `rabadon usage` (alias: stats): the value-proof surface. It reads
// the same spool the gate writes and answers ONE question — what did rabadon
// actually do for you — grouped by RULE, not by detail-string prefix.
//
// Renderer law:
//   - blocked actions are grouped by rule id. The id comes from, in order:
//     the STOP event's own "rule" field (new emits), the CHECK_FAIL that
//     shares the STOP's run id (fails[0].check), or the detail split at the
//     em dash (legacy events).
//   - WATCH-mode verdicts (WOULD_BLOCK) are first-class: a week of watching
//     produces "here is what I would have caught" — that bucket IS the
//     adoption story and it is rendered, never dropped.
//   - nothing is cut mid-word without an ellipsis; long reasons are
//     ellipsized to the terminal width (COLUMNS override, ioctl, fallback 100).
//   - drills/demos/self-tests are excluded from every number and said so —
//     the ledger's honesty is the product.
//   - deterministic: RABADON_NOW (ms, test hook) pins the clock; TZ pins the
//     timestamps. The golden tests depend on this.
//
// Spool semantics kept from the differential-oracle port (proven previously
// against core/store.mjs, now guarded by golden files in stats_test.sh):
//   RABADON_DIR fallback, --days JS Number() quirks, per-event ts filter,
//   stable sorts, UTF-16 slice semantics, markDrills two-pass exclusion.

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <dirent.h>
#include <pwd.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>
#include "cli_help.h"
#include "drill.h"
#include "prices.h"
#include "counter.h"
#include "moves.h"
#include "signals.h"

using std::string;
using std::u16string;

// ---------- time ----------
static double now_ms() {
  const char* t = getenv("RABADON_NOW"); // test hook: pin the clock
  if (t && t[0]) { double v = strtod(t, nullptr); if (v > 0) return v; }
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  long long ms = (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
  return (double)ms;
}

// ---------- UTF-8 <-> UTF-16 code units (JS string semantics) ----------
static void push_cp(u16string& out, uint32_t cp) {
  if (cp <= 0xFFFF) out.push_back((char16_t)cp);
  else { cp -= 0x10000; out.push_back((char16_t)(0xD800 + (cp >> 10))); out.push_back((char16_t)(0xDC00 + (cp & 0x3FF))); }
}

static u16string json_body_to_u16(const string& s) {
  u16string out;
  size_t i = 0;
  while (i < s.size()) {
    unsigned char c = (unsigned char)s[i];
    if (c == '\\' && i + 1 < s.size()) {
      char e = s[i + 1]; i += 2;
      switch (e) {
        case 'n': out.push_back(u'\n'); break;
        case 't': out.push_back(u'\t'); break;
        case 'r': out.push_back(u'\r'); break;
        case 'b': out.push_back(u'\b'); break;
        case 'f': out.push_back(u'\f'); break;
        case '"': out.push_back(u'"'); break;
        case '\\': out.push_back(u'\\'); break;
        case '/': out.push_back(u'/'); break;
        case 'u': {
          unsigned v = 0;
          for (int k = 0; k < 4 && i < s.size(); k++, i++) {
            char h = s[i]; v <<= 4;
            if (h >= '0' && h <= '9') v |= (unsigned)(h - '0');
            else if (h >= 'a' && h <= 'f') v |= (unsigned)(h - 'a' + 10);
            else if (h >= 'A' && h <= 'F') v |= (unsigned)(h - 'A' + 10);
          }
          out.push_back((char16_t)v);
          break;
        }
        default: out.push_back((char16_t)(unsigned char)e); break;
      }
    } else if (c < 0x80) { out.push_back((char16_t)c); i++; }
    else {
      uint32_t cp = 0; int extra = 0;
      if ((c >> 5) == 0x6) { cp = c & 0x1F; extra = 1; }
      else if ((c >> 4) == 0xE) { cp = c & 0x0F; extra = 2; }
      else if ((c >> 3) == 0x1E) { cp = c & 0x07; extra = 3; }
      else { out.push_back((char16_t)0xFFFD); i++; continue; }
      if (i + (size_t)extra >= s.size()) { out.push_back((char16_t)0xFFFD); i++; continue; }
      bool okc = true;
      for (int k = 1; k <= extra; k++) {
        unsigned char cc = (unsigned char)s[i + (size_t)k];
        if ((cc & 0xC0) != 0x80) { okc = false; break; }
        cp = (cp << 6) | (cc & 0x3F);
      }
      if (!okc) { out.push_back((char16_t)0xFFFD); i++; continue; }
      i += (size_t)extra + 1;
      push_cp(out, cp);
    }
  }
  return out;
}

static string u16_to_utf8(const u16string& s) {
  string out;
  for (size_t i = 0; i < s.size(); i++) {
    uint32_t cp = s[i];
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < s.size() && s[i + 1] >= 0xDC00 && s[i + 1] <= 0xDFFF) {
      cp = 0x10000 + ((cp - 0xD800) << 10) + (uint32_t)(s[i + 1] - 0xDC00); i++;
    } else if (cp >= 0xD800 && cp <= 0xDFFF) {
      cp = 0xFFFD;
    }
    if (cp < 0x80) out += (char)cp;
    else if (cp < 0x800) { out += (char)(0xC0 | (cp >> 6)); out += (char)(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { out += (char)(0xE0 | (cp >> 12)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
    else { out += (char)(0xF0 | (cp >> 18)); out += (char)(0x80 | ((cp >> 12) & 0x3F)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
  }
  return out;
}

// ---------- strict JSON parser (JSON.parse grammar; a bad line = unparseable) ----------
struct JV {
  enum T { OBJ, ARR, STR, NUM, BOOL, NUL } t = NUL;
  std::vector<std::pair<string, JV>> o;
  std::vector<JV> a;
  string s;
  bool b = false;
  double num() const { return strtod(s.c_str(), nullptr); }
  const JV* get(const string& key) const {
    const JV* r = nullptr;
    for (auto& kv : o) if (kv.first == key) r = &kv.second;
    return r;
  }
};

struct JParse {
  const string& s; size_t i = 0; bool ok = true;
  explicit JParse(const string& src) : s(src) {}
  void ws() { while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) i++; }
  JV root() { ws(); JV v = value(); ws(); if (i != s.size()) ok = false; return v; }
  JV value() {
    ws();
    if (i >= s.size()) { ok = false; return {}; }
    char c = s[i];
    if (c == '{') return object();
    if (c == '[') return array();
    if (c == '"') { JV v; v.t = JV::STR; v.s = str(); return v; }
    if (c == 't') { if (s.compare(i, 4, "true") == 0) { i += 4; JV v; v.t = JV::BOOL; v.b = true; return v; } ok = false; return {}; }
    if (c == 'f') { if (s.compare(i, 5, "false") == 0) { i += 5; JV v; v.t = JV::BOOL; v.b = false; return v; } ok = false; return {}; }
    if (c == 'n') { if (s.compare(i, 4, "null") == 0) { i += 4; JV v; v.t = JV::NUL; return v; } ok = false; return {}; }
    return number();
  }
  string str() {
    string out; i++;
    while (i < s.size()) {
      unsigned char c = (unsigned char)s[i];
      if (c == '"') { i++; return out; }
      if (c < 0x20) break;
      if (c == '\\') {
        if (i + 1 >= s.size()) break;
        char e = s[i + 1];
        if (e == '"' || e == '\\' || e == '/' || e == 'b' || e == 'f' || e == 'n' || e == 'r' || e == 't') {
          out += (char)c; out += e; i += 2; continue;
        }
        if (e == 'u') {
          bool hex4 = true;
          for (int k = 2; k <= 5; k++) if (i + (size_t)k >= s.size() || !isxdigit((unsigned char)s[i + (size_t)k])) { hex4 = false; break; }
          if (!hex4) break;
          out.append(s, i, 6); i += 6; continue;
        }
        break;
      }
      out += (char)c; i++;
    }
    ok = false; return out;
  }
  JV number() {
    size_t a0 = i;
    if (i < s.size() && s[i] == '-') i++;
    if (i < s.size() && s[i] == '0') i++;
    else if (i < s.size() && s[i] >= '1' && s[i] <= '9') { while (i < s.size() && isdigit((unsigned char)s[i])) i++; }
    else { ok = false; return {}; }
    if (i < s.size() && s[i] == '.') {
      i++; if (i >= s.size() || !isdigit((unsigned char)s[i])) { ok = false; return {}; }
      while (i < s.size() && isdigit((unsigned char)s[i])) i++;
    }
    if (i < s.size() && (s[i] == 'e' || s[i] == 'E')) {
      i++; if (i < s.size() && (s[i] == '+' || s[i] == '-')) i++;
      if (i >= s.size() || !isdigit((unsigned char)s[i])) { ok = false; return {}; }
      while (i < s.size() && isdigit((unsigned char)s[i])) i++;
    }
    JV v; v.t = JV::NUM; v.s = s.substr(a0, i - a0); return v;
  }
  JV object() {
    JV v; v.t = JV::OBJ; i++; ws();
    if (i < s.size() && s[i] == '}') { i++; return v; }
    while (i < s.size()) {
      ws(); if (i >= s.size() || s[i] != '"') { ok = false; break; }
      string key = str(); if (!ok) break; ws();
      if (i >= s.size() || s[i] != ':') { ok = false; break; }
      i++;
      JV val = value(); if (!ok) break;
      v.o.push_back({key, val}); ws();
      if (i < s.size() && s[i] == ',') { i++; continue; }
      if (i < s.size() && s[i] == '}') { i++; return v; }
      ok = false; break;
    }
    ok = false; return v;
  }
  JV array() {
    JV v; JV e; v.t = JV::ARR; i++; ws();
    if (i < s.size() && s[i] == ']') { i++; return v; }
    while (i < s.size()) {
      e = value(); if (!ok) break;
      v.a.push_back(e); ws();
      if (i < s.size() && s[i] == ',') { i++; continue; }
      if (i < s.size() && s[i] == ']') { i++; return v; }
      ok = false; break;
    }
    ok = false; return v;
  }
};

// ---------- JS Number() for --days (kept: CLI contract is stable) ----------
static double js_number(const char* a, bool& is_nan) {
  is_nan = false;
  string s(a);
  size_t b = s.find_first_not_of(" \t\r\n\f\v");
  if (b == string::npos) return 0.0;
  size_t e = s.find_last_not_of(" \t\r\n\f\v");
  s = s.substr(b, e - b + 1);
  if (s.size() > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
    for (size_t k = 2; k < s.size(); k++) if (!isxdigit((unsigned char)s[k])) { is_nan = true; return 0; }
    return (double)strtoull(s.c_str() + 2, nullptr, 16);
  }
  if (s.size() > 2 && s[0] == '0' && (s[1] == 'o' || s[1] == 'O')) {
    for (size_t k = 2; k < s.size(); k++) if (s[k] < '0' || s[k] > '7') { is_nan = true; return 0; }
    return (double)strtoull(s.c_str() + 2, nullptr, 8);
  }
  if (s.size() > 2 && s[0] == '0' && (s[1] == 'b' || s[1] == 'B')) {
    for (size_t k = 2; k < s.size(); k++) if (s[k] != '0' && s[k] != '1') { is_nan = true; return 0; }
    return (double)strtoull(s.c_str() + 2, nullptr, 2);
  }
  string t = s; bool neg = false;
  if (!t.empty() && (t[0] == '+' || t[0] == '-')) { neg = t[0] == '-'; t = t.substr(1); }
  if (t == "Infinity") return neg ? -INFINITY : INFINITY;
  string low; for (char c : t) low += (char)tolower((unsigned char)c);
  if (low == "inf" || low == "infinity" || low == "nan") { is_nan = true; return 0; }
  if (t.size() > 1 && t[0] == '0' && (t[1] == 'x' || t[1] == 'X')) { is_nan = true; return 0; }
  char* endp = nullptr;
  double v = strtod(s.c_str(), &endp);
  if (endp && *endp == '\0' && endp != s.c_str()) return v;
  is_nan = true; return 0;
}

static string js_num_str(double v) {
  if (std::isinf(v)) return v < 0 ? "-Infinity" : "Infinity";
  if (v == std::floor(v) && std::fabs(v) < 1e15) {
    long long i = (long long)v;
    return std::to_string(i == 0 ? 0 : i);
  }
  char buf[64];
  for (int prec = 1; prec <= 17; prec++) {
    snprintf(buf, sizeof buf, "%.*g", prec, v);
    if (strtod(buf, nullptr) == v) break;
  }
  return string(buf);
}

// thousands separator: 3290 -> "3,290"
static string commas(long long n) {
  string s = std::to_string(n);
  bool neg = !s.empty() && s[0] == '-';
  string d = neg ? s.substr(1) : s;
  string out;
  int c = 0;
  for (int i = (int)d.size() - 1; i >= 0; i--) {
    out += d[(size_t)i];
    if (++c % 3 == 0 && i > 0) out += ',';
  }
  std::reverse(out.begin(), out.end());
  return (neg ? "-" : "") + out;
}

// local timestamp "YYYY-MM-DD HH:MM" (TZ env pins it for the goldens)
static string local_stamp(double ms) {
  time_t t = (time_t)(ms / 1000.0);
  struct tm tmv; localtime_r(&t, &tmv);
  char buf[24]; strftime(buf, sizeof buf, "%Y-%m-%d %H:%M", &tmv);
  return string(buf);
}

// terminal width: COLUMNS env, else ioctl, else 100
static size_t term_width() {
  const char* c = getenv("COLUMNS");
  if (c && c[0]) { long v = strtol(c, nullptr, 10); if (v >= 40) return (size_t)v; }
  struct winsize w;
  if (isatty(STDOUT_FILENO) && ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 && w.ws_col >= 40) return w.ws_col;
  return 100;
}

// ellipsize a UTF-16 string to fit `cols` columns (code units ~ columns) —
// never a bare mid-word cut: if it does not fit, it ends in a visible "…"
static string fit(const u16string& s, size_t cols) {
  u16string one;
  for (char16_t ch : s) one += (ch == u'\n' || ch == u'\r' || ch == u'\t') ? u' ' : ch;
  if (one.size() <= cols) return u16_to_utf8(one);
  if (cols == 0) return "";
  u16string cut = one.substr(0, cols - 1);
  cut += u'…';
  return u16_to_utf8(cut);
}

// ---------- spool event model ----------
struct Event {
  double ts = 0;
  double seq = 0;
  bool drill = false;
  bool drill_emit = false;
  bool has_pipe = false;
  string pipe;
  string run;
  string ev;
  string reason;      // STOP: BLOCKED/...; WOULD_BLOCK: the rule id
  string rule;        // explicit "rule" field (new emits)
  bool has_fails_arr = false;
  long long fails_len = 0;
  long long loop_stops = 0;
  string fail_check;  // fails[0].check
  u16string fail_why; // fails[0].why
  u16string detail;   // STOP / WOULD_BLOCK
  // REPAIR_OK carries FOUR different facts under one event name. repair_kind
  // separates them at the source: "testrun" = the push gate ran the suite and
  // it went green, "rule" = a guard rule was written, absent = an actual code
  // repair. For a repair, `locks` is how many test files were hash-locked while
  // the fix was re-checked — 0 means the anti-tamper check had nothing to hold.
  string repair_kind;
  long long locks = 0;
  bool marker_hit = false;
  // R6: the counter's own event, kept whole. `rabadon usage` READS the number
  // the gate already committed to the ledger at session close — it does not
  // recompute it. A surface that recomputes is a second implementation of the
  // arithmetic, and the two would disagree the first time one of them changed.
  bool has_counter = false;
  JV counter;
  string sess;
};

// The four drill rules live in drill.h — one implementation, so the number
// printed here and the spans rabadon-export ships agree on what a drill is.

// A pipe label is "<project>:<surface>": the hooks write ":session"
// (gate.cpp, drift.cpp, repair.cpp), `rabadon do` writes ":do" (pipeline.cpp),
// `rabadon exec` writes ":exec" (sandbox.cpp). The surface is how the event
// arrived, not what it happened to — so the ledger folds it off and groups by
// the project. Listing the known suffixes was the bug: ":exec" was not on the
// list, so one repo rendered as two projects, `proj` and `proj:exec`, in the
// one screen a user would show someone else. Cut at the LAST colon instead —
// the same rule trace.cpp already uses — so a new surface can never fork a
// row again. No colon (or an empty/absent pipe) means the label is already the
// project.
static string project_of(bool has_pipe, const string& pipe) {
  const string p = (has_pipe && !pipe.empty()) ? pipe : "?";
  const size_t c = p.rfind(':');
  if (c == string::npos || c == 0) return p;
  return p.substr(0, c);
}

static bool parse_day_utc(const string& name, double& out_ms) {
  if (name.size() < 10) return false;
  const char* p = name.c_str();
  for (int k : {0, 1, 2, 3, 5, 6, 8, 9}) if (p[k] < '0' || p[k] > '9') return false;
  if (p[4] != '-' || p[7] != '-') return false;
  int y = (p[0]-'0')*1000 + (p[1]-'0')*100 + (p[2]-'0')*10 + (p[3]-'0');
  int m = (p[5]-'0')*10 + (p[6]-'0');
  int d = (p[8]-'0')*10 + (p[9]-'0');
  if (m < 1 || m > 12) return false;
  static const int md[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  int dim = md[m - 1] + ((m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) ? 1 : 0);
  if (d < 1 || d > dim) return false;
  int yy = y - (m <= 2 ? 1 : 0);
  long long era = (yy >= 0 ? yy : yy - 399) / 400;
  unsigned yoe = (unsigned)(yy - era * 400);
  unsigned doy = (unsigned)((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1);
  unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  long long days = era * 146097 + (long long)doe - 719468;
  out_ms = (double)days * 86400000.0;
  return true;
}

static string read_file(const string& p) {
  struct stat st;
  if (stat(p.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return string();
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

// ---------- per-project ledger ----------
struct Catch { double ts; u16string detail; };
struct Rule {
  string id;
  u16string why;      // representative: first seen
  long long n = 0;
  std::vector<Catch> hits; // kept for --full
};
struct Proj {
  string name;
  long long gated = 0, blocked = 0, wouldBlocked = 0, checkFails = 0, loopsStopped = 0;
  // one bucket per FACT, never one bucket for the word "repair"
  long long repairsHeld = 0, repairsUnverified = 0, pushGates = 0, rulesWritten = 0;
  double lastTs = 0;
  std::vector<Rule> rules;      // blocked, grouped by rule id
  std::vector<Rule> wouldRules; // watch-mode verdicts, grouped by rule id
};

static Rule& rule_for(std::vector<Rule>& v, const string& id) {
  for (Rule& r : v) if (r.id == id) return r;
  v.push_back(Rule{}); v.back().id = id;
  return v.back();
}

static string json_escape(const string& s) {
  string out;
  for (unsigned char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); out += b; }
        else out += (char)c;
    }
  }
  return out;
}

// ---------- R6: the counter, read back off the ledger ----------------------
// The gate computes the counter once, at session close, where the session's own
// moves are in hand, and commits it to the ledger as a COUNTER event. This
// surface READS that event. It does not recompute anything: a second
// implementation of the same arithmetic is a second answer waiting to disagree
// with the first, and the whole claim of R6 is that there is one number and it
// can be traced to one line of one file.
static bool jv_num(const JV& o, const char* k, double& out) {
  const JV* v = o.get(k);
  if (!v || v->t != JV::NUM) return false;
  out = v->num();
  return true;
}
static string jv_str(const JV& o, const char* k) {
  const JV* v = o.get(k);
  return (v && v->t == JV::STR) ? u16_to_utf8(json_body_to_u16(v->s)) : string();
}
static void counter_from_jv(const JV& o, rbcount::Counter& c) {
  double d = 0;
  c.sess = jv_str(o, "sess");
  if (jv_num(o, "chains_cut", d)) c.chains_cut = (long long)d;
  if (jv_num(o, "fixed", d)) c.fixed_instantly = (long long)d;
  if (jv_num(o, "injections", d)) c.injections = (long long)d;
  c.has_saved = jv_num(o, "saved_usd", d);
  if (c.has_saved) c.saved_usd = d;
  if (jv_num(o, "gross_usd", d)) c.gross_usd = d;
  c.reason = jv_str(o, "reason");
  c.has_median = jv_num(o, "median_uncut", d);
  if (c.has_median) c.median_uncut = d;
  if (jv_num(o, "median_n", d)) c.median_n = (long long)d;
  if (const JV* sm = o.get("samples")) if (sm->t == JV::ARR)
    for (const JV& x : sm->a) if (x.t == JV::NUM) c.samples.push_back(x.num());
  c.has_avg = jv_num(o, "avg_call_usd", d);
  if (c.has_avg) c.avg_call_usd = d;
  if (jv_num(o, "session_usd", d)) c.session_usd = d;
  if (jv_num(o, "calls", d)) c.calls = (long long)d;
  if (jv_num(o, "tok_in", d)) c.tok_in = (long long)d;
  if (jv_num(o, "tok_cw", d)) c.tok_cw = (long long)d;
  if (jv_num(o, "tok_cr", d)) c.tok_cr = (long long)d;
  if (jv_num(o, "tok_out", d)) c.tok_out = (long long)d;
  if (jv_num(o, "inject_usd", d)) c.inject_usd = d;
  c.inject_bound = jv_str(o, "inject_bound");
  if (c.inject_bound.empty()) c.inject_bound = "upper";
  if (jv_num(o, "repair_usd", d)) c.repair_usd = d;
  if (jv_num(o, "repair_tok_in", d)) c.repair_tok_in = (long long)d;
  if (jv_num(o, "repair_tok_out", d)) c.repair_tok_out = (long long)d;
  c.model = jv_str(o, "model");
  c.price_key = jv_str(o, "price_key");
  c.price_cache = jv_str(o, "prices_cached");
  if (const JV* r = o.get("rates")) if (r->t == JV::OBJ) {
    rbprice::Rates rr;
    if (jv_num(*r, "input", rr.in) && jv_num(*r, "output", rr.out) &&
        jv_num(*r, "cache_write", rr.cache_write) && jv_num(*r, "cache_read", rr.cache_read)) {
      c.rates = rr; c.has_rates = true;
    }
  }
  c.spool = jv_str(o, "spool");
  if (const JV* rf = o.get("refs")) if (rf->t == JV::ARR)
    for (const JV& x : rf->a) if (x.t == JV::STR) c.refs.push_back(u16_to_utf8(json_body_to_u16(x.s)));
}

// THE WEEK, NOT THE SESSION. `rabadon usage` reports a window, so the counts
// and the dollars are SUMS over every session that closed inside it, and the
// per-session facts that are not summable — the measured median, this session's
// average call cost, the model and its rates — come from the newest close in
// the window. One caveat is load-bearing: if ANY session in the window could not
// be priced, the window's total is not a total. It is printed as absent, with
// that session's reason, rather than as a smaller number that looks complete.
static rbcount::Counter aggregate_counter(const std::vector<rbcount::Counter>& v) {
  rbcount::Counter out;
  if (v.empty()) {
    out.reason = "no-close";
    out.price_cache = rbprice::ensure_cache();
    return out;
  }
  out = v.back();                       // the newest close carries the per-session facts
  out.chains_cut = 0; out.fixed_instantly = 0; out.injections = 0;
  out.calls = 0; out.tok_in = out.tok_cw = out.tok_cr = out.tok_out = 0;
  out.repair_tok_in = out.repair_tok_out = 0;
  out.inject_usd = out.repair_usd = out.gross_usd = out.session_usd = out.saved_usd = 0;
  out.refs.clear();
  out.has_saved = true;
  for (const rbcount::Counter& c : v) {
    out.chains_cut += c.chains_cut;
    out.fixed_instantly += c.fixed_instantly;
    out.injections += c.injections;
    out.calls += c.calls;
    out.tok_in += c.tok_in; out.tok_cw += c.tok_cw;
    out.tok_cr += c.tok_cr; out.tok_out += c.tok_out;
    out.repair_tok_in += c.repair_tok_in; out.repair_tok_out += c.repair_tok_out;
    out.inject_usd += c.inject_usd;
    out.repair_usd += c.repair_usd;
    out.gross_usd += c.gross_usd;
    out.session_usd += c.session_usd;
    for (const string& r : c.refs) out.refs.push_back(r);
    if (c.has_saved) out.saved_usd += c.saved_usd;
    else { out.has_saved = false; out.reason = c.reason; }
  }
  if (out.has_saved) out.reason.clear();
  if (out.price_cache.empty()) out.price_cache = rbprice::ensure_cache();
  return out;
}

static const char* kHelp =
  "rabadon-stats — what this machine actually spent, from the local ledger.\n"
  "Sessions, tokens by class, cost, tools and duration, read from transcripts that\n"
  "are already on disk. Nothing is estimated and nothing leaves the machine.\n"
  "\n"
  "usage: rabadon-stats [--days N] [--project NAME] [--full] [--json|--md]\n"
  "\n"
  "  --days N        window to report (default 7). Must be positive.\n"
  "  --project NAME  only this project. A name that is not in the window is an\n"
  "                  error (exit 1), not an empty report — the message lists\n"
  "                  the project names that ARE in the window.\n"
  "  --signals       a different store and a different question: replay the five\n"
  "                  R2 detectors over this machine's recorded move rings and\n"
  "                  print what they wrote, with the loss the ring caused, the\n"
  "                  session file behind every count, and NOT MEASURED (with the\n"
  "                  reason) for any detector that never fired. Reads no spool.\n"
  "  --full          every row, not just the top of the table.\n"
  "  --explain       re-derive the session-close counter step by step, citing the\n"
  "                  ledger lines every subtotal came from.\n"
  "  --json          machine-readable.\n"
  "  --md            markdown, for pasting into a report.\n"
  "  -h, --help      this screen.\n"
  "\n"
  "environment:\n"
  "  RABADON_DIR   where the spool lives (default ~/.rabadon).\n"
  "\n"
  "example:\n"
  "  rabadon-stats --days 30 --project rabadon --json\n";

// ===========================================================================
// `rabadon usage --signals` — the R2 move record, read back and counted.
//
// WHAT THIS SCREEN CLAIMS, AND THE TWO THINGS IT REFUSES TO CLAIM
// It claims exactly one layer: rabadon WROTE this, in your own sessions, and
// here is the file each number came out of. It does not claim that anything was
// refused because of it — the R2 signals are silent by construction (signals.h)
// and nothing here ever reached a permission decision. It also prints no
// counterfactual: what an agent would have done in a world where these signals
// spoke is not a measurement, it is a story, and a guard tool that tells that
// story about itself has already lost the argument it exists to win.
//
// WHY THE LOSS IS THE FIRST THING ON THE SCREEN
// The record is a ring of CAP moves per session behind a header that counts
// every move ever appended (moves.h). When a session runs longer than the ring,
// the oldest moves are overwritten: they happened, they were recorded, and they
// are gone. Every count below is therefore over the SURVIVORS. A screen that
// prints the survivors as if they were the record is a smaller number wearing a
// complete number's clothes, which is the exact defect this product refuses in
// other people's test suites. So the loss is disclosed with its size, per ring.
//
// WHY n=0 IS "NOT MEASURED" AND NOT A RESULT
// A detector that never fired on this corpus has not been shown to be quiet; it
// has been shown to be untested here. Those two readings differ by everything,
// and only one of them is honest at n=0. So a zero renders as NOT MEASURED with
// the corpus fact that explains it — how close the corpus came to the threshold
// the detector needs — and it is named as staying out of any live decision.
//
// COST: this is an early-exit arm reached before the spool is opened. Nothing
// in the hook path, the gate or the default `usage` screen runs a byte of it.
namespace rbscreen {

struct SigRow {
  string name;
  long long n = 0;                                   // firings over the corpus
  string why;                                        // the detector's own clause
  std::vector<std::pair<string, std::vector<long long>>> where;  // file -> seqs
  string reason;                                     // set only when n == 0
};

struct Ring {
  string file;
  long long counted = 0;      // header: every move ever appended to this session
  long long kept = 0;         // records still on disk
  std::vector<rbmoves::Move> mv;
};

// One ring off disk. A file that is not a ring is reported as unreadable and
// never silently skipped: "I could not read this" is a designed path.
static bool read_ring(const string& path, Ring& r) {
  FILE* f = fopen(path.c_str(), "rb");
  if (!f) return false;
  rbmoves::Hdr h{};
  if (fread(&h, 1, sizeof h, f) != sizeof h || memcmp(h.magic, "RBMV1", 5) != 0) { fclose(f); return false; }
  r.counted = h.count;
  if (r.counted < 0) { fclose(f); return false; }
  const long long keep = r.counted < (long long)rbmoves::CAP ? r.counted : (long long)rbmoves::CAP;
  std::vector<rbmoves::Rec> ring(rbmoves::CAP);
  if (fseek(f, (long)rbmoves::HDR_BYTES, SEEK_SET) != 0) { fclose(f); return false; }
  if (fread(ring.data(), 1, rbmoves::CAP * sizeof(rbmoves::Rec), f) == 0 && keep > 0) { fclose(f); return false; }
  fclose(f);
  const long long first = r.counted - keep;
  for (long long k = 0; k < keep; k++) {
    rbmoves::Move m;
    rbmoves::from_rec(ring[(size_t)((first + k) % (long long)rbmoves::CAP)], m);
    r.mv.push_back(std::move(m));
  }
  r.kept = keep;
  return true;
}

// A reason is a sentence, not a column, and it has to survive being read in a
// terminal and pasted into a screenshot. Wrapped at the real width, never cut.
static string wrap(const string& text, const string& indent, size_t W) {
  const size_t cols = (W > indent.size() + 20) ? W - indent.size() : 40;
  string out = indent;
  size_t col = 0, i = 0;
  while (i < text.size()) {
    size_t j = text.find(' ', i);
    if (j == string::npos) j = text.size();
    const string word = text.substr(i, j - i);
    if (col && col + 1 + word.size() > cols) { out += "\n" + indent; col = 0; }
    else if (col) { out += ' '; col++; }
    out += word;
    col += word.size();
    i = j + 1;
  }
  return out + "\n";
}

static SigRow* row_for(std::vector<SigRow>& v, const string& name) {
  for (SigRow& s : v) if (s.name == name) return &s;
  return nullptr;
}

static void note(SigRow& s, const string& file, long long seq) {
  for (auto& kv : s.where) if (kv.first == file) { kv.second.push_back(seq); return; }
  s.where.push_back({ file, { seq } });
}

// "file  seq 2, 3" — the §7 rule: no number without the session it came from.
static string where_line(const SigRow& s) {
  string out;
  size_t shown = 0;
  for (const auto& kv : s.where) {
    if (shown == 2) { out += "  (+" + std::to_string(s.where.size() - shown) + " more session file(s))"; break; }
    if (shown) out += "\n            ";
    out += "sessions/" + kv.first + "  seq ";
    for (size_t i = 0; i < kv.second.size() && i < 4; i++) {
      if (i) out += ", ";
      out += std::to_string(kv.second[i]);
    }
    if (kv.second.size() > 4) out += ", +" + std::to_string(kv.second.size() - 4);
    shown++;
  }
  return out;
}

int render(const string& base, bool full) {
  const string sdir = base + "/sessions";
  std::vector<string> names;
  if (DIR* d = opendir(sdir.c_str())) {
    while (struct dirent* e = readdir(d)) {
      const string n = e->d_name;
      if (n.size() > 10 && n.compare(n.size() - 10, 10, ".moves.bin") == 0) names.push_back(n);
    }
    closedir(d);
  }
  std::sort(names.begin(), names.end());

  string out;
  out += "rabadon usage --signals — what rabadon RECORDED in your own sessions\n";
  out += "local, nothing leaves this machine · these signals are silent: none of them\n";
  out += "refused anything, and none of them reached a decision\n\n";

  if (names.empty()) {
    out += "corpus: " + sdir + "\n";
    out += "  NOT MEASURED — there is no move ring on this machine (0 files matching\n";
    out += "  *.moves.bin). reason: moves are recorded by the hooks, inside a project\n";
    out += "  where `rabadon init` has been run. Without a ring there is nothing to\n";
    out += "  replay the detectors over, and a zero here would be about this machine's\n";
    out += "  setup, not about your sessions.\n\n";
    out += "next: run `rabadon init` in the project you are working in\n";
    fwrite(out.data(), 1, out.size(), stdout);
    return 0;
  }

  std::vector<Ring> rings;
  std::vector<string> unreadable;
  for (const string& n : names) {
    Ring r; r.file = n;
    if (read_ring(sdir + "/" + n, r)) rings.push_back(std::move(r));
    else unreadable.push_back(n);
  }

  long long onDisk = 0, counted = 0, lost = 0;
  long long tsMin = 0, tsMax = 0;
  for (const Ring& r : rings) {
    onDisk += r.kept; counted += r.counted; lost += r.counted - r.kept;
    for (const rbmoves::Move& m : r.mv) {
      if (m.ts <= 0) continue;
      if (tsMin == 0 || m.ts < tsMin) tsMin = m.ts;
      if (m.ts > tsMax) tsMax = m.ts;
    }
  }

  // ---- replay: every detector, at every move, exactly as the hook would ----
  std::vector<SigRow> rows;
  for (const char* n : { "repeat", "oscillation", "root_migration", "scope_drift", "green_redefined" })
    { SigRow s; s.name = n; rows.push_back(std::move(s)); }

  // how close the corpus came to each detector's threshold — the material a
  // NOT MEASURED row owes the reader.
  long long repMax = 0, repMaxFailed = 0, oscMax = 0, rootMax = 0, driftMax = 0, greenEdits = 0;

  for (const Ring& r : rings) {
    std::vector<rbmoves::Move> pre;
    for (size_t i = 0; i < r.mv.size(); i++) {
      pre.push_back(r.mv[i]);
      for (const rbsig::Hit& h : rbsig::detect(pre)) {
        SigRow* s = row_for(rows, h.name);
        if (!s) continue;
        s->n++;
        if (s->why.empty()) s->why = h.why;
        note(*s, r.file, r.mv[i].seq);
      }
    }
    // eligibility, measured the same way the detectors read the record
    std::vector<std::pair<string, long long>> pathEdits;
    std::set<string> dirs;
    for (size_t i = 0; i < r.mv.size(); i++) {
      const rbmoves::Move& m = r.mv[i];
      long long seen = 0, failed = 0;
      const size_t from = i + 1 > (size_t)rbsig::REPEAT_WINDOW ? i + 1 - (size_t)rbsig::REPEAT_WINDOW : 0;
      for (size_t k = from; k <= i; k++)
        if (r.mv[k].sig == m.sig) { seen++; if (r.mv[k].claimed_rc == 1) failed++; }
      if (seen > repMax) { repMax = seen; repMaxFailed = failed; }
      if (rbsig::is_edit(m) && !m.path.empty()) {
        dirs.insert(rbsig::dir_of(m.path));
        bool hit = false;
        for (auto& kv : pathEdits) if (kv.first == m.path) { kv.second++; hit = true; break; }
        if (!hit) pathEdits.push_back({ m.path, 1 });
        if (rbsig::decides_green(m.path)) greenEdits++;
      }
      if (!m.err_sig.empty()) {
        std::set<string> sigs;
        for (size_t k = 0; k <= i; k++) if (r.mv[k].err_sig == m.err_sig) sigs.insert(r.mv[k].sig);
        if ((long long)sigs.size() > rootMax) rootMax = (long long)sigs.size();
      }
    }
    for (auto& kv : pathEdits) if (kv.second > oscMax) oscMax = kv.second;
    if ((long long)dirs.size() > driftMax) driftMax = (long long)dirs.size();
  }

  row_for(rows, "repeat")->reason =
      "no move signature repeats " + std::to_string(rbsig::REPEAT_MIN) + "+ times with 2+ of them"
      " returning an error. The longest run of one identical move in this corpus is " +
      std::to_string(repMax) + " (" + std::to_string(repMaxFailed) + " of them carried an error).";
  row_for(rows, "oscillation")->reason =
      "no single file was rewritten back and forth. It needs " + std::to_string(rbsig::OSC_CYCLES * 2) +
      " alternating edits to ONE path; the most-edited file in this corpus has " +
      std::to_string(oscMax) + " edit(s).";
  row_for(rows, "root_migration")->reason =
      "no one error signature survived " + std::to_string(rbsig::ROOT_MIN_PATHS) +
      " different moves. The widest an error spread here is " + std::to_string(rootMax) + " distinct move(s).";
  row_for(rows, "scope_drift")->reason =
      "no session edited " + std::to_string(rbsig::DRIFT_DIRS) + " directories. The widest session here"
      " touched " + std::to_string(driftMax) + ".";
  row_for(rows, "green_redefined")->reason =
      "the suite was never seen red while a test or harness file was edited, and no"
      " test file lost assertions. Edits to a file that decides green in this corpus: " +
      std::to_string(greenEdits) + ".";

  // ---- corpus block: what was read, and what was lost before it was read ----
  out += "corpus: " + sdir + "\n";
  out += "  " + commas((long long)rings.size()) + " session file(s) · " + commas(onDisk) + " move(s) on disk";
  if (tsMin > 0) out += " · " + local_stamp((double)tsMin) + " → " + local_stamp((double)tsMax);
  out += "\n";
  if (lost > 0) {
    out += "  LOSS: " + commas(lost) + " recorded move(s) are gone — the ring keeps the newest "
         + std::to_string(rbmoves::CAP) + " per\n";
    out += "        session, the header counted " + commas(counted) + ". Every number below is over the "
         + commas(onDisk) + "\n        that survived, not over the " + commas(counted) + " that happened.\n";
    size_t shown = 0;
    for (const Ring& r : rings) {
      const long long d = r.counted - r.kept;
      if (d <= 0) continue;
      if (!full && shown == 4) {
        long long more = 0;
        for (const Ring& q : rings) if (q.counted - q.kept > 0) more++;
        out += "        (+" + commas(more - (long long)shown) + " more ring(s); add --full to name them all)\n";
        break;
      }
      out += "        -" + commas(d) + "  sessions/" + r.file + "  (" + commas(r.counted)
           + " counted, " + commas(r.kept) + " kept)\n";
      shown++;
    }
  } else {
    out += "  LOSS: 0 — no ring on this machine has overflowed its " + std::to_string(rbmoves::CAP)
         + " slots yet.\n";
  }
  if (!unreadable.empty()) {
    out += "  UNREADABLE: " + commas((long long)unreadable.size()) + " file(s) in this directory are not"
           " move rings and were not read:\n";
    for (size_t i = 0; i < unreadable.size() && i < 3; i++) out += "        sessions/" + unreadable[i] + "\n";
  }
  out += "\n";

  long long fired = 0, unmeasured = 0;
  for (const SigRow& s : rows) { if (s.n > 0) fired++; else unmeasured++; }
  const size_t W = term_width();

  out += "detectors replayed over every surviving move, in order:\n";
  for (const SigRow& s : rows) {
    string head = "  " + s.name;
    while (head.size() < 20) head += ' ';
    if (s.n == 0) {
      out += head + "NOT MEASURED (n=0)\n";
      out += wrap("reason: " + s.reason + " It stays out of every live decision until it has samples.",
                  "            ", W);
    } else {
      out += head + "n=" + std::to_string(s.n) + "  ·  0 of " + std::to_string(s.n)
           + " labelled by a human — raw counts only\n";
      if (!s.why.empty()) out += "            " + s.why + "\n";
      out += "            " + where_line(s) + "\n";
    }
  }
  out += "\n";

  string sum = "summary: " + std::to_string(fired) + " of " + std::to_string(rows.size())
             + " detectors wrote anything at all here; " + std::to_string(unmeasured)
             + " are NOT MEASURED and are named above with the corpus fact behind each zero. "
             + commas(onDisk) + " move(s) is a short corpus";
  if (lost > 0) sum += " and " + commas(lost) + " more were lost before this screen could read them";
  sum += ", and none of the samples carry a human label — so nothing here is a rate, and"
         " nothing here is evidence that a detector is right.";
  out += wrap(sum, "", W);
  out += "\n";

  // The last line looks forward, at ONE command. A screen about a record ends
  // with the next session, not with a verdict on the last one.
  out += "the corpus grows as you work, and these zeros are the first thing that should move.\n";
  out += "next: run `rabadon usage --signals` again after your next session\n";
  fwrite(out.data(), 1, out.size(), stdout);
  return 0;
}

} // namespace rbscreen

int main(int argc, char** argv) {
  // `rabadon-stats --help` used to be ignored and print the real usage table.
  rb_help(argc, argv, kHelp);

  double days = 7;
  bool full = false, json = false, md = false, explain = false, signals = false;
  // "was --project given" is its own bit, not the emptiness of the value. When
  // the empty string was the sentinel, `--project "$P"` with an unset P asked
  // for one project and got the WHOLE machine's usage at exit 0, under a
  // heading the operator reads as that one project's — the same hazard the
  // unknown-flag guard below was written for, through a different door.
  bool want_project = false;
  bool days_given = false;
  string only_project;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--days") == 0 && i + 1 < argc) {
      bool nan = false;
      double v = js_number(argv[i + 1], nan);
      days = (nan || v == 0) ? 7 : v;
      // A window cannot run backwards. `--days -5` was accepted, rendered the
      // heading "last -5 day(s)" over a spool full of events, matched no event
      // (every ts is newer than a cutoff in the future) and then answered with
      // the empty-ledger onboarding copy at exit 0 — the same lie as a wrong
      // --project, from the other direction. Refused where it is read, so no
      // renderer ever sees a negative window.
      if (days < 0) {
        fprintf(stderr, "rabadon-stats: --days must be positive — \"%s\" asks for a window that ends"
                        " before it starts; the ledger only looks backwards from now\n", argv[i + 1]);
        return 2;
      }
      i++;
      days_given = true;
    } else if (strcmp(argv[i], "--full") == 0) full = true;
    else if (strcmp(argv[i], "--signals") == 0) signals = true;
    else if (strcmp(argv[i], "--explain") == 0) explain = true;
    else if (strcmp(argv[i], "--json") == 0) json = true;
    else if (strcmp(argv[i], "--md") == 0) md = true;
    else if (strcmp(argv[i], "--project") == 0 && i + 1 < argc) { only_project = argv[++i]; want_project = true; }
    // silently ignoring an argument is the dangerous half: `--project foo`
    // mistyped as `--projekt foo` used to print the WHOLE machine's usage under
    // a heading the operator read as one project's.
    else rb_unknown_flag("rabadon-stats", argv[i]);
  }

  string rdir;
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) rdir = rd;
  else {
    const char* h = getenv("HOME");
    string home = (h && h[0]) ? h : "";
    if (home.empty()) { struct passwd* pw = getpwuid(getuid()); if (pw && pw->pw_dir) home = pw->pw_dir; }
    while (home.size() > 1 && home.back() == '/') home.pop_back();
    if (home == "/") home.clear();
    rdir = home + "/.rabadon";
  }
  string base = rdir;
  while (base.size() > 1 && base.back() == '/') base.pop_back();
  string spool = base + "/spool";

  // --signals is its own arm and it exits before the spool is opened. It reads a
  // different store (the binary move rings) and answers a different question, so
  // combining it with a renderer flag would mean honouring one and dropping the
  // other — the silent-ignore hazard this file already refuses for --projekt.
  // Refused where it is read, so no renderer ever sees a half-honoured request.
  if (signals) {
    const char* clash = json ? "--json" : md ? "--md" : explain ? "--explain" : want_project ? "--project" : nullptr;
    if (clash) {
      fprintf(stderr, "rabadon-stats: --signals cannot be combined with %s — the signal screen reads the"
                      " move rings in %s/sessions, not the spool, and has no %s renderer yet;"
                      " run them separately\n", clash, base.c_str(), clash);
      return 2;
    }
    if (days_given) {
      fprintf(stderr, "rabadon-stats: --signals cannot be combined with --days — the move ring is a"
                      " fixed-size ring per session, not a time window, so a day count would name a"
                      " filter that is not applied. The screen prints the date range it actually read.\n");
      return 2;
    }
    return rbscreen::render(base, full);
  }

  const double cutoff = now_ms() - days * 86400000.0;

  // ---- readEvents ----
  std::vector<string> files;
  if (DIR* d = opendir(spool.c_str())) {
    while (struct dirent* ent = readdir(d)) {
      string n = ent->d_name;
      if (n.size() >= 6 && n.compare(n.size() - 6, 6, ".jsonl") == 0) files.push_back(n);
    }
    closedir(d);
  }
  std::sort(files.begin(), files.end());

  std::vector<Event> events;
  for (const string& f : files) {
    double day = 0;
    if (parse_day_utc(f, day) && day + 86400000.0 < cutoff) continue;
    string body = read_file(spool + "/" + f);
    if (body.empty()) continue;
    size_t pos = 0;
    while (pos <= body.size()) {
      size_t nl = body.find('\n', pos);
      string line = body.substr(pos, (nl == string::npos ? body.size() : nl) - pos);
      pos = (nl == string::npos) ? body.size() + 1 : nl + 1;
      bool blank = true;
      for (char c : line) if (c != ' ' && c != '\t' && c != '\r' && c != '\n' && c != '\f' && c != '\v') { blank = false; break; }
      if (blank) continue;
      JParse p(line);
      JV root = p.root();
      if (!p.ok) continue;
      if (root.t == JV::NUL) continue;
      Event e;
      const JV* ts = (root.t == JV::OBJ) ? root.get("ts") : nullptr;
      if (!ts || ts->t != JV::NUM) continue;
      e.ts = ts->num();
      if (!(e.ts >= cutoff)) continue;
      if (const JV* sq = root.get("seq")) if (sq->t == JV::NUM) e.seq = sq->num();
      e.drill_emit = rb_drill_tag(line);
      if (const JV* pp = root.get("pipe")) if (pp->t == JV::STR) { e.has_pipe = true; e.pipe = u16_to_utf8(json_body_to_u16(pp->s)); }
      if (const JV* ev = root.get("ev")) if (ev->t == JV::STR) e.ev = u16_to_utf8(json_body_to_u16(ev->s));
      if (const JV* rn = root.get("run")) if (rn->t == JV::STR) e.run = u16_to_utf8(json_body_to_u16(rn->s));
      if (const JV* rl = root.get("rule")) if (rl->t == JV::STR) e.rule = u16_to_utf8(json_body_to_u16(rl->s));
      if (e.ev == "STOP" || e.ev == "WOULD_BLOCK") {
        if (const JV* r = root.get("reason")) if (r->t == JV::STR) e.reason = u16_to_utf8(json_body_to_u16(r->s));
        const JV* dt = root.get("detail");
        if (dt && dt->t == JV::STR && !dt->s.empty()) e.detail = json_body_to_u16(dt->s);
        else if (dt && dt->t == JV::NUM && dt->num() != 0) e.detail = json_body_to_u16(dt->s);
        else if (dt && dt->t == JV::BOOL && dt->b) e.detail = u"true";
        else e.detail = u"?";
      }
      if (e.ev == "CHECK_FAIL") {
        const JV* fl = root.get("fails");
        if (fl && fl->t == JV::ARR) {
          e.has_fails_arr = true;
          e.fails_len = (long long)fl->a.size();
          bool first = true;
          for (const JV& fj : fl->a) {
            if (fj.t != JV::OBJ) continue;
            const JV* c = fj.get("check");
            string check = (c && c->t == JV::STR) ? u16_to_utf8(json_body_to_u16(c->s)) : "";
            if (check == "loop-stop") e.loop_stops++;
            if (first) {
              e.fail_check = check;
              const JV* w = fj.get("why");
              if (w && w->t == JV::STR) e.fail_why = json_body_to_u16(w->s);
              first = false;
            }
          }
        }
      }
      if (e.ev == "REPAIR_OK") {
        if (const JV* rk = root.get("repair_kind")) if (rk->t == JV::STR) e.repair_kind = u16_to_utf8(json_body_to_u16(rk->s));
        if (const JV* lk = root.get("locks")) if (lk->t == JV::NUM) e.locks = (long long)lk->num();
      }
      if (const JV* sj = root.get("sess")) if (sj->t == JV::STR) e.sess = u16_to_utf8(json_body_to_u16(sj->s));
      if (e.ev == "COUNTER") { e.has_counter = true; e.counter = root; }
      e.drill = e.drill_emit;
      e.marker_hit = !e.drill_emit && rb_drill_marker(line);
      events.push_back(std::move(e));
    }
  }

  std::stable_sort(events.begin(), events.end(), [](const Event& a, const Event& b) {
    if (a.ts != b.ts) return a.ts < b.ts;
    return a.seq < b.seq;
  });

  // ---- markDrills ---- rules 1-5, from drill.h, the same code rabadon-export
  // runs so the local number and the exported spans cannot disagree. rule 5's
  // facts come off the parsed `ev` here rather than the raw line; the verb names
  // are the ones drill.h matches.
  {
    std::vector<RbDrillEv> dv;
    dv.reserve(events.size());
    for (const Event& e : events) {
      RbDrillEv d;
      d.has_pipe = e.has_pipe; d.pipe = e.pipe; d.ts = e.ts;
      d.tag = e.drill_emit; d.marker = e.marker_hit;
      d.run = e.run;
      d.repair_start = (e.ev == "REPAIR_START");
      d.repair_end = (e.ev == "REPAIR_OK" || e.ev == "REPAIR_FAIL" || e.ev == "REPAIR_FLAKY");
      d.gated = (e.ev == "STEP_START");
      dv.push_back(std::move(d));
    }
    std::vector<char> marked = rb_mark_drills(dv);
    for (size_t i = 0; i < events.size(); i++) events[i].drill = marked[i] != 0;
  }

  // ---- rule id resolution: run -> (check, why) from CHECK_FAILs ----
  std::vector<std::pair<string, std::pair<string, u16string>>> runRule;
  for (const Event& e : events) {
    if (e.drill || e.ev != "CHECK_FAIL" || e.run.empty() || e.fail_check.empty()) continue;
    runRule.push_back({e.run, {e.fail_check, e.fail_why}});
  }
  auto find_run = [&](const string& run) -> const std::pair<string, u16string>* {
    if (run.empty()) return nullptr;
    for (auto& kv : runRule) if (kv.first == run) return &kv.second;
    return nullptr;
  };

  // legacy fallback: detail split at " — " = rule-ish prefix
  auto detail_prefix = [](const u16string& d) -> string {
    u16string rule = d;
    static const char16_t dash[3] = {u' ', u'—', u' '};
    size_t k = rule.find(u16string(dash, 3));
    if (k != u16string::npos) rule = rule.substr(0, k);
    if (rule.size() > 80) rule = rule.substr(0, 80);
    return u16_to_utf8(rule);
  };

  // ---- aggregate ----
  std::vector<Proj> projects;
  long long drills = 0;
  auto proj_for = [&](const string& name) -> Proj& {
    for (Proj& p : projects) if (p.name == name) return p;
    projects.push_back(Proj{}); projects.back().name = name;
    return projects.back();
  };
  std::vector<std::pair<string, rbcount::Counter>> closes;   // newest close per session
  for (const Event& e : events) {
    if (e.drill) { drills++; continue; }
    if (e.has_counter) {
      // one close per session: a session that answered both SessionEnd and Stop
      // wrote the same total twice, and adding it twice is the first way a
      // weekly number inflates without anybody typing a wrong digit.
      rbcount::Counter c;
      counter_from_jv(e.counter, c);
      if (c.sess.empty()) c.sess = e.sess;
      const string key = c.sess.empty() ? e.run : c.sess;
      for (size_t i = 0; i < closes.size(); i++)
        if (closes[i].first == key) { closes.erase(closes.begin() + (long)i); break; }
      closes.push_back({ key, c });
    }
    Proj& s = proj_for(project_of(e.has_pipe, e.pipe));
    if (e.ts > s.lastTs) s.lastTs = e.ts;
    if (e.ev == "STEP_START") s.gated++;
    if (e.ev == "CHECK_FAIL") {
      long long n = (e.has_fails_arr && e.fails_len > 0) ? e.fails_len : 1;
      s.checkFails += n;
      s.loopsStopped += e.loop_stops;
    }
    if (e.ev == "STOP" && e.reason == "BLOCKED") {
      s.blocked++;
      string id = e.rule;
      u16string why = e.detail;
      // the paired CHECK_FAIL carries "<detail> — <rule's why>"; prefer it —
      // the rule's why is the line worth reading under the id
      if (const auto* rr = find_run(e.run)) {
        if (id.empty()) id = rr->first;
        if (!rr->second.empty()) why = rr->second;
      }
      if (id.empty()) id = detail_prefix(e.detail);
      Rule& r = rule_for(s.rules, id);
      if (r.n == 0) r.why = why;
      r.n++;
      r.hits.push_back({e.ts, e.detail});
    }
    if (e.ev == "WOULD_BLOCK") {
      s.wouldBlocked++;
      string id = !e.rule.empty() ? e.rule : (!e.reason.empty() ? e.reason : detail_prefix(e.detail));
      Rule& r = rule_for(s.wouldRules, id);
      if (r.n == 0) r.why = e.detail;
      r.n++;
      r.hits.push_back({e.ts, e.detail});
    }
    // A single "repairs accepted" number counted a green test suite, an
    // installed rule and an unwitnessed fix as if they were the same
    // achievement. They are not, and the one that sells the product is the
    // smallest of them, so it gets counted alone.
    if (e.ev == "REPAIR_OK") {
      if (e.repair_kind == "testrun") s.pushGates++;
      else if (e.repair_kind == "rule") s.rulesWritten++;
      else if (e.locks > 0) s.repairsHeld++;
      else s.repairsUnverified++;
    }
  }
  std::stable_sort(projects.begin(), projects.end(), [](const Proj& a, const Proj& b) { return a.lastTs > b.lastTs; });
  for (Proj& p : projects) {
    std::stable_sort(p.rules.begin(), p.rules.end(), [](const Rule& a, const Rule& b) { return a.n > b.n; });
    std::stable_sort(p.wouldRules.begin(), p.wouldRules.end(), [](const Rule& a, const Rule& b) { return a.n > b.n; });
  }
  if (want_project) {
    std::vector<Proj> kept;
    for (Proj& p : projects) if (p.name == only_project) kept.push_back(std::move(p));
    // A filter that matched nothing is a FAILED QUESTION, not an empty ledger.
    // Dropping every project used to land in the projects.empty() branch below,
    // which prints the onboarding block — "the ledger fills itself: run `claude`
    // inside a project where `rabadon init` has been run" — and returns 0. That
    // told a user who had already run init, already run claude and already had
    // catches on disk that rabadon had recorded nothing. The ledger was not
    // empty; their filter was. `rabadon trace nosuchrun` already exits 1 and
    // names the word it could not find; this is the same failure on the surface
    // the README calls the only sales artifact that matters, so it answers the
    // same way — before any renderer runs, so --md and --json cannot disagree
    // with the terminal. --json's "projects":[] with every total 0 was the worst
    // of the three: a script asking "how many catches for project X this week"
    // could not tell a wrong name from a clean week.
    if (kept.empty()) {
      // nothing was moved out, so the pre-filter vector is still intact and can
      // say what the window DOES hold — the one thing that turns the refusal
      // into a usable answer (usually a typo, sometimes the wrong window).
      string have;
      for (const Proj& p : projects) { if (!have.empty()) have += ", "; have += p.name; }
      if (!have.empty())
        fprintf(stderr, "rabadon-stats: no such project — \"%s\" is not in %s within the last %s day(s);"
                        " the window holds: %s (widen with --days N, or drop --project for all of them)\n",
                only_project.c_str(), spool.c_str(), js_num_str(days).c_str(), have.c_str());
      else
        fprintf(stderr, "rabadon-stats: no such project — \"%s\" is not in %s within the last %s day(s),"
                        " and neither is anything else: this window holds no events at all"
                        " (drop --project to see how to fill it)\n",
                only_project.c_str(), spool.c_str(), js_num_str(days).c_str());
      return 1;
    }
    projects = std::move(kept);
  }

  long long tBlocked = 0, tWould = 0, tGated = 0, tFails = 0;
  long long tHeld = 0, tUnverified = 0, tPushGates = 0, tRules = 0;
  for (const Proj& p : projects) {
    tBlocked += p.blocked; tWould += p.wouldBlocked; tGated += p.gated;
    tFails += p.checkFails;
    tHeld += p.repairsHeld; tUnverified += p.repairsUnverified;
    tPushGates += p.pushGates; tRules += p.rulesWritten;
  }

  rbcount::Counter CTR;
  {
    std::vector<rbcount::Counter> v;
    for (auto& kv : closes) v.push_back(kv.second);
    CTR = aggregate_counter(v);
  }

  // ---- render: --explain ----
  // The counter, re-derived out loud. This is the surface Law 5 promises: every
  // subtotal, the ledger line it came from, and the same number the closing
  // line printed at the bottom of it.
  if (explain) {
    const string out = rbcount::explain(CTR);
    fwrite(out.data(), 1, out.size(), stdout);
    return 0;
  }

  // ---- render: --json ----
  if (json) {
    string out = "{\"days\":" + js_num_str(days) + ",\"spool\":\"" + json_escape(spool) + "\",";
    out += "\"totals\":{\"refused\":" + std::to_string(tBlocked) + ",\"wouldRefuse\":" + std::to_string(tWould)
        + ",\"gated\":" + std::to_string(tGated) + ",\"checkFails\":" + std::to_string(tFails)
        + ",\"repairsHeld\":" + std::to_string(tHeld) + ",\"repairsUnverified\":" + std::to_string(tUnverified)
        + ",\"pushGatesPassed\":" + std::to_string(tPushGates) + ",\"rulesWritten\":" + std::to_string(tRules)
        + ",\"drillsExcluded\":" + std::to_string(drills) + "},";
    out += "\"projects\":[";
    for (size_t i = 0; i < projects.size(); i++) {
      const Proj& p = projects[i];
      if (i) out += ",";
      out += "{\"name\":\"" + json_escape(p.name) + "\",\"gated\":" + std::to_string(p.gated)
          + ",\"refused\":" + std::to_string(p.blocked) + ",\"wouldRefuse\":" + std::to_string(p.wouldBlocked)
          + ",\"checkFails\":" + std::to_string(p.checkFails) + ",\"loopsStopped\":" + std::to_string(p.loopsStopped)
          + ",\"repairsHeld\":" + std::to_string(p.repairsHeld) + ",\"repairsUnverified\":" + std::to_string(p.repairsUnverified)
          + ",\"pushGatesPassed\":" + std::to_string(p.pushGates) + ",\"rulesWritten\":" + std::to_string(p.rulesWritten)
          + ",\"lastTs\":" + js_num_str(p.lastTs) + ",";
      auto rules_json = [&](const std::vector<Rule>& v) {
        string o = "[";
        for (size_t k = 0; k < v.size(); k++) {
          if (k) o += ",";
          o += "{\"rule\":\"" + json_escape(v[k].id) + "\",\"n\":" + std::to_string(v[k].n)
             + ",\"why\":\"" + json_escape(u16_to_utf8(v[k].why)) + "\"}";
        }
        return o + "]";
      };
      out += "\"rules\":" + rules_json(p.rules) + ",\"watchRules\":" + rules_json(p.wouldRules) + "}";
    }
    out += "],\"counter\":" + rbcount::json_object(CTR);
    out += "}\n";
    fwrite(out.data(), 1, out.size(), stdout);
    return 0;
  }

  // ---- render: --md (report) ----
  if (md) {
    string out = "# rabadon usage — last " + js_num_str(days) + " day(s)\n\n";
    out += "**" + commas(tBlocked) + " refused before they happened · " + commas(tGated)
         + " actions gated · " + commas(tHeld) + " repairs held**";
    if (tUnverified) out += " · " + commas(tUnverified) + " repair(s) unverified";
    if (tWould) out += " · " + commas(tWould) + " would-have-refused (watch mode)";
    out += "\n\n";
    if (projects.empty()) out += "_no events in this window._\n\n";
    for (const Proj& p : projects) {
      out += "## " + p.name + "\n\n";
      out += "| metric | value |\n|---|---|\n";
      out += "| actions gated | " + commas(p.gated) + " |\n";
      out += "| caught before happening | " + commas(p.blocked) + " |\n";
      if (p.wouldBlocked) out += "| would have caught (watch) | " + commas(p.wouldBlocked) + " |\n";
      out += "| checks failed (caught) | " + commas(p.checkFails) + " |\n";
      if (p.loopsStopped) out += "| loops stopped | " + commas(p.loopsStopped) + " |\n";
      out += "| repairs held (test files hash-locked) | " + commas(p.repairsHeld) + " |\n";
      out += "| repairs unverified (nothing was locked) | " + commas(p.repairsUnverified) + " |\n";
      if (p.pushGates) out += "| push gates passed (suite ran green) | " + commas(p.pushGates) + " |\n";
      if (p.rulesWritten) out += "| rules written | " + commas(p.rulesWritten) + " |\n";
      out += "\n";
      auto md_rules = [&](const std::vector<Rule>& v, const char* title) {
        if (v.empty()) return;
        out += string("**") + title + "**\n\n";
        for (const Rule& r : v)
          out += "- `" + r.id + "` ×" + std::to_string(r.n) + " — " + u16_to_utf8(r.why) + "\n";
        out += "\n";
      };
      md_rules(p.rules, "refused");
      md_rules(p.wouldRules, "watch verdicts");
    }
    out += "---\n";
    out += "generated from `" + spool + "` · drills and self-tests are tagged at emit and excluded from every number"
           " · reproduce with `rabadon usage --days " + js_num_str(days) + "`\n";
    fwrite(out.data(), 1, out.size(), stdout);
    return 0;
  }

  // ---- render: terminal ----
  const size_t W = term_width();
  string out;
  out += "rabadon usage — last " + js_num_str(days) + " day(s) · local, nothing leaves this machine\n";
  out += fit(json_body_to_u16("source: " + spool), W) + "\n\n";

  if (projects.empty()) {
    out += "  no events in this window.\n\n";
    out += "  the ledger fills itself: run `claude` inside a project where `rabadon init`\n";
    out += "  has been run — every gated action lands here as a timestamped event.\n\n";
    out += "  to watch the gate fire right now, without waiting for a real incident:\n";
    out += "      rabadon drill\n";
    out += "  drill events are tagged at emit and never counted in the numbers here.\n";
    fwrite(out.data(), 1, out.size(), stdout);
    return 0;
  }

  out += "  " + commas(tBlocked) + " refused before they happened · " + commas(tGated)
       + " actions gated · " + commas(tHeld) + " repairs held";
  if (tUnverified) out += " · " + commas(tUnverified) + " unverified";
  if (tWould) out += " · " + commas(tWould) + " would-have-refused (watch)";
  out += "\n\n";

  auto render_rules = [&](const std::vector<Rule>& v) {
    for (const Rule& r : v) {
      char head[32]; snprintf(head, sizeof head, "    %5sx  ", commas(r.n).c_str());
      out += head + r.id + "\n";
      const string pad = "            ";
      if (!r.why.empty() && r.why != u"?")
        out += pad + fit(r.why, W > pad.size() ? W - pad.size() : 40) + "\n";
      if (full) {
        for (const Catch& c : r.hits)
          out += pad + "· " + local_stamp(c.ts) + "  " + u16_to_utf8(c.detail) + "\n";
      }
    }
  };

  for (const Proj& s : projects) {
    string head = "  " + s.name;
    string when = s.lastTs > 0 ? ("last event: " + local_stamp(s.lastTs)) : "";
    if (!when.empty() && head.size() + when.size() + 2 < W)
      head += string(W - head.size() - when.size(), ' ') + when;
    out += head + "\n";
    out += "    actions gated:            " + commas(s.gated) + "\n";
    out += "    caught before happening:  " + commas(s.blocked) + "\n";
    render_rules(s.rules);
    if (s.wouldBlocked) {
      out += "    would have caught (watch): " + commas(s.wouldBlocked) + "\n";
      render_rules(s.wouldRules);
    }
    out += "    checks failed (caught):   " + commas(s.checkFails);
    if (s.loopsStopped > 0) out += "  (loops stopped: " + commas(s.loopsStopped) + ")";
    out += "\n";
    out += "    repairs held (locked):    " + commas(s.repairsHeld) + "\n";
    out += "    repairs unverified:       " + commas(s.repairsUnverified) + "\n";
    if (s.pushGates) out += "    push gates passed:        " + commas(s.pushGates) + "\n";
    if (s.rulesWritten) out += "    rules written:            " + commas(s.rulesWritten) + "\n";
    out += "\n";
  }
  if (drills > 0) out += "  (" + commas(drills) + " event(s) from rabadon's own drills/demos/self-tests — excluded from every number above)\n";
  fwrite(out.data(), 1, out.size(), stdout);
  return 0;
}
