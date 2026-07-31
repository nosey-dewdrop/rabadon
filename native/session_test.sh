#!/usr/bin/env bash
# rabadon-gate state proof — .rabadon/state.json has ONE owner. The native
# gate reads and writes the full schema; the stray top-level "s" alias the
# old JS writer leaked (doubling every session) dies on the first native
# save; counters survive round-trips; a twin delivery books nothing twice.
set -u
# HERMETIC: rabadon is DEFAULT-OFF, so the gate is dormant unless a project opts
# in (cwd/.rabadon/on) or the machine has ~/.rabadon/enabled. A test that reads
# the real HOME passes or fails on whether the developer happens to have rabadon
# switched on — which is not a test. Give this run its own HOME with the flag set.
export HOME="$(mktemp -d)"; mkdir -p "$HOME/.rabadon"; : > "$HOME/.rabadon/enabled"
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

ev() { # $1=cwd $2=tool_use_id $3=command
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"sess-alpha","tool_use_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "$2" "$3"
}

# --- A: first event creates state.json with the session booked ---
A="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"
ev "$A" a1 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ -f "$A/.rabadon/state.json" ] && ok "state.json is created by the native gate" || bad "state.json missing"
python3 - "$A/.rabadon/state.json" <<'EOF' && ok "session booked: recent trail + actionCount live in sessions map" || bad "sessions map wrong"
import json,sys
d=json.load(open(sys.argv[1]))
s=d["sessions"]["sess-alpha"]
assert s["actionCount"]==1 and len(s["recent"])==1 and "make build" in s["recent"][0]["s"]
EOF

# --- B: the stray top-level "s" alias dies on first native save,
#         while foreign top-level counters survive the round-trip ---
B="$(mktemp -d)"; mkdir -p "$B/.rabadon"; RD="$(mktemp -d)"; : > "$RD/enabled"
cat > "$B/.rabadon/state.json" <<'EOF'
{"lastTestPass":1753000000000,"lastCodeEdit":42,
 "s":{"goalPrompt":"leaked alias","goalTs":1},
 "sessions":{"old-one":{"goalPrompt":"the real goal","goalTs":1753000000000,"recent":[{"t":1,"s":"bash: old move"}],"actionCount":7}}}
EOF
ev "$B" b1 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
python3 - "$B/.rabadon/state.json" <<'EOF' && ok "stray top-level 's' alias is gone; goal + counters preserved" || bad "state rewrite wrong"
import json,sys
d=json.load(open(sys.argv[1]))
assert "s" not in d, "stray alias survived"
assert d["lastTestPass"]==1753000000000 and d["lastCodeEdit"]==42
old=d["sessions"]["old-one"]
assert old["goalPrompt"]=="the real goal" and old["actionCount"]==7
assert d["sessions"]["sess-alpha"]["actionCount"]==1
EOF

# --- C: twin delivery (same tool_use_id) books NOTHING twice ---
C="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"
ev "$C" c1 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
ev "$C" c1 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1; rc=$?
count="$(python3 -c "import json;print(json.load(open('$C/.rabadon/state.json'))['sessions']['sess-alpha']['actionCount'])")"
[ $rc -eq 0 ] && [ "$count" = "1" ] && ok "twin delivery: exit 0, actionCount stays 1" || bad "twin double-booked (rc=$rc count=$count)"

# --- D: loop-stop counters live in state.json — 3rd identical run refused ---
D="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"
rcs=""
for i in 1 2 3; do
  ev "$D" "d$i" "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
  rcs="$rcs $?"
done
[ "$rcs" = " 0 0 2" ] && ok "loop-stop persists through state.json ($rcs)" || bad "expected ' 0 0 2', got '$rcs'"

# --- E: an edit recorded as lastCodeEdit releases the loop counter ---
E="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"
ev "$E" e1 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
ev "$E" e2 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
python3 - "$E/.rabadon/state.json" <<'EOF'
import json,sys,time
p=sys.argv[1]; d=json.load(open(p))
d["lastCodeEdit"]=int(time.time()*1000)+1000
json.dump(d,open(p,"w"))
EOF
ev "$E" e3 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a code edit in between resets the loop counter" || bad "edit should release loop-stop"

# --- F: retired state-native-*.txt twin is removed on sight ---
F="$(mktemp -d)"; mkdir -p "$F/.rabadon"; RD="$(mktemp -d)"; : > "$RD/enabled"
echo "lastCmd=stale" > "$F/.rabadon/state-native-sess-alpha.txt"
ev "$F" f1 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ ! -f "$F/.rabadon/state-native-sess-alpha.txt" ] && ok "old state-native twin file is retired on sight" \
  || bad "stale state-native file survived"

# ============ S2: cold paths native (no node anywhere) ============

pev() { # $1=cwd $2=hook $3=extra-json-fields (already comma-prefixed or empty)
  printf '{"hook_event_name":"%s","cwd":"%s","session_id":"sess-alpha"%s}' "$2" "$1" "$3"
}

# --- G: goal capture — first prompt pinned, gate's own recursion refused ---
G="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"
pev "$G" UserPromptSubmit ',"prompt":"You are rabadon, a reliability runtime supervising"' | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
sleep 2.1
pev "$G" UserPromptSubmit ',"prompt":"build the native session kernel"' | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
sleep 2.1
pev "$G" UserPromptSubmit ',"prompt":"a later prompt must not steal the goal"' | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
goal="$(python3 -c "import json;print(json.load(open('$G/.rabadon/state.json'))['sessions']['sess-alpha']['goalPrompt'])")"
[ "$goal" = "build the native session kernel" ] \
  && ok "goal capture: recursion refused, first real prompt pinned, later prompt ignored" \
  || bad "goal wrong: '$goal'"

# --- H: non-tool twin (same 2s bucket) books once ---
H="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"
pev "$H" UserPromptSubmit ',"prompt":"the goal"' | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
pev "$H" UserPromptSubmit ',"prompt":"the goal"' | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
runs="$(grep -c '"ev":"RUN_START"' "$RD/spool/$(date -u +%Y-%m-%d).jsonl" 2>/dev/null || echo 0)"
[ "$runs" = "1" ] && ok "non-tool twin dedupe: one RUN_START, not two" || bad "expected 1 RUN_START, got $runs"

# --- I: Stop writes the devridaim handoff from the trail ---
I="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"
pev "$I" UserPromptSubmit ',"prompt":"ship the native stop path"' | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
ev "$I" i1 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
sleep 2.1
pev "$I" Stop '' | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
grep -q "ship the native stop path" "$I/.rabadon/handoff.md" 2>/dev/null \
  && grep -q "make build" "$I/.rabadon/handoff.md" \
  && ok "Stop distills goal + last moves into handoff.md" || bad "handoff missing goal or moves"

# --- J: SessionStart injects a fresh handoff as context (stdout) ---
outj="$(pev "$I" SessionStart '' | RABADON_DIR="$RD" "$BIN" 2>/dev/null)"
echo "$outj" | grep -q "rabadon devridaim" \
  && ok "SessionStart injects the handoff into the new session" || bad "handoff not injected"
ac="$(python3 -c "import json;print(json.load(open('$I/.rabadon/state.json'))['sessions']['sess-alpha']['actionCount'])")"
[ "$ac" = "0" ] && ok "SessionStart resets the per-session counters" || bad "actionCount not reset ($ac)"

# --- K: Stop reads REAL usage from the transcript, incrementally ---
K="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"
T="$(mktemp)"
printf '{"type":"assistant","message":{"usage":{"input_tokens":100,"output_tokens":40}}}\n{"type":"assistant","message":{"usage":{"input_tokens":7,"output_tokens":3}}}\n' > "$T"
pev "$K" Stop ",\"transcript_path\":\"$T\"" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
toks="$(python3 -c "import json;s=json.load(open('$K/.rabadon/state.json'))['sessions']['sess-alpha'];print(s['tokensOut'],s['tokensIn'])")"
[ "$toks" = "43 107" ] && ok "token ledger measured from the transcript (43 out / 107 in)" || bad "tokens wrong: $toks"
sleep 2.1
printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":2}}}\n' >> "$T"
pev "$K" Stop ",\"transcript_path\":\"$T\"" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
toks2="$(python3 -c "import json;s=json.load(open('$K/.rabadon/state.json'))['sessions']['sess-alpha'];print(s['tokensOut'],s['tokensIn'])")"
[ "$toks2" = "45 108" ] && ok "ledger is incremental: only the new bytes are counted" || bad "incremental read wrong: $toks2"

# --- L: caught-today lands in the handoff ---
L="$(mktemp -d)"; mkdir -p "$L/.rabadon"; RD="$(mktemp -d)"; : > "$RD/enabled"
cat > "$L/.rabadon/guard.json" <<'EOF'
{ "project": "l", "bash": [{ "id": "no-rm-rf", "deny": "rm -rf /", "why": "never" }] }
EOF
ev "$L" l1 "rm -rf /tmp/x && rm -rf /" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
sleep 2.1
pev "$L" Stop '' | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
grep -q "matched deny rule" "$L/.rabadon/handoff.md" 2>/dev/null \
  && ok "the handoff carries today's catches" || bad "catch missing from handoff"

echo "gate state: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
