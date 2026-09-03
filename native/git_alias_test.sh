#!/bin/bash
# git_alias_test.sh — a verb written into a config value is still the verb.
#
# THE HOLE. git resolves the word after its own options against an alias table,
# and `-c` builds that table from the SAME command line:
#
#   git -c alias.x='push --force' x origin main
#
# The option walk in the parser already knew that `-c` takes a value and stepped
# over it correctly — which is exactly how the force-push got through. The walk
# landed on `x`, the compiled law compared that token to `push`, and a user's
# `git\s+push` deny regex needs the literal word `push` in the text. Both layers
# returned 0. The dangerous verb was written down once, inside a quoted value,
# and never said again.
#
# WHAT REAL GIT DOES, measured against git 2.39.5 in a repo with no remote
# before any of this was written (the failures below are push-shaped, i.e. the
# alias really did become `push --force`):
#
#   -c alias.x='push --force' x origin main   -> fatal: 'origin' does not appear
#                                                to be a git repository
#   -c alias.x=push x --force origin main     -> same; trailing args are appended
#   -c alias.X=... invoked as x               -> runs (config keys fold case)
#   -c alias.x=... invoked as X               -> runs (same fold, other side)
#   -c alias.a=b -c alias.b='...' a           -> runs (aliases chain)
#   -c alias.x=FIRST -c alias.x=SECOND x      -> SECOND (last definition wins)
#   -c alias.x='!echo hi' x aa bb             -> `hi aa bb` (a `!` body is a
#                                                shell program, args appended)
#   -calias.x='push --force' x                -> REJECTED by git ("unknown
#                                                option"), so it is not a hole
#                                                and is not tested as one
#   -c alias.status='!echo SHADOW' status     -> runs status; a builtin wins,
#                                                and an alias cannot rename one.
#                                                NAMED LIMIT: this parser has no
#                                                list of git builtins and will
#                                                expand that line anyway. The
#                                                error it makes is a refusal of
#                                                a command nobody writes.
#
# NOTHING HERE IS EXECUTED, AND THE SETUP ASSUMES THE OPPOSITE.
# The cases below are real force-pushes, a real hard reset and a real recursive
# delete. The run is built so that a TOTAL failure of the gate — every case
# allowed, and something then running them — still costs nothing:
#   * PATH is prefixed with a shim dir holding fake `git` and `rm`. They execute
#     nothing, append their argv to a log, and exit 111. The log is asserted
#     EMPTY at the end, which is the proof that judging is not running.
#   * the repos under judgement are mktemp'd and have NO REMOTE, so a
#     force-push has nowhere to go.
#   * HOME is redirected into the same mktemp root, so `rm -rf ~/Documents`
#     names a scratch directory this script created, and a canary file in it is
#     read back at the end.
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
[ -x "$GATE" ] || { echo "git_alias_test: build first (make)"; exit 1; }

FAIL=0
PASSN=0
pass() { PASSN=$((PASSN+1)); echo "  ok   $1"; }
bad()  { FAIL=1; echo "  FAIL $1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbalias.XXXXXX")"
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
REPO="$ROOT/proj"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
git -C "$REPO" branch -M main
REPO_HEAD="$(git -C "$REPO" rev-parse HEAD)"
# no `git remote add` anywhere in this file, on purpose: there is nothing to push to.

# the same shapes against the USER RULE layer, whose deny regexes need the
# literal word `push` in the text
GREPO="$ROOT/guarded"
mkdir -p "$GREPO/.rabadon"
git init -q "$GREPO"
git -C "$GREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
git -C "$GREPO" branch -M main
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
# unit: the ONE parser, asked what argv git will really run
# ---------------------------------------------------------------------------
cat > "$ROOT/probe.cpp" <<'CPP'
#include <cstdio>
#include <iostream>
#include <string>
#include "cmdtext.h"
int main() {
  std::string cmd((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
  while (!cmd.empty() && cmd[cmd.size()-1] == '\n') cmd.erase(cmd.size()-1);
  rbtext::Parsed p = rbtext::parse(cmd);
  if (p.degraded) { printf("DEGRADED %s\n", p.why.c_str()); return 0; }
  for (size_t i = 0; i < p.segs.size(); i++) {
    const rbtext::Seg& s = p.segs[i];
    const size_t ci = rbtext::command_index(s.words);
    std::string name = ci < s.words.size() ? rbtext::base_of(s.words[ci].text) : "";
    printf("cmd=%s is_git=%d words=", name.c_str(), rbtext::name_is(name, "git") ? 1 : 0);
    for (size_t k = ci; k < s.words.size(); k++)
      printf("%s%s", k == ci ? "" : "|", s.words[k].text.c_str());
    printf("\n");
  }
  for (size_t i = 0; i < p.limits.size(); i++) printf("limit=%s\n", p.limits[i].c_str());
  return 0;
}
CPP
UNIT_OK=1
"$CXX" -std=c++17 -O1 -Wall -Wextra -I "$HERE" -o "$ROOT/probe" "$ROOT/probe.cpp" 2>"$ROOT/cc.log" || UNIT_OK=0

u_argv() { # u_argv NAME CMD EXPECTED-SUBSTRING
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then pass "$name"
  else bad "$name: no command decomposed to <$want>"; printf '%s\n' "$out" | sed 's/^/         got: /'; fi
}
u_notargv() {
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then
    bad "$name: a command decomposed to <$want>, and git would not run that"
    printf '%s\n' "$out" | sed 's/^/         got: /'
  else pass "$name"; fi
}

echo "== unit: the subcommand git resolves, not the token that was typed =="
if [ "$UNIT_OK" = "0" ]; then
  echo "  (probe did not compile)"; sed -n '1,12p' "$ROOT/cc.log" | sed 's/^/         /'
fi
u_argv "alias body becomes argv"      "git -c alias.x='push --force' x origin main"      '|push|--force|origin|main'
u_argv "trailing args are appended"   "git -c alias.x=push x --force origin main"        '|push|--force|origin|main'
u_argv "alias name folds case (def)"  "git -c alias.X='push --force' x origin main"      '|push|--force|origin|main'
u_argv "alias name folds case (use)"  "git -c alias.x='push --force' X origin main"      '|push|--force|origin|main'
u_argv "section folds case"           "git -c ALIAS.x='push --force' x origin main"      '|push|--force|origin|main'
u_argv "aliases chain"                "git -c alias.a=b -c alias.b='push --force' a origin main" '|push|--force|origin|main'
u_argv "last definition wins"         "git -c alias.x=status -c alias.x='push --force' x origin main" '|push|--force|origin|main'
u_argv "globals and alias together"   "git -C /tmp -c alias.x='push --force' x origin main" '|push|--force|origin|main'
u_argv "bang body is a shell program" "git -c alias.x='!git push --force origin main' x" 'is_git=1 words=git|push|--force|origin|main'
u_argv "bang body gets the args"      "git -c alias.x='!git push --force' x origin main" 'is_git=1 words=git|push|--force|origin|main'
u_argv "config-env is a named limit"  "git --config-env=alias.x=AV x origin main"        'limit=an alias'

echo
echo "== unit: an alias definition does not invent a command =="
u_notargv "alias defined, not invoked" "git -c alias.x='push --force' status" '|push|--force'
u_notargv "alias loop terminates"      "git -c alias.a=b -c alias.b=a a"      '|push'
u_notargv "not an alias key"           "git -c user.name=push x"              '|push|'

# ---------------------------------------------------------------------------
# e2e: the real binary
# ---------------------------------------------------------------------------
judge() { # judge <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"alias","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
blocks() { local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then pass "$1"; else bad "$1: allowed (exit $got), the plain spelling of it is refused"; fi; }
allows() { local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then bad "$1: refused, and refusing it cuts real work"; else pass "$1"; fi; }

echo
echo "== e2e: the alias hole, against the three compiled-in laws (no guard.json) =="
blocks "the reported command"        "$REPO" "git -c alias.x='push --force' x origin main"
blocks "args after the alias"        "$REPO" "git -c alias.x=push x --force origin main"
blocks "alias name folds case"       "$REPO" "git -c alias.X='push --force' x origin main"
blocks "invoked in another case"     "$REPO" "git -c alias.x='push --force' X origin main"
blocks "chained aliases"             "$REPO" "git -c alias.a=b -c alias.b='push --force' a origin main"
blocks "last definition wins"        "$REPO" "git -c alias.x=status -c alias.x='push --force' x origin main"
blocks "-C global plus alias"        "$REPO" "git -C $REPO -c alias.x='push --force' x origin main"
blocks "the + refspec via alias"     "$REPO" "git -c alias.x=push x origin +main"
blocks "hard reset via alias"        "$REPO" "git -c alias.x='reset --hard' x origin/main"
blocks "bang alias, force-push"      "$REPO" "git -c alias.x='!git push --force origin main' x"
blocks "bang alias, args appended"   "$REPO" "git -c alias.x='!git push --force' x origin main"
blocks "bang alias, rm outside"      "$REPO" "git -c alias.x='!rm -rf ~/Documents' x"
blocks "alias inside sh -lc"         "$REPO" "sh -lc \"git -c alias.x='push --force' x origin main\""
blocks "alias inside eval"           "$REPO" "eval \"git -c alias.x='push --force' x origin main\""

echo
echo "== e2e: an alias ALREADY ON DISK, and one this line writes =="
# THE HOLE AN OUTSIDE REVIEWER FOUND, 2026-09-03. Every case above puts the
# alias on the command line with `-c`. A user does not: they run
# `git config alias.yolo "push --force"` once, and months later type
# `git yolo origin main`. That was exit 0 — a general bypass of every git law
# in baseline.h, with no quoting trick and nothing odd in the command text.
"$REALGIT" -C "$REPO" config alias.yolo "push --force"
"$REALGIT" -C "$REPO" config alias.lg   "log --oneline -5"
"$REALGIT" -C "$REPO" config alias.bang "!git push --force origin main"
blocks "configured alias, force push"  "$REPO" "git yolo origin main"
blocks "configured bang alias"         "$REPO" "git bang"
blocks "configured alias in sh -lc"    "$REPO" "sh -lc 'git yolo origin main'"
allows "configured alias of a read"    "$REPO" "git lg"
# git PRINTS THE MANUAL and runs nothing for `--help`, measured against git
# 2.39.5: `git yolo --help` says "'yolo' is aliased to 'push --force'" and
# opens git-push(1), exit 0, remote untouched. Expanding it anyway refuses a
# documentation lookup — a false reject while the user is READING.
allows "an alias asked for its manual" "$REPO" "git yolo --help"
allows "the short form of that"        "$REPO" "git yolo -h"

# A definition EARLIER ON THE SAME LINE is not on disk yet when the gate
# decides — nothing has run — so the parse collects it as it walks segments.
blocks "defined and used, one line"    "$REPO" "git config alias.z 'push --force'; git z origin main"
blocks "defined --global, then used"   "$REPO" "git config --global alias.q 'push -f'; git q origin main"
allows "defined but never invoked"     "$REPO" "git config alias.z 'push --force'; git status"
allows "an alias of a read, same line" "$REPO" "git config alias.st status; git st"
allows "the definition quoted in echo" "$REPO" "echo 'git config alias.z push --force'"
# and the table must not leak from one command line into the next
allows "the next line does not inherit it" "$REPO" "git z origin main"

echo
echo "== e2e: the same shapes reach the user rule layer =="
blocks "guard.json + alias"          "$GREPO" "git -c alias.x='push --force' x origin main"
blocks "guard.json + chained alias"  "$GREPO" "git -c alias.a=b -c alias.b='push --force' a origin main"
blocks "guard.json + bang alias"     "$GREPO" "git -c alias.x='!git push --force origin main' x"

echo
echo "== e2e: the legitimate twin of every case above still runs =="
allows "alias of a read"             "$REPO" "git -c alias.x='status --short' x"
allows "alias of a log"              "$REPO" "git -c alias.lg='log --oneline -5' lg"
allows "alias with lease"            "$REPO" "git -c alias.x='push --force-with-lease' x origin main"
allows "alias, force to own branch"  "$REPO" "git -c alias.x='push --force' x origin feature/mine"
allows "alias, plain push"           "$REPO" "git -c alias.x=push x origin main"
allows "alias defined, not invoked"  "$REPO" "git -c alias.x='push --force' status"
allows "bang alias of a read"        "$REPO" "git -c alias.x='!git status --short' x"
allows "bang alias, rm inside"       "$REPO" "git -c alias.x='!rm -rf node_modules' x"
allows "reset --hard to a local ref" "$REPO" "git -c alias.x='reset --hard' x HEAD~0"
allows "-c that is not an alias"     "$REPO" "git -c user.name=x -c user.email=y commit --allow-empty -m hello"
allows "-c http.proxy then push"     "$REPO" "git -c http.proxy=http://p:8080 push origin main"
allows "guard.json + read alias"     "$GREPO" "git -c alias.x='status --short' x"
allows "the alias in a commit msg"   "$REPO" "git commit -m \"git -c alias.x='push --force' x origin main was the bypass\""
allows "the alias in an echo"        "$REPO" "echo \"git -c alias.x='push --force' x origin main\""

echo
echo "== exec: the OTHER caller of the rule engine, and it is handed argv =="
# `rabadon exec` is sold as the harder version of the hook, so a command the
# hook refuses may not run here. It receives argv rather than a line and joined
# it with plain spaces, which turned the single argument `alias.x=push --force`
# back into two words: the alias then bound `x` to a bare push and the `--force`
# beside it read as one of git's own leading options. The stub git first on PATH
# is the whole proof — exit 2 is the rule engine refusing, 111 is the stub
# reporting that it was really invoked.
#
# It runs on a SECOND stub with its OWN log, because unlike every other section
# in this file exec is supposed to run the commands it allows. The first log
# stays empty and keeps meaning what it means: judging is not running.
EXEC="$HERE/rabadon-sandbox"
XSHIM="$ROOT/xshim"; mkdir -p "$XSHIM"
XLOG="$ROOT/xran.log"; : > "$XLOG"
cat > "$XSHIM/git" <<SH
#!/bin/sh
printf 'git %s\n' "\$*" >> "$XLOG"
exit 111
SH
chmod +x "$XSHIM/git"
xrun() { # xrun <alias-body> [operands]
  ( cd "$REPO" && PATH="$XSHIM:/usr/bin:/bin" "$EXEC" -- "$XSHIM/git" -c "alias.x=$1" x $2 >/dev/null 2>&1 )
  echo $?
}
xblocks() { local got; got="$(xrun "$2" "${3-}")"
  if [ "$got" = "2" ]; then pass "$1"; else bad "$1: exec returned $got (111 = the stub really ran it)"; fi; }
xallows() { local got; got="$(xrun "$2" "${3-}")"
  if [ "$got" = "2" ]; then bad "$1: exec refused, and refusing it cuts real work"; else pass "$1"; fi; }
if [ -x "$EXEC" ]; then
  xblocks "exec: alias force-push"    "push --force" "origin main"
  xblocks "exec: alias hard reset"    "reset --hard" "origin/main"
  xblocks "exec: bang alias"          "!git push --force origin main"
  xallows "exec: alias of a read"     "status --short"
  xallows "exec: alias with lease"    "push --force-with-lease" "origin main"
  xallows "exec: force to own branch" "push --force" "origin feature/mine"
  # the log is the claim: what exec refused never reached git, what it allowed did
  if grep -q -- "alias.x=push --force x origin main" "$XLOG"; then
    bad "exec: the refused force-push reached git anyway"; sed 's/^/         /' "$XLOG"
  else pass "exec: the refused commands never reached git"; fi
  if grep -q -- "alias.x=status --short" "$XLOG"; then
    pass "exec: the allowed alias did reach git (the stub is really on PATH)"
  else bad "exec: nothing reached git at all, so the refusals prove nothing"; fi
else
  bad "exec: $EXEC not built"
fi

echo
echo "== e2e: the plain spellings did not stop working =="
blocks "plain force-push"            "$REPO" "git push --force origin main"
blocks "plain hard reset"            "$REPO" "git reset --hard origin/main"
blocks "global option walk"          "$REPO" "git -C $REPO push --force origin main"
allows "plain push"                  "$REPO" "git push origin main"
allows "force-with-lease"            "$REPO" "git push --force-with-lease origin main"
allows "rm inside the project"       "$REPO" "rm -rf node_modules"

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
  && pass "the rm -rf target still holds its canary file" \
  || bad "the rm -rf target was touched"
[ "$("$REALGIT" -C "$REPO" rev-parse HEAD 2>/dev/null)" = "$REPO_HEAD" ] \
  && pass "the repo under judgement still points at the same commit" \
  || bad "the judged repo moved"
[ -z "$("$REALGIT" -C "$REPO" remote 2>/dev/null)" ] \
  && pass "the judged repo never had a remote to force-push to" \
  || bad "the judged repo grew a remote"

echo
if [ "$FAIL" = "0" ]; then echo "PASS ($PASSN checks)"; else echo "FAIL ($PASSN checks passed)"; fi
exit $FAIL
