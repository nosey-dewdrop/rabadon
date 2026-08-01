#!/bin/bash
# audit_test.sh — the hash-chained ledger is tamper-evident, PROVEN.
#
# Chain events through the REAL gate (not synthetic writes), then attack the
# spool the way an attacker actually would and demand a verdict each time:
#   a) untouched                      -> INTACT, exit 0
#   b) one character edited           -> BREAK named at the line, exit 1
#   c) a middle line deleted          -> BREAK, exit 1
#   d) EVERY prev field stripped      -> BREAK, exit 1   (pre-0.4: said INTACT)
#   e) the day file deleted whole     -> BREAK on the orphan sidecar, exit 1
#   f) a headless legacy file         -> UNVERIFIABLE, PARTIAL, exit 2, NOT intact
# plus: the tail truncated -> the .head sidecar catches it; a line removed and
# the chain RE-STITCHED -> the head's line count catches it; --replay renders
# the verified timeline.
#
# (d) and (e) are the holes the 31.07 hand-audit walked through: strip the
# chain, or delete the file, and the old audit returned INTACT with exit 0.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
AUDIT=./native/rabadon-audit
[ -x "$GATE" ] && [ -x "$AUDIT" ] || { echo "audit_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

TMP=$(mktemp -d /tmp/rabadon-audit-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# THE LEDGER DAY IS UTC, and this file gets ONE name for it. Every writer of the
# chained day file names it with gmtime -- gate.cpp, repair.cpp, sandbox.cpp and
# the JS bus (toISOString) -- so a fixture the test builds under the LOCAL date
# is a file the gate will never append to. It cost this suite two checks: east
# of Greenwich after midnight, (h) prepared 2026-08-02.jsonl, the gate migrated
# and chained 2026-08-01.jsonl, the sidecar the test then read had no count, and
# the audit found a pre-0.4 file next to a fresh one -> rc=2. Nothing was wrong
# with the gate; the test was measuring a file it had not written. Not a mystery
# that needs a clock either: local-vs-UTC divergence is reproducible at ANY hour
# from a zone (native/ledger_day_test.sh picks one and proves the convention).
LEDGER_DAY="$(date -u +%Y-%m-%d)"
export HOME="$TMP/home"; mkdir -p "$HOME/.rabadon/spool"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
PROJ="$TMP/proj"; mkdir -p "$PROJ/.rabadon"
touch "$HOME/.rabadon/enabled"   # enforce mode: denies emit CHECK_FAIL + STOP
cat > "$PROJ/.rabadon/guard.json" <<'EOF'
{ "project": "proj", "bash": [
  { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b", "why": "test rule" }
] }
EOF

echo "audit: hash-chained ledger"

# 1) sha256 vector check via a throwaway binary is overkill; assert through the
# chain instead: known input -> known head. FIPS vector for "abc":
VEC="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
GOT=$(python3 - <<'PY'
import hashlib; print(hashlib.sha256(b"abc").hexdigest())
PY
)
[ "$GOT" = "$VEC" ] && pass "reference sha256(abc) vector agrees with python (test harness sanity)" || fail "python sanity"

fire() { # fire one denied command through the real gate (exit 2 expected)
  printf '{"hook_event_name":"PreToolUse","session_id":"s-audit","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$PROJ" \
    | "$GATE" >/dev/null 2>&1
}
fire; fire; fire

DAY=$(ls "$RABADON_DIR/spool" | grep '\.jsonl$' | head -1)
F="$RABADON_DIR/spool/$DAY"
LINES=$(wc -l < "$F" | tr -d ' ')
[ "$LINES" -ge 6 ] && pass "real gate emitted $LINES chained events (3 denies -> CHECK_FAIL+STOP each)" || fail "expected >=6 events, got $LINES"

NOPREV=$(grep -cv '"prev":"' "$F" || true)
[ "$NOPREV" -eq 0 ] && pass "every gate-emitted line carries prev" || fail "$NOPREV line(s) missing prev"

# the sidecar commits the last hash AND how many chained lines the file must have
HEAD_COUNT=$(awk '{print $2}' "$F.head")
[ "$HEAD_COUNT" = "$LINES" ] && pass "the .head sidecar commits the line count ($HEAD_COUNT = the file's $LINES chained lines)" \
  || fail "head count mismatch: sidecar says '$HEAD_COUNT', file has $LINES"

# a) untouched -> INTACT, exit 0
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "verdict: INTACT"; then pass "(a) untouched spool verifies INTACT (exit 0)"; else fail "(a) untouched spool: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

cp "$F" "$F.orig"; cp "$F.head" "$F.head.orig"
restore() { cp "$F.orig" "$F"; cp "$F.head.orig" "$F.head"; }

# b) edit one character of line 2 -> BREAK at line 3, exit 1
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split("\n")
lines[1] = lines[1].replace("force", "farce", 1)
open(p, "w").write("\n".join(lines))
PY
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -q "chain BROKEN at line 3"; then pass "(b) one edited character -> BREAK named at line 3 (exit 1)"; else fail "(b) edit not caught: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
restore

# c) delete a middle line -> BREAK, exit 1
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().rstrip("\n").split("\n")
del lines[2]
open(p, "w").write("\n".join(lines) + "\n")
PY
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -q "chain BROKEN"; then pass "(c) a deleted line -> BREAK (exit 1)"; else fail "(c) deletion not caught: rc=$RC"; fi
restore

# d) strip EVERY prev field -> BREAK, exit 1.
#    the attack the pre-0.4 audit blessed: no prev anywhere means no link can be
#    checked, and "0 chained, N unchained" was reported as INTACT.
python3 - "$F" <<'PY'
import re, sys
p = sys.argv[1]
out = []
for line in open(p).read().rstrip("\n").split("\n"):
    out.append(re.sub(r',"prev":"(genesis|[0-9a-f]{64})"\}$', '}', line))
open(p, "w").write("\n".join(out) + "\n")
PY
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -q "NOT ONE line carries prev"; then pass "(d) every prev stripped -> BREAK (exit 1) — the pre-0.4 hole"; else fail "(d) chain-strip not caught: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
restore

# e) delete the day file whole, leave the sidecar -> orphan BREAK, exit 1
rm -f "$F"
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -q "day file is GONE"; then pass "(e) whole day file deleted -> the orphan .head convicts it (exit 1)"; else fail "(e) whole-file deletion not caught: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
restore

# truncate the tail -> head hash mismatch, exit 1
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().rstrip("\n").split("\n")
open(p, "w").write("\n".join(lines[:-1]) + "\n")
PY
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -q "head sidecar does not match"; then pass "a truncated tail -> the head hash catches it (exit 1)"; else fail "truncation not caught: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
restore

# remove a line and RE-STITCH the chain, then repair the head HASH so the chain
# and the tail both verify. Every link agrees, the head hash agrees — the file
# is internally consistent, and only the committed line COUNT convicts it.
#
# KNOWN LIMIT, tested here on purpose: an attacker who also rewrites the count
# forges the day and this audit says INTACT. The sidecar sits on the same disk
# with the same permissions as the ledger; there is no external anchor. That is
# stated in docs/threat-model.md, not papered over.
python3 - "$F" <<'PY'
import hashlib, re, sys
p = sys.argv[1]
lines = [l for l in open(p).read().rstrip("\n").split("\n") if l]
old_count = len(lines)
del lines[2]                      # the line the attacker wants gone
prev = "genesis"
out = []
for l in lines:
    l = re.sub(r'"prev":"(genesis|[0-9a-f]{64})"', '"prev":"%s"' % prev, l)
    out.append(l)
    prev = hashlib.sha256(l.encode()).hexdigest()
open(p, "w").write("\n".join(out) + "\n")
open(p + ".head", "w").write(prev + " %d\n" % old_count)  # hash repaired, count untouched
PY
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -q "head commits"; then pass "a line removed and the chain RE-STITCHED -> the committed line count convicts it (exit 1)"; else fail "re-stitch not caught: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
restore

# strip ONE middle line's prev -> still BREAK. this is why "an unchained line in
# a chained file" does not have to be a break on its own: the chain catches it at
# the NEXT chained line, whose prev no longer matches.
python3 - "$F" <<'PY'
import re, sys
p = sys.argv[1]
lines = [l for l in open(p).read().rstrip("\n").split("\n") if l]
lines[2] = re.sub(r',"prev":"(genesis|[0-9a-f]{64})"\}$', '}', lines[2])
open(p, "w").write("\n".join(lines) + "\n")
PY
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -q "chain BROKEN at line 4"; then pass "one middle prev stripped -> the NEXT chained line convicts it (exit 1)"; else fail "single strip not caught: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
restore

# strip the LAST line's prev -> no later link to catch it, so the head hash does
python3 - "$F" <<'PY'
import re, sys
p = sys.argv[1]
lines = [l for l in open(p).read().rstrip("\n").split("\n") if l]
lines[-1] = re.sub(r',"prev":"(genesis|[0-9a-f]{64})"\}$', '}', lines[-1])
open(p, "w").write("\n".join(lines) + "\n")
PY
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -q "head sidecar does not match"; then pass "the LAST line's prev stripped -> the head hash convicts it (exit 1)"; else fail "tail strip not caught: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
restore

# a second writer that does not chain (the legacy JS gate is one, and it appends
# to the SAME day file) must not read as an attack — but its lines are not
# provable either, so the file is chain OK and the verdict is PARTIAL.
printf '{"v":1,"seq":1,"ts":%s,"run":"ng-1","pipe":"engine:session","ev":"STEP_OK","step":"legacy js writer"}\n' \
  "$(python3 -c 'import time;print(int(time.time()*1000))')" >> "$F"
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 2 ] && printf '%s' "$OUT" | grep -q "chain OK · UNPROVEN" && printf '%s' "$OUT" | grep -q "verdict: PARTIAL"; then
  pass "a non-chaining writer beside the chain -> chain OK, verdict PARTIAL (exit 2), not an accusation"
else fail "mixed-writer file: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
restore

# --replay renders the verified timeline
OUT=$("$AUDIT" --days 2 --replay)
if printf '%s' "$OUT" | grep -q "✓ .*STOP" && printf '%s' "$OUT" | grep -q "CHECK_FAIL"; then pass "--replay renders the timeline with chain marks"; else fail "--replay"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# f) a headless file with no prev on any line: a legacy writer OR an attacker who
#    stripped both halves. rabadon cannot tell them apart and says so — reported
#    UNVERIFIABLE, verdict PARTIAL, exit 2, and never INTACT.
LEGACY="$RABADON_DIR/spool/2020-01-01.jsonl"
printf '{"v":1,"seq":9,"ts":%s,"run":"js1","pipe":"legacy:session","ev":"STEP_OK","step":"x"}\n' \
  "$(python3 -c 'import time;print(int(time.time()*1000))')" > "$LEGACY"
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 2 ] && printf '%s' "$OUT" | grep -q "UNVERIFIABLE" && printf '%s' "$OUT" | grep -q "verdict: PARTIAL" && ! printf '%s' "$OUT" | grep -q "verdict: INTACT"; then
  pass "(f) a headless legacy file -> UNVERIFIABLE, verdict PARTIAL (exit 2), never INTACT"
else fail "(f) legacy file handling: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi
rm -f "$LEGACY"

# the loop binary writes into the same day file: it must chain too, or every
# `rabadon loop` run would read exactly like a stripped line.
grep -q "rbchain::append" native/loop.cpp && pass "rabadon-loop appends through the same chained writer (chain.h)" || fail "loop.cpp writes to the spool unchained"

# ---------------------------------------------------------------------------
# g) A STRANGER'S SERIALIZER. SPEC §2 fixes the ledger as single-line JSON whose
#    prev is the sha256 of the whole previous line. It fixes NO byte layout, and
#    SPEC Part II exists so someone else's agent can write this ledger. A stock
#    serializer (python json.dumps, Go encoding/json, JSON.stringify) puts a
#    space after every ':' and ','.
#
#    audit used to read fields by matching the literal bytes `"prev":"`, so it
#    answered `NOT ONE line carries prev — the chain was stripped out` /
#    TAMPER-EVIDENT BREAK over a chain that was mathematically perfect. Every
#    line carried prev. An INTACT ledger accused of being edited is the worst
#    verdict a tamper-evidence tool can return, and it is the one the byte match
#    picked.
#
#    The arm is PAIRED so it cannot pass by going blind: the same spaced file is
#    first proven INTACT with the chained COUNT asserted (a reader that sees
#    nothing reports 0 chained and fails here), then mutated and required to
#    convict at the right line. A reader that stopped parsing would fail the
#    first half; a reader that convicts everything would fail it too.
SPACED="$TMP/spaced"; mkdir -p "$SPACED/spool"
SPACED_DAY="$SPACED/spool/$LEDGER_DAY.jsonl"
python3 - "$SPACED_DAY" <<'PY'
import hashlib, json, sys, time
path = sys.argv[1]           # named by the caller: one definition of the day
prev, out = "genesis", []
for i in range(3):
    e = {"v": 1, "seq": i + 1, "ts": int(time.time() * 1000) + i,
         "run": "stranger-1", "pipe": "vendor:session", "ev": "STEP_OK",
         "step": "Bash", "prev": prev}
    line = json.dumps(e)                 # default separators: ", " and ": "
    out.append(line)
    prev = hashlib.sha256(line.encode()).hexdigest()
open(path, "w").write("\n".join(out) + "\n")
open(path + ".head", "w").write(prev + " 3\n")
PY

# the fixture must really be spaced, or the arm proves nothing about spacing
grep -q '"prev": "' "$SPACED_DAY" && pass "(g) the stranger fixture really is stock-serialized (\"prev\": \" with a space)" || fail "(g) fixture is not spaced — the arm would prove nothing"

# ...and its chain must really be valid, judged outside rabadon
if python3 - "$SPACED_DAY" <<'PY'
import hashlib, json, sys
lines = open(sys.argv[1]).read().rstrip("\n").split("\n")
prev = "genesis"
for l in lines:
    if json.loads(l).get("prev") != prev: sys.exit(1)
    prev = hashlib.sha256(l.encode()).hexdigest()
head = open(sys.argv[1] + ".head").read().split()
sys.exit(0 if head[0] == prev and int(head[1]) == len(lines) else 1)
PY
then pass "(g) that fixture's chain is valid per SPEC, verified independently of rabadon"
else fail "(g) fixture chain is not valid — fix the fixture before trusting the verdict"; fi

OUT=$(RABADON_DIR="$SPACED" "$AUDIT" --days 2); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "verdict: INTACT" && printf '%s' "$OUT" | grep -q "3 chained" && printf '%s' "$OUT" | grep -q "0 unchained"; then
  pass "(g) a stock-serialized chain audits INTACT — 3 chained, 0 unchained (exit 0)"
else fail "(g) spaced chain falsely accused: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# the negative half, on the SAME spaced file: edit one field of line 2, keeping
# it valid JSON with the same spacing. Line 3's prev no longer matches.
python3 - "$SPACED_DAY" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().rstrip("\n").split("\n")
assert '"step": "Bash"' in lines[1], lines[1]
lines[1] = lines[1].replace('"step": "Bash"', '"step": "Edit"')
open(p, "w").write("\n".join(lines) + "\n")
PY
OUT=$(RABADON_DIR="$SPACED" "$AUDIT" --days 2); RC=$?
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -q "chain BROKEN at line 3" && printf '%s' "$OUT" | grep -q "verdict: TAMPER-EVIDENT BREAK"; then
  pass "(g) one field edited in that same spaced file -> chain BROKEN at line 3 (exit 1)"
else fail "(g) spaced tamper not caught: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# h) the same stranger format through the MIGRATION path: a pre-0.4 sidecar
#    carries a hash but no count, so chain.h recounts the file before appending.
#    That recount used to require the literal suffix `,"prev":"<v>"}`, counted a
#    spaced file as 1 chained line instead of 3, committed the low count, and
#    audit convicted the file the moment the real gate touched it.
MIG="$TMP/mig"; mkdir -p "$MIG/spool"; touch "$MIG/enabled"   # enforce, like $RABADON_DIR
cp "$SPACED/spool"/*.jsonl "$MIG/spool/" 2>/dev/null
MIG_DAY="$MIG/spool/$LEDGER_DAY.jsonl"   # the file the GATE will append to
python3 - "$MIG_DAY" <<'PY'
import hashlib, sys
p = sys.argv[1]
lines = open(p).read().rstrip("\n").split("\n")
# restore the untampered 3rd line's chain so the file is clean again
import json, time
prev = "genesis"; out = []
for i, l in enumerate(lines):
    e = json.loads(l); e["prev"] = prev
    l2 = json.dumps(e); out.append(l2)
    prev = hashlib.sha256(l2.encode()).hexdigest()
open(p, "w").write("\n".join(out) + "\n")
open(p + ".head", "w").write(prev + "\n")   # pre-0.4: hash only, NO count
PY
printf '{"hook_event_name":"PreToolUse","session_id":"s-mig","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$PROJ" \
  | RABADON_DIR="$MIG" "$GATE" >/dev/null 2>&1
COMMITTED=$(awk '{print $2}' "$MIG_DAY.head")
if [ "$COMMITTED" = "5" ]; then
  pass "(h) migrating a stock-serialized spool recounts all 3 chained lines (sidecar commits 5 after the gate's 2)"
else fail "(h) migration miscounted: sidecar committed '$COMMITTED', expected 5"; sed 's/^/    | /' "$MIG_DAY.head"; fi
OUT=$(RABADON_DIR="$MIG" "$AUDIT" --days 2); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "verdict: INTACT" && printf '%s' "$OUT" | grep -q "5 chained"; then
  pass "(h) the migrated spool — stranger's 3 lines + rabadon's 2 — audits INTACT (exit 0)"
else fail "(h) migrated spool: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# and after all of it, the untouched spool still verifies
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "verdict: INTACT"; then pass "the restored spool verifies INTACT again (exit 0)"; else fail "post-restore: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# ---------------------------------------------------------------------------
# i) THE FOURTH WRITER IS THE SHIPPED PUBLIC API. chain.h opens with "the ledger
#    has ONE writer" and names three binaries (gate, repair, loop). The npm
#    package exports a fourth: package.json "exports" -> index.mjs, i.e.
#    `import { pipeline } from 'rabadon'` — the API the README and SPEC document.
#    core/bus.mjs used to appendFileSync straight into the CHAINED day file with
#    no prev, no lock and no .head. So a stranger doing exactly what the docs say
#    turned a clean ledger into one audit reports in the vocabulary of tampering,
#    and that day file can never be cleaned again: prev cannot be retro-fitted
#    without rewriting the file, which is the thing audit exists to detect.
#    This repo's own ledger already carries 1007 such lines in 2026-07-31.jsonl.
#
#    Node cannot take the flock(2) that chain.h holds (no fs binding, no flock(1)
#    on macOS), so the JS bus can never be a safe co-writer of the SAME file —
#    racing the C++ writers would forge a BREAK, a false accusation. It chains
#    its own day file with the identical protocol instead. Both halves are
#    asserted below: INTACT/exit 0, AND the events are still all there.
JSDIR="$TMP/jsapi"; mkdir -p "$JSDIR/spool"; touch "$JSDIR/enabled"
JSPROJ="$TMP/jsproj"; mkdir -p "$JSPROJ/.rabadon"
cp "$PROJ/.rabadon/guard.json" "$JSPROJ/.rabadon/guard.json"
printf '{"hook_event_name":"PreToolUse","session_id":"s-js","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$JSPROJ" \
  | RABADON_DIR="$JSDIR" "$GATE" >/dev/null 2>&1

# baseline: a fresh install with one gated action is INTACT. if this arm ever
# fails, the arm below proves nothing — it would be measuring a broken baseline.
OUT=$(RABADON_DIR="$JSDIR" "$AUDIT" --days 2); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "verdict: INTACT"; then
  pass "(i) baseline: fresh install + one gated action -> INTACT (exit 0)"
else fail "(i) baseline is not INTACT: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

RABADON_DIR="$JSDIR" node -e \
  "import('./index.mjs').then(m=>m.pipeline('js-api').step('a',async()=>'ok').bound({maxSteps:2}).run('x'))" \
  >/dev/null 2>&1
OUT=$(RABADON_DIR="$JSDIR" "$AUDIT" --days 2); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "verdict: INTACT" && ! printf '%s' "$OUT" | grep -q "verdict: PARTIAL"; then
  pass "(i) one run of the documented public JS API leaves the ledger INTACT (exit 0)"
else fail "(i) the public JS API damaged the ledger: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# POSITIVE HALF. "INTACT" alone is also satisfied by a bus that stopped emitting,
# or by writing somewhere audit never looks. Assert the run's four events are
# still on disk, still readable through the store, and carry prev — chained, not
# hidden. python3, not grep -P: BSD grep has no -P and exits 2, which a shell
# reads as "no match" and a negative assertion reads as success.
JSCOUNT=$(RABADON_DIR="$JSDIR" node -e \
  "import('./core/store.mjs').then(m=>console.log(m.readEvents({days:2}).events.filter(e=>e.pipe==='js-api').length))" 2>/dev/null)
[ "${JSCOUNT:-0}" -ge 4 ] && pass "(i) the same run's $JSCOUNT JS events are still readable through the store (replay sees them)" \
  || fail "(i) the JS events vanished: store found '${JSCOUNT:-0}', expected >= 4"

CHAINED_OK=$(RABADON_DIR="$JSDIR" python3 - "$JSDIR/spool" <<'PY'
import glob, hashlib, json, os, sys
spool = sys.argv[1]
found = unchained = 0
for f in sorted(glob.glob(os.path.join(spool, '*.jsonl'))):
    lines = [l for l in open(f).read().split('\n') if l]
    mine = [l for l in lines if json.loads(l).get('pipe') == 'js-api']
    if not mine: continue
    found += len(mine)
    unchained += sum(1 for l in mine if not json.loads(l).get('prev'))
    head = f + '.head'
    if not os.path.exists(head): print('NO-HEAD'); sys.exit(0)
    h, c = open(head).read().split()
    if h != hashlib.sha256(lines[-1].encode()).hexdigest(): print('HEAD-HASH'); sys.exit(0)
    if int(c) != sum(1 for l in lines if json.loads(l).get('prev')): print('HEAD-COUNT'); sys.exit(0)
print('OK' if found >= 4 and unchained == 0 else 'UNCHAINED=%d/%d' % (unchained, found))
PY
)
[ "$CHAINED_OK" = "OK" ] && pass "(i) every JS event carries prev and its .head sidecar commits the right hash + count" \
  || fail "(i) JS events are not chained the way chain.h chains: $CHAINED_OK"

# the negative above ("no unchained line") can only be trusted while a positive
# arm proves lines with that pipe exist at all — hence found >= 4 inside it.

# ---------------------------------------------------------------------------
# j) ONE CHAINED FILE, TWO IMPLEMENTATIONS, ONE MUTEX. chain.h (C++) and
#    core/bus.mjs (JS) both append to `<day>.jsonl`, and a chain has exactly one
#    critical section: read_head -> append -> rewrite head. flock(2) cannot be
#    the mutex across that pair — Node has no flock binding and macOS ships no
#    flock(1) to shell out to. The one atomic primitive both ends share is an
#    O_EXCL create, so the lock is the sentinel `<day>.jsonl.lock` and BOTH
#    writers take it. Without it the two read the same head, append the same
#    prev, and the second line's prev stops matching: audit convicting an honest
#    ledger of a BREAK. A false accusation is worse than the bug it reports.
DAY="$(date -u +%Y-%m-%d)"
LKDIR="$TMP/lock"; mkdir -p "$LKDIR/spool"; touch "$LKDIR/enabled"
LKPROJ="$TMP/lockproj"; mkdir -p "$LKPROJ/.rabadon"
cp "$PROJ/.rabadon/guard.json" "$LKPROJ/.rabadon/guard.json"
LKFILE="$LKDIR/spool/$DAY.jsonl"
fire_native() {   # one gated (blocked) action -> the native writer appends
  printf '{"hook_event_name":"PreToolUse","session_id":"s-lk","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$LKPROJ" \
    | RABADON_DIR="$LKDIR" "$GATE" >/dev/null 2>&1 || true
}
lines_in() { [ -f "$1" ] && grep -c . "$1" || echo 0; }

# POSITIVE HALF FIRST. The arm below asserts the native writer did NOT append;
# that assertion is satisfied for free by a writer that never appends at all.
fire_native
BEFORE=$(lines_in "$LKFILE")
[ "$BEFORE" -gt 0 ] && pass "(j) baseline: with no lock held the native writer appends $BEFORE line(s) to the day file" \
  || fail "(j) baseline: the native writer wrote nothing to $LKFILE"

# a live JS writer holds the sentinel: the native writer must stay out of the
# chained file and fail open to the sibling, exactly as it does for flock.
: > "$LKFILE.lock"
fire_native
AFTER=$(lines_in "$LKFILE")
if [ "$AFTER" = "$BEFORE" ] && [ -s "$LKDIR/spool/$DAY.unchained.jsonl" ]; then
  pass "(j) a lock held by the JS writer keeps the native writer out of the chained file"
else
  fail "(j) native ignored the cross-language lock: $BEFORE -> $AFTER line(s), sibling $([ -s "$LKDIR/spool/$DAY.unchained.jsonl" ] && echo present || echo missing)"
fi

# a lock FILE is not released by the kernel when its holder is killed, the way
# flock is. Without a stale reap one SIGKILL would push every later event of the
# day out of the chain — the fail-open turned permanent.
python3 -c "import os,sys,time; t=time.time()-60; os.utime(sys.argv[1],(t,t))" "$LKFILE.lock"
fire_native
AFTER2=$(lines_in "$LKFILE")
[ "$AFTER2" -gt "$AFTER" ] && pass "(j) a lock left by a killed writer is stolen, not obeyed forever" \
  || fail "(j) the stale lock blocked the chain forever (still $AFTER line(s))"

# EEXIST is the only refusal that means "held". An unwritable spool refuses the
# same way for the whole wait, and this lock sits in the gate's hot path on every
# single tool call: 5 invocations x 2 events x LOCK_WAIT_MS would be ~2.5s of an
# agent hanging on a dead directory. Fail open at once instead. The margin here
# is ~100x, so this measures the spin and not the machine.
RODIR="$TMP/ro"; mkdir -p "$RODIR/spool"; touch "$RODIR/enabled"
chmod 555 "$RODIR/spool"
T0=$(python3 -c 'import time;print(time.time())')
for _ in 1 2 3 4 5; do
  printf '{"hook_event_name":"PreToolUse","session_id":"s-ro","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$LKPROJ" \
    | RABADON_DIR="$RODIR" "$GATE" >/dev/null 2>&1 || true
done
ELAPSED=$(python3 -c "import time;print(int((time.time()-$T0)*1000))")
chmod 755 "$RODIR/spool"
[ "$ELAPSED" -lt 1000 ] && pass "(j) an unwritable spool fails open at once, it does not spin the wait (${ELAPSED}ms for 5 gate runs)" \
  || fail "(j) the gate stalled on a dead spool dir: ${ELAPSED}ms for 5 runs"

# ---------------------------------------------------------------------------
# k) BOTH WRITERS, ONE FILE, ONE VERDICT. The readers of this ledger look up
#    exactly one name: ui/server.mjs (the `rabadon watch` cockpit) tails
#    `<day>.jsonl`, and hooks/gate.mjs — the hook `rabadon init` installs — reads
#    it back to build handoff.md. Giving the JS bus its own second day file makes
#    every event the shipped gate records invisible to both, silently. So they
#    share the file, and audit must still return INTACT over the mixture.
MXDIR="$TMP/mixed"; mkdir -p "$MXDIR/spool"; touch "$MXDIR/enabled"
MXPROJ="$TMP/mixedproj"; mkdir -p "$MXPROJ/.rabadon"
cp "$PROJ/.rabadon/guard.json" "$MXPROJ/.rabadon/guard.json"
printf '{"hook_event_name":"PreToolUse","session_id":"s-mx","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$MXPROJ" \
  | RABADON_DIR="$MXDIR" "$GATE" >/dev/null 2>&1
RABADON_DIR="$MXDIR" node -e \
  "import('./index.mjs').then(m=>m.pipeline('mixed-api').step('a',async()=>'ok').bound({maxSteps:2}).run('x'))" \
  >/dev/null 2>&1
printf '{"hook_event_name":"PreToolUse","session_id":"s-mx2","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$MXPROJ" \
  | RABADON_DIR="$MXDIR" "$GATE" >/dev/null 2>&1

MXFILE="$MXDIR/spool/$DAY.jsonl"
if grep -q '"mixed-api"' "$MXFILE" 2>/dev/null && grep -q '"ev":"STOP"' "$MXFILE" 2>/dev/null; then
  pass "(k) the JS bus and the native gate land in the SAME day file the readers tail"
else
  fail "(k) the two writers split the day: $(ls "$MXDIR/spool" | tr '\n' ' ')"
fi
OUT=$(RABADON_DIR="$MXDIR" "$AUDIT" --days 2); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "verdict: INTACT"; then
  pass "(k) interleaved C++ and JS writes verify as one chain -> INTACT (exit 0)"
else fail "(k) the mixed-writer day file does not verify: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

echo "audit: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
