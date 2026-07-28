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
#   - hard wall-clock cap: macOS ships no `timeout(1)`, so a portable watchdog kills
#     an overrunning child. Default 180s, override with RABADON_LLM_TIMEOUT.
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

# portable timeout: run claude in the background, SIGKILL it if it overruns CAP.
claude -p "$prompt" \
  --output-format text \
  --permission-mode acceptEdits \
  --allowedTools "$ALLOWED" >/dev/null 2>&1 &
pid=$!
( sleep "$CAP"; kill -9 "$pid" 2>/dev/null ) &
watcher=$!
wait "$pid" 2>/dev/null
kill "$watcher" 2>/dev/null
exit 0
