#!/usr/bin/env bash
# R6 acceptance — the counter: one honest line at session close.
#
# WRITTEN BEFORE THE CODE and red on the day it is written.
#
# WHAT R6 IS. One line, at session close, inside `rabadon usage`:
#
#     rabadon: N hata zinciri kesildi, M'i anında düzeltildi, tahmini X $ kurtarıldı.
#
# That line is the shop window. It is also the single place where this product
# can most cheaply lie, and a counter that has ever inflated one number is worth
# less than no counter at all — the user cannot audit dollars, so the only thing
# holding the number up is that every digit is derived from the ledger and can
# be re-derived in front of them. Law 5 and Law 7.
#
# SO THIS FILE IS MOSTLY A LIE DETECTOR, NOT A FEATURE CHECKLIST.
# Claims 1-3 assert the number is RIGHT on fixtures whose answer is computed by
# hand, here, from the same inputs. Claim 4 — the longest — asserts the counter
# SHUTS UP when it does not know: no transcript, no price, no history, no
# intervention. Claim 5 asserts it can show its work. Claim 6 asserts it did not
# widen the CLI or move onto the hot path. Claim 7 is the regression net.
#
# THE ARITHMETIC THIS FILE HOLDS THE CODE TO (docs/COUNTER.md must say the same;
# the formula is read FROM here, never hand-synced):
#
#     saved_usd = median(uncut_chain_lengths) * chains_cut * avg_call_usd
#                 - inject_usd - repair_usd
#
#   chains_cut        a repeat / oscillation / root-migration sequence in THIS
#                     session that ended with a block (STOP) or an injection
#                     (INJECT). Derived from the ledger, not from anybody's word.
#   fixed_instantly   within the 3 moves after an INJECT the same err_sig never
#                     appears again, AND (if a suite ran) it went green. The
#                     agent SAYING it fixed the thing is an assertion, not
#                     evidence — claimed_rc is a claim. Fixture 1c drives an
#                     agent that says "fixed it" and is lying, and the counter
#                     that believes it goes red.
#   median(...)       measured, from the ledger: past chains that ran to
#                     completion UNCUT. Never a constant. Fewer than
#                     MIN_HISTORY of them and the dollar figure is not printed
#                     at all ("ölçüm birikiyor").
#   avg_call_usd      this session's real cost / this session's assistant calls,
#                     read from the agent's own local transcript
#                     (~/.claude/projects/*.jsonl). Nothing goes to the network.
#   inject_usd        what rabadon's own injected characters cost. If they
#                     cannot be told apart inside the transcript, the charge is
#                     written at the UPPER bound: 400 chars * injections,
#                     CHARS_PER_TOKEN=4, priced as input. No rounding our way.
#   repair_usd        the repair arm's tokens, when there was one.
#
# PRICES: the LiteLLM table, cached on disk, four SEPARATE classes — input,
# output, cache-write, cache-read. In a long session most volume is cache-read
# at a tenth of input; a counter that folds it into input reports a number
# several times too large and it reports it in OUR favour. Claim 2b computes
# both the right and the folded answer and requires the right one.
#
# WHAT --json MUST CARRY (the counter's machine-readable contract, since M2's
# share card is generated from it and not by hand):
#     .counter.chains_cut          integer
#     .counter.fixed_instantly     integer
#     .counter.saved_usd           number, or null when it must not be printed
#     .counter.reason              why saved_usd is null (string, else null)
#     .counter.estimated           true whenever saved_usd is non-null
#     .counter.median_uncut_chain  number, or null
#     .counter.avg_call_usd        number, or null
#     .counter.inject_usd          number
#     .counter.inject_bound        "upper" | "measured"
#     .counter.repair_usd          number
#     .counter.prices.source       "litellm"
#     .counter.prices.cached       path to the offline cache, which must exist
#     .counter.prices.rates        {input,output,cache_write,cache_read} per Mtok
#
# NO VACUOUS PASSES. Every fixture first proves the gate actually saw it: an
# empty spool means the assertion below it proved nothing and is RED, not green.
# An empty ledger is a failure of this script, not a quiet success.

set -uo pipefail
export LC_ALL=C
export TZ=UTC

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

GATE="$ROOT/native/rabadon-gate"
STATS="$ROOT/native/rabadon-stats"
COUNTER_DOC="$ROOT/docs/COUNTER.md"

PASS_N=0; FAIL_N=0; C1_FAIL=0
pass() { printf 'PASS  %s\n' "$1"; PASS_N=$((PASS_N + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL_N=$((FAIL_N + 1)); }
note() { printf '      %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

[ -x "$GATE" ]  || { printf 'FAIL  no gate binary — run make first\n'; exit 1; }
[ -x "$STATS" ] || { printf 'FAIL  no rabadon-stats binary — run make first\n'; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL  python3 required\n'; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rbr6.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

# --- the constants this file legislates, and docs/COUNTER.md must match -----
FORMULA='saved_usd = median(uncut_chain_lengths) * chains_cut * avg_call_usd - inject_usd - repair_usd'
CHARS_PER_TOKEN=4
UPPER_CHARS=400
MIN_HISTORY=3

# ---------------------------------------------------------------------------
# One sandbox per scenario: its own HOME (spool + transcripts) and its own
# project tree, so "what did this session cost" is always a question about one
# session's own bytes.
NEW_HOME=""; NEW_PROJ=""; PROJ_SLUG=""; LENS=""
sandbox() {
  NEW_HOME="$(mktemp -d "$WORK/h.XXXXXX")"
  NEW_PROJ="$(mktemp -d "$WORK/p.XXXXXX")"
  mkdir -p "$NEW_HOME/.rabadon/spool" "$NEW_PROJ/.git" "$NEW_PROJ/src" "$NEW_PROJ/tests"
  printf 'ref: refs/heads/main\n' > "$NEW_PROJ/.git/HEAD"
  PROJ_SLUG="$(printf '%s' "$NEW_PROJ" | tr '/.' '--')"
  LENS="$NEW_HOME/.claude/projects/$PROJ_SLUG"
  mkdir -p "$LENS"
}
enforce() { : > "$NEW_HOME/.rabadon/enabled"; }
watch()   { rm -f "$NEW_HOME/.rabadon/enabled"; }

# ev <hook> <tool> <session> <json-tool-input> [tool_response]
ev() {
  local hook="$1" tool="$2" sid="$3" input="$4" resp="${5:-}"
  local j
  j="$(printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s","transcript_path":"%s","tool_name":"%s","tool_input":%s' \
        "$hook" "$sid" "$NEW_PROJ" "$LENS/$sid.jsonl" "$tool" "$input")"
  [ -n "$resp" ] && j="$j,\"tool_response\":$(jstr "$resp")"
  j="$j}"
  printf '%s' "$j" | env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" \
    RABADON_LENS_DIR="$NEW_HOME/.claude/projects" RABADON_NOTIFY=0 \
    ${EXTRA_ENV:-} "$GATE" 2>/dev/null
}
EXTRA_ENV=""

ran() { # ran <sid> <command> <output>
  ev PreToolUse  Bash "$1" "{\"command\":$(jstr "$2")}" >/dev/null
  ev PostToolUse Bash "$1" "{\"command\":$(jstr "$2")}" "$3" >/dev/null
}
edit() { # edit <sid> <relpath> <text>
  ev PreToolUse Edit "$1" \
    "{\"file_path\":$(jstr "$NEW_PROJ/$2"),\"old_string\":\"\",\"new_string\":$(jstr "$3")}" >/dev/null
}

# the session close. SessionEnd if the gate answers to it, Stop otherwise —
# the plan names both, in that order.
CLOSE_HOOK=""
close_line() { # close_line <sid>  -> the counter line on stdout, if any
  local sid="$1" out
  for h in SessionEnd Stop; do
    out="$(printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s","transcript_path":"%s"}' \
            "$h" "$sid" "$NEW_PROJ" "$LENS/$sid.jsonl" \
          | env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" \
                RABADON_LENS_DIR="$NEW_HOME/.claude/projects" RABADON_NOTIFY=0 \
                ${EXTRA_ENV:-} "$GATE" 2>/dev/null)"
    if printf '%s' "$out" | grep -q '^rabadon:'; then CLOSE_HOOK="$h"; printf '%s' "$out"; return 0; fi
  done
  CLOSE_HOOK=""
  printf '%s' ""
}

usage_json()    { env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" \
                      RABADON_LENS_DIR="$NEW_HOME/.claude/projects" \
                      "$STATS" --days 7 --json 2>/dev/null; }
usage_explain() { env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" \
                      RABADON_LENS_DIR="$NEW_HOME/.claude/projects" \
                      "$STATS" --days 7 --explain 2>/dev/null; }

# --- reading the spool ------------------------------------------------------
spool_lines() { cat "$NEW_HOME"/.rabadon/spool/*.jsonl 2>/dev/null | grep -c . ; }
live() { [ "$(spool_lines)" -gt 0 ] 2>/dev/null; }

# count events of one kind, optionally for one session
nev() { # nev <EV> [sid]
  python3 - "$NEW_HOME/.rabadon/spool" "$1" "${2:-}" <<'PY'
import json,glob,os,sys
d,kind,sid=sys.argv[1],sys.argv[2],sys.argv[3]
n=0
for f in sorted(glob.glob(os.path.join(d,"*.jsonl"))):
    for line in open(f):
        line=line.strip()
        if not line: continue
        try: e=json.loads(line)
        except Exception: continue
        if e.get("ev")!=kind: continue
        if sid and e.get("sess")!=sid: continue
        n+=1
print(n)
PY
}

# the median chain length of sessions that ran to completion UNCUT, derived
# here, independently of the counter: a session with no INJECT and no STOP, and
# the length of its last SIGNAL's seqs.
derive_median() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json,glob,os,sys,statistics
d=sys.argv[1]
last={}; cut=set()
for f in sorted(glob.glob(os.path.join(d,"*.jsonl"))):
    for line in open(f):
        line=line.strip()
        if not line: continue
        try: e=json.loads(line)
        except Exception: continue
        s=e.get("sess")
        if e.get("ev")=="SIGNAL" and isinstance(e.get("seqs"),list):
            last[s]=len(e["seqs"])
        if e.get("ev") in ("INJECT","STOP"):
            cut.add(s)
lens=sorted(v for s,v in last.items() if s not in cut)
print(statistics.median(lens) if lens else "", len(lens))
PY
}

# --- the transcript the agent already writes, synthesised ------------------
# One line per assistant turn, exactly the shape usage.h reads.
write_transcript() { # write_transcript <sid> <model> <turns> <in> <cw> <cr> <out>
  python3 - "$LENS/$1.jsonl" "$2" "$3" "$4" "$5" "$6" "$7" <<'PY'
import json,sys
path,model,turns,i,cw,cr,o=sys.argv[1],sys.argv[2],int(sys.argv[3]),int(sys.argv[4]),int(sys.argv[5]),int(sys.argv[6]),int(sys.argv[7])
with open(path,"w") as f:
    f.write(json.dumps({"type":"user","message":{"role":"user","content":"go"}})+"\n")
    for n in range(turns):
        f.write(json.dumps({"type":"assistant","message":{"role":"assistant","model":model,
            "usage":{"input_tokens":i,"cache_creation_input_tokens":cw,
                     "cache_read_input_tokens":cr,"output_tokens":o}}})+"\n")
PY
}

# --- reading the counter's own numbers back --------------------------------
jq_counter() { # jq_counter <json> <dotted.path>
  python3 - "$2" <<PY 2>/dev/null
import json,sys
try: d=json.loads(sys.stdin.read())
except Exception: sys.exit(1)
cur=d
for k in sys.argv[1].split('.'):
    if not isinstance(cur,dict) or k not in cur: sys.exit(1)
    cur=cur[k]
print("" if cur is None else cur)
PY
}
# the dollar figure printed on the closing line, as a number
line_usd() { printf '%s' "$1" | grep -oE '[-]?[0-9]+[.,][0-9]+ ?\$' | head -1 | tr ',' '.' | tr -d ' $'; }

# median wall time of 21 PreToolUse calls, in ms
bench_pre() { # bench_pre <sid>
  python3 - "$GATE" "$NEW_HOME" "$NEW_PROJ" "$1" <<'PY'
import json,os,statistics,subprocess,sys,time
gate,home,proj,sid=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
env=dict(os.environ,HOME=home,RABADON_DIR=home+"/.rabadon",RABADON_NOTIFY="0")
ev=json.dumps({"hook_event_name":"PreToolUse","session_id":sid,"cwd":proj,
               "tool_name":"Bash","tool_input":{"command":"echo hi"}}).encode()
ts=[]
for _ in range(21):
    t0=time.perf_counter()
    subprocess.run([gate],input=ev,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,env=env)
    ts.append((time.perf_counter()-t0)*1000)
print(f"{statistics.median(ts):.2f}")
PY
}

# float compare to a tolerance
close_to() { # close_to <a> <b> <tol>
  python3 -c 'import sys;a,b,t=map(float,sys.argv[1:4]);sys.exit(0 if abs(a-b)<=t else 1)' "$1" "$2" "$3" 2>/dev/null
}

# ===========================================================================
# THE MAIN FIXTURE. Everything in claims 1-3 and 5 is measured on this one
# session, so the numbers can be checked against each other as well as against
# the hand computation.
#
#   history : five sessions that ran to completion UNCUT, in watch mode with
#             injection off, of lengths 4, 6, 6, 8, 10 -> median 6
#   session : two root-migration chains, each ended by an injection -> 2 cuts.
#             After the first injection the error is gone and the suite goes
#             green -> fixed. After the second the agent SAYS it fixed it and
#             the same error comes back -> not fixed. fixed_instantly = 1.
#   money   : four assistant turns, sonnet, 1000 in / 2000 cache-write /
#             40000 cache-read / 500 out each. Most of the volume is cache-read
#             on purpose: that is the class a careless counter folds into input.
HIST_LENS="4 6 6 8 10"
EXP_MEDIAN=6
EXP_CUTS=2
EXP_FIXED=1
T_IN=1000; T_CW=2000; T_CR=40000; T_OUT=500; T_TURNS=4
MODEL="claude-sonnet-4-5-20250929"

# one session per chain length, every move inside the same session — that is
# what makes the chain a chain, and what makes its length mean anything.
build_history() {
  watch
  EXTRA_ENV="RABADON_INJECT=0"
  local n i sid
  for n in $HIST_LENS; do
    sid="hist-$n-$RANDOM"
    i=0
    while [ "$i" -lt "$n" ]; do
      ran "$sid" 'npm run build' 'Error: cannot find module x'
      i=$((i + 1))
    done
  done
  EXTRA_ENV=""
}

# one root-migration chain, ended by an injection
chain_cut() { # chain_cut <sid> <tag>
  local s="$1" t="$2"
  ran  "$s" 'npm test'          '12 passed, 0 failed'
  edit "$s" "src/$t.js"         "function total(a, b) { return a.value + b.value; }"
  ran  "$s" "npm run build"     "TypeError: undefined is not a function in $t"
  ran  "$s" "npx tsc --noEmit"  "TypeError: undefined is not a function in $t"
  ran  "$s" "node dist/$t.js"   "TypeError: undefined is not a function in $t"
  ran  "$s" 'npm test'          '3 passed, 2 failed'
  edit "$s" "src/$t.js"         "function total(a, b) { return a.value + b.val; }"
}

build_main() {
  sandbox
  build_history
  enforce
  SID="s-main"
  # chain 1 -> injected, then really fixed inside 3 moves
  chain_cut "$SID" one
  edit "$SID" src/one.js 'function total(a, b) { return (a?.value ?? 0) + (b?.value ?? 0); }'
  ran  "$SID" 'npm run build' 'built in 1.2s'
  ran  "$SID" 'npm test'      '14 passed, 0 failed'
  # chain 2 -> injected, agent CLAIMS the fix, the same error returns
  chain_cut "$SID" two
  edit "$SID" src/two.js 'function total(a, b) { return a.value + b.value; /* fixed */ }'
  ran  "$SID" 'npm run build' 'fixed it — all good, build clean'
  ran  "$SID" 'node dist/two.js' 'TypeError: undefined is not a function in two'
  write_transcript "$SID" "$MODEL" "$T_TURNS" "$T_IN" "$T_CW" "$T_CR" "$T_OUT"
}

build_main
LINE="$(close_line "$SID")"
UJ="$(usage_json)"
UE="$(usage_explain)"

# ---------------------------------------------------------------------------
head_ "CLAIM 0 — the fixture is real (nothing below means anything otherwise)"

if live; then pass "0a the gate saw the fixture: $(spool_lines) ledger lines"
else fail "0a the spool is EMPTY — the fixture never reached the gate, and every claim below proves nothing"; fi

N_INJ="$(nev INJECT "$SID")"
if [ "${N_INJ:-0}" = "2" ]; then pass "0b the session has exactly 2 injections, so 2 chains were cut"
else fail "0b expected 2 INJECT events in $SID, ledger has ${N_INJ:-0} — the fixture no longer cuts two chains"; fi

read -r DERIVED_MED DERIVED_N <<<"$(derive_median)"
if [ "${DERIVED_N:-0}" -ge "$MIN_HISTORY" ] 2>/dev/null && close_to "${DERIVED_MED:-0}" "$EXP_MEDIAN" 0.001; then
  pass "0c the ledger's uncut chains have median $EXP_MEDIAN over ${DERIVED_N} sessions"
else
  fail "0c the history fixture is wrong: ${DERIVED_N:-0} uncut chains, median [${DERIVED_MED:-none}], expected 5 and $EXP_MEDIAN"
fi

C0_FAIL="$FAIL_N"

# ---------------------------------------------------------------------------
head_ "CLAIM 1 — the closing line exists, says the three things, and hedges the estimate"

if [ -n "$LINE" ]; then pass "1a a counter line is printed at session close (hook: $CLOSE_HOOK)"
else fail "1a no 'rabadon:' line at SessionEnd or Stop — the shop window is dark"; fi

if [ "$(printf '%s\n' "$LINE" | grep -c .)" = "1" ]; then
  pass "1b the close writes exactly one line"
else
  fail "1b the close wrote $(printf '%s\n' "$LINE" | grep -c .) lines — the plan says one"
fi

if printf '%s' "$LINE" | grep -qiE 'tahmini|estimated'; then
  pass "1c the line labels the dollar figure as an estimate"
else
  fail "1c the line carries no 'tahmini'/'estimated' — Law 5: an estimate printed bare reads as a measurement"
fi

if printf '%s' "$LINE" | grep -qE "(^|[^0-9])$EXP_CUTS([^0-9]|$)"; then
  pass "1d the line reports $EXP_CUTS chains cut"
else
  fail "1d the line does not report $EXP_CUTS cut chains: [$LINE]"
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 2 — the number equals the number computed by hand, here"

R_IN="$(printf '%s' "$UJ"  | jq_counter - counter.prices.rates.input)"
R_OUT="$(printf '%s' "$UJ" | jq_counter - counter.prices.rates.output)"
R_CW="$(printf '%s' "$UJ"  | jq_counter - counter.prices.rates.cache_write)"
R_CR="$(printf '%s' "$UJ"  | jq_counter - counter.prices.rates.cache_read)"

if [ -n "$R_IN" ] && [ -n "$R_OUT" ] && [ -n "$R_CW" ] && [ -n "$R_CR" ]; then
  pass "2a --json declares four price classes for the session's model"
else
  fail "2a --json does not declare per-class rates (input/output/cache_write/cache_read) — nothing can be hand-checked against a price nobody states"
fi

CACHED="$(printf '%s' "$UJ" | jq_counter - counter.prices.cached)"
SRC="$(printf '%s' "$UJ"    | jq_counter - counter.prices.source)"
if [ -n "$CACHED" ] && [ -f "$CACHED" ] && [ "$SRC" = "litellm" ]; then
  pass "2b prices come from an offline LiteLLM cache that exists on disk ($CACHED)"
else
  fail "2b no offline LiteLLM price cache is named by --json (source=[${SRC:-none}] cached=[${CACHED:-none}])"
  note "a counter that reaches the network to price a session is a counter that leaks the session"
fi

# The hand computation. Written out long, on purpose: this is the arithmetic
# the product is selling and it should be readable without running anything.
if [ -n "$R_IN" ] && [ -n "$R_CR" ]; then
  read -r EXP_AVG EXP_GROSS EXP_INJ EXP_NET EXP_FOLDED <<<"$(python3 - \
      "$R_IN" "$R_OUT" "$R_CW" "$R_CR" "$T_IN" "$T_CW" "$T_CR" "$T_OUT" "$T_TURNS" \
      "$EXP_MEDIAN" "$EXP_CUTS" "$N_INJ" "$UPPER_CHARS" "$CHARS_PER_TOKEN" <<'PY'
import sys
r_in,r_out,r_cw,r_cr,t_in,t_cw,t_cr,t_out,turns,med,cuts,ninj,ub,cpt=[float(x) for x in sys.argv[1:15]]
turn=(t_in*r_in + t_cw*r_cw + t_cr*r_cr + t_out*r_out)/1e6
avg=turn                       # session cost / assistant calls, and every call is identical
gross=med*cuts*avg
inj=(ub*ninj/cpt)*r_in/1e6     # upper bound: 400 chars per injection, priced as input
net=gross-inj
folded=((t_in+t_cw+t_cr)*r_in + t_out*r_out)/1e6*med*cuts-inj   # the wrong answer
print(f"{avg:.10f} {gross:.10f} {inj:.10f} {net:.10f} {folded:.10f}")
PY
)"
else
  EXP_AVG=""; EXP_GROSS=""; EXP_INJ=""; EXP_NET=""; EXP_FOLDED=""
fi

GOT_NET="$(printf '%s' "$UJ" | jq_counter - counter.saved_usd)"
if [ -n "$EXP_NET" ] && [ -n "$GOT_NET" ] && close_to "$GOT_NET" "$EXP_NET" 0.0000005; then
  pass "2c --json saved_usd equals the hand computation exactly ($EXP_NET)"
else
  fail "2c saved_usd is [${GOT_NET:-none}], the hand computation says [${EXP_NET:-uncomputable}]"
fi

if [ -n "$EXP_FOLDED" ] && [ -n "$GOT_NET" ] && close_to "$GOT_NET" "$EXP_FOLDED" 0.0000005; then
  fail "2d cache-read is being priced as input: the number matches the FOLDED answer ($EXP_FOLDED)"
  note "in a long session most volume is cache-read at a tenth of input; folding it inflates the"
  note "number by roughly an order of magnitude, and it inflates it in our favour"
elif [ -n "$GOT_NET" ]; then
  pass "2d cache-read is priced as its own class, not folded into input"
else
  fail "2d nothing to check: --json printed no saved_usd"
fi

GOT_AVG="$(printf '%s' "$UJ" | jq_counter - counter.avg_call_usd)"
if [ -n "$EXP_AVG" ] && [ -n "$GOT_AVG" ] && close_to "$GOT_AVG" "$EXP_AVG" 0.0000005; then
  pass "2e avg_call_usd is the session's own measured average ($EXP_AVG)"
else
  fail "2e avg_call_usd is [${GOT_AVG:-none}], hand computation says [${EXP_AVG:-uncomputable}]"
fi

GOT_MED="$(printf '%s' "$UJ" | jq_counter - counter.median_uncut_chain)"
if [ -n "$GOT_MED" ] && close_to "$GOT_MED" "$EXP_MEDIAN" 0.001; then
  pass "2f the chain-length estimate is the MEASURED median of uncut chains ($EXP_MEDIAN), not a constant"
else
  fail "2f median_uncut_chain is [${GOT_MED:-none}], the ledger's own uncut chains say $EXP_MEDIAN"
fi

GOT_INJ="$(printf '%s' "$UJ" | jq_counter - counter.inject_usd)"
GOT_BOUND="$(printf '%s' "$UJ" | jq_counter - counter.inject_bound)"
if [ -n "$EXP_INJ" ] && [ -n "$GOT_INJ" ] && close_to "$GOT_INJ" "$EXP_INJ" 0.0000005 && [ "$GOT_BOUND" = "upper" ]; then
  pass "2g rabadon's own injected tokens are charged at the upper bound ($UPPER_CHARS chars x $N_INJ)"
else
  fail "2g inject_usd is [${GOT_INJ:-none}] bound=[${GOT_BOUND:-none}]; the upper bound says [${EXP_INJ:-uncomputable}]"
  note "the injected text is not distinguishable inside this transcript, so the charge is the"
  note "ceiling, not a guess — Law 5 forbids rounding into our own column"
fi

LUSD="$(line_usd "$LINE")"
if [ -n "$LUSD" ] && [ -n "$EXP_NET" ] && close_to "$LUSD" "$EXP_NET" 0.005; then
  pass "2h the printed line shows the same money as --json ($LUSD)"
else
  fail "2h the line shows [${LUSD:-no figure}] and --json says [${EXP_NET:-uncomputable}]"
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 3 — 'fixed instantly' is read off the ledger, not off the agent's word"

GOT_FIX="$(printf '%s' "$UJ" | jq_counter - counter.fixed_instantly)"
if [ "$GOT_FIX" = "$EXP_FIXED" ]; then
  pass "3a exactly $EXP_FIXED of the 2 cut chains counts as fixed instantly"
elif [ "$GOT_FIX" = "2" ]; then
  fail "3a both chains counted as fixed — the second one only SAID it was fixed and the same error came back"
  note "claimed_rc is a claim. 'fixed it — all good' is a sentence, and the TypeError returned two moves later."
else
  fail "3a fixed_instantly is [${GOT_FIX:-none}], the ledger says $EXP_FIXED"
fi

GOT_CUTS="$(printf '%s' "$UJ" | jq_counter - counter.chains_cut)"
if [ "$GOT_CUTS" = "$EXP_CUTS" ]; then
  pass "3b chains_cut is $EXP_CUTS, matching the ledger's INJECT events"
else
  fail "3b chains_cut is [${GOT_CUTS:-none}], the ledger has $N_INJ injections"
fi

if printf '%s' "$LINE" | grep -qiE "düzeltildi|fixed"; then
  pass "3c the line names the instantly-fixed count"
else
  fail "3c the line does not report the instantly-fixed count: [$LINE]"
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 4 — when the counter does not know, it says so and prints no dollars"

# 4a. no transcript at all -> error count only, no money.
sandbox; build_history; enforce
chain_cut s-nojsonl one
rm -f "$LENS"/*.jsonl
L4A="$(close_line s-nojsonl)"
if ! live; then
  fail "4a the spool is empty — this fixture proved nothing"
elif [ -z "$L4A" ]; then
  fail "4a no line at all with the transcript missing; the plan says the error count is still printed"
elif [ -n "$(line_usd "$L4A")" ] || printf '%s' "$L4A" | grep -q '\$'; then
  fail "4a a dollar figure was printed with NO session transcript to price: [$L4A]"
else
  pass "4a no transcript -> the count is printed, the money is not"
fi

# 4b. a model the price table does not know -> no money.
sandbox; build_history; enforce
chain_cut s-nomodel one
write_transcript s-nomodel "some-model-nobody-priced-v9" "$T_TURNS" "$T_IN" "$T_CW" "$T_CR" "$T_OUT"
L4B="$(close_line s-nomodel)"
if ! live; then
  fail "4b the spool is empty — this fixture proved nothing"
elif [ -n "$(line_usd "$L4B")" ]; then
  fail "4b an unpriceable model still produced a dollar figure: [$L4B]"
elif [ -z "$L4B" ]; then
  fail "4b no line at all for an unpriceable model; the count should still be printed"
else
  pass "4b unresolvable model price -> the count is printed, the money is not"
fi

# 4c. net negative -> the negative is printed, and never rounded away.
# A tiny model, tiny turns, one cut, one injection: the injected characters cost
# more than the calls they prevented. This is the session where rabadon did not
# pay for itself, and the whole argument for the counter is that it says so.
sandbox
watch; EXTRA_ENV="RABADON_INJECT=0"
for n in 1 2 2; do
  i=0; sid="neg-hist-$n-$RANDOM"
  while [ "$i" -lt "$n" ]; do ran "$sid" 'npm run build' 'Error: cannot find module x'; i=$((i+1)); done
done
EXTRA_ENV=""; enforce
chain_cut s-neg one
write_transcript s-neg "claude-haiku-4-5-20251001" 4 8 0 0 1
L4C="$(close_line s-neg)"
NEG_JSON="$(usage_json)"
NEG_NET="$(printf '%s' "$NEG_JSON" | jq_counter - counter.saved_usd)"
if ! live; then
  fail "4c the spool is empty — this fixture proved nothing"
elif [ -z "$NEG_NET" ]; then
  fail "4c --json produced no saved_usd for the negative session"
elif python3 -c 'import sys;sys.exit(0 if float(sys.argv[1])<0 else 1)' "$NEG_NET" 2>/dev/null; then
  if printf '%s' "$L4C" | grep -qE '\-[0-9]*[.,]?[0-9]*[1-9]'; then
    pass "4c a net-negative session prints the negative ($NEG_NET)"
  else
    fail "4c --json says $NEG_NET but the printed line hides it: [$L4C]"
    note "a non-zero loss rounded to 0.00 is rounding in our favour; print the precision it takes"
  fi
else
  fail "4c the negative fixture came out non-negative ($NEG_NET) — either the fixture or the arithmetic is wrong"
fi

# 4d. not enough history for the distribution -> "ölçüm birikiyor", no coefficient.
sandbox; enforce
chain_cut s-nohist one
write_transcript s-nohist "$MODEL" "$T_TURNS" "$T_IN" "$T_CW" "$T_CR" "$T_OUT"
L4D="$(close_line s-nohist)"
if ! live; then
  fail "4d the spool is empty — this fixture proved nothing"
elif [ -n "$(line_usd "$L4D")" ]; then
  fail "4d with no measured chain distribution a dollar figure appeared anyway: [$L4D]"
  note "that figure can only have come from a constant, and a constant is the one thing the plan forbids"
elif printf '%s' "$L4D" | grep -qiE 'ölçüm birikiyor|olcum birikiyor|measurement is accumulating'; then
  pass "4d too little history -> 'ölçüm birikiyor', no invented coefficient"
else
  fail "4d expected 'ölçüm birikiyor' with no history; got: [${L4D:-nothing}]"
fi

# 4e. no interventions at all -> no savings sentence, and no zero dollars.
sandbox; build_history; enforce
ran  s-quiet 'npm test'      '12 passed, 0 failed'
edit s-quiet src/a.js        'export const a = 1;'
ran  s-quiet 'npm run build' 'built in 0.9s'
write_transcript s-quiet "$MODEL" "$T_TURNS" "$T_IN" "$T_CW" "$T_CR" "$T_OUT"
L4E="$(close_line s-quiet)"
if ! live; then
  fail "4e the spool is empty — this fixture proved nothing"
elif printf '%s' "$L4E" | grep -qiE 'kurtarıldı|kurtarildi|saved'; then
  fail "4e a session with no intervention still used the word 'kurtarıldı': [$L4E]"
  note "zero dollars printed as 'saved' is the first lie a counter tells"
elif printf '%s' "$L4E" | grep -qiE 'müdahale yok|mudahale yok|no intervention'; then
  pass "4e zero interventions -> 'bu oturumda müdahale yok'"
else
  fail "4e expected 'bu oturumda müdahale yok'; got: [${L4E:-nothing}]"
fi

# 4f. an EMPTY ledger must not produce a confident line. This is the vacuous
#     pass this whole file is written against: no events, no numbers.
sandbox; enforce
write_transcript s-empty "$MODEL" "$T_TURNS" "$T_IN" "$T_CW" "$T_CR" "$T_OUT"
L4F="$(close_line s-empty)"
# "empty" means empty OF THE THINGS THE COUNTER COUNTS. The gate writes a MODE
# line the first time it runs in a fresh home, and that line is not a chain, not
# an injection and not a refusal — it is bookkeeping, and counting it as
# evidence that the fixture is populated would make this assertion untestable.
E4F=$(( $(nev SIGNAL) + $(nev INJECT) + $(nev STOP) ))
if [ "$E4F" -gt 0 ]; then
  fail "4f the empty-ledger fixture is not empty ($E4F signal/inject/stop lines) — it proves nothing"
elif [ -n "$(line_usd "$L4F")" ] || printf '%s' "$L4F" | grep -qiE 'kurtarıldı|kurtarildi|saved'; then
  fail "4f an empty ledger produced a savings claim: [$L4F]"
else
  pass "4f an empty ledger claims nothing"
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 5 — the counter can show its work, and the doc says what the code does"

if [ -n "$UE" ] && printf '%s' "$UE" | grep -qiE 'unknown|usage: rabadon-stats' ; then
  fail "5a 'usage --explain' is not a flag the binary knows"
elif [ -z "$UE" ]; then
  fail "5a 'usage --explain' printed nothing"
else
  pass "5a 'usage --explain' answers"
fi

if [ -n "$UE" ] && [ -n "$EXP_NET" ] && \
   printf '%s' "$UE" | grep -qE "$(python3 -c 'import sys;print(f"{float(sys.argv[1]):.2f}")' "$EXP_NET" 2>/dev/null || echo '__nope__')"; then
  pass "5b --explain arrives at the same number the line prints"
else
  fail "5b --explain does not re-derive the printed number"
fi

if [ -n "$UE" ] && printf '%s' "$UE" | grep -qE '\.jsonl' && printf '%s' "$UE" | grep -qiE 'seq|line [0-9]+|INJECT'; then
  pass "5c --explain cites the ledger lines its subtotals came from"
else
  fail "5c --explain does not reference ledger lines — an explanation nobody can follow back to a byte is a paragraph, not a proof"
fi

# Valid JSON is not the claim — `usage --json` was already valid JSON before R6.
# The claim is that the same numbers the line prints are in it, under a key a
# generator can find, because M2's share card is built from this and not by hand.
CJ_KEYS='chains_cut fixed_instantly saved_usd reason estimated median_uncut_chain avg_call_usd inject_usd inject_bound repair_usd prices'
if [ -n "$UJ" ] && printf '%s' "$UJ" | python3 -c '
import json,sys
d=json.loads(sys.stdin.read()); c=d.get("counter")
assert isinstance(c,dict)
for k in sys.argv[1].split(): assert k in c, k
' "$CJ_KEYS" 2>/dev/null; then
  pass "5d --json carries the whole counter object, machine-readable"
else
  fail "5d --json has no complete counter object — the share card would have to be typed by hand"
fi

if [ -f "$COUNTER_DOC" ]; then
  DOC_N="$(python3 - "$COUNTER_DOC" "$FORMULA" <<'PY'
import re,sys
want=re.sub(r'\s+','',sys.argv[2])
txt=re.sub(r'\s+','',open(sys.argv[1],encoding='utf-8',errors='replace').read())
print(1 if want in txt else 0)
PY
)"
  if [ "$DOC_N" = "1" ]; then
    pass "5e docs/COUNTER.md carries the same formula this test holds the code to"
  else
    fail "5e docs/COUNTER.md does not contain the formula: $FORMULA"
    note "the doc is read FROM this test; if they disagree the published formula is decoration"
  fi
  if grep -qE "$UPPER_CHARS" "$COUNTER_DOC" && grep -qiE "cache.?read" "$COUNTER_DOC"; then
    pass "5f docs/COUNTER.md states the $UPPER_CHARS-char upper bound and the cache-read class"
  else
    fail "5f docs/COUNTER.md does not state the upper bound and the separate cache-read class"
  fi
else
  fail "5e docs/COUNTER.md does not exist"
  fail "5f docs/COUNTER.md does not exist"
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 6 — the surface did not widen and the hot path did not move"

RABADON_CLI=""
[ -x "$ROOT/native/rabadon-cli.sh" ] && RABADON_CLI="$ROOT/native/rabadon-cli.sh"
[ -z "$RABADON_CLI" ] && [ -x "$ROOT/bin/rabadon" ] && RABADON_CLI="$ROOT/bin/rabadon"
[ -z "$RABADON_CLI" ] && RABADON_CLI="node $ROOT/bin/rabadon.mjs"

HELP_TXT="$WORK/help.txt"
$RABADON_CLI --help > "$HELP_TXT" 2>/dev/null
# the command column only — the same reader reports/T2/accept.sh uses.
HELP_TOKENS="$(awk '
  /^[ \t]+[a-z]/ {
    line = $0; sub(/^[ \t]+/, "", line)
    if (line ~ /^rabadon([ \t]|$)/) next
    names = line
    if (match(names, /  +/)) names = substr(names, 1, RSTART - 1)
    else if (names ~ /[ \t]/) next
    if (match(names, / [[<]/)) names = substr(names, 1, RSTART - 1)
    n = split(names, parts, /[ \t|,]+/)
    for (i = 1; i <= n; i++) if (parts[i] ~ /^[a-z][a-z0-9_-]*$/) print parts[i]
  }' "$HELP_TXT" | sort -u)"
# The five rows T2 froze (reports/T2/baseline.txt LIST_SURFACE), plus the two
# tokens that are on the help screen today and are not verbs of the product:
# `dev`, the bucket the 29 moved verbs live under, and `version`. Anything else
# on this screen after R6 is a sixth verb, and the counter is not allowed to be
# one.
SURFACE="init on off usage repair doctor dev version"
EXTRA=""
for t in $HELP_TOKENS; do
  found=0
  for s in $SURFACE; do [ "$t" = "$s" ] && found=1; done
  [ "$found" = "0" ] && EXTRA="$EXTRA $t"
done
if [ -z "$HELP_TOKENS" ]; then
  fail "6a could not read the verb column out of --help"
elif [ -z "$EXTRA" ]; then
  pass "6a the surface is still the five rows (init, on|off, usage, repair, doctor) — the counter lives inside usage"
else
  fail "6a --help advertises a verb outside the surface:$EXTRA"
  note "the counter is a flag on usage, not a sixth verb; the surface is five and is not re-inflated"
fi

# 6b. the counter must not run on the hot path: no counter output, and no
#     savings text, on any PreToolUse or PostToolUse of the main fixture.
sandbox; build_history; enforce
HOT="$(chain_cut s-hot one 2>&1; ev PreToolUse Bash s-hot "{\"command\":$(jstr 'echo hi')}")"
if printf '%s' "$HOT" | grep -qiE 'kurtarıldı|kurtarildi|saved|\$ '; then
  fail "6b the counter spoke during tool calls: [$(printf '%s' "$HOT" | head -1)]"
else
  pass "6b nothing is counted or printed on the hot path"
fi

# 6c. and it did not slow the gate down. An absolute millisecond ceiling would
# measure this laptop, not the code — the plan already records that the same
# unchanged binary read 602, 118, 213, -59 and 228 us across five runs. So the
# assertion is the INVARIANT instead: the hot path's cost may not depend on how
# much history the session has. A counter that runs per call reads the whole
# ledger, so its cost grows with the ledger; one that runs at close does not.
# Fresh session against a session with a full chain history behind it, ratio
# capped at 1.5 (the standing length-dependency budget is 10%).
sandbox; enforce
BENCH_FRESH="$(bench_pre s-bench-fresh)"
build_history; enforce
BENCH_LOADED="$(bench_pre s-bench-loaded)"
if [ -n "$BENCH_FRESH" ] && [ -n "$BENCH_LOADED" ] && \
   python3 -c 'import sys;a,b=float(sys.argv[1]),float(sys.argv[2]);sys.exit(0 if a>0 and b/a<=1.5 else 1)' \
       "$BENCH_FRESH" "$BENCH_LOADED" 2>/dev/null; then
  pass "6c hot-path cost does not grow with ledger size (${BENCH_FRESH} ms fresh, ${BENCH_LOADED} ms loaded)"
else
  fail "6c PreToolUse got slower as the ledger grew: ${BENCH_FRESH} ms fresh -> ${BENCH_LOADED} ms loaded"
  note "that is the shape of a counter running on every call instead of at session close"
fi

# 6d. nothing goes to the network: with every proxy poisoned, the same bytes.
sandbox; build_history; enforce
chain_cut s-net one
write_transcript s-net "$MODEL" "$T_TURNS" "$T_IN" "$T_CW" "$T_CR" "$T_OUT"
NET_A="$(close_line s-net)"
NET_B="$(env http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 \
             HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 \
             HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" \
             RABADON_LENS_DIR="$NEW_HOME/.claude/projects" RABADON_NOTIFY=0 \
        sh -c "printf '%s' '{\"hook_event_name\":\"Stop\",\"session_id\":\"s-net\",\"cwd\":\"$NEW_PROJ\"}' | '$GATE'" 2>/dev/null)"
if [ -z "$NET_A" ]; then
  fail "6d nothing to compare: the counter printed no line for this fixture"
elif [ "$NET_A" = "$NET_B" ] || printf '%s' "$NET_B" | grep -q '^rabadon:'; then
  pass "6d the counter produces its line with every proxy poisoned — prices are cached offline"
else
  fail "6d the counter behaves differently when the network is unreachable"
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 7 — nothing that was green went red"

# Up to three attempts, best result. NOT leniency: reports/R3's claim 3 is a
# microsecond-scale microbenchmark, and KOSU-RABADON.md records the same
# unchanged binary reading 602, 118, 213, -59 and 228 us across five runs on
# this machine. A net that goes red on that noise stops being read, which is the
# only way a real regression gets through it. The count still has to be hit
# exactly, on some run.
reg() { # reg <label> <expected> <command...>
  local label="$1" expect="$2"; shift 2
  local out got best="none" try
  for try in 1 2 3; do
    out="$("$@" 2>&1)"
    got="$(printf '%s' "$out" | grep -oE '[0-9]+ (passed|green)' | tail -1 | grep -oE '^[0-9]+')"
    best="${got:-none}"
    if [ "${got:-0}" = "$expect" ] && ! printf '%s' "$out" | grep -qE 'NOT ACCEPTED|at least one failed'; then
      pass "7 $label — $expect, no red$([ "$try" -gt 1 ] && printf ' (attempt %s)' "$try")"
      return 0
    fi
  done
  fail "7 $label regressed: expected $expect, best of 3 was [$best]"
}
reg "native/moves_test.sh"    21 bash "$ROOT/native/moves_test.sh"
reg "native/signals_test.sh"  39 bash "$ROOT/native/signals_test.sh"
reg "reports/R2/accept.sh"    19 bash "$ROOT/reports/R2/accept.sh"
reg "reports/R3/accept.sh"    14 bash "$ROOT/reports/R3/accept.sh"

# ---------------------------------------------------------------------------
printf '\n== R6 acceptance: %d green, %d red\n' "$PASS_N" "$FAIL_N"
if [ "$C0_FAIL" -gt 0 ]; then
  printf '      NOTE: claim 0 had %d red — the fixture itself did not build, so every number\n' "$C0_FAIL"
  printf '      claimed below it was checked against an input that is not what this file describes.\n'
fi
[ "$FAIL_N" -gt 0 ] && { printf 'R6 NOT ACCEPTED\n'; exit 1; }
printf 'R6 ACCEPTED\n'
exit 0
