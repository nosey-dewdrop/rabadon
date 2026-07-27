#!/usr/bin/env bash
# rabadon-gate promise proof — the goal contract is enforced INSIDE the
# session, not confessed at its end. Drives the real binary with real hook
# events: an anti-path edit is refused at attempt time, area creep is
# challenged once, the promise itself cannot be rewritten by the session,
# and a missing/broken promise fails open.
set -u
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

scratch() {
  d="$(mktemp -d)"; mkdir -p "$d/.rabadon"
  cat > "$d/.rabadon/promise.json" <<'EOF'
{ "north_star": "native C++ core only",
  "areas": ["^native/"], "anti_paths": ["\\.mjs$"] }
EOF
  echo "$d"
}
# fire one PreToolUse edit event at the gate. The id must be unique per call
# or the gate's twin-delivery dedupe (correctly) swallows the repeat — and a
# pipeline runs this function in a subshell, so no shared counter: derive the
# id from the file path itself.
edit_event() { # $1=cwd $2=file_path $3=session
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"%s","tool_use_id":"t-%s-%s","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' \
    "$1" "$3" "$(printf %s "$2" | cksum | cut -d' ' -f1)" "$$" "$2"
}

# --- A: anti-path edit -> BLOCKED (exit 2) with the star named ---
A="$(scratch)"; RD="$(mktemp -d)"
out="$(edit_event "$A" "$A/web/feature.mjs" s1 | RABADON_DIR="$RD" "$BIN" 2>&1)"; rc=$?
[ $rc -eq 2 ] && ok "anti-path edit is refused at attempt time (exit 2)" || bad "anti-path edit should be exit 2 (got $rc)"
echo "$out" | grep -q "swore off" && ok "the refusal names the promise it protects" || bad "refusal should carry the star"
day="$(date -u +%Y-%m-%d)"
grep -q '"check":"promise-anti-path"' "$RD/spool/$day.jsonl" 2>/dev/null \
  && ok "the ledger carries the mid-session catch" || bad "spool must record promise-anti-path"

# --- B: on-area edit -> allowed (exit 0) ---
B="$(scratch)"; RD="$(mktemp -d)"
edit_event "$B" "$B/native/gate.cpp" s1 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "on-area edit flows freely (exit 0)" || bad "on-area edit should be exit 0"

# --- C: area creep -> 5th off-target edit challenged ONCE, 6th allowed ---
C="$(scratch)"; RD="$(mktemp -d)"
rc_seq=""
for i in 1 2 3 4 5 6; do
  edit_event "$C" "$C/docs/note$i.md" s1 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
  rc_seq="$rc_seq $?"
done
[ "$rc_seq" = " 0 0 0 0 2 0" ] && ok "area creep: 5th off-target edit challenged once, then released ($rc_seq)" \
  || bad "expected ' 0 0 0 0 2 0', got '$rc_seq'"

# --- D: the session cannot rewrite the promise itself ---
D="$(scratch)"; RD="$(mktemp -d)"
edit_event "$D" "$D/.rabadon/promise.json" s1 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 2 ] && ok "promise-tamper: the contract cannot be edited by the supervised session" \
  || bad "editing promise.json from the session must be exit 2"

# --- E: no promise / broken promise -> fail OPEN ---
E="$(mktemp -d)"; mkdir -p "$E/.rabadon"; RD="$(mktemp -d)"
edit_event "$E" "$E/web/x.mjs" s1 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "no promise -> nothing to enforce (exit 0)" || bad "missing promise must fail open"
echo '{ not json' > "$E/.rabadon/promise.json"
edit_event "$E" "$E/web/y.mjs" s2 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "broken promise -> fails open, no crash (exit 0)" || bad "broken promise must fail open"

# --- F: disabled[] in guard.json silences a promise rule (the override is real) ---
F="$(scratch)"; RD="$(mktemp -d)"
echo '{ "project": "f", "disabled": ["promise-anti-path"] }' > "$F/.rabadon/guard.json"
edit_event "$F" "$F/web/feature.mjs" s1 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "disabled[] override silences the promise rule (exit 0)" \
  || bad "disabled promise-anti-path should allow the edit"

echo "gate promise: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
