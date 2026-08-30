#!/usr/bin/env bash
# brake_persist_test.sh — THE BRAKE MAY NOT COME OFF BY ITSELF.
#
# WHAT WAS MEASURED, 2026-08-30 (F3i), on this machine, before this file existed:
#
#   cat ~/.rabadon/mode          -> watch
#   ls  ~/.rabadon/enabled       -> No such file
#   printf '{"hook_event_name":"PreToolUse","tool_name":"Bash",
#            "tool_input":{"command":"git push --force origin main"}}' \
#     | native/rabadon-gate      -> "rabadon (watch) would have blocked this.
#                                   Nothing was stopped."   EXIT=0
#
# A real force-push event through the shipped binary was ALLOWED. The product's
# one promise was off on the machine that builds it.
#
# WHO PUT IT THERE — measured, not guessed. The ledger's last MODE line is
#   {"ts":1788044242076,"run":"cli-73188","ev":"MODE","from":"enforce","to":"watch"}
# with NO "outOfBand" flag, i.e. the CLI itself wrote it. `~/.claude/history.jsonl`
# names the hand that typed it, three times, in the harness's bash prompt:
#   01:57:21  !rabadon off
#   02:03:02  ! cd ~/damla_projects_2026/_arsiv_2026-08-18/sightstone && rabadon off
#   02:03:15  !rabadon off
# The operator owns the switch and used it. No agent and no install path did.
# That is exactly why THIS suite exists rather than a rule against `rabadon off`:
# the deliberate command must keep working, and everything else must not be able
# to reach the switch.
#
# So the lock is: whatever the INSTALL path does — `rabadon init`, and the
# self-healing SessionStart refresh that F3f added — the two files that ARE the
# brake (<RABADON_DIR>/mode and <RABADON_DIR>/enabled) come out the way they went
# in, and a real PreToolUse force-push still exits 2 afterwards.
#
# Arms 1-2 are the control that keeps the rest from going vacuous: the fixture
# is shown refusing under enforce and allowing under watch, with the same event,
# before it is used to certify that nothing moved the mode.
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "brake_persist: node is required"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL - %s\n' "$1"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# A project with a law of its own, so the event has something to be judged by
# and the reading does not depend on the machine's own repo.
PROJ="$T/proj"; mkdir -p "$PROJ/.rabadon"
cat > "$PROJ/.rabadon/guard.json" <<'JSON'
{ "project": "brake-fixture", "bash": [] }
JSON

# A decoy home, stocked the way home_isolation_test.sh stocks one: it already
# carries rabadon entries pointing somewhere else, so the self-heal path has a
# reason to run at all.
mkdecoy() {
  rm -rf "$1"; mkdir -p "$1/.claude"
  cat > "$1/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "/nonexistent/elsewhere/native/rabadon-gate" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "/nonexistent/elsewhere/native/rabadon-gate" } ] }
    ]
  },
  "statusLine": { "type": "command", "command": "/somebody/elses/statusline.sh" }
}
JSON
}

# an ENFORCE brake, on a RABADON_DIR of our own
mkbrake() { rm -rf "$1"; mkdir -p "$1"; printf 'enforce\n' > "$1/mode"; printf 'on\n' > "$1/enabled"; }

# fire one real PreToolUse force-push at the shipped binary; echo its exit code
pushevent() { # pushevent <home> <rabadon-dir>
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"},"cwd":"%s","session_id":"bp"}' "$PROJ" \
    | env HOME="$1" RABADON_DIR="$2" RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
  echo $?
}

echo "brake_persist: the install path may not lower the brake"

# ---------------------------------------------------------------------------
# ARM 1 — THE FIXTURE REFUSES. enforce + enabled => a real force-push is exit 2.
H="$T/h1"; mkdecoy "$H"; RD="$T/rd1"; mkbrake "$RD"
RC="$(pushevent "$H" "$RD")"
[ "$RC" = "2" ] && ok "enforce: a real PreToolUse force-push exits 2" \
                || bad "enforce: force-push exited $RC, expected 2 — the fixture cannot refuse"

# ---------------------------------------------------------------------------
# ARM 2 — THE FIXTURE CAN TELL THE DIFFERENCE. watch, no enabled => exit 0.
# Without this arm every assertion below would pass on a gate that refuses
# nothing at all.
H="$T/h2"; mkdecoy "$H"; RD="$T/rd2"; rm -rf "$RD"; mkdir -p "$RD"; printf 'watch\n' > "$RD/mode"
RC="$(pushevent "$H" "$RD")"
[ "$RC" = "0" ] && ok "control: watch with no enabled allows the same event (exit 0)" \
                || bad "control: watch exited $RC, expected 0 — arm 1 proves nothing"

# ---------------------------------------------------------------------------
# ARM 3 — THE SELF-HEALING SessionStart. F3f made the product rewrite the
# operator's settings by itself. It may repoint a hook; it may not touch the
# switch.
H="$T/h3"; mkdecoy "$H"; RD="$T/rd3"; mkbrake "$RD"
printf '{"hook_event_name":"SessionStart","cwd":"%s","session_id":"bp3"}' "$PROJ" \
  | env HOME="$H" RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
[ "$(cat "$RD/mode" 2>/dev/null)" = "enforce" ] \
  && ok "self-heal SessionStart leaves mode=enforce" \
  || bad "self-heal SessionStart changed mode to '$(cat "$RD/mode" 2>/dev/null)'"
[ -e "$RD/enabled" ] \
  && ok "self-heal SessionStart leaves the enabled flag in place" \
  || bad "self-heal SessionStart removed the enabled flag"
RC="$(pushevent "$H" "$RD")"
[ "$RC" = "2" ] && ok "after self-heal the force-push is still refused (exit 2)" \
                || bad "after self-heal the force-push exited $RC — the install dropped the brake"

# ---------------------------------------------------------------------------
# ARM 4 — `rabadon init`, the documented install. Its own screen says the
# default is watch; that default is for a machine with NO mode, and it may not
# be applied on top of an operator who already turned enforcement on.
H="$T/h4"; mkdecoy "$H"; RD="$T/rd4"; mkbrake "$RD"
P4="$T/p4"; mkdir -p "$P4"
( cd "$P4" && env HOME="$H" RABADON_DIR="$RD" node "$ROOT/hooks/manage.mjs" init --no-llm "$P4" ) >/dev/null 2>&1
[ "$(cat "$RD/mode" 2>/dev/null)" = "enforce" ] \
  && ok "rabadon init leaves an existing mode=enforce alone" \
  || bad "rabadon init lowered mode to '$(cat "$RD/mode" 2>/dev/null)'"
[ -e "$RD/enabled" ] \
  && ok "rabadon init leaves the enabled flag in place" \
  || bad "rabadon init removed the enabled flag"
RC="$(pushevent "$H" "$RD")"
[ "$RC" = "2" ] && ok "after rabadon init the force-push is still refused (exit 2)" \
                || bad "after rabadon init the force-push exited $RC — install disarmed the guard"

# ---------------------------------------------------------------------------
# ARM 5 — `rabadon on` from a cold machine really arms it. The README's last
# line is this command; if it produced a mode without the flag (or a flag
# without the mode) the user would read "ON" over a gate that refuses nothing.
H="$T/h5"; mkdecoy "$H"; RD="$T/rd5"; rm -rf "$RD"; mkdir -p "$RD"
env HOME="$H" RABADON_DIR="$RD" "$GATE" --on >/dev/null 2>&1
[ "$(cat "$RD/mode" 2>/dev/null)" = "enforce" ] && [ -e "$RD/enabled" ] \
  && ok "rabadon on writes BOTH mode=enforce and the enabled flag" \
  || bad "rabadon on left mode='$(cat "$RD/mode" 2>/dev/null)' enabled=$([ -e "$RD/enabled" ] && echo yes || echo no)"
RC="$(pushevent "$H" "$RD")"
[ "$RC" = "2" ] && ok "and the very next force-push is refused (exit 2)" \
                || bad "rabadon on printed ON but the gate exited $RC"

# ---------------------------------------------------------------------------
# ARM 6 — THE OPERATOR'S OWN COMMAND STILL WORKS, AND LEAVES A MARK. A guard
# with no way out is a trap; a way out with no record is what let this machine
# sit unguarded for an hour with nobody able to name the cause.
H="$T/h6"; mkdecoy "$H"; RD="$T/rd6"; mkbrake "$RD"; mkdir -p "$RD/spool"
# one MODE line has to exist for the comparison to have a floor to stand on
env HOME="$H" RABADON_DIR="$RD" "$GATE" --on  >/dev/null 2>&1
env HOME="$H" RABADON_DIR="$RD" "$GATE" --off >/dev/null 2>&1
[ "$(cat "$RD/mode" 2>/dev/null)" = "watch" ] && [ ! -e "$RD/enabled" ] \
  && ok "rabadon off still lowers the brake — the exit door is not welded shut" \
  || bad "rabadon off did not reach watch"
grep -qs '"ev":"MODE"' "$RD"/spool/*.jsonl 2>/dev/null \
  && ok "and the lowering is written on the ledger as a MODE line" \
  || bad "rabadon off lowered the brake without a MODE line — nobody could name the cause"
RC="$(pushevent "$H" "$RD")"
[ "$RC" = "0" ] && ok "after the operator's own off, the event is allowed again (exit 0)" \
                || bad "after rabadon off the gate still exited $RC"

printf 'brake_persist: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
