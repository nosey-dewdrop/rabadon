#!/bin/bash
# shell_cwd_test.sh — where the shell is standing when the second half runs.
#
# Every containment law in this engine asks one question: is the thing being
# destroyed inside the project tree, where git can undo it, or outside, where
# nothing can. That question is answered against the segment's working
# directory, and the walk that computes it followed exactly one verb:
#
#   if (name_is(base, "cd") && ci + 1 < words.size()) { arg = words[ci + 1]; ... }
#
# Two holes in one line. It reads the word AFTER cd as the directory, so
# `cd -P /elsewhere && rm -rf engine` moves into `-P`, which resolves nowhere,
# leaves the walk standing in the project, and judges a delete next door as a
# delete at home. And `pushd` is not a verb it knows at all, though it is the
# same move with a stack behind it — six probes in the red-team corpus are these
# two facts:
#
#   cd -P <tree> && rm -rf engine
#   cd -- <tree> && rm -rf engine
#   pushd <tree> && rm -rf engine
#   pushd <tree> >/dev/null && rm -rf engine
#   pushd <tree>; rm -rf engine
#   pushd <tree> && rm -rf engine && popd
#
# THE FAILURE DIRECTION IS WHAT MAKES THIS URGENT. A walk that loses track of
# the shell does not refuse too much, it refuses too little: it believes the
# delete is happening inside the project, and inside the project deletes are
# allowed. Every one of these is a silent pass.
#
# `popd` is here as the twin, and it is the one that keeps the fix honest. After
# a pushd and a popd the shell is back where it started, so the delete on the
# END of that line is an ordinary delete in the project and must go through. A
# fix that only pushes and never pops turns this file green while blocking real
# work, which is the same failure wearing the other face.
#
# NOTHING RUNS. The gate is a judge; HOME is redirected into a mktemp lab, a
# canary sits in it, fake rm/git shadow the real ones, and the tree next door is
# a path that exists nowhere — mktemp cannot be used for it, because on macOS it
# lands under /var/folders and the containment law waives the shared temp root
# on purpose. delete_verbs_test.sh measures that waiver.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rabadon-shellcwd.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
export RABADON_DIR="$ROOT/home/.rabadon"
export RABADON_NOTIFY=0
mkdir -p "$HOME" "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"
echo alive > "$HOME/CANARY"

PROJ="$ROOT/work/proj"
OTHER="/Users/nobody/work/proj-other"
mkdir -p "$PROJ/.rabadon" "$PROJ/engine" "$PROJ/sub/deep"
echo '{ "project": "p", "bash": [], "protectedPaths": [], "disabled": [] }' > "$PROJ/.rabadon/guard.json"
git init -q "$PROJ" 2>/dev/null
echo keep > "$PROJ/keep.txt"

FAKE="$ROOT/fakebin"; mkdir -p "$FAKE"; RAN="$ROOT/ran.log"; : > "$RAN"
for n in rm git find rsync shred truncate dd pushd popd cd; do
  printf '#!/bin/sh\necho "%s $*" >> %s\nexit 0\n' "$n" "$RAN" > "$FAKE/$n"
  chmod +x "$FAKE/$n"
done

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
jstr() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }
SESSION=c0
judge() {
  local err
  err=$(printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$SESSION" "$PROJ" "$(jstr "$1")" | PATH="$FAKE:$PATH" "$GATE" 2>&1 >/dev/null)
  if [ $? -eq 2 ]; then echo "BLOCK:$(printf '%s' "$err" | sed -n 's/^Rule: \([^ ]*\) .*/\1/p' | head -1)"
  else echo ALLOW; fi
}
must_block() { local v; v=$(judge "$1"); case "$v" in BLOCK:*) ok "refused by ${v#BLOCK:}: $1" ;;
                                                     *) bad "ALLOWED, must refuse: $1" ;; esac; }
must_allow() { local v; v=$(judge "$1"); [ "$v" = ALLOW ] && ok "allowed: $1" \
                                          || bad "REFUSED by ${v#BLOCK:}, must allow: $1"; }

echo "shell cwd — the walk has to know where the shell went"
echo

# ---------------------------------------------------------------------------
# 0. the premise: the plain form is already refused, so anything below that
#    passes is the WALK losing the shell, not the delete law being absent.
# ---------------------------------------------------------------------------
echo "0. the premise"
SESSION=c0
must_block "cd $OTHER && rm -rf engine"
echo

# ---------------------------------------------------------------------------
# 1. the shell moved and the delete is next door
# ---------------------------------------------------------------------------
echo "1. the shell moved out of the project"
SESSION=c1
must_block "cd -P $OTHER && rm -rf engine"
must_block "cd -- $OTHER && rm -rf engine"
must_block "cd -L -- $OTHER && rm -rf engine"
must_block "pushd $OTHER && rm -rf engine"
must_block "pushd $OTHER >/dev/null && rm -rf engine"
must_block "pushd $OTHER; rm -rf engine"
must_block "pushd -n $OTHER && rm -rf engine"
must_block "cd $OTHER && shred -u ROADMAP.md"
must_block "pushd $OTHER && truncate -s 0 ROADMAP.md"
must_block "cd $OTHER && > ROADMAP.md"
echo

# ---------------------------------------------------------------------------
# 2. the twins. the shell is still in the project, and the work must run.
#    popd is the one that matters: after a push and a pop the delete at the end
#    of the line is an ordinary delete at home.
# ---------------------------------------------------------------------------
echo "2. the shell is still in the project"
SESSION=c2
must_allow "pushd $OTHER && ls && popd && rm -rf engine"
must_allow "cd sub && rm -rf deep"
must_allow "cd sub/deep && rm -rf build"
must_allow "cd $PROJ && rm -rf engine"
must_allow "cd -P $PROJ && rm -rf engine"
must_allow "pushd sub && rm -rf deep"
must_allow "pushd $PROJ && rm -rf engine && popd"
must_allow "cd .. && cd proj && rm -rf engine"
must_allow "rm -rf engine"
must_allow "echo 'cd elsewhere && rm -rf x is the escape' >> NOTES.md"
echo

# ---------------------------------------------------------------------------
# 3. judging is not running
# ---------------------------------------------------------------------------
echo "3. judging is not running"
[ -s "$RAN" ] && { bad "something REACHED a destructive binary:"; sed 's/^/        /' "$RAN" | head -5; } \
              || ok "the fake binary log is empty: nothing was executed"
[ -f "$PROJ/keep.txt" ] && ok "project canary intact" || bad "project canary damaged"
[ -f "$HOME/CANARY" ] && ok "home canary intact" || bad "home canary damaged"
[ ! -e "$OTHER" ] && ok "the tree next door was judged, never created" \
                  || bad "$OTHER exists — a judge wrote to the tree it was asked about"

echo
echo "  pass $pass   fail $fail"
[ "$fail" -eq 0 ] && echo "  shell cwd: GREEN" || echo "  shell cwd: RED"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
