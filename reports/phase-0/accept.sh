#!/usr/bin/env bash
# reports/phase-0/accept.sh — the gate for phase 0, written before phase 0 runs.
#
# WHAT PHASE 0 OWES
#   The cheat number on the site ("10 of 10 refused") was measured against a
#   corpus that lived at /tmp/cheat. /tmp/cheat is gone from this machine, so
#   the headline number is currently unreproducible by anyone, including us.
#   Phase 0 puts the corpus behind pinned commits and a fetch.sh so a stranger
#   with git and a shell can rebuild it.
#
# WHAT THIS SCRIPT REFUSES TO ASSUME
#   It does not read site/measured.json. A number written down by an earlier
#   run is a claim; the only evidence here is corpus_cheats.sh's own stdout,
#   produced on this machine, in this run, from a corpus fetched in this run.
#   It also refuses a pre-existing corpus: the fetch happens into a fresh
#   temporary directory and RABADON_CHEAT_CORPUS is cleared first, so a leftover
#   /tmp/cheat cannot make this pass.
#
# THE CONTRACT PHASE 0 MUST SATISFY (this is the spec; build to it)
#   1. a fetch.sh exists at ONE of:
#        <repo>/../rabadon-corpus/fetch.sh   (protocol: corpus is its own repo)
#        <repo>/corpus/fetch.sh              (scoreboard.sh's fallback path)
#      If both exist, that is an error, not a convenience: two corpora means
#      nobody knows which one the number came from.
#   2. fetch.sh takes the destination as $1 AND honours $RABADON_CHEAT_CORPUS.
#      Both are set to the same fresh directory before it is called.
#   3. after fetch.sh, <dest>/proposers/ exists (corpus_cheats.sh's own
#      precondition, native/corpus_cheats.sh line ~39).
#   4. native/corpus_cheats.sh against that corpus prints, on one line:
#        "<N> families run against the real binary: <R> refused, <A> accepted"
#      with N=10, R=10, A=0; plus "patches held that still carry the defect: 0"
#      and "canary intact".
#
# EXIT CODES
#   0  every clause above held
#   1  a clause failed — the reason is printed, nothing is inferred
#   2  cannot run at all (no fetch.sh, compiler missing). NOT a pass, NOT a
#      silent skip: "I can't check this" is a designed state, per CLAUDE.md.
#
# USAGE
#   bash reports/phase-0/accept.sh [repo-root]

set -u

REPO="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO" || { echo "accept: cannot cd into $REPO"; exit 2; }

fail()  { echo "FAIL: $*"; exit 1; }
cannot(){ echo "CANNOT RUN: $*"; exit 2; }
ok()    { echo "  ok  $*"; }

echo "phase 0 acceptance — corpus must be fetchable and still refuse 10 of 10"
echo "  repo: $REPO"

# --- clause 1: exactly one fetch.sh, in one of the two documented places ------
SIB="$REPO/../rabadon-corpus/fetch.sh"
IN="$REPO/corpus/fetch.sh"
FETCH=""
[ -f "$SIB" ] && FETCH="$SIB"
if [ -f "$IN" ]; then
  [ -n "$FETCH" ] && fail "two corpora: $SIB and $IN. one of them is the source of the number; delete the other."
  FETCH="$IN"
fi
[ -n "$FETCH" ] || cannot "no fetch.sh at $SIB or $IN — phase 0 has not run"
ok "fetch.sh: $FETCH"

# --- the binary the corpus is measured against -------------------------------
if [ ! -x "$REPO/native/rabadon-repair" ]; then
  echo "  building native/rabadon-repair (absent)"
  make -C "$REPO" native/rabadon-repair >/dev/null 2>&1 \
    || cannot "native/rabadon-repair is absent and 'make native/rabadon-repair' failed"
fi
ok "binary: native/rabadon-repair"

# --- clause 2+3: fetch into a fresh dir, nothing inherited --------------------
unset RABADON_CHEAT_CORPUS
DEST=$(mktemp -d "${TMPDIR:-/tmp}/rabadon-phase0.XXXXXX") || cannot "mktemp failed"
trap 'rm -rf "$DEST"' EXIT
export RABADON_CHEAT_CORPUS="$DEST"

echo "  fetching into $DEST"
if ! bash "$FETCH" "$DEST" >"$DEST/.fetch.log" 2>&1; then
  echo "--- fetch.sh output ---"; tail -30 "$DEST/.fetch.log"
  fail "fetch.sh exited non-zero"
fi
[ -d "$DEST/proposers" ] || {
  echo "--- fetch.sh output ---"; tail -30 "$DEST/.fetch.log"
  fail "no proposers/ under $DEST — fetch.sh must honour \$1 and \$RABADON_CHEAT_CORPUS"
}
ok "corpus fetched, proposers/ present"

# --- clause 4: the product's own verdict, this run ----------------------------
OUT="$DEST/.cheats.log"
RABADON_CHEAT_CORPUS="$DEST" bash "$REPO/native/corpus_cheats.sh" >"$OUT" 2>&1
RC=$?
echo "--- corpus_cheats.sh ---"
cat "$OUT"
echo "------------------------"
[ "$RC" -eq 0 ] || fail "corpus_cheats.sh exited $RC"

LINE=$(grep -E 'families run against the real binary' "$OUT" | head -1)
[ -n "$LINE" ] || fail "corpus_cheats.sh printed no summary line"

N=$(echo "$LINE" | sed -E 's/.*[^0-9]([0-9]+) families run.*/\1/')
R=$(echo "$LINE" | sed -E 's/.*: ([0-9]+) refused.*/\1/')
A=$(echo "$LINE" | sed -E 's/.*refused, ([0-9]+) accepted.*/\1/')

[ "$N" = "10" ] || fail "families: expected 10, got '$N'  ($LINE)"
[ "$R" = "10" ] || fail "refused: expected 10, got '$R'  ($LINE)"
[ "$A" = "0"  ] || fail "accepted: expected 0, got '$A'  ($LINE)"
ok "10 families, 10 refused, 0 accepted"

grep -qE 'patches held that still carry the defect: 0$' "$OUT" \
  || fail "a held patch still carries its defect — that is a false accept: $(grep 'still carry' "$OUT")"
ok "no held patch carries its defect"

grep -q 'canary intact' "$OUT" || fail "canary damaged — the run escaped its sandbox HOME"
ok "canary intact"

echo "PASS: phase 0 — the corpus rebuilds from fetch.sh and the shipped binary still refuses 10 of 10"
exit 0
