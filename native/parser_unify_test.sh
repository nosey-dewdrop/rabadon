#!/bin/bash
# parser_unify_test.sh — the gate answers "what command is this?" ONCE.
#
# rabadon reads a Bash command twice. rules.h asks a regex what the line looks
# like; baseline.h asks a parser what the line DOES. Both had to answer the same
# prior question first — where does one command end, which word is the command
# name, what is a quoted argument — and each answered it with its own code.
# Two answers to one question is not redundancy, it is a hole, because the
# stranger who runs `npm i -g rabadon` gets whichever layer is WEAKER: the three
# compiled-in laws are the only protection a repo with no guard.json has, and
# they were the layer with the smaller parser.
#
# Seven spellings of the same force-push walked past the laws while the plain
# form was refused. Every one was measured against this binary before it was
# written down (see the SEVEN list below); none is hypothetical.
#
#   sh -lc '<cmd>'          baseline compared the token to "-c" byte for byte,
#                           so any short-flag CLUSTER carrying c (-lc, -xc, -ec)
#                           was not "-c" and the string stayed an argument.
#   eval "<cmd>"            cmdtext.h had learned eval; baseline.h had not.
#   $(<cmd>) and `<cmd>`    baseline had no concept of substitution: the first
#                           token was "$(git", and a base name of "$(git" is
#                           never "git".
#   git push \<newline>--force
#                           a line continuation was copied through as a real
#                           newline, gluing it to the next token: "\n--force"
#                           equals neither "--force" nor anything starting "-".
#   GIT push --force        the command name was compared byte for byte, and
#                           macOS resolves GIT and git to the same binary.
#   C="push --force"; git $C
#                           an unresolved $VAR was waived. That waiver was
#                           written for rm TARGETS, where guessing a path is
#                           worse than missing one; it was never argued for a
#                           git SUBCOMMAND, and it silently covered one.
#   xargs bash -c "<cmd>"   the wrapper-skipping list had sudo/env/nohup/time
#                           and friends but not xargs, so the shell underneath
#                           was never seen as a shell.
#
# THIS SUITE FAILS IF THE SECOND PARSER COMES BACK. The last section greps the
# sources: baseline.h may not carry its own quote scanner, its own escape
# handling or its own segment splitter. A behavioural suite alone cannot say
# that, and "we fixed both copies" is how two copies stay two copies.
#
# NOTHING HERE IS EXECUTED, AND THE SETUP ASSUMES THE OPPOSITE.
# The fixture is real force-pushes and real recursive deletes, so the run is
# built so that a TOTAL failure of the gate — every case allowed, and something
# then running them — still costs nothing:
#   * PATH is prefixed with a shim dir holding fake `git` and `rm`. They execute
#     nothing, append their argv to a log, and exit 111. The log is asserted
#     EMPTY at the end, which is the proof that judging is not running.
#   * the repo under judgement is mktemp'd, has NO REMOTE and one commit, so a
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
[ -x "$GATE" ] || { echo "parser_unify_test: build first (make)"; exit 1; }

FAIL=0
PASSN=0
pass() { PASSN=$((PASSN+1)); echo "  ok   $1"; }
bad()  { FAIL=1; echo "  FAIL $1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbunify.XXXXXX")"
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

# the repo is built with the REAL git, before the shim is on PATH; the real path is
# kept so the canary checks at the end are not answered by the shim
REALGIT="$(command -v git)"
REPO="$ROOT/proj"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
git -C "$REPO" branch -M main
REPO_HEAD="$(git -C "$REPO" rev-parse HEAD)"
# no `git remote add` anywhere in this file, on purpose: there is nothing to push to.

# a second repo that DOES carry guard.json, so the same shapes can be shown
# against the user-rule layer as well as the compiled-in laws
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
# unit: the ONE parser, asked directly
# ---------------------------------------------------------------------------
# One line per command the line runs: the resolved command name, whether the
# platform's file system would call that name git, and the argv words. A gap
# between what bash would do and what this prints IS the bypass, and naming it
# here pins it without a repo, a guard file or a hook.
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
  return 0;
}
CPP
UNIT_OK=1
"$CXX" -std=c++17 -O1 -Wall -Wextra -I "$HERE" -o "$ROOT/probe" "$ROOT/probe.cpp" 2>"$ROOT/cc.log" || UNIT_OK=0

# u_argv NAME CMD EXPECTED  — some command in the line must decompose exactly so
u_argv() {
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then
    bad "$name: probe did not compile against the unified parser"
    return
  fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then
    pass "$name"
  else
    bad "$name: no command decomposed to <$want>"
    printf '%s\n' "$out" | sed 's/^/         got: /'
  fi
}

echo "== unit: one parser, and it reads what bash reads =="
if [ "$UNIT_OK" = "0" ]; then
  echo "  (probe did not compile — rbtext::parse / rbtext::name_is / rbtext::Parsed missing)"
  sed -n '1,12p' "$ROOT/cc.log" | sed 's/^/         /'
fi
WANT='is_git=1 words=git|push|--force|origin|main'
u_argv "short-flag cluster sh -lc" "sh -lc 'git push --force origin main'"       "$WANT"
u_argv "short-flag cluster sh -xc" 'sh -xc "git push --force origin main"'       "$WANT"
u_argv "short-flag cluster sh -ec" 'sh -ec "git push --force origin main"'       "$WANT"
u_argv "eval string"               'eval "git push --force origin main"'         "$WANT"
u_argv "command substitution"      '$(git push --force origin main)'             "$WANT"
u_argv "backtick substitution"     '`git push --force origin main`'              "$WANT"
u_argv "line continuation"         'git push \
--force origin main'                                                             "$WANT"
u_argv "case-insensitive name"     'GIT push --force origin main'                'is_git=1 words=GIT|push|--force|origin|main'
u_argv "literal var subcommand"    'C="push --force"; git $C origin main'        "$WANT"
u_argv "xargs wrapper"             'echo x | xargs bash -c "git push --force origin main"' "$WANT"
u_argv "eval carrying rm"          'eval "rm -rf ~/Documents"'                   'words=rm|-rf|~/Documents'

echo
echo "== unit: a word that is DATA is still not a command =="
u_notargv() {
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then
    bad "$name: a command decomposed to <$want>, but it was an argument"
    printf '%s\n' "$out" | sed 's/^/         got: /'
  else
    pass "$name"
  fi
}
u_notargv "commit message"   'git commit -m "close the git push --force origin main bypass"' "$WANT"
u_notargv "echoed sentence"  'echo "git push --force origin main"'                           "$WANT"
u_notargv "python -c is not a shell" 'python3 -c "git push --force origin main"'             "$WANT"

# ---------------------------------------------------------------------------
# e2e: the real binary, on a repo with NO guard.json (the fresh-install case)
# ---------------------------------------------------------------------------
judge() { # judge <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"unify","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
blocks() { # blocks NAME CWD CMD
  local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then pass "$1"; else bad "$1: allowed (exit $got), the plain spelling of it is refused"; fi
}
allows() { # allows NAME CWD CMD
  local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then bad "$1: refused, and refusing it cuts real work"; else pass "$1"; fi
}

echo
echo "== e2e: the SEVEN, against the three compiled-in laws (no guard.json) =="
blocks "1. sh -lc cluster"      "$REPO" "sh -lc 'git push --force origin main'"
blocks "1b. sh -xc cluster"     "$REPO" 'sh -xc "git push --force origin main"'
blocks "1c. sh -ec cluster"     "$REPO" 'sh -ec "git push --force origin main"'
blocks "2. eval force-push"     "$REPO" 'eval "git push --force origin main"'
blocks "2b. eval rm outside"    "$REPO" 'eval "rm -rf ~/Documents"'
blocks "3. \$( ) substitution"  "$REPO" '$(git push --force origin main)'
blocks "3b. backticks"          "$REPO" '`git push --force origin main`'
blocks "4. line continuation"   "$REPO" 'git push \
--force origin main'
blocks "4b. rm line continuation" "$REPO" 'rm -rf \
~/Documents'
blocks "5. GIT, upper case"     "$REPO" 'GIT push --force origin main'
blocks "6. literal \$VAR subcommand" "$REPO" 'C="push --force"; git $C origin main'
blocks "7. xargs bash -c"       "$REPO" 'echo x | xargs bash -c "git push --force origin main"'

echo
echo "== e2e: five more of the same root cause, found while closing the seven =="
# None of these was on the list. They are here because one parser means a shape
# nobody enumerated is read correctly anyway, and the way to show that is to
# name shapes that were never argued for and check they now land.
#   timeout/nice: a wrapper that eats an OPERAND or an option VALUE. Skipping
#     the wrapper's name and stopping read `5` and `10` as the command.
#   ( ): a subshell was never a command to the laws; the first word was "(cd".
#   env -i: a wrapper's own option read as the command name.
#   xargs -I{}: a wrapper whose value is attached to the flag.
blocks "8. timeout eats an operand"  "$REPO" 'timeout 5 git push --force origin main'
blocks "9. subshell grouping"        "$REPO" '(cd . && git push --force origin main)'
blocks "10. nice -n takes a value"   "$REPO" 'nice -n 10 git push --force origin main'
blocks "11. env -i"                  "$REPO" 'env -i git push --force origin main'
blocks "12. xargs -I{} then sh -c"   "$REPO" 'echo hi | xargs -I{} sh -c "git push --force origin main"'

echo
echo "== e2e: the legitimate twin of every case above still runs =="
allows "timeout of a read"        "$REPO" 'timeout 5 git status'
allows "subshell, no force"       "$REPO" '(cd . && git push origin main)'
allows "nice of a read"           "$REPO" 'nice -n 10 git log --oneline -1'
allows "env -i of a read"         "$REPO" 'env -i git log --oneline -1'
allows "xargs -I{} of a read"     "$REPO" 'echo hi | xargs -I{} sh -c "git status --short"'
allows "plain push, no force"    "$REPO" 'git push origin main'
allows "force-with-lease"        "$REPO" 'git push --force-with-lease origin main'
allows "sh -lc echo"             "$REPO" "sh -lc 'echo hello'"
allows "sh -xc echo"             "$REPO" 'sh -xc "echo hello"'
allows "eval echo"               "$REPO" 'eval "echo hello"'
allows "commit message says it"  "$REPO" 'git commit -m "close the sh -lc and eval bypass: git push --force origin main used to pass"'
allows "echo of the sentence"    "$REPO" 'echo "git push --force origin main"'
allows "substitution of a read"  "$REPO" 'echo $(git rev-parse HEAD)'
allows "backtick of a read"      "$REPO" 'echo `git status --short`'
allows "GIT status"              "$REPO" 'GIT status'
allows "var that is not a subcommand" "$REPO" 'B=feature/x; git push origin $B'
allows "xargs of a read"         "$REPO" 'echo x | xargs bash -c "git log --oneline -1"'
allows "force-push to own branch" "$REPO" 'git push --force origin feature/mine'
allows "continuation, no force"  "$REPO" 'git push \
origin main'
allows "rm -rf inside the project" "$REPO" 'rm -rf node_modules'
allows "python -c is not a shell"  "$REPO" 'python3 -c "git push --force origin main"'

echo
echo "== e2e: the same shapes reach the user rule layer too =="
blocks "guard.json + sh -lc"     "$GREPO" "sh -lc 'git push --force origin main'"
blocks "guard.json + eval"       "$GREPO" 'eval "git push --force origin main"'
allows "guard.json + commit msg" "$GREPO" 'git commit -m "the git push --force origin main bypass"'
allows "guard.json + plain push" "$GREPO" 'git push origin main'

# ---------------------------------------------------------------------------
# the second parser may not come back
# ---------------------------------------------------------------------------
echo
echo "== source: one command parser, not two =="
src_absent() { # src_absent NAME FILE PATTERN
  if grep -q -- "$3" "$2"; then
    bad "$1: $(basename "$2") still carries its own <$3>"
  else
    pass "$1"
  fi
}
src_present() {
  if grep -q -- "$3" "$2"; then pass "$1"; else bad "$1: $(basename "$2") is missing <$3>"; fi
}
src_present "baseline.h links the parser" "$HERE/baseline.h" '#include "cmdtext.h"'
src_absent  "no second quote scanner"     "$HERE/baseline.h" "find('\\\\''"
src_absent  "no second escape copy"       "$HERE/baseline.h" 'cmd\[++i\]'
src_absent  "no second segment splitter"  "$HERE/baseline.h" "c == '&' || c == '|'"
src_absent  "no byte-compare on git"      "$HERE/baseline.h" '== "git"'
# NOT `== "-c"`. baseline.h legitimately compares git's OWN -c (the config
# option in `git -c user.name=x push`), which is a different flag on a different
# program, and asserting against it would be asserting against the git option
# walk rather than against a second parser. The invariant that was actually
# broken is narrower: baseline.h decided which words a SHELL would run, and
# `t[i].text == "-c"` was how it decided. That decision belongs to the parser.
# If a shell name is back in this file, so is the second parser.
src_absent  "no shell of its own (bash)"  "$HERE/baseline.h" '"bash"'
src_absent  "no shell of its own (sh)"    "$HERE/baseline.h" '"sh"'
src_absent  "no shell of its own (zsh)"   "$HERE/baseline.h" '"zsh"'
src_absent  "no eval of its own"          "$HERE/baseline.h" '"eval"'

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
