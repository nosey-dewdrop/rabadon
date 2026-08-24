#!/usr/bin/env bash
# ab_day.sh — did the day-string cache actually move the median, or did the
# machine move under it?
#
# reports/R7/PROFIL-YARGILAMA.md is explicit that its own absolute medians are
# not trustworthy (1108 -> 3058 us across two runs of the same code) and that
# only the SHARES held. So a single accept.sh reading before and a single one
# after cannot settle whether the cache paid: the run-to-run spread is larger
# than the effect being claimed.
#
# This runs the SAME instrument accept.sh 2b uses (the R1.3 in-process probe,
# patched into a copy of the gate source under /tmp) against two gate sources,
# OLD and NEW, INTERLEAVED, in one sitting. Interleaving is the whole design:
# if the machine drifts, it drifts through both arms, and the paired difference
# survives what a before/after comparison cannot.
#
#   OLD = the tree at $BASE (default: the commit before the cache landed)
#   NEW = the working tree
#
# usage: bash reports/R7/ab_day.sh [rounds] [samples] [base-commit]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; cd "$ROOT"
ROUNDS="${1:-3}"; SAMPLES="${2:-300}"; BASE="${3:-12fb21f}"

W="$(mktemp -d /tmp/rabadon-abday.XXXXXX)"; trap 'rm -rf "$W"' EXIT
echo "ab_day: base=$BASE rounds=$ROUNDS samples=$SAMPLES workdir=$W"

# OLD tree: the two files the change touched, at $BASE, over a copy of today's
# headers. Only gate.cpp and gated.cpp differ between the arms — checked below.
mkdir -p "$W/old" "$W/new"
cp native/*.h "$W/old"/ && cp native/*.h "$W/new"/
git show "$BASE:native/gate.cpp"  >"$W/old/gate_src.cpp"  || exit 1
git show "$BASE:native/gated.cpp" >"$W/old/gated_src.cpp" || exit 1
cp native/gate.cpp  "$W/new/gate_src.cpp"
cp native/gated.cpp "$W/new/gated_src.cpp"
for h in gate.cpp; do cp "$W/old/gate_src.cpp" "$W/old/$h"; cp "$W/new/gate_src.cpp" "$W/new/$h"; done
echo "  differing files old vs new: $(diff -q "$W/old/gate_src.cpp" "$W/new/gate_src.cpp" >/dev/null || echo -n 'gate.cpp ')$(diff -q "$W/old/gated_src.cpp" "$W/new/gated_src.cpp" >/dev/null || echo -n 'gated.cpp')"

patch_probe() { # $1 = source in, $2 = out
python3 - "$1" "$2" <<'PY'
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
}

for arm in old new; do
  patch_probe "$W/$arm/gate_src.cpp" "$W/$arm/gate_probe.cpp" || { echo "patch failed ($arm)"; exit 1; }
  ${CXX:-c++} -std=c++17 -O2 -I "$W/$arm" -o "$W/$arm/gate-probe" "$W/$arm/gate_probe.cpp" 2>"$W/$arm.cc.log" \
    || { echo "probe build failed ($arm)"; tail -5 "$W/$arm.cc.log"; exit 1; }
  # the daemon is built UNPATCHED: it is the thing under test, not the ruler.
  ${CXX:-c++} -std=c++17 -O2 -I "$W/$arm" -o "$W/$arm/gated" "$W/$arm/gated_src.cpp" 2>>"$W/$arm.cc.log" \
    || { echo "daemon build failed ($arm)"; tail -5 "$W/$arm.cc.log"; exit 1; }
done
echo "  both arms built"

sock_bekle(){ local i=0; while [ "$i" -lt 100 ]; do [ -S "$1" ] && return 0; sleep 0.1 2>/dev/null || sleep 1; i=$((i+1)); done; [ -S "$1" ]; }
jstr(){ python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

run_arm() { # $1 = arm, $2 = round; prints the median
  local arm="$1" r="$2"
  local DH H PJ SOCK O EVX
  DH="$(mktemp -d "$W/dh.XXXXXX")"; H="$(mktemp -d "$W/h.XXXXXX")"; PJ="$(mktemp -d "$W/p.XXXXXX")"
  mkdir -p "$DH/.rabadon/spool" "$H/.rabadon/spool" "$PJ/.git"
  printf 'ref: refs/heads/main\n' >"$PJ/.git/HEAD"; : >"$H/.rabadon/enabled"; : >"$DH/.rabadon/enabled"
  SOCK="$W/s.$arm.$r.sock"; O="$W/med.$arm.$r"
  env HOME="$DH" RABADON_DIR="$DH/.rabadon" RABADON_GATED_SOCK="$SOCK" "$W/$arm/gated" >>"$W/gated.$arm.log" 2>&1 &
  local DPID=$!
  sock_bekle "$SOCK" || { echo "NODAEMON"; kill "$DPID" 2>/dev/null; return; }
  EVX="$(printf '{"hook_event_name":"PreToolUse","session_id":"speed","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' "$PJ" "$(jstr 'echo hello world')")"
  local i=0
  while [ "$i" -lt 60 ]; do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK" "$W/$arm/gate-probe" >/dev/null 2>&1; i=$((i+1)); done
  i=0
  while [ "$i" -lt "$SAMPLES" ]; do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK" RABADON_PROBE_OUT="$O" "$W/$arm/gate-probe" >/dev/null 2>&1; i=$((i+1)); done
  kill "$DPID" 2>/dev/null; wait "$DPID" 2>/dev/null
  python3 -c "
import statistics,sys,os
p=sys.argv[1]
v=[float(x) for x in open(p)] if os.path.exists(p) else []
print(f'{statistics.median(v):.1f}' if v else 'NONE')" "$O"
}

echo "  load before: $(uptime | sed 's/.*load average/load/')"
printf '\n%-6s %10s %10s %10s\n' round OLD_us NEW_us DELTA_us
r=1
OLDS=""; NEWS=""
while [ "$r" -le "$ROUNDS" ]; do
  # OLD first on odd rounds, NEW first on even: order is not a variable either.
  if [ $((r % 2)) -eq 1 ]; then O_MED="$(run_arm old "$r")"; N_MED="$(run_arm new "$r")"
  else                          N_MED="$(run_arm new "$r")"; O_MED="$(run_arm old "$r")"; fi
  D=$(python3 -c "
try: print('%.1f' % (float('$O_MED') - float('$N_MED')))
except Exception: print('?')")
  printf '%-6s %10s %10s %10s\n' "$r" "$O_MED" "$N_MED" "$D"
  OLDS="$OLDS $O_MED"; NEWS="$NEWS $N_MED"
  r=$((r+1))
done

echo
python3 -c "
import statistics as st, sys
o=[float(x) for x in '''$OLDS'''.split() if x not in ('NONE','?')]
n=[float(x) for x in '''$NEWS'''.split() if x not in ('NONE','?')]
if not o or not n:
    print('INCONCLUSIVE: an arm produced no samples'); sys.exit(0)
mo, mn = st.median(o), st.median(n)
print('OLD medians:', ' '.join('%.1f'%x for x in o))
print('NEW medians:', ' '.join('%.1f'%x for x in n))
print('median of medians: OLD %.1f us   NEW %.1f us' % (mo, mn))
d = mo - mn
print('paired deltas (OLD-NEW):', ' '.join('%.1f'%(a-b) for a,b in zip(o,n)))
print('DELTA %.1f us  (%.1f%% of OLD)' % (d, 100.0*d/mo if mo else 0))
print('every paired round favours NEW:', all(a>b for a,b in zip(o,n)))
"
echo "  load after: $(uptime | sed 's/.*load average/load/')"
