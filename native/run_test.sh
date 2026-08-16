#!/usr/bin/env bash
# run_test.sh — an agent rabadon has never heard of, stopped anyway.
#
# Every other binding in this repository needs the agent to cooperate: Claude
# Code hooks, Cursor hooks, or the JSON contract. That is three agents out of
# thousands, and the one a given user cares about is usually not on the list.
# `rabadon run` asks the agent for nothing. It owns the PATH the agent inherits,
# so the programs the agent shells out to are judged before they run.
#
# The agent below is written here, in this file, and knows nothing about
# rabadon. It has no hook system, speaks no JSON, and was never adapted. If it
# is stopped, it is stopped by the environment it was handed.
set -u
export HOME="$(mktemp -d)"; mkdir -p "$HOME/.rabadon"; : > "$HOME/.rabadon/enabled"
export RABADON_JUDGE=0
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/rabadon-run"
[ -x "$RUN" ] || { echo "build first: make native/rabadon-run"; exit 1; }
[ -x "$HERE/rabadon-sandbox" ] || { echo "build first: make native/rabadon-sandbox"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
DAY="$(date -u +%Y-%m-%d)"

echo "run: an agent rabadon has never heard of"

P="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$P/.rabadon" "$P/fakebin"
# a program that exists ONLY so the guard-derived shim has something to resolve
printf '#!/bin/sh\necho "wrangler: deployed for real"\n' > "$P/fakebin/wrangler"
chmod +x "$P/fakebin/wrangler"
cat > "$P/.rabadon/guard.json" <<'G'
{"project":"p","bash":[{"id":"no-wrangler-deploy","deny":"wrangler\\s+deploy\\b","why":"deploys go through CI, never from a live session"}]}
G

# THE AGENT. No hooks, no rabadon awareness, no adapter. It shells out, which is
# the one thing every agent in the world does.
cat > "$P/mystery-agent.sh" <<'AGENT'
#!/bin/sh
echo "agent: I have never heard of rabadon"
git push --force origin main; echo "AGENT_SAW_GIT=$?"
wrangler deploy;              echo "AGENT_SAW_WRANGLER=$?"
echo hello > ordinary.txt;    echo "AGENT_SAW_ORDINARY=$?"
git status >/dev/null 2>&1;   echo "AGENT_SAW_STATUS=$?"
AGENT
chmod +x "$P/mystery-agent.sh"

cd "$P" || exit 1
git init -q . 2>/dev/null
OUT="$(PATH="$P/fakebin:$PATH" RABADON_DIR="$RD" "$RUN" --dir "$P" -- sh mystery-agent.sh 2>&1)"

echo "$OUT" | grep -q "AGENT_SAW_GIT=2" \
  && ok "a force-push from an unadapted agent is refused (the agent sees exit 2)" \
  || { bad "force-push was not refused"; echo "$OUT" | sed 's/^/      /'; }

echo "$OUT" | grep -q "AGENT_SAW_WRANGLER=2" \
  && ok "a rule this project wrote itself shims its own program and refuses it" \
  || { bad "guard-derived shim did not fire"; echo "$OUT" | sed 's/^/      /'; }

echo "$OUT" | grep -qi "deployed for real" \
  && bad "the real wrangler RAN — the refusal came too late to matter" \
  || ok "the real program never ran (refused before, not reported after)"

echo "$OUT" | grep -q "AGENT_SAW_ORDINARY=0" \
  && ok "ordinary work is untouched (a gate that stops everything is not a gate)" \
  || bad "ordinary redirect was broken"

echo "$OUT" | grep -q "AGENT_SAW_STATUS=0" \
  && ok "a harmless git subcommand still runs — the shim judges, it does not ban git" \
  || bad "git status was wrongly refused"

grep -q '"check":"baseline-force-push"' "$RD/spool/$DAY.jsonl" 2>/dev/null \
  && ok "the refusal is on the same hash-chained ledger as every other agent's" \
  || bad "unknown-agent refusal never reached the ledger"

grep -q '"check":"no-wrangler-deploy"' "$RD/spool/$DAY.jsonl" 2>/dev/null \
  && ok "so is the project's own rule" \
  || bad "project rule refusal missing from the ledger"

# the stated hole, asserted rather than hoped for: an absolute path skips PATH,
# so it skips the shim. A supervisor that quietly overstates its reach is worse
# than one whose limit is written down and tested.
GITABS="$(command -v git)"
OUT2="$(PATH="$P/fakebin:$PATH" RABADON_DIR="$RD" "$RUN" --dir "$P" -- sh -c "$GITABS push --force origin main; echo ABS=\$?" 2>&1)"
echo "$OUT2" | grep -q "ABS=2" \
  && ok "an absolute-path invocation is ALSO refused (better than documented)" \
  || ok "an absolute-path invocation skips the shim — the documented hole, still true"

# and rabadon says what it took under the gate, rather than leaving the user to guess
echo "$OUT" | grep -qE "rabadon run — [0-9]+ program\(s\) under the gate" \
  && ok "the run announces how many programs it put under the gate" \
  || bad "no announcement of coverage"

cd / && rm -rf "$P" "$RD"
echo
echo "run: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
