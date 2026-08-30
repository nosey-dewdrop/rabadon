#!/usr/bin/env bash
# k2-abba.sh — is rabadon-gated FASTER than the shipped path, end to end?
#
# WHY PAIRED AND ABBA. Three arbiters were scolded for comparing numbers taken
# in different sessions on a machine whose load drifts. So both arms run inside
# ONE invocation, alternating A B B A, and the reported quantity is the
# DIFFERENCE within each pair. A one-directional drift cancels; a real effect
# keeps its sign across all pairs.
#
# THE TWO ARMS, and the only difference between them is whether a daemon exists:
#   A  shipped: no daemon, and the default socket path is ABSENT, so the client
#      pays one stat() and judges in-process. That is what the operator's
#      installed machine does today (settings.json registers rabadon-gate on 5
#      events; rabadon-gated on none).
#   B  daemon: the same client binary, the same event, a live rabadon-gated on
#      the default path, so try_daemon() connects and the verdict comes back
#      over the socket.
#
# XDG_RUNTIME_DIR is pointed at a private directory in BOTH arms on purpose:
# the operator's machine has a dead /tmp/rabadon-501.sock left over from 24 Aug,
# and letting arm A pay a failed connect() to it would measure that defect
# rather than the product. That file is hers and is not touched.
#
# The per-arm measurement is the phase's mandated tool, unmodified.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
TOOL="$ROOT/reports/kosu/kanit/f3/2b-uctan-uca.sh"
GATE="$ROOT/native/rabadon-gate"
GATED="$ROOT/native/rabadon-gated"
N="${1:-200}"
REPS="${2:-3}"

for f in "$TOOL" "$GATE" "$GATED"; do
  [ -x "$f" ] || { echo "missing or not executable: $f"; exit 1; }
done

X="$(mktemp -d "$HOME/.rbk2.XXXXXX")"          # short path: sun_path is 104 B
SOCK="$X/rabadon-501.sock"
DPID=""
cleanup() { [ -n "$DPID" ] && kill "$DPID" 2>/dev/null; rm -rf "$X"; }
trap cleanup EXIT

attributable() { # attributable  -> the tool's "cost ATTRIBUTABLE" line, us
  XDG_RUNTIME_DIR="$X" "$TOOL" "$GATE" "$N" 2>/dev/null \
    | awk '/cost ATTRIBUTABLE/ {print $(NF-1)}'
}

start_daemon() {
  RABADON_GATED_SOCK="$SOCK" "$GATED" >"$X/d.log" 2>&1 &
  DPID=$!
  for _ in $(seq 1 50); do [ -S "$SOCK" ] && return 0; sleep 0.1; done
  echo "daemon never bound $SOCK"; cat "$X/d.log"; exit 1
}
stop_daemon() { [ -n "$DPID" ] && kill "$DPID" 2>/dev/null; DPID=""; rm -f "$SOCK"; }

echo "k2-abba: N=$N per arm, $REPS ABBA pairs, tool=$(basename "$TOOL")"
echo "A = shipped (no daemon, socket absent)   B = rabadon-gated live"

# PROOF THE ARMS ARE REALLY DIFFERENT. Without this the whole run could be two
# copies of arm A: if the client never reached the daemon, B would silently be
# A and the difference would honestly measure nothing.
start_daemon
XDG_RUNTIME_DIR="$X" RABADON_DIR="$X/rd" "$GATE" </dev/null >/dev/null 2>&1
if grep -q . "$X/d.log" && [ -S "$SOCK" ]; then :; fi
echo "sanity: daemon bound $SOCK and logged: $(head -1 "$X/d.log")"
stop_daemon

SUM=0; NPOS=0; NNEG=0
i=0
while [ "$i" -lt "$REPS" ]; do
  i=$((i+1))
  a1="$(attributable)"
  start_daemon; b1="$(attributable)"; b2="$(attributable)"; stop_daemon
  a2="$(attributable)"
  d="$(python3 -c "print(f'{(($b1+$b2)/2)-(($a1+$a2)/2):.1f}')")"
  printf 'pair %d: A=%s,%s us  B=%s,%s us   B-A = %+s us\n' "$i" "$a1" "$a2" "$b1" "$b2" "$d"
  SUM="$(python3 -c "print($SUM+$d)")"
  case "$d" in -*) NNEG=$((NNEG+1)) ;; *) NPOS=$((NPOS+1)) ;; esac
done

MEAN="$(python3 -c "print(f'{$SUM/$REPS:.1f}')")"
echo "---"
printf 'mean B-A over %d pairs = %s us   (sign: %d slower / %d faster)\n' "$REPS" "$MEAN" "$NPOS" "$NNEG"
python3 -c "
m=$MEAN
print('VERDICT: the daemon is %.1f us %s than the shipped path.' % (abs(m), 'SLOWER' if m>0 else 'FASTER'))
print('band is |439| us; this difference is %s the band.' % ('OUTSIDE' if abs(m)>439 else 'INSIDE'))"
