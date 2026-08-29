#!/usr/bin/env bash
# 6-2b-profil.sh — where does the shipped gate's per-event cost go?
#
# Same harness and same definition as reports/kosu/kanit/f3/2b-uctan-uca.sh
# (mean over N, attributable = raw - /usr/bin/true), run once per switch so the
# arms are comparable to each other. Switches only: no code is modified, so
# every number here describes the binary that actually ships.
set -u
GATE="${1:?usage: 6-2b-profil.sh <gate-binary> [N]}"
N="${2:-300}"

T="$(mktemp -d "${TMPDIR:-/tmp}/rb2bp.XXXXXX")"
trap 'rm -rf "$T"' EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"
P="$T/proj"; mkdir -p "$P/src" "$P/.git"
printf '{"name":"p","scripts":{"test":"node -e 0"}}' > "$P/package.json"
printf 'module.exports=1;\n' > "$P/src/a.js"
EV="$T/event.json"
printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"bench","tool_name":"Bash","tool_input":{"command":"git status --short"}}' "$P" > "$EV"
export RABADON_DIR="$RD" RABADON_JUDGE=0

loop() { # loop <cmd> [env...] -> mean us per call
  local c="$1"; shift
  local s e i=0
  s=$(python3 -c 'import time;print(time.perf_counter_ns())')
  while [ "$i" -lt "$N" ]; do env "$@" "$c" < "$EV" >/dev/null 2>&1; i=$((i+1)); done
  e=$(python3 -c 'import time;print(time.perf_counter_ns())')
  python3 -c "print(f'{($e-$s)/1000/$N:.1f}')"
}

"$GATE" < "$EV" >/dev/null 2>&1
/usr/bin/true < "$EV" >/dev/null 2>&1

BASE="$(loop /usr/bin/true)"
echo "N=$N   empty baseline (env + /usr/bin/true) = $BASE us"
echo
row() { # row <label> [env...]
  local label="$1"; shift
  local raw; raw="$(loop "$GATE" "$@")"
  python3 -c "print(f'{\"$label\":38s} raw {$raw:8.1f}   attributable {$raw-$BASE:8.1f} us')"
}
row "everything on (what ships)"
row "detectors off"        RABADON_SIGNALS=0
row "injection off"        RABADON_INJECT=0
row "detectors+injection off" RABADON_SIGNALS=0 RABADON_INJECT=0
row "gate switched off entirely" RABADON_OFF=1
