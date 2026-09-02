#!/usr/bin/env bash
# inject_payload_test.sh — DOES THE INJECTION TELL THE TRUTH, AND DOES THE
# CONTRAST TRIGGER FIRE ON A RED THAT USES NO ERROR WORDS?
#
# WHY THIS FILE EXISTS, WITH WHAT PUT IT HERE (all measured 2026-09-02, live).
#   1. The injection quoted `{"stdout":"def collect(item, bucket=[]):` as "the
#      previous attempt ended with". Claude Code delivers a Bash result as an
#      object; the move record read that object as ONE line and quoted its first
#      120 characters, which were a file the agent had cat'ed.
#   2. "Changed since that green" was empty. The agent wrote the failing test
#      with `cat > x.py <<EOF`; the ring only called the Edit tool an edit.
#   3. `Tests: 1 failed, 2 passed` after a green produced CHECK_FAIL and no
#      SIGNAL. The detectors run before the verdict is stamped, so the trigger
#      depended on error vocabulary, and jest's summary has none.
# Every case below is one of those three, driven through the binary the same
# way the harness drives it, plus the nearest neighbour that must stay quiet.
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
FAIL=0; PASSN=0
pass() { printf '  ok   - %s\n' "$1"; PASSN=$((PASSN + 1)); }
fail() { printf '  FAIL - %s\n' "$1"; FAIL=1; }
[ -x "$GATE" ] || { printf 'inject-payload: no gate binary at %s — run make first\n' "$GATE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'inject-payload: python3 required\n' >&2; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rbinjp.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

H=""; P=""; SID=""
sandbox() {
  H="$(mktemp -d "$WORK/h.XXXXXX")"; P="$(mktemp -d "$WORK/p.XXXXXX")"; SID="s$RANDOM"
  mkdir -p "$H/.rabadon/spool" "$P/.rabadon" "$P/.git" "$P/tests"
  printf 'ref: refs/heads/main\n' > "$P/.git/HEAD"
  : > "$H/.rabadon/enabled"
  printf '{"project":"p","testCommand":"%s"}\n' "$1" > "$P/.rabadon/guard.json"
}
# run <command> <stdout> [stderr] — pre + post, the response in the OBJECT shape
# Claude Code actually sends (the string shape is covered by signals_test.sh).
run() {
  python3 - "$GATE" "$P" "$SID" "$1" "$2" "${3:-}" <<'PY'
import json, subprocess, sys, os
G, P, sid, cmd, out, err = sys.argv[1:7]
def ev(hook, resp=None):
    e = {"hook_event_name": hook, "session_id": sid, "cwd": P, "tool_name": "Bash", "tool_input": {"command": cmd}}
    if resp is not None: e["tool_response"] = resp
    subprocess.run([G], input=json.dumps(e), capture_output=True, text=True)
ev("PreToolUse"); ev("PostToolUse", {"stdout": out, "stderr": err, "interrupted": False})
PY
}
field() { python3 -c 'import json,sys,glob; d=json.load(open(glob.glob(sys.argv[1]+"/.rabadon/sessions/*.json")[0])); print(d.get(sys.argv[2],""))' "$P" "$1"; }
signals() { cat "$H"/.rabadon/spool/*.jsonl 2>/dev/null | python3 -c 'import json,sys; print("\n".join(json.loads(l)["signal"] for l in sys.stdin if l.strip() and json.loads(l).get("ev")=="SIGNAL"))'; }
export RABADON_NOTIFY=0

printf 'inject-payload: 1. the quoted error is the error, not the envelope\n'
sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
DUMP=$'def collect(item, bucket=[]):\n    bucket.append(item)\n    return bucket\n'
run "pytest -q; cat store.py" $'F.\n=== FAILURES ===\nE       AssertionError: assert 2 == 1\n1 failed, 1 passed in 0.02s\n'"$DUMP"
E="$(field lastErrText)"
case "$E" in *AssertionError*) pass "object-shaped response: the assertion line is quoted ($E)";; *) fail "expected the assertion line, got: $E";; esac
case "$E" in *stdout*|*collect*) fail "the envelope or the file dump leaked into the quote: $E";; *) pass "neither the JSON key nor the cat'ed file is in the quote";; esac

printf 'inject-payload: 2. a traceback is quoted by its last line\n'
sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "python3 store.py" "" $'Traceback (most recent call last):\n  File "store.py", line 3, in <module>\nNameError: name x is not defined\n'
E="$(field lastErrText)"
case "$E" in NameError*) pass "stderr-only failure: NameError line quoted, not the Traceback header";; *) fail "expected NameError..., got: $E";; esac

printf 'inject-payload: 3. a file written through the shell is a changed file\n'
sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "pytest -q" $'2 passed in 0.01s\n'
run $'cat > tests/test_b.py <<\'EOF\'\ndef test_x():\n    assert 2 == 1\nEOF' ""
run "echo hi > /dev/null" "hi"
run "pytest -q" $'F.\nE       AssertionError: assert 2 == 1\n1 failed, 1 passed in 0.02s\n'
INJ="$(field injPending)"
case "$INJ" in *"Changed since that green: tests/test_b.py."*) pass "heredoc target named as the change since green";; *) fail "changed list wrong: $INJ";; esac
case "$INJ" in *"/dev/null"*) fail "/dev/null counted as a written file";; *) pass "a redirect to /dev/null is not a file";; esac
case "$INJ" in *"it was red."*) pass "the red half of the contrast is stated as a suite verdict";; *) fail "contrast sentence: $INJ";; esac

printf 'inject-payload: 3b. a redirect target the shell had not expanded is not a file\n'
sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "pytest -q" $'2 passed in 0.01s\n'
run 'for i in 01 02; do echo x > app/stage$i.py; done' ""
run "pytest -q" $'F.\nE       AssertionError: assert 2 == 1\n1 failed, 1 passed in 0.02s\n'
INJ="$(field injPending)"
case "$INJ" in *'$i'*) fail "an unexpanded shell variable was recorded as a file: $INJ";; *) pass "a target still holding a \$variable is not named";; esac
case "$INJ" in *"green earlier"*) pass "the contrast still fires without a file to name";; *) fail "no injection: $INJ";; esac

printf 'inject-payload: 4. a red with no error words still fires the contrast\n'
sandbox "npm test"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "npm test" $'Tests: 3 passed, 3 total\n'
run $'cat > tests/b.test.js <<\'EOF\'\ntest("x",()=>expect(2).toBe(1))\nEOF' ""
run "npm test" $'  ● x\n\n    expect(received).toBe(expected)\n\nTests: 1 failed, 2 passed, 3 total\n'
N="$(signals | grep -c '^regression_contrast$')"
[ "$N" = "1" ] && pass "exactly one regression_contrast SIGNAL after the verdict was stamped" || fail "regression_contrast count = $N (want 1)"
[ "$(field injPendingSignal)" = "regression_contrast" ] && pass "the injection is queued for the next PreToolUse" || fail "no injection queued: $(field injPendingSignal)"

printf 'inject-payload: 5. nearest neighbour — a red with error words is not said twice\n'
sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "pytest -q" $'2 passed in 0.01s\n'
run "sed -i 's/1/2/' tests/test_a.py" ""
run "pytest -q" $'FAILED tests/test_a.py::test_x - AssertionError\n1 failed, 1 passed in 0.02s\n'
N="$(signals | grep -c '^regression_contrast$')"
[ "$N" = "1" ] && pass "one SIGNAL when both the vocabulary and the verdict say red" || fail "duplicate SIGNAL: count = $N"
case "$(field injPending)" in *"tests/test_a.py"*) pass "sed -i target named as the change";; *) fail "sed -i target missing: $(field injPending)";; esac

printf 'inject-payload: 6. nearest neighbour — a green after a green says nothing\n'
sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "pytest -q" $'2 passed in 0.01s\n'
run "echo x >> notes.md" ""
run "pytest -q" $'2 passed in 0.01s\n'
[ -z "$(signals)" ] && pass "no SIGNAL on green -> write -> green" || fail "fired on a green: $(signals | tr '\n' ' ')"

ledger() { cat "$H"/.rabadon/spool/*.jsonl 2>/dev/null | python3 -c 'import json,sys; ev=sys.argv[1]; f=sys.argv[2]
for l in sys.stdin:
    if not l.strip(): continue
    d=json.loads(l)
    if d.get("ev")==ev: print(d.get(f,""))' "$1" "$2"; }
pre() { python3 - "$GATE" "$P" "$SID" "$1" <<'PY2'
import json, subprocess, sys
G, P, sid, cmd = sys.argv[1:5]
e = {"hook_event_name": "PreToolUse", "session_id": sid, "cwd": P, "tool_name": "Bash", "tool_input": {"command": cmd}}
subprocess.run([G], input=json.dumps(e), capture_output=True, text=True)
PY2
}

printf 'inject-payload: 7. a command that PRINTS error words is not a failed command\n'
sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "pytest -q" $'2 passed in 0.01s\n'
run "echo x >> notes.md" ""
run "cat handlers.py" $'try:\n    load()\nexcept ImportError:\n    raise ValueError("config not found")\n'
run "tail -3 ledger.jsonl" $'{"ev":"INJECT","text":"attempt 4 on the same failure ... not found"}\n'
[ -z "$(signals)" ] && pass "cat of a handler and a ledger dump after a green: no SIGNAL" || fail "fired on printed vocabulary: $(signals | tr '\n' ' ')"
run "python3 store.py" "" $'Traceback (most recent call last):\n  File "store.py", line 3, in <module>\nNameError: name x is not defined\n'
N="$(signals | grep -c '^regression_contrast$')"
[ "$N" = "1" ] && pass "a runtime error that LEADS its line still claims the failure" || fail "Traceback no longer counts as a failure: count=$N"

printf 'inject-payload: 8. (b) that can be false — did the next move go where the paragraph pointed?\n'
sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "pytest -q" $'2 passed in 0.01s\n'
run $'cat > tests/test_b.py <<\'EOF\'\ndef test_x():\n    assert 2 == 1\nEOF' ""
run "pytest -q" $'F.\nE       AssertionError: assert 2 == 1\n1 failed, 1 passed in 0.02s\n'
pre "git status"                      # carrier: the injection rides on this call
pre "sed -n 1,20p tests/test_b.py"    # the answer: goes to the named file
[ "$(ledger INJECT_ANSWER named)" = "True" ] && pass "named=true when the next move opens the file the injection named" || fail "named: '$(ledger INJECT_ANSWER named)' names: '$(ledger INJECT_ANSWER names)'"
[ "$(ledger INJECT_ANSWER same)" = "False" ] && pass "same=false on the same pair (the old metric would have said nothing more)" || fail "same: $(ledger INJECT_ANSWER same)"

sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "pytest -q" $'2 passed in 0.01s\n'
run $'cat > tests/test_b.py <<\'EOF\'\ndef test_x():\n    assert 2 == 1\nEOF' ""
run "pytest -q" $'F.\nE       AssertionError: assert 2 == 1\n1 failed, 1 passed in 0.02s\n'
pre "git status"
pre "cat README.md"
[ "$(ledger INJECT_ANSWER named)" = "False" ] && pass "named=false when the next move goes elsewhere" || fail "named: '$(ledger INJECT_ANSWER named)'"

sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "pytest -q" $'2 passed in 0.01s\n'
run "pytest -q" $'F.\nE       AssertionError: assert 2 == 1\n1 failed, 1 passed in 0.02s\n'
pre "git status"
pre "cat README.md"
[ "$(ledger INJECT_ANSWER named)" = "" ] && [ "$(ledger INJECT_ANSWER same)" = "False" ] && pass "no named field when the paragraph named no file — an unanswerable question is not a no" || fail "named: '$(ledger INJECT_ANSWER named)' same: '$(ledger INJECT_ANSWER same)'"

printf 'inject-payload: %s passed, %s\n' "$PASSN" "$([ $FAIL = 0 ] && echo '0 failed' || echo 'SOME FAILED')"
exit $FAIL
