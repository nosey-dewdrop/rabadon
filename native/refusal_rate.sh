#!/bin/bash
# refusal_rate.sh — the false-reject rate, derived from the LEDGER instead of
# counted by hand.
#
# WHY THIS EXISTS. CLAUDE.md: "False rejects are counted, not excused... the
# count is published either way." Until this script the count was produced by a
# human reading a transcript, and a hand count has three failure modes that a
# guard tool cannot afford: it drifts from the ledger, it has no denominator, and
# it cannot be re-run by the person checking the claim. The number published for
# this run — "4 events / 2 classes", "catch 4" — is a hand count. It is NOT
# deleted and it is NOT compared with anything below: it was produced by a
# different method against a different population, and quietly replacing it with
# a ledger number would be the same move as redefining a gate.
#
# WHAT IT READS. ~/.rabadon/spool/*.jsonl, read-only, no network, no model call.
#   denominator  ev=STOP with reason=BLOCKED   (a refusal that stopped an action)
#                ev=WOULD_BLOCK                (a refusal watch mode only recorded)
#   numerator    ev=WRONG_REFUSAL              (a refusal a human declared wrong,
#                                               written only by `rabadon wrong`)
#
# WHY A SCOPE IS REQUIRED. The spool is one file per DAY across every project on
# the machine — stitchu, fixed, damummyphus:cli all write into the same lines as
# this run. An unfiltered count answers a question nobody asked. The scope is a
# `sid` prefix and it is an argument, not a default guess.
#
# TWO DEFINITIONS, BOTH PRINTED. S13 asks for STOP+WOULD_BLOCK. The number this
# project has published so far ("15 refusals") counted STOP ALONE. Those are
# different populations and either one can be the right question, so this script
# prints both and says which is which. Declaring one of them "the" number and
# dropping the other is how a metric starts lying.
#
# Needs: bash, grep, sed, sort, awk. No python3, no jq, no node.
set -u
export LC_ALL=C

SPOOL="${RABADON_SPOOL:-$HOME/.rabadon/spool}"
SID="${1:-}"

if [ -z "$SID" ]; then
  echo "usage: bash native/refusal_rate.sh <sid-prefix> [spool-dir]" >&2
  echo "  the sid prefix is not optional: one spool file holds every project on" >&2
  echo "  this machine, and an unscoped count is a wrong number, not a rough one." >&2
  exit 2
fi
[ -n "${2:-}" ] && SPOOL="$2"
[ -d "$SPOOL" ] || { echo "I can't check this: no ledger directory at $SPOOL"; exit 1; }

FILES=$(ls "$SPOOL"/*.jsonl 2>/dev/null)
[ -n "$FILES" ] || { echo "I can't check this: no *.jsonl in $SPOOL"; exit 1; }

NOW_EPOCH=$(date -u +%s)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# every line of this run's scope, frozen into one temp file so that every count
# below is taken from the SAME bytes. The ledger is append-only and live: two
# greps a second apart can legitimately disagree, and a rate whose numerator and
# denominator came from different moments is not a rate.
FROZEN=$(mktemp "${TMPDIR:-/tmp}/rbrate.XXXXXX") || exit 1
ALL=$(mktemp "${TMPDIR:-/tmp}/rbrateall.XXXXXX") || exit 1
trap 'rm -f "$FROZEN" "$ALL"' EXIT
cat $FILES > "$ALL"
grep -F "\"sid\":\"$SID" "$ALL" > "$FROZEN" 2>/dev/null

rules_of() { sed -n 's/.*"rule":"\([^"]*\)".*/\1/p' | sort | uniq -c | sort -rn; }
n_of() { grep -c . 2>/dev/null || true; }

STOPS=$(grep '"ev":"STOP"' "$FROZEN" | grep '"reason":"BLOCKED"')
WOULDS=$(grep '"ev":"WOULD_BLOCK"' "$FROZEN")
NSTOP=$(printf '%s' "$STOPS" | grep -c . )
NWOULD=$(printf '%s' "$WOULDS" | grep -c . )
NBOTH=$((NSTOP + NWOULD))

LASTTS=$(sed -n 's/.*"ts":\([0-9]*\).*/\1/p' "$FROZEN" | sort -n | tail -1)
FIRSTTS=$(sed -n 's/.*"ts":\([0-9]*\).*/\1/p' "$FROZEN" | sort -n | head -1)

echo "rabadon refusal rate — denominator from the ledger, not from a transcript"
echo "measured at : $NOW_ISO  (epoch ${NOW_EPOCH}s)"
echo "frozen at   : last scoped ledger ts = ${LASTTS:-none}  (first = ${FIRSTTS:-none})"
echo "scope       : sid prefix $SID"
echo "ledger      : $SPOOL  ($(printf '%s\n' $FILES | grep -c .) day files, $(grep -c . "$ALL") lines, $(grep -c . "$FROZEN") in scope)"
echo "LIVE        : this ledger is append-only and this run is still writing to it."
echo "              Re-running this script later legitimately returns a BIGGER"
echo "              denominator. Every number below belongs to the frozen ts above."
echo

echo "== A. denominator, definition 1: ev=STOP and reason=BLOCKED =="
echo "   (this is the definition behind the '15 refusals' published in SAPMA-KARARLARI)"
printf '%s\n' "$STOPS" | rules_of | sed 's/^/   /'
echo "   TOTAL $NSTOP"
echo

echo "== B. denominator, definition 2: STOP+BLOCKED plus ev=WOULD_BLOCK =="
echo "   (this is the definition S13/a asks for; watch-mode refusals count too)"
{ printf '%s\n' "$STOPS"; printf '%s\n' "$WOULDS"; } | grep . | rules_of | sed 's/^/   /'
echo "   TOTAL $NBOTH   ( STOP $NSTOP + WOULD_BLOCK $NWOULD )"
echo

echo "== C. numerator: ev=WRONG_REFUSAL, by rule =="
echo "   NOT SCOPED, and this is a measured hole, not a shortcut: a WRONG_REFUSAL"
echo "   line carries no sess, no sid and no call — only rule, why, ts. So a"
echo "   numerator cannot be joined to the individual refusal it belongs to, and"
echo "   cannot be filtered to this run at all. The join happens on the RULE NAME"
echo "   only. Fixing the record shape is out of this card's scope; the gap is"
echo "   named here so no reader mistakes the join for a tight one."
WRONGS=$(grep '"ev":"WRONG_REFUSAL"' "$ALL")
NWRONG=$(printf '%s' "$WRONGS" | grep -c . )
printf '%s\n' "$WRONGS" | grep . | rules_of | sed 's/^/   /'
echo "   TOTAL $NWRONG  (whole machine, every project, every day in the spool)"
echo

echo "== D. rate, per rule =="
echo "   n < 10 prints RAW COUNTS and no ratio. A percentage over a handful of"
echo "   events is a number with no error bar, and printing one without its"
echo "   denominator is forbidden in this project."
printf '   %-34s %-14s %-14s %s\n' "rule" "wrong/STOP" "wrong/STOP+WB" "rate"
{
  printf '%s\n' "$STOPS" | sed -n 's/.*"rule":"\([^"]*\)".*/D1 \1/p'
  printf '%s\n' "$WOULDS" | sed -n 's/.*"rule":"\([^"]*\)".*/D2 \1/p'
  printf '%s\n' "$WRONGS" | sed -n 's/.*"rule":"\([^"]*\)".*/W  \1/p'
} | grep . | awk '
  $1=="D1"{d1[$2]++; d2[$2]++; seen[$2]=1}
  $1=="D2"{d2[$2]++; seen[$2]=1}
  $1=="W" {w[$2]++;  seen[$2]=1}
  END{
    for (r in seen) {
      a=d1[r]+0; b=d2[r]+0; x=w[r]+0
      if (b>=10) rate=sprintf("%.1f%% of %d",100*x/b,b); else rate="n<10 — raw counts only"
      # a numerator with a ZERO denominator is not a rate and not an error: the
      # wrong refusal was declared on this machine under a rule this run never
      # tripped. It is printed, labelled, and never divided.
      if (b==0) rate="wrong declared OUT OF SCOPE (no refusal by this rule in scope)"
      printf "   %-34s %-14s %-14s %s\n", r, x"/"a, x"/"b, rate
    }
  }' | sort
echo
if [ "$NBOTH" -lt 10 ]; then
  echo "   OVERALL: $NWRONG wrong / $NSTOP STOP / $NBOTH STOP+WOULD_BLOCK — n<10, raw counts only"
else
  echo "   OVERALL: $NWRONG wrong / $NSTOP STOP / $NBOTH STOP+WOULD_BLOCK"
  echo "            (the OVERALL numerator is machine-wide, see C: it is an upper"
  echo "             bound on this run's wrong refusals, not this run's count)"
fi
echo
echo "== E. what this script does NOT measure =="
echo "   - a refusal nobody declared wrong is counted as CORRECT here. Silence is"
echo "     not evidence; native/refusal_rate.sh cannot tell a right refusal from"
echo "     an unreported wrong one."
echo "   - WRONG_REFUSAL cannot be scoped to a run (C), so wrong/denominator mixes"
echo "     one machine's numerator with one run's denominator."
echo "   - the hand-counted numbers published for this run ('4 events / 2 classes',"
echo "     'catch 4') are a DIFFERENT method on a DIFFERENT population. They stand"
echo "     as written and are not compared with anything above."
exit 0
