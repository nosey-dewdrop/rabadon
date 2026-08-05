#!/usr/bin/env bash
# The switch, when it cannot be read.
#
# rabadon decides between WATCH and ENFORCE by looking for one flag file. That
# look was a bare stat(), and stat() answers "not there" and "not allowed to
# look" with the same false. So an installed, enabled gate on a machine whose
# home had gone unreadable resolved to WATCH and returned exit 0 on a
# force-push, printing nothing. From the user's seat that is identical to a
# gate that examined the command and approved it.
#
# Measured 5 August, before this file existed: unset HOME, RABADON_DIR pointing
# at a regular file, RABADON_DIR at mode 000, and a read-only home all produced
# exit 0 with zero bytes of output. In the same run every storage failure fell
# closed, including a real ENOSPC on a full disk.
#
# The law this file holds: an ABSENT flag still watches, because that is a
# choice the user made. An UNREADABLE flag enforces and says why, because
# nothing dangerous may pass silently.
set -u
# RABADON_GATE_BIN lets this file be pointed at a gate built from an older
# commit, which is how the red-before-green proof was taken.
BIN="${RABADON_GATE_BIN:-$(cd "$(dirname "$0")" && pwd)/rabadon-gate}"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

PROJ="$(mktemp -d)"

# One dangerous PreToolUse event. The id must be unique per call or the gate's
# twin-delivery dedupe swallows the repeat and the exit code means nothing.
danger() { # $1 = unique tag
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"s-%s","tool_use_id":"t-%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
    "$PROJ" "$1" "$1"
}

# run <tag> ; echoes the exit code, stderr captured to $ERRFILE
ERRFILE="$(mktemp)"
run() { danger "$1" | "$BIN" >/dev/null 2>"$ERRFILE"; echo $?; }

# --- A: the flag is genuinely absent -> WATCH, the user never turned it on ---
D_absent="$(mktemp -d)"
rc=$(RABADON_DIR="$D_absent" run absent)
[ "$rc" = 0 ] && ok "an absent switch still watches (exit 0)" \
              || bad "an absent switch should watch, got exit $rc"

# --- B: the flag is present -> ENFORCE, the ordinary path still works ---
D_on="$(mktemp -d)"; : > "$D_on/enabled"
rc=$(RABADON_DIR="$D_on" run present)
[ "$rc" = 2 ] && ok "a present switch enforces (exit 2)" \
              || bad "a present switch should enforce, got exit $rc"

# --- C: the home is a regular file -> unreadable, not absent ---
D_file="$(mktemp)"
rc=$(RABADON_DIR="$D_file" run regfile)
[ "$rc" = 2 ] && ok "a home that is a regular file enforces (exit 2)" \
              || bad "a home that is a regular file must not pass silently, got exit $rc"
grep -q "cannot read its own switch" "$ERRFILE" \
  && ok "and it says why" || bad "it enforced without saying why"

# --- D: the home cannot be entered -> unreadable ---
if [ "$(id -u)" = 0 ]; then
  echo "  skip - mode 000 is meaningless as root"
else
  D_000="$(mktemp -d)"; chmod 000 "$D_000"
  rc=$(RABADON_DIR="$D_000" run mode000)
  chmod 755 "$D_000"
  [ "$rc" = 2 ] && ok "an unreadable home enforces (exit 2)" \
                || bad "an unreadable home must not pass silently, got exit $rc"
fi

# --- E: nobody named a home at all -> the path would be a guess ---
rc=$(danger nohome | env -u HOME -u RABADON_DIR "$BIN" >/dev/null 2>"$ERRFILE"; echo $?)
[ "$rc" = 2 ] && ok "with no home named at all it enforces (exit 2)" \
              || bad "an unnamed home must not pass silently, got exit $rc"

# --- F: the safe command is still allowed while blind ---
rc=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"s-safe","tool_use_id":"t-safe","tool_name":"Bash","tool_input":{"command":"git status"}}' "$PROJ" \
     | env -u HOME -u RABADON_DIR "$BIN" >/dev/null 2>&1; echo $?)
[ "$rc" = 0 ] && ok "blind enforcement still allows a harmless command" \
              || bad "blind enforcement must not block everything, got exit $rc"

echo
echo "blind switch: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
