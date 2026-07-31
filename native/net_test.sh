#!/usr/bin/env bash
# the always-on net, end to end — the 3.254 story, executed.
#
# A repo that is green. The agent edits a file and breaks it. Nobody wrote a gate
# at that line. The net runs the project's OWN check in the background, the next
# tool call reads the verdict, and the run is stopped at the transition — not at
# step 10, and not by an opinion.
#
# The assertions that matter most are the negative ones: watch mode must not run
# a single command on the user's machine, a suite that never finishes must never
# be called green, and a red that was ALREADY red must not be re-reported as a
# fresh catch.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"; NET="$HERE/rabadon-net"
[ -x "$GATE" ] && [ -x "$NET" ] || { echo "build first: make"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
day="$(date -u +%Y-%m-%d)"

H_ON="$(mktemp -d)";   mkdir -p "$H_ON/.rabadon";   : > "$H_ON/.rabadon/enabled"
H_WATCH="$(mktemp -d)"; mkdir -p "$H_WATCH/.rabadon"

mkrepo() {  # a healthy python project
  d="$(mktemp -d)"; mkdir -p "$d/.rabadon"
  printf 'def add(a, b):\n    return a + b\n' > "$d/app.py"
  echo "$d"
}
post_edit() { # $1=cwd $2=file $3=home $4=rabadon_dir  -> exit code of the gate
  printf '{"hook_event_name":"PostToolUse","cwd":"%s","session_id":"s1","tool_use_id":"u-%s","tool_name":"Edit","tool_input":{"file_path":"%s"},"tool_response":""}' \
    "$1" "$RANDOM$RANDOM" "$2" | HOME="$3" RABADON_DIR="$4" RABADON_JUDGE=0 "$GATE" >"$TMP/out.txt" 2>&1
  echo $?
}
netts() { grep -o '"ts":[0-9]*' "$1/.rabadon/net.json" 2>/dev/null | head -1 | cut -d: -f2; }
wait_for_net() {  # $1=dir $2=ts-to-beat — the net is detached, so wait for a NEWER verdict
  want="${2:-0}"
  for _ in $(seq 1 300); do
    cur="$(netts "$1")"
    [ -n "$cur" ] && [ "$cur" -gt "$want" ] 2>/dev/null && [ ! -f "$1/.rabadon/net.lock" ] && return 0
    perl -e 'select(undef,undef,undef,0.05)'
  done
  return 1
}

# ---- 1: ON — an edit starts the net, and the net finds the project green ----
R1="$(mkrepo)"; RD1="$(mktemp -d)"; : > "$RD1/enabled"
post_edit "$R1" "$R1/app.py" "$H_ON" "$RD1" >/dev/null
wait_for_net "$R1" && ok "an edit in ON mode starts the net without the agent waiting" || bad "net never produced a verdict"
grep -q '"verdict":"green"' "$R1/.rabadon/net.json" 2>/dev/null \
  && ok "a healthy repo is reported GREEN by its own check" || bad "healthy repo not green: $(cat "$R1/.rabadon/net.json" 2>/dev/null)"

# ---- 2: the agent breaks it — the NEXT call catches the transition ----
prev_ts="$(netts "$R1")"
printf 'def add(a, b):\n    return a +\n' > "$R1/app.py"     # the 3.254 moment
post_edit "$R1" "$R1/app.py" "$H_ON" "$RD1" >/dev/null
wait_for_net "$R1" "$prev_ts" || bad "net did not re-run after the breaking edit"
grep -q '"verdict":"red"' "$R1/.rabadon/net.json" 2>/dev/null \
  && ok "the net turns RED on the edit that broke it" || bad "net stayed green after a real break"
rc=$(post_edit "$R1" "$R1/app.py" "$H_ON" "$RD1")
[ "$rc" = "2" ] && ok "the run is stopped at the transition (exit 2 = correction fed back to the agent)" \
  || bad "green->red did not stop the run (rc=$rc)"
grep -qi "GREEN -> RED" "$TMP/out.txt" && ok "the agent is told what broke, in its own output" || bad "no correction text: $(head -3 "$TMP/out.txt")"
grep -q '"check":"net-turned-red"' "$RD1/spool/$day.jsonl" 2>/dev/null \
  && ok "the catch is on the ledger with the evidence level" || bad "no CHECK_FAIL on the ledger"
grep -q '"lastTestRun":0' "$R1/.rabadon/state.json" 2>/dev/null \
  && bad "lastTestRun is still 0 — the net did not actually record a run" \
  || ok "lastTestRun is no longer 0 (this is the number that proved the net was dead)"

# ---- 3: a STANDING red is not re-reported as a fresh catch ----
rc=$(post_edit "$R1" "$R1/app.py" "$H_ON" "$RD1")
[ "$rc" = "0" ] && ok "an already-red project is not re-reported every call (no nagging)" \
  || bad "standing red reported again (rc=$rc) — the agent would learn to ignore it"

# ---- 4: WATCH — not one command is run on the user's machine ----
R2="$(mkrepo)"; RD2="$(mktemp -d)"
post_edit "$R2" "$R2/app.py" "$H_WATCH" "$RD2" >/dev/null
perl -e 'select(undef,undef,undef,0.6)'
[ ! -f "$R2/.rabadon/net.json" ] \
  && ok "WATCH never runs the project's checks — zero CPU spent on the user's repo" \
  || bad "watch mode ran a check: $(cat "$R2/.rabadon/net.json")"

# ---- 5: a check that never finishes is INCONCLUSIVE, never green ----
R3="$(mktemp -d)"; mkdir -p "$R3/.rabadon"
printf 'x = 1\n' > "$R3/app.py"
printf 'test:\n\tsleep 30\n' > "$R3/Makefile"      # detected as a level-1 suite
RABADON_NET_CAP_MS=800 "$NET" "$R3" >/dev/null 2>&1
grep -q '"verdict":"inconclusive"' "$R3/.rabadon/net.json" \
  && ok "a check that blows its budget is INCONCLUSIVE, never green" || bad "timeout verdict wrong: $(cat "$R3/.rabadon/net.json")"
grep -q '"verdict":"green"' "$R3/.rabadon/net.json" && bad "a timed-out check was called green" || ok "timeout is never green"

# ---- 6: single flight — a burst of edits does not start a suite per edit ----
# The first CI run exposed two races here: a fixed 0.4s nap is not enough for a
# cold runner to reach the lock, and `pgrep -f "sleep 5"` counts OTHER jobs'
# sleeps on a shared box. So: wait for the lock file itself (that is the
# product's own signal that the first flight is airborne), and grep a sleep
# duration unique to this test.
R4="$(mktemp -d)"; mkdir -p "$R4/.rabadon"
printf 'x = 1\n' > "$R4/app.py"
printf 'test:\n\tsleep 5.37\n' > "$R4/Makefile"
RABADON_NET_CAP_MS=9000 "$NET" "$R4" >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 60); do [ -f "$R4/.rabadon/net.lock" ] && break; perl -e 'select(undef,undef,undef,0.1)'; done
[ -f "$R4/.rabadon/net.lock" ] || bad "first flight never took the lock (setup, not single-flight)"
n=0
for _ in 1 2 3 4 5; do RABADON_NET_CAP_MS=9000 "$NET" "$R4" >/dev/null 2>&1; n=$((n+1)); done
running=$(pgrep -f "sleep 5.37" | wc -l | tr -d ' ')
[ "$running" -le 1 ] && ok "5 more edits during an in-flight check start 0 extra suites (single flight holds)" \
  || bad "$running suites running at once — a burst of edits would melt the machine"
kill -9 "$first" 2>/dev/null; pkill -f "sleep 5.37" 2>/dev/null; wait "$first" 2>/dev/null

# ---- 7: a dead lock holder does not wedge the net forever ----
R5="$(mktemp -d)"; mkdir -p "$R5/.rabadon"
printf 'x = 1\n' > "$R5/app.py"
printf '999999 {"at":1}\n' > "$R5/.rabadon/net.lock"     # a pid that cannot exist
"$NET" "$R5" >/dev/null 2>&1
[ -f "$R5/.rabadon/net.json" ] \
  && ok "a lock left by a dead process is reclaimed (the net cannot wedge itself)" \
  || bad "stale lock blocked the net forever"

echo ""
echo "net: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
