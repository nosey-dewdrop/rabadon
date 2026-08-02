#!/bin/bash
# truth_level_order_test.sh — the strength number has to be orderable.
#
# `rabadon-truth --json` publishes `level` as a machine-readable field and its
# own --help documents the scale as 3 SUITE, 2 BUILD, 1 SYNTAX, 0 NONE. The code
# emitted the opposite: 1 for a real test suite, 3 for a bare syntax check, and 0
# for nothing at all. So the field was not merely mislabelled, it could not be
# compared in either direction -- 0 means nothing runnable and sat below 1, which
# meant the strongest rung. `level >= 2` read as "build or syntax but never the
# suite", and `level <= 1` read as "the suite, or nothing".
#
# Found on 2 August 2026 while measuring discovery on two foreign JavaScript
# repositories: one of them reported `level 1  SUITE (strong: real behaviour)`,
# a number and a word that contradict each other on the same line.
#
# Nothing in the repo ordered the field at the time, only `== 0` and a pair of
# equality checks for wording, so this closes a contract that was wrong before a
# consumer relied on it.
set -u
cd "$(dirname "$0")/.."
TRUTH=./native/rabadon-truth
[ -x "$TRUTH" ] || { echo "truth_level_order_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

ROOT=$(mktemp -d /tmp/rabadon-truth-order.XXXXXX)
trap 'rm -rf "$ROOT"' EXIT

lvl() { "$TRUTH" "$1" --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["level"])'; }
kind() { "$TRUTH" "$1" --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["kind"])'; }

# a repo whose own test suite is discoverable
SUITE="$ROOT/suite"; mkdir -p "$SUITE"
printf '{"name":"s","scripts":{"test":"node t.js","build":"tsc"}}' > "$SUITE/package.json"

# a repo that can only be built
BUILD="$ROOT/build"; mkdir -p "$BUILD"
printf '{"name":"b","scripts":{"build":"tsc"}}' > "$BUILD/package.json"

# a repo where only parsing is possible
SYNTAX="$ROOT/syntax"; mkdir -p "$SYNTAX"
printf 'print("hi")\n' > "$SYNTAX/a.py"

# a repo with nothing runnable
NONE="$ROOT/none"; mkdir -p "$NONE"
printf 'read me\n' > "$NONE/README.md"

L_SUITE=$(lvl "$SUITE"); L_BUILD=$(lvl "$BUILD"); L_SYNTAX=$(lvl "$SYNTAX"); L_NONE=$(lvl "$NONE")
echo "  measured: suite=$L_SUITE build=$L_BUILD syntax=$L_SYNTAX none=$L_NONE"

[ "$(kind "$SUITE")" = "suite" ] && pass "the suite repo is detected as a suite" \
  || fail "the suite repo was detected as $(kind "$SUITE") — the fixture is wrong, not the scale"

[ "$L_NONE" = "0" ] && pass "nothing runnable is 0" || fail "nothing runnable reported $L_NONE"

if [ "$L_SUITE" -gt "$L_BUILD" ] && [ "$L_BUILD" -gt "$L_SYNTAX" ] && [ "$L_SYNTAX" -gt "$L_NONE" ]; then
  pass "the scale is monotonic: suite > build > syntax > none"
else
  fail "the scale is not orderable: suite=$L_SUITE build=$L_BUILD syntax=$L_SYNTAX none=$L_NONE"
fi

# the number and the word on the same line must agree with --help
LINE=$("$TRUTH" "$SUITE" 2>/dev/null | head -1)
if echo "$LINE" | grep -q "level 3  SUITE"; then
  pass "the printed line agrees with the documented legend"
else
  fail "the printed line contradicts the legend: $LINE"
fi

# the twin: the legend in --help must be the scale the code emits, so a reader
# who trusts the help ranks repos the same way the binary does
HELP=$("$TRUTH" --help 2>&1)
if echo "$HELP" | grep -q "level 3 SUITE" && echo "$HELP" | grep -q "level 1 SYNTAX"; then
  pass "--help still documents 3 SUITE and 1 SYNTAX"
else
  fail "--help no longer documents the scale it emits"
fi

echo
echo "truth_level_order_test: $ok ok, $bad failed"
[ "$bad" = "0" ] || exit 1
