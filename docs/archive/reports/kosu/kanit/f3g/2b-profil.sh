#!/usr/bin/env bash
# 2b-profil.sh — WHICH LEG, MEASURED. Not guessed.
#
# Three phases in a row blamed a different leg of the gate's end-to-end cost and
# all three were struck down: F3d said process start was 60%, F3e said the rule
# path was 70%, F3f's own reading came back inside the noise band. The rule for
# this card is therefore: no leg may be blamed without a profile that shows its
# microseconds, and the split has to be taken WITHIN one run so no leg is the
# difference of two populations measured at different moments (that method
# produced 524.6 / 676.4 / 915.2 us for the SAME leg on three runs).
#
# gate.cpp already carries that split behind RABADON_PROFILE=1:
#   ctor_to_main   static initialization
#   main_to_exit   every line rabadon runs: state, guard, rules, laws, ledger
#   wall - both    kernel exec + dyld + the shared library images, this run
#
# This harness runs N real PreToolUse events on the ALLOW path, one process per
# event exactly as a hook does, and prints the median of each leg.
set -u
GATE="${1:?usage: 2b-profil.sh <gate-binary> [N]}"
N="${2:-200}"
[ -x "$GATE" ] || { echo "not executable: $GATE"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/rb2bp.XXXXXX")"
trap 'rm -rf "$T"' EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"
P="$T/proj"; mkdir -p "$P/src" "$P/.git"
printf '{"name":"p","scripts":{"test":"node -e 0"}}' > "$P/package.json"
printf 'module.exports=1;\n' > "$P/src/a.js"
EV="$T/event.json"
printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"prof","tool_name":"Bash","tool_input":{"command":"git status --short"}}' "$P" > "$EV"

export RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_PROFILE=1
"$GATE" < "$EV" >/dev/null 2>/dev/null
rc=$?
[ "$rc" = "0" ] || { echo "sanity failed: not the allow path (exit $rc)"; exit 1; }

OUT="$T/prof.tsv"
: > "$OUT"
i=0
while [ "$i" -lt "$N" ]; do
  python3 - "$GATE" "$EV" >> "$OUT" <<'PY'
import subprocess, sys, time, re
gate, ev = sys.argv[1], sys.argv[2]
data = open(ev, 'rb').read()
t0 = time.perf_counter_ns()
p = subprocess.run([gate], input=data, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
t1 = time.perf_counter_ns()
m = re.search(rb'ctor_to_main_us=([0-9.]+) main_to_exit_us=([0-9.]+)', p.stderr)
if m:
    ctor, mainx = float(m.group(1)), float(m.group(2))
    print(f"{(t1-t0)/1000.0:.1f}\t{ctor:.1f}\t{mainx:.1f}")
PY
  i=$((i+1))
done

python3 - "$OUT" "$N" <<'PY'
import sys, statistics
rows = [tuple(float(x) for x in l.split('\t')) for l in open(sys.argv[1]) if l.strip()]
if not rows:
    print("no samples"); sys.exit(1)
wall = [r[0] for r in rows]; ctor = [r[1] for r in rows]; mainx = [r[2] for r in rows]
pre  = [w - c - m for w, c, m in rows]          # paired, within the same run
med = statistics.median
tot = med(wall)
print(f"samples                                   = {len(rows)} (asked for {sys.argv[2]})")
print(f"wall, one gate process (python harness)   = {tot:.1f} us   100.0%")
print(f"  leg 1  exec + dyld + images, PRE-MAIN   = {med(pre):.1f} us   {100*med(pre)/tot:5.1f}%")
print(f"  leg 2  static initialization            = {med(ctor):.1f} us   {100*med(ctor)/tot:5.1f}%")
print(f"  leg 3  rabadon's OWN logic, main->exit  = {med(mainx):.1f} us   {100*med(mainx)/tot:5.1f}%")
print(f"legs 1+2 (nothing rabadon's code does)    = {med(pre)+med(ctor):.1f} us   {100*(med(pre)+med(ctor))/tot:5.1f}%")
PY
