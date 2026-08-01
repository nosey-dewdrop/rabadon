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
        for (const string& raw : refs) {
          // `HEAD` and `@` name no branch; they ask the repo which one it is on.
          // Every other spelling reaches the name comparison untouched.
          const string r = push_dest_ref(raw, root);
          if (r.empty()) continue;
          if (!shared_branch(r)) continue;
          // when the branch was not the word the line carried, say both: the
          // operator asked about HEAD and needs to be told which branch that is
          const string wrote = (r == raw) ? string() : " (written as " + raw + ")";
          hit = {"baseline-force-push",
                 "a force-push to a shared branch rewrites history other people already have",
                 "force-push to shared branch '" + r + "'" + wrote +
                     " — use --force-with-lease, or push to your own branch"};
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
