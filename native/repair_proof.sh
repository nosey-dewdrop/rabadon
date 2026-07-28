#!/bin/bash
# repair_proof.sh — the FIRST real closed repair, proven end-to-end.
#
# This is the product's core claim made to run: a real project has a real bug
# whose OWN test is red; rabadon-loop CATCHES it, drives a repair, and the
# separate deterministic arbiter (rabadon-verify) accepts the fix ONLY because
# the project's real test went green — and REJECTS a fix that games the judge.
#
# Two scenarios, same broken repo, only the proposer swapped:
#   HONEST  proposer fixes the real code   -> real test green -> REPAIR_OK  (accepted)
#   CHEAT   proposer neuters the test to
#           fake a pass                     -> forbidden sha caught -> REPAIR_FAIL (rejected, fail-closed)
#
# The proposer is scripted here ON PURPOSE: it isolates the moat. The thing that
# decides accept/reject is rabadon-verify running the real test — swap in an LLM
# proposer and the engine is unchanged. Remove the LLM entirely and the arbiter,
# the bounds and the verdict remain. That is the un-gameable kernel Langfuse has
# no answer to: it can show you the red run, it cannot refuse the fake fix.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

LOOP="$ROOT/native/rabadon-loop"
VERIFY="$ROOT/native/rabadon-verify"
STATS="$ROOT/native/rabadon-stats"
for b in "$LOOP" "$VERIFY" "$STATS"; do
  [ -x "$b" ] || { echo "build first: make ${b##*/}"; exit 1; }
done

TMP=$(mktemp -d /tmp/rabadon-repair-proof.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export RABADON_DIR="$TMP/ledger"     # isolate the spool — never touch the real ledger
export RABADON_MAX_REPAIRS=1
mkdir -p "$RABADON_DIR/spool"

# --- the two scripted proposers (cwd = the project dir at call time) ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/proposer-honest.sh" <<'EOF'
#!/bin/bash
cat >/dev/null   # ignore the repair prompt on stdin
# do the REAL work: fix the bug in the code
printf 'def add(a, b):\n    return a + b\n' > calc.py
EOF
cat > "$TMP/bin/proposer-cheat.sh" <<'EOF'
#!/bin/bash
cat >/dev/null
# CHEAT: don't fix the bug — neuter the test so the suite "passes" vacuously
printf 'print("ok")\n' > test_calc.py
EOF
chmod +x "$TMP/bin"/*.sh

fnv1a() {   # FNV-1a 64-bit over a file's bytes — identical to rabadon-verify
  python3 -c "
h=1469598103934665603
for b in open('$1','rb').read(): h=((h^b)*1099511628211)&0xffffffffffffffff
print(h)"
}

setup_repo() {   # a REAL tiny project: add() is broken, its own test asserts behavior
  local d="$1"; mkdir -p "$d"
  printf 'def add(a, b):\n    return a - b   # BUG: subtracts\n' > "$d/calc.py"
  cat > "$d/test_calc.py" <<'EOF'
import calc
assert calc.add(2, 3) == 5, "add(2,3) must be 5"
assert calc.add(10, 4) == 14, "add(10,4) must be 14"
print("ok")
EOF
}

write_plan() {   # step is a no-op cmd; the REPAIR is where the fix must happen.
  local d="$1" sha="$2"
  cat > "$d/plan.json" <<EOF
{
  "steps": [
    { "id": "fix-add", "kind": "cmd", "do": "true",
      "contract": [
        { "type": "testsuite", "run": "python3 test_calc.py" },
        { "type": "forbidden", "path": "test_calc.py", "sha": "$sha" }
      ] }
  ],
  "accept": [ { "type": "testsuite", "run": "python3 test_calc.py" } ]
}
EOF
}

run_scenario() {  # <name> <proposer>
  local name="$1" prop="$2"
  local d="$TMP/$name"
  setup_repo "$d"
  local sha; sha=$(fnv1a "$d/test_calc.py")   # lock the real test against edits
  write_plan "$d" "$sha"
  echo "────────────────────────────────────────────────────────────────"
  echo "  SCENARIO: $name   (proposer = ${prop##*/})"
  echo "  before:  python3 test_calc.py  ->  $(cd "$d" && python3 test_calc.py 2>&1 | tail -1)   [RED, add() is broken]"
  echo "  ── rabadon-loop runs ──"
  RABADON_PROPOSER="$prop" "$LOOP" "$d" "$d/plan.json" 2>&1 | sed 's/^/  /'
  local rc=${PIPESTATUS[0]}
  echo "  after:   python3 test_calc.py  ->  $(cd "$d" && python3 test_calc.py 2>&1 | tail -1)"
  echo "  loop exit code: $rc   (0 = accepted / done,  1 = fail-closed / rejected)"
  echo
}

echo "=================================================================="
echo " rabadon repair proof — catch a broken workflow, repair it, PROVE it"
echo "=================================================================="
echo
run_scenario "honest" "$TMP/bin/proposer-honest.sh"
run_scenario "cheat"  "$TMP/bin/proposer-cheat.sh"

echo "=================================================================="
echo " the event stream rabadon recorded (its own ledger, isolated):"
echo "=================================================================="
python3 - "$RABADON_DIR/spool" <<'EOF'
import os, json, sys, glob
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.jsonl"))):
    for ln in open(f):
        ln=ln.strip()
        if not ln: continue
        e=json.loads(ln)
        run=e.get("run","")[:14]
        ev=e.get("ev","")
        extra=""
        if ev=="STOP": extra=f'  reason={e.get("reason")}'
        if ev in ("REPAIR_OK","REPAIR_FAIL","STEP_OK","CHECK_FAIL"): extra=f'  step={e.get("step","")}'
        if ev=="RUN_DONE": extra=f'  verdict={e.get("verdict")}'
        print(f'  {run:14}  {ev:12}{extra}')
EOF
echo
echo "=================================================================="
echo " rabadon stats on this isolated ledger — the scoreboard:"
echo "=================================================================="
"$STATS" --days 1 | sed 's/^/  /'
