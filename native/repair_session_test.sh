#!/bin/bash
# repair_session_test.sh — the SESSION repair loop is real, proven end-to-end.
#
# HANDOFF §6.1's proof definition, enforced by tests:
#   a repair counts ONLY when the same deterministic check that caught the
#   problem re-runs green AND no test file was touched. Anything else is
#   REPAIR_FAIL and reaches no number.
#
# The proposer is a scripted fake `claude` ON PURPOSE (same isolation the old
# repair_proof.sh uses): what is under test is the ARBITER — copy isolation,
# the re-run, the hash locks, propose-and-hold. Swap the real claude in and
# the engine is unchanged.
#
# Cases:
#   1. green repo -> "nothing to repair", no events;
#   2. honest proposer fixes the code -> REPAIR_OK, patch HELD, the user's
#      tree UNTOUCHED, applying the held patch turns the real repo green,
#      `rabadon usage` counts 1 repair accepted;
#   3. cheat proposer neuters the test -> REPAIR_FAIL (hash lock), exit 2;
#   4. useless proposer changes nothing -> check still red -> REPAIR_FAIL;
#   5. proposer missing -> clean exit 3, no REPAIR_* event;
#   6. every emitted event is hash-chained: `rabadon audit` verdict INTACT
#      (the gate and repair share one spool protocol — audit is the referee);
#   7. the headline word matches the evidence: locks>0 prints VERIFIED, locks==0
#      prints HELD, UNVERIFIED with the reason. Both halves are asserted, the
#      positive one first — a lone "must not say VERIFIED" check would start
#      passing for free the moment someone renamed the line.
#   8. ONE SAMPLE IS NOT A VERDICT, entry side: a check that flakes GREEN on the
#      entry run must not end the session with "nothing to repair" while the
#      break is still in the tree. Green is confirmed by a second sample;
#      disagreement is FLAKY with its own reason and its own exit code (4).
#   9. ONE SAMPLE IS NOT A VERDICT, arbiter side — the expensive direction: a
#      suite that flakes RED once must not destroy a correct source-only fix the
#      user already paid a proposer call for, and must never write "check still
#      red after proposal" onto the hash-chained ledger about a fix that went
#      green. Red is re-sampled; red twice is still REPAIR_FAIL (case 4 pins
#      that half), red-then-green is HELD and labelled FLAKY, and the word
#      VERIFIED is not spent on it (case 7a pins that the word still appears
#      when it IS earned).
#  10. and the second sample is COUNTED, because a verdict confirmed twice is
#      only affordable if the confirmation is charged where it buys something:
#      2 check runs to hold a repair, 2 to leave a green repo alone, 3 to reject.
#
# Mutation-checked, both directions (this is why 7a exists):
#   locks==0 branch left saying VERIFIED  -> 15 passed, 2 failed
#   locks>0 branch made to drop VERIFIED  -> 15 passed, 2 failed (7a + case 2)
#   arbiter re-sample deleted (grade sample 1) -> 25 passed, 6 failed
#   entry re-sample deleted (grade sample 1)   -> 27 passed, 4 failed
set -u
cd "$(dirname "$0")/.."
REPAIR=./native/rabadon-repair
AUDIT=./native/rabadon-audit
STATS=./native/rabadon-stats
for b in "$REPAIR" "$AUDIT" "$STATS" ./native/rabadon-truth; do
  [ -x "$b" ] || { echo "repair_session_test: build first (make)"; exit 1; }
done

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

# word-exact match. NOT grep: BSD grep (macOS) has no -P, and more importantly a
# plain substring test for "VERIFIED" ALSO matches inside "UNVERIFIED" — which is
# precisely the confusion case 7 exists to catch. python3 \b keeps them apart.
has_word() { # has_word WORD TEXT
  printf '%s' "$2" | python3 -c 'import sys,re; sys.exit(0 if re.search(r"\b"+sys.argv[1]+r"\b", sys.stdin.read()) else 1)' "$1"
}

TMP=$(mktemp -d /tmp/rabadon-repair-session.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export RABADON_DIR="$TMP/ledger"; mkdir -p "$RABADON_DIR/spool"

mkproj() { # broken python project with its own real test
  local d="$1"; rm -rf "$d"; mkdir -p "$d"
  printf 'def add(a, b):\n    return a - b  # BUG\n' > "$d/calc.py"
  cat > "$d/test_calc.py" <<'EOF'
import calc
assert calc.add(2, 3) == 5, "add(2,3) must be 5"
print("ok")
EOF
}

mkproj_nolocks() { # same bug, but NO file `rabadon truth` will call a test ->
  # zero hash locks. The check is handed in with --cmd, so repair still runs.
  local d="$1"; rm -rf "$d"; mkdir -p "$d"
  printf 'def add(a, b):\n    return a - b  # BUG\n' > "$d/calc.py"
  cat > "$d/check.py" <<'EOF'
import calc
assert calc.add(2, 3) == 5, "add(2,3) must be 5"
print("ok")
EOF
}

# A fake `claude` bin whose behavior is the argument. Each one sleeps past
# drill.h's kRbStubProposerMs floor before answering. This suite drives
# rabadon-repair directly, so no action is ever gated on its pipe — which is
# rule 5's other half — and a proposer that returns in 40ms then satisfies both
# halves and the run is classified a fixture. It IS a fixture; the point is that
# case 6 asserts on the ledger AFTER the drill filter, so without this the test
# reads `0 repairs held` and fails for being right. Sleeping is not a workaround,
# it is the one property of a real proposer this stub was missing.
mkfake() {
  local kind="$1"
  local bin="$TMP/bin-$kind"; mkdir -p "$bin"
  case "$kind" in
    honest) cat > "$bin/claude" <<'EOF'
#!/bin/bash
sleep 2.5   # see mkfake's note: drill.h rule 5
# real fix, in cwd (= the isolated work copy)
printf 'def add(a, b):\n    return a + b\n' > calc.py
echo done
EOF
;;
    cheat) cat > "$bin/claude" <<'EOF'
#!/bin/bash
sleep 2.5   # see mkfake's note: drill.h rule 5
# fake fix: neuter the test instead of fixing the code
printf 'print("ok")\n' > test_calc.py
echo done
EOF
;;
    useless) cat > "$bin/claude" <<'EOF'
#!/bin/bash
sleep 2.5   # see mkfake's note: drill.h rule 5
echo "i looked at it"
EOF
;;
  esac
  chmod +x "$bin/claude"
  printf '%s' "$bin/claude"
}

echo "repair session: caught -> proposed -> re-verified"

CHECK="python3 test_calc.py"

# 1) green repo
P0="$TMP/p0"; mkproj "$P0"; printf 'def add(a, b):\n    return a + b\n' > "$P0/calc.py"
OUT=$(RABADON_CLAUDE_BIN="$(mkfake honest)" "$REPAIR" "$P0" --cmd "$CHECK"); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "nothing to repair"; then pass "green repo: nothing to repair, exit 0"; else fail "green repo rc=$RC"; fi

# 2) honest proposer
P1="$TMP/p1"; mkproj "$P1"
OUT=$(RABADON_CLAUDE_BIN="$(mkfake honest)" "$REPAIR" "$P1" --cmd "$CHECK"); RC=$?
if [ $RC -eq 0 ] && has_word VERIFIED "$OUT"; then pass "honest fix: arbiter re-ran green, REPAIR_OK (exit 0)"; else fail "honest rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
grep -q 'return a - b' "$P1/calc.py" && pass "propose-and-hold: the user's tree is UNTOUCHED" || fail "user tree was modified!"
PATCH=$(ls "$P1/.rabadon/"repair-*.patch 2>/dev/null | head -1)
[ -n "$PATCH" ] && pass "verified patch is held at .rabadon/$(basename "$PATCH")" || fail "no held patch"
( cd "$P1" && patch -p1 < "$PATCH" >/dev/null 2>&1 && python3 test_calc.py >/dev/null 2>&1 ) \
  && pass "applying the held patch turns the REAL repo green" || fail "held patch does not fix the real repo"
grep -q '"ev":"REPAIR_OK"' "$RABADON_DIR/spool/"*.jsonl && pass "REPAIR_OK on the ledger" || fail "no REPAIR_OK event"

# 3) cheat proposer
P2="$TMP/p2"; mkproj "$P2"
OUT=$(RABADON_CLAUDE_BIN="$(mkfake cheat)" "$REPAIR" "$P2" --cmd "$CHECK" 2>&1); RC=$?
if [ $RC -eq 2 ] && printf '%s' "$OUT" | grep -q "REJECTED"; then pass "test-neutering fix REJECTED by the hash lock (exit 2)"; else fail "cheat rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
grep -q '"why":"test-tamper' "$RABADON_DIR/spool/"*.jsonl && pass "REPAIR_FAIL test-tamper on the ledger" || fail "no test-tamper event"

# 4) useless proposer
P3="$TMP/p3"; mkproj "$P3"
OUT=$(RABADON_CLAUDE_BIN="$(mkfake useless)" "$REPAIR" "$P3" --cmd "$CHECK" 2>&1); RC=$?
if [ $RC -eq 2 ] && printf '%s' "$OUT" | grep -q "did NOT turn the check green"; then pass "no-op proposal: still red -> REPAIR_FAIL (exit 2)"; else fail "useless rc=$RC"; fi

# 5) proposer missing
P4="$TMP/p4"; mkproj "$P4"
BEFORE_EVENTS=$(cat "$RABADON_DIR/spool/"*.jsonl | grep -cE '"ev":"REPAIR_(OK|FAIL|START)"' || true)
OUT=$(RABADON_CLAUDE_BIN="$TMP/definitely-not-a-binary" "$REPAIR" "$P4" --cmd "$CHECK" 2>&1); RC=$?
AFTER_EVENTS=$(cat "$RABADON_DIR/spool/"*.jsonl | grep -cE '"ev":"REPAIR_(OK|FAIL|START)"' || true)
if [ $RC -eq 3 ] && printf '%s' "$OUT" | grep -q "proposer unavailable"; then pass "missing proposer: clean exit 3 with the fix instruction"; else fail "missing proposer rc=$RC"; fi
[ "$AFTER_EVENTS" -eq "$BEFORE_EVENTS" ] && pass "no repair event claimed without a proposer" || fail "events grew without a proposer ($BEFORE_EVENTS -> $AFTER_EVENTS)"

# 6) the chain holds across gate+repair writers
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "INTACT"; then pass "audit: repair events are chained, verdict INTACT"; else fail "audit rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# usage counts exactly the accepted repair — and in the bucket it EARNED. A fix
# only reaches "held" if test files were hash-locked while it was re-checked;
# landing in "unverified" here would mean the anti-tamper evidence never
# existed, which is the one thing this path sells.
U=$(RABADON_DIR="$RABADON_DIR" "$STATS" --days 2)
printf '%s' "$U" | grep -q "1 repairs held" && pass "usage headline counts exactly 1 repair HELD (hash-locked, not merely accepted)" || { fail "usage count"; printf '%s\n' "$U" | sed 's/^/    | /'; }

# 7) the headline word must match the evidence that actually exists.
# "VERIFIED" is earned by the anti-tamper check RUNNING, not by the check going
# green. With zero test files there was nothing to lock, so the tamper check
# never ran and the word must not be printed. Own ledger: these two runs must not
# move the counts case 2/6 just asserted.
L7="$TMP/ledger7"; mkdir -p "$L7/spool"

# 7a POSITIVE FIRST (K2): locks exist -> the word IS printed. Without this, a
# later rename of the headline would make 7b pass by simply saying nothing.
P5="$TMP/p5"; mkproj "$P5"
OUT=$(RABADON_DIR="$L7" RABADON_CLAUDE_BIN="$(mkfake honest)" "$REPAIR" "$P5" --cmd "$CHECK" 2>&1); RC=$?
LOCKED=$(printf '%s' "$OUT" | python3 -c 'import sys,re; m=re.search(r"all (\d+) hash-locked", sys.stdin.read()); print(m.group(1) if m else 0)')
if [ $RC -eq 0 ] && [ "$LOCKED" -gt 0 ] && has_word VERIFIED "$OUT"; then
  pass "locks>0 ($LOCKED locked): headline says VERIFIED — the tamper check really ran"
else fail "locks>0 case rc=$RC locked=$LOCKED"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# 7b NEGATIVE: zero locks -> the word must be GONE, replaced by UNVERIFIED
P6="$TMP/p6"; mkproj_nolocks "$P6"
OUT=$(RABADON_DIR="$L7" RABADON_CLAUDE_BIN="$(mkfake honest)" "$REPAIR" "$P6" --cmd "python3 check.py" 2>&1); RC=$?
if [ $RC -eq 0 ] && ! has_word VERIFIED "$OUT"; then
  pass "locks==0: headline does NOT claim VERIFIED"
else fail "locks==0 still claims VERIFIED (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
if has_word UNVERIFIED "$OUT"; then
  pass "locks==0: headline says UNVERIFIED instead"
else fail "locks==0 headline never says UNVERIFIED"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
# and it must say WHY, so the screen and the ledger tell the same story
if printf '%s' "$OUT" | grep -q "0 test files" && printf '%s' "$OUT" | grep -q "anti-tamper"; then
  pass "locks==0: the reason is stated (0 test files, anti-tamper never ran)"
else fail "locks==0 gives no reason"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# 8) THE ENTRY SAMPLE IS NOT A VERDICT.
# A nondeterministic check that flakes GREEN on the entry run used to end the run
# with "the check is GREEN — nothing to repair.", exit 0 — a caught break dropped
# on the floor, with nothing on the ledger to show it ever happened. The check
# below is deterministically flaky: green on odd runs, and on even runs it tells
# the truth (the bug is there). Sample 1 green, sample 2 red -> FLAKY.
L8="$TMP/ledger8"; mkdir -p "$L8/spool"
mkflaky() { # mkflaky DIR MODE  — MODE=entry (flake green odd) | arbiter (flake red even)
  local d="$1" mode="$2"; rm -rf "$d"; mkdir -p "$d"
  printf 'def add(a, b):\n    return a - b  # BUG\n' > "$d/calc.py"
  # the run counter lives OUTSIDE both the repo and the isolated copies, so the
  # same physical counter is shared by the entry run, the arbiter and the re-sample
  local ctr="$TMP/flakes/$(basename "$d").n"; mkdir -p "$TMP/flakes"; rm -f "$ctr"
  if [ "$mode" = entry ]; then
    cat > "$d/check.sh" <<EOF
#!/bin/sh
n=\$(cat "$ctr" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$ctr"
[ \$((n % 2)) -eq 1 ] && exit 0
python3 -c 'import calc,sys; sys.exit(0 if calc.add(2,3)==5 else 1)'
EOF
  else
    cat > "$d/check.sh" <<EOF
#!/bin/sh
n=\$(cat "$ctr" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$ctr"
python3 -c 'import calc,sys; sys.exit(0 if calc.add(2,3)==5 else 1)' || exit 1
[ \$((n % 2)) -eq 0 ] && exit 1
exit 0
EOF
  fi
  chmod +x "$d/check.sh"
}

P7="$TMP/p7"; mkflaky "$P7" entry
OUT=$(RABADON_DIR="$L8" RABADON_CLAUDE_BIN="$(mkfake honest)" "$REPAIR" "$P7" --cmd ./check.sh 2>&1); RC=$?
# POSITIVE FIRST (K2): the run must SAY flaky and exit on its own code. Without
# this half, the "must not say nothing to repair" check below would start passing
# for free the moment the headline was renamed — or removed altogether.
if [ $RC -eq 4 ] && has_word FLAKY "$OUT"; then
  pass "entry flake (green then red): FLAKY, exit 4 — its own verdict, not exit 0"
else fail "entry flake rc=$RC (want 4)"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
if printf '%s' "$OUT" | grep -q "nothing to repair"; then
  fail "entry flake still claims 'nothing to repair' — the break was dropped"
else pass "entry flake: the run never claims 'nothing to repair'"; fi
if grep -q '"why":"flaky check: entry samples disagree' "$L8/spool/"*.jsonl 2>/dev/null; then
  pass "entry flake: the ledger carries its OWN reason (entry samples disagree)"
else fail "entry flake left no flaky reason on the ledger"; fi

# 9) THE ARBITER SAMPLE IS NOT A VERDICT EITHER — the expensive direction.
# Same proposal, one run apart, two answers. The old arbiter graded the first,
# wrote "check still red after proposal" into the hash-chained ledger as fact and
# threw away a correct source-only fix the user had already paid a proposer call
# for. Entry run red (the bug is real), arbiter run #2 red by flake, re-sample #3
# green -> the patch is HELD and the run is labelled FLAKY, never "still red".
P8="$TMP/p8"; mkflaky "$P8" arbiter
OUT=$(RABADON_DIR="$L8" RABADON_CLAUDE_BIN="$(mkfake honest)" "$REPAIR" "$P8" --cmd ./check.sh 2>&1); RC=$?
if [ $RC -eq 0 ] && has_word FLAKY "$OUT"; then
  pass "arbiter flake (red then green): the fix is kept, exit 0, labelled FLAKY"
else fail "arbiter flake rc=$RC (want 0)"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
PATCH8=$(ls "$P8/.rabadon/"repair-*.patch 2>/dev/null | head -1)
if [ -n "$PATCH8" ] && grep -q 'return a + b' "$PATCH8"; then
  pass "arbiter flake: the correct source-only fix is HELD, not discarded"
else fail "arbiter flake: no held patch (the paid-for repair was thrown away)"; fi
grep -q 'return a - b' "$P8/calc.py" && pass "arbiter flake: the user's tree is still UNTOUCHED" || fail "user tree was modified!"
# the two false sentences, each paired with the positive that already proves the
# same words are still printed when they are TRUE: case 4 (deterministic red ->
# "did NOT turn the check green") and case 7a (deterministic green + locks ->
# "VERIFIED"). Neither may be spent on a run the arbiter could not grade.
if printf '%s' "$OUT" | grep -q "did NOT turn the check green"; then
  fail "arbiter flake still says the fix did NOT turn the check green — it did"
else pass "arbiter flake: never says 'did NOT turn the check green'"; fi
if has_word VERIFIED "$OUT"; then
  fail "arbiter flake claims VERIFIED — a coin flip verified nothing"
else pass "arbiter flake: the word VERIFIED is not spent on an ungradeable run"; fi
if grep -q '"why":"flaky check: arbiter samples disagree' "$L8/spool/"*.jsonl 2>/dev/null; then
  pass "arbiter flake: the ledger says FLAKY, in its own words"
else fail "arbiter flake left no flaky reason on the ledger"; fi
# The screen refuses the word VERIFIED on this run, and the ledger went on
# writing REPAIR_OK underneath it — so `rabadon stats` counted a coin flip among
# the held repairs, which is the one number this product is sold on.
if grep -q '"ev":"REPAIR_FLAKY"' "$L8/spool/"*.jsonl 2>/dev/null; then
  pass "arbiter flake: the ledger event is REPAIR_FLAKY, not an OK"
else fail "arbiter flake: no REPAIR_FLAKY event on the ledger"; fi
if grep '"step":"session-repair"' "$L8/spool/"*.jsonl 2>/dev/null | grep -q '"ev":"REPAIR_OK"'; then
  fail "an ungradeable run still wrote REPAIR_OK — the held counter counts a coin flip"
else pass "arbiter flake: the word OK never reaches the counter"; fi
if grep -q '"why":"check still red after proposal"' "$L8/spool/"*.jsonl 2>/dev/null; then
  fail "the ledger recorded 'check still red after proposal' for a fix that went green"
else pass "the false sentence never reached the hash-chained ledger"; fi
# and the flaky events chain like every other event
OUT=$(RABADON_DIR="$L8" "$AUDIT" --days 2); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "INTACT"; then pass "audit: the flaky events are chained too, verdict INTACT"; else fail "audit(L8) rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# 10) THE PRICE OF THE SECOND SAMPLE, COUNTED.
# Confirming a verdict is only affordable if it is charged where it buys
# something. The second sample is spent on the two answers that throw work away
# — a green that sends repair home, a red that rejects a proposal — and on
# nothing else. So the successful repair path (entry red, arbiter green) must
# still cost exactly TWO runs of the check, the same as before this existed. On
# a real suite that is the difference between a repair and twice a repair.
mkcounted() { # mkcounted DIR COUNTERFILE — the project's own test, run through a tally
  local d="$1" ctr="$2"; mkproj "$d"; mkdir -p "$(dirname "$ctr")"; rm -f "$ctr"
  cat > "$d/check.sh" <<EOF
#!/bin/sh
echo run >> "$ctr"
python3 test_calc.py >/dev/null 2>&1
EOF
  chmod +x "$d/check.sh"
}
runs() { wc -l < "$1" 2>/dev/null | tr -d ' '; }

C9="$TMP/flakes/p9.n"; P9="$TMP/p9"; mkcounted "$P9" "$C9"
RABADON_DIR="$L8" RABADON_CLAUDE_BIN="$(mkfake honest)" "$REPAIR" "$P9" --cmd ./check.sh >/dev/null 2>&1; RC=$?
if [ $RC -eq 0 ] && [ "$(runs "$C9")" = "2" ]; then
  pass "held repair still costs exactly 2 check runs — the happy path pays nothing for sampling"
else fail "honest path ran the check $(runs "$C9") time(s), rc=$RC (want 2 runs, rc 0)"; fi

C10="$TMP/flakes/p10.n"; P10="$TMP/p10"; mkcounted "$P10" "$C10"
printf 'def add(a, b):\n    return a + b\n' > "$P10/calc.py"   # already green
RABADON_DIR="$L8" RABADON_CLAUDE_BIN="$(mkfake honest)" "$REPAIR" "$P10" --cmd ./check.sh >/dev/null 2>&1; RC=$?
if [ $RC -eq 0 ] && [ "$(runs "$C10")" = "2" ]; then
  pass "green repo runs the check twice — the green that ends the session is confirmed"
else fail "green path ran the check $(runs "$C10") time(s), rc=$RC (want 2 runs, rc 0)"; fi

C11="$TMP/flakes/p11.n"; P11="$TMP/p11"; mkcounted "$P11" "$C11"
RABADON_DIR="$L8" RABADON_CLAUDE_BIN="$(mkfake useless)" "$REPAIR" "$P11" --cmd ./check.sh >/dev/null 2>&1; RC=$?
if [ $RC -eq 2 ] && [ "$(runs "$C11")" = "3" ]; then
  pass "rejection costs a 3rd run — no proposal is thrown away on one sample"
else fail "rejection path ran the check $(runs "$C11") time(s), rc=$RC (want 3 runs, rc 2)"; fi

echo "repair session: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
