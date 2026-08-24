// rabadon thin client — hand this PreToolUse call to the persistent daemon.
//
// WHY. ~2.3 ms of a 4.2 ms gate call is fork/exec/dyld before a single line of
// rabadon runs (reports/R1.3/PROFIL.md). The daemon (native/gated.cpp) is a
// warm process that already paid that; it forks a worker whose pages, heap and
// file cache are inherited, and the worker runs THE SAME judging code — the
// daemon is literally gate.cpp compiled with main() renamed, so there is no
// second implementation that can drift from this one.
//
// WHAT IS AND IS NOT SAVED. The client below does not return until the daemon
// has answered, because the exit code IS the verdict. So the time a caller
// measures still contains the whole judgement; what disappears is only the
// worker's process startup. A client that replied early would be measuring
// nothing, which is why the read() of the verdict byte is blocking and last.
//
// FAIL-SAME, NOT FAIL-OPEN. Every failure here — no socket, refused connect,
// short write, dead daemon — returns kFallback, and the caller runs today's
// in-process path unchanged. The one outcome this file must never produce is
// "allow because the daemon was down".
//
// WHY THE EVENT IS COPIED AND stdin IS NOT PASSED. An earlier version of this
// file handed the caller's fd 0 to the worker, which is faster and was wrong:
// when the worker died before answering, the client fell back to the in-process
// path, read the stdin the worker had already drained, saw an empty event and
// returned 0. A dead daemon silently ALLOWED the command. Falling back is only
// honest if the caller still owns everything it needs to judge alone, so the
// event travels as bytes and the caller keeps its copy. stdout and stderr ARE
// passed, because the worker writing refusals straight to the caller's terminal
// is what keeps the output byte-identical, and neither is read from.
#ifndef RABADON_GATED_CLIENT_H
#define RABADON_GATED_CLIENT_H

#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

extern char** environ;

namespace rbgated {

// Caller contract: kFallback means "I did nothing, run the normal path".
static const int kFallback = -1;

// The socket lives OUTSIDE the repo, at a short absolute path, on purpose.
// sockaddr_un.sun_path is 104 bytes on macOS and 108 on Linux. A socket named
// inside a deep worktree overruns that, and the overrun is SILENT: strncpy
// truncates, connect() then fails with ENOENT, and the symptom is identical to
// "the daemon is not running". KOSU-RABADON-2.md A1 fixes the path for exactly
// this reason.
inline std::string default_sock_path() {
  const char* rt = getenv("XDG_RUNTIME_DIR");
  std::string dir = (rt && *rt) ? rt : "/tmp";
  char buf[64];
  snprintf(buf, sizeof buf, "/rabadon-%u.sock", (unsigned)getuid());
  return dir + buf;
}

// Which socket to try: an explicit RABADON_GATED_SOCK always wins, and it wins
// even when the file is absent, because an explicit request that silently fell
// back to a different socket would be the worst of both worlds. The default
// path is only tried when it already exists, so a machine with no daemon pays
// one stat() and not a connect() timeout.
inline bool resolve_sock(std::string* out) {
  const char* env = getenv("RABADON_GATED_SOCK");
  if (env && *env) { *out = env; return true; }
  std::string d = default_sock_path();
  struct stat st;
  if (stat(d.c_str(), &st) == 0 && S_ISSOCK(st.st_mode)) { *out = d; return true; }
  return false;
}

// The daemon must not talk to itself. The worker it forks runs the very same
// gate source, so without this marker the worker would find the socket and
// hand the call straight back — an infinite round trip on every event.
inline bool is_daemon_worker() {
  const char* m = getenv("RABADON_GATED_CHILD");
  return m && *m == '1';
}

// Returns the gate's exit code, or kFallback if the daemon could not answer.
// `raw` is the hook event exactly as it arrived on stdin; the caller must still
// hold it after this returns, because kFallback means "judge it yourself".
inline int try_daemon(const std::string& raw) {
  if (is_daemon_worker()) return kFallback;
  std::string sockPath;
  if (!resolve_sock(&sockPath)) return kFallback;

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof addr);
  addr.sun_family = AF_UNIX;
  // LOUD about the one failure that used to be silent. Truncating here would
  // manufacture a "daemon is down" that no operator could ever debug.
  if (sockPath.size() >= sizeof addr.sun_path) {
    fprintf(stderr,
            "rabadon: daemon socket path is %zu bytes, the kernel limit is %zu — "
            "not connecting. Set RABADON_GATED_SOCK to a shorter absolute path "
            "(default is $XDG_RUNTIME_DIR/rabadon-<uid>.sock).\n",
            sockPath.size(), sizeof addr.sun_path);
    return kFallback;
  }
  memcpy(addr.sun_path, sockPath.c_str(), sockPath.size());

  const int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) return kFallback;
  if (connect(fd, (struct sockaddr*)&addr, sizeof addr) < 0) { close(fd); return kFallback; }

  // Payload: a 4-byte length, then cwd, then every environment entry, each
  // NUL-terminated and closed by one empty entry, then the event bytes. The
  // whole environment goes because the gate reads a dozen variables across five
  // files and a client that shipped a hand-picked subset would judge
  // differently from the same binary run directly — which is the one difference
  // this design is not allowed to have. The length prefix is what lets the
  // daemon know the event ended, since the event itself may contain anything.
  std::string body;
  char cwdbuf[4096];
  body.append(getcwd(cwdbuf, sizeof cwdbuf) ? cwdbuf : ".");
  body.push_back('\0');
  for (char** e = environ; e && *e; ++e) { body.append(*e); body.push_back('\0'); }
  body.push_back('\0');
  body.append(raw);

  std::string payload;
  const uint32_t n32 = (uint32_t)body.size();
  payload.append((const char*)&n32, 4);
  payload.append(body);

  int passed[2] = {1, 2};
  char cbuf[CMSG_SPACE(sizeof passed)];
  memset(cbuf, 0, sizeof cbuf);
  struct iovec iov;
  iov.iov_base = (void*)payload.data();
  iov.iov_len = payload.size();
  struct msghdr msg;
  memset(&msg, 0, sizeof msg);
  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  msg.msg_control = cbuf;
  msg.msg_controllen = sizeof cbuf;
  struct cmsghdr* cm = CMSG_FIRSTHDR(&msg);
  cm->cmsg_level = SOL_SOCKET;
  cm->cmsg_type = SCM_RIGHTS;
  cm->cmsg_len = CMSG_LEN(sizeof passed);
  memcpy(CMSG_DATA(cm), passed, sizeof passed);

  // The first sendmsg carries the descriptors and as much of the payload as the
  // socket will take; the rest follows as ordinary writes. SOCK_STREAM is free
  // to accept a partial buffer, and treating that as a failure would send every
  // large event down the fallback path for no reason.
  ssize_t sent = sendmsg(fd, &msg, 0);
  if (sent <= 0) { close(fd); return kFallback; }
  size_t off = (size_t)sent;
  while (off < payload.size()) {
    const ssize_t w = write(fd, payload.data() + off, payload.size() - off);
    if (w <= 0) { close(fd); return kFallback; }
    off += (size_t)w;
  }

  // Blocking, and deliberately the last thing that happens: the byte IS the
  // verdict, so the caller's clock keeps running until the judgement is done.
  unsigned char code = 0;
  const ssize_t got = read(fd, &code, 1);
  close(fd);
  if (got != 1) {
    // The worker died before answering. Falling back re-judges, which can write
    // the same ledger event twice; NOT falling back would let the action
    // through unjudged. A duplicated line is visible and auditable, a silent
    // allow is neither, so the guard takes the loud failure every time.
    return kFallback;
  }
  return (int)code;
}

}  // namespace rbgated

#endif  // RABADON_GATED_CLIENT_H
