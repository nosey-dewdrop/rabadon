#!/bin/bash
# glob_escape_test.sh — a pattern is judged by where it LANDS, not by its prefix.
#
# The delete law was taught that the system temp area is scratch, not somebody's
# data. That carve-out was written against the text of a target, and a pattern
# is not text the way a path is: the shell rewrites it before rm ever sees it.
# The rule read a target up to the first `*`, judged the directory part, and
# never looked at the rest. So this passed:
#
#     rm -rf /tmp/*/../../Users/u/proj1
#             ^^^^ judged            ^^^^^^^^^^^^^^^^ never looked at
#
# The judged part is /tmp, which is scratch, so the command was waved through.
# The shell then expands the pattern to /tmp/<entry>/../../Users/u/proj1 for
# every entry, and every one of those lands outside the temp area. The same
# path WITHOUT the glob was refused, which is the tell: the glob was the one
# spelling whose destination was never computed. Braces are the same shape by
# another route — `{a,../../Users/u/proj1}` is two words, and only one of them
# stays home.
#
# THE FIRST SECTION EXECUTES A SHELL, ON PURPOSE, TO PROVE THE ESCAPE IS REAL
# AND NOT A STORY ABOUT A PARSER. It runs with a FAKE `rm` first on PATH that
# records its arguments and deletes nothing, everything it names is inside one
# mktemp lab, and the lab has no remote and no history. If the fake were never
# found and the real rm ran, the worst case is the lab deleting a file it
# created seconds earlier.
#
# EVERY OTHER SECTION EXECUTES NOTHING. Commands are handed to rabadon-gate on
# stdin as PreToolUse events and only the exit code is read. The canaries at the
# bottom are the proof that judging is not running.
#
# The must-BLOCK list comes first and is longer than the must-ALLOW list, on
# purpose: the cheapest way to make an escape test pass is to refuse every
# pattern, and that would delete the carve-out this rule was measured into
# existence for. Both directions are asserted here, in one file, so neither can
# be bought with the other.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "glob_escape_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

LAB=$(mktemp -d /tmp/rabadon-glob-test.XXXXXX)
trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"; mkdir -p "$HOME/.rabadon/spool"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
touch "$RABADON_DIR/enabled"                 # enforce
# no guard.json anywhere: the three compiled laws, judged alone
PROJ="$LAB/proj"; mkdir -p "$PROJ/.git" "$PROJ/build" "$PROJ/node_modules"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"

run() { # run <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"s-glob","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> the sentence the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-glob","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}

# ---------------------------------------------------------------------------
# 1. the shell really leaves the directory the pattern names (fake rm, no delete)
# ---------------------------------------------------------------------------
echo "glob escape: what the shell actually hands to rm"
mkdir -p "$LAB/sandbox/tmpish/a" "$LAB/sandbox/tmpish/b" "$LAB/sandbox/victim"
echo "do not lose me" > "$LAB/sandbox/victim/keep.txt"
mkdir -p "$LAB/fakebin"
cat > "$LAB/fakebin/rm" <<FAKE
#!/bin/sh
# records what a real rm would have been given, and removes nothing
for a in "\$@"; do printf '%s\n' "\$a" >> "$LAB/argv.log"; done
exit 0
FAKE
chmod +x "$LAB/fakebin/rm"
: > "$LAB/argv.log"
env PATH="$LAB/fakebin:$PATH" bash -c "rm -rf $LAB/sandbox/tmpish/*/../../victim" >/dev/null 2>&1

ESCAPED=$(python3 - "$LAB" <<'PY'
import os, sys
lab = sys.argv[1]
inside = os.path.realpath(os.path.join(lab, "sandbox", "tmpish"))
args = [l.rstrip("\n") for l in open(os.path.join(lab, "argv.log"))]
targets = [a for a in args if not a.startswith("-")]
out = [t for t in targets
       if not (os.path.realpath(t) == inside or os.path.realpath(t).startswith(inside + os.sep))]
print(len(targets), len(out), out[0] if out else "")
PY
)
set -- $ESCAPED
NT=${1:-0}; NOUT=${2:-0}; WHERE=${3:-}
if [ "$NT" -gt 0 ] && [ "$NOUT" = "$NT" ]; then
  pass "every word the pattern expanded to lands outside the dir it names ($NT/$NT, e.g. $WHERE)"
else
  fail "expansion proof did not run: $NT targets, $NOUT outside"
fi
[ -f "$LAB/sandbox/victim/keep.txt" ] \
  && pass "the fake rm deleted nothing: the escape is proved without paying for it" \
  || fail "the victim file is gone — a real rm ran"

# ---------------------------------------------------------------------------
# 2. must BLOCK: the destination is outside, however the target is spelled
# ---------------------------------------------------------------------------
echo "glob escape: refused (the positives — these are the product)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused: $desc" || fail "NOT refused ($RC): $cmd"
done <<EOF
plain path out of the temp area, no pattern at all|rm -rf /tmp/../Users/u/proj1
a star, then walk out|rm -rf /tmp/*/../../Users/u/proj1
a single-character wildcard, then walk out|rm -rf /tmp/?/../../Users/u/proj1
a bracket class, then walk out|rm -rf /tmp/[ab]/../../Users/u/proj1
a globstar, then walk out|rm -rf /tmp/**/../../Users/u/proj1
a star that walks up to the users tree|rm -rf /tmp/*/../../../Users
a star that walks back to the temp root every process holds|rm -rf /tmp/*/..
a brace where only one of the two words stays home|rm -rf /tmp/{a,../../Users/u/proj1}
a quoted prefix does not hide the pattern|rm -rf "/tmp"/*/../../Users/u/proj1
the launchd temp tree, same escape|rm -rf /var/folders/*/../../../Users/u/proj1
a star under a home dir that itself sits under a temp dir|rm -rf $HOME/*
an expansion too large to compute is not judged safe|rm -rf /tmp/{a,b}{c,d}{e,f}{g,h}{i,j}{k,l}{m,n}{o,p}{q,r}
EOF

# the same law, one directory up from the project instead of the temp area: a
# pattern inside the tree is not a licence to walk out of it. The walk-up is
# longer than the tree is deep on purpose — `..` at the root is a no-op, so the
# destination is /Users/u/proj1 on any machine this runs on.
RC=$(run "$PROJ" "rm -rf build/*/../../../../../../../../Users/u/proj1")
[ "$RC" = "2" ] && pass "refused: a pattern inside the project that walks out of it" \
                || fail "NOT refused ($RC): pattern walking out of the project tree"

# it is THIS law that refuses, and it says where the command was going
D=$(detail "$PROJ" "rm -rf /tmp/*/../../Users/u/proj1")
case "$D" in
  *baseline-rm-rf-outside*) pass "the refusal carries the delete law's id, not another rule's" ;;
  *) fail "wrong rule refused it: $(printf '%s' "$D" | head -2 | tr '\n' ' ')" ;;
esac
case "$D" in
  *"/Users/u/proj1"*) pass "the message names the destination, not the prefix it was cut off at" ;;
  *) fail "message never names the destination: $(printf '%s' "$D" | grep -i 'rm -r' | head -1)" ;;
esac
LEDGER=$(grep -h '"rule":"baseline-rm-rf-outside"' "$RABADON_DIR/spool/"*.jsonl 2>/dev/null | tail -1)
[ -n "$LEDGER" ] && pass "the refusal is on the ledger under the baseline id" \
                 || fail "no baseline-rm-rf-outside event on the ledger"

# `rm -rf /tmp/**/cache` sat on the must-ALLOW list below until the temp
# carve-out was measured to hand over the shared root's entries. `**` is not
# "deeper", it is a component like any other: with globstar off bash expands it
# the way it expands `/tmp/*/cache`, and with globstar on it also reaches every
# depth. Either way the first component under the shared temp root is
# unanchored, so the target is a `cache` dir inside every OTHER session's
# scratch tree — the same handover as `rm -rf /tmp/*`, one level down. The law
# and both of its directions live in native/temp_root_glob_test.sh; the
# must-allow list keeps an anchored globstar so this cannot be paid for by
# refusing `**` outright.
RC=$(run "$PROJ" "rm -rf /tmp/**/cache")
[ "$RC" = "2" ] && pass "refused: a globstar whose first component enumerates the shared temp root" \
                || fail "NOT refused ($RC): rm -rf /tmp/**/cache"

# ---------------------------------------------------------------------------
# 3. must ALLOW: refusing every pattern would be the cheapest way to pass
#    section 2, and it would delete the reason the carve-out exists
# ---------------------------------------------------------------------------
echo "glob escape: still allowed (the carve-out this rule was measured into)"
mkdir -p "$LAB/work"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<EOF
a glob under the temp root|rm -rf /tmp/rb-scratch.*
a glob one level deeper|rm -rf /tmp/proj-out/*
a glob in the middle of the path|rm -rf /tmp/build-*/out
a walk-up after a glob that stays inside the temp area|rm -rf /tmp/a*/../b
a brace whose every word stays inside the temp area|rm -rf /tmp/{a,b}
a globstar under a scratch dir the caller named|rm -rf /tmp/proj-out/**/cache
a glob inside the project tree|rm -rf ./build/*
a deeper glob inside the project tree|rm -rf node_modules/*/dist
a walk-up after a glob that stays inside the project|rm -rf build/x*/../out
a scratch dir this run made and is about to remake|rm -rf /tmp/fp && mkdir -p /tmp/fp/out
EOF

# ---------------------------------------------------------------------------
# 4. judging is not running
# ---------------------------------------------------------------------------
[ -f "$LAB/sandbox/victim/keep.txt" ] && [ "$(cat "$LAB/sandbox/victim/keep.txt")" = "do not lose me" ] \
  && pass "the canary survived judging every command above" || fail "the canary is gone"
[ -d "$LAB/sandbox/tmpish/a" ] && [ -d "$LAB/sandbox/tmpish/b" ] \
  && pass "the pattern's own matches are still on disk" || fail "the matched dirs are gone"
[ -d /tmp ] && [ -d /etc ] && [ -d "$HOME" ] \
  && pass "/tmp, /etc and the home dir are still on the machine" || fail "the test ran what it judged"

echo "glob escape: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
