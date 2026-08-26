#!/bin/bash
# heredoc_prose_test.sh — a rule that spells a PIPE may read the whole line, and
# the whole line is not the whole EVENT.
#
# THE MEASURED INCIDENT. The shipped gate refused this, in this repo, on a
# legitimate documentation write:
#
#   Rule: no-exit-code-after-pipe
#   command matched deny rule: cat >> reports/kosu/SAPMA-KARARLARI.md <<'MARKER' ...
#
# The forbidden shape was not in the command. It was in the PROSE inside the
# heredoc — a paragraph describing the mistake the rule exists to prevent. The
# operator was writing down what rabadon caught, and rabadon refused the writing
# down. That is a WRONG_REFUSAL, and a guard that cannot be written about is a
# guard nobody documents.
#
# WHY THE PIPE RULES ARE THE EXCEPTION. cmdtext.h already lifts heredoc bodies
# out of every per-segment surface, which is why `cat <<EOF` + a prose
# force-push has been allowed since that header existed (native/cmdtext_test.sh
# pins it). But rules.h hands ONE extra surface to rules whose pattern spells a
# pipe, because no segment can ever contain a `|` — and that extra surface was
# the RAW line, heredoc body and all. One surface out of ten had not been told.
#
# THE ORDER IS THE POINT, same law as cmdtext_test.sh: every "must still be
# refused" case is checked BEFORE its "must not be refused" twin. The cheapest
# way to make a false-positive suite green is to stop the rule firing at all,
# and that deletes the product instead of fixing it.
#
# HERMETIC: its own mktemp RABADON_DIR and project, its own guard.json holding
# VERBATIM COPIES of the two incident-authored rules. Nothing is executed — each
# command is handed to the gate on stdin and only its exit code is read. Needs
# git and a shell; no node, no python3, no jq.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
FAIL=0
PASSN=0

[ -x "$GATE" ] || {
  echo "  FAIL BLOCKED: $GATE is not built, so no refusal can be measured against anything; run: (cd $HERE/.. && make all)"
  echo "FAILED"; exit 1; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbheredoc.XXXXXX")" || exit 1
trap 'rm -rf "$ROOT"' EXIT

export RABADON_DIR="$ROOT/rhome"
export RABADON_NOTIFY=0
mkdir -p "$RABADON_DIR/spool"
printf 'enforce\n' > "$RABADON_DIR/mode"

PROJ="$ROOT/proj"
mkdir -p "$PROJ/.rabadon" "$PROJ/reports/kosu"
# The two rules below are copied byte for byte from the machine baseline that
# produced the incident. They are not paraphrased: a paraphrase would let the
# fix be "the test's regex was different", which is not a fix.
cat > "$PROJ/.rabadon/guard.json" <<'JSON'
{
  "project": "heredocprose",
  "bash": [
    {
      "id": "no-exit-code-after-pipe",
      "deny": "\\|\\s*(tail|head|grep|sed|awk)\\b[^\\n]*\\n?\\s*echo\\s+[\"']?exit=\\$\\?",
      "why": "`echo exit=$?` after a pipe reports the last pipe stage's status, not the command under test, so a RED suite reads as exit=0.",
      "authoredBy": "incident"
    },
    {
      "id": "no-gnu-timeout-on-macos",
      "deny": "(^|[;&|]\\s*)timeout\\s+\\d",
      "why": "macOS has no `timeout` binary; the command dies before the real work runs.",
      "authoredBy": "incident"
    }
  ],
  "protectedPaths": [], "disabled": []
}
JSON

# a canary the fixture would land on if judging ever turned into running
mkdir -p "$ROOT/canary"
echo "do not lose me" > "$ROOT/canary/file.txt"

# JSON string escaping without a JSON library: backslash, quote, then newlines.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk 'BEGIN{ORS=""} NR>1{printf "\\n"} {print}'
}

verdict() { # verdict <cmd> -> BLOCK|ALLOW
  _esc=$(json_escape "$1")
  printf '{"hook_event_name":"PreToolUse","session_id":"heredocprose","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' \
    "$PROJ" "$_esc" | "$GATE" >/dev/null 2>&1
  _code=$?
  [ "$_code" = "2" ] && echo BLOCK || echo ALLOW
}

t() { # t NAME EXPECT CMD
  _name="$1"; _want="$2"; _cmd="$3"
  _got="$(verdict "$_cmd")"
  if [ "$_got" = "$_want" ]; then PASSN=$((PASSN+1)); echo "  ok   $_name -> $_got"
  else echo "  FAIL $_name: expected $_want, gate said $_got"; FAIL=1; fi
}

echo "heredoc prose: a rule that spells a pipe reads commands, not documents"
echo
echo "== positives: the two rules still fire on REAL commands =="
t "exit code after | tail"        BLOCK "$(printf 'make test 2>&1 | tail -5\necho exit=$?')"
t "exit code after | grep"        BLOCK "$(printf 'make test | grep -c ok\necho "exit=$?"')"
t "exit code on one line"         BLOCK 'make test | head -3 ; echo exit=$?'
t "exit code after a real cat"    BLOCK "$(printf 'cat out.txt | awk "{print}"\necho exit=$?')"
t "gnu timeout at line start"     BLOCK 'timeout 5 make test'
t "gnu timeout after &&"          BLOCK 'make all && timeout 30 ./native/rabadon-gate'

echo
echo "== negatives: the same shapes, sitting inside a document being written =="
# the measured incident, reproduced: a report file describing the very rule.
C6=$(printf 'cat >> reports/kosu/SAPMA-KARARLARI.md <<%s\n### C6 — the counter\nthe operator must not write `make test | grep -c ok\necho exit=$?` in a shell,\nbecause the pipe hides the real exit code and rabadon refuses it.\nMARKER' "'MARKER'")
t "the measured C6 write"         ALLOW "$C6"
t "heredoc prose, | tail form"    ALLOW "$(printf 'cat > notes.md <<%s\nnever do: make test | tail -5\necho exit=$?\nEOF' "'EOF'")"
t "heredoc prose, unquoted delim" ALLOW "$(printf 'cat > notes.md <<EOF\nnever do: ls | sed -n 1p\necho exit=$?\nEOF')"
t "heredoc prose, gnu timeout"    ALLOW "$(printf 'cat > notes.md <<%s\non macOS timeout 5 make test dies before the work runs\nEOF' "'EOF'")"
# the same rule, in the one prose shape that DOES reach its pattern: the timeout
# rule spells `[;&|]`, so it is handed the raw line too, and a `;` in the prose
# is all it takes. This is the (d) half of the acceptance — the family, not the
# single rule.
t "heredoc prose, timeout after ;" ALLOW "$(printf 'cat > notes.md <<%s\nwrong: cd build ; timeout 5 make test\nEOF' "'EOF'")"
t "two heredocs, prose in both"   ALLOW "$(printf 'cmd <<A <<B\nmake test | head -1\necho exit=$?\nA\ntimeout 9 sleep 1\nB')"

echo
echo "== the exception stays an exception: real pipes still reach the rule =="
# The fix must not turn "ignore heredoc bodies" into "ignore the line". A pipe
# on the COMMAND is still on the surface the rule reads, even when the same
# command also carries a heredoc.
t "heredoc AND a real violation"  BLOCK "$(printf 'cat > notes.md <<%s\njust prose\nEOF\nmake test | tail -2\necho exit=$?' "'EOF'")"

echo
[ "$(cat "$ROOT/canary/file.txt" 2>/dev/null)" = "do not lose me" ] \
  || { echo "  FAIL canary changed — judging turned into running"; FAIL=1; }
PASSN=$((PASSN+1)); echo "  ok   canary intact (judging is not running)"

echo
if [ "$FAIL" = "0" ]; then echo "PASS ($PASSN checks)"; else echo "FAILED"; fi
exit $FAIL
