#!/usr/bin/env bash
# 2b-uctan-uca.sh — what the user's hook really costs, end to end.
#
# The number R7's `2b` publishes comes from an IN-PROCESS probe. DURUM.md §8.5
# measured the other one on 2026-08-26 and it was worse: the shipped binary,
# started as a real PreToolUse hook, cost 3381.3 us raw / 1994.5 us attributable
# against a 1000 us ceiling = 1.99x. This script reproduces that DEFINITION so a
# later phase can say whether it moved, and so a phase that touched gate.cpp can
# show it did not make the hot path slower (CLAUDE.md, quality bar).
#
# Definition:
#   raw          = wall time of one `rabadon-gate` process on one event
#   baseline     = wall time of one /usr/bin/true, same harness
#   attributable = raw - baseline
#
# NOT IDENTICAL TO §8.5, and the difference is written here rather than hidden:
# §8.5 reported a MEDIAN of 300 per-call timings and benchmarked a REFUSED
# event. This reports a MEAN over N calls (one clock read for the whole loop, so
# the timer costs nothing per call) on the ALLOWED path, which is what every
# ordinary tool call pays. The two are the same order and the same definition of
# "attributable"; they are not the same number and must not be quoted as one.
#
# usage: reports/kosu/kanit/f3/2b-uctan-uca.sh <gate-binary> [N]
set -u
GATE="${1:?usage: 2b-uctan-uca.sh <gate-binary> [N]}"
N="${2:-200}"
[ -x "$GATE" ] || { echo "not executable: $GATE"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/rb2b.XXXXXX")"
trap 'rm -rf "$T"' EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"
P="$T/proj"; mkdir -p "$P/src" "$P/.git"
printf '{"name":"p","scripts":{"test":"node -e 0"}}' > "$P/package.json"
printf 'module.exports=1;\n' > "$P/src/a.js"
EV="$T/event.json"
printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"bench","tool_name":"Bash","tool_input":{"command":"git status --short"}}' "$P" > "$EV"

export RABADON_DIR="$RD" RABADON_JUDGE=0
"$GATE" < "$EV" >/dev/null 2>&1
rc=$?
[ "$rc" = "0" ] || { echo "sanity failed: the benchmarked event is not the allow path (exit $rc)"; exit 1; }
echo "sanity: the benchmarked event is ALLOWED -> gate exit $rc (must be 0)"

loop() { # loop <cmd> -> mean microseconds per call
  local c="$1" s e i=0
  s=$(python3 -c 'import time;print(time.perf_counter_ns())')
  while [ "$i" -lt "$N" ]; do "$c" < "$EV" >/dev/null 2>&1; i=$((i+1)); done
  e=$(python3 -c 'import time;print(time.perf_counter_ns())')
  python3 -c "print(f'{($e-$s)/1000/$N:.1f}')"
}
"$GATE" < "$EV" >/dev/null 2>&1        # warm the page cache for both
/usr/bin/true < "$EV" >/dev/null 2>&1
RAW="$(loop "$GATE")"
BASE="$(loop /usr/bin/true)"
ATTR="$(python3 -c "print(f'{$RAW-$BASE:.1f}')")"
printf 'binary                                = %s\n' "$GATE"
printf 'N (mean, not median)                  = %s\n' "$N"
printf 'REAL gate, end to end                 = %s us\n' "$RAW"
printf 'empty baseline /usr/bin/true, same    = %s us\n' "$BASE"
printf 'cost ATTRIBUTABLE to rabadon          = %s us\n' "$ATTR"
printf 'ceiling (R7 2b)                       = 1000.0 us\n'
python3 -c "print(f'attributable / ceiling                = {$ATTR/1000.0:.2f}x')"
