// gitcfg.h — the config a git command will really see. (C++17)
//
// WHY THIS FILE EXISTS. The force-push law learned that `remote.<name>.push`
// and `push.default` decide which refs a push writes, and it read them from ONE
// place: the `-c key=value` pairs on the command line. It said so out loud:
//
//   NAMED LIMIT: the same two keys can also be set in .git/config,
//   ~/.gitconfig or /etc/gitconfig, and none of those are in this command
//   line. This law judges what the LINE says. Reading only the repo's file
//   would report the other two as absent, which is a worse answer than a
//   named limit.
//
// The reason given argues for reading all three, not for reading none. Two
// ordinary commands, one turn apart, and the law's fallback answers a question
// nobody asked:
//
//   git config remote.origin.push refs/heads/scratch:refs/heads/main
//   git push --force origin
//
// Neither line contains the word `main`, so a project's deny regex misses both;
// the compiled law read .git/HEAD, saw `scratch`, and allowed the second one.
// Measured against the gate before this file existed: exit 0. The
// `push.default matching` spelling of the same pair: exit 0.
//
// SO THE FILES ARE READ, AND NOTHING IS EXECUTED TO READ THEM. `git config
// --get-all` would have been the short way and it is the wrong way: the gate
// runs on every tool call, judging a command must never RUN one (the suites put
// a fake git first on PATH and assert it was never called), and shelling out to
// a binary named by PATH is the one thing a security boundary may not do while
// deciding whether to allow a command that names the same binary. This is a
// reader, not a runner.
//
// WHAT GIT READS, IN THIS ORDER (git-config(1), and every line of it measured
// against git 2.39.5 with `push --dry-run --porcelain` — the cases are in
// native/push_config_file_test.sh):
//   /etc/gitconfig                 system; skipped when GIT_CONFIG_NOSYSTEM is
//                                  set, replaced by $GIT_CONFIG_SYSTEM
//   $XDG_CONFIG_HOME/git/config    or ~/.config/git/config
//   ~/.gitconfig                   $GIT_CONFIG_GLOBAL replaces BOTH of these
//   .git/config                    the repo
//   .git/config.worktree           only when extensions.worktreeConfig is set
//   -c key=value                   the command line, read by the ONE parser
//                                  (cmdtext.h) and appended last
//
// TWO FACTS THAT DECIDE THE SHAPE OF THIS READER, BOTH MEASURED:
//   * remote.<name>.push ACCUMULATES. A value in ~/.gitconfig and a value in
//     .git/config are BOTH pushed, and a `-c` on the line is pushed on top of
//     both. So a reader that stops at the first file that answers, or lets the
//     nearer file replace the farther one, reads half of the command.
//   * push.default is single-valued and the LAST value wins: global=matching
//     with repo=simple is not matching. So values come back in git's order and
//     the caller takes back() — which is why this returns a list and not an
//     answer.
//
// AN INCLUDE IS FOLLOWED, AND A CONDITIONAL ONE IS FOLLOWED WITHOUT ITS
// CONDITION. `[include] path = x` is spliced in where it appears, so the
// recursion happens mid-scan and the ORDER above survives it. `[includeIf
// "gitdir:..."] path = x` is followed too, and its condition is NOT evaluated:
// deciding `gitdir:`/`onbranch:` needs a wildmatch, this repo has no wildmatch,
// and it is not growing a second glob engine for one predicate. That is a
// deliberate over-refusal with a named price — a conditional include that binds
// a push refspec onto a shared branch is refused even where git would not apply
// it — and the twin in the test file pays it: an includeIf carrying an ordinary
// identity refuses nothing, which is what every real one carries.
//
// WHAT IS STILL NOT READ, NAMED AND NOT GUESSED AT: the process ENVIRONMENT of
// the command. GIT_CONFIG_COUNT/GIT_CONFIG_KEY_n bind config from it, and an
// env prefix on the command itself rebinds which files git reads. This process
// reads its OWN environment for HOME/XDG_CONFIG_HOME/GIT_CONFIG_SYSTEM/
// GIT_CONFIG_GLOBAL, because the shell that will run the command inherits it —
// a prefix written on the line is a different source and is the next one to
// close.
//
// THE WALK IS BOUNDED. This runs inside a hook whose latency is a published
// number, and an unbounded include chain or a pathological file is a hang in
// the one place that must not hang: 8 levels of include, 32 files, 4000 lines
// per file, 64 values, and a file bigger than 4 MiB is not a config file.

#pragma once

#include <cctype>
#include <cstdlib>
#include <fstream>
#include <string>
#include <sys/stat.h>
#include <vector>

#include "cmdtext.h"
#include "pathres.h"

namespace rbgitcfg {

using std::string;
using std::vector;

// A value and WHERE it was read from. The origin is not decoration: a refusal
// that says "force-push to shared branch 'main'" when the line says neither
// `main` nor a refspec is a refusal the operator cannot act on. It has to name
// the file that decided.
struct Value {
  string text;
  string origin;
};

struct Limits {
  int files = 0;
  int values = 0;
};

// git's own boolean reading of an environment variable: unset or empty is
// false, "0"/"false"/"no"/"off" are false, anything else is true.
inline bool env_true(const char* name) {
  const char* v = getenv(name);
  if (!v || !*v) return false;
  string s(v);
  for (size_t i = 0; i < s.size(); i++) s[i] = rbtext::lower_c(s[i]);
  return !(s == "0" || s == "false" || s == "no" || s == "off");
}

inline string env_str(const char* name) {
  const char* v = getenv(name);
  return (v && *v) ? string(v) : string();
}

// ---------- one line of a config file ----------------------------------------
// The header. Three spellings, and the third folds differently from the second:
//   [remote "origin"]   subsection kept as written (case-SENSITIVE)
//   [remote.ORIGIN]     the deprecated dotted form, subsection LOWER-CASED —
//                       measured: this file supplies origin's push refspec,
//                       while `-c remote.ORIGIN.push=...` does not, because on
//                       the command line the subsection keeps its case. Two
//                       surfaces, two rules, both measured, one fold function.
//
// The closing bracket is the first one OUTSIDE quotes, not the last one on the
// line: `[q "x]y"]` is a subsection containing a bracket (measured — real git
// reads q.x]y.k out of it), and a header may be followed by a variable on the
// same line (`[a "b"] c = d`, measured), so where the header ENDS is an answer
// the caller needs and not an internal detail.
inline bool parse_header(const string& line, string& sec, string& sub, size_t& end) {
  size_t close = string::npos;
  bool q2 = false;
  for (size_t i = 1; i < line.size(); i++) {
    if (line[i] == '\\' && i + 1 < line.size()) { i++; continue; }
    if (line[i] == '"') { q2 = !q2; continue; }
    if (line[i] == ']' && !q2) { close = i; break; }
  }
  if (close == string::npos || close < 1) return false;
  end = close;
  const string body = line.substr(1, close - 1);
  const size_t q = body.find('"');
  if (q == string::npos) {
    const size_t dot = body.find('.');
    if (dot == string::npos) {
      sec = body;
      sub.clear();
    } else {
      sec = body.substr(0, dot);
      sub = body.substr(dot + 1);
      for (size_t i = 0; i < sub.size(); i++) sub[i] = rbtext::lower_c(sub[i]);
    }
  } else {
    sec = body.substr(0, q);
    while (!sec.empty() && (sec.back() == ' ' || sec.back() == '\t')) sec.pop_back();
    sub.clear();
    for (size_t i = q + 1; i < body.size(); i++) {
      if (body[i] == '\\' && i + 1 < body.size()) { sub += body[++i]; continue; }
      if (body[i] == '"') break;
      sub += body[i];
    }
  }
  while (!sec.empty() && (sec[0] == ' ' || sec[0] == '\t')) sec.erase(0, 1);
  return !sec.empty();
}

// The value side of `name = value`. Quotes suspend the comment characters and
// the whitespace handling; a trailing backslash continues onto the next line;
// and the escapes git defines are the only ones (git-config(1): \n \t \b \" \\).
//
// WHITESPACE IS NOT COPIED, IT IS NORMALIZED, and that was measured rather than
// assumed: `k = a<TAB>b` comes back from real git as `a b`, and `k = a b   c `
// as `a b   c` — so an unquoted tab becomes ONE space, a run of spaces keeps
// its length, and the trailing run is dropped. A reader that copied the tab
// through would answer a different string than git for the same file, which for
// a refspec is a different destination branch.
inline string parse_value(const string& rest, std::ifstream& f, int& lines) {
  string src = rest, out;
  size_t i = 0;
  bool quoted = false;
  string trailing;   // the pending whitespace run, dropped if the line ends here
  for (;;) {
    while (i < src.size()) {
      const char c = src[i];
      if (c == '"') { quoted = !quoted; i++; continue; }
      if (c == '\\') {
        if (i + 1 >= src.size()) {                   // a continued line
          if (++lines > 4000) return out;
          string next;
          if (!std::getline(f, next)) return out;
          while (!next.empty() && (next.back() == '\r')) next.pop_back();
          src = next;
          i = 0;
          continue;
        }
        const char e = src[i + 1];
        i += 2;
        out += trailing; trailing.clear();
        switch (e) {
          case 'n': out += '\n'; break;
          case 't': out += '\t'; break;
          case 'b': out += '\b'; break;
          default:  out += e;    break;   // \" and \\ land here as themselves
        }
        continue;
      }
      if (!quoted && (c == '#' || c == ';')) return out;   // a comment ends it
      if (!quoted && isspace((unsigned char)c)) { trailing += ' '; i++; continue; }
      out += trailing; trailing.clear();
      out += c;
      i++;
    }
    return out;
  }
}

inline void read_file(const string& path, const string& want, const string& label,
                      vector<Value>& out, int depth, Limits& lim);

// `include.path` / `includeIf.<cond>.path`: the value is a path, relative to
// the directory of the file that named it, with a leading `~/` meaning the
// user's home. It is spliced in WHERE IT APPEARS, so this recursion sits in the
// middle of the scan and the order of values survives.
inline void follow_include(const string& value, const string& fromFile, const string& want,
                           const string& label, vector<Value>& out, int depth, Limits& lim) {
  if (value.empty()) return;
  string p = value;
  if (p[0] == '~') {
    const string home = rbpath::real_home();
    if (home.empty()) return;
    p = home + p.substr(1);
  } else if (p[0] != '/') {
    const size_t slash = fromFile.rfind('/');
    p = (slash == string::npos ? string(".") : fromFile.substr(0, slash)) + "/" + p;
  }
  read_file(p, want, label, out, depth + 1, lim);
}

inline void read_file(const string& path, const string& want, const string& label,
                      vector<Value>& out, int depth, Limits& lim) {
  if (depth > 8 || lim.files >= 32 || out.size() >= 64) return;
  struct stat st;
  if (stat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return;
  if (st.st_size > (4 << 20)) return;              // not a config file
  std::ifstream f(path.c_str());
  if (!f) return;
  lim.files++;
  string sec, sub, line;
  int lines = 0;
  while (std::getline(f, line)) {
    if (++lines > 4000 || out.size() >= 64) break;
    while (!line.empty() && (line.back() == '\r')) line.pop_back();
    size_t i = 0;
    while (i < line.size() && (line[i] == ' ' || line[i] == '\t')) i++;
    if (i >= line.size()) continue;
    if (line[i] == '#' || line[i] == ';') continue;
    if (line[i] == '[') {
      size_t end = 0;
      if (!parse_header(line.substr(i), sec, sub, end)) continue;
      i += end + 1;                                // a variable may follow it here
      while (i < line.size() && (line[i] == ' ' || line[i] == '\t')) i++;
      if (i >= line.size() || line[i] == '#' || line[i] == ';') continue;
    }
    if (sec.empty()) continue;                     // a variable outside any section
    size_t n = i;
    while (n < line.size() && (isalnum((unsigned char)line[n]) || line[n] == '-')) n++;
    const string name = line.substr(i, n - i);
    if (name.empty()) continue;
    while (n < line.size() && (line[n] == ' ' || line[n] == '\t')) n++;
    string value = "true";                         // a bare key is a true boolean
    if (n < line.size() && line[n] == '=') {
      size_t v = n + 1;
      while (v < line.size() && (line[v] == ' ' || line[v] == '\t')) v++;
      value = parse_value(line.substr(v), f, lines);
    } else if (n < line.size() && line[n] != '#' && line[n] != ';') {
      continue;                                    // not `name` and not `name =`
    }
    const string key = rbtext::config_key(sec, sub, name);
    if (key == want) out.push_back({value, label});
    if (key == "include.path")
      follow_include(value, path, want, label + " -> " + value, out, depth, lim);
    else if (key.size() > 15 && key.compare(0, 10, "includeif.") == 0 &&
             key.compare(key.size() - 5, 5, ".path") == 0)
      follow_include(value, path, want,
                     label + " -> " + value + " (an includeIf whose condition this law does "
                                              "not evaluate)",
                     out, depth, lim);
  }
}

// ---------- the files, in git's order ----------------------------------------
// The repo is named by its GIT DIR, which is what pathres.h resolves for the
// line (`git -C other`, `--git-dir`, a worktree's .git FILE). A linked worktree
// keeps only its own config.worktree there and reads the shared one through the
// `commondir` pointer, so that pointer is followed — otherwise a push judged
// from a worktree would find no config at all and fall back to HEAD, which is
// the bug this file exists to close, one directory over.
inline string common_dir(const string& gitDir) {
  std::ifstream f((gitDir + "/commondir").c_str());
  if (!f) return gitDir;
  string p;
  std::getline(f, p);
  while (!p.empty() && (p.back() == '\n' || p.back() == '\r' || p.back() == ' ')) p.pop_back();
  if (p.empty()) return gitDir;
  const string abs = rbpath::resolve_real(rbpath::lexical_abs(p, gitDir));
  return abs.empty() ? gitDir : abs;
}

inline void config_files(const string& gitDir, vector<std::pair<string, string> >& files) {
  const string sys = env_str("GIT_CONFIG_SYSTEM");
  if (!env_true("GIT_CONFIG_NOSYSTEM"))
    files.push_back(std::make_pair(sys.empty() ? string("/etc/gitconfig") : sys,
                                   sys.empty() ? string("in /etc/gitconfig")
                                               : string("in $GIT_CONFIG_SYSTEM")));
  const string glob = env_str("GIT_CONFIG_GLOBAL");
  if (!glob.empty()) {
    files.push_back(std::make_pair(glob, string("in $GIT_CONFIG_GLOBAL")));
  } else {
    const string home = rbpath::real_home();
    const string xdg = env_str("XDG_CONFIG_HOME");
    if (!xdg.empty())
      files.push_back(std::make_pair(xdg + "/git/config", string("in $XDG_CONFIG_HOME/git/config")));
    else if (!home.empty())
      files.push_back(std::make_pair(home + "/.config/git/config", string("in ~/.config/git/config")));
    if (!home.empty()) files.push_back(std::make_pair(home + "/.gitconfig", string("in ~/.gitconfig")));
  }
  if (gitDir.empty()) return;
  const string common = common_dir(gitDir);
  files.push_back(std::make_pair(common + "/config", string("in .git/config")));
  // measured: .git/config.worktree decides a push ONLY with the extension set,
  // and is ignored without it. Reading it either way would be a refusal a real
  // git never earns.
  vector<Value> ext;
  Limits lim;
  read_file(common + "/config", "extensions.worktreeconfig", "in .git/config", ext, 0, lim);
  if (!ext.empty() && ext.back().text != "false" && ext.back().text != "0" &&
      ext.back().text != "no" && ext.back().text != "off")
    files.push_back(std::make_pair(gitDir + "/config.worktree", string("in .git/config.worktree")));
}

// EVERY value git will see for `wantRaw` in this repo, in git's own order:
// the files first, the `-c` pairs on THIS line last. Multi-valued keys are all
// of it; single-valued keys are back().
inline void values(const vector<rbtext::Word>& t, size_t gi, size_t sub, const string& gitDir,
                   const string& wantRaw, vector<Value>& out) {
  const string want = rbtext::fold_config_key(wantRaw);
  vector<std::pair<string, string> > files;
  config_files(gitDir, files);
  Limits lim;
  for (size_t i = 0; i < files.size(); i++)
    read_file(files[i].first, want, files[i].second, out, 0, lim);
  vector<string> line;
  rbtext::git_config_values(t, gi, sub, want, line);
  for (size_t i = 0; i < line.size(); i++)
    out.push_back({line[i], "on this command line"});
}

// the single-valued reading: git's last definition wins.
inline bool last_value(const vector<rbtext::Word>& t, size_t gi, size_t sub, const string& gitDir,
                       const string& wantRaw, Value& v) {
  vector<Value> all;
  values(t, gi, sub, gitDir, wantRaw, all);
  if (all.empty()) return false;
  v = all.back();
  return true;
}

}  // namespace rbgitcfg
