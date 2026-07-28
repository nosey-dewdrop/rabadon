// rabadon-stats — the catch ledger, native (C++17, zero deps).
//
// Port of `rabadon stats` (bin/rabadon.mjs lines 106-127) over the same spool
// the JS reads: core/store.mjs readEvents + markDrills + aggregate, byte-exact
// output parity with the node oracle (proven by native/stats_test.sh, a
// differential harness that runs BOTH against the same spool and diffs).
//
// Semantics ported deliberately, not approximately:
//   - RABADON_DIR = env if non-empty (JS `||`), else HOME/.rabadon; spool under it.
//   - --days: JS Number() semantics; NaN or 0 falls back to 7 (JS `|| 7`).
//   - file fast-path skip by YYYY-MM-DD name (UTC midnight); unparseable names
//     are still read — the per-event ts filter is the real gate.
//   - stable sorts everywhere JS relies on stability (ts/seq event order,
//     equal-n blocked rules, equal-lastTs projects).
//   - .slice(0,80)/.slice(0,60) count UTF-16 CODE UNITS, not bytes — strings
//     are decoded to UTF-16 units before truncation, re-encoded to UTF-8 for
//     output (lone surrogate from a mid-pair cut -> U+FFFD, Node behavior).
//   - drill exclusion = markDrills two-pass: /(fleet|doctor)-\d+/ markers
//     (tested on the raw line — byte-equivalent to JSON.stringify for the
//     compact JSON rabadon itself writes), self pipes, tmp.*, ±2min neighbors.
// Exit code is always 0 (missing spool dir = "(no events yet)", like the JS).

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
#include <sys/stat.h>
#include <unistd.h>

using std::string;
using std::u16string;

// ---------- time ----------
// whole milliseconds, exactly like JS Date.now() (integer ms). Compute in
// integer then widen — the sub-ms remainder is deliberately dropped so the
// --days cutoff matches the oracle to the millisecond.
static double now_ms() {
  struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
  long long ms = (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
  return (double)ms;
}

// ---------- UTF-8 <-> UTF-16 code units (JS string semantics) ----------
static void push_cp(u16string& out, uint32_t cp) {
  if (cp <= 0xFFFF) out.push_back((char16_t)cp);
  else { cp -= 0x10000; out.push_back((char16_t)(0xD800 + (cp >> 10))); out.push_back((char16_t)(0xDC00 + (cp & 0x3FF))); }
}

// decode a raw JSON string body (escape sequences kept verbatim by the lexer)
// into UTF-16 code units — the unit JS .slice() counts in.
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
        case 'u': { // lexer guarantees 4 hex digits follow
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
      cp = 0xFFFD; // lone surrogate: what Node emits to a utf8 stdout
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
  std::vector<std::pair<string, JV>> o; // key = raw body, insertion order
  std::vector<JV> a;
  string s;      // STR: raw body (escapes verbatim); NUM: verbatim token
  bool b = false;
  double num() const { return strtod(s.c_str(), nullptr); }
  // JSON.parse: a duplicated key keeps the LAST occurrence
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
    string out; i++; // opening quote
    while (i < s.size()) {
      unsigned char c = (unsigned char)s[i];
      if (c == '"') { i++; return out; }
      if (c < 0x20) break; // JSON.parse rejects raw control chars in strings
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
        break; // invalid escape
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

// ---------- JS Number() for --days ----------
static double js_number(const char* a, bool& is_nan) {
  is_nan = false;
  string s(a);
  size_t b = s.find_first_not_of(" \t\r\n\f\v");
  if (b == string::npos) return 0.0; // Number('') / whitespace-only = 0
  size_t e = s.find_last_not_of(" \t\r\n\f\v");
  s = s.substr(b, e - b + 1);
  // radix literals — sign NOT allowed in JS for these
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
  // strtod accepts "inf"/"nan"/signed hex — JS Number() does not; reject those
  string low; for (char c : t) low += (char)tolower((unsigned char)c);
  if (low == "inf" || low == "infinity" || low == "nan") { is_nan = true; return 0; }
  if (t.size() > 1 && t[0] == '0' && (t[1] == 'x' || t[1] == 'X')) { is_nan = true; return 0; } // "+0x2"/"-0x2" -> NaN in JS
  char* endp = nullptr;
  double v = strtod(s.c_str(), &endp);
  if (endp && *endp == '\0' && endp != s.c_str()) return v;
  is_nan = true; return 0;
}

// JS Number-to-string for the header (integers plain, else shortest round-trip)
static string js_num_str(double v) {
  if (std::isinf(v)) return v < 0 ? "-Infinity" : "Infinity";
  if (v == std::floor(v) && std::fabs(v) < 1e15) {
    long long i = (long long)v;
    return std::to_string(i == 0 ? 0 : i); // String(-0) === "0"
  }
  char buf[64];
  for (int prec = 1; prec <= 17; prec++) {
    snprintf(buf, sizeof buf, "%.*g", prec, v);
    if (strtod(buf, nullptr) == v) break;
  }
  return string(buf);
}

// ---------- spool event model ----------
struct Event {
  double ts = 0;
  double seq = 0;
  bool drill = false;      // final flag (emit-tagged OR set by markDrills)
  bool drill_emit = false; // drill field truthy on the line itself
  bool has_pipe = false;   // pipe present as a string
  string pipe;             // decoded UTF-8
  string ev;
  string reason;           // STOP only
  bool has_fails_arr = false;
  long long fails_len = 0;
  long long loop_stops = 0;
  u16string detail;        // STOP only; already the String(e.detail || '?') value
  bool marker_hit = false; // raw line matched /(fleet|doctor)-\d+/
};

// /(fleet|doctor)-\d+/ over the raw line (\d = ASCII digits only)
static bool drill_marker(const string& line) {
  static const char* words[2] = {"fleet-", "doctor-"};
  for (const char* w : words) {
    size_t wl = strlen(w), from = 0, k;
    while ((k = line.find(w, from)) != string::npos) {
      if (k + wl < line.size() && line[k + wl] >= '0' && line[k + wl] <= '9') return true;
      from = k + 1;
    }
  }
  return false;
}

// ^(vibecoded-demo|do-test|llm-repair-live|bus-test)(:|$)
static bool self_pipe(const string& p) {
  static const char* names[4] = {"vibecoded-demo", "do-test", "llm-repair-live", "bus-test"};
  for (const char* n : names) {
    size_t nl = strlen(n);
    if (p.size() == nl && p.compare(0, nl, n) == 0) return true;
    if (p.size() > nl && p.compare(0, nl, n) == 0 && p[nl] == ':') return true;
  }
  return p.rfind("tmp.", 0) == 0; // pipe.startsWith('tmp.') shares the same branch
}

// projectOf: String(pipe || '?') with ONE trailing :session/:do stripped
static string project_of(bool has_pipe, const string& pipe) {
  string p = (has_pipe && !pipe.empty()) ? pipe : "?";
  const string a = ":session", b = ":do";
  if (p.size() >= a.size() && p.compare(p.size() - a.size(), a.size(), a) == 0) return p.substr(0, p.size() - a.size());
  if (p.size() >= b.size() && p.compare(p.size() - b.size(), b.size(), b) == 0) return p.substr(0, p.size() - b.size());
  return p;
}

// Date.parse("YYYY-MM-DD") -> UTC midnight ms, or false (Hinnant civil days)
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
  if (stat(p.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return string(); // readFileSync(dir) throws -> continue
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

// ---------- per-project ledger ----------
struct Proj {
  string name;
  long long gated = 0, blocked = 0, checkFails = 0, loopsStopped = 0, repairsOk = 0;
  double lastTs = 0;
  std::vector<std::pair<u16string, long long>> rules; // insertion order = first seen
};

int main(int argc, char** argv) {
  // --days: first "--days" wins; Number(next) with NaN/0 -> 7 (the oracle default)
  double days = 7;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--days") == 0) {
      if (i + 1 < argc) {
        bool nan = false;
        double v = js_number(argv[i + 1], nan);
        days = (nan || v == 0) ? 7 : v;
      }
      break;
    }
  }

  // RABADON_DIR: env if NON-EMPTY (JS `||`), else homedir/.rabadon (HOME, passwd fallback)
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
  while (base.size() > 1 && base.back() == '/') base.pop_back(); // path.join normalization (the common case)
  string spool = base + "/spool";

  const double cutoff = now_ms() - days * 86400000.0;

  // ---- readEvents ----
  std::vector<string> files;
  if (DIR* d = opendir(spool.c_str())) {
    while (struct dirent* ent = readdir(d)) {
      string n = ent->d_name;
      if (n.size() >= 6 && n.compare(n.size() - 6, 6, ".jsonl") == 0) files.push_back(n);
    }
    closedir(d);
  } // missing/unreadable dir is NOT an error: zero files
  std::sort(files.begin(), files.end());

  std::vector<Event> events;
  for (const string& f : files) {
    double day = 0;
    if (parse_day_utc(f, day) && day + 86400000.0 < cutoff) continue; // whole-file fast path
    string body = read_file(spool + "/" + f);
    if (body.empty()) continue;
    size_t pos = 0;
    while (pos <= body.size()) {
      size_t nl = body.find('\n', pos);
      string line = body.substr(pos, (nl == string::npos ? body.size() : nl) - pos);
      pos = (nl == string::npos) ? body.size() + 1 : nl + 1;
      // skip blank / whitespace-only
      bool blank = true;
      for (char c : line) if (c != ' ' && c != '\t' && c != '\r' && c != '\n' && c != '\f' && c != '\v') { blank = false; break; }
      if (blank) continue;
      JParse p(line);
      JV root = p.root();
      if (!p.ok) continue;                    // unparseable: silently tolerated (never printed)
      if (root.t == JV::NUL) continue;        // JSON.parse -> null -> e.ts throws -> caught as unparseable
      Event e;
      const JV* ts = (root.t == JV::OBJ) ? root.get("ts") : nullptr;
      if (!ts || ts->t != JV::NUM) continue;  // missing ts -> excluded (undefined >= cutoff is false)
      e.ts = ts->num();
      if (!(e.ts >= cutoff)) continue;
      if (const JV* sq = root.get("seq")) if (sq->t == JV::NUM) e.seq = sq->num();
      if (const JV* dr = root.get("drill")) {
        e.drill_emit = (dr->t == JV::BOOL && dr->b) || (dr->t == JV::NUM && dr->num() != 0) || (dr->t == JV::STR && !dr->s.empty());
      }
      if (const JV* pp = root.get("pipe")) if (pp->t == JV::STR) { e.has_pipe = true; e.pipe = u16_to_utf8(json_body_to_u16(pp->s)); }
      if (const JV* ev = root.get("ev")) if (ev->t == JV::STR) e.ev = u16_to_utf8(json_body_to_u16(ev->s));
      if (e.ev == "STOP") {
        if (const JV* r = root.get("reason")) if (r->t == JV::STR) e.reason = u16_to_utf8(json_body_to_u16(r->s));
        const JV* dt = root.get("detail");
        if (dt && dt->t == JV::STR && !dt->s.empty()) e.detail = json_body_to_u16(dt->s);
        else if (dt && dt->t == JV::NUM && dt->num() != 0) e.detail = json_body_to_u16(dt->s);
        else if (dt && dt->t == JV::BOOL && dt->b) e.detail = u"true";
        else e.detail = u"?"; // String(e.detail || '?')
      }
      if (e.ev == "CHECK_FAIL") {
        const JV* fl = root.get("fails");
        if (fl && fl->t == JV::ARR) {
          e.has_fails_arr = true;
          e.fails_len = (long long)fl->a.size();
          for (const JV& f : fl->a) {
            if (f.t != JV::OBJ) continue;
            const JV* c = f.get("check");
            if (c && c->t == JV::STR && u16_to_utf8(json_body_to_u16(c->s)) == "loop-stop") e.loop_stops++;
          }
        }
      }
      e.drill = e.drill_emit;
      e.marker_hit = !e.drill_emit && drill_marker(line);
      events.push_back(std::move(e));
    }
  }

  // sort: (ts asc, then seq asc), stable — full ties keep file-then-line order
  std::stable_sort(events.begin(), events.end(), [](const Event& a, const Event& b) {
    if (a.ts != b.ts) return a.ts < b.ts;
    return a.seq < b.seq;
  });

  // ---- markDrills ----
  struct Marker { bool has_pipe; string pipe; double ts; };
  std::vector<Marker> markers;
  for (Event& e : events) {
    if (e.drill) continue; // emit-tagged drills never become markers
    if (e.marker_hit) { e.drill = true; markers.push_back({e.has_pipe, e.pipe, e.ts}); }
  }
  for (Event& e : events) {
    if (e.drill) continue;
    const string p = e.has_pipe ? e.pipe : ""; // String(e.pipe || '')
    if (self_pipe(p)) { e.drill = true; continue; }
    for (const Marker& m : markers) {
      // m.pipe === e.pipe strict: two missing pipes both undefined DO match
      bool same = (m.has_pipe == e.has_pipe) && (!m.has_pipe || m.pipe == e.pipe);
      if (same && std::fabs(e.ts - m.ts) < 120000.0) { e.drill = true; break; }
    }
  }

  // ---- aggregate ----
  std::vector<Proj> projects;
  long long drills = 0;
  auto proj_for = [&](const string& name) -> Proj& {
    for (Proj& p : projects) if (p.name == name) return p;
    projects.push_back(Proj{}); projects.back().name = name;
    return projects.back();
  };
  for (const Event& e : events) {
    if (e.drill) { drills++; continue; }
    Proj& s = proj_for(project_of(e.has_pipe, e.pipe));
    if (e.ts > s.lastTs) s.lastTs = e.ts;
    if (e.ev == "STEP_START") s.gated++;
    if (e.ev == "CHECK_FAIL") {
      long long n = (e.has_fails_arr && e.fails_len > 0) ? e.fails_len : 1; // (e.fails||[]).length || 1
      s.checkFails += n;
      s.loopsStopped += e.loop_stops;
    }
    if (e.ev == "STOP" && e.reason == "BLOCKED") {
      s.blocked++;
      // rule = String(detail||'?').split(' — ')[0].slice(0,80) — em dash, UTF-16 units
      u16string rule = e.detail;
      static const char16_t dash[3] = {u' ', u'—', u' '};
      size_t k = rule.find(u16string(dash, 3));
      if (k != u16string::npos) rule = rule.substr(0, k);
      if (rule.size() > 80) rule = rule.substr(0, 80);
      bool found = false;
      for (auto& kv : s.rules) if (kv.first == rule) { kv.second++; found = true; break; }
      if (!found) s.rules.push_back({rule, 1});
    }
    if (e.ev == "REPAIR_OK") s.repairsOk++;
  }
  // projects by lastTs DESC, ties stable in first-encounter order
  std::stable_sort(projects.begin(), projects.end(), [](const Proj& a, const Proj& b) { return a.lastTs > b.lastTs; });
  for (Proj& p : projects)
    std::stable_sort(p.rules.begin(), p.rules.end(), [](const std::pair<u16string, long long>& a, const std::pair<u16string, long long>& b) { return a.second > b.second; });

  // ---- print (byte-exact template) ----
  string out;
  out += "rabadon stats — last " + js_num_str(days) + " day(s), source: " + spool + "\n\n";
  if (projects.empty()) out += "  (no events yet)\n";
  for (const Proj& s : projects) {
    out += "  " + s.name + "\n";
    out += "    actions gated:            " + std::to_string(s.gated) + "\n";
    out += "    caught before happening:  " + std::to_string(s.blocked) + "\n";
    for (const auto& kv : s.rules) {
      u16string r60 = kv.first.size() > 60 ? kv.first.substr(0, 60) : kv.first;
      out += "      " + std::to_string(kv.second) + "x  " + u16_to_utf8(r60) + "\n";
    }
    out += "    checks failed (caught):   " + std::to_string(s.checkFails);
    if (s.loopsStopped > 0) out += "  (loops stopped: " + std::to_string(s.loopsStopped) + ")";
    out += "\n";
    out += "    repairs accepted:         " + std::to_string(s.repairsOk) + "\n\n";
  }
  if (drills > 0) out += "  (" + std::to_string(drills) + " event(s) from rabadon's own drills/demos/self-tests — excluded from every number above)\n";
  fwrite(out.data(), 1, out.size(), stdout);
  return 0;
}
