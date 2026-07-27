#!/usr/bin/env bash
# rabadon-verify proof — the contract cannot be gamed. Drives the real binary.
# The whole moat is here: a repair that FAKES the check (writes the string,
# creates the file) is REJECTED, because the differential check runs the code
# and compares behavior. A repair that genuinely preserves behavior is ACCEPTED.
set -u
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-verify"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-verify"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

D="$(mktemp -d)"
# a tiny module with a real behavior: double(x) = x*2
cat > "$D/lib.js" <<'EOF'
function double(x){ return x*2 }
console.log(double(Number(process.argv[2])))
EOF
# baseline behavior on input 21 -> 42
BASE="$(cd "$D" && node lib.js 21)"

# contract: behavior on 21 must stay 42 (differential) AND lib.js must exist
cat > "$D/contract.json" <<EOF
[ { "type": "fileExists", "path": "lib.js" },
  { "type": "differential", "run": "node lib.js 21", "expect": "$BASE" } ]
EOF

# --- 1: the known-good state passes ---
"$BIN" "$D" "$D/contract.json" >/dev/null 2>&1 && ok "known-good state passes" || bad "good state should pass"

# --- 2: a GENUINE change that preserves behavior is accepted ---
cat > "$D/lib.js" <<'EOF'
const double = x => x + x   // refactored, same behavior
console.log(double(Number(process.argv[2])))
EOF
"$BIN" "$D" "$D/contract.json" >/dev/null 2>&1 && ok "genuine behavior-preserving refactor is accepted" || bad "genuine refactor should pass"

# --- 3: a GOODHART change that breaks behavior is REJECTED ---
# the classic cheat: satisfy the shallow signal, break the real thing
cat > "$D/lib.js" <<'EOF'
const double = x => x*2 + 1   // subtly wrong: 21 -> 43
console.log(double(Number(process.argv[2])))
EOF
"$BIN" "$D" "$D/contract.json" >/dev/null 2>&1 && bad "broken behavior slipped through (contract gamed!)" || ok "broken behavior is REJECTED by the differential check"

# --- 4: forbidden path — repair cannot edit what it must preserve ---
echo "SPEC v1" > "$D/spec.txt"
SHA="$("$BIN" --sha "$D/spec.txt" 2>/dev/null || true)"   # optional helper; fall back to inline
python3 - "$D" <<'PY'
import sys,os
d=sys.argv[1]
# compute fnv1a to match the C++ (kept in sync with verify.cpp)
def fnv1a(b):
    h=1469598103934665603
    for c in b: h=((h^c)*1099511628211)&0xFFFFFFFFFFFFFFFF
    return h
body=open(os.path.join(d,'spec.txt'),'rb').read()
open(os.path.join(d,'forbid.json'),'w').write('[ {"type":"forbidden","path":"spec.txt","sha":"%d"} ]'%fnv1a(body))
PY
"$BIN" "$D" "$D/forbid.json" >/dev/null 2>&1 && ok "unchanged protected file passes" || bad "unchanged file should pass"
echo "SPEC v2 tampered" > "$D/spec.txt"
"$BIN" "$D" "$D/forbid.json" >/dev/null 2>&1 && bad "tampered protected file slipped through" || ok "tampered protected file is REJECTED"

# --- 5: fail-closed — empty contract never passes ---
echo '[]' > "$D/empty.json"
"$BIN" "$D" "$D/empty.json" >/dev/null 2>&1; [ $? -eq 2 ] && ok "empty contract fails closed (exit 2)" || bad "empty contract must fail closed"

# --- 6: fail-closed — unknown check type never passes ---
echo '[ {"type":"vibes","note":"trust me"} ]' > "$D/unk.json"
"$BIN" "$D" "$D/unk.json" >/dev/null 2>&1; [ $? -eq 1 ] && ok "unknown check type is rejected" || bad "unknown type must fail"

echo ""
echo "verify: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
