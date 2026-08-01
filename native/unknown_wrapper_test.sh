#!/bin/bash
# unknown_wrapper_test.sh — a name the table never heard of is still a wrapper.
#
# THE HOLE.
#
#     caffeinate -i rm -rf ~/work/proj2
#
# command_index() (native/cmdtext.h) answers the one question every layer above
# it depends on: which word is the command? It skips the shell's own syntax,
# then `FOO=bar` prefixes, then a WRAPPER and everything that wrapper eats. The
# wrapper part is a TABLE OF NAMES — sudo, doas, env, command, builtin, nohup,
# setsid, exec, stdbuf, time, nice, ionice, timeout, xargs — and a name that is
# not in the table is read as the command itself. `caffeinate` is not in it, so
# base_of() handed the rule engine `caffeinate`; that is neither git nor rm, the
# relevance test at native/baseline.h:599 marked the segment irrelevant, and
# NONE of the compiled laws was asked. Exit 0, no ledger line.
#
# Measured on the shipped binary before this file was written, in a repo with no
# guard.json so only the compiled laws could answer:
#
#   rm -rf $H/work/proj2                       -> exit 2   (blocked)
#   caffeinate -i rm -rf $H/work/proj2         -> exit 0   (the leak)
#   git push --force origin main               -> exit 2   (blocked)
#   caffeinate -i git push --force origin main -> exit 0   (the same leak)
#
# One missing name turns off BOTH compiled laws at once, because both of them
# hang off the same word.
#
# WHAT THE HANDOFF GOT WRONG, MEASURED. The escape was reported as leaking
# through "both" layers — the project's own deny regexes as well as the compiled
# laws. It does not. A deny rule is matched against the SEGMENT SURFACE
# (native/rules.h), which is text, and a prefix in front of that text changes
# nothing about it. Measured against the four-rule guard.json the fixture ships:
#
#   rm -rf /Users/u/work/proj2                       -> exit 2  no-rm-rf-outside
#   caffeinate -i rm -rf /Users/u/work/proj2         -> exit 2  no-rm-rf-outside
#   caffeinate -i git push --force origin main       -> exit 2  no-force-push-main
#
# The reported guard=exit0 came from a home directory that sat under /tmp, which
# that rule's own `(?!tmp)` excludes on purpose. The regex layer held. The hole
# is on the fresh-install path, where the compiled laws are alone — the path
# baseline.h exists for.
#
# WHY THIS IS NOT FIXED BY ADDING ONE NAME. The table can only ever hold the
# wrappers someone has already been bitten by. Anything that execs its argv is
# one: caffeinate, arch, script, chroot, flock, unbuffer, systemd-run, a
# three-line runner in the repo's own bin/. So the parser stops treating an
# unknown first word as proof that nothing behind it is a command:
#
#   an unknown leading word, followed by option-looking words, followed by a
#   word this parser ALREADY acts on — git, a delete command, a shell, or
#   another wrapper — is read as a wrapper, and the command is that word.
#
# It is a rule about SHAPE, so it covers the wrapper names nobody has typed into
# the table yet. Section 0 measures the premise instead of asserting it: a
# wrapper this repo creates seconds earlier, under a name no table anywhere has,
# really does exec the argv behind it.
#
# WHAT KEEPS IT FROM BUYING BLOCKS WITH FALSE REFUSALS. The must-ALLOW list
# below is longer than the must-BLOCK list, and two entries on it are the whole
# reason the rule is shaped the way it is:
#
#   echo rm -rf ~/Documents      `echo`, `printf` and `cat` are the commands
#                                whose operands ARE their output — cmdtext.h
#                                already reads them that way (produced_stdout).
#                                Their operands are data, so they are never
#                                wrappers, and that is the carve-out.
#   grep rm -r ~/notes           the pattern is the word `rm`, spelled BEFORE
#                                the flag, which real grep accepts (measured).
#                                This was a live false refusal: the rule's first
#                                run refused it, so the grep family joined the
#                                same carve-out.
#   FOO+bar=/x git push ...      a word carrying '=' that is not an assignment
#                                is a name no shell can resolve — bash looks for
#                                a command by that name and never reaches git.
#                                The rule's first run refused all three
#                                spellings native/assign_prefix_test.sh measures
#                                with a real shell, and that suite is what
#                                caught it.
#
# A LIMIT, NAMED RATHER THAN LEFT TO BE FOUND. The shape rule skips option-
# LOOKING words only. A wrapper whose option takes a SEPARATE value, or that
# eats a plain operand of its own, still hides the command behind it unless its
# NAME is in the table with what it eats — which is exactly what `timeout`'s
# operands=1 is there for. Measured against this fix, with the wrapper this file
# creates in section 0:
#
#   rbwrap rm -rf ~/Documents          -> exit 2   the shape rule reaches it
#   rbwrap --jobs 4 rm -rf ~/Documents -> exit 0   `4` is not an option; the walk
#                                                  stops there and the name is
#                                                  not in the table
#
# So the table is not obsolete: it is what closes a wrapper whose arity is known.
# The shape rule is what keeps the NEXT unlisted name from turning the gate off.
#
# SECTION 0 EXECUTES A SHELL, ON PURPOSE. Everything after it EXECUTES NOTHING:
# each command is handed to rabadon-gate on stdin as a PreToolUse event and only
# its exit code is read. Section 0 runs with a FAKE `git` and a FAKE `rm` first
# on PATH that record their argv and do nothing else, inside one mktemp lab
# whose repo has no remote and no history, with $HOME pointed inside that lab
# and a canary in it. If the fakes were somehow not found, the real git would
# have no remote to push to and the real rm would only see paths this test made
# seconds earlier. The canaries at the bottom are the proof.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "unknown_wrapper_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

LAB=$(mktemp -d /tmp/rabadon-unknown-wrapper-test.XXXXXX)
trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"; mkdir -p "$HOME/.rabadon/spool" "$HOME/Documents" "$HOME/work/proj2"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
touch "$RABADON_DIR/enabled"                  # enforce
CANARY="$HOME/Documents/keep.txt"
echo "do not lose me" > "$CANARY"
echo "nor me" > "$HOME/work/proj2/file.txt"
# no guard.json anywhere: the compiled laws, judged alone — the fresh-install
# path, which is the only path this escape was ever live on
PROJ="$LAB/proj"; mkdir -p "$PROJ/.git" "$PROJ/build" "$PROJ/node_modules"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"

run() { # run <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"s-unkwrap","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> what the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-unkwrap","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}

# ---------------------------------------------------------------------------
# 0. the premise: a name the table never heard of really does exec the argv
# ---------------------------------------------------------------------------
echo "unknown wrappers: what a shell actually runs (fake git, fake rm, nothing deleted, nothing pushed)"
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
# a wrapper under a name no table on any machine has. Three lines, and it is
# every bit as much a wrapper as sudo: it execs its argv.
cat > "$LAB/fakebin/rbwrap" <<'WRAP'
#!/bin/sh
# an unknown wrapper: eat leading options, exec the rest
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done
exec "$@"
WRAP
chmod +x "$LAB/fakebin/rbwrap"

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
RMARGV='rm [-rf] [/etc/nginx]'
ran "a wrapper the table never heard of"        'rbwrap git push --force origin main'    "$PUSHARGV"
ran "the same wrapper with its own options"     'rbwrap -x --keep git push --force origin main' "$PUSHARGV"
ran "the same wrapper ending its options"       'rbwrap -x -- rm -rf /etc/nginx'         "$RMARGV"
ran "an unknown wrapper in front of a known one" 'rbwrap -x env rm -rf /etc/nginx'        "$RMARGV"
# a wrapper that lives in the repo being worked on. No table anywhere will ever
# have this name, and it is two lines long. native/xcrun_wrapper_test.sh asserted
# both of these must be ALLOWED, as the guard that its table lookup compares a
# whole NAME and not a prefix; the measurement below is why that pair moved to
# its must-BLOCK list and the guard is now spelled `xcrunner -sdk macosx ...`,
# which still tells a prefix match from a whole-name one and still passes.
mkdir -p "$LAB/sandbox/tools"
printf '#!/bin/sh\nexec "$@"\n' > "$LAB/sandbox/tools/xcrun-helper"
chmod +x "$LAB/sandbox/tools/xcrun-helper"
cp "$LAB/fakebin/rbwrap" "$LAB/fakebin/xcrunner"
ran "a two-line helper inside the repo"         './tools/xcrun-helper git push --force origin main' "$PUSHARGV"
ran "a name that merely starts with a listed one" 'xcrunner git push --force origin main'  "$PUSHARGV"
if command -v caffeinate >/dev/null 2>&1; then
  ran "caffeinate, the reported one"            'caffeinate -i git push --force origin main' "$PUSHARGV"
  ran "caffeinate with a flag that eats a value" 'caffeinate -t 30 rm -rf /etc/nginx'     "$RMARGV"
else
  echo "  skip - caffeinate is not on this machine; the shape cases below still run"
fi
[ -f "$LAB/sandbox/keep.txt" ] && pass "the fakes ran instead of the real git and rm: nothing was pushed or deleted" \
  || fail "a real rm ran in the lab"

# ---------------------------------------------------------------------------
# 1. must BLOCK: the law judges the command, whatever word stands in front of it
# ---------------------------------------------------------------------------
echo "unknown wrappers: refused (the escape, in the spellings that carry it)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused: $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
the reported command|caffeinate -i rm -rf ~/work/proj2
the same wrapper with no options|caffeinate rm -rf ~/Documents
a force-push behind the same wrapper|caffeinate -i git push --force origin main
a hard reset behind the same wrapper|caffeinate -i git reset --hard origin/main
a wrapper name no table has|rbwrap rm -rf ~/Documents
the same, with a long option|rbwrap --keep-going rm -rf ~/Documents
the same, with clustered short options|rbwrap -x -y git push --force origin main
the same, after an explicit end of options|rbwrap -- rm -rf ~/Documents
a branch delete behind an unknown wrapper|rbwrap git push origin :main
an unknown wrapper in front of a known one|rbwrap sudo rm -rf ~/Documents
a known wrapper in front of an unknown one|sudo caffeinate -i rm -rf ~/Documents
an unknown wrapper in front of a shell|rbwrap bash -c 'git push --force origin main'
caffeinate in front of a shell|caffeinate -i bash -c 'rm -rf ~/Documents'
a recursive delete of / behind an unknown wrapper|rbwrap rm -rf /
a two-line helper inside the repo|./tools/xcrun-helper git push --force origin main
a name that merely starts with a listed wrapper|xcrunner rm -rf ~/Documents
an unknown wrapper inside a brace group|{ rbwrap rm -rf ~/Documents; }
an unknown wrapper behind an assignment|FOO=bar rbwrap git push --force origin main
an unknown wrapper in the then branch|if true; then rbwrap rm -rf ~/Documents; fi
EOF

# the refusal is the compiled law's, and it names what it protected
D=$(detail "$PROJ" "caffeinate -i rm -rf ~/work/proj2")
case "$D" in
  *baseline-rm-rf-outside*) pass "the refusal carries the delete law's id" ;;
  *) fail "wrong rule refused it: $(printf '%s' "$D" | head -2 | tr '\n' ' ')" ;;
esac
D=$(detail "$PROJ" "rbwrap git push --force origin main")
case "$D" in
  *baseline-force-push*) pass "the refusal behind an unknown name carries the push law's id" ;;
  *) fail "wrong rule refused it: $(printf '%s' "$D" | head -2 | tr '\n' ' ')" ;;
esac
LEDGER=$(grep -h '"rule":"baseline-rm-rf-outside"' "$RABADON_DIR/spool/"*.jsonl 2>/dev/null | tail -1)
[ -n "$LEDGER" ] && pass "the refusal is on the ledger under the baseline id" \
                 || fail "no baseline-rm-rf-outside event on the ledger"

# ---------------------------------------------------------------------------
# 2. must ALLOW: the twin of every block above, and the work a shape rule is
#    most likely to cut. This list is longer than the block list on purpose.
# ---------------------------------------------------------------------------
echo "unknown wrappers: still allowed (the work this must not cut)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<'EOF'
the twin of the reported command: a build dir|caffeinate -i rm -rf ./build
a node_modules delete behind the wrapper|caffeinate -i rm -rf node_modules
a scratch delete behind the wrapper|caffeinate -i rm -rf /tmp/scratch
an ordinary push behind the wrapper|caffeinate -i git push origin my-branch
a force-push to your own branch behind the wrapper|caffeinate -i git push --force origin my-personal-branch
a local hard reset behind the wrapper|caffeinate -i git reset --hard HEAD~1
a status check behind the wrapper|caffeinate -i git status --short
a long job that is neither git nor rm|caffeinate -i make
a flag that eats a value, then an ordinary build|caffeinate -t 3600 npm run build
the wrapper on its own|caffeinate -i
a scratch delete behind an unknown wrapper|rbwrap rm -rf /tmp/scratch
a build delete behind an unknown wrapper|rbwrap rm -rf ./build
an ordinary command behind an unknown wrapper|rbwrap npm test
the words as an echoed string|echo rm -rf ~/Documents
the same, with echo's own option first|echo -n rm -rf ~/Documents
a force-push echoed, not run|echo git push --force origin main
the whole line quoted as data|echo "caffeinate -i rm -rf ~/Documents"
a grep whose pattern is the word rm|grep -r rm ~/notes
a grep whose pattern is the word rm, flag after|grep rm -r ~/notes
a word carrying = that is not an assignment|FOO+bar=/x git push --force origin main
a subscript that was never closed|arr[0=/x git push --force origin main
a name that may not start with a digit|2FOO=/x rm -rf ~/Documents
asking where a binary is|which git
the line as a commit message|git commit -m "caffeinate -i rm -rf ~/Documents"
a delete of the project's own tree behind the wrapper|caffeinate -i rm -rf build node_modules
EOF

# the words in a heredoc are prose being written to a file, not a program
RC=$(run "$PROJ" "$(printf 'cat <<EOF > notes.md\ncaffeinate -i rm -rf ~/Documents\nEOF\n')")
[ "$RC" = "0" ] && pass "allowed: the same line inside a heredoc body is prose, not a program" \
                || fail "WRONGLY refused ($RC): heredoc body"

# ---------------------------------------------------------------------------
# 3. the rule is about SHAPE, and the shape is checked in the parser once
# ---------------------------------------------------------------------------
# `rbwrapgit` is one word: the shell looks for a command by that name. Nothing
# is skipped, because there is no second word to skip TO. This is the assertion
# that the skip needs a real command word behind it and is not a prefix match.
RC=$(run "$PROJ" "rbwrapgit --force origin main")
[ "$RC" = "0" ] && pass "allowed: a name that merely contains a command name is not a wrapper" \
                || fail "WRONGLY refused ($RC): rbwrapgit"

# The limit, asserted rather than described: the walk skips option-LOOKING words
# and stops at the first plain operand. An unlisted wrapper whose option eats a
# SEPARATE value still hides what is behind it, and the answer to that is the
# NAME in the table with what it eats (`timeout` carries operands=1 for exactly
# this reason). Written down here so the boundary is a measurement and not a
# thing someone discovers in a repo one night.
RC=$(run "$PROJ" "rbwrap --jobs 4 rm -rf ~/Documents")
[ "$RC" = "0" ] && pass "named limit: an unlisted wrapper whose option eats a separate value is still missed" \
                || fail "the limit moved and this file did not: rbwrap --jobs 4 (rc=$RC)"

# ---------------------------------------------------------------------------
# 4. judging is not running
# ---------------------------------------------------------------------------
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = "do not lose me" ] \
  && pass "the canary in the home dir survived judging every command above" || fail "the canary is gone"
[ -f "$HOME/work/proj2/file.txt" ] \
  && pass "the directory the reported command targeted is still there" || fail "proj2 is gone"
[ -f "$LAB/sandbox/keep.txt" ] && pass "the canary in the lab survived" || fail "the lab canary is gone"
[ -d /tmp ] && [ -d /etc ] && [ -d "$HOME" ] \
  && pass "/tmp, /etc and the home dir are still on the machine" || fail "the test ran what it judged"

echo "unknown wrappers: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
