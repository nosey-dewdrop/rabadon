#!/bin/bash
# llm-proposer.sh — the REAL-LLM proposer rabadon-loop swaps in via RABADON_PROPOSER.
#
# This is the ONLY new variable between the scripted proof (repair_proof.sh) and a
# real run: a live `claude -p` writes the fix instead of a canned script. Everything
# that DECIDES accept/reject — rabadon-verify running the project's real test, the
# forbidden-sha lock on the test file, the repair bound — is unchanged. Remove this
# proposer and the un-gameable kernel still stands; that is the moat test.
#
# BOUNDED by construction (the launch rule: no open-ended / overnight runs):
#   - RABADON_OFF=1 in our own env: the child `claude` fires this very gate on every
#     tool call; without the flag the supervisor supervises itself into recursion.
#   - exit-on-done: the process is torn down the instant the model signals completion
#     (stream-json terminal "result" event), not when it finally exits on its own —
#     it lingers ~160s past finishing. A poll loop bounds total wall-clock to CAP
#     (default 180s, override with RABADON_LLM_TIMEOUT); macOS ships no `timeout(1)`.
#   - one shot: no retry here — the loop owns the repair budget (RABADON_MAX_REPAIRS).
#
# Contract with rabadon-loop: the repair prompt arrives on stdin, cwd is the project
# dir. We make the edit and exit; the loop re-verifies against the real contract.
set -u
export RABADON_OFF=1      # recursion root-fix: the child's own gate must exit at once
export RABADON_JUDGE=0    # and no drift judge inside the child either

CAP="${RABADON_LLM_TIMEOUT:-180}"     # seconds, wall-clock hard cap
ALLOWED="${RABADON_LLM_TOOLS:-Read,Edit,Write}"   # honest path needs only these
prompt="$(cat)"                        # rabadon-loop pipes the repair prompt on stdin

# VERIFIED ROUTING (second face): rabadon-loop names the tier for THIS attempt in
# RABADON_MODEL (e.g. haiku for the first try, opus after the arbiter rejects it).
# Nothing else changes — same proposer, same bounds, same sidecar. Unset = the
# account default, so every existing caller behaves exactly as before.
MODEL_ARG=()
[ -n "${RABADON_MODEL:-}" ] && MODEL_ARG=(--model "$RABADON_MODEL")

# stream-json emits one event per line and ends with a terminal {"type":"result"}
# event. The measured problem: the claude process does its work in ~21s but then
# LINGERS ~160s before exiting on its own, so waiting for exit burns the full cap
# on every repair — which would poison the $/time report Step D is built on. Fix:
# don't wait for exit; leave the instant the work is provably done (result event
# seen, or the process exited). The poll loop IS the wall-clock cap (CAP*4 * 0.25s),
# so no separate watchdog subshell can orphan a sleep.
tmpout=$(mktemp /tmp/rabadon-llm-out.XXXXXX)
claude -p "$prompt" \
  --output-format stream-json --verbose \
  --permission-mode acceptEdits \
  "${MODEL_ARG[@]}" \
  --allowedTools "$ALLOWED" >"$tmpout" 2>/dev/null &
pid=$!
iters=$(( CAP * 4 )); i=0
while [ "$i" -lt "$iters" ]; do
  kill -0 "$pid" 2>/dev/null || break                       # exited on its own
  grep -q '"type":"result"' "$tmpout" 2>/dev/null && break  # model signalled done
  sleep 0.25; i=$((i+1))
done
kill -9 "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

# Step D fusing: the stream-json terminal {"type":"result"} event carries the
# byte-exact usage + total_cost_usd + duration_ms for THIS repair — the same
# numbers Langfuse would show, straight from the model's own accounting. Hand the
# raw result line to rabadon-loop via a sidecar so the spool becomes a self-
# contained, deterministic ledger (the trace renderer never has to hunt a
# transcript). Best-effort: absent RABADON_DIR or a text-mode proposer just
# means the trace shows the token column as "—", never a fabricated number.
if [ -n "${RABADON_DIR:-}" ]; then
  result_line=$(grep '"type":"result"' "$tmpout" 2>/dev/null | tail -1)
  [ -n "$result_line" ] && printf '%s\n' "$result_line" > "$RABADON_DIR/.proposer-metrics.json"
fi
rm -f "$tmpout"
exit 0
