#!/usr/bin/env bash
# rabadon-gate push-gate proof — at push time rabadon RUNS the project's OWN
# suite and opens the gate on the REAL result (telling is a warning, solving is
# the product). Native now — this was the last thing that delegated to node.
# Green suite -> push allowed + REPAIR_OK + lastTestPass stamped; red -> blocked
# + REPAIR_FAIL with the failing lines; no edit since last pass -> nothing to
# run; a hanging suite is killed and the push blocked (the gate never hangs).
set -u
export RABADON_NOTIFY=0
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

scratch(){ # $1=pushGate.run  $2=testPassPattern
  d="$(mktemp -d)"; mkdir -p "$d/.rabadon"
  cat > "$d/.rabadon/guard.json" <<EOF
{ "project": "pg", "testPassPattern": "$2",
  "pushGate": { "run": "$1", "why": "green before push", "timeoutSec": 30 } }
EOF
  now=$(python3 -c 'import time;print(int(time.time()*1000))')
  printf '{"lastCodeEdit":%s,"lastTestPass":0,"sessions":{}}' "$now" > "$d/.rabadon/state.json"
  echo "$d"
}
pushev(){ printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"pg1","tool_use_id":"p%s","tool_name":"Bash","tool_input":{"command":"git push origin main"}}' "$1" "$RANDOM"; }
day=$(date -u +%Y-%m-%d)

# --- A: green suite -> push ALLOWED (exit 0) + REPAIR_OK + lastTestPass stamped ---
A="$(scratch "echo 100 percent tests passed" "tests passed")"; RD="$(mktemp -d)"
pushev "$A" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && ok "green suite: push allowed (exit 0)" || bad "green push should be exit 0 (got $rc)"
grep -q '"ev":"REPAIR_OK"' "$RD/spool/$day.jsonl" 2>/dev/null && ok "green: REPAIR_OK on the ledger" || bad "green should emit REPAIR_OK"
lp=$(python3 -c "import json;print(json.load(open('$A/.rabadon/state.json')).get('lastTestPass',0))")
[ "$lp" != "0" ] && ok "green: lastTestPass stamped so the next push is clean" || bad "green should stamp lastTestPass"

# --- B: red suite -> push BLOCKED (exit 2) + REPAIR_FAIL + failing lines ---
B="$(scratch "echo FAILED 1 test; exit 1" "tests passed")"; RD="$(mktemp -d)"
out="$(pushev "$B" | RABADON_DIR="$RD" "$BIN" 2>&1)"; rc=$?
[ $rc -eq 2 ] && ok "red suite: push blocked (exit 2)" || bad "red push should be exit 2 (got $rc)"
echo "$out" | grep -q "ran the tests itself" && ok "red: rabadon says it ran the suite itself" || bad "red should name the self-run"
grep -q '"ev":"REPAIR_FAIL"' "$RD/spool/$day.jsonl" 2>/dev/null && ok "red: REPAIR_FAIL on the ledger" || bad "red should emit REPAIR_FAIL"

# --- C: no code edit since last pass -> gate does nothing, push flows ---
C="$(scratch "exit 1" "tests passed")"
now=$(python3 -c 'import time;print(int(time.time()*1000))')
printf '{"lastCodeEdit":10,"lastTestPass":%s,"sessions":{}}' "$now" > "$C/.rabadon/state.json"
RD="$(mktemp -d)"
pushev "$C" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "tests green since last edit: push flows, suite not re-run" || bad "no-edit push should be exit 0"

# --- D: a hanging suite is killed and the push blocked (the gate never hangs) ---
D="$(scratch "sleep 5" "tests passed")"
sed -i.bak 's/"timeoutSec": 30/"timeoutSec": 1/' "$D/.rabadon/guard.json"
RD="$(mktemp -d)"
t0=$(python3 -c 'import time;print(time.time())')
pushev "$D" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1; rc=$?
t1=$(python3 -c 'import time;print(time.time())')
[ $rc -eq 2 ] && ok "timeout: a hanging suite is killed and the push blocked (exit 2)" || bad "timeout should block (got $rc)"
python3 -c "import sys;sys.exit(0 if ($t1-$t0)<4 else 1)" && ok "timeout: gate returned fast, did not wait out the sleep" || bad "timeout should return fast"

echo "gate push: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
