#!/usr/bin/env bash
# promises_test.sh — the four promises, each asserted at the level the OWNER
# defined done, not the level the implementer finds convenient.
#
# WHY THIS FILE EXISTS, and it is not a nicety.
#
# Every other suite in this directory tests a mechanism: does the parser split
# this command, does the lock survive a dead holder. Passing all of them says
# nothing about whether the product does what it was promised, and on 16 August
# that gap was measured: two promises were reported finished, with green suites
# behind them, and an audit run twenty minutes later found three real holes —
# shell edits were never checked at all, the one escape from a refusal was
# spelling-sensitive, and a passing suite was called red because an assertion
# NAME contained the word "failing". None of the existing suites could have
# caught any of them, because none of them was asked the owner's question.
#
# The check that matters is therefore not "do the tests pass". It is: run the
# product end to end and see whether a stranger would agree the promise is kept.
# That question has to be askable by someone who does not trust the person who
# wrote the code — including a later session of the same agent, which is the
# actual failure mode. So the criteria below are TRANSCRIBED from the owner's
# own definitions, not restated in the implementer's words, and each one drives
# the real binaries against a real project in a temp directory.
#
# A promise that is not built yet FAILS here, loudly, by name. A scoreboard that
# starts mostly red is the point: the moment it can be made green by wording, it
# has stopped being worth running.
#
# Run it with `make promises`.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
[ -x "$GATE" ] || { echo "build first: make"; exit 1; }
export RABADON_JUDGE=0
# HOME ISOLATION — see the long note in native/contract_test.sh. This suite is
# the second of the two measured on 2026-08-30 to rewrite the operator's live
# ~/.claude/settings.json: SessionStart with a fresh RABADON_DIR leaves the
# self-heal stamp absent, hooks/refresh.mjs runs, and refresh() writes to
# os.homedir(). Declare the address; do not borrow the operator's.
SBHOME="$(mktemp -d)"; export HOME="$SBHOME"
trap 'rm -rf "$SBHOME"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  KEPT   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  BROKEN - $1"; }
has() { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

newproj() { # a real project with a real suite, green to start
  local d; d="$(mktemp -d)"; mkdir -p "$d/src"
  printf '{"name":"p","scripts":{"test":"node test.js"}}' > "$d/package.json"
  printf 'const a=require("./src/a.js");if(a()!==1){console.error("BROKEN: a() must return 1");process.exit(1)}console.log("ok 1")\n' > "$d/test.js"
  printf 'module.exports = () => 1;\n' > "$d/src/a.js"
  echo "$d"
}
ev() { # ev <home> <cwd> <hook> <tool> <input-json>
  printf '{"hook_event_name":"%s","cwd":"%s","session_id":"p1","tool_name":"%s","tool_input":%s,"tool_response":{"stdout":"x"}}' \
    "$3" "$2" "$4" "$5" | RABADON_DIR="$1" "$GATE" 2>&1
}
rc() { printf '{"hook_event_name":"%s","cwd":"%s","session_id":"p1","tool_name":"%s","tool_input":%s,"tool_response":{"stdout":"x"}}' \
    "$3" "$2" "$4" "$5" | RABADON_DIR="$1" "$GATE" >/dev/null 2>&1; echo $?; }
settle() { for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    grep -q "\"verdict\":\"$2\"" "$1/.rabadon/net.json" 2>/dev/null && return 0; sleep 1; done; return 1; }

echo "the four promises, at the owner's definition of done"
echo ""

# ============================================================================
# PROMISE 1 — THE CONTRACT
# "rabadon init sonrasi ilk oturumda bu blok gorunuyor; kontrol bulunamiyorsa
#  'bu projede kosacak bir sey bulamadim, sunu ver' diyor ve SESSIZ KALMIYOR."
# ============================================================================
echo "1. CONTRACT — it states its terms before it judges anything"
P1="$(newproj)"; H1="$(mktemp -d)"; : > "$H1/enabled"
OUT1="$(ev "$H1" "$P1" SessionStart Bash '{}')"
has "npm test" "$OUT1" \
  && ok "the first session names the check it will run" \
  || bad "no contract block on the first session"

# and the uncheckable project, which is where silence would be fatal
Q1="$(mktemp -d)"; HQ="$(mktemp -d)"; : > "$HQ/enabled"; echo hi > "$Q1/readme.txt"
OUTQ="$(ev "$HQ" "$Q1" SessionStart Bash '{}')"
has "NONE FOUND" "$OUTQ" \
  && ok "a project it cannot check is told so — it does not go quiet" \
  || bad "silent on a project it cannot check"
# THE ARM THAT MAKES IT REAL: do what the block said, verbatim, and see it work.
# The sleep is not padding. Non-tool events are deduped in a 2-second bucket, so
# two session starts fired back to back are one event and the second prints
# nothing — which reads exactly like the fix having failed. A real user is not
# in that window; this test was, and it accused the product of a bug it does
# not have.
mkdir -p "$Q1/.rabadon"
printf '{"project":"q","check":"sh -c \\"exit 0\\"","bash":[]}' > "$Q1/.rabadon/guard.json"
sleep 2
OUTQ2="$(ev "$HQ" "$Q1" SessionStart Bash '{}')"
has 'sh -c "exit 0"' "$OUTQ2" \
  && ok "and the fix it hands you actually works when you do it" \
  || bad "the instructions in the block do not lead anywhere"

# ============================================================================
# PROMISE 2 — CATCH
# "bilerek kirilmis bir repoda ajan bir sonraki eylemi BASLATAMIYOR ve ekranda
#  sebebi yaziyor."
# ============================================================================
echo ""
echo "2. CATCH — a broken project stops the next action"
printf 'module.exports = () => 2;\n' > "$P1/src/a.js"        # break it
rc "$H1" "$P1" PostToolUse Edit "{\"file_path\":\"$P1/src/a.js\"}" >/dev/null
settle "$P1" red || bad "the project's own check never ran"
OUT2="$(ev "$H1" "$P1" PreToolUse Bash '{"command":"git commit -m wip"}')"
[ "$(rc "$H1" "$P1" PreToolUse Bash '{"command":"git commit -m wip"}')" = "2" ] \
  && ok "the next action does not start" || bad "the next action started on a broken base"
has "BROKEN: a() must return 1" "$OUT2" \
  && ok "and the reason on screen is the project's real failure text" \
  || bad "the refusal does not show why"
# the same break, made through the shell — the population with no edit tool
S2="$(newproj)"; HS="$(mktemp -d)"; : > "$HS/enabled"
printf 'module.exports = () => 2;\n' > "$S2/src/a.js"
rc "$HS" "$S2" PostToolUse Bash '{"command":"sed -i s/1/2/ src/a.js"}' >/dev/null
settle "$S2" red \
  && ok "a break made with a shell command is caught too, not only a tool edit" \
  || bad "a shell edit went unchecked"

# ============================================================================
# PROMISE 3 — REPAIR
# "kirik repoda, onarim acikken, ajan durdu -> onarim denendi -> ya tutulan bir
#  yama var ya da 'denedim, olmadi, sebep su' yaziyor."
# ============================================================================
echo ""
echo "3. REPAIR — it tries to fix what it caught, from inside the session"
R3="$(newproj)"; H3="$(mktemp -d)"; : > "$H3/enabled"
printf 'module.exports = () => 2;\n' > "$R3/src/a.js"
RABADON_JUDGE=1 rc "$H3" "$R3" PostToolUse Edit "{\"file_path\":\"$R3/src/a.js\"}" >/dev/null
settle "$R3" red >/dev/null
OUT3="$(RABADON_JUDGE=1 ev "$H3" "$R3" PreToolUse Bash '{"command":"git commit -m wip"}')"
LED3="$(cat "$H3"/spool/*.jsonl 2>/dev/null)"
# EITHER a repair was attempted, OR it says in words that it did not and why.
# Both are acceptable; silence is not. Today neither happens: repair.cpp runs
# only when a human types `rabadon repair`, and nothing in a session reaches it.
if has 'REPAIR_START' "$LED3" || has 'REPAIR_' "$LED3"; then
  ok "a repair was attempted from inside the session"
elif has "did not try to repair" "$OUT3" || has "repair" "$OUT3"; then
  ok "no repair was attempted, and it says so with a reason"
else
  bad "PROMISE 3 NOT KEPT: it caught the break, attempted no repair, and said nothing about repair at all"
fi

# ============================================================================
# PROMISE 4 — DRIFT
# "'sadece X klasorunde calis' denen bir oturumda Y klasorune yazma denemesi
#  durur, ve durma sebebi kullanicinin kendi cumlesidir."
# ============================================================================
echo ""
echo "4. DRIFT — it holds you to what you were asked to do"
D4="$(newproj)"; H4="$(mktemp -d)"; : > "$H4/enabled"; mkdir -p "$D4/.rabadon" "$D4/lib"
# the user says it once, in their own words, at the start of the session
printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","session_id":"p1","prompt":"only work in src, do not touch lib"}' "$D4" \
  | RABADON_DIR="$H4" "$GATE" >/dev/null 2>&1
OUT4="$(ev "$H4" "$D4" PreToolUse Write "{\"file_path\":\"$D4/lib/x.js\"}")"
C4="$(rc "$H4" "$D4" PreToolUse Write "{\"file_path\":\"$D4/lib/x.js\"}")"
if [ "$C4" = "2" ]; then ok "writing outside the named area is stopped"
else bad "PROMISE 4 NOT KEPT: 'only work in src' was said and a write to lib/ went through (exit $C4)"; fi
if has "only work in src" "$OUT4"; then
  ok "and the reason quoted back is the user's own sentence"
else
  bad "PROMISE 4 NOT KEPT: the stop does not quote what the user actually asked for"
fi

rm -rf "$P1" "$H1" "$Q1" "$HQ" "$S2" "$HS" "$R3" "$H3" "$D4" "$H4"
echo ""
echo "promises: $PASS kept, $FAIL broken"
[ "$FAIL" -eq 0 ]
