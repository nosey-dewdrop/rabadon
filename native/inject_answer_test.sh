#!/usr/bin/env bash
# inject_answer_test.sh — CAN THE LEDGER STILL ANSWER "DID THE AGENT READ IT?"
# AFTER THE MOVE RING HAS ROLLED OVER ITSELF.
#
# WHY THIS FILE EXISTS, WITH THE NUMBER THAT PUT IT HERE.
# KOSU-RABADON-5.md §F3's acceptance has three layers and the second one is
# "(b) did the agent read it": the signature of the first move AFTER an
# injection must differ from the signature that was repeating BEFORE it. Two
# phases in a row delivered 0% of that layer, and the reason was measured in
# F3b rather than guessed:
#
#   - the ledger held 7 INJECT lines and the number of them that could be
#     JUDGED was 0;
#   - the INJECT line carried `mseq` (which move it rode on) but the move
#     itself — and every move after it — lived only in the 200-slot ring in
#     native/moves.h;
#   - 39 rings on that machine, 2 had rolled past CAP=200. Both of those two
#     were the rings that carried an injection. 2 of 2, not 2 of 39: the loss
#     is SELECTIVE, because a signal is born in a long session and a long
#     session is exactly the one that rolls its ring. The evidence is deleted
#     precisely where it is produced;
#   - `grep -ln INJECT native/*_test.sh` answered 0. Nothing drove an injection
#     end to end, so (b) was not measured in a fixture either.
#
# So the fix is not a bigger CAP. Raising CAP postpones the loss and calls it a
# repair. The fix is that the two facts (b) needs stop living in a ring at all:
#
#   1. INJECT carries `psig` — the signature that was repeating when the
#      diagnosis was assembled. Written at queue time, not reconstructed later.
#   2. A new event, INJECT_ANSWER, is written on the first move that happens
#      AFTER the injection was handed over, carrying that move's `sig`, the
#      `psig` it is being compared against, and `same`.
#
# Both go into the spool, which is append-only and hash-chained. Once they are
# there, (b) is a question about two ledger lines and the ring can roll as
# often as it likes.
#
# WHAT THIS SUITE REFUSES TO ACCEPT.
#   - `same` hardwired either way. Section 4 drives the agent REPEATING itself
#     after the injection and requires same=true. A field that is always false
#     proves nothing about the agent, it only proves the field exists.
#   - a green that never ran. Every section first requires the spool to be
#     non-empty AND the injection to have been physically handed over on
#     stdout as additionalContext. "nothing fired" and "nothing ran" print the
#     same on a green line (the vacuity bug moves_test.sh and R2/accept.sh each
#     shipped once).
#   - an answer that only survives a short session. Section 3 pushes the ring
#     PAST CAP=200 after the injection, proves from the ring header that it
#     really rolled and that mseq is really gone from it, and then asks the
#     same question again off the ledger alone.
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"

FAIL=0
PASSN=0
pass() { printf '  ok   - %s\n' "$1"; PASSN=$((PASSN + 1)); }
fail() { printf '  FAIL - %s\n' "$1"; FAIL=1; }
head_() { printf '%s\n' "inject-answer: $1"; }

[ -x "$GATE" ] || { printf 'inject-answer: no gate binary at %s — run make first\n' "$GATE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'inject-answer: python3 is required to read the spool\n' >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rbinja.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

# One sandbox per fixture. Sessions never share a spool, so every question
# below is a question about ONE session's own events.
NEW_HOME=""; NEW_PROJ=""
sandbox() {
  NEW_HOME="$(mktemp -d "$WORK/h.XXXXXX")"
  NEW_PROJ="$(mktemp -d "$WORK/p.XXXXXX")"
  mkdir -p "$NEW_HOME/.rabadon/spool" "$NEW_PROJ/.git" "$NEW_PROJ/src"
  printf 'ref: refs/heads/main\n' > "$NEW_PROJ/.git/HEAD"
  : > "$NEW_HOME/.rabadon/enabled"
}

# ev <hook> <tool> <session> <json-tool-input>  -> stdout of the gate
ev() {
  printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":%s}' \
    "$1" "$3" "$NEW_PROJ" "$2" "$4" \
  | env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" RABADON_NOTIFY=0 "$GATE" 2>/dev/null
}

# an Edit PreToolUse. $2 = path under the project, $3 = new text.
edit_pre() { ev PreToolUse Edit "$1" "{\"file_path\":$(jstr "$NEW_PROJ/$2"),\"old_string\":\"\",\"new_string\":$(jstr "$3")}"; }
# the same, with the JSON built inline — no python3 per call, because section 3
# runs this two hundred times and a 30 ms interpreter start each way is the
# whole runtime of the suite.
edit_pre_fast() { ev PreToolUse Edit "$1" "{\"file_path\":\"$NEW_PROJ/$2\",\"old_string\":\"\",\"new_string\":\"$3\"}"; }

# --- reading the ledger -----------------------------------------------------
# ledger_field <ev> <field>  -> that field of the FIRST event of that kind
ledger_field() {
  python3 - "$NEW_HOME/.rabadon/spool" "$1" "$2" <<'PY'
import json, os, sys, glob
want_ev, want_f = sys.argv[2], sys.argv[3]
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.jsonl"))):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        if e.get("ev") == want_ev and want_f in e:
            v = e[want_f]
            print("true" if v is True else "false" if v is False else v)
            sys.exit(0)
PY
}
ledger_count() {
  python3 - "$NEW_HOME/.rabadon/spool" "$1" <<'PY'
import json, os, sys, glob
n = 0
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.jsonl"))):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        if e.get("ev") == sys.argv[2]: n += 1
print(n)
PY
}
nevents() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import os, sys, glob
n = 0
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.jsonl"))):
    for line in open(f):
        if line.strip(): n += 1
print(n)
PY
}
# the ring header: "RBMV1" magic, then count (total ever appended) and nextSeq.
ring_count() {
  python3 - "$NEW_PROJ/.rabadon/sessions" <<'PY'
import os, struct, sys, glob
best = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.moves.bin")):
    with open(f, "rb") as fh:
        h = fh.read(24)
    if len(h) < 24 or not h.startswith(b"RBMV1"): continue
    best = max(best, struct.unpack("<q", h[8:16])[0])
print(best)
PY
}

# THE VACUITY GUARD, both halves. An empty spool means the gate never saw the
# fixture; a delivery that never happened means there is no injection to judge.
live() { local n; n="$(nevents)"; case "$n" in ''|*[!0-9]*) return 1;; 0) return 1;; *) return 0;; esac; }
delivered() { case "$1" in *additionalContext*) return 0;; *) return 1;; esac; }

# drive_to_injection <session> -> echoes the stdout of the carrier event
# Six alternating edits to ONE file is native/signals_test.sh's oscillation
# fixture; the sixth QUEUES the diagnosis (it can never speak on the event it
# fired on) and the seventh — the carrier — is where it is handed over.
# psig is therefore the signature of the SIXTH move: `const timeout = 5000;`
# on src/app.js, the content that was repeating when the pattern completed.
drive_to_injection() {
  local sid="$1"
  local i
  for i in 1 2 3; do
    edit_pre "$sid" src/app.js 'const timeout = 500;'  >/dev/null
    edit_pre "$sid" src/app.js 'const timeout = 5000;' >/dev/null
  done
  edit_pre "$sid" src/carrier.js 'const carrier = 1;'
}

# ===========================================================================
head_ "1. INJECT carries the signature it is about, on the line itself"

sandbox
OUT="$(drive_to_injection s1)"
if ! live; then fail "the spool is empty — the gate never saw the fixture"
elif ! delivered "$OUT"; then fail "no injection was handed over; the rest of this section would be vacuous"
else
  pass "the injection reached the agent (additionalContext on stdout)"
  [ "$(ledger_count INJECT)" = "1" ] && pass "exactly one INJECT on the ledger" \
    || fail "expected 1 INJECT, ledger has $(ledger_count INJECT)"
  PSIG="$(ledger_field INJECT psig)"
  case "$PSIG" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
      pass "INJECT carries psig, a 16-hex signature ($PSIG)";;
    "") fail "INJECT has no psig field — (b) cannot be judged once the ring rolls";;
    *)  fail "INJECT psig is not a signature: '$PSIG'";;
  esac
  MSEQ="$(ledger_field INJECT mseq)"
  case "$MSEQ" in ''|*[!0-9]*) fail "INJECT mseq is not a move seq: '$MSEQ'";;
                  *) pass "INJECT still carries mseq ($MSEQ)";; esac
fi

# ===========================================================================
head_ "2. INJECT_ANSWER — the first move after the injection, on the ledger"

sandbox
OUT="$(drive_to_injection s2)"
# the answer: a different file, different content. The agent moved on.
edit_pre s2 src/other.js 'const other = 2;' >/dev/null
if ! delivered "$OUT"; then fail "section 2 is vacuous — nothing was injected"
else
  [ "$(ledger_count INJECT_ANSWER)" = "1" ] && pass "one INJECT_ANSWER after one injection" \
    || fail "expected 1 INJECT_ANSWER, ledger has $(ledger_count INJECT_ANSWER)"
  A_PSIG="$(ledger_field INJECT_ANSWER psig)"
  A_SIG="$(ledger_field INJECT_ANSWER sig)"
  A_SAME="$(ledger_field INJECT_ANSWER same)"
  I_PSIG="$(ledger_field INJECT psig)"
  [ -n "$A_PSIG" ] && [ "$A_PSIG" = "$I_PSIG" ] \
    && pass "INJECT_ANSWER quotes the same psig as its INJECT" \
    || fail "INJECT_ANSWER psig '$A_PSIG' does not match INJECT psig '$I_PSIG'"
  [ -n "$A_SIG" ] && [ "$A_SIG" != "$A_PSIG" ] \
    && pass "the answering move has its own signature ($A_SIG)" \
    || fail "INJECT_ANSWER sig is missing or equal to psig: '$A_SIG'"
  [ "$A_SAME" = "false" ] && pass "same=false — the agent did NOT repeat itself" \
    || fail "expected same=false on a changed move, got '$A_SAME'"
  A_MSEQ="$(ledger_field INJECT_ANSWER mseq)"
  I_MSEQ="$(ledger_field INJECT mseq)"
  if [ -n "$A_MSEQ" ] && [ -n "$I_MSEQ" ] && [ "$A_MSEQ" -gt "$I_MSEQ" ] 2>/dev/null; then
    pass "the answer is a LATER move than the one the injection rode on ($A_MSEQ > $I_MSEQ)"
  else
    fail "INJECT_ANSWER mseq '$A_MSEQ' is not after INJECT mseq '$I_MSEQ'"
  fi
fi

# ===========================================================================
head_ "3. the ring rolls past CAP=200 and (b) is STILL answerable"
#
# This is the whole point of the card. The ring keeps 200 moves; a session that
# produces a signal is a long session. So: inject, then bury the injection under
# more than 200 further moves, prove from the ring header that it rolled and
# that mseq is no longer in it, and ask (b) again off the ledger alone.

sandbox
OUT="$(drive_to_injection s3)"
edit_pre s3 src/other.js 'const other = 2;' >/dev/null   # the answer
i=0
while [ $i -lt 210 ]; do
  edit_pre_fast s3 "src/f$i.js" "const v = $i;" >/dev/null
  i=$((i + 1))
done
RING="$(ring_count)"
I_MSEQ="$(ledger_field INJECT mseq)"
if ! delivered "$OUT"; then fail "section 3 is vacuous — nothing was injected"
elif [ -z "$RING" ] || [ "$RING" -le 200 ] 2>/dev/null; then
  fail "the ring did not roll (header count $RING <= CAP 200) — this section proves nothing"
else
  pass "the ring rolled: header counts $RING moves, CAP is 200"
  # the injected move is gone from the ring: the oldest seq still held is
  # count-200, and mseq is below it.
  OLDEST=$((RING - 200))
  if [ -n "$I_MSEQ" ] && [ "$I_MSEQ" -lt "$OLDEST" ] 2>/dev/null; then
    pass "the move the injection rode on (seq $I_MSEQ) has been evicted (oldest held: $OLDEST)"
  else
    fail "mseq $I_MSEQ is still inside the ring (oldest held $OLDEST) — the loss was not reproduced"
  fi
  [ "$(ledger_count INJECT_ANSWER)" = "1" ] \
    && pass "exactly one INJECT_ANSWER survives — later moves do not re-answer" \
    || fail "expected 1 INJECT_ANSWER after 210 further moves, got $(ledger_count INJECT_ANSWER)"
  A_PSIG="$(ledger_field INJECT_ANSWER psig)"
  A_SIG="$(ledger_field INJECT_ANSWER sig)"
  A_SAME="$(ledger_field INJECT_ANSWER same)"
  if [ -n "$A_PSIG" ] && [ -n "$A_SIG" ] && [ "$A_SAME" = "false" ]; then
    pass "(b) is answerable from the ledger with the ring rolled: $A_PSIG -> $A_SIG, same=false"
  else
    fail "(b) is NOT answerable after the roll: psig='$A_PSIG' sig='$A_SIG' same='$A_SAME'"
  fi
fi

# ===========================================================================
head_ "4. same=true when the agent repeats itself — the field is not hardwired"

sandbox
OUT="$(drive_to_injection s4)"
# the answer repeats EXACTLY the content that was repeating before: same file,
# same text, therefore the same tier-0 signature. This is what "the message did
# not reach the agent, or was read as noise" looks like in the record.
edit_pre s4 src/app.js 'const timeout = 5000;' >/dev/null
if ! delivered "$OUT"; then fail "section 4 is vacuous — nothing was injected"
else
  A_SIG="$(ledger_field INJECT_ANSWER sig)"
  A_PSIG="$(ledger_field INJECT_ANSWER psig)"
  A_SAME="$(ledger_field INJECT_ANSWER same)"
  [ -n "$A_SIG" ] && [ "$A_SIG" = "$A_PSIG" ] \
    && pass "the repeated move hashes back to psig ($A_SIG)" \
    || fail "expected the repeated move to carry psig, got sig='$A_SIG' psig='$A_PSIG'"
  [ "$A_SAME" = "true" ] \
    && pass "same=true — the ledger says the injection did not change the next move" \
    || fail "expected same=true when the agent repeats itself, got '$A_SAME'"
fi

# ===========================================================================
head_ "5. no injection, no answer"
# INJECT_ANSWER must be a fact about an injection, not about any move. A session
# that never got one must not produce one, or every (b) number is inflated by
# sessions rabadon never spoke to.

sandbox
edit_pre s5 src/app.js 'const a = 1;' >/dev/null
edit_pre s5 src/b.js    'const b = 2;' >/dev/null
if ! live; then fail "section 5 is vacuous — the spool is empty"
else
  [ "$(ledger_count INJECT)" = "0" ] && [ "$(ledger_count INJECT_ANSWER)" = "0" ] \
    && pass "a session with no injection writes no INJECT_ANSWER" \
    || fail "an un-injected session wrote INJECT=$(ledger_count INJECT) INJECT_ANSWER=$(ledger_count INJECT_ANSWER)"
fi

printf 'inject-answer: %d passed, %d failed\n' "$PASSN" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
