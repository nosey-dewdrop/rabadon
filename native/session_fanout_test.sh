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
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
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

# and the aging is by CLOCK, not by arrival. A record that has been quiet for
# longer than the ttl goes; a record from a session that is still working stays,
# however many newer sessions turn up beside it. Driven through the real gate so
# it is the shipped sweep being measured and not a re-implementation of it.
AGED="$T/aged"
mkdir -p "$AGED/.git" "$AGED/.rabadon"
cp "$PROJ/.rabadon/promise.json" "$AGED/.rabadon/promise.json"
aged_edit() {
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' \
    "$1" "$AGED" "$AGED/native/x.c" | "$GATE" >/dev/null 2>&1
}
aged_edit "old-one"
aged_edit "still-here"
OLDF=$(ls "$AGED/.rabadon/sessions"/*.json 2>/dev/null | head -1)
if [ -z "$OLDF" ]; then
  bad "aging is not by time: there is no per-session store to age"
else
  # two days back, past the 24h ttl, and the sweep marker cleared so the
  # ten-minute throttle does not swallow the one sweep this assertion needs.
  touch -t "$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)" "$OLDF"
  rm -f "$AGED/.rabadon/sessions/.swept"
  aged_edit "newcomer"
  if [ ! -f "$OLDF" ] && [ "$(ls "$AGED/.rabadon/sessions"/*.json 2>/dev/null | wc -l | tr -d ' ')" -ge 2 ]; then
    ok "a record quiet for two days was swept and the live ones were not"
  else
    bad "aging is not by time: $(ls "$AGED/.rabadon/sessions" 2>/dev/null | tr '\n' ' ')"
  fi
fi

echo
# ---------------------------------------------------------------------------
# 4. a red one session watched is not a red another session inherits
# ---------------------------------------------------------------------------
# The second half of the same incident, one layer up from the sessions map.
# lastTestFail and lastTestPass were top-level, so a red stamped at 02:18 by one
# session sat there while lastTestPass stayed at 00:48, and a session opened
# hours later was told "tests are RED" with its own suite green in front of it.
# It happened twice and both are on the ledger as `rabadon wrong
# stale-net-verdict`.
#
# `test-tamper` is the probe because it is the rule that acts on that verdict:
# suite red plus an edit that puts a skip marker into a test file. If the red
# leaks, a session that has never run a test refuses an edit on somebody else's
# evidence.
echo "4. one session's red is not another session's red"
LEAK="$T/leak"
mkdir -p "$LEAK/.git" "$LEAK/.rabadon" "$LEAK/test"
cat > "$LEAK/.rabadon/guard.json" <<'JSON'
{ "project": "leak",
  "testCommand": "run-the-suite",
  "testPaths": ["test/"],
  "bash": [], "protectedPaths": [], "disabled": [] }
JSON

# session R watches its own suite go red
printf '{"hook_event_name":"PostToolUse","session_id":"sess-R","cwd":"%s","tool_name":"Bash","tool_input":{"command":"run-the-suite"},"tool_response":"FAILED: 3 failed, 7 passed"}' \
  "$LEAK" | "$GATE" >/dev/null 2>&1

tamper_as() {  # tamper_as <session> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s/test/a_test.js","old_string":"it(\\"x\\", () => { expect(1).toBe(1) })","new_string":"it.skip(\\"x\\", () => { expect(1).toBe(1) })"}}' \
    "$1" "$LEAK" "$LEAK" | "$GATE" >"$T/out" 2>"$T/err"
  echo $?
}

rc=$(tamper_as "sess-R")
if [ "$rc" -ne 0 ] && grep -q "test-tamper" "$T/err"; then
  ok "the session that saw the red is still held to it"
else
  bad "the session that watched its own suite go red was not held to it (exit $rc)"
fi

rc=$(tamper_as "sess-Q")
if [ "$rc" -eq 0 ]; then
  ok "a session that has run nothing does not inherit that red"
else
  bad "sess-Q inherited sess-R's red — refused by $(grep -o 'Rule: [a-z-]*' "$T/err" | head -1)"
fi

echo
# ---------------------------------------------------------------------------
# 5. the push gate, measured across two sessions
# ---------------------------------------------------------------------------
# The question the split has to answer out loud: does one agent's green release
# another agent's push? For a green rabadon RAN and read the exit code of, YES,
# and deliberately — that is a fact about the tree, and re-running a suite that
# was verified thirty seconds ago on an untouched tree is a tax, not a check.
# What makes it safe is that lastCodeEdit is shared too, so ANY session touching
# the tree puts the tree past the last verified run and the next push re-runs.
# Both directions are asserted; one without the other is half an answer.
echo "5. a verified green crosses sessions, and any edit ends it"
PG="$T/pg"
mkdir -p "$PG/.git" "$PG/.rabadon" "$PG/src"
RUNS="$PG/.suite-runs"
: > "$RUNS"
cat > "$PG/.rabadon/guard.json" <<JSON
{ "project": "pg",
  "pushGate": { "run": "echo x >> $RUNS; echo '12 passed, 0 failed'; exit 0",
                "why": "tests must be green before push", "timeoutSec": 30 },
  "bash": [], "protectedPaths": [], "disabled": [] }
JSON

edit_code() {  # edit_code <session>
  printf '{"hook_event_name":"PostToolUse","session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s/src/main.c","old_string":"a","new_string":"b"},"tool_response":"ok"}' \
    "$1" "$PG" "$PG" | "$GATE" >/dev/null 2>&1
}
push_as() {    # push_as <session> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push origin feature-x"}}' \
    "$1" "$PG" | "$GATE" >"$T/out" 2>"$T/err"
  echo $?
}
runs() { wc -l < "$RUNS" | tr -d ' '; }

edit_code "sess-V"
rc=$(push_as "sess-V")
if [ "$rc" -eq 0 ] && [ "$(runs)" = "1" ]; then
  ok "the session that edited the tree had its suite run before the push"
else
  bad "push gate did not run the suite for the editing session (exit $rc, runs $(runs))"
fi

rc=$(push_as "sess-W")
if [ "$rc" -eq 0 ] && [ "$(runs)" = "1" ]; then
  ok "a second session pushing an untouched tree rides the verified green"
else
  bad "the verified green did not cross sessions (exit $rc, runs $(runs))"
fi

edit_code "sess-W"
rc=$(push_as "sess-V")
if [ "$(runs)" = "2" ]; then
  ok "one session's edit put the tree past the green and the suite ran again"
else
  bad "an edit by another session did not invalidate the verified green (runs $(runs))"
fi

echo
# ---------------------------------------------------------------------------
# 6. two session ids that begin the same are two sessions
# ---------------------------------------------------------------------------
# The record used to be keyed on the first 16 characters of the session id. For
# the harness's own uuids that collides with nobody, measured rather than
# assumed. But the id is whatever the caller puts in the event, it is now also a
# FILENAME, and a collision here is not a wrong answer — it is two sessions
# sharing one counter, which is the failure this whole file is about.
#
# Its own project, and only two sessions in it, so the only thing that can move
# a counter here is the prefix. Run inside $PROJ it would share a tree with the
# 25 sessions above and the eviction from section 1 would be measured a second
# time under a different name.
echo "6. a shared 16-character prefix is not a shared session"
PFX="$T/pfx"
mkdir -p "$PFX/.git" "$PFX/.rabadon" "$PFX/docs"
cp "$PROJ/.rabadon/promise.json" "$PFX/.rabadon/promise.json"
edit_pfx() {
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' \
    "$1" "$PFX" "$2" | "$GATE" >"$T/out" 2>"$T/err"
  echo $?
}
P1="aaaaaaaaaaaaaaaa-one"
P2="aaaaaaaaaaaaaaaa-two"
# six edits, three each. Neither id has reached five, so under a correct key
# nothing fires; sharing one key makes the sixth the combined sixth and the
# challenge lands inside this loop.
EARLY=0
for i in 1 2 3; do [ "$(edit_pfx "$P1" "$PFX/docs/x1$i.md")" -eq 0 ] || EARLY=1; done
for i in 1 2 3; do [ "$(edit_pfx "$P2" "$PFX/docs/x2$i.md")" -eq 0 ] || EARLY=1; done
rc=$(edit_pfx "$P1" "$PFX/docs/x14.md")
if [ "$rc" -eq 0 ] && [ "$EARLY" -eq 0 ]; then
  ok "seven edits across two ids sharing a prefix challenged neither"
else
  bad "the two ids shared one counter — the combined fifth edit was challenged"
fi
rc=$(edit_pfx "$P1" "$PFX/docs/x15.md")
if [ "$rc" -ne 0 ] && grep -q "promise-off-target" "$T/err"; then
  ok "and each id still reaches its own fifth"
else
  bad "the first id never reached its own fifth edit (exit $rc)"
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
