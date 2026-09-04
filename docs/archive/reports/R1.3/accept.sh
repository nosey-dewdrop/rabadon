#!/usr/bin/env bash
# R1.3 acceptance — ONE goal: the move record stops rewriting a whole file per event.
#
# An intermediate round measures its one goal and nothing else. It adds no
# feature. R1's contract is unchanged and native/moves_test.sh is the proof of
# that — this file does not restate it, it RUNS it.
#
# The goal, stated so it can fail: writing a move must cost an append, not a
# rewrite, and the gate's latency with recording on must come within the ceiling
# of the same gate with recording off. That ceiling is 212 us and it is now
# checked IN-PROCESS — read the block comment above GOAL 4 for why the end-to-end
# ruler was replaced and for the planted-regression proof that this one works.
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
# R1.3 moved the record from a JSONL text log to a fixed-width binary ring, and
# the file it is stored in was renamed with it: <key>.moves.bin. This glob still
# said .jsonl, so it matched nothing, `logf` returned the empty string, and every
# block guarded by `[ -n "$L" ]` was skipped in silence — GOAL 3 never ran at all
# and GOAL 5's wc had no file to count. A glob that matches nothing is the worst
# kind of green: the script reported success on measurements it never took.
logf(){ ls "$PJ"/.rabadon/sessions/*.moves.bin 2>/dev/null | head -1; }

head_ "GOAL 1 — a move is appended, not rewritten"
sb; fire s1 'echo one'
L="$(logf)"
if [ -n "$L" ]; then pass "1a the record is its own append-only log ($(basename "$L"))"
else fail "1a no *.moves.bin next to the session — the record is still inside the session object"; fi
if [ -n "$L" ]; then
  B1=$(wc -c <"$L"); fire s1 'echo two'; B2=$(wc -c <"$L"); fire s1 'echo three'; B3=$(wc -c <"$L")
  # An append leaves every earlier byte where it was. A rewrite does not.
  # The ts field is masked on both sides. This is NOT a loosening: the claim is
  # "the bytes already written did not move", and two sandboxes are created at
  # two different milliseconds, so an unmasked compare tests the clock rather
  # than the storage. Everything the claim is about — seq, tool, sig, prev — is
  # still compared byte for byte.
  # The mask used to be `sed 's/"ts":[0-9]+/"ts":T/'` over the whole file. Against
  # a binary ring that sed emits "RE error: illegal byte sequence" and prints
  # NOTHING, so both sides hashed the empty string and 1b passed without ever
  # comparing a byte. Same claim, expressed in the format the record now has:
  # hash record #0 itself (offset 4096, length 320) with only its ts field (bytes
  # 8..16 of the record) zeroed. The 4096-byte header is deliberately NOT part of
  # the comparison — it carries `count`, which is supposed to change on append.
  rec0(){ python3 -c 'import sys,hashlib
HDR,REC=4096,320
b=bytearray(open(sys.argv[1],"rb").read()[HDR:HDR+REC])
b[8:16]=bytes(8)
print(hashlib.sha256(bytes(b)).hexdigest())' "$1"; }
  H1=$(rec0 "$L")
  sb; fire s2 'echo one'; L2="$(logf)"; H0=$(rec0 "$L2")
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

### THE INSTRUMENT (GOAL 4 and GOAL 6 both use it) ###############################
#
# WHAT CHANGED AND WHY. GOAL 4 and GOAL 6 assert exactly what they always
# asserted — "recording costs less than the ceiling" and "cost does not depend on
# session length". Neither subject moved. What moved is the RULER.
#
# The old ruler was end-to-end wall clock: fork + exec + dyld + main(), divided
# by the call count. About 2.3 ms of a 4.2 ms call is process startup
# (PROFIL.md), and that startup carries all the scheduler noise. On ONE UNCHANGED
# BINARY, five runs of the old GOAL 4 returned deltas of 602, 118, 213, -59 and
# 228 us against a ~212 us ceiling, and GOAL 6 returned 5.0%, 11.7%, 0.9%, 0.4%
# and 11.6% against a 10% ceiling: green and red out of identical code, in both
# goals. A budget gate whose verdict is drawn from noise is worse than no gate —
# it passes real regressions and fails clean rounds, and neither verdict can be
# believed. KOSU-RABADON.md §4 already rules this method out in writing ("Bu
# tablodaki her sayı süreç-İÇİ ölçülür, uçtan uca çağrıyla değil").
#
# The new ruler measures main() from the inside. A COPY of the shipped
# native/gate.cpp is patched under /tmp with one probe — a steady_clock stamp at
# the top of main() and an atexit handler that appends the elapsed microseconds
# to a file — and compiled there. native/ is not touched, exactly as PROFIL.md
# describes. The probe is registered FIRST, so being LIFO it fires LAST and
# covers StateFlushGuard's own atexit write; it reads the clock before it writes,
# so its own write is outside the measurement; and it costs the same on both arms
# of every comparison, so it cannot move a delta.
#
# Second change, and it matters as much as the probe: the two arms are
# INTERLEAVED CALL BY CALL, not run as two blocks. Both sandboxes are seeded
# first, then every iteration fires arm A once and arm B once. Machine drift then
# lands on both arms inside the same millisecond instead of being charged to
# whichever arm happened to run while the box was busy.
#
# THE PROOF THAT THIS WAS NOT A LOOSENING — the planted regression. A second copy
# of the same source was built with a deliberate 150 us busy-wait on the
# recording path only (immediately after `stt.pendingRecord = true`), a cost far
# below the old method's noise floor and far above this one's:
#
#   OLD end-to-end ruler vs the planted binary — 5 standalone runs of the exact
#   old procedure, then 3 runs of the old accept.sh itself in a git worktree with
#   the plant compiled into native/gate.cpp:
#     453/212 RED  351/211 RED  207/210 GREEN  216/210 RED  155/209 GREEN
#     226/207 RED  132/215 GREEN  303/206 RED
#     => 5 caught, 3 MISSED out of 8. It cannot do this job.
#   NEW in-process ruler vs the same planted binary — 4 standalone runs, then 3
#   runs of THIS script in that worktree:
#     242.8, 267.5, 237.5, 235.7, 238, 232, 227 us  -> RED 7 of 7 (ceiling 212)
#   NEW in-process ruler vs the CLEAN binary — 4 standalone, then the 5 recorded
#   acceptance runs below:
#      79.7, 81.7, 67.4, 79.7, 78, 93, 82, 76, 74 us -> GREEN 9 of 9
#   => clean tops out at 93 us, planted bottoms out at 227 us. The gap is 134 us,
#      which is the 150 us that was planted, minus this ruler's own few-us drift.
#      The ceiling sits 119 us above every clean reading and 15 us below every
#      planted one. Same verdict every time, on both sides.
#
PROBE_DIR="$W/probe"; PGATE="$PROBE_DIR/rabadon-gate-probe"; PROBE_OK=0
mkdir -p "$PROBE_DIR" && cp native/*.h "$PROBE_DIR"/ 2>/dev/null
python3 - native/gate.cpp "$PROBE_DIR/gate_probe.cpp" <<'PY' 2>/dev/null
import sys
src = open(sys.argv[1]).read()
PROBE = r'''
// ---- in-process probe, added to a COPY under /tmp by reports/R1.3/accept.sh ----
#include <chrono>
static std::chrono::steady_clock::time_point g_rbp_t0;
static void rbprobe_dump() {
  const char* p = getenv("RABADON_PROBE_OUT");
  if (!p || !*p) return;
  const double us = std::chrono::duration<double, std::micro>(
      std::chrono::steady_clock::now() - g_rbp_t0).count();
  char buf[64];
  const int n = snprintf(buf, sizeof buf, "%.1f\n", us);
  const int fd = open(p, O_WRONLY | O_APPEND | O_CREAT, 0644);
  if (fd < 0) return;
  ssize_t w = write(fd, buf, (size_t)n); (void)w;
  close(fd);
}
// Registered first => runs last (atexit is LIFO), so StateFlushGuard's own
// atexit write is inside the window. exit() runs atexit handlers; the three
// _exit(127) calls are in a failed-exec fork child, which must not report.
static void rbprobe_begin() { g_rbp_t0 = std::chrono::steady_clock::now(); atexit(rbprobe_dump); }
// ---- end probe ----

'''
a = "int main(int argc, char** argv) {"
assert src.count(a) == 1, "main() anchor is not unique"
open(sys.argv[2], "w").write(src.replace(a, PROBE + a + "\n  rbprobe_begin();"))
PY
if [ -s "$PROBE_DIR/gate_probe.cpp" ] && \
   ${CXX:-c++} -std=c++17 -O2 -I "$PROBE_DIR" -o "$PGATE" "$PROBE_DIR/gate_probe.cpp" 2>"$W/probe.log"; then
  PROBE_OK=1
fi

# One interleaved comparison. $1/$2 are the env of arm A and arm B; $3 is the
# number of paired iterations. Prints "medianA medianB" in microseconds.
# Each arm gets its own sandbox because RABADON_MOVES=0 writes a different tree.
pair(){ local ea="$1" eb="$2" n="$3"
  sb; local HA="$H" PA="$PJ"; sb; local HB="$H" PB="$PJ"
  local EA EB OA OB; OA="$W/pa.$$.$RANDOM"; OB="$W/pb.$$.$RANDOM"
  EA=$(printf '{"hook_event_name":"PreToolUse","session_id":"b","cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo hello world"}}' "$PA")
  EB=$(printf '{"hook_event_name":"PreToolUse","session_id":"b","cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo hello world"}}' "$PB")
  local i
  for i in $(seq 60); do
    printf '%s' "$EA" | env HOME="$HA" RABADON_DIR="$HA/.rabadon" RABADON_NOTIFY=0 $ea "$PGATE" >/dev/null 2>&1
    printf '%s' "$EB" | env HOME="$HB" RABADON_DIR="$HB/.rabadon" RABADON_NOTIFY=0 $eb "$PGATE" >/dev/null 2>&1
  done
  for i in $(seq "$n"); do
    printf '%s' "$EA" | env HOME="$HA" RABADON_DIR="$HA/.rabadon" RABADON_NOTIFY=0 RABADON_PROBE_OUT="$OA" $ea "$PGATE" >/dev/null 2>&1
    printf '%s' "$EB" | env HOME="$HB" RABADON_DIR="$HB/.rabadon" RABADON_NOTIFY=0 RABADON_PROBE_OUT="$OB" $eb "$PGATE" >/dev/null 2>&1
  done
  python3 -c "
import statistics,sys
a=[float(x) for x in open(sys.argv[1])]; b=[float(x) for x in open(sys.argv[2])]
print(f'{statistics.median(a):.1f} {statistics.median(b):.1f}')" "$OA" "$OB"; }

head_ "GOAL 4 — the number this round exists for"
if [ "$PROBE_OK" != 1 ]; then
  fail "4 the in-process instrument did not build — this goal was NOT measured"
  note "$(tail -3 "$W/probe.log" 2>/dev/null | tr '\n' ' ')"
  note "a goal that cannot be measured is red, never skipped"
else
  read -r P_OFF P_ON <<<"$(pair RABADON_MOVES=0 RABADON_SIGNALS=1 300)"
  DUS="$(python3 -c "print(f'{float('$P_ON')-float('$P_OFF'):.0f}')")"
  note "in-process main(), recording off: ${P_OFF} us   on: ${P_ON} us   delta: ${DUS} us"
  note "300 interleaved pairs, median of each arm, process startup excluded"
  # THE CEILING: 212 us, fixed. It is the same number this gate already enforced
  # — 5% of the 4.248 ms recording-off median measured on 22 Aug (PROFIL.md,
  # "Kabul koşusu") is 212 us — carried over unchanged so the assertion is
  # identical. It is now a CONSTANT instead of being recomputed from each run's
  # own median, because recomputing made the ceiling itself noise: across six
  # recorded runs of the old script it came out 209, 210, 211, 212, 286, 323 and
  # 476 us. 212 is the strictest of those, and holding it fixed is the opposite
  # of a loosening. The quantity compared against it did not change either: the
  # end-to-end delta and the in-process delta are the same number, because
  # process startup is common to both arms and cancels — the old ruler just
  # could not see it under ±150 us of noise.
  CEIL=212
  note "ceiling = 212 us, fixed (5% of the 4.248 ms off-median of 22 Aug; see comment)"
  if [ "${DUS%.*}" -le "$CEIL" ] 2>/dev/null; then
    pass "4 recording costs ${DUS} us in-process, at or under the ${CEIL} us ceiling"
  else
    fail "4 recording costs ${DUS} us in-process, ceiling is ${CEIL} us"
    note "STOP. No guessing: the profile below is the next thing to read."
  fi
fi

head_ "GOAL 5 — where the remaining cost actually is"
# Parse-only, with the chain check off (the hot path), against a log that has
# been grown to a full session. Reported separately because 'it is the parse'
# and 'it is the hashing' are different sentences and only one of them is true.
sb
EVX=$(printf '{"hook_event_name":"PreToolUse","session_id":"prof","cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo hello world"}}' "$PJ")
for i in $(seq 400); do echo "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1; done
LOGF="$(logf)"
# `wc -l` on a binary ring counts stray 0x0a bytes, not records. The ring is
# fixed-width, so the record count is arithmetic on the size.
LBYTES=$(wc -c <"$LOGF" | tr -d ' ')
note "ring after 400 events: $(( (LBYTES - 4096) / 320 )) records, ${LBYTES} bytes (capped at CAP=200)"
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

head_ "GOAL 6 — the invariant: cost does not depend on session length"
# This is the criterion KARAR.md opens with — "the same median at 50 events and
# at 400 events" — and until now it was the one thing the script never measured.
# It is the whole reason the record became a fixed-width ring: the old JSONL log
# was re-read and re-parsed line by line, so a long session paid more than a
# short one for nothing. A ring reads ONE pread of a KNOWN size whether 50 or 400
# events came before it, and the CAP=200 window means even the live record count
# stops growing. If these two medians diverge, the format did not buy what it was
# bought for, and no amount of "the delta in GOAL 4 is small" repairs that.
# The assertion is untouched. The RULER is the same one GOAL 4 now uses: the
# in-process probe, and the two arms interleaved call by call. One earlier noise
# control survives inside it and is still load-bearing — BOTH sandboxes are
# seeded before EITHER is timed, so the 400 arm is not measured on a box still
# warm from its own seed. Interleaving replaces the old alternating-block order,
# because per-call alternation cancels drift that block alternation only
# averages. The old end-to-end version of this measurement returned 5.0%, 11.7%,
# 0.9%, 0.4% and 11.6% over five runs of ONE UNCHANGED BINARY: it crossed its own
# 10% ceiling twice out of five on code that never changed. The same experiment
# with the ruler below returned 5.43%, 3.85%, 5.44%, 5.04% and 5.60% — a spread
# of 1.75 points instead of 11.3, and the same verdict every time.
if [ "$PROBE_OK" != 1 ]; then
  fail "6 the in-process instrument did not build — this goal was NOT measured"
else
  sb; HA="$H"; PA="$PJ"; sb; HB="$H"; PB="$PJ"
  EVA=$(printf '{"hook_event_name":"PreToolUse","session_id":"d","cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo hello world"}}' "$PA")
  EVB=$(printf '{"hook_event_name":"PreToolUse","session_id":"d","cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo hello world"}}' "$PB")
  for i in $(seq 50);  do printf '%s' "$EVA" | env HOME="$HA" RABADON_DIR="$HA/.rabadon" RABADON_NOTIFY=0 "$PGATE" >/dev/null 2>&1; done
  for i in $(seq 400); do printf '%s' "$EVB" | env HOME="$HB" RABADON_DIR="$HB/.rabadon" RABADON_NOTIFY=0 "$PGATE" >/dev/null 2>&1; done
  OA="$W/g6a"; OB="$W/g6b"
  for i in $(seq 250); do
    printf '%s' "$EVA" | env HOME="$HA" RABADON_DIR="$HA/.rabadon" RABADON_NOTIFY=0 RABADON_PROBE_OUT="$OA" "$PGATE" >/dev/null 2>&1
    printf '%s' "$EVB" | env HOME="$HB" RABADON_DIR="$HB/.rabadon" RABADON_NOTIFY=0 RABADON_PROBE_OUT="$OB" "$PGATE" >/dev/null 2>&1
  done
  R6="$(python3 -c "
import statistics,sys
a=[float(x) for x in open(sys.argv[1])]; b=[float(x) for x in open(sys.argv[2])]
ma,mb=statistics.median(a),statistics.median(b)
print(f'{ma:.1f} {mb:.1f} {abs(mb-ma)/min(ma,mb)*100:.1f}')" "$OA" "$OB")"
  read -r M50 M400 PCT <<<"$R6"
  note "50-event session : ${M50} us in-process   (250 interleaved samples)"
  note "400-event session: ${M400} us in-process   (250 interleaved samples)"
  # THE CEILING: 10%, the same number this goal always carried. Its DENOMINATOR
  # got stricter, not looser. It used to be a percentage of the ~4.2 ms
  # end-to-end call, ~2.3 ms of which is process startup that cannot depend on
  # session length and therefore dilutes any real dependence by about 2.4x.
  # PROFIL.md measured exactly that dilution: an in-process +18.1% showed up
  # end-to-end as +7.0% and PASSED a 10% ceiling. 10% of the gate own ~1.0 ms of
  # work is the tighter rule, and it is the denominator KOSU-RABADON.md 4 asks
  # for ("Butce, gate in kendi isine oranla yazilir").
  note "divergence: ${PCT}% of the smaller median (ceiling 10%, in-process denominator)"
  if [ "$(python3 -c "print(1 if float('$PCT')<=10.0 else 0)")" = 1 ]; then
    pass "6 the median is length-independent: ${M50} us at 50 events vs ${M400} us at 400, ${PCT}% apart"
  else
    fail "6 the median moved with session length: ${M50} us at 50 events vs ${M400} us at 400, ${PCT}% apart (ceiling 10%)"
    note "the fixed-width ring exists to make this number zero; it is not zero"
    note "reports/R1.3/PROFIL.md locates it: the move ring contributes +7 us of it,"
    note "last_ledger_mode() reads the whole spool day-file when it holds no MODE line"
  fi
fi

printf '\n== R1.3 acceptance: %d green, %d red\n' "$P_N" "$F_N"
[ "$F_N" -gt 0 ] && { printf 'R1.3 NOT ACCEPTED\n'; exit 1; }
printf 'R1.3 ACCEPTED\n'; exit 0
