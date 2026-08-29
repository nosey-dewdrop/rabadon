#!/usr/bin/env bash
# k3-esli.sh — paired, alternating, end-to-end. Two binaries and the empty
# baseline are timed in the SAME interleaved sweep, so a machine that drifts
# drifts through all three equally.
#
# The band this has to clear was set by the F3e arbiter's A/A run: a paired
# claim must exceed |439 us| AND be one-sided across repeats. Anything under
# that is noise, and three phases already published a fake descending series by
# ignoring it. Repeats and the sign test are printed whatever they say.
#
# usage: k3-esli.sh <gate-A> <gate-B> [N] [REPEATS]
set -u
A="${1:?usage: k3-esli.sh <gate-A> <gate-B> [N] [REPEATS]}"
B="${2:?}"; N="${3:-200}"; R="${4:-5}"
for g in "$A" "$B"; do [ -x "$g" ] || { echo "not executable: $g"; exit 1; }; done

T="$(mktemp -d "${TMPDIR:-/tmp}/rb2bp.XXXXXX")"
trap 'rm -rf "$T"' EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"
P="$T/proj"; mkdir -p "$P/src" "$P/.git"
printf '{"name":"p","scripts":{"test":"node -e 0"}}' > "$P/package.json"
printf 'module.exports=1;\n' > "$P/src/a.js"
EV="$T/event.json"
printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"bench","tool_name":"Bash","tool_input":{"command":"git status --short"}}' "$P" > "$EV"
export RABADON_DIR="$RD" RABADON_JUDGE=0
unset RABADON_PROFILE

for g in "$A" "$B"; do
  "$g" < "$EV" >/dev/null 2>&1
  rc=$?
  [ "$rc" = "0" ] || { echo "sanity failed: $g exits $rc on the benchmarked event, not the allow path"; exit 1; }
done
echo "sanity: both binaries take the ALLOW path (exit 0) on the benchmarked event"

python3 - "$A" "$B" "$EV" "$N" "$R" <<'PY'
import subprocess, sys, time, statistics
a, b, ev, n, reps = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
data = open(ev, "rb").read()
def sweep(cmd):
    t0 = time.perf_counter_ns()
    for _ in range(n):
        subprocess.run([cmd], input=data, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return (time.perf_counter_ns() - t0) / 1000.0 / n
for c in (a, b, "/usr/bin/true"): sweep(c)          # warm all three
diffs, rowsA, rowsB, rowsE = [], [], [], []
for r in range(reps):
    # alternate the order every repeat so a warming trend cannot favour one side
    order = (a, b, "/usr/bin/true") if r % 2 == 0 else ("/usr/bin/true", b, a)
    res = {c: sweep(c) for c in order}
    rowsA.append(res[a]); rowsB.append(res[b]); rowsE.append(res["/usr/bin/true"])
    diffs.append(res[b] - res[a])
    print("  rep %d: A=%8.1f  B=%8.1f  empty=%8.1f  B-A=%+8.1f us" % (r + 1, res[a], res[b], res["/usr/bin/true"], res[b] - res[a]))
mA, mB, mE = statistics.median(rowsA), statistics.median(rowsB), statistics.median(rowsE)
plus = sum(1 for d in diffs if d > 0); minus = len(diffs) - plus
print()
print("A (%s)" % a)
print("B (%s)" % b)
print("A end-to-end median            = %8.1f us   attributable = %8.1f us" % (mA, mA - mE))
print("B end-to-end median            = %8.1f us   attributable = %8.1f us" % (mB, mB - mE))
print("empty baseline median          = %8.1f us" % mE)
print("paired B-A mean                = %+8.1f us   sign %d+/%d-" % (statistics.mean(diffs), plus, minus))
print("noise band (F3e arbiter, A/A)  =   439.0 us, and the sign must be one-sided")
band = abs(statistics.mean(diffs)) > 439.0 and (plus == 0 or minus == 0)
print("VERDICT                        = %s" % ("a real change" if band else "INSIDE THE NOISE BAND — no claim may be made"))
print("ceiling                        =  1000.0 us   (untouched)")
PY
