#!/bin/bash
# claims_test.sh — a number in a report has to have a run behind it.
#
# The failure this exists for is not an attack. Nobody is injecting anything.
# It is a session writing down a number that no run produced, and eight of those
# happened here in nine days: a benchmark that subtracted x from x, a fixture
# the measured party had chosen, a precision figure measured in its own
# laboratory, a hash lock that locked 0 of 122 files, a drift check reading the
# drifter's own words, two numbers measured at different moments presented as a
# regression, a rule passed by reading a test's exit code instead of the verdict,
# and a fixture built in the one place the law is switched off.
#
# The ledger already knows which commands ran on this machine. So a report can be
# asked the only question that separates a measurement from a sentence: is the
# command under this number one that was actually run?
#
# WHAT THIS CANNOT DO, said out loud so the number it prints is not read as more
# than it is. The ledger stores the command, clipped to 80 characters, and it
# does NOT store the command's output. So this can prove that a cited command
# ran and it cannot prove the output said what the report claims it said. It
# catches the number that came from nowhere. It does not catch the rigged run.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/rabadon-claims"
[ -x "$BIN" ] || { echo "  build first: make native/rabadon-claims"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export RABADON_DIR="$T/.rabadon"
mkdir -p "$RABADON_DIR/spool"

# a ledger in which exactly two commands were ever run. `step` is what the gate
# writes: the verb, then the command clipped to 80 characters.
python3 - "$RABADON_DIR/spool/2026-08-03.jsonl" <<'PY'
import json, sys
def step(seq, verb, cmd):
    return {"v": 1, "seq": seq, "ts": 1785600000000 + seq, "run": "r%d" % seq,
            "pipe": "proj:session", "ev": "STEP_OK",
            "step": "%s: %s" % (verb, cmd[:80]), "prev": "x" * 64}
rows = [
    step(1, "ran", "./native/gate_bench.sh --iterations 2000"),
    step(2, "ran", "python3 site/field_stats.py"),
    step(3, "ran", "make test"),
]
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY

echo "claims — every number is asked which run produced it"
echo

# ---------------------------------------------------------------------------
# 1. the honest report: every number sits under a command the ledger saw run
# ---------------------------------------------------------------------------
cat > "$T/honest.md" <<'MD'
# session report

The gate judges one command in 2.3 microseconds.

    $ ./native/gate_bench.sh --iterations 2000

The extractor published 448 records and dropped 1 as sensitive.

    $ python3 site/field_stats.py
MD

OUT=$("$BIN" "$T/honest.md" 2>&1); RC=$?
if [ $RC -eq 0 ]; then ok "the honest report passes (exit 0)"
else bad "the honest report was rejected (exit $RC)"; echo "$OUT" | sed 's/^/        /'; fi
if echo "$OUT" | grep -qi "2.3"; then ok "it names the number it checked"
else bad "it does not say which numbers it checked"; echo "$OUT" | sed 's/^/        /'; fi

echo

# ---------------------------------------------------------------------------
# 2. the twin: same shape, same prose, and the command was never run
# ---------------------------------------------------------------------------
# This is the one that matters. Nothing about the sentence is different. The
# only difference is that no run behind it exists.
cat > "$T/fake.md" <<'MD'
# session report

The gate judges one command in 2.3 microseconds.

    $ ./native/gate_bench.sh --iterations 2000

Throughput reached 41,000 commands per second.

    $ ./native/throughput_bench.sh --iterations 2000
MD

OUT=$("$BIN" "$T/fake.md" 2>&1); RC=$?
if [ $RC -ne 0 ]; then ok "the fabricated twin is caught (exit $RC)"
else bad "the fabricated twin passed"; echo "$OUT" | sed 's/^/        /'; fi
if echo "$OUT" | grep -q "throughput_bench"; then ok "it names the command that never ran"
else bad "it does not name the unrun command"; echo "$OUT" | sed 's/^/        /'; fi
if echo "$OUT" | grep -q "41,000\|41000"; then ok "it names the number that has nothing behind it"
else bad "it does not name the unbacked number"; echo "$OUT" | sed 's/^/        /'; fi
# and it must not smear: the number that IS backed stays backed
if echo "$OUT" | grep -qi "2.3"; then ok "the backed number in the same file is still reported"
else bad "a bad neighbour invalidated a good number"; fi

echo

# ---------------------------------------------------------------------------
# 3. a number with no command anywhere near it
# ---------------------------------------------------------------------------
cat > "$T/bare.md" <<'MD'
# session report

Precision climbed to 90.0 percent this week.
MD

OUT=$("$BIN" "$T/bare.md" 2>&1); RC=$?
if [ $RC -ne 0 ]; then ok "a number with no command at all is caught (exit $RC)"
else bad "an unsourced number passed"; echo "$OUT" | sed 's/^/        /'; fi
if echo "$OUT" | grep -qi "90.0"; then ok "it names the unsourced number"
else bad "it does not name the unsourced number"; echo "$OUT" | sed 's/^/        /'; fi

echo

# ---------------------------------------------------------------------------
# 4. the clip. the ledger holds 80 characters of a command, no more
# ---------------------------------------------------------------------------
# 60% of every command in this machine's ledger sits exactly at that boundary,
# so a checker that demands a whole-string match would call almost every real
# report a fabrication. The comparison happens on the prefix the ledger kept.
LONG="./native/gate_bench.sh --iterations 2000 --warmup 500 --report json --out /tmp/bench_result_with_a_very_long_tail.json"
cat > "$T/long.md" <<MD
# session report

The gate judges one command in 2.3 microseconds.

    \$ $LONG
MD
python3 - "$RABADON_DIR/spool/2026-08-03.jsonl" "$LONG" <<'PY'
import json, sys
line = json.dumps({"v": 1, "seq": 9, "ts": 1785600009, "run": "r9", "pipe": "proj:session",
                   "ev": "STEP_OK", "step": "ran: " + sys.argv[2][:80], "prev": "x" * 64},
                  ensure_ascii=False)
open(sys.argv[1], "a", encoding="utf-8").write(line + "\n")
PY
OUT=$("$BIN" "$T/long.md" 2>&1); RC=$?
if [ $RC -eq 0 ]; then ok "a command longer than the clip still matches its ledger line"
else bad "the clip made a real run unmatchable (exit $RC)"; echo "$OUT" | sed 's/^/        /'; fi

echo

# ---------------------------------------------------------------------------
# 5. it says what it cannot do
# ---------------------------------------------------------------------------
# The tool proves a command RAN. It cannot prove the output said what the report
# says it said, because the ledger does not store output. A checker that returns
# a clean verdict without saying that is teaching the reader to trust more than
# was measured.
OUT=$("$BIN" "$T/honest.md" 2>&1)
if echo "$OUT" | grep -qi "output"; then ok "the verdict states the limit: output is not on the ledger"
else bad "the verdict does not state what it cannot check"; echo "$OUT" | sed 's/^/        /'; fi

# ---------------------------------------------------------------------------
# 6. machine-readable, for the site and for a hook
# ---------------------------------------------------------------------------
OUT=$("$BIN" --json "$T/fake.md" 2>&1)
if python3 -c "
import json,sys
d=json.loads(sys.argv[1])
assert d['unbacked'] >= 1, d
assert any(c['verdict'] != 'backed' for c in d['claims']), d
" "$OUT" 2>/dev/null; then ok "--json reports the unbacked count and every claim"
else bad "--json is not machine-readable"; echo "$OUT" | head -5 | sed 's/^/        /'; fi

echo

# ---------------------------------------------------------------------------
# 7. a report cites the command, not the whole line the shell ran
# ---------------------------------------------------------------------------
# A report says `rabadon on`. The ledger holds the line as it was typed:
# `rabadon on 2>&1 | head -20; rabadon status`. Exact matching called that
# unrun, on this tool's own first real report, for a command that had plainly
# been run minutes earlier. A citation that is a PREFIX of a line the ledger saw
# counts, cut on a word boundary so that citing `git` does not match everything.
echo "7. a citation is the command, not the whole line the shell ran"
cat > "$T/prefix.md" <<'MD'
# session report

Enforce mode was armed and it refused 256 commands.

    $ rabadon on
MD
python3 - "$RABADON_DIR/spool/2026-08-03.jsonl" <<'PYEOF'
import json, sys
line = json.dumps({"v": 1, "seq": 20, "ts": 1785600020, "run": "r20", "pipe": "proj:session",
                   "ev": "STEP_OK", "step": "ran: rabadon on 2>&1 | head -20; rabadon status",
                   "prev": "x" * 64}, ensure_ascii=False)
open(sys.argv[1], "a", encoding="utf-8").write(line + "\n")
PYEOF
OUT=$("$BIN" "$T/prefix.md" 2>&1); RC=$?
if [ $RC -eq 0 ]; then ok "a citation that heads a longer ledger line is backed"
else bad "prefix citation still reads as unrun (exit $RC)"; echo "$OUT" | sed 's/^/        /'; fi

# and the boundary holds: one bare word is not a citation of every line
cat > "$T/toobroad.md" <<'MD'
# session report

Something happened 4200 times.

    $ rabadon
MD
OUT=$("$BIN" "$T/toobroad.md" 2>&1); RC=$?
if [ $RC -ne 0 ]; then ok "a bare program name does not match every line starting with it"
else bad "a one-word citation matched anything"; echo "$OUT" | sed 's/^/        /'; fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
