#!/bin/bash
# ledger_utf8_test.sh — the ledger must be readable by a standard JSON parser,
# not only by the hash that chains it.
#
# Found in the field on 2 August 2026, while running the gate over a foreign
# repository. Eight of that day's 982 spool lines could not be decoded as UTF-8.
# `rabadon audit` still reported "chain OK · head verified" for the same file,
# because the chain hashes bytes and never asks whether those bytes are text.
#
# The cause is one cut. gate.cpp labels a Bash step with the first 80 BYTES of
# the command (`"bash: " + command.substr(0, 80)`), and a command carrying a
# multi-byte character across that boundary loses part of it. `═` is three bytes
# (e2 95 90); the ledger kept `e2 95` and wrote it straight into a JSON string,
# because json_escape passes every byte through untouched. RFC 8259 requires
# JSON text to be valid UTF-8, so those lines are not JSON. Python refuses them,
# jq silently substitutes, and an independent verifier written from a spec would
# stop at the first one.
#
# Two properties are asserted here, and they are different properties:
#   1. every emitted line decodes as UTF-8 and parses with a strict JSON parser;
#   2. the step label still carries the readable beginning of the command, so
#      the fix is not "drop the label".
#
# SAFETY: everything happens under one mktemp root, HOME points inside it, the
# temp repo has no remote, and no command in this file is ever executed by a
# shell — the gate only ever reads them as text on stdin.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "ledger_utf8_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

ROOT=$(mktemp -d /tmp/rabadon-utf8-test.XXXXXX)
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"; mkdir -p "$HOME/.rabadon/spool"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
touch "$HOME/.rabadon/enabled"

PROJ="$ROOT/proj"; mkdir -p "$PROJ"
git -C "$PROJ" init -q 2>/dev/null || mkdir -p "$PROJ/.git"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"
[ -z "$(git -C "$PROJ" remote 2>/dev/null)" ] || { echo "test repo HAS a remote — refusing to run"; exit 1; }

# ensure_ascii=False on purpose: the hook payload the gate really receives
# carries raw UTF-8, and escaping it to \uXXXX here would hide the whole bug.
jq_str() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"; }

gate() {
  printf '{"hook_event_name":"PreToolUse","session_id":"s-utf8","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$PROJ" "$(jq_str "$1")" | "$GATE" >/dev/null 2>&1
}

# Each command below is harmless and puts a multi-byte character across a
# different byte offset near the 80-byte label boundary, so at least one of them
# lands mid-character no matter where the cut sits.
echo "ledger: a multi-byte command must not leave half a character in the spool"
for pad in 70 71 72 73 74 75 76 77 78 79 80; do
  gate "echo $(python3 -c "print('a'*$pad)")═══════ tail"
done
gate "echo şşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşşş done"
gate "echo 🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂🙂 done"

SPOOL=$(ls "$HOME/.rabadon/spool"/*.jsonl 2>/dev/null | head -1)
[ -n "$SPOOL" ] || { echo "  FAIL - the gate wrote no spool file"; exit 1; }

REPORT=$(python3 - "$SPOOL" <<'PY'
import json, sys
bad_utf8 = bad_json = total = 0
first = ""
for raw in open(sys.argv[1], "rb").read().split(b"\n"):
    if not raw.strip():
        continue
    total += 1
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        bad_utf8 += 1
        if not first:
            first = repr(raw[max(0, e.start - 24):e.start + 4])
        continue
    try:
        json.loads(text)
    except ValueError as e:
        bad_json += 1
        if not first:
            first = str(e)[:80]
print(f"{total} {bad_utf8} {bad_json} {first}")
PY
)
TOTAL=$(echo "$REPORT" | cut -d' ' -f1)
BAD_UTF8=$(echo "$REPORT" | cut -d' ' -f2)
BAD_JSON=$(echo "$REPORT" | cut -d' ' -f3)
WHERE=$(echo "$REPORT" | cut -d' ' -f4-)

[ "$BAD_UTF8" = "0" ] \
  && pass "all $TOTAL spool line(s) decode as UTF-8" \
  || fail "$BAD_UTF8 of $TOTAL spool line(s) are not UTF-8 — first at $WHERE"

# counted over the lines that decoded; a line that is not UTF-8 never reaches a
# JSON parser at all, so it is reported by the assertion above, not by this one.
[ "$BAD_JSON" = "0" ] \
  && pass "every decodable spool line parses with a strict JSON parser" \
  || fail "$BAD_JSON decodable spool line(s) do not parse — $WHERE"

# the twin: clamping must not turn the label into nothing
KEPT=$(python3 - "$SPOOL" <<'PY'
import json, sys
for raw in open(sys.argv[1], "rb").read().split(b"\n"):
    if not raw.strip():
        continue
    try:
        e = json.loads(raw.decode("utf-8", "replace"))
    except ValueError:
        continue
    step = e.get("step", "")
    if step.startswith("bash: echo aaaaaaaaaa"):
        print("yes")
        break
else:
    print("no")
PY
)
[ "$KEPT" = "yes" ] \
  && pass "the step label still carries the readable head of the command" \
  || fail "the step label lost the command text entirely"

echo
echo "ledger_utf8_test: $ok ok, $bad failed"
[ "$bad" = "0" ] || exit 1
