#!/bin/bash
# usage_order_test.sh — the meter reads a REAL transcript, not a fixture-shaped one.
#
# WHY THIS EXISTS. usage.h decided "is this a billable assistant response?" by
# taking the FIRST `"type"` key on the line and requiring it to be "assistant".
# Every fixture in this repo (session_test.sh, budget_test.sh, export_test.sh)
# writes `{"type":"assistant","message":{...}}` — top-level type first — so the
# check passed everywhere it was looked at. Claude Code does not write that
# shape. A real transcript line is:
#
#   {"parentUuid":...,"isSidechain":false,"message":{"model":...,"id":...,
#    "type":"message","role":"assistant",...,"usage":{...}},"requestId":...,
#    "type":"assistant","uuid":...}
#
# `message` comes BEFORE the top-level `type`, so the first `"type"` on every
# real line is `"type":"message"` and the predicate returned false for all of
# them. Measured on this repo's own transcripts: 165, 382 and 1 usage-bearing
# lines respectively, and rabadon read `calls: 0` on all three. The counter, the
# Stop token ledger (gate.cpp) and the lens all read through this one predicate,
# so rabadon's third claim — "it tells you the money" — was reading zero in the
# field while the suite was green. The fixtures were the mask.
#
# So this test holds the shape rabadon actually meets, and it holds the shape
# the naive fix would break: a `"type":"user"` line whose TEXT quotes a
# fixture-shaped assistant line (this repo's own session logs are full of them,
# including this file). "Find any `"type":"assistant"` anywhere on the line"
# turns that into a phantom billable call. The key has to be read at the top
# level of the object or the meter is guessing.
#
# LIVE PROOF at the end: if a real Claude Code transcript exists on this
# machine, the meter must find calls in it. That assertion is skipped, never
# faked, when no transcript is present (clean container).
set -u
cd "$(dirname "$0")/.."

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

echo "usage order: the meter reads real transcript key order"

CXX=${CXX:-c++}
command -v "$CXX" >/dev/null 2>&1 || { echo "usage order: no $CXX on PATH"; exit 1; }
TMP=$(mktemp -d /tmp/rabadon-usageorder.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# the probe is the real header, nothing reimplemented: it prints
# "<calls> <in> <out> <cacheCreate> <cacheRead>" for whatever it is fed.
cat > "$TMP/probe.cpp" <<'CPP'
#include "native/usage.h"
#include <iostream>
#include <sstream>
int main() {
  std::ostringstream buf; buf << std::cin.rdbuf();
  long long calls = 0;
  Usage u = sum_usage_calls(buf.str(), calls);
  std::cout << calls << " " << u.in << " " << u.out << " "
            << u.cacheCreate << " " << u.cacheRead << "\n";
  return 0;
}
CPP
if ! "$CXX" -std=c++17 -O2 -I. -o "$TMP/probe" "$TMP/probe.cpp" >"$TMP/cc.log" 2>&1; then
  fail "the probe does not compile against the real meter (native/usage.h)"
  sed 's/^/    | /' "$TMP/cc.log" | tail -20
  echo "usage order: $ok passed, $bad failed"; exit 1
fi
pass "the probe compiles against the real meter (native/usage.h)"

# expect <name> <expected "calls in out cc cr"> < file
expect() {
  got=$("$TMP/probe" < "$2")
  if [ "$got" = "$3" ]; then pass "$1"
  else fail "$1 — expected [$3], got [$got]"; fi
}

# 1. the shape Claude Code actually writes. message{} first, top-level type last.
cat > "$TMP/real.jsonl" <<'EOF'
{"parentUuid":"8c996050-e9e8-4b5f-997b-733d9bf6d661","isSidechain":false,"message":{"model":"claude-opus-5","id":"msg_01","type":"message","role":"assistant","content":[{"type":"text","text":"hello"}],"stop_reason":null,"usage":{"input_tokens":681,"cache_creation_input_tokens":2940,"cache_read_input_tokens":33982,"output_tokens":7}},"requestId":"req_01","type":"assistant","uuid":"20da62c9","timestamp":"2026-08-24T18:29:00Z","sessionId":"49f2b3ea","version":"2.0.0","gitBranch":"kosu2"}
EOF
expect "a real transcript line is one billable call" "$TMP/real.jsonl" "1 681 7 2940 33982"

# 2. the compact stream-json shape (type first) still counts — no regression.
cat > "$TMP/compact.jsonl" <<'EOF'
{"type":"assistant","message":{"model":"claude-opus-5","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":40}}}
EOF
expect "the compact stream shape still counts" "$TMP/compact.jsonl" "1 100 40 0 0"

# 3. whitespace between key and value (RFC 8259, stock json.dumps) still counts.
printf '{"parentUuid":null, "message" : {"type": "message", "role": "assistant", "usage" : {"input_tokens": 5, "output_tokens": 6}}, "type" : "assistant"}\n' > "$TMP/ws.jsonl"
expect "whitespace around the top-level type still counts" "$TMP/ws.jsonl" "1 5 6 0 0"

# 4. a subagent result echoed on a user line is billed to the SUBAGENT's own
#    transcript. Summing it here double-counts, so it must stay uncounted.
cat > "$TMP/tur.jsonl" <<'EOF'
{"parentUuid":"a","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","content":"x"}]},"toolUseResult":{"usage":{"input_tokens":9999,"output_tokens":8888}},"type":"user","uuid":"b"}
EOF
expect "a toolUseResult line is not a billable call" "$TMP/tur.jsonl" "0 0 0 0 0"

# 5. THE TRAP. A user line whose TEXT quotes a fixture-shaped assistant line —
#    exactly what this repo's session logs contain. Matching `"type":"assistant"`
#    anywhere on the line invents a call that was never made. The key must be
#    read at the top level of the object.
cat > "$TMP/quote.jsonl" <<'EOF'
{"parentUuid":"a","isSidechain":false,"message":{"role":"user","content":[{"type":"text","text":"the fixture writes {\"type\":\"assistant\",\"message\":{\"usage\":{\"input_tokens\":777,\"output_tokens\":666}}} which is not a real line"}]},"type":"user","uuid":"b"}
EOF
expect "a quoted assistant line inside user text is not a call" "$TMP/quote.jsonl" "0 0 0 0 0"

# 6. and the same trap on a line that IS billable: the quoted numbers must not
#    be added to the real ones.
cat > "$TMP/both.jsonl" <<'EOF'
{"parentUuid":"a","isSidechain":false,"message":{"model":"claude-opus-5","type":"message","role":"assistant","content":[{"type":"text","text":"I will write {\"type\":\"assistant\",\"message\":{\"usage\":{\"input_tokens\":777}}} to the file"}],"usage":{"input_tokens":10,"output_tokens":20}},"type":"assistant","uuid":"b"}
EOF
expect "quoted numbers inside a real call are not summed" "$TMP/both.jsonl" "1 10 20 0 0"

# 7. mixed file: the three counted lines sum, the two decoys stay out.
cat "$TMP/real.jsonl" "$TMP/tur.jsonl" "$TMP/compact.jsonl" "$TMP/quote.jsonl" "$TMP/ws.jsonl" > "$TMP/mixed.jsonl"
expect "a mixed transcript counts exactly the billable lines" "$TMP/mixed.jsonl" "3 786 53 2940 33982"

# LIVE PROOF — a real transcript on this machine, if there is one. The bug was
# invisible to every fixture; only real bytes catch it, so real bytes are the
# last assertion. No transcript (clean container) = SKIP, never a silent pass.
live=""
for d in "$HOME/.claude/projects"/*; do
  [ -d "$d" ] || continue
  for f in "$d"/*.jsonl; do
    [ -f "$f" ] || continue
    if grep -q '"usage"' "$f" 2>/dev/null; then live="$f"; break 2; fi
  done
done
#
# "non-zero" is NOT the assertion. One compact line in a 425-line transcript
# makes a blind meter look alive. SPEC §2 promises a stranger's transcript reads
# with a stock parser, so the stock parser IS the expected value: python3 walks
# the same file, counts top-level type=="assistant" lines that carry
# message.usage and no toolUseResult, and the meter must agree exactly.
if [ -z "$live" ]; then
  echo "  SKIP - no real transcript on this machine (clean container); fixtures above still hold"
elif ! command -v python3 >/dev/null 2>&1; then
  echo "  SKIP - no python3 for the stock-parser oracle; fixtures above still hold"
else
  want=$(python3 - "$live" <<'PY'
import json, sys
c = i = o = cc = cr = 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line: continue
    try: obj = json.loads(line)
    except Exception: continue
    if not isinstance(obj, dict): continue
    if obj.get("type") != "assistant" or "toolUseResult" in obj: continue
    u = (obj.get("message") or {}).get("usage")
    if not isinstance(u, dict): continue
    c += 1
    i  += u.get("input_tokens") or 0
    o  += u.get("output_tokens") or 0
    cc += u.get("cache_creation_input_tokens") or 0
    cr += u.get("cache_read_input_tokens") or 0
print(c, i, o, cc, cr)
PY
)
  got=$("$TMP/probe" < "$live")
  if [ "$got" = "$want" ]; then
    pass "a real transcript agrees byte-for-byte with a stock parser [$want] ($(basename "$live"))"
  else
    fail "a real transcript disagrees with a stock parser — stock says [$want], meter says [$got] ($live)"
  fi
fi

echo "usage order: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
