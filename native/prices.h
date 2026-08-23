// prices.h — the price table, offline, four classes, one file. (C++17, zero deps)
//
// WHY THIS IS NOT usage.h's model_rate()
// usage.h prices a session for the BUDGET CAP: two numbers, input and output,
// with cache write and cache read expressed as multipliers of input. That is
// enough to halt a run at a ceiling and it has been enough for a year. It is
// not enough for R6, for one measured reason: in a long agent session most of
// the token volume is CACHE READ, and cache read is a tenth of input. A counter
// that folds cache read into input reports a number several times too large,
// and it reports it in OUR favour. So the counter prices four SEPARATE classes
// and reads them from a table it can name, not from a multiplier baked into a
// function nobody can audit.
//
// WHY A FILE ON DISK AND NOT A CONSTANT
// The counter's whole claim is that its arithmetic can be re-done by the person
// reading it. A price compiled into a binary cannot be checked and cannot be
// corrected. So the snapshot below is MATERIALISED to $RABADON_DIR/prices.json
// the first time anything asks for a price, and from then on that file is what
// is read: the operator can open it, diff it against LiteLLM's own table, and
// edit it if a rate moved. `rabadon usage --json` prints the path.
//
// NOTHING GOES TO THE NETWORK, EVER. This is Law 7 and CLAUDE.md rule 7. The
// table is a SNAPSHOT of the LiteLLM model_prices_and_context_window.json that
// ccusage prices from, taken on the date in the file. It is refreshed by a
// human replacing the file, never by rabadon dialling out — reports/R6's claim
// 6d proves the counter produces the identical line with every proxy poisoned.
//
// AN UNKNOWN MODEL IS UNKNOWN, NOT GUESSED AT ZERO. lookup() returns false and
// the caller prints no dollar figure at all. A price of 0 for a model nobody
// has is a saving of 0 dollars presented as a measurement.
#pragma once

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <sys/stat.h>

namespace rbprice {

using std::string;

// USD per MILLION tokens, the unit LiteLLM's table is trivially converted to
// (its own numbers are per token) and the unit a human reads on the pricing
// page. Four classes, because there are four prices.
struct Rates {
  double in = 0, out = 0, cache_write = 0, cache_read = 0;
};

struct Entry { const char* key; double in, out, cw, cr; };

// The snapshot. Source, and the date it was taken, travel with it into the
// cache file so nobody has to guess how old a number is.
static const char* SOURCE = "litellm";
static const char* ORIGIN =
  "https://raw.githubusercontent.com/BerriAI/litellm/main/"
  "model_prices_and_context_window.json";
static const char* SNAPSHOT = "2026-08-22";

static const Entry MODELS[] = {
  { "claude-opus-4-5-20251101",   5.00, 25.00,  6.25,  0.50 },
  { "claude-opus-4-1-20250805",  15.00, 75.00, 18.75,  1.50 },
  { "claude-opus-4-20250514",    15.00, 75.00, 18.75,  1.50 },
  { "claude-3-opus-20240229",    15.00, 75.00, 18.75,  1.50 },
  { "claude-sonnet-4-5-20250929", 3.00, 15.00,  3.75,  0.30 },
  { "claude-sonnet-4-20250514",   3.00, 15.00,  3.75,  0.30 },
  { "claude-3-7-sonnet-20250219", 3.00, 15.00,  3.75,  0.30 },
  { "claude-3-5-sonnet-20241022", 3.00, 15.00,  3.75,  0.30 },
  { "claude-haiku-4-5-20251001",  1.00,  5.00,  1.25,  0.10 },
  { "claude-3-5-haiku-20241022",  0.80,  4.00,  1.00,  0.08 },
};

// LAST RESORT, AND IT IS A FAMILY, NOT A DEFAULT. A dated model id that is not
// in the snapshot yet still prices at its family's published rate, because a
// new dated build of sonnet has never shipped at a different price than sonnet.
// A name that matches no family at all prices at nothing — see 4b in
// reports/R6/accept.sh, where an unpriceable model must print no dollars.
static const Entry FAMILIES[] = {
  { "opus",   15.00, 75.00, 18.75, 1.50 },
  { "sonnet",  3.00, 15.00,  3.75, 0.30 },
  { "haiku",   1.00,  5.00,  1.25, 0.10 },
};

inline string home() {
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) return rd;
  const char* h = getenv("HOME");
  return string((h && h[0]) ? h : ".") + "/.rabadon";
}

inline string cache_path() { return home() + "/prices.json"; }

inline string num(double v) {
  char b[40];
  snprintf(b, sizeof b, "%.10g", v);
  return string(b);
}

inline string snapshot_json() {
  std::ostringstream o;
  o << "{\n  \"source\": \"" << SOURCE << "\",\n"
    << "  \"origin\": \"" << ORIGIN << "\",\n"
    << "  \"snapshot\": \"" << SNAPSHOT << "\",\n"
    << "  \"unit\": \"usd_per_mtok\",\n"
    << "  \"note\": \"cache_write and cache_read are SEPARATE price classes. "
       "Folding cache_read into input overstates a long session several times over.\",\n"
    << "  \"models\": {\n";
  const size_t nm = sizeof(MODELS) / sizeof(MODELS[0]);
  for (size_t i = 0; i < nm; i++)
    o << "    \"" << MODELS[i].key << "\": {\"input\": " << num(MODELS[i].in)
      << ", \"output\": " << num(MODELS[i].out)
      << ", \"cache_write\": " << num(MODELS[i].cw)
      << ", \"cache_read\": " << num(MODELS[i].cr) << "}"
      << (i + 1 < nm ? "," : "") << "\n";
  o << "  },\n  \"families\": {\n";
  const size_t nf = sizeof(FAMILIES) / sizeof(FAMILIES[0]);
  for (size_t i = 0; i < nf; i++)
    o << "    \"" << FAMILIES[i].key << "\": {\"input\": " << num(FAMILIES[i].in)
      << ", \"output\": " << num(FAMILIES[i].out)
      << ", \"cache_write\": " << num(FAMILIES[i].cw)
      << ", \"cache_read\": " << num(FAMILIES[i].cr) << "}"
      << (i + 1 < nf ? "," : "") << "\n";
  o << "  }\n}\n";
  return o.str();
}

// Materialise the snapshot if it is not on disk yet, and hand back the path.
// Never overwrites: a file the operator has corrected stays corrected.
inline string ensure_cache() {
  const string p = cache_path();
  struct stat st;
  if (stat(p.c_str(), &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0) return p;
  ::mkdir(home().c_str(), 0755);
  std::ofstream f(p, std::ios::trunc);
  if (!f) return p;                       // unwritable home: the path is still named
  f << snapshot_json();
  return p;
}

inline string read_all(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

// one "name": <number> inside the object that starts at `from`
inline bool field_num(const string& body, size_t from, size_t to, const char* key, double& out) {
  const string pat = string("\"") + key + "\"";
  const size_t k = body.find(pat, from);
  if (k == string::npos || k >= to) return false;
  size_t i = body.find(':', k + pat.size());
  if (i == string::npos || i >= to) return false;
  out = strtod(body.c_str() + i + 1, nullptr);
  return true;
}

// the object literal that follows "key" inside `body`, as [start,end)
inline bool object_of(const string& body, const string& key, size_t from, size_t& s, size_t& e) {
  const string pat = "\"" + key + "\"";
  size_t k = body.find(pat, from);
  if (k == string::npos) return false;
  s = body.find('{', k + pat.size());
  if (s == string::npos) return false;
  int depth = 0;
  for (size_t i = s; i < body.size(); i++) {
    if (body[i] == '{') depth++;
    else if (body[i] == '}') { depth--; if (depth == 0) { e = i; return true; } }
  }
  return false;
}

inline bool rates_at(const string& body, const string& section, const string& key, Rates& r) {
  size_t ss = 0, se = 0;
  if (!object_of(body, section, 0, ss, se)) return false;
  size_t os = 0, oe = 0;
  if (!object_of(body, key, ss, os, oe)) return false;
  if (oe > se) return false;                       // that key belongs to a later section
  return field_num(body, os, oe, "input", r.in) &&
         field_num(body, os, oe, "output", r.out) &&
         field_num(body, os, oe, "cache_write", r.cache_write) &&
         field_num(body, os, oe, "cache_read", r.cache_read);
}

// model -> four rates. `matched` says WHICH key answered, because "sonnet"
// answering for an id nobody has priced yet is a different fact from an exact
// hit and the explanation prints both.
inline bool lookup(const string& model, Rates& r, string& matched, string& cache) {
  matched.clear();
  cache = ensure_cache();
  if (model.empty()) return false;
  const string body = read_all(cache);
  if (body.empty()) return false;
  if (rates_at(body, "models", model, r)) { matched = model; return true; }
  // a family word inside the id, longest first so "opus" cannot answer for a
  // name that also carries "sonnet"
  size_t ss = 0, se = 0;
  if (object_of(body, "families", 0, ss, se)) {
    size_t i = ss;
    while (i < se) {
      const size_t q1 = body.find('"', i);
      if (q1 == string::npos || q1 >= se) break;
      const size_t q2 = body.find('"', q1 + 1);
      if (q2 == string::npos || q2 >= se) break;
      const string fam = body.substr(q1 + 1, q2 - q1 - 1);
      size_t os = 0, oe = 0;
      if (!object_of(body, fam, ss, os, oe) || oe > se) break;
      if (!fam.empty() && model.find(fam) != string::npos) {
        if (field_num(body, os, oe, "input", r.in) &&
            field_num(body, os, oe, "output", r.out) &&
            field_num(body, os, oe, "cache_write", r.cache_write) &&
            field_num(body, os, oe, "cache_read", r.cache_read)) {
          matched = fam + " (family)";
          return true;
        }
      }
      i = oe + 1;
    }
  }
  return false;
}

}  // namespace rbprice
