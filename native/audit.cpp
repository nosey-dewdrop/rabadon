// rabadon-audit — verify the hash-chained ledger (C++17, zero deps).
//
// The gate writes every spool event with prev = SHA-256 of the previous event
// line in the same day file (sha256.h, one shared implementation), and commits
// the day under the same flock into a `.head` sidecar holding TWO facts: the
// hash of the last chained line, and HOW MANY chained lines the file must have.
//
// THE SIDECAR IS THE AUTHORITY. Everything below is one question asked six
// ways: does the day file still agree with the sidecar written beside it?
//
//   - a line whose prev does not match the hash of the last chained line
//     before it = a BROKEN link, named by file and line number;
//   - a headed file with ZERO chained lines = the prev fields were stripped
//     (the pre-0.4 audit called this "legacy, tolerated" and returned INTACT —
//     that was the hole an attacker walked through: strip every prev, pass);
//   - a headed file with ANY unchained line = that link was cut out;
//   - head hash != last chained line = truncated or rewritten tail;
//   - head count != chained lines = a line was removed and the chain
//     re-stitched around the hole;
//   - chained lines but NO sidecar, or a sidecar whose day file is GONE =
//     someone deleted the half that would have convicted them.
//
//   - --replay renders the verified timeline event by event, chain mark per
//     line — the "what happened" answer with the tamper check inline.
//
// What this does NOT detect, stated plainly: a file with no sidecar and no
// prev on any line is UNVERIFIABLE, not intact — rabadon cannot tell a
// pre-chain legacy file from one an attacker stripped bare. It is reported as
// unverifiable and it never counts as INTACT.
//
// Exit 0 = every file verified against its sidecar. Exit 1 = at least one
// break. Exit 2 = nothing broken, but at least one file cannot be verified.

#include <algorithm>
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
#include "sha256.h"
#include "jsonl.h"
#include "cli_help.h"
#include "moves.h"

using std::string;

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

// A top-level string / number field of one ledger line, read AS JSON (jsonl.h).
//
// These used to match the literal bytes `"key":"`. SPEC §2 fixes the ledger as
// "single-line JSON" and fixes no byte layout, so a producer using a stock
// serializer writes `"prev": "..."` — one space — and the match found nothing.
// This referee then answered `NOT ONE line carries prev — the chain was
// stripped out` / `TAMPER-EVIDENT BREAK` over a chain whose every prev really
// was the SHA-256 of the previous line. An intact ledger accused of being
// edited is the worst verdict a tamper-evidence tool can return, so the reader
// parses the object instead of fingerprinting whoever printed it.
static string get_field(const string& line, const string& key) {
  return rbjson::get_str(line, key);
}

static double get_num(const string& line, const string& key) {
  return rbjson::get_num(line, key);
}

static string local_stamp(double ms) {
  time_t t = (time_t)(ms / 1000.0);
  struct tm tmv; localtime_r(&t, &tmv);
  char buf[24]; strftime(buf, sizeof buf, "%Y-%m-%d %H:%M:%S", &tmv);
  return string(buf);
}

// ---------- the .head sidecar: "<sha256 of last chained line> <chained count>"
// count is absent in sidecars written before v0.4 — such a file is reported
// unverifiable (a deleted line cannot be ruled out), never intact.
struct Head {
  bool present = false;     // the sidecar exists and is not empty
  bool malformed = false;
  string hash;
  long long count = -1;     // -1 = pre-0.4 sidecar, no count committed
};

static bool is_hex64(const string& s) {
  if (s.size() != 64) return false;
  for (char c : s) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  return true;
}

static Head read_head(const string& p) {
  Head h;
  string raw = read_file(p);
  while (!raw.empty() && (raw.back() == '\n' || raw.back() == '\r' ||
                          raw.back() == ' ' || raw.back() == '\t')) raw.pop_back();
  if (raw.empty()) return h;             // absent or emptied = absent
  h.present = true;
  size_t sp = raw.find(' ');
  h.hash = (sp == string::npos) ? raw : raw.substr(0, sp);
  if (!is_hex64(h.hash)) { h.malformed = true; return h; }
  if (sp != string::npos) {
    string c = raw.substr(sp + 1);
    if (!c.empty() && c.find_first_not_of("0123456789") == string::npos)
      h.count = strtoll(c.c_str(), nullptr, 10);
    else h.malformed = true;
  }
  return h;
}

// ---------- --export writes JSON, so it has to write JSON.
//
// This used to be a raw printf of `"raw":"%s"` with the recorded bytes dropped
// in unescaped. A move record holds whatever the agent typed: a command with
// double quotes in it, a Windows path with backslashes, a diff with newlines and
// tabs, a colour escape at 0x1b. Every one of those ends the string early or is
// an illegal control character, and the line stops being JSON. Measured on the
// frozen corpus at commit 49fd73d: 281 of 608 exported lines would not parse.
//
// That is not a cosmetic defect. --export is the ONLY door out of the binary
// ring — native/moves_test.sh reads through it, and so does anyone studying a
// session. A reader that hits an unparsable line either dies or (worse, and this
// is what happened) drops it and keeps going, and then every count taken from
// the record is quietly short. A record you cannot read is not a record.
//
// So: RFC 8259 escaping, and no byte is thrown away to get it.
//   - " \ and the C0 controls become their escapes (\" \\ \n \r \t \b \f, and
//     \u00XX for the rest of < 0x20);
//   - well-formed UTF-8 is passed through as itself;
//   - a byte that is NOT part of well-formed UTF-8 — and the fixed-width Rec
//     fields guarantee these, because put() truncates at a byte boundary and can
//     cut a multi-byte character in half — is emitted as \u00XX of the byte's own
//     value. The parser then yields U+0080..U+00FF, one codepoint per lost byte,
//     so the original byte is still recoverable (latin-1 encode) instead of being
//     replaced by a U+FFFD that destroys it. Escaped, never dropped.
static string jesc(const string& in) {
  string out;
  out.reserve(in.size() + 8);
  const size_t n = in.size();
  size_t i = 0;
  char b[8];
  while (i < n) {
    const unsigned char c = (unsigned char)in[i];
    if (c < 0x80) {
      switch (c) {
        case '"':  out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n";  break;
        case '\r': out += "\\r";  break;
        case '\t': out += "\\t";  break;
        case '\b': out += "\\b";  break;
        case '\f': out += "\\f";  break;
        default:
          if (c < 0x20) { snprintf(b, sizeof b, "\\u%04x", c); out += b; }
          else out += (char)c;
      }
      i++;
      continue;
    }
    size_t len = 0;
    unsigned int cp = 0;
    if      ((c & 0xE0) == 0xC0) { len = 2; cp = c & 0x1Fu; }
    else if ((c & 0xF0) == 0xE0) { len = 3; cp = c & 0x0Fu; }
    else if ((c & 0xF8) == 0xF0) { len = 4; cp = c & 0x07u; }
    bool ok = (len != 0) && (i + len <= n);
    if (ok)
      for (size_t k = 1; k < len; k++) {
        const unsigned char cc = (unsigned char)in[i + k];
        if ((cc & 0xC0) != 0x80) { ok = false; break; }
        cp = (cp << 6) | (cc & 0x3Fu);
      }
    if (ok) {                                   // reject overlong / surrogate / out of range
      if (len == 2 && cp < 0x80) ok = false;
      else if (len == 3 && cp < 0x800) ok = false;
      else if (len == 4 && cp < 0x10000) ok = false;
      if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) ok = false;
    }
    if (ok) { out.append(in, i, len); i += len; continue; }
    snprintf(b, sizeof b, "\\u%04x", c);        // lone byte, kept as its own value
    out += b;
    i++;
  }
  return out;
}

static const char* kHelp =
  "rabadon-audit — has the ledger been tampered with?\n"
  "Every spool line is hash-chained to the one before it and each day file carries\n"
  "a .head sidecar. This walks the chain and reports, per file, how many lines are\n"
  "chained, where a break is, and what cannot be verified at all. An unchained or\n"
  "broken region is named out loud, never averaged away.\n"
  "\n"
  "usage: rabadon-audit [--days N] [--replay]\n"
  "\n"
  "  --days N    how far back to verify (default 7).\n"
  "  --replay    re-derive every hash from the bytes instead of trusting the head.\n"
  "  -h, --help  this screen.\n"
  "\n"
  "environment:\n"
  "  RABADON_DIR   where the spool lives (default ~/.rabadon).\n"
  "\n"
  "example:\n"
  "  rabadon-audit --days 30 --replay\n";

int main(int argc, char** argv) {
  // `rabadon-audit --help` used to be ignored by this loop and fall through to
  // the ledger walk: exit 0, an integrity report, and the flag never honoured.
  rb_help(argc, argv, kHelp);

  // --export <ring>: render the binary move ring as JSONL. R1.3 made the record
  // fixed-width binary so the hot path never parses text; a human and a test
  // still need to read it, and this is the one place text is produced. Reading
  // is not the hot path, so it can afford to be convenient.
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--export") == 0 && i + 1 < argc) {
      const char* path = argv[i + 1];
      FILE* f = fopen(path, "rb");
      if (!f) { fprintf(stderr, "audit --export: cannot open %s\n", path); return 1; }
      rbmoves::Hdr h{};
      if (fread(&h, 1, sizeof h, f) != sizeof h || memcmp(h.magic, "RBMV1", 5) != 0) {
        fprintf(stderr, "audit --export: %s is not a move ring\n", path); fclose(f); return 1;
      }
      const long long total = h.count;
      const long long keep = total < (long long)rbmoves::CAP ? total : (long long)rbmoves::CAP;
      std::vector<rbmoves::Rec> ring(rbmoves::CAP);
      if (fseek(f, (long)rbmoves::HDR_BYTES, SEEK_SET) != 0) { fclose(f); return 1; }
      if (fread(ring.data(), 1, rbmoves::CAP * sizeof(rbmoves::Rec), f) == 0 && keep > 0) { fclose(f); return 1; }
      fclose(f);
      const long long first = total - keep;
      for (long long k = 0; k < keep; k++) {
        const rbmoves::Rec& r = ring[(size_t)((first + k) % (long long)rbmoves::CAP)];
        rbmoves::Move m; rbmoves::from_rec(r, m);
        // raw only on the newest RAW_KEEP, same rule every reader gets
        const bool oldEnough = (keep - k) > (long long)rbmoves::RAW_KEEP;
        const string raw = oldEnough ? string() : m.raw;
        printf("{\"seq\":%lld,\"ts\":%lld,\"tool\":\"%s\",\"path\":\"%s\","
               "\"sig\":\"%s\",\"raw\":\"%s\",\"claimed_rc\":%d,"
               "\"err_sig\":\"%s\",\"suite\":%d,\"asserts\":%d,\"prev\":\"%s\"}\n",
               m.seq, m.ts, jesc(m.tool).c_str(), jesc(m.path).c_str(),
               jesc(m.sig).c_str(), jesc(raw).c_str(), m.claimed_rc,
               jesc(m.err_sig).c_str(), m.suite, m.asserts,
               jesc(rbmoves::get(r.prev, sizeof r.prev)).c_str());
      }
      return 0;
    }
  }

  double days = 7;
  bool replay = false;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--days") == 0 && i + 1 < argc) { double v = strtod(argv[++i], nullptr); if (v > 0) days = v; }
    else if (strcmp(argv[i], "--replay") == 0) replay = true;
    else rb_unknown_flag("rabadon-audit", argv[i]);
  }

  string rdir;
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) rdir = rd;
  else {
    const char* h = getenv("HOME");
    string home = (h && h[0]) ? h : "";
    if (home.empty()) { struct passwd* pw = getpwuid(getuid()); if (pw && pw->pw_dir) home = pw->pw_dir; }
    rdir = home + "/.rabadon";
  }
  string spool = rdir + "/spool";

  const double cutoff = now_ms() - days * 86400000.0;

  std::vector<string> files, heads;
  if (DIR* d = opendir(spool.c_str())) {
    while (struct dirent* ent = readdir(d)) {
      string n = ent->d_name;
      if (n.size() >= 6 && n.compare(n.size() - 6, 6, ".jsonl") == 0) files.push_back(n);
      else if (n.size() >= 11 && n.compare(n.size() - 11, 11, ".jsonl.head") == 0) heads.push_back(n);
    }
    closedir(d);
  }
  std::sort(files.begin(), files.end());
  std::sort(heads.begin(), heads.end());

  printf("rabadon audit — ledger integrity · %s\n\n", spool.c_str());
  if (files.empty() && heads.empty()) {
    // A NEVER-USED LEDGER AND A DELETED ONE ARE NOT THE SAME FACT, and this
    // branch used to answer both with exit 0 — "nothing to verify yet" on a
    // spool somebody had just wiped. Every HARDER attack convicts: a byte
    // edited, a line removed, a day file deleted while its sidecar remains,
    // all exit 1. Deleting both halves is the easiest of them and it was the
    // one that passed (found by an outside reviewer, 2026-09-03).
    //
    // The two are told apart by what the directory itself says. A spool that
    // has never existed is a fresh install. A spool DIRECTORY that exists and
    // holds nothing is either a fresh install one event short, or a wipe —
    // this cannot tell which, so it says exactly that and exits 2, the code
    // this tool already uses for "I could not check", never 0.
    struct stat sst;
    const bool dirExists = stat(spool.c_str(), &sst) == 0 && S_ISDIR(sst.st_mode);
    if (!dirExists) {
      printf("  no spool directory. rabadon has not recorded anything here yet.\n");
      return 0;
    }
    printf("  the spool directory exists and holds no day files and no sidecars.\n"
           "  that is a fresh install before its first event — or a ledger that was\n"
           "  deleted whole, and from here the two look identical. UNVERIFIABLE.\n"
           "  if this project has ever been supervised, treat it as a wipe:\n"
           "    git -C <project> checkout .rabadon   # the law, if you committed it\n");
    return 2;
  }

  long long totalChained = 0, totalUnchained = 0, totalBreaks = 0, totalUnverifiable = 0;

  // an orphan sidecar convicts a whole-file deletion: the day file is gone but
  // the commitment written beside it is still on disk.
  for (const string& h : heads) {
    string base = h.substr(0, h.size() - 5);          // strip ".head"
    if (std::binary_search(files.begin(), files.end(), base)) continue;
    printf("  %-22s      · chain BROKEN — day file is GONE, its .head sidecar remains (whole file deleted)\n",
           base.c_str());
    totalBreaks++;
  }

  for (const string& f : files) {
    const string path = spool + "/" + f;
    string body = read_file(path);
    Head hd = read_head(path + ".head");
    if (body.empty() && !hd.present) continue;   // nothing written, nothing claimed

    string last = "genesis";     // hash of the last CHAINED line seen
    long long chained = 0, unchained = 0, firstUnchainedLine = 0;
    long long firstBreakLine = 0;
    string breakNote;
    long long lineNo = 0;
    bool inWindow = false;

    size_t pos = 0;
    while (pos < body.size()) {
      size_t nl = body.find('\n', pos);
      string line = body.substr(pos, (nl == string::npos ? body.size() : nl) - pos);
      pos = (nl == string::npos) ? body.size() : nl + 1;
      lineNo++;
      if (line.empty()) continue;
      double ts = get_num(line, "ts");
      if (ts >= cutoff) inWindow = true;

      string prev = get_field(line, "prev");
      if (prev.empty()) {
        unchained++;
        if (firstUnchainedLine == 0) firstUnchainedLine = lineNo;
        continue;
      }
      if (prev != last && firstBreakLine == 0) {
        firstBreakLine = lineNo;
        breakNote = "prev=" + prev.substr(0, 12) + "… expected=" +
                    (last == "genesis" ? last : last.substr(0, 12) + "…");
      }
      last = rbsha::hex(line);
      chained++;

      if (replay && ts >= cutoff) {
        string ev = get_field(line, "ev");
        string pipe = get_field(line, "pipe");
        string what = get_field(line, "step");
        if (what.empty()) what = get_field(line, "detail");
        if (what.size() > 90) { what.resize(89); what += "…"; }
        printf("  %s %s  %-24s %-12s %s\n",
               (firstBreakLine && lineNo >= firstBreakLine) ? "✗" : "✓",
               local_stamp(ts).c_str(), pipe.c_str(), ev.c_str(), what.c_str());
      }
    }

    // ---- judge the file against its sidecar. the sidecar is written under the
    // same flock as the line it commits to, so anything the two disagree about
    // happened AFTER emit. "no sidecar" is not innocence: a chaining writer
    // always leaves one, so its absence beside chained lines is the deletion.
    bool broken = firstBreakLine != 0;
    bool unverifiable = false;
    string sidecarNote;
    if (hd.present) {
      if (hd.malformed)
        sidecarNote = "head sidecar is malformed (expected \"<sha256> <count>\")";
      else if (chained == 0)
        sidecarNote = "head sidecar present but NOT ONE line carries prev — the chain was stripped out";
      else if (hd.hash != last)
        sidecarNote = "head sidecar does not match the last chained line (truncated or rewritten tail)";
      else if (hd.count < 0) {
        unverifiable = true;
        sidecarNote = "head commits no line count (pre-0.4 sidecar) — a removed line cannot be ruled out";
      } else if (hd.count != chained)
        sidecarNote = "head commits " + std::to_string(hd.count) + " chained line(s), the file has " +
                      std::to_string(chained) + " — line(s) removed and the chain re-stitched";
    } else if (chained > 0) {
      sidecarNote = "chained lines but NO .head sidecar — the sidecar was deleted";
    } else if (unchained > 0) {
      unverifiable = true;
      sidecarNote = (f.size() > 16 && f.compare(f.size() - 16, 16, ".unchained.jsonl") == 0)
        ? "recorded outside the chain — an emitter could not take the day file's lock"
        : "no .head sidecar and no prev on any line — legacy writer, unverifiable";
    }
    if (!sidecarNote.empty() && !unverifiable) broken = true;

    // Lines with no prev sitting BESIDE a verified chain are not evidence of
    // tampering, and calling them that was a false alarm on the first real
    // ledger it met: a second, non-chaining writer (the legacy JS gate) appends
    // to the same day file, and every day would have read as attacked.
    //
    // Nothing is lost by not calling it a break, because stripping prev from a
    // line the chain covers is ALREADY caught elsewhere, always:
    //   - strip a middle line's prev -> the next chained line's prev no longer
    //     matches the hash chain -> BREAK at that line;
    //   - strip the last chained line's prev -> the head hash no longer matches
    //     -> BREAK;
    //   - strip every line's prev -> chained == 0 -> BREAK (above).
    // So the rule was redundant against an attacker and wrong against a friend.
    // What is true is that those lines cannot be proven, and the verdict says so
    // rather than folding them into a clean bill of health.
    if (!broken && unchained > 0 && chained > 0) {
      unverifiable = true;
      sidecarNote = std::to_string(unchained) + " line(s) from a writer that does not chain — " +
                    "verified events and unprovable ones share this file (first at line " +
                    std::to_string(firstUnchainedLine) + ")";
    }

    // old file, verified clean: keep the report short. anything unresolved prints.
    if (!broken && !unverifiable && !inWindow && !replay) continue;

    printf("  %-22s %6lld chained · %lld unchained", f.c_str(), chained, unchained);
    if (broken) {
      printf(" · chain BROKEN");
      if (firstBreakLine) printf(" at line %lld (%s)", firstBreakLine, breakNote.c_str());
      if (!sidecarNote.empty()) printf(" · %s", sidecarNote.c_str());
      printf("\n");
      totalBreaks++;
    } else if (unverifiable) {
      if (chained > 0) printf(" · chain OK · UNPROVEN: %s\n", sidecarNote.c_str());
      else printf(" · UNVERIFIABLE — %s\n", sidecarNote.c_str());
      totalUnverifiable++;
    } else {
      printf(" · chain OK · head verified (%lld line(s))\n", hd.count);
    }
    totalChained += chained; totalUnchained += unchained;
  }

  printf("\n");
  if (totalBreaks == 0 && totalUnverifiable == 0) {
    printf("  verdict: INTACT — %lld chained event(s) verified against their head sidecars\n", totalChained);
    return 0;
  }
  if (totalBreaks) {
    printf("  verdict: TAMPER-EVIDENT BREAK in %lld file(s) — the ledger was edited, truncated, reordered,\n"
           "           stripped of its chain, or deleted after emit\n", totalBreaks);
    if (totalUnverifiable)
      printf("           %lld further file(s) UNVERIFIABLE (see above)\n", totalUnverifiable);
    return 1;
  }
  printf("  verdict: PARTIAL — %lld chained event(s) verified, %lld file(s) UNVERIFIABLE holding %lld\n"
         "           line(s) outside any chain (see above). nothing is proven broken, but this is not a\n"
         "           clean bill of health: rabadon cannot tell a pre-chain file from one stripped bare.\n",
         totalChained, totalUnverifiable, totalUnchained);
  return 2;
}
