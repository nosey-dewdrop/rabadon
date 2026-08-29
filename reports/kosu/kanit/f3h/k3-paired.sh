#!/usr/bin/env bash
# k3-paired.sh — the one difference from k3-911.sh that was worth pairing.
#
# k3-911.sh read accept.sh's `2b` arm at 1333.1 us and the SAME binary, SAME
# fixture, SAME daemon, with only RABADON_GATED_SOCK unset, at 879.4 us. That
# is the largest single factor in the unexplained gap, and it points the wrong
# way: the daemon exists to make the gate cheaper.
#
# A single median is not a claim. This runs the two arms INTERLEAVED, R paired
# rounds, so machine state is shared between them, and reports the per-round
# difference and its sign. The run's own noise band is |439 us| (DURUM.md), and
# a paired claim has to beat it AND be one-sided.
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"
GATED="$ROOT/native/rabadon-gated"
N="${N:-120}"; WARM="${WARM:-40}"; R="${R:-8}"

W="$(mktemp -d)"; trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$W"' EXIT
PROBE_DIR="$W/probe"; PGATE="$PROBE_DIR/rabadon-gate-probe"
mkdir -p "$PROBE_DIR" && cp native/*.h "$PROBE_DIR"/
python3 - native/gate.cpp "$PROBE_DIR/gate_probe.cpp" <<'PY'
import sys
src = open(sys.argv[1]).read()
PROBE = r'''
#include <chrono>
static std::chrono::steady_clock::time_point g_rbp_t0;
static void rbprobe_dump() {
  const char* p = getenv("RABADON_PROBE_OUT");
  if (!p || !*p) return;
  const double us = std::chrono::duration<double, std::micro>(
      std::chrono::steady_clock::now() - g_rbp_t0).count();
  char buf[64];
  const int n = snprintf(buf, sizeof buf, "%.1f\n", us);
  const int fd = open(p, O_WRONLY | O_APPEND | O_CREAT, 0644);
  if (fd < 0) return;
  ssize_t w = write(fd, buf, (size_t)n); (void)w;
  close(fd);
}
static void rbprobe_begin() { g_rbp_t0 = std::chrono::steady_clock::now(); atexit(rbprobe_dump); }
'''
a = "int main(int argc, char** argv) {"
assert src.count(a) == 1
open(sys.argv[2], "w").write(src.replace(a, PROBE + a + "\n  rbprobe_begin();"))
PY
${CXX:-c++} -std=c++17 -O2 -I "$PROBE_DIR" -o "$PGATE" "$PROBE_DIR/gate_probe.cpp" || exit 1

H="$(mktemp -d "$W/h.XXXXXX")"; PJ="$(mktemp -d "$W/p.XXXXXX")"
mkdir -p "$H/.rabadon/spool" "$PJ/.git"; printf 'ref: refs/heads/main\n' >"$PJ/.git/HEAD"; : >"$H/.rabadon/enabled"
DH="$(mktemp -d "$W/dh.XXXXXX")"; mkdir -p "$DH/.rabadon/spool"; : >"$DH/.rabadon/enabled"
SOCK="$W/gated.sock"
env HOME="$DH" RABADON_DIR="$DH/.rabadon" RABADON_GATED_SOCK="$SOCK" "$GATED" >"$W/gated.log" 2>&1 &
for _ in $(seq 100); do [ -S "$SOCK" ] && break; sleep 0.05; done
[ -S "$SOCK" ] || { echo "daemon did not come up — NOT MEASURED"; exit 2; }

EVX="$(python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"speed","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":"echo hello world"}}))' "$PJ")"
med() { python3 -c "
import statistics,sys
v=[float(x) for x in open(sys.argv[1])]
print(f'{statistics.median(v):.1f}')" "$1"; }

echo "k3-paired: RABADON_GATED_SOCK set vs unset, interleaved, R=$R rounds of N=$N"
echo ""
DIFFS=""
for r in $(seq "$R"); do
  OA="$W/a.$r"; OB="$W/b.$r"
  for _ in $(seq "$WARM"); do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK" "$PGATE" >/dev/null 2>&1; done
  for _ in $(seq "$N");    do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK" RABADON_PROBE_OUT="$OA" "$PGATE" >/dev/null 2>&1; done
  for _ in $(seq "$WARM"); do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$PGATE" >/dev/null 2>&1; done
  for _ in $(seq "$N");    do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_PROBE_OUT="$OB" "$PGATE" >/dev/null 2>&1; done
  A="$(med "$OA")"; B="$(med "$OB")"
  D="$(python3 -c "print(f'{float('$A')-float('$B'):.1f}')")"
  printf 'round %d   SOCK set %8s   SOCK unset %8s   diff %+8s us\n' "$r" "$A" "$B" "$D"
  DIFFS="$DIFFS $D"
done
echo ""
python3 -c "
import statistics,sys
d=[float(x) for x in sys.argv[1].split()]
print(f'paired diffs      : {d}')
print(f'median difference : {statistics.median(d):+.1f} us')
print(f'min / max         : {min(d):+.1f} / {max(d):+.1f} us')
print(f'one-sided         : {\"YES\" if all(x>0 for x in d) or all(x<0 for x in d) else \"NO\"}')
print(f'beats |439 us|    : {\"YES\" if abs(statistics.median(d))>439 else \"NO\"}')
" "$DIFFS"
