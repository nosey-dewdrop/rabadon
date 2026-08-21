#!/usr/bin/env bash
# ledger_day_test.sh — ONE definition of "today's ledger file", proven.
#
# The chained day file is named by a date, and until this suite ran, the repo
# held two answers to the question "which date". gate.cpp, repair.cpp,
# sandbox.cpp and the JS bus all name it in UTC (gmtime / toISOString), while
# pipeline.cpp and drift.cpp named it in LOCAL time (localtime_r). East of Greenwich
# after midnight -- the hours this project is actually written in -- those are
# two different files, so:
#
#   * the loop's own comment ("the loop writes into the same day file as the
#     gate, so it chains through the same writer") was false for three hours a
#     night: two files, two chains, one session split across them;
#   * `rabadon drift` READS today's spool for the session's own commands and
#     feeds them to the north-star vocabulary check. Reading the local-dated
#     file while the gate writes the UTC-dated one means the evidence is simply
#     missing, and a session whose commands are on-target scores as if it had
#     run no commands at all;
#   * the drift event drift itself writes lands in a file the readers of "today"
#     are not looking at.
#
# The bug is not "a bug that happens after midnight". It is local-vs-UTC date
# DIVERGENCE, and divergence is reachable at any hour of any day from some zone:
# at 10:00 UTC or later a +14 zone is already on tomorrow, before 10:00 UTC a
# -12 zone is still on yesterday. This suite picks the zone off the clock and
# asserts the divergence it depends on, so it is red at 15:00 exactly as it is
# red at 00:48, and it can never quietly become a test that proves nothing.
#
# Each "must land in the same file" check has its must-NOT twin: run the same
# three binaries under UTC, where no divergence exists, and nothing may move --
# same single file, same name, still the real UTC date. A "fix" that renamed the
# day file to something else, or that merged the files by breaking the naming,
# fails that half.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
GATE=./native/rabadon-gate
LOOP=./native/rabadon-pipeline
DRIFT=./native/rabadon-drift
AUDIT=./native/rabadon-audit
for b in "$GATE" "$LOOP" "$DRIFT" "$AUDIT"; do
  [ -x "$b" ] || { echo "ledger-day: build first (make)"; exit 1; }
done

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

echo "ledger day: one file, one name"

# ---------------------------------------------------------------------------
# isolation. Everything this suite writes lives under one temp root: HOME is
# redirected into it (so a binary that falls back to ~/.rabadon cannot reach the
# real one) and a canary file sits in that fake HOME, checked at the end. The
# scratch project is a git repo with NO REMOTE, and the only destructive string
# in this file is gate INPUT -- text the gate judges and never executes.
# ---------------------------------------------------------------------------
ROOT=$(mktemp -d /tmp/rabadon-ledger-day.XXXXXX)
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"; mkdir -p "$HOME"
CANARY="$HOME/canary.txt"; printf 'canary\n' > "$CANARY"
export RABADON_NOTIFY=0
unset RABADON_DIR

# ---- the divergent zone, chosen from the clock so the arm works at ANY hour --
UTC_DAY="$(date -u +%Y-%m-%d)"
UH=$((10#$(date -u +%H)))                      # base 10 explicitly: "08" is not octal here
if [ "$UH" -ge 10 ]; then Z="Etc/GMT-14"; else Z="Etc/GMT+12"; fi   # POSIX sign: GMT-14 is UTC+14
LOC_DAY="$(TZ="$Z" date +%Y-%m-%d)"
if [ "$LOC_DAY" != "$UTC_DAY" ]; then
  ok "premise: under TZ=$Z the local date is $LOC_DAY while UTC is $UTC_DAY (divergence is real)"
else
  bad "premise: TZ=$Z did not diverge from UTC at ${UH}:00 -- the whole suite would prove nothing"
fi

# ---- fixtures ---------------------------------------------------------------
guard_at() {   # $1 = project dir
  mkdir -p "$1/.rabadon"
  cat > "$1/.rabadon/guard.json" <<'EOF'
{ "project": "proj", "bash": [
  { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b", "why": "test rule" }
] }
EOF
}
scratch_proj() {   # a git repo with no remote
  d="$ROOT/$1"; mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && mkdir -p native && printf 'x\n' > native/seed.c && git add -A && git commit -qm seed ) >/dev/null 2>&1
  guard_at "$d"
  printf '%s' "$d"
}
fire_gate() {   # $1 = project, $2 = RABADON_DIR, $3 = TZ. one denied command, judged not run.
  printf '{"hook_event_name":"PreToolUse","session_id":"s-day","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$1" \
    | TZ="$3" RABADON_DIR="$2" "$GATE" >/dev/null 2>&1
  return 0
}
run_loop() {   # $1 = project, $2 = RABADON_DIR, $3 = TZ. stub proposer, `do` is true(1).
  printf 'console.log(42)\n' > "$1/mod.js"
  printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf "console.log(42)\\n" > mod.js\n' > "$1/prop.sh"
  chmod +x "$1/prop.sh"
  cat > "$1/plan.json" <<'EOF'
{ "steps": [ { "id":"s1","kind":"cmd","do":"true",
    "contract":[ {"type":"differential","run":"node mod.js","expect":"42"} ] } ],
  "accept":[ {"type":"differential","run":"node mod.js","expect":"42"} ] }
EOF
  TZ="$3" RABADON_DIR="$2" RABADON_PROPOSER="bash $1/prop.sh" "$LOOP" "$1" "$1/plan.json" >/dev/null 2>&1
  return 0
}
promise_at() {   # north star whose vocabulary lives ONLY in the spool, not in the tree
  cat > "$1/.rabadon/promise.json" <<'EOF'
{ "north_star": "native core only",
  "areas": ["^native/"], "anti_paths": ["\\.mjs$"],
  "keywords": ["bash"], "off_keywords": ["landing"] }
EOF
}
days_in() { ls "$1/spool" 2>/dev/null | grep '\.jsonl$' | sort | tr '\n' ' ' | sed 's/ $//'; }

# ===========================================================================
# 1) THE WRITERS. gate and loop, same RABADON_DIR, under the divergent zone.
# ===========================================================================
RD1="$ROOT/rd1"; mkdir -p "$RD1/spool"; touch "$RD1/enabled"
P1="$(scratch_proj proj1)"
fire_gate "$P1" "$RD1" "$Z"
GOT="$(days_in "$RD1")"
[ "$GOT" = "$UTC_DAY.jsonl" ] \
  && ok "the gate names its day file in UTC ($UTC_DAY.jsonl), not local ($LOC_DAY.jsonl)" \
  || bad "gate day file is '$GOT', expected $UTC_DAY.jsonl"

run_loop "$P1" "$RD1" "$Z"
GOT="$(days_in "$RD1")"
[ "$GOT" = "$UTC_DAY.jsonl" ] \
  && ok "the loop joins the gate in ONE day file -- the spool holds exactly $GOT" \
  || bad "one session split across day files: spool holds '$GOT'"

grep -q '"ev":"RUN_DONE"' "$RD1/spool/$UTC_DAY.jsonl" 2>/dev/null \
  && ok "the loop's own events are IN the file the gate chained (RUN_DONE present)" \
  || bad "the loop's RUN_DONE is not in $UTC_DAY.jsonl -- it went to another file"

# the file two binaries appended to is still one valid chain, judged by audit
OUT="$(RABADON_DIR="$RD1" "$AUDIT" --days 2 2>&1)"; RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "verdict: INTACT"; then
  ok "gate + loop interleaved in that one file audits INTACT (exit 0)"
else
  bad "merged day file does not audit clean: rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/    | /'
fi

# ===========================================================================
# 2) THE DRIFT WRITER, and the drift READER. Separate spool: drift appends an
#    unchained line (a known, separate defect), so it is kept out of the audit
#    arm above on purpose -- this arm asks only WHICH FILE it lands in.
# ===========================================================================
RD2="$ROOT/rd2"; mkdir -p "$RD2/spool"; touch "$RD2/enabled"
P2="$(scratch_proj proj2)"; promise_at "$P2"
fire_gate "$P2" "$RD2" "$Z"
mkdir -p "$P2/web"; printf 'export const x=1\n' > "$P2/web/feature.mjs"
DOUT="$(TZ="$Z" RABADON_DIR="$RD2" "$DRIFT" "$P2" 2>&1)"; DRC=$?

grep -q '"check":"goal-drift"' "$RD2/spool/$UTC_DAY.jsonl" 2>/dev/null \
  && ok "the drift event lands in the same day file the gate writes ($UTC_DAY.jsonl)" \
  || bad "drift wrote its goal-drift event outside the gate's day file (spool: $(days_in "$RD2"))"

GOT="$(days_in "$RD2")"
[ "$GOT" = "$UTC_DAY.jsonl" ] \
  && ok "gate + drift leave ONE day file behind, not two" \
  || bad "gate + drift left '$GOT'"

# the reader half: the promise's only keyword is "bash", which appears nowhere
# in the changed files or the goal -- it exists solely as the `step` of the
# event the gate wrote to today's spool. Finding it proves drift opened the file
# the gate actually wrote.
if printf '%s' "$DOUT" | grep -q "north-star vocabulary: 1/1 present"; then
  ok "drift READS the session evidence the gate wrote (vocabulary 1/1, from the spool)"
else
  bad "drift missed the gate's own session events -- $(printf '%s' "$DOUT" | grep -o 'north-star vocabulary: [^)]*)*' | head -1)"
fi
[ $DRC -eq 3 ] && ok "and the verdict still fires: off-target session -> DRIFT (exit 3)" \
               || bad "drift verdict changed: expected exit 3, got $DRC"

# ===========================================================================
# 3) THE TWIN: under UTC nothing diverges, so nothing may move. This half fails
#    for any "fix" that renames the day file, shifts it off UTC, or merges the
#    two files by breaking the name the readers already tail.
# ===========================================================================
RD3="$ROOT/rd3"; mkdir -p "$RD3/spool"; touch "$RD3/enabled"
P3="$(scratch_proj proj3)"; promise_at "$P3"
fire_gate "$P3" "$RD3" "UTC"
run_loop "$P3" "$RD3" "UTC"
mkdir -p "$P3/web"; printf 'export const x=1\n' > "$P3/web/feature.mjs"
TZ=UTC RABADON_DIR="$RD3" "$DRIFT" "$P3" >/dev/null 2>&1
GOT="$(days_in "$RD3")"
[ "$GOT" = "$UTC_DAY.jsonl" ] \
  && ok "twin: under TZ=UTC all three binaries still share the one file, unchanged" \
  || bad "twin: TZ=UTC spool holds '$GOT'"
[ "$GOT" = "$(date -u +%Y-%m-%d).jsonl" ] \
  && ok "twin: that name is the real UTC date the store and trace readers tail" \
  || bad "twin: the day file drifted off the UTC date"

# ---- isolation held ---------------------------------------------------------
[ "$(cat "$CANARY" 2>/dev/null)" = "canary" ] \
  && ok "isolation: the canary in the redirected HOME is untouched" \
  || bad "isolation: something wrote through the fake HOME"

echo ""
echo "ledger day: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
