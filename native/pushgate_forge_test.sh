#!/usr/bin/env bash
# pushgate_forge_test.sh — the push gate asked a timestamp question, and the
# answer to a timestamp question can be written by the thing being checked.
#
# The gate only runs the project's suite when `lastCodeEdit > lastTestPass`. That
# stamp is set in two very different places and the gate could not tell them
# apart:
#
#   RUN     gate.cpp runs pushGate.run itself and reads the real exit code.
#   OBSERVE gate.cpp watches a Bash tool result float past, matches
#           testPassPattern against the TEXT, and stamps. No exit code reaches
#           the post hook at all — tool_response is a string the session
#           produced.
#
# So any command whose output looks green refreshed the stamp, and the next push
# skipped verification entirely. Measured 3 August on two real repos: in
# terraform `go test -run TestNothingMatchesThis ./...` prints
# `ok  vac  0.142s [no tests to run]` and exits 0 — measured here, not guessed —
# the stamp refreshed, and `git push` was allowed with the suite still red. In
# discourse `bin/rspec spec/nonexistent` did the same. Feeding a single line of
# text as a fake tool result works identically, because long tool outputs are
# truncated anyway, so there was no trick to detect.
#
# The fix separates the two stamps. Only a green rabadon ran ITSELF may let a
# push skip the suite. An observed green still records what happened — the
# handoff needs it — but it no longer opens a gate.
#
# The twins matter more than usual here, because the failure mode of this fix is
# refusing an honest push forever. F2 keeps the fast path, and F5 is the one
# that kills a naive substring search: `go test ./...` prints `[no test files]`
# for every package without tests, next to real green lines, on a perfectly good
# run.
set -u
export HOME="$(mktemp -d)"; mkdir -p "$HOME/.rabadon"; : > "$HOME/.rabadon/enabled"
export RABADON_NOTIFY=0
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

NOW=$(python3 -c 'import time;print(int(time.time()*1000))')

# scratch <run-command> <testPassPattern> <lastCodeEdit> <lastTestPass> <lastTestVerified>
scratch(){
  d="$(mktemp -d)"; mkdir -p "$d/.rabadon"
  RUN="$1" PAT="$2" ED="$3" TP="$4" TV="$5" python3 - "$d" <<'PY'
import json, os, sys
d = sys.argv[1]
g = {"project": "pgf",
     "pushGate": {"run": os.environ["RUN"], "why": "green before push", "timeoutSec": 30}}
if os.environ["PAT"]:
    g["testPassPattern"] = os.environ["PAT"]
json.dump(g, open(d + "/.rabadon/guard.json", "w"))
st = {"lastCodeEdit": int(os.environ["ED"]),
      "lastTestPass": int(os.environ["TP"]),
      "lastTestVerified": int(os.environ["TV"]), "sessions": {}}
json.dump(st, open(d + "/.rabadon/state.json", "w"))
PY
  echo "$d"
}
pushev(){ printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"pgf","tool_use_id":"p%s","tool_name":"Bash","tool_input":{"command":"git push origin main"}}' "$1" "$RANDOM"; }

# run <dir> -> prints the exit code, leaves stderr in $OUT
runpush(){ RD="$(mktemp -d)"; : > "$RD/enabled"; OUT="$(pushev "$1" | RABADON_DIR="$RD" "$BIN" 2>&1)"; echo $?; }

blocked(){ # <dir> <label>
  rc=$(runpush "$1")
  [ "$rc" = "2" ] && ok "$2" || bad "$2 — push was ALLOWED (exit $rc)"
}
allowed(){ # <dir> <label>
  rc=$(runpush "$1")
  [ "$rc" = "0" ] && ok "$2" || bad "$2 — push was BLOCKED (exit $rc)"
}

echo "push gate — a stamp the session can write is not verification"
echo

# ---------------------------------------------------------------------------
# F1. The forged stamp. Code was edited, then something green-looking was
#     observed, and the suite underneath is red. The gate must run it anyway.
F1="$(scratch "exit 1" "tests passed" "$NOW" "$((NOW+5000))" 0)"
blocked "$F1" "an observed green does not let a red suite through"

# F2. TWIN — the fast path survives. rabadon verified this suite itself, nothing
#     was edited since, so the push flows and the suite is NOT re-run. Without
#     this the fix means every push pays for a full suite forever.
F2="$(scratch "exit 1" "tests passed" "$NOW" "$((NOW+5000))" "$((NOW+5000))")"
allowed "$F2" "a green rabadon verified itself still skips the re-run"

# ---------------------------------------------------------------------------
# F3. Zero tests ran, exit 0. Real `go test -run <nothing> ./...` output,
#     measured. No testPassPattern, so the gate's own rule is exit-code-only.
F3="$(scratch "echo 'ok      vac     0.142s [no tests to run]'" "" "$NOW" 0 0)"
blocked "$F3" "go: a run with [no tests to run] is not a green"

# F4. TWIN — the same shape with tests in it opens the gate.
F4="$(scratch "echo 'ok      vac     0.357s'" "" "$NOW" 0 0)"
allowed "$F4" "go: a real green still opens the gate"

# F5. TWIN, the sharp one. `go test ./...` prints [no test files] for every
#     package that has none, beside real green lines. This run is GREEN and a
#     substring search would refuse it.
F5="$(scratch "printf '?   vac/empty  [no test files]\nok      vac     0.357s\n'" "" "$NOW" 0 0)"
allowed "$F5" "go: packages without tests beside a real green is still green"

# ---------------------------------------------------------------------------
# F6. pytest against a directory with nothing in it. Measured output.
F6="$(scratch "echo 'no tests ran in 0.00s'" "" "$NOW" 0 0)"
blocked "$F6" "pytest: 'no tests ran' is not a green"

# F7. TWIN — pytest with one real test.
F7="$(scratch "echo '1 passed in 0.00s'" "" "$NOW" 0 0)"
allowed "$F7" "pytest: '1 passed' opens the gate"

# ---------------------------------------------------------------------------
# F8. rspec with a filter that matched nothing.
F8="$(scratch "echo '0 examples, 0 failures'" "" "$NOW" 0 0)"
blocked "$F8" "rspec: '0 examples' is not a green"

# F9. TWIN — a real rspec green counts examples above zero.
F9="$(scratch "echo '15 examples, 0 failures'" "" "$NOW" 0 0)"
allowed "$F9" "rspec: '15 examples, 0 failures' opens the gate"

echo
echo "gate push forge: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
