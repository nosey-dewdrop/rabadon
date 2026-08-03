#!/usr/bin/env bash
# guard_deny_twin_test.sh — `allow` proves a rule is not too WIDE. Nothing
# proved it was not too NARROW, and the schema had no way to say it.
#
# The gap is not theoretical and it is not small. On the night of 3 August every
# guard rule on this machine was driven through the real gate with a command its
# own pattern was written to refuse. 16 of 430 refused nothing, in any
# repository, ever. Three of those had been authored by the engine itself after
# real incidents, so each one named something that had already happened once and
# was free to happen again. All sixteen passed `rabadon lint` clean, because
# lint asks whether the promise COMPILES and had never asked whether it can be
# KEPT.
#
# Two mechanisms did most of it, and both are invisible in the pattern:
#
#   protectedPaths. The rule is authored the way a person names a file in their
#   own repository, `^.github/workflows/x.yml$`, and the event carries an
#   ABSOLUTE path. Measured across 865 transcripts: 12,948 Edit/Write calls
#   arrived absolute, 180 with a leading ~/, and project-relative arrived zero
#   times. Fourteen of the sixteen were that one mistake.
#
#   The pipe. A command line is split on ; && || | before any rule sees it, so a
#   pattern that spells \| is asking to see a character the matcher removed.
#
# An author cannot be expected to know either. What an author CAN write is the
# thing the rule exists to stop, in the same file, next to the rule. So every
# rule carries `catches` the way it carries `allow`, lint runs it through the
# rule's own pattern with the gate's own matcher, and a rule that cannot cut its
# own example is reported as dead at author time instead of on the night the
# danger arrives.
#
# The twins are the point, in both directions:
#   a rule that catches its example and lets its allow example through -> valid
#   a rule that cannot catch its own example                           -> DEAD
#   a rule that refuses its own allow example                          -> too wide
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   - %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL - %s\n' "$1"; }

LAB="$(mktemp -d "${TMPDIR:-/tmp}/rabadon-denytwin.XXXXXX")"
trap 'rm -rf "$LAB"' EXIT

# lint <guard-json> -> sets RC and OUT
lint() {
  local d="$LAB/p$RANDOM$RANDOM"
  mkdir -p "$d/.rabadon"
  printf '%s\n' "$1" > "$d/.rabadon/guard.json"
  OUT="$("$GATE" --lint "$d" 2>&1)"; RC=$?
  LAST_DIR="$d"
}

echo "deny twins — a rule has to prove it can still cut"
echo

# ---------------------------------------------------------------------------
# 1. the shape of the sixteen: lints clean, cuts nothing
# ---------------------------------------------------------------------------
# A rule written across a `&&`, which is how a person describes the dangerous
# thing they actually saw: go there, then delete. The pattern compiles and reads
# correctly, and the gate splits the line on `&&` before any rule is consulted,
# so no surface a rule is judged against ever contains both halves. The whole
# line is offered as an extra surface only to a pattern that names a PIPE, and
# only since 3 August -- the first draft of this case used a pipe rule and it
# passed, because that repair had already brought those rules back to life.
echo "1. a rule that cannot cut its own example is named"
lint '{ "project": "p", "bash": [
  { "id": "no-cd-then-delete",
    "deny": "cd\\s+\\S+\\s+&&\\s+rm\\s+-rf",
    "why": "walking somewhere and then deleting recursively hides the target from review",
    "allow": ["cd /tmp/build"],
    "catches": ["cd /tmp/build && rm -rf ."] } ] }'
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "no-cd-then-delete" \
   && printf '%s' "$OUT" | grep -q "cannot refuse"; then
  ok "the dead rule is named, and named as unable to refuse"
else
  bad "lint passed a rule that cannot cut its own example (rc=$RC): $OUT"
fi
# and it has to say WHICH example, or the author is told a rule is dead with no
# way to see what it failed against.
printf '%s' "$OUT" | grep -q "cd /tmp/build && rm -rf ." \
  && ok "and it quotes the example the rule failed to catch" \
  || bad "lint named the rule without quoting the example: $OUT"

echo
# ---------------------------------------------------------------------------
# 2. the twin: the same rule, written so it can fire, passes
# ---------------------------------------------------------------------------
# Same intent, spelled against a surface the matcher actually offers. A test
# that only proves rules can be rejected proves nothing about the ones that work.
echo "2. a rule that can cut its example still passes"
lint '{ "project": "p", "bash": [
  { "id": "no-force-push-main",
    "deny": "git\\s+push[^;&]*(--force|-f)\\b[^;&]*\\b(main|master)\\b",
    "why": "force-pushing a shared branch destroys history",
    "allow": ["git push origin feature-x"],
    "catches": ["git push --force origin main"] } ] }'
[ "$RC" -eq 0 ] && ok "a rule with a working twin lints clean" \
                || bad "a working rule was rejected (rc=$RC): $OUT"

echo
# ---------------------------------------------------------------------------
# 3. protectedPaths, and the spelling a real event actually carries
# ---------------------------------------------------------------------------
# The rule that killed fourteen. The author writes the path the way it appears
# in their own repository; the event carries the absolute one. Both spellings
# are offered to a rule at judging time, so both are accepted here — and the
# example is written the way the author thinks, because an author who could
# write the absolute one would not have made the mistake.
echo "3. a path rule proves itself against the spelling the event carries"
lint '{ "project": "p", "protectedPaths": [
  { "id": "workflow-frozen",
    "match": "^\\.github/workflows/release\\.yml$",
    "why": "the release workflow is the one thing that can publish",
    "allow": ["src/index.js"],
    "catches": [".github/workflows/release.yml"] } ] }'
[ "$RC" -eq 0 ] && ok "a relative example is accepted, because the gate offers the relative spelling too" \
                || bad "the relative spelling was rejected (rc=$RC): $OUT"

# and the twin that is genuinely dead: anchored at a directory that is not there
lint '{ "project": "p", "protectedPaths": [
  { "id": "workflow-frozen-typo",
    "match": "^workflows/release\\.yml$",
    "why": "the release workflow is the one thing that can publish",
    "allow": ["src/index.js"],
    "catches": [".github/workflows/release.yml"] } ] }'
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "workflow-frozen-typo" \
   && printf '%s' "$OUT" | grep -q "cannot refuse"; then
  ok "a path rule anchored at the wrong root is named as dead"
else
  bad "a path rule that protects nothing lints clean (rc=$RC): $OUT"
fi

echo
# ---------------------------------------------------------------------------
# 4. the other direction still holds
# ---------------------------------------------------------------------------
# A rule that refuses everything is as broken as one that matches nothing, and
# it is worse to live with, because it blocks real work every day while the
# other only fails on the day the danger arrives. Adding one direction must not
# cost the other.
echo "4. the allow twin is still enforced"
lint '{ "project": "p", "bash": [
  { "id": "too-wide",
    "deny": "git\\s+push",
    "why": "pushes need review",
    "allow": ["git push origin feature-x"],
    "catches": ["git push --force origin main"] } ] }'
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "allow example"; then
  ok "a rule that refuses its own allow example is still rejected"
else
  bad "the allow twin stopped being enforced (rc=$RC): $OUT"
fi

echo
# ---------------------------------------------------------------------------
# 5. a rule with no `catches` is reported, and the count is honest
# ---------------------------------------------------------------------------
# Nothing in the wild carries the key yet, so a missing twin is named rather
# than failed — the same landing the `allow` twin was given. What must not
# happen is silence: a guard where nothing proves anything, reported as valid,
# is the exact reading that let sixteen dead rules sit on this machine.
echo "5. a rule with no catches example is counted out loud"
lint '{ "project": "p", "bash": [
  { "id": "unproven",
    "deny": "git\\s+push\\s+--force",
    "why": "force pushes need review",
    "allow": ["git push origin feature-x"] } ] }'
[ "$RC" -eq 0 ] && ok "a rule with no catches example does not fail the guard yet" \
                || bad "a missing twin should be reported, not failed (rc=$RC): $OUT"
printf '%s' "$OUT" | grep -q "1 of 1" \
  && ok "and the guard says how many rules nothing proves" \
  || bad "the missing-twin count is not reported: $OUT"

echo
# ---------------------------------------------------------------------------
# 6. the rule the engine wrote for itself tonight
# ---------------------------------------------------------------------------
# `no-scripted-inplace-test-rewrite` was authored at 18:32 on 3 August from a
# misread diagnosis, and it carries neither twin. Its own pattern requires the
# filename on the command line, and every scripted rewrite in that session put
# the filename inside a heredoc, where the pattern cannot reach it. It is the
# first real customer of this check, driven here as its author wrote it.
echo "6. the engine's own newest rule, driven as written"
lint '{ "project": "p", "bash": [
  { "id": "no-scripted-inplace-test-rewrite",
    "deny": "(sed\\s+-i|perl\\s+-i|python3?[^\\n]*re\\.sub)[^\\n]*_test\\.sh",
    "why": "blind bulk regex rewrites of test scripts silently corrupt expected fixtures",
    "allow": ["bash native/session_test.sh"],
    "catches": ["python3 - <<PY"] } ] }'
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "no-scripted-inplace-test-rewrite" \
   && printf '%s' "$OUT" | grep -q "cannot refuse"; then
  ok "the rule cannot cut the shape it was written about, and lint says so"
else
  bad "a rule authored from an incident, unable to fire, lints clean (rc=$RC): $OUT"
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
