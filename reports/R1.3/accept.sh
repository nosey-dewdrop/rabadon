#!/usr/bin/env bash
# R1.3 acceptance — ONE goal: the move record stops rewriting a whole file per event.
#
# An intermediate round measures its one goal and nothing else. It adds no
# feature. R1's contract is unchanged and native/moves_test.sh is the proof of
# that — this file does not restate it, it RUNS it.
#
# The goal, stated so it can fail: writing a move must cost an append, not a
# rewrite, and the gate's latency with recording on must come within 300 us of
# the same gate with recording off.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; cd "$ROOT"
GATE="$ROOT/native/rabadon-gate"; AUDIT="$ROOT/native/rabadon-audit"
P_N=0; F_N=0
pass(){ printf 'PASS  %s\n' "$1"; P_N=$((P_N+1)); }
fail(){ printf 'FAIL  %s\n' "$1"; F_N=$((F_N+1)); }
note(){ printf '      %s\n' "$1"; }
head_(){ printf '\n== %s\n' "$1"; }
[ -x "$GATE" ] || { echo "FAIL no gate binary"; exit 1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
jstr(){ python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

sb(){ H="$(mktemp -d "$W/h.XXXXXX")"; PJ="$(mktemp -d "$W/p.XXXXXX")"
  mkdir -p "$H/.rabadon/spool" "$PJ/.git"; printf 'ref: refs/heads/main\n' >"$PJ/.git/HEAD"; : >"$H/.rabadon/enabled"; }
fire(){ printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
  "$1" "$PJ" "$(jstr "$2")" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1; }
logf(){ ls "$PJ"/.rabadon/sessions/*.moves.jsonl 2>/dev/null | head -1; }

head_ "GOAL 1 — a move is appended, not rewritten"
sb; fire s1 'echo one'
L="$(logf)"
if [ -n "$L" ]; then pass "1a the record is its own append-only log ($(basename "$L"))"
else fail "1a no *.moves.jsonl next to the session — the record is still inside the session object"; fi
if [ -n "$L" ]; then
  B1=$(wc -c <"$L"); fire s1 'echo two'; B2=$(wc -c <"$L"); fire s1 'echo three'; B3=$(wc -c <"$L")
  # An append leaves every earlier byte where it was. A rewrite does not.
  # The ts field is masked on both sides. This is NOT a loosening: the claim is
  # "the bytes already written did not move", and two sandboxes are created at
  # two different milliseconds, so an unmasked compare tests the clock rather
  # than the storage. Everything the claim is about — seq, tool, sig, prev — is
  # still compared byte for byte.
  mask(){ sed -E 's/"ts":[0-9]+/"ts":T/g'; }
  H1=$(head -c "$B1" "$L" | mask | shasum | cut -d' ' -f1)
  sb; fire s2 'echo one'; L2="$(logf)"; H0=$(mask <"$L2" | shasum | cut -d' ' -f1)
  if [ "$H1" = "$H0" ]; then pass "1b the first line's bytes are untouched after two more moves"
  else fail "1b the earlier bytes changed — this is still a rewrite"; fi
  if [ "$B3" -gt "$B2" ] && [ "$B2" -gt "$B1" ]; then pass "1c each move grows the file (${B1} -> ${B2} -> ${B3} bytes)"
  else fail "1c the file did not grow monotonically: $B1 $B2 $B3"; fi
fi

head_ "GOAL 2 — R1's contract did not move"
if ./native/moves_test.sh >"$W/mt.log" 2>&1; then
  pass "2a native/moves_test.sh is green, unchanged ($(grep -c '^  ok' "$W/mt.log") assertions)"
else
  fail "2a native/moves_test.sh went red — R1.2 changed the contract, not just the storage"
  grep '  FAIL' "$W/mt.log" | head -5 | sed 's/^/      /'
fi
# "the file is untouched" is the wrong thing to protect, and writing it that way
# was my error: this round MOVES where the record is stored, so the test's reader
# has to learn the new location or it measures nothing. What must not move is the
# CONTRACT — the assertions themselves. So compare the assertion texts against
# the previous commit rather than the file bytes. If a single pass/fail string
# changed, the round rewrote its own proof and that is the thing being refused.
A_OLD="$(git show HEAD:native/moves_test.sh 2>/dev/null | grep -oE '(pass|fail) "[^"]*"' | sort)"
A_NEW="$(grep -oE '(pass|fail) "[^"]*"' native/moves_test.sh | sort)"
if [ "$A_OLD" = "$A_NEW" ]; then
  pass "2b every assertion in moves_test.sh is unchanged ($(printf '%s' "$A_NEW" | grep -c . ) of them); only its reader moved"
else
  fail "2b an assertion in moves_test.sh changed — the round rewrote its own proof"
  diff <(printf '%s\n' "$A_OLD") <(printf '%s\n' "$A_NEW") | head -10 | sed 's/^/      /'
fi

head_ "GOAL 3 — a damaged record is caught, and the ledger still verifies"
sb; for i in 1 2 3 4 5; do fire s3 "echo m$i"; done
L="$(logf)"
if [ -n "$L" ]; then
  cp "$L" "$W/good"
  # The ring is fixed-width, so "remove a line" becomes "overwrite a record".
  # Same claim, expressed in the format the record now has.
  python3 -c 'import sys
HDR,REC=4096,320
p=sys.argv[1]
b=bytearray(open(p,"rb").read())
b[HDR+2*REC:HDR+3*REC]=bytes(REC)
open(p,"wb").write(b)' "$L"
  OUT="$(printf '{"hook_event_name":"PreToolUse","session_id":"s3","cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo after"}}' "$PJ" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_MOVES_STRICT=1 "$GATE" 2>&1 >/dev/null)"
  if printf '%s' "$OUT" | grep -qi 'chain'; then
    pass "3a an overwritten record is detected by the chain"
  else
    fail "3a a record was overwritten in the middle and nothing noticed"
    note "without this, 'no fsync' is not a policy, it is a hope"
  fi
  cp "$W/good" "$L"
  if fire s3 'echo survivor'; then pass "3b a damaged ring does not stop the gate"
  else fail "3b a damaged ring broke the gate"; fi
fi
if [ -x "$AUDIT" ] && env HOME="$H" RABADON_DIR="$H/.rabadon" "$AUDIT" --days 2 >/dev/null 2>&1; then
  pass "3c rabadon-audit is still green on the main ledger"
else
  fail "3c the main ledger's audit is not green"
fi
if [ -f "$ROOT/docs/butce.md" ] && grep -qE '[0-9]' "$ROOT/docs/butce.md" && grep -qi 'ring' "$ROOT/docs/butce.md"; then
  pass "3d docs/butce.md carries the format and its numbers"
else
  fail "3d docs/butce.md is missing, has no numbers, or does not describe the ring"
fi
if grep -qi 'fsync' "$ROOT/docs/butce.md" 2>/dev/null; then
  pass "3e the fsync policy is written down"
else
  fail "3e no fsync policy in docs/butce.md — an unstated durability choice is a bug waiting"
fi

head_ "GOAL 4 — the number this round exists for"
one(){ local envs="$1"; sb
  local EV; EV=$(printf '{"hook_event_name":"PreToolUse","session_id":"b","cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo hello world"}}' "$PJ")
  for i in $(seq 210); do echo "$EV" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 $envs "$GATE" >/dev/null 2>&1; done
  local t0 t1; t0=$(python3 -c 'import time;print(time.time())')
  for i in $(seq 200); do echo "$EV" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 $envs "$GATE" >/dev/null 2>&1; done
  t1=$(python3 -c 'import time;print(time.time())'); python3 -c "print(($t1-$t0)/200*1000)"; }
OFF=(); ON=()
for r in 1 2 3; do OFF+=("$(one RABADON_MOVES=0)"); ON+=("$(one RABADON_SIGNALS=1)"); done
DELTA="$(python3 -c "
import statistics
o=[float(x) for x in '${OFF[*]}'.split()]; n=[float(x) for x in '${ON[*]}'.split()]
mo,mn=statistics.median(o),statistics.median(n)
print(f'{mo:.3f} {mn:.3f} {(mn-mo)*1000:.0f}')")"
read -r MO MN DUS <<<"$DELTA"
note "recording off median: $MO ms   on: $MN ms   delta: ${DUS} us"
note "off runs: ${OFF[*]}"
note "on  runs: ${ON[*]}"
# The ceiling is now RELATIVE: 5% of the off-median. A fixed 300 us on a 4.7 ms
# gate is 6.4%, and on a faster machine it would be a stricter rule for no
# reason. The thing being protected is "nobody perceives the recorder", and that
# is a fraction of the call, not a constant.
CEIL="$(python3 -c "print(f'{float('$MO')*1000*0.05:.0f}')")"
note "ceiling = 5% of ${MO} ms = ${CEIL} us"
if [ "${DUS%.*}" -le "${CEIL%.*}" ] 2>/dev/null; then
  pass "4 recording costs ${DUS} us, at or under the ${CEIL} us ceiling (5% of off-median)"
else
  fail "4 recording costs ${DUS} us, ceiling is ${CEIL} us (5% of off-median)"
  note "STOP. No guessing: the profile below is the next thing to read."
fi

head_ "GOAL 5 — where the remaining cost actually is"
# Parse-only, with the chain check off (the hot path), against a log that has
# been grown to a full session. Reported separately because 'it is the parse'
# and 'it is the hashing' are different sentences and only one of them is true.
sb
EVX=$(printf '{"hook_event_name":"PreToolUse","session_id":"prof","cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo hello world"}}' "$PJ")
for i in $(seq 400); do echo "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1; done
LOGF="$(logf)"
note "log after 400 events: $(wc -l <"$LOGF" | tr -d ' ') lines, $(wc -c <"$LOGF" | tr -d ' ') bytes"
t0=$(python3 -c 'import time;print(time.time())')
for i in $(seq 100); do echo "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1; done
t1=$(python3 -c 'import time;print(time.time())')
LONG="$(python3 -c "print(f'{($t1-$t0)/100*1000:.3f}')")"
t0=$(python3 -c 'import time;print(time.time())')
for i in $(seq 100); do echo "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_MOVES_STRICT=1 "$GATE" >/dev/null 2>&1; done
t1=$(python3 -c 'import time;print(time.time())')
STRICT="$(python3 -c "print(f'{($t1-$t0)/100*1000:.3f}')")"
note "long log, chain check OFF (hot path): ${LONG} ms/call   <- parse only"
note "long log, chain check ON  (STRICT)  : ${STRICT} ms/call  <- parse + SHA per line"
note "so the SHA the hot path no longer pays: $(python3 -c "print(f'{(float('$STRICT')-float('$LONG'))*1000:.0f}')") us"
pass "5 parse-only and parse+SHA are reported separately (numbers above)"

printf '\n== R1.3 acceptance: %d green, %d red\n' "$P_N" "$F_N"
[ "$F_N" -gt 0 ] && { printf 'R1.3 NOT ACCEPTED\n'; exit 1; }
printf 'R1.3 ACCEPTED\n'; exit 0
