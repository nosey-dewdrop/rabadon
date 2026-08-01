// jsonl.h — read a field out of ONE ledger line as JSON, not as bytes.
// (C++17, zero deps, header-only.)
//
// SPEC.md §2 fixes the ledger contract as "single-line JSON" whose `prev` is
// the SHA-256 of the whole previous line. It fixes no byte layout: no compact
// separators, no key order, no "byte-for-byte what rabadon's printf emits".
// Part II of the SPEC exists precisely so a stranger's agent can write this
// ledger with a stock serializer.
//
// The readers here replace a substring match on the literal bytes `"prev":"`.
// A producer using `json.dumps` (or Go's encoding/json, or JSON.stringify with
// an indent) writes `"prev": "..."` — one space — and the substring match then
// finds nothing, so a mathematically valid chain was reported as
//
//     0 chained · 3 unchained · chain BROKEN · head sidecar present but
//     NOT ONE line carries prev — the chain was stripped out
//     verdict: TAMPER-EVIDENT BREAK
//
// Every line carried prev. That is a tamper-evidence tool accusing an intact
// ledger of having been edited — the single worst answer it can give, and the
// reason this header exists. A verifier whose real predicate is "these bytes
// came out of my own printf" does not verify a chain, it fingerprints an
// emitter.
//
// So: walk the object. Whitespace is allowed anywhere JSON allows it. Only
// DEPTH-1 keys are answers, so a `"prev"` sitting inside a nested value — a
// fails[] entry, a quoted command in `detail` — can never be mistaken for the
// line's own chain link, which the old substring match could not tell apart.
//
// Absent, mistyped and unparseable all read the same as absent (empty / 0).
// That is deliberate: a truncated line is not silently promoted to a chained
// one, it is reported unchained, which is what SPEC §2 requires of a line with
// no usable `prev`.

#pragma once

#include <cstdlib>
#include <string>

namespace rbjson {

using std::string;

inline size_t skip_ws(const string& s, size_t i) {
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) i++;
  return i;
}

inline void utf8_append(string& out, unsigned cp) {
  if (cp < 0x80) { out += (char)cp; }
  else if (cp < 0x800) { out += (char)(0xC0 | (cp >> 6)); out += (char)(0x80 | (cp & 0x3F)); }
  else if (cp < 0x10000) {
    out += (char)(0xE0 | (cp >> 12)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F));
  } else {
    out += (char)(0xF0 | (cp >> 18)); out += (char)(0x80 | ((cp >> 12) & 0x3F));
    out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F));
  }
}

inline bool hex4(const string& s, size_t i, unsigned& v) {
  if (i + 4 > s.size()) return false;
  v = 0;
  for (size_t k = i; k < i + 4; k++) {
    char c = s[k]; unsigned d;
    if (c >= '0' && c <= '9') d = (unsigned)(c - '0');
    else if (c >= 'a' && c <= 'f') d = (unsigned)(c - 'a') + 10;
    else if (c >= 'A' && c <= 'F') d = (unsigned)(c - 'A') + 10;
    else return false;
    v = (v << 4) | d;
  }
  return true;
}

// s[i] must be the opening quote. Returns the index just past the closing
// quote, or npos if the literal never closes. `out`, when given, receives the
// UNESCAPED content.
inline size_t scan_string(const string& s, size_t i, string* out) {
  if (i >= s.size() || s[i] != '"') return string::npos;
  i++;
  while (i < s.size()) {
    char c = s[i];
    if (c == '"') return i + 1;
    if (c != '\\') { if (out) *out += c; i++; continue; }
    if (i + 1 >= s.size()) return string::npos;
    char e = s[i + 1];
    i += 2;
    switch (e) {
      case 'n': if (out) *out += '\n'; break;
      case 't': if (out) *out += '\t'; break;
      case 'r': if (out) *out += '\r'; break;
      case 'b': if (out) *out += '\b'; break;
      case 'f': if (out) *out += '\f'; break;
      case '"': case '\\': case '/': if (out) *out += e; break;
      case 'u': {
        unsigned cp;
        if (!hex4(s, i, cp)) return string::npos;
        i += 4;
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < s.size() && s[i] == '\\' && s[i + 1] == 'u') {
          unsigned lo;
          if (hex4(s, i + 2, lo) && lo >= 0xDC00 && lo <= 0xDFFF) {
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
            i += 6;
          }
        }
        if (out) utf8_append(*out, cp);
        break;
      }
      default: if (out) *out += e; break;
    }
  }
  return string::npos;
}

// Skip exactly one JSON value beginning at i (whitespace already skipped).
// Returns the index just past it, or npos on malformed input.
inline size_t skip_value(const string& s, size_t i) {
  if (i >= s.size()) return string::npos;
  char c = s[i];
  if (c == '"') return scan_string(s, i, nullptr);
  if (c == '{' || c == '[') {
    int depth = 0;
    while (i < s.size()) {
      char d = s[i];
      if (d == '"') { size_t n = scan_string(s, i, nullptr); if (n == string::npos) return string::npos; i = n; continue; }
      if (d == '{' || d == '[') depth++;
      else if (d == '}' || d == ']') { depth--; if (depth == 0) return i + 1; }
      i++;
    }
    return string::npos;
  }
  // number, true, false, null — ends at the first structural character
  size_t j = i;
  while (j < s.size() && s[j] != ',' && s[j] != '}' && s[j] != ']' &&
         s[j] != ' ' && s[j] != '\t' && s[j] != '\r' && s[j] != '\n') j++;
  return j == i ? string::npos : j;
}

// Index of the VALUE of top-level `key`, or npos when the line is not an
// object or does not carry that key at depth 1.
inline size_t find_field(const string& s, const string& key) {
  size_t i = skip_ws(s, 0);
  if (i >= s.size() || s[i] != '{') return string::npos;
  i = skip_ws(s, i + 1);
  if (i < s.size() && s[i] == '}') return string::npos;
  while (i < s.size()) {
    string k;
    size_t n = scan_string(s, i, &k);
    if (n == string::npos) return string::npos;
    i = skip_ws(s, n);
    if (i >= s.size() || s[i] != ':') return string::npos;
    i = skip_ws(s, i + 1);
    if (k == key) return i;
    n = skip_value(s, i);
    if (n == string::npos) return string::npos;
    i = skip_ws(s, n);
    if (i >= s.size() || s[i] == '}') return string::npos;
    if (s[i] != ',') return string::npos;
    i = skip_ws(s, i + 1);
  }
  return string::npos;
}

// Walk the top-level keys in document order, handing each to `fn(key, value,
// is_string)`. A string value arrives UNESCAPED; anything else (number, bool,
// null, object, array) arrives as its raw JSON text, so a reader that does not
// know the field can still carry it somewhere without inventing a type.
//
// This exists because SPEC §2's other MUST is "unknown fields MUST be
// preserved". A reader with a fixed struct can only preserve what it was
// compiled to know about; enumerating the line is the only way a field named
// after next year's verb survives the trip.
template <typename F>
inline void for_each_field(const string& s, F fn) {
  size_t i = skip_ws(s, 0);
  if (i >= s.size() || s[i] != '{') return;
  i = skip_ws(s, i + 1);
  if (i < s.size() && s[i] == '}') return;
  while (i < s.size()) {
    string k;
    size_t n = scan_string(s, i, &k);
    if (n == string::npos) return;
    i = skip_ws(s, n);
    if (i >= s.size() || s[i] != ':') return;
    i = skip_ws(s, i + 1);
    size_t vstart = i;
    n = skip_value(s, i);
    if (n == string::npos) return;
    bool is_string = s[vstart] == '"';
    string v;
    if (is_string) scan_string(s, vstart, &v);
    else v = s.substr(vstart, n - vstart);
    fn(k, v, is_string);
    i = skip_ws(s, n);
    if (i >= s.size() || s[i] == '}') return;
    if (s[i] != ',') return;
    i = skip_ws(s, i + 1);
  }
}

// The top-level string field `key`, unescaped. "" when absent, unparseable, or
// not a string.
inline string get_str(const string& line, const string& key) {
  size_t i = find_field(line, key);
  if (i == string::npos || i >= line.size() || line[i] != '"') return "";
  string out;
  if (scan_string(line, i, &out) == string::npos) return "";
  return out;
}

// True when top-level `key` is present AND holds a non-empty string. This is
// the ledger's definition of "this line is chained".
inline bool has_str(const string& line, const string& key) {
  return !get_str(line, key).empty();
}

// The top-level numeric field `key`. 0 when absent or not a number.
inline double get_num(const string& line, const string& key) {
  size_t i = find_field(line, key);
  if (i == string::npos || i >= line.size()) return 0;
  char c = line[i];
  if (c != '-' && c != '+' && c != '.' && !(c >= '0' && c <= '9')) return 0;
  return strtod(line.c_str() + i, nullptr);
}

}  // namespace rbjson
