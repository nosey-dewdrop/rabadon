#!/bin/bash
# lens_test.sh — DIFFERENTIAL proof for native/rabadon-lens.
#
# Two kinds of proof:
#   1. FIXTURE with KNOWN usage — every printed number (in/out/cache/tokens,
#      $cost, tool calls, duration, model) is asserted exactly. The fixture also
#      plants two traps: a nested "iterations" usage copy and a "toolUseResult"
#      user line, both with huge counts that MUST be ignored — if the meter ever
#      summed them, the totals would jump and these cases would fail.
#   2. REAL transcripts — lens' per-session TOKEN total is compared BYTE-FOR-BYTE
#      against the canonical message.usage sum (python), the same invariant the
#      gate meter is proven against. This is the moat claim: the number on screen
#      is the number the runtime already wrote, no estimate.
set -u
cd "$(dirname "$0")/.."

NATIVE=./native/rabadon-lens
[ -x "$NATIVE" ] || { echo "lens_test: build first (make native/rabadon-lens)"; exit 1; }

ok=0; bad=0
TMP=$(mktemp -d /tmp/rabadon-lens-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

pass() { echo "ok    $1"; ok=$((ok+1)); }
fail() { echo "FAIL  $1"; bad=$((bad+1)); }

# assert that `grep -E pat` is present in file
has() { # <label> <file> <ere>
  if grep -Eq "$2" "$1"; then pass "$3"; else
    fail "$3 — pattern not found: $2"; echo "        --- output ---"; sed 's/^/        /' "$1"; fi
}

# ---------- 1. fixture with known usage + traps ----------
FIX="$TMP/fix"
mkdir -p "$FIX/proj-a"
python3 - "$FIX/proj-a" <<'PY'
import json, sys, os
d = sys.argv[1]
def J(o): return json.dumps(o, separators=(',', ':'))
cwd = "/tmp/lens-fixture/myproj"
# usage with a NESTED iterations copy carrying DIFFERENT numbers — the meter
# must take the top-level count only (add_field = first match after "usage":).
def usage(i, o, cw, cr):
    return {"input_tokens": i, "cache_creation_input_tokens": cw,
            "cache_read_input_tokens": cr, "output_tokens": o,
            "iterations": [{"input_tokens": 999999, "output_tokens": 999999,
                            "cache_creation_input_tokens": 999999,
                            "cache_read_input_tokens": 999999}]}
def asst(ts, model, u, ntools):
    content = [{"type": "text", "text": "hi"}]
    content += [{"type": "tool_use", "id": f"t{k}", "name": "Bash", "input": {}} for k in range(ntools)]
    return {"type": "assistant", "timestamp": ts, "cwd": cwd, "sessionId": "aaaa1111-known",
            "message": {"role": "assistant", "model": model, "usage": u, "content": content}}
lines = []
# assistant #1: in100 out10 cw1000 cr5000, 2 tool calls, opus
lines.append(asst("2026-07-28T10:00:00.000Z", "claude-opus-4-8", usage(100, 10, 1000, 5000), 2))
# TRAP: a user line whose toolUseResult embeds a subagent usage (888888) — a
# double-count would inflate the totals; the meter skips any toolUseResult line.
lines.append({"type": "user", "timestamp": "2026-07-28T10:02:30.000Z", "cwd": cwd,
              "toolUseResult": {"message": {"usage": {"input_tokens": 888888, "output_tokens": 888888,
                                                       "cache_creation_input_tokens": 888888,
                                                       "cache_read_input_tokens": 888888}}}})
# assistant #2: in200 out20 cw2000 cr6000, 1 tool call, opus
lines.append(asst("2026-07-28T10:05:00.000Z", "claude-opus-4-8", usage(200, 20, 2000, 6000), 1))
with open(os.path.join(d, "aaaa1111-known.jsonl"), "w") as f:
    f.write("\n".join(J(x) for x in lines) + "\n")

# second session, UNKNOWN model -> cost must render "?"
def asst2(ts, model, u):
    return {"type": "assistant", "timestamp": ts, "cwd": "/tmp/lens-fixture/other",
            "sessionId": "bbbb2222", "message": {"role": "assistant", "model": model,
            "usage": u, "content": [{"type": "tool_use", "id": "x", "name": "Read", "input": {}}]}}
with open(os.path.join(d, "bbbb2222-mystery.jsonl"), "w") as f:
    f.write(J(asst2("2026-07-28T09:00:00.000Z", "claude-mystery-9",
             {"input_tokens": 50, "output_tokens": 5, "cache_creation_input_tokens": 0,
              "cache_read_input_tokens": 0})) + "\n")
print("fixture written")
PY

OUT="$TMP/fix.out"; ERR="$TMP/fix.err"
# large window so the assertions never depend on the calendar date
RABADON_LENS_DIR="$FIX" $NATIVE --days 100000 >"$OUT" 2>"$ERR"
rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$ERR" ] && pass "fixture: exit 0, clean stderr" || { fail "fixture: exit=$rc / stderr:"; sed 's/^/        /' "$ERR"; }

# KNOWN session row: id aaaa1111, in=300 out=30 cache=14000 tokens=14330,
# cost $0.0265 (300*5 + 3000*5*1.25 + 11000*5*0.1 + 30*25 = 26500 /1e6),
# 3 tool calls, duration 5m00s, model opus-4-8. (traps 999999/888888 absent.)
has "$OUT" '^  aaaa1111 +myproj +opus-4-8 +300 +30 +14000 +14330 +\$0\.0265 +3 +5m00s' \
    "fixture: known session in/out/cache/tokens/\$cost/tools/dur all exact"
# the trap numbers must NOT appear anywhere
if grep -Eq '999999|888888|1099|14330[0-9]' "$OUT"; then
  fail "fixture: a trap (iterations/toolUseResult) leaked into the totals"
  sed 's/^/        /' "$OUT"
else pass "fixture: iterations + toolUseResult traps correctly ignored"; fi
# unknown model -> cost "?"
has "$OUT" '^  bbbb2222 +other +mystery-9 +50 +5 +0 +55 +\? +1 ' \
    "fixture: unknown model renders \$cost as ? (tokens still counted)"
# TOTAL line: 2 sessions, 14385 tokens, unpriced note present
has "$OUT" '^  TOTAL  2 session\(s\) · 14385 tokens · \$0\.0265\+ \(some models unpriced\) · 4 tool calls' \
    "fixture: TOTAL aggregates tokens/cost/tools + flags unpriced"

# ---------- 2. single-file mode + empty/missing sources ----------
RABADON_LENS_DIR="$FIX/proj-a/aaaa1111-known.jsonl" $NATIVE --days 100000 >"$TMP/one.out" 2>/dev/null
has "$TMP/one.out" '^  aaaa1111 +myproj +opus-4-8 +300 +30 +14000 +14330 ' \
    "single-file source: one .jsonl argument = one session"

RABADON_LENS_DIR="$TMP/does-not-exist" $NATIVE >"$TMP/miss.out" 2>"$TMP/miss.err"
rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$TMP/miss.err" ] && grep -q "no sessions" "$TMP/miss.out" \
  && pass "missing source: exit 0, clean stderr, '(no sessions...)'" \
  || fail "missing source: exit=$rc or stderr/body wrong"

# ---------- 3. REAL transcripts: lens tokens == canonical message.usage ----------
# The gate meter is proven byte-exact against the canonical sum; lens uses that
# SAME meter (usage.h), so per session the TOKENS column must equal python's sum
# over assistant lines (excluding toolUseResult). A live session appending mid
# test would make an honest diff flake, so we retry once on mismatch.
real_checked=0; real_ok=0
for f in $(ls -t "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | head -8); do
  id=$(basename "$f" .jsonl); id8=${id:0:8}
  canon=$(python3 - "$f" <<'PY'
import json, sys
tot = 0
for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
    l = l.strip()
    if not l: continue
    try: o = json.loads(l)
    except Exception: continue
    if o.get("type") == "assistant" and o.get("toolUseResult") is None:
        u = (o.get("message") or {}).get("usage") or {}
        tot += (u.get("input_tokens", 0) + u.get("output_tokens", 0)
                + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0))
print(tot)
PY
)
  [ "$canon" = "0" ] && continue   # no billable usage in this transcript, skip
  real_checked=$((real_checked+1))
  get_tok() { RABADON_LENS_DIR="$f" $NATIVE --days 100000 2>/dev/null | awk -v id="$id8" '$1==id {print $7}'; }
  lens_tok=$(get_tok)
  [ "$lens_tok" != "$canon" ] && lens_tok=$(get_tok)   # retry once (live append)
  if [ "$lens_tok" = "$canon" ]; then
    real_ok=$((real_ok+1))
  else
    fail "real transcript $id8 — lens tokens=$lens_tok != canonical=$canon"
  fi
done
if [ "$real_checked" -eq 0 ]; then
  echo "skip  real transcripts (none with billable usage under ~/.claude/projects)"
elif [ "$real_ok" -eq "$real_checked" ]; then
  pass "real transcripts: $real_ok/$real_checked sessions — lens tokens == canonical message.usage"
fi

echo
echo "lens_test: $ok ok, $bad bad"
[ "$bad" -eq 0 ] || exit 1
exit 0
