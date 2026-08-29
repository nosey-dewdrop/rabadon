#!/bin/bash
# day_cache_test.sh — the spool's day string is computed once, and is still right.
#
# WHY THIS EXISTS. reports/R7/PROFIL-YARGILAMA.md measured the line that builds
# that string (`time()` + `gmtime_r()` + `strftime()`, gate.cpp) at 28.5% of the
# daemon's entire judging cost. Not because formatting is slow: the FIRST
# gmtime_r in a process loads the timezone data, 269-483 us cold and 1.0 us
# warm, measured. rabadon-gated forks a worker per request, so every request
# paid it again, for a string that does not change all day.
#
# Caching it is therefore obvious and therefore dangerous: a day string cached
# "for the process" is WRONG the moment a daemon that lives all day crosses
# midnight, and the damage is silent — the ledger keeps appending to
# yesterday's spool file. So this test is two assertions that pull in opposite
# directions, and neither may be dropped to satisfy the other:
#   CORRECT — the cache agrees with the uncached computation on every day it is
#             asked about, including both sides of midnight, a leap day and a
#             year boundary.
#   CHEAP   — a repeat call costs ~nothing, and a FORKED CHILD inherits the
#             warm cache, which is the entire point for the daemon.
set -u
cd "$(dirname "$0")/.."

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

echo "day cache: one timezone load per process, still the right day"

CXX=${CXX:-c++}
command -v "$CXX" >/dev/null 2>&1 || { echo "day cache: no $CXX on PATH"; exit 1; }
TMP=$(mktemp -d /tmp/rabadon-daycache.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

if ! "$CXX" -std=c++17 -O2 -o "$TMP/probe" native/day_cache_probe.cpp >"$TMP/cc.log" 2>&1; then
  fail "the probe does not compile against the real gate"
  sed 's/^/    | /' "$TMP/cc.log" | tail -20
  echo "day cache: $ok passed, $bad failed"; exit 1
fi
pass "the probe compiles against the real gate (gate.cpp, main renamed)"

"$TMP/probe" >"$TMP/out" 2>"$TMP/err" || { fail "the probe exited non-zero"; sed 's/^/    | /' "$TMP/err"; }

# ---- CORRECT ----
AGREE=$(grep '^AGREE ' "$TMP/out")
CHECKED=$(printf '%s' "$AGREE" | awk '{print $2}')
MISMATCH=$(printf '%s' "$AGREE" | awk '{print $3}')
[ "${CHECKED:-0}" -ge 64800 ] 2>/dev/null \
  && pass "the probe compared $CHECKED timestamps against the uncached computation" \
  || { fail "only ${CHECKED:-0} timestamps were compared — this run proves nothing"; }
[ "${MISMATCH:-1}" = "0" ] \
  && pass "every one agreed with gmtime_r+strftime" \
  || { fail "$MISMATCH timestamps came back with the WRONG day"; grep '^MISMATCH' "$TMP/out" | sed 's/^/    | /'; }

# midnight, spelled out: the two seconds either side of 2025-01-01T00:00:00Z
# must not be the same day. A cache that never invalidates prints them equal.
B=$(grep '^BOUNDARY ' "$TMP/out")
BEFORE=$(printf '%s' "$B" | awk '{print $2}')
AFTER=$(printf '%s' "$B" | awk '{print $3}')
if [ "$BEFORE" = "2024-12-31" ] && [ "$AFTER" = "2025-01-01" ]; then
  pass "midnight flips the string: $BEFORE -> $AFTER, asked in reverse order"
else
  fail "across midnight the cache said '$BEFORE' then '$AFTER' (want 2024-12-31 then 2025-01-01)"
fi

# the live entry point, against an independent witness
TODAY=$(grep '^TODAY ' "$TMP/out" | awk '{print $2}')
WITNESS=$(date -u +%F)
if [ "$TODAY" = "$WITNESS" ]; then
  pass "the live call answers today's UTC date ($TODAY), same as \`date -u +%F\`"
else
  # a run that straddles midnight is not a failure; re-read the witness once.
  WITNESS2=$(date -u +%F)
  [ "$TODAY" = "$WITNESS2" ] && pass "the live call answers today's UTC date ($TODAY)" \
    || fail "the live call said '$TODAY', \`date -u +%F\` says '$WITNESS2'"
fi

# ---- CHEAP, AND FOR THE SHAPE THE USER ACTUALLY RUNS ----
# The arms below this one measure a REPEAT call and a FORKED CHILD. Both are
# the daemon's shape. The shipped `rabadon-gate` is one process per hook event
# and gets neither: it pays the FIRST call, cold, on every action a developer
# takes. That number was never asserted, so a 269-483 us timezone load sat on
# the hot path this whole file is about while every arm here stayed green.
COLD=$(grep '^COLD_FIRST_US ' "$TMP/out" | awk '{print $2}')
if [ -n "${COLD:-}" ] && [ "$COLD" -lt 50 ] 2>/dev/null; then
  pass "the FIRST call in a cold process cost ${COLD}us (<50us): the one-shot gate pays no timezone load"
else
  fail "the FIRST call in a cold process cost ${COLD:-?}us — every hook event pays it, and the gate is one process per event"
fi

# ---- CHEAP ----
# 100k repeat calls. The uncached line cost 269-483 us for ONE cold call, so a
# generous ceiling here still cannot be met by re-entering gmtime_r each time:
# 100k uncached calls would be seconds, not milliseconds.
REP=$(grep '^REPEAT_US_100K ' "$TMP/out" | awk '{print $2}')
if [ -n "${REP:-}" ] && [ "$REP" -lt 100000 ] 2>/dev/null; then
  pass "100k repeat calls cost ${REP}us total (<100000us): the timezone load happened once"
else
  fail "100k repeat calls cost ${REP:-?}us — the cache is not holding"
fi

# the daemon's shape. This is the assertion the optimisation exists for.
CF=$(grep '^CHILD_FIRST_US ' "$TMP/out" | awk '{print $2}')
if [ -n "${CF:-}" ] && [ "$CF" -lt 50 ] 2>/dev/null; then
  pass "a forked child's FIRST call cost ${CF}us (<50us): it inherited the warm cache"
else
  fail "a forked child's first call cost ${CF:-?}us — the cold 269-483us path is still being paid per fork"
fi

echo "day cache: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
