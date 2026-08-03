#!/bin/bash
# session_fanout_test.sh — the session model has to survive a fan-out.
#
# Every per-session guarantee in the gate lives in <project>/.rabadon/state.json
# (gate.cpp: stt.path = cwd + "/.rabadon/state.json", so it is PER PROJECT and not
# machine-wide -- worth stating because it was first diagnosed against the wrong
# file). It holds: the
# drift challenge that is documented to fire ONCE per session, the recent-event
# list that stops one hook event being judged twice, the repeated-command
# counter, the set of directories a session has touched. One file, no lock
# between writers, and the loader keeps only the LAST FOUR sessions:
#
#   if (sessions.size() > 4) sessions.erase(sessions.begin(), sessions.end() - 4);
#
# On 3 August seven sessions ran at once, one main and six agents. The main
# session's record was evicted, so `promise-off-target` — whose own refusal text
# says "fires once per session" — fired three times, and its driftChallenged flag
# could not survive long enough to mean anything.
#
# That is not a corner case. Fanning out across agents is what this tool is FOR.
# The supervisor of a fan-out cannot be a thing that degrades once the fan-out is
# wider than four, and it cannot degrade SILENTLY, which is what a cap plus
# last-writer-wins does.
#
# Two properties are asserted here and neither is about a specific rule:
#   a session's state survives other sessions arriving, however many arrive;
#   two sessions writing at the same time do not lose each other's writes.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
[ -x "$GATE" ] || { echo "  build first: make native/rabadon-gate"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

T="$(cd "$HERE/.." && pwd)/.fanouttest-$$"
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT

PROJ="$T/proj"
mkdir -p "$PROJ/.git" "$PROJ/.rabadon" "$T/rd/spool"
export RABADON_DIR="$T/rd"
# ENFORCE. In watch mode block() records the verdict and exits 0, so a fixture
# without this measures nothing and reads as green. The premise of a fixture is
# the first thing to check.
: > "$RABADON_DIR/enabled"

cat > "$PROJ/.rabadon/promise.json" <<'JSON'
{
  "north_star": "the engine gets faster and stays provable",
  "areas": ["^native/"],
  "anti_paths": [],
  "keywords": ["native"],
  "off_keywords": []
}
JSON

# one Edit through the real gate, as session $1, on file $2
edit_as() {
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' \
    "$1" "$PROJ" "$2" | "$GATE" >"$T/out" 2>"$T/err"
  echo $?
}

echo "session fan-out — the supervisor of a fan-out cannot break at four"
echo

# ---------------------------------------------------------------------------
# 1. a session's own state survives other sessions arriving
# ---------------------------------------------------------------------------
# `promise-off-target` counts off-target edits per session and challenges once.
# Session A is walked up to the edge of its challenge. Then six other sessions
# each do a little work. Then A continues. A's count must be A's count.
echo "1. one session's count is not another session's business"
for i in 1 2 3 4; do edit_as "sess-A" "$PROJ/docs/a$i.md" >/dev/null; done

# six other sessions arrive, which is a fan-out, which is the normal case
for s in B C D E F G; do
  edit_as "sess-$s" "$PROJ/docs/$s.md" >/dev/null
done

# A's fifth off-target edit. Its own counter says this is the fifth.
rc=$(edit_as "sess-A" "$PROJ/docs/a5.md")
if [ "$rc" -ne 0 ] && grep -q "promise-off-target" "$T/err"; then
  ok "session A was challenged on its own fifth edit, after six others arrived"
else
  bad "session A's count did not survive six other sessions (exit $rc)"
  python3 - "$PROJ/.rabadon/state.json" <<'PY' 2>/dev/null || true
import json,sys
d=json.load(open(sys.argv[1]))
s=d.get("sessions",{})
print("        sessions kept: %d -> %s" % (len(s), list(s)[:8]))
for k,v in list(s.items())[:8]:
    print("          %-10s offTarget=%s driftChallenged=%s" % (k, v.get("offTarget"), v.get("driftChallenged")))
PY
fi

# and the challenge really is once: A's sixth must pass
rc=$(edit_as "sess-A" "$PROJ/docs/a6.md")
if [ "$rc" -eq 0 ]; then ok "the challenge fired once and let the session past"
else bad "the challenge fired again — it is a wall, not a challenge"; fi

# even after six MORE sessions turn up
for s in H I J K L M; do edit_as "sess-$s" "$PROJ/docs/$s.md" >/dev/null; done
rc=$(edit_as "sess-A" "$PROJ/docs/a7.md")
if [ "$rc" -eq 0 ]; then ok "and it stays fired after twelve other sessions have been seen"
else bad "the challenge came back once A's record was evicted"; fi

echo
# ---------------------------------------------------------------------------
# 2. concurrent writers do not lose each other
# ---------------------------------------------------------------------------
# The failure this catches is silent: two sessions read the same state, both
# write it, and the second write erases the first session's record entirely.
echo "2. sessions writing at the same time do not erase each other"
for s in $(seq 1 12); do
  ( edit_as "par-$s" "$PROJ/docs/p$s.md" >/dev/null ) &
done
wait

KEPT=$(python3 - "$PROJ" <<'PY'
import json, os, sys, glob
rd = sys.argv[1]
names = set()
sp = os.path.join(rd, ".rabadon", "state.json")
if os.path.exists(sp):
    try:
        names |= set(json.load(open(sp)).get("sessions", {}))
    except Exception:
        pass
for f in glob.glob(os.path.join(rd, ".rabadon", "sessions", "*.json")):
    names.add(os.path.basename(f)[:-5])
print(len([n for n in names if n.startswith("par-")]))
PY
)
if [ "$KEPT" = "12" ]; then ok "all twelve concurrent sessions kept their record"
else bad "only $KEPT of 12 concurrent sessions survived — writes were lost"; fi

echo
# ---------------------------------------------------------------------------
# 3. whatever the storage is, it stays bounded
# ---------------------------------------------------------------------------
# Removing a cap is not a fix if it turns into unbounded growth on a machine that
# runs this all day. Old sessions have to age out; the rule is that they age out
# by TIME rather than by being pushed out by whoever is newest.
echo "3. it does not grow without bound"
BYTES=$(python3 - "$PROJ" <<'PY'
import os, sys, glob
rd = sys.argv[1]
n = 0
sp = os.path.join(rd, ".rabadon", "state.json")
if os.path.exists(sp): n += os.path.getsize(sp)
for f in glob.glob(os.path.join(rd, ".rabadon", "sessions", "*.json")): n += os.path.getsize(f)
print(n)
PY
)
if [ "$BYTES" -lt 400000 ]; then ok "state is $BYTES bytes after 25 sessions"
else bad "state grew to $BYTES bytes after 25 sessions"; fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
