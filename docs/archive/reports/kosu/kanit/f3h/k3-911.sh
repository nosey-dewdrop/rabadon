#!/usr/bin/env bash
# k3-911.sh — WHERE DOES THE 911 us GO? MEASURE IT, DO NOT BLAME A LEG.
#
# The F3g verdict left one number standing and unexplained: the shipped
# binary's leg 3 (main -> exit) profiled at 1031.5 us, while reports/R7/
# accept.sh's `2b` probe — which starts at the first line of main() and dumps at
# atexit, i.e. THE SAME LEG — read 1942.8 us. Same -O2. 911 us with no owner.
#
# Four phases have each blamed a different leg and the arbiter refuted all four.
# So this script blames nothing. It rebuilds accept.sh's own instrument, then
# removes ONE factor at a time from accept.sh's environment and reads the
# median again. Whatever moves is where the 911 us lives.
#
# accept.sh is NOT touched, NOT sourced, and NOT re-run. Its probe recipe is
# reproduced here (native/gate.cpp copied, the probe injected at the main()
# anchor, built with -O2) so the two numbers are comparable by construction.
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"
GATE="$ROOT/native/rabadon-gate"
GATED="$ROOT/native/rabadon-gated"
N="${N:-300}"; WARM="${WARM:-60}"

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
assert src.count(a) == 1, "main() anchor is not unique"
open(sys.argv[2], "w").write(src.replace(a, PROBE + a + "\n  rbprobe_begin();"))
PY
${CXX:-c++} -std=c++17 -O2 -I "$PROBE_DIR" -o "$PGATE" "$PROBE_DIR/gate_probe.cpp" || exit 1

sb() { H="$(mktemp -d "$W/h.XXXXXX")"; PJ="$(mktemp -d "$W/p.XXXXXX")"
  mkdir -p "$H/.rabadon/spool" "$PJ/.git"; printf 'ref: refs/heads/main\n' >"$PJ/.git/HEAD"
  : >"$H/.rabadon/enabled"; }
jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

med() { python3 -c "
import statistics,sys,os
p=sys.argv[1]
v=[float(x) for x in open(p)] if os.path.exists(p) else []
print(f'{statistics.median(v):.1f}' if v else 'NONE')" "$1"; }

# run <label> <extra-env...> -- reads $EVX, $H, $PJ
run() {
  local label="$1"; shift
  local out="$W/o.$RANDOM"
  for _ in $(seq "$WARM"); do printf '%s' "$EVX" | env "$@" "$PGATE" >/dev/null 2>&1; done
  for _ in $(seq "$N");    do printf '%s' "$EVX" | env "$@" RABADON_PROBE_OUT="$out" "$PGATE" >/dev/null 2>&1; done
  printf '%-52s %s us\n' "$label" "$(med "$out")"
}

echo "k3: where the 911 us goes — median over $N samples, $WARM warm, in-process probe"
echo ""

# --- A. accept.sh's exact environment: daemon up, socket exported ------------
SOCK="$W/gated.sock"
sb; DH="$H"
env HOME="$DH" RABADON_DIR="$DH/.rabadon" RABADON_GATED_SOCK="$SOCK" "$GATED" >"$W/gated.log" 2>&1 &
for _ in $(seq 100); do [ -S "$SOCK" ] && break; sleep 0.05; done
[ -S "$SOCK" ] && echo "daemon: up at $SOCK" || echo "daemon: NOT UP — arm A is not accept.sh's arm"
sb; EVX="$(printf '{"hook_event_name":"PreToolUse","session_id":"speed","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' "$PJ" "$(jstr 'echo hello world')")"

run "A  accept.sh's arm: daemon up, SOCK exported" HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK"
run "B  same, SOCK unset (daemon still running)"   HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0
run "C  SOCK pointing at a socket nobody listens on" HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$W/dead.sock"

kill %1 2>/dev/null; wait 2>/dev/null
run "D  daemon DOWN, SOCK unset"                   HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0
run "E  daemon DOWN, SOCK exported (stale path)"   HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK"

# --- F. the project this session actually guards, not a bare fixture ---------
EVR="$(printf '{"hook_event_name":"PreToolUse","session_id":"speed","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' "$ROOT" "$(jstr 'echo hello world')")"
EVX="$EVR"
run "F  same as D but cwd = the rabadon repo itself" HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0
