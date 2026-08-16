#!/usr/bin/env bash
# rabadon-gate PostToolUse proof — DIFFERENTIAL. The native PostToolUse path
# (S3) must match the node gate (hooks/gate.mjs, the parity oracle) event for
# event: same exit code, same .rabadon/state.json mutation, same spool events.
#
# For each case the IDENTICAL hook JSON is piped into BOTH `node hooks/gate.mjs`
# and `native/rabadon-gate`, each with its OWN fresh scratch cwd + RABADON_DIR.
# We then assert: exit codes equal; state.json equal after normalizing volatile
# time fields to a sentinel; spool events equal after stripping the volatile
# envelope (seq/ts/run) and keeping the load-bearing fields in emission order.
#
# The LLM branches (diagnose / driftJudge) are made deterministic by a stub
# `claude` first on PATH that returns canned JSON, records the inherited
# RABADON_OFF (the recursion root-fix), and counts its own calls. Their
# STRUCTURAL behavior is asserted (REPAIR_START emitted, rule authored into
# guard.json, RABADON_OFF propagated, a hanging stub is killed by the timeout).
#
# Style mirrors native/session_test.sh: ok/bad counters, nonzero exit on any fail.
set -u
# HERMETIC: rabadon is DEFAULT-OFF, so the gate is dormant unless a project opts
# in (cwd/.rabadon/on) or the machine has ~/.rabadon/enabled. A test that reads
# the real HOME passes or fails on whether the developer happens to have rabadon
# switched on — which is not a test. Give this run its own HOME with the flag set.
export HOME="$(mktemp -d)"; mkdir -p "$HOME/.rabadon"; : > "$HOME/.rabadon/enabled"
# Same reasoning, one variable further. RABADON_JUDGE decides whether a model is
# called at all, and the cases below exist to prove that path runs — they stub
# `claude` and count its calls. A test that reads this variable from the outside
# is testing the shell it was launched from: this repo's own settings.json set
# it once, the maintainer's every shell carried it, `make test` and
# bench/reproduce.sh both inherited it, and the suite reported `44 ok, 17 fail`
# against a gate that was fine.
#
# It used to say `unset` here, which was right while the default was ON. The
# default is OFF now, so unset means the paid path never runs and every case
# below would pass by not testing anything — the same silent failure wearing the
# other face. EXPORT, never unset: the suite owns the variable in both
# directions, and the cases that want it off pass RABADON_JUDGE=0 per-invocation.
export RABADON_JUDGE=1
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BIN="$HERE/rabadon-gate"
GATE="$ROOT/hooks/gate.mjs"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
[ -f "$GATE" ] || { echo "parity oracle missing: $GATE"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
DAY="$(date -u +%Y-%m-%d)"

# --- the stub claude: canned JSON, RABADON_OFF sentinel, call counter ---
STUBDIR="$(mktemp -d)"
cat > "$STUBDIR/claude" <<'STUB'
#!/usr/bin/env bash
# rabadon test stub for `claude`. Ignores stdin except that a real claude
# would; records the inherited RABADON_OFF (the recursion root-fix the native
# port MUST set on the child), records argv when asked (which model was picked
# is an argv fact, not a log line), bumps a call-count file, optionally hangs,
# then prints the canned JSON from $RABADON_STUB_JSON.
if [ -n "${RABADON_STUB_SENTINEL:-}" ]; then printf '%s' "${RABADON_OFF:-unset}" > "$RABADON_STUB_SENTINEL"; fi
if [ -n "${RABADON_STUB_ARGV:-}" ]; then printf '%s\n' "$@" > "$RABADON_STUB_ARGV"; fi
if [ -n "${RABADON_STUB_CALLS:-}" ]; then n=$(cat "$RABADON_STUB_CALLS" 2>/dev/null || echo 0); echo $((n+1)) > "$RABADON_STUB_CALLS"; fi
if [ -n "${RABADON_STUB_SLEEP:-}" ]; then sleep "$RABADON_STUB_SLEEP"; fi
cat >/dev/null   # drain stdin so the writer's pipe closes cleanly
printf '%s' "${RABADON_STUB_JSON:-}"
STUB
chmod +x "$STUBDIR/claude"

# ---------------- differential machinery ----------------
# canonicalize a state.json: json.load, sort_keys, and replace every volatile
# time field (Date.now() differs between the two runs) with a sentinel so only
# structure + non-time values are compared.
norm_state() { # $1=state.json path -> stdout canonical json (or "MISSING")
python3 - "$1" <<'PY'
import json,sys,os,glob
# WHERE a fact is stored stopped being the same in the two engines on 3 August.
# The native gate keeps each session's own record in
# <project>/.rabadon/sessions/<key>.json, one writer per file, because the shared
# map capped itself at four and a seven-way fan-out evicted its own main session.
# The node gate, which is the retiring engine, still writes one map with that cap
# in it. Comparing the two files byte for byte would now be comparing the bug.
#
# So the differential compares WHAT was recorded rather than WHICH FILE it landed
# in: both sides are flattened into one view, the session records folded in, and
# the per-session keys dropped because the two engines key them differently. The
# storage layout is asserted on its own by native/session_fanout_test.sh, which
# is where it belongs. One file measures parity of meaning, the other measures
# whether that meaning survives a fan-out.
def flatten(p):
    try:
        d=json.load(open(p))
    except Exception:
        d=None
    sess=[]
    if isinstance(d,dict):
        for v in (d.pop("sessions",None) or {}).values():
            if isinstance(v,dict): sess.append(v)
    for f in sorted(glob.glob(os.path.join(os.path.dirname(p),"sessions","*.json"))):
        try: sess.append(json.load(open(f)))
        except Exception: pass
    if d is None and not sess: return None
    out=dict(d or {})
    for s in sess:
        for k,v in s.items():
            if isinstance(v,(int,float)) and isinstance(out.get(k),(int,float)):
                out[k]=max(out[k],v)      # the later stamp is the one either engine reports
            else:
                out.setdefault(k,v)
    return out
d=flatten(sys.argv[1])
if d is None:
    print("MISSING"); sys.exit(0)
# Volatile time fields: Date.now() differs between the two runs -> SET/UNSET.
VOL={"lastCodeEdit","lastTestPass","lastTestFail","lastTestRun","lastDiagAt",
     "goalTs","lastCmdTs","tsOffset","incidentAt"}
# The node gate writes a SPARSE object (only the keys it touched) and leaks a
# stray top-level "s" alias (the exact bug S1's native single-owner writer
# fixed); the native gate writes the FULL fixed schema with zero/empty
# defaults. So the differential compares MEANING, not shape: drop the "s"
# alias, and collapse every zero/empty/false/default field to absent so a key
# the native writes as 0 == a key node never wrote. Only non-default content
# is compared.
def default(k,v):
    if k in ("cmdRepeat",): return v in (0,1)   # native seeds 1, node omits
    if isinstance(v,(int,float)): return v==0
    if isinstance(v,str): return v==""
    if isinstance(v,bool): return v is False
    if isinstance(v,list): return len(v)==0
    if isinstance(v,dict): return len(v)==0
    if v is None: return True
    return False
def walk(x):
    if isinstance(x,dict):
        o={}
        for k,v in x.items():
            if k=="s": continue                 # drop the leaked node alias
            if k=="recentEv": continue          # dedupe bookkeeping, not verdict state
            if k in VOL:
                setv=(isinstance(v,(int,float)) and v!=0) or (isinstance(v,str) and v)
                if setv: o[k]="SET"
                continue
            if k=="lastDiagSig":
                if v: o[k]="SET"
                continue
            if k=="recent":
                cleaned=[{"s":e.get("s")} for e in v]
                if cleaned: o[k]=cleaned
                continue
            w=walk(v)
            if not default(k,w): o[k]=w
        return o
    if isinstance(x,list): return [walk(e) for e in x]
    return x
print(json.dumps(walk(d),sort_keys=True))
PY
}

# The flattened NATIVE view: the shared file plus every per-session file. A fact
# that used to sit at the top of state.json (lastTestPass, actionCount) now lives
# in <project>/.rabadon/sessions/<key>.json, and an assertion that still reads
# only the shared file measures an empty object and passes for the wrong reason,
# which is worse than failing.
nstate() { # $1=project dir -> stdout one flattened json object
python3 - "$1/.rabadon/state.json" <<'PYEOF'
import json,sys,os,glob
d={}
try: d=json.load(open(sys.argv[1]))
except Exception: pass
sess=list((d.pop("sessions",None) or {}).values())
for f in sorted(glob.glob(os.path.join(os.path.dirname(sys.argv[1]),"sessions","*.json"))):
    try: sess.append(json.load(open(f)))
    except Exception: pass
for s in sess:
    for k,v in s.items():
        if isinstance(v,(int,float)) and isinstance(d.get(k),(int,float)): d[k]=max(d[k],v)
        else: d.setdefault(k,v)
print(json.dumps(d))
PYEOF
}

# strip the volatile envelope (seq, ts, run) from each spool line and keep only
# {ev + step, fails, reason, detail, attempt, fixing, why} in emission order.
norm_spool() { # $1=spool path -> stdout one canonical json per event
python3 - "$1" <<'PY'
import json,sys,os
p=sys.argv[1]
if not os.path.exists(p): sys.exit(0)
KEEP=["ev","step","fails","reason","detail","attempt","fixing","why"]
for line in open(p):
    line=line.strip()
    if not line: continue
    try: e=json.loads(line)
    except Exception: continue
    o={}
    for k in KEEP:
        if k in e: o[k]=e[k]
    # 'why' inside fails[] often carries volatile text (file basenames, dir
    # lists) that is deterministic here; keep fails structure but drop nothing.
    print(json.dumps(o,sort_keys=True))
PY
}

# run ONE event through both engines in fresh sandboxes, then diff.
# usage: differential <label> <event-json-with-CWD-placeholder> [guard-json] [extra-env...]
# extra env is applied to BOTH runs via a prefix string in DIFF_ENV.
DIFF_ENV=""
differential() {
  local label="$1" evt="$2" guard="${3:-}"
  local Cn RDn Cv RDv
  Cn="$(mktemp -d)"; RDn="$(mktemp -d)"; : > "$RDn/enabled"; mkdir -p "$Cn/.rabadon"
  Cv="$(mktemp -d)"; RDv="$(mktemp -d)"; : > "$RDv/enabled"; mkdir -p "$Cv/.rabadon"
  [ -n "$guard" ] && { printf '%s\n' "$guard" > "$Cn/.rabadon/guard.json"; printf '%s\n' "$guard" > "$Cv/.rabadon/guard.json"; }
  local en ev
  en="${evt//CWD/$Cn}"; ev="${evt//CWD/$Cv}"
  local rcn rcv
  echo "$en" | env $DIFF_ENV RABADON_DIR="$RDn" RABADON_NOTIFY=0 node "$GATE" >/dev/null 2>/tmp/pt_ns.$$; rcn=$?
  echo "$ev" | env $DIFF_ENV RABADON_DIR="$RDv" RABADON_NOTIFY=0 "$BIN" >/dev/null 2>/tmp/pt_vs.$$; rcv=$?
  local good=1
  [ "$rcn" = "$rcv" ] || { bad "$label: exit codes differ (node=$rcn native=$rcv)"; good=0; }
  if [ "$(norm_state "$Cn/.rabadon/state.json")" != "$(norm_state "$Cv/.rabadon/state.json")" ]; then
    bad "$label: state.json differs"
    echo "    node : $(norm_state "$Cn/.rabadon/state.json")"
    echo "    nativ: $(norm_state "$Cv/.rabadon/state.json")"
    good=0
  fi
  if [ "$(norm_spool "$RDn/spool/$DAY.jsonl")" != "$(norm_spool "$RDv/spool/$DAY.jsonl")" ]; then
    bad "$label: spool events differ"
    echo "    node : $(norm_spool "$RDn/spool/$DAY.jsonl" | tr '\n' ' ')"
    echo "    nativ: $(norm_spool "$RDv/spool/$DAY.jsonl" | tr '\n' ' ')"
    good=0
  fi
  [ $good = 1 ] && ok "$label: node==native (exit $rcn, state, spool)"
  # export the native sandbox for follow-up single-engine assertions
  LAST_CN="$Cn"; LAST_RDN="$RDn"; LAST_CV="$Cv"; LAST_RDV="$RDv"
}

# =====================================================================
# BR1 — code-edit tracking (isCode)
# =====================================================================
echo "BR1 code-edit tracking"
DIFF_ENV="RABADON_JUDGE=0"
differential "BR1a edit no guard -> lastCodeEdit SET, STEP_OK edited" \
  '{"hook_event_name":"PostToolUse","cwd":"CWD","session_id":"s1","tool_use_id":"u1","tool_name":"Edit","tool_input":{"file_path":"CWD/src/x.js"}}'
python3 -c "import json;d=json.load(open('$LAST_CV/.rabadon/state.json'));import sys;sys.exit(0 if d.get('lastCodeEdit',0)!=0 and 'lastCodeEdit' in d and 's' not in d else 1)" \
  && ok "BR1a lastCodeEdit is a TOP-LEVEL field (feeds Pre loop-stop)" || bad "BR1a lastCodeEdit not top-level / stray 's'"

# guard.codePaths that does NOT match x.js -> isCode false -> lastCodeEdit stays 0
differential "BR1b codePaths miss -> lastCodeEdit UNSET, still STEP_OK" \
  '{"hook_event_name":"PostToolUse","cwd":"CWD","session_id":"s1","tool_use_id":"u2","tool_name":"Edit","tool_input":{"file_path":"CWD/x.js"}}' \
  '{"project":"p","codePaths":["\\.ts$"]}'
python3 -c "import json;d=json.load(open('$LAST_CV/.rabadon/state.json'));import sys;sys.exit(0 if d.get('lastCodeEdit',0)==0 else 1)" \
  && ok "BR1b non-code edit leaves lastCodeEdit unset" || bad "BR1b lastCodeEdit should stay 0"

# =====================================================================
# BR2 — scope fan-out (5th top-level dir, once per session)
# =====================================================================
echo "BR2 scope fan-out"
FAN_STATE='{"sessions":{"s1":{"touchedDirs":["a","b","c","d"],"fanoutWarned":false,"actionCount":0,"recent":[]}}}'
seed_both() { # writes FAN_STATE into node+native sandboxes created by differential
  :
}
# custom driver: seed 4 dirs, fire 5th (e), assert exit2 + why lists a,b,c,d,e
Cn="$(mktemp -d)"; RDn="$(mktemp -d)"; : > "$RDn/enabled"; mkdir -p "$Cn/.rabadon"; printf '%s' "$FAN_STATE" > "$Cn/.rabadon/state.json"
Cv="$(mktemp -d)"; RDv="$(mktemp -d)"; : > "$RDv/enabled"; mkdir -p "$Cv/.rabadon"; printf '%s' "$FAN_STATE" > "$Cv/.rabadon/state.json"
EVT='{"hook_event_name":"PostToolUse","cwd":"CWD","session_id":"s1","tool_use_id":"e1","tool_name":"Edit","tool_input":{"file_path":"CWD/e/f.js"}}'
sn="$(echo "${EVT//CWD/$Cn}" | RABADON_JUDGE=0 RABADON_DIR="$RDn" node "$GATE" 2>/tmp/pt_bn.$$)"; rn=$?
sv="$(echo "${EVT//CWD/$Cv}" | RABADON_JUDGE=0 RABADON_DIR="$RDv" "$BIN" 2>/tmp/pt_bv.$$)"; rv=$?
en="$(cat /tmp/pt_bn.$$)"; ev="$(cat /tmp/pt_bv.$$)"
[ "$rn" = 2 ] && [ "$rv" = 2 ] && ok "BR2 5th dir -> exit 2 on both" || bad "BR2 expected exit 2/2 (node=$rn native=$rv)"
echo "$en" | grep -q "a, b, c, d, e" && echo "$ev" | grep -q "a, b, c, d, e" \
  && ok "BR2 stderr names all 5 top dirs (a, b, c, d, e) on both" || bad "BR2 dir list missing"
[ "$en" = "$ev" ] && ok "BR2 stderr frame is byte-identical node==native" || { bad "BR2 stderr differs"; echo "    node: $en"; echo "    nat : $ev"; }
grep -q '"check":"scope-fanout"' "$RDv/spool/$DAY.jsonl" && ok "BR2 CHECK_FAIL scope-fanout on the ledger" || bad "BR2 spool missing scope-fanout"
nstate "$Cv" | python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(0 if d.get('fanoutWarned') and d.get('lastCodeEdit',0)!=0 else 1)" \
  && ok "BR2 fanoutWarned latched + lastCodeEdit still SET after fan-out exit" || bad "BR2 latch/lastCodeEdit wrong"
# 6th off-target edit -> exit 0 (latched)
EVT6='{"hook_event_name":"PostToolUse","cwd":"'"$Cv"'","session_id":"s1","tool_use_id":"e2","tool_name":"Edit","tool_input":{"file_path":"'"$Cv"'/g/h.js"}}'
echo "$EVT6" | RABADON_JUDGE=0 RABADON_DIR="$RDv" "$BIN" >/dev/null 2>&1
[ $? = 0 ] && ok "BR2 6th off-target edit exits 0 (fires once per session)" || bad "BR2 6th edit should be exit 0"
# file OUTSIDE cwd (rel starts '..') -> no top dir, exit 0, but lastCodeEdit set
Cout="$(mktemp -d)"; RDout="$(mktemp -d)"; mkdir -p "$Cout/.rabadon"
OUTEVT='{"hook_event_name":"PostToolUse","cwd":"'"$Cout"'","session_id":"s1","tool_use_id":"o1","tool_name":"Edit","tool_input":{"file_path":"/tmp/outside/z.js"}}'
echo "$OUTEVT" | RABADON_JUDGE=0 RABADON_DIR="$RDout" "$BIN" >/dev/null 2>&1; rco=$?
nstate "$Cout" | python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(0 if d.get('lastCodeEdit',0)!=0 and len(d.get('touchedDirs',[]))==0 else 1)" 2>/dev/null
[ $rco = 0 ] && [ $? = 0 ] && ok "BR2 file outside cwd: no top dir, exit 0, lastCodeEdit still SET" || bad "BR2 outside-cwd handling wrong (exit=$rco)"

# =====================================================================
# BR3 — active re-anchor arithmetic (every 12th action) — STUB claude
# =====================================================================
echo "BR3 active re-anchor (12th action)"
reanchor() { # $1=actionCount $2=stubjson $3=judgeEnv -> sets RC/STDERR from native
  local ac="$1" sj="$2" je="$3"
  local C RD
  C="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$C/.rabadon"
  python3 -c "import json;json.dump({'sessions':{'s1':{'goalPrompt':'build the kernel','actionCount':$ac,'recent':[{'t':1,'s':'m'}]}}},open('$C/.rabadon/state.json','w'))"
  local tripwire="$C/tripwire"
  RC=$(echo '{"hook_event_name":"PostToolUse","cwd":"'"$C"'","session_id":"s1","tool_use_id":"ra'"$ac"'","tool_name":"Edit","tool_input":{"file_path":"'"$C"'/src/x.js"}}' \
    | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON="$sj" RABADON_STUB_CALLS="$tripwire" ${je:+RABADON_JUDGE=$je} RABADON_DIR="$RD" "$BIN" 2>/tmp/pt_ra.$$; echo $?)
  RC="${RC##* }"
  STDERR="$(cat /tmp/pt_ra.$$)"
  CALLS="$(cat "$tripwire" 2>/dev/null || echo 0)"
  RC_PROJ="$C"
}
# actionCount=12, judge returns off-track -> exit 2 + re-anchor stderr
reanchor 12 '{"onTrack":false,"anchor":"stop touching web/"}' ""
[ "$RC" = 2 ] && ok "BR3 12th action + off-track judge -> exit 2" || bad "BR3 expected exit 2 (got $RC)"
echo "$STDERR" | grep -q 'rabadon re-anchor: the session goal is "build the kernel". stop touching web/' \
  && ok "BR3 re-anchor stderr carries goal + anchor verbatim" || { bad "BR3 stderr wrong"; echo "    $STDERR"; }
nstate "$RC_PROJ" | python3 -c "import json,sys;print(json.load(sys.stdin)['actionCount'])" | grep -qx 12 \
  && ok "BR3 actionCount stays 12 (Post must NOT increment)" || bad "BR3 actionCount changed"
# on-track -> exit 0 + STEP_OK edited
reanchor 12 '{"onTrack":true}' ""
[ "$RC" = 0 ] && grep -q '"step":"edited: x.js"' "$LAST_RDV/spool/$DAY.jsonl" 2>/dev/null || true
[ "$RC" = 0 ] && ok "BR3 on-track judge -> exit 0 (STEP_OK edited)" || bad "BR3 on-track should be exit 0 (got $RC)"
# actionCount=11 -> judge NOT invoked (tripwire call-count stays 0)
reanchor 11 '{"onTrack":false,"anchor":"X"}' ""
[ "$RC" = 0 ] && [ "$CALLS" = 0 ] && ok "BR3 actionCount=11 -> judge not invoked (no claude call)" || bad "BR3 judge fired off-cadence (calls=$CALLS rc=$RC)"
# RABADON_JUDGE=0 -> judge NOT invoked
reanchor 12 '{"onTrack":false,"anchor":"X"}' 0
[ "$RC" = 0 ] && [ "$CALLS" = 0 ] && ok "BR3 RABADON_JUDGE=0 -> judge skipped entirely" || bad "BR3 JUDGE=0 still called claude (calls=$CALLS rc=$RC)"

# =====================================================================
# BR4 — test GREEN + the 'fail 0' false-positive trap
# =====================================================================
echo "BR4 test GREEN + 'fail 0' trap"
DIFF_ENV="RABADON_JUDGE=0"
# 'Failures: 0' delivered as a STRING tool_response — real newlines survive so
# the word-boundary before "Failures" is intact and the count regex matches
# N=0 -> GREEN. (When the SAME text is an OBJECT, JSON.stringify keeps the
# literal \n which glues 'n' onto 'Failures', the boundary breaks and the
# oracle reads it RED — proven by BR4a2 below, where node==native agree.)
differential "BR4a 'Failures: 0' string response -> GREEN (the word 'fail' does not trip red)" \
  '{"hook_event_name":"PostToolUse","cwd":"CWD","session_id":"s1","tool_use_id":"g1","tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":"Tests: 12 passed\nFailures: 0"}' \
  '{"project":"p","testCommand":"npm test"}'
grep -q '"step":"tests: GREEN"' "$LAST_RDV/spool/$DAY.jsonl" && ok "BR4a GREEN emitted (measured count N=0, not a keyword sighting)" || bad "BR4a expected tests: GREEN"
nstate "$LAST_CV" | python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(0 if d.get('lastTestPass',0)!=0 and d.get('lastTestFail',1)==0 else 1)" \
  && ok "BR4a lastTestPass SET, lastTestFail=0" || bad "BR4a test state wrong"
# BR4a2 — THE ONE DELIBERATE DIVERGENCE FROM THE ORACLE. Read this before
# turning it back into a differential.
#
# The SAME 'Failures: 0' as an OBJECT keeps a literal \n after JSON.stringify.
# The boundary before "Failures" breaks, no count matches, no green phrase is
# found, and node concludes RED. BR4a one block up hands node the identical TEXT
# in the string shape and node calls it GREEN. The oracle returns two opposite
# verdicts for one suite based on nothing but the delivery shape of the result,
# and the verdict it gives here is about a run that says, in plain words, twelve
# tests passed and zero failures.
#
# That is a false red, and this case used to freeze it as the required answer.
# On 3 August this repo measured what a false red costs: `make test` exited 0
# with 2942 ok lines, the output went to a file, the hook saw only `EXIT=0`,
# lastTestFail was stamped, and .rabadon/handoff.md told the next session the
# red WAS the open front.
#
# Native first answered the honest third answer here, not green and not red.
# That was the right verdict for the wrong reason: the text was never
# unreadable, the READER was reading JSON source instead of the run's output.
# An object-shaped tool_response is now un-escaped once, before anything judges
# it, so the delivery shape stops being a variable and both shapes get the same
# verdict — GREEN, which is what the run said in plain words.
#
# So this case asserts NATIVE's behaviour instead of equality, and prints what
# node did so the gap stays visible. hooks/gate.mjs still carries the false red.
# It is the retiring engine and tonight's devir forbids writing JS, so this is
# recorded as an open front rather than papered over.
C4="$(mktemp -d)"; RD4="$(mktemp -d)"; : > "$RD4/enabled"; mkdir -p "$C4/.rabadon"
CN4="$(mktemp -d)"; RN4="$(mktemp -d)"; : > "$RN4/enabled"; mkdir -p "$CN4/.rabadon"
echo '{"project":"p","testCommand":"npm test"}' > "$C4/.rabadon/guard.json"
echo '{"project":"p","testCommand":"npm test"}' > "$CN4/.rabadon/guard.json"
EV4a2='{"hook_event_name":"PostToolUse","cwd":"CWD","session_id":"s1","tool_use_id":"g1b","tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":{"stdout":"Tests: 12 passed\nFailures: 0"}}'
echo "${EV4a2//CWD/$C4}"  | env $DIFF_ENV RABADON_DIR="$RD4" RABADON_NOTIFY=0 "$BIN"        >/dev/null 2>&1; rcv4=$?
echo "${EV4a2//CWD/$CN4}" | env $DIFF_ENV RABADON_DIR="$RN4" RABADON_NOTIFY=0 node "$GATE" >/dev/null 2>&1; rcn4=$?
[ "$rcv4" = "0" ] && ok "BR4a2 native: 'Failures: 0' in the object shape is not a failure (exit 0)" \
                  || bad "BR4a2 native should exit 0, got $rcv4"
nstate "$C4" | python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(0 if d.get('lastTestFail',0)==0 else 1)" \
  && ok "BR4a2 native: lastTestFail NOT stamped (no false red in the handoff)" \
  || bad "BR4a2 native stamped a red with no evidence"
grep -q '"step":"tests: GREEN"' "$RD4/spool/$DAY.jsonl" \
  && ok "BR4a2 native: the delivery shape no longer changes the verdict — GREEN either way" \
  || bad "BR4a2 native should read the object shape the same as the string shape"
[ "$rcn4" = "0" ] \
  && bad "BR4a2 the oracle stopped diverging — fold this case back into a differential" \
  || ok "BR4a2 node still calls the same run RED in the object shape (open front, JS side)"

# and the third answer still exists, on a payload that really is unreadable:
# a suite redirected to a file, where the hook sees an exit line and nothing else.
C4b="$(mktemp -d)"; RD4b="$(mktemp -d)"; : > "$RD4b/enabled"; mkdir -p "$C4b/.rabadon"
echo '{"project":"p","testCommand":"npm test"}' > "$C4b/.rabadon/guard.json"
printf '{"hook_event_name":"PostToolUse","cwd":"%s","session_id":"s1","tool_use_id":"g1c","tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":{"stdout":"EXIT=0"}}' "$C4b" \
  | env $DIFF_ENV RABADON_DIR="$RD4b" RABADON_NOTIFY=0 "$BIN" >/dev/null 2>&1; rcv4b=$?
grep -q '"ev":"TEST_EVIDENCE_MISSING"' "$RD4b/spool/$DAY.jsonl" && [ "$rcv4b" = "0" ] \
  && ok "BR4a2b a redirected run is still neither green nor red, and says so" \
  || bad "BR4a2b expected TEST_EVIDENCE_MISSING at exit 0, got $rcv4b"
echo "    note: hooks/gate.mjs (retiring oracle) exits $rcn4 here — a false red, tracked."

differential "BR4b ctest '100% tests passed, 0 failed' -> GREEN" \
  '{"hook_event_name":"PostToolUse","cwd":"CWD","session_id":"s1","tool_use_id":"g2","tool_name":"Bash","tool_input":{"command":"ctest"},"tool_response":{"stdout":"100% tests passed, 0 tests failed out of 12"}}' \
  '{"project":"p","testCommand":"ctest"}'
# object response with ESCAPED \n (the exact Claude Code delivery shape)
differential "BR4c JSON-object tool_response with escaped \\n -> de-escaped then matched" \
  '{"hook_event_name":"PostToolUse","cwd":"CWD","session_id":"s1","tool_use_id":"g3","tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":{"stdout":"ℹ tests 52\\nℹ pass 52\\nℹ fail 0"}}' \
  '{"project":"p","testCommand":"npm test"}'
grep -q '"step":"tests: GREEN"' "$LAST_RDV/spool/$DAY.jsonl" && ok "BR4c escaped-newline object still reads GREEN" || bad "BR4c escaped \\n not de-escaped"

# =====================================================================
# BR5 — test RED + incident loop
# =====================================================================
echo "BR5 test RED + incident"
DIFF_ENV="RABADON_JUDGE=0"
differential "BR5a RED with JUDGE=0 -> exit 2, CHECK_FAIL test-run, no REPAIR_START" \
  '{"hook_event_name":"PostToolUse","cwd":"CWD","session_id":"s1","tool_use_id":"r1","tool_name":"Bash","tool_input":{"command":"ctest"},"tool_response":{"stdout":"2 failed, 5 passed\nboom at line 9"}}' \
  '{"project":"p","testCommand":"ctest"}'
grep -q '"check":"test-run"' "$LAST_RDV/spool/$DAY.jsonl" && ok "BR5a CHECK_FAIL test-run present" || bad "BR5a missing test-run"
grep -q '"ev":"REPAIR_START"' "$LAST_RDV/spool/$DAY.jsonl" && bad "BR5a REPAIR_START must NOT fire with JUDGE=0" || ok "BR5a no REPAIR_START under JUDGE=0"
nstate "$LAST_CV" | python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(0 if d.get('lastTestFail',0)!=0 and d.get('lastTestPass',1)==0 else 1)" \
  && ok "BR5a lastTestFail SET, lastTestPass untouched" || bad "BR5a red test state wrong"
grep -q "rabadon: tests are RED. Fix the failure before moving on." /tmp/pt_vs.$$ && ok "BR5a RED stderr (no advice under JUDGE=0)" || bad "BR5a RED stderr wrong"

# RED WITH the stub diagnose (newRule null) -> REPAIR_START + advice, no rule
C="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$C/.rabadon"
echo '{"project":"p","testCommand":"ctest"}' > "$C/.rabadon/guard.json"
S="$C/sentinel"; K="$C/calls"
echo '{"hook_event_name":"PostToolUse","cwd":"'"$C"'","session_id":"s1","tool_use_id":"r2","tool_name":"Bash","tool_input":{"command":"ctest"},"tool_response":{"stdout":"2 failed\nboom"}}' \
  | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"where":"w","cause":"c","fix":"f","newRule":null}' RABADON_STUB_SENTINEL="$S" RABADON_STUB_CALLS="$K" RABADON_DIR="$RD" "$BIN" 2>/tmp/pt_d.$$; rc=$?
[ "$rc" = 2 ] && ok "BR5b RED + diagnose -> exit 2" || bad "BR5b expected exit 2 (got $rc)"
grep -q '"ev":"REPAIR_START"' "$RD/spool/$DAY.jsonl" && ok "BR5b REPAIR_START emitted" || bad "BR5b REPAIR_START missing"
grep -q "where: w" /tmp/pt_d.$$ && grep -q "cause: c" /tmp/pt_d.$$ && grep -q "fix:   f" /tmp/pt_d.$$ \
  && ok "BR5b advice block carries where/cause/fix" || bad "BR5b advice block wrong"
python3 -c "import json;d=json.load(open('$C/.rabadon/state.json'));import sys;sys.exit(0 if d.get('lastDiagAt',0)!=0 and d.get('lastDiagSig') else 1)" \
  && ok "BR5b lastDiagSig + lastDiagAt set (top-level dedup fields)" || bad "BR5b diag dedup fields not set"

# =====================================================================
# BR6 — incident dedup (same failSig within 15min -> no 2nd diagnose)
# =====================================================================
echo "BR6 incident dedup"
C="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$C/.rabadon"
echo '{"project":"p","testCommand":"ctest"}' > "$C/.rabadon/guard.json"
K="$C/calls"; echo 0 > "$K"
EVT='{"hook_event_name":"PostToolUse","cwd":"'"$C"'","session_id":"s1","tool_use_id":"TID","tool_name":"Bash","tool_input":{"command":"ctest"},"tool_response":{"stdout":"2 failed\nsame boom"}}'
echo "${EVT/TID/d1}" | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"where":"w","cause":"c","fix":"f","newRule":null}' RABADON_STUB_CALLS="$K" RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
echo "${EVT/TID/d2}" | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"where":"w","cause":"c","fix":"f","newRule":null}' RABADON_STUB_CALLS="$K" RABADON_DIR="$RD" "$BIN" >/tmp/pt_d2.$$ 2>&1
calls="$(cat "$K")"
[ "$calls" = 1 ] && ok "BR6 same incident within 15min -> diagnose runs ONCE (call count 1)" || bad "BR6 expected 1 diagnose call, got $calls"
reps="$(grep -c '"ev":"REPAIR_START"' "$RD/spool/$DAY.jsonl")"
[ "$reps" = 1 ] && ok "BR6 REPAIR_START emitted once, not twice" || bad "BR6 REPAIR_START fired $reps times"
# bump lastDiagAt back >15min and refire -> diagnose runs again
python3 -c "import json;p='$C/.rabadon/state.json';d=json.load(open(p));d['lastDiagAt']=d['lastDiagAt']-16*60000;json.dump(d,open(p,'w'))"
echo "${EVT/TID/d3}" | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"where":"w","cause":"c","fix":"f","newRule":null}' RABADON_STUB_CALLS="$K" RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
calls2="$(cat "$K")"
[ "$calls2" = 2 ] && ok "BR6 after 15min the same incident diagnoses again (call count 2)" || bad "BR6 stale-window refire wrong (calls=$calls2)"

# =====================================================================
# BR7 — rule authoring into guard.json (deny -> bash, match -> protectedPaths)
# =====================================================================
echo "BR7 rule authoring"
author() { # $1=stubjson $2=guard-extra-json -> native run; sets AC (cwd) / ARD
  AC="$(mktemp -d)"; ARD="$(mktemp -d)"; : > "$ARD/enabled"; mkdir -p "$AC/.rabadon"
  printf '%s\n' "$2" > "$AC/.rabadon/guard.json"
  echo '{"hook_event_name":"PostToolUse","cwd":"'"$AC"'","session_id":"s1","tool_use_id":"a'"$RANDOM"'","tool_name":"Bash","tool_input":{"command":"ctest"},"tool_response":{"stdout":"9 failed\ncrash"}}' \
    | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON="$1" RABADON_DIR="$ARD" "$BIN" >/tmp/pt_a.$$ 2>&1
}
GUARD_BASE='{"project":"p","testCommand":"ctest","bash":[{"id":"existing","deny":"rm -rf /","why":"never"}]}'
author '{"where":"w","cause":"c","fix":"f","newRule":{"id":"no-force-push","deny":"git push --force","why":"never","catches":["git push --force origin main"]}}' "$GUARD_BASE"
python3 - "$AC/.rabadon/guard.json" <<'PY' && ok "BR7 deny rule installed into bash[] with authoredBy+incidentAt, pretty+trailing-nl" || bad "BR7 deny rule authoring wrong"
import json,sys
p=sys.argv[1]; txt=open(p).read(); g=json.loads(txt)
r=[x for x in g["bash"] if x["id"]=="no-force-push"]
assert r, "rule not in bash[]"
r=r[0]
assert r["deny"]=="git push --force" and r["why"]=="never"
assert r["authoredBy"]=="incident" and r.get("incidentAt")
assert txt.endswith("\n"), "no trailing newline"
assert '\n  "project"' in txt or '\n  "' in txt, "not 2-space pretty"
sys.exit(0)
PY
grep -q '"step":"new gate: no-force-push"' "$ARD/spool/$DAY.jsonl" && ok "BR7 REPAIR_OK 'new gate: no-force-push' on the ledger" || bad "BR7 REPAIR_OK missing"
grep -q "new gate installed: no-force-push" /tmp/pt_a.$$ && ok "BR7 advice mentions the new gate" || bad "BR7 advice missing new-gate line"
# refire same red with same rule id -> NOT appended twice (id dedup)
echo '{"hook_event_name":"PostToolUse","cwd":"'"$AC"'","session_id":"s1","tool_use_id":"a-again","tool_name":"Bash","tool_input":{"command":"ctest"},"tool_response":{"stdout":"9 failed\ncrash-different"}}' \
  | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"where":"w","cause":"c","fix":"f","newRule":{"id":"no-force-push","deny":"git push --force","why":"never","catches":["git push --force origin main"]}}' RABADON_DIR="$ARD" "$BIN" >/dev/null 2>&1
cnt="$(python3 -c "import json;g=json.load(open('$AC/.rabadon/guard.json'));print(len([x for x in g['bash'] if x['id']=='no-force-push']))")"
[ "$cnt" = 1 ] && ok "BR7 id-dedup: the same rule id is not appended twice" || bad "BR7 rule duplicated ($cnt copies)"
# newRule.match -> lands in protectedPaths[]
author '{"where":"w","cause":"c","fix":"f","newRule":{"id":"no-touch-lock","match":"package-lock\\.json$","why":"generated","catches":["/Users/x/proj/package-lock.json"]}}' '{"project":"p","testCommand":"ctest"}'
python3 -c "import json;g=json.load(open('$AC/.rabadon/guard.json'));import sys;sys.exit(0 if any(x['id']=='no-touch-lock' for x in g.get('protectedPaths',[])) and not g.get('bash') else 1)" \
  && ok "BR7 match rule lands in protectedPaths[], not bash[]" || bad "BR7 match rule mis-targeted"
# invalid regex -> NOT installed, no crash
author '{"where":"w","cause":"c","fix":"f","newRule":{"id":"bad-rx","deny":"[","why":"broken"}}' '{"project":"p","testCommand":"ctest"}'
python3 -c "import json;g=json.load(open('$AC/.rabadon/guard.json'));import sys;sys.exit(0 if not any(x.get('id')=='bad-rx' for x in g.get('bash',[])) else 1)" \
  && ok "BR7 invalid-regex rule is dropped, never installed" || bad "BR7 invalid regex installed"
grep -q '"step":"new gate: bad-rx"' "$ARD/spool/$DAY.jsonl" && bad "BR7 REPAIR_OK for the dropped invalid rule" || ok "BR7 no REPAIR_OK for the dropped rule"

# BR7b — COMPILING IS NOT FIRING, and this is the path that paid for the
# difference. Of the 16 rules on this machine that could refuse nothing in any
# repository, three were authored right here after real incidents, so each named
# something that had already happened once and was free to happen again — and
# the session that authored one was told a new gate had been installed.
#
# A proposal now has to name what it would have refused, and the example is
# driven through the proposal's own pattern with the gate's own matcher.
#
# The pattern below is the ordinary authoring mistake: a rule written across an
# `&&`, which is how a person describes what they saw. The line is split on `&&`
# before any rule is consulted, so no surface a rule is judged against carries
# both halves, and this rule can never fire.
author '{"where":"w","cause":"c","fix":"f","newRule":{"id":"cd-then-delete","deny":"cd\\s+\\S+\\s+&&\\s+rm\\s+-rf","why":"hides the target","catches":["cd /tmp/build && rm -rf ."]}}' '{"project":"p","testCommand":"ctest"}'
python3 -c "import json;g=json.load(open('$AC/.rabadon/guard.json'));import sys;sys.exit(0 if not any(x.get('id')=='cd-then-delete' for x in g.get('bash',[])) else 1)" \
  && ok "BR7b a proposed rule that cannot refuse its own example is NOT installed" \
  || bad "BR7b a rule that can never fire was written into the guard"
grep -q "cannot refuse cd /tmp/build && rm -rf ." /tmp/pt_a.$$ \
  && ok "BR7b the session is told which example the proposal could not catch" \
  || bad "BR7b the drop was silent: $(tail -3 /tmp/pt_a.$$ | tr '\n' ' ')"

# BR7c — and a proposal with no example at all is not installed either. A rule
# nothing proves is the state all 430 rules on this machine were in until
# tonight, and it is the state that hid sixteen dead ones.
author '{"where":"w","cause":"c","fix":"f","newRule":{"id":"unproven-rule","deny":"git\\s+push\\s+--force","why":"needs review"}}' '{"project":"p","testCommand":"ctest"}'
python3 -c "import json;g=json.load(open('$AC/.rabadon/guard.json'));import sys;sys.exit(0 if not any(x.get('id')=='unproven-rule' for x in g.get('bash',[])) else 1)" \
  && ok "BR7c a proposal carrying no example is not installed" \
  || bad "BR7c a rule with nothing proving it was installed"

# BR7d — TWIN. A proposal that names what it would have stopped, and whose
# pattern really does stop it, still lands. A check that only ever rejects is a
# check nobody can ship behind.
author '{"where":"w","cause":"c","fix":"f","newRule":{"id":"no-hard-reset","deny":"git\\s+reset\\s+--hard","why":"discards work","catches":["git reset --hard origin/main"]}}' '{"project":"p","testCommand":"ctest"}'
python3 -c "import json;g=json.load(open('$AC/.rabadon/guard.json'));import sys;sys.exit(0 if any(x.get('id')=='no-hard-reset' for x in g.get('bash',[])) else 1)" \
  && ok "BR7d a proven proposal is still installed" \
  || bad "BR7d a rule that can fire was refused: $(tail -3 /tmp/pt_a.$$ | tr '\n' ' ')"

# =====================================================================
# BR8 — RABADON_OFF=1 in the child env (the recursion root-fix)
# =====================================================================
echo "BR8 RABADON_OFF propagated to the claude child"
C="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$C/.rabadon"
echo '{"project":"p","testCommand":"ctest"}' > "$C/.rabadon/guard.json"
S="$C/sentinel"
echo '{"hook_event_name":"PostToolUse","cwd":"'"$C"'","session_id":"s1","tool_use_id":"off1","tool_name":"Bash","tool_input":{"command":"ctest"},"tool_response":{"stdout":"2 failed\nboom"}}' \
  | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"where":"w","cause":"c","fix":"f","newRule":null}' RABADON_STUB_SENTINEL="$S" RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ "$(cat "$S" 2>/dev/null)" = 1 ] && ok "BR8 diagnose child saw RABADON_OFF=1 (supervisor never supervises itself)" || bad "BR8 child RABADON_OFF was '$(cat "$S" 2>/dev/null)', expected 1"
# re-anchor child too
C2="$(mktemp -d)"; RD2="$(mktemp -d)"; mkdir -p "$C2/.rabadon"
python3 -c "import json;json.dump({'sessions':{'s1':{'goalPrompt':'g','actionCount':12,'recent':[{'t':1,'s':'m'}]}}},open('$C2/.rabadon/state.json','w'))"
S2="$C2/sentinel"
echo '{"hook_event_name":"PostToolUse","cwd":"'"$C2"'","session_id":"s1","tool_use_id":"off2","tool_name":"Edit","tool_input":{"file_path":"'"$C2"'/src/x.js"}}' \
  | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"onTrack":true}' RABADON_STUB_SENTINEL="$S2" RABADON_DIR="$RD2" "$BIN" >/dev/null 2>&1
[ "$(cat "$S2" 2>/dev/null)" = 1 ] && ok "BR8 driftJudge child also saw RABADON_OFF=1" || bad "BR8 judge child RABADON_OFF was '$(cat "$S2" 2>/dev/null)'"

# BR8b — a hanging stub is killed by the bounded timeout (fail-open to RED)
echo "BR8b bounded subprocess kills a hanging stub"
C="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$C/.rabadon"
echo '{"project":"p","testCommand":"ctest"}' > "$C/.rabadon/guard.json"
# a 1s timeout override is not exposed; instead prove the wall-clock path by a
# stub that sleeps LONGER than the process should wait for output-less hang.
# We can't wait 90s in CI, so cap the harness: run with a short sleep and assert
# the RED terminal still fires (advice may be empty) and the process returns.
t0=$(python3 -c "import time;print(time.time())")
echo '{"hook_event_name":"PostToolUse","cwd":"'"$C"'","session_id":"s1","tool_use_id":"hang1","tool_name":"Bash","tool_input":{"command":"ctest"},"tool_response":{"stdout":"2 failed\nboom"}}' \
  | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"where":"w","cause":"c","fix":"f","newRule":null}' RABADON_STUB_SLEEP=2 RABADON_DIR="$RD" "$BIN" >/dev/null 2>/tmp/pt_h.$$; rc=$?
t1=$(python3 -c "import time;print(time.time())")
dt=$(python3 -c "print($t1-$t0)")
[ "$rc" = 2 ] && ok "BR8b RED terminal still fires around a slow child (exit 2, ${dt}s)" || bad "BR8b slow child broke the terminal (rc=$rc)"

# =====================================================================
# BR9 — non-test Bash
# =====================================================================
echo "BR9 non-test Bash"
DIFF_ENV="RABADON_JUDGE=0"
differential "BR9 'ls -la' -> STEP_OK ran, no state mutation" \
  '{"hook_event_name":"PostToolUse","cwd":"CWD","session_id":"s1","tool_use_id":"n1","tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_response":{"stdout":"files"}}'
grep -q '"step":"ran: ls -la"' "$LAST_RDV/spool/$DAY.jsonl" && ok "BR9 STEP_OK 'ran: ls -la'" || bad "BR9 ran step missing"
nstate "$LAST_CV" | python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(0 if d.get('lastCodeEdit',0)==0 and d.get('lastTestRun',0)==0 else 1)" \
  && ok "BR9 no lastTest*/lastCodeEdit mutation on a non-test bash" || bad "BR9 unexpected state mutation"

# =====================================================================
# BR10 — any other tool (Read) -> done(null), zero events
# =====================================================================
echo "BR10 other tool (Read/Grep)"
DIFF_ENV="RABADON_JUDGE=0"
differential "BR10 Read -> exit 0, ZERO spool events, no state mutation" \
  '{"hook_event_name":"PostToolUse","cwd":"CWD","session_id":"s1","tool_use_id":"rd1","tool_name":"Read","tool_input":{"file_path":"CWD/foo"}}'
n="$(norm_spool "$LAST_RDV/spool/$DAY.jsonl" | grep -c . || true)"
[ "${n:-0}" = 0 ] && ok "BR10 Read emits ZERO spool events (done(null))" || bad "BR10 emitted $n events"

# =====================================================================
# BR11 — twin dedupe on PostToolUse (same tool_use_id)
# =====================================================================
echo "BR11 twin dedupe on Post"
twincheck() { # $1=engine ($BIN or 'node GATE') $2=label
  local C RD
  C="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$C/.rabadon"
  local E='{"hook_event_name":"PostToolUse","cwd":"'"$C"'","session_id":"s1","tool_use_id":"tu1","tool_name":"Edit","tool_input":{"file_path":"'"$C"'/src/x.js"}}'
  if [ "$1" = node ]; then
    echo "$E" | RABADON_JUDGE=0 RABADON_DIR="$RD" node "$GATE" >/dev/null 2>&1; local r1=$?
    echo "$E" | RABADON_JUDGE=0 RABADON_DIR="$RD" node "$GATE" >/dev/null 2>&1; local r2=$?
  else
    echo "$E" | RABADON_JUDGE=0 RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1; local r1=$?
    echo "$E" | RABADON_JUDGE=0 RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1; local r2=$?
  fi
  local steps
  steps="$(grep -c '"step":"edited: x.js"' "$RD/spool/$DAY.jsonl" 2>/dev/null || echo 0)"
  echo "$r1 $r2 $steps"
}
tn="$(twincheck node n)"; tv="$(twincheck "$BIN" v)"
[ "$tn" = "$tv" ] && ok "BR11 twin dedupe: node==native ($tv = r1 r2 STEP_OK-count)" || bad "BR11 node='$tn' native='$tv'"
echo "$tv" | grep -qx "0 0 1" && ok "BR11 first STEP_OK + lastCodeEdit, twin swallowed (exit 0, one STEP_OK)" || bad "BR11 expected '0 0 1', got '$tv'"

# =====================================================================
# BR12 — WHICH MODEL the judge is sent to, on both engines
# =====================================================================
# The drift judge used to carry `claude-haiku-4-5` as a literal in two source
# files. Nobody running rabadon could say which model saw their session goal and
# their last moves, and nobody could point it somewhere else. It is env now, and
# the default is the same literal — so the first case here is the OLD behaviour,
# asserted, and the second is the new lever. Read off argv, because which model
# was picked is an argv fact; a log line could agree with a wrong flag.
echo "BR12 judge model is sayable from outside"
judgemodel() { # $1=engine (native|node) $2=env value ('' = unset) -> echoes the --model argument
  local C RD argv
  C="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$C/.rabadon"
  argv="$C/argv"
  python3 -c "import json;json.dump({'sessions':{'s1':{'goalPrompt':'build the kernel','actionCount':12,'recent':[{'t':1,'s':'m'}]}}},open('$C/.rabadon/state.json','w'))"
  local E='{"hook_event_name":"PostToolUse","cwd":"'"$C"'","session_id":"s1","tool_use_id":"jm1","tool_name":"Edit","tool_input":{"file_path":"'"$C"'/src/x.js"}}'
  if [ "$1" = node ]; then
    echo "$E" | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"onTrack":true}' RABADON_STUB_ARGV="$argv" \
      ${2:+RABADON_JUDGE_MODEL=$2} RABADON_DIR="$RD" node "$GATE" >/dev/null 2>&1
  else
    echo "$E" | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"onTrack":true}' RABADON_STUB_ARGV="$argv" \
      ${2:+RABADON_JUDGE_MODEL=$2} RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
  fi
  grep -A1 -x -- '--model' "$argv" 2>/dev/null | tail -1
}
# =====================================================================
# BR13 — DEFAULT OFF: nothing is bought unless somebody asked
# =====================================================================
# The headline claim of this build. Installing rabadon used to sign you up for
# two `claude -p` calls on your own account from inside a hook. The counter
# below is the whole proof: a red suite, no RABADON_JUDGE anywhere, no guard
# key — and the stub must never be executed. The refusal itself is untouched,
# so exit 2 still has to hold.
echo "BR13 default off: a red suite calls nobody"
# Runs one red-suite incident and leaves its evidence in files, not variables:
# the assertions below need the spool and the stderr as well as the exit code,
# and a function called in $(...) is a subshell whose variables never come back.
DEFOFF_SPOOL=""; DEFOFF_ERR=""
defoff() { # $1=engine $2=guard json $3=env ('' = unset) -> echoes "rc calls"
  local C RD K rc
  C="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$C/.rabadon"
  printf '%s' "$2" > "$C/.rabadon/guard.json"
  K="$C/calls"; echo 0 > "$K"
  local E='{"hook_event_name":"PostToolUse","cwd":"'"$C"'","session_id":"s1","tool_use_id":"do1","tool_name":"Bash","tool_input":{"command":"ctest"},"tool_response":{"stdout":"2 failed\nboom"}}'
  if [ "$1" = node ]; then
    echo "$E" | env -u RABADON_JUDGE PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"where":"w","cause":"c","fix":"f"}' \
      RABADON_STUB_CALLS="$K" ${3:+RABADON_JUDGE=$3} RABADON_DIR="$RD" node "$GATE" >/tmp/pt_do.$$ 2>&1; rc=$?
  else
    echo "$E" | env -u RABADON_JUDGE PATH="$STUBDIR:$PATH" RABADON_STUB_JSON='{"where":"w","cause":"c","fix":"f"}' \
      RABADON_STUB_CALLS="$K" ${3:+RABADON_JUDGE=$3} RABADON_DIR="$RD" "$BIN" >/tmp/pt_do.$$ 2>&1; rc=$?
  fi
  printf '%s' "$RD/spool/$DAY.jsonl" > /tmp/pt_do_spool.$$
  printf '%s %s' "$rc" "$(cat "$K")" > /tmp/pt_do_rc.$$
}
# Sets DEFOFF_RC / DEFOFF_SPOOL / DEFOFF_ERR. Called plainly, NEVER as
# $(defoff_run ...) — command substitution is a subshell and every assignment
# inside it dies with the child. Same mistake twice in one function while writing
# this, so it is written down rather than rediscovered.
DEFOFF_RC=""
defoff_run() {
  defoff "$@"
  DEFOFF_RC="$(cat /tmp/pt_do_rc.$$)"
  DEFOFF_SPOOL="$(cat /tmp/pt_do_spool.$$)"
  DEFOFF_ERR="$(cat /tmp/pt_do.$$)"
}
G_PLAIN='{"project":"p","testCommand":"ctest"}'
G_JUDGE='{"project":"p","testCommand":"ctest","judge":true}'
for eng in native node; do
  defoff_run "$eng" "$G_PLAIN" ''; r="$DEFOFF_RC"
  [ "$r" = "2 0" ] \
    && ok "BR13 $eng nothing set: red still refuses (exit 2) and calls claude ZERO times" \
    || bad "BR13 $eng expected '2 0' (rc calls), got '$r'"
  grep -q '"ev":"REPAIR_START"' "$DEFOFF_SPOOL" 2>/dev/null \
    && bad "BR13 $eng REPAIR_START emitted with no model call" \
    || ok "BR13 $eng no REPAIR_START without a model — the ledger claims no diagnosis"
  echo "$DEFOFF_ERR" | grep -q 'does not spend on your account unless asked' \
    && ok "BR13 $eng names the switch it is not using (no silent capability loss)" \
    || { bad "BR13 $eng silent about the disabled judge"; echo "    $DEFOFF_ERR"; }
  # the two ways to say yes
  defoff_run "$eng" "$G_PLAIN" 1; r="$DEFOFF_RC"
  [ "$r" = "2 1" ] && ok "BR13 $eng RABADON_JUDGE=1 opts in (one call)" || bad "BR13 $eng env opt-in failed, got '$r'"
  defoff_run "$eng" "$G_JUDGE" ''; r="$DEFOFF_RC"
  [ "$r" = "2 1" ] && ok "BR13 $eng guard.json \"judge\":true opts in (one call)" || bad "BR13 $eng guard opt-in failed, got '$r'"
  # and the old spelling still means off
  defoff_run "$eng" "$G_JUDGE" 0; r="$DEFOFF_RC"
  [ "$r" = "2 0" ] && ok "BR13 $eng RABADON_JUDGE=0 still wins over the guard key (backwards compatible)" || bad "BR13 $eng =0 no longer off, got '$r'"
done

# BR12b — the ledger records the spend, on both engines, success AND failure.
# A supervisor that calls a model on the operator's account has to say so in the
# same ledger it judges them with; the spend most worth seeing is the one that
# bought nothing, so a judge that timed out still has to leave a line.
llmcall() { # $1=engine $2=stub json ('' = judge returns nothing) -> echoes the LLM_CALL line
  local C RD
  C="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"; mkdir -p "$C/.rabadon"
  python3 -c "import json;json.dump({'sessions':{'s1':{'goalPrompt':'build the kernel','actionCount':12,'recent':[{'t':1,'s':'m'}]}}},open('$C/.rabadon/state.json','w'))"
  local E='{"hook_event_name":"PostToolUse","cwd":"'"$C"'","session_id":"s1","tool_use_id":"lc1","tool_name":"Edit","tool_input":{"file_path":"'"$C"'/src/x.js"}}'
  if [ "$1" = node ]; then
    echo "$E" | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON="$2" RABADON_DIR="$RD" node "$GATE" >/dev/null 2>&1
  else
    echo "$E" | env PATH="$STUBDIR:$PATH" RABADON_STUB_JSON="$2" RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
  fi
  grep '"ev":"LLM_CALL"' "$RD/spool/$DAY.jsonl" 2>/dev/null | tail -1
}
for eng in native node; do
  line="$(llmcall "$eng" '{"onTrack":true}')"
  echo "$line" | grep -q '"purpose":"drift"' && echo "$line" | grep -q '"ok":true' \
    && ok "BR12b $eng drift judge writes LLM_CALL ok:true" \
    || { bad "BR12b $eng LLM_CALL missing/wrong on success"; echo "    $line"; }
  echo "$line" | grep -q '"model":"claude-haiku-4-5"' \
    && ok "BR12b $eng LLM_CALL names the model that was actually called" \
    || bad "BR12b $eng LLM_CALL model wrong"
  echo "$line" | grep -qE '"ms":[0-9]+' \
    && ok "BR12b $eng LLM_CALL carries the wall-clock the session waited" \
    || bad "BR12b $eng LLM_CALL has no ms"
  # unparseable answer = the judge bought nothing; the line must still exist
  line="$(llmcall "$eng" 'not json at all')"
  echo "$line" | grep -q '"ok":false' \
    && ok "BR12b $eng a judge that answered nothing STILL leaves a spend line" \
    || { bad "BR12b $eng no LLM_CALL on a failed judge"; echo "    $line"; }
done

for eng in native node; do
  got="$(judgemodel "$eng" '')"
  [ "$got" = "claude-haiku-4-5" ] \
    && ok "BR12 $eng default judge model is claude-haiku-4-5 (what used to be compiled in)" \
    || bad "BR12 $eng default model wrong (got '$got')"
  got="$(judgemodel "$eng" 'some-other-model')"
  [ "$got" = "some-other-model" ] \
    && ok "BR12 $eng RABADON_JUDGE_MODEL overrides it" \
    || bad "BR12 $eng override ignored (got '$got')"
done

# ---------------- BR13: a passing suite that TALKS about failure ----------------
# Measured today, on this repository, by rabadon refusing its own work. The
# suite redbase_test.sh finished `26 ok, 0 fail` and the gate answered "tests
# are RED. Fix the failure before moving on." — because one of the things that
# suite proves is named "carries the real failing output". The word `failing`,
# inside the NAME of an assertion that PASSED.
#
# Same family as BR4a2 above, and the family that decides whether anyone keeps
# the tool: a supervisor that stops a green run stops being consulted. The
# counted zero was already being stripped out of the evidence; it simply had no
# vote. A run that counted its own failures and found none now outranks a loose
# failure word standing further down the same output.
#
# The last arm is what keeps the fix from becoming a hole: a crash string still
# wins, because `0 failed` next to a segfault is a count describing a run that
# never reached the end.
C13="$(mktemp -d)"; RD13="$(mktemp -d)"; : > "$RD13/enabled"; mkdir -p "$C13/.rabadon"
echo '{"project":"p","testCommand":"npm test"}' > "$C13/.rabadon/guard.json"
br13() {
  printf '{"hook_event_name":"PostToolUse","cwd":"%s","session_id":"s13","tool_use_id":"t%s","tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":{"stdout":"%s"}}' \
    "$C13" "$RANDOM" "$1" | env $DIFF_ENV RABADON_DIR="$RD13" RABADON_NOTIFY=0 RABADON_JUDGE=0 "$BIN" >/dev/null 2>&1; echo $?
}
[ "$(br13 'ok - and carries the real failing output\\nred base: 26 ok, 0 fail')" = "0" ] \
  && ok "BR13 a suite counting 0 failures is GREEN even when its own text says 'failing'" \
  || bad "BR13 false red: the word beat the count — this is the bug that refused our own green suite"
[ "$(br13 'FAILED tests/x.py::test_a\\n1 failed, 5 passed')" = "2" ] \
  && ok "BR13 a real counted failure is still RED" \
  || bad "BR13 a genuine red went unnoticed"
[ "$(br13 'Segmentation fault\\n0 failed')" = "2" ] \
  && ok "BR13 a crash string still outranks a zero count — the run died before it could count" \
  || bad "BR13 a segfault was excused by a zero count"

# ---------------- cleanup + verdict ----------------
rm -f /tmp/pt_*.$$ 2>/dev/null
rm -rf "$STUBDIR" 2>/dev/null
echo "gate postuse: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
