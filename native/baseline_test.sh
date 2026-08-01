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

# --- the temp area: scratch is not data -------------------------------------
# 73 of the refusals on the four-session watch ledger were this rule, and 68 of
# them were an agent deleting a directory it had made under /tmp minutes before.
# The carve-out is only worth having if it is narrow, so the must-block list
# comes FIRST and is longer than the must-allow list: a temp exemption that also
# swallowed $HOME, /, /etc or a path that walks out of /tmp would have bought
# precision by deleting the product.
#
# Nothing here is executed. Every command is handed to the gate on stdin and
# only its exit code is read; the canaries below are the proof.
CANARY_HOME="$HOME/Documents/keep.txt"
echo "do not lose me" > "$CANARY_HOME"
mkdir -p "$TMP/scratch/deep"
echo "scratch" > "$TMP/scratch/deep/file.txt"
ln -s "$HOME/Documents" "$TMP/scratch/escape-home"
ln -s /etc "$TMP/scratch/escape-etc"
REALTMP=$(cd /tmp && pwd -P)          # /private/tmp on macOS, /tmp on linux
MKTMP=$(mktemp -d)                    # /var/folders/... under a launchd session

echo "baseline: the temp area (must-block first)"

while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused: $desc" || fail "NOT refused ($RC): $cmd"
done <<EOF
home directory root|rm -rf $HOME
a directory under a home that itself sits under /tmp|rm -rf $HOME/bir_sey
the temp root itself, named directly|rm -rf /tmp
the temp root itself, as it really resolves|rm -rf $REALTMP
walking out of the temp dir with ..|rm -rf /tmp/../Users/x
walking out of the temp dir into /etc|rm -rf /tmp/../etc
a symlink in the temp dir pointing at a home dir|rm -rf $TMP/scratch/escape-home
a symlink in the temp dir pointing at /etc|rm -rf $TMP/scratch/escape-etc
the users tree|rm -rf /Users
a system config dir|rm -rf /etc/nginx
a system library dir|rm -rf /usr/local/lib
/var outside the temp area|rm -rf /var/log
an external disk|rm -rf /Volumes/Backup/photos
another project tree under the home dir|rm -rf $HOME/work/proj5
EOF

while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<EOF
a scratch dir under /tmp|rm -rf /tmp/scratch
a nested scratch dir under /tmp|rm -rf /tmp/build-scratch/out
the same path written as it resolves|rm -rf $REALTMP/scratch
a dir mktemp -d actually handed out|rm -rf $MKTMP
a scratch dir under /var/tmp|rm -rf /var/tmp/proj-cache
a glob under the temp root|rm -rf /tmp/rb-scratch.*
a glob one level deeper|rm -rf /tmp/proj-out/*
a scratch dir this run made and is about to remake|rm -rf /tmp/fp && mkdir -p /tmp/fp/out
relative path with the shell already in a temp dir|cd /tmp/work && rm -rf out
EOF

# $TMPDIR is environment, and the environment is what an agent can change. If it
# were trusted as written, TMPDIR=/ would make the whole disk scratch space.
run_env() { # run_env <cwd> <command> <VAR=VAL>...
  local cwd="$1" cmd="$2"; shift 2
  printf '{"hook_event_name":"PreToolUse","session_id":"s-base","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$cwd" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$cmd")" \
    | env "$@" "$GATE" >/dev/null 2>&1
  echo $?
}
RC=$(run_env "$PROJ" "rm -rf /Users/someone/work" "TMPDIR=/")
[ "$RC" = "2" ] && pass "TMPDIR=/ does not turn the disk into scratch space" || fail "TMPDIR=/ opened /Users: rc=$RC"
RC=$(run_env "$PROJ" "rm -rf $HOME/bir_sey" "TMPDIR=$HOME")
[ "$RC" = "2" ] && pass "TMPDIR=\$HOME does not turn the home dir into scratch space" || fail "TMPDIR=\$HOME opened the home dir: rc=$RC"
RC=$(run_env "$PROJ" "rm -rf /tmp/scratch" "TMPDIR=/")
[ "$RC" = "0" ] && pass "a bogus TMPDIR does not take /tmp away either" || fail "bogus TMPDIR lost /tmp: rc=$RC"

# judging is not running: everything the block above named is still here
[ -f "$CANARY_HOME" ] && [ "$(cat "$CANARY_HOME")" = "do not lose me" ] \
  && pass "canary in the home dir survived judging 26 deletes" || fail "canary in the home dir is gone"
[ -f "$TMP/scratch/deep/file.txt" ] \
  && pass "canary in the temp dir survived judging 26 deletes" || fail "canary in the temp dir is gone"
[ -d "$MKTMP" ] && pass "the mktemp dir survived judging 26 deletes" || fail "the mktemp dir is gone"
[ -d /tmp ] && [ -d /etc ] && pass "/tmp and /etc are still on the machine" || fail "the test ran what it judged"
rmdir "$MKTMP" 2>/dev/null

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
