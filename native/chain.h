// chain.h — the ledger has ONE writer. (C++17, zero deps)
//
// Every event line in a spool day file is `{...,"prev":"<sha256 of the line
// before it>"}`. Beside the day file sits a `.head` sidecar committing two
// facts under the same flock as the line itself:
//
//     <sha256 of the last chained line> <number of chained lines>
//
// The hash catches an edited, reordered or truncated file. The COUNT catches
// the one attack the hash alone cannot: remove a line and re-stitch the chain
// around the hole — the file is then internally consistent, but shorter than
// its own sidecar says it is.
//
// ONE FORMAT, ONE MUTEX, ONE FILE PER DAY — that is the rule, and `<day>.jsonl`
// is the file. Three binaries append to it (gate, repair, loop). They all call
// append() so there is one format, and `rabadon audit` is the single referee
// for all of them. If you change the sidecar format here, audit.cpp's
// read_head() is the other half.
//
// There is a FOURTH writer in the same npm package and it is not a binary:
// core/bus.mjs, reached through index.mjs, which package.json exports — i.e.
// `import { pipeline } from 'rabadon'`. It used to append into this file with no
// prev, no lock and no sidecar: one run of the documented public API turned a
// fresh install from INTACT/exit 0 into PARTIAL/exit 2, permanently, because
// prev cannot be retro-fitted without rewriting the file — the edit audit exists
// to detect.
//
// It chains now, and it chains HERE, in this file. Giving it a private
// `<day>.js.jsonl` also fixes the audit and costs more than it saves: the
// readers of this ledger look up exactly one name. ui/server.mjs — the `rabadon
// watch` cockpit — tails `<day>.jsonl`, and hooks/gate.mjs, the hook `rabadon
// init` installs, reads it back to build handoff.md. A second file leaves both
// dark while every test still passes.
//
// Sharing the file is safe because the mutex is shared. flock(2) alone could
// never be it — Node has no flock, not in `fs`, and macOS ships no flock(1) to
// shell out to — so append() takes the `<path>.lock` sentinel below with O_EXCL,
// which both languages have, and holds flock inside it. A fifth writer takes
// that sentinel and calls append(); it does not get to append bare into a
// chained file, and it does not get a private file either.
//
// Fail-open, without lying: if the lock cannot be taken the line is recorded in
// a sibling `<day>.unchained.jsonl` instead of being appended unchained into the
// chained file. The ledger keeps recording, the chained file stays provable,
// and the audit reports that sibling as an unverifiable stream rather than
// pretending it is part of the chain.

#pragma once

#include <cstdlib>
#include <fstream>
#include <string>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "sha256.h"
#include "jsonl.h"

namespace rbchain {

using std::string;

// --- the cross-language mutex ---------------------------------------------
// flock(2) below guards the native writers against each other, and it is the
// stronger lock: the kernel releases it when the holder dies. It cannot be the
// whole story, because core/bus.mjs writes this same file and cannot take it —
// Node has no flock binding, and macOS ships no flock(1) to shell out to.
//
// The one atomic primitive both languages share is an O_EXCL create. So the
// chained file's mutex is the sentinel `<path>.lock`, and EVERY writer in both
// languages takes it before read_head. core/bus.mjs is the other half of this
// protocol and carries the same two constants; change one, change both.
//
// Without it the two implementations read the same head, append lines carrying
// the same prev, and the second one's prev stops matching — audit convicting an
// honest ledger of a BREAK. A false accusation is worse than the bug it reports.
static const long long LOCK_STALE_MS = 5000;   // older than this: a killed holder
static const long long LOCK_WAIT_MS  = 250;    // fight this long, then fail open

inline long long lock_now_ms() {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// A lock FILE is not released by the kernel when its holder is killed, the way
// flock is. Without the stale reap below, one SIGKILL would push every later
// event of that day permanently out of the chain — the fail-open made forever.
inline bool acquire_lock(const string& lockPath) {
  const long long deadline = lock_now_ms() + LOCK_WAIT_MS;
  for (;;) {
    int fd = ::open(lockPath.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0644);
    if (fd >= 0) { close(fd); return true; }
    struct stat st;
    const bool stale = ::stat(lockPath.c_str(), &st) == 0 &&
                       lock_now_ms() - (long long)st.st_mtime * 1000 > LOCK_STALE_MS;
    if (stale && ::unlink(lockPath.c_str()) == 0) continue;  // steal it once, then retry
    if (lock_now_ms() >= deadline) return false;
    usleep(2000);
  }
}

// number of chained lines already in the file. Only ever called once per day
// file, to migrate a pre-0.4 sidecar that carries no count.
//
// A line is chained when it carries a non-empty top-level `prev` — the SAME
// predicate audit.cpp judges by, read the same way (jsonl.h). The value is read
// as whatever sits there, because the FIRST line of every day carries
// prev:"genesis", not a hash. Requiring 64 hex here undercounted every migrated
// file by exactly one and made it read as tampered forever.
//
// This used to require the literal suffix `,"prev":"<value>"}`, which is a fact
// about rabadon's own printf, not about the SPEC — SPEC §2 says single-line
// JSON and fixes neither spacing nor key order. On a spool written by a stock
// serializer (`"prev": "..."`, or prev not written last) the suffix matched
// nothing: 3 chained lines counted as 1, the migrated sidecar then committed a
// count lower than the file's, and audit convicted an intact ledger — the very
// same false accusation, arriving through the migration path instead.
inline long long count_chained_lines(const string& path) {
  std::ifstream f(path);
  if (!f) return 0;
  long long n = 0;
  string line;
  while (std::getline(f, line)) {
    if (line.empty()) continue;
    if (rbjson::has_str(line, "prev")) n++;
  }
  return n;
}

// prev = the committed hash ("genesis" when there is no sidecar);
// count = the committed line count (-1 = pre-0.4 sidecar, no count)
inline void read_head(const string& headPath, string& prev, long long& count) {
  prev = "genesis"; count = -1;
  std::ifstream hf(headPath);
  if (!hf) return;
  string h;
  if (!std::getline(hf, h)) return;
  size_t sp = h.find(' ');
  string hash = (sp == string::npos) ? h : h.substr(0, sp);
  if (hash.size() != 64) return;
  prev = hash;
  if (sp == string::npos) return;
  string c = h.substr(sp + 1);
  while (!c.empty() && (c.back() == '\r' || c.back() == ' ')) c.pop_back();
  if (!c.empty() && c.find_first_not_of("0123456789") == string::npos)
    count = strtoll(c.c_str(), nullptr, 10);
}

// `bodyOpen` is a JSON object WITHOUT its closing brace, e.g. {"v":1,...,"ev":"X"
// Returns the exact line written (newline included) so a caller can also fan it
// out to a socket.
inline string append(const string& spoolPath, const string& bodyOpen) {
  const string lockPath = spoolPath + ".lock";
  if (acquire_lock(lockPath)) {
    int fd = ::open(spoolPath.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0 && flock(fd, LOCK_EX) == 0) {
      const string headPath = spoolPath + ".head";
      string prev; long long count;
      read_head(headPath, prev, count);
      if (count < 0) count = (prev == "genesis") ? 0 : count_chained_lines(spoolPath);
      const string chained = bodyOpen + ",\"prev\":\"" + prev + "\"}";
      const string line = chained + "\n";
      ssize_t w = write(fd, line.c_str(), line.size()); (void)w;
      { std::ofstream hf(headPath, std::ios::trunc);
        if (hf) hf << rbsha::hex(chained) << " " << (count + 1) << "\n"; }
      flock(fd, LOCK_UN);
      close(fd);
      ::unlink(lockPath.c_str());
      return line;
    }
    if (fd >= 0) close(fd);
    ::unlink(lockPath.c_str());
  }
  // could not take the lock: record it, but outside the chain and outside the
  // chained file, so the day's proof is not damaged by our own fail-open.
  const string line = bodyOpen + ",\"unlocked\":true}\n";
  string side = spoolPath;
  if (side.size() > 6 && side.compare(side.size() - 6, 6, ".jsonl") == 0)
    side = side.substr(0, side.size() - 6) + ".unchained.jsonl";
  std::ofstream f(side, std::ios::app);
  if (f) f << line;
  return line;
}

}  // namespace rbchain
