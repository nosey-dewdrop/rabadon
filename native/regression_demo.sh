#!/usr/bin/env bash
# rabadon behavior gate — LIVE regression catch on a REAL test suite.
#
# The hard point: today rabadon caught none of the real errors. The
# reason was it only watched shell-actions, never ran the project's own tests.
# This proves the fix on a REAL test runner (node --test), not hand-written
# goldens: an agent-style edit breaks behavior; a shallow self-check (file
# exists + syntax ok) waves it through; rabadon's testsuite gate catches it,
# because the ground-truth is the project's OWN tests — no dataset needed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
VERIFY="$HERE/rabadon-verify"
[ -x "$VERIFY" ] || { echo "build first: make native/rabadon-verify"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

D="$(mktemp -d)"; cd "$D"
# a real module with real behavior
cat > cart.js <<'EOF'
export function total(items){
  return items.reduce((s,i)=> s + i.price * i.qty, 0)
}
export function discount(sum, pct){
  if(pct < 0 || pct > 100) throw new Error('bad pct')
  return sum - (sum * pct / 100)
}
EOF
# a REAL test suite (node's built-in runner) — this is the ground-truth oracle
cat > cart.test.mjs <<'EOF'
import { test } from 'node:test'
import assert from 'node:assert'
import { total, discount } from './cart.js'
test('total sums price*qty', ()=> assert.equal(total([{price:10,qty:2},{price:5,qty:3}]), 35))
test('discount 20% of 100 is 80', ()=> assert.equal(discount(100,20), 80))
test('discount rejects bad pct', ()=> assert.throws(()=> discount(100,150)))
EOF

# contracts a builder would attach
cat > shallow.json <<'EOF'
[ {"type":"fileExists","path":"cart.js"},
  {"type":"fileContains","path":"cart.js","pattern":"discount"},
  {"type":"cmd","run":"node -c cart.js"} ]
EOF
cat > behavior.json <<'EOF'
[ {"type":"testsuite","run":"node --test"} ]
EOF

echo "  baseline (correct code):"
"$VERIFY" "$D" shallow.json  >/dev/null 2>&1 && ok "shallow gate passes on good code"   || bad "shallow should pass good code"
"$VERIFY" "$D" behavior.json >/dev/null 2>&1 && ok "behavior gate passes on good code" || bad "behavior should pass good code"

# --- an agent-style edit that BREAKS behavior (subtle: forgets qty) ---
cat > cart.js <<'EOF'
export function total(items){
  return items.reduce((s,i)=> s + i.price, 0)   // BUG: dropped * i.qty
}
export function discount(sum, pct){
  if(pct < 0 || pct > 100) throw new Error('bad pct')
  return sum - (sum * pct / 100)
}
EOF

echo "  after a behavior-breaking edit:"
"$VERIFY" "$D" shallow.json  >/dev/null 2>&1 && ok "shallow gate MISSES the regression (waves the broken edit through)" || bad "shallow unexpectedly caught it"
"$VERIFY" "$D" behavior.json >/dev/null 2>&1 && bad "behavior gate missed the regression!" || ok "rabadon behavior gate CATCHES the regression via the project's own tests"

echo ""
echo "  what rabadon reports (the failing test is named):"
"$VERIFY" "$D" behavior.json 2>&1 | grep -iE "fail|total" | head -4 | sed 's/^/    /'

echo ""
echo "regression: $PASS passed, $FAIL failed"
rm -rf "$D"
[ $FAIL -eq 0 ]
