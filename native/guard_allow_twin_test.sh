#!/bin/bash
# guard_allow_twin_test.sh — a rule that refuses everything must fail lint.
#
# guard_lint_test.sh proves lint catches a rule that can never fire. This one
# proves the other direction, which is the one that broke in the field on
# 2 August 2026: rabadon authored a `semantic-commit-required` rule for a Go
# project and that rule denied EVERY commit, including the `fix:` ones it
# existed to permit. Four commands were run against it and four were refused.
# lint called the same guard "valid", because the rule compiled and it fired.
#
# The pattern below is the authored one, verbatim. Its flaw is an optional
# quantifier standing in front of a negative lookahead: `\s-m\s*` lets `\s*`
# match zero characters, so the lookahead is evaluated on the space after `-m`,
# and a space never starts with `fix`, so the lookahead is satisfied every time
# and the rule refuses the commit it was written to allow. Measured in three
# regex engines against three commands, refused in all nine — the pattern, not
# the engine.
#
# The repair is to make the separator mandatory, `\s-m\s+`. Requiring the quote
# instead does not work here and the third case below is why: the gate matches
# against a parsed surface, and that surface has the quotes stripped, so a rule
# asking for a quote character can never fire at all.
#
# The twin under every assertion here is the point of the file: a rule must be
# shown to refuse the wrong command AND to let the right one through, and until
# today only the first half had a checker.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "guard_allow_twin_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

ROOT=$(mktemp -d /tmp/rabadon-allow-twin.XXXXXX)
trap 'rm -rf "$ROOT"' EXIT

guard() { mkdir -p "$1/.rabadon"; cat > "$1/.rabadon/guard.json"; }

# 1. the real broken rule, with the commit it is supposed to permit as its twin
BROKEN="$ROOT/broken"; mkdir -p "$BROKEN"
guard "$BROKEN" <<'JSON'
{
  "project": "broken",
  "bash": [
    {
      "id": "semantic-commit-required",
      "deny": "git\\s+commit\\b[^&|;]*\\s-m\\s*[\"']?(?!(feat|fix|chore|refactor|docs|sec|test|perf|build|ci|style|revert)(\\([^)]*\\))?!?:)",
      "why": "AGENTS.md Committing: ALWAYS use semantic commits.",
      "allow": ["git commit -m \"fix: correct the off-by-one\""]
    }
  ]
}
JSON
OUT=$("$GATE" --lint "$BROKEN" 2>&1); RC=$?
if [ "$RC" != "0" ] && echo "$OUT" | grep -q "refuses its own allow example"; then
  pass "a rule that denies its own allow example fails lint"
else
  fail "lint passed a rule that refuses the work it exists to permit (rc=$RC): $OUT"
fi

# 2. the twin: the same rule with the separator made mandatory must PASS
FIXED="$ROOT/fixed"; mkdir -p "$FIXED"
guard "$FIXED" <<'JSON'
{
  "project": "fixed",
  "bash": [
    {
      "id": "semantic-commit-required",
      "deny": "git\\s+commit\\b[^&|;]*\\s-m\\s+(?!(feat|fix|chore|refactor|docs|sec|test|perf|build|ci|style|revert)(\\([^)]*\\))?!?:)",
      "why": "AGENTS.md Committing: ALWAYS use semantic commits.",
      "allow": ["git commit -m \"fix: correct the off-by-one\""]
    }
  ]
}
JSON
OUT=$("$GATE" --lint "$FIXED" 2>&1); RC=$?
if [ "$RC" = "0" ]; then
  pass "the same rule with the separator made mandatory passes lint"
else
  fail "lint rejected a repaired rule (rc=$RC): $OUT"
fi

# 3. the fixed rule must still REFUSE the command it was written for, or the
#    twin check would have been satisfied by a rule that does nothing
printf '{"hook_event_name":"PreToolUse","session_id":"twin","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git commit -m \\"wip\\""}}' "$FIXED" \
  | "$GATE" > "$ROOT/o.txt" 2> "$ROOT/e.txt"
if grep -q "semantic-commit-required" "$ROOT/o.txt" "$ROOT/e.txt"; then
  pass "the repaired rule still refuses a non-semantic commit"
else
  fail "the repaired rule refuses nothing at all — the twin proved emptiness"
fi

# 4. a guard with no allow examples is reported, not failed: nothing in the
#    wild carries them until the author writes them
BARE="$ROOT/bare"; mkdir -p "$BARE"
guard "$BARE" <<'JSON'
{
  "project": "bare",
  "bash": [
    { "id": "no-deploy", "deny": "wrangler\\s+deploy", "why": "deploys go through CI" }
  ]
}
JSON
OUT=$("$GATE" --lint "$BARE" 2>&1); RC=$?
if [ "$RC" = "0" ] && echo "$OUT" | grep -q "carry no \"allow\" example"; then
  pass "a guard with no twins is reported and still valid"
else
  fail "the missing-twin report is wrong (rc=$RC): $OUT"
fi

echo
echo "guard_allow_twin_test: $ok ok, $bad failed"
[ "$bad" = "0" ] || exit 1
