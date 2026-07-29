#!/usr/bin/env bash
# rabadon budget cap — the deterministic halt-before-burn, proven two ways.
# The setter (rabadon-budget) writes the ceiling; the gate (rabadon-gate)
# measures this session's REAL usage from the transcript and refuses the next
# tool the moment the ceiling is reached — BEFORE it burns. Under cap: pass.
# Over cap: exit 2 + the halt message. All four token classes are counted, so a
# cache-only burn (which the old in+out-only ledger would have scored as zero)
# still trips the cap. The meter is opt-in: no budget.json -> no cost, no block.
set -u
# HERMETIC: rabadon is DEFAULT-OFF, so the gate is dormant unless a project opts
# in (cwd/.rabadon/on) or the machine has ~/.rabadon/enabled. A test that reads
# the real HOME passes or fails on whether the developer happens to have rabadon
# switched on — which is not a test. Give this run its own HOME with the flag set.
export HOME="$(mktemp -d)"; mkdir -p "$HOME/.rabadon"; : > "$HOME/.rabadon/enabled"
DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$DIR/rabadon-gate"
BUDGET="$DIR/rabadon-budget"
[ -x "$GATE" ]   || { echo "build first: make native/rabadon-gate";   exit 1; }
[ -x "$BUDGET" ] || { echo "build first: make native/rabadon-budget"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

# one assistant transcript line: $1=model $2=in $3=cacheCreate $4=cacheRead $5=out
line() {
  printf '{"type":"assistant","message":{"model":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' \
    "$1" "$2" "$3" "$4" "$5"
}
# fire a PreToolUse tool call through the real gate: $1=cwd $2=transcript $3=RABADON_DIR
fire() {
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"sess-b","tool_use_id":"tu-%s","tool_name":"Bash","tool_input":{"command":"echo hi"},"transcript_path":"%s"}' \
    "$1" "$RANDOM" "$2" | RABADON_DIR="$3" "$GATE"
}

# ============ the setter writes the exact shape the gate reads ============

# --- S1: '200k' -> {tokens:200000} ---
S="$(mktemp -d)"
"$BUDGET" 200k "$S" >/dev/null 2>&1
python3 -c "import json;assert json.load(open('$S/.rabadon/budget.json'))=={'tokens':200000}" \
  && ok "setter: '200k' writes {\"tokens\":200000}" || bad "setter tokens wrong"

# --- S2: '5usd' -> {usd:5} ---
"$BUDGET" 5usd "$S" >/dev/null 2>&1
python3 -c "import json;assert json.load(open('$S/.rabadon/budget.json'))=={'usd':5}" \
  && ok "setter: '5usd' writes {\"usd\":5}" || bad "setter usd wrong"

# --- S3: 'off' clears the cap ---
"$BUDGET" off "$S" >/dev/null 2>&1
[ ! -f "$S/.rabadon/budget.json" ] && ok "setter: 'off' clears the cap" || bad "setter off did not clear"

# --- S4: no-arg shows the cwd's cap, grouped ---
"$BUDGET" 200000 "$S" >/dev/null 2>&1
show="$(cd "$S" && "$BUDGET" 2>&1)"
echo "$show" | grep -qF "200,000 tokens" && ok "setter: show prints the current cap" || bad "show wrong: $show"

# ============ the gate enforces it — halt before burn ============

# --- E1: under cap -> tool passes ---
C="$(mktemp -d)"; RD="$(mktemp -d)"; T="$(mktemp)"
line "claude-opus-4-8" 100 300 600 50 > "$T"   # 1050 tokens total
"$BUDGET" 2000 "$C" >/dev/null 2>&1
fire "$C" "$T" "$RD" >/dev/null 2>&1; rc=$?
[ "$rc" = "0" ] && ok "under cap (1050/2000): the tool is allowed" || bad "under cap blocked (rc=$rc)"

# --- E2: over cap -> exit 2 + halt message ---
C="$(mktemp -d)"; RD="$(mktemp -d)"; T="$(mktemp)"
line "claude-opus-4-8" 100 300 600 50 > "$T"   # 1050
"$BUDGET" 1000 "$C" >/dev/null 2>&1
err="$(fire "$C" "$T" "$RD" 2>&1 1>/dev/null)"; rc=$?
{ [ "$rc" = "2" ] && echo "$err" | grep -qF "budget cap 1000 tokens" && echo "$err" | grep -qF "halted before burn"; } \
  && ok "over cap (1050/1000): halted before burn, exit 2 + message" || bad "over cap not halted (rc=$rc) [$err]"

# --- E3: all four token classes count — a cache-only burn still trips it ---
C="$(mktemp -d)"; RD="$(mktemp -d)"; T="$(mktemp)"
line "claude-opus-4-8" 0 0 1200 0 > "$T"   # cache_read only = 1200, in/out = 0
"$BUDGET" 1000 "$C" >/dev/null 2>&1
err="$(fire "$C" "$T" "$RD" 2>&1 1>/dev/null)"; rc=$?
{ [ "$rc" = "2" ] && echo "$err" | grep -qF "spent 1200 tokens"; } \
  && ok "cache tokens counted: cache-only 1200/1000 blocks (old ledger would miss it)" \
  || bad "cache tokens not counted (rc=$rc) [$err]"

# --- E4: no cap set -> the meter is opt-in, even a huge session passes ---
C="$(mktemp -d)"; RD="$(mktemp -d)"; T="$(mktemp)"
line "claude-opus-4-8" 100000 300000 600000 50000 > "$T"   # ~1.05M tokens
fire "$C" "$T" "$RD" >/dev/null 2>&1; rc=$?
[ "$rc" = "0" ] && ok "no budget.json: opt-in meter, huge usage still passes" || bad "opt-in broken (rc=$rc)"

# --- E5: 'budget-cap' in disabled[] is a real override ---
C="$(mktemp -d)"; mkdir -p "$C/.rabadon"; RD="$(mktemp -d)"; T="$(mktemp)"
line "claude-opus-4-8" 100 300 600 50 > "$T"   # 1050
"$BUDGET" 1000 "$C" >/dev/null 2>&1
echo '{"project":"c","disabled":["budget-cap"]}' > "$C/.rabadon/guard.json"
fire "$C" "$T" "$RD" >/dev/null 2>&1; rc=$?
[ "$rc" = "0" ] && ok "override: budget-cap in disabled[] lets the run through" || bad "disabled override ignored (rc=$rc)"

# --- E6: dollar cap, priced model, over -> blocked ---
C="$(mktemp -d)"; RD="$(mktemp -d)"; T="$(mktemp)"
line "claude-opus-4-8" 0 0 0 400 > "$T"        # opus out=400 -> $0.01
"$BUDGET" 0.009usd "$C" >/dev/null 2>&1
err="$(fire "$C" "$T" "$RD" 2>&1 1>/dev/null)"; rc=$?
{ [ "$rc" = "2" ] && echo "$err" | grep -qF 'budget cap $0.009' && echo "$err" | grep -qF "halted before burn"; } \
  && ok "usd cap (opus \$0.01/\$0.009): halted before burn" || bad "usd cap not enforced (rc=$rc) [$err]"

# --- E7: dollar cap, unpriced model -> usd skipped (no false block) ---
C="$(mktemp -d)"; RD="$(mktemp -d)"; T="$(mktemp)"
line "claude-mystery-9" 0 0 0 400 > "$T"       # would cost $0.01 IF we could price it
"$BUDGET" 0.009usd "$C" >/dev/null 2>&1
fire "$C" "$T" "$RD" >/dev/null 2>&1; rc=$?
[ "$rc" = "0" ] && ok "usd cap skipped for an unpriced model — no false halt" || bad "unknown model not skipped (rc=$rc)"

echo "budget gate: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
