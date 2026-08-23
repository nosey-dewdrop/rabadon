// counter.h — R6. The one line at session close, and the arithmetic behind it.
//
// WHY THIS FILE IS THE PRODUCT
// Three claims are made for rabadon: it catches, it makes the agent fix, and it
// says what that was worth. The first two are visible while you work. The third
// is one sentence printed when the session ends:
//
//     rabadon: 4 hata zinciri kesildi, 3'ü anında düzeltildi, tahmini 6.80 $ kurtarıldı.
//
// That sentence is the entire advertisement, which is exactly why its HONESTY
// is the marketing. Nobody can audit a dollar figure the way they can audit a
// refusal, so the only thing holding it up is that every digit comes off the
// ledger and can be re-derived in front of the person reading it
// (`rabadon usage --explain`). One inflated number and the counter is worth
// less than no counter at all. Law 5.
//
// THE FORMULA, and docs/COUNTER.md carries it verbatim:
//
//     saved_usd = median(uncut_chain_lengths) * chains_cut * avg_call_usd
//                 - inject_usd - repair_usd
//
// Every term is measured, none is a coefficient:
//   chains_cut       INJECT and chain-ending STOP events in THIS session.
//   fixed_instantly  read off the moves that FOLLOWED an injection, never off
//                    the agent's own account of itself — claimed_rc is a claim.
//   median(...)      the measured length distribution of chains that ran to
//                    completion UNCUT, from sessions on this machine. Fewer
//                    than MIN_HISTORY of them and no dollar figure is printed.
//   avg_call_usd     this session's real cost / its assistant calls, from the
//                    agent's own transcript. Four price classes, cache-read
//                    separate: folding it into input inflates a long session
//                    several times over, in our favour.
//   inject_usd       what rabadon's own injected characters cost. They cannot
//                    be told apart inside the transcript, so they are charged
//                    at the UPPER bound: UPPER_CHARS per injection. No
//                    rounding into our own column, ever.
//   repair_usd       the repair arm's tokens, off its own COST ledger lines.
//
// WHEN IT DOES NOT KNOW, IT SAYS SO. No transcript, no resolvable price, not
// enough history, no intervention at all — each has its own sentence and none
// of them contains a dollar figure. A net negative prints the negative: that is
// a session rabadon did not pay for, and saying so out loud is the reason the
// positive number is believable.
#pragma once

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include "prices.h"

namespace rbcount {

using std::string;
using std::vector;

// The three constants reports/R6/accept.sh legislates. They are named here and
// nowhere else, and docs/COUNTER.md quotes these names.
static const long long CHARS_PER_TOKEN = 4;    // the injection budget is characters
static const long long UPPER_CHARS = 400;      // rbinject::MAX_CHARS, the ceiling
static const long long MIN_HISTORY = 3;        // fewer measured chains = no figure

// why a dollar figure is absent, as a machine-readable token plus the sentence
// the human sees
static const char* R_NO_TRANSCRIPT = "no-transcript";
static const char* R_NO_PRICE      = "no-price";
static const char* R_NO_HISTORY    = "no-history";
static const char* R_NO_CHAINS     = "no-chains";

struct Counter {
  string sess;
  long long chains_cut = 0, fixed_instantly = 0, injections = 0;

  bool   has_saved = false;
  double saved_usd = 0, gross_usd = 0;
  string reason;                       // one of R_* above; empty when saved is real

  bool   has_median = false;
  double median_uncut = 0;
  long long median_n = 0;
  vector<double> samples;

  bool   has_avg = false;
  double avg_call_usd = 0, session_usd = 0;
  long long calls = 0;
  long long tok_in = 0, tok_cw = 0, tok_cr = 0, tok_out = 0;

  double inject_usd = 0;
  string inject_bound = "upper";
  double repair_usd = 0;
  long long repair_tok_in = 0, repair_tok_out = 0;

  string model, price_key, price_cache;
  bool   has_rates = false;
  rbprice::Rates rates;

  string spool;                        // the day file the citations point into
  vector<string> refs;                 // one per cut chain, citing its ledger line
};

// ---------------------------------------------------------------------------
// MONEY, PRINTED AT THE PRECISION IT TAKES TO BE TRUE.
// Two decimals is what a price looks like, and two decimals turns a real loss
// of -0.000074 into "-0.00" — a non-zero cost rounded away, in our favour, on
// the one line whose whole job is to not do that. So: two decimals normally,
// and when the value would round to zero without being zero, enough decimals to
// show it plus one more digit of it.
inline string money(double v) {
  char b[64];
  if (v == 0.0) return "0.00";
  int p = 2;
  while (p < 9) {
    snprintf(b, sizeof b, "%.*f", p, v);
    if (strtod(b, nullptr) != 0.0) break;
    p++;
  }
  if (p > 2 && p < 9) p++;             // one significant digit is a rounding, not a number
  snprintf(b, sizeof b, "%.*f", p, v);
  return string(b);
}

inline string num(double v) { char b[48]; snprintf(b, sizeof b, "%.12g", v); return string(b); }

// the human sentence for an absent dollar figure
inline string reason_text(const string& r) {
  if (r == R_NO_TRANSCRIPT) return "oturum kaydı bulunamadı, tahmini tutar hesaplanamadı";
  if (r == R_NO_PRICE)      return "model fiyatı çözülemedi, tahmini tutar hesaplanamadı";
  if (r == R_NO_HISTORY)    return "tahmini tutar için ölçüm birikiyor";
  return "tahmini tutar hesaplanamadı";
}

// ---------------------------------------------------------------------------
// THE LINE. One, at close, and never anywhere else.
inline string line(const Counter& c) {
  if (c.chains_cut <= 0) return "rabadon: bu oturumda müdahale yok.";
  string s = "rabadon: " + std::to_string(c.chains_cut) + " hata zinciri kesildi, " +
             std::to_string(c.fixed_instantly) + "'i anında düzeltildi, ";
  if (!c.has_saved) return s + reason_text(c.reason) + ".";
  if (c.saved_usd > 0) return s + "tahmini " + money(c.saved_usd) + " $ kurtarıldı.";
  // A session rabadon did not pay for. It is printed, at full precision, with
  // the word that says whose side the number is not on.
  return s + "tahmini " + money(c.saved_usd) + " $ — rabadon bu oturumda kendi masrafını çıkarmadı.";
}

// ---------------------------------------------------------------------------
// SHOWING THE WORK. Every subtotal, and the ledger lines it came from.
inline string explain(const Counter& c) {
  std::string o;
  o += "rabadon usage --explain — the counter, re-derived step by step\n";
  o += "formula: saved_usd = median(uncut_chain_lengths) * chains_cut * avg_call_usd"
       " - inject_usd - repair_usd\n";
  if (!c.spool.empty()) o += "ledger:  " + c.spool + "\n";
  o += "\n1. chains cut — a repeat/oscillation/root-migration sequence this session\n"
       "   that ended with an injection (INJECT) or a block (STOP), off the ledger:\n";
  if (c.refs.empty()) o += "   (none)\n";
  for (const string& r : c.refs) o += "   " + r + "\n";
  o += "   chains_cut = " + std::to_string(c.chains_cut) +
       ", fixed_instantly = " + std::to_string(c.fixed_instantly) +
       "  (fixed = within the 3 moves after the INJECT the same err_sig never\n"
       "   returned and, where a suite ran, it was green. The agent SAYING it fixed\n"
       "   the thing is a claim, not evidence.)\n";

  o += "\n2. median length of past chains that ran to completion UNCUT (measured,\n"
       "   never a constant; fewer than " + std::to_string(MIN_HISTORY) + " of them and no figure is printed):\n";
  if (c.samples.empty()) o += "   samples: none\n";
  else {
    o += "   samples (" + std::to_string(c.median_n) + "): ";
    for (size_t i = 0; i < c.samples.size(); i++) o += (i ? ", " : "") + num(c.samples[i]);
    o += "\n";
  }
  if (c.has_median) o += "   median_uncut_chain = " + num(c.median_uncut) + "\n";
  else o += "   median_uncut_chain = (not enough history)\n";

  o += "\n3. this session's own average call cost, from the agent's own transcript\n"
       "   (nothing goes to the network):\n";
  if (!c.model.empty()) o += "   model: " + c.model + "\n";
  if (c.has_rates) {
    o += "   prices: " + string(rbprice::SOURCE) + ", cached at " + c.price_cache +
         (c.price_key.empty() ? "" : " (matched: " + c.price_key + ")") + "\n";
    o += "   $/Mtok: input " + num(c.rates.in) + ", output " + num(c.rates.out) +
         ", cache_write " + num(c.rates.cache_write) +
         ", cache_read " + num(c.rates.cache_read) +
         "   <- four classes; cache_read is NOT input\n";
    // Law 7. rabadon cannot see which plan the session was billed on, and it
    // does not guess: the table it prices from is the API list price, so the
    // figure is theoretical at API list price for anyone on a subscription.
    // Said here, where the derivation is, and not as an unqualified word on the
    // shop-window line.
    o += "   basis:  API list price (api_list). rabadon cannot see the billing plan;\n"
         "           on a subscription this figure is theoretical at list price.\n";
  } else {
    o += "   prices: unresolved for this model — no dollar figure is printed\n";
  }
  if (c.has_avg) {
    o += "   tokens: " + std::to_string(c.tok_in) + " input + " + std::to_string(c.tok_cw) +
         " cache-write + " + std::to_string(c.tok_cr) + " cache-read + " +
         std::to_string(c.tok_out) + " output\n";
    o += "   session " + money(c.session_usd) + " $ / " + std::to_string(c.calls) +
         " assistant call(s) = avg_call_usd " + num(c.avg_call_usd) + " $\n";
  } else {
    o += "   avg_call_usd = (no priced transcript)\n";
  }

  o += "\n4. what rabadon itself spent, charged against the saving:\n";
  o += "   " + std::to_string(c.injections) + " injection(s) x " + std::to_string(UPPER_CHARS) +
       " chars (UPPER bound: the injected text cannot be told apart inside the\n"
       "   transcript, so it is charged at the ceiling) / " + std::to_string(CHARS_PER_TOKEN) +
       " chars per token, priced as input\n";
  o += "   inject_usd = " + num(c.inject_usd) + " $  (bound: " + c.inject_bound + ")\n";
  o += "   repair_usd = " + num(c.repair_usd) + " $";
  if (c.repair_tok_in || c.repair_tok_out)
    o += "  (" + std::to_string(c.repair_tok_in) + " in / " + std::to_string(c.repair_tok_out) +
         " out tokens, from the repair arm's own COST lines)";
  o += "\n";

  o += "\n5. the number:\n";
  if (c.has_saved) {
    o += "   " + num(c.median_uncut) + " x " + std::to_string(c.chains_cut) + " x " +
         num(c.avg_call_usd) + " = " + money(c.gross_usd) + " $ gross\n";
    o += "   " + money(c.gross_usd) + " - " + num(c.inject_usd) + " - " + num(c.repair_usd) +
         " = tahmini " + money(c.saved_usd) + " $ (estimated)\n";
  } else if (c.chains_cut <= 0) {
    o += "   no chain was cut this session, so nothing was saved and no zero is\n"
         "   printed as a saving.\n";
  } else {
    o += "   not printed: " + reason_text(c.reason) + "\n";
  }
  o += "\n" + line(c) + "\n";
  return o;
}

// ---------------------------------------------------------------------------
// THE MACHINE-READABLE CONTRACT. M2's share card is generated from this and
// never typed by hand, so the keys are a contract and the test names them.
inline string json_escape_(const string& s) {
  string out;
  for (unsigned char ch : s) {
    switch (ch) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (ch < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", ch); out += b; }
        else out += (char)ch;
    }
  }
  return out;
}

inline string json_object(const Counter& c) {
  string o = "{";
  o += "\"chains_cut\":" + std::to_string(c.chains_cut);
  o += ",\"fixed_instantly\":" + std::to_string(c.fixed_instantly);
  o += ",\"injections\":" + std::to_string(c.injections);
  o += ",\"saved_usd\":" + (c.has_saved ? num(c.saved_usd) : string("null"));
  o += ",\"reason\":" + (c.has_saved || c.reason.empty()
                          ? string("null") : "\"" + json_escape_(c.reason) + "\"");
  o += ",\"estimated\":" + string(c.has_saved ? "true" : "false");
  o += ",\"median_uncut_chain\":" + (c.has_median ? num(c.median_uncut) : string("null"));
  o += ",\"median_samples\":" + std::to_string(c.median_n);
  o += ",\"avg_call_usd\":" + (c.has_avg ? num(c.avg_call_usd) : string("null"));
  o += ",\"calls\":" + std::to_string(c.calls);
  o += ",\"gross_usd\":" + (c.has_saved ? num(c.gross_usd) : string("null"));
  o += ",\"inject_usd\":" + num(c.inject_usd);
  o += ",\"inject_bound\":\"" + json_escape_(c.inject_bound) + "\"";
  o += ",\"repair_usd\":" + num(c.repair_usd);
  o += ",\"model\":" + (c.model.empty() ? string("null") : "\"" + json_escape_(c.model) + "\"");
  o += ",\"line\":\"" + json_escape_(line(c)) + "\"";
  o += ",\"prices\":{\"source\":\"" + string(rbprice::SOURCE) + "\"";
  o += ",\"cached\":\"" + json_escape_(c.price_cache) + "\"";
  o += ",\"snapshot\":\"" + string(rbprice::SNAPSHOT) + "\"";
  o += ",\"matched\":" + (c.price_key.empty() ? string("null") : "\"" + json_escape_(c.price_key) + "\"");
  o += ",\"unit\":\"usd_per_mtok\",\"basis\":\"api_list\",\"rates\":";
  if (c.has_rates)
    o += "{\"input\":" + num(c.rates.in) + ",\"output\":" + num(c.rates.out) +
         ",\"cache_write\":" + num(c.rates.cache_write) +
         ",\"cache_read\":" + num(c.rates.cache_read) + "}";
  else o += "null";
  o += "}";
  o += ",\"refs\":[";
  for (size_t i = 0; i < c.refs.size(); i++)
    o += (i ? "," : "") + string("\"") + json_escape_(c.refs[i]) + "\"";
  o += "]}";
  return o;
}

// ---------------------------------------------------------------------------
// The COUNTER ledger event. The gate computes at close, where the session's
// moves and the price table are both in hand; `rabadon usage` reads the event
// back, so the surface never recomputes a number the ledger already committed
// to — and the two can never disagree.
inline string event_body(const Counter& c) {
  string o;
  o += "\"chains_cut\":" + std::to_string(c.chains_cut);
  o += ",\"fixed\":" + std::to_string(c.fixed_instantly);
  o += ",\"injections\":" + std::to_string(c.injections);
  o += ",\"saved_usd\":" + (c.has_saved ? num(c.saved_usd) : string("null"));
  o += ",\"gross_usd\":" + num(c.gross_usd);
  o += ",\"reason\":\"" + json_escape_(c.reason) + "\"";
  o += ",\"median_uncut\":" + (c.has_median ? num(c.median_uncut) : string("null"));
  o += ",\"median_n\":" + std::to_string(c.median_n);
  o += ",\"samples\":[";
  for (size_t i = 0; i < c.samples.size(); i++) o += (i ? "," : "") + num(c.samples[i]);
  o += "]";
  o += ",\"avg_call_usd\":" + (c.has_avg ? num(c.avg_call_usd) : string("null"));
  o += ",\"session_usd\":" + num(c.session_usd);
  o += ",\"calls\":" + std::to_string(c.calls);
  o += ",\"tok_in\":" + std::to_string(c.tok_in);
  o += ",\"tok_cw\":" + std::to_string(c.tok_cw);
  o += ",\"tok_cr\":" + std::to_string(c.tok_cr);
  o += ",\"tok_out\":" + std::to_string(c.tok_out);
  o += ",\"inject_usd\":" + num(c.inject_usd);
  o += ",\"inject_bound\":\"" + json_escape_(c.inject_bound) + "\"";
  o += ",\"repair_usd\":" + num(c.repair_usd);
  o += ",\"repair_tok_in\":" + std::to_string(c.repair_tok_in);
  o += ",\"repair_tok_out\":" + std::to_string(c.repair_tok_out);
  o += ",\"model\":\"" + json_escape_(c.model) + "\"";
  o += ",\"price_key\":\"" + json_escape_(c.price_key) + "\"";
  o += ",\"prices_cached\":\"" + json_escape_(c.price_cache) + "\"";
  o += ",\"prices_source\":\"" + string(rbprice::SOURCE) + "\"";
  o += ",\"rates\":" + string(c.has_rates
        ? "{\"input\":" + num(c.rates.in) + ",\"output\":" + num(c.rates.out) +
          ",\"cache_write\":" + num(c.rates.cache_write) +
          ",\"cache_read\":" + num(c.rates.cache_read) + "}"
        : "null");
  o += ",\"spool\":\"" + json_escape_(c.spool) + "\"";
  o += ",\"refs\":[";
  for (size_t i = 0; i < c.refs.size(); i++)
    o += (i ? "," : "") + string("\"") + json_escape_(c.refs[i]) + "\"";
  o += "]";
  o += ",\"line\":\"" + json_escape_(line(c)) + "\"";
  return o;
}

}  // namespace rbcount
