// moves.h — the move record. What this session actually did, in order. (C++17)
//
// WHY THIS FILE EXISTS
// The gate can already answer "is this one command dangerous". It cannot answer
// "has this session done this four times already", "did the suite go red after
// that edit and not this one", or "is the same error coming back through
// different-looking commands". Those are questions about a SEQUENCE, and until
// this file there was nowhere a sequence was written down. The agent cannot
// answer them either: its own context is exactly what it has already forgotten.
//
// So R1 records, and only records. No signal is computed here. Nothing here can
// change an exit code — see the assertion at the bottom of native/moves_test.sh
// that runs the same commands with recording on and off and compares verdicts.
// The order is deliberate: a detector cannot be validated against a record that
// does not exist, and when a false positive shows up later, the only way to find
// out where it came from is to have the moves that produced it.
//
// TIER 0 NORMALISATION, AND WHY IT IS THIS SHAPE
// Two moves are "the same move" if the agent meant the same thing. The cheap
// version of that judgement — the only one R1 makes — is a normalised string,
// hashed. What gets normalised away is spelling. What survives is meaning:
//
//   whitespace      collapsed. `npm  run   build` is `npm run build`.
//   scratch paths   masked. /tmp/rbxyz123/app.py and /tmp/rbabc999/app.py are
//                   the same file to a retry loop, and if the random middle
//                   survives, the SECOND attempt looks brand new and repetition
//                   becomes structurally invisible.
//   numbers         KEPT. `--port 3000` and `--port 8080` are different
//                   commands. Masking digits is the obvious next step and it is
//                   wrong: it would collapse the two commands whose difference
//                   is the entire point of running them both.
//
// Tier 1 (token-sequence / winnowing, so a reformatted retry still matches) is
// R3's job and is deliberately not here. Tier 0 is exact-after-spelling, and
// where it fails it fails by missing a match, never by inventing one.
//
// ERR_SIG: BUCKET THE ERROR, NOT THE RUN
// The same crash reached through two different temp dirs, at two different line
// numbers, is one error. Paths and line numbers are stripped before hashing for
// the same reason crash reporters have done it for twenty years: without it,
// every occurrence is unique and "this keeps happening" cannot be seen.
//
// CLAIMED_RC IS A CLAIM
// PostToolUse hands over a tool_response string. There is no exit code in it.
// Whatever we infer from that text is the session's account of its own work, and
// the field is named so that nobody downstream forgets it.
#pragma once

#include <string>
#include <vector>
#include <sstream>
#include <cstdlib>
#include <cstring>
#include "sha256.h"

namespace rbmoves {

using std::string;

// 200 moves is roughly a long session's worth of context and about 60 KB of
// JSON with raw text on the newest 50. Both numbers are asserted by
// native/moves_test.sh; changing one here without changing it there is caught.
static const size_t CAP = 200;
static const size_t RAW_KEEP = 50;
static const size_t RAW_CLIP = 200;   // characters of raw text kept per move

struct Move {
  long long seq = 0;          // never resets; the only ordering left after eviction
  long long ts = 0;
  string tool;                // Bash | Edit | Write | MultiEdit
  string path;                // relative to the project root; may be empty
  string sig;                 // normalised signature, first 16 hex of sha256
  string raw;                 // clipped; carried only for the newest RAW_KEEP
  int claimed_rc = -1;        // -1 unknown. A CLAIM, not an exit status.
  string err_sig;             // empty = no error seen
  int suite = -1;             // -1 unknown, 0 red, 1 green
};

// ---------------------------------------------------------------------------
// recording is on unless the user turns it off. One switch, read once.
inline bool enabled() {
  const char* v = getenv("RABADON_MOVES");
  return !(v && v[0] == '0' && v[1] == '\0');
}

inline bool is_ws(char c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }
inline bool is_dig(char c) { return c >= '0' && c <= '9'; }

// A run of [A-Za-z0-9_.-] that looks like a scratch name: it has both letters
// and digits and is long enough not to be a word. `abc123`, `rbmoves.XXXXXX`'s
// expansion, `T2f8Kq` all qualify; `build`, `src`, `app.py`, `v2` do not.
inline bool looks_random(const string& s) {
  if (s.size() < 5) return false;
  bool digit = false, alpha = false;
  for (char c : s) {
    if (is_dig(c)) digit = true;
    else if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) alpha = true;
    else if (c != '_' && c != '-') return false;
  }
  return digit && alpha;
}

// Replace the volatile component of a scratch path with <tmp>. Only inside a
// path that is already rooted at a temp directory: a random-looking word in an
// ordinary argument is somebody's identifier and is left alone.
inline string mask_scratch(const string& in) {
  static const char* ROOTS[] = { "/tmp/", "/var/folders/", "/private/tmp/", "/private/var/folders/" };
  string out;
  out.reserve(in.size());
  size_t i = 0;
  while (i < in.size()) {
    size_t hit = string::npos, hitlen = 0;
    for (const char* r : ROOTS) {
      const size_t n = strlen(r);
      if (in.compare(i, n, r) == 0) { hit = i; hitlen = n; break; }
    }
    if (hit != i) { out += in[i++]; continue; }
    out += "<tmp>/";
    i += hitlen;
    // consume path components while they look like scratch names
    while (i < in.size()) {
      size_t j = i;
      while (j < in.size() && in[j] != '/' && !is_ws(in[j])) j++;
      const string comp = in.substr(i, j - i);
      if (!looks_random(comp)) break;
      i = j;
      if (i < in.size() && in[i] == '/') i++;
    }
  }
  return out;
}

// whitespace collapsed, leading/trailing dropped.
inline string squeeze(const string& in) {
  string out;
  out.reserve(in.size());
  bool sp = false;
  for (char c : in) {
    if (is_ws(c)) { sp = !out.empty(); continue; }
    if (sp) { out += ' '; sp = false; }
    out += c;
  }
  return out;
}

// The project root is stripped so the same work in a clone matches, and so a
// signature never carries somebody's home directory into a ledger.
inline string relativise(const string& in, const string& root) {
  if (root.empty()) return in;
  string out;
  out.reserve(in.size());
  size_t i = 0;
  while (i < in.size()) {
    if (in.compare(i, root.size(), root) == 0) {
      i += root.size();
      if (i < in.size() && in[i] == '/') i++;
      continue;
    }
    out += in[i++];
  }
  return out;
}

inline string hash16(const string& s) { return rbsha::hex(s).substr(0, 16); }

// ---- the two signature kinds ----------------------------------------------

inline string sig_bash(const string& command, const string& root) {
  return hash16("b\x01" + squeeze(mask_scratch(relativise(command, root))));
}

// An edit is its file plus what was written into it. Indentation is collapsed
// because re-indenting is not a new attempt; the text itself is kept, because
// tier 0's whole promise is that it never claims a match it did not see.
inline string sig_edit(const string& relPath, const string& newText, const string& root) {
  return hash16("e\x01" + relPath + "\x01" + squeeze(mask_scratch(relativise(newText, root))));
}

// ---- err_sig ---------------------------------------------------------------
// Strip what is unique to this run — quoted paths, line numbers, hex addresses,
// and the scratch dirs — then hash what is left of the lines that look like an
// error. Nothing that looks like an error means no signature at all: inventing
// one for clean output would make "the same error came back" fire on success.
inline bool error_line(const string& l) {
  static const char* MARKS[] = {
    "Error", "error:", "ERROR", "Traceback", "Exception", "error TS",
    "FAILED", "failed:", "panic:", "fatal:", "Segmentation fault",
    "AssertionError", "TypeError", "ValueError", "SyntaxError", "NameError",
    "undefined reference", "cannot find", "No such file", "not found"
  };
  for (const char* m : MARKS)
    if (l.find(m) != string::npos) return true;
  return false;
}

inline string err_sig(const string& out, const string& root) {
  string keep;
  size_t i = 0;
  int taken = 0;
  while (i < out.size() && taken < 12) {
    size_t e = out.find('\n', i);
    if (e == string::npos) e = out.size();
    const string line = out.substr(i, e - i);
    i = e + 1;
    if (!error_line(line)) continue;
    // drop the volatile parts of the line
    string s = mask_scratch(relativise(line, root));
    string t;
    t.reserve(s.size());
    for (size_t k = 0; k < s.size(); k++) {
      if (is_dig(s[k])) {                    // any number is a line/offset/addr
        while (k < s.size() && (is_dig(s[k]) || s[k] == 'x')) k++;
        t += '#';
        if (k < s.size()) t += s[k];
        continue;
      }
      t += s[k];
    }
    keep += squeeze(t);
    keep += '\n';
    taken++;
  }
  if (keep.empty()) return string();
  return hash16("x\x01" + keep);
}

// ---------------------------------------------------------------------------
// the ring

inline void push(std::vector<Move>& v, long long& nextSeq, Move m) {
  m.seq = nextSeq++;
  v.push_back(std::move(m));
  if (v.size() > CAP) v.erase(v.begin(), v.begin() + (v.size() - CAP));
  // raw text only on the newest RAW_KEEP; older entries keep everything else.
  if (v.size() > RAW_KEEP)
    for (size_t i = 0; i + RAW_KEEP < v.size(); i++) v[i].raw.clear();
}

inline string clip(const string& s) {
  return s.size() <= RAW_CLIP ? s : s.substr(0, RAW_CLIP);
}

} // namespace rbmoves
