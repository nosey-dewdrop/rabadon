#!/bin/bash
# export_test.sh — the ledger exports as valid OTLP/JSON any backend can read.
#
# Contract:
#   1. output is a single valid JSON object with the OTLP resourceSpans shape;
#   2. one trace id per pipe; a span per meaningful event;
#   3. a refusal (STOP/CHECK_FAIL/WOULD_BLOCK/REPAIR_FAIL) is status ERROR
#      (code 2) so it renders red in a trace viewer;
#   4. token counts surface as GenAI-semconv attributes;
#   5. drills never leave the machine (excluded from the export too);
#   6. timestamps are unix-nanos strings (OTLP requires string, not number).
set -u
cd "$(dirname "$0")/.."
EXPORT=./native/rabadon-export
[ -x "$EXPORT" ] || { echo "export_test: build first (make native/rabadon-export)"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "export_test: needs python3 to validate JSON"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

TMP=$(mktemp -d /tmp/rabadon-export-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export RABADON_DIR="$TMP/rd"; mkdir -p "$RABADON_DIR/spool"
NOW=1768046400000; export RABADON_NOW="$NOW"
TS=$((NOW - 3600000))
cat > "$RABADON_DIR/spool/2026-01-10.jsonl" <<EOF
{"v":1,"seq":1,"ts":$TS,"run":"r1","pipe":"alpha:session","ev":"STEP_START","step":"ls","tokensIn":100,"tokensOut":50}
{"v":1,"seq":1,"ts":$TS,"run":"r2","pipe":"alpha:session","ev":"STOP","reason":"BLOCKED","rule":"no-force-push-main","detail":"git push --force"}
{"v":1,"seq":1,"ts":$TS,"run":"r3","pipe":"beta:session","ev":"CHECK_FAIL","step":"Bash","fails":[{"check":"loop-stop","why":"3x"}]}
{"v":1,"seq":1,"ts":$TS,"run":"d1","pipe":"gamma:session","ev":"STOP","reason":"BLOCKED","rule":"drilled","detail":"x","drill":true}
EOF

echo "export: OTLP/JSON"

export OUT="$TMP/out.json"
"$EXPORT" --otlp --days 7 > "$OUT"

python3 -c 'import json,os; json.load(open(os.environ["OUT"]))' 2>/dev/null && pass "output is a single valid JSON object" || { fail "invalid JSON"; head -c 400 "$OUT"; }

python3 - <<'PY' && pass "OTLP resourceSpans/scopeSpans/spans shape" || fail "OTLP shape"
import json,os
d=json.load(open(os.environ["OUT"]))
sp=d["resourceSpans"][0]["scopeSpans"][0]["spans"]
assert isinstance(sp,list) and len(sp)>=3, sp
PY

python3 - <<'PY' && pass "one trace id per pipe (alpha != beta)" || fail "trace grouping"
import json,os
d=json.load(open(os.environ["OUT"]))
sp=d["resourceSpans"][0]["scopeSpans"][0]["spans"]
tids={}
for s in sp:
    pipe=[a["value"]["stringValue"] for a in s["attributes"] if a["key"]=="rabadon.pipe"][0]
    tids.setdefault(pipe,set()).add(s["traceId"])
assert len(tids["alpha:session"])==1 and len(tids["beta:session"])==1
assert tids["alpha:session"]!=tids["beta:session"]
PY

python3 - <<'PY' && pass "refusals are span status ERROR (code 2)" || fail "error status"
import json,os
d=json.load(open(os.environ["OUT"]))
sp=d["resourceSpans"][0]["scopeSpans"][0]["spans"]
errs=[s for s in sp if s.get("status",{}).get("code")==2]
names={s["name"] for s in errs}
assert any("no-force-push-main" in n for n in names), names
assert any("CHECK_FAIL" in n or "loop-stop" in n for n in names), names
PY

python3 - <<'PY' && pass "GenAI semconv token attributes present" || fail "genai attrs"
import json,os
d=json.load(open(os.environ["OUT"]))
sp=d["resourceSpans"][0]["scopeSpans"][0]["spans"]
keys={a["key"] for s in sp for a in s["attributes"]}
assert "gen_ai.system" in keys and "gen_ai.usage.input_tokens" in keys, keys
PY

python3 - <<'PY' && pass "drills are excluded from the export" || fail "drill leaked into export"
import json,os
d=json.load(open(os.environ["OUT"]))
sp=d["resourceSpans"][0]["scopeSpans"][0]["spans"]
assert not any("drilled" in s["name"] for s in sp)
PY

python3 - <<'PY' && pass "timestamps are unix-nano STRINGS (OTLP requires string)" || fail "timestamp type"
import json,os
d=json.load(open(os.environ["OUT"]))
s=d["resourceSpans"][0]["scopeSpans"][0]["spans"][0]
assert isinstance(s["startTimeUnixNano"],str) and s["startTimeUnixNano"].isdigit()
PY

echo "export: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
