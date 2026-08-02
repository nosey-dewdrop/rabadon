#!/bin/bash
# guard_reach_test.sh — a project's own rules have to reach the project.
#
# THE RULES A PERSON WRITES ARE THE ONES THEY CARE ABOUT, and they were the only
# layer that could be stepped out of. The gate reads the guard once, from the
# directory the session happens to be standing in:
#
#   const string guardRaw = read_file(cwd + "/.rabadon/guard.json");
#
# So a session started in $HOME, which is how an agent that works across several
# repositories runs all day, loads no guard at all. Every rule the owner wrote
# is absent — not overridden, not disabled, absent — and the line goes through
# with only the compiled-in floor underneath it. Measured on 2 August:
#
#   cwd=project  git commit -m "note: x"             refused by the project rule
#   cwd=$HOME    cd <project> && git commit -m "..." ALLOWED
#   cwd=$HOME    git -C <project> commit -m "..."    ALLOWED
#
# The baseline laws do not have this hole, because they follow the shell:
# segment_cwds() computes where each half of the line really runs, and
# git_repo_knobs() reads which repository `git -C` points at. The guard loader
# was the one thing still asking the question once, at the top, about the wrong
# directory.
#
# THE FIX IS ADDITIVE AND ONLY ADDITIVE. A guard found next to a segment can
# REFUSE that segment; it can never permit one, and its disabled[] is not read,
# so walking into a directory can never switch a law off. That direction matters
# because guard.json is a file inside a tree — the agent may write there, and
# guard-weaken governs edits to the session's own guard, not to one it wanders
# into. A reachable guard that could waive rules would be the escape hatch this
# whole file exists to close, spelled backwards.
#
# NOTHING RUNS. The gate is a judge; HOME is redirected into a mktemp lab, fake
# git shadows the real one, canaries are checked after.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rabadon-guardreach.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
export RABADON_DIR="$ROOT/home/.rabadon"
export RABADON_NOTIFY=0
mkdir -p "$HOME" "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"
echo alive > "$HOME/CANARY"

# two projects side by side, each with its OWN rule, plus one with no guard.
# the second project is what proves a reachable guard does not become a global
# one: A's rule must not fire on a line running in B.
A="$ROOT/work/alpha"; B="$ROOT/work/beta"; N="$ROOT/work/plain"
mkdir -p "$A/.rabadon" "$B/.rabadon" "$N" "$A/sub"
for d in "$A" "$B" "$N"; do git init -q "$d" 2>/dev/null; done
cat > "$A/.rabadon/guard.json" <<'J'
{ "project": "alpha",
  "bash": [ { "id": "alpha-no-note", "deny": "git\\s+commit[^|;&]*note:", "why": "alpha writes real messages" } ],
  "protectedPaths": [], "disabled": [] }
J
cat > "$B/.rabadon/guard.json" <<'J'
{ "project": "beta",
  "bash": [ { "id": "beta-no-yarn", "deny": "\\byarn\\b", "why": "beta is npm only" } ],
  "protectedPaths": [], "disabled": [] }
J
# a guard that tries to switch a compiled-in law off. walking into this
# directory must not disarm anything.
cat > "$B/.rabadon/guard.json.disarm" <<'J'
{ "project": "beta", "bash": [], "protectedPaths": [],
  "disabled": ["baseline-rm-rf-outside", "baseline-force-push"] }
J

FAKE="$ROOT/fakebin"; mkdir -p "$FAKE"; RAN="$ROOT/ran.log"; : > "$RAN"
for n in git rm yarn npm find shred; do
  printf '#!/bin/sh\necho "%s $*" >> %s\nexit 0\n' "$n" "$RAN" > "$FAKE/$n"
  chmod +x "$FAKE/$n"
done

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
jstr() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }
N_ID=0
judge() {   # $1 cwd  $2 command -> ALLOW or BLOCK:<rule>
  local err; N_ID=$((N_ID+1))
  err=$(printf '{"hook_event_name":"PreToolUse","session_id":"gr%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$N_ID" "$1" "$(jstr "$2")" | PATH="$FAKE:$PATH" "$GATE" 2>&1 >/dev/null)
  if [ $? -eq 2 ]; then echo "BLOCK:$(printf '%s' "$err" | sed -n 's/^Rule: \([^ ]*\) .*/\1/p' | head -1)"
  else echo ALLOW; fi
}
blocks() { case "$2" in "BLOCK:$3") ok "refused by $3: $1" ;;
                        BLOCK:*)    bad "refused by ${2#BLOCK:}, expected $3: $1" ;;
                        *)          bad "ALLOWED, must refuse ($3): $1" ;; esac; }
allows() { [ "$2" = ALLOW ] && ok "allowed: $1" || bad "REFUSED by ${2#BLOCK:}, must allow: $1"; }

echo "guard reach — a project's own rules have to reach the project"
echo

echo "0. the premise: the rule works when the session is standing in the project"
blocks "cwd=alpha  git commit -m 'note: x'" "$(judge "$A" "git commit -m \"note: x\"")" alpha-no-note
echo

echo "1. the session is somewhere else and the line walks into the project"
blocks "cwd=HOME   cd alpha && git commit -m 'note: x'" \
  "$(judge "$HOME" "cd $A && git commit -m \"note: x\"")" alpha-no-note
blocks "cwd=HOME   git -C alpha commit -m 'note: x'" \
  "$(judge "$HOME" "git -C $A commit -m \"note: x\"")" alpha-no-note
blocks "cwd=HOME   pushd alpha && git commit -m 'note: x'" \
  "$(judge "$HOME" "pushd $A && git commit -m \"note: x\"")" alpha-no-note
blocks "cwd=beta   cd alpha && git commit -m 'note: x'" \
  "$(judge "$B" "cd $A && git commit -m \"note: x\"")" alpha-no-note
blocks "cwd=HOME   cd alpha/sub && git commit -m 'note: x'" \
  "$(judge "$HOME" "cd $A/sub && git commit -m \"note: x\"")" alpha-no-note
blocks "cwd=alpha  cd beta && yarn add x" \
  "$(judge "$A" "cd $B && yarn add x")" beta-no-yarn
echo

echo "2. a reachable guard is not a global one"
# alpha's rule is about git commit; beta's is about yarn. neither may leak.
allows "cwd=HOME   cd beta && git commit -m 'note: x'" \
  "$(judge "$HOME" "cd $B && git commit -m \"note: x\"")"
allows "cwd=HOME   cd plain && git commit -m 'note: x'" \
  "$(judge "$HOME" "cd $N && git commit -m \"note: x\"")"
allows "cwd=alpha  yarn add x" "$(judge "$A" "yarn add x")"
allows "cwd=HOME   git commit -m 'note: x'" "$(judge "$HOME" "git commit -m \"note: x\"")"
allows "cwd=alpha  git commit -m 'a real message'" "$(judge "$A" "git commit -m \"a real message\"")"
allows "cwd=HOME   echo 'the rule is git commit note:' >> NOTES.md" \
  "$(judge "$HOME" "echo 'the rule is git commit note:' >> $HOME/NOTES.md")"
echo

echo "3. reaching a guard may refuse, never permit"
cp "$B/.rabadon/guard.json.disarm" "$B/.rabadon/guard.json"
blocks "cwd=HOME   cd beta && rm -rf /Users/nobody/elsewhere  (beta disables the law)" \
  "$(judge "$HOME" "cd $B && rm -rf /Users/nobody/elsewhere")" baseline-rm-rf-outside
# the twin, and this file asserted the wrong half of it first. A project's own
# disabled[] IS the legitimate override for a session standing in that project:
# the owner wrote it, in their own tree, on purpose. What must never happen is a
# guard REACHED mid-line disarming a law for a session that never opted into it.
# Owner overrides, visitor does not.
allows "cwd=beta   rm -rf /Users/nobody/elsewhere  (its own disabled[] is the owner's override)" \
  "$(judge "$B" "rm -rf /Users/nobody/elsewhere")"
cat > "$B/.rabadon/guard.json" <<'J'
{ "project": "beta",
  "bash": [ { "id": "beta-no-yarn", "deny": "\\byarn\\b", "why": "beta is npm only" } ],
  "protectedPaths": [], "disabled": [] }
J
echo

echo "4. judging is not running"
[ -s "$RAN" ] && { bad "something REACHED a real binary:"; sed 's/^/        /' "$RAN" | head -5; } \
              || ok "the fake binary log is empty: nothing was executed"
[ -f "$HOME/CANARY" ] && [ "$(cat "$HOME/CANARY")" = alive ] && ok "home canary intact" || bad "home canary damaged"
[ -f "$A/.rabadon/guard.json" ] && [ -f "$B/.rabadon/guard.json" ] \
  && ok "both guards still on disk, unmodified by judging" || bad "a guard file changed"

echo
echo "  pass $pass   fail $fail"
[ "$fail" -eq 0 ] && echo "  guard reach: GREEN" || echo "  guard reach: RED"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
