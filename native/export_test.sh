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
#   6. timestamps are unix-nanos strings (OTLP requires string, not number);
#   7. a stranger's serializer exports identically to rabadon's own bytes;
#   8. EVERY event renders — all ten of SPEC §2's `ev` values plus verbs this
#      repo has never heard of, counted in and counted out, with an unknown
#      event's own fields carried as attributes;
#   9. even a line with no `ev` ships, under a name a human can read.
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
{"v":1,"seq":1,"ts":$TS,"run":"r1","pipe":"alpha:session","ev":"STEP_START","step":"ls","tokens":150,"in":100,"out":50,"usd_e6":700}
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

# This fixture line used to read {"tokensIn":100,"tokensOut":50} — the names
# export.cpp read, and the names NOTHING writes. It is now loop.cpp's shape,
# with the values checked rather than just the key set: a key-presence assertion
# is happy with a reader that maps the wrong field.
python3 - <<'PY' && pass "GenAI semconv token + cost attributes carry the right values" || fail "genai attrs"
import json,os
d=json.load(open(os.environ["OUT"]))
sp=d["resourceSpans"][0]["scopeSpans"][0]["spans"]
a={x["key"]: list(x["value"].values())[0]
   for s in sp if s["name"]=="STEP_START" for x in s["attributes"]}
assert a.get("gen_ai.system")=="anthropic", a
assert a.get("gen_ai.usage.input_tokens")=="100", a
assert a.get("gen_ai.usage.output_tokens")=="50", a
assert a.get("rabadon.usd_e6")=="700", a
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
        e = {"v": 1, "seq": i + 1, "ts": ts + i * 1000,
             "run": "r%d" % i, "pipe": "omega:session", "ev": ev,
             "step": "s", "customField": "keepme"}
        # only the verb this repo has never heard of is priced — a stranger's
        # producer that both extends the vocabulary AND reports usage.
        if ev == "POLICY_ESCALATE":
            e.update({"tokens": 1545, "in": 1200, "out": 345, "usd_e6": 12345})
        # a third-party producer that mirrors .rabadon/state.json's field names
        # instead of the spool's. Hand-written on purpose: it is by definition
        # not this repo's shape, so no binary here could generate it.
        if ev == "REPAIR_OK":
            e.update({"tokensIn": 11, "tokensOut": 22})
        f.write(json.dumps(e, separators=(",", ":")) + "\n")
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

# The two MUSTs of SPEC §2 meet here: an unknown verb that is ALSO priced has to
# render generically AND reach the standard attributes. The token block runs off
# the line's fields, never off the verb — so a producer that extends the
# vocabulary is not charged for it by losing its usage. And the raw fields must
# still ride along as rabadon.<key>: the day someone adds "in"/"out" to
# is_mapped_field to tidy the duplication, an unknown event whose "out" meant
# something else entirely would lose it silently, which is the preservation MUST
# broken by a cleanup.
python3 - <<'PY' && pass "an unknown ev that is PRICED gets gen_ai.usage.* and keeps its raw fields" || fail "the priced unknown verb lost its usage or its payload"
import json, os
sp = json.load(open(os.environ["ALL_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
gen = [s for s in sp if s["name"] == "POLICY_ESCALATE"][0]
a = {x["key"]: list(x["value"].values())[0] for x in gen["attributes"]}
assert a.get("gen_ai.usage.input_tokens") == "1200", a
assert a.get("gen_ai.usage.output_tokens") == "345", a
assert a.get("rabadon.usd_e6") == "12345", a
# the split wins over the total: "tokens":1545 must not become an output count
assert a.get("gen_ai.usage.output_tokens") != "1545", a
assert a.get("rabadon.tokens") == "1545", ("raw field dropped by a mapping", a)
assert a.get("rabadon.in") == "1200" and a.get("rabadon.out") == "345", a
# a KNOWN, unpriced verb next to it stays clean — no manufactured usage block
known = [s for s in sp if s["name"] == "STEP_OK"][0]
ka = {x["key"] for x in known["attributes"]}
assert not any(k.startswith("gen_ai") for k in ka), ka
# and the state.json-mirror alias a stranger might write still maps
rep = [s for s in sp if s["name"] == "REPAIR_OK"][0]
ra = {x["key"]: list(x["value"].values())[0] for x in rep["attributes"]}
assert ra.get("gen_ai.usage.input_tokens") == "11", ra
assert ra.get("gen_ai.usage.output_tokens") == "22", ra
PY

# 9. the edge under the edge: a line with no `ev` at all. Not in SPEC's ten and
#    not an unknown verb either — but still something that happened, so the one
#    thing it must not do is vanish. It used to leave a span with an EMPTY name,
#    which is a blank row in a trace list: present, unreadable, as good as gone.
export NOEV_DIR="$TMP/rd-noev"; mkdir -p "$NOEV_DIR/spool"
python3 - <<'PY'
import json, os
now = int(os.environ["RABADON_NOW"]); ts = now - 3600000
p = os.path.join(os.environ["NOEV_DIR"], "spool", "2026-01-10.jsonl")
with open(p, "w") as f:
    f.write(json.dumps({"v": 1, "seq": 1, "ts": ts, "run": "r1",
                        "pipe": "omega:session", "note": "no ev field at all"}) + "\n")
    f.write(json.dumps({"v": 1, "seq": 2, "ts": ts + 1, "run": "r1",
                        "pipe": "omega:session", "ev": "STOP",
                        "reason": "BLOCKED", "rule": "x"}) + "\n")
PY
export NOEV_OUT="$TMP/out-noev.json"
RABADON_DIR="$NOEV_DIR" "$EXPORT" --otlp --days 7 > "$NOEV_OUT"
python3 - <<'PY' && pass "an event with no ev ships under a readable name, payload intact" || fail "the ev-less event vanished or rendered nameless"
import json, os
sp = json.load(open(os.environ["NOEV_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
names = [s["name"] for s in sp]
assert "STOP:x" in names, ("the ordinary event stopped shipping", names)
assert len(sp) == 2, ("2 events in, spans out:", len(sp), names)
assert "" not in names, ("a nameless span is a blank row in the viewer", names)
assert "UNKNOWN" in names, names
u = [s for s in sp if s["name"] == "UNKNOWN"][0]
a = {x["key"]: x["value"].get("stringValue") for x in u["attributes"]}
assert a.get("rabadon.note") == "no ev field at all", a
PY

# 10. the fixture is BUILT BY THE PRODUCER, not typed by the reader.
#
#     Arm 5 above asserts gen_ai.usage.* is present — and it passed for months
#     over a spool line no rabadon binary has ever written. The fixture at the
#     top of this file says "tokensIn"/"tokensOut" because that is what
#     export.cpp read; those two keys live in .rabadon/state.json and never in
#     a spool line. What `rabadon-gate` actually appends on Stop is
#     `"tokens":<out>` (gate.cpp), and `rabadon-loop` appends
#     `"tokens","in","out","usd_e6","model"` (loop.cpp). On this machine the
#     ledger held 1366 lines with a `"tokens"` key and 0 with a `"tokensIn"`
#     key, so every span that ever left carried rabadon.ev and rabadon.pipe
#     and nothing else — the advertised GenAI mapping was true of the test and
#     false of the product.
#
#     This is the same failure SPEC Part II §2 names: "a verifier whose true
#     predicate is 'these bytes came from me'". The cure is that the fixture
#     here is GENERATED — the gate writes the spool, the export reads it, and
#     nobody in between gets to choose the key names.
[ -x ./native/rabadon-gate ] || { echo "export_test: build first (make native/rabadon-gate)"; exit 1; }
GATE_DIR="$TMP/rd-gate"; mkdir -p "$GATE_DIR"; : > "$GATE_DIR/enabled"
GATE_CWD="$TMP/proj"; mkdir -p "$GATE_CWD"
GATE_TS="$TMP/transcript.jsonl"
printf '{"type":"assistant","message":{"usage":{"input_tokens":1200,"output_tokens":345}}}\n' > "$GATE_TS"
printf '{"hook_event_name":"Stop","cwd":"%s","session_id":"sess-export-arm10","transcript_path":"%s"}' \
  "$GATE_CWD" "$GATE_TS" \
  | env -u RABADON_NOW -u RABADON_OFF RABADON_DIR="$GATE_DIR" ./native/rabadon-gate >/dev/null 2>&1
export GATE_SPOOL_DIR="$GATE_DIR/spool"

python3 - <<'PY' && pass "the gate really emitted a token event, and NOT in the reader's key names" || fail "no gate-emitted token line — the arm below would prove nothing"
import glob, json, os
lines = []
for p in glob.glob(os.path.join(os.environ["GATE_SPOOL_DIR"], "*.jsonl")):
    lines += [json.loads(l) for l in open(p) if l.strip()]
# POSITIVE first: the producer wrote a machine-readable token count.
toks = [e for e in lines if isinstance(e.get("tokens"), int) and e["tokens"] > 0]
assert toks, ("rabadon-gate wrote no token-bearing event", lines)
assert toks[0]["tokens"] == 345, ("gate's token field is not the measured count", toks[0])
# and only now the negative it exists to justify: the key export.cpp used to
# read is not a key any producer writes.
assert not any("tokensIn" in e or "tokensOut" in e for e in lines), \
    ("a producer now writes tokensIn/tokensOut — re-read this arm", lines)
PY

export GATE_OUT="$TMP/out-gate.json"
env -u RABADON_NOW RABADON_DIR="$GATE_DIR" "$EXPORT" --otlp --days 7 > "$GATE_OUT"
python3 - <<'PY' && pass "a REAL gate-emitted token event round-trips to gen_ai.usage.*" || fail "the shipped binary's tokens never reach the standard attributes"
import json, os
sp = json.load(open(os.environ["GATE_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
assert sp, "the gate's own events exported as zero spans"
def attrs(s): return {a["key"]: list(a["value"].values())[0] for a in s["attributes"]}
step = [s for s in sp if s["name"] == "STEP_OK"]
assert len(step) == 1, [s["name"] for s in sp]
a = attrs(step[0])
# gate.cpp emits "tokens" = the session's cumulative OUTPUT count.
assert a.get("gen_ai.usage.output_tokens") == "345", a
assert a.get("gen_ai.system") == "anthropic", a
# RUN_DONE carries "tokens":0 — a zero is not a measurement, it must not
# manufacture an empty usage block.
done = [s for s in sp if s["name"] == "RUN_DONE"]
assert done, [s["name"] for s in sp]
assert not any(k.startswith("gen_ai.usage") for k in attrs(done[0])), attrs(done[0])
PY

# 11. the OTHER producer, and the number the product model actually sells.
#
#     gate.cpp writes a bare "tokens". loop.cpp writes the full split —
#     "tokens","in","out","usd_e6","dur_ms","model" — on REPAIR_OK/REPAIR_FAIL
#     and STEP_TRY. Cost was read by nobody: `usd_e6` never appeared in
#     export.cpp at all, so the one number rabadon charges for stayed on the
#     machine while the README sold the OTLP surface as the standard view.
#
#     Fixture generated again, by driving rabadon-loop through a real failing
#     step with a stub proposer that writes the sidecar metrics the way
#     `claude -p --output-format json` does. No LLM, no network.
[ -x ./native/rabadon-loop ] && [ -x ./native/rabadon-verify ] \
  || { echo "export_test: build first (make native/rabadon-loop native/rabadon-verify)"; exit 1; }
LOOP_DIR="$TMP/rd-loop"; mkdir -p "$LOOP_DIR"
# NOT under a name starting with "tmp." — drill rule 3 calls that pipe rabadon's
# own noise and would keep the whole arm home.
LOOP_PROJ="$TMP/loopproj"; mkdir -p "$LOOP_PROJ"
printf '43\n' > "$LOOP_PROJ/val.txt"
cat > "$LOOP_PROJ/prop.sh" <<PROPEOF
#!/usr/bin/env bash
# the sidecar accounting a real \`claude -p --output-format json\` leaves behind
cat > "$LOOP_DIR/.proposer-metrics.json" <<'JSON'
{"usage":{"input_tokens":1200,"output_tokens":345,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},
 "total_cost_usd":0.012345,"duration_ms":2500,"modelUsage":{"claude-opus-4-8":{"inputTokens":1200}}}
JSON
printf '42\n' > val.txt
PROPEOF
chmod +x "$LOOP_PROJ/prop.sh"
cat > "$LOOP_PROJ/plan.json" <<'EOF'
{ "steps": [ { "id":"s1","kind":"cmd","do":"true",
    "contract":[ {"type":"differential","run":"cat val.txt","expect":"42"} ] } ],
  "accept":[ {"type":"differential","run":"cat val.txt","expect":"42"} ] }
EOF
env -u RABADON_NOW -u RABADON_OFF RABADON_DIR="$LOOP_DIR" \
  RABADON_PROPOSER="bash $LOOP_PROJ/prop.sh" \
  ./native/rabadon-loop "$LOOP_PROJ" "$LOOP_PROJ/plan.json" >/dev/null 2>&1
export LOOP_SPOOL_DIR="$LOOP_DIR/spool"

python3 - <<'PY' && pass "rabadon-loop really wrote a priced event, in ITS key names" || fail "no loop-emitted cost line — the arm below would prove nothing"
import glob, json, os
lines = []
for p in glob.glob(os.path.join(os.environ["LOOP_SPOOL_DIR"], "*.jsonl")):
    lines += [json.loads(l) for l in open(p) if l.strip()]
# POSITIVE: the producer priced the attempt and split the tokens.
priced = [e for e in lines if e.get("usd_e6")]
assert priced, ("rabadon-loop wrote no usd_e6", [e.get("ev") for e in lines])
e = priced[0]
assert (e["usd_e6"], e["in"], e["out"], e["tokens"]) == (12345, 1200, 345, 1545), e
# only now the negative: the reader's old names are still absent here too.
assert not any("tokensIn" in x or "tokensOut" in x for x in lines), lines
PY

export LOOP_OUT="$TMP/out-loop.json"
env -u RABADON_NOW RABADON_DIR="$LOOP_DIR" "$EXPORT" --otlp --days 7 > "$LOOP_OUT"
python3 - <<'PY' && pass "loop's split tokens, model and COST all reach the export" || fail "the priced event lost its tokens, model or cost on the way out"
import json, os
sp = json.load(open(os.environ["LOOP_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
assert sp, "the loop's own events exported as zero spans"
def attrs(s): return {a["key"]: list(a["value"].values())[0] for a in s["attributes"]}
priced = [s for s in sp if any(k == "rabadon.usd_e6" for k in attrs(s))]
assert priced, ("no span carried a cost", [(s["name"], sorted(attrs(s))) for s in sp])
a = attrs(priced[0])
assert a["gen_ai.usage.input_tokens"] == "1200", a
assert a["gen_ai.usage.output_tokens"] == "345", a
assert a["gen_ai.request.model"] == "claude-opus-4-8", a
# money: the exact integer is the record, the USD double is the rendering.
assert a["rabadon.usd_e6"] == "12345", a
assert abs(float(a["rabadon.cost_usd"]) - 0.012345) < 1e-9, a
# and rabadon does not squat a namespace it does not own: OTel's GenAI
# conventions define no cost attribute, they derive money from token counts.
assert not any(k.startswith("gen_ai") and "cost" in k for k in a), a
PY

echo "export: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
