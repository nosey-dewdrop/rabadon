// baseline.h — the laws rabadon holds with NO configuration. (C++17)
//
// Until now a repo with no `.rabadon/guard.json` got a gate that refused
// nothing: `git push --force origin main` and `rm -rf /` both returned 0 with
// enforce ON. The README promised "the deterministic gate refuses the
// force-push before it rewrites history" to everyone who runs `npm i -g
// rabadon`, and for a fresh install that sentence was false. These are now
// compiled in. guard.json EXTENDS them; it does not bring them into being.
//
//   baseline-force-push     force-push to a shared branch (main/master/trunk/
//                           develop). --force, -f, and the +refspec form are
//                           each recognized. --force-with-lease ALONE is
//                           legitimate and passes; beside an explicit force it
//                           is not an excuse, because git overrides it.
//   baseline-branch-delete  a push that REMOVES a shared branch from the
//                           remote: the empty-source refspec (`origin :main`),
//                           `--delete`, and `-d`. Its own id, not a clause of
//                           the force-push law, because a repo that allows
//                           force-pushing its trunk has not agreed to that
//                           trunk being deleted — and because the two are not
//                           the same harm. Deleting your own merged branch is
//                           ordinary work and passes.
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
//                           and its one remaining limit at pattern_forms(), and
//                           which roots the carve-out covers at
//                           plausible_temp_root() — $TMPDIR is environment, and
//                           an assignment an agent writes for itself does not
//                           get to name a tree disposable.
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
// force-push walked past these laws while the plain form was refused, and
// every one of them was a difference between the two parsers rather than a new
// kind of danger. There is one parser now (cmdtext.h) and this file is only the
// laws. native/parser_unify_test.sh fails if the second one comes back.

#pragma once

#include <climits>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <string>
#include <vector>
#include <sys/stat.h>
#include <unistd.h>

#include "cmdtext.h"
#include "gitcfg.h"
#include "pathres.h"

namespace rbbase {

using std::string;
using std::vector;

struct Hit { string id, why, detail; };

// ---------- paths ----------
// The resolver moved to pathres.h and did not get copied: rules.h needs the
// same answers for the project's OWN deny rules, and a path question answered
// in two headers is answered two ways -- which is exactly the bug this file
// spent the morning on for COMMANDS (cmdtext.h). These names are the same
// functions, not a second set.
using rbpath::Land;
using rbpath::brace_expand;
using rbpath::entry_under;
using rbpath::expand_known_vars;
using rbpath::glob_anchored;
using rbpath::in_temp_area;
using rbpath::inside;
using rbpath::is_temp_root;
using rbpath::land_of;
using rbpath::lexical_abs;
using rbpath::norm_dir;
using rbpath::pattern_forms;
using rbpath::project_root;
using rbpath::real_home;
using rbpath::resolve_real;
using rbpath::show_pattern;
using rbpath::temp_roots;


// ---------- shared branches ----------
// The branch a ref operand names, with every spelling git allows around it
// stripped: `src:dst` answers on the DESTINATION (the side that gets written or
// removed), a leading `+` is the force marker, `refs/heads/x` and `heads/x` are
// both `x` written out, and `origin/x` is `x` on a remote. "" when the operand
// names no branch at all — a tag, a nested path, some other remote's namespace.
//
// THERE ARE TWO SPELLINGS OF THE HEADS NAMESPACE AND THIS KNEW ONE. git
// resolves a partially qualified ref through the refs/ search order
// (gitrevisions(7): `$GIT_DIR/<refname>`, then `refs/<refname>`, then
// refs/tags, refs/heads, refs/remotes), and rule two turns `heads/main` into
// refs/heads/main before anything else is tried. This function handled the
// fully spelled prefix and stopped exactly one level short of the spelling git
// also accepts, so what was left fell into the remote test below, which read
// `heads` as a remote nobody has and answered "" — no branch here, nothing to
// judge. Six spellings left through that "": the delete refspec, --delete, -d,
// --force, a destination written after a colon, and `git reset --hard`, which
// asks this same function the same question.
//
//   git push --dry-run --porcelain origin :heads/main
//     -> -  :refs/heads/main  [deleted]
//   git push --force --dry-run --porcelain origin heads/main
//     -> +  refs/heads/main:refs/heads/main  6b108ad...5cba7d4 (forced update)
//   git rev-parse --symbolic-full-name heads/main   -> refs/heads/main
//
// ONLY THAT ONE PREFIX, AND THE LIMIT WAS MEASURED, NOT REASONED ABOUT.
// `tags/main` is refs/TAGS/main and carries the same last word:
//   git push --dry-run --porcelain origin :tags/main
//     -> error: unable to delete 'tags/main': remote ref does not exist
//   git push --force --dry-run --porcelain origin main:tags/main
//     -> *  refs/heads/main:refs/heads/tags/main  [new branch]
// Neither line touches the branch, so a fix that read the LAST path component
// would have bought the six blocks above with two false refusals. `heads/` and
// `refs/heads/` name the branch namespace; no other prefix does.
//
// AND ONCE THE NAMESPACE IS WRITTEN DOWN, NO REMOTE IS HUNTED FOR IN WHAT
// FOLLOWS IT. The remote test used to run after the `refs/heads/` strip as
// well, so a branch literally NAMED `origin/main` had its own name eaten and
// was judged as `main` — a false refusal that was already shipped, because git
// reports that push as a branch CREATION and creating a branch rewrites
// nobody's history:
//   git push --force --dry-run --porcelain origin refs/heads/origin/main
//     -> *  refs/heads/origin/main:refs/heads/origin/main  [new branch]
// The remote test is for the bare `origin/x` spelling, which is the only one
// that has not already said which namespace it is in.
//
// NAMED LIMIT: a repo holding BOTH refs/heads/main and a branch actually called
// `heads/main` (refs/heads/heads/main) is read here as main — which is what git
// does too while refs/heads/main exists, since search order rule two beats rule
// four. If refs/heads/main were then deleted git would fall through to the
// literal branch, and this would still say main: a refusal of a push that
// rewrites nothing. It errs in that direction on purpose.
// native/partial_ref_test.sh holds every line above from both directions.
//
// It is one function because two callers need two different things out of the
// same answer: shared_branch() needs the yes/no, and a refusal has to PRINT the
// branch it is talking about. A message that re-derived the name would be a
// second derivation of it, and the two would drift.
inline string dest_name(const string& refIn) {
  string r = refIn;
  const size_t colon = r.rfind(':');            // src:dst — the destination decides
  if (colon != string::npos) r = r.substr(colon + 1);
  while (!r.empty() && r[0] == '+') r = r.substr(1);
  // the heads namespace, in both spellings git accepts for it. Written down, so
  // what follows is the branch name verbatim and no remote is looked for in it.
  if (r.compare(0, 11, "refs/heads/") == 0) return r.substr(11);
  if (r.compare(0, 6, "heads/") == 0) return r.substr(6);
  const size_t slash = r.find('/');
  if (slash != string::npos) {
    const string remote = r.substr(0, slash);
    if (remote != "origin" && remote != "upstream") return "";
    r = r.substr(slash + 1);
    if (r.find('/') != string::npos) return "";
  }
  return r;
}

inline bool shared_branch(const string& refIn) {
  const string r = dest_name(refIn);
  return r == "main" || r == "master" || r == "trunk" || r == "develop";
}

// `HEAD` and `@` are not branch names. They are the ref the repo resolves, and
// shared_branch() above is a NAME comparison: it strips a `+`, a `refs/heads/`
// prefix and a remote prefix, then compares what is left against four words.
// Both spellings survive every one of those strips because they need none, so
// the law read the word HEAD, found it in none of the four, and allowed
// `git push --force origin HEAD` while refusing the same push with the branch
// spelled out. git-push(1): "git push origin HEAD — A handy way to push the
// current branch to the same name on the remote." On main, HEAD IS main.
//
// The law already knew this. With NO refspec at all it reads .git/HEAD and
// resolves the current branch (see the refs.empty() case below); writing the
// word `HEAD` where the refspec goes turned that resolution off, because the
// argument was there, so nothing had to be resolved, so nothing was. This is
// that same resolution, applied to the two words that ask for it.
//
// THE COLON GOES THE OTHER WAY, AND IT WAS MEASURED, NOT REASONED ABOUT:
//   git push --dry-run --porcelain origin main:HEAD
//     -> refs/heads/main:refs/heads/HEAD   [new branch]
// A destination written after a colon is taken literally, so `HEAD` there is a
// branch called HEAD that git will CREATE on the remote — and creating a branch
// rewrites nobody's history. A fix that saw the word HEAD anywhere in a refspec
// would have bought this block with a false refusal.
//
// AND IT IS SCOPED TO PUSH. In `git reset --hard HEAD` the same word names a
// COMMIT, not a destination branch; resolving it there would turn the most
// ordinary line in git into a refusal on every shared branch. The hard-reset
// law below keeps reading names, on purpose. native/head_ref_test.sh holds all
// three of these from both directions.
//
// AND THE REPO IT RESOLVES IN IS NOT ALWAYS THE ONE THE SHELL IS IN. This used
// to take the project root and read `<root>/.git/HEAD`; it takes the git dir
// rbpath::git_dir_for() resolved off the same command line, because `-C`,
// `--git-dir` and $GIT_DIR are the words that make git operate somewhere else.
inline string current_branch(const string& gitDir);

inline string push_dest_ref(const string& refIn, const string& gitDir) {
  if (refIn.find(':') != string::npos) return refIn;   // the destination is written down
  string r = refIn;
  while (!r.empty() && r[0] == '+') r = r.substr(1);   // the force refspec form
  if (r != "HEAD" && r != "@") return refIn;
  return current_branch(gitDir);   // "" on a detached HEAD: it is on no branch
}

inline string current_branch(const string& gitDir) {
  if (gitDir.empty()) return "";       // no repo could be named from this line
  std::ifstream f(gitDir + "/HEAD");
  if (!f) return "";
  string h;
  std::getline(f, h);
  const string pre = "ref: refs/heads/";
  if (h.compare(0, pre.size(), pre) != 0) return "";
  string b = h.substr(pre.size());
  while (!b.empty() && (b.back() == '\n' || b.back() == '\r' || b.back() == ' ')) b.pop_back();
  return b;
}

// ---------- which remote a push with no operand goes to ----------------------
// `git push --force` names no remote, and the law used to answer that with the
// word `origin`. git answers it with a ladder, measured (git 2.39.5, --dry-run
// --porcelain, no remote operand, each rung beating the one below it):
//   branch.<cur>.pushRemote   ->  remote.pushDefault  ->  branch.<cur>.remote
// and with none of them set, origin.
//
// It decides WHICH remote.<name>.push is this push's refspec, so guessing it is
// wrong in both directions: `remote.backup.push=<x>:<main>` under
// remote.pushDefault=backup was a force-push of main the law read as origin's
// empty config, and reading origin's refspec for a push that goes to backup
// would be a refusal real git never earns.
inline string current_branch(const string& gitDir);

inline string push_remote(const vector<rbtext::Word>& t, size_t ci, size_t sub,
                          const string& gitDir) {
  const string cur = current_branch(gitDir);
  rbgitcfg::Value v;
  if (!cur.empty() &&
      rbgitcfg::last_value(t, ci, sub, gitDir, "branch." + cur + ".pushRemote", v) &&
      !v.text.empty())
    return v.text;
  if (rbgitcfg::last_value(t, ci, sub, gitDir, "remote.pushDefault", v) && !v.text.empty())
    return v.text;
  if (!cur.empty() && rbgitcfg::last_value(t, ci, sub, gitDir, "branch." + cur + ".remote", v) &&
      !v.text.empty())
    return v.text;
  return "origin";
}

// ---------- the refspace, for the pushes that do not name a branch ----------
// `--mirror` and `--all` push every branch there is. They carry no refspec, so
// the push law's "no refspec means the current branch" fallback answers with
// HEAD — and HEAD is not the target. Run from a feature branch, `git push --all
// --force origin` force-updates main and the fallback never looks at main.
//
// So for those two the target is read from the repo instead of from the line,
// in the two halves a mirror actually has:
//   * refs/heads/*   what gets force updated on the remote;
//   * refs/remotes/* (mirror only) what this clone knows is THERE. A mirror
//     makes the remote identical to this refspace, so a branch known only as a
//     remote-tracking ref is a branch the mirror REMOVES — the "deleted refs
//     will be removed from the remote end" half of git-push(1).
// Both are read from this repo alone; nothing here contacts a remote. Loose
// refs live as files under .git/refs, packed ones in .git/packed-refs, and a
// repo uses both at once after a gc, so both are read.
//
// The walk is bounded. A ref tree is small, but this runs inside a hook on
// every command, and an unbounded recursive walk of an attacker-shaped
// directory is a hang in the one place that must not hang.
inline void refs_under(const string& dir, const string& prefix, vector<string>& out, int depth) {
  if (depth > 8 || out.size() >= 4096) return;
  DIR* d = opendir(dir.c_str());
  if (!d) return;
  while (struct dirent* e = readdir(d)) {
    const string n = e->d_name;
    if (n == "." || n == "..") continue;
    const string full = dir + "/" + n;
    struct stat st;
    if (lstat(full.c_str(), &st) != 0) continue;      // lstat: a symlinked ref dir is not followed
    if (S_ISDIR(st.st_mode)) refs_under(full, prefix + n + "/", out, depth + 1);
    else out.push_back(prefix + n);
    if (out.size() >= 4096) break;
  }
  closedir(d);
}

// The sha a ref points at, loose file first and packed-refs after, because a
// repository uses both at once after a gc and a branch that has been packed is
// not a branch that stopped existing.
inline string ref_sha(const string& gitDir, const string& ref) {
  if (gitDir.empty()) return "";
  {
    std::ifstream f(gitDir + "/" + ref);
    string line;
    if (f && std::getline(f, line)) {
      while (!line.empty() && (line.back() == '\n' || line.back() == '\r' || line.back() == ' ')) line.pop_back();
      if (line.compare(0, 5, "ref: ") == 0) return ref_sha(gitDir, line.substr(5));
      if (line.size() >= 7) return line;
    }
  }
  std::ifstream pf(gitDir + "/packed-refs");
  string line;
  while (pf && std::getline(pf, line)) {
    if (line.empty() || line[0] == '#' || line[0] == '^') continue;
    const size_t sp = line.find(' ');
    if (sp == string::npos) continue;
    string name = line.substr(sp + 1);
    while (!name.empty() && (name.back() == '\n' || name.back() == '\r')) name.pop_back();
    if (name == ref) return line.substr(0, sp);
  }
  return "";
}

// Is this commit held anywhere a remote can hand it back? `git branch -D` is
// the override of git's own merged check, and what it discards is commits
// nothing else has. Comparing tips is deliberately cheap: this runs inside a
// hook with a 2.3ms budget and a commit-graph walk does not belong there. It
// errs toward refusing, and the refusal names `git branch -d` as the way out,
// which is git's own safe spelling and succeeds exactly when the work is safe.
inline bool sha_on_a_remote(const string& gitDir, const string& sha) {
  if (gitDir.empty() || sha.empty()) return false;
  vector<string> remotes;
  refs_under(gitDir + "/refs/remotes", "", remotes, 0);
  for (size_t i = 0; i < remotes.size(); i++)
    if (ref_sha(gitDir, "refs/remotes/" + remotes[i]) == sha) return true;
  std::ifstream pf(gitDir + "/packed-refs");
  string line;
  while (pf && std::getline(pf, line)) {
    if (line.empty() || line[0] == '#' || line[0] == '^') continue;
    const size_t sp = line.find(' ');
    if (sp == string::npos) continue;
    string name = line.substr(sp + 1);
    while (!name.empty() && (name.back() == '\n' || name.back() == '\r')) name.pop_back();
    if (name.compare(0, 13, "refs/remotes/") == 0 && line.compare(0, sp, sha) == 0) return true;
  }
  return false;
}

inline void refspace_branches(const string& gitDir, bool mirror, vector<string>& out) {
  if (gitDir.empty()) return;          // the same repo the branch fallback reads
  refs_under(gitDir + "/refs/heads", "", out, 0);
  if (mirror) refs_under(gitDir + "/refs/remotes", "", out, 0);
  std::ifstream f(gitDir + "/packed-refs");
  if (!f) return;
  string line;
  while (std::getline(f, line) && out.size() < 4096) {
    if (line.empty() || line[0] == '#' || line[0] == '^') continue;   // header, and a peeled tag
    const size_t sp = line.find(' ');
    if (sp == string::npos) continue;
    string ref = line.substr(sp + 1);
    while (!ref.empty() && (ref.back() == '\n' || ref.back() == '\r')) ref.pop_back();
    if (ref.compare(0, 11, "refs/heads/") == 0) out.push_back(ref.substr(11));
    else if (mirror && ref.compare(0, 13, "refs/remotes/") == 0) out.push_back(ref.substr(13));
  }
}

// ---------- git option walk: it lives in the parser now ----------------------
// `git --exec-path=/x push --force` slipped a hand-listed set (31.07) and the
// walk that replaced it was written here. It moved to cmdtext.h when
// `git -c alias.x='push --force' x` arrived: the walk was RIGHT — it stepped
// over `-c` and its value exactly as git does — and landing on `x` was still
// the wrong answer, because git resolves that token through the alias table the
// same `-c` options just built. Reading the options and resolving the
// subcommand is one question, and this file is not where a command is read.
using rbtext::git_subcommand;

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

// ---------- the laws ----------
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

// ---------- the destroyers that are not called rm ----------------------------
// What each verb takes apart, and which operand is the thing taken apart.
// Membership in the family is not the verdict, the flags are: `find` walks a
// tree and destroys only with a -delete primary or an -exec of a delete
// command, `rsync` only with --delete and then the DESTINATION empties rather
// than the source, `dd` only through of=, and `truncate` and the delete family
// always take apart what they name.
struct Destroy {
  bool isDestroy = false;
  const char* verb = "";
  const char* how = "";
  vector<string> targets;
};

inline Destroy destroy_of(const vector<rbtext::Word>& t) {
  Destroy d;
  const size_t ci = rbtext::command_index(t);
  if (ci >= t.size()) return d;
  const string base = rbtext::base_of(t[ci].text);

  if (rbtext::name_is(base, "find")) {
    // find's operands are the paths; everything from the first primary on is
    // the expression, and `!` and `(` open one too.
    bool inExpr = false, destroys = false;
    for (size_t i = ci + 1; i < t.size(); i++) {
      const string& s = t[i].text;
      if (!inExpr && (s == "!" || s == "(" || (s.size() > 1 && s[0] == '-'))) inExpr = true;
      if (s == "-delete") { destroys = true; d.how = "-delete removes every path the walk matches"; }
      if (s == "-exec" || s == "-execdir" || s == "-ok" || s == "-okdir") {
        // the command run per match is the NEXT word: rm is an argument here,
        // never the command word, which is why the walk above never saw it
        if (i + 1 < t.size() && rbpath::is_delete_command(rbtext::base_of(t[i + 1].text))) {
          destroys = true;
          d.how = "-exec runs a delete on every path the walk matches";
        }
      }
      if (!inExpr) d.targets.push_back(s);
    }
    if (!destroys || d.targets.empty()) return d;
    d.isDestroy = true; d.verb = "find";
    return d;
  }

  if (rbtext::name_is(base, "rsync")) {
    bool del = false; vector<string> operands;
    for (size_t i = ci + 1; i < t.size(); i++) {
      const string& s = t[i].text;
      if (s.size() > 1 && s[0] == '-') {
        if (s.compare(0, 8, "--delete") == 0) del = true;
        continue;
      }
      operands.push_back(s);
    }
    if (!del || operands.empty()) return d;
    d.isDestroy = true; d.verb = "rsync";
    d.how = "--delete removes everything in the destination the source does not have";
    d.targets.push_back(operands.back());
    return d;
  }

  if (rbtext::name_is(base, "truncate")) {
    for (size_t i = ci + 1; i < t.size(); i++) {
      const string& s = t[i].text;
      if (s == "-s" || s == "--size") { i++; continue; }   // the size is not a path
      if (s.size() > 1 && s[0] == '-') continue;
      d.targets.push_back(s);
    }
    if (d.targets.empty()) return d;
    d.isDestroy = true; d.verb = "truncate";
    d.how = "the contents go and the inode stays, so nothing about the file says it was emptied";
    return d;
  }

  if (rbtext::name_is(base, "dd")) {
    for (size_t i = ci + 1; i < t.size(); i++) {
      const string& s = t[i].text;
      if (s.compare(0, 3, "of=") == 0) d.targets.push_back(s.substr(3));
    }
    if (d.targets.empty()) return d;
    d.isDestroy = true; d.verb = "dd";
    d.how = "of= is opened for writing and overwritten in place";
    return d;
  }

  // shred, trash, unlink are already the delete family and delete_of already
  // reads their targets. They reached no law only because the rm-rf law asks
  // whether the command word is spelled rm.
  if (rbpath::is_delete_command(base) && !rbtext::name_is(base, "rm") &&
      !rbtext::name_is(base, "rmdir")) {
    const rbpath::Delete del = rbpath::delete_of(t);
    if (del.targets.empty()) return d;
    d.isDestroy = true; d.verb = "shred";
    d.how = "the contents are overwritten before the name is removed";
    d.targets = del.targets;
    return d;
  }
  return d;
}

inline bool check_parsed(const rbtext::Parsed& p, const string& cwd0, const string& root,
                         const vector<string>& disabled, Hit& hit) {
  const vector<string> cwds = rbpath::segment_cwds(p, cwd0);
  for (size_t s = 0; s < p.segs.size(); s++) {
    // A redirection destroys a file with no command on the line at all.
    // `> ROADMAP.md` opens it for writing and truncates it before anything
    // runs, and the parser has always carried redirections separately from
    // argv, so no law ever saw one. `>>` appends and is not a loss. /dev/ is
    // where output is thrown away on purpose, which is what the `2>/dev/null`
    // on almost every line in this repository is doing.
    if (!disabled_has(disabled, "baseline-truncating-redirect")) {
      for (size_t r = 0; r < p.segs[s].redirs.size(); r++) {
        const rbtext::Redir& rd = p.segs[s].redirs[r];
        if (rd.op.find('>') == string::npos || rbtext::redir_appends(rd)) continue;
        if (rd.target.empty() || rd.target.compare(0, 5, "/dev/") == 0) continue;
        // `2>&1` is a DESCRIPTOR DUPLICATION, not a write. It opens nothing,
        // creates nothing, truncates nothing, and there is no file named `1`
        // anywhere in it. The operator carries a `>`, so this law read it as a
        // truncating write to <cwd>/1, and whenever the segment's cwd sat
        // outside the tree the session started in, it refused the command.
        //
        // Measured the night it was found: four of five agent sessions were
        // refused on their first or second command, every one on the shape
        //
        //     cd <another repo> && <anything> 2>&1
        //
        // which is on nearly every line an agent writes. A false refusal is the
        // expensive kind of wrong here. A missed catch costs one incident; a
        // refusal the operator knows is wrong costs their belief in every other
        // refusal, and the tool gets switched off after that. It was switched
        // off that night, at 02:25, by a session that is not in this file.
        //
        // The test is the operator ENDING in `&`, which is the only thing that
        // makes a duplication: `>&`, `1>&`, `2>&`. `&> file` ends in `>` and IS
        // a write to `file`, so it is untouched. A duplication's target is a
        // descriptor number, or `-` to close it, and never a path.
        if (!rd.op.empty() && rd.op.back() == '&') {
          bool fd = rd.target == "-";
          if (!fd) {
            fd = true;
            for (char c : rd.target) if (c < '0' || c > '9') { fd = false; break; }
          }
          if (fd) continue;
        }
        const Land L = land_of(rd.target, cwds[s], root);
        if (L.where != rbpath::ESCAPES) continue;
        hit = {"baseline-truncating-redirect",
               "a redirection empties the file it points at, and there is no command on the line to name",
               "'" + rd.op + " " + rd.target + "' resolves to " + L.real +
               ", outside the project tree (" + root + ") — the contents are gone before anything runs"};
        return true;
      }
    }
    if (check_segment(p.segs[s].words, cwds[s], root, disabled, hit)) return true;
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

    // `-C <dir>` and `--git-dir` move which repository the verb acts on, and
    // every law below has to ask the same repository the shell will. Read once
    // per segment rather than once per law: the answer cannot differ between
    // them, and a second walk is a second answer to the same question.
    vector<string> chdirs;
    string gitDirOpt;
    const bool repoElsewhere = rbtext::git_repo_knobs(t, ci, sub, chdirs, gitDirOpt);
    (void)repoElsewhere;

    if (subcmd == "push") {
      // TWO LAWS, TWO SWITCHES. A repo that silenced the force-push law because
      // one person rewrites their own trunk did not thereby agree to that trunk
      // being DELETED, so each is asked for by name and the walk below still
      // runs when only one of them is off.
      const bool noForce = disabled_has(disabled, "baseline-force-push");
      const bool noDelete = disabled_has(disabled, "baseline-branch-delete");
      if (noForce && noDelete) return false;

      // ---- WHICH REPO this line pushes from ---------------------------------
      // Not `root`. `git -C ../other push --force origin`,
      // `git --git-dir=../other/.git ... push --force origin` and
      // `GIT_DIR=../other/.git git push --force origin` all operate on a repo
      // the shell is not standing in, so every question below that has to be
      // answered by READING a repo — which branch is checked out, which
      // branches exist — is answered in the one git will use. The parser reads
      // the words (it already stepped over them to find `push`); pathres.h
      // resolves where they land; nothing here has a second idea of either.
      //
      // The `cd` sibling is the same bug and closes with the same line:
      // `cd ../other && git push --force origin` was judged against the repo
      // the line STARTED in, because the root was resolved once per command
      // line while the cwd is tracked per segment. This resolves from the
      // segment's own cwd.
      const bool elsewhere = repoElsewhere;
      const string gdir = rbpath::git_dir_for(cwd, chdirs, gitDirOpt);
      // named in the refusal only when the LINE pointed git somewhere else: an
      // operator who is told 'main' about a repo she is not in has to be told
      // which repo that is.
      const string inRepo = (elsewhere && !gdir.empty()) ? " in the repo at " + gdir : string();

      bool force = false, lease = false, mirror = false, all = false, del = false;
      // `--tags` is the one option that REPLACES the default refspec with
      // something that is not a branch, and `matching` is the one config value
      // that widens it to every branch. Both decide what an unnamed push writes.
      bool tags = false, matching = false;
      vector<string> operands;
      for (size_t i = sub + 1; i < t.size(); i++) {
        const string& s = t[i].text;
        // A LEASE IS NOT AN EXCUSE, IT IS ONLY A SENTENCE. This used to set a
        // boolean that switched the whole law off, so `--force-with-lease
        // --force origin main` and `--force-if-includes --force origin main`
        // both walked past the compiled floor while the same push MINUS the
        // word that is supposed to make it safer was refused.
        //
        // The tempting reading is that git resolves the two last-one-wins and
        // the bug is the ORDER. It does not. Measured against git 2.39.5 with
        // real pushes into a bare repo and a genuinely STALE lease (a second
        // clone pushed a commit the first has never fetched):
        //
        //   --force-with-lease              ! [rejected] (stale info)
        //   --force-if-includes             ! [rejected] (fetch first)
        //   --force-with-lease --force      + main -> main (forced update)
        //   --force --force-with-lease      + main -> main (forced update)
        //   -f --force-with-lease           + main -> main (forced update)
        //   --force-if-includes --force     + main -> main (forced update)
        //   --force-with-lease origin +main + main -> main (forced update)
        //
        // The remote lost the other clone's commit on every one of the last
        // five. `--force` sets a transport flag and the lease populates a
        // compare-and-swap entry; a forced ref update is never asked to clear
        // the CAS, so the force wins from EITHER side of the line. A law built
        // on the position of the last force-ish token would have refused the
        // first spelling and gone on allowing the second — the one measured
        // above destroying a commit.
        //
        // So the walk no longer asks where the lease sits. It records only that
        // one was written, and that fact is spent on the refusal's wording:
        // telling someone who wrote a lease to "use --force-with-lease" is
        // advice they already followed. The two spellings alone still pass,
        // because with no explicit force this law never fires.
        if (s.compare(0, 18, "--force-with-lease") == 0 ||
            s.compare(0, 19, "--force-if-includes") == 0) { lease = true; continue; }
        if (s == "--force" || s == "-f") { force = true; continue; }
        // git-push(1): "--delete — All listed refs are deleted from the remote
        // repository. This is the same as prefixing all refs with a colon."
        // git's own words: the switch and the colon are one operation.
        //
        // `-fd` and `-qd` are this same switch written in a cluster, and they
        // are NOT read here: cmdtext.h splits a short-option cluster into the
        // options it stands for before any law sees the words, so `-d` arrives
        // as its own token. A second reading of the cluster in this file would
        // be a second answer to a question the parser has already answered —
        // the divergence this whole layer exists to end.
        if (s == "--delete" || s == "-d") { del = true; continue; }
        // --mirror IS the force, and it is spelled with none of the three
        // tokens above. git-push(1): "locally updated refs will be force
        // updated on the remote end, and deleted refs will be removed from the
        // remote end." The strongest destructive push git has was reaching this
        // walk as just another option to skip.
        if (s == "--mirror") { mirror = true; force = true; continue; }
        if (s == "--all") { all = true; continue; }         // not force by itself
        // git-push(1): "--tags — All refs under refs/tags are pushed, in
        // addition to refspecs explicitly listed on the command line." With no
        // refspec listed there is nothing to add them to, so this line writes
        // TAGS AND NO BRANCH. Measured from `main` with an upstream set:
        // `git push --tags --force origin` reports `v1 -> v1` and nothing else.
        // The law refused it anyway, because the fallback below asked which
        // branch was checked out — a question this line does not raise.
        // `--follow-tags` is the opposite word: the ordinary refspec PLUS tags,
        // measured as `main -> main (forced update)`, and it is not this token.
        if (s == "--tags") { tags = true; continue; }
        if (!s.empty() && s[0] == '-') continue;
        if (!s.empty() && s[0] == '+') force = true;       // the canonical force refspec
        operands.push_back(s);
      }

      // operands are <remote> [<refspec>...]. The ref words are taken off ONCE,
      // here, because both laws below judge the same words and a second
      // derivation of them is a second answer to the same question.
      const vector<string> named(operands.begin() + (operands.empty() ? 0 : 1), operands.end());

      // ---- the branch REMOVED from the remote --------------------------------
      // A refspec is <src>:<dst>. An empty source side means "put nothing where
      // dst is", which is git's spelling for a deletion:
      //
      //     git push origin :main
      //
      // It begins with ':' and not '+', so the force predicate above never
      // fired, `if (force && ...)` was false, and the walk returned before the
      // branch name was ever consulted — though dest_name() splits at the colon
      // and had the answer `main` waiting the whole time. Both layers missed it
      // together: a project's own deny regex hunts for `--force|-f`, and there
      // is no `-f` in a deletion either.
      //
      // It gets its own id because it is not a force-push and the remedy is not
      // the same sentence. A force-push replaces history other people already
      // have; a deletion removes the branch and every commit reachable only
      // from it, and the remote keeps no reflog to walk back through.
      if (!noDelete) {
        for (const string& raw : named) {
          string spec = raw;
          while (!spec.empty() && spec[0] == '+') spec = spec.substr(1);
          // `git push origin :` is the matching-refs form and deletes nothing,
          // so the colon has to have a destination after it.
          const bool emptySource = spec.size() > 1 && spec[0] == ':';
          if (!del && !emptySource) continue;   // an ordinary push writes, it does not remove
          if (!shared_branch(raw)) continue;
          hit = {"baseline-branch-delete",
                 "deleting a shared branch removes it for everyone, with every commit reachable "
                 "only from it, and the remote keeps no reflog to walk back through",
                 "git push deletes shared branch '" + dest_name(raw) + "' on the remote (written "
                 "as '" + raw + "') — delete your own branch instead, or silence "
                 "baseline-branch-delete by id"};
          return true;
        }
      }

      // `force` is set only by an UNCONDITIONAL force: --force, -f, --mirror,
      // or a leading + on the refspec. A lease written beside any of them is
      // overridden by git (measured above, in both orders and on the +refspec),
      // so it is not consulted here — the question this law asks is whether the
      // line carries a force, not whether it also carries an apology for one.
      if (!noForce && force) {
        // with no refspec git pushes the current branch, so HEAD is the target
        // — unless the line asked for the whole refspace, in which case HEAD is
        // not the target and the repo is.
        vector<string> refs = named;

        // ---- where a refspec comes from when the line does not carry one ----
        // A push that names no refspec has not thereby asked for HEAD. git asks
        // in order: --all/--mirror (above), then remote.<name>.push, then
        // push.default, and only then the current branch. This line can set the
        // middle two itself, because `-c` builds git's config from the same
        // command line — the same shape as the alias hole one layer over, and
        // the same answer: what the line writes down is not unknown.
        //
        // Reading .git/HEAD first answered a different question than the one
        // asked, so both spellings below were refused only in the accident that
        // the shell already sat on main:
        //   git -c remote.origin.push=refs/heads/x:refs/heads/main push --force origin
        //   git -c push.default=matching push --force origin
        //
        // Measured against git 2.39.5 with --dry-run, from `feat`, main
        // rewritten so it is a real non-fast-forward: the first reports
        // `+ feat -> main (forced update)`, the second `+ main -> main (forced
        // update)`. Neither consulted HEAD. With no remote operand the default
        // remote is origin, measured the same way.
        //
        // AND THE SAME TWO KEYS OUT OF THE FILES, WHICH IS WHERE THE LIMIT USED
        // TO BE. This law used to stop at the command line and say so:
        //
        //   NAMED LIMIT: the same two keys can also be set in .git/config,
        //   ~/.gitconfig or /etc/gitconfig, and none of those are in this
        //   command line. Reading only the repo's file would report the other
        //   two as absent, which is a worse answer than a named limit.
        //
        // That reason argues for reading all three. It does not argue for
        // reading none, and reading none cost the whole law to two ordinary
        // commands one turn apart:
        //
        //   git config remote.origin.push refs/heads/scratch:refs/heads/main
        //   git push --force origin
        //
        // Neither line contains `main` or a refspec, so a project's deny regex
        // misses both, and the compiled law read .git/HEAD, saw `scratch` and
        // allowed the second one. Measured against this gate before the fix:
        // exit 0, and exit 0 for the `push.default matching` spelling too.
        // gitcfg.h reads every file git reads, in git's order, and appends the
        // `-c` pairs of THIS line last — which is also the order the values
        // accumulate in, measured: a refspec in ~/.gitconfig and one in
        // .git/config are BOTH pushed, so a reader that let the nearer file win
        // would read half the command.
        string viaCfg, matchOrigin, cfgKey;
        vector<string> refOrigin;             // parallel to refs while they come from config
        if (refs.empty() && !mirror && !all) {
          cfgKey = "remote." + (operands.empty() ? push_remote(t, ci, sub, gdir) : operands[0]) +
                   ".push";
          vector<rbgitcfg::Value> cfg;
          rbgitcfg::values(t, ci, sub, gdir, cfgKey, cfg);
          for (size_t k = 0; k < cfg.size(); k++) {
            refs.push_back(cfg[k].text);
            refOrigin.push_back(cfg[k].origin);
          }
          if (refs.empty()) {
            // `matching` means every branch that exists on both sides, so the
            // target is the refspace and not HEAD. Every other value
            // (simple, current, upstream, nothing) resolves to the current
            // branch, which the fallback below already answers correctly.
            // push.default is SINGLE-valued and the last definition wins, so
            // this asks for the last one and not for any one: measured,
            // global=matching under repo=simple is not matching.
            rbgitcfg::Value pd;
            if (rbgitcfg::last_value(t, ci, sub, gdir, "push.default", pd) &&
                pd.text == "matching") {
              all = true;
              matching = true;
              matchOrigin = pd.origin;
            }
          }
        }

        if (refs.empty() && (mirror || all)) {
          refspace_branches(gdir, mirror, refs);
          // A mirror onto a remote makes that remote identical to this
          // refspace. An empty or unreadable one is not the harmless case: it
          // is the case where every branch the remote has gets removed.
          if (mirror && refs.empty()) {
            hit = {"baseline-force-push",
                   "a mirror push makes the remote identical to this repo's refs, force-updating "
                   "what is here and removing what is only there",
                   "git push --mirror from a repo whose refs cannot be read or hold no branch" +
                       inRepo +
                       " — it would empty the remote; name the branch you mean, or silence "
                       "baseline-force-push by id"};
            return true;
          }
        }
        // and only now HEAD — unless the line replaced the default refspec with
        // tags, in which case this push writes no branch at all.
        if (refs.empty() && !tags) {
          const string b = current_branch(gdir);
          if (!b.empty()) refs.push_back(b);
        }
        for (size_t k = 0; k < refs.size(); k++) {
          const string& raw = refs[k];
          // `HEAD` and `@` name no branch; they ask the repo which one it is on.
          // Every other spelling reaches the name comparison untouched.
          const string r = push_dest_ref(raw, gdir);
          if (r.empty()) continue;
          if (!shared_branch(r)) continue;
          // an operator told 'main' about a line that says neither `main` nor a
          // refspec cannot act on that sentence. It has to name the key AND the
          // file the value was read out of.
          if (k < refOrigin.size()) viaCfg = " (" + cfgKey + " " + refOrigin[k] + " names it)";
          if (mirror || all) {
            const string flag =
                mirror ? "--mirror"
                       : (matching ? "with push.default=matching (" + matchOrigin + ")"
                                   : "--all --force");
            hit = {"baseline-force-push",
                   "a force-push to a shared branch rewrites history other people already have",
                   "git push " + flag + " writes every branch, and '" + r + "' is one of them" +
                       inRepo + " — name the branch you mean, or push to your own branch"};
          } else {
            // NAME THE BRANCH, NOT THE SPELLING. `r` may still be a whole
            // refspec — a config value is one — and a refusal that reads
            // "shared branch 'refs/heads/x:refs/heads/main'" names something
            // that is not a branch. dest_name() is the function that already
            // answered which branch this writes, and shared_branch() next to it
            // just said yes to that answer; printing anything else here would
            // be a second derivation of it.
            const string b = dest_name(r);
            // when the branch was not the word the line carried, say both: the
            // operator asked about HEAD, or about a refspec out of a file, and
            // needs to be told which branch that is
            const string wrote = (b == raw) ? string() : " (written as " + raw + ")";
            // Someone who WROTE a lease and is refused anyway must not be told
            // to use one. The remedy for that line is the opposite word: take
            // the --force off and the lease they already wrote does its job.
            const string advice =
                lease ? " — the --force cancels the lease (git forces the update from either "
                        "side of the line), so drop the --force and the lease stands"
                      : " — use --force-with-lease, or push to your own branch";
            hit = {"baseline-force-push",
                   "a force-push to a shared branch rewrites history other people already have",
                   "force-push to shared branch '" + b + "'" + wrote + inRepo + viaCfg + advice};
          }
          return true;
        }
      }
      return false;
    }

    if (subcmd == "reset" && !disabled_has(disabled, "baseline-hard-reset")) {
      bool hard = false;
      for (size_t i = sub + 1; i < t.size(); i++) if (t[i].text == "--hard") hard = true;
      if (!hard) return false;
      const string gdir = rbpath::git_dir_for(cwd, chdirs, gitDirOpt);
      for (size_t i = sub + 1; i < t.size(); i++) {
        string s = t[i].text;
        if (!s.empty() && s[0] == '-') continue;
        // The law used to compare the WORD against main/master/trunk/develop, so
        // every other way of naming the same commit walked past it. git resolves
        // three of them and they were all still open in the red-team corpus:
        //   @{u} and @{upstream}      the upstream of the current branch, read
        //                             out of branch.<cur>.merge
        //   refs/remotes/origin/main  the same ref, fully spelled
        //   origin/main               the one spelling the law already knew
        // Measured: `git rev-parse --symbolic-full-name @{upstream}` on a branch
        // tracking origin/main answers refs/remotes/origin/main. So the ref is
        // RESOLVED and then judged, which is what keeps a fourth spelling from
        // being a fourth hole.
        string shown = s;
        if (s == "@{u}" || s == "@{upstream}" || s == "@{U}") {
          const string cur = current_branch(gdir);
          rbgitcfg::Value v;
          if (!cur.empty() &&
              rbgitcfg::last_value(t, ci, sub, gdir, "branch." + cur + ".merge", v) &&
              !v.text.empty()) {
            s = v.text;
            if (s.compare(0, 11, "refs/heads/") == 0) s = s.substr(11);
          }
        }
        if (s.compare(0, 13, "refs/remotes/") == 0) {
          const string rest = s.substr(13);
          const size_t sl = rest.find('/');
          if (sl != string::npos) s = rest.substr(sl + 1);
        }
        if (!shared_branch(s)) continue;
        hit = {"baseline-hard-reset",
               "a hard reset onto a shared branch discards local work with no way back",
               "git reset --hard onto '" + shown + "'" +
               (shown == s ? "" : " (which resolves to '" + s + "')") +
               " — commit or stash first, or reset to a local ref"};
        return true;
      }
      return false;
    }

    // ---- the verbs that lose work without ever saying push ------------------
    // Every spelling the push law learned was a spelling of ONE verb. git ships
    // others that discard just as permanently, and the corpus collected them
    // because the law names none of them: a branch delete that overrides git's
    // own merged check, a clean that takes files git never tracked, and the two
    // commands that remove the way back.

    if (subcmd == "branch" && !disabled_has(disabled, "baseline-branch-discard")) {
      // `-d` is safe: git itself refuses it on an unmerged branch. `-D` and
      // `--delete --force` are the override of that check, and what they discard
      // is commits nothing else holds. So the law is not "protect main" — on a
      // repo with a remote, deleting main locally is recoverable by checkout,
      // measured in git_verbs_test.sh section 0. What is unrecoverable is a tip
      // no remote has, whatever the branch is called.
      bool force = false, del = false;
      string target;
      for (size_t i = sub + 1; i < t.size(); i++) {
        const string& w = t[i].text;
        if (w == "-D") { del = true; force = true; continue; }
        if (w == "--delete" || w == "-d") { del = true; continue; }
        if (w == "--force" || w == "-f") { force = true; continue; }
        if (!w.empty() && w[0] == '-') continue;
        if (target.empty()) target = w;
      }
      if (del && force && !target.empty()) {
        const string gdir = rbpath::git_dir_for(cwd, chdirs, gitDirOpt);
        const string sha = ref_sha(gdir, "refs/heads/" + target);
        // no such branch: git will refuse it itself and there is nothing to lose
        if (!sha.empty() && !sha_on_a_remote(gdir, sha)) {
          hit = {"baseline-branch-discard",
                 "force-deleting a branch no remote holds discards those commits with no way back",
                 "git branch -D '" + target + "' — its tip " + sha.substr(0, 8) +
                 " is on no remote. push it, or use `git branch -d " + target +
                 "` which git allows once the work is merged"};
          return true;
        }
      }
      return false;
    }

    if (subcmd == "clean" && !disabled_has(disabled, "baseline-clean-ignored")) {
      // -x is the flag that takes IGNORED files too, which is where the loss
      // lives: .env, local config, a build nobody can reproduce. Measured in
      // section 0 — `clean -xfd -n` lists .gitignore and an ignored file. A
      // dry run is a question and always allowed; `clean -fd` without -x only
      // takes untracked-and-not-ignored files and stays allowed.
      bool x = false, force = false, dry = false;
      for (size_t i = sub + 1; i < t.size(); i++) {
        const string& w = t[i].text;
        if (w == "--dry-run") { dry = true; continue; }
        if (w == "-x" || w == "--force-x") { x = true; continue; }
        if (w == "--force") { force = true; continue; }
        if (w.size() > 1 && w[0] == '-' && w[1] != '-') {
          for (size_t k = 1; k < w.size(); k++) {
            if (w[k] == 'x' || w[k] == 'X') x = true;
            else if (w[k] == 'f') force = true;
            else if (w[k] == 'n') dry = true;
          }
        }
      }
      if (x && force && !dry) {
        hit = {"baseline-clean-ignored",
               "git clean -x removes ignored files, which is everything git was never watching",
               "git clean with -x takes ignored files too (.env, local config, build output) — "
               "run it with -n first to see the list, or drop the -x"};
        return true;
      }
      return false;
    }

    if ((subcmd == "reflog" || subcmd == "gc") &&
        !disabled_has(disabled, "baseline-reflog-drop")) {
      // The two laws above lean on one assumption: a bad reset or a bad delete
      // can be undone because the reflog still holds the old tip. These two
      // commands remove that, and after them the other refusals are advice about
      // something already gone.
      bool now = false;
      for (size_t i = sub + 1; i < t.size(); i++) {
        const string& w = t[i].text;
        const size_t eq = w.find('=');
        if (eq == string::npos) continue;
        const string k = w.substr(0, eq), v = w.substr(eq + 1);
        if ((k == "--expire" || k == "--expire-unreachable" || k == "--prune") &&
            (v == "now" || v == "all" || v == "0"))
          now = true;
      }
      if (now) {
        hit = {"baseline-reflog-drop",
               "expiring the reflog now removes the only record of where a branch used to point",
               "git " + subcmd + " with an immediate expiry throws away the way back from a bad "
               "reset or delete — leave a window (--expire=90.days.ago), or run it after the work is pushed"};
        return true;
      }
      return false;
    }
    return false;
  }

  // ---- the same loss, spelled without the word rm -------------------------
  // The law below this one asks whether the command word is `rm` and whether
  // it carries -r, which is the shape of exactly one of the ways to empty a
  // tree. `find -delete` is a recursive delete written as a search, `rsync
  // --delete` empties a destination by synchronising an empty source onto it,
  // `truncate` and `dd` leave the inode and take everything in it, and shred
  // was in the delete family the whole time. The containment question is
  // identical for all of them, so it is asked with the same land_of the rm law
  // uses: inside the project git can undo it, outside nothing can.
  if (!disabled_has(disabled, "baseline-delete-not-rm")) {
    const Destroy dz = destroy_of(t);
    if (dz.isDestroy) {
      const bool scratchCwd0 = is_temp_root(root);
      for (const string& raw : dz.targets) {
        const Land L = land_of(raw, cwd, scratchCwd0 ? string() : root);
        if (L.where != rbpath::ESCAPES) continue;
        hit = {"baseline-delete-not-rm",
               string("`") + dz.verb + "` destroys outside the project tree, where git cannot undo it",
               string(dz.verb) + " on '" + raw + "' " + (L.rewritten ? "expands to " : "resolves to ") +
               L.real + ", outside the project tree (" + root + ") — " + dz.how};
        return true;
      }
    }
  }

  if (!disabled_has(disabled, "baseline-rm-rf-outside")) {
    const rbpath::Delete d = rbpath::delete_of(t);
    if (!d.isDelete || !rbtext::name_is(name, "rm")) return false;

    // THE SWITCH AND THE LEDGER, before anything else here gets a say.
    //
    // Measured in an isolated lab: enforce mode refused `git push --force origin
    // main` with exit 2; `rm -f <rabadon home>/enabled` returned exit 0 and was
    // allowed; the identical force-push then returned exit 0. `rm -rf <rabadon
    // home>` was allowed too, which is the whole ledger — every refusal, every
    // wrong-refusal record, every hash chain — in one line. Nothing in this file
    // saw any of it.
    //
    // It sits ABOVE the recursive test because the switch is a single file and
    // `rm -f` on it needs no -r, and OUTSIDE the temp carve-out because
    // RABADON_DIR legitimately points into a temp tree during tests and a law
    // that waives itself there is a law an agent can arrange to be waived.
    //
    // This does not make the switch unremovable. An operator who owns the disk
    // owns it, and the tool says so. It makes the AGENT unable to reach it
    // through the one surface rabadon actually mediates, which is the surface
    // that removed it in the first place.
    if (!disabled_has(disabled, "baseline-supervision-tamper")) {
      const string rdir = rbpath::norm_dir(rbpath::rabadon_dir());
      for (size_t i = 0; i < d.targets.size(); i++) {
        const string abs = rbpath::lexical_abs(d.targets[i], cwd);
        if (abs.empty()) continue;
        const string absDir = rbpath::norm_dir(abs);
        // The directory itself, or something UNDER it — and "under" means the
        // next character is a separator. norm_dir drops the trailing slash, so
        // a bare prefix test made `<home>foo/x` a child of `<home>`, and the
        // twin that had to pass was refused. This file's own comment names the
        // trap forty lines up: a prefix is where an escape hides. It is also
        // where a false refusal hides, which is the same mistake pointing the
        // other way.
        const bool self = absDir == rdir;
        const bool under = absDir.size() > rdir.size() &&
                           absDir.compare(0, rdir.size(), rdir) == 0 &&
                           absDir[rdir.size()] == '/';
        if (!self && !under) continue;
        hit = {"baseline-supervision-tamper",
               "this deletes rabadon's own switch or ledger, which is the record that would "
               "have shown the deletion",
               "rm on '" + d.targets[i] + "' resolves inside " + rdir +
               " — that tree holds the enforce switch and the hash-chained ledger. Turning "
               "supervision off is `rabadon off`, which writes the change down; removing the "
               "file does the same thing with no record. Silence baseline-supervision-tamper "
               "by id if this is really what you meant."};
        return true;
      }
    }

    if (!d.recursive) return false;

    // The repository's own .git, which the delete law above cannot see because
    // it is INSIDE the tree the law carves out. That carve-out exists for one
    // reason, that git can undo a delete inside the project — and this is the
    // delete that removes the thing doing the undoing. It takes the index, the
    // reflog, every unpushed commit and every stash in one line, and the two git
    // laws above are advice about a recovery path that is gone.
    if (!disabled_has(disabled, "baseline-git-dir-delete")) {
      for (size_t i = 0; i < d.targets.size(); i++) {
        const string abs = rbpath::lexical_abs(d.targets[i], cwd);
        const size_t sl = abs.rfind('/');
        const string leaf = sl == string::npos ? abs : abs.substr(sl + 1);
        if (leaf != ".git") continue;
        struct stat st;
        if (stat(abs.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) continue;
        hit = {"baseline-git-dir-delete",
               "deleting .git removes the history, the reflog and every unpushed commit at once",
               "rm -rf on '" + d.targets[i] + "' takes the repository itself, which is what every "
               "other refusal here assumes is still there — delete the working tree instead if "
               "that is what you meant"};
        return true;
      }
    }
    // The project tree is the carve-out because git can undo a delete inside it.
    // With no worktree above cwd that tree falls back to cwd ITSELF, and if the
    // shell is sitting in the shared temp root the fallback hands back exactly
    // what the temp law refuses: `cd /tmp && rm -rf *` would be "inside the
    // project". A directory every process on the machine writes into is not a
    // project, so the fallback does not apply there and the temp law judges
    // those targets — `cd /tmp && rm -rf my-scratch` still passes, and a real
    // project that merely LIVES under /tmp (root /tmp/work) is untouched.
    const bool scratchCwd = is_temp_root(root);
    static const string why =
        "a recursive delete outside the project tree cannot be undone by git";
    for (const string& raw : d.targets) {
      // where every word the shell can make of this target lands — the
      // destination, not the spelling. pathres.h computes it, and rules.h asks
      // the same function about the same target one layer up.
      const Land L = land_of(raw, cwd, scratchCwd ? string() : root);
      if (L.where == rbpath::WAIVED || L.where == rbpath::CONTAINED) continue;
      if (L.where == rbpath::UNCOMPUTABLE) {
        hit = {"baseline-rm-rf-outside", why,
               "rm -r '" + raw + "' expands to more than 256 words, so where it lands cannot be "
               "computed — name the paths, or silence baseline-rm-rf-outside by id"};
        return true;
      }
      hit = {"baseline-rm-rf-outside", why,
             "rm -r '" + raw + "' " + (L.rewritten ? "expands to " : "resolves to ") + L.real +
             (scratchCwd ? ", and cwd is the shared temp root itself (" + root +
                           "), which is not a project tree"
                         : ", outside the project tree (" + root + ")")};
      return true;
    }
  }
  return false;
}

// The entry point: true = one of the laws refuses this command.
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
    // a redirection destroys with no command word to read, so a segment that
    // carries one is relevant before its argv is looked at
    for (size_t r = 0; r < p.segs[s].redirs.size() && !relevant; r++)
      relevant = p.segs[s].redirs[r].op.find('>') != string::npos;
    const size_t ci = rbtext::command_index(p.segs[s].words);
    if (ci >= p.segs[s].words.size()) continue;
    const string b = rbtext::base_of(p.segs[s].words[ci].text);
    relevant = relevant || rbtext::name_is(b, "git") || rbpath::is_delete_command(b) ||
               rbtext::is_content_destroyer(b);
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
  if (!rbtext::mentions_acted_on(command)) return false;
  return check_parsed(rbtext::parse(command), cwd, disabled, hit);
}

}  // namespace rbbase
