#!/bin/bash
# reserved_word_test.sh — a shell reserved word is not a command name.
#
# command_index() answers one question for every layer that judges a command:
# which word is the command? It skipped `FOO=bar` assignments and the wrapper
# list (sudo, env, timeout, xargs, ...) and stopped there. So the first word of
# a compound list was read as the command name:
#
#     { git push --force origin main; }        command name read as `{`
#     if true; then git push --force ... ; fi  command name read as `then`
#     while ...; do git push --force ... ; done command name read as `do`
#     ! git push --force origin main           command name read as `!`
#
# `{`, `then`, `do`, `!`, `else`, `elif`, `until`, `case` are RESERVED WORDS.
# The shell consumes them and runs the command AFTER them. rabadon read them as
# the command, so baseline.h never saw `git`, the relevance pre-filter marked
# the segment irrelevant, and the three compiled laws were never asked. Exit 0,
# no ledger line, nothing to see — on the fresh-install path with no guard.json,
# which is the path baseline.h exists for. (With a guard.json present a deny
# REGEX happens to match the surface text, which is why this hid: the escape
# was invisible in every project that had already written rules.)
#
# THE FIRST SECTION EXECUTES A SHELL, ON PURPOSE, so this is a measurement and
# not a story about a parser. It runs with a FAKE `git` and a FAKE `rm` first on
# PATH that record their argv and do nothing else, inside one mktemp lab whose
# repo has no remote and no history, with $HOME pointed inside that lab and a
# canary in it. If the fakes were somehow not found, the real git would have no
# remote to push to and the real rm would only see paths this test made seconds
# earlier.
#
# EVERY OTHER SECTION EXECUTES NOTHING: each command is handed to rabadon-gate
# on stdin as a PreToolUse event and only its exit code is read. The canaries at
# the bottom are the proof.
#
# The must-ALLOW list is as long as the must-BLOCK list on purpose. Skipping
# words to find the command name is the kind of fix that buys a block with a
# false refusal — reserved words are also ORDINARY TEXT inside a commit message,
# a heredoc and an echo, and every one of those spellings is on the allow list.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "reserved_word_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

LAB=$(mktemp -d /tmp/rabadon-reserved-test.XXXXXX)
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
  printf '{"hook_event_name":"PreToolUse","session_id":"s-reserved","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> what the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-reserved","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}

# ---------------------------------------------------------------------------
# 1. the reserved word is not decoration: the shell really runs git
# ---------------------------------------------------------------------------
echo "reserved words: what the shell actually runs (fake git, fake rm, nothing deleted, nothing pushed)"
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

ran() { # ran <label> <command> <expected argv line>
  : > "$LAB/argv.log"
  ( cd "$LAB/sandbox" && env PATH="$LAB/fakebin:$PATH" bash -c "$2" ) >/dev/null 2>&1
  if grep -qxF "$3" "$LAB/argv.log" 2>/dev/null; then
    pass "the shell runs it: $1"
  else
    fail "the shell did NOT run it ($1): log=[$(tr '\n' ';' < "$LAB/argv.log")]"
  fi
}
PUSHARGV='git [push] [--force] [origin] [main]'
ran "a brace group"           '{ git push --force origin main; }'                  "$PUSHARGV"
ran "the then branch"         'if true; then git push --force origin main; fi'     "$PUSHARGV"
ran "a loop body"             'n=1; while [ "$n" = 1 ]; do git push --force origin main; n=0; done' "$PUSHARGV"
ran "a negated command"       '! git push --force origin main'                     "$PUSHARGV"
ran "the else branch"         'if false; then echo a; else git push --force origin main; fi' "$PUSHARGV"
ran "a case arm"              'x=a; case $x in a) git push --force origin main;; esac' "$PUSHARGV"
ran "a for-loop body deletes" 'for f in one; do rm -rf /etc/nginx; done'           'rm [-rf] [/etc/nginx]'
[ -f "$LAB/sandbox/keep.txt" ] && pass "the fakes ran instead of the real git and rm: nothing was pushed or deleted" \
  || fail "a real rm ran in the lab"

# ---------------------------------------------------------------------------
# 2. must BLOCK: the law judges the command, wherever the syntax puts it
# ---------------------------------------------------------------------------
echo "reserved words: refused (the escape, in every spelling that carries it)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused: $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
a brace group|{ git push --force origin main; }
a brace group with a tab after the brace|{	git push --force origin main; }
a brace group nested in a brace group|{ { git push --force origin main; }; }
the then branch|if true; then git push --force origin main; fi
the condition of an if|if git push --force origin main; then echo ok; fi
a negated condition|if ! git push --force origin main; then echo x; fi
the else branch|if false; then echo a; else git push --force origin main; fi
the elif branch|if false; then echo a; elif true; then git push --force origin main; fi
a while-loop body|while false; do git push --force origin main; done
an until-loop condition|until git push --force origin main; do echo x; done
a for-loop body|for f in one two; do git push --force origin main; done
a negated command|! git push --force origin main
a negated command with padding|!    git push --force origin main
a case arm|case $x in a) git push --force origin main;; esac
a reserved word under the time keyword|time { git push --force origin main; }
a hard reset in a brace group|{ git reset --hard origin/main; }
a recursive delete of / in a brace group|{ rm -rf /; }
a recursive delete in a for-loop body|for f in one; do rm -rf /etc/nginx; done
a recursive delete of a home dir in the then branch|if true; then rm -rf ~/Documents; fi
a brace group inside a shell string|bash -c '{ git push --force origin main; }'
a brace group behind a wrapper|sudo bash -c 'if true; then git push --force origin main; fi'
EOF

# the refusal is the compiled law's, and it names the branch it protected
D=$(detail "$PROJ" "{ git push --force origin main; }")
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
# 3. must ALLOW: the same words are ordinary text, and the same shapes carry
#    ordinary work. Refusing these is how a skip-list buys a block with a lie.
# ---------------------------------------------------------------------------
echo "reserved words: still allowed (the work this must not cut)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<'EOF'
an ordinary push in a brace group|{ git push origin feature/my-branch; }
an ordinary push in the then branch|if true; then git push origin my-branch; fi
a negated ordinary push|! git push origin my-branch
the safe force in a brace group|{ git push --force-with-lease origin main; }
a force-push to your own branch in a brace group|{ git push --force origin my-personal-branch; }
a local hard reset in a brace group|{ git reset --hard HEAD~1; }
a build dir delete in a brace group|{ rm -rf ./build; }
a node_modules delete in the then branch|if true; then rm -rf node_modules; fi
a scratch delete in the else branch|if false; then echo a; else rm -rf /tmp/scratch; fi
a scratch delete in a loop body|for f in one two; do rm -rf /tmp/scratch/$f; done
an ordinary push in a case arm|case $x in a) git push origin my-branch;; esac
an ordinary push as an until condition|until git push origin my-branch; do sleep 1; done
the words as a commit message|git commit -m "if true; then git push --force origin main; fi"
the words as an echoed string|echo "{ git push --force origin main; }"
the words inside a single-quoted argument|grep -F '{ git push --force origin main; }' notes.md
a status check in a brace group|{ git status --short; }
a fetch in a loop body|for r in origin upstream; do git fetch $r; done
a reserved word as a plain argument|git commit -m "then do fi esac"
EOF

# the words in a heredoc are prose being written to a file, not a program
RC=$(run "$PROJ" "$(printf 'cat <<EOF > notes.md\n{ git push --force origin main; }\nEOF\n')")
[ "$RC" = "0" ] && pass "allowed: the same line inside a heredoc body is prose, not a program" \
                || fail "WRONGLY refused ($RC): heredoc body"

# `{git` is not the reserved word — the shell would look for a command spelled
# `{git` and not find one — so nothing is skipped and nothing is judged. This is
# the assertion that the skip is a WORD comparison and not a prefix match.
RC=$(run "$PROJ" "{git push --force origin main; }")
[ "$RC" = "0" ] && pass "allowed: \`{git\` is a command name the shell cannot run, not a brace group" \
                || fail "WRONGLY refused ($RC): {git push"

# ---------------------------------------------------------------------------
# 4. judging is not running
# ---------------------------------------------------------------------------
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = "do not lose me" ] \
  && pass "the canary in the home dir survived judging every command above" || fail "the canary is gone"
[ -f "$LAB/sandbox/keep.txt" ] && pass "the canary in the lab survived" || fail "the lab canary is gone"
[ -d /tmp ] && [ -d /etc ] && [ -d "$HOME" ] \
  && pass "/tmp, /etc and the home dir are still on the machine" || fail "the test ran what it judged"

echo "reserved words: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
