#!/bin/bash
# trace_demo.sh — STEP D proof: the Langfuse-grade fused trace, on a REAL run.
#
# A 5-step pipeline where the bug is buried in the MIDDLE (step 3), exactly the
# vision: "10 adımlık iş, bela 3. adımın 3.24'ünde, kapı olmayan ufacık derin bir
# yer." Steps 1,2 do real work and pass. Step 3 ships a stats library whose
# moving_average has a door-less off-by-one — no gate was placed at that line; the
# net = the project's OWN suite, run after the work, catches it the instant a
# truth is touched. A live claude -p repairs it (propose-and-hold), the fix is
# accepted ONLY because the real suite goes green, and step 4 (which DEPENDS on
# moving_average being correct) then runs on a clean base. Step 5 publishes.
#
# Two scenarios, same pipeline, only the proposer swapped:
#   honest — live claude -p fixes the off-by-one -> real suite green -> steps 4,5 run
#   cheat  — scripted neuter of the test -> forbidden-sha -> REPAIR_FAIL -> STOP at
#            step 3 -> steps 4,5 NEVER run on a broken base (param cepte)
#
# The point of this file is the LAST command: rabadon-trace renders each run's
# isolated spool into the nested catch/fix/proof/cost trace. Every number in it
# already exists in the ledger — remove the LLM and the renderer still draws the
# same tree. BOUNDED: isolated spool, RABADON_MAX_REPAIRS=1, one live claude -p.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

LOOP="$ROOT/native/rabadon-pipeline"
VERIFY="$ROOT/native/rabadon-verify"
LLM="$ROOT/native/llm-proposer.sh"
TRACE="$ROOT/native/rabadon-trace"
for b in "$LOOP" "$VERIFY" "$LLM" "$TRACE"; do
  [ -x "$b" ] || { echo "build first: $b   (run: make)"; exit 1; }
done
command -v claude >/dev/null || { echo "claude CLI not on PATH"; exit 1; }

TMP=$(mktemp -d /tmp/rabadon-trace-demo.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export RABADON_DIR="$TMP/ledger"
export RABADON_MAX_REPAIRS=1
export RABADON_LLM_TIMEOUT="${RABADON_LLM_TIMEOUT:-180}"
mkdir -p "$RABADON_DIR/spool"

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

write_plan() {   # 5 steps; the bug is at step 3, downstream step 4 depends on it
  local d="$1" sha="$2"
  cat > "$d/plan.json" <<EOF
{
  "goal": "ship the analytics rollup — validate, index, stats, report, publish",
  "steps": [
    { "id": "validate-input", "kind": "cmd", "do": "printf 'a,b\\n1,2\\n' > data.csv",
      "contract": [ { "type": "fileExists", "path": "data.csv" } ] },

    { "id": "build-index", "kind": "cmd", "do": "printf 'idx\\n' > index.txt",
      "contract": [ { "type": "fileExists", "path": "index.txt" } ] },

    { "id": "ship-statslib", "kind": "cmd", "do": "true",
      "contract": [
        { "type": "testsuite", "run": "python3 test_statslib.py" },
        { "type": "forbidden", "path": "test_statslib.py", "sha": "$sha" }
      ] },

    { "id": "emit-report", "kind": "cmd",
      "do": "python3 -c 'import statslib,json; open(\"report.json\",\"w\").write(json.dumps(statslib.moving_average([1,2,3,4],2)))'",
      "contract": [
        { "type": "cmd", "run": "cat report.json", "passPattern": "[1.5, 2.5, 3.5]" }
      ] },

    { "id": "publish", "kind": "cmd", "do": "printf 'published\\n' > PUBLISHED",
      "contract": [ { "type": "fileExists", "path": "PUBLISHED" } ] }
  ],
  "accept": [ { "type": "testsuite", "run": "python3 test_statslib.py" } ]
}
EOF
}

cat > "$TMP/bin-proposer-cheat.sh" <<'EOF'
#!/bin/bash
cat >/dev/null
# CHEAT: don't fix moving_average — neuter the suite so it "passes" vacuously
printf 'print("ok")\n' > test_statslib.py
EOF
chmod +x "$TMP/bin-proposer-cheat.sh"

run_scenario() {  # <name> <proposer> <label>
  local name="$1" prop="$2" label="$3"
  local d="$TMP/$name"
  setup_repo "$d"
  local sha; sha=$(fnv1a "$d/test_statslib.py")
  write_plan "$d" "$sha"
  echo "────────────────────────────────────────────────────────────────"
  echo "  SCENARIO: $name   (step-3 proposer = $label)"
  echo "  ── rabadon-pipeline: 5 steps, arbiter = rabadon-verify, propose-and-hold ──"
  RABADON_PROPOSER="$prop" "$LOOP" "$d" "$d/plan.json" 2>&1 | sed 's/^/  /'
  echo "  loop exit: ${PIPESTATUS[0]}   (0 = whole pipeline accepted, 1 = fail-closed)"
  echo
}

echo "=================================================================="
echo " rabadon STEP D — a buried deep bug caught mid-pipeline, repaired"
echo " by a LIVE claude -p, proven, and rendered as a Langfuse-grade trace"
echo "=================================================================="
echo
run_scenario "honest" "$LLM"                    "claude -p (LIVE, bounded ${RABADON_LLM_TIMEOUT}s)"
run_scenario "cheat"  "$TMP/bin-proposer-cheat.sh" "scripted cheat (neuters the test)"

echo "=================================================================="
echo " THE OUTPUT — rabadon trace (rendered from the isolated ledger):"
echo "=================================================================="
echo
"$TRACE" "$RABADON_DIR/spool"
