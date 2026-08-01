#!/usr/bin/env bash
# rabadon-trace routing view — renderer proof, deterministic, no LLM and no
# claude -p anywhere. The spool below is written by hand precisely so the thing
# under test is the ARITHMETIC AND THE WORDING of the A/B block, not a model:
# does it add the rejected cheap attempts into the routed arm, does it get the
# direction right, and does it say "routed lost" out loud when routing loses.
# (These numbers are a fixture. The real ones only ever come from route_demo.sh,
# where both arms are actually run and each is priced by the model itself.)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TRACE="$HERE/rabadon-trace"
[ -x "$TRACE" ] || { echo "build first: make"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---- fixture 1: routing WINS (4 cheap steps proven, 1 escalated) ----
S="$TMP/win.jsonl"
{
# routed arm: 5 steps on haiku, step 3 rejected by the arbiter -> opus
echo '{"v":1,"ts":1000,"run":"loop-r","pipe":"demo:do","ev":"RUN_START","goal":"ship the rollup","steps":5,"arm":"routed","tiers":"haiku,opus","bound":{"maxRepairsPerStep":1}}'
for i in 1 2; do
echo "{\"v\":1,\"ts\":10$i,\"run\":\"loop-r\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"s$i\",\"tiers\":\"haiku,opus\"}"
echo "{\"v\":1,\"ts\":11$i,\"run\":\"loop-r\",\"pipe\":\"demo:do\",\"ev\":\"STEP_TRY\",\"step\":\"s$i\",\"tier\":1,\"tier_name\":\"haiku\",\"tokens\":12000,\"in\":9000,\"out\":3000,\"usd_e6\":20000,\"dur_ms\":9000,\"model\":\"claude-haiku-4-5-20251001\"}"
echo "{\"v\":1,\"ts\":12$i,\"run\":\"loop-r\",\"pipe\":\"demo:do\",\"ev\":\"STEP_OK\",\"step\":\"s$i\",\"tier\":1,\"tier_name\":\"haiku\"}"
done
# the escalated one: cheap try burns money AND still gets rejected
echo '{"v":1,"ts":1300,"run":"loop-r","pipe":"demo:do","ev":"STEP_START","step":"s3","tiers":"haiku,opus"}'
echo '{"v":1,"ts":1310,"run":"loop-r","pipe":"demo:do","ev":"STEP_TRY","step":"s3","tier":1,"tier_name":"haiku","tokens":11000,"in":8000,"out":3000,"usd_e6":18000,"dur_ms":8000,"model":"claude-haiku-4-5-20251001"}'
echo '{"v":1,"ts":1320,"run":"loop-r","pipe":"demo:do","ev":"CHECK_FAIL","step":"s3","tier":1,"tier_name":"haiku","fails":[{"check":"contract","why":"FAIL testsuite [python3 spec_test.py]: the project’s own suite is RED (exit 1)\nSUITE RED — failing: wrap_text_edge"}]}'
echo '{"v":1,"ts":1330,"run":"loop-r","pipe":"demo:do","ev":"ESCALATE","step":"s3","from":"haiku","to":"opus","why":"suite RED"}'
echo '{"v":1,"ts":1340,"run":"loop-r","pipe":"demo:do","ev":"STEP_TRY","step":"s3","tier":2,"tier_name":"opus","tokens":90000,"in":80000,"out":10000,"usd_e6":300000,"dur_ms":40000,"model":"claude-opus-4-8[1m]"}'
echo '{"v":1,"ts":1350,"run":"loop-r","pipe":"demo:do","ev":"STEP_OK","step":"s3","tier":2,"tier_name":"opus"}'
for i in 4 5; do
echo "{\"v\":1,\"ts\":14$i,\"run\":\"loop-r\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"s$i\",\"tiers\":\"haiku,opus\"}"
echo "{\"v\":1,\"ts\":15$i,\"run\":\"loop-r\",\"pipe\":\"demo:do\",\"ev\":\"STEP_TRY\",\"step\":\"s$i\",\"tier\":1,\"tier_name\":\"haiku\",\"tokens\":12000,\"in\":9000,\"out\":3000,\"usd_e6\":20000,\"dur_ms\":9000,\"model\":\"claude-haiku-4-5-20251001\"}"
echo "{\"v\":1,\"ts\":16$i,\"run\":\"loop-r\",\"pipe\":\"demo:do\",\"ev\":\"STEP_OK\",\"step\":\"s$i\",\"tier\":1,\"tier_name\":\"haiku\"}"
done
echo '{"v":1,"ts":1700,"run":"loop-r","pipe":"demo:do","ev":"RUN_DONE","verdict":"PASS"}'
# control arm: identical plan, every step on opus
echo '{"v":1,"ts":2000,"run":"loop-c","pipe":"demo:do","ev":"RUN_START","goal":"ship the rollup","steps":5,"arm":"control","tiers":"opus","bound":{"maxRepairsPerStep":1}}'
for i in 1 2 3 4 5; do
echo "{\"v\":1,\"ts\":20$i,\"run\":\"loop-c\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"s$i\",\"tiers\":\"opus\"}"
echo "{\"v\":1,\"ts\":21$i,\"run\":\"loop-c\",\"pipe\":\"demo:do\",\"ev\":\"STEP_TRY\",\"step\":\"s$i\",\"tier\":1,\"tier_name\":\"opus\",\"tokens\":90000,\"in\":80000,\"out\":10000,\"usd_e6\":280000,\"dur_ms\":40000,\"model\":\"claude-opus-4-8[1m]\"}"
echo "{\"v\":1,\"ts\":22$i,\"run\":\"loop-c\",\"pipe\":\"demo:do\",\"ev\":\"STEP_OK\",\"step\":\"s$i\",\"tier\":1,\"tier_name\":\"opus\"}"
done
echo '{"v":1,"ts":2300,"run":"loop-c","pipe":"demo:do","ev":"RUN_DONE","verdict":"PASS"}'
} > "$S"

OUT="$("$TRACE" "$S" --no-color)"
# routed total = 4*20000 + 18000 + 300000 = 398000 e6 = $0.3980
# control total = 5*280000 = 1400000 e6 = $1.4000  -> delta $1.0020 (72%)
echo "$OUT" | grep -q '\$0.3980' && ok "routed arm total includes the REJECTED cheap attempt (\$0.3980)" || bad "routed total wrong: $(echo "$OUT" | grep routed)"
echo "$OUT" | grep -q '\$1.4000' && ok "control arm total is the sum of its own measured calls (\$1.4000)" || bad "control total wrong"
echo "$OUT" | grep -q '\$1.0020 kept (72%)' && ok "delta + percent are computed from the two arms (\$1.0020, %72)" || bad "delta line wrong: $(echo "$OUT" | grep -i delta)"
echo "$OUT" | grep -q 'PROVEN CHEAP 4/5' && ok "counts 4/5 steps as proven-cheap, 1 escalated" || bad "cheap/escalated counters wrong"
echo "$OUT" | grep -q 'the cheap answer was NOT PROVEN' && ok "the rejected cheap answer is shown with the failing check" || bad "escalation detail line missing"
echo "$OUT" | grep -q '↑ retried with opus' && ok "the climb to the expensive tier is drawn under the step" || bad "escalation climb line missing"

# ---- fixture 2: routing LOSES — the report must say so, not hide it ----
S2="$TMP/lose.jsonl"
{
echo '{"v":1,"ts":1000,"run":"loop-r2","pipe":"demo:do","ev":"RUN_START","steps":2,"arm":"routed","tiers":"haiku,opus","bound":{"maxRepairsPerStep":1}}'
for i in 1 2; do
echo "{\"v\":1,\"ts\":10$i,\"run\":\"loop-r2\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"s$i\",\"tiers\":\"haiku,opus\"}"
echo "{\"v\":1,\"ts\":11$i,\"run\":\"loop-r2\",\"pipe\":\"demo:do\",\"ev\":\"STEP_TRY\",\"step\":\"s$i\",\"tier\":1,\"tier_name\":\"haiku\",\"tokens\":12000,\"usd_e6\":20000,\"dur_ms\":9000,\"model\":\"claude-haiku-4-5-20251001\"}"
echo "{\"v\":1,\"ts\":12$i,\"run\":\"loop-r2\",\"pipe\":\"demo:do\",\"ev\":\"CHECK_FAIL\",\"step\":\"s$i\",\"tier\":1,\"fails\":[{\"check\":\"contract\",\"why\":\"FAIL testsuite: RED\"}]}"
echo "{\"v\":1,\"ts\":13$i,\"run\":\"loop-r2\",\"pipe\":\"demo:do\",\"ev\":\"ESCALATE\",\"step\":\"s$i\",\"from\":\"haiku\",\"to\":\"opus\",\"why\":\"RED\"}"
echo "{\"v\":1,\"ts\":14$i,\"run\":\"loop-r2\",\"pipe\":\"demo:do\",\"ev\":\"STEP_TRY\",\"step\":\"s$i\",\"tier\":2,\"tier_name\":\"opus\",\"tokens\":90000,\"usd_e6\":300000,\"dur_ms\":40000,\"model\":\"claude-opus-4-8[1m]\"}"
echo "{\"v\":1,\"ts\":15$i,\"run\":\"loop-r2\",\"pipe\":\"demo:do\",\"ev\":\"STEP_OK\",\"step\":\"s$i\",\"tier\":2,\"tier_name\":\"opus\"}"
done
echo '{"v":1,"ts":1700,"run":"loop-r2","pipe":"demo:do","ev":"RUN_DONE","verdict":"PASS"}'
echo '{"v":1,"ts":2000,"run":"loop-c2","pipe":"demo:do","ev":"RUN_START","steps":2,"arm":"control","tiers":"opus","bound":{"maxRepairsPerStep":1}}'
for i in 1 2; do
echo "{\"v\":1,\"ts\":20$i,\"run\":\"loop-c2\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"s$i\",\"tiers\":\"opus\"}"
echo "{\"v\":1,\"ts\":21$i,\"run\":\"loop-c2\",\"pipe\":\"demo:do\",\"ev\":\"STEP_TRY\",\"step\":\"s$i\",\"tier\":1,\"tier_name\":\"opus\",\"tokens\":90000,\"usd_e6\":300000,\"dur_ms\":40000,\"model\":\"claude-opus-4-8[1m]\"}"
echo "{\"v\":1,\"ts\":22$i,\"run\":\"loop-c2\",\"pipe\":\"demo:do\",\"ev\":\"STEP_OK\",\"step\":\"s$i\",\"tier\":1,\"tier_name\":\"opus\"}"
done
echo '{"v":1,"ts":2300,"run":"loop-c2","pipe":"demo:do","ev":"RUN_DONE","verdict":"PASS"}'
} > "$S2"

OUT2="$("$TRACE" "$S2" --no-color)"
# routed 2*(20000+300000)=640000 vs control 600000 -> routing LOST by $0.0400
echo "$OUT2" | grep -q 'routing came out MORE expensive' && ok "when routing loses, the report says it lost (no hiding)" || bad "loss case not reported: $(echo "$OUT2" | grep -i delta)"
echo "$OUT2" | grep -q '\-\$0.0400' && ok "the loss is quantified (-\$0.0400), same measured way" || bad "loss amount wrong"

# ---- fixture 3: a single-arm run must NOT print an A/B ----
S3="$TMP/one.jsonl"; grep 'loop-r"' "$S" > "$S3"
# A NEGATIVE assertion has to be pinned to a string that still exists, or it
# passes because the needle was renamed rather than because the haystack is
# clean. This one grepped for the pre-translation wording and would have gone
# on passing even if a one-armed run DID print a comparison. So the positive
# case is asserted first: the two-arm fixture MUST print the banner, which
# proves the needle is real before the single-arm case asserts its absence.
"$TRACE" "$S" --no-color | grep -q 'MEASURED A/B' \
  && ok "the A/B banner exists to look for (two-arm fixture prints it)" \
  || bad "the A/B banner string is gone — the single-arm check below would be vacuous"
"$TRACE" "$S3" --no-color | grep -q 'MEASURED A/B' \
  && bad "printed an A/B comparison with only one arm on the ledger" \
  || ok "no second arm -> no comparison printed (never a half-measured claim)"

# ---- fixture 4: the ledger must not count a NON-repair as a repair ----
# The gate emits REPAIR_OK when it installs a guard rule, and when it merely
# observes a green test run before a push. Neither repaired anything. Before
# this was marked, a session spool rendered "TAMIR 2" with zero repairs in it —
# a number an investor can check by hand, and the fastest way to lose them.
S4="$TMP/notrepair.jsonl"
{
echo '{"v":1,"ts":1000,"run":"sess-1","pipe":"demo:session","ev":"RUN_START","steps":1}'
echo '{"v":1,"ts":1010,"run":"sess-1","pipe":"demo:session","ev":"STEP_START","step":"Edit"}'
echo '{"v":1,"ts":1020,"run":"sess-1","pipe":"demo:session","ev":"CHECK_FAIL","step":"Edit","fails":[{"check":"net-turned-red","why":"FAIL testsuite: RED"}]}'
echo '{"v":1,"ts":1030,"run":"sess-1","pipe":"demo:session","ev":"REPAIR_OK","step":"new gate: no-force-push","attempt":1,"repair_kind":"rule"}'
echo '{"v":1,"ts":1040,"run":"sess-1","pipe":"demo:session","ev":"REPAIR_OK","step":"push-gate","attempt":1,"repair_kind":"testrun"}'
echo '{"v":1,"ts":1050,"run":"sess-1","pipe":"demo:session","ev":"STEP_OK","step":"Edit"}'
echo '{"v":1,"ts":1060,"run":"sess-1","pipe":"demo:session","ev":"RUN_DONE","verdict":"PASS"}'
} > "$S4"
OUT4="$("$TRACE" "$S4" --no-color)"
echo "$OUT4" | grep -q 'REPAIRED 0'   && ok "installing a rule and observing a green run are NOT counted as repairs (REPAIRED 0)"   || bad "the ledger counted a non-repair as a repair: $(echo "$OUT4" | grep -i 'REPAIRED')"

# and the real thing still counts
S5="$TMP/realrepair.jsonl"
{
echo '{"v":1,"ts":1000,"run":"loop-x","pipe":"demo:do","ev":"RUN_START","steps":1}'
echo '{"v":1,"ts":1010,"run":"loop-x","pipe":"demo:do","ev":"STEP_START","step":"s1"}'
echo '{"v":1,"ts":1020,"run":"loop-x","pipe":"demo:do","ev":"CHECK_FAIL","step":"s1","fails":[{"check":"contract","why":"FAIL testsuite: RED"}]}'
echo '{"v":1,"ts":1030,"run":"loop-x","pipe":"demo:do","ev":"REPAIR_OK","step":"s1","attempt":1,"tokens":1000,"usd_e6":5000}'
echo '{"v":1,"ts":1040,"run":"loop-x","pipe":"demo:do","ev":"STEP_OK","step":"s1"}'
echo '{"v":1,"ts":1050,"run":"loop-x","pipe":"demo:do","ev":"RUN_DONE","verdict":"PASS"}'
} > "$S5"
"$TRACE" "$S5" --no-color | grep -q 'REPAIRED 1'   && ok "a real repair from the loop is still counted (REPAIRED 1)" || bad "a genuine repair stopped counting"

# ---- fixture 6: rabadon must not count its OWN self-tests as catches --------
# drill.h is the single definition of "this spool line is rabadon's own noise",
# and its header names TWO readers of the spool. There are three. trace carried
# no copy of the rules at all, so the exact 18 events of a `do-test:do` self-run
# rendered "CAUGHT 2 · REPAIRED 2" and the money line, while `rabadon usage` and
# `rabadon export --otlp` over the SAME bytes answered "no events in this
# window" and "0 spans". trace is also the surface that gets screenshotted, so
# it is the single place the false number does the most damage.
#
# The needle is proved to exist BEFORE it is asserted absent: the identical
# event stream is rendered once on an ORDINARY pipe, where CAUGHT 2 and the
# "saved:" line MUST appear. Without that positive arm, renaming "CAUGHT" would
# make every check below pass over an empty haystack.
selfspool(){   # $1 out file · $2 pipe label · $3 extra RUN_START keys
  local out="$1" pipe="$2" extra="${3:-}"
  {
  echo "{\"v\":1,\"ts\":1000,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"RUN_START\",\"goal\":\"prove the loop\",\"steps\":5$extra}"
  echo "{\"v\":1,\"ts\":1010,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"STEP_START\",\"step\":\"s1\"}"
  echo "{\"v\":1,\"ts\":1020,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"STEP_OK\",\"step\":\"s1\"}"
  echo "{\"v\":1,\"ts\":1030,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"STEP_START\",\"step\":\"s2\"}"
  echo "{\"v\":1,\"ts\":1040,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"CHECK_FAIL\",\"step\":\"s2\",\"fails\":[{\"check\":\"contract\",\"why\":\"FAIL testsuite: RED\"}]}"
  echo "{\"v\":1,\"ts\":1050,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"REPAIR_START\",\"step\":\"s2\",\"attempt\":1}"
  echo "{\"v\":1,\"ts\":1060,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"REPAIR_OK\",\"step\":\"s2\",\"attempt\":1,\"tokens\":1200,\"usd_e6\":4000}"
  echo "{\"v\":1,\"ts\":1070,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"STEP_OK\",\"step\":\"s2\"}"
  echo "{\"v\":1,\"ts\":1080,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"STEP_START\",\"step\":\"s3\"}"
  echo "{\"v\":1,\"ts\":1090,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"STEP_OK\",\"step\":\"s3\"}"
  echo "{\"v\":1,\"ts\":1100,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"STEP_START\",\"step\":\"s4\"}"
  echo "{\"v\":1,\"ts\":1110,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"STEP_OK\",\"step\":\"s4\"}"
  echo "{\"v\":1,\"ts\":1120,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"STEP_START\",\"step\":\"s5\"}"
  echo "{\"v\":1,\"ts\":1130,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"CHECK_FAIL\",\"step\":\"s5\",\"fails\":[{\"check\":\"contract\",\"why\":\"FAIL testsuite: RED\"}]}"
  echo "{\"v\":1,\"ts\":1140,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"REPAIR_START\",\"step\":\"s5\",\"attempt\":1}"
  echo "{\"v\":1,\"ts\":1150,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"REPAIR_OK\",\"step\":\"s5\",\"attempt\":1,\"tokens\":1200,\"usd_e6\":4000}"
  echo "{\"v\":1,\"ts\":1160,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"STEP_OK\",\"step\":\"s5\"}"
  echo "{\"v\":1,\"ts\":1170,\"run\":\"selfrun\",\"pipe\":\"$pipe\",\"ev\":\"RUN_DONE\",\"verdict\":\"PASS\"}"
  } > "$out"
}
DRILL_LABEL="rabadon's own drill — excluded from every number"

# the positive arm: same 18 events, ordinary pipe. These MUST be present, or
# every absence asserted below is vacuous.
selfspool "$TMP/ordinary.jsonl" "demo:do"
OUT6="$("$TRACE" "$TMP/ordinary.jsonl" --no-color)"
echo "$OUT6" | grep -q 'CAUGHT 2 (step 2,5)' && ok "needle proved present: the 18 events on an ORDINARY pipe render CAUGHT 2 (step 2,5)" || bad "the positive arm does not render CAUGHT 2 — every drill check below would be vacuous: $(echo "$OUT6" | grep -i caught | tail -1)"
echo "$OUT6" | grep -q 'REPAIRED 2'   && ok "needle proved present: the same run renders REPAIRED 2 on an ordinary pipe"   || bad "the positive arm does not render REPAIRED 2"
echo "$OUT6" | grep -q '  saved:'     && ok "needle proved present: the money line renders on an ordinary pipe"            || bad "the 'saved:' money line is gone — its absence below would prove nothing"
echo "$OUT6" | grep -q "$DRILL_LABEL" && bad "an ordinary run was labelled a drill — the exclusion is too wide"            || ok "an ordinary run is NOT labelled a drill"

# rule 3 — every literal self pipe in drill.h, bare and with a `:verb` suffix,
# plus the rabadon-bench prefix. The bench alone fires thousands of synthetic
# denies; as CAUGHT lines they read as production catches.
for P in do-test do-test:do vibecoded-demo:do llm-repair-live:do bus-test:do rabadon-bench-7:do; do
  selfspool "$TMP/self.jsonl" "$P"
  O="$("$TRACE" "$TMP/self.jsonl" --no-color)"
  echo "$O" | grep -q 'CAUGHT 0' && echo "$O" | grep -q 'REPAIRED 0' \
    && ok "self pipe '$P' counts 0 catches and 0 repairs" \
    || bad "self pipe '$P' still counted its own self-test: $(echo "$O" | grep -i 'CAUGHT' | tail -1)"
  echo "$O" | grep -q "$DRILL_LABEL" && ok "self pipe '$P' says out loud that it is rabadon's own drill" || bad "self pipe '$P' rendered with no drill label"
  echo "$O" | grep -q '  saved:' && bad "self pipe '$P' still printed the money line for a self-test" || ok "self pipe '$P' prints no 'saved:' claim"
done

# rule 1 — the emit tag the emitter itself writes.
selfspool "$TMP/tagged.jsonl" "demo:do" ',"drill":true'
O1="$("$TRACE" "$TMP/tagged.jsonl" --no-color)"
echo "$O1" | grep -q 'CAUGHT 0' && ok "rule 1: a \"drill\":true emit tag zeroes the catch count" || bad "rule 1 not applied: $(echo "$O1" | grep -i caught | tail -1)"

# rule 2 + rule 4 — a doctor-N session id on RUN_START marks that line, and the
# rest of the run is fallout inside the same pipe within the 2-minute window.
selfspool "$TMP/marked.jsonl" "demo:do" ',"session":"doctor-3"'
O2="$("$TRACE" "$TMP/marked.jsonl" --no-color)"
echo "$O2" | grep -q 'CAUGHT 0' && ok "rules 2+4: a doctor-3 marker excludes the run and its 2-minute fallout" || bad "rules 2/4 not applied: $(echo "$O2" | grep -i caught | tail -1)"

# a drill arm must never feed the A/B money block either: the delta is the one
# number a buyer checks by hand.
S7="$TMP/drillab.jsonl"; sed 's/"pipe":"demo:do"/"pipe":"do-test:do"/g' "$S" > "$S7"
"$TRACE" "$S7" --no-color | grep -q 'MEASURED A/B' \
  && bad "a self-pipe drill still produced a MEASURED A/B money claim" \
  || ok "a drill run is kept out of the MEASURED A/B block (no money claim from a self-test)"

# ---- fixture 7: the exclusion is PER RUN, not per file --------------------
# The cheap way to make the checks above pass is to drop the whole spool the
# moment one drill line appears in it. That would silently delete the customer's
# real catches, which is a worse failure than the one being fixed: the drill and
# the day's real work land in the SAME day file. Both runs are asserted from one
# render — the real one must still count everything.
S8="$TMP/mixed.jsonl"
{
echo '{"v":1,"ts":1000,"run":"drillrun","pipe":"do-test:do","ev":"RUN_START","steps":1}'
echo '{"v":1,"ts":1010,"run":"drillrun","pipe":"do-test:do","ev":"STEP_START","step":"d1"}'
echo '{"v":1,"ts":1020,"run":"drillrun","pipe":"do-test:do","ev":"CHECK_FAIL","step":"d1","fails":[{"check":"contract","why":"FAIL testsuite: RED"}]}'
echo '{"v":1,"ts":1030,"run":"drillrun","pipe":"do-test:do","ev":"REPAIR_OK","step":"d1","attempt":1,"tokens":9999,"usd_e6":99999}'
echo '{"v":1,"ts":1040,"run":"drillrun","pipe":"do-test:do","ev":"STEP_OK","step":"d1"}'
echo '{"v":1,"ts":1050,"run":"drillrun","pipe":"do-test:do","ev":"RUN_DONE","verdict":"PASS"}'
echo '{"v":1,"ts":2000,"run":"realrun","pipe":"acme-api:do","ev":"RUN_START","steps":1}'
echo '{"v":1,"ts":2010,"run":"realrun","pipe":"acme-api:do","ev":"STEP_START","step":"r1"}'
echo '{"v":1,"ts":2020,"run":"realrun","pipe":"acme-api:do","ev":"CHECK_FAIL","step":"r1","fails":[{"check":"contract","why":"FAIL testsuite: RED"}]}'
echo '{"v":1,"ts":2030,"run":"realrun","pipe":"acme-api:do","ev":"REPAIR_OK","step":"r1","attempt":1,"tokens":1000,"usd_e6":5000}'
echo '{"v":1,"ts":2040,"run":"realrun","pipe":"acme-api:do","ev":"STEP_OK","step":"r1"}'
echo '{"v":1,"ts":2050,"run":"realrun","pipe":"acme-api:do","ev":"RUN_DONE","verdict":"PASS"}'
} > "$S8"
OUT8="$("$TRACE" "$S8" --no-color)"
echo "$OUT8" | grep -q '(2 runs)'      && ok "a mixed spool still renders BOTH runs (the drill is labelled, not deleted)" || bad "a drill line dropped the whole file: $(echo "$OUT8" | head -1)"
echo "$OUT8" | grep -q 'CAUGHT 0'      && ok "in a mixed spool the drill run counts 0"                                    || bad "the drill run in a mixed spool still counted"
echo "$OUT8" | grep -q 'CAUGHT 1 (step 1)' && ok "in the SAME render the customer's real run still counts CAUGHT 1"       || bad "the drill exclusion swallowed a real run's catch — worse than the bug it fixes"
echo "$OUT8" | grep -q '  saved:'      && ok "the real run keeps its money line while the drill has none"                 || bad "the real run lost its 'saved:' line"
echo "$OUT8" | grep -q '\$0.0050'      && ok "the real run keeps its own measured cost (\$0.0050)"                        || bad "the real run's cost went missing"
# and the drill's OWN spend stays visible: an operator debugging their own drill
# needs to see what it cost. It is excluded from the counts, not erased from the
# record — erasing real spend would just be a different false number.
echo "$OUT8" | grep -q '9,999 tok'     && ok "the drill's own spend is still shown to the operator, under the exclusion banner" || bad "the drill's real spend was erased rather than excluded"

# ---- fixture 8: the fail-closed branch is a brand number too ---------------
# "FAKE FIX REJECTED" and the STOP money line ("the remaining steps NEVER ran")
# are separate claims on a separate code path from the repaired branch, and a
# demo pipe is exactly where a rejected fake fix gets rehearsed. Positive arm
# first: the identical events on an ordinary pipe MUST print both.
stopspool(){   # $1 out file · $2 pipe
  local out="$1" pipe="$2"
  {
  echo "{\"v\":1,\"ts\":1000,\"run\":\"ds\",\"pipe\":\"$pipe\",\"ev\":\"RUN_START\",\"steps\":4}"
  echo "{\"v\":1,\"ts\":1010,\"run\":\"ds\",\"pipe\":\"$pipe\",\"ev\":\"STEP_START\",\"step\":\"x1\"}"
  echo "{\"v\":1,\"ts\":1020,\"run\":\"ds\",\"pipe\":\"$pipe\",\"ev\":\"CHECK_FAIL\",\"step\":\"x1\",\"fails\":[{\"check\":\"contract\",\"why\":\"FAIL testsuite: RED\"}]}"
  echo "{\"v\":1,\"ts\":1030,\"run\":\"ds\",\"pipe\":\"$pipe\",\"ev\":\"REPAIR_FAIL\",\"step\":\"x1\",\"attempt\":1}"
  echo "{\"v\":1,\"ts\":1040,\"run\":\"ds\",\"pipe\":\"$pipe\",\"ev\":\"STOP\",\"reason\":\"BLOCKED\",\"detail\":\"fake fix\"}"
  echo "{\"v\":1,\"ts\":1050,\"run\":\"ds\",\"pipe\":\"$pipe\",\"ev\":\"RUN_DONE\",\"verdict\":\"CHECK_FAILED\"}"
  } > "$out"
}
stopspool "$TMP/stop-ord.jsonl" "demo:do"
O9="$("$TRACE" "$TMP/stop-ord.jsonl" --no-color)"
echo "$O9" | grep -q 'FAKE FIX REJECTED 1' && ok "needle proved present: an ordinary pipe renders FAKE FIX REJECTED 1" || bad "the positive arm lost FAKE FIX REJECTED 1 — the drill check below would be vacuous"
echo "$O9" | grep -q 'NEVER ran on a blind base' && ok "needle proved present: the ordinary run prints the fail-closed money line" || bad "the fail-closed money line is gone"
stopspool "$TMP/stop-drill.jsonl" "vibecoded-demo:do"
O10="$("$TRACE" "$TMP/stop-drill.jsonl" --no-color)"
echo "$O10" | grep -q 'FAKE FIX REJECTED 0' && ok "a drill's rejected fake fix is NOT counted as a refusal (FAKE FIX REJECTED 0)" || bad "a drill still claimed a fake fix refusal: $(echo "$O10" | grep -i 'REJECTED' | tail -1)"
echo "$O10" | grep -q 'NEVER ran on a blind base' && bad "a drill still printed the fail-closed money claim" || ok "a drill prints no fail-closed money claim"
echo "$O10" | grep -q '1 refusal-shaped' && ok "the drill's refusal is still reported as a SHAPE, so nothing is hidden from the operator" || bad "the drill's refusal-shaped event was hidden instead of excluded"

echo ""
echo "route: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
