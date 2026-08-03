#!/usr/bin/env bash
# rabadon-gate push-gate proof — at push time rabadon RUNS the project's OWN
# suite and opens the gate on the REAL result (telling is a warning, solving is
# the product). Native now — this was the last thing that delegated to node.
# Green suite -> push allowed + REPAIR_OK + lastTestPass stamped; red -> blocked
# + REPAIR_FAIL with the failing lines; no edit since last pass -> nothing to
# run; a hanging suite is killed and the push blocked (the gate never hangs).
set -u
# HERMETIC: rabadon is DEFAULT-OFF, so the gate is dormant unless a project opts
# in (cwd/.rabadon/on) or the machine has ~/.rabadon/enabled. A test that reads
# the real HOME passes or fails on whether the developer happens to have rabadon
# switched on — which is not a test. Give this run its own HOME with the flag set.
export HOME="$(mktemp -d)"; mkdir -p "$HOME/.rabadon"; : > "$HOME/.rabadon/enabled"
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
A="$(scratch "echo 100 percent tests passed" "tests passed")"; RD="$(mktemp -d)"; : > "$RD/enabled"
pushev "$A" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && ok "green suite: push allowed (exit 0)" || bad "green push should be exit 0 (got $rc)"
grep -q '"ev":"REPAIR_OK"' "$RD/spool/$day.jsonl" 2>/dev/null && ok "green: REPAIR_OK on the ledger" || bad "green should emit REPAIR_OK"
lp=$(python3 -c "import json;print(json.load(open('$A/.rabadon/state.json')).get('lastTestPass',0))")
[ "$lp" != "0" ] && ok "green: lastTestPass stamped so the next push is clean" || bad "green should stamp lastTestPass"

# --- B: red suite -> push BLOCKED (exit 2) + REPAIR_FAIL + failing lines ---
B="$(scratch "echo FAILED 1 test; exit 1" "tests passed")"; RD="$(mktemp -d)"; : > "$RD/enabled"
out="$(pushev "$B" | RABADON_DIR="$RD" "$BIN" 2>&1)"; rc=$?
[ $rc -eq 2 ] && ok "red suite: push blocked (exit 2)" || bad "red push should be exit 2 (got $rc)"
echo "$out" | grep -q "ran the tests itself" && ok "red: rabadon says it ran the suite itself" || bad "red should name the self-run"
grep -q '"ev":"REPAIR_FAIL"' "$RD/spool/$day.jsonl" 2>/dev/null && ok "red: REPAIR_FAIL on the ledger" || bad "red should emit REPAIR_FAIL"

# --- C: no code edit since last pass -> gate does nothing, push flows ---
C="$(scratch "exit 1" "tests passed")"
now=$(python3 -c 'import time;print(int(time.time()*1000))')
# lastTestVerified, not lastTestPass, and the difference is the whole point.
# lastTestPass is ALSO stamped from merely watching a Bash result go past, where
# no exit code reaches the hook at all, so anything that printed green-looking
# text used to buy the skip below. This fixture now sets the stamp rabadon
# writes only after running the suite itself. The assertion is unchanged — a
# genuinely green suite is not re-run — and its twin is F1 in
# pushgate_forge_test.sh, where an observed-only stamp must NOT skip.
printf '{"lastCodeEdit":10,"lastTestPass":%s,"lastTestVerified":%s,"sessions":{}}' "$now" "$now" > "$C/.rabadon/state.json"
RD="$(mktemp -d)"; : > "$RD/enabled"
pushev "$C" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "tests green since last edit: push flows, suite not re-run" || bad "no-edit push should be exit 0"

# --- D: a hanging suite is killed and the push blocked (the gate never hangs) ---
D="$(scratch "sleep 5" "tests passed")"
sed -i.bak 's/"timeoutSec": 30/"timeoutSec": 1/' "$D/.rabadon/guard.json"
RD="$(mktemp -d)"; : > "$RD/enabled"
t0=$(python3 -c 'import time;print(time.time())')
pushev "$D" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1; rc=$?
t1=$(python3 -c 'import time;print(time.time())')
[ $rc -eq 2 ] && ok "timeout: a hanging suite is killed and the push blocked (exit 2)" || bad "timeout should block (got $rc)"
python3 -c "import sys;sys.exit(0 if ($t1-$t0)<4 else 1)" && ok "timeout: gate returned fast, did not wait out the sleep" || bad "timeout should return fast"

# --- E: the suite runs under a shell that can hold the project's own env ---
# Measured on aaif-goose/goose, whose test command starts `source bin/activate-hermit`.
# Under `sh -c` that script dies on line 68 with
#   bin/activate-hermit: line 68: `deactivate-hermit': not a valid identifier
# because POSIX sh rejects a hyphen in a function name. cargo never ran, the
# gate read a nonzero exit and blocked a green tree while saying the tests
# failed. hermit, nvm and asdf all define hyphenated functions, so this is every
# repo that activates a toolchain before testing, not one project.
E="$(scratch "deactivate-hermit() { :; }; echo 100 percent tests passed" "tests passed")"
RD="$(mktemp -d)"; : > "$RD/enabled"
out="$(pushev "$E" | RABADON_DIR="$RD" "$BIN" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "env shell: a suite needing bash function syntax runs and the push is allowed" || bad "env shell: push should be allowed (got $rc)"

# --- E2 (twin of E): the bigger shell must not turn a red suite green ---
E2="$(scratch "deactivate-hermit() { :; }; echo FAILED 1 test; exit 1" "tests passed")"
RD="$(mktemp -d)"; : > "$RD/enabled"
out="$(pushev "$E2" | RABADON_DIR="$RD" "$BIN" 2>&1)"; rc=$?
[ $rc -eq 2 ] && ok "env shell twin: a real failure under the same shell still blocks (exit 2)" || bad "env shell twin: red should still block (got $rc)"

echo "gate push: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
