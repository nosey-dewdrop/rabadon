#!/bin/bash
# short_cluster_test.sh — a cluster of short options is the options in it.
#
# THE HOLE.
#
#   git push -fu origin main
#
# git's subcommands read their options with parse-options, and parse-options
# accepts short options written as ONE word: `-fu` is `--force --set-upstream`.
# Both layers missed it from the same side. The compiled law compared the WHOLE
# token to `-f`, so `-fu` fell past it into "starts with a dash, skip" and force
# stayed false. A project writes the same law as `(--force|-f)\b`, and there is
# no word boundary between the f and the u. One word, two layers, zero refusals.
#
# WHAT REAL GIT DOES. Measured against git 2.39.5 before any of this was
# written, and section 0 below re-measures it on the machine running the suite
# rather than trusting this comment:
#
#   push -fu    into a rewound branch  -> `+ 9179351...728cead main -> main
#                                          (forced update)`, and
#                                         `branch 'main' set up to track
#                                          'origin/main'`. Both halves: the f
#                                         forced, the u set upstream.
#   push -qf / -fq / -uf / -qfu        -> option parse passes (it reaches the
#                                         remote lookup), so order and company
#                                         do not matter.
#   push -fZ                           -> exit 129, "unknown switch `Z'". An
#                                         unknown letter inside a cluster is not
#                                         ignored, it kills the command.
#   git -pv status / git -pC . status  -> exit 129, "unknown option: -pv". git's
#                                         OWN options, the ones before the
#                                         subcommand, are not parse-options and
#                                         do NOT cluster. That is why the split
#                                         starts at the subcommand and not at
#                                         the word `git`.
#
# NOTHING UNDER JUDGEMENT IS EXECUTED, AND THE SETUP ASSUMES THE OPPOSITE.
# Section 2 onward hands real force-pushes and a real recursive delete to the
# gate. The run is built so that a TOTAL failure of the gate — every case
# allowed, and something then running them — still costs nothing:
#   * PATH is prefixed with a shim dir holding fake `git` and `rm` that execute
#     nothing, append their argv to a log and exit 111. The log is asserted
#     EMPTY at the end: judging is not running.
#   * the repos under judgement are mktemp'd and have NO REMOTE, so a
#     force-push has nowhere to go.
#   * HOME is redirected into the same mktemp root, so `rm -rf ~/Documents`
#     names a directory this script created, and a canary file in it is read
#     back at the end.
# Section 0 is the one place a real git runs, it runs BEFORE the shim goes on
# PATH, and it pushes into a bare repo this script created two lines earlier.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
CXX="${CXX:-clang++}"
[ -x "$GATE" ] || { echo "short_cluster_test: build first (make)"; exit 1; }

FAIL=0
PASSN=0
pass() { PASSN=$((PASSN+1)); echo "  ok   $1"; }
bad()  { FAIL=1; echo "  FAIL $1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbcluster.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

REALGIT="$(command -v git)"
export HOME="$ROOT/home"
mkdir -p "$HOME/Documents"
echo "do not lose me" > "$HOME/Documents/canary.txt"

# ---------------------------------------------------------------------------
# 0. the premise, measured on this machine: the f inside a cluster is --force
#    (its own repo, its own bare "remote", both created here, both thrown away)
# ---------------------------------------------------------------------------
echo "== premise: what git does with a clustered short option =="
G() { "$REALGIT" -C "$ROOT/premise" -c user.email=t@t -c user.name=t "$@"; }
"$REALGIT" init -q --bare "$ROOT/bare.git"
"$REALGIT" init -q "$ROOT/premise"
G commit -q --allow-empty -m one
G branch -M main
G remote add origin "$ROOT/bare.git"
G push -q origin main
G commit -q --allow-empty -m two
G push -q origin main
AHEAD="$("$REALGIT" -C "$ROOT/bare.git" rev-parse main)"
G reset -q --hard HEAD~1
BEHIND="$(G rev-parse HEAD)"

PLAIN_OUT="$(G push origin main 2>&1)"; PLAIN=$?
[ "$PLAIN" != "0" ] && printf '%s' "$PLAIN_OUT" | grep -q 'rejected' \
  && pass "a plain push of a rewound branch is rejected (so the next line proves force)" \
  || bad  "a plain push of a rewound branch was accepted; the premise cannot be measured"

CLUSTER_OUT="$(G push -fu origin main 2>&1)"; CLUSTER=$?
[ "$CLUSTER" = "0" ] && [ "$("$REALGIT" -C "$ROOT/bare.git" rev-parse main)" = "$BEHIND" ] \
  && pass "push -fu FORCED the remote back to $(printf '%s' "$BEHIND" | cut -c1-7) (it was $(printf '%s' "$AHEAD" | cut -c1-7))" \
  || { bad "push -fu did not force; the hole this file closes is not the hole"; printf '%s\n' "$CLUSTER_OUT" | sed 's/^/         /'; }
[ "$(G rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" = "origin/main" ] \
  && pass "push -fu also set upstream, so the u in it is --set-upstream" \
  || bad "push -fu did not set upstream"

# a repo with no remote answers "does the option parse pass" and nothing else:
# 128 is the remote lookup, 129 is git refusing the option itself.
N() { "$REALGIT" -C "$ROOT/noremote" -c user.email=t@t -c user.name=t "$@" >/dev/null 2>&1; echo $?; }
"$REALGIT" init -q "$ROOT/noremote"
N commit -q --allow-empty -m one >/dev/null
N branch -M main >/dev/null
for OPT in -fu -qf -fq -uf -qfu; do
  [ "$(N push $OPT origin main)" = "128" ] \
    && pass "git accepts 'push $OPT' as options (it reached the remote lookup)" \
    || bad  "git did not parse 'push $OPT' as options"
done
[ "$(N push -fZ origin main)" = "129" ] \
  && pass "an unknown letter in a cluster is refused by git, not ignored" \
  || bad  "git accepted an unknown letter inside a cluster"
[ "$(N -pv status)" = "129" ] \
  && pass "git's OWN options do not cluster (-pv is unknown), so the split starts at the subcommand" \
  || bad  "git clustered its own leading options; the split must then start earlier"
[ "$(N -pC . status)" = "129" ] \
  && pass "the same for -pC, a global that takes a value" \
  || bad  "git clustered -pC"

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

REPO="$ROOT/proj"
"$REALGIT" init -q "$REPO"
"$REALGIT" -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
"$REALGIT" -C "$REPO" branch -M main
REPO_HEAD="$("$REALGIT" -C "$REPO" rev-parse HEAD)"
# no `git remote add` in this repo, on purpose: there is nothing to push to.

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
# 1. unit: the ONE parser, asked what argv git will really run
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
u_notargv() {
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then
    bad "$name: a command decomposed to <$want>, and git does not read it that way"
    printf '%s\n' "$out" | sed 's/^/         got: /'
  else pass "$name"; fi
}

echo
echo "== unit: the options a cluster carries =="
if [ "$UNIT_OK" = "0" ]; then
  echo "  (probe did not compile)"; sed -n '1,12p' "$ROOT/cc.log" | sed 's/^/         /'
fi
u_argv "-fu is --force --set-upstream" "git push -fu origin main"   '|push|-f|-u|origin|main'
u_argv "order does not matter"         "git push -uf origin main"   '|push|-u|-f|origin|main'
u_argv "company does not matter"       "git push -qfu origin main"  '|push|-q|-f|-u|origin|main'
u_argv "a cluster with no operands"    "git push -fu"               '|push|-f|-u'
u_argv "globals then a cluster"        "git -C /tmp push -fu origin main" '|push|-f|-u|origin|main'
u_argv "an alias body carries one"     "git -c alias.x='push -fu' x origin main" '|push|-f|-u|origin|main'
u_argv "a single short option is one"  "git push -f origin main"    '|push|-f|origin|main'

echo
echo "== unit: what a cluster is NOT (the split invents nothing) =="
u_notargv "git's own options do not cluster" "git -pv status"        '|-p|-v|'
u_notargv "a global taking a value"          "git -pC . status"      '|-p|-C|'
u_notargv "a long option is not a cluster"   "git push --force origin main" '|-f|-o|'
u_notargv "an attached value with a dot"     "git push -oci.skip origin main" '|-o|-c|'
u_notargv "an attached value with a hyphen"  "git commit -mfix-typo" '|-m|-f|'
u_notargv "an attached count is a number"    "git log -12"           '|-1|-2'
u_notargv "an attached count after a letter" "git log -n5"           '|-n|-5'
u_notargv "after -- it is a path, not flags" "git log --oneline -- -fu" '|-f|-u'
# NAMED LIMIT, not hidden: an attached value made only of letters reads as more
# options than git sees. It changes no verdict — no law reads a short flag
# outside `git push` — and the twin at the bottom of section 4 holds that.
u_argv    "a letters-only attached value (named limit)" "git commit -mfix" '|commit|-m|-f|-i|-x'

# ---------------------------------------------------------------------------
# 2. e2e: the real binary
# ---------------------------------------------------------------------------
judge() { # judge <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"cluster","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
blocks() { local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then pass "$1"; else bad "$1: allowed (exit $got), and the same push spelled -f is refused"; fi; }
allows() { local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then bad "$1: refused, and refusing it cuts real work"; else pass "$1"; fi; }

echo
echo "== e2e: the cluster against the three compiled-in laws (no guard.json) =="
blocks "the reported command"        "$REPO" "git push -fu origin main"
blocks "sibling -qf"                 "$REPO" "git push -qf origin main"
blocks "sibling -fq"                 "$REPO" "git push -fq origin main"
blocks "sibling -uf"                 "$REPO" "git push -uf origin main"
blocks "three letters"               "$REPO" "git push -qfu origin main"
blocks "no refspec, current branch"  "$REPO" "git push -fu"
blocks "no refspec, remote only"     "$REPO" "git push -fu origin"
blocks "the + refspec and a cluster" "$REPO" "git push -qu origin +main"
blocks "a global before it"          "$REPO" "git -C $REPO push -fu origin main"
blocks "inside sh -lc"               "$REPO" "sh -lc 'git push -fu origin main'"
blocks "inside eval"                 "$REPO" "eval 'git push -fu origin main'"
blocks "inside an alias body"        "$REPO" "git -c alias.x='push -fu' x origin main"
blocks "inside a loop body"          "$REPO" "for b in main; do git push -fu origin \$b; done"
blocks "inside a function body"      "$REPO" "gx() { git push -fu origin main; }; gx"
blocks "after a && chain"            "$REPO" "npm test && git push -fu origin main"

echo
echo "== e2e: the same shapes reach the user rule layer =="
blocks "guard.json + -fu"            "$GREPO" "git push -fu origin main"
blocks "guard.json + -qf"            "$GREPO" "git push -qf origin main"
blocks "guard.json + -qfu"           "$GREPO" "git push -qfu origin main"
blocks "guard.json + alias body"     "$GREPO" "git -c alias.x='push -fu' x origin main"
blocks "guard.json + sh -lc"         "$GREPO" "sh -lc 'git push -fu origin main'"

echo
echo "== e2e: the legitimate twin of every case above still runs =="
allows "-u alone"                    "$REPO" "git push -u origin main"
allows "-q alone"                    "$REPO" "git push -q origin main"
allows "-qu, no f in it"             "$REPO" "git push -qu origin main"
allows "a cluster to a private branch" "$REPO" "git push -fu origin feature/mine"
allows "a lease push with -u"        "$REPO" "git push -u --force-with-lease origin main"
allows "a lease push, cluster order" "$REPO" "git push --force-with-lease -qu origin main"
allows "a fetch cluster"             "$REPO" "git fetch -pq origin"
allows "an attached push option"     "$REPO" "git push -oci.skip origin main"
allows "a separated push option"     "$REPO" "git push -o ci.skip origin main"
allows "commit with -am"             "$REPO" "git commit -am fix"
allows "commit with an attached msg" "$REPO" "git commit -mfix"
allows "log with a count"            "$REPO" "git log -12 --oneline"
allows "the cluster in a commit msg" "$REPO" "git commit -m \"git push -fu origin main is the bypass\""
allows "the cluster in an echo"      "$REPO" "echo 'git push -fu origin main'"
allows "guard.json + -qu"            "$GREPO" "git push -qu origin main"
allows "guard.json + private branch" "$GREPO" "git push -fu origin feature/mine"

echo
echo "== e2e: the plain spellings did not stop working =="
blocks "plain force-push"            "$REPO" "git push --force origin main"
blocks "-f as its own word"          "$REPO" "git push -f -u origin main"
blocks "plain hard reset"            "$REPO" "git reset --hard origin/main"
blocks "rm -rf outside the project"  "$REPO" "rm -rf ~/Documents"
allows "plain push"                  "$REPO" "git push origin main"
allows "force-with-lease"            "$REPO" "git push --force-with-lease origin main"
allows "rm -rf inside the project"   "$REPO" "rm -rf node_modules"

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
