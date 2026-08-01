#!/bin/bash
# script_wrapper_test.sh — a session recorder is a wrapper, and it eats a FILE.
#
# command_index() answers the one question every layer depends on: which word is
# the command? It skips the shell's own syntax, `FOO=bar` prefixes, and then a
# LIST of wrappers — sudo, env, nohup, timeout, xargs, nice, stdbuf. `script`
# was not on that list, so:
#
#     script -q /dev/null git push --force origin main
#
# reported its command name as `script`, which is neither git nor rm, so the
# segment was marked irrelevant and the three compiled laws were never asked.
# Exit 0, no ledger line, nothing to see — on the fresh-install path with no
# guard.json, the path baseline.h exists for.
#
# script(1) is not a logger that wraps a shell it cannot reach: `script [-aeFkqr]
# [-t time] [file [command ...]]` runs the command itself, with the typescript
# FILE standing between the options and the argv. That file operand is the whole
# reason a name-only entry would not have been enough — the same mistake
# `timeout 5 git ...` made, where `5` was read as the command. So the entry
# declares what it eats, exactly like the others: `-t` takes a separate value,
# every other option is a boolean, and ONE plain operand (the typescript file)
# comes before the command.
#
# THE FIRST SECTION EXECUTES A REAL script(1), ON PURPOSE, so this is a
# measurement and not a story about a parser. script(1) needs a terminal —
# without one it dies with "tcgetattr/ioctl: Operation not supported on socket"
# and proves nothing — so the premise runs under a pty from python3's stdlib.
# It runs with a FAKE `git` and a FAKE `rm` first on PATH that record their argv
# and do nothing else, inside one mktemp lab whose repo has no remote and no
# history, with $HOME pointed inside that lab and a canary in it. If the fakes
# were somehow not found, the real git would have no remote to push to and the
# real rm would only see paths this test made seconds earlier.
#
# EVERY OTHER SECTION EXECUTES NOTHING: each command is handed to rabadon-gate
# on stdin as a PreToolUse event and only its exit code is read. The canaries at
# the bottom are the proof.
#
# The sharpest line in the file is on the ALLOW list, not the block list:
#
#     script git push --force origin main
#
# runs nothing at all. `git` is the typescript FILE (section 1 measures it: the
# fake git is never called and a file named `git` appears in the lab), and
# `push` is the command, which does not exist. A fix that skipped the wrapper
# NAME and stopped there would land on `git` and refuse a line whose only effect
# is a junk file — a block bought with a false refusal. The operand count is
# what keeps those two apart, in both directions.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "script_wrapper_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

LAB=$(mktemp -d /tmp/rabadon-script-test.XXXXXX)
trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"; mkdir -p "$HOME/.rabadon/spool" "$HOME/Documents"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
touch "$RABADON_DIR/enabled"                  # enforce
CANARY="$HOME/Documents/keep.txt"
echo "do not lose me" > "$CANARY"
# no guard.json anywhere: the three compiled laws, judged alone — the
# fresh-install path, which is the only path this escape was ever live on
PROJ="$LAB/proj"; mkdir -p "$PROJ/.git" "$PROJ/build" "$PROJ/node_modules"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"

run() { # run <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"s-script","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> what the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-script","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}

# ---------------------------------------------------------------------------
# 1. the recorder is not decoration: it really hands the argv over
# ---------------------------------------------------------------------------
echo "script(1): what the recorder actually runs (fake git, fake rm, under a pty, nothing pushed or deleted)"
mkdir -p "$LAB/fakebin" "$LAB/sandbox"
echo "do not lose me either" > "$LAB/sandbox/keep.txt"
for name in git rm; do
  cat > "$LAB/fakebin/$name" <<FAKE
#!/bin/sh
# records what a real $name would have been given, and does nothing else
printf '$name' >> "$LAB/argv.log"
for a in "\$@"; do printf ' [%s]' "\$a" >> "$LAB/argv.log"; done
printf '\n' >> "$LAB/argv.log"
exit 0
FAKE
  chmod +x "$LAB/fakebin/$name"
done

# script(1) refuses to run when stdin is not a terminal, and a test harness has
# no terminal. python3's pty.spawn gives it one; if that is not available here
# the premise is unmeasurable and says so instead of pretending.
PTY_OK=0
: > "$LAB/argv.log"
( cd "$LAB/sandbox" && python3 -c 'import pty,sys;pty.spawn(["/bin/sh","-c",sys.argv[1]])' \
    'script -q /dev/null /bin/echo RAN-script' ) 2>/dev/null | grep -q 'RAN-script' && PTY_OK=1
rm -f "$LAB/sandbox/typescript"

ran() { # ran <label> <command> <expected argv line>
  : > "$LAB/argv.log"
  ( cd "$LAB/sandbox" && env PATH="$LAB/fakebin:$PATH" \
      python3 -c 'import pty,sys;pty.spawn(["/bin/sh","-c",sys.argv[1]])' "$2" ) >/dev/null 2>&1
  if grep -qxF "$3" "$LAB/argv.log" 2>/dev/null; then
    pass "the recorder runs it: $1"
  else
    fail "the recorder did NOT run it ($1): log=[$(tr '\n' ';' < "$LAB/argv.log")]"
  fi
}
notran() { # notran <label> <command>
  : > "$LAB/argv.log"
  ( cd "$LAB/sandbox" && env PATH="$LAB/fakebin:$PATH" \
      python3 -c 'import pty,sys;pty.spawn(["/bin/sh","-c",sys.argv[1]])' "$2" ) >/dev/null 2>&1
  if [ ! -s "$LAB/argv.log" ]; then
    pass "the recorder runs nothing here: $1"
  else
    fail "something ran ($1): log=[$(tr '\n' ';' < "$LAB/argv.log")]"
  fi
}

if [ "$PTY_OK" = "1" ]; then
  PUSHARGV='git [push] [--force] [origin] [main]'
  ran "a quiet recording"            'script -q /dev/null git push --force origin main'      "$PUSHARGV"
  ran "no options at all"            'script /dev/null git push --force origin main'         "$PUSHARGV"
  ran "a flush interval, separate"   'script -q -t 0 /dev/null git push --force origin main' "$PUSHARGV"
  ran "a cluster ending in -t"       'script -qt 0 /dev/null git push --force origin main'   "$PUSHARGV"
  ran "a cluster of booleans"        'script -qk /dev/null git push --force origin main'     "$PUSHARGV"
  ran "an appended recording deletes" 'script -aq /dev/null rm -rf /etc/nginx'               'rm [-rf] [/etc/nginx]'
  # the operand is a FILE, and this is the line that proves it
  notran "the file operand eats the first word" 'script git push --force origin main'
  [ -f "$LAB/sandbox/git" ] \
    && pass "it wrote a typescript FILE named git instead of running git" \
    || fail "no file named git: the first operand was not read as the typescript file"
  [ -f "$LAB/sandbox/keep.txt" ] && pass "the fakes ran instead of the real git and rm: nothing was pushed or deleted" \
    || fail "a real rm ran in the lab"
else
  echo "  skip - no usable pty here, so script(1) cannot be measured on this machine"
fi
rm -f "$LAB/sandbox/git" "$LAB/sandbox/typescript"

# ---------------------------------------------------------------------------
# 2. must BLOCK: the law judges the command the recorder is about to run
# ---------------------------------------------------------------------------
echo "script(1): refused (the escape, in every spelling that carries it)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused: $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
the reported escape|script -q /dev/null git push --force origin main
a recording with no options|script /dev/null git push --force origin main
a recording into a real file|script session.log git push --force origin main
the short force spelling|script -q /dev/null git push -f origin main
a flush interval given separately|script -t 0 /dev/null git push --force origin main
a flush interval after other options|script -q -t 0 /dev/null git push --force origin main
a cluster whose last flag takes the value|script -qt 0 /dev/null git push --force origin main
a cluster of booleans|script -qk /dev/null git push --force origin main
an appended recording|script -a /dev/null git push --force origin main
a hard reset under a recording|script -q /dev/null git reset --hard origin/main
a branch delete under a recording|script -q /dev/null git push origin :main
a recursive delete under a recording|script -aq /dev/null rm -rf /etc/nginx
a home dir delete under a recording|script -q /dev/null rm -rf ~/Documents
a recording under sudo|sudo script -q /dev/null git push --force origin main
a recording under xargs|xargs script -q /dev/null git push --force origin main
a timeout under a recording|script -q /dev/null timeout 5 git push --force origin main
a recording under a timeout|timeout 60 script -q /dev/null git push --force origin main
an assignment prefix before a recording|GIT_DIR=/x script -q /dev/null git push --force origin main
an env prefix inside a recording|script -q /dev/null env FOO=bar git push --force origin main
a shell string under a recording|script -q /dev/null bash -c 'git push --force origin main'
a recording inside a brace group|{ script -q /dev/null git push --force origin main; }
a recording in the then branch|if true; then script -q /dev/null git push --force origin main; fi
a recording by absolute path|/usr/bin/script -q /dev/null git push --force origin main
EOF

# the refusal is the compiled law's, and it names the branch it protected
D=$(detail "$PROJ" "script -q /dev/null git push --force origin main")
case "$D" in
  *baseline-force-push*) pass "the refusal carries the force-push law's id" ;;
  *) fail "wrong rule refused it: $(printf '%s' "$D" | head -2 | tr '\n' ' ')" ;;
esac
case "$D" in
  *"main"*) pass "the message names the shared branch the push was going to" ;;
  *) fail "message never names the branch: $(printf '%s' "$D" | head -3 | tr '\n' ' ')" ;;
esac
LEDGER=$(grep -h '"rule":"baseline-force-push"' "$RABADON_DIR/spool/"*.jsonl 2>/dev/null | tail -1)
[ -n "$LEDGER" ] && pass "the refusal is on the ledger under the baseline id" \
                 || fail "no baseline-force-push event on the ledger"

# ---------------------------------------------------------------------------
# 3. must ALLOW: recording a session is ordinary work, and one word of it is a
#    FILE NAME. Refusing these is how a skip-list buys a block with a lie.
# ---------------------------------------------------------------------------
echo "script(1): still allowed (the work this must not cut)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<'EOF'
the file operand IS the first word, so nothing is pushed|script git push --force origin main
the same, with the delete spelling|script rm -rf /etc/nginx
an interactive recording with a file|script /tmp/session.log
an interactive recording, quiet|script -q /tmp/session.log
the recorder with nothing after it|script
an ordinary push under a recording|script -q /dev/null git push origin feature/my-branch
a status check under a recording|script -q session.log git status --short
a test run under a recording|script -q /tmp/build.log make test
an install under a recording|script -q /tmp/npm.log npm test
the safe force under a recording|script -q /dev/null git push --force-with-lease origin main
a force to your own branch under a recording|script -q /dev/null git push --force origin my-personal-branch
a local hard reset under a recording|script -q /dev/null git reset --hard HEAD~1
a build dir delete under a recording|script -q /dev/null rm -rf ./build
a node_modules delete under a recording|script -q /dev/null rm -rf node_modules
a scratch delete under a recording|script -q /dev/null rm -rf /tmp/scratch
a fetch under a recording in a loop|for r in origin upstream; do script -q /dev/null git fetch $r; done
the words as a commit message|git commit -m "script -q /dev/null git push --force origin main"
the words as an echoed string|echo "script -q /dev/null git push --force origin main"
the words inside a single-quoted argument|grep -F 'script -q /dev/null git push --force origin main' notes.md
a file whose NAME starts with script|bash scripts.sh
a helper under a directory called script|./script/deploy.sh --dry-run
EOF

# the words in a heredoc are prose being written to a file, not a program
RC=$(run "$PROJ" "$(printf 'cat <<EOF > notes.md\nscript -q /dev/null git push --force origin main\nEOF\n')")
[ "$RC" = "0" ] && pass "allowed: the same line inside a heredoc body is prose, not a program" \
                || fail "WRONGLY refused ($RC): heredoc body"

# `scripted` is not the wrapper — a shell looks for a command by THAT name — so
# nothing is skipped. This is the assertion that the entry is a NAME comparison
# and not a prefix match.
RC=$(run "$PROJ" "scripted -q /dev/null git push --force origin main")
[ "$RC" = "0" ] && pass "allowed: \`scripted\` is a different command name, not the recorder" \
                || fail "WRONGLY refused ($RC): scripted"

# ---------------------------------------------------------------------------
# 4. judging is not running
# ---------------------------------------------------------------------------
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = "do not lose me" ] \
  && pass "the canary in the home dir survived judging every command above" || fail "the canary is gone"
[ -f "$LAB/sandbox/keep.txt" ] && pass "the canary in the lab survived" || fail "the lab canary is gone"
[ -d /tmp ] && [ -d /etc ] && [ -d "$HOME" ] \
  && pass "/tmp, /etc and the home dir are still on the machine" || fail "the test ran what it judged"

echo "script(1) wrapper: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
