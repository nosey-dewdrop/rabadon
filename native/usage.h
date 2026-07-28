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
// nested "iterations"/"cache_creation" copies that follow are ignored. Proven
// byte-exact against a real 571M-token transcript (31 tool-result lines, 0
// delta vs a canonical message.usage sum).
#ifndef RABADON_USAGE_H
#define RABADON_USAGE_H

#include <string>
#include <cstring>
#include <cstdlib>

struct Usage {
  long long in = 0, out = 0, cacheCreate = 0, cacheRead = 0;
  long long tokens() const { return in + out + cacheCreate + cacheRead; }
};

static void add_field(const std::string& line, std::size_t from, const char* key, long long& acc) {
  std::size_t p = line.find(key, from);
  if (p != std::string::npos) acc += atoll(line.c_str() + p + strlen(key));
}

static Usage sum_usage(const std::string& win) {
  Usage u;
  std::size_t ls = 0;
  while (ls < win.size()) {
    std::size_t le = win.find('\n', ls);
    if (le == std::string::npos) le = win.size();
    const std::string line = win.substr(ls, le - ls);
    // count ONLY genuine assistant API responses. The billable usage lives on
    // "type":"assistant" lines; a "type":"user" line can embed a subagent's
    // result (toolUseResult) whose nested usage is billed to the SUBAGENT's own
    // transcript, not this session — summing it double-counts.
    std::size_t up = line.find("\"usage\":");
    if (up != std::string::npos &&
        line.find("\"type\":\"assistant\"") != std::string::npos &&
        line.find("\"toolUseResult\"") == std::string::npos) {
      add_field(line, up, "\"input_tokens\":", u.in);
      add_field(line, up, "\"output_tokens\":", u.out);
      add_field(line, up, "\"cache_creation_input_tokens\":", u.cacheCreate);
      add_field(line, up, "\"cache_read_input_tokens\":", u.cacheRead);
    }
    ls = le + 1;
  }
  return u;
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
  const std::string pat = "\"model\":\"";
  std::size_t p = text.rfind(pat);
  if (p == std::string::npos) return "";
  std::size_t s = p + pat.size();
  std::size_t e = text.find('"', s);
  return e == std::string::npos ? "" : text.substr(s, e - s);
}

#endif // RABADON_USAGE_H
