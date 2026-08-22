#!/usr/bin/env bash
# R4 acceptance — injection: the error is repaired at the moment it happens.
#
# WRITTEN BEFORE THE CODE and red on the day it is written. That is the correct
# state: R4 does not exist yet. Turning it green is R4's job. Every red below
# must be readable as "the feature is absent", never as "the script is broken",
# and the vacuity guards exist so the two can never be confused.
#
# WHAT R4 IS, IN ONE SENTENCE.
# When a signal fires the agent is NOT stopped. The history it cannot see is put
# into its context through the PreToolUse additionalContext channel, and the
# agent repairs the problem itself on its next attempt. This is the round that
# closes complaint 2 in the plan — "it catches things but it does not solve
# them, and the cost goes up". The tokens are already being spent by the model
# that is running; rabadon makes no second call (Law 6).
#
# THE THREE LEVELS, AND ONLY ONE OF THEM STOPS ANYTHING.
#   certain -> block.  The 11 compiled laws and test-tamper are unchanged. What
#              is NEW is signal 5's deterministic subset: writing to a
#              test/harness/gate file while the suite is RED is refused, and
#              stderr says why. Deterministic, so it is allowed to act.
#   likely  -> inject, never block.  Semantic repeat, oscillation, root
#              migration, red->green-with-only-the-test-side-changed.
#   weak    -> ledger only.  The agent never sees it.
# Law 1 is the whole reason for that split: an unmeasured guess never enforces,
# and everything at the "likely" level is still a guess about intent.
#
# WHAT THE INJECTED TEXT MUST CONTAIN (Law 2 + Law 3):
#   - which file was being worked in         (file-level localisation)
#   - what broke on the previous attempt     (the readable form of err_sig)
#   - the CONTRAST: after this move the suite was green, after this one red
#   - which attempt number this is
# WHAT IT MUST NOT CONTAIN:
#   - a line number. Law 2 is not a style preference: on SWE-bench Verified
#     file-level localisation is the dominant factor and line-level context
#     raises noise and often LOWERS the score. Naming a line is an active harm.
#   - an instruction telling the agent what to do. Information, not advice.
#   - anything over 400 characters. Law 6: every token rabadon injects is
#     written to the counter as a COST, so the budget is a hard edge.
#
# WHY THE CHANNEL IS ASSERTED SEPARATELY (claim 2).
# stdout is a hook's PERMISSION channel. A bare printf on stdout is not "the
# same thing, delivered informally" — it is a malformed permission response, and
# the plan records that this exact mistake was already made once and is not to
# be repeated. So the SHAPE matters, not just the presence of the text: the
# response has to parse as JSON and carry additionalContext for PreToolUse.
#
# NO ASSERTION MAY PASS VACUOUSLY. "no injection was produced" and "the gate
# never ran" print the same on a green line. Every check below first proves the
# fixture was actually seen — a non-empty spool, or a captured response — and is
# RED, not silently green, when it was not. Copied from native/signals_test.sh,
# where the same bug had already shipped twice.
#
# ENFORCE, NOT WATCH. The sandbox touches $RABADON_DIR/enabled. Without that
# marker the gate refuses nothing and returns 0 to everything, and claim 3's
# "identical exit codes" and claim 5's "this is blocked" would both be true for
# reasons that have nothing to do with R4. Claims 3 and 5 prove the fixture can
# refuse something before they compare anything.
#
# THE KILL SWITCH: RABADON_INJECT=0.

set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

GATE="$ROOT/native/rabadon-gate"

PASS_N=0; FAIL_N=0; C1_FAIL=0
pass() { printf 'PASS  %s\n' "$1"; PASS_N=$((PASS_N + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL_N=$((FAIL_N + 1)); }
note() { printf '      %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

[ -x "$GATE" ] || { printf 'FAIL  no gate binary — run make first\n'; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL  python3 required\n'; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rbr4.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

# ---------------------------------------------------------------------------
# One sandbox per fixture, the way reports/R2 and native/signals_test.sh do it.
# Sessions never share a spool, so "was this injected" is always a question
# about ONE session's own events and no fixture can be contaminated by the one
# before it. CAP is where every PreToolUse response of the current fixture is
# kept, one file per event, so claim 4 can count them.
NEW_HOME=""; NEW_PROJ=""; CAP=""; CAPN=0
sandbox() {
  NEW_HOME="$(mktemp -d "$WORK/h.XXXXXX")"
  NEW_PROJ="$(mktemp -d "$WORK/p.XXXXXX")"
  CAP="$(mktemp -d "$WORK/c.XXXXXX")"; CAPN=0
  mkdir -p "$NEW_HOME/.rabadon/spool" "$NEW_PROJ/.git" "$NEW_PROJ/src" "$NEW_PROJ/tests"
  printf 'ref: refs/heads/main\n' > "$NEW_PROJ/.git/HEAD"
  # enforce, not watch — see the header.
  : > "$NEW_HOME/.rabadon/enabled"
}

# ev <hook> <tool> <session> <json-tool-input> [tool_response]
# stdout is RETURNED, because stdout is the channel the injection has to travel.
# stderr is dropped here; ev_err below is the one that reads it.
ev() {
  local hook="$1" tool="$2" sid="$3" input="$4" resp="${5:-}"
  local j
  j="$(printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":%s' \
        "$hook" "$sid" "$NEW_PROJ" "$tool" "$input")"
  [ -n "$resp" ] && j="$j,\"tool_response\":$(jstr "$resp")"
  j="$j}"
  printf '%s' "$j" | env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" RABADON_NOTIFY=0 \
    ${INJ_ENV:-} "$GATE" 2>/dev/null
}

# the same event, but stderr is what comes back — claim 5 has to read the reason
# a refusal gives, not just its exit code.
ev_err() {
  local hook="$1" tool="$2" sid="$3" input="$4" resp="${5:-}"
  local j
  j="$(printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":%s' \
        "$hook" "$sid" "$NEW_PROJ" "$tool" "$input")"
  [ -n "$resp" ] && j="$j,\"tool_response\":$(jstr "$resp")"
  j="$j}"
  printf '%s' "$j" | env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" RABADON_NOTIFY=0 \
    ${INJ_ENV:-} "$GATE" 2>&1 >/dev/null
}

# capturing forms: every PreToolUse response is written to CAP so claim 1 can
# read the text and claim 4 can count how many times it appeared.
# NOT A PIPE, and that is the whole point. Under bash the last element of a
# pipeline runs in a SUBSHELL, so `... | cap` incremented CAPN inside a child
# that then exited: the parent's CAPN stayed 0 and every response overwrote
# 001.out. Only the LAST PreToolUse of each fixture was ever graded — which made
# claims 1 and 4 jointly unsatisfiable, because claim 4 requires the third
# occurrence to carry no injection, and claim 1 then read that empty response.
# Proven under bash: `echo a|cap; echo b|cap; echo c|cap` leaves CAPN=0 and one
# file. (zsh does not do this, which is how it survived being written.)
# Command substitution keeps the counter in this shell.
cap() { CAPN=$((CAPN + 1)); printf '%s' "$1" > "$CAP/$(printf '%03d' "$CAPN").out"; }

bash_pre()  { cap "$(ev PreToolUse  Bash "$1" "{\"command\":$(jstr "$2")}")"; }
bash_post() { ev PostToolUse Bash "$1" "{\"command\":$(jstr "$2")}" "$3" >/dev/null; }
edit_pre()  { cap "$(ev PreToolUse  Edit "$1" "{\"file_path\":$(jstr "$NEW_PROJ/$2"),\"old_string\":\"\",\"new_string\":$(jstr "$3")}")"; }
ran()       { bash_pre "$1" "$2"; bash_post "$1" "$2" "$3"; }

# ---------------------------------------------------------------------------
# READING THE RESPONSES.
#
# THE SHAPE IS THE ASSERTION, not the presence of the string. A hook's stdout is
# its permission channel; Claude Code reads
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":...}}
# and a bare print of the same sentence is a malformed permission response that
# happens to contain the right words. The top-level "additionalContext" spelling
# is accepted as well, because the plan fixes the CHANNEL and not the exact
# envelope, but a response that does not parse as a JSON object is never
# accepted (see JUDGEMENT CALL 2 in the closing notes).

# acx <dir> — every additionalContext string captured in that dir, one per line,
# newlines inside a string flattened so the count of lines is the count of
# injections.
acx() {
  python3 - "$1" <<'PY'
import json, os, sys, glob
out = []
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.out"))):
    raw = open(f, encoding="utf-8", errors="replace").read().strip()
    if not raw: continue
    for chunk in [raw] + raw.splitlines():
        try: o = json.loads(chunk)
        except Exception: continue
        if not isinstance(o, dict): continue
        hs = o.get("hookSpecificOutput")
        v = ""
        if isinstance(hs, dict) and hs.get("additionalContext"):
            v = hs["additionalContext"]
        elif o.get("additionalContext"):
            v = o["additionalContext"]
        if v:
            out.append(" ".join(str(v).split()))
            break
print("\n".join(out))
PY
}

# json_shape <dir> — "ok" if at least one captured response parses as a JSON
# object AND carries additionalContext under hookSpecificOutput with
# hookEventName PreToolUse; "loose" if it parses and carries a top-level
# additionalContext; "bare" if there was output that carries the field but does
# not parse as JSON; "none" if nothing was captured.
json_shape() {
  python3 - "$1" <<'PY'
import json, os, sys, glob
best = "none"
rank = {"none": 0, "bare": 1, "loose": 2, "ok": 3}
def better(a, b): return a if rank[a] >= rank[b] else b
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.out"))):
    raw = open(f, encoding="utf-8", errors="replace").read().strip()
    if not raw: continue
    parsed = None
    for chunk in [raw] + raw.splitlines():
        try: o = json.loads(chunk)
        except Exception: continue
        if isinstance(o, dict): parsed = o; break
    if parsed is None:
        if "additionalContext" in raw: best = better(best, "bare")
        continue
    hs = parsed.get("hookSpecificOutput")
    if isinstance(hs, dict) and hs.get("additionalContext"):
        if hs.get("hookEventName") == "PreToolUse": best = better(best, "ok")
        else: best = better(best, "loose")
    elif parsed.get("additionalContext"):
        best = better(best, "loose")
print(best)
PY
}

# THE VACUITY GUARD, copied from native/signals_test.sh. Total ledger lines of
# any kind. Zero means the gate never saw the fixture — wrong sandbox, dead
# binary, malformed event — and every judgement about the fixture below would be
# a judgement about nothing.
nevents() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import os, sys, glob
n = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f, encoding="utf-8", errors="replace"):
        if line.strip(): n += 1
print(n)
PY
}
live() { local n; n="$(nevents)"; case "$n" in ''|*[!0-9]*) return 1;; 0) return 1;; *) return 0;; esac; }

# every SIGNAL name in this sandbox's spool — used only to prove a fixture
# really did produce the signal it claims to be about, so that "no injection"
# can be told apart from "no signal to inject".
fired() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
names = []
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        if e.get("ev") == "SIGNAL": names.append(e.get("signal") or e.get("name") or "?")
print(" ".join(sorted(set(names))))
PY
}
has() { case " $(fired) " in *" $1 "*) return 0;; *) return 1;; esac; }

# ---------------------------------------------------------------------------
# THE FIXTURE THE WHOLE ROUND IS BUILT ON: a synthetic ROOT MIGRATION session,
# which the plan names as the acceptance fixture for injection.
#
# Its shape is chosen so that the injected text has something to say on every
# one of Law 2 and Law 3's four points:
#   - a GREEN move first, so the contrast has a left-hand side
#   - an edit to ONE file, so there is a file context to name
#   - the same error surviving three different commands, which is the root
#     migration signal itself (ROOT_MIN_PATHS = 3) and the readable err_sig
#   - a RED suite after, so the contrast has a right-hand side
#   - a final PreToolUse, which is the first moment an injection can legally be
#     delivered: root migration is detected on PostToolUse, and additionalContext
#     only exists on PreToolUse (see JUDGEMENT CALL 1).
drive_root() { # drive_root <sid>
  local s="$1"
  ran      "$s" 'npm test'          '12 passed, 0 failed'
  edit_pre "$s" src/app.js          'function total(a, b) { return a.value + b.value; }'
  ran      "$s" 'npm run build'     'TypeError: undefined is not a function'
  ran      "$s" 'npx tsc --noEmit'  'TypeError: undefined is not a function'
  ran      "$s" 'node dist/main.js' 'TypeError: undefined is not a function'
  ran      "$s" 'npm test'          '3 passed, 2 failed'
  edit_pre "$s" src/app.js          'function total(a, b) { return a.value + b.val; }'
}

# ===========================================================================
head_ "CLAIM 1 — an injection is produced, and it says the four things and none of the forbidden ones"

sandbox
drive_root s-root
INJ="$(acx "$CAP")"
FIRST="$(printf '%s\n' "$INJ" | head -1)"

if ! live; then
  fail "1a the spool is empty — the gate never saw the root-migration fixture"
  note "nothing below this line is a statement about R4"
elif ! has root_migration; then
  fail "1a root_migration did not even fire — fired: [$(fired)]; there was nothing to inject"
  note "this is an R2 regression, not an R4 absence — read it that way"
elif [ -z "$FIRST" ]; then
  fail "1a no injected text was produced on a root-migration session"
else
  pass "1a a root-migration session produces injected text"
fi

# --- no line number (Law 2) ------------------------------------------------
# Law 2 is a measured claim, not a taste: file-level localisation dominates on
# SWE-bench Verified and line-level context raises noise and frequently lowers
# the score. So a line number is not merely useless here, it is a regression in
# the thing the injection exists to improve. The patterns below are the forms a
# line number actually takes; "attempt 3" is deliberately NOT one of them,
# because the attempt number is required by Law 3.
if [ -z "$FIRST" ]; then
  fail "1b no line-number check was possible — nothing was injected"
elif printf '%s' "$FIRST" | grep -Eqi ':[0-9]+|\bline[[:space:]]+[0-9]+|\bsatır[[:space:]]+[0-9]+|\bL[0-9]+\b'; then
  fail "1b the injected text carries a line number: [$FIRST]"
  note "Law 2 — file context helps, line context measurably hurts"
else
  pass "1b the injected text carries no line number"
fi

# --- 400 characters (Law 6) ------------------------------------------------
# Characters, not bytes: the counter charges the model for tokens, and a budget
# that a non-ASCII word can blow through by accident is not a budget.
if [ -z "$FIRST" ]; then
  fail "1c no length check was possible — nothing was injected"
else
  NCH="$(printf '%s' "$FIRST" | python3 -c 'import sys;print(len(sys.stdin.buffer.read().decode("utf-8","replace")))')"
  if [ "${NCH:-9999}" -le 400 ] 2>/dev/null; then
    pass "1c the injected text is ${NCH} characters, within the 400 budget"
  else
    fail "1c the injected text is ${NCH} characters, over the 400 budget"
    note "Law 6 — every injected token is a COST line in the counter"
  fi
fi

# --- it names the file -----------------------------------------------------
# File-level localisation is the half of Law 2 that is a requirement rather than
# a prohibition. The session edited exactly one file and the text has to say so.
if [ -z "$FIRST" ]; then
  fail "1d no file-context check was possible — nothing was injected"
elif printf '%s' "$FIRST" | grep -q 'app\.js'; then
  pass "1d the injected text names the file being worked in (app.js)"
else
  fail "1d the injected text does not name app.js: [$FIRST]"
fi

# --- it carries what broke -------------------------------------------------
# The readable form of err_sig. The agent's own transcript has this; what the
# agent does NOT have is the fact that it survived three different moves.
if [ -z "$FIRST" ]; then
  fail "1e no err_sig check was possible — nothing was injected"
elif printf '%s' "$FIRST" | grep -qi 'TypeError'; then
  pass "1e the injected text carries what broke (TypeError)"
else
  fail "1e the injected text does not say what broke: [$FIRST]"
fi

# --- THE CONTRAST (Law 3) --------------------------------------------------
# ContrastRepair's result: given a passing/failing PAIR the model localises the
# root cause markedly better than it does from the failure alone. The move
# record has that pair for free — one move left the suite green, a later one
# left it red. This is the single highest-value sentence in the whole injection
# and it is why the fixture opens with a green `npm test`.
if [ -z "$FIRST" ]; then
  fail "1f no contrast check was possible — nothing was injected"
else
  GRE=0; RED=0
  printf '%s' "$FIRST" | grep -Eqi 'green|ye[sş]il|passed|ge[cç]ti' && GRE=1
  printf '%s' "$FIRST" | grep -Eqi '\bred\b|k[iı]rm[iı]z|failed|kald[iı]'   && RED=1
  if [ "$GRE" = 1 ] && [ "$RED" = 1 ]; then
    pass "1f the injected text carries the contrast — a green move and a red move"
  else
    fail "1f the injected text has no green/red contrast pair (green=$GRE red=$RED): [$FIRST]"
    note "Law 3 — the pair is free from the move record and it is worth more than the error alone"
  fi
fi

# --- which attempt this is -------------------------------------------------
if [ -z "$FIRST" ]; then
  fail "1g no attempt-number check was possible — nothing was injected"
elif printf '%s' "$FIRST" | grep -Eqi '([0-9]+)[.)]?[[:space:]]*(attempt|deneme|try)|(attempt|deneme|try)[[:space:]]*#?[0-9]+'; then
  pass "1g the injected text says which attempt this is"
else
  fail "1g the injected text does not say which attempt this is: [$FIRST]"
fi

C1_FAIL="$FAIL_N"

# ===========================================================================
head_ "CLAIM 2 — the injection travels the permission channel, in the right shape"

# stdout is a hook's PERMISSION channel. This is not a formatting preference:
# a bare printf of the same sentence is a MALFORMED permission response that
# happens to contain the right words, and the plan records that this mistake was
# already made once ("hook'ların başarıda stdout'a yazması yasak") and is not to
# be repeated. Presence is not the assertion. Shape is.
SHAPE="$(json_shape "$CAP")"
case "$SHAPE" in
  ok)
    pass "2a the response parses as JSON and carries PreToolUse additionalContext" ;;
  loose)
    pass "2a the response parses as JSON and carries additionalContext"
    note "it is not under hookSpecificOutput/hookEventName=PreToolUse — the documented envelope" ;;
  bare)
    fail "2a the injection reached stdout but the response does not parse as JSON"
    note "stdout is the permission channel; an unparseable object there is a malformed verdict" ;;
  *)
    fail "2a no response carrying additionalContext was produced at all" ;;
esac

# stderr is the OTHER wrong channel, and the more tempting one, because a
# refusal already writes there. stderr is for the human; additionalContext is
# for the model. Text that only reaches stderr never enters the context window
# and the agent repairs nothing.
sandbox
ERRTXT=""
ran      s-ch 'npm test'          '12 passed, 0 failed'
edit_pre s-ch src/app.js          'function total(a, b) { return a.value + b.value; }'
ran      s-ch 'npm run build'     'TypeError: undefined is not a function'
ran      s-ch 'npx tsc --noEmit'  'TypeError: undefined is not a function'
ran      s-ch 'node dist/main.js' 'TypeError: undefined is not a function'
ERRTXT="$(ev_err PreToolUse Edit s-ch "{\"file_path\":$(jstr "$NEW_PROJ/src/app.js"),\"old_string\":\"\",\"new_string\":$(jstr 'function total(a, b) { return a.value + b.val; }')}")"
if ! live; then
  fail "2b the spool is empty — the channel fixture never ran"
elif printf '%s' "$ERRTXT" | grep -qi 'TypeError'; then
  fail "2b the diagnosis was written to stderr: [$ERRTXT]"
  note "stderr is read by the human, not by the model — nothing there repairs anything"
else
  pass "2b the diagnosis is not delivered on stderr"
fi

# ===========================================================================
head_ "CLAIM 3 — injection never blocks"

# Law 1, stated as an exit code. Everything at the 'likely' level is a guess
# about intent and its false positive rate has never been measured on real
# sessions, so it is allowed to inform and never to stop. If R4 ever moves an
# exit code from this level, the product becomes the thing the plan's complaint
# 1 describes: a tool whose felt slowness is a block followed by blind groping.

# First prove the fixture can refuse ANYTHING. In watch mode the gate returns 0
# to everything and "the exit codes are identical" is two allow paths compared
# to each other — green, and worth nothing.
sandbox
ev PreToolUse Bash s-guard "{\"command\":$(jstr 'git push --force origin main')}" >/dev/null 2>&1
DENY_RC=$?
if [ "$DENY_RC" = "2" ]; then
  pass "3a the fixture is in enforce mode: the force-push is refused (exit 2)"
else
  fail "3a the fixture refuses nothing — the force-push exited $DENY_RC, expected 2"
  note "nothing in claim 3 or claim 5 means anything until this is 2"
fi

# ON: injection live. OFF: RABADON_INJECT=0. Same likely-level session, same
# final PreToolUse, and the exit code of that final event has to match.
INJ_ENV=""; sandbox; drive_root s-on
ON_RC=$?
ON_FIRED="$(fired)"; ON_LIVE=0; live && ON_LIVE=1
ON_INJ="$(acx "$CAP")"

INJ_ENV="RABADON_INJECT=0"; sandbox; drive_root s-off
OFF_RC=$?
OFF_LIVE=0; live && OFF_LIVE=1
OFF_INJ="$(acx "$CAP")"
INJ_ENV=""

if [ "$ON_LIVE" != 1 ] || [ "$OFF_LIVE" != 1 ]; then
  fail "3b one of the two arms never reached the gate (on=$ON_LIVE off=$OFF_LIVE)"
elif [ "$ON_RC" != "0" ]; then
  fail "3b a likely-level signal moved the exit code: the final PreToolUse exited $ON_RC, not 0"
  note "Law 1 — an unmeasured guess informs, it never stops"
elif [ "$ON_RC" = "$OFF_RC" ]; then
  pass "3b exit code identical with injection on and off — $ON_RC, and the agent keeps working"
else
  fail "3b injection moved the verdict: on=$ON_RC off=$OFF_RC"
fi

# and the kill switch has to actually kill it, or it is a switch nobody tested.
if [ -z "$ON_INJ" ]; then
  fail "3c RABADON_INJECT=0 is not proven — nothing was injected with it ON either"
elif [ -n "$OFF_INJ" ]; then
  fail "3c RABADON_INJECT=0 still injected: [$(printf '%s' "$OFF_INJ" | head -1)]"
else
  pass "3c RABADON_INJECT=0 turns injection off"
fi

# ===========================================================================
head_ "CLAIM 4 — the same signal is injected at most twice per session"

# Law 6 again, from the cost side, and complaint 3 in the plan ("it burns
# tokens"). A supervisor that repeats itself every turn is a supervisor the
# operator learns to skim, and every repetition is charged to the user. The
# third occurrence goes to the ledger only — and per the plan that third one is
# what will later trigger R5's repair arm, so the cap is not merely a mute, it
# is the hand-off point.
sandbox
drive_root s-cap
# two further chances for the SAME signal to speak: the same error, from two
# more different moves, each followed by a PreToolUse where an injection could
# be delivered.
ran      s-cap 'node --test'      'TypeError: undefined is not a function'
edit_pre s-cap src/app.js         'function total(a, b) { return a?.value + b?.value; }'
ran      s-cap 'npm run verify'   'TypeError: undefined is not a function'
edit_pre s-cap src/app.js         'function total(a, b) { return (a||{}).value + (b||{}).value; }'
ran      s-cap 'npm run smoke'    'TypeError: undefined is not a function'
edit_pre s-cap src/app.js         'function total(a, b) { return Number(a.value) + Number(b.value); }'

NSAME="$(acx "$CAP" | grep -ci 'TypeError' || true)"
if ! live; then
  fail "4 the spool is empty — the cap fixture never reached the gate"
elif ! has root_migration; then
  fail "4 root_migration never fired, so the cap was never under load — fired: [$(fired)]"
elif [ "${NSAME:-0}" -eq 0 ]; then
  fail "4 the same signal was never injected once, so the cap proved nothing"
elif [ "${NSAME:-0}" -le 2 ]; then
  pass "4 the same signal was injected ${NSAME} time(s) across the session, never a third"
else
  fail "4 the same signal was injected ${NSAME} times — the cap is 2, the third belongs to the ledger"
  note "the third occurrence is R5's trigger, not another paragraph in the context window"
fi

# ===========================================================================
head_ "CLAIM 5 — the certain level: a red suite closes the door on the test file, a green suite does not"

# THIS IS THE FIXTURE THAT SEPARATES THE PRODUCT FROM ITS NEAREST FAILURE MODE.
# The pair below is the same write, byte for byte, and the only difference is
# the colour of the suite:
#   red   -> blocked. Editing the thing that decides green while it is failing
#            is how a check gets satisfied without the value behind it. This is
#            the deterministic subset of signal 5, which is why it is allowed to
#            act at all while the rest of signal 5 only injects.
#   green -> allowed. Editing tests on a green suite is the single most valuable
#            thing an agent does, and a rule that punishes it gets the tool
#            uninstalled on the first afternoon (Law 1).
# Note the write is an ADDED assertion, not a skip and not a deletion: today's
# test-tamper already refuses those two, so a weakening edit would be green here
# for a reason that predates R4 and would prove nothing about this round.

TEST_TEXT='expect(total(a, b)).toBe(3); expect(total(a, c)).toBe(4);'

# --- red suite -------------------------------------------------------------
sandbox
ran s-red 'npm test' '3 passed, 2 failed'
RED_ERR="$(ev_err PreToolUse Edit s-red "{\"file_path\":$(jstr "$NEW_PROJ/tests/app.test.js"),\"old_string\":\"\",\"new_string\":$(jstr "$TEST_TEXT")}")"
ev PreToolUse Edit s-red "{\"file_path\":$(jstr "$NEW_PROJ/tests/app.test.js"),\"old_string\":\"\",\"new_string\":$(jstr "$TEST_TEXT")}" >/dev/null 2>&1
RED_RC=$?

if ! live; then
  fail "5a the spool is empty — the red-suite fixture never reached the gate"
elif [ "$RED_RC" = "2" ]; then
  pass "5a a write to a test file while the suite is RED is blocked (exit 2)"
else
  fail "5a a write to a test file while the suite is RED exited $RED_RC, expected 2"
fi

# The reason has to be in the refusal. A block with no reason is complaint 1 in
# the plan: the gate stops the work and the diagnosis is left to guesswork.
if [ -z "$RED_ERR" ]; then
  fail "5b the red-suite refusal said nothing on stderr"
elif printf '%s' "$RED_ERR" | grep -Eqi 'suite k[iı]rm[iı]z|suite is red|tests are RED|k[iı]rm[iı]z[iı]'; then
  pass "5b the refusal says why: the suite is red"
else
  fail "5b the refusal does not name the red suite as the reason: [$(printf '%s' "$RED_ERR" | head -3 | tr '\n' ' ')]"
fi

# --- green suite, THE SAME WRITE -------------------------------------------
sandbox
ran s-green 'npm test' '12 passed, 0 failed'
ev PreToolUse Edit s-green "{\"file_path\":$(jstr "$NEW_PROJ/tests/app.test.js"),\"old_string\":\"\",\"new_string\":$(jstr "$TEST_TEXT")}" >/dev/null 2>&1
GREEN_RC=$?
if ! live; then
  fail "5c the spool is empty — the green-suite fixture never reached the gate"
elif [ "$GREEN_RC" = "0" ]; then
  pass "5c the identical write on a GREEN suite passes (exit 0)"
else
  fail "5c the identical write on a GREEN suite exited $GREEN_RC — the rule punishes writing tests"
  note "Law 1 — this is the false positive that deletes the product"
fi

# ===========================================================================
head_ "CLAIM 6 — nothing regressed"

# R4 touches the record (moves.h), the detectors (signals.h) and the gate's
# response path all at once. That is exactly the change that quietly breaks the
# thing it reads from while every one of its own checks stays green, so the four
# numbers below are PINNED rather than eyeballed.
regress() { # regress <label> <command> <expected last line>
  local label="$1" cmd="$2" want="$3" out
  out="$(eval "$cmd" 2>&1 | tail -1)"
  if [ -z "$out" ]; then
    fail "6 $label printed nothing — the suite did not run"
  elif [ "$out" = "$want" ]; then
    pass "6 $label: $want"
  else
    fail "6 $label regressed or changed shape: [$out]"
  fi
}
regress "native/moves_test.sh"   "./native/moves_test.sh"   "moves: 21 passed, 0 failed"
regress "native/signals_test.sh" "./native/signals_test.sh" "signals: 39 passed, 0 failed"

R2_OUT="$(./reports/R2/accept.sh 2>&1)"
R2_TALLY="$(printf '%s' "$R2_OUT" | grep -E '^== R2 acceptance:' | tail -1)"
if [ -z "$R2_TALLY" ]; then
  fail "6 reports/R2/accept.sh printed no tally — it did not run"
elif [ "$R2_TALLY" = "== R2 acceptance: 19 green, 0 red" ]; then
  pass "6 reports/R2/accept.sh: 19 green, 0 red"
else
  fail "6 reports/R2/accept.sh regressed: [$R2_TALLY]"
fi

R3_OUT="$(./reports/R3/accept.sh 2>&1)"
R3_TALLY="$(printf '%s' "$R3_OUT" | grep -E '^== R3 acceptance:' | tail -1)"
if [ -z "$R3_TALLY" ]; then
  fail "6 reports/R3/accept.sh printed no tally — it did not run"
elif [ "$R3_TALLY" = "== R3 acceptance: 14 green, 0 red" ]; then
  pass "6 reports/R3/accept.sh: 14 green, 0 red"
else
  fail "6 reports/R3/accept.sh regressed: [$R3_TALLY]"
fi

# ===========================================================================
printf '\n== R4 acceptance: %d green, %d red\n' "$PASS_N" "$FAIL_N"
# Claim 1 is "an injection exists and says the right things". With no injection
# built, claims 2, 3 and 4 are all statements about a thing that is not there:
# text that was never produced cannot travel the wrong channel, cannot move an
# exit code, and cannot be repeated a third time. Say so, or a round that has
# delivered nothing reads as most of the way finished.
if [ "$C1_FAIL" -gt 0 ]; then
  printf '      NOTE: claim 1 had %d red, so claims 2, 3 and 4 proved nothing this run —\n' "$C1_FAIL"
  printf '      an injection that does not exist cannot take the wrong channel, cannot move\n'
  printf '      a verdict, and cannot be repeated a third time.\n'
fi
[ "$FAIL_N" -gt 0 ] && { printf 'R4 NOT ACCEPTED\n'; exit 1; }
printf 'R4 ACCEPTED\n'
exit 0

# ---------------------------------------------------------------------------
# WHERE THE PLAN WAS AMBIGUOUS AND THIS FILE HAD TO CHOOSE. Named, not silently
# decided, so the implementation can overrule any of them on purpose.
#
# JUDGEMENT CALL 1 — WHEN the injection is delivered.
#   root_migration is detected on PostToolUse (err_sig only exists there), but
#   additionalContext only exists on PreToolUse. So the injection for a signal
#   found at the end of move N can only ride the front of move N+1. This file
#   therefore accepts the injection on ANY PreToolUse response in the session
#   rather than demanding a particular one. The plan's line about agents with no
#   before-edit hook ("enjeksiyon bir sonraki mümkün noktada verilir") points the
#   same way.
#
# JUDGEMENT CALL 2 — the exact ENVELOPE on stdout.
#   The plan fixes the channel ("PreToolUse additionalContext yolundan gider,
#   stdout'a değil") but not the JSON shape. Claude Code's documented shape is
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":…}}.
#   Claim 2a treats that as the full pass and a top-level "additionalContext" as
#   a pass with a note; anything that does not parse as a JSON object is red.
#
# JUDGEMENT CALL 3 — the name of the kill switch.
#   Claim 3 needs "injection on vs off" and the plan names no switch. This file
#   uses RABADON_INJECT=0, following RABADON_SIGNALS / RABADON_SEM / RABADON_MOVES.
#
# JUDGEMENT CALL 4 — the LANGUAGE of the injected text.
#   The plan quotes the certain-level stderr in Turkish ("suite kırmızı; kapıyı
#   değil kodu düzelt") and describes the injected text in Turkish without
#   quoting it. Since the injection is read by a model and the rest of the gate's
#   refusals are English, every content check here accepts either language.
#
# JUDGEMENT CALL 5 — what "the same signal" means for the cap of 2.
#   Read as: the same signal NAME within one session id. Claim 4 counts
#   injections mentioning the one error signature the fixture keeps producing,
#   which is the observable form of that from outside the binary.
