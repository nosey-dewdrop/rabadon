#!/usr/bin/env bash
# signals_screen_test.sh — the acceptance suite for `rabadon usage --signals`.
#
# WHY A NEW FILE AND NOT native/signals_test.sh
# signals_test.sh proves the DETECTORS fire on a fixture (reports/R7/accept.sh
# pins its result to an exact 39/0). This suite proves the SCREEN: what the user
# is shown when the detectors are run over their own recorded moves. Two
# different claims, two different files, so neither one's count moves when the
# other changes.
#
# WHAT THIS SUITE REFUSES TO LET SHIP
#   - a screen that hides LOSS. The ring keeps the newest 200 moves per session
#     and the header counts every move ever appended. The difference is moves
#     that were recorded and are gone. A screen that prints the surviving count
#     as if it were the whole record is the false-green this product cures.
#   - a signal with n=0 rendered as anything other than NOT MEASURED plus the
#     reason it was not measured. Zero is not a result.
#   - a counterfactual. "would have", "saved", "prevented" are claims about a
#     world that did not run. What happened is printable; what might have
#     happened is not.
#   - a number without the session file it came from, or a screen whose last
#     line looks backwards instead of naming the next single command.
#
# HERMETIC: its own mktemp HOME and RABADON_DIR, its own synthetic move rings
# written byte by byte below. No network, no python3, no jq, no node — bash,
# coreutils and the binary under test.
#
# The binary under test is $RABADON_STATS if set (so this suite can be run
# against a pre-change build to prove it can go red), else ./native/rabadon-stats.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATS="${RABADON_STATS:-$ROOT/native/rabadon-stats}"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "ok $PASS - $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
chk()  { if [ "$1" = "y" ]; then pass "$2"; else fail "$3"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rbsigscr.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export RABADON_DIR="$TMP/rb"
SESS="$RABADON_DIR/sessions"
mkdir -p "$SESS"

# ---------------------------------------------------------------------------
# fixture writer: the on-disk move ring, exactly as native/moves.h declares it.
#   Hdr  : char magic[8] ("RBMV1"), long long count, long long nextSeq, then
#          zero padding out to HDR_BYTES = 4096.
#   Rec  : seq(8) ts(8) claimed_rc(4) suite(4) asserts(4) tool(4)
#          sig[17] err[17] prev[17] pad(1) path[140] raw[96]  = 320 bytes,
#          CAP = 200 slots, record k of the file living at (count-keep+k)%CAP.
# Writing them here rather than driving the gate is the point: the fixture has
# to be able to state a LOSS (count > CAP) that no short local run produces.
OCT=()
for i in $(seq 0 255); do OCT[$i]=$(printf '%03o' "$i"); done
b()    { printf "\\${OCT[$(( $1 & 255 ))]}"; }
le()   { local n=$1 w=$2 i=0; while [ $i -lt "$w" ]; do b $(( n & 255 )); n=$(( n >> 8 )); i=$((i+1)); done; }
zeros(){ head -c "$1" /dev/zero; }
fx()   { local s="$1" cap="$2"; printf '%s' "$s"; zeros $(( cap - ${#s} )); }

# rec seq ts rc suite asserts tool sig err prev path raw
rec() {
  le "$1" 8; le "$2" 8; le "$3" 4; le "$4" 4; le "$5" 4; le "$6" 4
  fx "$7" 17; fx "$8" 17; fx "$9" 17; zeros 1
  fx "${10}" 140; fx "${11}" 96
}
hdr() { printf 'RBMV1'; zeros 3; le "$1" 8; le "$2" 8; zeros 4072; }

# --- fixture A: a FULL ring that lost moves ---------------------------------
# 250 moves were appended, 200 slots survive: 50 moves are gone. Every surviving
# record is the same successful Bash move, so no detector may fire on it — a
# repeat that never failed is a command doing its job (signals.h, rule 1).
LOSSFILE="lossy-session.moves.bin"
rec 1 1787539617208 0 -1 -1 1 "aaaaaaaaaaaaaaaa" "" "" "" "make build" > "$TMP/blob"
{ hdr 250 250; for _ in $(seq 200); do cat "$TMP/blob"; done; } > "$SESS/$LOSSFILE"

# --- fixture B: a short ring in which the definition of green moves ---------
# move 0 says the suite is red; moves 1 and 2 edit the file that judges it, and
# the second one edits away three assertions.
GREENFILE="green-session.moves.bin"
{
  hdr 3 3
  rec 1 1787539000000 1 0 -1 1 "bbbbbbbbbbbbbbbb" "" ""            ""                "npm test"
  rec 2 1787539100000 0 -1 5 2 "cccccccccccccccc" "" "prev1"       "src/app.test.js" "expect(x).toBe(1)"
  rec 3 1787539200000 0 -1 2 2 "dddddddddddddddd" "" "prev2"       "src/app.test.js" "expect(x).toBe(1)"
  zeros $(( 197 * 320 ))
} > "$SESS/$GREENFILE"

SIZE_OK=$(( $(wc -c < "$SESS/$GREENFILE") == 4096 + 200*320 ? 1 : 0 ))
chk "$([ "$SIZE_OK" = 1 ] && echo y || echo n)" \
  "the synthetic ring is exactly HDR_BYTES + CAP*REC_BYTES = 68096 bytes" \
  "BLOCKED: the fixture ring is $(wc -c < "$SESS/$GREENFILE") bytes, not 68096 — the fixture writer in this file no longer matches native/moves.h. NEXT: diff the Rec layout in native/moves.h against rec() above."

# ---------------------------------------------------------------------------
OUT="$TMP/screen.out"
"$STATS" --signals > "$OUT" 2>&1; RC=$?
echo "--- screen (exit $RC) ---"; cat "$OUT"; echo "--- end screen ---"

chk "$([ $RC -eq 0 ] && echo y || echo n)" \
  "\`usage --signals\` exits 0 on a corpus it can read" \
  "BLOCKED: \`usage --signals\` exited $RC. WHY: the screen is the surface; a non-zero exit means the user sees nothing. NEXT: $STATS --signals"

has() { grep -q -- "$1" "$OUT"; }
hasi(){ grep -qi -- "$1" "$OUT"; }

# ---- S4: the screen declares the corpus it read, INCLUDING the loss --------
chk "$(hasi "LOSS" && echo y || echo n)" \
  "S4: the screen names the LOSS out loud" \
  "BLOCKED: the screen never says LOSS. WHY: 50 of this fixture's 250 recorded moves are gone and the screen printed the survivors as if they were the record. NEXT: $STATS --signals"

chk "$(grep -q "50" "$OUT" && echo y || echo n)" \
  "S4: the loss is the real number (50 = 250 counted - 200 kept)" \
  "BLOCKED: the loss figure 50 is not on the screen. WHY: naming a loss without its size is not disclosure. NEXT: $STATS --signals"

chk "$(grep -q "$LOSSFILE" "$OUT" && echo y || echo n)" \
  "S4/§7: the ring that lost moves is named by file" \
  "BLOCKED: $LOSSFILE is not on the screen. WHY: a loss the user cannot locate is not actionable. NEXT: $STATS --signals"

chk "$(grep -qE '203|20[0-9] move' "$OUT" && echo y || echo n)" \
  "S4: the number of moves actually on disk is printed (200 + 3 = 203)" \
  "BLOCKED: the on-disk move count is missing. WHY: every n below is a fraction of this number and it has to be visible. NEXT: $STATS --signals"

chk "$(grep -q "2 session" "$OUT" && echo y || echo n)" \
  "S4: the session count is printed (2 ring files)" \
  "BLOCKED: the session-file count is missing from the corpus block. NEXT: $STATS --signals"

chk "$(grep -qE '2026-[0-9]{2}-[0-9]{2}' "$OUT" && echo y || echo n)" \
  "S4: the corpus date range is printed" \
  "BLOCKED: no date range on the screen. WHY: 'how much' without 'over what span' is not a measurement. NEXT: $STATS --signals"

# ---- S1: n=0 is NOT MEASURED, with a reason -------------------------------
chk "$(has "NOT MEASURED" && echo y || echo n)" \
  "S1: a signal with n=0 prints NOT MEASURED" \
  "BLOCKED: no NOT MEASURED on a screen where repeat and oscillation fired zero times. WHY: rendering a zero as a result is the reward hack this tool refuses. NEXT: $STATS --signals"

for S in repeat oscillation; do
  L=$(grep -n "^ *$S\b" "$OUT" | head -1 | cut -d: -f1)
  ok=n
  if [ -n "$L" ]; then
    sed -n "${L},$((L+4))p" "$OUT" | grep -q "NOT MEASURED" && \
    sed -n "${L},$((L+4))p" "$OUT" | grep -qi "reason" && ok=y
  fi
  chk "$ok" \
    "S1: \`$S\` is NOT MEASURED and the screen says why" \
    "BLOCKED: \`$S\` fired 0 times on this corpus and its block is not 'NOT MEASURED + reason'. WHY: a silent zero reads as 'clean', which is a claim nobody measured. NEXT: $STATS --signals"
done

# ---- S1: a NOT MEASURED signal must not be sold as a live capability ------
chk "$(hasi "not measured" && ! grep -qiE 'all clear|no problems found|clean run' "$OUT" && echo y || echo n)" \
  "S1: the screen does not translate zero findings into an all-clear" \
  "BLOCKED: the screen turned unmeasured signals into an all-clear. NEXT: $STATS --signals"

# ---- S2: n and the labelled count, as raw numbers -------------------------
chk "$(grep -qE 'n=[0-9]+' "$OUT" && echo y || echo n)" \
  "S2: each signal carries an explicit n=" \
  "BLOCKED: no 'n=' on the screen. WHY: a finding without its sample size cannot be judged. NEXT: $STATS --signals"

chk "$(hasi "labelled" && echo y || echo n)" \
  "S2: the screen says how many samples carry a human label" \
  "BLOCKED: the screen never states the labelled count. WHY: an unlabelled signal has no precision, and the screen must say so rather than imply one. NEXT: $STATS --signals"

chk "$(grep -qE '[0-9]+(\.[0-9]+)?%' "$OUT" && echo n || echo y)" \
  "S2: no percentage is printed on a corpus this small with zero labels" \
  "BLOCKED: the screen prints a percentage. WHY: n<10 and 0 labelled — a rate here has no numerator. NEXT: $STATS --signals"

# ---- green_redefined actually fired, and its number is located ------------
GL=$(grep -n "^ *green_redefined\b" "$OUT" | head -1 | cut -d: -f1)
ok=n
if [ -n "$GL" ]; then sed -n "${GL},$((GL+6))p" "$OUT" | grep -qE 'n=[1-9]' && ok=y; fi
chk "$ok" \
  "the corpus's real firing (green_redefined) is reported with n>=1" \
  "BLOCKED: green_redefined did not report a firing, though the fixture edits a test file while the suite is red and then removes assertions. WHY: a screen that misses the one thing on disk is worse than no screen. NEXT: $ROOT/native/rabadon-audit --export $SESS/$GREENFILE"

ok=n
if [ -n "$GL" ]; then sed -n "${GL},$((GL+6))p" "$OUT" | grep -q "$GREENFILE" && ok=y; fi
chk "$ok" \
  "§7: the firing is printed next to the session file that produced it" \
  "BLOCKED: green_redefined's count has no session path beside it. WHY: a number the user cannot trace to a session is an accusation, not a record. NEXT: $STATS --signals"

# ---- §4.6 / S7: no counterfactual, no credit-taking -----------------------
for W in "would have" "would-have" "saved" "prevented" "averted" "rescued" "avoided" "sub-ms" "we caught"; do
  chk "$(grep -qi -- "$W" "$OUT" && echo n || echo y)" \
    "§4.6/S7/S9: the screen never says \"$W\"" \
    "BLOCKED: the screen contains \"$W\". WHY: §4.6 forbids counterfactual numbers and S7 limits this screen to layer (a) — rabadon WROTE this. What an agent would have done instead is F3's claim, not this screen's. NEXT: grep -in '$W' <($STATS --signals)"
done

# ---- §7: the screen ends looking forward, at ONE command ------------------
LAST=$(grep -v '^[[:space:]]*$' "$OUT" | tail -1)
chk "$(printf '%s' "$LAST" | grep -qi '^next' && echo y || echo n)" \
  "§7: the closing line looks at the next session, not the past" \
  "BLOCKED: the last line is [$LAST]. WHY: this screen ends by telling the user the single next thing to run. NEXT: $STATS --signals | tail -1"

NCMD=$(printf '%s' "$LAST" | tr -cd '`' | wc -c | tr -d ' ')
chk "$([ "$NCMD" = "2" ] && echo y || echo n)" \
  "§7: the closing line names exactly ONE command" \
  "BLOCKED: the closing line carries $((NCMD/2)) backticked commands, not 1. WHY: 'here are your options' at the bottom of a screen is the oldest way to stall someone. NEXT: $STATS --signals | tail -1"

# ---- S6: the summary does not hide the NOT MEASURED rows ------------------
SUM=$(grep -in "^summary" "$OUT" | head -1 | cut -d: -f1)
ok=n
if [ -n "$SUM" ]; then sed -n "${SUM},\$p" "$OUT" | grep -qi "not measured" && ok=y; fi
chk "$ok" \
  "S6: the summary sentence itself carries the NOT MEASURED count" \
  "BLOCKED: there is no summary line, or it omits how many signals were NOT MEASURED. WHY: a summary that averages the unmeasured rows away is how a small corpus gets sold as a result. NEXT: $STATS --signals"

ok=n
if [ -n "$SUM" ]; then sed -n "${SUM},\$p" "$OUT" | grep -qiE "small|short|not a rate|too few" && ok=y; fi
chk "$ok" \
  "S6: the summary states that the corpus is too short to generalise from" \
  "BLOCKED: the summary does not admit the corpus's size. NEXT: $STATS --signals"

# ---- UX: one screen, screenshot-able --------------------------------------
LINES=$(wc -l < "$OUT" | tr -d ' ')
chk "$([ "$LINES" -le 44 ] && echo y || echo n)" \
  "UX: the whole thing is $LINES lines — one screen" \
  "BLOCKED: the screen is $LINES lines and no longer fits in a screenshot. WHY: a value-proof surface that has to be scrolled does not get shown to anyone. NEXT: $STATS --signals | wc -l"

# ---- S9: the hot path and the default screen are untouched ----------------
PLAIN="$TMP/plain.out"
"$STATS" > "$PLAIN" 2>&1; PRC=$?
chk "$([ $PRC -eq 0 ] && ! grep -q "NOT MEASURED" "$PLAIN" && echo y || echo n)" \
  "S9: plain \`usage\` is a separate branch — no signal block leaks into it" \
  "BLOCKED: plain \`usage\` exited $PRC or now renders the signal screen. WHY: --signals is an early-exit arm; the default surface and the hook path must not change. NEXT: $STATS"

# ---- silent-ignore hazard: --signals with a renderer flag must refuse -----
"$STATS" --signals --json > "$TMP/combo.out" 2>&1; CRC=$?
chk "$([ $CRC -ne 0 ] && echo y || echo n)" \
  "--signals combined with a renderer flag is refused, not silently ignored" \
  "BLOCKED: \`--signals --json\` exited $CRC. WHY: silently honouring one of two flags is how a caller reads the wrong screen under the right heading. NEXT: $STATS --signals --json"

# ---- Promise 1: an empty corpus says it cannot measure, it does not zero ---
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
RABADON_DIR="$EMPTY" "$STATS" --signals > "$TMP/none.out" 2>&1; NRC=$?
chk "$([ $NRC -eq 0 ] && grep -qi "not measured\|no session" "$TMP/none.out" && echo y || echo n)" \
  "Promise 1: with no ring on disk the screen says it cannot measure" \
  "BLOCKED: an empty corpus produced exit $NRC and [$(head -1 "$TMP/none.out")]. WHY: 'I can't check this' is a designed path; printing zeros for a corpus that does not exist is not. NEXT: RABADON_DIR=$EMPTY $STATS --signals"

chk "$(grep -qE '`[^`]+`' "$TMP/none.out" && echo y || echo n)" \
  "Promise 1: the empty-corpus screen still names the next command" \
  "BLOCKED: the empty-corpus screen leaves the user with nothing to run. NEXT: RABADON_DIR=$EMPTY $STATS --signals"

# ---- the shipped surface is a DOCUMENTED surface --------------------------
# CLAUDE.md: "a commit that changes what rabadon does updates README/docs in the
# same commit. Stale docs are lies with good formatting." `--signals` shipped in
# 28340e2 with a CLI hint line and nothing in docs/. These three assertions hold
# docs/commands.md to what the binary above was just measured printing: the flag
# itself, the word its loss block is printed under, and the rendering a
# zero-sample detector gets. All three strings are asserted on the SCREEN
# earlier in this file, so the page is tied to the binary, not to a copy of the
# page.
DOC="$ROOT/docs/commands.md"
UHEAD="$(grep -n '^## `rabadon usage' "$DOC" 2>/dev/null | head -1)"

chk "$([ -f "$DOC" ] && printf '%s' "$UHEAD" | grep -q -- '--signals' && echo y || echo n)" \
  "docs: the \`rabadon usage\` heading in docs/commands.md lists --signals" \
  "BLOCKED: docs/commands.md's usage heading does not carry --signals [$UHEAD]. WHY: a flag only the CLI hint mentions cannot be found by a reader of the reference page, and that page then describes a binary that no longer ships. NEXT: grep -n '^## .rabadon usage' $DOC"

chk "$(grep -q -- '--signals' "$DOC" && grep -qi 'LOSS' "$DOC" && echo y || echo n)" \
  "docs: the page names the LOSS the screen prints" \
  "BLOCKED: docs/commands.md names --signals without naming the loss. WHY: the ring keeps the newest 200 moves per session, the screen exists to say so, and a page that omits it sells the survivors as the whole record. NEXT: grep -ni loss $DOC"

chk "$(grep -q 'NOT MEASURED' "$DOC" && echo y || echo n)" \
  "docs: the page names NOT MEASURED as what a zero-sample detector renders as" \
  "BLOCKED: docs/commands.md never says NOT MEASURED. WHY: the screen prints it for four of the five detectors on the frozen corpus, and a reader who was never told what it means reads it as a failure. NEXT: grep -n 'NOT MEASURED' $DOC"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
