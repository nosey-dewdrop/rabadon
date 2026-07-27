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

# ---- 5: the report exists — events landed in the spool ----
day="$(date +%Y-%m-%d)"
grep -q '"ev":"REPAIR_OK"' "$RD/spool/$day.jsonl" 2>/dev/null && ok "a real REPAIR_OK is on the ledger (not a demo pipe)" || bad "repair event missing from spool"
grep -q '"ev":"RUN_DONE"' "$RD/spool/$day.jsonl" 2>/dev/null && ok "run outcomes are reported to the spool" || bad "RUN_DONE missing from spool"

echo ""
echo "loop: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
