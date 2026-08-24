#!/usr/bin/env bash
# The watcher socket path and the kernel's cap on it.
#
# sockaddr_un.sun_path is 104 bytes on macOS and 108 on Linux, and it is not a
# soft limit: the kernel copies that many bytes and stops. gate.cpp's emitter
# used strncpy into that field with no length check, which does NOT fail when
# the path is too long -- it silently produces a DIFFERENT, SHORTER path that is
# a prefix of the one asked for, and then connects to it. Anyone able to create
# a socket at that prefix receives the ledger event stream.
#
# That is a Promise 1 violation before it is a security one: rabadon never goes
# quiet. "I could not open the watcher socket because the path is too long" is a
# sentence it must say. Falling back to spool-only is CORRECT; doing it silently,
# so the caller cannot tell "no watcher" from "wrong watcher", is not.
#
# The two sibling call sites already guard this (native/gated.cpp:157,
# native/gated_client.h:98, both with an explicit size check and a stderr line).
# gate.cpp was the one that was missed. This test is the check that was claimed
# to exist and did not -- see reports/R7/CHALLENGE-3.md.
#
# Headroom is NOT theoretical: a mktemp -d HOME, which this repo's own
# acceptance scripts use, produces a sockPath of ~85 bytes against a cap of 104.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "sock_path_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

# The cap is the kernel's, so the test asks the platform rather than assuming.
case "$(uname -s)" in
  Darwin) CAP=104 ;;
  *)      CAP=108 ;;
esac

TMP=$(mktemp -d /tmp/rbsock.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Build a RABADON_DIR deep enough that rdir + "/rabadon.sock" overruns CAP.
# gate.cpp:2736 sets sockPath = rabadon_home() + "/rabadon.sock" (13 bytes).
SUFFIX="/rabadon.sock"
NEED=$(( CAP + 4 - ${#SUFFIX} ))          # 4 bytes past the cap: no borderline
DEEP="$TMP"
while [ ${#DEEP} -lt "$NEED" ]; do DEEP="$DEEP/ddddddddd"; done
mkdir -p "$DEEP/spool"
SOCKPATH="$DEEP$SUFFIX"
TRUNC="$(printf '%s' "$SOCKPATH" | cut -c1-$((CAP - 1)))"   # where strncpy lands

[ ${#SOCKPATH} -gt "$CAP" ] || { echo "sock_path_test: fixture did not exceed the cap"; exit 1; }

# A listener sitting exactly at the truncation point. If the gate truncates, it
# connects HERE. This is the attacker's socket, and it must receive nothing.
CAUGHT="$TMP/caught.bin"
: > "$CAUGHT"
python3 - "$TRUNC" "$CAUGHT" <<'PY' &
import socket, sys, os
path, out = sys.argv[1], sys.argv[2]
try: os.unlink(path)
except OSError: pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path); s.listen(4)
s.settimeout(20)
try:
    c, _ = s.accept()
    c.settimeout(3)
    buf = b""
    while True:
        try:
            d = c.recv(65536)
        except socket.timeout:
            break
        if not d: break
        buf += d
    open(out, "wb").write(buf)
except socket.timeout:
    pass
PY
LPID=$!
# wait for the listener to actually bind (no sleep-and-hope)
for _ in $(seq 100); do [ -S "$TRUNC" ] && break; sleep 0.05; done
[ -S "$TRUNC" ] || { echo "sock_path_test: listener never bound at the truncation point"; kill $LPID 2>/dev/null; exit 1; }

PROJ="$TMP/proj"; mkdir -p "$PROJ"
EV='{"session_id":"sp","tool_use_id":"t1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo hello"},"cwd":"'"$PROJ"'"}'

ERR="$TMP/stderr.txt"
printf '%s' "$EV" | env HOME="$TMP/home" RABADON_DIR="$DEEP" RABADON_NOTIFY=0 \
  "$GATE" >"$TMP/stdout.txt" 2>"$ERR"
RC=$?

# give the listener a moment to flush whatever it got, then reap it
wait $LPID 2>/dev/null
BYTES=$(wc -c < "$CAUGHT" | tr -d ' ')

# (a) THE LEDGER MUST NOT GO TO THE TRUNCATED PATH.
if [ "$BYTES" -eq 0 ]; then
  pass "(a) nothing is delivered to the truncated socket path"
else
  fail "(a) $BYTES bytes were written to the TRUNCATED path $TRUNC"
  head -c 200 "$CAUGHT" | sed 's/^/       | /'
fi

# (b) IT MUST SAY WHY. Silence here is the Promise 1 violation: spool-only is a
# fine outcome, an unexplained spool-only is not.
if grep -qiE 'path is [0-9]+ bytes|too long|kernel limit' "$ERR"; then
  pass "(b) the reason is on stderr — the caller can tell this from 'no watcher'"
else
  fail "(b) nothing on stderr explains the refusal to connect (Promise 1: never go quiet)"
  [ -s "$ERR" ] && sed 's/^/       | /' "$ERR" || echo "       | (stderr was empty)"
fi

# (c) The gate still does its job. Failing to reach a watcher is not a reason to
# stop judging, and it must not become a crash either.
if [ "$RC" -eq 0 ] || [ "$RC" -eq 2 ]; then
  pass "(c) the gate still ran and exited cleanly (rc=$RC) — spool-only, not dead"
else
  fail "(c) the gate exited rc=$RC with an over-long socket path"
fi

echo
if [ "$bad" -eq 0 ]; then echo "sock_path_test: $ok ok"; exit 0; fi
echo "sock_path_test: $ok ok, $bad FAILED"; exit 1
