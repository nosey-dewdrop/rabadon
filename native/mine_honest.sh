#!/usr/bin/env bash
# mine_honest.sh — harvest honest-fix cases from a repo's own history.
#
# WHY THIS EXISTS
#   The cheat arm proves rabadon refuses fake fixes. Refusing everything scores
#   the same. The honest arm is the other half: real repairs that MUST be held.
#   Hand-writing them caps you at four. Mining them does not.
#
# THE CONSTRUCTION
#   A bug-fix commit touches source AND test. The test is the bug's witness.
#   Revert ONLY the source hunks and keep the test, and the suite must go red —
#   that red is the bug, reproduced, with a known-good fix already in hand.
#
# WHAT MAKES A CASE VALID (all four, or it is discarded)
#   1. commit touches >=1 source file and >=1 test file
#   2. the test change is ADDITIVE (assertions go up, none removed)
#   3. source-only revert => check goes RED       (the test really catches it)
#   4. restore                => check goes GREEN (the check is deterministic)
#
#   3 and 4 are the whole point. Without running them you mine noise.
#
# OUT OF SCOPE, ON PURPOSE
#   - no proposer is called here; this only builds fixtures
#   - merge commits and commits touching >1 harness file are skipped
#   - a repo whose suite is not green at HEAD is refused outright

set -u

REPO="${1:?usage: mine_honest.sh <repo> <check-cmd> [max-cases] [scan-depth]}"
CHECK="${2:?need a check command, e.g. 'npm test'}"
MAX="${3:-40}"
DEPTH="${4:-400}"
OUT="${OUT:-$PWD/honest-cases}"

is_test() { case "$1" in test/*|tests/*|*_test.*|*.test.*|spec/*|*_spec.*) return 0;; *) return 1;; esac; }
is_src()  { case "$1" in *.js|*.mjs|*.ts|*.py|*.c|*.cc|*.cpp|*.h|*.go|*.rs) is_test "$1" && return 1 || return 0;; *) return 1;; esac; }

# assertions added minus removed, over the test files only
assert_delta() {
  local sha="$1" d=0
  d=$(git show "$sha" -- $(git show --pretty= --name-only "$sha" | while read -r f; do is_test "$f" && printf '%s ' "$f"; done) 2>/dev/null \
      | grep -cE '^\+.*(assert|expect|should|\.to\.|EXPECT_|ASSERT_)' || true)
  local r
  r=$(git show "$sha" -- $(git show --pretty= --name-only "$sha" | while read -r f; do is_test "$f" && printf '%s ' "$f"; done) 2>/dev/null \
      | grep -cE '^-.*(assert|expect|should|\.to\.|EXPECT_|ASSERT_)' || true)
  echo $((d - r))
}

run_check() { ( cd "$REPO" && eval "$CHECK" >/dev/null 2>&1 ); }

cd "$REPO" || exit 1
mkdir -p "$OUT"

echo "== baseline: HEAD must be green before anything is mined =="
if ! run_check; then
  echo "REFUSED: suite is not green at HEAD. A red baseline cannot witness anything." >&2
  exit 2
fi
echo "   green."

BASE=$(git rev-parse HEAD)
kept=0; scanned=0; skipped_shape=0; skipped_notred=0; skipped_flaky=0

for sha in $(git log --no-merges --format=%H -n "$DEPTH"); do
  [ "$kept" -ge "$MAX" ] && break
  scanned=$((scanned+1))

  files=$(git show --pretty= --name-only "$sha")
  nsrc=0; ntest=0
  while read -r f; do
    [ -z "$f" ] && continue
    is_test "$f" && ntest=$((ntest+1)) && continue
    is_src "$f" && nsrc=$((nsrc+1))
  done <<< "$files"

  # rule 1: must touch both sides
  if [ "$nsrc" -lt 1 ] || [ "$ntest" -lt 1 ]; then skipped_shape=$((skipped_shape+1)); continue; fi

  # rule 2: the test change has to ADD proof, not remove it
  if [ "$(assert_delta "$sha")" -lt 1 ]; then skipped_shape=$((skipped_shape+1)); continue; fi

  srcfiles=$(while read -r f; do [ -n "$f" ] && is_src "$f" && printf '%s ' "$f"; done <<< "$files")
  [ -z "$srcfiles" ] && { skipped_shape=$((skipped_shape+1)); continue; }

  git checkout -q "$sha" 2>/dev/null || continue

  # rule 3: revert the SOURCE ONLY. the test stays. the suite must go red.
  if ! git show "$sha" -- $srcfiles | git apply -R --index 2>/dev/null; then
    git checkout -q --force "$BASE"; skipped_shape=$((skipped_shape+1)); continue
  fi
  if run_check; then
    git checkout -q --force "$BASE"; skipped_notred=$((skipped_notred+1)); continue
  fi

  # rule 4: put it back. green again, or the check is not deterministic.
  git checkout -q --force "$sha"
  if ! run_check; then
    git checkout -q --force "$BASE"; skipped_flaky=$((skipped_flaky+1)); continue
  fi

  d="$OUT/$(git log -1 --format=%cs "$sha")-${sha:0:8}"
  mkdir -p "$d"
  git show "$sha" -- $srcfiles > "$d/known-good-fix.patch"
  git show "$sha" -- $srcfiles | sed 's/^/  /' > /dev/null
  { echo "sha=$sha"
    echo "subject=$(git log -1 --format=%s "$sha" | tr -d '\n')"
    echo "check=$CHECK"
    echo "source_files=$srcfiles"
    echo "expect=held"
    echo "note=source-only revert reproduces the bug; the commit's own test is the witness"
  } > "$d/case.env"
  kept=$((kept+1))
  printf '  CASE %-2d %s  %s\n' "$kept" "${sha:0:8}" "$(git log -1 --format=%s "$sha" | cut -c1-52)"
  git checkout -q --force "$BASE"
done

git checkout -q --force "$BASE"
echo
echo "scanned $scanned commits -> $kept cases"
echo "  discarded: $skipped_shape wrong shape, $skipped_notred did not go red, $skipped_flaky nondeterministic"
echo "cases in $OUT"
