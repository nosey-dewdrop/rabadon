#!/bin/bash
# exit_path_test.sh — the two halves of the user's way OUT, held from outside.
#
# Half one: `rabadon init` ends by telling a stranger what they now have. It
# named the two commands that CHANGE the mode (`rabadon on|off`) and never said
# which mode they are standing in. The default is watch, and watch refuses
# nothing — so somebody who follows the README installs a guard that stops
# no action of any kind, and the screen that says "done" does not mention it.
# That is the same false green this product exists to refuse, printed by the
# product's own installer. So the closing block has to answer the three
# questions every rabadon message answers (KOSU-RABADON-5 4.8): WHAT state this
# is, WHY it is that state, and the ONE command that comes next.
#
# Half two: `rabadon init` writes .cursor/hooks.json with five events, and
# `rabadon remove` — the command the screen names as "take it all back out" —
# stripped only .claude/settings.json. Measured before this suite: after a full
# init + remove round the Cursor file was still there with all five rabadon
# entries in it. A Cursor user had no exit at all, and the only instruction they
# were given claimed otherwise.
#
# Nothing here touches the real $HOME, the real ~/.claude, the real ~/.cursor or
# the real ~/.rabadon: every case runs in its own mktemp tree with HOME and
# RABADON_DIR pointed inside it. A test for an UNINSTALL that ran against the
# operator's own machine would be the same class of harm it is checking for.
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

command -v node >/dev/null 2>&1 || { echo "exit_path_test: needs node"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "exit_path_test: needs python3"; exit 1; }
[ -x "$ROOT/native/rabadon-gate" ] || {
  echo "exit_path_test: native/rabadon-gate is not built — \`rabadon init\` exits 3 without it"
  echo "                run: (cd $ROOT && make)"
  exit 1; }

TMP=$(mktemp -d /tmp/rabadon-exitpath-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

echo "exit path: what init SAYS, and what remove actually takes back out"

# a project nobody has ever run anything in, with a HOME of its own.
newproj() { d="$TMP/$1"; mkdir -p "$d/home" "$d/proj"; printf '%s' "$d"; }
# --no-llm on purpose: the closing block is printed after the authoring branch
# joins, so it is the same screen either way, and a suite must not depend on a
# model being reachable.
rbinit() { ( cd "$1/proj" && HOME="$1/home" RABADON_DIR="$1/home/.rabadon" RABADON_NOTIFY=0 \
    node "$ROOT/hooks/manage.mjs" init --no-llm 2>&1 ); }
rbremove() { ( cd "$1/proj" && HOME="$1/home" RABADON_DIR="$1/home/.rabadon" RABADON_NOTIFY=0 \
    node "$ROOT/hooks/manage.mjs" remove 2>&1 ); }
has() { printf '%s' "$1" | grep -qi -- "$2"; }
hasE() { printf '%s' "$1" | grep -Eqi -- "$2"; }

# how many hook commands in a .cursor/hooks.json belong to rabadon.
#   -1  the file is not valid JSON (a removal that corrupts the file is worse
#       than one that does nothing)
#   -2  the file is not there at all
rb_in_cursor() {
  [ -f "$1" ] || { echo -2; return; }
  python3 - "$1" <<'PY'
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    print(-1); sys.exit()
n = 0
for _ev, lst in (cfg.get("hooks") or {}).items():
    if isinstance(lst, list):
        for h in lst:
            c = h.get("command", "") if isinstance(h, dict) else ""
            if "rabadon" in str(c):
                n += 1
print(n)
PY
}
# how many hook commands carry a given string (the user's own entry)
mine_in_cursor() {
  [ -f "$1" ] || { echo -2; return; }
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    print(-1); sys.exit()
needle = sys.argv[2]
n = 0
for _ev, lst in (cfg.get("hooks") or {}).items():
    if isinstance(lst, list):
        for h in lst:
            c = h.get("command", "") if isinstance(h, dict) else ""
            if needle in str(c):
                n += 1
print(n)
PY
}

# ---- A. the init screen: what state, why, and the one next command ----
A=$(newproj a)
SCREEN=$(rbinit "$A"); A_RC=$?
LINES=$(printf '%s\n' "$SCREEN" | wc -l | tr -d ' ')

# A0. VACUITY GUARD. Every assertion below is "the screen contains X". With no
# screen captured they would all fail loudly, but with a screen captured for the
# WRONG run — an init that exited 3 with a two-line error — a future looser
# check could pass on text that is not the closing block at all. So the run is
# certified first: it succeeded, and it printed a real screen.
if [ "$A_RC" -eq 0 ]; then pass "init exits 0 on a clean project (the screen below is a successful run)"
else fail "init exited $A_RC — no closing block was produced, so nothing below is being measured; why: the screen is only printed on the success path; run: (cd $ROOT && make) then re-run this suite"
  printf '%s\n' "$SCREEN" | sed 's/^/    | /'; fi
if [ "$LINES" -ge 10 ] && [ -n "$SCREEN" ]; then pass "init printed a screen ($LINES lines), not silence"
else fail "init printed $LINES line(s) — the closing block is missing or empty; why: an installer that says nothing leaves the operator with no state and no next command; run: node hooks/manage.mjs init --no-llm"; fi

# A1. the mode BY NAME, and what it means in one sentence a stranger can act on.
has "$SCREEN" "watch" \
  && pass "the screen names the mode it left you in (watch)" \
  || { fail "the screen never says the word \"watch\"; why: init leaves the guard in watch by default and the operator ends up believing a guard that refuses nothing is enforcing; run: node hooks/manage.mjs init --no-llm"; printf '%s\n' "$SCREEN" | sed 's/^/    | /'; }
hasE "$SCREEN" "nothing (is|will be) (stopped|refused|blocked)|(refuses|stops|blocks) nothing|no action is (refused|stopped|blocked)" \
  && pass "the screen says outright that nothing is being stopped yet" \
  || { fail "the screen never says that nothing is refused in this mode; why: naming the mode is not enough — \"watch\" means nothing to somebody installing a guard for the first time; run: node hooks/manage.mjs init --no-llm"; printf '%s\n' "$SCREEN" | sed 's/^/    | /'; }

# A2. WHY it is in that state. Without this the screen reads like a defect
# report and the first move is to file an issue, not to type one command.
hasE "$SCREEN" "default" \
  && pass "the screen says watch is the default (not a fault of this install)" \
  || { fail "the screen does not say watch is the DEFAULT; why: a mode announced without a reason reads as something that went wrong during install; run: node hooks/manage.mjs init --no-llm"; printf '%s\n' "$SCREEN" | sed 's/^/    | /'; }
hasE "$SCREEN" "your (call|decision|choice|move)|you (decide|choose)|not ours" \
  && pass "the screen says turning enforcement on is the operator's decision" \
  || { fail "the screen does not say that enforcing is the operator's decision; why: a guard that switches itself to refusing on install is one nobody installs twice — the reason it waits has to be on the screen; run: node hooks/manage.mjs init --no-llm"; printf '%s\n' "$SCREEN" | sed 's/^/    | /'; }

# A3. ONE next command. Not three, not a menu: the whole failure this fixes is
# an operator who reads a screen and does not know which line is theirs.
NEXTN=$(printf '%s\n' "$SCREEN" | grep -Ec '^[[:space:]]*next:')
NEXTLINE=$(printf '%s\n' "$SCREEN" | grep -E '^[[:space:]]*next:' | head -1)
if [ "$NEXTN" -eq 1 ]; then pass "the screen carries exactly one \"next:\" line"
else fail "the screen carries $NEXTN \"next:\" lines — expected exactly 1; why: two competing next steps is the same as none, the reader picks neither; run: node hooks/manage.mjs init --no-llm"
  printf '%s\n' "$SCREEN" | sed 's/^/    | /'; fi
if printf '%s' "$NEXTLINE" | grep -q 'rabadon on'; then pass "the one next command is \`rabadon on\` ($(printf '%s' "$NEXTLINE" | sed 's/^[[:space:]]*//'))"
else fail "the \"next:\" line does not name \`rabadon on\` (got: ${NEXTLINE:-<none>}); why: the single command that turns the guard from watching into refusing is the only next step this screen has; run: node hooks/manage.mjs init --no-llm"; fi

# init must NOT have quietly enforced instead: the default stays watch, and the
# operator types `rabadon on` themselves. A screen that says "enforcing" here
# would pass every check above and break the promise underneath them.
hasE "$SCREEN" "now (enforcing|refusing)|enforcement is on" \
  && fail "the screen claims enforcement is already on — init must leave the default (watch) alone" \
  || pass "init does not claim to have turned enforcement on"

# ---- B. the Cursor exit path ----
# B1. the POSITIVE control. Every "nothing left behind" assertion below is
# satisfied by an init that wired nothing at all, so the wiring is proved first.
B=$(newproj b)
BI=$(rbinit "$B"); B_IRC=$?
BCJ="$B/proj/.cursor/hooks.json"
BEFORE=$(rb_in_cursor "$BCJ")
if [ "$BEFORE" -gt 0 ]; then pass "init wired Cursor: $BEFORE rabadon hook(s) in .cursor/hooks.json"
else fail "init left no rabadon hooks in .cursor/hooks.json (count $BEFORE, init rc $B_IRC) — the removal cases below would pass on an install that never happened; why: without this control the whole section is vacuous; run: node hooks/manage.mjs init --no-llm"
  printf '%s\n' "$BI" | sed 's/^/    | /'; fi

BR=$(rbremove "$B"); B_RRC=$?
[ "$B_RRC" -eq 0 ] && pass "remove exits 0" \
  || { fail "remove exited $B_RRC; why: the uninstall path is the one command a frustrated user runs, and it has to work; run: node hooks/manage.mjs remove"; printf '%s\n' "$BR" | sed 's/^/    | /'; }

AFTER=$(rb_in_cursor "$BCJ")
if [ "$AFTER" -eq 0 ] || [ "$AFTER" -eq -2 ]; then
  pass "after remove, no rabadon entry survives in .cursor/hooks.json (state: $AFTER)"
else
  fail "after remove, $AFTER rabadon hook(s) are STILL in $BCJ; why: Cursor keeps calling rabadon-gate on every shell command and prompt, so \`rabadon remove\` did not remove rabadon — the user's only documented exit does not exit; run: node hooks/manage.mjs remove"
  [ -f "$BCJ" ] && sed 's/^/    | /' "$BCJ"
fi

# B2. what remove SAYS. The .claude half prints a line per file it touched;
# silence about the Cursor file is how a fixed removal still reads as unfixed.
hasE "$BR" "cursor" \
  && pass "remove names the Cursor file in its output" \
  || { fail "remove says nothing about .cursor/hooks.json; why: an uninstall that strips a file without naming it leaves the operator checking by hand, and that is what they were trying to avoid; run: node hooks/manage.mjs remove"; printf '%s\n' "$BR" | sed 's/^/    | /'; }

# B3. THE PIN. With nothing but rabadon in it, whatever remove leaves behind is
# pinned here so it cannot change silently: the file is GONE (an empty skeleton
# rabadon invented and then abandoned is litter in somebody's repo).
if [ ! -f "$BCJ" ]; then pass "a hooks.json that rabadon created and rabadon emptied is deleted, not left as an empty skeleton"
else fail "$BCJ still exists after remove with nothing of the user's in it; why: init created that file, so leaving an empty one behind means uninstalling rabadon still leaves a rabadon artifact in the repo; run: node hooks/manage.mjs remove"
  sed 's/^/    | /' "$BCJ"; fi

# B4. the case that costs if it goes wrong: the user had their own Cursor hooks
# first. Deleting somebody's file is not an exit path, it is a second injury.
C=$(newproj c)
MINE="/usr/local/bin/my-own-cursor-hook"
mkdir -p "$C/proj/.cursor"
cat >"$C/proj/.cursor/hooks.json" <<JSON
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [ { "command": "$MINE" } ],
    "afterFileEdit": [ { "command": "$MINE" } ]
  }
}
JSON
CI=$(rbinit "$C"); C_IRC=$?
CCJ="$C/proj/.cursor/hooks.json"
C_RB_BEFORE=$(rb_in_cursor "$CCJ")
C_MINE_BEFORE=$(mine_in_cursor "$CCJ" "$MINE")
if [ "$C_RB_BEFORE" -gt 0 ] && [ "$C_MINE_BEFORE" -eq 2 ]; then
  pass "init merged into an existing hooks.json: $C_RB_BEFORE rabadon + $C_MINE_BEFORE of the user's own"
else
  fail "init did not merge cleanly (rabadon $C_RB_BEFORE, user's $C_MINE_BEFORE, rc $C_IRC); why: the removal case below only means something if both were there to begin with; run: node hooks/manage.mjs init --no-llm"
  printf '%s\n' "$CI" | sed 's/^/    | /'
fi
CR=$(rbremove "$C"); C_RRC=$?
C_RB_AFTER=$(rb_in_cursor "$CCJ")
C_MINE_AFTER=$(mine_in_cursor "$CCJ" "$MINE")
[ "$C_RB_AFTER" -eq 0 ] && pass "remove stripped every rabadon entry from the user's own hooks.json" \
  || { fail "after remove, rabadon count is $C_RB_AFTER in $CCJ (expected 0); why: Cursor still runs rabadon on every event; run: node hooks/manage.mjs remove"; [ -f "$CCJ" ] && sed 's/^/    | /' "$CCJ"; }
[ "$C_MINE_AFTER" -eq 2 ] && pass "the user's own two Cursor hooks survived init + remove untouched" \
  || { fail "the user's own hooks: $C_MINE_BEFORE before, $C_MINE_AFTER after (-2 = file deleted, -1 = not JSON); why: removing rabadon by deleting the operator's config is not an exit path, it is a second injury and it is unrecoverable from inside rabadon; run: node hooks/manage.mjs remove"; [ -f "$CCJ" ] && sed 's/^/    | /' "$CCJ"; }
if [ -f "$CCJ" ] && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CCJ" 2>/dev/null; then
  pass "the user's hooks.json is still valid JSON after the round trip"
else
  fail "$CCJ is missing or no longer valid JSON after remove; why: Cursor silently ignores a config it cannot parse, so the operator's own hooks stop running and nothing tells them; run: node hooks/manage.mjs remove"
fi
[ "$C_RRC" -eq 0 ] && pass "remove exits 0 on a project with the user's own Cursor hooks" \
  || { fail "remove exited $C_RRC on a merged hooks.json; run: node hooks/manage.mjs remove"; printf '%s\n' "$CR" | sed 's/^/    | /'; }

# B5. a project that never had Cursor at all: remove must not invent one, and
# must not fail. An error path here would send `rabadon remove --global` users
# to the issue tracker for a file that was never theirs.
D=$(newproj d)
DR=$(rbremove "$D"); D_RRC=$?
[ "$D_RRC" -eq 0 ] && pass "remove on a never-installed project exits 0" \
  || { fail "remove exited $D_RRC on a project with nothing installed; why: an uninstall that errors on a clean tree makes the operator think something is still there; run: node hooks/manage.mjs remove"; printf '%s\n' "$DR" | sed 's/^/    | /'; }
[ ! -e "$D/proj/.cursor" ] && pass "remove did not create a .cursor directory where there was none" \
  || fail "remove created $D/proj/.cursor; why: an uninstall must not add files"

# B6. the isolation this suite promises: nothing above reached the real home.
REAL_TOUCHED=""
for p in "$HOME/.cursor/hooks.json"; do
  [ -e "$p" ] && [ "$p" -nt "$TMP" ] && REAL_TOUCHED="$REAL_TOUCHED $p"
done
[ -z "$REAL_TOUCHED" ] && pass "no file under the real \$HOME was modified by this suite" \
  || fail "this suite modified real files:$REAL_TOUCHED"

echo "exit path: $ok ok / $bad fail"
[ "$bad" -eq 0 ]
