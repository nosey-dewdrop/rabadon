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
# A FAILURE PRINTS THE EVIDENCE. This suite went red on ubuntu CI and green on
# the developer's mac with the same source; a bare FAIL line could not say why.
# So every failure dumps the sandbox's ledger and session file — the two things
# a reader needs to tell "the detector did not fire" from "it fired and the
# queue dropped it".
fail() {
  printf '  FAIL - %s\n' "$1"; FAIL=1
  if [ -n "${H:-}" ]; then
    printf '    ledger:\n'; cat "$H"/.rabadon/spool/*.jsonl 2>/dev/null | python3 -c 'import json,sys
for l in sys.stdin:
    if not l.strip(): continue
    d=json.loads(l); print("     ", d.get("ev"), d.get("signal",""), str(d.get("step",""))[:50].replace("\n","⏎"), str(d.get("why",""))[:60])'
    printf '    session:\n'; python3 -c 'import json,glob,sys
for f in glob.glob(sys.argv[1]+"/.rabadon/sessions/*.json"):
    d=json.load(open(f)); print("     ", {k:str(d.get(k))[:80] for k in ("injPending","injPendingSignal","injSeen","injAnsSignal","lastErrText")})
    for m in d.get("moves",[]): print("      move", m.get("seq"), m.get("tool"), m.get("path"), "suite", m.get("suite"), "rc", m.get("claimed_rc"), str(m.get("raw",""))[:30].replace("\n","⏎"))' "$P"
  fi
}
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

printf 'inject-payload: 6b. the contrast names the command, it does not reproduce it\n'
sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
run "cd $P && python3 -m pytest -q 2>&1 | tail -40" $'2 passed in 0.01s\n'
run $'cat > tests/test_b.py <<\'EOF\'\ndef test_x():\n    assert 2 == 1\nEOF' ""
run "cd $P && python3 -m pytest -q 2>&1 | tail -40" $'F.\nE       AssertionError: assert 2 == 1\n1 failed, 1 passed in 0.02s\n'
INJ="$(field injPending)"
case "$INJ" in *'after `python3 -m pytest -q 2>&1` the suite was green; after `python3 -m pytest -q 2>&1` it was red.'*) pass "cd-prefix and tail stage dropped: the sentence names the test command";; *) fail "contrast wording: $INJ";; esac
case "$INJ" in *"$P"*) fail "the project path leaked into the sentence";; *) pass "no absolute path in the sentence";; esac

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

printf 'inject-payload: 7b. eleven real failure lines, and three that only mention one\n'
# THE CUT WAS MEASURED, NOT ASSUMED. Making a failure claim itself only from a
# line whose mark stands at column zero kept 4 of these 11 and dropped 7 — gcc,
# clang, tsc, go, eslint, make and npm all put the PLACE first. That is not a
# tightening, it is going blind on most compiled languages, so error_leads()
# also reads the line from after a leading `path:line:col:`, `path(line,col):`,
# `tool:` or `tool ERR!`. The three NOISE cases are the reason the strict rule
# existed at all and they must stay silent: a cat'ed source file, a dumped
# ledger line, and a grep hit that merely contains a colon and a number.
check_line() { # check_line <label> <output> <FIRES|silent>
  sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
  run "pytest -q" $'2 passed in 0.01s\n'
  run "sed -i s/a/b/ src/x.c" ""
  run "build" "$2"
  local got="silent"; [ -n "$(signals | grep '^regression_contrast$')" ] && got="FIRES"
  [ "$got" = "$3" ] && pass "$1: $3" || fail "$1: expected $3, got $got"
}
check_line "gcc"      'src/x.c:12:5: error: expected   before } token'                    FIRES
check_line "clang"    "main.cpp:44:9: error: no member named 'foo' in 'Bar'"              FIRES
check_line "tsc"      "src/app.ts(31,7): error TS2345: Argument of type 'string'"         FIRES
check_line "go"       './main.go:18:2: undefined: doThing'                                FIRES
check_line "rustc"    'error[E0308]: mismatched types'                                    FIRES
check_line "pytest"   'FAILED tests/test_a.py::test_x - AssertionError: assert 2 == 1'    FIRES
check_line "python"   "NameError: name 'x' is not defined"                                FIRES
check_line "eslint"   "  12:5  error  'x' is assigned but never used  no-unused-vars"     FIRES
check_line "make"     'make: *** [Makefile:12: all] Error 1'                              FIRES
check_line "cargo"    'error: could not compile `app` due to 2 previous errors'           FIRES
check_line "npm"      'npm ERR! code ELIFECYCLE'                                          FIRES
check_line "a cat'ed source file"  $'try:\n    load()\nexcept ImportError:\n    raise ValueError("nope")'  silent
check_line "a dumped ledger line"  '{"ev":"INJECT","text":"attempt 4 on the same failure ... not found"}' silent
check_line "a grep hit"            'docs/faq.md:56:the gate decides in 2.8 ms, no error here'             silent

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

printf 'inject-payload: 9. the budget is per failure, not per session\n'
# MEASURED, THEN CHANGED. Session f888faaf on 2026-09-02: 43 contrast signals,
# 2 injections delivered by 15:42, then 41 INJECT_CAPPED and 140 further
# CHECK_FAILs with the trigger mute for 3.4 hours. Two paragraphs per signal
# per session is right about repetition and wrong about the unit — a real
# session runs sixteen hours across unrelated problems, and the second bug got
# nothing because the first had spent the budget. The key now carries err_sig.
#
# Both halves are asserted here, and the second is the one that must not
# regress: a NEW failure gets its own two, the SAME failure still gets exactly
# two and no more.
inject_count() { cat "$H"/.rabadon/spool/*.jsonl 2>/dev/null | python3 -c 'import json,sys
print(sum(1 for l in sys.stdin if l.strip() and json.loads(l).get("ev")=="INJECT"))'; }
capped_count() { cat "$H"/.rabadon/spool/*.jsonl 2>/dev/null | python3 -c 'import json,sys
print(sum(1 for l in sys.stdin if l.strip() and json.loads(l).get("ev")=="INJECT_CAPPED"))'; }
# one failure, driven five times: green -> edit -> red, over and over
fail_cycle() { # fail_cycle <error line>
  run "pytest -q" $'2 passed in 0.01s\n'
  run "sed -i s/a/b/ src/x.py" ""
  run "pytest -q" "$1"
  run "git status" ""      # a carrier for the delivery
}
sandbox "pytest -q"; export HOME="$H" RABADON_DIR="$H/.rabadon"
for i in 1 2 3 4 5; do fail_cycle $'F.\nE       AssertionError: assert 2 == 1\n1 failed, 1 passed in 0.02s\n'; done
# PER SIGNAL, per failure — the cap was always per signal NAME and only the
# session half is being replaced. Five cycles of one failure wake two different
# detectors (the contrast on each red, and `repeat` once the same command comes
# back with the same error), so the ledger's own count is the assertion: no
# signal exceeds two for one failure.
per_signal() { cat "$H"/.rabadon/spool/*.jsonl 2>/dev/null | python3 -c 'import json,sys,collections
c=collections.Counter()
for l in sys.stdin:
    if not l.strip(): continue
    d=json.loads(l)
    if d.get("ev")=="INJECT": c[d.get("signal")]+=1
print(max(c.values()) if c else 0)'; }
N_SAME="$(inject_count)"
[ "$(per_signal)" = "2" ] && pass "one failure repeated five times: no signal exceeds two paragraphs" \
                          || fail "a signal was injected $(per_signal) times for one failure (want 2)"
[ "$(capped_count)" -gt 0 ] && pass "the extra attempts are capped and say so on the ledger" \
                            || fail "no INJECT_CAPPED after the budget was spent"
# now a DIFFERENT failure in the same session: it must get its own budget
for i in 1 2; do fail_cycle $'F.\nE       TypeError: unsupported operand type\n1 failed, 1 passed in 0.02s\n'; done
N_TOTAL="$(inject_count)"
[ "$N_TOTAL" -gt "$N_SAME" ] && pass "a different failure in the same session gets its own paragraphs ($N_SAME -> $N_TOTAL)" \
                             || fail "a new failure got nothing: still $N_TOTAL injections — the budget is still per session"
# The ledger's own record of the budget: injSeen holds one "<signal>#<err_sig>=<n>"
# per (signal, failure) pair. THAT is the invariant — no pair above two — and it
# is what distinguishes "a new failure got its own budget" from "the cap leaked".
worst_pair() { python3 -c 'import json,glob,sys
f=glob.glob(sys.argv[1]+"/.rabadon/sessions/*.json")
d=json.load(open(f[0])) if f else {}
print(max((int(e.rsplit("=",1)[1]) for e in d.get("injSeen",[])), default=0))' "$P"; }
pairs() { python3 -c 'import json,glob,sys
f=glob.glob(sys.argv[1]+"/.rabadon/sessions/*.json")
d=json.load(open(f[0])) if f else {}
print(len(d.get("injSeen",[])))' "$P"; }
[ "$(worst_pair)" = "2" ] && pass "no (signal, failure) pair exceeds two paragraphs — the cap holds" \
                          || fail "a (signal, failure) pair reached $(worst_pair)"
[ "$(pairs)" -ge 3 ] && pass "the second failure opened its own budget lines ($(pairs) pairs on the ledger)" \
                     || fail "only $(pairs) budget line(s) — the key is not carrying the failure"

printf 'inject-payload: %s passed, %s\n' "$PASSN" "$([ $FAIL = 0 ] && echo '0 failed' || echo 'SOME FAILED')"
exit $FAIL
