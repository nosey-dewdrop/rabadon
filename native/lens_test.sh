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

# ---------- 3. TRANSCRIPT CORPUS: lens tokens == canonical message.usage ----------
# The byte-exact claim needs transcripts shaped like the ones Claude Code writes:
# ~/.claude/projects/<slug>/<sessionId>.jsonl, many sessions, many projects, the
# junk lines a real file carries (summaries, tool results, a half-written last
# line after a crash). Those are GENERATED here, from a fixed spec — same 9 files
# on every machine and every OS — so the claim is reproducible by a stranger.
CORPUS="$TMP/home/.claude/projects"
mkdir -p "$CORPUS"
python3 - "$CORPUS" <<'PY'
import json, os, sys
d = sys.argv[1]
def J(o): return json.dumps(o, separators=(',', ':'))

# (id, project, model, [(in, out, cache_write, cache_read) per assistant turn])
SPEC = [
    ("c0de0001", "rabadon", "claude-opus-4-8",   [(1200, 300, 5000, 20000), (800, 120, 0, 30000)]),
    ("c0de0002", "rabadon", "claude-sonnet-4-5", [(400, 60, 1500, 7000)]),
    ("c0de0003", "stitchu", "claude-haiku-4-5",  [(90, 15, 0, 0), (10, 2, 0, 120)]),
    ("c0de0004", "stitchu", "claude-fable-1",    [(2500, 900, 12000, 88000)]),
    ("c0de0005", "icerik",  "claude-opus-4-8",   [(1, 1, 1, 1), (7, 3, 11, 13)]),
    ("c0de0006", "icerik",  "claude-mystery-9",  [(640, 64, 640, 6400)]),
    ("c0de0007", "rabadon", "claude-sonnet-4-5", [(333, 33, 3333, 33333), (1, 0, 0, 0)]),
    ("c0de0008", "stitchu", "claude-opus-4-8",   [(50000, 4000, 100000, 900000)]),
    ("c0de0009", "icerik",  "claude-haiku-4-5",  []),   # no billable turn at all
]

def usage(i, o, cw, cr, order="normal", trap=False):
    if order == "reversed":   # key order must not matter: the meter anchors on
        u = {"cache_read_input_tokens": cr, "cache_creation_input_tokens": cw,
             "output_tokens": o, "input_tokens": i}   # the LEADING quote of each key
    else:
        u = {"input_tokens": i, "cache_creation_input_tokens": cw,
             "cache_read_input_tokens": cr, "output_tokens": o}
    if trap:  # a nested per-iteration copy: counting it would inflate the row
        u["iterations"] = [{"input_tokens": 999999, "output_tokens": 999999,
                            "cache_creation_input_tokens": 999999,
                            "cache_read_input_tokens": 999999}]
    return u

def asst(ts, sid, cwd, model, u, ntools):
    content = [{"type": "text", "text": "ok"}]
    content += [{"type": "tool_use", "id": "t%d" % k, "name": "Bash", "input": {}} for k in range(ntools)]
    return {"type": "assistant", "timestamp": ts, "cwd": cwd, "sessionId": sid,
            "message": {"role": "assistant", "model": model, "usage": u, "content": content}}

for n, (sid8, proj, model, turns) in enumerate(SPEC):
    sid = sid8 + "-1111-2222-3333-444444444444"
    slug = "-tmp-lens-corpus-" + proj
    cwd = "/tmp/lens-corpus/" + proj
    os.makedirs(os.path.join(d, slug), exist_ok=True)
    lines = ["\n"] if n == 5 else []     # a blank line mid-file must not break parsing
    lines.append(J({"type": "summary", "summary": "onceki oturum",
                    "leafUuid": sid}) + "\n")
    lines.append(J({"type": "user", "timestamp": "2026-07-20T08:00:00.000Z", "cwd": cwd,
                    "sessionId": sid,
                    "message": {"role": "user", "content": "olcum surda mi? cok yasa"}}) + "\n")
    for k, (i, o, cw, cr) in enumerate(turns):
        ts = "2026-07-20T09:%02d:00.000Z" % (k * 7)
        u = usage(i, o, cw, cr, order="reversed" if n == 2 else "normal", trap=(n == 4))
        lines.append(J(asst(ts, sid, cwd, model, u, ntools=k + 1)) + "\n")
        if n == 0:   # a user line carrying a SUBAGENT's usage — billed to that
            lines.append(J({"type": "user", "timestamp": ts, "cwd": cwd, "sessionId": sid,
                            "toolUseResult": {"message": {"usage": {
                                "input_tokens": 888888, "output_tokens": 888888,
                                "cache_creation_input_tokens": 888888,
                                "cache_read_input_tokens": 888888}}}}) + "\n")
        if n == 1:   # ... and the same echo on an ASSISTANT line (sidechain result)
            lines.append(J({"type": "assistant", "timestamp": ts, "cwd": cwd, "sessionId": sid,
                            "toolUseResult": {"usage": {"input_tokens": 777777,
                                                        "output_tokens": 777777,
                                                        "cache_creation_input_tokens": 777777,
                                                        "cache_read_input_tokens": 777777}},
                            "message": {"role": "assistant", "content": []}}) + "\n")
    if n == 6:   # a transcript cut mid-write by a crash: the tail is not JSON.
        lines.append('{"type":"assistant","timestamp":"2026-07-20T10:00:00.00')
    with open(os.path.join(d, slug, sid + ".jsonl"), "w", encoding="utf-8") as f:
        f.write("".join(lines))
print("corpus: %d transcripts" % len(SPEC))
PY

corpus_files=$(ls "$CORPUS"/*/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
[ "$corpus_files" = "9" ] && pass "corpus: 9 generated transcripts across 3 projects" \
  || fail "corpus: expected 9 transcript files, found $corpus_files"

# Per session, lens' TOKENS column must equal python's sum over message.usage on
# assistant lines — two independent readers of the same bytes. The corpus is
# static, so unlike a live transcript there is nothing to retry: a mismatch here
# is a real disagreement, never a race.
checked=0; agreed=0
for f in "$CORPUS"/*/*.jsonl; do
  [ -f "$f" ] || continue
  id=$(basename "$f" .jsonl); id8=$(printf '%.8s' "$id")
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
  [ "$canon" = "0" ] && continue   # the no-billable-turn session, on purpose
  checked=$((checked+1))
  lens_tok=$(RABADON_LENS_DIR="$f" $NATIVE --days 100000 2>/dev/null | awk -v id="$id8" '$1==id {print $7}')
  if [ "$lens_tok" = "$canon" ]; then agreed=$((agreed+1))
  else fail "corpus $id8 — lens tokens=$lens_tok != canonical=$canon"; fi
done
[ "$checked" = "8" ] || fail "corpus: expected 8 billable sessions, checked $checked"
[ "$checked" = "8" ] && [ "$agreed" = "8" ] \
  && pass "corpus: 8/8 sessions — lens tokens == canonical message.usage (byte-exact)"

# ---------- 4. REAL transcripts: lens tokens == canonical message.usage ----------
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
