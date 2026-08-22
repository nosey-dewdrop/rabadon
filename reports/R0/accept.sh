#!/usr/bin/env bash
# R0 acceptance test — "the handover".
#
# R0 is not a behaviour round. It retires one plan document in favour of
# another, closes two hygiene debts, and writes docs/POSITIONING.md so that no
# marketing sentence ever has to come out of a chat window. So this script
# asserts documents and invariants, plus the one number a document round could
# still break: the test count.
#
# Run from anywhere; it finds the repo root from its own location.
#   reports/R0/accept.sh    -> exit 0 = every claim holds, exit 1 = at least one red
#
# Every number it compares against comes from reports/R0/baseline.txt. Nothing
# is typed twice. Lowering a number in that file to turn this green is the exact
# move this product exists to refuse, and `git log -- reports/R0/` shows it.
#
# SKIP THE SLOW CLAIM:  R0_SKIP_MAKE_TEST=1 reports/R0/accept.sh
# (claim 5 is then reported as SKIPPED and the script still exits non-zero if
# anything else is red — it never reports green for a claim it did not run.)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

BASELINE="$HERE/baseline.txt"

PASS_N=0
FAIL_N=0
SKIP_N=0

pass() { printf 'PASS  %s\n' "$1"; PASS_N=$((PASS_N + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL_N=$((FAIL_N + 1)); }
skip() { printf 'SKIP  %s\n' "$1"; SKIP_N=$((SKIP_N + 1)); }
note() { printf '      %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

[ -f "$BASELINE" ] || {
  printf 'FAIL  missing %s — R0 cannot be judged without the numbers measured with it\n' "$BASELINE"
  exit 1
}

# Read with grep, never sourced: baseline.txt is a report, not a shell script.
bnum() {
  v="$(grep -E "^$1=[0-9]+$" "$BASELINE" | head -n1 | cut -d= -f2 || true)"
  [ -n "$v" ] || { printf 'FAIL  baseline.txt has no %s= line\n' "$1" >&2; exit 1; }
  printf '%s' "$v"
}
blist() {
  v="$(grep -E "^$1=" "$BASELINE" | head -n1 | cut -d= -f2- || true)"
  [ -n "$v" ] || { printf 'FAIL  baseline.txt has no %s= line\n' "$1" >&2; exit 1; }
  printf '%s' "$v"
}

BASE_PASSED="$(bnum MAKE_TEST_PASSED)"

# ---------------------------------------------------------------------------
head_ "CLAIM 1 — one plan in the root, the retired one archived and marked"

if [ ! -e "PROTOCOL-T1-T8.md" ]; then
  pass "1a PROTOCOL-T1-T8.md is gone from the repo root"
else
  fail "1a PROTOCOL-T1-T8.md is still in the repo root — two plans, and an agent cannot tell which one binds it"
fi

ARCH="docs/internal/arsiv/PROTOCOL-T1-T8.md"
if [ -f "$ARCH" ]; then
  pass "1b the retired plan survives at $ARCH — archived, not deleted"
  # 'PTAL' not 'iptal': the marker is written "İPTAL" with a Turkish dotted
  # capital I (U+0130), which grep -i does not fold to ASCII 'i'.
  if head -n 3 "$ARCH" | grep -qE 'PTAL|[Cc]ancel'; then
    pass "1c its first lines carry the cancellation marker"
  else
    fail "1c $ARCH has no cancellation marker in its first three lines — a reader who opens it cannot tell it is dead"
    note "expected a line naming it cancelled and pointing at KOSU-RABADON.md"
  fi
else
  fail "1b $ARCH is missing — the retired plan was deleted instead of archived"
  fail "1c (cannot check the cancellation marker of a file that is not there)"
fi

if [ -f "KOSU-RABADON.md" ]; then
  pass "1d KOSU-RABADON.md is in the repo root and is the plan of record"
else
  fail "1d KOSU-RABADON.md is not in the repo root"
fi

# A live document is allowed to NAME the retired plan — PROJECT.md has to, to
# tell a reader where it went. What it may not do is name it without saying it
# is dead. So the test is not "no mention"; it is "no unmarked mention": every
# file that names it must also carry the archive path or a cancellation word.
STRAY=""
for f in $(grep -rl 'PROTOCOL-T1-T8' --include='*.md' . 2>/dev/null \
           | grep -v -e '^\./docs/internal/arsiv/' \
                     -e '^\./reports/T1/' -e '^\./reports/T2/' -e '^\./reports/R0/' || true); do
  if grep -q -e 'docs/internal/arsiv' -e 'PTAL' -e '[Cc]ancel' "$f"; then :; else STRAY="$STRAY $f"; fi
done
if [ -z "$STRAY" ]; then
  pass "1e every live document that names the retired plan also says it is dead and where it went"
  note "reports/T1 and reports/T2 still name it, deliberately: an acceptance"
  note "report is evidence of what was accepted on the day it ran, and editing"
  note "one to match today's tree is gate redefinition."
else
  fail "1e a live document names the retired plan without saying it is retired:$STRAY"
  note "name it if you must, but say it is cancelled and point at the archive —"
  note "an unmarked mention is how a dead plan comes back to life."
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 2 — every day-window printed in the docs is the window the code uses"

README_7="$(grep -c '7 day' README.md || true)"
if [ "$README_7" -eq 0 ]; then
  pass "2a README quotes no 7-day window (its sample is the 30-day one, matching BENCHMARK.md)"
else
  fail "2a README still quotes a 7-day window $README_7 time(s) while BENCHMARK.md counts 30 days"
  grep -n '7 day' README.md | sed 's/^/      /'
fi

# The quickstart's "last 7 day(s)" is allowed to stand ONLY while `rabadon
# usage` really defaults to 7 days. The moment that default changes, this claim
# turns red and the doc has to move with it.
DEFAULT_DAYS_OK=0
grep -qE '^[[:space:]]*double days = 7;' native/stats.cpp && DEFAULT_DAYS_OK=1
QS_7="$(grep -c '7 day' docs/quickstart.md || true)"

if [ "$QS_7" -eq 0 ]; then
  pass "2b docs/quickstart.md quotes no 7-day window"
elif [ "$DEFAULT_DAYS_OK" -eq 1 ]; then
  pass "2b docs/quickstart.md quotes a 7-day window and \`rabadon usage\` really defaults to 7 days (native/stats.cpp)"
  note "the sample under it is labelled EXAMPLE OUTPUT from a fresh install and"
  note "carries fresh-install numbers, not BENCHMARK.md's 30-day numbers."
else
  fail "2b docs/quickstart.md quotes a 7-day window but \`rabadon usage\` no longer defaults to 7 days"
  note "native/stats.cpp lost its 'double days = 7;' default — the doc is now a lie"
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 3 — POSITIONING.md exists and every product it names carries a URL"

POS="docs/POSITIONING.md"
if [ -f "$POS" ]; then
  pass "3a $POS exists"

  MISSING=""
  for p in $(blist POSITIONING_PRODUCTS); do
    # the product's name and an http URL must appear on the same line
    if grep -qiE "$p.*https?://|https?://[^ ]*$p" "$POS"; then :; else MISSING="$MISSING $p"; fi
  done
  if [ -z "$MISSING" ]; then
    pass "3b every product named in KOSU-RABADON.md section 1b carries a URL in $POS"
  else
    fail "3b these products are named with no URL beside them:$MISSING"
    note "Law 7: a marketing sentence derives from this file, so a product with"
    note "no source here is a product we cannot honestly mention anywhere."
  fi

  # Law 7's real teeth: a claim we could not confirm must be MARKED, not quietly
  # kept. If the marker vocabulary disappears, someone laundered a shaky claim.
  if grep -q 'UNVERIFIED' "$POS"; then
    pass "3c $POS still marks what could not be confirmed at a primary source"
    note "$(grep -c 'UNVERIFIED' "$POS") UNVERIFIED marker(s) present"
  else
    fail "3c $POS carries no UNVERIFIED marker"
    note "eleven section-1b claims failed primary-source verification on 2026-08-22."
    note "If they are all gone, either they were confirmed — say where — or they"
    note "were deleted, and deleting a known-shaky claim is how it gets re-invented."
  fi
else
  fail "3a $POS is missing — marketing has no source of record"
  fail "3b (cannot check product URLs)"
  fail "3c (cannot check UNVERIFIED markers)"
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 4 — no build path reaches for a compiler named clang++"

# reports/ is excluded: an acceptance script that greps for the broken pattern
# necessarily contains it, and a report is not a build path.
# `|| true` on the grep, not on the pipeline: under `set -o pipefail` a grep
# that matches nothing exits 1 and would kill this script at its best result.
CLANG_SITES="$({ grep -rn 'CXX:-clang' --include='*.sh' --include='Makefile' \
                 --include='*.yml' --include='*.py' --exclude-dir=reports . 2>/dev/null || true; } | wc -l | tr -d ' ')"
if [ "$CLANG_SITES" -eq 0 ]; then
  pass "4a no script falls back to a clang-only compiler name"
else
  fail "4a $CLANG_SITES site(s) still fall back to clang++ — these die on a g++-only Linux box"
  grep -rn 'CXX:-clang' --include='*.sh' --include='Makefile' --include='*.yml' --include='*.py' --exclude-dir=reports . | sed 's/^/      /'
fi

if grep -qE '^CXX \?= c\+\+$' Makefile; then
  pass "4b the Makefile's own default is c++, the alias every machine resolves"
else
  fail "4b the Makefile's CXX default is not c++:"
  grep -nE '^CXX' Makefile | sed 's/^/      /'
fi

if grep -qE '^[[:space:]]*export[[:space:]]+CXX' Makefile; then
  fail "4c the Makefile exports CXX — this overrides the ten test scripts' own"
  note "\${CXX:-c++} fallback, which is the protection native/cmdtext_test.sh:31"
  note "was written to provide. PROJECT.md S0.2 offers export as an alternative"
  note "remedy; taking BOTH remedies undoes the first one. See reports/R0/CLAIM.md."
else
  pass "4c the Makefile does not export CXX — the test scripts keep their own fallback"
fi

SCRIPTS="$({ grep -rl 'CXX:-c++' native/ 2>/dev/null || true; } | wc -l | tr -d ' ')"
BASE_SCRIPTS="$(bnum CXX_CPLUSPLUS_FALLBACK_SCRIPTS)"
if [ "$SCRIPTS" -ge "$BASE_SCRIPTS" ]; then
  pass "4d $SCRIPTS test script(s) carry the c++ fallback (baseline $BASE_SCRIPTS)"
else
  fail "4d only $SCRIPTS test script(s) carry the c++ fallback, down from $BASE_SCRIPTS"
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 5 — make test is green and the count did not drop (baseline $BASE_PASSED)"

if [ "${R0_SKIP_MAKE_TEST:-0}" = "1" ]; then
  skip "5 make test not run (R0_SKIP_MAKE_TEST=1) — this claim is UNJUDGED, not green"
else
  MT_LOG="$(mktemp -t rabadon-r0-maketest)"
  MT_EXIT=0
  make test >"$MT_LOG" 2>&1 || MT_EXIT=$?

  if [ "$MT_EXIT" -eq 0 ]; then
    pass "5a make test exited 0"
  else
    fail "5a make test exited $MT_EXIT"
  fi

  NOW_PASSED="$(grep -oE '[0-9]+ (passed|ok), *[0-9]+ failed' "$MT_LOG" \
                 | grep -oE '^[0-9]+' | paste -sd+ - | bc || true)"
  NOW_FAILED="$(grep -oE '[0-9]+ (passed|ok), *[0-9]+ failed' "$MT_LOG" \
                 | grep -oE ', *[0-9]+ failed' | grep -oE '[0-9]+' | paste -sd+ - | bc || true)"
  NOW_PASSED="${NOW_PASSED:-0}"
  NOW_FAILED="${NOW_FAILED:-0}"

  if [ "$NOW_PASSED" -ge "$BASE_PASSED" ]; then
    pass "5b make test passing count did not drop: $NOW_PASSED >= baseline $BASE_PASSED"
  else
    fail "5b make test passing count DROPPED: $NOW_PASSED < baseline $BASE_PASSED (-$((BASE_PASSED - NOW_PASSED)))"
  fi

  if [ "$NOW_FAILED" -eq 0 ]; then
    pass "5c no suite reported a failure"
  else
    fail "5c suites reported $NOW_FAILED failure(s)"
    grep -nE '[0-9]+ (passed|ok), *[1-9][0-9]* failed' "$MT_LOG" | sed 's/^/      /'
  fi
  note "full log: $MT_LOG"
fi

# ---------------------------------------------------------------------------
printf '\n== R0 acceptance: %d green, %d red, %d skipped\n' "$PASS_N" "$FAIL_N" "$SKIP_N"
if [ "$FAIL_N" -gt 0 ]; then
  printf 'R0 NOT ACCEPTED\n'
  exit 1
fi
if [ "$SKIP_N" -gt 0 ]; then
  printf 'R0 NOT ACCEPTED — %d claim(s) were skipped, and an unrun claim is not a green one\n' "$SKIP_N"
  exit 1
fi
printf 'R0 ACCEPTED\n'
exit 0
