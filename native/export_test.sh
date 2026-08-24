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
#   9. even a line with no `ev` ships, under a name a human can read;
#  10. one tool call is ONE row: the STEP_OK spans [its own START, itself] by
#      tool_use_id — not by adjacency — and the START ships as its child rather
#      than being dropped to buy the row;
#  11. a trace is a SESSION. `pipe` is a directory and a pipe-keyed trace was a
#      folder's entire history; a line with no session id falls back to the pipe,
#      then to its file, and every span says which of the three it got.
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
# export.cpp read, and the names NOTHING writes. It is now pipeline.cpp's shape,
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
#    REPAIR_START, which rabadon's own gate.cpp/repair.cpp/pipeline.cpp emit. The
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
#     `"tokens":<out>` (gate.cpp), and `rabadon-pipeline` appends
#     `"tokens","in","out","usd_e6","model"` (pipeline.cpp). On this machine the
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
# KEY ORDER IS PART OF THE FIXTURE: message{} before the top-level "type", the
# way Claude Code writes it, so the first "type" on the line is "message". The
# type-first shape hid a meter that read zero on every real transcript, which
# would have made this whole arm prove nothing. See usage_order_test.sh.
printf '{"parentUuid":null,"isSidechain":false,"message":{"model":"claude-opus-5","id":"msg_x","type":"message","role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":1200,"output_tokens":345}},"requestId":"req_x","type":"assistant","uuid":"u-x"}\n' > "$GATE_TS"
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
#     gate.cpp writes a bare "tokens". pipeline.cpp writes the full split —
#     "tokens","in","out","usd_e6","dur_ms","model" — on REPAIR_OK/REPAIR_FAIL
#     and STEP_TRY. Cost was read by nobody: `usd_e6` never appeared in
#     export.cpp at all, so the one number rabadon charges for stayed on the
#     machine while the README sold the OTLP surface as the standard view.
#
#     Fixture generated again, by driving rabadon-pipeline through a real failing
#     step with a stub proposer that writes the sidecar metrics the way
#     `claude -p --output-format json` does. No LLM, no network.
[ -x ./native/rabadon-pipeline ] && [ -x ./native/rabadon-verify ] \
  || { echo "export_test: build first (make native/rabadon-pipeline native/rabadon-verify)"; exit 1; }
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
  ./native/rabadon-pipeline "$LOOP_PROJ" "$LOOP_PROJ/plan.json" >/dev/null 2>&1
export LOOP_SPOOL_DIR="$LOOP_DIR/spool"

python3 - <<'PY' && pass "rabadon-pipeline really wrote a priced event, in ITS key names" || fail "no loop-emitted cost line — the arm below would prove nothing"
import glob, json, os
lines = []
for p in glob.glob(os.path.join(os.environ["LOOP_SPOOL_DIR"], "*.jsonl")):
    lines += [json.loads(l) for l in open(p) if l.strip()]
# POSITIVE: the producer priced the attempt and split the tokens.
priced = [e for e in lines if e.get("usd_e6")]
assert priced, ("rabadon-pipeline wrote no usd_e6", [e.get("ev") for e in lines])
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

# 12. a span is an INTERVAL, and the ledger knew the interval all along.
#
#     Every span this exporter shipped had startTimeUnixNano == endTimeUnixNano,
#     so a rabadon run rendered in a trace viewer as a row of zero-width marks.
#     The question a person opens a trace to answer — which step was slow — was
#     the one thing the document could not say, while pipeline.cpp had been writing
#     dur_ms beside the token count the whole time and nothing read it.
#
#     Same generated fixture as arm 11: the stub proposer leaves a sidecar with
#     duration_ms 2500, the loop fuses it in as dur_ms, and the export is asked
#     what the span's width is. The DIRECTION is the part that can silently
#     invert — `ts` is stamped when the line is appended, which is after the
#     work returned, so the span must END at the ledger's instant and start
#     2500ms earlier. A reader that got this backwards would put every span in
#     the future and no width check alone would notice.
python3 - <<'PY' && pass "the priced attempt is 2500ms WIDE, and it ends at the ledger's instant" || fail "the span is still zero-width, or the interval runs the wrong way"
import glob, json, os
sp = json.load(open(os.environ["LOOP_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
def attrs(s): return {a["key"]: list(a["value"].values())[0] for a in s["attributes"]}
priced = [s for s in sp if "rabadon.usd_e6" in attrs(s)]
assert priced, [(s["name"], sorted(attrs(s))) for s in sp]
s = priced[0]
width_ms = (int(s["endTimeUnixNano"]) - int(s["startTimeUnixNano"])) / 1e6
assert width_ms == 2500, ("span width", width_ms, s["name"])
# the producer's own line says when it was appended; the span ends there.
lines = []
for p in glob.glob(os.path.join(os.environ["LOOP_SPOOL_DIR"], "*.jsonl")):
    lines += [json.loads(l) for l in open(p) if l.strip()]
src = [e for e in lines if e.get("usd_e6") and e.get("dur_ms") == 2500][0]
assert int(s["endTimeUnixNano"]) == src["ts"] * 10**6, (s["endTimeUnixNano"], src["ts"])
assert int(s["startTimeUnixNano"]) == (src["ts"] - 2500) * 10**6, s["startTimeUnixNano"]
# mapping a field must not delete it: dur_ms still rides along raw, like every
# other unmapped key, so a reader that wants the producer's own number has it.
assert attrs(s).get("rabadon.dur_ms") == "2500", attrs(s)
# and an event that never had a duration is still an honest point in time
for other in sp:
    if "rabadon.dur_ms" in attrs(other):
        continue
    assert other["startTimeUnixNano"] == other["endTimeUnixNano"], (other["name"], "widened without a duration")
PY

#     The three refusals, because a wrong interval is worse than an honest
#     point. A duration bigger than the epoch instant it would be subtracted
#     from is not a duration; a negative one is not either; and an UNDATED
#     line's ts is the day its FILE is named for, not a moment, so widening it
#     would invent an interval out of a filename. All three stay point-in-time
#     and all three keep the raw value, so nothing is hidden from the reader.
export DUR_DIR="$TMP/rd-dur"; mkdir -p "$DUR_DIR/spool"
python3 - <<'PY'
import json, os
now = int(os.environ["RABADON_NOW"]); ts = now - 3600000
p = os.path.join(os.environ["DUR_DIR"], "spool", "2026-01-10.jsonl")
with open(p, "w") as f:
    w = lambda o: f.write(json.dumps(o) + "\n")
    base = {"v": 1, "run": "r1", "pipe": "delta:session"}
    w({**base, "seq": 1, "ts": ts, "ev": "STEP_TRY", "step": "sane", "dur_ms": 1500})
    w({**base, "seq": 2, "ts": ts, "ev": "STEP_TRY", "step": "negative", "dur_ms": -5})
    w({**base, "seq": 3, "ts": ts, "ev": "STEP_TRY", "step": "absurd", "dur_ms": ts + 1})
    w({**base, "seq": 4, "ev": "STEP_TRY", "step": "undated", "dur_ms": 1500})
    w({**base, "seq": 5, "ts": ts, "ev": "STEP_TRY", "step": "string", "dur_ms": "1500"})
PY
export DUR_OUT="$TMP/out-dur.json"
RABADON_DIR="$DUR_DIR" "$EXPORT" --otlp --days 7 > "$DUR_OUT"
python3 - <<'PY' && pass "a duration that is not one leaves the span a point, and keeps its raw value" || fail "export widened a span off a nonsense or undated duration"
import json, os
sp = json.load(open(os.environ["DUR_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
def attrs(s): return {a["key"]: list(a["value"].values())[0] for a in s["attributes"]}
by = {attrs(s)["rabadon.step"]: s for s in sp}
assert len(by) == 5, sorted(by)
def width(n): return int(by[n]["endTimeUnixNano"]) - int(by[n]["startTimeUnixNano"])
# POSITIVE first: the sane one in this same file really does widen, otherwise
# "everything is a point" would pass this arm for the wrong reason.
assert width("sane") == 1500 * 10**6, width("sane")
for n in ("negative", "absurd", "undated", "string"):
    assert width(n) == 0, (n, width(n))
    assert "rabadon.dur_ms" in attrs(by[n]), (n, "the refused duration was also swallowed")
# the undated span still says its time came from the filename
assert attrs(by["undated"]).get("rabadon.export.dated") == "no", attrs(by["undated"])
# EXACTNESS, pinned in its own right. ms -> ns used to be a double multiply,
# and ~1.79e18 is far past the 2^53 where a double still holds consecutive
# integers, so every timestamp shipped rounded to the nearest representable
# one — ts 1785841746341 left as ...340999936. Assert the full nine digits,
# not a tolerance: this document claims to BE the ledger.
ts = int(os.environ["RABADON_NOW"]) - 3600000
assert int(by["negative"]["startTimeUnixNano"]) == ts * 10**6, by["negative"]["startTimeUnixNano"]
assert by["negative"]["startTimeUnixNano"].endswith("000000"), by["negative"]["startTimeUnixNano"]
PY

# 13. a tool call is ONE call, and the ledger can finally say so.
#
#     STEP_START and STEP_OK are the two ends of one Claude Code tool call, and
#     for the whole life of this spool nothing written down joined them. `run`
#     is per-process (75,126 live events, 75,126 distinct run ids, zero reuse),
#     `seq` is 95.6% the literal 1, `prev` is a write-order chain that crosses
#     pipes. Pairing on "the next OK in the same pipe" closed 58.5% of the
#     starts and joined unrelated work in 17.6% of even those — a p99 of 15.5
#     minutes and one pair five days wide. `call` is the tool_use_id BOTH hooks
#     are handed, so the join is the identity itself.
#
#     The fixture is generated by the gate, and the two calls are NESTED on
#     purpose: START A, START B, OK B, OK A. Adjacency pairing gives A the width
#     of B and hands B's start the OK that closes A; only the id gets it right.
#     Both spans still ship — an exporter forbidden to drop events cannot buy
#     one row per call with a deleted START, so the START becomes the OK's
#     CHILD instead.
[ -x ./native/rabadon-gate ] || { echo "export_test: build first (make native/rabadon-gate)"; exit 1; }
PAIR_DIR="$TMP/rd-pair"; mkdir -p "$PAIR_DIR"; : > "$PAIR_DIR/enabled"
PAIR_CWD="$TMP/pairproj"; mkdir -p "$PAIR_CWD"
hook() {  # hook-name tool_use_id command [tool_response]
  if [ "$1" = "PreToolUse" ]; then
    printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"sess-pair-1","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"%s"}' \
      "$PAIR_CWD" "$3" "$2"
  else
    printf '{"hook_event_name":"PostToolUse","cwd":"%s","session_id":"sess-pair-1","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":"done","tool_use_id":"%s"}' \
      "$PAIR_CWD" "$3" "$2"
  fi | env -u RABADON_NOW -u RABADON_OFF RABADON_DIR="$PAIR_DIR" ./native/rabadon-gate >/dev/null 2>&1
}
hook PreToolUse  toolu_OUTER "echo outer"
hook PreToolUse  toolu_INNER "echo inner"
sleep 1
hook PostToolUse toolu_INNER "echo inner"
sleep 1
hook PostToolUse toolu_OUTER "echo outer"
export PAIR_SPOOL_DIR="$PAIR_DIR/spool"

python3 - <<'PY' && pass "the gate really wrote both ends of both calls, each with its tool_use_id" || fail "no call-bearing pair on the spool — the arms below would prove nothing"
import glob, json, os
lines = []
for p in glob.glob(os.path.join(os.environ["PAIR_SPOOL_DIR"], "*.jsonl")):
    lines += [json.loads(l) for l in open(p) if l.strip()]
evs = [(e.get("ev"), e.get("call")) for e in lines if e.get("ev") in ("STEP_START", "STEP_OK")]
assert evs == [("STEP_START", "toolu_OUTER"), ("STEP_START", "toolu_INNER"),
               ("STEP_OK", "toolu_INNER"), ("STEP_OK", "toolu_OUTER")], evs
# every one of them names the session too, or arm 14's producer half is a fiction
assert all(e.get("sess") == "sess-pair-1" for e in lines if e.get("ev")), \
    [(e.get("ev"), e.get("sess")) for e in lines]
PY

export PAIR_OUT="$TMP/out-pair.json"
export TMPERR="$TMP/pair.err"
env -u RABADON_NOW RABADON_DIR="$PAIR_DIR" "$EXPORT" --otlp --days 7 > "$PAIR_OUT" 2> "$TMPERR"
python3 - <<'PY' && pass "each tool call spans ITS OWN start->ok, nested calls and all" || fail "the call interval is wrong — adjacency, not identity"
import glob, json, os
sp = json.load(open(os.environ["PAIR_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
def attrs(s): return {a["key"]: list(a["value"].values())[0] for a in s["attributes"]}
lines = []
for p in glob.glob(os.path.join(os.environ["PAIR_SPOOL_DIR"], "*.jsonl")):
    lines += [json.loads(l) for l in open(p) if l.strip()]
led = {(e["ev"], e["call"]): e["ts"] for e in lines if e.get("ev") in ("STEP_START", "STEP_OK")}
oks = {attrs(s)["rabadon.call"]: s for s in sp if s["name"] == "STEP_OK"}
assert set(oks) == {"toolu_OUTER", "toolu_INNER"}, sorted(oks)
for call in ("toolu_OUTER", "toolu_INNER"):
    s = oks[call]
    assert int(s["startTimeUnixNano"]) == led[("STEP_START", call)] * 10**6, (call, s["startTimeUnixNano"])
    assert int(s["endTimeUnixNano"]) == led[("STEP_OK", call)] * 10**6, (call, s["endTimeUnixNano"])
    assert attrs(s)["rabadon.span.basis"] == "pair", attrs(s)
w = lambda c: int(oks[c]["endTimeUnixNano"]) - int(oks[c]["startTimeUnixNano"])
# POSITIVE: they really are wide, and the OUTER call really does contain the
# inner one. Adjacency pairing gives OUTER the inner width and this flips.
assert w("toolu_INNER") >= 1000 * 10**6, w("toolu_INNER")
assert w("toolu_OUTER") > w("toolu_INNER"), (w("toolu_OUTER"), w("toolu_INNER"))
PY

python3 - <<'PY' && pass "the START is not dropped to buy one row — it ships as the OK's child" || fail "a START vanished, lost its parent, or left the trace"
import json, os
sp = json.load(open(os.environ["PAIR_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
def attrs(s): return {a["key"]: list(a["value"].values())[0] for a in s["attributes"]}
starts = {attrs(s)["rabadon.call"]: s for s in sp if s["name"] == "STEP_START"}
oks = {attrs(s)["rabadon.call"]: s for s in sp if s["name"] == "STEP_OK"}
assert len(starts) == 2 and len(oks) == 2, [s["name"] for s in sp]
byid = {s["spanId"]: s for s in sp}
for call in ("toolu_OUTER", "toolu_INNER"):
    st, ok = starts[call], oks[call]
    # the START stays an honest point in time — it is one instant, not a range
    assert st["startTimeUnixNano"] == st["endTimeUnixNano"], (call, st)
    assert st.get("parentSpanId") == ok["spanId"], (call, st.get("parentSpanId"), ok["spanId"])
    # OTLP: a parent and its child share a trace, and the reference must resolve
    assert st["parentSpanId"] in byid, "dangling parent"
    assert st["traceId"] == ok["traceId"], (st["traceId"], ok["traceId"])
    # and the OK says which line it read the start off, so the join is checkable
    assert attrs(ok)["rabadon.span.start_source"] == attrs(st)["rabadon.export.source"], (attrs(ok), attrs(st))
    # the OK is not itself parented — it is the call
    assert "parentSpanId" not in ok, ok
# the books say it out loud, or the number is only in the code
err = open(os.environ["TMPERR"]).read()
assert "2 joined start->ok by call id" in err, err
PY

# The refusals. A wrong interval is worse than an honest point, and every one of
# these shapes would produce one: an OK that predates its START, an end whose ts
# is a FILE NAME rather than a moment, two ends in different sessions (OTLP says
# a parent and its child share a trace id), and a call with only one end.
export PAIRBAD_DIR="$TMP/rd-pairbad"; mkdir -p "$PAIRBAD_DIR/spool"
python3 - <<'PY'
import json, os
now = int(os.environ["RABADON_NOW"]); ts = now - 3600000
p = os.path.join(os.environ["PAIRBAD_DIR"], "spool", "2026-01-10.jsonl")
with open(p, "w") as f:
    w = lambda o: f.write(json.dumps(o) + "\n")
    b = {"v": 1, "pipe": "omega:session", "seq": 1}
    # the control: an ordinary call in the same file, so "nothing widened" cannot
    # pass this arm by accident
    w({**b, "run": "a1", "ts": ts,        "ev": "STEP_START", "call": "c-sane",  "sess": "s1", "step": "sane"})
    w({**b, "run": "a2", "ts": ts + 900,  "ev": "STEP_OK",    "call": "c-sane",  "sess": "s1", "step": "sane"})
    # backwards: the OK is older than the START
    w({**b, "run": "b1", "ts": ts + 500,  "ev": "STEP_START", "call": "c-back",  "sess": "s1", "step": "back"})
    w({**b, "run": "b2", "ts": ts,        "ev": "STEP_OK",    "call": "c-back",  "sess": "s1", "step": "back"})
    # undated START: its ts is the day the FILE is named for, not an instant
    w({**b, "run": "c1",                  "ev": "STEP_START", "call": "c-undat", "sess": "s1", "step": "undated"})
    w({**b, "run": "c2", "ts": ts + 700,  "ev": "STEP_OK",    "call": "c-undat", "sess": "s1", "step": "undated"})
    # the same tool_use_id in two different sessions: two traces, no link
    w({**b, "run": "d1", "ts": ts,        "ev": "STEP_START", "call": "c-split", "sess": "s1", "step": "split"})
    w({**b, "run": "d2", "ts": ts + 600,  "ev": "STEP_OK",    "call": "c-split", "sess": "s2", "step": "split"})
    # one end only, both ways round
    w({**b, "run": "e1", "ts": ts,        "ev": "STEP_START", "call": "c-open",  "sess": "s1", "step": "open"})
    w({**b, "run": "f1", "ts": ts + 400,  "ev": "STEP_OK",    "call": "c-orph",  "sess": "s1", "step": "orphan"})
PY
export PAIRBAD_OUT="$TMP/out-pairbad.json"
RABADON_DIR="$PAIRBAD_DIR" "$EXPORT" --otlp --days 7 > "$PAIRBAD_OUT" 2>/dev/null
python3 - <<'PY' && pass "a pair that is not one leaves both ends honest points, unlinked" || fail "export invented an interval or a parent out of a broken pair"
import json, os
sp = json.load(open(os.environ["PAIRBAD_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
def attrs(s): return {a["key"]: list(a["value"].values())[0] for a in s["attributes"]}
by = {(s["name"], attrs(s)["rabadon.step"]): s for s in sp}
assert len(by) == 10, sorted(by)
w = lambda n, st: int(by[(n, st)]["endTimeUnixNano"]) - int(by[(n, st)]["startTimeUnixNano"])
# POSITIVE first
assert w("STEP_OK", "sane") == 900 * 10**6, w("STEP_OK", "sane")
assert by[("STEP_START", "sane")].get("parentSpanId") == by[("STEP_OK", "sane")]["spanId"]
for step in ("back", "undated", "split", "open", "orphan"):
    for name in ("STEP_START", "STEP_OK"):
        s = by.get((name, step))
        if s is None: continue
        assert int(s["endTimeUnixNano"]) == int(s["startTimeUnixNano"]), (name, step, "widened")
        assert "parentSpanId" not in s, (name, step, "linked")
        assert "rabadon.span.basis" not in attrs(s), (name, step, attrs(s))
        # and nothing was swallowed on the way: the raw id still rides along
        assert attrs(s)["rabadon.call"].startswith("c-"), attrs(s)
PY

# 14. a TRACE is a session — not a folder.
#
#     `pipe` is spelled "<project>:session" and is a DIRECTORY. On this machine
#     227 of them cover nine days, and stitchu:session alone spans 214.1 hours:
#     every session and every subagent that ever ran in that folder wrote into
#     it, so `rabadon export` shipped a 24,056-span "trace" that was one
#     folder's entire history. No viewer renders that as anything. README has
#     advertised "one trace per session" the whole time.
#
#     Same pipe on every line here on purpose: keyed off the pipe these four
#     make ONE trace, which is the bug stated as a fixture.
export SESS_DIR="$TMP/rd-sess"; mkdir -p "$SESS_DIR/spool"
python3 - <<'PY'
import json, os
now = int(os.environ["RABADON_NOW"]); ts = now - 3600000
p = os.path.join(os.environ["SESS_DIR"], "spool", "2026-01-10.jsonl")
with open(p, "w") as f:
    w = lambda o: f.write(json.dumps(o) + "\n")
    b = {"v": 1, "seq": 1, "pipe": "omega:session"}
    w({**b, "run": "r1", "ts": ts,     "ev": "STEP_OK", "step": "in session A", "sess": "sess-A"})
    w({**b, "run": "r2", "ts": ts + 1, "ev": "STEP_OK", "step": "also A",       "sess": "sess-A"})
    w({**b, "run": "r3", "ts": ts + 2, "ev": "STEP_OK", "step": "in session B", "sess": "sess-B"})
    w({**b, "run": "r4", "ts": ts + 3, "ev": "STEP_OK", "step": "no session"})
    # neither a session nor a pipe: the trace falls all the way back to the file
    w({"v": 1, "seq": 1, "run": "r5", "ts": ts + 4, "ev": "STEP_OK", "step": "no pipe either"})
PY
export SESS_OUT="$TMP/out-sess.json"
RABADON_DIR="$SESS_DIR" "$EXPORT" --otlp --days 7 > "$SESS_OUT" 2>/dev/null
python3 - <<'PY' && pass "two sessions in one folder are two traces, and each span says which basis it got" || fail "the trace is still the folder, or the fallback ladder is silent"
import json, os
sp = json.load(open(os.environ["SESS_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
def attrs(s): return {a["key"]: list(a["value"].values())[0] for a in s["attributes"]}
by = {attrs(s)["rabadon.step"]: s for s in sp}
assert len(by) == 5, sorted(by)
# the premise: four of the five carry the SAME pipe, so a pipe-keyed export puts
# them in one trace. If this ever stops being true the arm proves nothing.
same = [by[k] for k in ("in session A", "also A", "in session B", "no session")]
assert len({attrs(s)["rabadon.pipe"] for s in same}) == 1, [attrs(s)["rabadon.pipe"] for s in same]
t = lambda k: by[k]["traceId"]
assert t("in session A") == t("also A"), "one session must be one trace"
assert t("in session A") != t("in session B"), "two sessions collapsed into one trace"
assert t("no session") not in (t("in session A"), t("in session B")), \
    "a line with no session id was filed under somebody's session"
assert t("no pipe either") != t("no session"), "the pipeless line joined the pipe's trace"
assert len({s["traceId"] for s in sp}) == 4, [s["traceId"] for s in sp]
# said on the span: a trace that is a folder's history must not pass for a session
a = lambda k: attrs(by[k])
assert a("in session A")["rabadon.export.trace_basis"] == "session", a("in session A")
assert a("no session")["rabadon.export.trace_basis"] == "pipe", a("no session")
assert a("no pipe either")["rabadon.export.trace_basis"] == "file", a("no pipe either")
# consumed, not swallowed: the id the trace was derived from is still readable
assert a("in session A")["rabadon.sess"] == "sess-A", a("in session A")
PY

python3 - <<'PY' && pass "a session that moves between folders stays ONE trace" || fail "the trace still tracks the directory"
import json, os
sp = json.load(open(os.environ["PAIR_OUT"]))["resourceSpans"][0]["scopeSpans"][0]["spans"]
# the gate-generated arm above: one real session, and every span of it in one trace
assert len({s["traceId"] for s in sp}) == 1, [s["traceId"] for s in sp]
def attrs(s): return {a["key"]: list(a["value"].values())[0] for a in s["attributes"]}
assert all(attrs(s)["rabadon.export.trace_basis"] == "session" for s in sp), [attrs(s) for s in sp]
assert all(attrs(s)["rabadon.sess"] == "sess-pair-1" for s in sp)
PY

echo "export: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
