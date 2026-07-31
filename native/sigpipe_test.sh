#!/usr/bin/env bash
# regression (adversarial-hunt CRITICAL): a DEAD watcher socket must never turn
# a block into an allow. The gate emits its verdict over the unix socket BEFORE
# exit(2); a peer-closed socket used to raise SIGPIPE and kill the gate
# mid-block, and Claude Code reads a signal-killed PreToolUse hook as ALLOW — so
# a force-push slipped through exactly when someone was watching. The fix:
# signal(SIGPIPE, SIG_IGN) so write() returns EPIPE (discarded) and the gate
# still reaches exit(2).
set -u
# HERMETIC: rabadon is DEFAULT-OFF, so the gate is dormant unless a project opts
# in (cwd/.rabadon/on) or the machine has ~/.rabadon/enabled. A test that reads
# the real HOME passes or fails on whether the developer happens to have rabadon
# switched on — which is not a test. Give this run its own HOME with the flag set.
export HOME="$(mktemp -d)"; mkdir -p "$HOME/.rabadon"; : > "$HOME/.rabadon/enabled"
export RABADON_NOTIFY=0
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

RD="$(mktemp -d)"; mkdir -p "$RD/spool"; : > "$RD/enabled"
# a watcher that accepts a connection then immediately slams it shut
python3 - "$RD/rabadon.sock" >/dev/null 2>&1 <<'PY' &
import socket, os, sys, time
p = sys.argv[1]
try: os.unlink(p)
except OSError: pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(p); s.listen(16)
s.settimeout(10)
end = time.time() + 10
while time.time() < end:
    try:
        c, _ = s.accept()
        c.close()          # peer-closed: the next write() from the gate hits EPIPE
    except Exception:
        break
PY
WPID=$!
sleep 0.4

D="$(mktemp -d)"; mkdir -p "$D/.rabadon"
cat > "$D/.rabadon/guard.json" <<'EOF'
{ "project": "sp", "bash": [{ "id": "no-force-push", "deny": "git\\s+push[^|;&]*--force", "why": "never force-push shared history" }] }
EOF
ev='{"hook_event_name":"PreToolUse","cwd":"'"$D"'","session_id":"sp","tool_use_id":"__ID__","tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}'

slipped=0
for i in $(seq 1 10); do
  printf '%s' "${ev/__ID__/s$i}" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
  rc=$?
  if [ $rc -ne 2 ]; then slipped=$((slipped+1)); echo "    run $i: rc=$rc (expected 2 = BLOCK; negative rc = signal-killed)"; fi
done
{ kill "$WPID"; wait "$WPID"; } 2>/dev/null

[ $slipped -eq 0 ] && ok "dead watcher never turns a block into an allow (10/10 exit 2, no SIGPIPE)" \
  || bad "$slipped/10 slipped through — the gate was killed mid-block"

# and the control: with NO watcher at all, the deny still blocks
RD2="$(mktemp -d)"; mkdir -p "$RD2/spool"; : > "$RD2/enabled"
printf '%s' "${ev/__ID__/n1}" | RABADON_DIR="$RD2" "$BIN" >/dev/null 2>&1
[ $? -eq 2 ] && ok "no watcher: deny still blocks (exit 2)" || bad "no-watcher deny should block"

# the wild bypass (caught live, 31.07): `git -C <path> push --force` slid past
# every `git\s+push` rule because the global option sits between them. The gate
# must also match the git-global-stripped form.
evc='{"hook_event_name":"PreToolUse","cwd":"'"$D"'","session_id":"sp","tool_use_id":"n2","tool_name":"Bash","tool_input":{"command":"git -C '"$D"' push origin main --force"}}'
printf '%s' "$evc" | RABADON_DIR="$RD2" "$BIN" >/dev/null 2>&1
[ $? -eq 2 ] && ok "git -C <path> push --force is still refused (global options stripped for the match)" \
  || bad "git -C bypass slipped through"

echo "gate sigpipe: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
