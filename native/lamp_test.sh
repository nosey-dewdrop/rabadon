#!/usr/bin/env bash
# statusline lamp proof — the ON lamp breathes, the OFF lamp is dead.
#
# The phase is a pure function of the wall clock (the process is spawned fresh
# for every render and keeps no state), so RABADON_LAMP_MS pins the clock and
# the whole breath becomes an assertable sequence instead of "whatever
# millisecond the test happened to run in".
set -u
# HERMETIC: rabadon is DEFAULT-OFF; give this run its own HOME with the flag set.
export HOME="$(mktemp -d)"; mkdir -p "$HOME/.rabadon"; : > "$HOME/.rabadon/enabled"
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

EV='{"current_dir":"/tmp/proj","display_name":"Opus"}'
frame(){ printf '%s' "$EV" | RABADON_LAMP_MS="$1" "$BIN" --statusline; }

# ---- 1: the word cycles through the whole lilac ramp, one breath ----
seq_out=""
for i in 0 1 2 3 4 5 6 7; do
  f="$(frame $((i*750)))"
  # the SECOND colour in the segment is the word's; the first is the star
  c="$(printf '%s' "$f" | grep -o '38;5;[0-9]*m rabadon' | sed 's/.*38;5;\([0-9]*\)m rabadon/\1/')"
  seq_out="$seq_out $c"
done
[ "$seq_out" = " 97 104 141 183 189 183 141 104" ] \
  && ok "one breath walks the full ramp and comes back ($seq_out)" \
  || bad "ramp wrong: '$seq_out'"

# ---- 2: it is a CYCLE — 6s later the same frame returns ----
[ "$(frame 0)" = "$(frame 6000)" ] && ok "the breath is periodic (6s cycle closes)" \
  || bad "frame at t=0 and t=6000ms should be identical"

# ---- 3: consecutive frames actually differ (it is not a still image) ----
[ "$(frame 0)" != "$(frame 750)" ] && ok "consecutive frames differ — the lamp is alive" \
  || bad "two consecutive frames are identical"

# ---- 4: the star leads the word (pilot light, not a flat block) ----
star="$(frame 0 | grep -o '38;5;[0-9]*m\*' | sed 's/.*38;5;\([0-9]*\)m\*/\1/')"
word="$(frame 0 | grep -o '38;5;[0-9]*m rabadon' | sed 's/.*38;5;\([0-9]*\)m rabadon/\1/')"
[ -n "$star" ] && [ "$star" != "$word" ] && ok "the star runs ahead of the word (star=$star word=$word)" \
  || bad "star should lead the word (star=$star word=$word)"

# ---- 5: OFF is dead and static — a dormant supervisor must look dormant ----
o1="$(printf '%s' "$EV" | RABADON_OFF=1 RABADON_LAMP_MS=0    "$BIN" --statusline)"
o2="$(printf '%s' "$EV" | RABADON_OFF=1 RABADON_LAMP_MS=3000 "$BIN" --statusline)"
[ "$o1" = "$o2" ] && ok "OFF never animates (same bytes at any phase)" || bad "OFF lamp moved"
printf '%s' "$o1" | grep -q 'rabadon off' && ok "OFF still says so in words, not just colour" || bad "OFF label missing"

# ---- 6: the lamp stays cheap — it is spawned on every render ----
t0=$(python3 -c 'import time;print(int(time.time()*1000))')
for i in $(seq 1 20); do frame $((i*137)) >/dev/null; done
t1=$(python3 -c 'import time;print(int(time.time()*1000))')
per=$(( (t1 - t0) / 20 ))
[ "$per" -lt 25 ] && ok "median render stays cheap (${per}ms/run, budget 25ms)" \
  || bad "statusline too slow: ${per}ms per run"

echo ""
echo "lamp: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
