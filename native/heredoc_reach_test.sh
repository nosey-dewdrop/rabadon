#!/usr/bin/env bash
# heredoc_reach_test.sh — where a project's own rules stop being consulted.
#
# A heredoc is not an exotic shape. It is how an agent writes anything longer
# than one line: `python3 - <<PY ... PY`, `cat <<EOF > file`, `bash <<EOF`.
# Measured on 3 August, one guard rule and one token delivered five ways:
#
#   echo marker-token                    refused
#   echo 'marker-token'                  refused
#   two lines, the token on the second   refused
#   python3 - <<PY / marker-token / PY   ALLOWED
#   python3 - <<'PY' / marker-token / PY ALLOWED
#
# So a project's own rule does not see inside a heredoc body. That is not a
# quirk of one pattern: rules.h matches a rule against one parsed SEGMENT
# surface at a time, and a heredoc body is not a segment. It came up because
# every scripted edit in one session went through a python heredoc, and a rule
# authored that same night to refuse exactly those edits never fired once.
#
# THE FLOOR HOLDS, AND THAT IS THE HALF THAT MATTERS. The compiled laws in
# baseline.h read words across the whole command text, so a heredoc fed to a
# SHELL — which is a program the shell will run — is still judged:
#
#   bash <<EOF / rm -rf ~/keep / EOF     refused by baseline-rm-rf-outside
#   sh   <<EOF / rm -rf ~/keep / EOF     refused by baseline-rm-rf-outside
#   bash <<EOF / git push --force main   refused by baseline-force-push
#
# and a body that merely NAMES a dangerous command without running it is
# allowed, which is correct — printing a string is not deleting anything.
#
# Both halves are pinned here because the gap between them is the thing to
# know: the floor is inside the heredoc, the project's own law is not. Widening
# the regex layer to read heredoc bodies is a real change with a real over-fire
# cost, and it is not made here; it is measured, named, and left visible.
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   - %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL - %s\n' "$1"; }

LAB="$(mktemp -d "${TMPDIR:-/tmp}/rabadon-heredoc.XXXXXX")"
trap 'rm -rf "$LAB"' EXIT
# the delete fixture may NOT live under the system temp area: /tmp, /var/tmp and
# /var/folders are exempt from the delete-coverage law by design (pathres.h
# machine_temp_roots), and a fixture built there measures the carve-out rather
# than the law. It goes inside the lab's own fake home.
FAKEHOME="$LAB/home"
PROJ="$LAB/proj"
RD="$LAB/rd"
mkdir -p "$FAKEHOME/.rabadon" "$FAKEHOME/keep" "$PROJ/.rabadon" "$RD/spool"
echo alive > "$FAKEHOME/keep/file.txt"
# ENFORCE. Without this the gate is in watch mode, block() exits 0, and every
# line below reads "allowed" while measuring nothing at all.
printf 'on\n' > "$FAKEHOME/.rabadon/enabled"
printf 'on\n' > "$RD/enabled"
printf '{"project":"p","bash":[{"id":"probe","deny":"marker-token","why":"the probe rule"}]}' \
  > "$PROJ/.rabadon/guard.json"

# judge <command> -> "<exit>:<rule>"
judge() {
  python3 -c '
import json,sys
print(json.dumps({"hook_event_name":"PreToolUse","session_id":"heredoc","cwd":sys.argv[1],
                  "tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$PROJ" "$1" \
  | env HOME="$FAKEHOME" RABADON_DIR="$RD" RABADON_NOTIFY=0 "$GATE" >/dev/null 2>"$LAB/err"
  printf '%s:%s' "$?" "$(grep -o 'Rule: [a-z-]*' "$LAB/err" | head -1 | sed 's/Rule: //')"
}

echo "heredoc reach — the floor is inside, a project's own law is not"
echo

# ---------------------------------------------------------------------------
# 1. the control: the same token, in the shapes a rule DOES see
# ---------------------------------------------------------------------------
echo "1. a guard rule sees the command line, including its later lines"
[ "$(judge 'echo marker-token')" = "2:probe" ] \
  && ok "a plain argument is judged" || bad "the probe rule did not fire on a plain argument"
[ "$(judge "echo 'marker-token'")" = "2:probe" ] \
  && ok "quoting does not hide it" || bad "quoting hid the token from its own rule"
[ "$(judge 'echo one
echo marker-token')" = "2:probe" ] \
  && ok "a second line does not hide it either" || bad "a token on line two was not judged"

echo
# ---------------------------------------------------------------------------
# 2. the boundary, stated as a fact rather than discovered again later
# ---------------------------------------------------------------------------
# This is an ALLOW that is asserted, which is the uncomfortable kind. It is
# written down so that the day somebody widens the matcher, this line fails and
# they have to come here and decide on purpose.
echo "2. a guard rule does NOT see inside a heredoc body"
[ "$(judge 'python3 - <<PY
print("marker-token")
PY')" = "0:" ] \
  && ok "an unquoted heredoc body is out of reach of the project's own rules" \
  || bad "the heredoc boundary moved — this is a widening, decide on purpose"
[ "$(judge "python3 - <<'PY'
print('marker-token')
PY")" = "0:" ] \
  && ok "and so is a quoted one" \
  || bad "the quoted heredoc boundary moved — decide on purpose"

echo
# ---------------------------------------------------------------------------
# 3. the floor does not have that gap
# ---------------------------------------------------------------------------
# The compiled laws read words across the whole command text, so a heredoc a
# SHELL will read is a program, and it is judged as one. This is the half that
# decides whether the boundary above is a footnote or a hole.
echo "3. the compiled laws are inside the heredoc"
[ "$(judge "rm -rf $FAKEHOME/keep")" = "2:baseline-rm-rf-outside" ] \
  && ok "the delete law refuses it stated plainly (the control)" \
  || bad "the control failed: the delete law did not fire on a plain delete"
[ "$(judge "bash <<EOF
rm -rf $FAKEHOME/keep
EOF")" = "2:baseline-rm-rf-outside" ] \
  && ok "and refuses it inside a bash heredoc" \
  || bad "a recursive delete rode into a bash heredoc unjudged"
[ "$(judge "sh <<'EOF'
rm -rf $FAKEHOME/keep
EOF")" = "2:baseline-rm-rf-outside" ] \
  && ok "and inside a quoted sh heredoc" \
  || bad "a recursive delete rode into an sh heredoc unjudged"
[ "$(judge 'bash <<EOF
git push --force origin main
EOF')" = "2:baseline-force-push" ] \
  && ok "the force-push law is in there too" \
  || bad "a force push rode into a heredoc unjudged"

echo
# ---------------------------------------------------------------------------
# 4. and it does not refuse a body that only NAMES the thing
# ---------------------------------------------------------------------------
# Printing a string is not deleting anything, and a supervisor that cannot tell
# those apart is one people switch off.
echo "4. naming a dangerous command is not running one"
[ "$(judge "python3 - <<PY
print('rm -rf $FAKEHOME/keep')
PY")" = "0:" ] \
  && ok "a python body that prints the words is allowed" \
  || bad "printing a string was refused as a delete"

# and nothing above ran: the canary is the whole claim
[ "$(cat "$FAKEHOME/keep/file.txt")" = "alive" ] \
  && ok "nothing was executed — the canary is untouched" || bad "a probe ran"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
