#!/bin/bash
# arch_wrapper_test.sh — a launcher that ships with the machine is still a launcher.
#
# THE HOLE.
#
#   arch -arm64 git push --force origin main
#
# arch(1) is in /usr/bin on every mac. Given an architecture it execs the
# program named after its options, exactly the way sudo, env and timeout do.
# The wrapper list in native/cmdtext.h had sudo/doas/env/command/builtin/nohup/
# setsid/exec/stdbuf/time/nice/ionice/timeout/xargs on it and did not have arch,
# so command_index() stopped on the word `arch`, base_of() handed the rule
# engine `arch` as the command name, and `arch` is neither git nor rm. The
# segment was marked irrelevant and NONE of the compiled laws were asked — not
# force-push, not branch-delete, not hard-reset, not rm -rf. One word in front
# of the line turned the whole baseline off.
#
# Measured before this file was written, against the built gate, in a repo with
# no guard.json so only the compiled laws could answer:
#
#   git push --force origin main                    -> BLOCK
#   sudo git push --force origin main               -> BLOCK   (a listed wrapper)
#   arch -arm64 git push --force origin main        -> ALLOW
#   arch -arch arm64 git push --force origin main   -> ALLOW
#   arch -arm64 git push origin :main               -> ALLOW
#   arch -arm64 git reset --hard origin/main        -> ALLOW
#   arch -arm64 rm -rf ~/Documents                  -> ALLOW
#
# WHY THE SHORT-CLUSTER MACHINERY DOES NOT FIT THIS WRAPPER. Every other
# wrapper on the list takes options a shell tool clusters: `-n1`, `-qf`, `-io`.
# arch does not cluster. A single-dash word is an ARCHITECTURE NAME unless it is
# one of arch's own five flags, and section 0 measures that on this machine:
# `arch -eFOO=bar ...` is refused with "Unknown architecture: eFOO=bar", not
# read as -e with an attached value. So `-arm64e` is one word whose trailing `e`
# is part of the name arm64e, and a parser that read it as the `-e` option would
# eat the next word — the command — and open the hole again from the other side.
# The fix therefore matches arch's value-taking options as WHOLE WORDS
# (`-arch`, `-d`, `-e`), which is the rule that was already there for `--long`
# options, applied to a single dash. No new code path: the same loop, the same
# table, one dash fewer.
#
# NOTHING UNDER JUDGEMENT IS EXECUTED, AND THE SETUP ASSUMES THE OPPOSITE.
# Sections 1 and 2 hand real force-pushes, a real branch delete and a real
# recursive delete to the gate. The run is built so that a TOTAL failure of the
# gate — every case allowed, and something then running them — still costs
# nothing:
#   * PATH is prefixed with a shim dir holding fake `git`, `rm` and `arch` that
#     execute nothing, append their argv to a log and exit 111. The log is
#     asserted EMPTY at the end: judging is not running.
#   * the repo under judgement is mktemp'd and has NO REMOTE, so a force-push
#     has nowhere to go and a branch delete has nothing to delete.
#   * HOME is redirected into the same mktemp root, so `rm -rf ~/Documents`
#     names a directory this script created, and a canary file in it is read
#     back at the end.
# Section 0 is the one place a real binary runs. It runs BEFORE the shim goes on
# PATH, the only program it launches is /bin/echo, and it launches it through
# the very wrapper under test — which is the point: the premise is measured, not
# quoted from a manual.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
CXX="${CXX:-clang++}"
[ -x "$GATE" ] || { echo "arch_wrapper_test: build first (make)"; exit 1; }

FAIL=0
PASSN=0
pass() { PASSN=$((PASSN+1)); echo "  ok   $1"; }
bad()  { FAIL=1; echo "  FAIL $1"; }
note() { echo "  --   $1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbarch.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

REALGIT="$(command -v git)"
REALARCH="$(command -v arch || true)"
export HOME="$ROOT/home"
mkdir -p "$HOME/Documents"
echo "do not lose me" > "$HOME/Documents/canary.txt"

# ---------------------------------------------------------------------------
# 0. the premise, measured on this machine: arch RUNS the command after it,
#    and its single-dash words are whole names, not clusters.
#    The only program launched here is /bin/echo.
# ---------------------------------------------------------------------------
echo "== premise: what arch(1) does with the words after it =="
MACH="$(uname -m 2>/dev/null || echo unknown)"
if [ "$(uname -s 2>/dev/null)" != "Darwin" ] || [ -z "$REALARCH" ]; then
  note "not a mac with arch(1): the premise cannot be measured here, and the"
  note "     parser checks below still run (they execute nothing)"
else
  OUT="$("$REALARCH" "-$MACH" /bin/echo RAN-arch 2>&1)"
  [ "$OUT" = "RAN-arch" ] \
    && pass "arch -$MACH /bin/echo RAN-arch printed RAN-arch (arch execs what follows it)" \
    || bad  "arch did not run the command after it; the hole this file closes is not the hole ($OUT)"

  OUT="$("$REALARCH" -arch "$MACH" /bin/echo RAN-arch 2>&1)"
  [ "$OUT" = "RAN-arch" ] \
    && pass "arch -arch $MACH /bin/echo ran too, so -arch takes a SEPARATE value word" \
    || bad  "-arch did not take a separate value ($OUT)"

  # if -d did not eat a word, RBARCHTEST would be the program and echo an argument
  OUT="$("$REALARCH" "-$MACH" -d RBARCHTEST /bin/echo RAN-arch 2>&1)"
  [ "$OUT" = "RAN-arch" ] \
    && pass "-d ate the word after it (the program was still /bin/echo)" \
    || bad  "-d did not take a separate value ($OUT)"

  OUT="$("$REALARCH" "-$MACH" -e RBARCHTEST=1 /bin/echo RAN-arch 2>&1)"
  [ "$OUT" = "RAN-arch" ] \
    && pass "-e ate the word after it" \
    || bad  "-e did not take a separate value ($OUT)"

  OUT="$("$REALARCH" -eFOO=bar /bin/echo RAN-arch 2>&1)"
  case "$OUT" in
    *"Unknown architecture"*) pass "arch has no attached-value form: -eFOO=bar is read as an ARCH NAME, so its single-dash words do not cluster" ;;
    *) bad "arch accepted an attached -e value; the whole-word rule below is then wrong ($OUT)" ;;
  esac

  if [ "$MACH" = "arm64" ]; then
    OUT="$("$REALARCH" -arm64e /bin/echo RAN-arch 2>&1)"
    [ "$OUT" = "RAN-arch" ] \
      && pass "-arm64e ran the command: its trailing 'e' is part of the name, not the -e option" \
      || note "-arm64e did not run here ($OUT); the parser check for it below still runs"
  else
    note "-arm64e is an Apple Silicon name; not measurable on $MACH, parser check below still runs"
  fi

  OUT="$("$REALARCH" 2>&1)"
  case "$OUT" in
    *" "*|"") bad "bare arch did not print a single architecture name ($OUT)" ;;
    *) pass "bare arch printed '$OUT' and ran nothing, so it must stay allowed" ;;
  esac
fi

# ---- the blast shield ------------------------------------------------------
SHIM="$ROOT/shim"; mkdir -p "$SHIM"
RANLOG="$ROOT/ran.log"
: > "$RANLOG"
for TOOL in git rm arch; do
  cat > "$SHIM/$TOOL" <<SH
#!/bin/sh
printf '%s %s\n' "$TOOL" "\$*" >> "$RANLOG"
exit 111
SH
  chmod +x "$SHIM/$TOOL"
done

REPO="$ROOT/proj"
"$REALGIT" init -q "$REPO"
"$REALGIT" -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
"$REALGIT" -C "$REPO" branch -M main
REPO_HEAD="$("$REALGIT" -C "$REPO" rev-parse HEAD)"
# no `git remote add` in this repo, on purpose: there is nothing to push to.
# no .rabadon/guard.json in it either, on purpose: the layer that leaked was the
# compiled baseline, and a project deny regex would have masked it (its pattern
# matches the raw text and never asks which word is the command).

GREPO="$ROOT/guarded"
mkdir -p "$GREPO/.rabadon"
"$REALGIT" init -q "$GREPO"
"$REALGIT" -C "$GREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
"$REALGIT" -C "$GREPO" branch -M main
cat > "$GREPO/.rabadon/guard.json" <<'JSON'
{
  "project": "guarded",
  "bash": [
    { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b", "why": "force-pushing a shared branch destroys history" }
  ],
  "protectedPaths": [], "disabled": []
}
JSON

export RABADON_DIR="$ROOT/rhome"; mkdir -p "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"
export RABADON_NOTIFY=0
export PATH="$SHIM:$PATH"

# ---------------------------------------------------------------------------
# 1. unit: the ONE parser, asked which word it calls the command
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

u_argv() { # u_argv NAME CMD EXPECTED-SUBSTRING
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then pass "$name"
  else bad "$name: no command decomposed to <$want>"; printf '%s\n' "$out" | sed 's/^/         got: /'; fi
}
u_notargv() { # u_notargv NAME CMD FORBIDDEN-SUBSTRING
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then
    bad "$name: a command decomposed to <$want>, and a shell does not read it that way"
    printf '%s\n' "$out" | sed 's/^/         got: /'
  else pass "$name"; fi
}

echo
echo "== unit: the command word behind arch =="
if [ "$UNIT_OK" = "0" ]; then
  echo "  (probe did not compile)"; sed -n '1,12p' "$ROOT/cc.log" | sed 's/^/         /'
fi
u_argv "an arch name is skipped"        "arch -arm64 git push --force origin main"        'cmd=git words=git|push|--force|origin|main'
u_argv "the intel name too"             "arch -x86_64 git push --force origin main"       'cmd=git words=git|push|--force|origin|main'
u_argv "the haswell name too"           "arch -x86_64h git push --force origin main"      'cmd=git words=git|push|--force|origin|main'
u_argv "-arch takes a value word"       "arch -arch arm64 git push --force origin main"   'cmd=git words=git|push|--force|origin|main'
u_argv "-d takes a value word"          "arch -arm64 -d FOO git push --force origin main" 'cmd=git words=git|push|--force|origin|main'
u_argv "-e takes a value word"          "arch -arm64 -e FOO=bar git push --force origin main" 'cmd=git words=git|push|--force|origin|main'
u_argv "-c takes none"                  "arch -arm64 -c git push --force origin main"     'cmd=git words=git|push|--force|origin|main'
u_argv "a trailing e is part of a name" "arch -arm64e git push --force origin main"       'cmd=git words=git|push|--force|origin|main'
u_argv "two arch names in a row"        "arch -arm64 -x86_64 git push --force origin main" 'cmd=git words=git|push|--force|origin|main'
u_argv "arch under a listed wrapper"    "sudo arch -arm64 git push --force origin main"   'cmd=git words=git|push|--force|origin|main'
u_argv "a listed wrapper under arch"    "arch -arm64 sudo git push --force origin main"   'cmd=git words=git|push|--force|origin|main'
u_argv "an absolute path to it"         "/usr/bin/arch -arm64 git push --force origin main" 'cmd=git words=git|push|--force|origin|main'
u_argv "rm behind it"                   "arch -arm64 rm -rf /etc"                         'cmd=rm words=rm|-rf|/etc'

echo
echo "== unit: what the skip does NOT swallow =="
# the value word of -d/-e is eaten; the word after an ARCH NAME never is
u_notargv "an arch name eats no word"   "arch -arm64 git status"        'cmd=status'
u_notargv "-arm64e eats no word"        "arch -arm64e git status"       'cmd=status'
# the name is matched exactly, not as a prefix. A plain `archey git push ...` is
# NOT the case that shows it: what happens to a word the table does not have is
# decided elsewhere in cmdtext.h and is not this entry's business. The word that
# separates the two is an option only ARCH eats -- `-d` takes a SEPARATE value,
# so a prefix match would swallow FOO and land on git. It has to stop at FOO.
u_notargv "the name is exact, not a prefix" "archey -d FOO git push --force origin main" 'cmd=git'
u_argv    "and archey stays the command"    "archey -d FOO git push --force origin main" 'cmd=archey'
u_argv    "bare arch names no command"      "arch"                          'cmd= words='

# ---------------------------------------------------------------------------
# 2. e2e: the real binary
# ---------------------------------------------------------------------------
judge() { # judge <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"archwrap","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
blocks() { local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then pass "$1"; else bad "$1: allowed (exit $got), and the same line without arch is refused"; fi; }
allows() { local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then bad "$1: refused, and refusing it cuts real work"; else pass "$1"; fi; }

echo
echo "== e2e: arch against the compiled-in laws (no guard.json) =="
blocks "the reported command"          "$REPO" "arch -arm64 git push --force origin main"
blocks "the intel name"                "$REPO" "arch -x86_64 git push -f origin main"
blocks "the -arch spelling"            "$REPO" "arch -arch arm64 git push --force origin main"
blocks "a name with a trailing e"      "$REPO" "arch -arm64e git push --force origin main"
blocks "an env delete in front"        "$REPO" "arch -arm64 -d SOMEVAR git push --force origin main"
blocks "an env set in front"           "$REPO" "arch -arm64 -e FOO=bar git push --force origin main"
blocks "a cleared environment"         "$REPO" "arch -arm64 -c git push --force origin main"
blocks "no refspec, current branch"    "$REPO" "arch -arm64 git push --force"
blocks "the + refspec"                 "$REPO" "arch -arm64 git push origin +main"
blocks "a branch delete"               "$REPO" "arch -arm64 git push origin :main"
blocks "the --delete spelling"         "$REPO" "arch -arm64 git push --delete origin main"
blocks "a hard reset"                  "$REPO" "arch -arm64 git reset --hard origin/main"
blocks "a delete outside the project"  "$REPO" "arch -arm64 rm -rf ~/Documents"
blocks "an absolute path to arch"      "$REPO" "/usr/bin/arch -arm64 git push --force origin main"
blocks "arch under sudo"               "$REPO" "sudo arch -arm64 git push --force origin main"
blocks "sudo under arch"               "$REPO" "arch -arm64 sudo git push --force origin main"
blocks "arch under env"                "$REPO" "env FOO=bar arch -arm64 git push --force origin main"
blocks "inside sh -lc"                 "$REPO" "sh -lc 'arch -arm64 git push --force origin main'"
blocks "inside eval"                   "$REPO" "eval 'arch -arm64 git push --force origin main'"
blocks "after a && chain"              "$REPO" "npm test && arch -arm64 git push --force origin main"
blocks "inside a loop body"            "$REPO" "for b in main; do arch -arm64 git push --force origin \$b; done"
blocks "inside a function body"        "$REPO" "gx() { arch -arm64 git push --force origin main; }; gx"
blocks "the case-insensitive name"     "$REPO" "ARCH -arm64 git push --force origin main"

echo
echo "== e2e: the same shapes reach the user rule layer =="
blocks "guard.json + arch"             "$GREPO" "arch -arm64 git push --force origin main"
blocks "guard.json + sh -lc"           "$GREPO" "sh -lc 'arch -arm64 git push --force origin main'"

echo
echo "== e2e: the legitimate twin of every case above still runs =="
allows "bare arch prints the machine"  "$REPO" "arch"
allows "arch with a name and no cmd"   "$REPO" "arch -arm64"
allows "a build under arch"            "$REPO" "arch -x86_64 npm test"
allows "an install under arch"         "$REPO" "arch -x86_64 npm install"
allows "an env set under arch"         "$REPO" "arch -arm64 -e FOO=bar npm run build"
allows "a status under arch"           "$REPO" "arch -arm64 git status"
allows "a plain push under arch"       "$REPO" "arch -arm64 git push origin main"
allows "a private branch under arch"   "$REPO" "arch -arm64 git push --force origin feature/mine"
allows "a lease push under arch"       "$REPO" "arch -arm64 git push --force-with-lease origin main"
allows "a private branch delete"       "$REPO" "arch -arm64 git push origin :feature/mine"
allows "a soft reset under arch"       "$REPO" "arch -arm64 git reset --soft origin/main"
allows "a scratch delete under arch"   "$REPO" "arch -arm64 rm -rf node_modules"
# `archey git push --force origin main` is deliberately NOT a case here. Its
# verdict belongs to whatever rule reads a word the wrapper table does not have,
# and that is a different subject from what arch's ENTRY says arch eats. The one
# question this file owes about the name -- that `archey` is not matched against
# ARCH's option grammar -- is the unit check above, where `-d` is the only word
# that can tell the two apart.
allows "the line inside a commit msg"  "$REPO" "git commit -m \"arch -arm64 git push --force origin main is the bypass\""
allows "the line inside an echo"       "$REPO" "echo 'arch -arm64 git push --force origin main'"
allows "guard.json + private branch"   "$GREPO" "arch -arm64 git push --force origin feature/mine"
allows "guard.json + plain push"       "$GREPO" "arch -arm64 git push origin main"

echo
echo "== e2e: the wrappers that were already listed did not change =="
blocks "plain force-push"              "$REPO" "git push --force origin main"
blocks "sudo force-push"               "$REPO" "sudo git push --force origin main"
blocks "env -i force-push"             "$REPO" "env -i git push --force origin main"
blocks "timeout force-push"            "$REPO" "timeout 5 git push --force origin main"
blocks "xargs bash -c force-push"      "$REPO" "xargs bash -c 'git push --force origin main'"
blocks "nice force-push"               "$REPO" "nice -n 10 git push --force origin main"
allows "plain push"                    "$REPO" "git push origin main"
allows "sudo plain push"               "$REPO" "sudo git push origin main"
allows "timeout plain push"            "$REPO" "timeout 5 git push origin main"
allows "rm -rf inside the project"     "$REPO" "rm -rf node_modules"

# ---------------------------------------------------------------------------
# judging is not running
# ---------------------------------------------------------------------------
echo
echo "== canaries =="
if [ -s "$RANLOG" ]; then
  bad "something EXECUTED while being judged:"; sed 's/^/         /' "$RANLOG"
else
  pass "the fake git/rm/arch on PATH were never called (judging is not running)"
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
