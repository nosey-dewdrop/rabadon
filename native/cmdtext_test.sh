#!/bin/bash
# cmdtext_test.sh — a deny rule may read what RUNS, and must still read all of it.
#
# Two halves, and the order is the point.
#
#   POSITIVES FIRST. Every "this must not be blocked" case below sits under a
#   "this must still be blocked" case for the SAME rule. The cheapest way to
#   make a false-positive suite green is to stop the rule from firing at all,
#   and that deletes the product rather than fixing it. If a negative ever
#   passes because its positive stopped blocking, the run fails.
#
#   NEGATIVES SECOND. A force-push quoted inside a commit message, a heredoc
#   body full of prose, a prompt handed to an agent: data, not commands.
#
# Two layers are checked because there are two:
#   unit  — rbtext::exec_surfaces directly (native/cmdtext.h), so an edge case
#           can be named and pinned without a repo, a guard file or a hook
#   e2e   — the real rabadon-gate binary reading a real PreToolUse event, so
#           the unit answers are not being marked by their own author
#
# NOTHING HERE IS EXECUTED. The e2e half hands each command to the gate on
# stdin and reads only its exit code; the gate is a judge. The scratch repo it
# judges against is an mktemp dir with NO REMOTE and no history, so a total
# failure of the gate still cannot reach anything: the force-pushes below have
# nowhere to go and the deletes have nothing to delete.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
# `c++`, not `clang++`. make does NOT export its builtin CXX, so under
# `make test` this variable is unset and the fallback is what actually runs —
# and on a Linux box with only g++ installed, `clang++` is a command that does
# not exist. `c++` is the standard alias and resolves to whichever compiler the
# machine has (PROJECT.md S0.2 / V1.2).
CXX="${CXX:-c++}"
FAIL=0
PASSN=0

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbcmdtext.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# ---------------------------------------------------------------------------
# unit: the surface extractor itself
# ---------------------------------------------------------------------------
cat > "$ROOT/probe.cpp" <<'CPP'
// prints one line per executable surface, with \x01 shown as ^ so a shell can
// read it. "DEGRADED <why>" when the line could not be parsed.
#include <cstdio>
#include <iostream>
#include <string>
#include "cmdtext.h"
int main() {
  std::string cmd((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
  while (!cmd.empty() && cmd[cmd.size()-1] == '\n') cmd.erase(cmd.size()-1);
  rbtext::Surfaces s = rbtext::exec_surfaces(cmd);
  if (s.degraded) { printf("DEGRADED %s\n", s.why.c_str()); return 0; }
  for (size_t i = 0; i < s.texts.size(); i++) {
    std::string t = s.texts[i];
    for (size_t k = 0; k < t.size(); k++) if (t[k] == '\x01') t[k] = '^';
    printf("%s\n", t.c_str());
  }
  return 0;
}
CPP
"$CXX" -std=c++17 -O1 -Wall -Wextra -I "$HERE" -o "$ROOT/probe" "$ROOT/probe.cpp" 2>"$ROOT/cc.log" || {
  echo "FAIL: probe did not compile"; sed -n '1,25p' "$ROOT/cc.log"; exit 1; }

# surfaces <cmd> -> the extractor's answer, newline separated
surfaces() { printf '%s' "$1" | "$ROOT/probe"; }

# u_has NAME CMD NEEDLE  — some surface must contain NEEDLE (a real command)
u_has() {
  local name="$1" cmd="$2" needle="$3" out
  out="$(surfaces "$cmd")"
  if printf '%s\n' "$out" | grep -qF -- "$needle"; then
    PASSN=$((PASSN+1)); echo "  ok   $name"
  else
    echo "  FAIL $name: no surface contains <$needle>"
    printf '%s\n' "$out" | sed 's/^/         surface: /'
    FAIL=1
  fi
}
# u_hasnt NAME CMD NEEDLE — no surface may contain NEEDLE (it was data)
u_hasnt() {
  local name="$1" cmd="$2" needle="$3" out
  out="$(surfaces "$cmd")"
  if printf '%s\n' "$out" | grep -qF -- "$needle"; then
    echo "  FAIL $name: a surface still contains <$needle>"
    printf '%s\n' "$out" | sed 's/^/         surface: /'
    FAIL=1
  else
    PASSN=$((PASSN+1)); echo "  ok   $name"
  fi
}

echo "== unit: what still counts as a command =="
u_has  "plain force-push"          'git push --force origin main' 'git push --force origin main'
u_has  "quoted operand unquoted"   'git push --force origin "main"' 'git push --force origin main'
u_has  "chained with &&"           'npm test && git push --force origin main' 'git push --force origin main'
u_has  "chained with ;"            'echo hi; git push --force origin main' 'git push --force origin main'
u_has  "chained with |"            'git push --force origin main | tee /tmp/log' 'git push --force origin main'
u_has  "subshell"                  '(cd /tmp/x && git push --force origin main)' 'git push --force origin main'
u_has  "command substitution"      'echo $(git push --force origin main)' 'git push --force origin main'
u_has  'cmdsubst inside dquotes'   'echo "$(git push --force origin main)"' 'git push --force origin main'
u_has  "backticks inside dquotes"  'echo "`git push --force origin main`"' 'git push --force origin main'
u_has  "bash -c string"            'bash -c "git push --force origin main"' 'git push --force origin main'
u_has  "sh -c string"              "sh -c 'git push --force origin main'" 'git push --force origin main'
u_has  "bash -lc cluster"          'bash -lc "git push --force origin main"' 'git push --force origin main'
u_has  "eval string"               'eval "git push --force origin main"' 'git push --force origin main'
u_has  "nested bash -c in bash -c" $'bash -c "bash -c \'git push --force origin main\'"' 'git push --force origin main'
u_has  "env wrapper"               'env FOO=1 git push --force origin main' 'git push --force origin main'
u_has  "trailing comment kept"     'git push --force origin main # cleanup' 'git push --force origin main'
u_has  "escaped quote in message"  'git commit -m "he said \"ok\"" && git push --force origin main' 'git push --force origin main'
u_has  "heredoc, command after"    $'cat <<EOF > /tmp/f\nbody\nEOF\ngit push --force origin main' 'git push --force origin main'

echo
echo "== unit: what is data =="
u_hasnt "commit -m message"        'git commit -m "close the git -C bypass: an agent wrote git push --force"' 'git push'
u_hasnt "commit -m, push after"    'git commit -m "an agent wrote git push --force origin main" && git push -q' 'git push --force'
u_hasnt "heredoc body"             $'cat >> /tmp/notes.txt <<\'EOF\'\nrun npx wrangler deploy yourself after review\nEOF' 'wrangler deploy'
u_hasnt "heredoc unquoted delim"   $'cat > /tmp/m.txt <<EOF\ngit push --force origin main\nEOF' 'git push --force'
u_hasnt "heredoc <<- tabs"         $'cat <<-END > /tmp/m\n\tgit push --force origin main\n\tEND' 'git push --force'
u_hasnt "two heredocs one line"    $'cmd <<A <<B\ngit push --force origin main\nA\nrm -rf /\nB' 'git push --force'
u_hasnt "echo single quoted"       "echo 'git push --force origin main'" 'git push --force'
u_hasnt "printf format string"     'printf %s "git push --force origin main"' 'git push --force'
u_hasnt "prompt to an agent"       'claude -p "run this: git push --force origin master" --max-turns 4' 'git push --force'
u_hasnt "python3 -c is not a shell" 'python3 -c "import os; os.system(\"x\"); cmds=[\"git push --force origin main\"]"' 'git push --force'
u_hasnt "for-loop word list"       'for c in "git push --force origin main" "git reset --hard origin/main"; do echo "$c"; done' 'git push --force'
u_hasnt "whole-line comment"       $'# git push --force origin main\nls' 'git push --force'
u_hasnt "shell var holding json"   "D='{\"command\":\"git push --force origin main\"}'; echo \"\$D\" | ./gate" 'git push --force'
u_hasnt "escaped space in message" 'git commit -m git\ push\ --force\ origin\ main' 'git push --force'

echo
echo "== unit: parse failure is declared, not guessed =="
for BAD in 'git commit -m "unterminated' $'cat <<EOF\nno terminator here' "echo 'open"; do
  OUT="$(surfaces "$BAD")"
  case "$OUT" in
    DEGRADED*) PASSN=$((PASSN+1)); echo "  ok   declared: ${OUT#DEGRADED }" ;;
    *) echo "  FAIL an unparseable line was answered as if parsed: $BAD"; FAIL=1 ;;
  esac
done
# and a degraded line must be judged the OLD way, i.e. still refused
OUT="$(printf '%s' 'git push --force origin main "unterminated' | "$ROOT/probe")"
case "$OUT" in DEGRADED*) PASSN=$((PASSN+1)); echo "  ok   degraded line falls back to whole-line matching" ;;
  *) echo "  FAIL degraded fallback not reported"; FAIL=1 ;; esac

# ---------------------------------------------------------------------------
# e2e: the real gate, on a real event
# ---------------------------------------------------------------------------
[ -x "$GATE" ] || { echo; echo "FAIL: $GATE not built (run make)"; exit 1; }

export RABADON_DIR="$ROOT/rhome"
export RABADON_NOTIFY=0
mkdir -p "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"

PROJ="$ROOT/proj"
mkdir -p "$PROJ/.rabadon"
cat > "$PROJ/.rabadon/guard.json" <<'JSON'
{
  "project": "proj0",
  "bash": [
    { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b", "why": "force-pushing a shared branch destroys history" },
    { "id": "no-hard-reset-main", "deny": "git\\s+reset\\s+--hard\\s+(origin/)?(main|master)\\b", "why": "rewrite shared state via commits, not resets" },
    { "id": "no-wrangler-deploy", "deny": "wrangler\\s+(deploy|publish)\\b", "why": "the operator deploys by hand" }
  ],
  "protectedPaths": [], "disabled": []
}
JSON

# a canary the fixture would land on if judging ever turned into running
mkdir -p "$ROOT/canary"
echo "do not lose me" > "$ROOT/canary/file.txt"

verdict() { # verdict <cmd> -> BLOCK|ALLOW
  local code
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","session_id":"cmdtext","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$PROJ" "$1" \
    | "$GATE" >/dev/null 2>&1
  code=$?
  [ "$code" = "2" ] && echo BLOCK || echo ALLOW
}

e2e() { # e2e NAME EXPECT CMD
  local name="$1" want="$2" cmd="$3" got
  got="$(verdict "$cmd")"
  if [ "$got" = "$want" ]; then PASSN=$((PASSN+1)); echo "  ok   $name -> $got"
  else echo "  FAIL $name: expected $want, gate said $got"; FAIL=1; fi
}

echo
echo "== e2e positives: the rule still fires (checked BEFORE any negative) =="
e2e "force-push to main"        BLOCK 'git push --force origin main'
e2e "force-push, -f short"      BLOCK 'git push -f origin main'
e2e "force-push, quoted branch" BLOCK 'git push --force origin "main"'
e2e "force-push via bash -c"    BLOCK 'bash -c "git push --force origin main"'
e2e "force-push via sh -c"      BLOCK "sh -c 'git push --force origin main'"
e2e "force-push via eval"       BLOCK 'eval "git push --force origin main"'
e2e "force-push in a subshell"  BLOCK '(cd '"$PROJ"' && git push --force origin main)'
e2e "force-push after &&"       BLOCK 'npm test && git push --force origin main'
e2e "hard reset to main"        BLOCK 'git reset --hard origin/main'
e2e "hard reset via bash -c"    BLOCK 'bash -c "git reset --hard origin/main"'
e2e "wrangler deploy"           BLOCK 'npx wrangler deploy'
e2e "wrangler deploy after cd"  BLOCK 'cd '"$PROJ"' && npx wrangler deploy'

echo
echo "== e2e negatives: the same text, carried as data =="
e2e "commit message"            ALLOW 'git commit -m "close the git -C bypass: an agent wrote git push --force origin main"'
e2e "commit message then push"  ALLOW 'git add -A && git commit -q -m "an agent wrote git push --force origin main" && git push -q'
e2e "heredoc body (deploy)"     ALLOW "$(printf 'cat >> /tmp/notes.txt <<%s\n## shipping\nthe deploy step is manual: run npx wrangler deploy yourself\nEOF' "'EOF'")"
e2e "heredoc body (force-push)" ALLOW "$(printf 'cat > /tmp/msg.txt <<MSGEOF\nthe gate refuses git push --force origin main before it rewrites history\nMSGEOF')"
e2e "heredoc body (reset)"      ALLOW "$(printf 'cat > /tmp/msg.txt <<MSGEOF\nand it refuses git reset --hard origin/main too\nMSGEOF')"
e2e "prompt to an agent"        ALLOW 'claude -p "Run exactly this and show the output: git push --force origin master" --max-turns 4'
e2e "python -c list of strings" ALLOW 'python3 -c "cmds=[\"git push --force origin main\"]; print(len(cmds))"'
e2e "echo of a gate fixture"    ALLOW "echo '{\"command\":\"git push --force origin main\"}' | ./rabadon-gate"
e2e "for-loop word list"        ALLOW 'for c in "git push --force origin main" "git reset --hard origin/main"; do echo "$c"; done'
e2e "comment only"              ALLOW "$(printf '# git push --force origin main\nls -la')"
e2e "deploy word in a message"  ALLOW 'git commit -m "document that npx wrangler deploy stays manual"'

echo
echo "== e2e: an unparseable line is judged the old way, and refused =="
e2e "degraded still refuses"    BLOCK 'git push --force origin main "unterminated'
DEG=$(grep -l PARSE_DEGRADED "$RABADON_DIR"/spool/*.jsonl 2>/dev/null | head -1)
if [ -n "$DEG" ]; then PASSN=$((PASSN+1)); echo "  ok   the degraded parse is in the ledger, not silent"
else echo "  FAIL degraded parse left no PARSE_DEGRADED line in the ledger"; FAIL=1; fi

# ---- judging is not running -------------------------------------------------
[ "$(cat "$ROOT/canary/file.txt" 2>/dev/null)" = "do not lose me" ] || { echo "FAIL: canary changed"; FAIL=1; }
echo "  ok   canary intact (judging is not running)"

echo
if [ "$FAIL" = "0" ]; then echo "PASS ($PASSN checks)"; else echo "FAILED"; fi
exit $FAIL
