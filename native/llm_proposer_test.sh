#!/usr/bin/env bash
# llm-proposer.sh argv assembly — deterministic, no live claude, no tokens spent.
#
# WHY THIS EXISTS: the proposer builds the claude argv in a bash ARRAY so the
# --model flag can be present or absent without quoting games. On macOS /bin/bash
# is 3.2.57, and there an EMPTY array expansion counts as "unbound" under
# `set -u` — even though the array was assigned two lines earlier. So the
# default path (no RABADON_MODEL, i.e. every caller that does not route) killed
# the proposer before `claude` was ever spawned. The loop still fails closed on
# it, but for the wrong reason: not "the model could not fix it", just "the
# proposer never ran".
#
# The thing under test is therefore the ARGV, not a model. `claude` is replaced
# by a stub that records the argv it was called with. That makes the untested
# region exactly the shell code we own.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PROPOSER="$HERE/llm-proposer.sh"
[ -x "$PROPOSER" ] || { echo "not executable: $PROPOSER"; exit 1; }
PASS=0; FAIL=0
ok(){  PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# stub claude: records argv, emits one terminal stream-json result event so the
# proposer's poll loop leaves at once. Never touches the network.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_ARGV_LOG"
printf '{"type":"result","subtype":"success","total_cost_usd":0.0,"duration_ms":1}\n'
exit 0
STUB
chmod +x "$TMP/bin/claude"

# run the real proposer with the stub in front of PATH.
# $1 = case name; env RABADON_MODEL is set by the caller when routing.
run_proposer(){
  local name="$1"
  STUB_ARGV_LOG="$TMP/$name.argv"; export STUB_ARGV_LOG
  rm -f "$STUB_ARGV_LOG"
  printf 'repair the off-by-one\n' \
    | PATH="$TMP/bin:$PATH" "$PROPOSER" >"$TMP/$name.out" 2>"$TMP/$name.err"
  echo $?
}

# ---- case 1 (POSITIVE FIRST): routing on -> --model reaches claude ----
# This runs before the absence checks on purpose. It proves the stub really
# records argv and that "--model" is a string this script can actually find; a
# renamed flag fails HERE loudly instead of making case 2's absence checks pass
# for free.
RABADON_MODEL=haiku; export RABADON_MODEL
RC1="$(run_proposer routed)"
unset RABADON_MODEL
if [ -s "$TMP/routed.argv" ]; then
  ok "routed: claude was actually spawned (argv recorded)"
else
  bad "routed: claude never ran — argv log empty"
fi
if grep -qx -- '--model' "$TMP/routed.argv" 2>/dev/null; then
  ok "routed: --model is passed through to claude"
else
  bad "routed: --model missing from argv (the flag this suite greps for is gone)"
fi
if grep -qx -- 'haiku' "$TMP/routed.argv" 2>/dev/null; then
  ok "routed: the tier name from RABADON_MODEL is the flag's value (haiku)"
else
  bad "routed: RABADON_MODEL value did not reach claude"
fi
[ "$RC1" = 0 ] && ok "routed: proposer exits 0" || bad "routed: proposer exit $RC1"

# ---- case 2 (THE REGRESSION): no routing -> claude must STILL be spawned ----
# Asserted positively. "no unbound-variable message" alone would keep passing if
# the whole invocation were deleted; "the argv log is non-empty" cannot.
RC2="$(run_proposer default)"
if [ -s "$TMP/default.argv" ]; then
  ok "default: claude spawned with RABADON_MODEL unset (bash 3.2 empty-array path)"
else
  bad "default: claude NEVER ran — proposer died before spawning it. stderr: $(tr '\n' ' ' < "$TMP/default.err")"
fi
if grep -q 'unbound variable' "$TMP/default.err" 2>/dev/null; then
  bad "default: set -u tripped on the empty array: $(grep 'unbound variable' "$TMP/default.err")"
else
  ok "default: no unbound-variable abort on the empty MODEL_ARG"
fi
if grep -qx -- '--model' "$TMP/default.argv" 2>/dev/null; then
  bad "default: --model passed with no RABADON_MODEL set"
else
  ok "default: no --model flag when no tier was named (account default is used)"
fi
if grep -qx -- '-p' "$TMP/default.argv" 2>/dev/null; then
  ok "default: the prompt flag -p survives the empty-array expansion"
else
  bad "default: -p missing — argv assembly is broken past the model flag"
fi
[ "$RC2" = 0 ] && ok "default: proposer exits 0" || bad "default: proposer exit $RC2"

# ---- case 3: the metrics sidecar, present and absent ----
# RABADON_DIR set and REAL -> the terminal result event is handed to the loop.
mkdir -p "$TMP/ledger"
RABADON_DIR="$TMP/ledger"; export RABADON_DIR
run_proposer sidecar >/dev/null
if [ -s "$TMP/ledger/.proposer-metrics.json" ] \
   && grep -q '"type":"result"' "$TMP/ledger/.proposer-metrics.json"; then
  ok "sidecar: the model's own result event is written for the loop to price"
else
  bad "sidecar: .proposer-metrics.json missing or not a result event"
fi
# RABADON_DIR set but the directory does not exist -> documented as best-effort,
# so it must be SILENT, not a shell error on stderr.
RABADON_DIR="$TMP/no-such-ledger"
run_proposer nodir >/dev/null
if [ -s "$TMP/nodir.err" ]; then
  bad "sidecar: best-effort write errored on a missing RABADON_DIR: $(tr '\n' ' ' < "$TMP/nodir.err")"
else
  ok "sidecar: a missing RABADON_DIR stays silent (best-effort, as documented)"
fi
unset RABADON_DIR

echo ""
echo "llm-proposer: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
