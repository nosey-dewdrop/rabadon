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

# verdict <tool_response-json> [testPassPattern] -> "pass" | "fail" | "unknown"
#
# The second argument matters more than it looks. A guard with no
# testPassPattern falls back to reading a `fail(ed|ures): N` count, so a summary
# line carrying `fail 0` reads as green on its own. A guard that HAS one — which
# this repo's does — is stricter, and the incident on 3 August happened in
# exactly that gap: the count said zero failures and the strict pattern still
# did not match, because the session had narrowed its own output.
verdict(){
  d="$(mktemp -d)"; mkdir -p "$d/.rabadon"
  if [ -n "${2:-}" ]; then
    PAT="$2" python3 - "$d/.rabadon/guard.json" <<'PYG'
import json, os, sys
json.dump({"project": "p", "testCommand": "make test",
           "testPassPattern": os.environ["PAT"]}, open(sys.argv[1], "w"))
PYG
  else
    echo '{"project":"p","testCommand":"make test"}' > "$d/.rabadon/guard.json"
  fi
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
  # The verdict is the SESSION's, and since 3 August it is written where a
  # session's own claims belong: <project>/.rabadon/sessions/<key>.json, one
  # writer per file. It left state.json because a red stamped there at 02:18 by
  # one session was still being read at 04:00 by a session with its own suite
  # green. Reading the shared file here would find nothing and report `unknown`
  # for every case, green ones included, which is a harness that measures the
  # storage layout instead of the classifier.
  python3 -c "
import json, glob, os
s = {}
for f in sorted(glob.glob('$d/.rabadon/sessions/*.json')):
    s.update(json.load(open(f)))
p,f=s.get('lastTestPass',0),s.get('lastTestFail',0)
print('pass' if p else ('fail' if f else 'unknown'))"
}

want(){ # <label> <expected> <tool_response-json> [testPassPattern]
  got="$(verdict "$3" "${4:-}")"
  [ "$got" = "$2" ] && ok "$1" || bad "$1 — expected $2, got $got"
}
# the shape this repo's own guard uses: a green is only a green when the runner
# prints its own summary line, which is what a narrowed tool result loses.
STRICT='(^|\n)[ \t]*(#|i)[ \t]*fail[ \t]+0([ \t]|$)'

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
# GREEN rather than unknown, and the change is a fix rather than a drift: with
# no testPassPattern the documented fallback is "a fail(ed|ures): N count exists,
# so green iff N is zero". It used to answer `unknown` only because the classifier
# was reading escaped JSON source, where the preceding \n made the word `failures`
# read as `nfailures` and the count was never found at all.
want "'failures: 0' is a counted green" pass '{"stdout":"suite done\nfailures: 0"}'
want "'0 errors' is not failure evidence" unknown '{"stdout":"compiled, 0 errors"}'

# V9. TWIN — a count above zero is still evidence.
want "'1 fail' in the same shape still goes RED" fail '{"stdout":"test verdict: 7 ok, 1 fail"}'

# V10. A run that STATES its exit status. Recorded as `rabadon wrong test-run`
# on 3 August: `make test` exited 0 and the summary said `pass 17  fail 0`, but
# the session had narrowed the output with grep and tail, so the runner's own
# `ℹ fail 0` line that testPassPattern needs was gone and the only
# failure-shaped text left was a line a fixture prints ON PURPOSE while proving
# it can detect a red downstream suite. The session was told its own green suite
# was red. A stated exit code is the one thing the post hook never sees for
# itself, and it outranks a failure WORD.
want "a stated EXIT=0 beside a failure word is UNKNOWN, not red" unknown \
  '{"stdout":"MAKE_TEST_EXIT=0\n    FAIL testsuite [node --test]: the suite is RED (exit 1)\n  pass 17   fail 0"}' \
  "$STRICT"

# V11. TWIN — the exit code has to be able to say the other thing too.
want "a stated EXIT=1 beside the same word still goes RED" fail \
  '{"stdout":"MAKE_TEST_EXIT=1\n    FAIL testsuite [node --test]: the suite is RED (exit 1)"}' \
  "$STRICT"

# V12. TWIN — a crash string is a thing that HAPPENED, and outranks the claim.
# `make test | tail` exits with tail's status, so EXIT=0 there is not the
# suite's answer, and this is the case that keeps the widening honest.
want "a crash string outranks a stated EXIT=0" fail \
  '{"stdout":"EXIT=0\nmake[1]: *** [test] Error 1"}'

# V13. TWIN — so does a counted failure.
want "a counted failure outranks a stated EXIT=0" fail \
  '{"stdout":"EXIT=0\n3 failed, 40 passed"}'

echo
echo "test verdict: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
