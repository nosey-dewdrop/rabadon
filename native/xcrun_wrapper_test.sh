#!/bin/bash
# xcrun_wrapper_test.sh — a tool finder is a wrapper, and the tool is the command.
#
# command_index() answers one question for every layer that judges a command:
# which word is the command? It skips the shell's own syntax, `FOO=bar`
# prefixes, and a list of WRAPPERS — programs that consume their own options and
# then run the command that follows (sudo, env, nohup, timeout, xargs, ...).
# `xcrun` was not on that list, so:
#
#     xcrun git push --force origin main       command name read as `xcrun`
#
# `xcrun` is neither git nor rm, so the relevance pre-filter marked the segment
# irrelevant and the three compiled laws were never asked. Exit 0, no ledger
# line — on the fresh-install path with no guard.json, the path baseline.h
# exists for. It is not an exotic spelling on this machine: xcrun ships with the
# Xcode command line tools, which this project already requires in order to
# build, and section 1 measures that `xcrun git` reaches a REAL git.
#
# The option walk is the other half. xcrun's value-taking options are spelled as
# WHOLE WORDS with ONE dash as readily as two — `-sdk macosx` and `--sdk macosx`
# are the same option to it — and the walk only knew how to read a value after a
# two-dash token. Reading `-sdk` as a short cluster would skip one word too few
# and name `macosx` as the command, which is the same escape wearing a flag.
#
# THE FIRST SECTION EXECUTES THE REAL xcrun, ON PURPOSE, so this is a
# measurement and not a story about a parser. Nothing dangerous runs there:
# every tool xcrun is asked to run is given as an ABSOLUTE PATH to a FAKE binary
# inside one mktemp lab, which records its argv and does nothing else. An
# absolute path is what makes that safe, and it is safe for a reason this test
# also measures: xcrun does NOT resolve a tool NAME through PATH, so a fake
# `git` earlier in PATH would have been walked straight past. The one real tool
# it is allowed to reach is `git --version`, which reads.
#
# EVERY OTHER SECTION EXECUTES NOTHING: each command is handed to rabadon-gate
# on stdin as a PreToolUse event and only its exit code is read. $HOME points
# inside the lab and carries a canary; the canaries at the bottom are the proof.
#
# The must-ALLOW list is longer than the must-BLOCK list on purpose. xcrun is
# how Xcode work is spelled — simctl, xcodebuild, notarytool, clang, swift — and
# a fix that names the tool as the command must not start refusing the tools.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "xcrun_wrapper_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

LAB=$(mktemp -d /tmp/rabadon-xcrun-test.XXXXXX)
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
  printf '{"hook_event_name":"PreToolUse","session_id":"s-xcrun","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> what the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-xcrun","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}

# ---------------------------------------------------------------------------
# 1. the wrapper is not decoration: the real xcrun hands the argv over intact
# ---------------------------------------------------------------------------
echo "xcrun: what the wrapper actually runs (real xcrun, fake tool by absolute path, nothing pushed or deleted)"
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

if command -v xcrun >/dev/null 2>&1; then
  handed() { # handed <label> <expected argv line> <xcrun args...>
    local label="$1" want="$2"; shift 2
    : > "$LAB/argv.log"
    ( cd "$LAB/sandbox" && xcrun "$@" ) >/dev/null 2>&1
    if grep -qxF "$want" "$LAB/argv.log" 2>/dev/null; then
      pass "xcrun hands the argv over: $label"
    else
      fail "xcrun did NOT reach the tool ($label): log=[$(tr '\n' ';' < "$LAB/argv.log")]"
    fi
  }
  FG="$LAB/fakebin/git"
  PUSHARGV='git [push] [--force] [origin] [main]'
  handed "plain"                  "$PUSHARGV" "$FG" push --force origin main
  handed "behind --sdk <name>"    "$PUSHARGV" --sdk macosx "$FG" push --force origin main
  handed "behind -sdk <name>"     "$PUSHARGV" -sdk macosx "$FG" push --force origin main
  handed "behind --toolchain <n>" "$PUSHARGV" --toolchain default "$FG" push --force origin main
  handed "behind -toolchain <n>"  "$PUSHARGV" -toolchain default "$FG" push --force origin main
  handed "behind -v"              "$PUSHARGV" -v "$FG" push --force origin main
  handed "behind -n -k"           "$PUSHARGV" -n -k "$FG" push --force origin main
  handed "behind --run"           "$PUSHARGV" --run "$FG" push --force origin main
  handed "behind --"              "$PUSHARGV" -- "$FG" push --force origin main
  handed "a recursive delete"     'rm [-rf] [/etc/nginx]' "$LAB/fakebin/rm" -rf /etc/nginx
  # the value word belongs to xcrun and NOT to the tool: skipping one word too
  # few would name `macosx` as the command, one too many would eat `status`
  handed "the option value is xcrun's, not the tool's" 'git [status]' -sdk macosx "$FG" status

  # the NAME `git` under xcrun is a real git. `-f` finds and runs nothing, so
  # this asks the question without answering it dangerously.
  GITPATH=$(xcrun -f git 2>/dev/null)
  if [ -n "$GITPATH" ] && [ -x "$GITPATH" ] && "$GITPATH" --version 2>/dev/null | grep -q "git version"; then
    pass "the name \`git\` under xcrun resolves to a real git: $GITPATH"
  else
    fail "xcrun -f git named nothing runnable: [$GITPATH]"
  fi

  # and PATH does not shield you from it: xcrun resolves the NAME through the
  # developer directory, so a fake first on PATH is walked past. This is why
  # every line above hands xcrun an absolute path instead.
  : > "$LAB/argv.log"
  ( cd "$LAB/sandbox" && env PATH="$LAB/fakebin:$PATH" xcrun git --version ) >/dev/null 2>&1
  if [ -s "$LAB/argv.log" ]; then
    pass "NOTE: on this machine xcrun did resolve the name through PATH"
  else
    pass "xcrun ignored a fake git first on PATH: a tool NAME is resolved by xcrun, not by the shell"
  fi

  # the two spellings xcrun itself refuses. Nothing runs behind them, so the
  # walk reading them as ordinary flags costs no work that could have happened.
  for spelling in "--sdk=macosx" "-nk"; do
    : > "$LAB/argv.log"
    ( cd "$LAB/sandbox" && xcrun "$spelling" "$FG" push --force origin main ) >/dev/null 2>&1
    [ -s "$LAB/argv.log" ] \
      && fail "xcrun accepted $spelling and reached the tool" \
      || pass "xcrun refuses \`$spelling\` and runs nothing behind it"
  done
else
  pass "SKIP section 1: no xcrun on this machine (the parser sections below still run)"
fi
[ -f "$LAB/sandbox/keep.txt" ] && pass "the fakes ran instead of a real git and rm: nothing was pushed or deleted" \
  || fail "a real rm ran in the lab"

# ---------------------------------------------------------------------------
# 2. must BLOCK: the law judges the tool, not the finder
# ---------------------------------------------------------------------------
echo "xcrun: refused (the escape, in every spelling that carries it)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused: $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
the plain form|xcrun git push --force origin main
the clustered short form|xcrun git push -f origin main
spelled by absolute path|/usr/bin/xcrun git push --force origin main
behind --sdk and its value|xcrun --sdk macosx git push --force origin main
behind -sdk, the one-dash spelling|xcrun -sdk macosx git push --force origin main
behind --toolchain and its value|xcrun --toolchain default git push --force origin main
behind -toolchain, the one-dash spelling|xcrun -toolchain default git push --force origin main
behind a valueless short option|xcrun -v git push --force origin main
behind two valueless short options|xcrun -n -k git push --force origin main
behind the long spelling of one|xcrun --no-cache git push --force origin main
behind --run|xcrun --run git push --force origin main
behind the end-of-options marker|xcrun -- git push --force origin main
a branch delete by empty source refspec|xcrun git push origin :main
a branch delete by --delete|xcrun git push --delete origin main
a mirror push|xcrun git push --mirror origin
a hard reset of the shared branch|xcrun git reset --hard origin/main
a recursive delete of /|xcrun rm -rf /
a recursive delete of a home dir|xcrun rm -rf ~/Documents
under an assignment prefix|FOO=bar xcrun git push --force origin main
under another wrapper|sudo xcrun git push --force origin main
under env|env xcrun git push --force origin main
under a shell string|bash -c 'xcrun git push --force origin main'
inside a brace group|{ xcrun git push --force origin main; }
in the then branch|if true; then xcrun git push --force origin main; fi
in a loop body|for b in one; do xcrun git push --force origin main; done
xcrun wrapping a shell that runs it|xcrun bash -c 'git push --force origin main'
a name that merely starts with a listed wrapper|xcrunner git push --force origin main
a two-line helper inside the repo being guarded|./tools/xcrun-helper git push --force origin main
EOF
# The last two spellings are the ones this file used to assert must be ALLOWED,
# as its guard that the table compares a whole NAME and not a prefix. Both were
# measured handing `git [push] [--force] [origin] [main]` to a real git under a
# real bash (native/unknown_wrapper_test.sh, section 0), so the guard was
# rewritten rather than the measurement ignored — see the note over the
# must-allow list below. A wrapper the table does not name is still a wrapper
# when a command this parser acts on stands behind it, and a two-line helper
# inside the repo being guarded is the cheapest wrapper there is.

# the refusal is the compiled law's, and it names the branch it protected
D=$(detail "$PROJ" "xcrun git push --force origin main")
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
# 3. must ALLOW: xcrun is how Xcode work is spelled. Naming the tool as the
#    command must not start refusing the tools.
# ---------------------------------------------------------------------------
# The last entry is the guard that this table lookup compares a whole NAME and
# not a prefix, respelled. It used to be `xcrunner git push --force origin main`,
# which asserted that a measured force-push must go unrefused. This spelling
# keeps the guard and loses the hole: under a PREFIX match `-sdk` is xcrun's
# valued option, two words are skipped and `git` lands in command position;
# under a whole-name match the walk stops at `macosx`, which is no command this
# parser acts on, so nothing behind it is read as one.
echo "xcrun: still allowed (the work this must not cut)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<'EOF'
the simulator control tool|xcrun simctl list devices
erasing a simulator|xcrun simctl erase all
a build|xcrun xcodebuild -scheme App -sdk iphonesimulator build
a compile behind --sdk|xcrun --sdk macosx clang -c main.c -o main.o
a compile behind -sdk|xcrun -sdk iphoneos clang -c main.c -o main.o
a swift build behind a toolchain|xcrun --toolchain default swift build
notarization|xcrun notarytool submit app.zip --keychain-profile prof
finding a tool|xcrun -f swiftc
finding git|xcrun -f git
printing the sdk path|xcrun --show-sdk-path
the version|xcrun --version
xcrun with no tool at all|xcrun
an ordinary push through xcrun|xcrun git push origin feature/my-branch
a status check through xcrun|xcrun git status --short
a fetch through xcrun|xcrun git fetch origin
the safe force through xcrun|xcrun git push --force-with-lease origin main
a force-push to your own branch through xcrun|xcrun git push --force origin my-personal-branch
a local hard reset through xcrun|xcrun git reset --hard HEAD~1
deleting your own merged branch through xcrun|xcrun git push origin :feature/my-branch
a build dir delete through xcrun|xcrun rm -rf ./build
a node_modules delete through xcrun|xcrun rm -rf node_modules
a scratch delete through xcrun behind an option|xcrun -sdk macosx rm -rf /tmp/scratch
an ordinary push behind -sdk and its value|xcrun -sdk macosx git push origin my-branch
an ordinary push behind two options|xcrun -n -v git push origin my-branch
an ordinary push after the end-of-options marker|xcrun -- git push origin my-branch
the words as a commit message|git commit -m "xcrun git push --force origin main"
the words as an echoed string|echo "xcrun git push --force origin main"
the word inside a single-quoted argument|grep -F 'xcrun git push --force origin main' notes.md
a name that merely starts with xcrun, before a value-taking option|xcrunner -sdk macosx git push --force origin main
EOF

# the words in a heredoc are prose being written to a file, not a program
RC=$(run "$PROJ" "$(printf 'cat <<EOF > notes.md\nxcrun git push --force origin main\nEOF\n')")
[ "$RC" = "0" ] && pass "allowed: the same line inside a heredoc body is prose, not a program" \
                || fail "WRONGLY refused ($RC): heredoc body"

# ---------------------------------------------------------------------------
# 4. the wrappers that were already on the list still read the same way. The
#    fix generalized the option walk, so every earlier wrapper is re-asked.
# ---------------------------------------------------------------------------
echo "xcrun: the wrappers that were already there did not move"
while IFS='|' read -r want desc cmd; do
  [ -z "$want" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "$want" ] && pass "unchanged ($want): $desc" || fail "MOVED (want $want got $RC): $cmd"
done <<'EOF'
2|sudo with a long option and a separate value|sudo --user root git push --force origin main
2|sudo with a long option and an attached value|sudo --user=root git push --force origin main
2|sudo with a short option and a separate value|sudo -u root git push --force origin main
2|env with an unset and a separate value|env --unset FOO git push --force origin main
2|timeout with its duration operand|timeout 5 git push --force origin main
2|timeout with a signal and a duration|timeout --signal TERM 5 git push --force origin main
2|xargs with a replace string|xargs -I{} git push --force origin main
2|nice with an adjustment|nice -n 10 git push --force origin main
0|sudo with a long option, ordinary work|sudo --user root git push origin my-branch
0|env with an unset, ordinary work|env --unset FOO git status
0|timeout with its duration, ordinary work|timeout 5 git fetch origin
EOF

# ---------------------------------------------------------------------------
# 5. judging is not running
# ---------------------------------------------------------------------------
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = "do not lose me" ] \
  && pass "the canary in the home dir survived judging every command above" || fail "the canary is gone"
[ -f "$LAB/sandbox/keep.txt" ] && pass "the canary in the lab survived" || fail "the lab canary is gone"
[ -d /tmp ] && [ -d /etc ] && [ -d "$HOME" ] \
  && pass "/tmp, /etc and the home dir are still on the machine" || fail "the test ran what it judged"

echo "xcrun wrapper: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
