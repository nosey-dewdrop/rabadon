// rabadon-sandbox — compile guard.json into a KERNEL-enforced sandbox and run
// a command inside it (C++17, zero deps).
//
// Why this exists: a hook is advice. The agent (or a subprocess it spawns, or
// an MCP tool, or a shell one-liner that dodges the matcher) can still touch a
// protected path or reach the network — the PreToolUse gate only sees the
// command it was handed. This binary closes that gap: it turns the SAME
// guard.json rules into an OS policy the kernel enforces, so a forbidden write
// or a denied network call fails with EPERM even when nothing asked rabadon
// first. Observation (Langfuse) cannot do this; a hook alone cannot do this.
//
//   macOS : a Seatbelt profile (`sandbox-exec -p`). protectedPaths -> deny
//           file-write* on each subpath; "network":"deny" -> deny network*.
//   Linux : bubblewrap (`bwrap`) — protected paths bound READ-ONLY over the
//           writable tree; --unshare-net when network is denied.
//
// Contract:
//   rabadon exec [--dir D] [--deny-net] -- <cmd...>
//   rabadon sandbox --print [--dir D] [--deny-net]     (emit the profile, run nothing)
//   rabadon sandbox --check                            (is a sandbox backend available?)
//
// Fail-closed where it matters: if rules ask for enforcement and NO backend
// exists, exec refuses (exit 3) rather than run unprotected — the one place
// rabadon must not fail open, because the caller asked for the kernel fence.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <deque>
#include <vector>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

#include "chain.h" // the ledger's one writer — a refusal here is evidence too
#include "rules.h" // the SAME deny rules the gate enforces, not a smaller set
#include "cli_help.h"

using std::string;
using std::vector;

static string read_file(const string& p) {
  struct stat st;
  if (stat(p.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return string();
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

static bool have(const string& bin) {
  string cmd = "command -v " + bin + " >/dev/null 2>&1";
  return system(cmd.c_str()) == 0;
}

// PRESENCE IS NOT CAPABILITY. `command -v bwrap` said "available — Linux
// bubblewrap" on a machine where every sandboxed command died with
// "bwrap: setting up uid map: Permission denied": Ubuntu 24.04+ blocks
// unprivileged user namespaces through AppArmor, so bwrap installs fine and
// cannot start. doctor reported a working kernel fence, `rabadon exec` refused
// nothing it claimed to, and the suite skipped every enforcement test. So the
// backend is asked to actually DO the smallest version of its job.
static bool backend_works() {
#if defined(__APPLE__)
  return system("sandbox-exec -p '(version 1)(allow default)' /usr/bin/true >/dev/null 2>&1") == 0;
#else
  return system("bwrap --dev-bind / / /bin/true >/dev/null 2>&1") == 0;
#endif
}

// extract each object's "match" string from guard.json protectedPaths — the
// same field the gate reads. These are regex in the gate; for the kernel we
// need literal path prefixes, so we take the longest leading literal (up to the
// first regex metacharacter) and anchor it. A rule like "^engine/.*\.cpp$" ->
// prefix "engine/"; "reports/gate/NABIZ.md" -> itself. A rule with no usable
// literal (starts with a metachar) is reported and skipped, never silently
// dropped — the caller sees exactly what the kernel will and will not fence.
static vector<string> protected_prefixes(const string& guard, vector<string>& skipped) {
  vector<string> out;
  size_t sec = guard.find("\"protectedPaths\"");
  if (sec == string::npos) return out;
  size_t arr = guard.find('[', sec);
  if (arr == string::npos) return out;
  int depth = 0; size_t objStart = 0;
  for (size_t i = arr; i < guard.size(); i++) {
    char c = guard[i];
    if (c == '"') { for (i++; i < guard.size(); i++) { if (guard[i] == '\\') i++; else if (guard[i] == '"') break; } continue; }
    if (c == '{') { if (depth == 0) objStart = i; depth++; }
    else if (c == '}') {
      if (depth == 1) {
        string obj = guard.substr(objStart, i - objStart + 1);
        size_t mk = obj.find("\"match\"");
        if (mk != string::npos) {
          size_t q = obj.find('"', obj.find(':', mk) + 1);
          if (q != string::npos) {
            string m;
            for (size_t j = q + 1; j < obj.size(); j++) {
              char ch = obj[j];
              if (ch == '\\' && j + 1 < obj.size()) { m += obj[j + 1]; j++; continue; }
              if (ch == '"') break;
              m += ch;
            }
            // strip a leading ^ anchor, then take the literal prefix
            string lit; size_t k = 0;
            if (!m.empty() && m[0] == '^') k = 1;
            for (; k < m.size(); k++) {
              char ch = m[k];
              if (strchr(".*+?()[]{}|\\$", ch)) break;
              lit += ch;
            }
            if (lit.empty()) skipped.push_back(m);
            else out.push_back(lit);
          }
        }
      }
      depth--;
      if (depth == 0 && i + 1 < guard.size()) { size_t n = guard.find_first_not_of(" \t\r\n", i + 1); if (n != string::npos && guard[n] == ']') break; }
    }
  }
  return out;
}

static bool guard_denies_net(const string& guard) {
  size_t k = guard.find("\"network\"");
  if (k == string::npos) return false;
  size_t q = guard.find('"', guard.find(':', k) + 1);
  if (q == string::npos) return false;
  return guard.compare(q + 1, 4, "deny") == 0;
}

// resolve a project-relative prefix to an absolute subpath for the profile
static string abspath(const string& dir, const string& rel) {
  if (!rel.empty() && rel[0] == '/') return rel;
  string d = dir;
  while (d.size() > 1 && d.back() == '/') d.pop_back();
  return d + "/" + rel;
}

static string seatbelt_profile(const string& dir, const vector<string>& prefixes, bool denyNet) {
  string p =
    "(version 1)\n"
    "(allow default)\n"
    "; rabadon: kernel-enforced guard.json — protected paths are read-only,\n"
    "; the denied writes fail with EPERM even if the hook was bypassed.\n";
  for (const string& pre : prefixes) {
    string ap = abspath(dir, pre);
    // deny writes to the subtree (or the single file); reads stay allowed
    p += "(deny file-write* (subpath \"" + ap + "\"))\n";
    p += "(deny file-write* (literal \"" + ap + "\"))\n";
  }
  if (denyNet) {
    p += "(deny network*)\n";
  }
  return p;
}

// Everything about this argv that has to face the law.
//
// Flattening argv into one line is not enough, and the way it fails is the
// dangerous way: the guard's regex rules search anywhere in a string and still
// match, while the three compiled-in laws are STRUCTURAL — they tokenize and
// ask what binary is being invoked, deliberately, so that
// `echo "git push --force origin main"` stays an echo with one argument. Join
// `sh -c "git push --force origin main"` into a line and that parser reads a
// shell invocation, which is true and useless: the loud user rules fire and
// the floor underneath them does not. Measured, not guessed — the gate returns
// 2 on the bare command and 0 on the joined one.
//
// So the shell wrapper is unwrapped. `sh -c X`, `bash -c X`, `zsh -c X` are
// running X, and X is judged as the command it is.
// An argv element is ONE word, and joining argv with spaces threw that away.
// `rabadon exec -- git -c 'alias.x=push --force' x origin main` handed the rule
// engine the text `git -c alias.x=push --force x origin main`, where the value
// of `-c` is `alias.x=push` and the `--force` beside it reads as one of git's
// own leading options — so the alias bound `x` to a plain push and exec ran the
// force-push the hook refuses. Everything downstream judges TEXT, so the text
// has to say what argv said.
//
// Only an element that NEEDS quoting gets it: for ordinary argv the joined
// string is byte for byte what it was before, so no rule a project already
// wrote changes meaning. The parser drops quotes when it builds both the argv
// and the surface, so a quoted element does not change what a deny regex sees
// either — it only stops one word from becoming two.
static string quote_arg(const string& a) {
  bool bare = !a.empty();
  for (size_t i = 0; i < a.size() && bare; i++) {
    const char c = a[i];
    bare = isalnum((unsigned char)c) || c == '.' || c == '_' || c == '-' || c == '=' ||
           c == '/' || c == ':' || c == '+' || c == '@' || c == ',' || c == '%' ||
           c == '^' || c == '~' || c == '*' || c == '?';
  }
  if (bare) return a;
  string out = "'";
  for (size_t i = 0; i < a.size(); i++) {
    if (a[i] == '\'') out += "'\\''";   // close, escape the literal quote, reopen
    else out += a[i];
  }
  out += "'";
  return out;
}

static vector<string> judge_targets(const vector<string>& cmd) {
  vector<string> out;
  string joined;
  for (size_t i = 0; i < cmd.size(); i++) { if (i) joined += " "; joined += quote_arg(cmd[i]); }
  if (!joined.empty()) out.push_back(joined);

  for (size_t i = 0; i + 2 < cmd.size() + 1 && i < cmd.size(); i++) {
    const string& a = cmd[i];
    size_t slash = a.rfind('/');
    const string base = slash == string::npos ? a : a.substr(slash + 1);
    const bool isShell = base == "sh" || base == "bash" || base == "zsh" || base == "dash" || base == "ksh";
    if (isShell && i + 2 < cmd.size() + 1) {
      for (size_t j = i + 1; j < cmd.size(); j++) {
        if (cmd[j] == "-c" && j + 1 < cmd.size()) { out.push_back(cmd[j + 1]); break; }
        if (!cmd[j].empty() && cmd[j][0] != '-') break; // the script arg, not -c
      }
    }
  }
  return out;
}

static string json_escape(const string& s) {
  string out;
  for (unsigned char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); out += b; }
        else out += (char)c;
    }
  }
  return out;
}

// A refusal that leaves no trace cannot be audited, and `rabadon audit` is the
// product's whole claim about its own honesty. exec wrote nothing at all
// before this: the ledger showed the gate's refusals and was silent about
// every command exec waved through OR stopped. Same chained writer as the
// gate and the loop (chain.h), same event shape, so `rabadon usage` counts an
// exec refusal exactly like a hook refusal.
static void emit_refusal(const string& dir, const string& id, const string& why, const string& detail) {
  const char* rd = getenv("RABADON_DIR");
  const char* home = getenv("HOME");
  const string rdir = (rd && rd[0]) ? string(rd) : string(home ? home : ".") + "/.rabadon";
  mkdir(rdir.c_str(), 0755);
  mkdir((rdir + "/spool").c_str(), 0755);

  char day[16]; { time_t t = time(nullptr); struct tm tmv; gmtime_r(&t, &tmv); strftime(day, 16, "%Y-%m-%d", &tmv); }
  struct timeval tv; gettimeofday(&tv, nullptr);
  const long long nowms = (long long)tv.tv_sec * 1000 + tv.tv_usec / 1000;

  size_t cs = dir.rfind('/');
  const string project = cs == string::npos ? dir : dir.substr(cs + 1);
  const string spool = rdir + "/spool/" + string(day) + ".jsonl";
  const string run = "ex-" + std::to_string(nowms % 100000000) + "-" + std::to_string(getpid());

  // The ":exec" on the pipe is the SURFACE the refusal came through, not a
  // project of its own — rabadon-export keys one trace per pipe and needs it.
  // The ledger is what must fold it: stats.cpp project_of() cuts at the last
  // colon, so an exec refusal lands on the same row as the repo's hook
  // refusals. Do not answer a split row by dropping this suffix here.
  auto emit = [&](int seq, const string& ev, const string& extra) {
    char buf[64]; snprintf(buf, sizeof buf, "%d", seq);
    string body = "{\"v\":1,\"seq\":" + string(buf) + ",\"ts\":" + std::to_string(nowms) +
                  ",\"run\":\"" + run + "\",\"pipe\":\"" + json_escape(project) + ":exec\",\"ev\":\"" + ev + "\"," + extra;
    rbchain::append(spool, body);
  };
  emit(1, "CHECK_FAIL", "\"step\":\"exec\",\"mode\":\"enforce\",\"fails\":[{\"check\":\"" + json_escape(id) +
                        "\",\"why\":\"" + json_escape(detail + " — " + why) + "\"}]");
  emit(2, "STOP", "\"reason\":\"BLOCKED\",\"rule\":\"" + json_escape(id) +
                  "\",\"sid\":\"exec\",\"detail\":\"" + json_escape(detail) + "\"");
}

static const char* kHelp =
  "rabadon-sandbox — run a command under the kernel's own confinement.\n"
  "macOS Seatbelt (sandbox-exec) or Linux bubblewrap (bwrap). The profile is\n"
  "compiled here and printable, so what is allowed can be read before it runs.\n"
  "\n"
  "usage:\n"
  "  rabadon-sandbox [--dir D] [--deny-net] -- <cmd...>   run <cmd> confined\n"
  "  rabadon-sandbox --print [--dir D] [--deny-net]       print the compiled profile\n"
  "  rabadon-sandbox --check                              is a backend available?\n"
  "\n"
  "  --dir D      the only directory the command may write (default: cwd).\n"
  "  --deny-net   no outbound network from inside the sandbox.\n"
  "  --           everything after this is the command, untouched. rabadon reads\n"
  "               no flags past it, so `-- pytest --help` runs pytest's help.\n"
  "  -h, --help   this screen.\n"
  "\n"
  "example:\n"
  "  rabadon-sandbox --dir ~/src/myrepo --deny-net -- npm test\n";

int main(int argc, char** argv) {
  rb_help(argc, argv, kHelp);

  string dir = ".";
  // --no-fence and --real exist for ONE caller: the PATH shims `rabadon run`
  // writes around an agent it knows nothing about. A shim judges one command
  // and then becomes the real binary, so it must not build a kernel profile
  // per command (the fence goes around the whole agent, once) and it must exec
  // the ORIGINAL binary rather than search PATH again, which would find the
  // shim and recurse forever. The command is still JUDGED as the user typed it,
  // `git push --force`, not `/usr/bin/git push --force`, because that is the
  // text every rule in every guard.json was written against.
  string realBin;
  bool noFence = false;
  bool denyNet = false, doPrint = false, doCheck = false;
  vector<string> cmd;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--dir" && i + 1 < argc) dir = argv[++i];
    else if (a == "--real" && i + 1 < argc) realBin = argv[++i];
    else if (a == "--no-fence") noFence = true;
    else if (a == "--deny-net") denyNet = true;
    else if (a == "--print") doPrint = true;
    else if (a == "--check") doCheck = true;
    else if (a == "--") { for (int j = i + 1; j < argc; j++) cmd.push_back(argv[j]); break; }
    // anything else is refused here, BEFORE the `--`: a flag rabadon does not
    // know must never be mistaken for part of the sandboxed command. `-h` used
    // to fall through and exit 2 with "nothing to run".
    else rb_unknown_flag("rabadon-sandbox", a.c_str());
  }

  // backend detection: installed, AND able to start
#if defined(__APPLE__)
  const bool installed = have("sandbox-exec");
  const char* backendName = "macOS Seatbelt (sandbox-exec)";
#else
  const bool installed = have("bwrap");
  const char* backendName = "Linux bubblewrap (bwrap)";
#endif
  const bool backend = installed && backend_works();

  // the difference between "not installed" and "installed but the kernel will
  // not let it start" is the difference between two completely different fixes
  auto why_not = [&]() {
    if (!installed) {
#if defined(__APPLE__)
      return "sandbox-exec is missing on this macOS";
#else
      return "bwrap is not installed — apt install bubblewrap";
#endif
    }
#if defined(__APPLE__)
    return "sandbox-exec is present but refused a trivial profile";
#else
    return "bwrap is installed but the kernel refused to start it (\"setting up uid map: "
           "Permission denied\" = unprivileged user namespaces are restricted, the default on "
           "Ubuntu 24.04+). allow them with: sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0";
#endif
  };

  if (doCheck) {
    if (backend) { printf("rabadon sandbox: available — %s\n", backendName); return 0; }
    printf("rabadon sandbox: NO usable kernel backend — %s\n", why_not());
    return 1;
  }

  { char rp[4096]; if (realpath(dir.c_str(), rp)) dir = rp; }
  const string guard = read_file(dir + "/.rabadon/guard.json");
  vector<string> skipped;
  vector<string> prefixes = protected_prefixes(guard, skipped);
  bool netDeny = denyNet || guard_denies_net(guard);

  for (const string& s : skipped)
    fprintf(stderr, "rabadon sandbox: rule \"%s\" has no literal path prefix — the KERNEL cannot fence a pure-regex path; the hook still checks it.\n", s.c_str());

#if defined(__APPLE__)
  string profile = seatbelt_profile(dir, prefixes, netDeny);
#else
  string profile; // Linux builds the bwrap argv directly below
#endif

  if (doPrint) {
#if defined(__APPLE__)
    fwrite(profile.data(), 1, profile.size(), stdout);
#else
    printf("# bubblewrap plan for %s\n", dir.c_str());
    for (const string& pre : prefixes) printf("--ro-bind %s %s\n", abspath(dir, pre).c_str(), abspath(dir, pre).c_str());
    if (netDeny) printf("--unshare-net\n");
#endif
    return 0;
  }

  if (cmd.empty()) { fprintf(stderr, "rabadon sandbox: nothing to run — pass a command after --\n"); return 2; }

  // ---------- the project's law, BEFORE anything runs ----------
  // exec used to compile only protectedPaths and network into a kernel policy
  // and never look at the bash deny rules, so the gate refused a command and
  // `rabadon exec` ran the identical string to completion, exit 0, no ledger
  // entry. That made exec a documented bypass of the thing it is sold as the
  // hard version of. It judges the command with rules.h now — the same parser,
  // the same segmentation, the same three compiled-in laws — so exec is a
  // SUPERSET of the gate: everything the hook refuses, plus a kernel fence.
  //
  // There is no watch mode here on purpose. The hook observes an agent that
  // did not ask to be supervised; `rabadon exec` is someone explicitly asking
  // to run inside the boundary. Letting watch mode wave a denied command
  // through would just move the bypass one flag to the left.
  // Path-resolving laws ("this rm -rf lands outside the project tree") are
  // resolved against the directory the command will ACTUALLY run in, which is
  // this process's cwd — not --dir, which only says whose guard.json to load.
  // Judging one tree and executing in another is how a correct-looking refusal
  // protects a directory nobody was working in.
  string runCwd = dir;
  { char wd[4096]; if (getcwd(wd, sizeof wd)) runCwd = wd; }

  rbrules::Verdict v;
  for (const string& target : judge_targets(cmd)) {
    v = rbrules::judge_command(guard, target, runCwd);
    if (v.refused) break;
  }
  if (v.refused) {
    emit_refusal(dir, v.id, v.why, v.detail);
    fprintf(stderr,
      "rabadon REFUSED this command — it breaks the project's own law.\n"
      "Rule: %s — %s\n%s\n"
      "exec enforces every rule the hook enforces; it is not a way around them.\n"
      "(user override: add \"%s\" to disabled[] in .rabadon/guard.json)\n",
      v.id.c_str(), v.why.c_str(), v.detail.c_str(), v.id.c_str());
    return 2;
  }

  // A shim has already been judged above; the fence is somebody else's job.
  if (noFence) {
    vector<string> run = cmd;
    if (!realBin.empty()) run[0] = realBin;
    vector<char*> bare;
    for (auto& c : run) bare.push_back((char*)c.c_str());
    bare.push_back(nullptr);
    execv(run[0].c_str(), bare.data());
    // execv, not execvp: the shim dir is first on PATH and a search would find
    // this shim again. A missing real binary is the caller's problem to report.
    fprintf(stderr, "rabadon: could not run %s: %s\n", run[0].c_str(), strerror(errno));
    return 127;
  }

  const bool wantsEnforcement = !prefixes.empty() || netDeny;
  if (wantsEnforcement && !backend) {
    fprintf(stderr,
      "rabadon sandbox: guard.json asks for kernel enforcement but %s is not usable here — REFUSING to run unprotected.\n"
      "  %s\n",
      backendName, why_not());
    return 3;
  }

  // no rules AND no need for a fence -> run bare (we only get here when
  // !wantsEnforcement, since the enforcement-without-backend case exited above)
  if (!wantsEnforcement) {
    vector<char*> bare;
    for (auto& c : cmd) bare.push_back((char*)c.c_str());
    bare.push_back(nullptr);
    execvp(cmd[0].c_str(), bare.data());
    perror("rabadon sandbox: exec failed");
    return 127;
  }

  // build argv for the backend
  vector<char*> args;
#if defined(__APPLE__)
  args.push_back((char*)"sandbox-exec");
  args.push_back((char*)"-p");
  args.push_back((char*)profile.c_str());
  for (auto& c : cmd) args.push_back((char*)c.c_str());
  args.push_back(nullptr);
  execvp("sandbox-exec", args.data());
#else
  // The argv holds raw pointers INTO these strings, so the storage must never
  // move. A vector<string> reallocates as it grows and every pointer taken from
  // an earlier element dangles — with two protected paths bwrap was handed
  // freed memory. A deque never moves an element it has already placed.
  std::deque<string> hold;
  args.push_back((char*)"bwrap");
  args.push_back((char*)"--dev-bind"); args.push_back((char*)"/"); args.push_back((char*)"/");
  args.push_back((char*)"--die-with-parent");
  for (const string& pre : prefixes) {
    hold.push_back(abspath(dir, pre));
    char* ap = (char*)hold.back().c_str();
    args.push_back((char*)"--ro-bind"); args.push_back(ap); args.push_back(ap);
  }
  if (netDeny) args.push_back((char*)"--unshare-net");
  for (auto& c : cmd) args.push_back((char*)c.c_str());
  args.push_back(nullptr);
  execvp("bwrap", args.data());
#endif

  perror("rabadon sandbox: exec failed");
  return 127;
}
