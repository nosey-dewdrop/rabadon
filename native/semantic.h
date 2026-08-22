// semantic.h — tier 1: the shape of an edit, not its spelling. (C++17)
//
// WHY THIS FILE EXISTS
// Tier 0 (native/moves.h: sig_edit) is exact-after-spelling. It relativises,
// masks scratch paths, squeezes runs of whitespace to one space, and hashes.
// That is a deliberate promise — tier 0 never claims a match it did not
// literally see — and it is also a hole with a known shape: `x = a + b` and
// `x = a+b` squeeze to different strings, so they hash to different 16-hex
// signatures, so the `repeat` detector in native/signals.h walks past them.
// Rename the identifiers and every byte differs; no amount of normalisation
// inside tier 0 can ever close that, because tier 0's promise is literalness.
//
// Tier 1 closes it with the MOSS technique (Schleimer/Wilkerson/Aiken, SIGMOD
// 2003): tokenise, rename identifiers to their first-occurrence position, hash
// every k-gram of the token sequence, and winnow — keep the minimum hash of
// every window of w consecutive k-grams. Two texts that share a run of at least
// k+w-1 tokens are guaranteed to share a selected fingerprint. Pure C++,
// microseconds, no dependency, thirty years old.
//
// THE CASCADE. Tier 0 answers first. detect() below refuses to run at all when
// tier 0's hash already matched something in the window: if the hashes are
// equal the work is done and a shape opinion adds nothing. Tier 1 may only ADD
// a signal to the ledger. It never changes a tier-0 verdict, never moves an
// exit code, never prints. reports/R3/accept.sh claim 2 holds that from
// outside.
//
// THE PARAMETERS, AND THE ARGUMENT FOR EACH
//   K = 5          k-grams of 5 tokens. `return x ; }` is 4 tokens and appears
//                  in half of every JavaScript file ever written; at k=5 the
//                  shortest thing that can match is long enough to mean
//                  something. Measured on reports/R3/accept.sh's own honest-work
//                  fixtures, k=4 raised 1c-ii from 0.43 to 0.50 and left the
//                  true positives at 1.0 — smaller k buys nothing and costs
//                  margin.
//   WIN = 4        the winnowing window. Guarantee threshold t = k+w-1 = 8
//                  tokens: any shared run of 8 tokens is certain to be seen,
//                  anything shorter may be missed. Density is 2/(w+1) = 40% of
//                  k-grams kept, which is small enough to be cheap and dense
//                  enough that a 19-token edit still gets several fingerprints.
//   THRESHOLD 0.80 Jaccard over the selected sets. LAW 1: THE EXPENSIVE FAILURE
//                  IS THE FALSE POSITIVE, NOT THE MISS. Measured against the
//                  nearest honest neighbours the acceptance script names:
//                    a real one-operator bugfix    0.43   (accept 1c-ii)
//                    three files of shared boilerplate up to 0.21 (1c-iii)
//                    three unrelated functions     0.00   (1c-i)
//                    the true positives            1.00   (1a, 1b)
//                  0.80 sits in the empty band between 0.43 and 1.00 with the
//                  margin spent on the honest side on purpose. It means tier 1
//                  currently catches only rewrites whose TOKEN SHAPE is
//                  identical — reformatting and renaming, which is exactly the
//                  hole tier 0 leaves — and MISSES a rewrite that also moves a
//                  line or two. That miss is chosen. If a later round wants to
//                  loosen it, it has to argue with 1c-ii at 0.43, not with a
//                  number that felt right.
//   MIN_HITS = 3   the same rule tier 0 uses: a second attempt is debugging, so
//                  fire on the third. Tier 1 is not allowed to be LOOSER than
//                  tier 0, and a semantic detector that fired on the second
//                  attempt would flag ordinary debugging — the exact failure
//                  that got the SWE-agent-era loop detectors ripped out.
//   same path      only edits to ONE file are compared, for oscillation's
//                  reason: two files that look alike are a house style, not a
//                  repeated attempt. This is also what keeps R2's scope_drift
//                  fixture (six directories, one near-identical line in each)
//                  from reading as a semantic repeat.
//
// CONFIDENCE IS FRACTIONAL AND CAPPED AT HALF. A shape match is weaker evidence
// than a hash match: tier 0's `repeat` carries 0.6, so a full-overlap shape
// match carries 0.5 and nothing here can ever reach 1.0. R4's promotion ladder
// needs the ledger to be able to sort tiers apart, and this is that sort key.
//
// NO TIER 2. No AST, no tree-sitter, no dependency. Out of scope this round.
#pragma once

#include <string>
#include <vector>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <unordered_map>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include "moves.h"

namespace rbsem {

using std::string;
using std::vector;

static const int    K         = 5;
static const int    WIN       = 4;
static const double THRESHOLD = 0.80;
static const int    MIN_HITS  = 3;
static const int    WINDOW    = 20;      // rbsig::REPEAT_WINDOW, same reason
static const size_t MIN_TOKENS = (size_t)(K + WIN - 1);   // the MOSS guarantee t
// The bottom-k sketch cap. A 4 000-token file selects ~1 600 fingerprints and
// storing them all would make the sidecar record bigger than the move record it
// annotates. Keeping the SMALLEST 64 hashes is not a truncation, it is a
// consistent sample: the same 64 slots of hash space are kept in every
// document, so the Jaccard estimate over two sketches is still an estimate of
// the Jaccard of the full sets.
static const size_t FP_MAX = 64;
// Tokenising is linear, but "linear" over a 4 MB generated file inside a
// PreToolUse hook is not free. Text past this point is not read. The cost of
// that choice is a miss on giant files, which is the direction Law 1 picks.
static const size_t MAX_CHARS = 65536;

// the kill switch. RABADON_SEM=0 disables tier 1 entirely — no fingerprint is
// computed, none is stored, none is compared.
inline bool enabled() {
  const char* v = getenv("RABADON_SEM");
  return !(v && v[0] == '0' && v[1] == '\0');
}

inline bool word_start(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$';
}
inline bool word_char(char c) {
  return word_start(c) || (c >= '0' && c <= '9');
}

// FNV-1a. Not a cryptographic choice — these hashes never leave the process's
// own session file and collisions cost a similarity point, not a claim.
inline uint64_t fnv(const void* p, size_t n, uint64_t h = 1469598103934665603ULL) {
  const unsigned char* b = (const unsigned char*)p;
  for (size_t i = 0; i < n; i++) { h ^= b[i]; h *= 1099511628211ULL; }
  return h;
}

// ---------------------------------------------------------------------------
// TOKENS. Three kinds, tagged in the top two bits so a word can never collide
// with a punctuation mark:
//   word    -> its FIRST-OCCURRENCE POSITION in this text, not its spelling.
//              This is the whole trick: `foo(x)` and `bar(y)` become the same
//              sequence, and a rewrite under new names stops being invisible.
//   number  -> kept literally, for moves.h's reason: `--port 3000` and
//              `--port 8080` are different work, and collapsing digits would
//              erase the difference that was the point of writing both.
//   punct   -> the character itself. Whitespace is dropped entirely, which is
//              what makes `a + b` and `a+b` one shape.
inline void tokenise(const string& in, vector<uint64_t>& out) {
  const size_t n = in.size() < MAX_CHARS ? in.size() : MAX_CHARS;
  std::unordered_map<string, uint64_t> seen;
  out.clear();
  out.reserve(n / 3 + 8);
  size_t i = 0;
  while (i < n) {
    const char c = in[i];
    if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { i++; continue; }
    if (word_start(c)) {
      size_t j = i;
      while (j < n && word_char(in[j])) j++;
      const string w = in.substr(i, j - i);
      i = j;
      auto it = seen.find(w);
      uint64_t idx;
      if (it == seen.end()) { idx = (uint64_t)seen.size(); seen.emplace(w, idx); }
      else idx = it->second;
      out.push_back((1ULL << 62) | idx);
      continue;
    }
    if (c >= '0' && c <= '9') {
      size_t j = i;
      while (j < n && ((in[j] >= '0' && in[j] <= '9') || in[j] == '.')) j++;
      out.push_back((2ULL << 62) | (fnv(in.data() + i, j - i) & ((1ULL << 62) - 1)));
      i = j;
      continue;
    }
    out.push_back((3ULL << 62) | (uint64_t)(unsigned char)c);
    i++;
  }
}

// ---------------------------------------------------------------------------
// WINNOWING. Every k-gram is hashed; the minimum of each window of WIN
// consecutive k-gram hashes is selected. Ties take the rightmost, which is the
// paper's rule and the reason the same run of text selects the same fingerprint
// wherever it appears.
//
// Returned sorted and unique, so similarity() is a linear merge and storage is
// a memcpy.
inline vector<uint64_t> fingerprint(const string& text) {
  vector<uint64_t> tok, fp;
  tokenise(text, tok);
  if (tok.size() < MIN_TOKENS) return fp;      // shorter than the guarantee: no opinion

  const size_t ng = tok.size() - (size_t)K + 1;
  vector<uint64_t> gram(ng);
  for (size_t i = 0; i < ng; i++)
    gram[i] = fnv(&tok[i], (size_t)K * sizeof(uint64_t));

  if (ng < (size_t)WIN) {
    fp.push_back(*std::min_element(gram.begin(), gram.end()));
  } else {
    size_t prev = (size_t)-1;
    for (size_t s = 0; s + (size_t)WIN <= ng; s++) {
      size_t mi = s;
      for (size_t j = s + 1; j < s + (size_t)WIN; j++)
        if (gram[j] <= gram[mi]) mi = j;        // <= : rightmost minimum
      if (mi != prev) { fp.push_back(gram[mi]); prev = mi; }
    }
  }
  std::sort(fp.begin(), fp.end());
  fp.erase(std::unique(fp.begin(), fp.end()), fp.end());
  if (fp.size() > FP_MAX) fp.resize(FP_MAX);    // bottom-k sketch; see FP_MAX
  return fp;
}

// Jaccard, |A n B| / |A u B|, over two sorted unique vectors. Jaccard rather
// than containment-in-the-smaller on purpose: containment calls a short edit
// that happens to sit inside a long one a full match, and "I pasted the header
// again" would read as a repeated attempt.
inline double similarity(const vector<uint64_t>& a, const vector<uint64_t>& b) {
  if (a.empty() || b.empty()) return 0.0;
  size_t i = 0, j = 0, inter = 0;
  while (i < a.size() && j < b.size()) {
    if (a[i] == b[j]) { inter++; i++; j++; }
    else if (a[i] < b[j]) i++;
    else j++;
  }
  const size_t uni = a.size() + b.size() - inter;
  return uni ? (double)inter / (double)uni : 0.0;
}

// ---------------------------------------------------------------------------
// STORAGE. A fingerprint belongs to a move, and moves outlive the process that
// recorded them, so it has to be on disk. It does NOT go into rbmoves::Rec: the
// move record is a fixed 320 bytes whose layout the chain hashes and
// native/moves_test.sh pins, and widening it to carry 512 bytes of hashes would
// change the record for every reader in the repo to serve one detector.
//
// So: a sidecar ring beside the move ring, addressed the same way the moves are
// — slot = seq % CAP — and each slot stamped with its own seq. A stale slot is
// one whose seq does not match what was asked for, which needs no header, no
// count and no atomicity argument: the seq IS the validity check.
//
// Reads are LAZY and by slot. Tier 1 asks for at most the same-path edits
// inside a 20-move window, so a session with 200 moves does not pay for 200
// fingerprints — hot-path cost still does not depend on session length, which
// is the invariant R1.3 exists to protect.
#pragma pack(push, 1)
struct FpRec {
  long long seq;                 // 8   the validity stamp
  int       n;                   // 4   how many of h[] are live
  int       _pad;                // 4
  uint64_t  h[FP_MAX];           // 512 -> 528
};
#pragma pack(pop)

inline void store(const string& path, long long seq, const vector<uint64_t>& fp) {
  if (fp.empty()) return;
  const int fd = open(path.c_str(), O_WRONLY | O_CREAT, 0644);
  if (fd < 0) return;            // fail open: never block on a diagnostic
  FpRec r{};
  r.seq = seq;
  r.n = (int)(fp.size() < FP_MAX ? fp.size() : FP_MAX);
  memcpy(r.h, fp.data(), (size_t)r.n * sizeof(uint64_t));
  const long long slot = seq % (long long)rbmoves::CAP;
  (void)!pwrite(fd, &r, sizeof r, slot * (long long)sizeof r);
  close(fd);                     // no fsync, for docs/butce.md's reason
}

inline bool load(const string& path, long long seq, vector<uint64_t>& out) {
  out.clear();
  const int fd = open(path.c_str(), O_RDONLY);
  if (fd < 0) return false;
  FpRec r{};
  const long long slot = seq % (long long)rbmoves::CAP;
  const bool ok = pread(fd, &r, sizeof r, slot * (long long)sizeof r) == (ssize_t)sizeof r
                  && r.seq == seq && r.n > 0 && (size_t)r.n <= FP_MAX;
  close(fd);
  if (!ok) return false;
  out.assign(r.h, r.h + r.n);
  return true;
}

// A tiny cache so one detect() pass does not pread the same slot twice.
struct Loader {
  string path;
  std::unordered_map<long long, vector<uint64_t>> mem;
  explicit Loader(string p) : path(std::move(p)) {}
  const vector<uint64_t>* get(long long seq) {
    auto it = mem.find(seq);
    if (it == mem.end()) {
      vector<uint64_t> v;
      load(path, seq, v);
      it = mem.emplace(seq, std::move(v)).first;
    }
    return it->second.empty() ? nullptr : &it->second;
  }
};

// ---------------------------------------------------------------------------
// THE DETECTOR. Same contract as rbsig::detect: evaluated after the newest move
// is recorded, asked only "did the newest move complete this pattern", returns
// a description and does nothing else.
//
// Deliberately returns rbsig::Hit's shape without including signals.h — the
// caller assembles the ledger line. Kept as its own struct so this header has
// no dependency on the detector set it adds to.
struct SemHit {
  string name;
  double conf = 0.0;
  vector<long long> seqs;
  string why;
};

inline bool is_edit(const rbmoves::Move& m) {
  return m.tool == "Edit" || m.tool == "Write" || m.tool == "MultiEdit";
}

inline vector<SemHit> detect(const vector<rbmoves::Move>& m, Loader& fps) {
  vector<SemHit> out;
  if (m.size() < (size_t)MIN_HITS) return out;
  const rbmoves::Move& last = m.back();
  if (!is_edit(last) || last.path.empty()) return out;

  const size_t n = m.size();
  const size_t from = n > (size_t)WINDOW ? n - (size_t)WINDOW : 0;

  // ---- THE CASCADE, and it is a `return`, not a flag -----------------------
  // If tier 0's hash already matched anything in this window, tier 0 has
  // spoken: the moves are literally the same text and `repeat` in signals.h is
  // the detector that owns that fact. Tier 1 is never consulted, so it can
  // neither confirm, weaken, duplicate nor contradict a tier-0 verdict.
  for (size_t i = from; i + 1 < n; i++)
    if (m[i].sig == last.sig) return out;

  const vector<uint64_t>* a = fps.get(last.seq);
  if (!a) return out;

  vector<long long> seqs;
  double sum = 0.0;
  double worst = 1.0;
  for (size_t i = from; i + 1 < n; i++) {
    if (!is_edit(m[i]) || m[i].path != last.path) continue;
    const vector<uint64_t>* b = fps.get(m[i].seq);
    if (!b) continue;
    const double s = similarity(*a, *b);
    if (s < THRESHOLD) continue;
    seqs.push_back(m[i].seq);
    sum += s;
    if (s < worst) worst = s;
  }

  // seqs.size() + 1 counts the newest move itself: three occurrences, exactly
  // tier 0's rule.
  if ((int)seqs.size() + 1 < MIN_HITS) return out;

  const double mean = sum / (double)seqs.size();
  seqs.push_back(last.seq);
  // capped at half of tier 0's 0.6 ceiling: a shape is weaker evidence than a
  // hash, and the ledger has to be able to say which one it saw.
  const double conf = 0.5 * mean;

  char buf[64];
  snprintf(buf, sizeof buf, "%.2f", worst);
  out.push_back({ "semantic_repeat", conf, seqs,
                  "the same shape written " + std::to_string(seqs.size()) +
                  " ways (tier 1, token overlap >= " + buf + ")" });
  return out;
}

} // namespace rbsem
