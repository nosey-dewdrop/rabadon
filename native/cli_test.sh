#!/bin/bash
# cli_test.sh — the first sixty seconds, for someone who has never seen this.
#
# Every case here is something a stranger does before they have read anything,
# and each one used to end badly:
#   - `rabadon --help`, `-h` and `help` all printed `unknown command` and
#     exited 1. That is the FIRST thing a new user types.
#   - a bare `rabadon` silently TOGGLED machine-wide enforcement, so the second
#     thing they type changed the tool's state without saying so — and typing
#     it twice put it back, which reads as "nothing happened".
#   - `rabadon trace`, the command that shows what the tool actually did,
#     rendered its whole interface in Turkish.
#
# None of these are bugs in the engine. All of them decide whether the engine
# ever gets run a second time.
set -u
cd "$(dirname "$0")/.."
CLI=./native/rabadon-cli.sh
[ -x "$CLI" ] || { echo "cli_test: $CLI is not executable"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

echo "cli: the stranger's first sixty seconds"

HOME_DIR=$(mktemp -d /tmp/rabadon-cli-test.XXXXXX)
trap 'rm -rf "$HOME_DIR"' EXIT
run() { RABADON_DIR="$HOME_DIR" RABADON_NOTIFY=0 "$CLI" "$@"; }

# ---- 1. help exists, under all three spellings a person actually types ----
for FLAG in --help -h help; do
  OUT=$(run $FLAG 2>&1); RC=$?
  [ $RC -eq 0 ] && pass "\`rabadon $FLAG\` exits 0" || fail "\`rabadon $FLAG\` exited $RC"
  printf '%s' "$OUT" | grep -qi "unknown command" && fail "\`rabadon $FLAG\` still says 'unknown command'" \
    || pass "\`rabadon $FLAG\` does not say 'unknown command'"
  # a help screen that lists no verbs is not a help screen
  MISSING=""
  for VERB in init usage exec audit doctor drill trace repair; do
    printf '%s' "$OUT" | grep -q "\b$VERB\b" || MISSING="$MISSING $VERB"
  done
  [ -z "$MISSING" ] && pass "\`rabadon $FLAG\` lists the verbs (init/usage/exec/audit/doctor/drill/trace/repair)" \
    || fail "\`rabadon $FLAG\` omits:$MISSING"
  printf '%s' "$OUT" | grep -q "rabadon init" \
    && pass "\`rabadon $FLAG\` shows a runnable example" || fail "\`rabadon $FLAG\` has no example"
done

# ---- 2. a bare `rabadon` REPORTS, it never changes state ----
# The flag file IS the state, so the test looks at the file rather than
# trusting the message printed about it.
BEFORE=$(ls "$HOME_DIR" 2>/dev/null | sort | tr '\n' ' ')
OUT=$(run 2>&1); RC=$?
AFTER=$(ls "$HOME_DIR" 2>/dev/null | sort | tr '\n' ' ')
[ $RC -eq 0 ] && pass "a bare \`rabadon\` exits 0" || fail "a bare \`rabadon\` exited $RC"
[ "$BEFORE" = "$AFTER" ] && pass "a bare \`rabadon\` did NOT change the enforce flag (watch -> watch)" \
  || fail "a bare \`rabadon\` changed state: [$BEFORE] -> [$AFTER]"
printf '%s' "$OUT" | grep -qE "WATCH|ON|SILENT" && pass "a bare \`rabadon\` prints the current mode" || fail "no mode printed"
printf '%s' "$OUT" | grep -q "read from:" && pass "it names the file the mode was read from" || fail "the source file is not named"

# the same, from the ON side — a report must not flip an armed machine off
run on >/dev/null 2>&1
BEFORE=$(ls "$HOME_DIR" 2>/dev/null | sort | tr '\n' ' ')
OUT=$(run 2>&1)
AFTER=$(ls "$HOME_DIR" 2>/dev/null | sort | tr '\n' ' ')
[ "$BEFORE" = "$AFTER" ] && pass "a bare \`rabadon\` did NOT change the enforce flag (on -> on)" \
  || fail "a bare \`rabadon\` disarmed an armed machine: [$BEFORE] -> [$AFTER]"
printf '%s' "$OUT" | grep -q "ON" && pass "it reports ON while ON" || fail "wrong mode reported"

# ---- 3. changing state still works, explicitly ----
run off >/dev/null 2>&1
[ ! -f "$HOME_DIR/enabled" ] && pass "\`rabadon off\` still turns it off" || fail "\`rabadon off\` did not"
run toggle >/dev/null 2>&1
[ -f "$HOME_DIR/enabled" ] && pass "\`rabadon toggle\` still flips it (the verb was kept, only the DEFAULT changed)" \
  || fail "\`rabadon toggle\` did not turn it on"
run toggle >/dev/null 2>&1
[ ! -f "$HOME_DIR/enabled" ] && pass "\`rabadon toggle\` flips it back" || fail "second toggle did not turn it off"

# ---- 4. the product speaks one language ----
# The trace renderer's interface strings were Turkish end to end. Assert on the
# SOURCE, because these strings only appear once a run exists, and a stranger
# hits them on their first real trace.
# python3, NOT `grep -P`: BSD grep has no -P, so on macOS every `grep -P`
# check exits 2 and the shell reads that as "no match found". A scan that
# silently reports clean on the maintainer's own machine is worse than no scan
# — this exact trap passed a Turkish-character check that had never run.
SCAN=$(python3 - <<'PY'
import re, sys
src = open('native/trace.cpp', encoding='utf-8').read()
lines = src.splitlines()
chars = [(i+1, l.strip()[:90]) for i, l in enumerate(lines) if re.search('[çğıöşüÇĞİÖŞÜ]', l)]
# whole words only: "accepted" contains "cepte", and a substring test would
# fail the suite forever on correct English
words = ['görev','YAKALANAN','YAKALANDI','TAMİR','REDDEDİLEN','adım','yakaladı',
         'kurtarılan','cepte','hakem','ucuzda','tamirden','koşmadı','yükseltilen']
found = sorted({w for w in words if re.search(r'(?<!\w)' + re.escape(w) + r'(?!\w)', src)})
print("CHARS", len(chars))
for n, l in chars[:5]: print("  |", n, l)
print("WORDS", " ".join(found))
PY
)
echo "$SCAN" | grep -q "^CHARS 0$" && pass "trace.cpp contains no Turkish characters" \
  || { fail "trace.cpp still contains Turkish characters"; echo "$SCAN" | sed 's/^/    /' | head -6; }
echo "$SCAN" | grep -q "^WORDS $" && pass "no Turkish interface words remain in trace.cpp" \
  || fail "trace.cpp still carries: $(echo "$SCAN" | sed -n 's/^WORDS //p')"

# The source being clean is not the same as the RENDER being clean, so the
# binary is driven over a synthetic run that exercises the translated lines:
# a caught step, a real repair, a rejected fake fix, a stop, a goal header.
if [ -x ./native/rabadon-trace ]; then
  TDIR=$(mktemp -d /tmp/rabadon-cli-trace.XXXXXX)
  mkdir -p "$TDIR/spool"
  DAY=$(date -u +%Y-%m-%d)
  NOW=$(python3 -c 'import time; print(int(time.time()*1000))')
  {
    echo "{\"v\":1,\"seq\":1,\"ts\":$NOW,\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"RUN_START\",\"goal\":\"ship the stats library\",\"steps\":3}"
    echo "{\"v\":1,\"seq\":2,\"ts\":$((NOW+10)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"validate-input\"}"
    echo "{\"v\":1,\"seq\":3,\"ts\":$((NOW+20)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STEP_OK\",\"step\":\"validate-input\",\"tier\":1}"
    echo "{\"v\":1,\"seq\":4,\"ts\":$((NOW+30)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"ship-statslib\"}"
    echo "{\"v\":1,\"seq\":5,\"ts\":$((NOW+40)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"CHECK_FAIL\",\"step\":\"ship-statslib\",\"why\":\"FAIL testsuite [python3 test_statslib.py]: the suite is RED\"}"
    echo "{\"v\":1,\"seq\":6,\"ts\":$((NOW+50)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"REPAIR_START\",\"step\":\"ship-statslib\",\"attempt\":1}"
    echo "{\"v\":1,\"seq\":7,\"ts\":$((NOW+60)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"REPAIR_OK\",\"step\":\"ship-statslib\",\"attempt\":1,\"tokens\":1200,\"usd_e6\":4000,\"dur_ms\":900}"
    echo "{\"v\":1,\"seq\":8,\"ts\":$((NOW+70)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STEP_OK\",\"step\":\"ship-statslib\",\"tier\":1}"
    echo "{\"v\":1,\"seq\":9,\"ts\":$((NOW+80)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"publish\"}"
    echo "{\"v\":1,\"seq\":10,\"ts\":$((NOW+90)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"CHECK_FAIL\",\"step\":\"publish\",\"why\":\"FAIL testsuite [python3 test_statslib.py]: the suite is RED\"}"
    echo "{\"v\":1,\"seq\":11,\"ts\":$((NOW+100)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"REPAIR_FAIL\",\"step\":\"publish\",\"attempt\":1}"
    echo "{\"v\":1,\"seq\":12,\"ts\":$((NOW+110)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STOP\",\"reason\":\"BLOCKED\",\"detail\":\"publish would not pass its contract\"}"
    echo "{\"v\":1,\"seq\":13,\"ts\":$((NOW+120)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"RUN_DONE\",\"verdict\":\"CHECK_FAILED\"}"
  } > "$TDIR/spool/$DAY.jsonl"

  RABADON_DIR="$TDIR" ./native/rabadon-trace > "$TDIR/render.txt" 2>&1 || true
  RENDER_BYTES=$(wc -c < "$TDIR/render.txt" | tr -d ' ')
  if [ "$RENDER_BYTES" -lt 50 ]; then
    fail "trace rendered nothing for the synthetic run (${RENDER_BYTES} bytes) — the language check would be vacuous"
  else
    pass "trace renders the synthetic run (${RENDER_BYTES} bytes of output to scan)"
    python3 -c "
import re, sys
t = open('$TDIR/render.txt', encoding='utf-8', errors='replace').read()
bad = [l for l in t.splitlines() if re.search('[çğıöşüÇĞİÖŞÜ]', l)]
if bad:
    print('    | ' + '\n    | '.join(bad[:5]))
    sys.exit(1)
sys.exit(0)" && pass "the RENDERED trace contains no Turkish characters" \
      || fail "the rendered trace still prints Turkish"
    grep -qi "caught" "$TDIR/render.txt" && pass "the rendered trace speaks English (says 'caught')" \
      || { fail "the render does not contain the English verdict wording"; head -12 "$TDIR/render.txt" | sed 's/^/    | /'; }
  fi
  rm -rf "$TDIR"
fi

echo "cli: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
