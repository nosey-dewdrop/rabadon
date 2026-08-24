// rabadon-gated — the persistent gate. One socket, one warm process, and NOT a
// second implementation of the judgement.
//
// THE ONE SOURCE OF TRUTH. This file includes native/gate.cpp with main()
// renamed. That is deliberate and it is the whole safety argument: a daemon
// that re-implemented the rules would be a fork of the product that drifts
// silently, and the first divergence would show up as a command the gate
// blocks and the daemon allows. There is exactly one judgement in this repo and
// this file runs it, not a copy of it.
//
// WHAT IT ACTUALLY SAVES. reports/R1.3/PROFIL.md measured ~2.3 ms of a 4.2 ms
// call in fork/exec/dyld, before rabadon runs at all. The worker here is forked
// from a process that already paid that, and inherits its code pages, its heap
// and its warm file cache copy-on-write. The judging work itself is NOT skipped
// and NOT cached — the worker reads state.json, the ring and the spool exactly
// as a cold gate does, because caching a verdict across calls would make the
// guard answer questions nobody asked it.
//
// TWO FORKS PER REQUEST, ON PURPOSE. The worker runs rb_gate_main(), which
// exits — so it cannot also write the verdict back. A handler process sits
// between: it owns the connection, forks the worker, waits for it, and sends
// the exit status. Serialising instead (judge in the accept loop) would be one
// fork cheaper and would let a single slow project block every other agent on
// the machine.
//
// FAIL-SAME. Nothing here can turn a block into an allow: if the daemon is
// absent, unreachable, or dies mid-request, native/gated_client.h returns
// kFallback and the caller runs the ordinary in-process gate.
#define main rb_gate_main
#include "gate.cpp"
#undef main

#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <cerrno>
#include <csignal>
#include <string>
#include <vector>

#include "gated_client.h"

namespace {

// A worker exit status that means "I did not judge this" — distinct from the
// gate's own 0 (allow) and 2 (block). The handler forwards no verdict for it,
// so the client falls back and judges locally. Any number the gate can itself
// return would be indistinguishable from a real answer.
const int kNoAnswer = 255;

// Reap handlers as they finish. Without this the daemon accumulates zombies for
// as long as it runs, which for a daemon meant to live all day is a leak with a
// process-table-sized blast radius.
void reap(int) {
  int saved = errno;
  while (waitpid(-1, nullptr, WNOHANG) > 0) {}
  errno = saved;
}

// Read the length-framed request and collect the two passed descriptors.
// SOCK_STREAM may split one sendmsg across several recvmsg calls; the
// descriptors arrive with the first segment.
bool read_request(int fd, std::string* body, int fds[2]) {
  fds[0] = fds[1] = -1;
  std::string in;
  char buf[8192];
  char cbuf[CMSG_SPACE(sizeof(int) * 2)];
  uint32_t want = 0;
  for (;;) {
    struct iovec iov;
    iov.iov_base = buf;
    iov.iov_len = sizeof buf;
    struct msghdr msg;
    memset(&msg, 0, sizeof msg);
    memset(cbuf, 0, sizeof cbuf);
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = cbuf;
    msg.msg_controllen = sizeof cbuf;
    const ssize_t n = recvmsg(fd, &msg, 0);
    if (n <= 0) return false;
    for (struct cmsghdr* cm = CMSG_FIRSTHDR(&msg); cm; cm = CMSG_NXTHDR(&msg, cm)) {
      if (cm->cmsg_level == SOL_SOCKET && cm->cmsg_type == SCM_RIGHTS &&
          cm->cmsg_len == CMSG_LEN(sizeof(int) * 2)) {
        memcpy(fds, CMSG_DATA(cm), sizeof(int) * 2);
      }
    }
    in.append(buf, (size_t)n);
    if (!want && in.size() >= 4) {
      memcpy(&want, in.data(), 4);
      if (want > (1u << 24)) return false;  // 16 MB is a broken client, not an event
    }
    if (want && in.size() >= (size_t)want + 4) break;
  }
  body->assign(in, 4, want);
  return fds[0] >= 0 && fds[1] >= 0;
}

// The worker: become the caller. Same cwd, same environment, the caller's own
// stdout and stderr, and the event on a pipe as stdin — then the ordinary gate
// main(), which exits on its own.
[[noreturn]] void run_worker(const std::string& body, int fds[2], int evfd, char** argv) {
  const char* p = body.c_str();
  const char* end = p + body.size();
  const std::string cwd = p;
  p += cwd.size() + 1;

  // The environment is REPLACED, not merged. A leftover RABADON_DIR from
  // whatever shell started the daemon would silently redirect another user's
  // ledger, so the daemon's own environment must not survive into a judgement.
  std::vector<std::string> keep;
  while (p < end && *p) {
    keep.emplace_back(p);
    p += keep.back().size() + 1;
  }
  keep.emplace_back("RABADON_GATED_CHILD=1");  // stops the worker calling us back
  std::vector<char*> envp;
  envp.reserve(keep.size() + 1);
  for (auto& s : keep) envp.push_back(const_cast<char*>(s.c_str()));
  envp.push_back(nullptr);
  environ = envp.data();

  // A cwd that no longer exists is not this daemon's call to make: dying here
  // without an answer sends the client back to its own in-process path, where
  // the same missing directory is handled by the same code as always.
  if (!cwd.empty() && chdir(cwd.c_str()) != 0) _exit(kNoAnswer);
  dup2(evfd, 0); close(evfd);
  if (fds[0] != 1) { dup2(fds[0], 1); close(fds[0]); }
  if (fds[1] != 2) { dup2(fds[1], 2); close(fds[1]); }
  char* self[2] = {argv[0], nullptr};
  _exit(rb_gate_main(1, self));
}

}  // namespace

// The daemon shipped without this and cli_test.sh caught it the day it was
// born: `rabadon-gated --help` did not print help, it fell straight through to
// listen() and sat there. Every other binary in this repo answers the first
// word a stranger types; a daemon that instead HANGS on it reads as a broken
// install. rb_help must run before any socket work, for the same reason
// rabadon-do's runs before any model call.
static const char* kGatedHelp =
  "rabadon-gated — the persistent gate. One warm process, the SAME judgement.\n"
  "This binary does not re-implement the rules: it includes rabadon-gate's own\n"
  "main() and forks a worker per request, so a verdict from the daemon and a\n"
  "verdict from the cold gate come from one source. It is a speed decision, not\n"
  "a policy decision.\n"
  "\n"
  "usage: rabadon-gated [--version] [-h|--help]\n"
  "\n"
  "  (no argument)   listen, and judge requests until killed. Runs in the\n"
  "                  foreground; supervise it the way you supervise any daemon.\n"
  "  --version       print the version.\n"
  "  -h, --help      this screen.\n"
  "\n"
  "It takes no flags of its own. The socket is chosen by the environment:\n"
  "  RABADON_GATED_SOCK   absolute path to bind. Default:\n"
  "                       $XDG_RUNTIME_DIR/rabadon-<uid>.sock, deliberately NOT\n"
  "                       inside the repo, where a deep worktree overruns the\n"
  "                       kernel's sun_path limit.\n"
  "\n"
  "FAIL-SAME: if this daemon is absent, unreachable, or dies mid-request, the\n"
  "caller judges in-process exactly as it did before. It can make the gate\n"
  "faster; it can never turn a block into an allow.\n"
  "\n"
  "example:\n"
  "  rabadon-gated &                 # then run agents as usual\n";

int main(int argc, char** argv) {
  rb_help(argc, argv, kGatedHelp);

  if (argc > 1 && std::string(argv[1]) == "--version") {
    printf("rabadon-gated " RABADON_VERSION "\n");
    return 0;
  }

  // A flag this daemon does not know is REFUSED, never swallowed. Swallowing is
  // the dangerous half here: an operator who typed `--sock /tmp/x` and saw the
  // daemon come up would believe it bound there, while it bound to the default
  // and every client kept talking to the old socket. There are no flags to
  // accept, so the rule is simple — anything flag-shaped that got this far is
  // a typo, and the run ends before a socket exists.
  for (int i = 1; i < argc; i++) {
    if (rb_is_flag(argv[i])) rb_unknown_flag("rabadon-gated", argv[i]);
  }

  // Same reason as the gate: a dead client must never kill this process
  // mid-judgement.
  signal(SIGPIPE, SIG_IGN);

  const char* envSock = getenv("RABADON_GATED_SOCK");
  const std::string sockPath =
      (envSock && *envSock) ? std::string(envSock) : rbgated::default_sock_path();

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof addr);
  addr.sun_family = AF_UNIX;
  // The check KOSU-RABADON-2.md A1 asks for, at the one place it decides
  // something. bind() would report ENAMETOOLONG here, but only after strncpy
  // had already truncated the name, so the error would name the wrong path.
  if (sockPath.size() >= sizeof addr.sun_path) {
    fprintf(stderr,
            "rabadon-gated: socket path is %zu bytes, the kernel limit is %zu.\n"
            "  path: %s\n"
            "  Set RABADON_GATED_SOCK to a shorter absolute path — the default is\n"
            "  $XDG_RUNTIME_DIR/rabadon-<uid>.sock, and it is deliberately NOT\n"
            "  inside the repository, where a deep worktree overruns this limit.\n",
            sockPath.size(), sizeof addr.sun_path, sockPath.c_str());
    return 2;
  }
  memcpy(addr.sun_path, sockPath.c_str(), sockPath.size());

  // A stale socket file from a killed daemon must be cleared, but a LIVE one
  // must not: unlinking it would leave the running daemon holding a name
  // nobody can reach any more. Connecting is the only honest way to tell the
  // two apart.
  {
    const int probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe >= 0) {
      if (connect(probe, (struct sockaddr*)&addr, sizeof addr) == 0) {
        close(probe);
        fprintf(stderr, "rabadon-gated: a daemon is already listening on %s\n", sockPath.c_str());
        return 3;
      }
      close(probe);
    }
    unlink(sockPath.c_str());
  }

  const int srv = socket(AF_UNIX, SOCK_STREAM, 0);
  if (srv < 0) { perror("rabadon-gated: socket"); return 4; }
  // 0600 before anyone can connect: the socket hands a caller this user's
  // judgement, this user's cwd and this user's ledger. umask is set rather than
  // chmod'ed after bind because the window between the two is a window.
  const mode_t old = umask(0177);
  if (bind(srv, (struct sockaddr*)&addr, sizeof addr) < 0) {
    umask(old);
    fprintf(stderr, "rabadon-gated: bind %s: %s\n", sockPath.c_str(), strerror(errno));
    return 5;
  }
  umask(old);
  chmod(sockPath.c_str(), 0600);  // belt and braces: some platforms ignore umask on bind
  if (listen(srv, 64) < 0) { perror("rabadon-gated: listen"); return 6; }

  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = reap;
  sa.sa_flags = SA_RESTART | SA_NOCLDSTOP;
  sigaction(SIGCHLD, &sa, nullptr);

  // Pay the timezone load ONCE, here, in the parent — this is where the 28.5%
  // goes. gate.cpp's day-string cache is a pair of statics, so every worker
  // forked below inherits it warm copy-on-write and its first call is a memcpy
  // instead of a 269-483 us load (reports/R7/PROFIL-YARGILAMA.md). Nothing is
  // cached ACROSS requests here: the worker still reads state.json, the ring
  // and the spool exactly as a cold gate does. What is reused is process
  // initialisation, which has no verdict in it.
  { char warm[16]; rb_day_str(warm); }

  fprintf(stderr, "rabadon-gated " RABADON_VERSION " listening on %s\n", sockPath.c_str());

  for (;;) {
    const int c = accept(srv, nullptr, nullptr);
    if (c < 0) {
      if (errno == EINTR) continue;  // SIGCHLD landed between calls
      break;
    }
    const pid_t handler = fork();
    if (handler == 0) {
      close(srv);
      // The reaper above is INHERITED, and it broke this daemon once: on the
      // worker's exit the handler's own SIGCHLD handler ran waitpid(-1) and
      // collected the status first, so the waitpid below returned ECHILD, no
      // verdict was sent, and the client fell back. Measured, not guessed —
      // the client read 0 bytes and a blocked `rm -rf /` came back as exit 0.
      // The handler waits for exactly one child and must own its status.
      signal(SIGCHLD, SIG_DFL);
      std::string body;
      int fds[2];
      if (!read_request(c, &body, fds)) _exit(0);  // client vanished; it falls back

      // The event reaches the worker down a pipe, and the write happens AFTER
      // the fork so the worker is already draining it. Writing first would
      // deadlock this handler the moment an event exceeded the pipe buffer.
      int ev[2];
      if (pipe(ev) != 0) { close(fds[0]); close(fds[1]); close(c); _exit(0); }
      const char* p = body.c_str();
      size_t off = strlen(p) + 1;                                  // past cwd
      while (off < body.size() && body[off] != '\0') off += strlen(p + off) + 1;  // past env
      if (off < body.size()) off++;                                // past the empty entry
      const std::string event = body.substr(off);

      const pid_t worker = fork();
      if (worker == 0) { close(c); close(ev[1]); run_worker(body, fds, ev[0], argv); }
      close(ev[0]);
      close(fds[0]); close(fds[1]);
      if (worker > 0) {
        size_t w = 0;
        while (w < event.size()) {
          const ssize_t k = write(ev[1], event.data() + w, event.size() - w);
          if (k <= 0) break;
          w += (size_t)k;
        }
      }
      close(ev[1]);

      int st = 0;
      if (worker > 0 && waitpid(worker, &st, 0) == worker && WIFEXITED(st) &&
          WEXITSTATUS(st) != kNoAnswer) {
        // A worker killed by a signal sends nothing on purpose: the client
        // would otherwise read a number no gate path ever returns. Silence
        // makes it fall back and judge locally, which is the only outcome that
        // cannot become an accidental allow.
        const unsigned char code = (unsigned char)WEXITSTATUS(st);
        const ssize_t wrote = write(c, &code, 1);
        (void)wrote;
      }
      close(c);
      _exit(0);
    }
    close(c);
    if (handler < 0) continue;  // out of processes: the client falls back
  }
  close(srv);
  unlink(sockPath.c_str());
  return 0;
}
