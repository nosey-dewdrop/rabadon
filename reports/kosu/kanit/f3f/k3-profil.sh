#!/usr/bin/env bash
# k3-profil.sh — WHICH LEG IS EXPENSIVE, measured before anything is optimised.
#
# The rule this obeys (F3f card, and the F3e arbiter's verdict): a decomposition
# whose legs sit inside the noise band may not choose a target. So no leg here is
# a difference between two populations. Every run reports, for ITSELF:
#
#   wall            fork+exec+dyld+staticinit+main+exit, timed by this script
#   pre_main        wall - (ctor->main) - (main->exit)   [kernel exec + dyld]
#   ctor_to_main    static initialisers
#   main_to_exit    rabadon's own logic — every rule, every file read
#
# The three inner numbers come from the binary's own monotonic clock in the same
# process the wall clock is timing, so the split is paired by construction.
# Reported as a median over N runs plus the min, because the min of a paired
# in-process number is the closest thing to a noise-free reading available here.
#
# usage: k3-profil.sh <gate-binary> [N]
set -u
GATE="${1:?usage: k3-profil.sh <gate-binary> [N]}"
N="${2:-120}"
[ -x "$GATE" ] || { echo "not executable: $GATE"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/rbprof.XXXXXX")"
trap 'rm -rf "$T"' EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"
P="$T/proj"; mkdir -p "$P/src" "$P/.git"
printf '{"name":"p","scripts":{"test":"node -e 0"}}' > "$P/package.json"
printf 'module.exports=1;\n' > "$P/src/a.js"
EV="$T/event.json"
printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"bench","tool_name":"Bash","tool_input":{"command":"git status --short"}}' "$P" > "$EV"
export RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_PROFILE=1

# same sanity gate as 2b-uctan-uca.sh: an event that is REFUSED runs a different
# amount of work, so a benchmark that silently drifts onto it is not the number.
"$GATE" < "$EV" >/dev/null 2>/dev/null
rc=$?
[ "$rc" = "0" ] || { echo "sanity failed: benchmarked event is not the allow path (exit $rc)"; exit 1; }
echo "sanity: benchmarked event is ALLOWED -> gate exit $rc"

"$GATE" < "$EV" >/dev/null 2>/dev/null   # warm

python3 - "$GATE" "$EV" "$N" <<'PY'
import subprocess, sys, time, statistics, os, re
gate, ev, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = open(ev, "rb").read()
rows = []
for _ in range(n):
    t0 = time.perf_counter_ns()
    p = subprocess.run([gate], input=data, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    t1 = time.perf_counter_ns()
    m = re.search(rb"ctor_to_main_us=([\d.]+) main_to_exit_us=([\d.]+)", p.stderr or b"")
    if not m:
        print("NO PROFILE OUTPUT — is this binary built with the probe?"); sys.exit(1)
    ctor_main = float(m.group(1)); main_exit = float(m.group(2))
    wall = (t1 - t0) / 1000.0
    rows.append((wall, wall - ctor_main - main_exit, ctor_main, main_exit))
def col(i): return [r[i] for r in rows]
names = ["wall (fork+exec+dyld+init+main)", "pre_main (kernel exec + dyld)",
         "ctor_to_main (static init)", "main_to_exit (rabadon's own logic)"]
print("N = %d" % n)
print("%-34s %10s %10s %10s" % ("leg", "median", "min", "p90"))
for i, nm in enumerate(names):
    c = sorted(col(i))
    print("%-34s %10.1f %10.1f %10.1f" % (nm, statistics.median(c), c[0], c[int(0.9 * (len(c) - 1))]))
w = statistics.median(col(0))
print()
for i in (1, 2, 3):
    print("%-34s %5.1f%% of wall" % (names[i], 100.0 * statistics.median(col(i)) / w))
PY
