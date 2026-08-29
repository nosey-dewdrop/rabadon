#!/usr/bin/env bash
# home_isolation_test.sh — A TEST SUITE MAY NOT REWRITE THE OPERATOR'S MACHINE.
#
# WHAT WAS MEASURED, 2026-08-30, on this machine, deterministically:
#
#   git worktree add --detach "$HOME/.rb-f3h-wt" F3h-oncesi
#   cd "$HOME/.rb-f3h-wt" && make all
#   shasum -a 256 ~/.claude/settings.json   # 6c14cc5f...
#   make test                              # EXIT=0
#   shasum -a 256 ~/.claude/settings.json   # 427ffae0...  CHANGED
#
# The diff was seven pointers: six rabadon hook `command` entries and one
# `rabadon-drift` entry, all repointed from the canonical clone to the
# throwaway worktree. `~/.claude/settings.json` on this machine is SHARED — it
# carries hooks and a statusLine that are not rabadon's — and once the worktree
# is removed the user's brake points at a binary that does not exist and dies
# without saying so. The run protocol asks for a worktree every phase, so this
# was not a one-off.
#
# The mechanism, read out of the source rather than guessed: gate.cpp's
# refresh_hook_subscriptions() rate-limits itself with `<RABADON_DIR>/
# hooks-refresh.stamp`. A suite that hands every arm a FRESH mktemp RABADON_DIR
# has no stamp, so every SessionStart spawns hooks/refresh.mjs, whose refresh()
# targets `os.homedir()`. Not a defect in the product: refreshing an install is
# what that path is for. The defect is a suite that never said which home it
# meant and therefore got the operator's.
#
# WHICH SUITES: found by hashing the live file around each of native/*_test.sh
# in turn, restoring between runs. Exactly two moved it — contract_test.sh and
# promises_test.sh. (The five named on suspicion beforehand — doctor,
# exit_path, failed_call, hook_upgrade, npm_install — were measured CLEAN;
# they already declare their own HOME.)
#
# THIS SUITE IS THE LOCK, and it is dynamic on purpose: a grep for `HOME=` in a
# script would pass the day somebody adds the assignment in a subshell. It runs
# the real suites against a DECOY home that is stocked to be maximally
# rewritable, and asserts the decoy comes out byte for byte identical.
#
# ARM 3 is what keeps the lock from going vacuous. If refresh.mjs ever stops
# firing, arms 1 and 2 would pass for the wrong reason forever. So arm 3 drives
# the gate directly, with no isolation at all, and asserts the decoy DOES get
# rewritten — the fixture is proven capable of catching the thing before it is
# used to certify that the thing is absent.
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "home_isolation: node is required"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL - %s\n' "$1"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# A decoy home that refresh.mjs is guaranteed to WANT to rewrite: it already
# carries rabadon entries (self-heal refuses to touch a home that does not, so
# an empty decoy would prove nothing), and every command points somewhere else,
# so `changed` is true on the first pass.
mkdecoy() { # mkdecoy <dir>
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

echo "home_isolation: no suite may rewrite the operator's ~/.claude/settings.json"

# ---------------------------------------------------------------------------
# ARMS 1-2 — the two measured suites, run against the decoy home.
for s in contract_test promises_test; do
  D="$T/home-$s"; mkdecoy "$D"
  BEFORE="$(cat "$D/.claude/settings.json")"
  ( HOME="$D" bash "$HERE/$s.sh" ) >/dev/null 2>&1
  AFTER="$(cat "$D/.claude/settings.json" 2>/dev/null || echo MISSING)"
  if [ "$BEFORE" = "$AFTER" ]; then
    ok "$s.sh leaves the home it was given untouched"
  else
    bad "$s.sh rewrote \$HOME/.claude/settings.json — it borrowed the operator's machine"
  fi
  [ -e "$D/.claude/settings.json.bak-rabadon" ] \
    && bad "$s.sh left a .bak-rabadon beside the operator's settings" \
    || ok "$s.sh leaves no .bak-rabadon behind either"
done

# ---------------------------------------------------------------------------
# ARM 3 — THE FIXTURE PROVES IT CAN SEE. No isolation here: one SessionStart,
# fresh RABADON_DIR, HOME pointed at the decoy. If this does NOT rewrite, arms
# 1-2 are measuring nothing and say so out loud.
D="$T/home-live"; mkdecoy "$D"
RD="$T/rd-live"; mkdir -p "$RD"; : > "$RD/enabled"
BEFORE="$(cat "$D/.claude/settings.json")"
printf '{"hook_event_name":"SessionStart","cwd":"%s","session_id":"hi1"}' "$T" \
  | env HOME="$D" RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
AFTER="$(cat "$D/.claude/settings.json")"
if [ "$BEFORE" != "$AFTER" ]; then
  ok "control: an un-isolated SessionStart DOES repoint the home it is given"
else
  bad "control: nothing rewrote the decoy — arms 1-2 cannot fail and prove nothing"
fi

# ---------------------------------------------------------------------------
# ARM 4 — the switch the header promises. RABADON_SELFHEAL=0 must hold the
# same command still, or the escape hatch documented in gate.cpp is fiction.
D="$T/home-off"; mkdecoy "$D"
RD="$T/rd-off"; mkdir -p "$RD"; : > "$RD/enabled"
BEFORE="$(cat "$D/.claude/settings.json")"
printf '{"hook_event_name":"SessionStart","cwd":"%s","session_id":"hi2"}' "$T" \
  | env HOME="$D" RABADON_DIR="$RD" RABADON_SELFHEAL=0 RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
AFTER="$(cat "$D/.claude/settings.json")"
[ "$BEFORE" = "$AFTER" ] \
  && ok "RABADON_SELFHEAL=0 freezes the settings file, as the source says it does" \
  || bad "RABADON_SELFHEAL=0 did not stop the rewrite"

printf 'home_isolation: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
