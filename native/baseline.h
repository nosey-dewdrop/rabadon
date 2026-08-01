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
//                           each recognized. --force-with-lease is legitimate
//                           and passes.
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
// removed), a leading `+` is the force marker, `refs/heads/x` is `x` written
// out, and `origin/x` is `x` on a remote. "" when the operand names no branch
// at all — a tag, a nested path, some other remote's namespace.
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
  if (r.compare(0, 11, "refs/heads/") == 0) r = r.substr(11);
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
inline string current_branch(const string& root);

inline string push_dest_ref(const string& refIn, const string& root) {
  if (refIn.find(':') != string::npos) return refIn;   // the destination is written down
  string r = refIn;
  while (!r.empty() && r[0] == '+') r = r.substr(1);   // the force refspec form
  if (r != "HEAD" && r != "@") return refIn;
  return current_branch(root);   // "" on a detached HEAD: it is on no branch
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

inline void refspace_branches(const string& root, bool mirror, vector<string>& out) {
  refs_under(root + "/.git/refs/heads", "", out, 0);
  if (mirror) refs_under(root + "/.git/refs/remotes", "", out, 0);
  std::ifstream f(root + "/.git/packed-refs");
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

inline bool check_parsed(const rbtext::Parsed& p, const string& cwd0, const string& root,
                         const vector<string>& disabled, Hit& hit) {
  const vector<string> cwds = rbpath::segment_cwds(p, cwd0);
  for (size_t s = 0; s < p.segs.size(); s++)
    if (check_segment(p.segs[s].words, cwds[s], root, disabled, hit)) return true;
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

    if (subcmd == "push") {
      // TWO LAWS, TWO SWITCHES. A repo that silenced the force-push law because
      // one person rewrites their own trunk did not thereby agree to that trunk
      // being DELETED, so each is asked for by name and the walk below still
      // runs when only one of them is off.
      const bool noForce = disabled_has(disabled, "baseline-force-push");
      const bool noDelete = disabled_has(disabled, "baseline-branch-delete");
      if (noForce && noDelete) return false;
      bool force = false, lease = false, mirror = false, all = false, del = false;
      // `--tags` is the one option that REPLACES the default refspec with
      // something that is not a branch, and `matching` is the one config value
      // that widens it to every branch. Both decide what an unnamed push writes.
      bool tags = false, matching = false;
      vector<string> operands;
      for (size_t i = sub + 1; i < t.size(); i++) {
        const string& s = t[i].text;
        if (s.compare(0, 18, "--force-with-lease") == 0 ||
            s.compare(0, 20, "--force-if-includes") == 0) { lease = true; continue; }
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

      // A lease is a promise about what ONE ref currently points at. A mirror
      // deletes refs the lease never named, so the lease excuses --force and
      // does not excuse --mirror.
      if (!noForce && force && (!lease || mirror)) {
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
        // NAMED LIMIT: the same two keys can also be set in .git/config,
        // ~/.gitconfig or /etc/gitconfig, and none of those are in this command
        // line. This law judges what the LINE says. Reading only the repo's file
        // would report the other two as absent, which is a worse answer than a
        // named limit.
        string viaCfg;
        if (refs.empty() && !mirror && !all) {
          const string remote = operands.empty() ? string("origin") : operands[0];
          rbtext::git_config_values(t, ci, sub, "remote." + remote + ".push", refs);
          if (!refs.empty())
            viaCfg = " (remote." + remote + ".push on this command line names it)";
          if (refs.empty()) {
            vector<string> pd;
            rbtext::git_config_values(t, ci, sub, "push.default", pd);
            // `matching` means every branch that exists on both sides, so the
            // target is the refspace and not HEAD. Every other value
            // (simple, current, upstream, nothing) resolves to the current
            // branch, which the fallback below already answers correctly.
            if (!pd.empty() && pd.back() == "matching") { all = true; matching = true; }
          }
        }

        if (refs.empty() && (mirror || all)) {
          refspace_branches(root, mirror, refs);
          // A mirror onto a remote makes that remote identical to this
          // refspace. An empty or unreadable one is not the harmless case: it
          // is the case where every branch the remote has gets removed.
          if (mirror && refs.empty()) {
            hit = {"baseline-force-push",
                   "a mirror push makes the remote identical to this repo's refs, force-updating "
                   "what is here and removing what is only there",
                   "git push --mirror from a repo whose refs cannot be read or hold no branch — "
                   "it would empty the remote; name the branch you mean, or silence "
                   "baseline-force-push by id"};
            return true;
          }
        }
        // and only now HEAD — unless the line replaced the default refspec with
        // tags, in which case this push writes no branch at all.
        if (refs.empty() && !tags) {
          const string b = current_branch(root);
          if (!b.empty()) refs.push_back(b);
        }
        for (const string& raw : refs) {
          // `HEAD` and `@` name no branch; they ask the repo which one it is on.
          // Every other spelling reaches the name comparison untouched.
          const string r = push_dest_ref(raw, root);
          if (r.empty()) continue;
          if (!shared_branch(r)) continue;
          if (mirror || all) {
            const string flag = mirror ? "--mirror"
                                       : (matching ? "-c push.default=matching" : "--all --force");
            hit = {"baseline-force-push",
                   "a force-push to a shared branch rewrites history other people already have",
                   "git push " + flag + " writes every branch, and '" + r + "' is one of them — "
                   "name the branch you mean, or push to your own branch"};
          } else {
            // when the branch was not the word the line carried, say both: the
            // operator asked about HEAD and needs to be told which branch that is
            const string wrote = (r == raw) ? string() : " (written as " + raw + ")";
            hit = {"baseline-force-push",
                   "a force-push to a shared branch rewrites history other people already have",
                   "force-push to shared branch '" + r + "'" + wrote + viaCfg +
                       " — use --force-with-lease, or push to your own branch"};
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

  if (!disabled_has(disabled, "baseline-rm-rf-outside")) {
    const rbpath::Delete d = rbpath::delete_of(t);
    if (!d.isDelete || !rbtext::name_is(name, "rm")) return false;
    if (!d.recursive) return false;
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
