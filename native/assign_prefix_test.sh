#!/bin/bash
# assign_prefix_test.sh — a VALUE with a slash in it is still an assignment.
#
# `FOO=bar git push --force origin main` was refused. `FOO=/x git push --force
# origin main` was not. The difference is one character in the value, and the
# shell does not care about it at all: both spellings export a variable and then
# run the same git.
#
# The parser cared. is_assignment() required the whole word to be slash-free, so
# `FOO=/x` was not an assignment, command_index() stopped on it, and the rule
# engine read the command name as `x` (base_of("FOO=/x")). Not git, not rm —
# so none of the three compiled laws was ever consulted. One character of value
# text turned every law off. `env FOO=/x git ...` went the same way through the
# wrapper branch, which skips assignments with the same predicate.
#
# The name is the part that may not carry a slash: `bin/tool=v2` is a path, not
# an assignment, and `2FOO=/x` is not one either (a name cannot start with a
# digit) — a shell runs those as commands and the gate must keep reading them
# as command words. Both directions are asserted below.
#
# SAFETY (this suite must be harmless even when it FAILS):
#   - everything happens under one mktemp root; HOME points inside it and holds
#     a canary file, so `rm -rf $HOME/Documents` names the canary and nothing
#     of Damla's;
#   - the temp repo is `git init` with NO remote, so a force-push that escapes
#     has nowhere to go;
#   - the real-shell evidence runs with stub `git` and `rm` first on PATH that
#     only log their argv. That log is the proof of what would have executed;
#   - the canary is verified byte-for-byte at the end.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
SBABS="$PWD/native/rabadon-sandbox"
[ -x "$GATE" ] || { echo "assign_prefix_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

ROOT=$(mktemp -d /tmp/rabadon-assign-test.XXXXXX)
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"; mkdir -p "$HOME/.rabadon/spool" "$HOME/Documents"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
touch "$HOME/.rabadon/enabled"
CANARY="$HOME/Documents/canary.txt"
printf 'this file stands in for every file the gate exists to protect\n' > "$CANARY"
CANARY_SUM=$(shasum "$CANARY" | cut -d' ' -f1)

PROJ="$ROOT/proj"; mkdir -p "$PROJ/build"
git -C "$PROJ" init -q 2>/dev/null || mkdir -p "$PROJ/.git"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"
if [ -z "$(git -C "$PROJ" remote 2>/dev/null)" ]; then
  pass "the test repo has no remote (a force-push that escapes reaches nothing)"
else
  fail "test repo HAS a remote — refusing to run"; exit 1
fi

# stubs: they execute nothing, they only record the argv a real bash handed them
BIN="$ROOT/bin"; mkdir -p "$BIN"
for n in git rm; do
  cat > "$BIN/$n" <<EOF
#!/bin/bash
printf '%s\n' "$n \$*" >> "$ROOT/ran.log"
EOF
  chmod +x "$BIN/$n"
done

jq_str() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

gate() {
  printf '{"hook_event_name":"PreToolUse","session_id":"s-assign","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$PROJ" "$(jq_str "$1")" | "$GATE" >/dev/null 2>&1
  echo $?
}

must_block() {
  RC=$(gate "$1")
  [ "$RC" = "2" ] && pass "blocked: $1" || fail "LEAK (rc=$RC): $1"
}
must_allow() {
  RC=$(gate "$1")
  [ "$RC" = "0" ] && pass "allowed: $1" || fail "FALSE POSITIVE (rc=$RC): $1"
}

echo "assignment prefix: a slash in the VALUE must not switch the laws off"
# every must-block line below has its must-not-block twin directly under it:
# same assignment prefix, same command, work that is not the harm.
must_block 'FOO=/x git push --force origin main'
must_allow 'FOO=/x git push origin feature/x'
must_block 'env FOO=/x git push --force origin main'
must_allow 'env FOO=/x git push --force-with-lease origin main'
must_block 'GIT_DIR=/x/.git git push --force origin main'
must_allow 'GIT_DIR=/x/.git git status'
must_block 'A=/a B=/b git push -f origin main'
must_allow 'A=/a B=/b npm test'
must_block 'TMPDIR=/tmp/mine git reset --hard origin/main'
must_allow 'TMPDIR=/tmp/mine git reset --hard HEAD~1'
must_block 'FOO=/x rm -rf $HOME/Documents'
must_allow 'FOO=/x rm -rf ./build'
must_block 'LD_LIBRARY_PATH=/usr/local/lib sudo git push --force origin main'
must_allow 'LD_LIBRARY_PATH=/usr/local/lib sudo npm ci'

echo
echo "the other two spellings of an assignment prefix a shell accepts"
# `FOO+=v` appends and `arr[i]=v` sets one element, and a shell runs the command
# after either of them exactly as it runs it after `FOO=v`. Both were found by
# asking bash, not by reading the code — see the real-shell block at the bottom.
must_block 'FOO+=/x git push --force origin main'
must_allow 'FOO+=/x git push origin feature/x'
must_block 'arr[0]=/x git push --force origin main'
must_allow 'arr[0]=/x npm test'
must_block 'FOO=/x BAR+=/y git push --force origin main'
must_allow 'FOO=/x BAR+=/y npm run build'
must_block 'arr[]=/x git push --force origin main'
must_allow 'arr[]=/x echo ok'

echo
echo "and the words a shell does NOT accept as assignments stay command words"
# bash runs neither of these: `FOO+bar=/x` has a '+' inside the name and
# `arr[0=/x` never closes its subscript, so the shell looks for a command by
# that name, fails, and never reaches git. Refusing them would be refusing
# something that cannot happen.
must_allow 'FOO+bar=/x git push --force origin main'
must_allow 'arr[0=/x git push --force origin main'

echo
echo "the control twins: no slash at all, which already worked and must keep working"
must_block 'FOO=x git push --force origin main'
must_allow 'FOO=x git push origin feature/x'

echo
echo "ordinary env-prefixed work, which is most of what these prefixes are for"
must_allow 'NODE_ENV=production npm run build'
must_allow 'PATH=/usr/local/bin:$PATH make test'
must_allow 'TMPDIR=/tmp/mine rm -rf /tmp/mine/scratch'
must_allow 'CARGO_TARGET_DIR=/tmp/t cargo build --release'
must_allow 'FOO=/x echo "git push --force origin main"'

echo
echo "a word with '=' is not automatically an assignment: the NAME rules still hold"
# `2FOO=/x git ...` — a name cannot start with a digit, so a shell looks for a
# COMMAND called `2FOO=/x`, fails, and never reaches git. Blocking it would be a
# refusal of something that cannot happen; the real-shell check below proves the
# claim rather than asserting it.
must_allow '2FOO=/x git push --force origin main'
must_allow 'bin/tool=v2 --release'

echo
echo "the same parser, reached through exec (rabadon-sandbox), not the hook"
sbrun() {
  ( cd "$PROJ" && PATH="$BIN:$PATH" RABADON_DIR="$HOME/.rabadon" RABADON_NOTIFY=0 \
      "$SBABS" --dir "$PROJ" -- /bin/bash -c "$1" >/dev/null 2>&1 ); echo $?
}
: > "$ROOT/ran.log"
RC=$(sbrun 'FOO=/x git push --force origin main')
if [ "$RC" = "2" ] && ! grep -q '^git push --force' "$ROOT/ran.log" 2>/dev/null; then
  pass "exec refuses it too, and the stub git was never called"
else
  fail "exec ran it (rc=$RC), stub log: $(tr '\n' ';' < "$ROOT/ran.log")"
fi
: > "$ROOT/ran.log"
RC=$(sbrun 'FOO=/x git status')
[ "$RC" = "0" ] && pass "exec still runs the harmless twin (FOO=/x git status)" \
  || fail "exec blocked ordinary work (rc=$RC)"

echo
echo "what a real shell does with these lines (the evidence, with stubs on PATH)"
: > "$ROOT/ran.log"
PATH="$BIN:$PATH" bash -c 'FOO=/x git push --force origin main' >/dev/null 2>&1
PATH="$BIN:$PATH" bash -c "FOO=/x rm -rf $HOME/Documents" >/dev/null 2>&1
PATH="$BIN:$PATH" bash -c '2FOO=/x git push --force origin main' >/dev/null 2>&1
# the shell is the authority on which spellings are prefixes at all: three that
# are (append, array element, empty subscript) and two that are not.
PATH="$BIN:$PATH" bash -c 'FOO+=/x git push -f origin main' >/dev/null 2>&1
PATH="$BIN:$PATH" bash -c 'arr[0]=/x git push -f origin main' >/dev/null 2>&1
PATH="$BIN:$PATH" bash -c 'arr[]=/x git push -f origin main' >/dev/null 2>&1
PATH="$BIN:$PATH" bash -c 'FOO+bar=/x git push -f origin main' >/dev/null 2>&1
PATH="$BIN:$PATH" bash -c 'arr[0=/x git push -f origin main' >/dev/null 2>&1
LOG=$(cat "$ROOT/ran.log" 2>/dev/null)
printf '%s\n' "$LOG" | sed 's/^/    | /'
printf '%s' "$LOG" | grep -q '^git push --force origin main$' \
  && pass "a real bash DOES run the force-push behind FOO=/x (so the gate must judge it)" \
  || fail "the shell did not run git — the premise of this suite is wrong"
printf '%s' "$LOG" | grep -q "^rm -rf $HOME/Documents$" \
  && pass "a real bash DOES run the delete behind FOO=/x" \
  || fail "the shell did not run rm — the premise of this suite is wrong"
N=$(printf '%s' "$LOG" | grep -c '^git push -f origin main$')
[ "$N" = "3" ] \
  && pass "a real bash treats FOO+=, arr[0]= and arr[]= as prefixes and runs git behind all three" \
  || fail "expected 3 runs behind the append/array prefixes, got $N"
M=$(printf '%s' "$LOG" | grep -c '^git push')
[ "$M" = "4" ] \
  && pass "and it reaches git behind NEITHER 2FOO=/x, FOO+bar=/x nor arr[0=/x (allowing those is correct)" \
  || fail "a word that is not a valid name reached git anyway ($M git runs, expected 4)"

echo
NOW_SUM=$(shasum "$CANARY" | cut -d' ' -f1)
[ "$NOW_SUM" = "$CANARY_SUM" ] && pass "canary intact after the whole suite (judging is not running)" \
  || fail "THE CANARY WAS TOUCHED — $CANARY"

echo
echo "assign-prefix: $ok passed, $bad failed"
[ "$bad" -eq 0 ] || exit 1
