#!/usr/bin/env bash
# rabadon-serve proof — the three questions a technical buyer asks, answered by
# running the real server over a real socket. No mocks: a live process, real
# HTTP, real files on disk, real concurrent writers.
#
#   "how does my team get runs in?"  -> a key per project, a POST, a counted result
#   "does it survive a reboot?"      -> kill -9 the server, restart, the ledger and
#                                        its dedupe memory are both still there
#   "can I trust the numbers?"       -> a retried batch is absorbed, not double-counted,
#                                        and 20 concurrent writers produce exactly the
#                                        lines they sent, none torn
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/rabadon-serve"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-serve"; exit 1; }
command -v curl >/dev/null || { echo "curl required"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

TMP="$(mktemp -d)"
PORT=$(( 14300 + (RANDOM % 400) ))
STORE="$TMP/team"
KEYS="$TMP/keys"
cat > "$KEYS" <<'EOF'
# key                project
sk-team-alpha        acme-api
sk-team-beta         acme-web
sk-evil              ../../etc/passwd
EOF

start_server() {
  "$BIN" --port "$PORT" --store "$STORE" --keys "$KEYS" --threads 8 >"$TMP/serve.log" 2>&1 &
  SPID=$!
  for _ in $(seq 1 100); do
    curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 && return 0
    perl -e 'select(undef,undef,undef,0.05)'
  done
  echo "server did not come up; log:"; cat "$TMP/serve.log"; return 1
}
stop_server() { kill -9 "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null; }
trap 'stop_server; rm -rf "$TMP"' EXIT

start_server || exit 1

post() {  # <key> <body-file>  -> prints the JSON response
  curl -sS --max-time 20 -H 'Connection: close' -X POST "http://127.0.0.1:$PORT/ingest" \
    -H "x-rabadon-key: $1" --data-binary "@$2" \
    -w '\n%{http_code}' 2>/dev/null
}

# ---- 1: health ----
curl -fsS "http://127.0.0.1:$PORT/healthz" | grep -q '"ok":true' \
  && ok "the server answers /healthz" || bad "/healthz failed"

# ---- 2: no key / wrong key are refused (a ledger with open write access is not a ledger) ----
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/ingest" --data '{"ev":"X","run":"r"}')
[ "$code" = "401" ] && ok "a POST with no key is refused (401)" || bad "no-key POST returned $code"
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/ingest" -H 'x-rabadon-key: nope' --data '{"ev":"X","run":"r"}')
[ "$code" = "401" ] && ok "an unknown key is refused (401)" || bad "bad-key POST returned $code"

# ---- 3: a real batch lands, counted ----
cat > "$TMP/batch1.jsonl" <<'EOF'
{"v":1,"ts":1,"run":"run-a","pipe":"acme:do","ev":"RUN_START","steps":2,"arm":"routed","tiers":"haiku,opus"}
{"v":1,"ts":2,"run":"run-a","pipe":"acme:do","ev":"STEP_TRY","step":"s1","tier":1,"tier_name":"haiku","usd_e6":20000}
{"v":1,"ts":3,"run":"run-a","pipe":"acme:do","ev":"STEP_OK","step":"s1","tier":1}
EOF
r=$(post sk-team-alpha "$TMP/batch1.jsonl")
echo "$r" | grep -q '"accepted":3' && ok "a 3-event batch is accepted and counted" || bad "first batch: $r"
DAY=$(date -u +%Y-%m-%d)
LEDGER="$STORE/acme-api/$DAY.jsonl"
[ -f "$LEDGER" ] && [ "$(wc -l < "$LEDGER")" -eq 3 ] \
  && ok "the events are on disk, in the project's own ledger" || bad "ledger missing or wrong length"

# ---- 4: the SAME batch again is absorbed, not double-counted ----
r=$(post sk-team-alpha "$TMP/batch1.jsonl")
echo "$r" | grep -q '"accepted":0' && echo "$r" | grep -q '"duplicate":3' \
  && ok "a retried batch is absorbed (accepted 0, duplicate 3) — a retry cannot double-bill" \
  || bad "retry not deduped: $r"
[ "$(wc -l < "$LEDGER")" -eq 3 ] && ok "the ledger did not grow on the retry" || bad "ledger grew on retry"

# ---- 5: garbage is rejected loudly, never appended quietly ----
printf 'not json at all\n{"ev":"NOFIELDS"}\n{"v":1,"ts":9,"run":"run-a","ev":"STEP_OK","step":"s2"}\n' > "$TMP/garbage.jsonl"
r=$(post sk-team-alpha "$TMP/garbage.jsonl")
echo "$r" | grep -q '"rejected":2' && echo "$r" | grep -q '"accepted":1' \
  && ok "malformed lines are rejected and counted, the good one still lands" || bad "garbage handling: $r"

# ---- 6: projects are isolated by key ----
r=$(post sk-team-beta "$TMP/batch1.jsonl")
echo "$r" | grep -q '"project":"acme-web"' && ok "a different key writes to a different project" || bad "project routing: $r"
[ -f "$STORE/acme-web/$DAY.jsonl" ] && ok "the second project has its own ledger file" || bad "second ledger missing"

# ---- 7: a project name cannot escape the store directory ----
r=$(post sk-evil "$TMP/batch1.jsonl")
[ ! -e "$STORE/../../etc/passwd" ] && ok "a hostile project name cannot traverse out of the store" \
  || bad "path traversal succeeded"

# ---- 8: 20 concurrent writers, nothing torn, nothing lost ----
CONC_DIR="$TMP/conc"; mkdir -p "$CONC_DIR"
for w in $(seq 1 20); do
  : > "$CONC_DIR/w$w.jsonl"
  for e in $(seq 1 50); do
    printf '{"v":1,"ts":%d,"run":"run-c%d","pipe":"acme:do","ev":"STEP_OK","step":"s%d"}\n' \
      "$((w*1000+e))" "$w" "$e" >> "$CONC_DIR/w$w.jsonl"
  done
done
before=$(wc -l < "$LEDGER")
pids=""
for w in $(seq 1 20); do post sk-team-alpha "$CONC_DIR/w$w.jsonl" >/dev/null & pids="$pids $!"; done
# wait on the WRITERS only: a bare `wait` also waits on the server we started in
# the background, which never exits — the test would hang forever on its own harness.
for p in $pids; do wait "$p"; done
after=$(wc -l < "$LEDGER")
[ $((after - before)) -eq 1000 ] \
  && ok "20 concurrent writers x 50 events = exactly 1000 new lines (no loss, no duplication)" \
  || bad "concurrent write count wrong: gained $((after - before)), wanted 1000"
python3 - "$LEDGER" <<'PY' && ok "every line in the ledger is still a complete, parseable event" || bad "the ledger has torn lines"
import json,sys
bad=0
for i,l in enumerate(open(sys.argv[1])):
    l=l.strip()
    if not l: continue
    try: json.loads(l)
    except Exception: bad+=1; print("  torn line",i+1,l[:80])
raise SystemExit(1 if bad else 0)
PY

# ---- 9: SURVIVES A REBOOT — kill -9, restart, history and dedupe memory intact ----
lines_before=$(wc -l < "$LEDGER")
stop_server
start_server || exit 1
[ "$(wc -l < "$LEDGER")" -eq "$lines_before" ] \
  && ok "after kill -9 and restart the ledger is intact ($lines_before lines)" || bad "ledger changed across restart"
r=$(post sk-team-alpha "$TMP/batch1.jsonl")
echo "$r" | grep -q '"duplicate":3' \
  && ok "the restarted server still remembers what it holds (rebuilt from disk, retry still absorbed)" \
  || bad "dedupe memory lost across restart: $r"

# ---- 10: an unknown route does not silently 200 ----
code=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/nope")
[ "$code" = "404" ] && ok "an unknown route is a 404, never a quiet 200" || bad "unknown route returned $code"

echo ""
echo "serve: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
