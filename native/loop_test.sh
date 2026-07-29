#!/usr/bin/env bash
# rabadon-loop proof — the autonomous engine, deterministic (stub proposer, no
# LLM). Proves the whole product loop and that a gamed repair cannot win.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOOP="$HERE/rabadon-loop"; VERIFY="$HERE/rabadon-verify"
[ -x "$LOOP" ] && [ -x "$VERIFY" ] || { echo "build first: make"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

RD="$(mktemp -d)"   # spool home, isolated

# ---- 1: a GENUINE repair passes the gate and the loop continues to accept ----
D="$(mktemp -d)"
cat > "$D/lib.js" <<'EOF'
const double = x => x*2 + 1   // BUG: 21 -> 43
console.log(double(Number(process.argv[2])))
EOF
# proposer that does the REAL fix
cat > "$D/prop_good.sh" <<'EOF'
#!/usr/bin/env bash
cat > lib.js <<'JS'
const double = x => x*2
console.log(double(Number(process.argv[2])))
JS
EOF
chmod +x "$D/prop_good.sh"
cat > "$D/plan.json" <<'EOF'
{ "steps": [ { "id":"s1","kind":"cmd","do":"true",
    "contract":[ {"type":"differential","run":"node lib.js 21","expect":"42"} ] } ],
  "accept":[ {"type":"differential","run":"node lib.js 21","expect":"42"} ] }
EOF
RABADON_DIR="$RD" RABADON_PROPOSER="bash $D/prop_good.sh" "$LOOP" "$D" "$D/plan.json" >/dev/null 2>&1 \
  && ok "broken step -> genuine repair -> gate passes -> accept PASS" || bad "genuine repair loop should exit 0"

# ---- 2: a GAMED repair cannot pass — loop fails closed ----
D2="$(mktemp -d)"
cat > "$D2/lib.js" <<'EOF'
const double = x => x*2 + 1
console.log(double(Number(process.argv[2])))
EOF
# proposer that CHEATS: writes a passing-looking string but keeps wrong behavior
cat > "$D2/prop_cheat.sh" <<'EOF'
#!/usr/bin/env bash
echo "// returns 42 for 21, trust me" >> lib.js   # cosmetic only, behavior still 43
EOF
chmod +x "$D2/prop_cheat.sh"
cp "$D/plan.json" "$D2/plan.json"
RABADON_DIR="$RD" RABADON_PROPOSER="bash $D2/prop_cheat.sh" "$LOOP" "$D2" "$D2/plan.json" >/dev/null 2>&1 \
  && bad "gamed repair slipped through (loop said PASS!)" || ok "gamed repair is rejected -> loop fails closed (exit 1)"

# ---- 3: a step with NO contract fails closed (the old fail-open hole) ----
D3="$(mktemp -d)"
cat > "$D3/plan.json" <<'EOF'
{ "steps": [ { "id":"s1","kind":"cmd","do":"true" } ],
  "accept":[ {"type":"fileExists","path":"plan.json"} ] }
EOF
RABADON_DIR="$RD" RABADON_PROPOSER="true" "$LOOP" "$D3" "$D3/plan.json" >/dev/null 2>&1 \
  && bad "contract-less step passed (fail-OPEN!)" || ok "contract-less step fails closed"

# ---- 4: missing acceptance fails closed (the other old fail-open hole) ----
D4="$(mktemp -d)"
cat > "$D4/plan.json" <<'EOF'
{ "steps": [ { "id":"s1","kind":"cmd","do":"true",
    "contract":[ {"type":"cmd","run":"true"} ] } ] }
EOF
RABADON_DIR="$RD" RABADON_PROPOSER="true" "$LOOP" "$D4" "$D4/plan.json" >/dev/null 2>&1 \
  && bad "missing acceptance auto-passed (fail-OPEN!)" || ok "missing acceptance fails closed"

# ---- 5: VERIFIED ROUTING — the cheap tier is trusted only when the arbiter
# says so. No LLM anywhere here: the "models" are two scripts, so what is being
# proven is the thing that decides — climb on rejection, stay cheap on proof.
D5="$(mktemp -d)"
cat > "$D5/mod.js" <<'EOF'
console.log("unset")
EOF
# one proposer, two tiers: "cheap" writes a plausible but WRONG answer, "pricey"
# writes the correct one. The tier arrives exactly the way a real model tier
# does — in RABADON_MODEL.
cat > "$D5/prop_tier.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
if [ "${RABADON_MODEL:-}" = "cheap" ]; then
  echo 'console.log(41)' > mod.js      # close, but the arbiter runs the code
else
  echo 'console.log(42)' > mod.js
fi
EOF
chmod +x "$D5/prop_tier.sh"
cat > "$D5/plan.json" <<'EOF'
{ "steps": [ { "id":"answer","kind":"work","do":"make mod.js print the answer",
    "contract":[ {"type":"differential","run":"node mod.js","expect":"42"} ] } ],
  "accept":[ {"type":"differential","run":"node mod.js","expect":"42"} ] }
EOF
RD5="$(mktemp -d)"
RABADON_DIR="$RD5" RABADON_TIERS="cheap,pricey" RABADON_MAX_REPAIRS=0 \
  RABADON_PROPOSER="bash $D5/prop_tier.sh" "$LOOP" "$D5" "$D5/plan.json" >/dev/null 2>&1 \
  && ok "cheap tier rejected -> auto-escalated -> pricey tier proven -> accept PASS" \
  || bad "escalation should have rescued the run (exit 0 expected)"
S5="$RD5/spool/$(date +%Y-%m-%d).jsonl"
grep -q '"ev":"ESCALATE".*"from":"cheap","to":"pricey"' "$S5" 2>/dev/null \
  && ok "the escalation is on the ledger with its from/to tier" || bad "ESCALATE event missing"
grep -q '"ev":"STEP_OK".*"tier":2' "$S5" 2>/dev/null \
  && ok "the ledger records WHICH tier actually carried the step" || bad "STEP_OK tier missing"

# ---- 6: when the cheap tier is genuinely right, nothing escalates (the whole
# point — money is kept only on a PROVEN answer, never on a hoped-for one) ----
D6="$(mktemp -d)"; RD6="$(mktemp -d)"
cat > "$D6/prop_tier.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo 'console.log(42)' > mod.js
EOF
chmod +x "$D6/prop_tier.sh"
cp "$D5/plan.json" "$D6/plan.json"
RABADON_DIR="$RD6" RABADON_TIERS="cheap,pricey" RABADON_MAX_REPAIRS=0 \
  RABADON_PROPOSER="bash $D6/prop_tier.sh" "$LOOP" "$D6" "$D6/plan.json" >/dev/null 2>&1
S6="$RD6/spool/$(date +%Y-%m-%d).jsonl"
if grep -q '"ev":"ESCALATE"' "$S6" 2>/dev/null; then bad "escalated even though the cheap tier passed"
else ok "cheap tier passes the arbiter -> no escalation, no extra spend"; fi
grep -q '"ev":"STEP_OK".*"tier":1' "$S6" 2>/dev/null \
  && ok "a cheap step is recorded as PROVEN at tier 1" || bad "tier-1 STEP_OK missing"

# ---- 7: the report exists — events landed in the spool ----
day="$(date +%Y-%m-%d)"
grep -q '"ev":"REPAIR_OK"' "$RD/spool/$day.jsonl" 2>/dev/null && ok "a real REPAIR_OK is on the ledger (not a demo pipe)" || bad "repair event missing from spool"
grep -q '"ev":"RUN_DONE"' "$RD/spool/$day.jsonl" 2>/dev/null && ok "run outcomes are reported to the spool" || bad "RUN_DONE missing from spool"

echo ""
echo "loop: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
