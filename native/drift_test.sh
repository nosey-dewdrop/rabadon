#!/usr/bin/env bash
# rabadon-drift proof — the direction check fires in BOTH directions and never
# blocks. Drives the real binary on scratch git repos. The JS judge this
# replaces never fired once in 1691 real events; this asserts it fires.
set -u
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-drift"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-drift"; exit 1; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

scratch() {
  d="$(mktemp -d)"; ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && mkdir -p native .rabadon && echo x > native/seed.c && git add -A && git commit -qm seed )
  echo "$d"
}
promise() {
  cat > "$1/.rabadon/promise.json" <<'EOF'
{ "north_star": "native C++ core only",
  "areas": ["^native/"], "anti_paths": ["\\.mjs$"],
  "keywords": ["native","gate"], "off_keywords": ["landing"] }
EOF
}

# --- case A: on-target work -> on the star (exit 0) ---
A="$(scratch)"; promise "$A"
echo "// gate work" >> "$A/native/gate.cpp"
RD="$(mktemp -d)"; RABADON_DIR="$RD" "$BIN" "$A" >/dev/null 2>&1
[ $? -eq 0 ] && ok "on-target session verdict is on-the-star (exit 0)" || bad "on-target should be exit 0"

# --- case B: off-target + forbidden .mjs -> DRIFT (exit 3) + ledger event ---
B="$(scratch)"; promise "$B"
mkdir -p "$B/web"; echo "export const x=1" > "$B/web/feature.mjs"; echo "body{}" > "$B/web/style.css"
RD="$(mktemp -d)"; out="$(RABADON_DIR="$RD" "$BIN" "$B" 2>&1)"; rc=$?
[ $rc -eq 3 ] && ok "off-target + .mjs session verdict is DRIFT (exit 3)" || bad "drift should be exit 3 (got $rc)"
echo "$out" | grep -q "swore off" && ok "drift names the forbidden ground it touched" || bad "drift should name the anti-path"
day="$(date +%Y-%m-%d)"
grep -q '"check":"goal-drift"' "$RD/spool/$day.jsonl" 2>/dev/null \
  && ok "the ledger finally carries a goal-drift event" || bad "drift must write CHECK_FAIL goal-drift to the spool"

# --- case C: no promise -> fail OPEN, silent (exit 0) ---
C="$(scratch)"
RD="$(mktemp -d)"; RABADON_DIR="$RD" "$BIN" "$C" --quiet-ok >/dev/null 2>&1
[ $? -eq 0 ] && ok "no north star -> advisory fails open (exit 0)" || bad "missing promise should be exit 0"

# --- case D: broken promise json -> fail OPEN (never crashes) ---
D="$(scratch)"; echo '{ this is not json ' > "$D/.rabadon/promise.json"
RD="$(mktemp -d)"; RABADON_DIR="$RD" "$BIN" "$D" >/dev/null 2>&1
[ $? -eq 0 ] && ok "unparseable promise -> fails open, no crash (exit 0)" || bad "broken promise must fail open"

echo ""
echo "drift: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
