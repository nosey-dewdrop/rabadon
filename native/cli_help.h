// cli_help.h — the first thing a stranger types.
//
// Measured on 2026-08-01, `--help` across the sixteen native binaries:
//   trace   exit 0, 31798 bytes — it swallowed the flag and printed the real
//           ledger, in a byte stream that is not even valid UTF-8
//   do      HUNG: the flag became the task, and the planner opened a model call
//   serve   `-h` HUNG: the flag was unknown, so the HTTP server started
//   stats/lens/audit/drift/gate/net
//           exit 0 and either printed real data or printed nothing at all
//   budget/loop/verify/export/sandbox/repair/truth
//           exited 1, 2 or 3 on the one word every new user types first
//
// None of that is an engine bug. All of it decides whether the engine is ever
// run a second time.
//
// Two rules live here:
//   1. --help and -h print a screen on stdout and exit 0.
//   2. a flag this binary does not know is REFUSED, never swallowed. Swallowing
//      is the dangerous half: the tool then prints real output, so the flag
//      looks honoured and the operator believes a filter applied that never did.
#ifndef RABADON_CLI_HELP_H
#define RABADON_CLI_HELP_H

#include <cstdio>
#include <cstdlib>
#include <cstring>

// A bare `--` ends rabadon's own flags. `rabadon-sandbox -- pytest --help`
// must run pytest's help inside the sandbox, not print the sandbox's.
static inline bool rb_help_asked(int argc, char** argv) {
  for (int i = 1; i < argc; i++) {
    if (std::strcmp(argv[i], "--") == 0) return false;
    if (std::strcmp(argv[i], "--help") == 0 || std::strcmp(argv[i], "-h") == 0) return true;
  }
  return false;
}

// Help is stdout (it is the requested output, not a diagnostic) and exit 0.
// Call this as the FIRST statement of main, before any file, socket, model or
// subprocess work — `rabadon-do --help` used to reach a model call.
static inline void rb_help(int argc, char** argv, const char* text) {
  if (!rb_help_asked(argc, argv)) return;
  std::fputs(text, stdout);
  std::exit(0);
}

// An unknown option ends the run. Exit 2 = "you typed something I do not
// understand", distinct from a real verdict.
static inline void rb_unknown_flag(const char* prog, const char* flag) {
  std::fprintf(stderr, "%s: unknown option \"%s\" — run `%s --help`\n", prog, flag, prog);
  std::exit(2);
}

// true when the argument looks like a flag rather than a path/value. A bare
// "-" is a filename convention (stdin), not an option.
static inline bool rb_is_flag(const char* a) {
  return a[0] == '-' && a[1] != '\0';
}

#endif
