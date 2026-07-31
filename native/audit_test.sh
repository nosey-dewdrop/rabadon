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

# and after all of it, the untouched spool still verifies
OUT=$("$AUDIT" --days 2); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "verdict: INTACT"; then pass "the restored spool verifies INTACT again (exit 0)"; else fail "post-restore: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

echo "audit: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
