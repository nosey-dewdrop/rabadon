#!/usr/bin/env bash
# agents_test.sh — the same law, from a different agent.
#
# A guardrail that only works inside one editor is a plugin. The laws in this
# repository never depended on Claude Code: `git push --force origin main` is the
# same refusal whoever typed it. The BINDING depended on it, in five separate
# readings of Claude Code's field names inside gate.cpp's main(), and that is why
# "does it work in Cursor" had no answer.
#
# These cases drive REAL refusals through payloads that share no field names with
# each other. The Cursor cases carry no tool_input, no tool_name, no session_id.
# The generic case carries no editor's vocabulary at all. If a future change
# quietly re-couples the gate to one agent, the cross-dialect cases go red while
# the Claude Code ones stay green, which is exactly the shape that says what
# broke.
set -u
export HOME="$(mktemp -d)"; mkdir -p "$HOME/.rabadon"; : > "$HOME/.rabadon/enabled"
export RABADON_JUDGE=0        # no model is involved in any law tested here
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
DAY="$(date -u +%Y-%m-%d)"

newproj() {  # -> echoes "PROJ RD"
  local P RD
  P="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$P/.rabadon"
  cat > "$P/.rabadon/guard.json" <<'G'
{"project":"p","bash":[{"id":"no-wrangler-deploy","deny":"wrangler\\s+deploy\\b","why":"deploys go through CI, never from a live session"}]}
G
  echo "$P $RD"
}

fire() { # $1=project $2=rabadon-dir $3=payload -> sets RC/OUT/ERR
  OUT="$(printf '%s' "$3" | RABADON_DIR="$2" "$BIN" 2>/tmp/ag_err.$$)"; RC=$?
  ERR="$(cat /tmp/ag_err.$$)"
}

echo "agents: the same law, from a different agent"

# =====================================================================
# 1. CURSOR — beforeShellExecution, a baseline law
# =====================================================================
echo
echo "1. cursor: beforeShellExecution"
read -r P RD <<<"$(newproj)"
fire "$P" "$RD" '{"hook_event_name":"beforeShellExecution","command":"git push --force origin main","cwd":"'"$P"'","conversation_id":"conv-1","generation_id":"gen-1","cursor_version":"1.7","workspace_roots":["'"$P"'"]}'
[ "$RC" = 2 ] && ok "a force-push from cursor is refused (exit 2)" || bad "expected exit 2, got $RC"
printf '%s' "$OUT" | grep -q '"permission":"deny"' \
  && ok "the verdict is on STDOUT as a cursor permission object" \
  || { bad "no permission object on stdout"; echo "    $OUT"; }
printf '%s' "$OUT" | grep -q '"agent_message"' && printf '%s' "$OUT" | grep -q 'baseline-force-push' \
  && ok "the agent is told WHICH rule refused it (a block with no reason is half a block)" \
  || bad "agent_message missing or does not name the rule"
printf '%s' "$ERR" | grep -q 'baseline-force-push' \
  && ok "the operator's terminal still gets the human text on stderr" \
  || bad "stderr lost the refusal"
grep -q '"ev":"CHECK_FAIL"' "$RD/spool/$DAY.jsonl" 2>/dev/null \
  && ok "the refusal is on the same hash-chained ledger as every other agent's" \
  || bad "cursor refusal never reached the ledger"
grep -q '"pipe":"' "$RD/spool/$DAY.jsonl" 2>/dev/null \
  && ok "the ledger line carries a project pipe (cursor has no session_id; conversation_id stood in)" \
  || bad "no pipe on the ledger line"

# the project's OWN rule, not just the compiled-in floor
read -r P RD <<<"$(newproj)"
fire "$P" "$RD" '{"hook_event_name":"beforeShellExecution","command":"npx wrangler deploy","cwd":"'"$P"'","conversation_id":"c2","generation_id":"g2"}'
[ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q 'no-wrangler-deploy' \
  && ok "a guard.json rule written for Claude Code fires unchanged on cursor" \
  || bad "project rule did not fire on cursor (rc=$RC)"

# and an ordinary command is NOT refused — a gate that blocks everything is not a gate
read -r P RD <<<"$(newproj)"
fire "$P" "$RD" '{"hook_event_name":"beforeShellExecution","command":"ls -la","cwd":"'"$P"'","conversation_id":"c3","generation_id":"g3"}'
[ "$RC" = 0 ] && ok "an ordinary command from cursor passes (exit 0, no permission object)" \
  || { bad "false refusal on cursor (rc=$RC)"; echo "    $OUT"; }
printf '%s' "$OUT" | grep -q 'permission' && bad "an allow must not print a permission object" \
  || ok "an allow stays silent on stdout"

# =====================================================================
# 2. CURSOR — afterFileEdit, and the honest gap
# =====================================================================
echo
echo "2. cursor: afterFileEdit"
read -r P RD <<<"$(newproj)"
mkdir -p "$P/src"
fire "$P" "$RD" '{"hook_event_name":"afterFileEdit","file_path":"'"$P"'/src/x.js","edits":[{"old_string":"a","new_string":"b"}],"conversation_id":"c4","generation_id":"g4","workspace_roots":["'"$P"'"]}'
[ "$RC" = 0 ] && ok "an ordinary edit from cursor is recorded, not refused" || bad "edit wrongly refused (rc=$RC)"
grep -q '"ev":"STEP_OK"' "$RD/spool/$DAY.jsonl" 2>/dev/null \
  && ok "the edit lands on the ledger, so the session is observable on cursor too" \
  || bad "cursor edit never reached the ledger"
# Stated, not hidden: Cursor has no beforeFileEdit, so an agent edit can be seen
# but not stopped before it lands. Shell writes still go through
# beforeShellExecution, which IS pre-spend.
fire "$P" "$RD" '{"hook_event_name":"beforeShellExecution","command":"rm -rf /Users/nobody/some-other-project","cwd":"'"$P"'","conversation_id":"c5","generation_id":"g5"}'
[ "$RC" = 2 ] && ok "a destructive shell write from cursor IS refused before it runs" \
  || bad "shell write not refused on cursor (rc=$RC)"

# =====================================================================
# 3. THE GENERIC CONTRACT — an agent nobody wrote a parser for
# =====================================================================
echo
echo "3. generic: an agent rabadon has never heard of"
read -r P RD <<<"$(newproj)"
fire "$P" "$RD" '{"rabadon":1,"event":"pre_tool","tool":"bash","command":"rm -rf /Users/nobody/other-project","cwd":"'"$P"'","session":"s9","call":"c9"}'
[ "$RC" = 2 ] && ok "the documented contract refuses with no editor vocabulary at all (exit 2)" \
  || { bad "generic contract did not refuse (rc=$RC)"; echo "    $ERR"; }
printf '%s' "$ERR" | grep -q 'baseline-rm-rf-outside' \
  && ok "and it names the rule, so a fourth agent needs no code in this repo" \
  || bad "generic refusal did not name the rule"
read -r P RD <<<"$(newproj)"
fire "$P" "$RD" '{"rabadon":1,"event":"pre_tool","tool":"bash","command":"npx wrangler deploy","cwd":"'"$P"'","session":"s9","call":"c10"}'
[ "$RC" = 2 ] && ok "project rules apply to the generic contract too" || bad "generic missed the project rule (rc=$RC)"

# =====================================================================
# 4. CLAUDE CODE — the dialect that already worked still works
# =====================================================================
echo
echo "4. claude code: unchanged"
read -r P RD <<<"$(newproj)"
fire "$P" "$RD" '{"hook_event_name":"PreToolUse","cwd":"'"$P"'","session_id":"s1","tool_use_id":"t1","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
[ "$RC" = 2 ] && ok "a force-push from claude code is still refused (exit 2)" || bad "claude code regressed (rc=$RC)"
printf '%s' "$OUT" | grep -q 'permission' \
  && bad "claude code must NOT get cursor's permission object on stdout" \
  || ok "claude code stdout stays clean — the verdict travels on stderr + exit 2"

# =====================================================================
# 5. AN AGENT NOBODY RECOGNISES — fail open, never fail loud
# =====================================================================
echo
echo "5. an unrecognised payload"
read -r P RD <<<"$(newproj)"
fire "$P" "$RD" '{"hook_event_name":"someFutureEditorEvent","command":"git push --force origin main","cwd":"'"$P"'"}'
[ "$RC" = 0 ] && ok "an event no dialect claims falls open (exit 0), same as an unknown hook always did" \
  || bad "unknown dialect did not fail open (rc=$RC)"

rm -f /tmp/ag_err.$$ 2>/dev/null
echo
echo "agents: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
