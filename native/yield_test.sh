#!/usr/bin/env bash
# yield_test.sh — WHEN A REFUSAL STANDS DOWN FOR A DIAGNOSIS, AND WHEN IT DOES NOT.
#
# WHY THIS FILE EXISTS.
# `block()` in gate.cpp carries a rule the whole product turns on: a NON-sealed
# rule with a diagnosis waiting stands down, emits RULE_YIELDED, and lets the
# call through — because rabadon's first law is that a run is repaired, not
# stopped. Sealed rules (promise-tamper, promise-anti-path, guard-weaken) keep
# refusing, because those are security decisions and an injection must never be
# able to move one.
#
# That is the most dangerous single branch in the binary — it turns refusals
# OFF — and on 2026-09-02 `grep -l RULE_YIELDED native/*_test.sh` answered
# nothing. Two live RULE_YIELDED events existed in the operator's own ledger
# and no fixture had ever driven one. This file is the standing check.
#
# WHAT IT REFUSES TO ACCEPT.
#   - a sealed rule yielding, ever. Section 3 drives guard-weaken with a
#     diagnosis pending and requires the refusal.
#   - yield without delivery: standing down and NOT handing the paragraph over
#     would be the worst of both — the call runs and the agent learns nothing.
#   - yield with no diagnosis pending: a refusal that disappears because the
#     queue happens to be empty is a refusal that disappears at random.
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
FAIL=0; PASSN=0
pass() { printf '  ok   - %s\n' "$1"; PASSN=$((PASSN + 1)); }
fail() { printf '  FAIL - %s\n' "$1"; FAIL=1
  [ -n "${H:-}" ] && { printf '    ledger:\n'; cat "$H"/.rabadon/spool/*.jsonl 2>/dev/null | python3 -c 'import json,sys
for l in sys.stdin:
    if not l.strip(): continue
    d=json.loads(l); print("     ", d.get("ev"), d.get("rule",""), d.get("signal",""), str(d.get("step",""))[:40].replace("\n","/"))'; }
}
[ -x "$GATE" ] || { printf 'yield: no gate binary at %s — run make first\n' "$GATE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'yield: python3 required\n' >&2; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rbyield.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

H=""; P=""; SID=""
sandbox() {
  H="$(mktemp -d "$WORK/h.XXXXXX")"; P="$(mktemp -d "$WORK/p.XXXXXX")"; SID="s$RANDOM$$"
  mkdir -p "$H/.rabadon/spool" "$P/.rabadon" "$P/.git" "$P/tests"
  printf 'ref: refs/heads/main\n' > "$P/.git/HEAD"
  : > "$H/.rabadon/enabled"                       # enforce, not watch
  # A REAL RULE IN THE GUARD, because section 3 needs a real weakening to
  # provoke. Changing testCommand is not one: guard-weaken compares the rule
  # ids and the disabled[] set, so an edit that removes neither is ordinary
  # work and passes — as it should. First draft of this file edited
  # testCommand, got exit 0, and would have been read as "a sealed rule stood
  # down" when nothing had been provoked at all.
  printf '%s\n' '{"project":"p","testCommand":"pytest -q","rules":[{"id":"no-force-push","bash":"git push --force"}]}' > "$P/.rabadon/guard.json"
  export HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0
}
# bash_pre <cmd> ; bash_post <cmd> <stdout>  — the object shape Claude Code sends
call() { python3 - "$GATE" "$P" "$SID" "$@" <<'PY'
import json, subprocess, sys
G, P, sid, hook, tool = sys.argv[1:6]
inp = json.loads(sys.argv[6]); resp = sys.argv[7] if len(sys.argv) > 7 else None
e = {"hook_event_name": hook, "session_id": sid, "cwd": P, "tool_name": tool, "tool_input": inp}
if resp is not None: e["tool_response"] = {"stdout": resp, "stderr": "", "interrupted": False}
r = subprocess.run([G], input=json.dumps(e), capture_output=True, text=True)
print(r.returncode)
PY
}
bash_pre()  { call PreToolUse  Bash "$(python3 -c 'import json,sys;print(json.dumps({"command":sys.argv[1]}))' "$1")"; }
bash_post() { call PostToolUse Bash "$(python3 -c 'import json,sys;print(json.dumps({"command":sys.argv[1]}))' "$1")" "$2" >/dev/null; }
run() { bash_pre "$1" >/dev/null; bash_post "$1" "$2"; }
# ledger <event> [field] — the whole line, or ONE field of it. A field is asked
# for by name rather than grepped out of the JSON: this file's first draft
# matched `'"rule":"baseline-law-unmade"'` against a line that python had
# re-serialised as `"rule": "baseline-law-unmade"`, and reported a missing
# event that was sitting right there in the failure dump.
ledger() { cat "$H"/.rabadon/spool/*.jsonl 2>/dev/null | python3 -c 'import json,sys
ev=sys.argv[1]; field=sys.argv[2] if len(sys.argv)>2 else None
for l in sys.stdin:
    if not l.strip(): continue
    d=json.loads(l)
    if d.get("ev")==ev: print(d.get(field,"") if field else json.dumps(d))' "$1" ${2:+"$2"}; }
pending() { python3 -c 'import json,glob,sys
f=glob.glob(sys.argv[1]+"/.rabadon/sessions/*.json")
print(json.load(open(f[0])).get("injPending","") if f else "")' "$P"; }

# A session that has a diagnosis WAITING: green suite, a shell write, a red
# suite. The contrast trigger queues; nothing has been delivered yet.
arm_diagnosis() {
  run "pytest -q" $'2 passed in 0.01s\n'
  run $'cat > tests/test_b.py <<\'EOF\'\ndef test_x():\n    assert 2 == 1\nEOF' ""
  run "pytest -q" $'F.\nE       AssertionError: assert 2 == 1\n1 failed, 1 passed in 0.02s\n'
}

printf 'yield: 1. a behavioural refusal stands down for a waiting diagnosis\n'
sandbox
# A ONE-CALL RULE, NOT A COUNTER. loop-stop needs three consecutive identical
# commands, and arming a diagnosis in between resets the count while delivering
# the paragraph empties the queue — the two cannot both hold on the same call.
# Both live RULE_YIELDED events in the operator's ledger came from single-call
# rules instead (`baseline-law-unmade`, `no-heredoc-source-writes`), so that is
# the shape driven here: `rm .rabadon/guard.json` is refused on sight, with no
# history required, so the diagnosis is still pending when it is provoked.
arm_diagnosis
[ -n "$(pending)" ] && pass "a diagnosis is queued and undelivered when the refusal is provoked" \
                    || fail "nothing queued — the rest of this section proves nothing"
RC3=$(bash_pre "rm -f .rabadon/guard.json")
[ "$RC3" = "0" ] && pass "the command is ALLOWED (exit 0), not refused" \
                 || fail "the rule refused with a diagnosis pending (exit $RC3)"
[ "$(ledger RULE_YIELDED rule | tail -1)" = "baseline-law-unmade" ] \
  && pass "RULE_YIELDED names the rule that stood down" \
  || fail "no RULE_YIELDED for baseline-law-unmade: [$(ledger RULE_YIELDED rule | tail -1)]"
[ "$(ledger RULE_YIELDED to | tail -1)" = "regression_contrast" ] \
  && pass "and names the diagnosis it stood down FOR" \
  || fail "RULE_YIELDED does not name the signal: [$(ledger RULE_YIELDED to | tail -1)]"
[ -z "$(ledger STOP)" ] && pass "no STOP was written — the call really ran" \
                        || fail "a STOP reached the ledger on a yielded rule"
# THE YIELD IS ONLY DEFENSIBLE IF THE PARAGRAPH IS HANDED OVER.
[ -n "$(ledger INJECT)" ] && pass "the diagnosis was delivered on that same call" \
                          || fail "the rule stood down and NOTHING was delivered — the worst of both"

printf 'yield: 2. with no diagnosis waiting, the same rule refuses\n'
sandbox
RC=$(bash_pre "rm -f .rabadon/guard.json")
[ "$RC" != "0" ] && pass "the same command is refused (exit $RC) when the queue is empty" \
                 || fail "baseline-law-unmade did not refuse without a pending diagnosis — the rule is dead"
[ -z "$(ledger RULE_YIELDED)" ] && pass "nothing yielded, because there was nothing to yield to" \
                                || fail "RULE_YIELDED with an empty queue"

printf 'yield: 3. a SEALED rule never stands down, diagnosis or not\n'
sandbox
arm_diagnosis
[ -n "$(pending)" ] && pass "a diagnosis is queued before the sealed rule is provoked" \
                    || fail "nothing queued — section 3 proves nothing"
# guard-weaken: an Edit to .rabadon/guard.json cannot be shown to be a
# strengthening, so it is refused. Sealed.
RULE_TEXT=',"rules":[{"id":"no-force-push","bash":"git push --force"}]'
RCG=$(call PreToolUse Edit "$(python3 -c 'import json,sys;print(json.dumps({"file_path":sys.argv[1]+"/.rabadon/guard.json","old_string":sys.argv[2],"new_string":""}))' "$P" "$RULE_TEXT")")
[ "$RCG" != "0" ] && pass "guard-weaken still refuses (exit $RCG) with a diagnosis pending" \
                  || fail "a SEALED rule stood down for an injection — an injection moved a security decision"
case "$(ledger RULE_YIELDED rule)" in *guard-weaken*) fail "guard-weaken emitted RULE_YIELDED" ;;
  *) pass "no RULE_YIELDED names a sealed rule" ;; esac
[ -n "$(ledger CHECK_FAIL)" ] && pass "the refusal reached the ledger as a CHECK_FAIL" \
                             || fail "the sealed refusal left no CHECK_FAIL"

printf 'yield: 4. nearest neighbour — an edit that removes no rule is ordinary work\n'
sandbox
arm_diagnosis
RCOK=$(call PreToolUse Edit "$(python3 -c 'import json,sys;print(json.dumps({"file_path":sys.argv[1]+"/.rabadon/guard.json","old_string":"pytest -q","new_string":"pytest -q -x"}))' "$P")")
[ "$RCOK" = "0" ] && pass "changing testCommand is allowed (exit 0) — guard-weaken guards RULES, not the file" \
                  || fail "an ordinary guard edit was refused (exit $RCOK) — the law is too wide"

printf 'yield: %s passed, %s\n' "$PASSN" "$([ $FAIL = 0 ] && echo '0 failed' || echo 'SOME FAILED')"
exit $FAIL
