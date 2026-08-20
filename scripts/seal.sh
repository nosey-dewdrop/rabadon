#!/usr/bin/env bash
# seal.sh — hash every file a phase is forbidden to change (AGENTS-PROTOCOL.md, kapı 3).
#
#   bash scripts/seal.sh <phase> before|after
#   diff reports/phase-<phase>/locks.txt.before reports/phase-<phase>/locks.txt.after
#
# WHY THIS IS A SCRIPT AND NOT A find(1) LINE IN A MARKDOWN FILE
#   The line in the protocol matched *_test.sh and test/* and missed the JS
#   suite entirely — nine live test files in core/, hooks/, ui/ and demo/ could
#   be weakened without the end-of-phase diff noticing. A list that lives in
#   prose drifts from the tree; a list that lives in one script does not, and
#   this one prints its own coverage so a gap is visible instead of silent.
#
# WHAT IS SEALED
#   tests      — anything a phase could weaken to make itself pass
#   fixtures   — corpus and heldout drivers
#   gates      — every accept.sh
#   harness    — the files that decide what "the tests" even means
#   law+ledger — the guard's own rules, the published numbers, the scoreboard
#                (the drift detector's memory is worth sealing: an unsealed
#                 memory can be edited to make drift disappear)

set -u

PHASE="${1:?usage: seal.sh <phase> before|after}"
WHEN="${2:?usage: seal.sh <phase> before|after}"
case "$WHEN" in before|after) ;; *) echo "second argument must be 'before' or 'after'" >&2; exit 2;; esac

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2
DEST="reports/phase-$PHASE/locks.txt.$WHEN"
mkdir -p "$(dirname "$DEST")"

if command -v sha256sum >/dev/null 2>&1; then HASH=sha256sum; else HASH="shasum -a 256"; fi

{
  # tests, fixtures, gates — by name and by location
  find . \( -name node_modules -o -name .git \) -prune -o \
    \( -name '*_test.sh'     -o -path './test/*'      -o -path './tests/*' \
       -o -name '*.test.mjs' -o -name '*.test.js'     -o -name '*_test.py' \
       -o -name '*.spec.mjs' -o -name '*.spec.js' \
       -o -name 'accept.sh'  -o -name 'corpus_*.sh'   -o -name 'heldout_test.sh' \) \
    -type f -print
  # harness: what "the tests" means
  for f in package.json Makefile pytest.ini CMakeLists.txt conftest.py; do
    [ -f "$f" ] && printf './%s\n' "$f"
  done
  # law, published numbers, and the drift detector's own memory
  for f in .rabadon/guard.json site/measured.json reports/scoreboard.tsv; do
    [ -f "$f" ] && printf './%s\n' "$f"
  done
} | sort -u | xargs $HASH > "$DEST"

echo "sealed $(wc -l < "$DEST" | tr -d ' ') files -> $DEST"

# coverage, printed so a gap is visible rather than assumed
MISSED=$(find . \( -name node_modules -o -name .git \) -prune -o \
           \( -name '*test*' -o -name '*spec*' \) -type f -print \
         | sort -u | while read -r f; do grep -q " $f\$" "$DEST" || echo "$f"; done)
if [ -n "$MISSED" ]; then
  echo "  not sealed, and named like a test — look at each one:"
  printf '%s\n' "$MISSED" | sed 's/^/    /'
fi
