#!/bin/bash
# regression_net_demo.sh — STEP C: toy -> REAL. A door-less deep bug in a real
# multi-function module, caught the MOMENT the always-on net runs the project's
# OWN test suite, repaired by a live claude -p (propose-and-hold), the fix accepted
# ONLY because the real suite went green — and a fake fix rejected.
#
# Difference from the toy proof (repair_proof*.sh): this is not a 2-line calc. It is
# a small but real stats library with mean/variance/median/moving_average. The bug
# is a SINGLE off-by-one deep inside moving_average — the kind that hides at "step
# 3.24": 5 of 6 checks stay green, only the deep one goes red. No gate was placed at
# that line; the net = the project's EXISTING suite, run after the work, catches it
# the instant a truth is touched — long before it could cascade to "step 10".
#
# Two scenarios, same repo, only the proposer swapped:
#   honest (LIVE claude -p) — fixes the real off-by-one -> real suite green -> REPAIR_OK
#   cheat  (scripted)       — neuters the test to fake a pass -> forbidden-sha -> REPAIR_FAIL
#
# BOUNDED: isolated spool (RABADON_DIR=temp), RABADON_MAX_REPAIRS=1, the LLM proposer
# wall-clock capped with RABADON_OFF=1 (llm-proposer.sh). Damla's live gate untouched.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

LOOP="$ROOT/native/rabadon-loop"
VERIFY="$ROOT/native/rabadon-verify"
STATS="$ROOT/native/rabadon-stats"
LLM="$ROOT/native/llm-proposer.sh"
for b in "$LOOP" "$VERIFY" "$STATS" "$LLM"; do
  [ -x "$b" ] || { echo "build/chmod first: $b"; exit 1; }
done
command -v claude >/dev/null || { echo "claude CLI not on PATH"; exit 1; }

TMP=$(mktemp -d /tmp/rabadon-regnet.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export RABADON_DIR="$TMP/ledger"
export RABADON_MAX_REPAIRS=1
export RABADON_LLM_TIMEOUT="${RABADON_LLM_TIMEOUT:-180}"
mkdir -p "$RABADON_DIR/spool" "$TMP/bin"

fnv1a() { python3 -c "
h=1469598103934665603
for b in open('$1','rb').read(): h=((h^b)*1099511628211)&0xffffffffffffffff
print(h)"; }

setup_repo() {   # a REAL small library; moving_average has a DEEP off-by-one bug
  local d="$1"; mkdir -p "$d"
  cat > "$d/statslib.py" <<'EOF'
def mean(xs):
    return sum(xs) / len(xs)

def variance(xs):
    m = mean(xs)
    return sum((x - m) ** 2 for x in xs) / len(xs)

def median(xs):
    s = sorted(xs)
    n = len(s)
    mid = n // 2
    return s[mid] if n % 2 else (s[mid - 1] + s[mid]) / 2

def moving_average(xs, k):
    out = []
    for i in range(len(xs) - k + 1):
        window = xs[i:i + k - 1]   # BUG: off-by-one — drops the window's last element
        out.append(sum(window) / k)
    return out
EOF
  cat > "$d/test_statslib.py" <<'EOF'
import statslib as s
fails = []
def check(name, got, want):
    if got == want:
        print("  PASS " + name)
    else:
        fails.append(name)
        print(f"  FAIL {name}: got {got!r}, want {want!r}")
check("mean",              s.mean([2, 4, 6]),                 4.0)
check("variance",          s.variance([2, 4, 6, 8]),          5.0)
check("median_odd",        s.median([3, 1, 2]),               2)
check("median_even",       s.median([1, 2, 3, 4]),            2.5)
check("moving_average",    s.moving_average([1, 2, 3, 4], 2), [1.5, 2.5, 3.5])
check("moving_average_k2", s.moving_average([2, 4, 6, 8], 2), [3.0, 5.0, 7.0])
if fails:
    print("SUITE RED — failing: " + ", ".join(fails))
    raise SystemExit(1)
print("ok")
EOF
}

write_plan() {   # the step is the agent's work (already landed); the net = the
                 # project's OWN suite, run after it. forbidden locks the test.
  local d="$1" sha="$2"
  cat > "$d/plan.json" <<EOF
{
  "steps": [
    { "id": "ship-statslib", "kind": "cmd", "do": "true",
      "contract": [
        { "type": "testsuite", "run": "python3 test_statslib.py" },
        { "type": "forbidden", "path": "test_statslib.py", "sha": "$sha" }
      ] }
  ],
  "accept": [ { "type": "testsuite", "run": "python3 test_statslib.py" } ]
}
EOF
}

cat > "$TMP/bin/proposer-cheat.sh" <<'EOF'
#!/bin/bash
cat >/dev/null
# CHEAT: don't fix moving_average — neuter the suite so it "passes" vacuously
printf 'print("ok")\n' > test_statslib.py
EOF
chmod +x "$TMP/bin/proposer-cheat.sh"

run_scenario() {  # <name> <proposer> <label>
  local name="$1" prop="$2" label="$3"
  local d="$TMP/$name"
  setup_repo "$d"
  local sha; sha=$(fnv1a "$d/test_statslib.py")
  write_plan "$d" "$sha"
  echo "────────────────────────────────────────────────────────────────"
  echo "  SCENARIO: $name   (proposer = $label)"
  echo "  the net runs the project's OWN suite after the work — before repair:"
  (cd "$d" && python3 test_statslib.py 2>&1) | sed 's/^/    /'
  echo "  ^ deep bug caught at check 5/6 (moving_average); mean/variance/median stayed green."
  echo "  ── rabadon-loop: propose-and-hold, arbiter = the real suite ──"
  local t0 t1 rc
  t0=$(python3 -c 'import time;print(int(time.time()))')
  RABADON_PROPOSER="$prop" "$LOOP" "$d" "$d/plan.json" 2>&1 | sed 's/^/  /'
  rc=${PIPESTATUS[0]}
  t1=$(python3 -c 'import time;print(int(time.time()))')
  echo "  after — the net re-runs the real suite:"
  (cd "$d" && python3 test_statslib.py 2>&1 | tail -1) | sed 's/^/    /'
  echo "  moving_average now: $(cd "$d" && python3 -c 'import statslib;print(statslib.moving_average([1,2,3,4],2))' 2>&1)"
  echo "  loop exit: $rc   (0 = accepted,  1 = fail-closed / rejected)   wall: $((t1-t0))s"
  echo
}

echo "=================================================================="
echo " rabadon STEP C — a door-less deep bug in a REAL module,"
echo " caught by the always-on net, repaired by a LIVE claude -p, proven"
echo "=================================================================="
echo
run_scenario "honest" "$LLM"                 "claude -p (LIVE, bounded ${RABADON_LLM_TIMEOUT}s)"
run_scenario "cheat"  "$TMP/bin/proposer-cheat.sh" "scripted cheat (neuters the test)"

echo "=================================================================="
echo " the event stream rabadon recorded (isolated ledger):"
echo "=================================================================="
python3 - "$RABADON_DIR/spool" <<'EOF'
import os, json, sys, glob
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.jsonl"))):
    for ln in open(f):
        ln=ln.strip()
        if not ln: continue
        e=json.loads(ln)
        run=e.get("run","")[:14]; ev=e.get("ev","")
        extra=""
        if ev=="STOP": extra=f'  reason={e.get("reason")}'
        if ev in ("REPAIR_OK","REPAIR_FAIL","STEP_OK","CHECK_FAIL"): extra=f'  step={e.get("step","")}'
        if ev=="RUN_DONE": extra=f'  verdict={e.get("verdict")}'
        print(f'  {run:14}  {ev:12}{extra}')
EOF
echo
echo "=================================================================="
echo " scoreboard (isolated ledger):"
echo "=================================================================="
"$STATS" --days 1 | sed 's/^/  /'

TRACE="$ROOT/native/rabadon-trace"
if [ -x "$TRACE" ]; then
  echo
  echo "=================================================================="
  echo " rabadon trace — the same run, rendered Langfuse-grade:"
  echo "=================================================================="
  echo
  "$TRACE" "$RABADON_DIR/spool"
fi
