#!/usr/bin/env bash
# 7-2b-aa.sh — an A/A test. The same binary, benchmarked against ITSELF, with
# the same paired procedure a phase uses to claim a speed-up.
#
# WHY. The F3c arbiter's verdict on `2b` was that the series
# 1681.3 -> 1475.4 -> 1424.1 -> 1378.9 is not real, because the instrument
# wanders ~170 us. That is a claim about the instrument, and the only honest way
# to size an instrument is to run it where the true difference is known to be
# ZERO. Everything this harness reports as a "difference" here is noise by
# construction, so the spread below IS the noise band, and any future phase
# claiming a speed-up has to clear it.
#
# usage: 7-2b-aa.sh <gate-binary> [N] [PAIRS]
set -u
GATE="${1:?usage: 7-2b-aa.sh <gate-binary> [N] [PAIRS]}"
N="${2:-500}"
PAIRS="${3:-8}"

T="$(mktemp -d "${TMPDIR:-/tmp}/rb2baa.XXXXXX")"
trap 'rm -rf "$T"' EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"
P="$T/proj"; mkdir -p "$P/src" "$P/.git"
printf '{"name":"p","scripts":{"test":"node -e 0"}}' > "$P/package.json"
printf 'module.exports=1;\n' > "$P/src/a.js"
EV="$T/event.json"
printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"bench","tool_name":"Bash","tool_input":{"command":"git status --short"}}' "$P" > "$EV"
export RABADON_DIR="$RD" RABADON_JUDGE=0

# the same sanity gate the F3b/F3c tool has: if the benchmarked event is not the
# ALLOW path, the number describes a refusal and not what a user pays.
"$GATE" < "$EV" >/dev/null 2>&1
rc=$?
[ "$rc" = 0 ] || { echo "sanity failed: benchmarked event is not the allow path (exit $rc)"; exit 1; }
echo "sanity: benchmarked event is ALLOWED, gate exit $rc"

loop() {
  local c="$1" s e i=0
  s=$(python3 -c 'import time;print(time.perf_counter_ns())')
  while [ "$i" -lt "$N" ]; do "$c" < "$EV" >/dev/null 2>&1; i=$((i+1)); done
  e=$(python3 -c 'import time;print(time.perf_counter_ns())')
  python3 -c "print(f'{($e-$s)/1000/$N:.1f}')"
}

"$GATE" < "$EV" >/dev/null 2>&1
/usr/bin/true < "$EV" >/dev/null 2>&1

echo "A/A: the SAME binary in both arms. N=$N per arm, $PAIRS pairs, arms alternated."
echo
DIFFS=""
i=0
while [ "$i" -lt "$PAIRS" ]; do
  a="$(loop "$GATE")"
  b="$(loop "$GATE")"
  base="$(loop /usr/bin/true)"
  d=$(python3 -c "print(f'{$b-$a:.1f}')")
  python3 -c "print(f'  pair {$i+1}: armA {$a:8.1f}  armB {$b:8.1f}  diff {$b-$a:+8.1f}   (attributable armA {$a-$base:8.1f})')"
  DIFFS="$DIFFS $d"
  i=$((i+1))
done
echo
python3 - "$DIFFS" <<'PY'
import sys, statistics
d = [float(x) for x in sys.argv[1].split()]
pos = sum(1 for x in d if x > 0); neg = sum(1 for x in d if x < 0)
print(f"  pairs            : {len(d)}")
print(f"  mean difference  : {statistics.mean(d):+.1f} us   (true difference is ZERO by construction)")
print(f"  spread           : min {min(d):+.1f}  max {max(d):+.1f}  range {max(d)-min(d):.1f} us")
if len(d) > 1:
    print(f"  stdev            : {statistics.stdev(d):.1f} us")
print(f"  sign split       : {pos} positive / {neg} negative")
print()
print(f"  => NOISE BAND, measured: a paired claim on this machine must clear")
print(f"     |{max(abs(min(d)), abs(max(d))):.0f} us| and be one-sided in the sign test to mean anything.")
PY
