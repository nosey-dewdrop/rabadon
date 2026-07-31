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
#include <fstream>
#include <sstream>
#include <string>
#include <deque>
#include <vector>
#include <sys/stat.h>
#include <unistd.h>

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

int main(int argc, char** argv) {
  string dir = ".";
  bool denyNet = false, doPrint = false, doCheck = false;
  vector<string> cmd;
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (a == "--dir" && i + 1 < argc) dir = argv[++i];
    else if (a == "--deny-net") denyNet = true;
    else if (a == "--print") doPrint = true;
    else if (a == "--check") doCheck = true;
    else if (a == "--") { for (int j = i + 1; j < argc; j++) cmd.push_back(argv[j]); break; }
    else if (a == "--help") {
      printf("usage:\n"
             "  rabadon-sandbox [--dir D] [--deny-net] -- <cmd...>   run <cmd> in the kernel sandbox\n"
             "  rabadon-sandbox --print [--dir D] [--deny-net]        print the compiled profile\n"
             "  rabadon-sandbox --check                               is a backend available?\n");
      return 0;
    }
  }

  // backend detection
#if defined(__APPLE__)
  const bool backend = have("sandbox-exec");
  const char* backendName = "macOS Seatbelt (sandbox-exec)";
#else
  const bool backend = have("bwrap");
  const char* backendName = "Linux bubblewrap (bwrap)";
#endif

  if (doCheck) {
    if (backend) { printf("rabadon sandbox: available — %s\n", backendName); return 0; }
    printf("rabadon sandbox: NO kernel backend on this platform "
#if defined(__APPLE__)
           "(sandbox-exec missing)\n");
#else
           "(install bubblewrap: apt install bubblewrap)\n");
#endif
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

  const bool wantsEnforcement = !prefixes.empty() || netDeny;
  if (wantsEnforcement && !backend) {
    fprintf(stderr,
      "rabadon sandbox: guard.json asks for kernel enforcement but no backend is available (%s) — REFUSING to run unprotected.\n"
#if defined(__APPLE__)
      "  (sandbox-exec is missing on this macOS)\n",
#else
      "  install bubblewrap: apt install bubblewrap\n",
#endif
      backendName);
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
