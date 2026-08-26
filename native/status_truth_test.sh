#!/bin/bash
# status_truth_test.sh — the CLI's CLAIM about supervision, held against what the
# REAL gate binary actually does in the same instant.
#
# WHY THIS FILE EXISTS.
# `rabadon status` is the one screen a user reads to answer "is this thing
# guarding me right now". It is a claim. Nothing in the suite compared that
# claim to the only thing that decides the answer: the exit code the real
# native/rabadon-gate returns for a real PreToolUse event. A status screen that
# says ON while the gate returns 0 and prints nothing is the exact false green
# this product sells a cure for, printed by the product's own dashboard.
#
# THE INVARIANT. The gate has three true states and each one has an observable
# signature for the SAME event through the SAME binary:
#
#   true state                     gate exit   gate stdout+stderr
#   ENFORCE  (refusing)                2       non-empty ("BLOCKED")
#   WATCH    (recording, not stopping) 0       NON-EMPTY ("would have blocked")
#   SILENT   (not running at all)      0       ZERO BYTES
#
# Whichever of those three the screen claims, the gate must produce that
# signature. If it does not, this suite prints BLOCKED.
#
# SECOND INVARIANT. `rabadon-gate --statusline` renders the lamp in the Claude
# Code status bar off the same instant. It must return the SAME verdict as
# `status` (ON / watch / off). A status screen saying ON beside a lamp saying
# off means one of the two is lying and the user has no way to tell which.
#
# THIRD (KOSU-RABADON-5 4.8). When a muter is in force, the screen must name it,
# say WHERE it is, and give the ONE command that lifts it:
#   RABADON_OFF=1        -> "environment variable",  next: unset RABADON_OFF
#   <proj>/.rabadon/off  -> the absolute path,       next: rm <path>
#   <RABADON_DIR>/silent -> the absolute path,       next: rabadon off
# A muted guard whose screen does not name the muter leaves the operator
# clicking a switch that is already overridden.
#
# THE MATRIX. 16 cells: mode {watch,enforce} x <proj>/.rabadon/off {y,n} x
# RABADON_OFF {1,unset} x <RABADON_DIR>/silent {y,n}. Each cell is asked three
# ways: `status`, then `on`, then `off` — every one of them a claim, every one
# of them checked against the gate that ran AFTER it.
#
# VACUITY GUARD (KOSU-RABADON-5 8.2). Every assertion here is satisfiable by a
# gate that is simply broken and returns 0 to everything. So section P requires
# that at least one cell saw the gate REALLY refuse (exit 2). If none did, the
# instrument is broken and this suite is BLOCKED rather than green.
#
# HERMETIC. Nothing touches the real $HOME or the real ~/.rabadon: every cell
# gets its own mktemp project and its own mktemp RABADON_DIR, and section H
# checks the real ones were not written. Needs only git and a shell — no node,
# no python3, no jq.
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

CLI="$ROOT/native/rabadon-cli.sh"
GATE="${RABADON_GATE:-$ROOT/native/rabadon-gate}"

# Preflight is BLOCKED, not skipped. A suite that quietly exits 0 because the
# binary is missing is the false green it was written to catch.
if [ ! -x "$GATE" ]; then
  echo "  FAIL - BLOCKED: the gate binary is not there, so no claim can be checked against anything; why: every assertion in this file compares a screen to $GATE and without it they would all pass vacuously; run: (cd $ROOT && make all)"
  echo "status truth: 0 ok / 1 fail"
  exit 1
fi
if [ ! -f "$CLI" ]; then
  echo "  FAIL - BLOCKED: $CLI is missing, so there is no claim to check; why: the dispatcher IS the public surface after npm i -g; run: git status --porcelain native/rabadon-cli.sh"
  echo "status truth: 0 ok / 1 fail"
  exit 1
fi
command -v git >/dev/null 2>&1 || {
  echo "  FAIL - BLOCKED: git is not on PATH; why: every cell is a real git repo because the gate's rules are repo-scoped; run: git --version"
  echo "status truth: 0 ok / 1 fail"; exit 1; }

TMP=$(mktemp -d /tmp/rabadon-statustruth.XXXXXX) || exit 1
trap 'rm -rf "$TMP"' EXIT
STAMP="$TMP/.stamp"; : > "$STAMP"

CELLN=0
PROJ=""; RD=""
ESC=$(printf '\033')

# setup_cell MODE PROJOFF ENVOFF SILENT — a brand new sandbox for one probe.
# Fresh every time because `rabadon on`/`off` MUTATE the mode file and unlink
# the silent marker: reusing a cell would measure the previous probe.
setup_cell() {
  CELLN=$((CELLN+1))
  PROJ="$TMP/c$CELLN/proj"; RD="$TMP/c$CELLN/rabadon"; HOMEDIR="$TMP/c$CELLN/home"
  mkdir -p "$PROJ" "$RD" "$HOMEDIR" || return 1
  git init -q "$PROJ" >/dev/null 2>&1 || return 1
  printf '%s\n' "$1" > "$RD/mode" || return 1
  if [ "$2" = yes ]; then mkdir -p "$PROJ/.rabadon" && : > "$PROJ/.rabadon/off" || return 1; fi
  if [ "$4" = yes ]; then : > "$RD/silent" || return 1; fi
  CELL_ENVOFF="$3"
  [ -f "$RD/mode" ] || return 1
  return 0
}

# run the CLI inside the cell. RABADON_OFF is only EXPORTED when the cell says
# so — an empty string is not the same as unset and the gate reads == "1".
cli() {
  if [ "$CELL_ENVOFF" = yes ]; then
    ( cd "$PROJ" && HOME="$HOMEDIR" RABADON_DIR="$RD" RABADON_OFF=1 RABADON_NOTIFY=0 bash "$CLI" "$@" 2>&1 )
  else
    ( cd "$PROJ" && HOME="$HOMEDIR" RABADON_DIR="$RD" RABADON_NOTIFY=0 bash "$CLI" "$@" 2>&1 )
  fi
}

# one real PreToolUse event, through the real binary, in the cell's cwd.
# Sets GRC (exit code) and GBYTES (stdout+stderr byte count).
EVENT_CMD='git push --force origin main'
gate_probe() {
  ev=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$PROJ" "$EVENT_CMD")
  if [ "$CELL_ENVOFF" = yes ]; then
    GOUT=$(printf '%s' "$ev" | ( cd "$PROJ" && HOME="$HOMEDIR" RABADON_DIR="$RD" RABADON_OFF=1 RABADON_NOTIFY=0 "$GATE" 2>&1 )); GRC=$?
  else
    GOUT=$(printf '%s' "$ev" | ( cd "$PROJ" && HOME="$HOMEDIR" RABADON_DIR="$RD" RABADON_NOTIFY=0 "$GATE" 2>&1 )); GRC=$?
  fi
  GBYTES=$(printf '%s' "$GOUT" | wc -c | tr -d ' ')
  [ "$GRC" -eq 2 ] && SAW_ENFORCE=1
}

# the lamp, for the same instant. Sets SLV to on|watch|off|?? .
statusline_probe() {
  if [ "$CELL_ENVOFF" = yes ]; then
    SL=$(printf '{"workspace":{"current_dir":"%s"}}' "$PROJ" | ( cd "$PROJ" && HOME="$HOMEDIR" RABADON_DIR="$RD" RABADON_OFF=1 "$GATE" --statusline 2>&1 ))
  else
    SL=$(printf '{"workspace":{"current_dir":"%s"}}' "$PROJ" | ( cd "$PROJ" && HOME="$HOMEDIR" RABADON_DIR="$RD" "$GATE" --statusline 2>&1 ))
  fi
  SLPLAIN=$(printf '%s' "$SL" | sed "s/${ESC}\[[0-9;]*m//g")
  case "$SLPLAIN" in
    *"rabadon off"*)   SLV=off ;;
    *"rabadon watch"*) SLV=watch ;;
    *"rabadon"*)       SLV=on ;;
    *)                 SLV="??" ;;
  esac
}

# what the screen CLAIMS. ON / WATCH / SILENT / ?? .
claim_of() {
  case "$1" in
    *"ON —"*|*"ON -"*)  printf 'ON' ;;
    *WATCH*)            printf 'WATCH' ;;
    *SILENT*)           printf 'SILENT' ;;
    *)                  printf '??' ;;
  esac
}

# the signature the claim promises, against the signature observed.
# expects: claim, label
check_signature() {
  _claim="$1"; _label="$2"
  case "$_claim" in
    ON)     _wrc=2; _wbytes=nonzero; _true=ENFORCE ;;
    WATCH)  _wrc=0; _wbytes=nonzero; _true=WATCH ;;
    SILENT) _wrc=0; _wbytes=zero;    _true=SILENT ;;
    *)
      fail "BLOCKED: $_label — the screen did not claim any of ON/WATCH/SILENT; why: a status screen that cannot be read has no truth value and nothing below it can be checked; run: (cd $PROJ && RABADON_DIR=$RD bash native/rabadon-cli.sh status)"
      return ;;
  esac
  _hit=1
  [ "$GRC" = "$_wrc" ] || _hit=0
  if [ "$_wbytes" = nonzero ]; then [ "$GBYTES" -gt 0 ] || _hit=0
  else [ "$GBYTES" -eq 0 ] || _hit=0; fi
  if [ "$_hit" = 1 ]; then
    pass "$_label — claim $_claim, gate exit $GRC / $GBYTES bytes (matches $_true)"
  else
    fail "BLOCKED: $_label — the screen claims $_claim but the real gate answered exit $GRC with $GBYTES bytes for \`$EVENT_CMD\`; why: $_claim means the gate is $_true, and $_true has signature exit $_wrc / $_wbytes output — the screen is describing a supervision state the binary is not in; run: printf '{\"hook_event_name\":\"PreToolUse\",\"cwd\":\"$PROJ\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$EVENT_CMD\"}}' | RABADON_DIR=$RD $GATE; echo \$?"
  fi
}

# the lamp must agree with the screen.
check_statusline() {
  _claim="$1"; _label="$2"
  case "$_claim" in
    ON)     _wsl=on ;;
    WATCH)  _wsl=watch ;;
    SILENT) _wsl=off ;;
    *)      _wsl="??" ;;
  esac
  if [ "$SLV" = "$_wsl" ]; then
    pass "$_label — status says $_claim and the lamp says \"$SLV\""
  else
    fail "BLOCKED: $_label — \`status\` says $_claim but \`--statusline\` says \"$SLV\" for the same project at the same instant; why: the screen and the status bar read different switches, so two surfaces of one product disagree about whether the user is supervised and neither is marked as the authority; run: printf '{\"workspace\":{\"current_dir\":\"$PROJ\"}}' | RABADON_DIR=$RD $GATE --statusline"
  fi
}

# 4.8: name it, locate it, lift it.
# check_disclosure SCREEN NAME LOCATION NEXTCMD LABEL
check_disclosure() {
  _s="$1"; _name="$2"; _loc="$3"; _next="$4"; _label="$5"
  _miss=""
  printf '%s' "$_s" | grep -qF -- "$_name" || _miss="$_miss name(\"$_name\")"
  printf '%s' "$_s" | grep -qF -- "$_loc"  || _miss="$_miss where(\"$_loc\")"
  printf '%s\n' "$_s" | grep -E '^[[:space:]]*next:' | grep -qF -- "$_next" \
    || _miss="$_miss next(\"$_next\")"
  if [ -z "$_miss" ]; then
    pass "$_label — the screen names $_name, where it is, and the one command that lifts it"
  else
    fail "BLOCKED: $_label — the screen is missing:$_miss; why: supervision is overridden by $_name and the screen never says so, so the operator reads a mode that is not in force and has no way to find the override; run: (cd $PROJ && RABADON_DIR=$RD bash native/rabadon-cli.sh status)"
  fi
}

SAW_ENFORCE=0

echo "status truth: what the CLI claims vs what the real gate does"
echo

# ---- A / B. the 16-cell matrix, three claims each -------------------------
for MODE in watch enforce; do
 for POFF in no yes; do
  for EOFF in no yes; do
   for SIL in no yes; do
    TAG="mode=$MODE projoff=$POFF RABADON_OFF=$EOFF silent=$SIL"

    # --- A. `status` ---
    if ! setup_cell "$MODE" "$POFF" "$EOFF" "$SIL"; then
      fail "BLOCKED: [$TAG] the sandbox could not be built; why: a cell that never got set up would let every assertion under it pass on nothing; run: mktemp -d && git init -q"
      continue
    fi
    SCREEN=$(cli status); SRC=$?
    CLAIM=$(claim_of "$SCREEN")
    gate_probe
    statusline_probe
    if [ "$SRC" -ne 0 ]; then
      fail "BLOCKED: [$TAG] \`rabadon status\` exited $SRC; why: the one command a user runs to learn whether they are supervised failed, so there is no claim to compare and the answer is unknown rather than off; run: (cd $PROJ && RABADON_DIR=$RD bash native/rabadon-cli.sh status)"
    fi
    check_signature "$CLAIM" "[$TAG] status"
    check_statusline "$CLAIM" "[$TAG] status/lamp"

    # 4.8, only where a muter is actually in force.
    [ "$EOFF" = yes ] && check_disclosure "$SCREEN" "RABADON_OFF" "environment variable" "unset RABADON_OFF" "[$TAG] status/4.8 env"
    [ "$POFF" = yes ] && check_disclosure "$SCREEN" ".rabadon/off" "$PROJ/.rabadon/off" "rm $PROJ/.rabadon/off" "[$TAG] status/4.8 project"
    [ "$SIL"  = yes ] && check_disclosure "$SCREEN" "silent" "$RD/silent" "rabadon off" "[$TAG] status/4.8 silent"

    # --- B1. `rabadon on` — a claim that also ACTS. Ask the gate after. ---
    if setup_cell "$MODE" "$POFF" "$EOFF" "$SIL"; then
      ONS=$(cli on); ONC=$(claim_of "$ONS")
      gate_probe
      check_signature "$ONC" "[$TAG] after \`rabadon on\`"
    else
      fail "BLOCKED: [$TAG] sandbox for \`on\` could not be built; run: mktemp -d && git init -q"
    fi

    # --- B2. `rabadon off` ---
    if setup_cell "$MODE" "$POFF" "$EOFF" "$SIL"; then
      OFFS=$(cli off); OFFC=$(claim_of "$OFFS")
      gate_probe
      check_signature "$OFFC" "[$TAG] after \`rabadon off\`"
    else
      fail "BLOCKED: [$TAG] sandbox for \`off\` could not be built; run: mktemp -d && git init -q"
    fi
   done
  done
 done
done

echo

# ---- P. the positive control ---------------------------------------------
# Everything above is satisfied by a gate that returns 0 to every input. If no
# cell ever saw a real refusal, the measuring instrument is broken and a green
# run here would mean nothing.
if [ "$SAW_ENFORCE" -eq 1 ]; then
  pass "positive control: at least one cell got a REAL refusal (gate exit 2), so the instrument works"
else
  fail "BLOCKED: not one of the $CELLN cells produced gate exit 2, so nothing above measured a real refusal; why: every check in this file is satisfied by a gate that returns 0 to everything, and a suite that cannot see a block cannot see a missing one either; run: (cd $ROOT && make all) then bash native/status_truth_test.sh"
fi

echo

# ---- C. the routing pin (must be GREEN) ----------------------------------
# on|off|status|toggle are the four verbs that change supervision. None of them
# may reach bin/rabadon.mjs, which is the frozen anti-path: it resolves
# ../native directly, misses the prebuilt platform package, and carries its own
# stale verb list. If any shipped path routes a supervision verb through it,
# the state the user flips is not the state the gate reads.
echo "routing pin: no shipped path sends on|off|status|toggle to bin/rabadon.mjs"

PJ="$ROOT/package.json"
BINVAL=$(awk '/"bin"[[:space:]]*:/{inb=1} inb{print; if (/}/ && !/"bin"/) exit}' "$PJ")
if printf '%s' "$BINVAL" | grep -q 'native/rabadon-cli.sh' && ! printf '%s' "$BINVAL" | grep -q 'rabadon.mjs'; then
  pass "package.json bin.rabadon points at native/rabadon-cli.sh, not bin/rabadon.mjs"
else
  fail "BLOCKED: package.json \"bin\" does not point at native/rabadon-cli.sh (got: $(printf '%s' "$BINVAL" | tr '\n' ' ')); why: \`npm i -g rabadon\` puts exactly one file on PATH, so if that file is the anti-path then on/off/status are answered by code that reads a different switch than the gate; run: grep -A3 '\"bin\"' package.json"
fi

ARM=$(grep -n 'on|off|status)' "$CLI" | head -1)
ARMBODY=$(printf '%s' "$ARM" | sed 's/^[0-9]*://')
if [ -z "$ARM" ]; then
  fail "BLOCKED: no \`on|off|status)\` arm found in native/rabadon-cli.sh; why: the dispatcher is the only surface an installed user has, and the three supervision verbs having no arm means they fall through to the unknown-verb path or to the anti-path; run: grep -n 'on|off|status' native/rabadon-cli.sh"
elif printf '%s' "$ARMBODY" | grep -q 'rabadon.mjs'; then
  fail "BLOCKED: the on|off|status arm mentions rabadon.mjs ($ARMBODY); why: the verb that flips supervision would be answered by the frozen anti-path instead of the gate binary that decides refusals; run: grep -n 'on|off|status' native/rabadon-cli.sh"
elif printf '%s' "$ARMBODY" | grep -q 'nbin gate'; then
  pass "the on|off|status arm goes straight to the gate binary, no rabadon.mjs in it"
else
  fail "BLOCKED: the on|off|status arm does not resolve the gate binary ($ARMBODY); why: the supervision verbs must be answered by the same binary the hooks call, or the screen and the gate read different state; run: grep -n 'on|off|status' native/rabadon-cli.sh"
fi

TARM=$(grep -E '^[[:space:]]*toggle\)' "$CLI" | head -1)
if [ -n "$TARM" ] && printf '%s' "$TARM" | grep -q 'nbin gate' && ! printf '%s' "$TARM" | grep -q 'rabadon.mjs'; then
  pass "the toggle arm goes straight to the gate binary, no rabadon.mjs in it"
else
  fail "BLOCKED: the \`toggle\` arm is missing or routes through rabadon.mjs (got: ${TARM:-<none>}); why: toggle is the verb that flips enforcement without naming a direction, and routing it to the anti-path means the flip and the gate disagree; run: grep -nE '^[[:space:]]*toggle\\)' native/rabadon-cli.sh"
fi

SCRIPTS=$(awk '/"scripts"[[:space:]]*:/{inb=1;next} inb{ if (/^[[:space:]]*}/) exit; print }' "$PJ")
BADSCRIPT=$(printf '%s\n' "$SCRIPTS" | grep -E '^[[:space:]]*"(on|off|status|toggle)"[[:space:]]*:' | grep 'rabadon.mjs')
if [ -z "$BADSCRIPT" ]; then
  pass "package.json scripts has no on/off/status/toggle entry calling rabadon.mjs"
else
  fail "BLOCKED: package.json scripts routes a supervision verb through rabadon.mjs ($BADSCRIPT); why: an npm script is a shipped path, and one that flips supervision through the anti-path writes state the gate does not read; run: grep -A8 '\"scripts\"' package.json"
fi

echo

# ---- H. hermeticity -------------------------------------------------------
REAL_TOUCHED=""
for p in "$HOME/.rabadon/mode" "$HOME/.rabadon/enabled" "$HOME/.rabadon/silent" "$HOME/.rabadon/mode.last"; do
  [ -e "$p" ] && [ "$p" -nt "$STAMP" ] && REAL_TOUCHED="$REAL_TOUCHED $p"
done
[ -z "$REAL_TOUCHED" ] && pass "no file under the real ~/.rabadon was written by this suite" \
  || fail "BLOCKED: this suite wrote the operator's own switch:$REAL_TOUCHED; why: a test that flips real supervision leaves the machine in whatever state it stopped in; run: rabadon status"

echo
echo "status truth: $ok ok / $bad fail"
[ "$bad" -eq 0 ] || exit 1
