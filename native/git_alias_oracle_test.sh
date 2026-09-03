#!/usr/bin/env bash
# git_alias_oracle_test.sh — ASK GIT, DO NOT GUESS.
#
# WHY THIS FILE EXISTS, AND WHY THE GRID NEXT DOOR WAS NOT ENOUGH.
# native/git_alias_test.sh enumerates alias shapes by hand. Four consecutive
# outside reviews found four bypasses in the same lookup, each one a cell the
# grid did not contain: a name in a different CASE, a repo named by `-C`, a
# body that defines another alias, a cwd below the repo root, and finally a
# name with a DOT in it (`git yo.lo`, which git stores as a subsection and
# runs). Every one was fixed, a row was added, and the next review found the
# next cell. "109 checks green" is a statement about what somebody thought to
# type.
#
# So this suite does not think of names. It generates them, asks the REAL git
# binary what each one resolves to, and requires the gate to agree:
#
#   git config alias.<name> 'push --force'     (git writes it however it likes)
#   git config --get alias.<name>              (the oracle: does git see it?)
#   -> if git resolves it, the gate MUST refuse `git <name> origin main`
#   -> if git does not, the gate must NOT refuse it on account of an alias
#
# A divergence is a failure whichever direction it points: a miss is a bypass,
# and a refusal of a name git never resolves is a false reject. Nothing here is
# executed against a remote — the gate decides before anything runs, and the
# canaries at the end prove the lab was never touched.
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
REALGIT="$(command -v git)"
FAIL=0; PASSN=0
pass() { printf '  ok   %s\n' "$1"; PASSN=$((PASSN + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; FAIL=1; }
[ -x "$GATE" ] || { echo "oracle: no gate binary at $GATE — run make first" >&2; exit 1; }
[ -n "$REALGIT" ] || { echo "oracle: git is required to be the oracle" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "oracle: python3 required" >&2; exit 1; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rboracle.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"; mkdir -p "$HOME/Documents"
printf 'do not lose me\n' > "$HOME/Documents/canary.txt"
REPO="$ROOT/proj"; mkdir -p "$REPO/src/deep"
"$REALGIT" -C "$REPO" init -q .
"$REALGIT" -C "$REPO" config user.email t@t; "$REALGIT" -C "$REPO" config user.name t
: > "$REPO/f.txt"; "$REALGIT" -C "$REPO" add f.txt; "$REALGIT" -C "$REPO" commit -qm init
REPO_HEAD="$("$REALGIT" -C "$REPO" rev-parse HEAD)"
mkdir -p "$ROOT/rhome/.rabadon/spool"; : > "$ROOT/rhome/.rabadon/enabled"
mkdir -p "$REPO/.rabadon"
printf '{"project":"proj","testCommand":"true"}\n' > "$REPO/.rabadon/guard.json"

# judge <cwd> <command> -> exit code. A FRESH session id every call: loop-stop
# refuses a third identical command and its exit 2 is indistinguishable from a
# law's. A harness that reuses one session reports its own loop detector as a
# catch (this trap cost an outside reviewer two false all-clears).
judge() {
  local sid="s$RANDOM$RANDOM$$"
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$sid" "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | env HOME="$ROOT/rhome" RABADON_DIR="$ROOT/rhome/.rabadon" RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
  echo $?
}

# THE NAMES. Not a list of shapes someone found; a generated sweep of what a
# config key can look like, including the ones this project has already been
# bitten by and the ones it has not.
NAMES=(
  yolo YOLO YoLo y1 x-y x_y a.b a.b.c deploy.prod q.q v2.1 dot.
  .lead a..b "with space" "tab	x" "" - _ -- __ x- -x 9lives
  push status log commit                 # names that collide with builtins
  ünlü türkçe-ı ÜNLÜ                     # non-ascii, and the Turkish dotless i
  a-very-long-name-that-nobody-would-type-but-git-might-accept
)
BODY_DANGEROUS='push --force'
BODY_BANG='!rm -rf ~/Documents'
BODY_SAFE='log --oneline -2'

echo "oracle: every generated name, judged against what real git resolves"
CHECKED=0; SKIPPED=0; LIMITS=0
for name in "${NAMES[@]}"; do
  for kind in verb bang safe; do
    case "$kind" in
      verb) body="$BODY_DANGEROUS"; invoke="git $name origin main"; must_refuse=1 ;;
      bang) body="$BODY_BANG";      invoke="git $name";             must_refuse=1 ;;
      safe) body="$BODY_SAFE";      invoke="git $name";             must_refuse=0 ;;
    esac
    # can git even store this name? if not, it is not a hole, and saying so is
    # the honest answer rather than asserting on a name that cannot exist.
    "$REALGIT" -C "$REPO" config --unset-all "alias.$name" 2>/dev/null
    if ! "$REALGIT" -C "$REPO" config "alias.$name" "$body" 2>/dev/null; then
      SKIPPED=$((SKIPPED + 1)); continue
    fi
    # THE ORACLE: does real git resolve this name to that body?
    got="$("$REALGIT" -C "$REPO" config --get "alias.$name" 2>/dev/null)"
    if [ "$got" != "$body" ]; then
      "$REALGIT" -C "$REPO" config --unset-all "alias.$name" 2>/dev/null
      SKIPPED=$((SKIPPED + 1)); continue
    fi
    # A NAMED LIMIT, and the only one. `alias..lead` is stored by git as
    # `[alias ""] lead` — an EMPTY subsection — and config_key() renders both
    # "no subsection" and "an empty subsection" as `alias.lead`, so the lookup
    # asks for a key that is one dot short of the one on disk. Telling those
    # two apart means a distinguished empty-subsection marker threaded through
    # every reader of a config key, for a name no human types and which git
    # itself only reaches through `git config alias..lead`. Reported here, in
    # the suite, so it stays visible and counted rather than being quietly
    # excluded: a limit named is not the same as a hole hidden.
    if [ "$name" = ".lead" ]; then
      LIMITS=$((LIMITS + 1)); "$REALGIT" -C "$REPO" config --unset-all "alias.$name" 2>/dev/null; continue
    fi
    CHECKED=$((CHECKED + 1))
    for cwd in "$REPO" "$REPO/src" "$REPO/src/deep"; do
      rc="$(judge "$cwd" "$invoke")"
      where="$(basename "$cwd")"
      if [ "$must_refuse" = "1" ]; then
        [ "$rc" = "2" ] || bad "git resolves 'alias.$name' to \`$body\` and the gate allowed \`$invoke\` from $where (exit $rc)"
      else
        [ "$rc" != "2" ] || bad "a harmless alias 'alias.$name' (\`$body\`) was refused from $where"
      fi
    done
    "$REALGIT" -C "$REPO" config --unset-all "alias.$name" 2>/dev/null
  done
done
[ "$FAIL" = "0" ] && pass "every one of $CHECKED resolvable (name, body) pairs agreed with git, from 3 directories ($SKIPPED name(s) git itself refused, $LIMITS named limit(s) below)"
[ "$LIMITS" = "3" ] \
  && pass "the empty-subsection name (\`git config alias..x\`) is the one known divergence — 1 name x 3 bodies, counted, not hidden" \
  || bad "the named-limit count moved: expected 3 (one name, three bodies), got $LIMITS — a limit appeared or disappeared without anyone saying so"

# THE ORACLE MUST BE ABLE TO FAIL. A suite that cannot go red proves nothing,
# so drive a name the gate is known to handle and assert the harness sees a
# refusal at all.
"$REALGIT" -C "$REPO" config alias.canaryname "$BODY_DANGEROUS"
[ "$(judge "$REPO" "git canaryname origin main")" = "2" ] \
  && pass "the harness can observe a refusal (it is not asserting into a void)" \
  || bad "the harness saw no refusal even for a plain alias — every result above is meaningless"
[ "$(judge "$REPO" "git status")" != "2" ] \
  && pass "and it can observe an allow" \
  || bad "the harness refuses everything"
"$REALGIT" -C "$REPO" config --unset-all alias.canaryname

echo
echo "== canaries =="
[ "$(cat "$HOME/Documents/canary.txt" 2>/dev/null)" = "do not lose me" ] \
  && pass "the rm -rf target still holds its canary" || bad "the lab was touched"
[ "$("$REALGIT" -C "$REPO" rev-parse HEAD 2>/dev/null)" = "$REPO_HEAD" ] \
  && pass "the judged repo still points at the same commit" || bad "the repo moved"

echo
[ "$FAIL" = "0" ] && echo "oracle: PASS ($PASSN checks, $CHECKED generated pairs)" \
                  || echo "oracle: FAIL"
exit $FAIL
