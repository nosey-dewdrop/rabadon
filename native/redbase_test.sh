#!/usr/bin/env bash
# redbase_test.sh — a failing check stops the next action, not the last one.
#
# What this replaces. The gate already knew the project had gone red: net.cpp
# forked the project's own suite, read the real exit code, wrote the verdict.
# The gate then printed one sentence, on the transition only, at PostToolUse —
# after the action had already run — and never mentioned it again. An agent
# that reads the sentence and continues is behaving correctly, because nothing
# stopped it. That is the whole of "it catches nothing": the catch existed and
# had no teeth.
#
# The property under test is not "a red is detected". It is:
#
#   1. the next action does NOT START on a red base       (PreToolUse, exit 2)
#   2. it keeps refusing, every action, while red         (not once, on the edge)
#   3. the fix path is never refused                      (read / edit / re-run)
#   4. a real pass clears it with no flag and no restart
#   5. INCONCLUSIVE never becomes red                     (the anti-wedge law)
#   6. watch mode refuses nothing                         (it promised nothing)
#
# 3 and 5 carry the product risk. A stop with no way out is a wedge, and a
# wedged session ends with rabadon uninstalled — so the arms that prove the fix
# path stays open matter more here than the arms that prove the stop works.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
[ -x "$HERE/rabadon-net" ] || { echo "build first: make native/rabadon-net"; exit 1; }
export RABADON_JUDGE=0
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

echo "red base: the next action does not start"

P="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"
mkdir -p "$P/src"
printf '{"name":"rb","scripts":{"test":"node test.js"}}' > "$P/package.json"
printf 'const a=require("./src/a.js");if(a()!==1){console.error("FAIL: a() must return 1");process.exit(1)}console.log("ok 1 - a returns 1")\n' > "$P/test.js"
printf 'module.exports = () => 1;\n' > "$P/src/a.js"

fire() { # fire <hook> <tool> <json-tool-input> -> exit code, stderr on stdout
  printf '{"hook_event_name":"%s","cwd":"%s","session_id":"s1","tool_name":"%s","tool_input":%s}' \
    "$1" "$P" "$2" "$3" | RABADON_DIR="$RD" "$GATE" 2>&1
}
code() { # same, but returns only the exit code
  printf '{"hook_event_name":"%s","cwd":"%s","session_id":"s1","tool_name":"%s","tool_input":%s}' \
    "$1" "$P" "$2" "$3" | RABADON_DIR="$RD" "$GATE" >/dev/null 2>&1; echo $?
}
settle() { # wait for the detached check to land a verdict of $1
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    grep -q "\"verdict\":\"$1\"" "$P/.rabadon/net.json" 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

# premise: the suite really passes before anything is broken. Without this the
# whole file could pass on a repo that was red for an unrelated reason.
(cd "$P" && node test.js >/dev/null 2>&1) \
  && ok "premise: the project's own suite is green to start with" \
  || bad "premise broken: the fixture suite does not pass"

# ---------- break it. The edit itself is never refused. ----------
printf 'module.exports = () => 2;\n' > "$P/src/a.js"
E=$(code PostToolUse Edit "{\"file_path\":\"$P/src/a.js\"}")
[ "$E" = "0" ] \
  && ok "the edit that breaks the code is not itself refused (rabadon is not a linter)" \
  || bad "the breaking edit was refused with $E — that is a pre-crime, not a check"
settle red \
  && ok "the project's own check ran detached and came back red" \
  || bad "no red verdict landed: $(cat "$P/.rabadon/net.json" 2>/dev/null)"

# ---------- 1. the next action does not start ----------
OUT="$(fire PreToolUse Bash '{"command":"git commit -m wip"}')"
E=$(code PreToolUse Bash '{"command":"git commit -m wip"}')
[ "$E" = "2" ] \
  && ok "the NEXT action does not start on a red base (exit 2 at PreToolUse)" \
  || bad "the next action ran anyway: exit $E"
case "$OUT" in *"red-base"*) ok "the refusal names the rule" ;; *) bad "no rule name: $OUT" ;; esac
case "$OUT" in *"npm test"*) ok "and names the check that is red, so the reason is not a mystery" ;;
                          *) bad "the refusal does not say WHICH check failed: $OUT" ;; esac
case "$OUT" in *"a() must return 1"*) ok "and carries the real failing output, not a summary of it" ;;
                          *) bad "the failing output is missing: $OUT" ;; esac

# ---------- 2. it does not go quiet after the first one ----------
A=$(code PreToolUse Bash '{"command":"npm install left-pad"}')
B=$(code PreToolUse Bash '{"command":"npm install left-pad"}')
C=$(code PreToolUse Bash '{"command":"git push"}')
[ "$A$B$C" = "222" ] \
  && ok "it refuses EVERY action while red — a red that stops complaining can be waited out" \
  || bad "the refusal decayed: $A$B$C"

# ---------- 3. the fix path is never refused ----------
[ "$(code PreToolUse Read "{\"file_path\":\"$P/src/a.js\"}")" = "0" ] \
  && ok "reading is allowed while red — you cannot fix what you may not look at" \
  || bad "Read was refused on a red base"
[ "$(code PreToolUse Grep '{"pattern":"module"}')" = "0" ] \
  && ok "searching is allowed while red" || bad "Grep was refused on a red base"
[ "$(code PreToolUse Edit "{\"file_path\":\"$P/src/a.js\"}")" = "0" ] \
  && ok "editing is allowed while red — the edit IS the fix" \
  || bad "Edit was refused on a red base: the session is wedged"
[ "$(code PreToolUse Write "{\"file_path\":\"$P/src/b.js\"}")" = "0" ] \
  && ok "writing is allowed while red" || bad "Write was refused on a red base"
[ "$(code PreToolUse Bash '{"command":"npm test --silent"}')" = "0" ] \
  && ok "re-running the check is allowed — that is the escape hatch, and it needs no flag" \
  || bad "the check itself was refused: the red can never be cleared"
# and the hatch is not spelling-sensitive. The check discovered here is
# `npm test --silent`; an agent types `npm test`. The first version of this rule
# compared whole strings and refused that, which shut the only exit from the
# inside — the exact wedge the carve-out exists to prevent.
[ "$(code PreToolUse Bash '{"command":"npm test"}')" = "0" ] \
  && ok "the check counts as the check without its flags (npm test vs npm test --silent)" \
  || bad "the escape hatch is spelling-sensitive: the session is wedged"
[ "$(code PreToolUse Bash '{"command":"cd packages/core && npm test"}')" = "0" ] \
  && ok "and still counts when it is run from a subdirectory" \
  || bad "running the check from a subdir was refused"
[ "$(code PreToolUse Bash '{"command":"npm run build"}')" = "2" ] \
  && ok "but a DIFFERENT npm command is still refused — the carve-out is the check, not the runner" \
  || bad "any command sharing the runner slipped through: the rule means nothing"

# ---------- 4. a real pass clears it ----------
printf 'module.exports = () => 1;\n' > "$P/src/a.js"
code PostToolUse Edit "{\"file_path\":\"$P/src/a.js\"}" >/dev/null
settle green \
  && ok "the fix makes the project's own check pass again" \
  || bad "still not green after the fix: $(cat "$P/.rabadon/net.json" 2>/dev/null)"
[ "$(code PreToolUse Bash '{"command":"git commit -m wip"}')" = "0" ] \
  && ok "and the refusal clears itself — no flag, no restart, no rabadon off" \
  || bad "still refusing after the check went green: the wedge is real"

# ---------- 4b. an edit made through the SHELL is caught too ----------
# The hole that made everything above half-true. The check used to start only
# after an Edit/Write tool call, so `sed -i`, a heredoc, `>` or a codegen script
# broke the project unwatched — and an agent driven by `rabadon run` has no edit
# tool at all, so for those agents supervision was zero. rabadon asks the
# filesystem now, not the tool name.
S="$(mktemp -d)"; RS="$(mktemp -d)"; : > "$RS/enabled"; mkdir -p "$S/src"
printf '{"name":"s","scripts":{"test":"node test.js"}}' > "$S/package.json"
printf 'const a=require("./src/a.js");if(a()!==1){console.error("SHELL-BREAK");process.exit(1)}console.log("ok")\n' > "$S/test.js"
printf 'module.exports = () => 1;\n' > "$S/src/a.js"
sfire() { printf '{"hook_event_name":"%s","cwd":"%s","session_id":"sh1","tool_name":"%s","tool_input":%s,"tool_response":{"stdout":"x"}}' \
    "$1" "$S" "$2" "$3" | RABADON_DIR="$RS" "$GATE" 2>&1; }
ssettle() { for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -q "\"verdict\":\"$1\"" "$S/.rabadon/net.json" 2>/dev/null && return 0; sleep 1; done; return 1; }
printf 'module.exports = () => 2;\n' > "$S/src/a.js"          # the shell edit
sfire PostToolUse Bash '{"command":"sed -i s/1/2/ src/a.js"}' >/dev/null 2>&1
ssettle red \
  && ok "a file changed by a SHELL command starts the check — no edit tool required" \
  || bad "a shell edit went unchecked: $(cat "$S/.rabadon/net.json" 2>/dev/null || echo 'no verdict at all')"
SE=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"sh1","tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' "$S" \
  | RABADON_DIR="$RS" "$GATE" >/dev/null 2>&1; echo $?)
[ "$SE" = "2" ] \
  && ok "and the break made through the shell stops the next action just the same" \
  || bad "a shell-made break did not stop anything: $SE"

# and the other direction: a command that changed NOTHING must not burn a suite
TS1="$(grep -o '"ts":[0-9]*' "$S/.rabadon/net.json")"
sfire PostToolUse Bash '{"command":"grep -r module src"}' >/dev/null 2>&1
sleep 2
TS2="$(grep -o '"ts":[0-9]*' "$S/.rabadon/net.json")"
[ "$TS1" = "$TS2" ] \
  && ok "a read-only command runs no suite — supervision does not become a CPU tax" \
  || bad "an untouched tree still triggered a check ($TS1 -> $TS2)"

# and when the tree is too big to answer, it says so instead of failing quiet
CAPOUT="$(printf '{"hook_event_name":"PostToolUse","cwd":"%s","session_id":"sh2","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"stdout":"x"}}' "$S" \
  | RABADON_DIR="$RS" RABADON_WALK_CAP=1 "$GATE" 2>&1)"
case "$CAPOUT" in *"did NOT run the check"*)
  ok "a tree too large to scan is ANNOUNCED — the miss is never silent" ;;
  *) bad "an unscannable tree failed quietly: $CAPOUT" ;;
esac
rm -rf "$S" "$RS"

# ---------- 5. INCONCLUSIVE IS NOT RED ----------
# The law that decides whether this feature is usable. A timeout, a missing
# runner, a run that executed no tests: net.cpp records all three as
# inconclusive, and if any of them read as red, a machine without pytest
# installed would refuse every action in a Python repo forever.
printf '{"ts":9999999999999,"level":3,"kind":"suite","cmd":"npm test --silent","verdict":"inconclusive","exit":-1,"dur_ms":1,"tail":"check exceeded its budget"}' \
  > "$P/.rabadon/net.json"
[ "$(code PreToolUse Bash '{"command":"git commit -m wip"}')" = "0" ] \
  && ok "an INCONCLUSIVE check refuses nothing — a timeout is not evidence of a break" \
  || bad "inconclusive was treated as red: a slow suite now wedges every session"

# ---------- 6. watch mode promised nothing, so it refuses nothing ----------
W="$(mktemp -d)"; RW="$(mktemp -d)"   # no `enabled` -> watch
mkdir -p "$W/.rabadon"
printf '{"ts":9999999999999,"level":3,"kind":"suite","cmd":"npm test","verdict":"red","exit":1,"dur_ms":1,"tail":"boom"}' \
  > "$W/.rabadon/net.json"
WE=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"w","tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' "$W" \
  | RABADON_DIR="$RW" "$GATE" >/dev/null 2>&1; echo $?)
[ "$WE" = "0" ] \
  && ok "watch mode blocks nothing, exactly as its contract said" \
  || bad "watch mode refused an action it promised not to refuse: $WE"

# ---------- 7. the user can switch it off, and is told how ----------
printf '{"ts":9999999999999,"level":3,"kind":"suite","cmd":"npm test --silent","verdict":"red","exit":1,"dur_ms":1,"tail":"boom"}' \
  > "$P/.rabadon/net.json"
[ "$(code PreToolUse Bash '{"command":"git commit -m wip"}')" = "2" ] \
  && ok "a fresh red refuses again" || bad "the fresh red did not refuse"
printf '{"project":"rb","disabled":["red-base"],"bash":[]}' > "$P/.rabadon/guard.json"
# a DISTINCT command on purpose. The first draft of this arm reused `git commit
# -m wip`, which by then had run seven times in one session, and loop-stop
# refused it — a correct refusal by a different rule, read here as "the override
# is broken". An arm that cannot tell which law stopped it is not evidence.
OVR="$(fire PreToolUse Bash '{"command":"git tag v9"}')"
[ "$(code PreToolUse Bash '{"command":"git tag v9"}')" = "0" ] \
  && ok "and disabled[\"red-base\"] really switches it off — the override line is not decoration" \
  || bad "the documented override does not work: $OVR"

rm -rf "$P" "$RD" "$W" "$RW"
echo ""
echo "red base: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
