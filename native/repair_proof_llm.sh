#!/bin/bash
# repair_proof_llm.sh — the scripted proof (repair_proof.sh), now with a REAL LLM.
#
# repair_proof.sh isolated the moat with a canned proposer. This is the toy->real
# bridge: the SAME broken repo, the SAME un-gameable contract (testsuite + forbidden
# sha), but the repair is written by a live, bounded `claude -p`. If REPAIR_OK lands,
# a real agent's fix passed the deterministic arbiter running the project's real test
# — not a script we wrote, and not a keyword the gate happened to spot.
#
# BOUNDED: isolated spool (RABADON_DIR=temp), RABADON_MAX_REPAIRS=1, and the proposer
# itself is wall-clock capped with RABADON_OFF=1 (see llm-proposer.sh). No overnight.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

LOOP="$ROOT/native/rabadon-loop"
VERIFY="$ROOT/native/rabadon-verify"
STATS="$ROOT/native/rabadon-stats"
PROPOSER="$ROOT/native/llm-proposer.sh"
for b in "$LOOP" "$VERIFY" "$STATS"; do
  [ -x "$b" ] || { echo "build first: make ${b##*/}"; exit 1; }
done
[ -x "$PROPOSER" ] || { echo "missing/!x: $PROPOSER"; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not on PATH"; exit 1; }

TMP=$(mktemp -d /tmp/rabadon-repair-llm.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export RABADON_DIR="$TMP/ledger"      # isolate the spool — never touch the real ledger
export RABADON_MAX_REPAIRS=1
export RABADON_LLM_TIMEOUT="${RABADON_LLM_TIMEOUT:-180}"
mkdir -p "$RABADON_DIR/spool"

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

write_plan() {   # step is a no-op cmd; the REPAIR is where the real LLM must fix it.
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

echo "=================================================================="
echo " rabadon repair proof — REAL LLM (claude -p) closes a real bug"
echo "=================================================================="
echo
d="$TMP/honest-llm"
setup_repo "$d"
sha=$(fnv1a "$d/test_calc.py")          # lock the real test against edits
write_plan "$d" "$sha"
echo "────────────────────────────────────────────────────────────────"
echo "  SCENARIO: honest-llm   (proposer = claude -p, bounded ${RABADON_LLM_TIMEOUT}s, RABADON_OFF=1)"
echo "  before:  python3 test_calc.py  ->  $(cd "$d" && python3 test_calc.py 2>&1 | tail -1)   [RED, add() is broken]"
echo "  calc.py before:  $(tr '\n' '|' < "$d/calc.py")"
echo "  ── rabadon-loop runs (a live claude -p writes the repair) ──"
t0=$(python3 -c 'import time;print(int(time.time()))')
RABADON_PROPOSER="$PROPOSER" "$LOOP" "$d" "$d/plan.json" 2>&1 | sed 's/^/  /'
rc=${PIPESTATUS[0]}
t1=$(python3 -c 'import time;print(int(time.time()))')
echo "  calc.py after:   $(tr '\n' '|' < "$d/calc.py")"
echo "  after:   python3 test_calc.py  ->  $(cd "$d" && python3 test_calc.py 2>&1 | tail -1)"
echo "  loop exit code: $rc   (0 = accepted / done,  1 = fail-closed / rejected)   wall: $((t1-t0))s"
echo

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
echo
if [ "$rc" = "0" ]; then
  echo "  RESULT: a REAL claude -p fix passed the deterministic arbiter -> REPAIR_OK."
else
  echo "  RESULT: loop did not accept (rc=$rc). Inspect the stream above."
fi
