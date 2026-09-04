#!/usr/bin/env bash
# k3-ledger.sh — HOW MUCH OF `2b` IS THE LEDGER'S OWN SIZE?
#
# Two things the F3h arbiter measured and left for this phase to write down:
# a spool that has grown costs the gate time on every later call, and a single
# uninterrupted run drifts upward with no code change at all. Both matter for
# how `2b` is read: a regression ruler whose reading depends on how long the
# machine has been running is measuring the machine as much as the binary.
#
# Three arms, same binary, same event, same N -- only the ledger differs:
#   EMPTY   a fresh spool directory
#   GROWN   the same directory after it has been written to by the run itself
#   HALVES  first half of one uninterrupted run vs second half (the drift)
#
# usage: N=400 bash reports/kosu/kanit/f3i/k3-ledger.sh
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"
GATE="$ROOT/native/rabadon-gate"
N="${N:-400}"; WARM="${WARM:-40}"
[ -x "$GATE" ] || { echo "build first: make"; exit 1; }

W="$(mktemp -d "$HOME/.rb-f3i-led.XXXXXX")"; trap 'rm -rf "$W"' EXIT
PJ="$W/proj"; mkdir -p "$PJ/.git"; printf 'ref: refs/heads/main\n' > "$PJ/.git/HEAD"
EV="$(python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"led","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":"echo hello world"}}))' "$PJ")"

# One clock read per batch, so the timer costs nothing per call.
batch() { # batch <rabadon-dir> <n> -> mean us per call
  local RD="$1" C="$2" i=0 s e
  s=$(python3 -c 'import time;print(time.perf_counter_ns())')
  while [ "$i" -lt "$C" ]; do
    printf '%s' "$EV" | env HOME="$W" RABADON_DIR="$RD" RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
    i=$((i+1))
  done
  e=$(python3 -c 'import time;print(time.perf_counter_ns())')
  python3 -c "print(f'{($e-$s)/1000/$C:.1f}')"
}
size() { du -sk "$1/spool" 2>/dev/null | awk '{print $1}'; }

echo "k3-ledger: same binary, same event, N=$N per batch -- only the spool differs"
echo ""

RD1="$W/rd1"; mkdir -p "$RD1/spool"; : > "$RD1/enabled"
i=0; while [ "$i" -lt "$WARM" ]; do printf '%s' "$EV" | env HOME="$W" RABADON_DIR="$RD1" RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1; i=$((i+1)); done
S0="$(size "$RD1")"
A="$(batch "$RD1" "$N")"
S1="$(size "$RD1")"
B="$(batch "$RD1" "$N")"
S2="$(size "$RD1")"

printf '  spool %5s KB -> first  %s calls: %8s us/call\n' "$S0" "$N" "$A"
printf '  spool %5s KB -> second %s calls: %8s us/call\n' "$S1" "$N" "$B"
printf '  spool %5s KB after\n' "$S2"
python3 -c "
a,b=$A,$B
print(f'  drift within one uninterrupted run, no code change: {b-a:+.1f} us  ({100*(b-a)/a:+.1f}%)')"

# CONTROL: the same two batches against a spool that is thrown away between
# them. If the drift is the machine and not the ledger, this moves the same way.
echo ""
RD2="$W/rd2"; mkdir -p "$RD2/spool"; : > "$RD2/enabled"
i=0; while [ "$i" -lt "$WARM" ]; do printf '%s' "$EV" | env HOME="$W" RABADON_DIR="$RD2" RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1; i=$((i+1)); done
C="$(batch "$RD2" "$N")"
rm -rf "$RD2/spool"; mkdir -p "$RD2/spool"
D="$(batch "$RD2" "$N")"
printf '  control, spool WIPED between the two batches:\n'
printf '    first  %s calls: %8s us/call\n' "$N" "$C"
printf '    second %s calls: %8s us/call\n' "$N" "$D"
python3 -c "
a,b,c,d=$A,$B,$C,$D
print(f'    drift with the ledger reset: {d-c:+.1f} us  ({100*(d-c)/c:+.1f}%)')
print()
print(f'  ATTRIBUTABLE TO LEDGER SIZE = (grown drift) - (reset drift) = {(b-a)-(d-c):+.1f} us')
print( '  (a positive number here is the spool; what is left over is the machine)')"
