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
#      (the gate and repair share one spool protocol — audit is the referee).
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

mkfake() { # a fake `claude` bin whose behavior is the argument
  local kind="$1"
  local bin="$TMP/bin-$kind"; mkdir -p "$bin"
  case "$kind" in
    honest) cat > "$bin/claude" <<'EOF'
#!/bin/bash
# real fix, in cwd (= the isolated work copy)
printf 'def add(a, b):\n    return a + b\n' > calc.py
echo done
EOF
;;
    cheat) cat > "$bin/claude" <<'EOF'
#!/bin/bash
# fake fix: neuter the test instead of fixing the code
printf 'print("ok")\n' > test_calc.py
echo done
EOF
;;
    useless) cat > "$bin/claude" <<'EOF'
#!/bin/bash
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
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "VERIFIED"; then pass "honest fix: arbiter re-ran green, REPAIR_OK (exit 0)"; else fail "honest rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
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

echo "repair session: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
