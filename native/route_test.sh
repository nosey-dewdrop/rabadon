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
echo "$OUT" | grep -q '\$1.0020 cepte (%72)' && ok "delta + percent are computed from the two arms (\$1.0020, %72)" || bad "delta line wrong: $(echo "$OUT" | grep -i fark)"
echo "$OUT" | grep -q 'UCUZDA KANITLANAN 4/5' && ok "counts 4/5 steps as proven-cheap, 1 escalated" || bad "cheap/escalated counters wrong"
echo "$OUT" | grep -q 'ucuz cevap KANITLANAMADI' && ok "the rejected cheap answer is shown with the failing check" || bad "escalation detail line missing"
echo "$OUT" | grep -q '↑ opus' && ok "the climb to the expensive tier is drawn under the step" || bad "escalation climb line missing"

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
echo "$OUT2" | grep -q 'routed PAHALIYA geldi' && ok "when routing loses, the report says it lost (no hiding)" || bad "loss case not reported: $(echo "$OUT2" | grep -i fark)"
echo "$OUT2" | grep -q '\-\$0.0400' && ok "the loss is quantified (-\$0.0400), same measured way" || bad "loss amount wrong"

# ---- fixture 3: a single-arm run must NOT print an A/B ----
S3="$TMP/one.jsonl"; grep 'loop-r"' "$S" > "$S3"
"$TRACE" "$S3" --no-color | grep -q 'ÖLÇÜLEN A/B' \
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
echo "$OUT4" | grep -q 'TAMİR 0'   && ok "installing a rule and observing a green run are NOT counted as repairs (TAMİR 0)"   || bad "the ledger counted a non-repair as a repair: $(echo "$OUT4" | grep -i 'TAMİR')"

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
"$TRACE" "$S5" --no-color | grep -q 'TAMİR 1'   && ok "a real repair from the loop is still counted (TAMİR 1)" || bad "a genuine repair stopped counting"

echo ""
echo "route: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
