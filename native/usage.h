// usage.h — rabadon's single token/cost meter.
//
// Claude Code writes one JSON object per line to a session transcript; each
// assistant turn carries "usage":{input_tokens, cache_creation_input_tokens,
// cache_read_input_tokens, output_tokens}. This header is the ONE place that
// turns that transcript into tokens and dollars, so the budget gate (the cap)
// and the lens (the ledger) can never disagree on what a session cost — one
// meter, two consumers.
//
// The leading quote in each key disambiguates "input_tokens" from the longer
// "..._input_tokens" fields (their preceding char is '_', never '"'), and
// add_field takes the FIRST match after "usage": — the top-level count — so the
// nested "iterations"/"cache_creation" copies that follow are ignored.
//
// A previous version of this comment said the meter was "proven byte-exact
// against a real 571M-token transcript". That claim did not survive 24 Aug
// 2026: the sum was right about which BYTES to add, and wrong about which LINES
// to add them from — see is_assistant_usage_line below. The standing proof is
// now native/usage_order_test.sh, which checks this header against a real
// transcript on the machine with a stock json parser as the oracle, and says
// SKIP rather than passing quietly when there is no real transcript to read.
#ifndef RABADON_USAGE_H
#define RABADON_USAGE_H

#include <string>
#include <cstring>
#include <cstdlib>

struct Usage {
  long long in = 0, out = 0, cacheCreate = 0, cacheRead = 0;
  long long tokens() const { return in + out + cacheCreate + cacheRead; }
};

// WHITESPACE IS ALLOWED BETWEEN A KEY AND ITS VALUE, and a meter that assumed
// otherwise was reading `"type": "assistant"` — a stock json.dumps line, RFC
// 8259 to the letter — as a line with no type at all, and pricing the whole
// session at zero. Claude Code happens to write compact JSON, so the assumption
// survived a year; SPEC §2 promises a stranger's transcript can be read with a
// stock parser, and this is the same promise from the other side. So: find the
// QUOTED key, skip whitespace, require the colon, skip whitespace, and hand
// back where the value starts. The leading quote is what keeps "input_tokens"
// from matching inside "cache_creation_input_tokens" (whose preceding char is
// '_', never '"').
static std::size_t rb_ws(const std::string& s, std::size_t i) {
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) i++;
  return i;
}
static std::size_t value_at(const std::string& line, std::size_t from, const char* key) {
  const std::string pat = std::string("\"") + key + "\"";
  std::size_t p = line.find(pat, from);
  if (p == std::string::npos) return std::string::npos;
  std::size_t i = rb_ws(line, p + pat.size());
  if (i >= line.size() || line[i] != ':') return std::string::npos;
  return rb_ws(line, i + 1);
}

// ...and WHICH "type" is the line's type is not answered by "the first one on
// the line". A real Claude Code transcript puts message{} BEFORE the top-level
// type:
//
//   {"parentUuid":...,"message":{...,"type":"message","role":"assistant",
//    "usage":{...}},"requestId":...,"type":"assistant","uuid":...}
//
// so the first "type" on every real line is "message", the predicate was false
// for all of them, and rabadon priced live sessions at zero. Measured on a real
// 425-line transcript: a stock parser finds 414 billable calls, this meter
// found 1. The suite stayed green because every fixture in the repo wrote the
// top-level type FIRST — the shape `--output-format=stream-json` prints, not
// the shape the transcript on disk has. The fixtures were the mask, so
// native/usage_order_test.sh now holds both shapes and the live file.
//
// The fix cannot be "find "type":"assistant" anywhere on the line" either: this
// repo's own logs quote fixture-shaped lines inside assistant TEXT, as does any
// transcript where an agent discusses a transcript, and that invents billable
// calls that were never made. So the key is read at a nesting DEPTH: one pass,
// string-aware — a brace inside a JSON string is not nesting and a \" does not
// end the string — returning the value position of `key` only where it appears
// as a key at exactly `depth`. Depth 1 is the top-level object; message's own
// keys are depth 2.
static std::size_t value_at_depth(const std::string& s, const char* key, int depth) {
  const std::string pat = std::string("\"") + key + "\"";
  int d = 0;
  bool in_str = false;
  for (std::size_t i = 0; i < s.size(); i++) {
    const char c = s[i];
    if (in_str) {
      if (c == '\\') { i++; continue; }   // escaped: the next byte is data, not syntax
      if (c == '"') in_str = false;
      continue;
    }
    if (c == '"') {
      if (d == depth && s.compare(i, pat.size(), pat) == 0) {
        const std::size_t j = rb_ws(s, i + pat.size());
        if (j < s.size() && s[j] == ':') return rb_ws(s, j + 1);
      }
      in_str = true;
      continue;
    }
    if (c == '{' || c == '[') d++;
    else if (c == '}' || c == ']') d--;
  }
  return std::string::npos;
}

static void add_field(const std::string& line, std::size_t from, const char* key, long long& acc) {
  std::size_t v = value_at(line, from, key);
  if (v != std::string::npos) acc += atoll(line.c_str() + v);
}

// one transcript line that is a genuine, billable assistant API response
static bool is_assistant_usage_line(const std::string& line, std::size_t& usageAt) {
  // count ONLY genuine assistant API responses. The billable usage lives on
  // top-level "type":"assistant" lines; a "type":"user" line can embed a
  // subagent's result (toolUseResult) whose nested usage is billed to the
  // SUBAGENT's own transcript, not this session — summing it double-counts.
  const std::size_t t = value_at_depth(line, "type", 1);
  if (t == std::string::npos || line.compare(t, 11, "\"assistant\"") != 0) return false;
  if (value_at_depth(line, "toolUseResult", 1) != std::string::npos) return false;
  // the usage object hangs off message. The depth-1 fallback is for the
  // stream-json shape and for any writer that hoists it to the top level; both
  // are read, neither is assumed.
  usageAt = value_at_depth(line, "usage", 2);
  if (usageAt == std::string::npos) usageAt = value_at_depth(line, "usage", 1);
  return usageAt != std::string::npos;
}

// tokens, and how many assistant CALLS produced them. R6's counter divides one
// by the other to get this session's real average call cost, and it reads that
// divisor here rather than counting lines of its own — one meter, three
// consumers (budget cap, lens, counter).
static Usage sum_usage_calls(const std::string& win, long long& calls) {
  Usage u;
  calls = 0;
  std::size_t ls = 0;
  while (ls < win.size()) {
    std::size_t le = win.find('\n', ls);
    if (le == std::string::npos) le = win.size();
    const std::string line = win.substr(ls, le - ls);
    std::size_t up = 0;
    if (is_assistant_usage_line(line, up)) {
      calls++;
      add_field(line, up, "input_tokens", u.in);
      add_field(line, up, "output_tokens", u.out);
      add_field(line, up, "cache_creation_input_tokens", u.cacheCreate);
      add_field(line, up, "cache_read_input_tokens", u.cacheRead);
    }
    ls = le + 1;
  }
  return u;
}

static Usage sum_usage(const std::string& win) {
  long long calls = 0;
  return sum_usage_calls(win, calls);
}

// price per Mtok — Damla's rates. cache write = input x1.25, cache read =
// input x0.1. Unknown model -> false; the caller shows "?" for the usd and the
// token counts still hold (the transcript always has tokens, not always a model
// we price).
struct Rate { double in, out; };
static bool model_rate(const std::string& model, Rate& r) {
  if (model.find("opus")   != std::string::npos) { r = {5.0, 25.0};  return true; }
  if (model.find("sonnet") != std::string::npos) { r = {3.0, 15.0};  return true; }
  if (model.find("haiku")  != std::string::npos) { r = {1.0, 5.0};   return true; }
  if (model.find("fable")  != std::string::npos) { r = {10.0, 50.0}; return true; }
  return false;
}
static double usd_cost(const Usage& u, const Rate& r) {
  return ((double)u.in * r.in
        + (double)u.cacheCreate * r.in * 1.25
        + (double)u.cacheRead * r.in * 0.1
        + (double)u.out * r.out) / 1e6;
}
// the most recent model string in the transcript (the session's current model)
static std::string last_model(const std::string& text) {
  const std::string pat = "\"model\"";
  std::size_t p = text.rfind(pat);
  while (p != std::string::npos) {
    std::size_t i = rb_ws(text, p + pat.size());
    if (i < text.size() && text[i] == ':') {
      i = rb_ws(text, i + 1);
      if (i < text.size() && text[i] == '"') {
        std::size_t e = text.find('"', i + 1);
        if (e != std::string::npos) return text.substr(i + 1, e - i - 1);
      }
    }
    if (p == 0) break;
    p = text.rfind(pat, p - 1);
  }
  return "";
}

#endif // RABADON_USAGE_H
