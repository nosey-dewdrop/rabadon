#!/bin/bash
# shell_function_test.sh — a name the line defines and then runs.
#
# The red team's line:
#
#   gitx() { git push --force origin main; }; gitx
#
# The scanner splits on `;` and hands the laws three commands. The first is
# called `gitx()` and happens to carry `git push --force origin main` in its
# argument list. The second is called `}`. The third is the bare word `gitx`,
# which resolves to nothing any law can read. Not one of the three is a `git`,
# so the force-push is invisible — and bash runs it.
#
# The same three-way split is why the MULTILINE spelling was already caught:
#
#   gitx() {
#     git push --force origin main
#   }
#   gitx
#
# there the newline puts the body in its own segment, so `git` lands in command
# position by accident. Same program, opposite verdict, decided by a semicolon.
# The gate was reading punctuation, not the shell.
#
# What a shell actually does with those bytes is two different things at two
# different times. A DEFINITION runs nothing at all: it binds a name to a body
# and moves on. A CALL runs the body, in the caller's own shell, with the
# caller's working directory. So the body is lifted out of the run list where it
# is written and put back where it is CALLED, and a function that is defined and
# never called is what it is — nothing that ran.
#
# THE NEGATIVES ARE THE POINT. The cheap way to pass the positives below is to
# refuse any line with `()` and a brace in it, which kills every helper any
# engineer has ever written at a prompt. Each block has a twin that must still
# run, and the twins differ only in what the BODY says or in whether the name is
# ever called.
#
# NOTHING HERE IS EXECUTED, AND THE SETUP ASSUMES THE OPPOSITE.
#   * PATH is prefixed with a shim dir holding fake git, rm, bash, sh, zsh and
#     dash. They run nothing, append their argv to a log and exit 111. The log
#     is asserted EMPTY at the end.
#   * the repo under judgement is mktemp'd and has NO REMOTE, so even a real
#     force-push has nowhere to land.
#   * HOME points inside the same mktemp root, so `rm -rf ~/Documents` names a
#     directory this script made; a canary file in it is read back at the end.
#   * the repo's HEAD is recorded before and compared after, so a `git reset
#     --hard` that got through would be visible instead of silent.
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
[ -x "$GATE" ] || { echo "shell_function_test: build first (make)"; exit 1; }

FAIL=0
PASSN=0
pass() { PASSN=$((PASSN+1)); echo "  ok   $1"; }
bad()  { FAIL=1; echo "  FAIL $1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbfn.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# ---- the blast shield ------------------------------------------------------
SHIM="$ROOT/shim"; mkdir -p "$SHIM"
RANLOG="$ROOT/ran.log"
: > "$RANLOG"
for TOOL in git rm bash sh zsh dash; do
  cat > "$SHIM/$TOOL" <<SH
#!/bin/sh
printf '%s %s\n' "$TOOL" "\$*" >> "$RANLOG"
exit 111
SH
  chmod +x "$SHIM/$TOOL"
done
# the shim goes on PATH at the BOTTOM of the setup, not here: this script builds
# a probe and inits a repo first, and a shimmed git would fake both. The real
# path is kept so the canary checks at the end are answered by git and not by a
# fake that prints nothing and exits 111 — a shimmed `rev-parse` would report
# every HEAD as unchanged, which is the one answer this file must not invent.
REALGIT="$(command -v git)"
REPO="$ROOT/proj"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
git -C "$REPO" branch -M main
REPO_HEAD="$(git -C "$REPO" rev-parse HEAD)"
# no `git remote add` anywhere in this file, on purpose.

export HOME="$ROOT/home"
mkdir -p "$HOME/Documents"
echo "do not lose me" > "$HOME/Documents/canary.txt"
export RABADON_DIR="$ROOT/rhome"; mkdir -p "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"
export RABADON_NOTIFY=0

# ---------------------------------------------------------------------------
# unit: the parser is asked what the line RUNS
# ---------------------------------------------------------------------------
# One line per command that runs, with its argv. A body that a call reaches has
# to appear here as its own command, the same way a `bash -c` string already
# does. A gap between this list and what bash would run IS the bypass.
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
    printf("cmd=%s words=", name.c_str());
    for (size_t k = ci; k < s.words.size(); k++)
      printf("%s%s", k == ci ? "" : "|", s.words[k].text.c_str());
    printf("\n");
  }
  return 0;
}
CPP
UNIT_OK=1
"$CXX" -std=c++17 -O1 -Wall -Wextra -I "$HERE" -o "$ROOT/probe" "$ROOT/probe.cpp" 2>"$ROOT/cc.log" || UNIT_OK=0

u_argv() { # u_argv NAME CMD EXPECTED
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then
    pass "$name"
  else
    bad "$name: no command decomposed to <$want>"
    printf '%s\n' "$out" | sed 's/^/         got: /'
  fi
}
u_notargv() { # u_notargv NAME CMD FORBIDDEN
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then
    bad "$name: a command decomposed to <$want>, but nothing runs it"
    printf '%s\n' "$out" | sed 's/^/         got: /'
  else
    pass "$name"
  fi
}

PUSH='cmd=git words=git|push|--force|origin|main'
RMDOC='cmd=rm words=rm|-rf|~/Documents'
RESET='cmd=git words=git|reset|--hard|origin/main'

echo "== unit: a body that gets called is a command that runs =="
if [ "$UNIT_OK" = "0" ]; then
  echo "  (probe did not compile)"; sed -n '1,12p' "$ROOT/cc.log" | sed 's/^/         /'
fi
u_argv "the red team's line" \
  'gitx() { git push --force origin main; }; gitx' "$PUSH"
u_argv "a space before the parens" \
  'gitx () { git push --force origin main; }; gitx' "$PUSH"
u_argv "the function keyword" \
  'function gitx { git push --force origin main; }; gitx' "$PUSH"
u_argv "the function keyword with parens" \
  'function gitx() { git push --force origin main; }; gitx' "$PUSH"
u_argv "the brace on its own line" \
  'gitx()
{
  git push --force origin main
}
gitx' "$PUSH"
u_argv "the multiline body, still caught" \
  'gitx() {
  git push --force origin main
}
gitx' "$PUSH"
u_argv "the delete law through a name" \
  'nuke() { rm -rf ~/Documents; }; nuke' "$RMDOC"
u_argv "the reset law through a name" \
  'undo() { git reset --hard origin/main; }; undo' "$RESET"
u_argv "one function calling another" \
  'a() { git push --force origin main; }; b() { a; }; b' "$PUSH"
u_argv "called twice, still once is enough" \
  'gitx() { git push --force origin main; }; gitx; gitx' "$PUSH"
u_argv "the call is not the last thing on the line" \
  'gitx() { git push --force origin main; }; gitx; echo done' "$PUSH"
u_argv "a bare brace group runs what is inside it" \
  '{ git push --force origin main; }' "$PUSH"

echo
echo "== unit: a definition binds a name, it does not run a body =="
u_notargv "defined, never called" \
  'gitx() { git push --force origin main; }' "$PUSH"
u_notargv "defined multiline, never called" \
  'gitx() {
  git push --force origin main
}' "$PUSH"
u_notargv "a different name is called" \
  'gitx() { git push --force origin main; }; ls' "$PUSH"
u_notargv "the name is quoted data" \
  "echo 'gitx() { git push --force origin main; }; gitx'" "$PUSH"

echo
echo "== unit: a recursive name terminates =="
# `gitx() { gitx; }; gitx` never returns in a shell either. What matters here is
# that the PARSER returns: an expansion budget bounds it instead of a stack.
# macOS ships no `timeout`, and a hang in a pre-commit gate is the failure this
# check exists to catch, so the bound is enforced here rather than assumed.
run_bounded() { # run_bounded SECONDS CMD... ; 124 on timeout
  local secs="$1"; shift
  "$@" >/dev/null 2>&1 &
  local pid=$! i=0
  while [ "$i" -lt "$((secs * 10))" ]; do
    kill -0 "$pid" 2>/dev/null || { wait "$pid"; return $?; }
    sleep 0.1
    i=$((i + 1))
  done
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return 124
}
u_terminates() { # u_terminates NAME CMD
  local name="$1"
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  printf '%s' "$2" > "$ROOT/rec.txt"
  if run_bounded 10 "$ROOT/probe" < "$ROOT/rec.txt"; then
    pass "$name"
  else
    bad "$name: the parser hung, crashed or was killed at the 10s bound"
  fi
}
u_terminates "a function that calls itself does not hang the parser" \
  'gitx() { gitx; }; gitx'
u_terminates "two functions calling each other do not hang the parser" \
  'a() { b; }; b() { a; }; a'
u_terminates "a recursive body with a real command in it still returns" \
  'gitx() { git push --force origin main; gitx; }; gitx'

# ---------------------------------------------------------------------------
# e2e: the real binary, on a repo with NO guard.json (the fresh-install case)
# ---------------------------------------------------------------------------
# No guard.json on purpose: a deny regex would match the definition TEXT and
# hide whether the laws can read the call. What answers here is the three laws
# compiled into the binary and nothing else.
export PATH="$SHIM:$PATH"

judge() {
  printf '{"hook_event_name":"PreToolUse","session_id":"fn","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
blocks() { local got; got="$(judge "$REPO" "$1")"
  if [ "$got" = "2" ]; then pass "$2"; else bad "$2: allowed (exit $got)"; fi; }
allows() { local got; got="$(judge "$REPO" "$1")"
  if [ "$got" = "2" ]; then bad "$2: refused, and refusing it cuts real work"; else pass "$2"; fi; }

echo
echo "== e2e: the line the red team proved, against the compiled-in laws =="
blocks 'gitx() { git push --force origin main; }; gitx'                "A. the red team's line"
blocks 'gitx () { git push --force origin main; }; gitx'               "B. a space before the parens"
blocks 'function gitx { git push --force origin main; }; gitx'         "C. the function keyword"
blocks 'function gitx() { git push --force origin main; }; gitx'       "D. the function keyword with parens"
blocks 'nuke() { rm -rf ~/Documents; }; nuke'                          "E. the delete law through a name"
blocks 'undo() { git reset --hard origin/main; }; undo'                "F. the reset law through a name"
blocks 'a() { git push --force origin main; }; b() { a; }; b'          "G. one function calling another"
blocks 'gitx() { git push --force origin main; }; gitx; echo done'     "H. the call is not last"
blocks '{ git push --force origin main; }'                             "I. a bare brace group"
blocks 'gitx() {
  git push --force origin main
}
gitx'                                                                  "J. the multiline spelling stays blocked"

echo
echo "== e2e: the twins — a name is not a crime =="
allows 'gitx() { git push origin main; }; gitx'                        "a helper that pushes without --force"
allows 'deploy() { git push --force-with-lease origin main; }; deploy' "a helper that uses the lease"
allows 'gitx() { git push --force origin scratch; }; gitx'             "a helper that forces a branch of her own"
allows 'st() { git status --short; }; st'                              "a status helper"
allows 'clean() { rm -rf ./node_modules; }; clean'                     "a helper that deletes its own build output"
allows 'gitx() { git push --force origin main; }'                      "defined and never called"
allows 'gitx() { git push --force origin main; }; ls'                  "defined, and something else is called"
allows "echo 'gitx() { git push --force origin main; }; gitx'"         "the whole thing as quoted data"
allows 'note() { echo "gitx() { git push --force origin main; }"; }; note' \
                                                                       "a helper whose body PRINTS the line"
allows '{ git status; }'                                               "a bare brace group that is harmless"
allows 'build() { npm run build; }; build'                             "the shape every engineer writes"

# ---------------------------------------------------------------------------
# nothing ran
# ---------------------------------------------------------------------------
echo
echo "== the shield held =="
if [ -s "$RANLOG" ]; then
  bad "a shimmed tool was executed:"; sed 's/^/         /' "$RANLOG"
else
  pass "no git/rm/bash/sh/zsh/dash was executed (judging is not running)"
fi
if [ "$(cat "$HOME/Documents/canary.txt" 2>/dev/null)" = "do not lose me" ]; then
  pass "the canary under \$HOME survived"
else
  bad "the canary under \$HOME is gone or changed"
fi
if [ "$("$REALGIT" -C "$REPO" rev-parse HEAD 2>/dev/null)" = "$REPO_HEAD" ]; then
  pass "the judged repo's HEAD did not move"
else
  bad "the judged repo's HEAD moved"
fi
if [ -z "$("$REALGIT" -C "$REPO" remote 2>/dev/null)" ]; then
  pass "the judged repo still has no remote (a force-push had nowhere to land)"
else
  bad "the judged repo grew a remote"
fi

echo
if [ "$FAIL" = "0" ]; then
  echo "PASS ($PASSN checks)"
else
  echo "FAIL"
fi
exit $FAIL
