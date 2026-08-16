#!/usr/bin/env bash
# prove_test.sh — the red is the evidence.
#
# `rabadon prove` answers one question: if the source half of this change is put
# back and every test is left exactly where the change left it, does the
# project's own check go red? A change whose removal keeps the suite green
# proved nothing, whatever its own tests report.
#
# The three cases below are built here, from scratch, so the fixture cannot
# drift away from what it claims to be. Each one is a shape that has been
# measured in the wild:
#
#   A  a real fix with a test that catches it        -> PROVEN*
#   B  a real change shipping tests that pass either way -> TEST_PASSES_BOTH_WAYS
#      ("Building to the Test", 2025; SpecBench, 2025 — models saturate the
#       suite they can see. commander.js c635fad50 is the same shape in the
#       wild: source reverted, 1367 tests still passed.)
#   C  a change with no test at all                  -> NO_COUNTERFACTUAL
#
# Case B is the one worth having. It is a change that looks diligent — it ships
# tests, the tests are green, review sees a tested patch — and the tests do not
# touch the thing the patch changed.
set -u
export RABADON_JUDGE=0
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/rabadon-prove"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-prove"; exit 1; }
command -v python3 >/dev/null || { echo "prove: python3 not on PATH — skipping"; exit 0; }
python3 -m pytest --version >/dev/null 2>&1 || { echo "prove: pytest not installed — skipping"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"
mkdir -p "$P/src" "$P/tests"
printf '[pytest]\n' > "$P/pytest.ini"

# the buggy baseline: clamp forgets its upper bound, and the suite never looks
printf 'def clamp(v, lo, hi):\n    if v < lo:\n        return lo\n    return v\n' > "$P/src/calc.py"
{ printf 'import sys, os\n'
  printf 'sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))\n'
  printf 'from calc import clamp\n\n\n'
  printf 'def test_inside():\n    assert clamp(5, 0, 10) == 5\n'; } > "$P/tests/test_calc.py"

( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -q -m base )

FIXED='def clamp(v, lo, hi):\n    if v < lo:\n        return lo\n    if v > hi:\n        return hi\n    return v\n'

mkpatch() { ( cd "$P" && git add -A >/dev/null 2>&1 && git diff --cached > "$1" && git reset -q && git checkout -q -- . && git clean -qfd ); }
runprove() { "$BIN" --dir "$P" --patch "$1" --cmd "python3 -m pytest -q" --timeout 120 > "$TMP/out" 2>&1; echo $?; }

echo "prove: the red is the evidence"

# ---- A: the fix, with a test that catches it -------------------------------
printf "$FIXED" > "$P/src/calc.py"
printf '\n\ndef test_upper():\n    assert clamp(15, 0, 10) == 10\n' >> "$P/tests/test_calc.py"
mkpatch "$TMP/A.patch"
RC="$(runprove "$TMP/A.patch")"
grep -q "verdict: PROVEN" "$TMP/out" && [ "$RC" = 0 ] \
  && ok "A: a fix whose test catches it is PROVEN (exit 0)" \
  || { bad "A: expected PROVEN exit 0, got $RC"; sed 's/^/      /' "$TMP/out"; }
grep -qE "counter .*RED" "$TMP/out" \
  && ok "A: the counterfactual tree really went red — that IS the proof" \
  || bad "A: counter tree was not red"
grep -qE "post .*GREEN" "$TMP/out" \
  && ok "A: and the change itself is green, so the red belongs to its removal" \
  || bad "A: post tree not green"

# ---- B: ships tests, tests pass either way ---------------------------------
# The shape that review cannot see: a diligent-looking patch with green tests
# that never exercise the line it changed.
printf "$FIXED" > "$P/src/calc.py"
{ printf 'import sys, os\n'
  printf 'sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))\n'
  printf 'from calc import clamp\n\n\n'
  printf 'def test_lower_bound_still_works():\n    assert clamp(-5, 0, 10) == 0\n\n\n'
  printf 'def test_inside_range_unchanged():\n    assert clamp(3, 0, 10) == 3\n'; } > "$P/tests/test_extra.py"
mkpatch "$TMP/B.patch"
RC="$(runprove "$TMP/B.patch")"
grep -q "verdict: TEST_PASSES_BOTH_WAYS" "$TMP/out" && [ "$RC" = 1 ] \
  && ok "B: tests that pass with the source put back are named, not counted (exit 1)" \
  || { bad "B: expected TEST_PASSES_BOTH_WAYS exit 1, got $RC"; sed 's/^/      /' "$TMP/out"; }
grep -qE "counter .*GREEN" "$TMP/out" \
  && ok "B: the counterfactual stayed green — the tests never touched the change" \
  || bad "B: counter tree was not green"

# ---- C: no test at all ------------------------------------------------------
printf "$FIXED" > "$P/src/calc.py"
mkpatch "$TMP/C.patch"
RC="$(runprove "$TMP/C.patch")"
grep -q "verdict: NO_COUNTERFACTUAL" "$TMP/out" && [ "$RC" = 2 ] \
  && ok "C: an untested change is UNPROVABLE, not failed and not fine (exit 2)" \
  || { bad "C: expected NO_COUNTERFACTUAL exit 2, got $RC"; sed 's/^/      /' "$TMP/out"; }
grep -q "not told apart here" "$TMP/out" \
  && ok "C: and it says which two possibilities it cannot separate" \
  || bad "C: silent about what it could not distinguish"

# ---- the sentence that keeps the tool honest -------------------------------
grep -q "NOT the claim: that the change is correct" "$TMP/out" \
  && ok "every run states what PROVEN does NOT mean, before any verdict" \
  || bad "the disclaimer is missing from the output"

# ---- no model is involved anywhere -----------------------------------------
# The moment a proof engine asks a model anything, the proof inherits the
# model's judgement and stops being a proof. Asserted against the source.
grep -qE "claude|RABADON_MODEL|RABADON_CLAUDE_BIN" "$HERE/prove.cpp" \
  && bad "prove.cpp reaches for a model — a proof cannot contain an opinion" \
  || ok "prove.cpp names no model anywhere: the verdict is a suite exit code"

echo
# `pass N  fail M`, word first, and not `N ok, M fail`. The gate decides how to
# read a summary from the summary itself: if any counter is written word-first
# it reads them all that way, and if none is, a bare `fail` next to no exit
# status is enough to call the run red (native/gate.cpp:1999-2003). This suite
# printed `9 ok, 0 fail`, which is number-first, and its own green run was
# reported to the session as RED. The rule is not the bug — it exists because
# `pass 17  fail 0` read number-first turns 17 passes into 17 failures — so the
# suite adopts the shape the rule was written for.
echo "prove: pass $PASS  fail $FAIL"
[ $FAIL -eq 0 ]
