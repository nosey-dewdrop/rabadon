#!/usr/bin/env bash
# k3-daemon.sh — WHERE DOES THE DAEMON ROUND TRIP GO?
#
# The F3h arbiter measured, over eight paired rounds, 8/8 one-sided: with the
# daemon up and RABADON_GATED_SOCK exported, accept.sh's own in-process probe
# reads +530.4 us MORE than with the daemon down. That beats the |439 us| noise
# band, so for the first time in six phases there is a leg that can be chased.
#
# Five phases have each blamed a different leg from the armchair and all five
# were refuted. This script blames nothing; it splits the round trip with a
# clock inside a COPY of gated_client.h and reports what each segment costs:
#
#   connect  socket() + connect()
#   send     sendmsg with the fd's + the whole environment + the event
#   wait     read() of the one verdict byte -- the daemon forking a worker, the
#            worker judging the event, and the worker exiting
#   close    close(fd)
#
# THE SEGMENT CLOCK IS NOT FREE: it appends to a file five times per call, and
# that write lands inside the region accept.sh's probe is timing. So the run is
# done twice on purpose -- arm A/D CLEAN gives the magnitude, arm S gives the
# split, and the difference between A and S is printed rather than hidden, so
# nobody quotes the instrumented total as the product's number.
#
# native/gated_client.h and reports/R7/accept.sh are NOT touched. The probe is
# injected at the same main() anchor accept.sh uses, built with the same -O2.
#
# usage: N=200 ROUNDS=8 bash reports/kosu/kanit/f3i/k3-daemon.sh
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"
GATED="$ROOT/native/rabadon-gated"
N="${N:-200}"; WARM="${WARM:-60}"; ROUNDS="${ROUNDS:-8}"
[ -x "$GATED" ] || { echo "build first: make native/rabadon-gated"; exit 1; }

W="$(mktemp -d "$HOME/.rb-f3i-k3.XXXXXX")"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$W"' EXIT

build_probe() { # build_probe <outdir> <with-seg:0|1>
  local PD="$1" SEG="$2"
  mkdir -p "$PD"; cp native/*.h "$PD"/
  if [ "$SEG" = 1 ]; then
    python3 - "$PD/gated_client.h" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('#include <string>', '#include <string>\n#include <chrono>\n#include <fcntl.h>\n'
  'static inline double rbnow(){using namespace std::chrono;'
  'return duration<double,std::micro>(steady_clock::now().time_since_epoch()).count();}\n'
  'static inline void rbseg(const char* k,double us){const char* p=getenv("RABADON_SEG_OUT");'
  'if(!p||!*p)return;char b[128];int n=snprintf(b,sizeof b,"%s %.1f\\n",k,us);'
  'int fd=open(p,O_WRONLY|O_APPEND|O_CREAT,0644);if(fd<0)return;ssize_t w=write(fd,b,(size_t)n);(void)w;close(fd);}\n', 1)
s = s.replace('  const int fd = socket(AF_UNIX, SOCK_STREAM, 0);',
              '  const double t_a = rbnow();\n  const int fd = socket(AF_UNIX, SOCK_STREAM, 0);', 1)
s = s.replace('  ssize_t sent = sendmsg(fd, &msg, 0);',
              '  const double t_b = rbnow(); rbseg("connect", t_b - t_a);\n  ssize_t sent = sendmsg(fd, &msg, 0);', 1)
s = s.replace('  unsigned char code = 0;\n  const ssize_t got = read(fd, &code, 1);\n  close(fd);',
              '  const double t_c = rbnow(); rbseg("send", t_c - t_b);\n'
              '  unsigned char code = 0;\n  const ssize_t got = read(fd, &code, 1);\n'
              '  const double t_d = rbnow(); rbseg("wait", t_d - t_c);\n'
              '  close(fd);\n  rbseg("close", rbnow() - t_d);\n  rbseg("trip", rbnow() - t_a);', 1)
open(p, 'w').write(s)
PY
  fi
  python3 - native/gate.cpp "$PD/gate_probe.cpp" <<'PY'
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
assert src.count(a) == 1, "main() anchor is not unique"
open(sys.argv[2], "w").write(src.replace(a, PROBE + a + "\n  rbprobe_begin();"))
PY
  ${CXX:-c++} -std=c++17 -O2 -I "$PD" -o "$PD/gate-probe" "$PD/gate_probe.cpp" || exit 1
}

build_probe "$W/plain" 0
build_probe "$W/seg"   1
CLEAN="$W/plain/gate-probe"; SEGB="$W/seg/gate-probe"

H="$W/h"; mkdir -p "$H/.rabadon/spool"; : > "$H/.rabadon/enabled"
PJ="$W/proj"; mkdir -p "$PJ/.git"; printf 'ref: refs/heads/main\n' > "$PJ/.git/HEAD"
EV="$(python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"speed","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":"echo hello world"}}))' "$PJ")"

med() { python3 -c "
import statistics,sys,os
v=[float(x) for x in open(sys.argv[1])] if os.path.exists(sys.argv[1]) else []
print(f'{statistics.median(v):.1f}' if v else 'NONE')" "$1"; }

fire() { # fire <binary> <out> <n> [extra env...]
  local B="$1" OUT="$2" C="$3"; shift 3
  local i=0
  while [ "$i" -lt "$C" ]; do
    printf '%s' "$EV" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 \
      RABADON_PROBE_OUT="$OUT" "$@" "$B" >/dev/null 2>&1
    i=$((i+1))
  done
}
warm() { local B="$1"; shift; local i=0
  while [ "$i" -lt "$WARM" ]; do printf '%s' "$EV" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$@" "$B" >/dev/null 2>&1; i=$((i+1)); done; }

SOCK="$W/g.sock"
up_daemon() {
  env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_GATED_SOCK="$SOCK" "$GATED" > "$W/gated.log" 2>&1 &
  local i=0; while [ "$i" -lt 100 ]; do [ -S "$SOCK" ] && return 0; sleep 0.05; i=$((i+1)); done; return 1
}
down_daemon() { kill %1 2>/dev/null; wait 2>/dev/null; rm -f "$SOCK"; }

echo "k3-daemon: N=$N per arm, $ROUNDS paired rounds, warm=$WARM, -O2, accept.sh's probe recipe"
echo ""

# ---------------------------------------------------------------------------
# 1. PAIRED ROUNDS, CLEAN BINARY. Magnitude and sign, alternating within each
#    round so a machine that warms up or throttles cannot produce the sign.
echo "--- 1. paired rounds, no segment clock (magnitude + sign test)"
POS=0; NEG=0; DELTAS=""
r=1
while [ "$r" -le "$ROUNDS" ]; do
  up_daemon || { echo "daemon did not come up"; exit 1; }
  U="$W/up.$r"; warm "$CLEAN" RABADON_GATED_SOCK="$SOCK"; fire "$CLEAN" "$U" "$N" RABADON_GATED_SOCK="$SOCK"
  down_daemon
  D="$W/dn.$r"; warm "$CLEAN"; fire "$CLEAN" "$D" "$N"
  MU="$(med "$U")"; MD="$(med "$D")"
  DL="$(python3 -c "print(f'{$MU-$MD:+.1f}')")"
  case "$DL" in +*) POS=$((POS+1)) ;; *) NEG=$((NEG+1)) ;; esac
  DELTAS="$DELTAS $DL"
  printf '  round %d   daemon UP %8s us   DOWN %8s us   delta %s us\n' "$r" "$MU" "$MD" "$DL"
  r=$((r+1))
done
echo "  sign test: $POS rounds slower with the daemon, $NEG faster (out of $ROUNDS)"
python3 -c "
import statistics
d=[float(x) for x in '''$DELTAS'''.split()]
print(f'  median delta = {statistics.median(d):+.1f} us   mean = {statistics.mean(d):+.1f} us   band = |439| us')
print('  VERDICT: the daemon COSTS leg 3 time, one-sided, outside the band' if min(d)>0 and abs(statistics.median(d))>439 else
      '  VERDICT: inside the band or not one-sided -- no claim')"

# ---------------------------------------------------------------------------
# 2. THE SPLIT. Instrumented binary, daemon up. The totals here are INFLATED by
#    the five appends the segment clock itself does; that inflation is printed.
echo ""
echo "--- 2. the split (instrumented binary -- totals inflated on purpose, see header)"
up_daemon || { echo "daemon did not come up"; exit 1; }
SU="$W/segup.us"; SEGF="$W/seg.txt"
warm "$SEGB" RABADON_GATED_SOCK="$SOCK"
i=0; while [ "$i" -lt "$N" ]; do
  printf '%s' "$EV" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 \
    RABADON_GATED_SOCK="$SOCK" RABADON_PROBE_OUT="$SU" RABADON_SEG_OUT="$SEGF" "$SEGB" >/dev/null 2>&1
  i=$((i+1))
done
CU="$W/cleanup.us"; warm "$CLEAN" RABADON_GATED_SOCK="$SOCK"; fire "$CLEAN" "$CU" "$N" RABADON_GATED_SOCK="$SOCK"
down_daemon
python3 - "$SEGF" "$SU" "$CU" <<'PY'
import statistics,sys
seg={}
for l in open(sys.argv[1]):
    k,v=l.split(); seg.setdefault(k,[]).append(float(v))
trip=statistics.median(seg['trip'])
for k in ('connect','send','wait','close'):
    v=statistics.median(seg[k])
    print(f"  {k:<10} {v:8.1f} us   {100*v/trip:5.1f}% of the round trip   (n={len(seg[k])})")
print(f"  {'ROUND TRIP':<10} {trip:8.1f} us  100.0%")
si=statistics.median([float(x) for x in open(sys.argv[2])])
ci=statistics.median([float(x) for x in open(sys.argv[3])])
print(f"\n  instrumented leg 3 {si:.1f} us vs clean leg 3 {ci:.1f} us -> the segment clock itself costs {si-ci:+.1f} us")
print(f"  so the round trip in the CLEAN binary is at most {trip-(si-ci):.1f} us")
PY
