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
#   Why the red is trustworthy: the parent tree was green with the OLD source
#   and the OLD tests. Source-only revert is OLD source + NEW tests. Anything
#   that fails therefore differs from the parent on the test side — it is a
#   test this commit added or changed. The one way that reasoning breaks is
#   cross-test pollution (a new test file leaving state that fails an old one),
#   which is why the failing output is now recorded per case instead of being
#   thrown away: a reviewer can see WHICH test went red and judge it.
#
# WHAT MAKES A CASE VALID (all four, or it is discarded)
#   1. commit touches >=1 source file and >=1 test file
#   2. the test change is ADDITIVE (assertions go up, none removed)
#   3. source-only revert => check goes RED       (the test really catches it)
#   4. restore                => check goes GREEN (the check is deterministic)
#
#   3 and 4 are the whole point. Without running them you mine noise.
#
# WHAT IT REFUSES TO DO
#   - it will not run in a dirty worktree. Every path here ends in
#     `git checkout --force`, which is unrecoverable for uncommitted work.
#   - it will not leave you somewhere else: the branch you were on is restored
#     on every exit, including Ctrl-C.
#   - it will not write inside the repo it is mining (that would dirty the
#     tree it just promised to leave alone).
#
# OUT OF SCOPE, ON PURPOSE
#   - no proposer is called here; this only builds fixtures
#   - merge commits and commits touching >1 harness file are skipped
#   - a repo whose suite is not green at HEAD is refused outright
#
# USAGE
#   mine_honest.sh <repo> <check-cmd> [max-cases] [scan-depth]
#   max-cases defaults to 0 = no cap. A cap is recorded in discards.txt as
#   max_hit=yes so a round number in the results is never mistaken for the
#   shape of the data (AGENTS-PROTOCOL.md, gate 2).

set -u

REPO="${1:?usage: mine_honest.sh <repo> <check-cmd> [max-cases] [scan-depth]}"
CHECK="${2:?need a check command, e.g. 'npm test'}"
MAX="${3:-0}"
DEPTH="${4:-400}"
OUT="${OUT:-$PWD/honest-cases}"

REPO=$(cd "$REPO" && pwd) || exit 2
case "$OUT" in
  "$REPO"|"$REPO"/*)
    echo "REFUSED: OUT ($OUT) is inside the repo being mined. Mining rewrites that" >&2
    echo "         worktree; artifacts written into it would be destroyed or committed." >&2
    exit 2;;
esac

is_test() { case "$1" in test/*|tests/*|*_test.*|*.test.*|spec/*|*_spec.*) return 0;; *) return 1;; esac; }
is_src()  { case "$1" in *.js|*.mjs|*.ts|*.py|*.c|*.cc|*.cpp|*.h|*.go|*.rs) is_test "$1" && return 1 || return 0;; *) return 1;; esac; }

testfiles_of() {
  git show --pretty= --name-only "$1" | while read -r f; do is_test "$f" && printf '%s ' "$f"; done
}

# assertions added minus removed, over the test files only.
# `git show` prints `+++ b/path` and `--- a/path` headers; when the path itself
# contains "assert"/"expect"/"should" those headers score as assertions. On a
# modified file the two cancel, on an added file (`--- /dev/null`) they do not,
# which handed rule 2 a free point. Both header forms are dropped first.
assert_delta() {
  local sha="$1" tf d r
  tf=$(testfiles_of "$sha")
  [ -z "$tf" ] && { echo 0; return; }
  local diff
  diff=$(git show "$sha" -- $tf 2>/dev/null | grep -vE '^(\+\+\+|---) ')
  d=$(printf '%s\n' "$diff" | grep -cE '^\+.*(assert|expect|should|\.to\.|EXPECT_|ASSERT_)' || true)
  r=$(printf '%s\n' "$diff" | grep -cE '^-.*(assert|expect|should|\.to\.|EXPECT_|ASSERT_)' || true)
  echo $((d - r))
}

run_check()      { ( cd "$REPO" && eval "$CHECK" >/dev/null 2>&1 ); }
run_check_log()  { ( cd "$REPO" && eval "$CHECK" ) >"$1" 2>&1; }

cd "$REPO" || exit 2

# --- refuse a dirty worktree -------------------------------------------------
# TRACKED changes only. `git checkout --force` overwrites tracked files and
# leaves untracked ones alone, so refusing on untracked files would refuse
# every real checkout on a mac (.DS_Store) while protecting nothing. They are
# still named, because a commit that introduces the same path would clobber one.
DIRTY=$(git status --porcelain 2>/dev/null | grep -v '^??' || true)
UNTRACKED=$(git status --porcelain 2>/dev/null | grep '^??' || true)
if [ -n "$DIRTY" ]; then
  echo "REFUSED: worktree has uncommitted changes to TRACKED files. This script" >&2
  echo "         runs 'git checkout --force', which would destroy them permanently:" >&2
  printf '%s\n' "$DIRTY" | sed 's/^/           /' >&2
  echo "         commit or stash first, then re-run." >&2
  exit 2
fi
if [ -n "$UNTRACKED" ]; then
  echo "   note: untracked files present; checkout leaves them alone, but a" >&2
  echo "         commit that adds the same path would overwrite one:" >&2
  printf '%s\n' "$UNTRACKED" | sed 's/^/           /' >&2
fi

# --- remember where the human was, and go back there no matter how we exit ---
ORIG_REF=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse HEAD)
restore() { git -C "$REPO" checkout -q --force "$ORIG_REF" 2>/dev/null || true; }
trap restore EXIT INT TERM

mkdir -p "$OUT"

echo "== baseline: HEAD must be green before anything is mined =="
if ! run_check; then
  echo "REFUSED: suite is not green at HEAD. A red baseline cannot witness anything." >&2
  exit 2
fi
echo "   green."

BASE=$(git rev-parse HEAD)
kept=0; scanned=0
skipped_shape=0        # rule 1 / rule 2: not a bug-fix shape
skipped_norevert=0     # the source-only revert would not apply
skipped_checkout=0     # could not check the commit out at all
skipped_notred=0       # rule 3: revert did not reproduce anything
skipped_flaky=0        # rule 4: restore did not come back green
max_hit=no

for sha in $(git log --no-merges --format=%H -n "$DEPTH"); do
  if [ "$MAX" -gt 0 ] && [ "$kept" -ge "$MAX" ]; then max_hit=yes; break; fi
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

  if ! git checkout -q "$sha" 2>/dev/null; then
    skipped_checkout=$((skipped_checkout+1)); continue
  fi

  # rule 3: revert the SOURCE ONLY. the test stays. the suite must go red.
  # a revert that will not apply is NOT a shape problem — it gets its own
  # counter, because gate 2 reads these numbers as causes, not as a total.
  if ! git show "$sha" -- $srcfiles | git apply -R --index 2>/dev/null; then
    git checkout -q --force "$BASE"; skipped_norevert=$((skipped_norevert+1)); continue
  fi
  REDLOG=$(mktemp "${TMPDIR:-/tmp}/mine-red.XXXXXX")
  if run_check_log "$REDLOG"; then
    rm -f "$REDLOG"
    git checkout -q --force "$BASE"; skipped_notred=$((skipped_notred+1)); continue
  fi

  # rule 4: put it back. green again, or the check is not deterministic.
  git checkout -q --force "$sha"
  if ! run_check; then
    rm -f "$REDLOG"
    git checkout -q --force "$BASE"; skipped_flaky=$((skipped_flaky+1)); continue
  fi

  d="$OUT/$(git log -1 --format=%cs "$sha")-${sha:0:8}"
  mkdir -p "$d"
  git show "$sha" -- $srcfiles > "$d/known-good-fix.patch"
  git show "$sha" -- $(testfiles_of "$sha") > "$d/witness-test.patch"
  mv "$REDLOG" "$d/red.log"
  nsrcfiles=$(printf '%s\n' $srcfiles | grep -c .)
  { echo "sha=$sha"
    echo "subject=$(git log -1 --format=%s "$sha" | tr -d '\n')"
    echo "check=$CHECK"
    echo "source_files=$srcfiles"
    echo "source_file_count=$nsrcfiles"
    echo "test_files=$(testfiles_of "$sha")"
    echo "expect=held"
    echo "note=source-only revert reproduces a failure the parent tree did not have."
    echo "note=red.log is that failure verbatim; witness-test.patch is the test side."
    echo "note=read red.log before trusting this case: the failing test must be one"
    echo "note=witness-test.patch touches, not an unrelated test poisoned by it."
    [ "$nsrcfiles" -gt 1 ] && echo "warn=commit changed $nsrcfiles source files; the fixture is not minimal"
  } > "$d/case.env"
  kept=$((kept+1))
  printf '  CASE %-2d %s  %s\n' "$kept" "${sha:0:8}" "$(git log -1 --format=%s "$sha" | cut -c1-52)"
  git checkout -q --force "$BASE"
done

git checkout -q --force "$ORIG_REF"

discarded=$((skipped_shape + skipped_norevert + skipped_checkout + skipped_notred + skipped_flaky))
{
  echo "# mine_honest.sh — elimination report (gate 2 requires these numbers)"
  echo "repo=$REPO"
  echo "check=$CHECK"
  echo "scan_depth=$DEPTH"
  echo "max_cases=$MAX"
  echo "max_hit=$max_hit"
  echo "scanned=$scanned"
  echo "kept=$kept"
  echo "discarded_total=$discarded"
  echo "discarded_wrong_shape=$skipped_shape"
  echo "discarded_revert_would_not_apply=$skipped_norevert"
  echo "discarded_checkout_failed=$skipped_checkout"
  echo "discarded_did_not_go_red=$skipped_notred"
  echo "discarded_nondeterministic=$skipped_flaky"
} > "$OUT/discards.txt"

echo
echo "scanned $scanned commits -> $kept cases  (cap: $MAX, hit: $max_hit)"
echo "  discarded $discarded:"
echo "    $skipped_shape wrong shape"
echo "    $skipped_norevert revert would not apply"
echo "    $skipped_checkout checkout failed"
echo "    $skipped_notred did not go red"
echo "    $skipped_flaky nondeterministic"
echo "cases in $OUT"
echo "counts in $OUT/discards.txt"
[ "$discarded" -eq 0 ] && echo "  WARNING: zero eliminations. gate 2 treats that as a broken filter, not a clean run."
exit 0
