// run.cpp — supervise an agent rabadon knows nothing about.  (C++17)
//
// THE PROBLEM THIS EXISTS FOR
// Every other binding in this repository asks the agent to cooperate. Claude
// Code has hooks, Cursor has hooks, and docs/agent-contract.md lets a third
// agent pipe JSON at the gate. That covers three agents. There are thousands,
// most of them have no hook API at all, and the one that matters to a given
// user is usually not on anybody's list. Writing an adapter per agent is not a
// strategy, it is a treadmill — and the user who opens rabadon, looks for their
// own tool, and does not find it, leaves.
//
// So stop asking the agent anything.
//
// Whatever an agent is, it does its damage the same way every program does: it
// runs a program. `git push --force`, `rm -rf`, `wrangler deploy`, `curl | sh`.
// If rabadon owns the PATH the agent inherits, every one of those goes through
// the gate before it runs, and the agent does not have to know rabadon exists.
//
//     rabadon run -- <any agent, any flags>
//
// HOW
// A temporary directory is put FIRST on PATH holding one shim per dangerous
// program. Each shim is two lines: hand the command to `rabadon exec` for
// judgment, then become the real binary. Judgment is the SAME rules.h the hook
// uses — one law, one parser, one ledger — so a rule someone wrote for Claude
// Code refuses the identical command under an agent nobody has heard of.
//
// WHICH PROGRAMS GET A SHIM
// Not a fashion list. The baseline set below is the programs the compiled-in
// laws can actually refuse, plus every literal program name that appears at the
// head of a deny pattern in this project's guard.json — so a project that
// writes a rule about `wrangler` gets `wrangler` shimmed without being asked.
// Shimming everything on PATH would put a fork on every `ls` in a build.
//
// WHAT THIS DOES NOT CATCH, said plainly because a supervisor that overstates
// its reach is worse than one that admits a hole:
//   - an absolute path (`/usr/bin/git push --force`) skips PATH and skips the
//     shim. `rabadon exec` and the kernel fence still cover writes; the command
//     law does not see it.
//   - a program the agent compiles or downloads at runtime and then invokes.
//   - anything the agent does through a library instead of a process (a python
//     agent calling shutil.rmtree). The kernel fence is the answer there, and
//     `--fence` turns it on for the whole session.
// The honest claim is: every agent that shells out, and that is nearly all of
// them, is supervised with zero integration.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <string>
#include <vector>
#include <set>
#include <fstream>
#include <sstream>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include "rules.h"
#include "cli_help.h"

using std::string;
using std::vector;

// The programs the compiled-in laws can refuse. `git` carries force-push,
// branch delete, hard reset, reflog expiry; the file movers carry the
// outside-the-tree deletes and the overwrite-with-nothing tricks.
static const char* kBaseline[] = {
  "git", "rm", "mv", "cp", "install", "dd", "shred", "truncate",
  "chmod", "chown", "ln", "rsync", "scp", "curl", "wget",
  nullptr
};

static string read_file(const string& p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return "";
  std::ostringstream ss; ss << f.rdbuf(); return ss.str();
}

static bool is_exec(const string& p) {
  struct stat st;
  return stat(p.c_str(), &st) == 0 && S_ISREG(st.st_mode) && access(p.c_str(), X_OK) == 0;
}

// Resolve a program against the PATH we were STARTED with, before the shim dir
// is prepended. Doing this at shim-writing time is what makes the shim safe to
// exec: it carries an absolute path and can never find itself.
static string which(const string& name, const string& path) {
  size_t i = 0;
  while (i <= path.size()) {
    size_t j = path.find(':', i);
    if (j == string::npos) j = path.size();
    string dir = path.substr(i, j - i);
    if (!dir.empty()) {
      string cand = dir + "/" + name;
      if (is_exec(cand)) return cand;
    }
    i = j + 1;
  }
  return "";
}

// Pull literal program names out of the head of each deny pattern. A pattern
// like "wrangler\\s+deploy\\b" names wrangler; one like ".*" names nothing and
// contributes nothing, which is correct — an unanchored pattern is not evidence
// about which program it is for.
static void names_from_guard(const string& guard, std::set<string>& out) {
  for (const string& obj : rbrules::parse_rule_objects(guard, "bash")) {
    string pat = rbrules::get_str(obj, "deny");
    if (pat.empty()) continue;
    size_t k = 0;
    while (k < pat.size() && (pat[k] == '^' || pat[k] == '(' || pat[k] == '\\')) {
      if (pat[k] == '\\' && k + 1 < pat.size() && (pat[k+1] == 'b' || pat[k+1] == 's')) k += 2;
      else k++;
    }
    string word;
    while (k < pat.size() && (isalnum((unsigned char)pat[k]) || pat[k] == '-' || pat[k] == '_' || pat[k] == '.')) {
      word += pat[k++];
    }
    // npx/npm/yarn style launchers carry the real program in the next word, so
    // shim the launcher too when a rule mentions one.
    if (word.size() >= 2) out.insert(word);
  }
}

static const char kHelp[] =
  "rabadon-run — supervise an agent rabadon knows nothing about.\n"
  "\n"
  "Every other binding asks the agent to cooperate: Claude Code hooks, Cursor\n"
  "hooks, or the JSON contract in docs/agent-contract.md. This one asks nothing.\n"
  "The agent runs with rabadon first on its PATH, so the dangerous programs it\n"
  "invokes are judged by the project's own laws before they run — whatever the\n"
  "agent is, and even if it has no hook system at all.\n"
  "\n"
  "usage:\n"
  "  rabadon run [--dir D] [--fence] [--deny-net] -- <agent cmd...>\n"
  "\n"
  "  --dir D      the project whose guard.json applies (default: cwd).\n"
  "  --fence      also run the agent inside the kernel sandbox, so writes\n"
  "               outside the project fail with EPERM even from a library call.\n"
  "  --deny-net   no outbound network from inside the fence (implies --fence).\n"
  "  --           everything after this is the agent's command, untouched.\n"
  "  -h, --help   this screen.\n"
  "\n"
  "example:\n"
  "  rabadon run -- aider --model gpt-4o\n"
  "  rabadon run -- my-own-agent.py --loop\n"
  "  rabadon run --fence -- npx some-agent\n"
  "\n"
  "not caught: a program invoked by absolute path skips PATH and skips the\n"
  "shim, and an agent that deletes through a library call never runs a program\n"
  "at all. --fence is the answer to both; see docs/agent-contract.md.\n";

int main(int argc, char** argv) {
  rb_help(argc, argv, kHelp);

  string dir = ".";
  bool fence = false, denyNet = false;
  vector<string> cmd;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--dir" && i + 1 < argc) dir = argv[++i];
    else if (a == "--fence") fence = true;
    else if (a == "--deny-net") { denyNet = true; fence = true; }
    else if (a == "--") { for (int j = i + 1; j < argc; j++) cmd.push_back(argv[j]); break; }
    else rb_unknown_flag("rabadon-run", a.c_str());
  }
  if (cmd.empty()) {
    fprintf(stderr, "rabadon run: nothing to run. Put the agent after `--`.\n"
                    "  rabadon run -- <your agent>\n");
    return 2;
  }

  { char wd[4096]; if (dir == "." && getcwd(wd, sizeof wd)) dir = wd; }

  // the two binaries this needs, resolved beside ourselves
  string self = argv[0];
  size_t sl = self.rfind('/');
  string selfDir = sl == string::npos ? string(".") : self.substr(0, sl);
  const string sandboxBin = selfDir + "/rabadon-sandbox";
  if (!is_exec(sandboxBin)) {
    fprintf(stderr, "rabadon run: rabadon-sandbox not found beside %s — the install is incomplete.\n", self.c_str());
    return 3;
  }

  const char* penv = getenv("PATH");
  const string origPath = penv ? penv : "/usr/bin:/bin:/usr/sbin:/sbin";

  std::set<string> names;
  for (const char** p = kBaseline; *p; p++) names.insert(*p);
  names_from_guard(read_file(dir + "/.rabadon/guard.json"), names);

  // the shim directory
  char tmpl[] = "/tmp/rabadon-run-XXXXXX";
  const char* shimDir = mkdtemp(tmpl);
  if (!shimDir) { perror("rabadon run: mkdtemp"); return 3; }

  int shimmed = 0;
  for (const string& n : names) {
    const string real = which(n, origPath);
    if (real.empty()) continue;                  // not installed here, nothing to shim
    if (real.rfind(shimDir, 0) == 0) continue;   // paranoia: never shim ourselves
    const string sp = string(shimDir) + "/" + n;
    FILE* f = fopen(sp.c_str(), "w");
    if (!f) continue;
    // The command is judged as the user typed it (`git push --force`), and the
    // absolute path is what actually execs. --no-fence because the fence, when
    // asked for, wraps the whole agent once rather than every command it runs.
    fprintf(f,
      "#!/bin/sh\n"
      "exec '%s' --no-fence --real '%s' --dir '%s' -- %s \"$@\"\n",
      sandboxBin.c_str(), real.c_str(), dir.c_str(), n.c_str());
    fclose(f);
    chmod(sp.c_str(), 0755);
    shimmed++;
  }

  setenv("PATH", (string(shimDir) + ":" + origPath).c_str(), 1);
  setenv("RABADON_RUN", "1", 1);   // a nested `rabadon run` can see it is inside one

  fprintf(stderr, "rabadon run — %d program(s) under the gate, project %s%s\n",
          shimmed, dir.c_str(), fence ? ", kernel fence on" : "");

  vector<string> full;
  if (fence) {
    full.push_back(sandboxBin);
    full.push_back("--dir"); full.push_back(dir);
    if (denyNet) full.push_back("--deny-net");
    full.push_back("--");
  }
  for (const string& c : cmd) full.push_back(c);

  vector<char*> a;
  for (auto& c : full) a.push_back((char*)c.c_str());
  a.push_back(nullptr);

  pid_t pid = fork();
  if (pid == 0) { execvp(a[0], a.data()); perror("rabadon run: exec"); _exit(127); }
  if (pid < 0) { perror("rabadon run: fork"); return 3; }
  int st = 0;
  waitpid(pid, &st, 0);

  // the shim directory is this run's, and it goes with it
  for (const string& n : names) unlink((string(shimDir) + "/" + n).c_str());
  rmdir(shimDir);

  if (WIFEXITED(st)) return WEXITSTATUS(st);
  return 1;
}
