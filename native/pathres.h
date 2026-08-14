// pathres.h — ONE answer to "where does this path land". (C++17)
//
// This used to live inside baseline.h, next to the three compiled-in laws, and
// it was the only path resolver in the binary — so the OTHER layer that judges
// paths did not have one. A project's guard.json deny rule is a regex, and a
// regex reads the spelling:
//
//     rm -rf /tmp/proj-build && cmake -B /tmp/proj-build ...
//     the compiled law  -> resolves to /private/tmp/proj-build, machine
//                          scratch, allowed
//     the project rule  -> the text begins with "/", the allow-list says
//                          "/Users/u/work/proj1", no match, REFUSED
//
// Nine of the twenty refusals in native/precision_fixture.jsonl are that one
// disagreement, and all nine cut an agent cleaning up scratch it had made
// minutes earlier. The rule was not wrong about danger. It was never given the
// path. So the resolver is its own header now and BOTH layers link it:
// baseline.h for the compiled delete law, rules.h for the project's own rules
// (rbrules::path_landing). A question answered in two places is answered two
// ways, which is the whole reason cmdtext.h exists for commands; this is the
// same move for paths.
//
// What "resolve" covers, each one because a spelling walked past a rule that
// only looked at text:
//   - symbolic links: the destination decides, not the name that reaches it
//   - `..`, including a `..` that cancels a glob component
//   - globs and braces: where the shell can LAND, not the text before the `*`
//   - the variables whose value is not a guess. $HOME and $TMPDIR are read from
//     the environment the command will run in; every other `$` stays unresolved
//     and its target stays waived, because guessing is worse than missing
//   - the system temp area, as it really is on this machine: /tmp and what /tmp
//     resolves to (/private/tmp on macOS), /var/tmp, and the /var/folders tree
//     mktemp writes into. Disposable means MY scratch, never THE scratch.
//
// NOTHING HERE TOUCHES THE DISK except realpath(), stat(), and the one line a
// `.git` FILE holds when it is a link to a real git dir. It computes where a
// command WOULD land; running it is somebody else's job, and in rabadon it is
// nobody's.
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

namespace rbpath {

using std::string;
using std::vector;

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

// WHERE THE SUPERVISION LIVES — the switch, the mode marker and the ledger.
//
// This is the one definition. gate.cpp's rabadon_home() calls it, and so does
// the baseline law that refuses a delete aimed at it, because a law protecting
// a directory and a program choosing that directory must not be able to
// disagree about which directory it is. The same file already carries the
// lesson twice over: two spellings of one path is how the encoded project key
// walked past three checks in a row.
inline string rabadon_dir() {
  const char* rd = getenv("RABADON_DIR");
  if (rd && rd[0]) return string(rd);
  const char* h = getenv("HOME");
  return string(h && h[0] ? h : ".") + "/.rabadon";
}

inline void add_root(vector<string>& roots, const string& p) {
  const string d = norm_dir(p);
  if (d.size() < 2 || d[0] != '/') return;
  for (const string& e : roots) if (e == d) return;
  roots.push_back(d);
}

// The machine's own scratch, read WITHOUT the environment: /tmp and its real
// location (/private/tmp on macOS), /var/tmp, and the /var/folders tree
// mktemp -d writes into under a launchd session. Each is added both as written
// and as it resolves, so the list is right on a machine where /tmp is a symlink
// and on one where it is not.
//
// This is a separate list from temp_roots() below because plausible_temp_root()
// has to read it: the question it answers is whether the root $TMPDIR names is
// part of the machine's temp area, and it cannot ask a list that already
// contains $TMPDIR's own answer.
inline const vector<string>& machine_temp_roots() {
  static vector<string> roots;
  static bool built = false;
  if (built) return roots;
  built = true;
  const char* fixed[] = {"/tmp", "/var/tmp", "/var/folders"};
  for (const char* f : fixed) { add_root(roots, f); add_root(roots, resolve_real(f)); }
  return roots;
}

// $TMPDIR comes from the environment, and the environment is exactly what an
// agent writes for itself. Naming a root there does not make that root's
// contents disposable — it makes THIS LAW'S OPINION of them disposable, which
// is why the value is checked at all.
//
// The check used to be a DENYLIST of system directories compared for exact
// equality, and it scored what a list of spellings always scores. Eleven of
// twelve measured shapes walked through it:
//
//     TMPDIR=/usr        rm -rf /usr/lib          refused   (on the list)
//     TMPDIR=/usr/local  rm -rf /usr/local/lib    ALLOWED   (one level down)
//     TMPDIR=/root       rm -rf /root/backups     ALLOWED   (never on the list)
//     TMPDIR=/srv        rm -rf /srv/www          ALLOWED
//     TMPDIR=/lib /boot /nix /data ...            ALLOWED
//
// One `TMPDIR=` assignment ahead of the command turned the delete law off for
// the tree underneath. The same function already read the USER trees as
// subtrees (`inside`) and the system trees as exact names (`==`), and there was
// never a reason for the difference — a subdirectory of /etc is no more
// disposable than /etc.
//
// So the test is inverted, and the list it consults is the one thing here that
// is not a guess: a root offered through the environment is taken only when it
// lands in the machine's OWN temp area, and never under $HOME (a harness that
// points HOME at a mktemp dir must not hand back the home directory it just
// made). Nothing else is asked, because every other question is a denylist
// again.
//
// THE COST, STATED: a genuinely unusual $TMPDIR — /run/user/1000 under systemd,
// $SCRATCH on a cluster — is no longer read as scratch. What it holds is then
// judged like any other path, so a recursive delete there is refused when it is
// also outside the project tree. That is a false refusal, silenceable by id in
// guard.json's disabled[]; the direction it fails in is the one that keeps
// files. /tmp, /var/tmp and /var/folders are unaffected and need no $TMPDIR at
// all, which is where an agent's scratch actually is.
inline bool plausible_temp_root(const string& real, const string& home) {
  if (real.size() < 2 || real[0] != '/') return false;
  if (!home.empty() && inside(home, real)) return false;
  for (const string& t : machine_temp_roots()) if (inside(t, real)) return true;
  return false;
}

// the machine's temp area plus whatever $TMPDIR adds to it, which is what a
// target is judged against. $TMPDIR can only ever name a root DEEPER than one
// already here (plausible_temp_root), and that depth is the point: only the
// deeper root can see that the first component under it is a shared list of
// entries rather than one caller's scratch.
inline const vector<string>& temp_roots() {
  static vector<string> roots;
  static bool built = false;
  if (built) return roots;
  built = true;
  roots = machine_temp_roots();
  const char* td = getenv("TMPDIR");
  if (td && td[0]) {
    const string a = norm_dir(resolve_real(lexical_abs(td, "/")));
    if (plausible_temp_root(a, real_home())) add_root(roots, a);
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

// ---------- the variables that are not a guess ----------
// A target carrying `$` is waived: where `$TARGET` expands to cannot be read
// off the text, and refusing on a guess is worse than missing one. That waiver
// swallowed two names it should never have covered. $HOME and $TMPDIR are not
// unknown — they are in the environment the command is about to run in, they
// are what an agent actually writes when it names a home or a scratch dir, and
// `rm -rf $HOME/Documents` walked past the compiled delete law for exactly this
// reason (path_answer_test.sh holds it now).
//
// Only these two, and only from the environment. Everything else stays `$` and
// stays waived, so the waiver the delete law was argued for is intact.
inline bool env_known(const string& name, string& val) {
  if (name != "HOME" && name != "TMPDIR") return false;
  const char* v = getenv(name.c_str());
  if (!v || !v[0]) return false;
  val = norm_dir(v);
  return !val.empty();
}

// the word with $HOME / ${TMPDIR} / ... replaced by their values. Any other
// expansion is left exactly as written, so has_unresolved() below still sees it.
inline string expand_known_vars(const string& w) {
  if (w.find('$') == string::npos) return w;
  string out;
  for (size_t i = 0; i < w.size(); i++) {
    if (w[i] != '$') { out += w[i]; continue; }
    size_t a = i + 1;
    bool braced = false;
    if (a < w.size() && w[a] == '{') { braced = true; a++; }
    size_t b = a;
    while (b < w.size() && (isalnum((unsigned char)w[b]) || w[b] == '_')) b++;
    string val;
    const bool closed = !braced || (b < w.size() && w[b] == '}');
    if (b > a && closed && env_known(w.substr(a, b - a), val)) {
      out += val;
      i = braced ? b : b - 1;
      continue;
    }
    out += w[i];
  }
  return out;
}

inline bool has_unresolved(const string& w) {
  return w.find('$') != string::npos || w.find('`') != string::npos;
}

// ---------- the one verdict both layers ask for ----------
// Where a delete target lands. The compiled law and the project's own deny
// rules both call THIS, which is the whole point of the header: a question
// answered in two places is answered two ways.
//
//   WAIVED        an unresolved `$` or backtick is left. Where it expands to
//                 cannot be read off the text and refusing on a guess is worse
//                 than missing one, so the compiled law passes over it — and
//                 the rule layer keeps whatever its regex already decided,
//                 because failing toward more refusals is the safe direction.
//   UNCOMPUTABLE  a brace expansion wider than the cap: the destination cannot
//                 be computed at all, and that is a refusal, not a pass.
//   CONTAINED     every path every word can name lands inside `root`, or in the
//                 machine's temp area. Nothing here is unrecoverable.
//   ESCAPES       one of them does not, and one is enough. `.real` is where.
enum Landing { WAIVED, UNCOMPUTABLE, CONTAINED, ESCAPES };

struct Land {
  Landing where = CONTAINED;
  string real;              // where it escapes to, stand-ins spoken back as `*`
  bool rewritten = false;   // the shell would rewrite the word before rm sees it
};

// `root` is the tree a delete can be undone in. Pass "" for no project
// carve-out at all — which is what the shell sitting in the shared temp root
// gets, and what a project's OWN deny rule gets: that rule wrote its own
// anchor, and this resolver hands it the destination and the temp law, not a
// different idea of which tree is protected.
inline Land land_of(const string& rawIn, const string& cwd, const string& root) {
  Land L;
  const string raw = expand_known_vars(rawIn);
  if (has_unresolved(raw)) { L.where = WAIVED; return L; }
  vector<string> words;
  if (!brace_expand(raw, 0, words, 256)) { L.where = UNCOMPUTABLE; return L; }
  for (size_t w = 0; w < words.size(); w++) {
    const vector<string> forms = pattern_forms(words[w]);
    for (size_t f = 0; f < forms.size(); f++) {
      const string abs = lexical_abs(forms[f], cwd);
      if (abs.empty()) continue;
      const string real = resolve_real(abs);
      if (!root.empty() && inside(root, real)) continue;
      if (in_temp_area(real)) continue;
      L.where = ESCAPES;
      L.real = show_pattern(real);
      L.rewritten = (forms[f] != raw);
      return L;
    }
  }
  return L;
}

// ---------- a delete command's targets ----------
// The operands of an `rm`-shaped command, flags off. Both layers read the same
// list: the compiled law to judge them, the rule layer to ask where the text a
// regex just matched is actually pointing.
//
// The names themselves moved to cmdtext.h and are read from there. The walk
// that finds WHICH WORD is the command now has to know the delete family too —
// it is how an unlisted wrapper is told from a command — and a list that exists
// twice diverges twice: the day `trash` is added to one of them, one walk finds
// the command and the other refuses to read its targets.
inline bool is_delete_command(const string& base) { return rbtext::is_delete_command(base); }

struct Delete {
  bool isDelete = false;
  bool recursive = false;
  vector<string> targets;
};

inline Delete delete_of(const vector<rbtext::Word>& t) {
  Delete d;
  const size_t ci = rbtext::command_index(t);
  if (ci >= t.size()) return d;
  if (!is_delete_command(rbtext::base_of(t[ci].text))) return d;
  d.isDelete = true;
  bool endOfFlags = false;
  for (size_t i = ci + 1; i < t.size(); i++) {
    const string& s = t[i].text;
    if (!endOfFlags && s == "--") { endOfFlags = true; continue; }
    if (!endOfFlags && s.size() > 1 && s[0] == '-') {
      if (s.compare(0, 2, "--") == 0) { if (s == "--recursive") d.recursive = true; }
      else for (size_t k = 1; k < s.size(); k++) if (s[k] == 'r' || s[k] == 'R') d.recursive = true;
      continue;
    }
    d.targets.push_back(s);
  }
  return d;
}


// ---------- which repo a git command line really operates on ----------
// The push law's fallback — "a push that names no refspec writes the current
// branch" — has to read HEAD, and it read it in `project_root(cwd) + "/.git"`:
// the repo the SHELL is standing in. `-C`, `--git-dir` and $GIT_DIR are exactly
// the knobs that make git operate on a DIFFERENT one, so from a scratch branch
// all three force-updated main next door while the law was reading `scratch`.
// This is the one place that answers "where does the HEAD git will read live",
// and both the branch fallback and the refspace walk ask it.
//
// `.git` is not always a directory. `git worktree add` and a submodule write a
// FILE holding `gitdir: <path>` and git follows it (measured in
// native/other_repo_test.sh), and a BARE repo has no `.git` at all — it IS the
// git dir, with HEAD sitting directly inside. All three shapes are one
// question, asked once.
inline string gitdir_link(const string& file, const string& relTo) {
  std::ifstream f(file.c_str());
  if (!f) return "";
  string line;
  if (!std::getline(f, line)) return "";
  static const string pre = "gitdir: ";
  if (line.size() <= pre.size() || line.compare(0, pre.size(), pre) != 0) return "";
  string p = line.substr(pre.size());
  while (!p.empty() && (p.back() == '\n' || p.back() == '\r' || p.back() == ' ')) p.pop_back();
  if (p.empty()) return "";
  return resolve_real(lexical_abs(p, relTo));
}

// the git dir OF a directory, or "" if that directory is not the top of a repo
inline string git_dir_at(const string& dir) {
  if (dir.empty()) return "";
  struct stat st;
  const string dot = dir + "/.git";
  if (stat(dot.c_str(), &st) == 0) {
    if (S_ISDIR(st.st_mode)) return dot;
    return gitdir_link(dot, dir);
  }
  // a bare repo: HEAD and refs live here, and there is no worktree above them
  if (stat((dir + "/HEAD").c_str(), &st) == 0 && S_ISREG(st.st_mode) &&
      stat((dir + "/refs").c_str(), &st) == 0)
    return dir;
  return "";
}

// the git dir the LINE points at: the -C chain, then --git-dir/$GIT_DIR
// relative to where that chain landed, then git's own upward discovery from
// there. Empty when the repo cannot be named from this text — an unresolved
// `$` in the path, or a directory that is not there. That answer is a named
// limit and not a guess: git itself refuses to run when `-C` cannot chdir
// ("fatal: cannot change to '../nope'"), so there is no branch to protect, and
// falling back to the shell's own repo would be answering about a repo this
// command never touches, which is the bug this exists to end.
inline string git_dir_for(const string& cwd, const vector<string>& chdirs,
                          const string& gitDirOpt) {
  string base = cwd;
  for (size_t i = 0; i < chdirs.size(); i++) {
    const string c = expand_known_vars(chdirs[i]);
    if (c.empty()) continue;                       // `git -C ''` is a measured no-op
    if (has_unresolved(c)) return "";
    base = resolve_real(lexical_abs(c, base));
    struct stat st;
    // git chdirs, so a `-C` at a directory that is not there is not a repo one
    // level up — it is the whole command failing before it opens anything
    if (base.empty() || stat(base.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) return "";
  }
  if (!gitDirOpt.empty()) {
    const string g = expand_known_vars(gitDirOpt);
    if (has_unresolved(g)) return "";
    const string abs = resolve_real(lexical_abs(g, base));
    struct stat st;
    if (abs.empty() || stat(abs.c_str(), &st) != 0) return "";
    if (S_ISDIR(st.st_mode)) return abs;
    return gitdir_link(abs, abs.substr(0, abs.rfind('/')));  // --git-dir at a link file
  }
  string p = base;
  while (!p.empty()) {
    const string g = git_dir_at(p);
    if (!g.empty()) return g;
    const size_t s = p.rfind('/');
    if (s == string::npos || s == 0) break;
    p = p.substr(0, s);
  }
  return "";
}

// ---------- where each command in a line really runs ----------
// The parser flattened `sh -lc '...'`, `eval`, `$( )`, subshells and xargs into
// a flat segment list, but directories do not flatten: a `cd` inside
// `sh -c '...'` moves that shell and not its caller. Each segment carries the
// context it runs in, and a context starts where the one that created it was.
//
// Both layers need this, because both layers judge paths and a relative path
// means nothing without it. It is computed once per line and handed to both.
inline vector<string> segment_cwds(const rbtext::Parsed& p, const string& cwd0) {
  const size_t n = p.groups > 0 ? (size_t)p.groups : 1;
  vector<string> groupCwd(n, cwd0), out(p.segs.size(), cwd0);
  vector<vector<string> > dirStack(n);   // what pushd saved and popd restores
  vector<char> seen(n, 0);
  seen[0] = 1;
  for (size_t s = 0; s < p.segs.size(); s++) {
    const rbtext::Seg& sg = p.segs[s];
    const size_t g = (size_t)sg.group < n ? (size_t)sg.group : 0;
    const size_t par = (size_t)sg.parent < n ? (size_t)sg.parent : 0;
    if (!seen[g]) { groupCwd[g] = groupCwd[par]; seen[g] = 1; }
    out[s] = groupCwd[g];
    // Follow the verbs that move the shell, so a later segment is judged where
    // it really runs. This used to read the word straight after `cd` as the
    // directory and knew no other verb, which cost six red-team probes — and
    // cost them in the dangerous direction. A walk that loses the shell does
    // not over-refuse: it believes the delete is happening inside the project,
    // where deletes are allowed, so every miss is a silent pass.
    //
    //   cd -P /elsewhere   the directory is not words[ci+1], `-P` is
    //   cd -- /elsewhere   and `--` is not one either
    //   pushd /elsewhere   the same move with a stack behind it
    //   popd               the way back, which the twins depend on: after a
    //                      push and a pop the shell is home again, and a delete
    //                      at the end of that line is ordinary work
    const size_t ci = rbtext::command_index(sg.words);
    if (ci < sg.words.size()) {
      const string base = rbtext::base_of(sg.words[ci].text);
      const bool isCd = rbtext::name_is(base, "cd");
      const bool isPush = rbtext::name_is(base, "pushd");
      if (rbtext::name_is(base, "popd")) {
        if (!dirStack[g].empty()) { groupCwd[g] = dirStack[g].back(); dirStack[g].pop_back(); }
      } else if (isCd || isPush) {
        // the first operand that is not an option. pushd also takes +N and -N,
        // which select a slot in the stack rather than name a directory.
        string arg; bool endOpts = false;
        for (size_t i = ci + 1; i < sg.words.size(); i++) {
          const string& w = sg.words[i].text;
          if (!endOpts && w == "--") { endOpts = true; continue; }
          if (!endOpts && w.size() > 1 && (w[0] == '-' || (isPush && w[0] == '+'))) continue;
          arg = w; break;
        }
        // `cd -` is the previous directory, not a path. Treating it as one puts
        // the walk in <cwd>/- and every later judgement on this line with it.
        if (!arg.empty() && arg != "-" && arg.find('$') == string::npos) {
          const string next = lexical_abs(arg, groupCwd[g]);
          if (!next.empty()) {
            if (isPush) dirStack[g].push_back(groupCwd[g]);
            groupCwd[g] = next;
          }
        }
      }
    }
  }
  return out;
}

}  // namespace rbpath
