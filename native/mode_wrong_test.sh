#!/bin/bash
# mode_wrong_test.sh — the two things that happened tonight and left no record.
#
# 1. THE SUPERVISOR WAS SWITCHED OFF AND NOTHING SAID SO.
#    At 02:25 a session ran `rabadon off`. The machine was unguarded from then
#    on and four other sessions running at the same time had no way to know.
#    The only reason it was reconstructable at all is that the TEXT of the
#    command happened to land in a STEP record, which is an accident of another
#    feature. Turning supervision off is the single most consequential thing
#    anyone can do to this tool and it was the one action the ledger did not
#    record as an event. A mode change is now a first-class line: what it was,
#    what it became, and when.
#
# 2. A REFUSAL THAT WAS WRONG HAD NOWHERE TO GO.
#    The standing instruction is: when the gate refuses something it should not
#    have, do not add the rule to disabled[] and do not route around it — record
#    it as a wrong refusal and fix the rule. Tonight produced three of them
#    (a descriptor duplication read as a file write, a `.h` pattern matching
#    `.html`, and a once-per-session challenge firing three times), and all
#    three were recorded in PROSE, in a report, because there was no record type
#    for them.
#
#    That is the number this whole product lives or dies on. Anybody can publish
#    how many commands they refused. The refusal count is only worth something
#    beside the count of refusals that were wrong, and nobody can publish that
#    without a ledger that holds both. So `rabadon wrong <rule> <why>` writes a
#    WRONG_REFUSAL into the same hash-chained ledger, and the site prints it
#    next to the refusals rather than under them.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
[ -x "$GATE" ] || { echo "  build first: make native/rabadon-gate"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export RABADON_DIR="$T/rd"
mkdir -p "$RABADON_DIR/spool"

# every ledger line written during this run, whatever day file it landed in
allrows() { cat "$RABADON_DIR"/spool/*.jsonl 2>/dev/null; }
evs() { allrows | python3 -c "
import json,sys
want=sys.argv[1]
for l in sys.stdin:
    l=l.strip()
    if not l: continue
    try: d=json.loads(l)
    except Exception: continue
    if d.get('ev')==want: print(json.dumps(d,ensure_ascii=False))
" "$1"; }

echo "mode + wrong refusal — the two events the ledger was not keeping"
echo

# ---------------------------------------------------------------------------
# 1. every mode change is a line
# ---------------------------------------------------------------------------
echo "1. switching supervision on and off is recorded"
"$GATE" --on     >/dev/null 2>&1
"$GATE" --off    >/dev/null 2>&1
"$GATE" --toggle >/dev/null 2>&1   # from watch -> enforce
"$GATE" --status >/dev/null 2>&1   # asks, changes nothing, must NOT be recorded

N=$(evs MODE | wc -l | tr -d ' ')
if [ "$N" = "3" ]; then ok "three changes, three lines (and --status wrote none)"
else bad "expected 3 MODE lines, got $N"; evs MODE | sed 's/^/        /'; fi

if evs MODE | python3 -c "
import json,sys
rows=[json.loads(l) for l in sys.stdin]
want=[('watch','enforce'),('enforce','watch'),('watch','enforce')]
got=[(r.get('from'),r.get('to')) for r in rows]
sys.exit(0 if got==want else 1)
"; then ok "each line carries what the mode was and what it became"
else bad "the from/to pairs are wrong"; evs MODE | sed 's/^/        /'; fi

# the loudest one has to be legible without a parser: going dark
if "$GATE" --off 2>&1 | grep -qi "watch"; then ok "the command still says the mode out loud"
else bad "the mode change is silent to the person who typed it"; fi

echo
# ---------------------------------------------------------------------------
# 2. a wrong refusal is a first-class record
# ---------------------------------------------------------------------------
echo "2. a refusal that was wrong can be written down"
"$GATE" --wrong baseline-truncating-redirect "2>&1 is a descriptor duplication, not a write to a file named 1" >/dev/null 2>&1
RC=$?
[ $RC -eq 0 ] && ok "rabadon wrong exits 0" || bad "rabadon wrong exited $RC"

N=$(evs WRONG_REFUSAL | wc -l | tr -d ' ')
if [ "$N" = "1" ]; then ok "one wrong refusal, one line"
else bad "expected 1 WRONG_REFUSAL, got $N"; evs WRONG_REFUSAL | sed 's/^/        /'; fi

if evs WRONG_REFUSAL | python3 -c "
import json,sys
d=json.loads(sys.stdin.readline())
assert d.get('rule')=='baseline-truncating-redirect', d
assert 'descriptor' in (d.get('why') or ''), d
assert d.get('ts'), d
"; then ok "it names the rule and the reason it was wrong"
else bad "the record does not carry rule + why"; evs WRONG_REFUSAL | sed 's/^/        /'; fi

# a rule id with no reason is a complaint, not a record
"$GATE" --wrong some-rule >/dev/null 2>&1
if [ $? -ne 0 ]; then ok "a rule with no reason is refused"
else bad "accepted a wrong-refusal report with no reason"; fi

echo
# ---------------------------------------------------------------------------
# 3. both ride the same hash chain as everything else
# ---------------------------------------------------------------------------
# A number that lives outside the tamper-evident chain is a number somebody can
# edit, and the false-positive count is exactly the number a vendor has the most
# reason to edit.
echo "3. both are inside the tamper-evident chain"
if allrows | python3 -c "
import json,sys
rows=[json.loads(l) for l in sys.stdin if l.strip()]
new=[r for r in rows if r.get('ev') in ('MODE','WRONG_REFUSAL')]
assert new, 'no new events at all'
missing=[r for r in new if not r.get('prev')]
assert not missing, 'events with no prev: %r' % missing[:1]
assert all(r.get('seq') for r in new), 'events with no seq'
"; then ok "every new line carries prev and seq like the rest of the ledger"
else bad "the new events are outside the chain"; fi

AUDIT="$HERE/rabadon-audit"
if [ -x "$AUDIT" ]; then
  if "$AUDIT" --days 2 >/dev/null 2>&1; then ok "rabadon audit still verifies the spool"
  else bad "audit rejects the spool after the new events"; "$AUDIT" --days 2 2>&1 | tail -5 | sed 's/^/        /'; fi
else
  echo "  --    rabadon-audit not built, chain verification skipped"
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
