#!/bin/bash
# long_option_prefix_test.sh — an unambiguous PREFIX of a long option is that option.
#
# THE HOLE.
#
#   git push --del origin main        git push --mir origin
#   git reset --har main              git push --al --force origin
#
# git's subcommands read their options with parse-options, and parse-options
# resolves a long option from any UNAMBIGUOUS PREFIX of its name. The compiled
# laws compared whole strings — `s == "--delete"`, `s == "--mirror"`,
# `s == "--all"`, `t[i].text == "--hard"` — so every shortened spelling fell
# into "starts with a dash, skip" and the flag stayed false. A project writes
# the same law as `(--delete|--mirror)\b` and misses it from the same side.
# Four destructive commands, two layers, zero refusals.
#
# This is the SAME argument the short-cluster pass already won one word over:
# resolving `-fu` into `-f -u` belongs to the parser, because what git will
# really run is a question about reading the line, not about which harms are
# forbidden. A long option shortened to a prefix is the same question with the
# other kind of dash.
#
# WHAT REAL GIT DOES. Measured against git 2.39.5 before any of this was
# written, and section 0 below re-measures it on the machine running the suite
# rather than trusting this comment:
#
#   push --dele / --del / --de   -> `- :refs/heads/main [deleted]`. Three
#                                   spellings of the branch deletion the law
#                                   refuses when it is written `--delete`.
#   push --d                     -> exit 129, "ambiguous option: d (could be
#                                   --delete or --dry-run)". git refuses it.
#   push --mirr / --mir / --mi / --m -> `+ refs/heads/main:refs/heads/main
#                                   (forced update)` plus the remote-tracking
#                                   half. --mirror is push's only m, so the
#                                   prefix goes all the way down to one letter.
#   push --al                    -> pushes every branch; --a is ambiguous with
#                                   --atomic (exit 129).
#   reset --har / --ha / --h     -> `HEAD is now at ...`. --hard is reset's
#                                   only h, and `--h` is not `-h`.
#   push --force                 -> the forced update, though --force-with-lease
#                                   and --force-if-includes both begin with it.
#                                   An EXACT name beats its own extensions, and
#                                   --forc / --for / --fo / --f are all
#                                   ambiguous and refused (exit 129).
#   push --tag --force           -> `* refs/tags/v1:refs/tags/v1 [new tag]` and
#                                   NO branch — byte for byte what `--tags`
#                                   does. So the prefix rule has a direction the
#                                   laws must follow downward too: this line
#                                   writes no branch and must not be refused.
#
# NOTHING UNDER JUDGEMENT IS EXECUTED, AND THE SETUP ASSUMES THE OPPOSITE.
# Sections 2 onward hand real branch deletions, mirror pushes and hard resets to
# the gate. The run is built so that a TOTAL failure of the gate — every case
# allowed, and something then running them — still costs nothing:
#   * PATH is prefixed with a shim dir holding fake `git` and `rm` that execute
#     nothing, append their argv to a log and exit 111. The log is asserted
#     EMPTY at the end: judging is not running.
#   * the repos under judgement are mktemp'd and have NO REMOTE, so a delete or
#     a mirror push has nowhere to go.
#   * HOME is redirected into the same mktemp root, so `rm -rf ~/Documents`
#     names a directory this script created, and a canary file in it is read
#     back at the end.
# Section 0 is the one place a real git runs, it runs BEFORE the shim goes on
# PATH, and it touches only a bare repo this script created two lines earlier —
# through --dry-run for the pushes, so even there nothing is deleted.
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
[ -x "$GATE" ] || { echo "long_option_prefix_test: build first (make)"; exit 1; }

FAIL=0
PASSN=0
pass() { PASSN=$((PASSN+1)); echo "  ok   $1"; }
bad()  { FAIL=1; echo "  FAIL $1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rblongopt.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

REALGIT="$(command -v git)"
export HOME="$ROOT/home"
mkdir -p "$HOME/Documents"
echo "do not lose me" > "$HOME/Documents/canary.txt"

# ---------------------------------------------------------------------------
# 0. the premise, measured on this machine: a prefix IS the option
#    (its own repo, its own bare "remote", both created here, both thrown away;
#     the pushes are --dry-run, so the deletion is read as intent and not run)
# ---------------------------------------------------------------------------
echo "== premise: what git does with a shortened long option =="
G() { "$REALGIT" -C "$ROOT/premise" -c user.email=t@t -c user.name=t "$@"; }
"$REALGIT" init -q --bare "$ROOT/bare.git"
"$REALGIT" init -q "$ROOT/premise"
G commit -q --allow-empty -m one
G branch -M main
G remote add origin "$ROOT/bare.git"
G push -q origin main
G tag v1
G commit -q --allow-empty -m two

# a spelling that git will not resolve answers 129 ("ambiguous"/"unknown"), and
# that is the whole reason this pass refuses to guess: what git refuses to read
# is not a hole.
amb() { # amb <name> <subcommand> <option...>
  local name="$1"; shift
  local out; out="$(G "$@" 2>&1)"; local rc=$?
  if [ "$rc" = "129" ]; then pass "git refuses $name (exit 129), so nothing may expand it"
  else bad "git accepted $name (exit $rc); the ambiguity premise is wrong"
       printf '%s\n' "$out" | head -2 | sed 's/^/         /'; fi
}
dryrun() { G push --dry-run --porcelain "$@" 2>&1; }

for O in --delete --dele --del --de; do
  if dryrun "$O" origin main | grep -q '\[deleted\]'; then
    pass "push $O deletes refs/heads/main on the remote"
  else
    bad "push $O did not read as a deletion; the hole this file closes is not the hole"
    dryrun "$O" origin main | head -3 | sed 's/^/         /'
  fi
done
amb "push --d" push --d origin main

for O in --mirror --mirr --mir --mi --m; do
  if dryrun "$O" origin | grep -q 'refs/heads/main'; then
    pass "push $O mirrors the refspace (it writes refs/heads/main)"
  else
    bad "push $O did not read as a mirror"
    dryrun "$O" origin | head -3 | sed 's/^/         /'
  fi
done

for O in --all --al; do
  if dryrun "$O" --force origin | grep -q 'refs/heads/main'; then
    pass "push $O --force writes every branch, main among them"
  else
    bad "push $O --force did not write main"
  fi
done
amb "push --a" push --a --force origin

# an EXACT name wins over the two longer options that begin with it, and every
# shorter spelling of it is ambiguous — which is why --force needs no expansion
# and must not get one.
if dryrun --force origin main | grep -q 'refs/heads/main'; then
  pass "push --force is exact, though --force-with-lease/--force-if-includes share the prefix"
else
  bad "push --force did not resolve to --force"
fi
for O in --forc --for --fo --f; do amb "push $O" push "$O" origin main; done

# the prefix rule cuts the other way too: --tag is --tags, and --tags writes
# tags and NO branch. A law that refuses it refuses ordinary work.
if dryrun --tag --force origin | grep -q 'refs/tags/v1' && \
   ! dryrun --tag --force origin | grep -q 'refs/heads/'; then
  pass "push --tag --force writes tags and no branch (same as --tags)"
else
  bad "push --tag --force wrote a branch"
  dryrun --tag --force origin | head -3 | sed 's/^/         /'
fi

# reset, in the premise repo, walking its own HEAD back and forth
G branch -f feat HEAD~1
for O in --hard --har --ha --h; do
  if G reset "$O" feat >/dev/null 2>&1 && [ "$(G rev-parse HEAD)" = "$(G rev-parse feat)" ]; then
    pass "reset $O feat moved HEAD, so it is --hard"
  else
    bad "reset $O did not read as --hard"
  fi
  G reset --hard main >/dev/null 2>&1
done
amb "reset --m" reset --m HEAD
for O in --mi --so; do
  if G reset "$O" HEAD >/dev/null 2>&1; then pass "reset $O is a real option and is NOT --hard"
  else bad "reset $O was refused; the harmless twin cannot be measured"; fi
done

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

# the SAME repo checked out on a private branch. --all and --mirror carry no
# refspec, so the law's "no refspec means the current branch" fallback answers
# `feat` — and from main it would have answered `main` and hidden the hole by
# accident. The reported command was measured from a feature branch.
FREPO="$ROOT/onfeat"
"$REALGIT" init -q "$FREPO"
"$REALGIT" -C "$FREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
"$REALGIT" -C "$FREPO" branch -M main
"$REALGIT" -C "$FREPO" checkout -q -b feat
FREPO_HEAD="$("$REALGIT" -C "$FREPO" rev-parse HEAD)"

GREPO="$ROOT/guarded"
mkdir -p "$GREPO/.rabadon"
"$REALGIT" init -q "$GREPO"
"$REALGIT" -C "$GREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
"$REALGIT" -C "$GREPO" branch -M main
# the four-rule guard.json the report ran against: a project that wrote its own
# laws for these harms, spelling every option out in full.
cat > "$GREPO/.rabadon/guard.json" <<'JSON'
{
  "project": "guarded",
  "bash": [
    { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b", "why": "force-pushing a shared branch destroys history" },
    { "id": "no-branch-delete", "deny": "git\\s+push[^|;&]*--delete\\b", "why": "deleting a shared branch removes it for everyone" },
    { "id": "no-mirror-push", "deny": "git\\s+push[^|;&]*--mirror\\b", "why": "a mirror push rewrites and removes refs on the remote" },
    { "id": "no-hard-reset", "deny": "git\\s+reset[^|;&]*--hard\\b", "why": "a hard reset discards local work" }
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
echo "== unit: the option a prefix names =="
if [ "$UNIT_OK" = "0" ]; then
  echo "  (probe did not compile)"; sed -n '1,12p' "$ROOT/cc.log" | sed 's/^/         /'
fi
u_argv "--del is --delete"          "git push --del origin main"  '|push|--delete|origin|main'
u_argv "--dele is --delete"         "git push --dele origin main" '|push|--delete|origin|main'
u_argv "--de is --delete"           "git push --de origin main"   '|push|--delete|origin|main'
u_argv "--mir is --mirror"          "git push --mir origin"       '|push|--mirror|origin'
u_argv "--m is --mirror"            "git push --m origin"         '|push|--mirror|origin'
u_argv "--al is --all"              "git push --al --force origin" '|push|--all|--force|origin'
u_argv "--har is --hard"            "git reset --har main"        '|reset|--hard|main'
u_argv "--h is --hard"              "git reset --h main"          '|reset|--hard|main'
u_argv "--tag is --tags"            "git push --tag --force origin" '|push|--tags|--force|origin'
u_argv "--force-w is a lease"       "git push --force-w origin main" '|push|--force-with-lease|origin|main'
u_argv "globals then a prefix"      "git -C /tmp push --del origin main" '|push|--delete|origin|main'
u_argv "an alias body carries one"  "git -c alias.x='push --del' x origin main" '|push|--delete|origin|main'
u_argv "a prefix beside a cluster"  "git push -qf --mir origin"   '|push|-q|-f|--mirror|origin'

echo
echo "== unit: what the pass refuses to guess (git refuses it too) =="
u_notargv "--d is ambiguous"        "git push --d origin main"    '|--delete|'
u_notargv "--d is not --dry-run either" "git push --d origin main" '|--dry-run|'
u_notargv "--a is ambiguous"        "git push --a --force origin" '|--all|'
u_notargv "--f is ambiguous"        "git push --f origin main"    '|--force|'
u_notargv "--fo is ambiguous"       "git push --fo origin main"   '|--force|'
u_notargv "--m on reset is ambiguous" "git reset --m HEAD"        '|--mixed|'
u_notargv "a harmless prefix stays harmless" "git push --dr origin main" '|--delete|'
u_notargv "reset --mi is --mixed, not --hard" "git reset --mi HEAD" '|--hard|'
u_notargv "after -- it is an operand"  "git push origin -- --del" '|--delete|'
u_notargv "an unrelated subcommand is untouched" "git log --on" '|--oneline|'
u_argv    "--force stays --force"   "git push --force origin main" '|push|--force|origin|main'
u_argv    "--dr is --dry-run"       "git push --dr origin main"   '|push|--dry-run|origin|main'
u_argv    "reset --mi is --mixed"   "git reset --mi HEAD"         '|reset|--mixed|HEAD'

# ---------------------------------------------------------------------------
# 2. e2e: the real binary
# ---------------------------------------------------------------------------
judge() { # judge <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"longopt","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
blocks() { local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then pass "$1"; else bad "$1: allowed (exit $got), and the same command spelled out is refused"; fi; }
allows() { local got; got="$(judge "$2" "$3")"
  if [ "$got" = "2" ]; then bad "$1: refused, and refusing it cuts real work"; else pass "$1"; fi; }
# the invariant underneath both of the above, and the only one that survives a
# project writing its own rules: a shortened option and the full name it stands
# for get the SAME verdict, whatever that verdict is. A guard.json that forbids
# every `git push --delete` forbids `--del` too, and that is not a false refusal
# — it is the project's own rule, finally reaching the spelling that dodged it.
same() { local a b; a="$(judge "$2" "$3")"; b="$(judge "$2" "$4")"
  if [ "$a" = "$b" ]; then pass "$1 (both exit $a)"
  else bad "$1: shortened exit $a, spelled out exit $b — the two spellings disagree"; fi; }

echo
echo "== e2e: the four reported commands, against the compiled-in laws (no guard.json) =="
blocks "git push --del origin main"    "$REPO"  "git push --del origin main"
blocks "git push --mir origin"         "$FREPO" "git push --mir origin"
blocks "git reset --har main"          "$REPO"  "git reset --har main"
blocks "git push --al --force origin"  "$FREPO" "git push --al --force origin"

echo
echo "== e2e: the rest of each family =="
blocks "--dele"                        "$REPO"  "git push --dele origin main"
blocks "--de"                          "$REPO"  "git push --de origin main"
blocks "--de on master"                "$REPO"  "git push --de origin master"
blocks "--mirr"                        "$FREPO" "git push --mirr origin"
blocks "--mi"                          "$FREPO" "git push --mi origin"
blocks "--m, one letter"               "$FREPO" "git push --m origin"
blocks "--al -f"                       "$FREPO" "git push --al -f origin"
blocks "--al and a short cluster"      "$FREPO" "git push --al -fq origin"
blocks "reset --ha"                    "$REPO"  "git reset --ha main"
blocks "reset --h, one letter"         "$REPO"  "git reset --h main"
blocks "reset --har onto origin/main"  "$REPO"  "git reset --har origin/main"

echo
echo "== e2e: the same shapes wrapped the way an agent writes them =="
blocks "a global before it"            "$REPO"  "git -C $REPO push --del origin main"
blocks "inside sh -lc"                 "$REPO"  "sh -lc 'git push --del origin main'"
blocks "inside eval"                   "$REPO"  "eval 'git reset --har main'"
blocks "inside an alias body"          "$REPO"  "git -c alias.x='push --del' x origin main"
blocks "inside a loop body"            "$REPO"  "for b in main; do git push --del origin \$b; done"
blocks "inside a function body"        "$REPO"  "gx() { git push --del origin main; }; gx"
blocks "after a && chain"              "$REPO"  "npm test && git push --del origin main"

echo
echo "== e2e: the user rule layer sees the full name too =="
blocks "guard.json + --del"            "$GREPO" "git push --del origin main"
blocks "guard.json + --mir"            "$GREPO" "git push --mir origin"
blocks "guard.json + reset --har"      "$GREPO" "git reset --har main"
blocks "guard.json + sh -lc"           "$GREPO" "sh -lc 'git push --del origin main'"
same "guard.json judges --del as --delete, private branch" "$GREPO" \
     "git push --del origin feature/mine" "git push --delete origin feature/mine"
same "guard.json judges --mir as --mirror"                 "$GREPO" \
     "git push --mir origin" "git push --mirror origin"
same "no guard.json: --de as --delete, private branch"     "$REPO" \
     "git push --de origin feature/mine" "git push --delete origin feature/mine"
same "no guard.json: --ha as --hard, local ref"            "$REPO" \
     "git reset --ha HEAD~1" "git reset --hard HEAD~1"
same "no guard.json: --dr as --dry-run"                    "$REPO" \
     "git push --dr origin main" "git push --dry-run origin main"

echo
echo "== e2e: the legitimate twin of every case above still runs =="
allows "deleting your OWN branch"      "$REPO"  "git push --del origin feature/mine"
allows "--de on your own branch"       "$REPO"  "git push --de origin feature/mine"
allows "--al with no force"            "$FREPO" "git push --al origin"
allows "--dr, a dry run"               "$REPO"  "git push --dr origin main"
allows "--dry-run spelled out"         "$REPO"  "git push --dry-run origin main"
allows "--po, machine-readable output" "$REPO"  "git push --po origin main"
allows "--at, an atomic push"          "$REPO"  "git push --at origin main"
allows "--force-w, a lease push"       "$REPO"  "git push --force-w origin main"
allows "--force-with-lease spelled out" "$REPO" "git push --force-with-lease origin main"
allows "--tag --force writes no branch" "$REPO" "git push --tag --force origin"
allows "--tags --force, spelled out"   "$REPO"  "git push --tags --force origin"
allows "reset --mi, a mixed reset"     "$REPO"  "git reset --mi main"
allows "reset --so, a soft reset"      "$REPO"  "git reset --so main"
allows "reset --ha onto a local ref"   "$REPO"  "git reset --ha HEAD~1"
allows "an ambiguous prefix git refuses" "$REPO" "git push --f origin main"
allows "reset's ambiguous --m"         "$REPO"  "git reset --m main"
allows "a prefix after --"             "$REPO"  "git push origin -- --del"
allows "the prefix inside a commit msg" "$REPO" "git commit -m \"git push --del origin main is the bypass\""
allows "the prefix inside an echo"     "$REPO"  "echo 'git push --del origin main'"
allows "guard.json + --dr"             "$GREPO" "git push --dr origin main"
allows "guard.json + a plain push"     "$GREPO" "git push origin main"

echo
echo "== e2e: the plain spellings did not stop working =="
blocks "plain force-push"              "$REPO"  "git push --force origin main"
blocks "plain branch delete"           "$REPO"  "git push --delete origin main"
blocks "plain mirror push"             "$FREPO" "git push --mirror origin"
blocks "plain hard reset"              "$REPO"  "git reset --hard origin/main"
blocks "the short cluster still splits" "$REPO" "git push -fu origin main"
blocks "rm -rf outside the project"    "$REPO"  "rm -rf ~/Documents"
allows "plain push"                    "$REPO"  "git push origin main"
allows "force-with-lease"              "$REPO"  "git push --force-with-lease origin main"
allows "rm -rf inside the project"     "$REPO"  "rm -rf node_modules"

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
[ "$("$REALGIT" -C "$FREPO" rev-parse HEAD 2>/dev/null)" = "$FREPO_HEAD" ] \
  && pass "the feature-branch repo still points at the same commit" \
  || bad "the feature-branch repo moved"
for R in "$REPO" "$FREPO" "$GREPO"; do
  [ -z "$("$REALGIT" -C "$R" remote 2>/dev/null)" ] \
    && pass "$(basename "$R") never had a remote to delete a branch on" \
    || bad "$(basename "$R") grew a remote"
done

echo
if [ "$FAIL" = "0" ]; then echo "PASS ($PASSN checks)"; else echo "FAIL ($PASSN checks passed)"; fi
exit $FAIL
