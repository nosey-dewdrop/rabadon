// baseline.h — the three laws rabadon holds with NO configuration. (C++17)
//
// Until now a repo with no `.rabadon/guard.json` got a gate that refused
// nothing: `git push --force origin main` and `rm -rf /` both returned 0 with
// enforce ON. The README promised "the deterministic gate refuses the
// force-push before it rewrites history" to everyone who runs `npm i -g
// rabadon`, and for a fresh install that sentence was false. These three are
// now compiled in. guard.json EXTENDS them; it does not bring them into being.
//
//   baseline-force-push     force-push to a shared branch (main/master/trunk/
//                           develop). --force, -f, and the +refspec form are
//                           each recognized. --force-with-lease is legitimate
//                           and passes.
//   baseline-rm-rf-outside  recursive rm whose target resolves OUTSIDE the
//                           project tree AND outside the system temp area. The
//                           target is resolved, not matched: `..`, `~` and a
//                           symlink all land where they really land, and a
//                           wildcard or a brace is expanded the way a shell
//                           expands it BEFORE it is judged — judging the text
//                           before the first `*` judged a prefix, and a prefix
//                           is where an escape hides. (Five hand-written guards
//                           in five wild repos all baked the machine's path into
//                           a regex, and all five failed open on `..` — which is
//                           why this is code, not a pattern.) The temp carve-out
//                           is documented at in_temp_area(), the pattern rule
//                           and its one remaining limit at pattern_forms().
//   baseline-hard-reset     `git reset --hard` onto a shared branch.
//
// Any of them can be silenced by id in guard.json's disabled[].
//
// WHY THIS IS A PARSER AND NOT A REGEX. A regex over the whole command string
// gets both directions wrong, and the audit caught both in the wild:
//   - it MISSES `git --exec-path=/x push --force`, `git -C /path push -f`, and
//     `git push origin +master` — the canonical force refspec slipped past four
//     of five hand-written guards;
//   - it FIRES on `npm test && git push origin feature/x`, because a `-f`
//     anywhere in the line matches a `git push` anywhere else in the line. Four
//     of five wild guards blocked an ordinary feature-branch push this way.
// So the command is split into segments (&& || ; | newline, quote-aware) and
// each segment is tokenized and read as a command: name, options, operands.
// `echo "git push --force origin main"` is an echo with one argument.
//
// KNOWN LIMITS, by design (the sandbox is the hard boundary, not this):
//   - an operand that only a shell can resolve ($VAR, $(cmd), backticks) is not
//     guessed at — it passes. A false refusal costs more than a missed
//     obfuscation here, and `rabadon exec` is the answer for adversarial input.
//     What the SAME LINE assigns from a literal is not in that class and is
//     resolved before it gets here (cmdtext.h, apply_env).
//   - `cd` is followed across segments only when its argument is a literal path.
//
// THE READING OF THE COMMAND IS NOT DONE HERE. This file used to carry its own
// tokenizer, and it was the smaller of the two rabadon shipped: it compared the
// command name byte for byte, compared `-c` byte for byte so `sh -lc` was not a
// shell, had never heard of eval, `$( )` or a line continuation, and skipped a
// wrapper list that did not include xargs. Twelve spellings of a refused
// force-push walked past these three laws while the plain form was refused, and
// every one of them was a difference between the two parsers rather than a new
// kind of danger. There is one parser now (cmdtext.h) and this file is only the
// three laws. native/parser_unify_test.sh fails if the second one comes back.

#pragma once

#include <climits>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>
#include <sys/stat.h>
#include <unistd.h>

#include "cmdtext.h"

namespace rbbase {

using std::string;
using std::vector;

struct Hit { string id, why, detail; };

// ---------- paths: resolve, do not match ----------
inline string lexical_abs(const string& raw, const string& cwd) {
  string p = raw;
  if (!p.empty() && p[0] == '~') {
    const char* h = getenv("HOME");
    if (!h || !h[0]) return "";
    if (p.size() == 1) p = h;
    else if (p[1] == '/') p = string(h) + p.substr(1);
    else return "";                       // ~otheruser: not ours to guess
  }
  if (p.empty()) return "";
  if (p[0] != '/') p = cwd + "/" + p;
  vector<string> out;
  size_t i = 0;
  while (i < p.size()) {
    size_t j = p.find('/', i);
    if (j == string::npos) j = p.size();
    const string part = p.substr(i, j - i);
    if (part == "..") { if (!out.empty()) out.pop_back(); }
    else if (!part.empty() && part != ".") out.push_back(part);
    i = j + 1;
  }
  string abs;
  for (const string& s : out) { abs += "/"; abs += s; }
  return abs.empty() ? "/" : abs;
}

// realpath the longest existing prefix so a symlinked parent cannot smuggle a
// target out of the tree; the non-existent tail is re-appended as written.
inline string resolve_real(const string& absLexical) {
  string p = absLexical, tail;
  for (;;) {
    char buf[PATH_MAX];
    if (realpath(p.c_str(), buf)) {
      string r = buf;
      if (!tail.empty()) { if (r != "/") r += "/"; else r = "/"; r += tail; }
      return r;
    }
    const size_t s = p.rfind('/');
    if (s == string::npos || s == 0) return absLexical;
    tail = tail.empty() ? p.substr(s + 1) : p.substr(s + 1) + "/" + tail;
    p = p.substr(0, s);
  }
}

inline bool inside(const string& root, const string& path) {
  if (path == root) return true;
  return path.size() > root.size() && path.compare(0, root.size(), root) == 0 &&
         path[root.size()] == '/';
}

// ---------- what a glob component leaves behind ----------
// pattern_forms() (below) rewrites every glob COMPONENT of a delete target into
// one of these stand-ins before the target is resolved, so where the command
// lands can be computed without asking the disk. There are TWO because which
// entries a component can name is the whole question in the temp area:
// `scratch-*` can only match entries whose names the caller chose, while `*`,
// `*.log` and `.*` match whatever the directory happens to hold — under a
// shared temp root, that is every other process's scratch. The leading byte is
// one no file name can carry, so neither can collide with a real entry.
inline const string& glob_stand_in() { static const string s = "\x01glob"; return s; }
inline const string& any_stand_in()  { static const string s = "\x01any";  return s; }

// A component is ANCHORED when a literal name-part leads it: at least one
// character before the first wildcard, and dots do not count. `.*` is
// unanchored twice over — it names every dotted entry of its parent, and in
// bash it also names `.` and `..`.
inline bool glob_anchored(const string& comp) {
  const size_t w = comp.find_first_of("*?[");
  if (w == string::npos) return true;            // not a pattern at all
  for (size_t i = 0; i < w; i++) if (comp[i] != '.') return true;
  return false;
}

// ---------- the system temp area is not data ----------
// "Outside the project tree" read the machine's scratch space as if it were
// someone's files. Of the 73 refusals this rule produced across four live
// watch-mode sessions, 68 were an agent deleting a directory it had made under
// /tmp minutes earlier, and the remaining 5 were a glob under /tmp. That is not
// a rare shape: making a scratch dir, using it, and removing it is what every
// agent does in every repo, so the rule cost its own product on a stranger's
// machine as surely as on this one.
//
// The temp area is the one place whose contents are DEFINED to be disposable,
// so a recursive delete there is not the thing this law is for. But disposable
// means MY scratch, not THE scratch: the carve-out covers what the caller made
// under a temp dir, never the shared root's own list of entries. What stays
// dangerous, and is tested from both sides:
//   - the temp ROOT itself. `rm -rf /tmp` removes the directory every other
//     process is holding a path into.
//   - the root's ENTRIES, named by an unanchored pattern. `rm -rf /tmp/*` is
//     identical to `rm -rf /tmp` for everyone but the OS: it hands over another
//     session's mktemp tree, a half-written build, an editor swap file, a
//     database socket. Refusing the root and waiving its contents was the hole
//     this carve-out opened, and it is strictly worse than the rule it fixed.
//     So the first component under a temp root must be a name the caller wrote:
//     `/tmp/scratch-*` and `/tmp/build-*/out` pass, `/tmp/*`, `/tmp/*.log`,
//     `/tmp/.*` and `/tmp/*/x` do not. One level down the shared root is no
//     longer being enumerated and a bare glob is fine again: `/tmp/proj-out/*`
//     passes.
//     It is the EXPANSION that decides, not the text: `rm -rf /tmp/*/..` is
//     spelled like a pattern and lands on the root, and is refused
//     (pattern_forms).
//   - anything under $HOME, even when $HOME is itself under a temp dir. Test
//     harnesses point HOME at a mktemp dir, and work lives in a home directory
//     wherever the home directory happens to be.
//   - anywhere the path only reaches by leaving. `/tmp/../Users/x` is resolved
//     to /Users/x before it is judged, and a symlink out of the temp dir is
//     resolved to what it points at. The temp check reads the destination, not
//     the spelling, which is the same reason this file is a parser.
inline string norm_dir(const string& p) {
  string s = p;
  while (s.size() > 1 && s.back() == '/') s.pop_back();
  return s;
}

inline string real_home() {
  const char* h = getenv("HOME");
  if (!h || !h[0]) return "";
  return norm_dir(resolve_real(lexical_abs(h, "/")));
}

// $TMPDIR comes from the environment, and the environment is exactly what an
// agent can change. A root offered there is taken only when it could plausibly
// be a temp dir: TMPDIR=/ or TMPDIR=$HOME must not turn the whole machine into
// scratch space.
inline bool plausible_temp_root(const string& real, const string& home) {
  if (real.size() < 2 || real[0] != '/') return false;
  static const char* systemDir[] = {"/etc", "/usr", "/bin", "/sbin", "/var", "/private",
                                    "/System", "/Library", "/Applications", "/opt", "/dev"};
  for (const char* d : systemDir) if (real == d) return false;
  static const char* userTree[] = {"/Users", "/home", "/Volumes", "/mnt", "/media"};
  for (const char* d : userTree) if (inside(d, real)) return false;
  if (!home.empty() && inside(home, real)) return false;
  return true;
}

// /tmp and its real location (/private/tmp on macOS), /var/tmp, and the
// /var/folders tree mktemp -d writes into under a launchd session. Each is
// added both as written and as it resolves, so the list is right on a machine
// where /tmp is a symlink and on one where it is not.
inline const vector<string>& temp_roots() {
  static vector<string> roots;
  static bool built = false;
  if (built) return roots;
  built = true;
  const string home = real_home();
  auto add = [&](const string& p) {
    const string d = norm_dir(p);
    if (d.size() < 2 || d[0] != '/') return;
    for (const string& e : roots) if (e == d) return;
    roots.push_back(d);
  };
  const char* fixed[] = {"/tmp", "/var/tmp", "/var/folders"};
  for (const char* f : fixed) { add(f); add(resolve_real(f)); }
  const char* td = getenv("TMPDIR");
  if (td && td[0]) {
    const string a = norm_dir(resolve_real(lexical_abs(td, "/")));
    if (plausible_temp_root(a, home)) add(a);
  }
  return roots;
}

inline bool is_temp_root(const string& p) {
  for (const string& t : temp_roots()) if (p == t) return true;
  return false;
}

// the entry of `t` that a path passes through, or "" when it is not under t.
inline string entry_under(const string& t, const string& path) {
  if (path == t || !inside(t, path)) return "";
  const string rest = path.substr(t.size() + 1);
  const size_t s = rest.find('/');
  return s == string::npos ? rest : rest.substr(0, s);
}

// `real` is a destination, never a spelling: a pattern is turned into the paths
// it can name before it gets here (see pattern_forms), so a target that only
// reaches the temp root by walking back up to it is judged as the temp root.
// Every root is checked, not the first that matches: with TMPDIR pointing deep
// inside /var/folders, a target is under two roots at once and only the deeper
// one can see that its first component is the shared list of entries.
inline bool in_temp_area(const string& real) {
  const string home = real_home();
  if (!home.empty() && inside(home, real)) return false;
  bool disposable = false;
  for (const string& t : temp_roots()) {
    if (real == t) continue;              // the root itself is never disposable
    if (!inside(t, real)) continue;
    // ...and neither is a pattern that names whatever the root happens to hold
    if (entry_under(t, real) == any_stand_in()) return false;
    disposable = true;
  }
  return disposable;
}

// ---------- a pattern is not a path ----------
// The shell rewrites a delete target before rm ever sees it: braces expand into
// separate words, then each glob COMPONENT is replaced by the name of one
// directory entry. Reading a target up to the first `*` and judging the
// directory part therefore judges a PREFIX of the destination, and the prefix is
// exactly where an escape hides:
//
//     rm -rf /tmp/*/../../Users/u/proj1
//             ^^^^ the prefix, which is scratch
//                  ^^^^^^^^^^^^^^^^^^^^ the destination, which is not
//
// The same path without the pattern was refused, which is the tell: the pattern
// was the one spelling whose destination was never computed. So it is computed.
// Every word the shell can produce is resolved and judged, and one word landing
// outside is enough to refuse.
//
// LIMIT, stated because it is the next hole: what a pattern matches is decided
// by the disk at the moment it runs, so a match that is itself a SYMLINK out of
// the temp area cannot be resolved from the text. `rabadon exec` is the hard
// boundary for adversarial input; this is the law for honest commands.

// the stand-ins (glob_stand_in / any_stand_in, defined above with the temp law
// that reads them) name where a match will go. `*`, `?` and `[...]` never match
// a `/`, so a glob component is exactly one component: a `..` after it cancels
// the stand-in exactly as it will cancel the match.

// a stand-in, spoken back as what it stands for, so a refusal reads as the
// command was written.
inline string show_pattern(const string& p) {
  string out = p;
  for (const string& g : {glob_stand_in(), any_stand_in()})
    for (size_t i = out.find(g); i != string::npos; i = out.find(g, i))
      out.replace(i, g.size(), "*");
  return out;
}

// brace expansion, the shell's first pass. `{a,b}` is two words; a brace with
// no top-level comma, or one that never closes, is not an expansion and stays
// literal — which is what bash does with it. Returns false when the word would
// expand past `cap`: an expansion that large is a destination that cannot be
// computed, and the caller refuses rather than guesses.
inline bool brace_expand(const string& w, size_t from, vector<string>& out, size_t cap) {
  if (out.size() >= cap) return false;
  size_t open = string::npos;
  for (size_t i = from; i < w.size(); i++) {
    if (w[i] == '\\') { i++; continue; }
    if (w[i] == '{') { open = i; break; }
  }
  if (open == string::npos) { out.push_back(w); return true; }
  int depth = 0;
  size_t close = string::npos;
  vector<size_t> cut;                      // the open brace, then each top-level comma
  for (size_t i = open; i < w.size(); i++) {
    if (w[i] == '\\') { i++; continue; }
    if (w[i] == '{') { if (++depth == 1) cut.push_back(i); }
    else if (w[i] == '}') { if (--depth == 0) { close = i; break; } }
    else if (w[i] == ',' && depth == 1) cut.push_back(i);
  }
  if (close == string::npos || cut.size() < 2) return brace_expand(w, open + 1, out, cap);
  cut.push_back(close);
  for (size_t k = 0; k + 1 < cut.size(); k++) {
    const string alt = w.substr(cut[k] + 1, cut[k + 1] - cut[k] - 1);
    // the alternative is spliced in and re-read from the same place, so a brace
    // nested inside it expands too
    if (!brace_expand(w.substr(0, open) + alt + w.substr(close + 1), open, out, cap)) return false;
  }
  return true;
}

// the concrete paths one word can name. Each glob component becomes a stand-in
// — the anchored one when a literal name leads the component, the unanchored
// one when the component names whatever its parent holds, which is the
// difference the temp carve-out turns on. A `**` component under globstar can
// also match NOTHING, and the shallower path is the one a following `..` can
// walk out of, so that form is judged as well.
inline vector<string> pattern_forms(const string& w) {
  if (w.find_first_of("*?[") == string::npos) return vector<string>{w};
  vector<string> comps;
  for (size_t i = 0;;) {
    const size_t j = w.find('/', i);
    comps.push_back(w.substr(i, j == string::npos ? string::npos : j - i));
    if (j == string::npos) break;
    i = j + 1;
  }
  string matched, skipped;                 // `**` matches one entry / matches none
  bool first1 = true, first0 = true, anyStar2 = false;
  for (const string& c : comps) {
    const string r = c.find_first_of("*?[") == string::npos
                       ? c : (glob_anchored(c) ? glob_stand_in() : any_stand_in());
    if (!first1) matched += "/";
    matched += r; first1 = false;
    if (c == "**") { anyStar2 = true; continue; }
    if (!first0) skipped += "/";
    skipped += r; first0 = false;
  }
  vector<string> forms{matched};
  if (anyStar2 && skipped != matched) forms.push_back(skipped.empty() ? "." : skipped);
  return forms;
}

// the project tree: the git worktree containing cwd, else cwd itself
inline string project_root(const string& cwd) {
  string p = resolve_real(lexical_abs(cwd, "/"));
  while (!p.empty()) {
    struct stat st;
    if (stat((p + "/.git").c_str(), &st) == 0) return p;
    const size_t s = p.rfind('/');
    if (s == string::npos || s == 0) break;
    p = p.substr(0, s);
  }
  return resolve_real(lexical_abs(cwd, "/"));
}

// ---------- shared branches ----------
inline bool shared_branch(const string& refIn) {
  string r = refIn;
  const size_t colon = r.rfind(':');            // src:dst — the destination decides
  if (colon != string::npos) r = r.substr(colon + 1);
  while (!r.empty() && r[0] == '+') r = r.substr(1);
  if (r.compare(0, 11, "refs/heads/") == 0) r = r.substr(11);
  const size_t slash = r.find('/');
  if (slash != string::npos) {
    const string remote = r.substr(0, slash);
    if (remote != "origin" && remote != "upstream") return false;
    r = r.substr(slash + 1);
    if (r.find('/') != string::npos) return false;
  }
  return r == "main" || r == "master" || r == "trunk" || r == "develop";
}

inline string current_branch(const string& root) {
  std::ifstream f(root + "/.git/HEAD");
  if (!f) return "";
  string h;
  std::getline(f, h);
  const string pre = "ref: refs/heads/";
  if (h.compare(0, pre.size(), pre) != 0) return "";
  string b = h.substr(pre.size());
  while (!b.empty() && (b.back() == '\n' || b.back() == '\r' || b.back() == ' ')) b.pop_back();
  return b;
}

// ---------- git option walk: EVERY leading option, not a list of known ones ----
// `git --exec-path=/x push --force` slipped through a hand-listed set (31.07).
// The rule is structural: after `git`, skip every token that starts with '-',
// consuming a value only for the options that genuinely take a separate one.
inline bool git_subcommand(const vector<rbtext::Word>& t, size_t gi, size_t& subIdx) {
  size_t i = gi + 1;
  while (i < t.size()) {
    const string& s = t[i].text;
    if (s.empty() || s[0] != '-') { subIdx = i; return true; }
    const bool takesValue = (s == "-C" || s == "-c" || s == "--git-dir" || s == "--work-tree");
    i += takesValue ? 2 : 1;
  }
  return false;
}

// the same walk, as a string rewrite, so USER regexes written as `git\s+push`
// still see a command an agent wrote as `git -C /path push`.
//
// Only the segments of the text as HANDED IN are rewritten. A caller passes one
// executable surface at a time and the parser may lift a subshell body out of
// it; that body is its own surface and the caller rewrites it on its own turn,
// so splicing it in here would hand the same command to a rule twice.
inline string strip_git_globals(const string& cmd) {
  const rbtext::Parsed p = rbtext::parse(cmd);
  if (p.degraded) return cmd;
  string out;
  for (size_t s = 0; s < p.segs.size(); s++) {
    if (p.segs[s].group != 0) continue;
    const vector<rbtext::Word>& t = p.segs[s].words;
    if (t.empty()) continue;
    if (!out.empty()) out += " ; ";
    const size_t ci = rbtext::command_index(t);
    size_t sub = 0;
    const bool isGit = ci < t.size() && rbtext::name_is(rbtext::base_of(t[ci].text), "git") &&
                       git_subcommand(t, ci, sub);
    bool firstWord = true;
    for (size_t i = 0; i < t.size(); i++) {
      if (isGit && i > ci && i < sub) continue;      // the globals, dropped
      if (!firstWord) out += " ";
      firstWord = false;
      out += t[i].text;
    }
  }
  return out;
}

// ---------- the three laws ----------
inline bool disabled_has(const vector<string>& disabled, const string& id) {
  for (const auto& d : disabled) if (d == id) return true;
  return false;
}

// Every command the line runs, in order, each judged where it really runs.
//
// The parser already flattened `sh -lc '...'`, `eval "..."`, `$( )`, a subshell
// and an xargs wrapper into segments, so this walk has no idea those spellings
// exist — which is the point: a spelling it has never heard of cannot be a
// spelling it gets wrong. What it does still track is the working directory,
// and directories do not flatten: a `cd` inside `sh -c '...'` moves that shell
// and not its caller. Each segment carries the context it runs in, and a
// context takes its starting directory from the one that created it.
inline bool check_segment(const vector<rbtext::Word>& t, const string& cwd, const string& root,
                          const vector<string>& disabled, Hit& hit);

inline bool check_parsed(const rbtext::Parsed& p, const string& cwd0, const string& root,
                         const vector<string>& disabled, Hit& hit) {
  const size_t n = p.groups > 0 ? (size_t)p.groups : 1;
  vector<string> groupCwd(n, cwd0);
  vector<char> seen(n, 0);
  seen[0] = 1;
  for (size_t s = 0; s < p.segs.size(); s++) {
    const rbtext::Seg& sg = p.segs[s];
    const size_t g = (size_t)sg.group < n ? (size_t)sg.group : 0;
    const size_t par = (size_t)sg.parent < n ? (size_t)sg.parent : 0;
    if (!seen[g]) { groupCwd[g] = groupCwd[par]; seen[g] = 1; }
    if (check_segment(sg.words, groupCwd[g], root, disabled, hit)) return true;
    // follow a literal `cd` so a later segment is judged where it really runs
    const size_t ci = rbtext::command_index(sg.words);
    if (ci < sg.words.size() && rbtext::name_is(rbtext::base_of(sg.words[ci].text), "cd") &&
        ci + 1 < sg.words.size()) {
      const string& arg = sg.words[ci + 1].text;
      const string next = lexical_abs(arg, groupCwd[g]);
      if (!next.empty() && arg.find('$') == string::npos) groupCwd[g] = next;
    }
  }
  return false;
}

inline bool check_segment(const vector<rbtext::Word>& t, const string& cwd, const string& root,
                          const vector<string>& disabled, Hit& hit) {
  const size_t ci = rbtext::command_index(t);
  if (ci >= t.size()) return false;
  const string name = rbtext::base_of(t[ci].text);

  if (rbtext::name_is(name, "git")) {
    size_t sub = 0;
    if (!git_subcommand(t, ci, sub)) return false;
    const string subcmd = t[sub].text;

    if (subcmd == "push" && !disabled_has(disabled, "baseline-force-push")) {
      bool force = false, lease = false;
      vector<string> operands;
      for (size_t i = sub + 1; i < t.size(); i++) {
        const string& s = t[i].text;
        if (s.compare(0, 18, "--force-with-lease") == 0 ||
            s.compare(0, 20, "--force-if-includes") == 0) { lease = true; continue; }
        if (s == "--force" || s == "-f") { force = true; continue; }
        if (!s.empty() && s[0] == '-') continue;
        if (!s.empty() && s[0] == '+') force = true;       // the canonical force refspec
        operands.push_back(s);
      }
      if (force && !lease) {
        // operands are <remote> [<refspec>...]; with no refspec git pushes the
        // current branch, so HEAD is the target.
        vector<string> refs(operands.begin() + (operands.empty() ? 0 : 1), operands.end());
        if (refs.empty()) {
          const string b = current_branch(root);
          if (!b.empty()) refs.push_back(b);
        }
        for (const string& r : refs) {
          if (!shared_branch(r)) continue;
          hit = {"baseline-force-push",
                 "a force-push to a shared branch rewrites history other people already have",
                 "force-push to shared branch '" + r + "' — use --force-with-lease, or push to your own branch"};
          return true;
        }
      }
      return false;
    }

    if (subcmd == "reset" && !disabled_has(disabled, "baseline-hard-reset")) {
      bool hard = false;
      for (size_t i = sub + 1; i < t.size(); i++) if (t[i].text == "--hard") hard = true;
      if (!hard) return false;
      for (size_t i = sub + 1; i < t.size(); i++) {
        const string& s = t[i].text;
        if (!s.empty() && s[0] == '-') continue;
        if (!shared_branch(s)) continue;
        hit = {"baseline-hard-reset",
               "a hard reset onto a shared branch discards local work with no way back",
               "git reset --hard onto '" + s + "' — commit or stash first, or reset to a local ref"};
        return true;
      }
    }
    return false;
  }

  if (rbtext::name_is(name, "rm") && !disabled_has(disabled, "baseline-rm-rf-outside")) {
    bool recursive = false, endOfFlags = false;
    vector<string> targets;
    for (size_t i = ci + 1; i < t.size(); i++) {
      const string& s = t[i].text;
      if (!endOfFlags && s == "--") { endOfFlags = true; continue; }
      if (!endOfFlags && s.size() > 1 && s[0] == '-') {
        if (s.compare(0, 2, "--") == 0) { if (s == "--recursive") recursive = true; }
        else for (size_t k = 1; k < s.size(); k++) if (s[k] == 'r' || s[k] == 'R') recursive = true;
        continue;
      }
      targets.push_back(s);
    }
    if (!recursive) return false;
    // The project tree is the carve-out because git can undo a delete inside it.
    // With no worktree above cwd that tree falls back to cwd ITSELF, and if the
    // shell is sitting in the shared temp root the fallback hands back exactly
    // what the temp law refuses: `cd /tmp && rm -rf *` would be "inside the
    // project". A directory every process on the machine writes into is not a
    // project, so the fallback does not apply there and the temp law judges
    // those targets — `cd /tmp && rm -rf my-scratch` still passes, and a real
    // project that merely LIVES under /tmp (root /tmp/work) is untouched.
    const bool scratchCwd = is_temp_root(root);
    for (const string& raw : targets) {
      if (raw.find('$') != string::npos || raw.find('`') != string::npos) continue;
      // every word the shell can make of this target, then every path each of
      // those words can name — the destination, not the spelling
      vector<string> words;
      if (!brace_expand(raw, 0, words, 256)) {
        hit = {"baseline-rm-rf-outside",
               "a recursive delete outside the project tree cannot be undone by git",
               "rm -r '" + raw + "' expands to more than 256 words, so where it lands cannot be "
               "computed — name the paths, or silence baseline-rm-rf-outside by id"};
        return true;
      }
      for (const string& word : words) {
        for (const string& form : pattern_forms(word)) {
          const string abs = lexical_abs(form, cwd);
          if (abs.empty()) continue;
          const string real = resolve_real(abs);
          if (!scratchCwd && inside(root, real)) continue;
          if (in_temp_area(real)) continue;
          hit = {"baseline-rm-rf-outside",
                 "a recursive delete outside the project tree cannot be undone by git",
                 "rm -r '" + raw + "' " + (form == raw ? "resolves to " : "expands to ") +
                 show_pattern(real) +
                 (scratchCwd ? ", and cwd is the shared temp root itself (" + root +
                               "), which is not a project tree"
                             : ", outside the project tree (" + root + ")")};
          return true;
        }
      }
    }
  }
  return false;
}

// The entry point: true = one of the three laws refuses this command.
//
// The overload taking a Parsed is what a caller that has ALREADY parsed the
// line should use — rules.h runs the user's deny rules over the same segments
// and would otherwise pay for the walk twice.
inline bool check_parsed(const rbtext::Parsed& p, const string& cwd,
                         const vector<string>& disabled, Hit& hit) {
  // Resolving the project root walks up the tree with a stat() at every level,
  // and the overwhelmingly common command is neither git nor rm. The test is
  // the laws' OWN precondition read off the parsed command — not a substring
  // scan of the line, which is how `echo "no git here"` used to pay for it and
  // how `GIT push` used to escape it.
  bool relevant = false;
  for (size_t s = 0; s < p.segs.size() && !relevant; s++) {
    const size_t ci = rbtext::command_index(p.segs[s].words);
    if (ci >= p.segs[s].words.size()) continue;
    const string b = rbtext::base_of(p.segs[s].words[ci].text);
    relevant = rbtext::name_is(b, "git") || rbtext::name_is(b, "rm");
  }
  if (!relevant) return false;
  const string root = project_root(cwd);
  const string realCwd = resolve_real(lexical_abs(cwd, "/"));
  return check_parsed(p, realCwd, root, disabled, hit);
}

inline bool check(const string& command, const string& cwd, const vector<string>& disabled, Hit& hit) {
  if (command.empty()) return false;
  // the gate runs on every tool call and its latency is a published number, so
  // the overwhelmingly common command — one that is neither git nor rm — costs
  // two substring scans and nothing else. this is a superset: any command the
  // laws could refuse must contain one of these. The scan asks the same
  // question the name comparison does, so on a file system that resolves GIT
  // and git to one binary it is the case-insensitive scan; otherwise the
  // pre-filter would drop the line before the law ever saw it.
  if (!rbtext::mentions(command, "git") && !rbtext::mentions(command, "rm")) return false;
  return check_parsed(rbtext::parse(command), cwd, disabled, hit);
}

}  // namespace rbbase
