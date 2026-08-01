#!/bin/bash
# stats_test.sh — proof that `rabadon usage` renders the ledger correctly.
#
# The old differential-vs-node harness died with the usage redesign (the JS
# stats block is legacy; the native renderer is the product). These tests pin
# the renderer's CONTRACT on a synthetic spool with a pinned clock
# (RABADON_NOW), pinned TZ and pinned COLUMNS, so every assertion is
# deterministic on any machine:
#   - refusals group by RULE ID (STOP.rule field, run-join fallback,
#     legacy em-dash-prefix fallback)
#   - the rule's why renders under the id; nothing is cut without an ellipsis
#   - WATCH verdicts (WOULD_BLOCK) are a first-class bucket
#   - drills are excluded three ways: emit tag, drill-/fleet-/doctor- marker,
#     self pipes incl. rabadon-bench
#   - headline totals, --project, --full, --json, --md, empty state, --days
set -u
cd "$(dirname "$0")/.."
NATIVE=./native/rabadon-stats
[ -x "$NATIVE" ] || { echo "stats_test: build first (make native/rabadon-stats)"; exit 1; }

ok=0; bad=0
TMP=$(mktemp -d /tmp/rabadon-stats-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
SPOOL="$TMP/rd/spool"; mkdir -p "$SPOOL"

# pinned clock: 2026-01-10T12:00:00Z
NOW=1768046400000
DAY="2026-01-10"
TS1=$((NOW - 3600000))   # 1h ago
TS2=$((NOW - 7200000))   # 2h ago
OLD=$((NOW - 30*86400000)) # 30 days ago

cat > "$SPOOL/$DAY.jsonl" <<EOF
{"v":1,"seq":1,"ts":$TS2,"run":"r1","pipe":"alpha:session","ev":"STEP_START","step":"bash: ls"}
{"v":1,"seq":1,"ts":$TS2,"run":"r2","pipe":"alpha:session","ev":"CHECK_FAIL","step":"Bash","fails":[{"check":"no-force-push-main","why":"force-pushing a shared branch destroys history"}]}
{"v":1,"seq":2,"ts":$TS2,"run":"r2","pipe":"alpha:session","ev":"STOP","reason":"BLOCKED","detail":"command matched deny rule: git push --force origin main"}
{"v":1,"seq":1,"ts":$TS1,"run":"r3","pipe":"alpha:session","ev":"STOP","reason":"BLOCKED","rule":"no-force-push-main","sid":"s1","detail":"command matched deny rule: git push -f origin main"}
{"v":1,"seq":1,"ts":$TS1,"run":"r4","pipe":"alpha:session","ev":"STOP","reason":"BLOCKED","detail":"legacy-rule-prefix — some long explanation after the em dash"}
{"v":1,"seq":1,"ts":$TS1,"run":"r5","pipe":"alpha:session","ev":"WOULD_BLOCK","reason":"no-rm-rf-outside","rule":"no-rm-rf-outside","sid":"s1","detail":"command matched deny rule: rm -rf /"}
{"v":1,"seq":1,"ts":$TS1,"run":"r6","pipe":"alpha:session","ev":"REPAIR_OK","step":"fix"}
{"v":1,"seq":1,"ts":$TS1,"run":"r6b","pipe":"alpha:session","ev":"REPAIR_OK","step":"session-repair","cmd":"npm test","patch":".rabadon/x.patch","locks":3}
{"v":1,"seq":1,"ts":$TS1,"run":"r6c","pipe":"alpha:session","ev":"REPAIR_OK","step":"session-repair","cmd":"npm test","patch":".rabadon/y.patch","locks":0}
{"v":1,"seq":1,"ts":$TS1,"run":"r6d","pipe":"alpha:session","ev":"REPAIR_OK","step":"push-gate","attempt":1,"repair_kind":"testrun"}
{"v":1,"seq":1,"ts":$TS1,"run":"r6e","pipe":"alpha:session","ev":"REPAIR_OK","step":"new gate: no-x","attempt":1,"repair_kind":"rule"}
{"v":1,"seq":1,"ts":$TS1,"run":"r7","pipe":"beta:session","ev":"STEP_START","step":"bash: pwd"}
{"v":1,"seq":1,"ts":$TS1,"run":"r8","pipe":"beta:session","ev":"CHECK_FAIL","step":"Bash","fails":[{"check":"loop-stop","why":"same command 3x"}]}
{"v":1,"seq":1,"ts":$TS1,"run":"d1","pipe":"gamma:session","ev":"STOP","reason":"BLOCKED","rule":"tagged-drill","detail":"x","drill":true}
{"v":1,"seq":1,"ts":$TS1,"run":"d2","pipe":"gamma:session","ev":"STOP","reason":"BLOCKED","rule":"marker-drill","sid":"drill-123","detail":"drill-123 marker"}
{"v":1,"seq":1,"ts":$TS1,"run":"d3","pipe":"rabadon-bench-xyz:session","ev":"STOP","reason":"BLOCKED","rule":"bench-noise","detail":"bench"}
{"v":1,"seq":1,"ts":$OLD,"run":"r9","pipe":"alpha:session","ev":"STOP","reason":"BLOCKED","rule":"too-old","detail":"outside the window"}
EOF

run() { RABADON_DIR="$TMP/rd" RABADON_NOW="$NOW" TZ=UTC COLUMNS=100 $NATIVE "$@"; }

check() { # check <label> <expected-grep-pattern> <text>
  local label="$1" pat="$2" out="$3"
  if printf '%s' "$out" | grep -qE "$pat"; then ok=$((ok+1)); echo "  ok   - $label"
  else bad=$((bad+1)); echo "  FAIL - $label"; echo "    wanted /$pat/ in:"; printf '%s\n' "$out" | sed 's/^/    | /'; fi
}
check_not() {
  local label="$1" pat="$2" out="$3"
  if printf '%s' "$out" | grep -qE "$pat"; then bad=$((bad+1)); echo "  FAIL - $label (found /$pat/)"
  else ok=$((ok+1)); echo "  ok   - $label"; fi
}

echo "stats_test: usage renderer contract"

U="$(run --days 7)"
check "headline totals: 3 refused, 2 gated, 1 repair HELD" '3 refused before they happened · 2 actions gated · 1 repairs held' "$U"
# five REPAIR_OK events, four different facts. The headline may only claim the
# one that is proven: a fix re-checked while the test files were hash-locked.
check "headline keeps unverified out of the held count" '1 repairs held · 2 unverified' "$U"
check "bucket: only a hash-locked fix counts as held" 'repairs held \(locked\): +1' "$U"
check "bucket: locks:0 and no-locks land in unverified" 'repairs unverified: +2' "$U"
check "bucket: a green push-gate suite repaired nothing" 'push gates passed: +1' "$U"
check "bucket: writing a rule repaired nothing" 'rules written: +1' "$U"
check_not "the old lumped counter is gone" 'repairs accepted' "$U"
check "watch bucket in headline" '1 would-have-refused \(watch\)' "$U"
check "rule-id grouping: 2x no-force-push-main (rule field + run-join)" '2x  no-force-push-main' "$U"
check "rule why rendered under the id" 'force-pushing a shared branch destroys history' "$U"
check "legacy detail falls back to em-dash prefix" '1x  legacy-rule-prefix' "$U"
check "watch verdict grouped by rule" '1x  no-rm-rf-outside' "$U"
check "loop counter survives" 'loops stopped: 1' "$U"
check "drills excluded and said so" 'excluded from every number above' "$U"
check_not "emit-tagged drill never counted" 'tagged-drill' "$U"
check_not "drill- marker session never counted" 'marker-drill' "$U"
check_not "rabadon-bench self pipe never counted" 'bench-noise' "$U"
check_not "events outside --days never counted" 'too-old' "$U"
check "last event stamp (TZ=UTC pinned)" 'last event: 2026-01-10 11:00' "$U"

PB="$(run --days 7 --project beta)"
check "--project filters to one project" 'beta' "$PB"
check_not "--project hides the others" 'alpha' "$PB"
check "--full lists each catch with a timestamp" '· 2026-01-10 (10|11):00  command matched deny rule' "$(run --days 7 --full)"

J="$(run --days 7 --json)"
check "--json totals" '"totals":\{"refused":3,"wouldRefuse":1,"gated":2,' "$J"
check "--json rule objects" '\{"rule":"no-force-push-main","n":2,' "$J"
check "--json drills counter" '"drillsExcluded":3' "$J"
check "--json splits the repair buckets too" '"repairsHeld":1,"repairsUnverified":2,"pushGatesPassed":1,"rulesWritten":1' "$J"
check_not "--json no longer ships one lumped repair number" 'repairsAccepted' "$J"

M="$(run --days 7 --md)"
check "--md headline" '\*\*3 refused before they happened' "$M"
check "--md methodology footer" 'drills and self-tests are tagged at emit and excluded' "$M"
check "--md reproducible pointer" 'rabadon usage --days 7' "$M"

# empty state
EMPTY_DIR="$TMP/empty"; mkdir -p "$EMPTY_DIR/spool"
check "empty state points at rabadon drill" 'rabadon drill' "$(RABADON_DIR="$EMPTY_DIR" RABADON_NOW="$NOW" TZ=UTC COLUMNS=100 $NATIVE --days 7)"

# ellipsis contract: a very long why must end in … and fit the width
LONGDIR="$TMP/long"; mkdir -p "$LONGDIR/spool"
LONGWHY=$(printf 'w%.0s' $(seq 1 300))
printf '{"v":1,"seq":1,"ts":%s,"run":"L1","pipe":"alpha:session","ev":"STOP","reason":"BLOCKED","rule":"long-rule","detail":"%s"}\n' "$TS1" "$LONGWHY" > "$LONGDIR/spool/$DAY.jsonl"
LOUT="$(RABADON_DIR="$LONGDIR" RABADON_NOW="$NOW" TZ=UTC COLUMNS=80 $NATIVE --days 7)"
check "long reason ends in an ellipsis, no silent cut" '…' "$LOUT"
# count CHARACTERS, not bytes (macOS awk length is byte-oriented; … is 3 bytes)
LONGEST=$(printf '%s\n' "$LOUT" | python3 -c 'import sys; print(max((len(l.rstrip("\n")) for l in sys.stdin), default=0))')
if [ "$LONGEST" -le 80 ]; then ok=$((ok+1)); echo "  ok   - no line exceeds COLUMNS (longest: $LONGEST)"
else bad=$((bad+1)); echo "  FAIL - line exceeds COLUMNS=80 (longest: $LONGEST)"; fi

# one repo is ONE row. The producers label the pipe by surface: the hooks emit
# "<project>:session", `rabadon do` emits "<project>:do", `rabadon exec` emits
# "<project>:exec" (native/sandbox.cpp). Same repo, same rules — so the ledger
# must fold every suffix back to the project. When it did not, the headline
# artifact printed `proj` and `proj:exec` as two different projects, and the
# more a user leaned on `rabadon exec` the more split the one screen they would
# show someone else became.
XDIR="$TMP/exec"; mkdir -p "$XDIR/spool"
cat > "$XDIR/spool/$DAY.jsonl" <<EOF
{"v":1,"seq":1,"ts":$TS1,"run":"x1","pipe":"proj:session","ev":"CHECK_FAIL","step":"Bash","fails":[{"check":"no-wrangler-deploy","why":"deploys go through CI"}]}
{"v":1,"seq":2,"ts":$TS1,"run":"x1","pipe":"proj:session","ev":"STOP","reason":"BLOCKED","rule":"no-wrangler-deploy","sid":"s1","detail":"command matched deny rule: npx wrangler deploy"}
{"v":1,"seq":1,"ts":$TS1,"run":"x2","pipe":"proj:exec","ev":"CHECK_FAIL","step":"exec","mode":"enforce","fails":[{"check":"no-wrangler-deploy","why":"command matched deny rule: npx wrangler deploy — deploys go through CI"}]}
{"v":1,"seq":2,"ts":$TS1,"run":"x2","pipe":"proj:exec","ev":"STOP","reason":"BLOCKED","rule":"no-wrangler-deploy","sid":"exec","detail":"command matched deny rule: npx wrangler deploy"}
{"v":1,"seq":1,"ts":$TS1,"run":"x3","pipe":"proj:do","ev":"CHECK_FAIL","step":"Bash","fails":[{"check":"no-wrangler-deploy","why":"deploys go through CI"}]}
EOF
xrun() { RABADON_DIR="$XDIR" RABADON_NOW="$NOW" TZ=UTC COLUMNS=100 $NATIVE "$@"; }
X="$(xrun --days 7)"
# positive first: the row that MUST be there, with every surface's events on it
check "session+exec+do fold into one row named proj" '^  proj +last event: 2026-01-10 11:00' "$X"
check "both catches counted on that one row" 'caught before happening:  2' "$X"
check "all three checks counted on that one row" 'checks failed \(caught\):   3' "$X"
check "one rule, counted twice, not once on each of two rows" '2x  no-wrangler-deploy' "$X"
# only now the negatives — a rename of the suffix cannot make these pass alone
check_not "no phantom project from the exec pipe" 'proj:exec' "$X"
check_not "no phantom project from the do pipe" 'proj:do' "$X"
# and exactly one row exists, whatever it is called (python3: macOS grep has no -P)
XROWS=$(printf '%s\n' "$X" | python3 -c 'import sys,re; print(sum(1 for l in sys.stdin if re.match(r"^  \S.*last event: ", l)))')
if [ "$XROWS" -eq 1 ]; then ok=$((ok+1)); echo "  ok   - exactly one project row (rows: $XROWS)"
else bad=$((bad+1)); echo "  FAIL - one repo rendered as $XROWS rows"; printf '%s\n' "$X" | sed 's/^/    | /'; fi
XSECT=$(printf '%s\n' "$(xrun --days 7 --md)" | python3 -c 'import sys; print(",".join(l.strip() for l in sys.stdin if l.startswith("## ")))')
if [ "$XSECT" = "## proj" ]; then ok=$((ok+1)); echo "  ok   - report (--md) has one section: $XSECT"
else bad=$((bad+1)); echo "  FAIL - report (--md) sections: $XSECT"; fi

echo "stats: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
