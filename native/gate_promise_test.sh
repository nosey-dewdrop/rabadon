#!/usr/bin/env bash
# rabadon-gate promise proof — the goal contract is enforced INSIDE the
# session, not confessed at its end. Drives the real binary with real hook
# events: an anti-path edit is refused at attempt time, area creep is
# challenged once, the promise itself cannot be rewritten by the session,
# and a missing/broken promise fails open.
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

# RABADON_DIR is the WHOLE rabadon home (flags + spool, one rule) — so the
# enforce flag lives inside it, not in $HOME.
rdnew() { d="$(mktemp -d)"; : > "$d/enabled"; echo "$d"; }

# --- A: anti-path edit -> BLOCKED (exit 2) with the star named ---
A="$(scratch)"; RD="$(rdnew)"
out="$(edit_event "$A" "$A/web/feature.mjs" s1 | RABADON_DIR="$RD" "$BIN" 2>&1)"; rc=$?
[ $rc -eq 2 ] && ok "anti-path edit is refused at attempt time (exit 2)" || bad "anti-path edit should be exit 2 (got $rc)"
echo "$out" | grep -q "swore off" && ok "the refusal names the promise it protects" || bad "refusal should carry the star"
day="$(date -u +%Y-%m-%d)"
grep -q '"check":"promise-anti-path"' "$RD/spool/$day.jsonl" 2>/dev/null \
  && ok "the ledger carries the mid-session catch" || bad "spool must record promise-anti-path"

# --- B: on-area edit -> allowed (exit 0) ---
B="$(scratch)"; RD="$(rdnew)"
edit_event "$B" "$B/native/gate.cpp" s1 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "on-area edit flows freely (exit 0)" || bad "on-area edit should be exit 0"

# --- C: area creep -> 5th off-target edit challenged ONCE, 6th allowed ---
C="$(scratch)"; RD="$(rdnew)"
rc_seq=""
for i in 1 2 3 4 5 6; do
  edit_event "$C" "$C/docs/note$i.md" s1 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
  rc_seq="$rc_seq $?"
done
[ "$rc_seq" = " 0 0 0 0 2 0" ] && ok "area creep: 5th off-target edit challenged once, then released ($rc_seq)" \
  || bad "expected ' 0 0 0 0 2 0', got '$rc_seq'"

# --- D: the session cannot rewrite the promise itself ---
D="$(scratch)"; RD="$(rdnew)"
edit_event "$D" "$D/.rabadon/promise.json" s1 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 2 ] && ok "promise-tamper: the contract cannot be edited by the supervised session" \
  || bad "editing promise.json from the session must be exit 2"

# --- E: no promise / broken promise -> fail OPEN ---
E="$(mktemp -d)"; mkdir -p "$E/.rabadon"; RD="$(rdnew)"
edit_event "$E" "$E/web/x.mjs" s1 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "no promise -> nothing to enforce (exit 0)" || bad "missing promise must fail open"
echo '{ not json' > "$E/.rabadon/promise.json"
edit_event "$E" "$E/web/y.mjs" s2 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "broken promise -> fails open, no crash (exit 0)" || bad "broken promise must fail open"

# --- F: disabled[] does NOT silence a promise rule ---
# This case asserted the opposite until 2 August 2026, and the assertion was the
# hole. A supervised session then wrote exactly this into the repository's own
# guard -- "disabled": ["promise-anti-path", "promise-tamper"] -- citing a
# permission the operator had given about something else, and rabadon-drift
# reported "on the star" for eight days while measuring against a promise the
# drifter could rewrite. An override that the overridden party can invoke is not
# an override. The two contract rules are sealed in the binary now; the operator
# changes what they protect by editing promise.json by hand, which never comes
# through this hook. promise-off-target stays overridable and case G proves it.
F="$(scratch)"; RD="$(rdnew)"
echo '{ "project": "f", "disabled": ["promise-anti-path"] }' > "$F/.rabadon/guard.json"
edit_event "$F" "$F/web/feature.mjs" s1 | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 2 ] && ok "disabled[] does not reach a sealed promise rule (exit 2)" \
  || bad "promise-anti-path is sealed and must still refuse with disabled[] naming it"

# --- G: the seal is narrow -- an unsealed rule still answers to disabled[] ---
G="$(scratch)"; RD="$(rdnew)"
echo '{ "project": "g", "bash": [ { "id": "no-touch-foo", "deny": "touch\\s+foo", "why": "ordinary" } ], "disabled": ["no-touch-foo"] }' > "$G/.rabadon/guard.json"
printf '{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"touch foo"}}' "$G" \
  | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "an ordinary rule named in disabled[] is still switched off (exit 0)" \
  || bad "the seal must cover the contract rules only, not every rule"

echo "gate promise: $PASS ok, $FAIL fail"
[ $FAIL -eq 0 ]
