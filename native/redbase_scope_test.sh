#!/usr/bin/env bash
# redbase_scope_test.sh — a red is about a TREE, and it stops where that tree does.
#
# redbase_test.sh proves the stop works. This one asks the question that decides
# whether the stop is usable: WHOSE work does it stop?
#
# Measured 2026-08-29, on the shipped binary, before a line of this file existed
# (F1b CHALLENGE-2, reproduced in F3): with project P red,
#
#     hook cwd = P,  `git commit -m wip`                     -> exit 2   correct
#     hook cwd = P,  `cd <neighbour> && git commit -m wip`   -> exit 2   FALSE REJECT
#     hook cwd = <neighbour>, `git commit -m wip`            -> exit 0   correct
#
# The neighbour is its own git worktree with its own verdict and shares nothing
# with P. The same action was refused or allowed depending on which directory
# the session happened to have started in — not on what it touched. CLAUDE.md
# counts a false reject at the same severity as a missed catch, and this is the
# shape that gets a guard uninstalled, because the user knows the work was
# unrelated and the tool says otherwise.
#
# The twins are the whole risk here, because the cheap version of the fix is a
# bypass: if `cd /tmp &&` in front of a command switched red-base off, an agent
# would learn that in one session. So every arm below has a partner that must
# stay refused — one segment inside the red tree refuses the whole line, `git -C`
# is followed to the repository it names, and a line the parser cannot read gets
# no waiver at all.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
NET="$HERE/rabadon-net"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
[ -x "$NET" ]  || { echo "build first: make native/rabadon-net"; exit 1; }
export RABADON_JUDGE=0
PASS=0; FAIL=0; SKIP=0; SKIPA=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
# An arm that cannot run HERE is announced with its NAME and its NUMBER, and
# the count reaches the summary line. This one is the whole file: without node
# the red fixture cannot exist, so all 9 assertions go. It used to be
#   ... || { echo "  skip - node is not installed"; exit 0; }
# printed BEFORE the counters existed, so the file left no summary at all and
# exited 0 — a suite that disappears completely and reads as success. §8.2.
skipped() { SKIP=$((SKIP+1)); SKIPA=$((SKIPA+$2)); echo "  SKIP - $1: $2 assertion(s) did NOT run — $3"; }
if ! command -v node >/dev/null 2>&1; then
  skipped "the whole suite" 9 "node is not installed, so the red fixture cannot be produced and NOTHING below was judged on this machine"
  echo ""
  echo "red base scope: $PASS ok, $FAIL fail, $SKIP skipped ($SKIPA assertion(s) not run)"
  echo "  red base scope: NOT JUDGED — every case needs node"
  exit 0
fi

T="$(mktemp -d "${TMPDIR:-/tmp}/rabadon-rbscope.XXXXXX")"
RD="$(mktemp -d "${TMPDIR:-/tmp}/rabadon-rbscope-rd.XXXXXX")"; : > "$RD/enabled"
trap 'rm -rf "$T" "$RD"' EXIT

# P: a project whose own suite really fails. N: a neighbour with its own root.
P="$T/proj"; mkdir -p "$P/src" "$P/.git"
printf '{"name":"rb","scripts":{"test":"node test.js"}}' > "$P/package.json"
printf 'const a=require("./src/a.js");if(a()!==1){console.error("FAIL: a() must return 1");process.exit(1)}console.log("ok")\n' > "$P/test.js"
printf 'module.exports = () => 2;\n' > "$P/src/a.js"
N="$T/neighbour"; mkdir -p "$N/.git/x"; printf 'x = 1\n' > "$N/app.py"

"$NET" "$P" --cap-ms 60000 >/dev/null 2>&1
grep -q '"verdict":"red"' "$P/.rabadon/net.json" 2>/dev/null \
  && ok "premise: the project's own check really is red" \
  || bad "premise broken, nothing below proves anything: $(cat "$P/.rabadon/net.json" 2>/dev/null)"
grep -q "\"root\":\"$(cd "$P" && pwd -P)\"" "$P/.rabadon/net.json" 2>/dev/null \
  && ok "premise: the verdict names the tree it is about" \
  || bad "premise broken: the verdict carries no usable root"

code() { # code <hook-cwd> <command-json-string>
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"rbs","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$2" | RABADON_DIR="$RD" "$GATE" >/dev/null 2>&1; echo $?
}
q() { printf '"%s"' "$1"; }

echo "red base scope: a red stops where its tree stops"

# ---- the refusal that must not move ----
[ "$(code "$P" "$(q 'git commit -m wip')")" = "2" ] \
  && ok "a command that runs IN the red tree is still refused" \
  || bad "the red stopped refusing work on the broken base — the rule is gone"

# ---- the false reject ----
[ "$(code "$P" "$(q "cd $N && git commit -m wip")")" = "0" ] \
  && ok "a command that runs entirely in a NEIGHBOUR tree is not refused" \
  || bad "a neighbour tree inherited this project's red: work the user knows is unrelated was refused"

# ---- twin 1: one segment inside is enough to refuse the line ----
[ "$(code "$P" "$(q "cd $N && cd $P && git commit -m wip")")" = "2" ] \
  && ok "one segment back inside the red tree refuses the whole line (cd is not an escape)" \
  || bad "'cd away && cd back' walked past red-base: the waiver is a bypass"

# ---- twin 2: git -C is followed to the repository it names ----
[ "$(code "$P" "$(q "cd $N && git -C $P push")")" = "2" ] \
  && ok "git -C into the red tree is refused wherever the shell stands" \
  || bad "git -C walked past red-base: the waiver reads the shell and not the action"

# ---- twin 3: the ordinary line, with no cd at all, is untouched ----
[ "$(code "$P" "$(q 'npm install left-pad')")" = "2" ] \
  && ok "an ordinary command with no cd is refused exactly as before" \
  || bad "the waiver leaked into lines that never left the red tree"

# ---- twin 4: the fix path stays open, which is the only way out ----
[ "$(code "$P" "$(q 'npm test')")" = "0" ] \
  && ok "re-running the check is still allowed — the escape hatch did not close" \
  || bad "the check itself was refused: the session is wedged"

# ---- twin 5: standing in the neighbour was always right and still is ----
[ "$(code "$N" "$(q 'git commit -m wip')")" = "0" ] \
  && ok "a session standing in the neighbour is not refused (unchanged)" \
  || bad "the neighbour is refused on its own ground"

echo ""
echo "red base scope: $PASS ok, $FAIL fail, $SKIP skipped ($SKIPA assertion(s) not run)"
[ "$FAIL" -eq 0 ]
