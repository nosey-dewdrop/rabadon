#!/bin/bash
# fd_dup_test.sh — `2>&1` is not a file called 1.
#
# The delete law learned to read redirections on 2 August, because `> file`
# destroys a file with no command on the line and no law had ever seen one. The
# reader it got treats every redirection whose operator contains `>` as a write
# to the path in `target`. `2>&1` has a `>` in it and a target of `1`, so it was
# judged as a truncating write to `<cwd>/1`, and when the segment's cwd sat
# outside the session's own tree the law refused the command.
#
# It refused four of five agent sessions on the night this was found, on their
# first or second command each, every time on the shape
#
#   cd <another repo> && <anything> 2>&1
#
# which is on nearly every line an agent writes. `2>&1` duplicates a file
# descriptor. It never opens a file, never creates one, never truncates one, and
# there is no file named `1` anywhere in any of this.
#
# A false refusal is the expensive kind of wrong for a tool like this. A missed
# catch costs one incident; a refusal the operator knows is wrong costs the
# operator's belief in every other refusal, and after that the tool gets turned
# off. So this file holds both directions: fd duplication passes, and the real
# truncating redirect it was mistaken for still gets refused.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
[ -x "$GATE" ] || { echo "  build first: make native/rabadon-gate"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# NOT mktemp. On macOS mktemp lands in /var/folders, and /tmp, /var/tmp and
# /var/folders are all machine temp roots that the coverage law deliberately
# exempts (pathres.h machine_temp_roots). A fixture built there is not judged by
# the law under test, so the first version of this file passed all seven cases
# in section 1 before the defect was fixed, and failed all four in section 2
# after -- it was measuring the carve-out, not the rule. The premise of a fixture
# is the first thing to measure.
T="$(cd "$HERE/.." && pwd)/.fdtest-$$"
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT

# two project trees. the hook's own root is `home`, the command runs in `other`,
# which is the arrangement that made this fire: a segment whose cwd is outside
# the tree the session started in.
HOMEREPO="$T/homerepo"; OTHER="$T/other"
mkdir -p "$HOMEREPO/.git" "$OTHER/.git" "$T/rd/spool"
export RABADON_DIR="$T/rd"
: > "$RABADON_DIR/enabled"          # ENFORCE, so a refusal is exit 2

# run one command through the real gate, with the hook standing in homerepo
probe() {
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$HOMEREPO" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")" \
    | "$GATE" >"$T/out" 2>"$T/err"
  echo $?
}

echo "fd duplication — 2>&1 is a descriptor, not a file"
echo

# ---------------------------------------------------------------------------
# 1. the shape that was refused, and every spelling of it
# ---------------------------------------------------------------------------
echo "1. these must pass"
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  rc=$(probe "$cmd")
  if [ "$rc" -eq 0 ]; then ok "$cmd"
  else
    bad "$cmd  (exit $rc)"
    sed -n '1,3p' "$T/err" | sed 's/^/        /'
  fi
done <<EOF
cd $OTHER && git status 2>&1
cd $OTHER && make test 2>&1 | tail -5
cd $OTHER && ls >&2
cd $OTHER && ls &> /dev/null
cd $OTHER && ls 1>&2
cd $OTHER && ls 2>&-
git -C $OTHER status 2>&1
EOF

echo
# ---------------------------------------------------------------------------
# 2. and the law it was mistaken for must not have moved
# ---------------------------------------------------------------------------
# If the fix widened into "ignore redirections whose target is short", the thing
# the law was written for walks free. These are the same command shapes with a
# real file on the other side of the arrow.
echo "2. these must still be refused"
: > "$OTHER/ROADMAP.md"
: > "$OTHER/1"                      # a file really named 1, aimed at on purpose
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  rc=$(probe "$cmd")
  if [ "$rc" -ne 0 ]; then ok "refused: $cmd"
  else bad "ALLOWED: $cmd"; fi
done <<EOF
cd $OTHER && > ROADMAP.md
cd $OTHER && echo x > ROADMAP.md
cd $OTHER && echo x > ./1
cd $OTHER && echo x 2> ROADMAP.md
EOF

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
