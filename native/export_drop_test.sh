#!/bin/bash
# export_drop_test.sh — what leaves the machine must be countable against what
# went in, and what could not be read must be SAID.
#
# `rabadon export --otlp` is the surface Part II of the SPEC sells: the ledger
# rendered as OTLP/JSON so a stranger's collector can read a rabadon run. Every
# other reader of the spool (audit, stats, trace) answers to a count. This one
# never has. Measured on 3 August 2026 against the live spool: 80,690 lines in,
# 77,084 spans out, exit 0, stderr empty — the 3,606 gap is drills, which is
# correct, but nothing in the program could have told anyone that. There is no
# counter, no total, no diagnostic. The arithmetic is only reconstructable by
# someone who already read the source.
#
# Under that silence sits a real discard. export.cpp:225-226 is the whole of the
# window filter:
#
#     double ts = get_num(line, "ts");
#     if (!(ts >= cutoff)) continue;
#
# rbjson::get_num returns 0 for absent, mistyped AND unparseable (jsonl.h:30 says
# so out loud), and 0 is never >= a cutoff in 2026. So "this line is older than
# the window" and "this line is broken and I could not read it" take the same
# branch, and that branch is a bare `continue`. A truncated write, a torn line
# from a concurrent append, a `ts` a producer wrote as a string — each vanishes
# with the same silence as a line from last year.
#
# rbjson::find_field walks keys left to right and gives up at the first
# structural error, so WHERE the damage sits decides the outcome, and both
# outcomes are wrong in different directions:
#   - damage BEFORE `ts`  -> the line is dropped, silently;
#   - damage AFTER `ts`   -> the line is kept, but every field past the break
#                            reads as absent, and it ships as a span named
#                            UNKNOWN with an empty pipe, into the trace id of
#                            the literal string "?". A corrupt line becomes an
#                            anonymous event in a trace that does not exist.
#
# The live spool does not trigger the first case today, because the shipped
# emitters put `ts` third. That is a property of one emitter's key order, not of
# the format — and Part II exists precisely so a stranger's agent can write this
# ledger with a stock serializer, which orders keys however it likes.
#
# Section 3 is the other half, and it is the one that costs a whole payload
# rather than a line. The export is ONE JSON document. jesc() escapes control
# characters and passes every byte >= 0x80 through untouched, so a single
# invalid UTF-8 byte in an exported field makes the entire 25 MB document
# invalid JSON (RFC 8259 §8.1) and a collector rejects all 77,084 spans, not
# one. 65 lines of the live spool carry invalid UTF-8 today. They are harmless
# only by luck: 59 of them hold the bad bytes in `step`, and section 4 shows
# `step` is never exported.
#
# SAFETY: one mktemp root, RABADON_DIR points inside it, RABADON_NOW pins the
# clock. Nothing reads the operator's real spool and nothing is written outside
# the temp root.
set -u
cd "$(dirname "$0")/.."
EXPORT=./native/rabadon-export
[ -x "$EXPORT" ] || { echo "export_drop_test: build first (make native/rabadon-export)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

ROOT=$(mktemp -d /tmp/rabadon-export-drop.XXXXXX)
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/spool"

# A pinned clock, so "in the window" is a fact and not a function of the hour
# this test runs at.
NOW=1785600000000            # ms
export RABADON_NOW=$NOW
export RABADON_DIR="$ROOT"

# The census. Every line below is IN the window and is NOT a drill, so the
# honest answer for the whole file is "one span each". The last line is the one
# deliberate exclusion, and it is counted separately.
python3 - "$ROOT/spool/2026-08-02.jsonl" "$NOW" <<'PY'
import json, sys
path, now = sys.argv[1], int(sys.argv[2])
ts = now - 1000

def line(seq, ev, step, pipe="fixture:session"):
    return json.dumps({"v": 1, "seq": seq, "ts": ts, "run": "fx-%d" % seq,
                       "pipe": pipe, "ev": ev, "step": step,
                       "prev": "genesis"}).encode()

L = []
# well-formed, five of SPEC section 2's own verbs
L.append(line(1, "RUN_START",  "goal: fixture"))
L.append(line(2, "STEP_START", "bash: echo hello"))
L.append(line(3, "STEP_OK",    "ran: echo hello"))
L.append(line(5, "RUN_DONE",   "done"))
# a refusal in the shape gate.cpp really writes it: the rule lives in fails[],
# there is no top-level "rule" key
L.append(json.dumps({"v": 1, "seq": 4, "ts": ts, "run": "fx-4",
                     "pipe": "fixture:session", "ev": "CHECK_FAIL",
                     "step": "Bash", "mode": "watch",
                     "fails": [{"check": "no-force-push-main",
                                "why": "force-push to main"}],
                     "prev": "genesis"}).encode())
# the same class of invalid UTF-8 the live spool carries: a lead byte with no
# continuation byte, inside a JSON string
bad = b"\xc3"
L.append(line(6, "STEP_START", "bash: echo XX").replace(b"echo XX", b"echo " + bad + b"X"))
L.append(line(7, "STEP_OK", "ran: ok").replace(b"fixture:session", b"fixture:" + bad + b"ses"))
L.append(line(8, "MY_CUSTOM_EV", "bash: echo YY").replace(b"echo YY", b"echo " + bad + b"Y"))
# structurally broken, damage BEFORE ts
L.append(b'{"v":1 "seq":11,"ts":%d,"pipe":"fixture:session","ev":"STEP_OK"}' % ts)
L.append(b'["seq",12,"ts",%d,"ev","STEP_OK"]' % ts)
L.append(b'this is not json at all')
L.append(b'{}')
# ts absent, mistyped, null, or only nested
L.append(b'{"v":1,"seq":14,"pipe":"fixture:session","ev":"STEP_OK","step":"ran: no ts"}')
L.append(b'{"v":1,"seq":15,"ts":"%d","pipe":"fixture:session","ev":"STEP_OK"}' % ts)
L.append(b'{"v":1,"seq":16,"ts":null,"pipe":"fixture:session","ev":"STEP_OK"}')
L.append(b'{"v":1,"seq":17,"meta":{"ts":%d},"pipe":"fixture:session","ev":"STEP_OK"}' % ts)
# structurally broken, damage AFTER ts — kept, but blanked
L.append(b'{"v":1,"ts":%d,"seq" 20,"pipe":"fixture:session","ev":"STEP_OK"}' % ts)
# truncated mid-write, the shape a torn concurrent append leaves
L.append(line(9, "STEP_START", "bash: truncated")[:60])
IN_WINDOW = len(L)
# the ONE line that is legitimately excluded: older than the window
L.append(line(18, "STEP_OK", "ran: ancient").replace(str(ts).encode(), b"1000000000000"))

open(path, "wb").write(b"\n".join(L) + b"\n")
open(path + ".census", "w").write("%d %d\n" % (len(L), IN_WINDOW))
PY

read -r TOTAL_IN IN_WINDOW < "$ROOT/spool/2026-08-02.jsonl.census"
rm -f "$ROOT/spool/2026-08-02.jsonl.census"

"$EXPORT" --otlp --days 7 > "$ROOT/out.json" 2> "$ROOT/out.err"
RC=$?
SPANS=$(python3 -c 'import re,sys;print(len(re.findall(rb"\"traceId\":\"", open(sys.argv[1],"rb").read())))' "$ROOT/out.json")
ERRBYTES=$(wc -c < "$ROOT/out.err" | tr -d ' ')

echo "export: $TOTAL_IN line(s) in, $IN_WINDOW of them inside the window, $SPANS span(s) out, exit $RC"
echo

echo "1. every in-window, non-drill line reaches the collector"
[ "$SPANS" = "$IN_WINDOW" ] \
  && pass "$IN_WINDOW in-window line(s) -> $SPANS span(s)" \
  || fail "$IN_WINDOW in-window line(s) -> $SPANS span(s): $((IN_WINDOW - SPANS)) never left"

echo
echo "2. a line the exporter could not read is REPORTED, not swallowed"
if [ "$SPANS" = "$IN_WINDOW" ]; then
  pass "nothing was discarded, so there is nothing to report"
elif [ "$RC" != "0" ] || [ "$ERRBYTES" != "0" ]; then
  pass "the discard was announced (exit $RC, $ERRBYTES byte(s) on stderr)"
else
  fail "$((IN_WINDOW - SPANS)) line(s) discarded with exit 0 and an empty stderr"
fi

echo
echo "3. the payload is one JSON document, and it has to survive as one"
VERDICT=$(python3 - "$ROOT/out.json" <<'PY'
import json, sys
raw = open(sys.argv[1], "rb").read()
try:
    text = raw.decode("utf-8")
except UnicodeDecodeError as e:
    print("utf8 %s" % str(e)[:70]); raise SystemExit
try:
    json.loads(text)
except ValueError as e:
    print("json %s" % str(e)[:70]); raise SystemExit
print("ok")
PY
)
[ "$VERDICT" = "ok" ] \
  && pass "the OTLP payload decodes as UTF-8 and parses as JSON" \
  || fail "one bad byte in one field invalidated all $SPANS span(s) — $VERDICT"

echo
echo "4. a span says what the agent actually ran"
CARRIED=$(python3 - "$ROOT/out.json" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], "rb").read().decode("utf-8", "replace"))
spans = d["resourceSpans"][0]["scopeSpans"][0]["spans"]
hit = rule = 0
for s in spans:
    a = {x["key"]: list(x["value"].values())[0] for x in s["attributes"]}
    if any(isinstance(v, str) and "echo hello" in v for v in a.values()) or "echo hello" in s["name"]:
        hit += 1
    if a.get("rabadon.ev") == "CHECK_FAIL" and "no-force-push-main" in json.dumps(s):
        rule += 1
print("%d %d" % (hit, rule))
PY
)
CMD_SPANS=${CARRIED% *}; RULE_SPANS=${CARRIED#* }
[ "$CMD_SPANS" -ge 2 ] \
  && pass "the STEP_START/STEP_OK pair carries the command text" \
  || fail "the command text reached $CMD_SPANS span(s) — the ledger's step field is not exported for any of SPEC section 2's ten verbs"

[ "$RULE_SPANS" -ge 1 ] \
  && pass "the refusal names the rule that fired" \
  || fail "the CHECK_FAIL span is red with no rule and no command: export reads a top-level \"rule\" key, the gate writes fails[]"

echo
echo "5. a line the reader could not fully parse does not ship as an anonymous span"
GHOSTS=$(python3 - "$ROOT/out.json" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], "rb").read().decode("utf-8", "replace"))
spans = d["resourceSpans"][0]["scopeSpans"][0]["spans"]
n = 0
for s in spans:
    a = {x["key"]: list(x["value"].values())[0] for x in s["attributes"]}
    if a.get("rabadon.pipe", "") == "" and a.get("rabadon.ev", "") == "":
        n += 1
print(n)
PY
)
[ "$GHOSTS" = "0" ] \
  && pass "no span left with neither a pipe nor an event name" \
  || fail "$GHOSTS span(s) shipped with no ev and no pipe, into the trace id of the string \"?\""

echo
echo "export_drop_test: $ok ok, $bad failed"
[ "$bad" = "0" ] || exit 1
