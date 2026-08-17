#!/bin/bash
# push_refspec_test.sh — a push with no refspec is not a push of HEAD.
#
# THE HOLE. The force-push law read the operands as `<remote> [<refspec>...]`,
# and when no refspec was written down it filled the gap with the current
# branch:
#
#   const string b = current_branch(root);   // reads .git/HEAD
#
# That answers a different question than the one asked. "Which branch am I on"
# is not "which refs will this push write", and git has four ways to answer the
# second one. Two of them do not consult HEAD at all:
#
#   git push --all --force origin
#   git -c remote.origin.push=refs/heads/x:refs/heads/main push --force origin
#
# Both were refused only in the accident that the shell already sat on main.
# From a feature branch — where an agent that has just been told to work on a
# branch actually is — the same two lines walked through both layers: the
# compiled law fell back to HEAD and saw `feat`, and a user's guard.json regex
# needs the literal word `main` in the text, which neither line contains.
#
# WHAT REAL GIT DOES. Measured against git 2.39.5 with --dry-run, in a scratch
# repo whose remote is a bare repo in the same mktemp root, HEAD on `feat`,
# local main rewritten so it is a real non-fast-forward. Each line below is the
# reason a case in this file expects what it expects:
#
#   push --all --force origin              main -> main (forced), feat -> feat.
#                                          Every local branch, HEAD not asked.
#   push --all origin        (no --force)  ! [rejected] main -> main
#                                          (non-fast-forward). --all alone is
#                                          NOT a force, so it must not block.
#   push --mirror origin     (no --force)  + main -> main (FORCED UPDATE).
#                                          --mirror forces by itself. This was
#                                          not in the report and is the wider
#                                          half of the hole.
#   push --all --force origin main         fatal: --all can't be combined with
#                                          refspecs. So "--all plus a refspec"
#                                          is not a shape that runs.
#   -c remote.origin.push=<a>:<main>       + feat -> main (forced update).
#     push --force origin                  Config supplies the refspec.
#   ...same, with NO remote operand        + feat -> main (forced update).
#                                          The default remote is origin.
#   -c remote.origin.push=<a>:<topic>      feat -> main AND feat -> topic.
#     -c remote.origin.push=<a>:<main>     The key is MULTI-VALUED: every
#                                          occurrence is a refspec, not the
#                                          last one only.
#   -c REMOTE.origin.PUSH=<a>:<main>       + feat -> main (forced update).
#                                          Section and variable fold case.
#   -c remote.ORIGIN.push=<a>:<main>       NOT used (git falls back to the
#                                          branch's upstream and fails). The
#                                          SUBSECTION is case-sensitive.
#   -c remote.other.push=<a>:<main>        NOT used. A config for a different
#                                          remote does not decide this push.
#   -c push.default=matching push --force  + main -> main (forced update).
#     origin                               Every same-named branch, HEAD not
#                                          asked.
#   push --tags --force origin             + v1 -> v1 ONLY. From `feat` AND
#                                          from `main` with an upstream set:
#                                          no branch is written. The old law
#                                          refused this line whenever HEAD sat
#                                          on main, and refusing it cut work
#                                          that touches no branch at all.
#   push --follow-tags --force origin      + main -> main (forced update).
#                                          The ordinary refspec, plus tags. It
#                                          must stay refused.
#   push --branches ...                    error: unknown option `branches`.
#                                          This git rejects the word outright,
#                                          so treating it as the --all synonym
#                                          a newer git documents cannot refuse
#                                          any command this git would run.
#
# A DELIBERATE CHOICE, NOT AN OVERSIGHT: the remote's NAME is not consulted for
# the blanket forms, so `git push --mirror --force backup` is refused too. That
# is the stance the law already takes one line up — `git push --force myfork
# main` has always been refused — and the message names the way out.
#
# A NAMED LIMIT: push.default and remote.<name>.push can also come from
# .git/config, ~/.gitconfig or /etc/gitconfig, and none of those are in the
# command line. This file judges what the LINE writes down. Reading the repo's
# config only would be a half-answer that reports the other half as absent.
#
# NOTHING HERE IS EXECUTED, AND THE SETUP ASSUMES THE OPPOSITE.
# Every case below is a real force-push. The run is built so that a TOTAL
# failure of the gate — every case allowed, and something then running them —
# still costs nothing:
#   * PATH is prefixed with a shim dir holding fake `git` and `rm`. They run
#     nothing, append their argv to a log, and exit 111. The log is asserted
#     EMPTY at the end, which is the proof that judging is not running.
#   * the repos under judgement are mktemp'd and have NO REMOTE, asserted at
#     the end with the real git, so a force-push has nowhere to land.
#   * HOME is redirected into the same mktemp root and a canary file is written
#     inside it, then read back at the end.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
# `c++`, not `clang++`. make does NOT export its builtin CXX, so under
# `make test` this variable is unset and the fallback is what actually runs —
# and on a Linux box with only g++ installed, `clang++` is a command that does
# not exist. `c++` is the standard alias and resolves to whichever compiler the
# machine has (PROJECT.md S0.2 / V1.2).
CXX="${CXX:-c++}"
[ -x "$GATE" ] || { echo "push_refspec_test: build first (make)"; exit 1; }

FAIL=0
PASSN=0
pass() { PASSN=$((PASSN+1)); echo "  ok   $1"; }
bad()  { FAIL=1; echo "  FAIL $1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbpushref.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# ---- the blast shield ------------------------------------------------------
SHIM="$ROOT/shim"; mkdir -p "$SHIM"
RANLOG="$ROOT/ran.log"
: > "$RANLOG"
for TOOL in git rm; do
  cat > "$SHIM/$TOOL" <<SH
#!/bin/sh
printf '%s %s\n' "$TOOL" "\$*" >> "$RANLOG"
exit 111
SH
  chmod +x "$SHIM/$TOOL"
done

# built with the REAL git, before the shim goes on PATH; the real path is kept
# so the canary checks at the end are not answered by the shim
REALGIT="$(command -v git)"

# Two repos that differ ONLY in which branch is checked out. That difference is
# the whole bug: every must-block case below is judged in both, and the two
# verdicts have to agree.
mkrepo() { # mkrepo <dir> <branch-to-sit-on>
  "$REALGIT" init -q "$1"
  "$REALGIT" -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
  "$REALGIT" -C "$1" branch -M main
  if [ "$2" != "main" ]; then "$REALGIT" -C "$1" checkout -q -b "$2"; fi
  # no `git remote add` anywhere in this file, on purpose.
}
ON_MAIN="$ROOT/on-main"; mkrepo "$ON_MAIN" main
ON_FEAT="$ROOT/on-feat"; mkrepo "$ON_FEAT" feat
MAIN_HEAD="$("$REALGIT" -C "$ON_MAIN" rev-parse HEAD)"
FEAT_HEAD="$("$REALGIT" -C "$ON_FEAT" rev-parse HEAD)"

# the same shapes against the USER RULE layer, whose deny regexes need the
# literal words `push`, `--force` and `main` in the text — none of which
# `git push --all --force origin` contains.
GREPO="$ROOT/guarded"
mkrepo "$GREPO" feat
mkdir -p "$GREPO/.rabadon"
cat > "$GREPO/.rabadon/guard.json" <<'JSON'
{
  "project": "guarded",
  "bash": [
    { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b", "why": "force-pushing a shared branch destroys history" }
  ],
  "protectedPaths": [], "disabled": []
}
JSON

export HOME="$ROOT/home"
mkdir -p "$HOME/Documents"
echo "do not lose me" > "$HOME/Documents/canary.txt"
export RABADON_DIR="$ROOT/rhome"; mkdir -p "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"
export RABADON_NOTIFY=0
export PATH="$SHIM:$PATH"

# ---------------------------------------------------------------------------
# unit: the ONE parser, asked what a `-c` config pair on this line binds
# ---------------------------------------------------------------------------
# The fold rules asserted here are the ones measured off git 2.39.5 in the
# header: section and variable fold, subsection does not, the key is
# multi-valued. They live in cmdtext.h because "what does this line say" is a
# question about reading the line, and there is one reader.
cat > "$ROOT/probe.cpp" <<'CPP'
#include <cstdio>
#include <iostream>
#include <string>
#include <vector>
#include "cmdtext.h"
int main(int argc, char** argv) {
  if (argc < 2) return 2;
  std::string cmd((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
  while (!cmd.empty() && cmd[cmd.size()-1] == '\n') cmd.erase(cmd.size()-1);
  rbtext::Parsed p = rbtext::parse(cmd);
  if (p.degraded) { printf("DEGRADED\n"); return 0; }
  for (size_t i = 0; i < p.segs.size(); i++) {
    const std::vector<rbtext::Word>& t = p.segs[i].words;
    const size_t ci = rbtext::command_index(t);
    if (ci >= t.size() || !rbtext::name_is(rbtext::base_of(t[ci].text), "git")) continue;
    size_t sub = 0;
    if (!rbtext::git_subcommand(t, ci, sub)) continue;
    std::vector<std::string> vals;
    rbtext::git_config_values(t, ci, sub, argv[1], vals);
    printf("values=%zu", vals.size());
    for (size_t k = 0; k < vals.size(); k++) printf(" [%s]", vals[k].c_str());
    printf("\n");
  }
  return 0;
}
CPP
UNIT_OK=1
"$CXX" -std=c++17 -O1 -Wall -Wextra -I "$HERE" -o "$ROOT/probe" "$ROOT/probe.cpp" 2>"$ROOT/cc.log" || UNIT_OK=0

u_cfg() { # u_cfg NAME KEY CMD EXPECTED-LINE
  local name="$1" key="$2" cmd="$3" want="$4" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe" "$key")"
  if [ "$out" = "$want" ]; then pass "$name"
  else bad "$name: got <$out>, want <$want>"; fi
}

echo "== unit: the config a -c pair binds, folded the way git folds a key =="
if [ "$UNIT_OK" = "0" ]; then
  echo "  (probe did not compile)"; sed -n '1,12p' "$ROOT/cc.log" | sed 's/^/         /'
fi
u_cfg "a push refspec from config" "remote.origin.push" \
  "git -c remote.origin.push=refs/heads/x:refs/heads/main push --force origin" \
  "values=1 [refs/heads/x:refs/heads/main]"
u_cfg "section and variable fold" "remote.origin.push" \
  "git -c REMOTE.origin.PUSH=refs/heads/x:refs/heads/main push --force origin" \
  "values=1 [refs/heads/x:refs/heads/main]"
u_cfg "subsection is case-sensitive" "remote.origin.push" \
  "git -c remote.ORIGIN.push=refs/heads/x:refs/heads/main push --force origin" \
  "values=0"
u_cfg "another remote is another key" "remote.origin.push" \
  "git -c remote.other.push=refs/heads/x:refs/heads/main push --force origin" \
  "values=0"
u_cfg "the key is multi-valued" "remote.origin.push" \
  "git -c remote.origin.push=refs/heads/x:refs/heads/topic -c remote.origin.push=refs/heads/x:refs/heads/main push --force origin" \
  "values=2 [refs/heads/x:refs/heads/topic] [refs/heads/x:refs/heads/main]"
u_cfg "a two-part key still reads" "push.default" \
  "git -c push.default=matching push --force origin" \
  "values=1 [matching]"
u_cfg "options after the subcommand are not git's" "remote.origin.push" \
  "git push --force origin -c remote.origin.push=refs/heads/x:refs/heads/main" \
  "values=0"

# ---------------------------------------------------------------------------
# e2e: the real binary
# ---------------------------------------------------------------------------
judge() { # judge <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"pushref","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}

# THE POINT OF THE FILE: the verdict may not depend on which branch is checked
# out. Every must-block case is judged twice, once in a repo sitting on main and
# once in a repo sitting on a feature branch, and both must refuse.
blocks_any_head() { # blocks_any_head NAME CMD
  local a b
  a="$(judge "$ON_MAIN" "$2")"
  b="$(judge "$ON_FEAT" "$2")"
  if [ "$a" = "2" ] && [ "$b" = "2" ]; then pass "$1"
  elif [ "$a" = "2" ]; then bad "$1: refused on main, ALLOWED on a feature branch — HEAD decided, and HEAD was not asked"
  elif [ "$b" = "2" ]; then bad "$1: refused on a feature branch, allowed on main"
  else bad "$1: allowed from both heads (exit $a/$b)"; fi
}
allows_any_head() { # allows_any_head NAME CMD
  local a b
  a="$(judge "$ON_MAIN" "$2")"
  b="$(judge "$ON_FEAT" "$2")"
  if [ "$a" != "2" ] && [ "$b" != "2" ]; then pass "$1"
  else bad "$1: refused (main:$a feat:$b), and refusing it cuts real work"; fi
}
blocks() { local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then pass "$1"; else bad "$1: allowed (exit $got)"; fi; }
allows() { local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then bad "$1: refused, and refusing it cuts real work"; else pass "$1"; fi; }

echo
echo "== e2e: the reported escapes, from either branch (no guard.json) =="
blocks_any_head "push --all --force"            "git push --all --force origin"
blocks_any_head "push --force --all"            "git push --force --all origin"
blocks_any_head "--all, no remote named"        "git push --all --force"
blocks_any_head "--all after the remote"        "git push --force origin --all"
blocks_any_head "-f short form with --all"      "git push --all -f origin"
blocks_any_head "config refspec"                "git -c remote.origin.push=refs/heads/x:refs/heads/main push --force origin"
blocks_any_head "config refspec, no remote"     "git -c remote.origin.push=refs/heads/x:refs/heads/main push --force"
blocks_any_head "config refspec, key folded"    "git -c REMOTE.origin.PUSH=refs/heads/x:refs/heads/main push --force origin"
blocks_any_head "config refspec, second value"  "git -c remote.origin.push=refs/heads/x:refs/heads/topic -c remote.origin.push=refs/heads/x:refs/heads/main push --force origin"
blocks_any_head "config refspec to upstream"    "git -c remote.upstream.push=refs/heads/x:refs/heads/master push --force upstream"

echo
echo "== e2e: the wider half — --mirror is a force-push with no --force =="
blocks_any_head "mirror, forced by itself"      "git push --mirror origin"
blocks_any_head "mirror with --force"           "git push --mirror --force origin"
blocks_any_head "push.default=matching"         "git -c push.default=matching push --force origin"

echo
echo "== e2e: the same escapes through the wrappers the parser already flattens =="
blocks_any_head "--all inside sh -lc"           "sh -lc 'git push --all --force origin'"
blocks_any_head "--all inside eval"             "eval \"git push --all --force origin\""
blocks_any_head "--all behind a git alias"      "git -c alias.x='push --all --force' x origin"
blocks_any_head "--all with a global option"    "git -C $ON_FEAT push --all --force origin"
blocks_any_head "--all after &&"                "npm test && git push --all --force origin"
# THIS LINE USED TO BE IN THE ALLOW LIST BELOW, and it was wrong. A lease token
# beside the force switched the whole law off, so `--force-if-includes` turned
# the refusal on the line directly above into a pass. Measured, not reasoned:
# real pushes into a bare repo, `main` on the remote carrying a commit this
# clone has never fetched, pushing from `feat` --
#   git push --all --force-if-includes --force origin
#     -> + 3fb409d...1d0d74c main -> main (forced update)
# and the remote no longer had the other clone's commit. `--force-if-includes`
# is inert without a lease (git refuses `--force-if-includes` alone with "fetch
# first"), so what this line really is, is `--all --force` -- the case refused
# three lines up. native/lease_force_test.sh holds the general rule.
blocks_any_head "--all with force-if-includes and a force" \
                                                "git push --all --force-if-includes --force origin"

echo
echo "== e2e: the user rule layer sees these too (its regex cannot) =="
blocks "guard.json + --all"        "$GREPO" "git push --all --force origin"
blocks "guard.json + --mirror"     "$GREPO" "git push --mirror origin"
blocks "guard.json + config refspec" "$GREPO" "git -c remote.origin.push=refs/heads/x:refs/heads/main push --force origin"

echo
echo "== e2e: the legitimate twin of every case above still runs =="
allows_any_head "--all without --force"         "git push --all origin"
allows_any_head "--all with a lease"            "git push --all --force-with-lease origin"
# the honest twin of the case now refused above: with no --force anywhere, an
# --all push writes nothing by force, and --force-if-includes on its own is the
# no-op git documents. Both of these still go.
allows_any_head "--all with force-if-includes"  "git push --all --force-if-includes origin"
allows_any_head "force-if-includes on its own"  "git push --force-if-includes origin"
allows_any_head "tags only, no branch written"  "git push --tags --force origin"
allows_any_head "tags only, short force"        "git push --tags -f origin"
allows_any_head "config refspec to a topic"     "git -c remote.origin.push=refs/heads/x:refs/heads/topic push --force origin"
allows_any_head "a config that is not a push"   "git -c remote.origin.fetch=+refs/heads/*:refs/remotes/origin/* push --force origin topic"
allows_any_head "the words in a commit message" "git commit -m 'git push --all --force origin was the bypass'"
allows_any_head "the words in an echo"          "echo 'git push --all --force origin'"
allows_any_head "a plain mirror-less fetch"     "git fetch --all"
allows_any_head "--all on a read"               "git branch --all"

echo
echo "== e2e: a config that does NOT supply a refspec falls back to HEAD, and HEAD"
echo "        is the right answer to THAT question — so these keep the old verdict =="
# Measured: with remote.<name>.push unset for the remote being pushed to, git
# reports "The current branch feat has no upstream branch", i.e. it went looking
# for the current branch. So the fallback is correct here and must not be lost:
# refused from main, allowed from a feature branch.
blocks "config for another remote, on main"   "$ON_MAIN" "git -c remote.other.push=refs/heads/x:refs/heads/main push --force origin"
allows "config for another remote, on feat"   "$ON_FEAT" "git -c remote.other.push=refs/heads/x:refs/heads/main push --force origin"
blocks "wrong subsection case, on main"       "$ON_MAIN" "git -c remote.ORIGIN.push=refs/heads/x:refs/heads/main push --force origin"
allows "wrong subsection case, on feat"       "$ON_FEAT" "git -c remote.ORIGIN.push=refs/heads/x:refs/heads/main push --force origin"
blocks "push.default=current, on main"        "$ON_MAIN" "git -c push.default=current push --force origin"
allows "push.default=current, on feat"        "$ON_FEAT" "git -c push.default=current push --force origin"
blocks "push.default=simple, on main"         "$ON_MAIN" "git -c push.default=simple push --force origin"
allows "push.default=simple, on feat"         "$ON_FEAT" "git -c push.default=simple push --force origin"

echo
echo "== e2e: --follow-tags is the ordinary refspec plus tags, and stays refused =="
blocks "follow-tags on main"       "$ON_MAIN" "git push --follow-tags --force origin"
allows "follow-tags on a branch"   "$ON_FEAT" "git push --follow-tags --force origin"

echo
echo "== e2e: the plain spellings did not stop working =="
blocks "plain force-push"          "$ON_FEAT" "git push --force origin main"
blocks "the + refspec"             "$ON_FEAT" "git push origin +main"
blocks "force-push from main"      "$ON_MAIN" "git push --force origin"
blocks "plain hard reset"          "$ON_FEAT" "git reset --hard origin/main"
allows "plain push"                "$ON_FEAT" "git push origin main"
allows "force-with-lease"          "$ON_FEAT" "git push --force-with-lease origin main"
allows "force-push of own branch"  "$ON_FEAT" "git push --force origin feature/mine"
allows "force-push from a branch"  "$ON_FEAT" "git push --force origin"
allows "rm inside the project"     "$ON_FEAT" "rm -rf node_modules"

# ---------------------------------------------------------------------------
# judging is not running
# ---------------------------------------------------------------------------
echo
echo "== canaries =="
if [ -s "$RANLOG" ]; then
  bad "something EXECUTED while being judged:"; sed 's/^/         /' "$RANLOG"
else
  pass "the fake git/rm on PATH were never called (judging is not running)"
fi
[ "$(cat "$HOME/Documents/canary.txt" 2>/dev/null)" = "do not lose me" ] \
  && pass "the redirected HOME still holds its canary file" \
  || bad "the canary under HOME was touched"
[ "$("$REALGIT" -C "$ON_MAIN" rev-parse HEAD 2>/dev/null)" = "$MAIN_HEAD" ] \
  && [ "$("$REALGIT" -C "$ON_FEAT" rev-parse HEAD 2>/dev/null)" = "$FEAT_HEAD" ] \
  && pass "both judged repos still point at the same commit" \
  || bad "a judged repo moved"
[ -z "$("$REALGIT" -C "$ON_MAIN" remote 2>/dev/null)$("$REALGIT" -C "$ON_FEAT" remote 2>/dev/null)" ] \
  && pass "neither judged repo ever had a remote to force-push to" \
  || bad "a judged repo grew a remote"

echo
if [ "$FAIL" = "0" ]; then echo "PASS ($PASSN checks)"; else echo "FAIL ($PASSN checks passed)"; fi
exit $FAIL
