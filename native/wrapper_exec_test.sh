#!/bin/bash
# wrapper_exec_test.sh — the wrapper list is not the list of wrappers.
#
# command_index() answers one question for every layer that judges a command:
# which word is the command? It skips the shell's own syntax, then `FOO=bar`
# assignments, then a WRAPPER and everything that wrapper eats. The wrapper part
# is a table of names, and a name that is not in the table is read as the
# command itself. So the whole gate turned off behind a name nobody had typed
# into the table yet:
#
#     caffeinate git push --force origin main      command name read as `caffeinate`
#     sandbox-exec -n prof rm -rf /                command name read as `sandbox-exec`
#
# `caffeinate` is not decoration. It is how a long job is kept alive on a mac,
# so it sits in front of exactly the commands that take long enough to be worth
# protecting. Read as the command name, it is neither git nor rm, the segment is
# marked irrelevant, and none of the three compiled laws is asked. Measured on
# the shipped binary before this suite existed: `caffeinate git push --force
# origin main` exited 0 while the same line without the first word exited 2, and
# `caffeinate rm -rf /` exited 0 as well — the delete law went out through the
# same hole as the push law.
#
# Both names are on this machine and both were measured EXECUTING the argv
# behind them, which is section 0. That is the whole membership test for the
# table: not "is it a famous wrapper" but "does a shell reach the dangerous argv
# through it". (Other names came out of the same measuring run; each is asserted
# by the suite that owns its option grammar, not a second time here.)
#
# SECTION 0 EXECUTES A SHELL, ON PURPOSE, so the premise is a measurement and
# not a story about a parser. It runs with a FAKE `git` and a FAKE `rm` first on
# PATH that record their argv and do nothing else, inside one mktemp lab whose
# repo is `git init`-ed with NO REMOTE and no history, with $HOME pointed inside
# that lab and a canary in it, and every path it hands the fake `rm` is a
# directory this test created seconds earlier. If the fakes were somehow not
# found, the real git would have nowhere to push and the real rm would delete
# only what this test made.
#
# EVERY OTHER SECTION EXECUTES NOTHING: each command is handed to rabadon-gate
# on stdin as a PreToolUse event and only its exit code is read. The canaries at
# the bottom are the proof.
#
# The must-ALLOW list is as long as the must-BLOCK list on purpose. Growing a
# skip table is the kind of fix that buys a block with a false refusal: the
# wrapper name is also ORDINARY TEXT in a commit message, an echo and a grep
# pattern, `caffeinated` is a different name than `caffeinate`, and the same
# wrappers carry ordinary work all day — a fetch, a status, a lease push, a
# delete of the project's own build output.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "wrapper_exec_test: build first (make)"; exit 1; }

ok=0; bad=0; SKIP=0; SKIPA=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }
# An arm that cannot run HERE is announced with its NAME and its NUMBER, and
# the count reaches the summary line. A skip that increments nothing is the
# suite getting smaller in silence, and every counter downstream reads the
# smaller number as health. native/silent_skip_test.sh holds this over the
# whole directory. $1 = arm, $2 = assertions not run, $3 = why.
skip() { SKIP=$((SKIP+1)); SKIPA=$((SKIPA+1)); echo "  SKIP - $1: 1 assertion(s) did NOT run — the wrapper binary is not on this machine"; }

LAB=$(mktemp -d /tmp/rabadon-wrapper-test.XXXXXX)
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
  printf '{"hook_event_name":"PreToolUse","session_id":"s-wrapper","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> what the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-wrapper","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}

# ---------------------------------------------------------------------------
# 0. the premise: a shell really reaches git and rm through these names
# ---------------------------------------------------------------------------
echo "wrappers: what the shell actually runs (fake git, fake rm, no remote, nothing deleted)"
mkdir -p "$LAB/fakebin" "$LAB/sandbox"
echo "do not lose me either" > "$LAB/sandbox/keep.txt"
# a real repo, created here, with no remote configured: a push that escaped the
# fakes would have nowhere to go
( cd "$LAB/sandbox" && git init -q . >/dev/null 2>&1 ) || true
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

ran() { # ran <tool> <label> <command> <expected argv line>
  if ! command -v "$1" >/dev/null 2>&1; then skip "$2 ($1)"; return; fi
  : > "$LAB/argv.log"
  ( cd "$LAB/sandbox" && env PATH="$LAB/fakebin:$PATH" bash -c "$3" ) >/dev/null 2>&1
  if grep -qxF "$4" "$LAB/argv.log" 2>/dev/null; then
    pass "the shell runs it: $2"
  else
    fail "the shell did NOT run it ($2): log=[$(tr '\n' ';' < "$LAB/argv.log")]"
  fi
}
PUSHARGV='git [push] [--force] [origin] [main]'
mkdir -p "$LAB/sandbox/deleteme"

ran caffeinate   "caffeinate, bare"                'caffeinate git push --force origin main'         "$PUSHARGV"
ran caffeinate   "caffeinate with an assertion"    'caffeinate -i git push --force origin main'      "$PUSHARGV"
ran caffeinate   "caffeinate with a clustered set" 'caffeinate -dimsu git push --force origin main'  "$PUSHARGV"
ran caffeinate   "caffeinate whose -t eats a word" 'caffeinate -t 3600 git push --force origin main' "$PUSHARGV"
ran caffeinate   "caffeinate ending options at --" 'caffeinate -i -- git push --force origin main'   "$PUSHARGV"
ran caffeinate   "caffeinate reaching rm"          "caffeinate rm -rf $LAB/sandbox/deleteme"         "rm [-rf] [$LAB/sandbox/deleteme]"
ran sandbox-exec "sandbox-exec with a profile"     "sandbox-exec -p '(version 1)(allow default)' git push --force origin main" "$PUSHARGV"

[ -f "$LAB/sandbox/keep.txt" ] && pass "the fakes ran instead of the real git and rm: nothing was pushed or deleted" \
  || fail "a real rm ran in the lab"
[ -d "$LAB/sandbox/deleteme" ] && pass "even the directory the fake rm was aimed at is still there" \
  || fail "a real rm reached the lab directory"
( cd "$LAB/sandbox" && git remote 2>/dev/null | grep -q . ) \
  && fail "the lab repo has a remote — the push section is not isolated" \
  || pass "the lab repo has no remote, so no push in this file could have left the machine"

# ---------------------------------------------------------------------------
# 1. must BLOCK: the law judges the command the wrapper runs
# ---------------------------------------------------------------------------
echo
echo "wrappers: refused (the escape, in every spelling that carries it)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused: $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
caffeinate holding a shared-branch force-push open|caffeinate git push --force origin main
caffeinate with an assertion flag|caffeinate -i git push --force origin main
caffeinate with a clustered assertion set|caffeinate -dimsu git push --force origin main
caffeinate whose -t eats the next word|caffeinate -t 3600 git push --force origin main
caffeinate whose -t carries its value joined|caffeinate -t3600 git push --force origin main
caffeinate whose -w eats a pid|caffeinate -w 99999 git push --force origin main
caffeinate ending its options with --|caffeinate -i -- git push --force origin main
caffeinate spelled by absolute path|/usr/bin/caffeinate git push --force origin main
caffeinate carrying the short force flag|caffeinate git push -f origin master
caffeinate carrying a force refspec|caffeinate git push origin +master
caffeinate carrying a hard reset of a shared branch|caffeinate git reset --hard origin/main
caffeinate carrying a delete of the root|caffeinate rm -rf /
caffeinate carrying a delete of a home dir|caffeinate rm -rf ~/Documents
caffeinate under sudo|sudo caffeinate git push --force origin main
caffeinate over sudo|caffeinate sudo git push --force origin main
caffeinate over env|caffeinate env FOO=bar git push --force origin main
caffeinate over nohup|caffeinate nohup git push --force origin main
caffeinate holding a shell open|caffeinate bash -c 'git push --force origin main'
caffeinate inside a brace group|{ caffeinate git push --force origin main; }
caffeinate inside a loop body|for i in 1; do caffeinate git push --force origin main; done
caffeinate behind an assignment prefix|GIT_SSH_COMMAND=ssh caffeinate git push --force origin main
caffeinate in the second segment of a list|npm test && caffeinate git push --force origin main
caffeinate with git's own global options after it|caffeinate git -C /any/path push --force origin master
sandbox-exec with an inline profile|sandbox-exec -p '(version 1)(allow default)' git push --force origin main
sandbox-exec with a profile file|sandbox-exec -f /tmp/p.sb git push --force origin main
sandbox-exec with a named profile|sandbox-exec -n no-network git push --force origin main
sandbox-exec whose -D eats a parameter|sandbox-exec -D KEY=value -n no-network git push --force origin main
sandbox-exec carrying a delete of the root|sandbox-exec -n no-network rm -rf /
EOF

# the refusal is the compiled law's, and it names what it protected
D=$(detail "$PROJ" "caffeinate git push --force origin main")
case "$D" in
  *baseline-force-push*) pass "the refusal carries the force-push law's id" ;;
  *) fail "wrong rule refused it: $(printf '%s' "$D" | head -2 | tr '\n' ' ')" ;;
esac
case "$D" in
  *"main"*) pass "the message names the shared branch the push was going to" ;;
  *) fail "message never names the branch: $(printf '%s' "$D" | head -3 | tr '\n' ' ')" ;;
esac
D=$(detail "$PROJ" "caffeinate rm -rf /")
case "$D" in
  *baseline-rm-rf-outside*) pass "the delete behind the wrapper is refused by the delete law" ;;
  *) fail "wrong rule refused the delete: $(printf '%s' "$D" | head -2 | tr '\n' ' ')" ;;
esac
LEDGER=$(grep -h '"rule":"baseline-force-push"' "$RABADON_DIR/spool/"*.jsonl 2>/dev/null | tail -1)
[ -n "$LEDGER" ] && pass "the refusal is on the ledger under the baseline id" \
                 || fail "no baseline-force-push event on the ledger"

# ---------------------------------------------------------------------------
# 2. must ALLOW: the same wrappers carry ordinary work, and the same names are
#    ordinary text. This is where a bigger skip table pays for its block.
# ---------------------------------------------------------------------------
echo
echo "wrappers: still allowed (the work this must not cut)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<'EOF'
caffeinate on an ordinary push|caffeinate git push origin my-branch
caffeinate on the safe force|caffeinate git push --force-with-lease origin main
caffeinate force-pushing your own branch|caffeinate git push --force origin my-personal-branch
caffeinate on a local hard reset|caffeinate git reset --hard HEAD~1
caffeinate deleting the project's own build output|caffeinate rm -rf ./build
caffeinate deleting node_modules|caffeinate rm -rf node_modules
caffeinate deleting a scratch dir under the temp root|caffeinate rm -rf /tmp/scratch
caffeinate on a status check|caffeinate git status --short
caffeinate on a fetch|caffeinate -i git fetch origin
caffeinate on a long test run|caffeinate -t 3600 npm test && git status
caffeinate with no utility behind it at all|caffeinate -w 12345 && git status
the wrapper name inside a commit message|git commit -m "caffeinate git push --force origin main"
the wrapper name echoed as text|echo "caffeinate git push --force origin main"
the wrapper name in a single-quoted argument|grep -F 'caffeinate git push --force origin main' notes.md
sandbox-exec on an ordinary push|sandbox-exec -p '(version 1)' git push origin my-branch
sandbox-exec deleting the project's own build output|sandbox-exec -n no-network rm -rf ./build
EOF

# the same line inside a heredoc is prose being written to a file, not a program
RC=$(run "$PROJ" "$(printf 'cat <<EOF > notes.md\ncaffeinate git push --force origin main\nEOF\n')")
[ "$RC" = "0" ] && pass "allowed: the same line inside a heredoc body is prose, not a program" \
                || fail "WRONGLY refused ($RC): heredoc body"

# ---------------------------------------------------------------------------
# 2b. what the NAME buys, stated as a difference and not as a claim
#
# A word this table does not know, sitting in front of a word the parser already
# acts on, is read as a wrapper anyway (native/unknown_wrapper_test.sh). So
# `caffeinated git push --force origin main` is refused too, and the old probe
# for "the table matches a NAME, not a prefix" no longer isolates anything.
#
# What the entry in the table still buys is the one thing that rule says out
# loud it cannot do: eat an option's SEPARATE value. `-t 3600` and `-w 99999`
# put a bare number between the wrapper and the command, and a rule that only
# skips option-LOOKING words stops on the number. Measured here as a pair, same
# command, one letter of difference in the first word.
# ---------------------------------------------------------------------------
while IFS='|' read -r desc known unknown; do
  [ -z "$desc" ] && continue
  RK=$(run "$PROJ" "$known"); RU=$(run "$PROJ" "$unknown")
  if [ "$RK" = "2" ] && [ "$RU" = "0" ]; then
    pass "the table entry is what reaches past a separate option value: $desc"
  else
    fail "named=$RK unknown=$RU (want 2 and 0): $desc"
  fi
done <<'EOF'
-t eats its timeout|caffeinate -t 3600 git push --force origin main|caffeinated -t 3600 git push --force origin main
-w eats its pid|caffeinate -w 99999 git push --force origin main|caffeinated -w 99999 git push --force origin main
EOF

# ---------------------------------------------------------------------------
# 3. judging is not running
# ---------------------------------------------------------------------------
echo
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = "do not lose me" ] \
  && pass "the canary in the home dir survived judging every command above" || fail "the canary is gone"
[ -f "$LAB/sandbox/keep.txt" ] && pass "the canary in the lab survived" || fail "the lab canary is gone"
[ -d /tmp ] && [ -d /etc ] && [ -d "$HOME" ] \
  && pass "/tmp, /etc and the home dir are still on the machine" || fail "the test ran what it judged"

echo
echo "wrappers: $ok passed, $bad failed, $SKIP skipped ($SKIPA assertion(s) not run)"
[ "$bad" -eq 0 ]
