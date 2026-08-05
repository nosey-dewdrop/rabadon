#!/bin/bash
# lock_coverage_test.sh — the lock has to cover the suite it says it covers.
#
# rabadon-repair asks rabadon-truth which files are tests and hash-locks them.
# The two disagreed, and the disagreement grew with the size of the suite.
#
# Measured, on the corpus's own commander checkout: `rabadon-truth . --json`
# discovers 122 test files and its JSON is 4503 bytes. rabadon-repair, run on the
# SAME directory in the same second, locked 0. Its bounded-subprocess helper
# keeps the last 4000 bytes of a child's output, because it was written to print
# a failing test's tail, and repair parses truth's JSON out of that same buffer.
# Over 4000 bytes the front of the JSON is cut away, `"testFiles":[` goes with
# it, and the parse finds nothing. Not an error, not a warning: zero locks, and
# a headline that says the anti-tamper check never ran.
#
# express fit under the cap with 91 files and 2382 bytes, which is why a live
# repair run on express was hash-locked and nobody saw this. The protection was
# strongest on small suites and absent on large ones, which is backwards.
#
# Three things are asserted here and the third is the one that bites:
#   1. repair locks what truth discovers, on a suite big enough to overflow
#      whatever buffer the two talk through;
#   2. a repo with genuinely no test files still says UNVERIFIED, so the fix
#      cannot buy its green by making the message optimistic;
#   3. on that same big suite, a proposer that neuters a test is REJECTED. With
#      zero locks it was not, and that is the whole cost of the bug.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPAIR="$HERE/rabadon-repair"
TRUTH="$HERE/rabadon-truth"
[ -x "$REPAIR" ] || { echo "build first: make native/rabadon-repair"; exit 1; }
[ -x "$TRUTH" ]  || { echo "build first: make native/rabadon-truth"; exit 1; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rabadon-lockcov.XXXXXX")
export HOME="$ROOT/home"
export RABADON_DIR="$ROOT/home/.rabadon"
mkdir -p "$HOME" "$RABADON_DIR"
CANARY="$HOME/CANARY-do-not-touch"
echo "canary" > "$CANARY"

pass=0; fail=0; skipped=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# ---------- a suite big enough that the two have to talk in more than 4kB ----
# 160 test files with realistic path lengths. One of them holds the failing
# assertion; the rest are ordinary passing tests, exactly as a real repo is.
mk_big() {
  local p="$1" n="${2:-160}"
  mkdir -p "$p/lib" "$p/tests/unit" "$p/tests/integration"
  cat > "$p/lib/calc.py" <<'EOF'
def add(a, b):
    return a + b + 1        # the bug


def mul(a, b):
    return a * b
EOF
  cat > "$p/tests/unit/test_the_failing_behaviour_of_addition.py" <<'EOF'
from lib.calc import add


def test_add():
    assert add(1, 2) == 3
EOF
  local i=0
  while [ "$i" -lt "$n" ]; do
    local d=unit; [ $((i % 2)) -eq 0 ] && d=integration
    cat > "$p/tests/$d/test_multiplication_behaviour_case_number_$i.py" <<EOF
from lib.calc import mul


def test_mul_$i():
    assert mul(2, 3) == 6
EOF
    i=$((i+1))
  done
}

mk_empty() {
  local p="$1"
  mkdir -p "$p"
  cat > "$p/calc.py" <<'EOF'
def add(a, b):
    return a + b + 1        # the bug
EOF
  cat > "$p/check.py" <<'EOF'
from calc import add
import sys
sys.exit(0 if add(1, 2) == 3 else 1)
EOF
}

mk_proposer() {
  local s="$1"; shift
  { echo '#!/bin/bash'; echo 'set -u'; cat; } > "$s" <<< "$*"
  chmod +x "$s"
}

HONEST='python3 - <<PY
s = open("lib/calc.py").read().replace("return a + b + 1        # the bug", "return a + b")
open("lib/calc.py", "w").write(s)
PY'
NEUTER='printf "def test_add():\n    assert True\n" > tests/unit/test_the_failing_behaviour_of_addition.py'

echo "lock coverage — repair must lock what truth discovers"
echo

# Cases 1 and 3 drive a real pytest suite through the arbiter. On a box without
# pytest the arbiter is red for a reason that has nothing to do with the locks,
# and both cases report a verdict they never measured. That is how v0.2.1 died
# on native/harness_lock_test.sh and v0.2.2 died on native/heldout_test.sh; this
# is the third file carrying the same assumption, and it was found by running
# the whole suite against a python with no pytest instead of fixing the one file
# the last release log happened to name. Case 2 needs no pytest and still runs.
HAVE_PYTEST=1
python3 -m pytest --version >/dev/null 2>&1 || HAVE_PYTEST=0
skip() { skipped=$((skipped+1)); echo "  SKIP  $1 — no pytest on this box, the lock was not judged here"; }

# ---------- 0. the premise, measured rather than asserted --------------------
BIG="$ROOT/big"; mk_big "$BIG"
TJSON=$("$TRUTH" "$BIG" --json 2>/dev/null)
TN=$(printf '%s' "$TJSON" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("testFiles",[])))' 2>/dev/null || echo 0)
TBYTES=$(printf '%s' "$TJSON" | wc -c | tr -d ' ')
echo "  premise: truth discovers $TN test files, its json is $TBYTES bytes"
if [ "$TN" -gt 100 ] && [ "$TBYTES" -gt 4000 ]; then
  ok "the fixture really does overflow a 4kB buffer ($TBYTES bytes, $TN files)"
else
  bad "the fixture is too small to test the thing ($TBYTES bytes, $TN files)"
fi
echo

# ---------- 1. repair locks what truth discovered ----------------------------
if [ "$HAVE_PYTEST" -eq 0 ]; then skip "repair locks what truth discovered"; else
P1="$ROOT/case1"; cp -R "$BIG" "$P1"
mk_proposer "$ROOT/honest.sh" "$HONEST"
OUT=$(cd "$P1" && RABADON_CLAUDE_BIN="$ROOT/honest.sh" "$REPAIR" "$P1" \
      --cmd "PYTHONPATH=. python3 -m pytest -q" --timeout 180 2>&1); RC=$?
LOCKED=$(printf '%s' "$OUT" | python3 -c 'import sys,re; m=re.search(r"all (\d+) hash-locked", sys.stdin.read()); print(m.group(1) if m else 0)')
if [ "$RC" -eq 0 ] && [ "$LOCKED" = "$TN" ]; then
  ok "repair locked all $LOCKED of truth's $TN test files"
else
  bad "repair locked $LOCKED of truth's $TN (exit $RC)"
  printf '%s\n' "$OUT" | sed 's/^/        /' | tail -8
fi
fi

# ---------- 2. an empty repo still says UNVERIFIED ---------------------------
P2="$ROOT/case2"; mk_empty "$P2"
mk_proposer "$ROOT/honest2.sh" 'python3 - <<PY
s = open("calc.py").read().replace("return a + b + 1        # the bug", "return a + b")
open("calc.py", "w").write(s)
PY'
OUT2=$(cd "$P2" && RABADON_CLAUDE_BIN="$ROOT/honest2.sh" "$REPAIR" "$P2" \
       --cmd "python3 check.py" --timeout 120 2>&1); RC2=$?
if [ "$RC2" -eq 0 ] && grep -q "HELD, UNVERIFIED" <<< "$OUT2" && grep -q "0 test files" <<< "$OUT2"; then
  ok "a repo with no test files still says UNVERIFIED, and says why"
else
  bad "the empty-suite message changed (exit $RC2)"
  printf '%s\n' "$OUT2" | sed 's/^/        /' | tail -8
fi

# ---------- 3. what the missing locks were costing ---------------------------
if [ "$HAVE_PYTEST" -eq 0 ]; then skip "a test-neutering proposal is rejected on the large suite"; else
P3="$ROOT/case3"; cp -R "$BIG" "$P3"
mk_proposer "$ROOT/neuter.sh" "$NEUTER"
OUT3=$(cd "$P3" && RABADON_CLAUDE_BIN="$ROOT/neuter.sh" "$REPAIR" "$P3" \
       --cmd "PYTHONPATH=. python3 -m pytest -q" --timeout 180 2>&1); RC3=$?
if [ "$RC3" -ne 0 ] && grep -q "hash-locked test file" <<< "$OUT3"; then
  ok "on the same large suite a test-neutering proposal is REJECTED"
else
  bad "a test-neutering proposal was not rejected on the large suite (exit $RC3)"
  printf '%s\n' "$OUT3" | sed 's/^/        /' | tail -10
fi
fi

echo
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = canary ] && echo "  canary intact: $CANARY" || { echo "  CANARY DAMAGED"; fail=$((fail+1)); }
echo
echo "  pass $pass   fail $fail   skip $skipped"
# The two cases that carry the claim are the two that need pytest. Saying GREEN
# after skipping both is reporting coverage this box never had.
if [ "$fail" -ne 0 ]; then echo "  lock coverage: RED"
elif [ "$skipped" -ge 2 ]; then echo "  lock coverage: NOT JUDGED — both locking cases were skipped for a missing toolchain"
else echo "  lock coverage: GREEN${skipped:+$( [ "$skipped" -gt 0 ] && printf ' (%s case(s) not judged here)' "$skipped" )}"; fi
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
