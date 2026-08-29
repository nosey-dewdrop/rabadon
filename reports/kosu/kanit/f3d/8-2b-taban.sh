#!/usr/bin/env bash
# 8-2b-taban.sh — how much of `2b` is spent BEFORE rabadon does anything?
#
# The same shipped binary, on the same event, twice: once doing its whole job,
# once with RABADON_OFF=1, which makes it read its switch and leave. The second
# arm is therefore process start + dyld + stdin + the switch read, and nothing
# else. Arms are ALTERNATED and paired because 7-2b-aa.sh measured this machine
# drifting monotonically upward inside a single run (1524 -> 2492 us across 8
# pairs); an A-then-B comparison on this box is biased by ordering alone.
#
# The number this produces decides what F3-S1 can still be. If the floor is a
# large fraction of the 1000 us ceiling, no amount of work inside gate.cpp
# reaches it, and the owner of that item needs to know that before spending
# another phase on it.
set -u
GATE="${1:?usage: 8-2b-taban.sh <gate-binary> [N] [PAIRS]}"
N="${2:-400}"
PAIRS="${3:-6}"

T="$(mktemp -d "${TMPDIR:-/tmp}/rb2bt.XXXXXX")"
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
[ "$rc" = 0 ] || { echo "sanity failed: not the allow path (exit $rc)"; exit 1; }
RABADON_OFF=1 "$GATE" < "$EV" >/dev/null 2>&1
orc=$?
echo "sanity: full path exit $rc (allow), RABADON_OFF=1 path exit $orc"

loop_on()  { local s e i=0; s=$(python3 -c 'import time;print(time.perf_counter_ns())')
  while [ "$i" -lt "$N" ]; do "$GATE" < "$EV" >/dev/null 2>&1; i=$((i+1)); done
  e=$(python3 -c 'import time;print(time.perf_counter_ns())'); python3 -c "print(f'{($e-$s)/1000/$N:.1f}')"; }
loop_off() { local s e i=0; s=$(python3 -c 'import time;print(time.perf_counter_ns())')
  while [ "$i" -lt "$N" ]; do RABADON_OFF=1 "$GATE" < "$EV" >/dev/null 2>&1; i=$((i+1)); done
  e=$(python3 -c 'import time;print(time.perf_counter_ns())'); python3 -c "print(f'{($e-$s)/1000/$N:.1f}')"; }
loop_nul() { local s e i=0; s=$(python3 -c 'import time;print(time.perf_counter_ns())')
  while [ "$i" -lt "$N" ]; do /usr/bin/true < "$EV" >/dev/null 2>&1; i=$((i+1)); done
  e=$(python3 -c 'import time;print(time.perf_counter_ns())'); python3 -c "print(f'{($e-$s)/1000/$N:.1f}')"; }

echo "paired, alternated. N=$N per arm, $PAIRS pairs."
echo
D=""
i=0
while [ "$i" -lt "$PAIRS" ]; do
  if [ $((i % 2)) -eq 0 ]; then on="$(loop_on)"; off="$(loop_off)"; else off="$(loop_off)"; on="$(loop_on)"; fi
  nul="$(loop_nul)"
  python3 -c "print(f'  pair {$i+1}: ON {$on:8.1f}  OFF {$off:8.1f}  null {$nul:8.1f}   attributable: ON {$on-$nul:7.1f}  OFF {$off-$nul:7.1f}   work {$on-$off:+7.1f}')"
  D="$D $(python3 -c "print(f'{$on-$nul:.1f},{$off-$nul:.1f}')")"
  i=$((i+1))
done
echo
python3 - "$D" <<'PY'
import sys, statistics
rows = [tuple(float(y) for y in x.split(',')) for x in sys.argv[1].split()]
on  = [r[0] for r in rows]
off = [r[1] for r in rows]
work = [a - b for a, b in rows]
print(f"  attributable, FULL path   : mean {statistics.mean(on):.1f} us   (median {statistics.median(on):.1f})")
print(f"  attributable, SWITCH ONLY : mean {statistics.mean(off):.1f} us   (median {statistics.median(off):.1f})")
print(f"  rabadon's own WORK        : mean {statistics.mean(work):.1f} us   signs {sum(1 for w in work if w>0)}+/{sum(1 for w in work if w<0)}-")
print()
print(f"  ceiling (R7 2b)           : 1000.0 us  — NOT moved, not movable by a phase agent (§3.8/4)")
print(f"  floor as a share of ceiling: {statistics.mean(off)/1000*100:.0f}%")
print(f"  headroom left for all of rabadon's logic: {1000-statistics.mean(off):.0f} us")
PY
