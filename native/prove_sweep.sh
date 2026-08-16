#!/usr/bin/env bash
# prove_sweep.sh — what does `rabadon prove` say about real merged code?
#
# One number decides whether a proof gate is a product or a curiosity: over real
# pull requests that real maintainers reviewed and merged, how often can it
# reach a verdict at all? A gate that answers "I cannot tell" most of the time is
# honest and useless, and finding that out from two hand-picked commits is how
# you fool yourself.
#
# So this walks a repository's actual history. For each commit that touches BOTH
# source and tests — the shape that claims a behaviour and claims to check it —
# it reconstructs the tree at that commit, hands `rabadon prove` the commit's own
# diff, and records the verdict. Nothing is selected by hand and nothing is
# skipped for being inconvenient; a commit that breaks the harness is recorded as
# breaking the harness.
#
# WHAT A ROW MEANS
#   PROVEN*                 removing the source turned the suite red
#   TEST_PASSES_BOTH_WAYS   the commit ships tests that pass without it
#   NO_COUNTERFACTUAL       no red could be produced (with a reason)
#   FLAKY_CHECK             the samples disagreed
#   NO_TRUTH / MIXED / ...   see rabadon prove --help
#
# usage:
#   prove_sweep.sh --url <git-url> --cmd "<check>" [--setup "<cmd>"]
#                  [--n 20] [--since <rev>] [--out <dir>]
#
# The --setup command runs once per checkout, before the check, and is where a
# repository's environment gets built (npm install, pip install -e .). It is
# separate from --cmd on purpose: setup failing and the suite failing are
# different facts and a sweep that confuses them measures nothing.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PROVE="$HERE/rabadon-prove"
[ -x "$PROVE" ] || { echo "build first: make native/rabadon-prove"; exit 1; }

URL=""; CHECK=""; SETUP=""; N=20; SINCE=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --cmd) CHECK="$2"; shift 2 ;;
    --setup) SETUP="$2"; shift 2 ;;
    --n) N="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "prove_sweep: unknown flag $1" >&2; exit 2 ;;
  esac
done
[ -n "$URL" ] && [ -n "$CHECK" ] || { echo "prove_sweep: --url and --cmd are required"; exit 2; }

NAME="$(basename "$URL" .git)"
[ -n "$OUT" ] || OUT="$(mktemp -d)/sweep-$NAME"
mkdir -p "$OUT"
CLONE="$OUT/repo"
LOGS="$OUT/logs"; mkdir -p "$LOGS"
TSV="$OUT/verdicts.tsv"
: > "$TSV"

echo "prove sweep — $NAME"
echo "  check : $CHECK"
[ -n "$SETUP" ] && echo "  setup : $SETUP"
echo "  out   : $OUT"
echo

if [ ! -d "$CLONE/.git" ]; then
  git clone -q "$URL" "$CLONE" || { echo "clone failed"; exit 1; }
fi

# Commits that touch source AND tests. Chosen by the shape of the change, not by
# whether the result will look good: a commit is a candidate the moment it edits
# a file under a test path and a file that is not under one.
RANGE="HEAD"
[ -n "$SINCE" ] && RANGE="$SINCE..HEAD"
CANDS="$OUT/candidates.txt"
git -C "$CLONE" log --format=%H "$RANGE" | head -400 | while read -r sha; do
  files="$(git -C "$CLONE" show --name-only --format= "$sha")"
  echo "$files" | grep -qE '(^|/)(tests?|spec)/|_test\.|\.test\.|\.spec\.|_spec\.|^test_|/test_' || continue
  echo "$files" | grep -vqE '(^|/)(tests?|spec)/|_test\.|\.test\.|\.spec\.|_spec\.|^test_|/test_|\.md$|\.rst$|\.txt$' || continue
  echo "$sha"
done | head -"$N" > "$CANDS"

TOTAL="$(wc -l < "$CANDS" | tr -d ' ')"
echo "  $TOTAL commit(s) touch both source and tests"
echo

i=0
while read -r sha; do
  i=$((i+1))
  subj="$(git -C "$CLONE" log -1 --format=%s "$sha" | cut -c1-58)"
  printf '  [%2d/%2d] %s  %s\n' "$i" "$TOTAL" "${sha:0:9}" "$subj"

  git -C "$CLONE" checkout -q "$sha" 2>/dev/null || {
    printf '%s\t%s\tCHECKOUT_FAILED\t%s\n' "$sha" "-" "$subj" >> "$TSV"; continue; }
  git -C "$CLONE" clean -qfdx -e node_modules 2>/dev/null

  if [ -n "$SETUP" ]; then
    if ! ( cd "$CLONE" && eval "$SETUP" ) > "$LOGS/$sha.setup.log" 2>&1; then
      printf '%s\t%s\tSETUP_FAILED\t%s\n' "$sha" "-" "$subj" >> "$TSV"
      printf '        SETUP_FAILED\n'
      continue
    fi
  fi

  git -C "$CLONE" show "$sha" > "$OUT/$sha.patch"
  "$PROVE" --dir "$CLONE" --patch "$OUT/$sha.patch" --cmd "$CHECK" --timeout 900 \
      > "$LOGS/$sha.prove.log" 2>&1
  rc=$?
  v="$(grep -o 'verdict: [A-Z_]*' "$LOGS/$sha.prove.log" | head -1 | sed 's/verdict: //')"
  [ -n "$v" ] || v="NO_OUTPUT"
  printf '%s\t%s\t%s\t%s\n' "$sha" "$rc" "$v" "$subj" >> "$TSV"
  printf '        %s (exit %s)\n' "$v" "$rc"
done < "$CANDS"

echo
echo "  verdict distribution"
awk -F'\t' '{c[$3]++} END {for (k in c) printf "    %-24s %3d\n", k, c[k]}' "$TSV" | sort -k2 -rn
echo
DECIDED="$(awk -F'\t' '$3 ~ /^(PROVEN|PROVEN_WITH_TEST_EDIT|PROVEN_WEAK_RUNG|TEST_PASSES_BOTH_WAYS)$/' "$TSV" | wc -l | tr -d ' ')"
RUN="$(awk -F'\t' '$3 !~ /^(SETUP_FAILED|CHECKOUT_FAILED)$/' "$TSV" | wc -l | tr -d ' ')"
echo "  decided: $DECIDED of $RUN commit(s) the harness could actually run"
echo "  rows   : $TSV"
