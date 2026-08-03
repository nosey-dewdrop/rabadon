#!/bin/bash
# rule_census_test.sh — the four ways a guard rule can pass `rabadon lint`, read
# correctly to a human, and still be structurally incapable of ever firing.
#
# A guard rule is a promise. `rabadon lint` checks that the promise COMPILES; it
# has never checked that the promise can be KEPT. This file measures the four
# gaps between those two things, each with a rule written the way a person
# actually writes one, driven through the real gate binary.
#
#   1. THE PIPE. cmdtext.h splits a command line on `; && || |` and rules.h
#      matches one text per segment surface, so `|` is never present in any
#      surface a rule is matched against. A pattern that spells `\|` is asking
#      to see a character the matcher has already removed.
#
#   2. REDIRECTIONS. The parser carries `>` `>>` out of argv into Seg.redirs.
#      The question this file answers is whether the SURFACE a deny regex reads
#      still carries them — the structural laws in baseline.h do not see them,
#      and it was not obvious that the regex layer does.
#
#   3. protectedPaths vs the path Claude Code sends. gate.cpp matches
#      protectedPaths against the raw file_path, and a real Edit event carries
#      an ABSOLUTE path. A rule authored `^`-anchored and relative — which is
#      how nearly every one on this machine is authored — is comparing an
#      absolute string against a pattern pinned to the start of a relative one.
#
#   4. GUARD REACH from a subdirectory. The guard is read once, from the exact
#      session cwd. A session standing one directory below the project root is
#      the ordinary case for anyone with a `src/`.
#
# NOTHING RUNS. Every command is handed to rabadon-gate on stdin as a PreToolUse
# event and only the exit code and the refusal line are read; a PreToolUse
# verdict executes nothing. The lab is a mktemp directory and is removed after.
# The one fixture that must NOT be under /tmp is the delete target: /tmp,
# /var/tmp and /var/folders are exempt by design (pathres.h machine_temp_roots),
# so a delete fixture built there measures the carve-out instead of the rule.
# That target is created inside the lab's own fake home.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }

LAB=$(mktemp -d "${TMPDIR:-/tmp}/rabadon-rulecensus.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"
export RABADON_DIR="$LAB/home/.rabadon"
export RABADON_NOTIFY=0
mkdir -p "$RABADON_DIR/spool" "$HOME/keepme"
printf 'on\n' > "$RABADON_DIR/enabled"
echo alive > "$HOME/CANARY"
echo alive > "$HOME/keepme/data.txt"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   - %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL - %s\n' "$1"; }
jstr() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

N=0
judge() { # judge <cwd> <tool> <json-tool-input> -> "<exit>:<ruleid>"
  local out rc; N=$((N+1))
  out=$(printf '{"hook_event_name":"PreToolUse","session_id":"rc%s","cwd":"%s","tool_name":"%s","tool_input":%s}' \
        "$N" "$1" "$2" "$3" | "$GATE" 2>&1 >/dev/null)
  rc=$?
  echo "$rc:$(printf '%s' "$out" | sed -n 's/^Rule: \([^ ]*\).*/\1/p' | head -1)"
}
bash_of() { judge "$1" Bash "{\"command\":$(jstr "$2")}"; }
edit_of() { judge "$1" Edit "{\"file_path\":$(jstr "$2")}"; }

refuses() { # refuses <desc> <result> <rule>
  case "$2" in "2:$3") ok "$1 -> refused by $3" ;;
               2:*)    bad "$1 -> refused by ${2#2:}, expected $3" ;;
               *)      bad "$1 -> ALLOWED (exit ${2%%:*}), expected $3" ;; esac
}
allows() { # allows <desc> <result>
  case "$2" in 0:*) ok "$1 -> allowed" ;;
               *)   bad "$1 -> refused by ${2#*:}, expected allow" ;; esac
}

mkproj() { # mkproj <dir> <guard-json>
  mkdir -p "$1/.rabadon"; printf '%s\n' "$2" > "$1/.rabadon/guard.json"
}

echo "rule census — four ways a rule that lints can still never fire"
echo

# ---------------------------------------------------------------------------
echo "1. the pipe: a pattern that spells \\| is matched against a surface a pipe cannot be in"
P1="$LAB/pipe"
mkproj "$P1" '{"project":"pipe","bash":[
 {"id":"no-reverse-patch","deny":"git\\s+show\\s+[0-9a-f]{7,40}[^|]*\\|\\s*git\\s+apply\\s+(-R|--reverse)","why":"reverse-applying an old commit onto HEAD silently no-ops"},
 {"id":"no-exit-after-pipe","deny":"\\|\\s*(tail|head|grep)\\b[^\\n]*\\n?\\s*echo\\s+[\"'"'"']?exit=\\$\\?","why":"echo exit=$? after a pipe reports the wrong stage"}
],"protectedPaths":[],"disabled":[]}'
# the exact command each rule was written about
R=$(bash_of "$P1" 'git show 1a2b3c4 | git apply -R')
case "$R" in 2:no-reverse-patch) ok   "the pipe rule fires on the line it was written for" ;;
             *) bad "the pipe rule CANNOT fire on its own subject (exit ${R%%:*}): git show 1a2b3c4 | git apply -R" ;; esac
R=$(bash_of "$P1" 'make test | tail -5
echo exit=$?')
case "$R" in 2:no-exit-after-pipe) ok "the exit-code rule fires on the line it was written for" ;;
             *) bad "the exit-code rule CANNOT fire on its own subject (exit ${R%%:*})" ;; esac
# and the reason, asserted rather than described: each half alone is a surface
allows "the left half alone is an ordinary command" "$(bash_of "$P1" 'git show 1a2b3c4')"
allows "the right half alone is an ordinary command" "$(bash_of "$P1" 'git apply -R')"
echo

# ---------------------------------------------------------------------------
echo "2. redirections: does the surface a deny regex reads still carry > and >>?"
P2="$LAB/redir"
mkproj "$P2" '{"project":"redir","bash":[
 {"id":"no-truncating-write","deny":"(>>?|\\btee\\b)[^\\n]*NOTES\\.md","why":"NOTES.md is appended to, never rewritten"}
],"protectedPaths":[],"disabled":[]}'
refuses "a truncating redirect at the named file" "$(bash_of "$P2" 'echo x > NOTES.md')" no-truncating-write
refuses "an appending redirect at the named file"  "$(bash_of "$P2" 'echo x >> NOTES.md')" no-truncating-write
refuses "the tee spelling"                          "$(bash_of "$P2" 'echo x | tee NOTES.md')" no-truncating-write
allows  "an unrelated file"                         "$(bash_of "$P2" 'echo x > OTHER.md')"
echo

# ---------------------------------------------------------------------------
echo "3. protectedPaths: the rule is written relative, the event carries absolute"
P3="$LAB/paths"
mkproj "$P3" '{"project":"paths","bash":[],"protectedPaths":[
 {"id":"anchored-relative","match":"^web/(data\\.js|index\\.html)$","why":"build outputs, regenerated"},
 {"id":"anchored-tolerant","match":"(^|/)web/(data\\.js|index\\.html)$","why":"the same rule, spelled to survive an absolute path"}
],"disabled":[]}'
R=$(edit_of "$P3" "$P3/web/data.js")
case "$R" in 2:anchored-relative) ok "the ^-anchored relative rule fires on the absolute path Claude Code sends" ;;
             2:anchored-tolerant) bad "the ^-anchored relative rule is DEAD: only its (^|/) twin caught the absolute path" ;;
             *) bad "neither rule fired on the absolute path (exit ${R%%:*})" ;; esac
# Both rules match this file and the FIRST one in the guard wins, so once the
# anchored-relative rule stopped being dead it started catching this too. That
# is the fix landing, not a regression: the assertion below used to name the
# tolerant twin because the twin was the only one that could fire.
R=$(edit_of "$P3" "$P3/web/index.html")
case "$R" in 2:anchored-relative|2:anchored-tolerant) ok "the absolute path is caught, by whichever rule is first" ;;
             *) bad "the absolute path was ALLOWED (exit ${R%%:*})" ;; esac
# the same rule, same file, spelled the way it was authored: this is the control
refuses "the ^-anchored rule DOES fire on a relative spelling (which nothing sends)" \
        "$(edit_of "$P3" 'web/data.js')" anchored-relative
echo

# ---------------------------------------------------------------------------
echo "4. guard reach: a session standing one directory below the project root"
# NOT under $LAB. mktemp lands in /var/folders, which is outside $HOME and
# outside any git repository, and the guard walk is bounded by the git root when
# there is one and by $HOME when there is not. There is no defensible bound in
# the system temp area -- walking up from /var/folders to / would apply a
# stranger's rules to this work -- so a fixture built there measures the absence
# of a bound rather than the reach of the guard. Same premise error that put a
# delete-law fixture inside the coverage carve-out earlier the same night.
P4="$(cd "$HERE/.." && pwd)/.censusreach-$$"
mkdir -p "$P4"
trap 'rm -rf "$P4"' EXIT
mkproj "$P4" '{"project":"reach","bash":[
 {"id":"reach-no-yarn","deny":"\\byarn\\b","why":"this project is npm only"}
],"protectedPaths":[],"disabled":[]}'
mkdir -p "$P4/src/deep"
refuses "at the project root the rule holds" "$(bash_of "$P4" 'yarn add x')" reach-no-yarn
R=$(bash_of "$P4/src" 'yarn add x')
case "$R" in 2:reach-no-yarn) ok "one directory down the rule still holds" ;;
             *) bad "one directory down the project's own rule is GONE (exit ${R%%:*}): cwd=$P4/src" ;; esac
R=$(bash_of "$P4/src/deep" 'yarn add x')
case "$R" in 2:reach-no-yarn) ok "two directories down the rule still holds" ;;
             *) bad "two directories down the project's own rule is GONE (exit ${R%%:*})" ;; esac
echo

# ---------------------------------------------------------------------------
echo "5. judging is not running"
[ -f "$HOME/CANARY" ] && [ "$(cat "$HOME/CANARY")" = alive ] && ok "the home canary survived" || bad "the home canary is gone"
[ -f "$HOME/keepme/data.txt" ] && ok "the delete fixture survived every probe above" || bad "a probe actually deleted something"
[ -f "$P1/.rabadon/guard.json" ] && [ -f "$P3/.rabadon/guard.json" ] \
  && ok "the guards on disk are unmodified by judging" || bad "a guard file changed"

echo
echo "  pass $pass   fail $fail"
[ "$fail" -eq 0 ] && echo "  rule census: GREEN (no mechanism found)" || echo "  rule census: RED — each FAIL above is a rule shape that cannot fire"
exit 0
