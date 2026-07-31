#!/bin/bash
# baseline_test.sh — rabadon protects a repo it was never configured for.
#
# Until 0.4 a project with no .rabadon/guard.json got a gate that refused
# NOTHING: with enforce on, `git push --force origin main` and `rm -rf /` both
# exited 0. README.md and package.json promised every new installer "the
# deterministic gate refuses the force-push before it rewrites history". For a
# fresh install that sentence was false, and it is the first sentence anyone
# reads. Three laws are compiled into the binary now.
#
# This suite runs with NO guard.json anywhere, then proves guard.json still
# rules where it exists.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "baseline_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

TMP=$(mktemp -d /tmp/rabadon-baseline-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.rabadon/spool"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
PROJ="$TMP/proj"; mkdir -p "$PROJ/.git" "$PROJ/build" "$PROJ/node_modules"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"
mkdir -p "$HOME/Documents"

# NO .rabadon/ directory in the project at all — the fresh-install case.
run() { # run <cwd> <command>  -> exit code, spool grows
  printf '{"hook_event_name":"PreToolUse","session_id":"s-base","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
spool_has() { grep -h "$1" "$RABADON_DIR/spool/"*.jsonl 2>/dev/null | tail -1; }

echo "baseline: the three laws, with no guard.json"

touch "$HOME/.rabadon/enabled"      # enforce

# --- refused (exit 2) ---
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused: $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
force-push to main|git push --force origin main
force-push short flag to master|git push -f origin master
recursive delete outside the tree|rm -rf ~/Documents
recursive delete of /|rm -rf /
hard reset onto a shared branch|git reset --hard origin/main
EOF

# --- allowed (exit 0), the false positives that would make someone uninstall ---
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<'EOF'
ordinary feature-branch push|git push origin feature/my-branch
--force-with-lease is the safe form|git push --force-with-lease origin my-branch
force-push to your own branch|git push --force origin my-personal-branch
build dir delete|rm -rf ./build
node_modules delete|rm -rf node_modules
local hard reset|git reset --hard HEAD~1
EOF

# every refusal is on the ledger, by baseline id
STOP=$(spool_has '"rule":"baseline-force-push"')
[ -n "$STOP" ] && pass "the refusal is written to the ledger under its baseline id" || fail "no baseline-force-push event on the ledger"

# --- watch mode: recorded, not enforced ---
rm -f "$HOME/.rabadon/enabled"
RC=$(run "$PROJ" "git push --force origin main")
WB=$(spool_has '"ev":"WOULD_BLOCK"')
if [ "$RC" = "0" ] && [ -n "$WB" ]; then pass "watch mode: exit 0, WOULD_BLOCK on the ledger"; else fail "watch mode: rc=$RC would_block=${WB:+yes}"; fi
touch "$HOME/.rabadon/enabled"

# --- the escape hatch: disabled[] by id ---
mkdir -p "$PROJ/.rabadon"
cat > "$PROJ/.rabadon/guard.json" <<'EOF'
{ "project": "proj", "disabled": ["baseline-force-push", "baseline-rm-rf-outside", "baseline-hard-reset"] }
EOF
RC=$(run "$PROJ" "git push --force origin main"); [ "$RC" = "0" ] && pass "disabled[]: baseline-force-push silenced by id" || fail "disabled force-push: rc=$RC"
RC=$(run "$PROJ" "rm -rf ~/Documents");           [ "$RC" = "0" ] && pass "disabled[]: baseline-rm-rf-outside silenced by id" || fail "disabled rm: rc=$RC"
RC=$(run "$PROJ" "git reset --hard origin/main"); [ "$RC" = "0" ] && pass "disabled[]: baseline-hard-reset silenced by id" || fail "disabled reset: rc=$RC"

# --- regression: a project WITH a guard behaves exactly as before ---
cat > "$PROJ/.rabadon/guard.json" <<'EOF'
{ "project": "proj", "bash": [
  { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b", "why": "test rule" }
] }
EOF
RC=$(run "$PROJ" "git push --force origin main")
RULE=$(spool_has '"ev":"STOP"' | python3 -c 'import sys,json;print(json.loads(sys.stdin.read() or "{}").get("rule",""))' 2>/dev/null)
if [ "$RC" = "2" ] && [ "$RULE" = "no-force-push-main" ]; then
  pass "with a guard, the USER's rule id is what lands on the ledger (not the baseline's)"
else fail "guard precedence: rc=$RC rule='$RULE'"; fi

# and the project's own rule still fires on what only it knows about
cat > "$PROJ/.rabadon/guard.json" <<'EOF'
{ "project": "proj", "bash": [
  { "id": "no-prod-deploy", "deny": "deploy\\s+--prod", "why": "ask first" }
] }
EOF
RC=$(run "$PROJ" "deploy --prod"); [ "$RC" = "2" ] && pass "guard.json extends the floor: a project rule still refuses" || fail "project rule: rc=$RC"

# ...and the baseline still holds underneath that same guard
RC=$(run "$PROJ" "rm -rf /"); [ "$RC" = "2" ] && pass "the baseline holds under a guard that never mentions it" || fail "baseline under guard: rc=$RC"

echo "baseline: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
