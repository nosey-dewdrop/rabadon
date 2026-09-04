#!/usr/bin/env bash
# failed_call_test.sh — THE BLIND SPOT SUITE.
#
# WHAT WAS MEASURED, AND WHY THIS FILE EXISTS.
# rabadon's whole reason to exist is "the same error came back" — and the only
# place `err_sig` is ever assigned is the PostToolUse branch. On 2026-08-29 the
# F3d arbiter measured that a Bash call which exits non-zero produced a
# STEP_START on the ledger and no STEP_OK: the failing call left no closed
# record at all. Four phases had read n=0 on the live injection ladder because
# of it, and the phase agent could only manufacture a signal by appending
# `; true` to every command — hand-compensating for the hole.
#
# The cause was measured in F3e, not guessed. Claude Code DOES deliver an event
# for a failing tool call; it delivers it under a DIFFERENT NAME:
#
#   hook_event_name: "PostToolUseFailure"
#   tool_input: {...}          tool_use_id: "toolu_..."
#   error: "Exit code 1\nls: /nope: No such file or directory"
#   (no tool_response field at all)
#
# Captured live, verbatim, in docs/archive/reports/kosu/RAPOR/f3e-1-posttooluse-failure-payload.json.
# So the hole was rabadon's on both counts: hookev.h's dialect table did not
# list the name (the event fell through to UNKNOWN and the gate fell open), and
# hooks/install.mjs never subscribed to it, so on a real machine the event was
# not even delivered to the binary.
#
# The assertions below are written against the SHAPE THAT WAS CAPTURED. They do
# not assert an exit code, a refusal, or any user-visible verdict: a failing
# tool call must be RECORDED, and recording must not change what the gate
# decides.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
export RB_AUDIT="${RABADON_AUDIT:-$HERE/rabadon-audit}"

PASSN=0; FAIL=0
pass() { printf '  ok   - %s\n' "$1"; PASSN=$((PASSN + 1)); }
fail() { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }

# NO SILENT SKIP. A missing binary is a red suite, not a green one: the class
# that let version_test.sh shrink from 13 assertions to 11 and still exit 0.
[ -x "$GATE" ]     || { printf 'failed_call: no gate binary at %s — run make first\n' "$GATE" >&2; exit 1; }
[ -x "$RB_AUDIT" ] || { printf 'failed_call: no audit binary at %s — run make first\n' "$RB_AUDIT" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'failed_call: python3 is required\n' >&2; exit 1; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbfail.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

export HOME="$ROOT/home"
export RABADON_DIR="$ROOT/home/.rabadon"
export RABADON_NOTIFY=0
export RABADON_JUDGE=0
mkdir -p "$RABADON_DIR/spool"
touch "$RABADON_DIR/enabled"   # enforce, not watch

PROJ="$ROOT/proj"
mkdir -p "$PROJ/.git"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"

DAY="$(date -u +%Y-%m-%d)"
jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }
fresh() { rm -rf "$PROJ/.rabadon" "$RABADON_DIR/sessions" "$RABADON_DIR/spool"; mkdir -p "$RABADON_DIR/spool"; }

pre_bash() { # pre_bash <session> <command> <call-id>
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_use_id":"%s","tool_input":{"command":%s}}' \
    "$1" "$PROJ" "$3" "$(jstr "$2")" | "$GATE" >/dev/null 2>&1
  echo $?
}

post_ok() { # post_ok <session> <command> <call-id> <tool_response>
  printf '{"hook_event_name":"PostToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_use_id":"%s","tool_input":{"command":%s},"tool_response":%s}' \
    "$1" "$PROJ" "$3" "$(jstr "$2")" "$(jstr "$4")" | "$GATE" >/dev/null 2>&1
  echo $?
}

# THE CAPTURED SHAPE. `error`, not `tool_response`; no exit code field.
post_fail() { # post_fail <session> <command> <call-id> <error-text>
  printf '{"hook_event_name":"PostToolUseFailure","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_use_id":"%s","tool_input":{"command":%s},"error":%s,"is_interrupt":false,"duration_ms":184}' \
    "$1" "$PROJ" "$3" "$(jstr "$2")" "$(jstr "$4")" | "$GATE" >/dev/null 2>&1
  echo $?
}

# The move record, read through the same export door a human uses.
moves_py() { # moves_py <python-expr over `m`>
  python3 - "$RABADON_DIR" "$PROJ" "$1" <<'PY'
import json, os, sys, glob, subprocess
rabdir, proj, expr = sys.argv[1:4]
moves = []
exp = os.environ.get("RB_AUDIT", "")
for base in (os.path.join(proj, ".rabadon", "sessions"),
             os.path.join(rabdir, "sessions")):
    for fn in glob.glob(os.path.join(base, "*.moves.bin")):
        p = subprocess.run([exp, "--export", fn], capture_output=True, text=True)
        if p.returncode != 0:
            print("ERR:export rc=%d %s" % (p.returncode, p.stderr.strip()[:120])); sys.exit(0)
        for line in p.stdout.splitlines():
            line = line.strip()
            if line:
                moves.append(json.loads(line))
moves.sort(key=lambda x: x.get("seq", 0))
m = moves
try:
    print(eval(expr))
except Exception as e:
    print("ERR:%s" % e)
PY
}

ERRTEXT='Exit code 1
ls: /nonexistent-rabadon-probe: No such file or directory'

echo "failed_call: a tool call that failed is a tool call rabadon has to see"

# ---------------------------------------------------------------------------
# CLAIM 0 — the harness itself works. Without this, every claim below could be
# green because nothing was ever recorded.
fresh
pre_bash s-ok 'ls -la' 'call-ok-1' >/dev/null
post_ok  s-ok 'ls -la' 'call-ok-1' 'total 0' >/dev/null
N="$(moves_py 'len(m)')"
[ "$N" = "1" ] && pass "a successful call leaves exactly one move on the record" \
                || fail "successful call left $N moves, expected 1"
RC="$(moves_py 'm[-1]["claimed_rc"] if m else "NONE"')"
[ "$RC" = "0" ] && pass "a successful call records claimed_rc 0" \
                || fail "successful call recorded claimed_rc=$RC, expected 0"

# ---------------------------------------------------------------------------
# CLAIM 1 — THE BLIND SPOT. A failing call must CLOSE the move PreToolUse
# opened. `claimed_rc` is -1 on an open move and is only ever set by the
# completion branch, so it is the one field that answers "did the completion
# arrive at all" — a move COUNT cannot answer it, because an event the gate
# does not understand writes nothing and leaves the count looking correct.
# That is exactly what this was before F3e: PostToolUseFailure was not in
# hookev.h's dialect table, the gate fell open, and the move stayed open.
fresh
pre_bash   s-f1 'ls /nonexistent-rabadon-probe' 'call-f-1' >/dev/null
OPEN="$(moves_py 'm[-1]["claimed_rc"] if m else "NONE"')"
[ "$OPEN" = "-1" ] && pass "before the completion the move is open (claimed_rc -1)" \
                   || fail "an unfinished move reads claimed_rc=$OPEN, expected -1"
post_fail  s-f1 'ls /nonexistent-rabadon-probe' 'call-f-1' "$ERRTEXT" >/dev/null
N="$(moves_py 'len(m)')"
[ "$N" = "1" ] && pass "a failing call closes its move rather than opening a second one" \
                || fail "failing call left $N moves, expected 1"
DONE="$(moves_py 'm[-1]["claimed_rc"] if m else "NONE"')"
[ "$DONE" != "-1" ] && pass "the completion for a failing call ARRIVED (claimed_rc left -1)" \
                    || fail "the move is still open after the failure event — the completion was dropped"

# ---------------------------------------------------------------------------
# CLAIM 2 — err_sig exists for a failing call. This is the whole product: the
# signature is what "the same error came back" is measured against, and it is
# assigned nowhere but on a completion.
SIG="$(moves_py 'm[-1]["err_sig"] if m else "NONE"')"
case "$SIG" in
  NONE|""|ERR:*) fail "a failing call recorded NO err_sig ('$SIG') — the repeat detector cannot see it" ;;
  *)             pass "a failing call records a non-empty err_sig ($SIG)" ;;
esac

RC="$(moves_py 'm[-1]["claimed_rc"] if m else "NONE"')"
[ "$RC" = "1" ] && pass "a failing call records claimed_rc 1" \
                || fail "failing call recorded claimed_rc=$RC, expected 1"

# ---------------------------------------------------------------------------
# CLAIM 3 — THE SAME ERROR TWICE, with no `; true` anywhere. This is the exact
# thing four phases could not produce live: two failing calls whose err_sig
# matches, which is what every repeat rule reads.
fresh
pre_bash  s-f2 'ls /nonexistent-rabadon-probe' 'call-g-1' >/dev/null
post_fail s-f2 'ls /nonexistent-rabadon-probe' 'call-g-1' "$ERRTEXT" >/dev/null
pre_bash  s-f2 'ls  /nonexistent-rabadon-probe' 'call-g-2' >/dev/null
post_fail s-f2 'ls  /nonexistent-rabadon-probe' 'call-g-2' "$ERRTEXT" >/dev/null
BOTH="$(moves_py '"%s|%s" % (m[0]["err_sig"], m[-1]["err_sig"]) if len(m) >= 2 else "SHORT"')"
A="${BOTH%%|*}"; B="${BOTH##*|}"
if [ "$BOTH" != "SHORT" ] && [ -n "$A" ] && [ "$A" = "$B" ]; then
  pass "the same failure twice carries the same err_sig ($A)"
else
  fail "two identical failures did not share an err_sig: $BOTH"
fi

# ---------------------------------------------------------------------------
# CLAIM 4 — the ledger closes the call. A STEP_START with no closing event is
# the shape the arbiter measured on the live spool.
fresh
pre_bash  s-f3 'ls /nonexistent-rabadon-probe' 'call-h-1' >/dev/null
post_fail s-f3 'ls /nonexistent-rabadon-probe' 'call-h-1' "$ERRTEXT" >/dev/null
SPOOL="$RABADON_DIR/spool/$DAY.jsonl"
if [ -f "$SPOOL" ] && grep -q '"ev":"STEP_START".*"call":"call-h-1"' "$SPOOL"; then
  pass "the failing call opened a STEP_START on the ledger"
else
  fail "no STEP_START for the failing call — the harness never reached the ledger"
fi
if [ -f "$SPOOL" ] && grep -q '"ev":"STEP_OK".*"call":"call-h-1"' "$SPOOL"; then
  pass "the failing call is CLOSED on the ledger (STEP_START no longer dangles)"
else
  fail "STEP_START for the failing call was never closed — the blind spot is open"
fi

# ---------------------------------------------------------------------------
# CLAIM 5 — the ledger does not call a failure a success. A closing event that
# is byte-identical to a successful one is a record that cannot be read back.
if [ -f "$SPOOL" ] && grep '"ev":"STEP_OK"' "$SPOOL" | grep -q '"rc":1'; then
  pass "the closing event carries rc:1 — a reader can tell failure from success"
else
  fail "the closing event for a failing call is indistinguishable from a successful one"
fi
fresh
pre_bash s-ok2 'ls -la' 'call-i-1' >/dev/null
post_ok  s-ok2 'ls -la' 'call-i-1' 'total 0' >/dev/null
SPOOL="$RABADON_DIR/spool/$DAY.jsonl"
if [ -f "$SPOOL" ] && ! grep '"ev":"STEP_OK"' "$SPOOL" | grep -q '"rc":1'; then
  pass "a successful call carries no rc:1 (the marker is not painted on everything)"
else
  fail "a successful call was marked rc:1"
fi

# ---------------------------------------------------------------------------
# CLAIM 6 — RECORDING IS NOT DECIDING. Seeing a failure must not change any
# exit code. If it can, this is no longer a recorder.
fresh
E1="$(pre_bash s-f4 'ls /nonexistent-rabadon-probe' 'call-j-1')"
E2="$(post_fail s-f4 'ls /nonexistent-rabadon-probe' 'call-j-1' "$ERRTEXT")"
[ "$E1" = "0" ] && pass "the PreToolUse before a failure still exits 0" \
                || fail "PreToolUse exit changed to $E1"
[ "$E2" = "0" ] && pass "observing a failed call exits 0 — it refuses nothing" \
                || fail "the failure event exited $E2, expected 0"

# ---------------------------------------------------------------------------
# CLAIM 7 — THE INSTALL SIDE. Understanding the event is worth nothing if the
# agent is never told to send it.
#
# THIS CLAIM WAS WRITTEN WRONG THE FIRST TIME AND THE MUTATION RUN CAUGHT IT:
# it grepped hooks/install.mjs for the string, so it stayed green after the
# subscription was deleted, matching the COMMENT that explains it. A gate that
# reads the file that is supposed to change is not a gate. It now RUNS the
# installer into a scratch directory and reads the settings.json that a user
# would actually get.
NODE_OK=0
command -v node >/dev/null 2>&1 && NODE_OK=1
if [ "$NODE_OK" = "0" ]; then
  # NOT a skip. The installer is JavaScript; without node this claim cannot be
  # answered, and an unanswerable claim is red, not absent.
  fail "node is not available — the install side of the blind spot went UNCHECKED"
else
  IDIR="$ROOT/installtarget"; mkdir -p "$IDIR"
  ROOTDIR="$(cd "$HERE/.." && pwd)"
  node -e '
    import(process.argv[1] + "/hooks/install.mjs").then((m) => {
      m.installHooks(process.argv[2], { gateCmd: process.argv[1] + "/native/rabadon-gate" });
    }).catch((e) => { console.error(String(e)); process.exit(3); });
  ' "$ROOTDIR" "$IDIR" >/dev/null 2>&1
  WROTE="$IDIR/.claude/settings.json"
  if [ -f "$WROTE" ] && python3 -c '
import json,sys
h = json.load(open(sys.argv[1])).get("hooks", {})
ents = h.get("PostToolUseFailure") or []
cmds = [k.get("command","") for e in ents for k in (e.get("hooks") or [])]
sys.exit(0 if any("rabadon-gate" in c for c in cmds) else 1)' "$WROTE"; then
    pass "the settings.json rabadon WRITES subscribes the gate to PostToolUseFailure"
  else
    fail "rabadon installs no PostToolUseFailure hook — on a real machine the event is never delivered"
  fi
fi

# ---------------------------------------------------------------------------
# CLAIM 8 — the captured payload is kept in the repo, verbatim. A shape nobody
# can re-read is a shape the next reader has to take on trust.
CAP="$(cd "$HERE/.." && pwd)/docs/archive/reports/kosu/RAPOR/f3e-1-posttooluse-failure-payload.json"
if [ -f "$CAP" ] && python3 -c '
import json,sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("hook_event_name") == "PostToolUseFailure" and "error" in d
              and "tool_response" not in d else 1)' "$CAP"; then
  pass "the live capture this suite is written against is in the repo"
else
  fail "the live PostToolUseFailure capture is missing or no longer has that shape"
fi

# ---------------------------------------------------------------------------
# CLAIM 9 — THE RESIDUAL, STATED RATHER THAN HIDDEN. A command that fails
# without printing anything an error scanner recognises (`false`, a bare
# `exit 1`) still has no err_sig, because there is no error text to sign. What
# it MUST have is claimed_rc 1: the record says "this failed, and I have no
# signature for it" instead of quietly saying "this succeeded". Pinned here so
# the gap is a documented shape and not a surprise for the next reader.
fresh
pre_bash  s-f5 'false' 'call-k-1' >/dev/null
post_fail s-f5 'false' 'call-k-1' 'Exit code 1' >/dev/null
RC="$(moves_py 'm[-1]["claimed_rc"] if m else "NONE"')"
SG="$(moves_py 'm[-1]["err_sig"] if m else "NONE"')"
[ "$RC" = "1" ] && pass "a silent failure is still recorded as a failure (claimed_rc 1)" \
                || fail "a silent failure recorded claimed_rc=$RC, expected 1"
[ -z "$SG" ] && pass "a silent failure honestly carries NO err_sig (nothing to sign)" \
             || fail "a silent failure invented an err_sig: $SG"

# ---------------------------------------------------------------------------
# CLAIM 10 — AN INSTALL FROM BEFORE TODAY IS STILL BLIND, AND THE PRODUCT HAS
# TO SAY SO. Teaching the binary the event fixes nothing on a machine whose
# .claude/settings.json was written last week: the agent still never sends it,
# and a supervisor that is silently blind is the failure this repo sells a cure
# for. The screen for this is the session contract's `blind spots:` block —
# the one place rabadon already lists where its coverage has holes.
#
# NOT `rabadon doctor`: bin/rabadon.mjs is a frozen anti-path in this project
# and the gate refused the edit. The refusal was correct and the approach
# changed rather than the rule.
# A DISTINCT SESSION PER PROBE. The contract is stated once per session, so
# reusing one id makes the second and third reads EMPTY — and an empty string
# passes a "does not contain" assertion for the wrong reason. That is a vacuous
# green, caught here while writing this suite.
SESSION_START() { # SESSION_START <project-dir> <session-id>
  printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s"}' "$2" "$1" | "$GATE" 2>/dev/null
}

STALE="$ROOT/stale"; mkdir -p "$STALE/.claude" "$STALE/.git"
printf 'ref: refs/heads/main\n' > "$STALE/.git/HEAD"
# the shape rabadon itself wrote before this fix: every event EXCEPT the one
# that carries a failure.
python3 -c '
import json, sys
g = sys.argv[2]
ev = lambda: [{"matcher": "*", "hooks": [{"type": "command", "command": g}]}]
json.dump({"hooks": {k: ev() for k in
          ("SessionStart","UserPromptSubmit","Stop","PreToolUse","PostToolUse")}},
          open(sys.argv[1], "w"))' "$STALE/.claude/settings.json" "$HERE/rabadon-gate"

CARD="$(SESSION_START "$STALE" s-card-1)"
case "$CARD" in
  *PostToolUseFailure*) pass "the session card DECLARES the blind spot on a stale install" ;;
  *) fail "a stale install is silently blind to failing calls — the card says nothing" ;;
esac

# and it must not cry wolf on a complete one. Same directory, one event added.
python3 -c '
import json, sys
p = sys.argv[1]; g = sys.argv[2]
d = json.load(open(p))
d["hooks"]["PostToolUseFailure"] = [{"matcher": "*", "hooks": [{"type": "command", "command": g}]}]
json.dump(d, open(p, "w"))' "$STALE/.claude/settings.json" "$HERE/rabadon-gate"
CARD2="$(SESSION_START "$STALE" s-card-2)"
case "$CARD2" in
  *PostToolUseFailure*) fail "the card cries blind spot at an install that IS subscribed" ;;
  *) pass "the card drops the blind spot once the install subscribes" ;;
esac

# the check reads a SUBSCRIPTION, not the word. A settings.json that merely
# mentions the event must not silence the warning — that is precisely the fake
# gate this suite already caught itself shipping once.
printf '{"hooks":{"PostToolUseFailure":[{"matcher":"*","hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}\n' \
  > "$STALE/.claude/settings.json"
CARD3="$(SESSION_START "$STALE" s-card-3)"
case "$CARD3" in
  *PostToolUseFailure*) pass "someone else's hook on the event does not count as rabadon subscribing" ;;
  *) fail "the card was silenced by an event entry that has no rabadon hook in it" ;;
esac

printf 'failed_call: %d passed, %d failed\n' "$PASSN" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
