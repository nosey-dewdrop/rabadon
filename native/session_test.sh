#!/usr/bin/env bash
# rabadon-gate state proof — .rabadon/state.json has ONE owner. The native
# gate reads and writes the full schema; the stray top-level "s" alias the
# old JS writer leaked (doubling every session) dies on the first native
# save; counters survive round-trips; a twin delivery books nothing twice.
set -u
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

ev() { # $1=cwd $2=tool_use_id $3=command
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"sess-alpha","tool_use_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "$2" "$3"
}

# --- A: first event creates state.json with the session booked ---
A="$(mktemp -d)"; RD="$(mktemp -d)"
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
B="$(mktemp -d)"; mkdir -p "$B/.rabadon"; RD="$(mktemp -d)"
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
C="$(mktemp -d)"; RD="$(mktemp -d)"
ev "$C" c1 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
ev "$C" c1 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1; rc=$?
count="$(python3 -c "import json;print(json.load(open('$C/.rabadon/state.json'))['sessions']['sess-alpha']['actionCount'])")"
[ $rc -eq 0 ] && [ "$count" = "1" ] && ok "twin delivery: exit 0, actionCount stays 1" || bad "twin double-booked (rc=$rc count=$count)"

# --- D: loop-stop counters live in state.json — 3rd identical run refused ---
D="$(mktemp -d)"; RD="$(mktemp -d)"
rcs=""
for i in 1 2 3; do
  ev "$D" "d$i" "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
  rcs="$rcs $?"
done
[ "$rcs" = " 0 0 2" ] && ok "loop-stop persists through state.json ($rcs)" || bad "expected ' 0 0 2', got '$rcs'"

# --- E: an edit recorded as lastCodeEdit releases the loop counter ---
E="$(mktemp -d)"; RD="$(mktemp -d)"
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
F="$(mktemp -d)"; mkdir -p "$F/.rabadon"; RD="$(mktemp -d)"
echo "lastCmd=stale" > "$F/.rabadon/state-native-sess-alpha.txt"
ev "$F" f1 "make build" | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ ! -f "$F/.rabadon/state-native-sess-alpha.txt" ] && ok "old state-native twin file is retired on sight" \
  || bad "stale state-native file survived"

echo "gate state: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
