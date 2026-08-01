#!/bin/bash
# export_test.sh — the ledger exports as valid OTLP/JSON any backend can read.
#
# Contract:
#   1. output is a single valid JSON object with the OTLP resourceSpans shape;
#   2. one trace id per pipe; a span per meaningful event;
#   3. a refusal (STOP/CHECK_FAIL/WOULD_BLOCK/REPAIR_FAIL) is status ERROR
#      (code 2) so it renders red in a trace viewer;
#   4. token counts surface as GenAI-semconv attributes;
#   5. drills never leave the machine — all four rules `rabadon usage` excludes
#      by (emit tag, marker session id, self pipe, drill window), and the
#      exported refusal count matches the local one;
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
{"v":1,"seq":1,"ts":$TS,"run":"d2","pipe":"delta:session","ev":"STOP","reason":"BLOCKED","rule":"marker-drill","sid":"drill-42"}
{"v":1,"seq":1,"ts":$TS,"run":"d3","pipe":"rabadon-bench-x:session","ev":"STOP","reason":"BLOCKED","rule":"bench-noise"}
{"v":1,"seq":1,"ts":$TS,"run":"d4","pipe":"epsilon:session","ev":"RUN_START","sid":"doctor-7"}
{"v":1,"seq":2,"ts":$((TS+5000)),"run":"d5","pipe":"epsilon:session","ev":"STOP","reason":"BLOCKED","rule":"window-fallout"}
{"v":1,"seq":1,"ts":$TS,"run":"d6","pipe":"zeta:session","ev":"HEARTBEAT","sid":"fleet-9"}
{"v":1,"seq":2,"ts":$((TS+5000)),"run":"d7","pipe":"zeta:session","ev":"STOP","reason":"BLOCKED","rule":"zeta-fallout"}
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

python3 - <<'PY' && pass "all four drill shapes stay home, real refusals still ship" || fail "a drill shape leaked into the export"
import json,os
d=json.load(open(os.environ["OUT"]))
sp=d["resourceSpans"][0]["scopeSpans"][0]["spans"]
names={s["name"] for s in sp}
# POSITIVE first: rename a rule and the exclusions below start passing for
# free. The only defence is a check that fails when real work stops shipping.
assert any("no-force-push-main" in n for n in names), ("real refusal missing", names)
assert any("loop-stop" in n or "CHECK_FAIL" in n for n in names), ("real check fail missing", names)
assert len(sp) == 3, ("exactly the three real events ship, got", sorted(names))
# and now each drill shape rabadon usage already excludes, one by one
for shape, rule in [("1 emit tag", "drilled"),
                    ("2 marker session id", "marker-drill"),
                    ("3 self pipe", "bench-noise"),
                    ("4 window association", "window-fallout"),
                    # the marker that names this drill is a HEARTBEAT, an event
                    # export itself never ships: classify every line or a drill
                    # whose marker is invisible to the exporter reads as work
                    ("4 window, marker on a non-exported event", "zeta-fallout")]:
    assert not any(rule in n for n in names), ("rule " + shape + " leaked", sorted(names))
pipes={a["value"]["stringValue"] for s in sp for a in s["attributes"] if a["key"]=="rabadon.pipe"}
assert not any(p.startswith("rabadon-bench") for p in pipes), pipes
PY

# The point of the export is that someone else reads it. If it says ERROR more
# times than `rabadon usage` says refused, it is inflating catches off-machine.
python3 - <<'PY' && pass "exported ERROR spans agree with rabadon usage's refused count" || fail "export and usage disagree on what a drill is"
import json,os,subprocess
d=json.load(open(os.environ["OUT"]))
sp=d["resourceSpans"][0]["scopeSpans"][0]["spans"]
stops=[s for s in sp if s["name"].startswith("STOP") and s.get("status",{}).get("code")==2]
u=json.loads(subprocess.check_output(["./native/rabadon-stats","--json","--days","7"],
    env={**os.environ,"RABADON_DIR":os.environ["RABADON_DIR"],"RABADON_NOW":os.environ["RABADON_NOW"]}))
assert u["totals"]["refused"] == len(stops), (u["totals"]["refused"], len(stops), [s["name"] for s in stops])
assert u["totals"]["drillsExcluded"] > 0, u["totals"]
PY

python3 - <<'PY' && pass "timestamps are unix-nano STRINGS (OTLP requires string)" || fail "timestamp type"
import json,os
d=json.load(open(os.environ["OUT"]))
s=d["resourceSpans"][0]["scopeSpans"][0]["spans"][0]
assert isinstance(s["startTimeUnixNano"],str) and s["startTimeUnixNano"].isdigit()
PY

# 7. the same events from a STRANGER'S serializer. SPEC §2 says single-line
#    JSON and fixes no byte layout; SPEC Part II exists so someone else's agent
#    can write this spool. get_field matched the literal `"key":"`, so a spool
#    with a space after the colon yielded an empty `ev` for every line, nothing
#    matched the exportable set, and this binary emitted valid OTLP with an
#    EMPTY spans array — a silent zero. rabadon's own g3 evidence ledger,
#    reports/2026-08-01-g3-first-held-repair/04-ledger-events.jsonl, is written
#    that way: 10 events, 0 spans.
#
#    The arm demands the spaced spool export EXACTLY what its compact twin does,
#    and asserts the span count is non-zero first — otherwise "0 == 0" would let
#    a blind reader pass.
export SPACED_DIR="$TMP/rd-spaced"; mkdir -p "$SPACED_DIR/spool"
python3 - <<'PY'
import json, os, glob
for src in glob.glob(os.path.join(os.environ["RABADON_DIR"], "spool", "*.jsonl")):
    dst = os.path.join(os.environ["SPACED_DIR"], "spool", os.path.basename(src))
    with open(dst, "w") as f:
        for line in open(src):
            line = line.strip()
            if line:
                f.write(json.dumps(json.loads(line)) + "\n")  # default ": " / ", "
PY
grep -q '"ev": "STOP"' "$SPACED_DIR/spool/2026-01-10.jsonl" && pass "the stranger spool really is stock-serialized (\"ev\": \" with a space)" || fail "spaced fixture is not spaced — the arm would prove nothing"

export SPACED_OUT="$TMP/out-spaced.json"
RABADON_DIR="$SPACED_DIR" "$EXPORT" --otlp --days 7 > "$SPACED_OUT"
python3 - <<'PY' && pass "a stock-serialized spool exports the SAME spans as its compact twin" || fail "spacing changes the export — the reader is fingerprinting the emitter"
import json, os
a = json.load(open(os.environ["OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
b = json.load(open(os.environ["SPACED_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
assert len(a) > 0, "compact export is empty — the comparison would be vacuous"
assert len(b) == len(a), (len(a), len(b), [s["name"] for s in b])
assert b == a, "spans differ beyond count"
PY

# 8. the WHOLE vocabulary, plus a verb this repo has never heard of.
#    SPEC §2 fixes ten `ev` values and adds a MUST: "unknown `ev` values MUST
#    be rendered generically, never dropped". export.cpp filtered every line
#    through a hardcoded eight-name allow-list instead, so it dropped both the
#    unknown verbs (the MUST) and two of SPEC's own ten — STEP_OK and
#    REPAIR_START, which rabadon's own gate.cpp/repair.cpp/loop.cpp emit. The
#    G3 proof ledger (5 REPAIR_START, 2 REPAIR_OK, 3 REPAIR_FAIL) exported as
#    5 spans: repairs that finish without ever starting.
#
#    This is a COUNT assertion on purpose. "the eleven names are present" alone
#    would still pass if a future allow-list kept eleven and dropped a twelfth;
#    n_in == n_out is the shape an allow-list cannot creep back through.
export ALL_DIR="$TMP/rd-all"; mkdir -p "$ALL_DIR/spool"
export ALL_EVS='RUN_START STEP_START STEP_OK CHECK_FAIL WOULD_BLOCK REPAIR_START REPAIR_OK REPAIR_FAIL STOP RUN_DONE POLICY_ESCALATE'
python3 - <<'PY'
import json, os
now = int(os.environ["RABADON_NOW"]); ts = now - 3600000
evs = os.environ["ALL_EVS"].split()
p = os.path.join(os.environ["ALL_DIR"], "spool", "2026-01-10.jsonl")
with open(p, "w") as f:
    for i, ev in enumerate(evs):
        f.write(json.dumps({"v": 1, "seq": i + 1, "ts": ts + i * 1000,
                            "run": "r%d" % i, "pipe": "omega:session", "ev": ev,
                            "step": "s", "customField": "keepme"},
                           separators=(",", ":")) + "\n")
PY
export ALL_OUT="$TMP/out-all.json"
RABADON_DIR="$ALL_DIR" "$EXPORT" --otlp --days 7 > "$ALL_OUT"
python3 - <<'PY' && pass "all ten SPEC ev values plus one unknown verb render — 11 in, 11 out" || fail "the export dropped an ev value"
import json, os
evs = os.environ["ALL_EVS"].split()
sp = json.load(open(os.environ["ALL_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
names = [s["name"] for s in sp]
missing = [e for e in evs if e not in names]
assert not missing, ("dropped from the export: " + repr(missing), names)
assert len(sp) == len(evs), ("11 events in, spans out:", len(sp), names)
assert names == evs, ("spans are not in ledger order", names)
PY

# SPEC §2's other MUST: "unknown fields MUST be preserved". A generic span that
# renders the verb but throws its payload away still loses the event's meaning,
# and a fixed C struct can only carry what it was compiled to know.
python3 - <<'PY' && pass "an unknown ev carries its own fields as attributes" || fail "unknown fields dropped on the generic span"
import json, os
sp = json.load(open(os.environ["ALL_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
gen = [s for s in sp if s["name"] == "POLICY_ESCALATE"]
assert len(gen) == 1, [s["name"] for s in sp]
a = {x["key"]: x["value"].get("stringValue") for x in gen[0]["attributes"]}
assert a.get("rabadon.ev") == "POLICY_ESCALATE", a
assert a.get("rabadon.customField") == "keepme", ("the third-party field is gone", a)
assert a.get("rabadon.pipe") == "omega:session", a
PY

echo "export: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
