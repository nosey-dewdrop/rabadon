#!/usr/bin/env bash
# three-state proof — SILENT / WATCH / ENFORCE, driven through the real binary
# with real hook events.
#
# The claim under test is the adoption ramp: in WATCH the very same rule fires,
# reaches the very same verdict, and writes it to the ledger as WOULD_BLOCK —
# but the action is allowed through (exit 0). Flip one file and that identical
# verdict becomes a refusal (exit 2). If watch mode quietly evaluated FEWER
# rules than enforce mode, the "here is what I would have caught" report would
# be a lie, so the decisive assertion is that both modes catch the same thing.
set -u
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

scratch() {
  d="$(mktemp -d)"; mkdir -p "$d/.rabadon"
  cat > "$d/.rabadon/promise.json" <<'EOF'
{ "north_star": "native C++ core only",
  "areas": ["^native/"], "anti_paths": ["\\.mjs$"] }
EOF
  echo "$d"
}
edit_event() { # $1=cwd $2=file_path $3=session
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"%s","tool_use_id":"t-%s-%s","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' \
    "$1" "$3" "$(printf %s "$2" | cksum | cut -d' ' -f1)" "$$" "$2"
}
day="$(date -u +%Y-%m-%d)"

# ---- ENFORCE: the anti-path edit is refused ----
# RABADON_DIR is the WHOLE rabadon home (flags + spool, one rule): when it is
# set, the mode flag lives inside it. HOME keeps a flag too for the
# statusline calls below, which run without RABADON_DIR.
H1="$(mktemp -d)"; mkdir -p "$H1/.rabadon"; : > "$H1/.rabadon/enabled"
A="$(scratch)"; RD1="$(mktemp -d)"; : > "$RD1/enabled"
edit_event "$A" "$A/web/feature.mjs" s1 | HOME="$H1" RABADON_DIR="$RD1" "$BIN" >/dev/null 2>&1
[ $? -eq 2 ] && ok "ENFORCE: the anti-path edit is refused (exit 2)" || bad "enforce should exit 2"
grep -q '"ev":"STOP"' "$RD1/spool/$day.jsonl" 2>/dev/null \
  && ok "ENFORCE: the ledger records a real STOP" || bad "enforce STOP missing"

# ---- WATCH: same rule, same verdict, allowed through ----
H2="$(mktemp -d)"; mkdir -p "$H2/.rabadon"        # no 'enabled', no 'silent' => watch
B="$(scratch)"; RD2="$(mktemp -d)"
out="$(edit_event "$B" "$B/web/feature.mjs" s1 | HOME="$H2" RABADON_DIR="$RD2" "$BIN" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "WATCH: the same edit is allowed through (exit 0)" || bad "watch should exit 0, got $rc"
echo "$out" | grep -qi "would have blocked" \
  && ok "WATCH: it says out loud what it would have done" || bad "watch advisory missing: $out"
grep -q '"ev":"WOULD_BLOCK"' "$RD2/spool/$day.jsonl" 2>/dev/null \
  && ok "WATCH: the would-be catch is on the ledger (the week-one sales artifact)" || bad "WOULD_BLOCK missing"
grep -q '"ev":"STOP"' "$RD2/spool/$day.jsonl" 2>/dev/null \
  && bad "watch wrote a STOP — it must never claim it stopped anything" \
  || ok "WATCH: no STOP is ever written — it never claims a block it did not make"

# ---- the decisive one: watch catches the SAME rule enforce does ----
r_enf="$(grep -o '"check":"[a-z-]*"' "$RD1/spool/$day.jsonl" | sort -u)"
r_wat="$(grep -o '"check":"[a-z-]*"' "$RD2/spool/$day.jsonl" | sort -u)"
[ -n "$r_enf" ] && [ "$r_enf" = "$r_wat" ] \
  && ok "WATCH evaluates the same rules and reaches the same verdict as ENFORCE ($r_enf)" \
  || bad "watch/enforce disagree — enforce=[$r_enf] watch=[$r_wat]"

# ---- WATCH still lets legitimate work through untouched ----
C="$(scratch)"; RD3="$(mktemp -d)"
edit_event "$C" "$C/native/gate.cpp" s1 | HOME="$H2" RABADON_DIR="$RD3" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "WATCH: on-target work flows normally (exit 0)" || bad "watch blocked on-target work"

# ---- SILENT: nothing is evaluated and nothing is written ----
H3="$(mktemp -d)"; mkdir -p "$H3/.rabadon"; : > "$H3/.rabadon/silent"
D="$(scratch)"; RD4="$(mktemp -d)"; : > "$RD4/silent"
edit_event "$D" "$D/web/feature.mjs" s1 | HOME="$H3" RABADON_DIR="$RD4" "$BIN" >/dev/null 2>&1
[ $? -eq 0 ] && ok "SILENT: allowed through (exit 0)" || bad "silent should exit 0"
[ ! -f "$RD4/spool/$day.jsonl" ] \
  && ok "SILENT: writes nothing at all — dormant means dormant" || bad "silent wrote to the ledger"

# ---- the recursion guard survives the new default ----
# A child `claude -p` inherits RABADON_OFF=1. If that no longer meant SILENT,
# every repair would spawn a supervisor that supervises itself.
E="$(scratch)"; RD5="$(mktemp -d)"
edit_event "$E" "$E/web/feature.mjs" s1 | HOME="$H2" RABADON_OFF=1 RABADON_DIR="$RD5" "$BIN" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && [ ! -f "$RD5/spool/$day.jsonl" ] \
  && ok "RABADON_OFF=1 is still fully dead (the child-recursion guard holds)" \
  || bad "RABADON_OFF=1 no longer silences the gate (rc=$rc)"

# ---- the statusline tells the truth about all three ----
sl(){ printf '{"current_dir":"%s","display_name":"Opus"}' "$1" | HOME="$2" "$BIN" --statusline; }
sl "$A" "$H1" | grep -q 'rabadon' && sl "$A" "$H1" | grep -qv 'watch' \
  && ok "statusline ENFORCE: the lamp is lit, no qualifier" || bad "enforce statusline wrong"
sl "$B" "$H2" | grep -q 'rabadon watch' && ok "statusline WATCH: says 'watch' in words" || bad "watch statusline wrong"
sl "$D" "$H3" | grep -q 'rabadon off'   && ok "statusline SILENT: says 'off' in words" || bad "silent statusline wrong"

echo ""
echo "watch: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
