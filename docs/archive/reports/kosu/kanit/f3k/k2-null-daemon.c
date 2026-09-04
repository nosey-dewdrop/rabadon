/* k2-null-daemon.c — A MEASUREMENT INSTRUMENT. NOT A PRODUCT, NEVER INSTALLED.
 *
 * It answers every request with ALLOW without judging anything. That is not a
 * gate and must never be one; it exists to measure a LOWER BOUND and to prove
 * a routing fact, and both uses are destroyed if anybody mistakes it for a
 * daemon. It is built into the phase's evidence directory, run by hand, and
 * killed.
 *
 * WHAT IT MEASURES. rabadon-gated's cost has three parts: the client's socket
 * round trip, the daemon's two fork()s, and the judging the worker does. This
 * server has ZERO forks and ZERO judging, so the time a client spends talking
 * to it is the FLOOR that any daemon design whatsoever must pay — including a
 * perfect one-fork rewrite. If that floor is already slower than judging
 * in-process, then no fork-count optimisation can make the daemon win, and the
 * question is closed by measurement rather than by argument.
 *
 * WHAT IT PROVES. It answers 0 (allow) to an event the real gate BLOCKS (exit
 * 2). So a client that comes back 0 demonstrably reached the socket, and a
 * client that comes back 2 demonstrably judged locally. Without that, an arm
 * that silently failed to connect would look like a fast daemon.
 *
 * Protocol copied from native/gated_client.h: 4-byte length, then the body,
 * with two descriptors attached; the reply is one byte, the verdict.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>

int main(int argc, char** argv) {
  if (argc < 2) { fprintf(stderr, "usage: k2-null-daemon <socket-path>\n"); return 1; }
  signal(SIGPIPE, SIG_IGN);
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof addr);
  addr.sun_family = AF_UNIX;
  if (strlen(argv[1]) >= sizeof addr.sun_path) { fprintf(stderr, "path too long\n"); return 1; }
  strcpy(addr.sun_path, argv[1]);
  unlink(argv[1]);
  int srv = socket(AF_UNIX, SOCK_STREAM, 0);
  if (srv < 0) { perror("socket"); return 1; }
  if (bind(srv, (struct sockaddr*)&addr, sizeof addr) < 0) { perror("bind"); return 1; }
  if (listen(srv, 64) < 0) { perror("listen"); return 1; }
  fprintf(stderr, "k2-null-daemon: listening on %s (ALLOWS EVERYTHING - instrument only)\n", argv[1]);

  for (;;) {
    int c = accept(srv, NULL, NULL);
    if (c < 0) continue;
    /* Drain exactly like the real daemon does, so the round trip is faithful. */
    char buf[8192];
    char cbuf[CMSG_SPACE(sizeof(int) * 2)];
    unsigned int want = 0;
    size_t got = 0;
    for (;;) {
      struct iovec iov = { buf, sizeof buf };
      struct msghdr msg;
      memset(&msg, 0, sizeof msg);
      memset(cbuf, 0, sizeof cbuf);
      msg.msg_iov = &iov; msg.msg_iovlen = 1;
      msg.msg_control = cbuf; msg.msg_controllen = sizeof cbuf;
      ssize_t n = recvmsg(c, &msg, 0);
      if (n <= 0) break;
      /* Close any descriptors we were handed; leaking them would make this
         instrument run out of files long before the run ends. */
      for (struct cmsghdr* cm = CMSG_FIRSTHDR(&msg); cm; cm = CMSG_NXTHDR(&msg, cm))
        if (cm->cmsg_level == SOL_SOCKET && cm->cmsg_type == SCM_RIGHTS &&
            cm->cmsg_len == CMSG_LEN(sizeof(int) * 2)) {
          int fds[2]; memcpy(fds, CMSG_DATA(cm), sizeof fds);
          close(fds[0]); close(fds[1]);
        }
      if (!want && (size_t)n >= 4) memcpy(&want, buf, 4);
      got += (size_t)n;
      if (want && got >= (size_t)want + 4) break;
    }
    unsigned char verdict = 0;   /* ALLOW, without looking. Instrument only. */
    ssize_t w = write(c, &verdict, 1);
    (void)w;
    close(c);
  }
}
