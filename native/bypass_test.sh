#!/bin/bash
# bypass_test.sh — two corpora, and BOTH have to hold.
#
# The 31.07 wild run put five hand-written guards in five foreign repos and then
# audited them. It found a bypass class and a false-positive class, and they
# pull in opposite directions:
#
#   MISSED   `git push origin +master` — the canonical force refspec — walked
#            past four of the five. So did `git -C /path push --force` and
#            `git --exec-path=/x push --force`: git's global options sit between
#            `git` and the subcommand, and every `git\s+push` regex reads them
#            as "not a push".
#   REFUSED  ordinary work. Four of the five blocked
#            `npm test && git push origin feature/x`, because a `-f` anywhere in
#            the line matched a `git push` anywhere else in the line.
#
# A gate that refuses ordinary work gets turned off within a day, and then it
# catches nothing at all. So the second corpus is not a nicety — it is the same
# requirement. Both run against the compiled baseline, no guard.json.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "bypass_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

TMP=$(mktemp -d /tmp/rabadon-bypass-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.rabadon/spool" "$HOME/Documents"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
touch "$HOME/.rabadon/enabled"
PROJ="$TMP/proj"; mkdir -p "$PROJ/.git" "$PROJ/build" "$PROJ/node_modules"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"

run() {
  printf '{"hook_event_name":"PreToolUse","session_id":"s-byp","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$PROJ" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}

echo "bypass: the forms that walked past hand-written guards"
while read -r cmd; do
  [ -z "$cmd" ] && continue
  RC=$(run "$cmd")
  [ "$RC" = "2" ] && pass "caught: $cmd" || fail "BYPASS ($RC): $cmd"
done <<'EOF'
git push --force origin main
git push -f origin master
git push origin +master
git push origin +refs/heads/main
git -C /any/path push --force origin master
git --exec-path=/x push --force origin main
git --git-dir=/x --work-tree=/y push -f origin main
cd /tmp && git push --force origin main
rm -rf ~/Documents
rm -rf /
git reset --hard origin/main
EOF

echo
echo "bypass: ordinary work, which must not be touched"
while read -r cmd; do
  [ -z "$cmd" ] && continue
  RC=$(run "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $cmd" || fail "FALSE POSITIVE ($RC): $cmd"
done <<'EOF'
git push origin feature/my-branch
git push --force-with-lease origin my-branch
git push --force origin my-personal-branch
npm test && git push origin feature/x
rm -rf ./build
rm -rf node_modules
git reset --hard HEAD~1
echo "git push --force origin main"
EOF

echo
echo "bypass: the same two directions, through a project's own rule"
# a rule written the way the wild guards were written, whole-line and greedy
mkdir -p "$PROJ/.rabadon"
cat > "$PROJ/.rabadon/guard.json" <<'EOF'
{ "project": "proj", "disabled": ["baseline-force-push","baseline-rm-rf-outside","baseline-hard-reset"],
  "bash": [ { "id": "no-force-push", "deny": "git\\s+push.*(--force|-f)\\b", "why": "wild-guard shape" } ] }
EOF
RC=$(run "git -C /any/path push --force origin master")
[ "$RC" = "2" ] && pass "user rule + git globals: the stripped form is matched too" || fail "user rule missed git -C form ($RC)"
RC=$(run "npm test && git push origin feature/x")
[ "$RC" = "0" ] && pass "user rule + segments: a -f in another command no longer trips it" || fail "user rule false positive ($RC)"
RC=$(run "git push --force origin main")
[ "$RC" = "2" ] && pass "user rule still refuses what it was written for" || fail "user rule regressed ($RC)"

echo
echo "bypass: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
