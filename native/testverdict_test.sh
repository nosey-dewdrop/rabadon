#!/usr/bin/env bash
# testverdict_test.sh — "the pattern did not match" was being read as "the suite
# failed", and those are different sentences.
#
# The PostToolUse path watches a Bash result go by, matches testPassPattern
# against the TEXT, and on no match stamps lastTestFail. No exit code reaches a
# post hook, so the text is all there is — and the text is not always there.
# Redirect a suite to a file, `make test > /tmp/log 2>&1`, and the hook sees
# `EXIT=0` and nothing else.
#
# Measured in rabadon's own repo, 3 August 14:24:28. `make test` exited 0 with
# 2942 ok lines and zero failing assertions. state.json recorded lastTestFail at
# that exact second, so the supervisor declared the suite RED while it was
# green. The handoff writes that verdict down and the next session is told, in
# as many words, "if tests are RED above: that is the open front — start there."
# A false red does not let a bad fix through; it sends the next session hunting
# a failure that does not exist.
#
# Same root as the false GREEN closed in pushgate_forge_test.sh, pointing the
# other way, and the same answer: when there is no evidence, say so. Not green,
# not red. The third answer the net has had all along.
#
# The twins are the point. A suite that really failed must still turn the state
# red, whether it counts its failures, prints make's `*** Error 1`, or dies on a
# segfault with no vocabulary at all.
set -u
export HOME="$(mktemp -d)"; mkdir -p "$HOME/.rabadon"; : > "$HOME/.rabadon/enabled"
export RABADON_NOTIFY=0 RABADON_JUDGE=0
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

# verdict <tool_response-json> -> prints "pass" | "fail" | "unknown"
verdict(){
  d="$(mktemp -d)"; mkdir -p "$d/.rabadon"
  echo '{"project":"p","testCommand":"make test"}' > "$d/.rabadon/guard.json"
  echo '{"lastCodeEdit":0,"lastTestPass":0,"lastTestFail":0,"sessions":{}}' > "$d/.rabadon/state.json"
  RD="$(mktemp -d)"; : > "$RD/enabled"
  RESP="$1" CWD="$d" python3 - <<'PY' > "$d/ev.json"
import json, os
print(json.dumps({
    "hook_event_name": "PostToolUse", "cwd": os.environ["CWD"],
    "session_id": "tv", "tool_use_id": "t1", "tool_name": "Bash",
    "tool_input": {"command": "make test"},
    "tool_response": json.loads(os.environ["RESP"])}))
PY
  RABADON_DIR="$RD" "$BIN" < "$d/ev.json" >/dev/null 2>&1
  python3 -c "
import json
s=json.load(open('$d/.rabadon/state.json'))
p,f=s.get('lastTestPass',0),s.get('lastTestFail',0)
print('pass' if p else ('fail' if f else 'unknown'))"
}

want(){ # <label> <expected> <tool_response-json>
  got="$(verdict "$3")"
  [ "$got" = "$2" ] && ok "$1" || bad "$1 — expected $2, got $got"
}

echo "test verdict — no evidence is not a failing suite"
echo

# V1. The measured case: the suite ran green and its output went to a file.
want "output redirected to a file is UNKNOWN, not red" unknown '"EXIT=0"'

# V2. Nothing at all came back.
want "an empty tool result is UNKNOWN, not red" unknown '""'

# V3. A tool result that is only a shell prompt's leftovers.
want "a result with no test vocabulary is UNKNOWN, not red" unknown '{"stdout":"","stderr":""}'

# --- twins: a suite that really failed must still go red ---

# V4. Counted failures.
want "counted failures still go RED" fail '{"stdout":"2 failed, 5 passed\nboom at line 9"}'

# V5. make's own failure line, no count anywhere.
want "make *** Error still goes RED" fail '{"stdout":"make[1]: *** [test] Error 1"}'

# V6. A crash with no testing vocabulary at all.
want "a segfault still goes RED" fail '{"stdout":"Segmentation fault: 11"}'

# V7. A python traceback.
want "a traceback still goes RED" fail '{"stdout":"Traceback (most recent call last):\n  File x\nValueError"}'

# --- twin: a real green is still green ---
want "a counted green is still GREEN" pass '{"stdout":"ℹ tests 52\nℹ pass 52\nℹ fail 0"}'

# V8. A ZERO count is not evidence of failure. rabadon caught this one in its
# own output while this fix was being written: the summary line a passing suite
# prints, "test verdict: 8 ok, 0 fail", carries the word fail, and reading the
# word instead of the number turned a green summary back into a red verdict.
want "'0 fail' in a summary line is not failure evidence" unknown '{"stdout":"test verdict: 8 ok, 0 fail"}'
want "'failures: 0' is not failure evidence" unknown '{"stdout":"suite done\nfailures: 0"}'
want "'0 errors' is not failure evidence" unknown '{"stdout":"compiled, 0 errors"}'

# V9. TWIN — a count above zero is still evidence.
want "'1 fail' in the same shape still goes RED" fail '{"stdout":"test verdict: 7 ok, 1 fail"}'

echo
echo "test verdict: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
