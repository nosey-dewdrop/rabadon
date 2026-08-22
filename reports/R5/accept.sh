#!/usr/bin/env bash
# R5 acceptance — the repair arm: policy gate, in-round trigger.
#
# WRITTEN BEFORE THE CODE and red on the day it is written.
#
# WHAT R5 IS NOT. It is not "build a repair arm". The controlled experiment
# already exists and works: native/repair.cpp clones the repo, hash-locks every
# test and harness file, lets a proposer edit the COPY, and re-runs the SAME
# check as the arbiter. native/repair_session_test.sh proves it catches a
# proposer that neuters a test. None of that is under test here.
#
# WHAT WAS MISSING WAS THE TRIGGER. Today a human has to type `rabadon repair`,
# and by the time a human notices, the error has already compounded through the
# next ten moves — which is the exact disease this product sells a cure for,
# left running inside the cure. R5 moves the trigger inside the round: R2's
# root_migration signal fires it, and only after the cheap remedy has already
# been tried and failed. The condition is BOTH halves:
#   the same error came out of a THIRD different move, AND
#   two injections did not help.
# One half is not enough. root_migration alone is a signal, not an emergency;
# spending a proposer call on the first sighting is spending the user's money on
# something an injection would have fixed for free. Claim 1's negative fixture
# sits exactly on that boundary: two injections spent, no third sighting yet, so
# nothing may run.
#
# CONSENT IS A POLICY, NOT A PROMPT. A tool that asks every time is a tool that
# gets answered "yes" without reading, and that is not consent. `rabadon init`
# sets it once:
#
#     repair.mode = ask | auto-propose | off
#
#   ask           one line at signal time; the arm runs only on approval.
#   auto-propose  for unattended/overnight runs. Runs WITHOUT asking, and
#                 NEVER TOUCHES THE USER'S TREE: the patch is held at
#                 .rabadon/repair-<ts>.patch and `rabadon repair --apply`
#                 applies it in the morning, by hand, once.
#   off           arm disabled; signals go to the ledger and nowhere else.
#
# CLAIM 3 IS THE ONE THAT MATTERS. auto-propose is the mode where nobody is
# watching, and it is the mode where a bug is unrecoverable: an agent that
# silently rewrites a sleeping developer's working tree has done the single
# worst thing this product could do, and no amount of "but the patch was
# correct" repairs the trust. So claim 3 does not check for the absence of a
# scary log line — it hashes the whole user tree before the run, hashes it after
# the run, and compares. Propose-and-hold either survives the hash or it is not
# a property, it is a hope.
#
# NO ASSERTION MAY PASS VACUOUSLY. "the proposer was never called" and "nothing
# ran at all" print the same on a green line, and off-mode/ask-mode are made
# entirely of that shape. So every negative here first requires proof that the
# fixture REACHED the escalation: a live spool, and a root_migration signal in
# it. If the session never escalated, the mode was never tested and the line is
# red, not green. Same guard on claim 3's hash comparison: an unchanged tree is
# worthless evidence if no proposer ever ran.
#
# ENFORCE, NOT WATCH. The sandbox touches $RABADON_DIR/enabled; without it the
# gate returns 0 to everything and the fixtures are driving a tool that is off.
#
# JUDGEMENT CALLS MADE HERE (the plan did not name these, and a later
# implementation is free to argue with them in its own commit):
#   - the policy lives at $RABADON_DIR/config.json as {"repair":{"mode":...}},
#     because it is a rabadon-home policy set once by `rabadon init`, not a
#     per-project guard rule (.rabadon/guard.json is the project's rule file).
#   - approval in ask mode is `rabadon-repair --approve`; the plan says "runs on
#     approval" without naming the door.
#   - the proposer call is witnessed TWICE: on the ledger (claim 2 demands the
#     ledger proof) and by a fake proposer binary via RABADON_CLAUDE_BIN, the
#     same fake-proposer door native/repair_session_test.sh already uses. No
#     network, no real model call, no cost.

set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

GATE="$ROOT/native/rabadon-gate"
REPAIR="$ROOT/native/rabadon-repair"

PASS_N=0; FAIL_N=0; C1_FAIL=0
pass() { printf 'PASS  %s\n' "$1"; PASS_N=$((PASS_N + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL_N=$((FAIL_N + 1)); }
note() { printf '      %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

[ -x "$GATE" ]   || { printf 'FAIL  no gate binary — run make first\n'; exit 1; }
[ -x "$REPAIR" ] || { printf 'FAIL  no rabadon-repair binary — run make first\n'; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL  python3 required\n'; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rbr5.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

# ---------------------------------------------------------------------------
# THE FAKE PROPOSER. One script, set through RABADON_CLAUDE_BIN — the same door
# native/repair_session_test.sh uses. It records that it was called, records the
# EXACT text it was handed (claim 5 reads that file and nothing else), and then
# fixes the source in its cwd, which is the work copy, never the user's tree.
# The sleep clears drill.h's minimum-proposer-latency floor; a proposer that
# returns instantly is treated as a stub.
CALLS="$WORK/proposer.calls"
PROMPT="$WORK/proposer.prompt"
FAKE="$WORK/bin/claude"
mkdir -p "$WORK/bin"
cat > "$FAKE" <<EOF
#!/usr/bin/env bash
printf 'call\n' >> "$CALLS"
printf '%s\0' "\$@" > "$PROMPT"
sleep 2.5
if [ -f src/calc.py ]; then
  printf 'def add(a, b):\n    return a + b\n' > src/calc.py
fi
echo done
EOF
chmod +x "$FAKE"

reset_proposer() { : > "$CALLS"; : > "$PROMPT"; }
proposer_calls_fs() {
  local n=0
  [ -f "$CALLS" ] && n="$(grep -c 'call' "$CALLS" 2>/dev/null)"
  case "${n:-0}" in ''|*[!0-9]*) n=0;; esac
  printf '%s' "$n"
}

# ---------------------------------------------------------------------------
# One sandbox per fixture: its own HOME, its own spool, its own project. A
# question about "did this fire" is always a question about ONE session.
#
# The project is a real, really-red, dependency-free check: check.sh exits 1 and
# its output carries a line number, which claim 5 needs — a text that is just
# the arbiter's raw output pasted through would carry that number with it.
NEW_HOME=""; NEW_PROJ=""
sandbox() { # sandbox <repair-mode>
  NEW_HOME="$(mktemp -d "$WORK/h.XXXXXX")"
  NEW_PROJ="$(mktemp -d "$WORK/p.XXXXXX")"
  mkdir -p "$NEW_HOME/.rabadon/spool" "$NEW_PROJ/.git" "$NEW_PROJ/src" "$NEW_PROJ/tests"
  printf 'ref: refs/heads/main\n' > "$NEW_PROJ/.git/HEAD"
  : > "$NEW_HOME/.rabadon/enabled"          # enforce, not watch
  printf 'def add(a, b):\n    return a - b\n' > "$NEW_PROJ/src/calc.py"
  printf 'import sys; sys.path.insert(0, "src")\nfrom calc import add\nassert add(2, 2) == 4, "TypeError: add is wrong"\nprint("ok")\n' \
    > "$NEW_PROJ/tests/test_calc.py"
  printf '#!/bin/sh\nexec python3 tests/test_calc.py\n' > "$NEW_PROJ/check.sh"
  chmod +x "$NEW_PROJ/check.sh"
  # the policy `rabadon init` is supposed to write, and the check the trigger is
  # supposed to run once it fires.
  printf '{"repair":{"mode":"%s","check":"sh check.sh"}}\n' "$1" > "$NEW_HOME/.rabadon/config.json"
  reset_proposer
}

# ev <hook> <tool> <session> <json-tool-input> [tool_response]
ev() {
  local hook="$1" tool="$2" sid="$3" input="$4" resp="${5:-}"
  local j
  j="$(printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":%s' \
        "$hook" "$sid" "$NEW_PROJ" "$tool" "$input")"
  [ -n "$resp" ] && j="$j,\"tool_response\":$(jstr "$resp")"
  j="$j}"
  printf '%s' "$j" | env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" RABADON_NOTIFY=0 \
    RABADON_CLAUDE_BIN="$FAKE" PATH="$WORK/bin:$PATH" "$GATE" 2>/dev/null
}
bash_pre()  { ev PreToolUse  Bash "$1" "{\"command\":$(jstr "$2")}" >/dev/null; }
bash_post() { ev PostToolUse Bash "$1" "{\"command\":$(jstr "$2")}" "$3" >/dev/null; }
ran_bad()   { bash_pre "$1" "$2"; bash_post "$1" "$2" "$3"; }

# THE ERROR. One string, unchanged, out of every command — that sameness is what
# root_migration reads, and the line number in it is claim 5's tripwire.
ERR='Traceback (most recent call last):
  File "tests/test_calc.py", line 3, in <module>
AssertionError: TypeError: add is wrong'

# one root-migration cycle: the SAME error out of three DIFFERENT moves.
cycle() { # cycle <sid> <n>
  ran_bad "$1" "sh check.sh            # try $2" "$ERR"
  ran_bad "$1" "python3 tests/test_calc.py # try $2" "$ERR"
  ran_bad "$1" "python3 -c 'import calc'   # try $2" "$ERR"
}

# ---------------------------------------------------------------------------
# READING THE LEDGER. The spool is the only place a silent arm is allowed to
# leave a trace, so it is the only place these assertions look.

evs() { # every ev name in this sandbox's spool
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
out = []
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        out.append(str(e.get("ev") or ""))
print(" ".join(sorted(set(out))))
PY
}

# THE VACUITY GUARD: total ledger lines of any kind. Zero means the gate never
# saw the fixture, and every negative below would be green for a reason that has
# nothing to do with the repair arm.
nevents() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import os, sys, glob
n = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        if line.strip(): n += 1
print(n)
PY
}

signals() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
out = []
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        if e.get("ev") == "SIGNAL":
            out.append(str(e.get("signal") or e.get("name") or "?"))
print(" ".join(sorted(set(out))))
PY
}

# how many injections this session actually spent. The trigger's second half is
# "two injections did not help", so the count has to be readable, not assumed.
n_inject() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
n = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        if str(e.get("ev") or "").startswith("INJECT"): n += 1
print(n)
PY
}

# every ledger line the repair arm owns: REPAIR_*, or any line naming the arm.
n_repair_ev() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
n = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        if str(e.get("ev") or "").upper().startswith("REPAIR"): n += 1
print(n)
PY
}

# PROPOSER CALLS, FROM THE LEDGER. Claim 2 says "prove it from the ledger", and
# it means it: a proposer call that the ledger cannot account for is a model
# call the user cannot audit, which is worse than the call itself.
n_proposer_ledger() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
n = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        ev = str(e.get("ev") or "").upper()
        if ev in ("REPAIR_START", "PROPOSER_CALL", "PROPOSER"): n += 1
        elif "proposer" in json.dumps(e).lower() and ev.startswith("REPAIR"): n += 1
print(n)
PY
}

# the ask-mode record: the one line that was put in front of the user, on the
# ledger. Its presence is what makes "no proposer call" a fact about the mode
# rather than a fact about a session that never escalated.
n_ask_ev() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
n = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        blob = json.dumps(e).lower()
        ev = str(e.get("ev") or "").upper()
        if "repair" in blob and ("ask" in ev.lower() or e.get("mode") == "ask"
                                 or "await" in blob or "approval" in blob):
            n += 1
print(n)
PY
}

# Yasa 6: the tokens the repair arm spent, banked on the ledger as a COST. A
# model call whose price never reaches the counter makes the counter a
# advertisement, not a measurement.
repair_cost_tokens() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
best = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        blob = json.dumps(e).lower()
        if "repair" not in blob: continue
        if str(e.get("ev") or "").upper() != "COST" and "cost" not in blob: continue
        for k in ("tokens", "total_tokens", "input_tokens", "output_tokens",
                  "tokens_in", "tokens_out", "usd_e6"):
            v = e.get(k)
            if isinstance(v, (int, float)) and v > best: best = v
        c = e.get("cost")
        if isinstance(c, dict):
            for v in c.values():
                if isinstance(v, (int, float)) and v > best: best = v
print(int(best))
PY
}

# THE USER TREE HASH. Claim 3's whole weight sits on this function: a digest
# over every path and every byte the user owns. Three things are excluded and
# each exclusion is a hole, so each one is argued:
#   .rabadon/       rabadon's own drawer, and where the held patch is supposed
#                   to land. Hashing it would make claim 3 fail for the arm
#                   doing exactly what it is told.
#   __pycache__/, .pytest_cache/, *.pyc
#                   the interpreter's litter. MEASURED, not assumed: the gate
#                   runs the project's own check, and python drops these on the
#                   way through — they moved this hash before anything named
#                   repair existed. A red for those is a red about CPython.
# Everything else is the user's, source included, and none of it may move. A
# patch that edits src/calc.py is still caught: that file is hashed.
tree_hash() {
  python3 - "$NEW_PROJ" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
SKIP_DIRS = {".rabadon", "__pycache__", ".pytest_cache"}
h = hashlib.sha256()
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
    for name in sorted(filenames):
        if name.endswith(".pyc"): continue
        p = os.path.join(dirpath, name)
        rel = os.path.relpath(p, root)
        h.update(rel.encode() + b"\0")
        try:
            with open(p, "rb") as fh: h.update(fh.read())
        except OSError:
            h.update(b"<unreadable>")
        h.update(b"\0")
print(h.hexdigest())
PY
}

held_patch() { ls "$NEW_PROJ"/.rabadon/repair-*.patch "$NEW_HOME"/.rabadon/repair-*.patch 2>/dev/null | head -1; }

live()      { local n; n="$(nevents)"; case "${n:-0}" in ''|*[!0-9]*|0) return 1;; *) return 0;; esac; }
escalated() { case " $(signals) " in *" root_migration "*) return 0;; *) return 1;; esac; }

# ===========================================================================
head_ "CLAIM 1 — the trigger is the third sighting AFTER two injections, and only that"

# POSITIVE. Three cycles: cycle 1 and cycle 2 each earn an injection, and by
# cycle 3 the cheap remedy has demonstrably not worked — the same error is still
# coming out of new moves. That is the moment repair is worth a model call, and
# not one move earlier.
sandbox auto-propose
cycle s-fire 1
cycle s-fire 2
cycle s-fire 3
FIRE_INJ="$(n_inject)"; FIRE_REP="$(n_repair_ev)"; FIRE_PROP="$(proposer_calls_fs)"
if ! live; then
  fail "1a the spool is empty — the gate never saw the fixture, nothing below this line was tested"
elif ! escalated; then
  fail "1a root_migration never fired on three cycles of one error through nine different moves — fired: [$(signals)]"
  note "the trigger cannot be tested until the signal it hangs off exists"
elif [ "${FIRE_REP:-0}" -gt 0 ] || [ "${FIRE_PROP:-0}" -gt 0 ]; then
  pass "1a root_migration after 2 injections produced a repair run (repair events: $FIRE_REP, proposer calls: $FIRE_PROP)"
else
  fail "1a root_migration fired with $FIRE_INJ injections spent and the repair arm never ran — ledger: [$(evs)]"
  note "this is the gap R5 exists to close: the experiment works, nothing starts it"
fi

# NEGATIVE, ON THE BOUNDARY. Two cycles: both injections spent, no third
# sighting. Everything the trigger needs except the half that says the cheap
# remedy has run out of road. If this fires, the arm spends a model call on a
# problem an injection was still in the middle of fixing, and the user pays for
# rabadon's impatience.
sandbox auto-propose
cycle s-quiet 1
cycle s-quiet 2
Q_REP="$(n_repair_ev)"; Q_PROP="$(proposer_calls_fs)"
if ! live; then
  fail "1b the spool is empty — nothing ran, so nothing was held back"
elif [ "${Q_REP:-0}" -eq 0 ] && [ "${Q_PROP:-0}" -eq 0 ]; then
  pass "1b two injections and no third sighting starts nothing"
else
  fail "1b the arm ran too early: repair events $Q_REP, proposer calls $Q_PROP"
  note "an arm that fires on the first sighting is an arm that bills for what an injection does free"
fi

C1_FAIL="$FAIL_N"

# ===========================================================================
head_ "CLAIM 2 — ask mode: not one proposer call without approval, proved from the ledger"

# The escalation is driven to the exact point where auto-propose would have run.
# The difference between this fixture and claim 1's positive is one word in the
# config, so if this goes green while claim 1 is green, the policy is real.
sandbox ask
cycle s-ask 1
cycle s-ask 2
cycle s-ask 3
ASK_PROP_L="$(n_proposer_ledger)"; ASK_PROP_F="$(proposer_calls_fs)"; ASK_ASK="$(n_ask_ev)"
if ! live || ! escalated; then
  fail "2a the ask fixture never escalated — 'no proposer call' proves nothing here; signals: [$(signals)]"
elif [ "${ASK_ASK:-0}" -eq 0 ]; then
  fail "2a ask mode left no record of having asked — ledger: [$(evs)]"
  note "silence is not a question; an ask nobody can audit is an arm that simply did not run"
elif [ "${ASK_PROP_L:-0}" -eq 0 ] && [ "${ASK_PROP_F:-0}" -eq 0 ]; then
  pass "2a ask mode escalated, asked, and called no proposer while unanswered"
else
  fail "2a ask mode called the proposer with no answer given (ledger: $ASK_PROP_L, actual: $ASK_PROP_F)"
  note "a consent gate that runs before the answer is a consent gate in name only"
fi

# and the other half of the word 'ask': an approved arm actually runs. A gate
# that never opens is not consent either, it is `off` wearing a costume.
if command -v true >/dev/null && [ -x "$REPAIR" ]; then
  env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" RABADON_CLAUDE_BIN="$FAKE" \
    "$REPAIR" --approve "$NEW_PROJ" >/dev/null 2>&1
  A_PROP="$(proposer_calls_fs)"
  if [ "${A_PROP:-0}" -gt 0 ]; then
    pass "2b ask mode runs once approval is given"
  else
    fail "2b approval did not start the arm — no proposer call after --approve"
  fi
fi

# ===========================================================================
head_ "CLAIM 3 — auto-propose runs, AND the user's tree is byte-identical afterwards"

# THE ASSERTION THAT MATTERS MOST. Nobody is watching in this mode. The hash is
# taken before anything runs and after everything has finished; the patch is
# expected to exist and to be waiting, unapplied.
sandbox auto-propose
H_BEFORE="$(tree_hash)"
cycle s-auto 1
cycle s-auto 2
cycle s-auto 3
# give a background arm a chance to finish before the tree is read again; a hash
# taken while the arm is mid-flight would clear a tree that is about to change.
sleep 6
H_AFTER="$(tree_hash)"
AUTO_PROP_L="$(n_proposer_ledger)"; AUTO_PROP_F="$(proposer_calls_fs)"; PATCH="$(held_patch)"

if [ "${AUTO_PROP_F:-0}" -gt 0 ] || [ "${AUTO_PROP_L:-0}" -gt 0 ]; then
  pass "3a auto-propose called the proposer without asking (ledger: $AUTO_PROP_L, actual: $AUTO_PROP_F)"
else
  fail "3a auto-propose never called the proposer — ledger: [$(evs)]"
fi

if [ "${AUTO_PROP_F:-0}" -eq 0 ] && [ "${AUTO_PROP_L:-0}" -eq 0 ]; then
  fail "3b the tree hash proves NOTHING this run — no proposer ever ran, so an unchanged tree is just an idle tree"
  note "this is the vacuity trap in the most important assertion in R5: propose-and-hold"
  note "is only a property if something actually proposed."
elif [ "$H_BEFORE" = "$H_AFTER" ]; then
  pass "3b the user's tree is byte-identical across a full unattended repair run"
else
  fail "3b THE USER'S TREE CHANGED during an unattended run: $H_BEFORE -> $H_AFTER"
  note "this is the worst failure this product has: an agent editing a sleeping developer's"
  note "working tree. A correct patch does not repair the trust that costs."
fi

if [ "${AUTO_PROP_F:-0}" -eq 0 ] && [ "${AUTO_PROP_L:-0}" -eq 0 ]; then
  fail "3c no patch was held because nothing ran — the hold is untested this run"
elif [ -n "$PATCH" ]; then
  pass "3c the fix is waiting as a patch, not applied ($(basename "$PATCH"))"
else
  fail "3c the arm ran and left no .rabadon/repair-<ts>.patch — the morning command has nothing to apply"
fi

# ===========================================================================
head_ "CLAIM 4 — off mode: the arm is not there"

sandbox off
cycle s-off 1
cycle s-off 2
cycle s-off 3
OFF_PROP_L="$(n_proposer_ledger)"; OFF_PROP_F="$(proposer_calls_fs)"; OFF_REP="$(n_repair_ev)"
if ! live || ! escalated; then
  fail "4a the off fixture never escalated — an arm that was never reached was never proved off; signals: [$(signals)]"
elif [ "${OFF_PROP_L:-0}" -eq 0 ] && [ "${OFF_PROP_F:-0}" -eq 0 ] && [ "${OFF_REP:-0}" -eq 0 ]; then
  pass "4a off mode escalated to the trigger and the proposer was never called"
else
  fail "4a off mode ran the arm anyway (ledger proposer: $OFF_PROP_L, actual: $OFF_PROP_F, repair events: $OFF_REP)"
  note "off has to mean off, or no one will ever believe any of the other two settings"
fi

# off is not mute. The signals still have to reach the ledger, or turning the arm
# off quietly turns the detectors off too and the counter loses a session.
if escalated; then
  pass "4b off mode still writes the signals to the ledger"
else
  fail "4b off mode swallowed the signals as well as the arm — signals: [$(signals)]"
fi

# ===========================================================================
head_ "CLAIM 5 — the text handed to the proposer obeys Yasa 2"

# The fixture's error output carries `line 3` on purpose. A prompt built by
# pasting the arbiter's raw tail through carries that number with it, and a line
# number is a claim about WHERE the fix goes — a claim rabadon has not earned and
# has no way to check. File-level context is what it is allowed to say.
if [ ! -s "$PROMPT" ]; then
  fail "5a no proposer text was captured — the arm never handed anything to a proposer"
  fail "5b no proposer text to check for line numbers"
  fail "5c no proposer text to check against the arbiter's raw output"
else
  PTXT="$(tr '\0' '\n' < "$PROMPT")"
  if printf '%s' "$PTXT" | grep -qE 'src/calc\.py|tests/test_calc\.py|check\.sh'; then
    pass "5a the proposer text names the files in play"
  else
    fail "5a the proposer text carries no file-level context at all"
  fi

  if printf '%s' "$PTXT" | grep -qEi ':[0-9]+:|[[:space:]]line[[:space:]]+[0-9]+'; then
    fail "5b the proposer text carries a line number (Yasa 2): [$(printf '%s' "$PTXT" | grep -oEi ':[0-9]+:|[[:space:]]line[[:space:]]+[0-9]+' | head -3 | tr '\n' ' ')]"
    note "a line number is a claim about where the bug is; rabadon knows where the ERROR"
    note "surfaced, which is a different fact, and shipping one as the other is a guess in a"
    note "guard tool's voice."
  else
    pass "5b the proposer text carries no line number"
  fi

  # 'the arbiter's raw output is not passed alone': the raw tail may be in there,
  # but it may not BE the message. Strip every line of the raw error and what is
  # left has to still be rabadon's own framing.
  REST="$(printf '%s\n' "$PTXT" | grep -vxF -f <(printf '%s\n' "$ERR") | tr -d '[:space:]')"
  if [ "${#REST}" -gt 40 ]; then
    pass "5c the arbiter's raw output is framed, not forwarded on its own"
  else
    fail "5c the proposer got the arbiter's raw output and essentially nothing else"
  fi
fi

# ===========================================================================
head_ "CLAIM 6 — Yasa 6: what the arm spends is measured and banked as a COST"

# rabadon sells "we save you money". An arm that makes its own model calls and
# never books them turns that sentence into an advertisement. The repair call is
# the one place rabadon spends tokens, so it is the one place the counter can be
# caught lying.
TOK="$(repair_cost_tokens)"
if [ "${AUTO_PROP_F:-0}" -eq 0 ] && [ "${AUTO_PROP_L:-0}" -eq 0 ]; then
  fail "6a no repair call was ever made, so no cost could be measured — untested this run"
elif [ "${TOK:-0}" -gt 0 ] 2>/dev/null; then
  pass "6a the repair arm's spend reached the ledger as a COST ($TOK)"
else
  fail "6a the arm made a model call and booked no cost — ledger: [$(evs)]"
  note "a counter that omits its own expenses is not a counter"
fi

if [ "${TOK:-0}" -gt 0 ] 2>/dev/null; then
  pass "6b the cost is a number, not a flag"
else
  fail "6b no measured token figure attributable to the repair arm"
fi

# ===========================================================================
head_ "CLAIM 7 — nothing that was green yesterday is red today"

# R5 adds a trigger into the gate's signal path and a policy read into the repair
# binary. Both sit on top of shipped, verified behaviour. A round that buys its
# own acceptance by moving something underneath it has not built anything.
regress() { # regress <label> <script> <expected-pattern>
  local label="$1" script="$2" want="$3" out
  out="$("$script" 2>&1)"
  if printf '%s' "$out" | grep -qE "$want"; then
    pass "7 no regression: $label"
  else
    fail "7 REGRESSION in $label — expected /$want/, got: [$(printf '%s' "$out" | tail -1)]"
  fi
}
regress "native/moves_test.sh 21/0"     "$ROOT/native/moves_test.sh"     '21 passed, 0 failed'
regress "native/signals_test.sh 39/0"   "$ROOT/native/signals_test.sh"   '39 passed, 0 failed'
regress "reports/R2/accept.sh 19 green" "$ROOT/reports/R2/accept.sh"     '19 green, 0 red'
regress "reports/R3/accept.sh 14 green" "$ROOT/reports/R3/accept.sh"     '14 green, 0 red'

# ===========================================================================
printf '\n== R5 acceptance: %d green, %d red\n' "$PASS_N" "$FAIL_N"
if [ "$C1_FAIL" -gt 0 ]; then
  printf '      NOTE: claim 1 had %d red, so claims 2-6 proved nothing this run —\n' "$C1_FAIL"
  printf '      a trigger that never fires cannot be gated by a policy, cannot call a\n'
  printf '      proposer, cannot spare a tree it never reached, and cannot spend a token.\n'
fi
[ "$FAIL_N" -gt 0 ] && { printf 'R5 NOT ACCEPTED\n'; exit 1; }
printf 'R5 ACCEPTED\n'
exit 0
