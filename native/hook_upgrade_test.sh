#!/usr/bin/env bash
# hook_upgrade_test.sh — SHIPPED IS NOT INSTALLED.
#
# WHAT WAS MEASURED, AND WHY THIS FILE EXISTS.
# On 2026-08-29 F3e taught the binary the PostToolUseFailure event and added the
# subscription to hooks/install.mjs. Every suite went green. Then the arbiter ran
# an exit-1 Bash on the live machine and read the ledger: STEP_START, no STEP_OK.
# The repair was in the repo and NOT on the machine. Measured cause, verbatim
# from reports/kosu/kanit/f3f/k1-teshis.txt:
#
#   registered set (~/.claude/settings.json, mtime 26 Aug 20:17):
#       PostToolUse PreToolUse SessionStart Stop UserPromptSubmit
#   set hooks/install.mjs would write today:
#       ... + PostToolUseFailure, and rabadon-drift on Stop
#
# Not a dead path, not a stale path, not a broken merge: installHooks() computes
# `healthy` against what it would write TODAY, so `rabadon init` WOULD have
# repaired it. The hole is that NOTHING RE-RUNS THE INSTALLER. `rabadon doctor`
# certified this exact file "global hooks healthy ... all from this install" and
# printed "all green", because it only asked whether the paths are dead or from
# another tree — never whether the EVENT SET is current.
#
# For a product whose users are overwhelmingly already installed, that is the
# most expensive defect class available: nothing you fix ever arrives, and the
# repo stays green while it does not.
#
# THE SHAPE OF THE FIX THIS SUITE PINS. SessionStart is in the oldest event set
# there is, so it is the one event an old install still delivers to new code.
# The gate uses it to re-register itself through the SAME installHooks() the
# installer uses (hooks/refresh.mjs), so an event added to desiredHooks()
# tomorrow reaches installed machines with no second list to keep in sync.
#
# Everything below runs against a FIXTURE install written in the pre-fix shape
# and the REAL shipped binary. No claim reads the source of the thing it tests.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOTDIR="$(cd "$HERE/.." && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"

PASSN=0; FAIL=0
pass() { printf '  ok   - %s\n' "$1"; PASSN=$((PASSN + 1)); }
fail() { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }

# NO SILENT SKIP: an unanswerable claim is red, not absent (the class that let
# version_test.sh shrink from 13 assertions to 11 and still exit 0).
[ -x "$GATE" ] || { printf 'hook_upgrade: no gate binary at %s — run make first\n' "$GATE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'hook_upgrade: python3 is required\n' >&2; exit 1; }
command -v node    >/dev/null 2>&1 || { printf 'hook_upgrade: node is required (the installer is JS)\n' >&2; exit 1; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbupg.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
# TMPDIR ends in a slash on macOS, so the fixture path arrives here as `T//rbupg`
# while node's path.join hands back the collapsed form — a claim that compares
# the path rabadon PRINTS with the path this suite built would fail on a
# difference that is not a defect. Collapse it once, here.
while [ "$ROOT" != "${ROOT//\/\///}" ]; do ROOT="${ROOT//\/\///}"; done

echo "hook_upgrade: an install written before today has to catch up by itself"

# The pre-fix subscription, exactly as rabadon wrote it before 2026-08-29, plus
# somebody else's hook on one of the same events — the thing an upgrade is most
# likely to destroy.
write_old_install() { # write_old_install <home>
  mkdir -p "$1/.claude"
  python3 -c '
import json, sys
home, gate = sys.argv[1], sys.argv[2]
ev   = lambda: [{"hooks": [{"type": "command", "command": gate}]}]
evm  = lambda t: [{"matcher": "*", "hooks": [{"type": "command", "command": gate, "timeout": t}]}]
hooks = {"SessionStart": ev(), "UserPromptSubmit": ev(), "Stop": ev(),
         "PreToolUse": evm(960), "PostToolUse": evm(120)}
hooks["PreToolUse"].append({"matcher": "*", "hooks": [{"type": "command", "command": "/usr/bin/true"}]})
json.dump({"model": "opus", "hooks": hooks,
           "statusLine": {"type": "command", "command": "/usr/bin/true"}},
          open(home + "/.claude/settings.json", "w"), indent=2)' "$1" "$GATE"
}

# what the gate says at SessionStart, for a given HOME / project
session_start() { # session_start <home> <rabadon-dir> <project> <session-id>
  printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s"}' "$4" "$3" \
    | env HOME="$1" RABADON_DIR="$2" RABADON_NOTIFY=0 RABADON_JUDGE=0 "$GATE" 2>/dev/null
}

events_with_rabadon() { # events_with_rabadon <settings.json>
  python3 -c '
import json, re, sys
try: d = json.load(open(sys.argv[1]))
except Exception: print("NOFILE"); sys.exit(0)
RE = re.compile(r"rabadon-(gate|drift)")
out = set()
for ev, arr in (d.get("hooks") or {}).items():
    for e in arr:
        for h in (e.get("hooks") or []):
            if RE.search(h.get("command") or ""): out.add(ev)
print(" ".join(sorted(out)) or "NONE")' "$1"
}

mkfixture() { # mkfixture <name>  -> echoes the home dir
  local h="$ROOT/$1"
  rm -rf "$h"; mkdir -p "$h/.rabadon/spool" "$h/proj/.git"
  printf 'ref: refs/heads/main\n' > "$h/proj/.git/HEAD"
  write_old_install "$h"
  echo "$h"
}

# ---------------------------------------------------------------------------
# CLAIM 0 — the fixture really is the OLD shape. Without this every claim below
# could pass because the fixture was current all along.
H="$(mkfixture a)"
BEFORE="$(events_with_rabadon "$H/.claude/settings.json")"
case " $BEFORE " in
  *" PostToolUseFailure "*) fail "the fixture is not a pre-fix install — it already subscribes ($BEFORE)" ;;
  *" PostToolUse "*)        pass "the fixture is a pre-fix install: $BEFORE" ;;
  *)                        fail "the fixture has no rabadon hooks at all ($BEFORE)" ;;
esac

# ---------------------------------------------------------------------------
# CLAIM 1 — THE UPGRADE. One SessionStart from the shipped binary, no user
# action, and the machine is subscribed to the event it was blind to.
OUT="$(session_start "$H" "$H/.rabadon" "$H/proj" s-up-1)"
AFTER="$(events_with_rabadon "$H/.claude/settings.json")"
case " $AFTER " in
  *" PostToolUseFailure "*) pass "after one session the install subscribes to PostToolUseFailure" ;;
  *) fail "the install is still blind after a session: $AFTER" ;;
esac

# ---------------------------------------------------------------------------
# CLAIM 2 — IT IS NOT A ONE-EVENT PATCH. rabadon-drift on Stop was missing from
# the same fixture for the same reason; a fix that only knows the name of
# today's event is a fix that has to be written again for the next one.
if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
cmds = [h.get("command","") for e in d["hooks"].get("Stop", []) for h in (e.get("hooks") or [])]
sys.exit(0 if any("rabadon-drift" in c for c in cmds) else 1)' "$H/.claude/settings.json"; then
  pass "the upgrade carried every stale subscription, not just the named one (drift on Stop)"
else
  fail "rabadon-drift is still unregistered — the upgrade only knew about one event"
fi

# ---------------------------------------------------------------------------
# CLAIM 3 — IT DOES NOT COST THE USER ANYTHING THEY HAD. An upgrade that eats
# somebody else's hook or repoints their statusLine is worse than staying stale.
if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
cmds = [h.get("command","") for e in d["hooks"].get("PreToolUse", []) for h in (e.get("hooks") or [])]
ok = "/usr/bin/true" in cmds
ok = ok and d.get("statusLine", {}).get("command") == "/usr/bin/true"
ok = ok and d.get("model") == "opus"
sys.exit(0 if ok else 1)' "$H/.claude/settings.json"; then
  pass "the foreign hook, the foreign statusLine and unrelated keys all survived"
else
  fail "the upgrade destroyed something that was not rabadon's"
fi
[ -f "$H/.claude/settings.json.bak-rabadon" ] \
  && pass "the file the upgrade rewrote was backed up first" \
  || fail "settings.json was rewritten with no .bak-rabadon beside it"

# ---------------------------------------------------------------------------
# CLAIM 4 — IT SAYS SO. A tool that rewrites the user's settings.json and keeps
# quiet about it is the failure mode Promise 1 exists to forbid.
case "$OUT" in
  *"PostToolUseFailure"*) : ;;
  *) fail "the session said nothing about the events it registered" ;;
esac
case "$OUT" in
  *"$H/.claude/settings.json"*) pass "the session names the file it changed" ;;
  *) fail "the session changed a settings file without naming it" ;;
esac
case "$OUT" in
  *bak-rabadon*) pass "the session tells the user where their previous settings are" ;;
  *) fail "the backup exists but is never mentioned — the user cannot get back" ;;
esac

# ---------------------------------------------------------------------------
# CLAIM 5 — IT DOES NOT ROUND UP. Claude Code read its hooks before this process
# existed, so THIS session is still blind. Reporting the repair as coverage is
# the exact spin CLAUDE.md 8 forbids, and it would hide a whole session of
# missed failures behind a green sentence.
case "$OUT" in
  *"blind spots:"*) : ;;
  *) fail "no blind-spot block on the session card at all" ;;
esac
case "$OUT" in
  *"this one stays blind"*) pass "the session still declares itself blind — the repair lands NEXT session" ;;
  *) fail "the repair was reported as if this session were already covered" ;;
esac

# ---------------------------------------------------------------------------
# CLAIM 6 — IT IS ON THE RECORD. A change to the user's machine that only ever
# existed as a line of stdout cannot be audited afterwards.
DAY="$(date -u +%Y-%m-%d)"
if grep -qh '"ev":"HOOKS_REFRESHED"' "$H/.rabadon/spool/$DAY.jsonl" "$H/.rabadon/spool/"*.jsonl 2>/dev/null; then
  pass "the upgrade is written to the ledger (HOOKS_REFRESHED)"
else
  fail "the machine was changed and the ledger has no record of it"
fi

# ---------------------------------------------------------------------------
# CLAIM 7 — ONCE, NOT EVERY SESSION. The second run must not rewrite anything:
# an upgrade that spawns node and rewrites settings.json on every SessionStart
# is a permanent cost for a one-time event.
cp "$H/.claude/settings.json" "$ROOT/a.snapshot"
OUT2="$(session_start "$H" "$H/.rabadon" "$H/proj" s-up-2)"
if cmp -s "$H/.claude/settings.json" "$ROOT/a.snapshot"; then
  pass "a second session changes nothing (the upgrade is idempotent)"
else
  fail "the second session rewrote settings.json again"
fi
case "$OUT2" in
  *"re-registered"*|*"was older than the binary"*) fail "the upgrade announces itself on every session" ;;
  *) pass "the upgrade is silent once there is nothing left to upgrade" ;;
esac
case "$OUT2" in
  *"this install does not subscribe to PostToolUseFailure"*)
    fail "the card still calls a subscribed install blind" ;;
  *) pass "once the subscription is live the blind-spot line is gone" ;;
esac

# ---------------------------------------------------------------------------
# CLAIM 8 — SELF-HEALING IS NOT SELF-INSTALLING. A machine where rabadon was
# never installed, or was deliberately removed, must come out untouched. This is
# the claim that keeps the whole mechanism defensible.
H2="$ROOT/b"; rm -rf "$H2"; mkdir -p "$H2/.claude" "$H2/.rabadon/spool" "$H2/proj/.git"
printf 'ref: refs/heads/main\n' > "$H2/proj/.git/HEAD"
printf '{"model":"opus","hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}\n' \
  > "$H2/.claude/settings.json"
cp "$H2/.claude/settings.json" "$ROOT/b.snapshot"
session_start "$H2" "$H2/.rabadon" "$H2/proj" s-up-3 >/dev/null
if cmp -s "$H2/.claude/settings.json" "$ROOT/b.snapshot"; then
  pass "a settings.json with no rabadon entries is left exactly as it was"
else
  fail "the upgrade INSTALLED rabadon into a machine that had not installed it"
fi

H3="$ROOT/c"; rm -rf "$H3"; mkdir -p "$H3/.rabadon/spool" "$H3/proj/.git"
printf 'ref: refs/heads/main\n' > "$H3/proj/.git/HEAD"
session_start "$H3" "$H3/.rabadon" "$H3/proj" s-up-4 >/dev/null
[ -f "$H3/.claude/settings.json" ] \
  && fail "the upgrade created a settings.json on a machine that had none" \
  || pass "a machine with no settings.json at all still has none"

# ---------------------------------------------------------------------------
# CLAIM 9 — THERE IS AN OFF SWITCH, and it is one environment variable rather
# than a fork. Anyone who wants their settings.json frozen gets to have that.
H4="$(mkfixture d)"
SNAP="$ROOT/d.snapshot"; cp "$H4/.claude/settings.json" "$SNAP"
printf '{"hook_event_name":"SessionStart","session_id":"s-up-5","cwd":"%s"}' "$H4/proj" \
  | env HOME="$H4" RABADON_DIR="$H4/.rabadon" RABADON_SELFHEAL=0 RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
if cmp -s "$H4/.claude/settings.json" "$SNAP"; then
  pass "RABADON_SELFHEAL=0 leaves the file alone"
else
  fail "the off switch does not switch it off"
fi

# ---------------------------------------------------------------------------
# CLAIM 10 — DOCTOR MAY NOT CERTIFY A BLIND INSTALL. This is the surface a user
# runs when they suspect something, and on 2026-08-29 it printed "global hooks
# healthy (1 rabadon command(s), all from this install)" and "all green" at the
# exact file that was missing the event. It asked whether the paths were dead or
# foreign; it never asked whether the EVENT SET was current.
H5="$(mkfixture e)"
DOUT="$(cd "$H5/proj" && env HOME="$H5" RABADON_DIR="$H5/.rabadon" node "$ROOTDIR/hooks/manage.mjs" doctor 2>&1)"
case "$DOUT" in
  *"global hooks healthy"*) fail "doctor certifies a stale install as healthy" ;;
  *) pass "doctor no longer calls a stale event set healthy" ;;
esac
case "$DOUT" in
  *PostToolUseFailure*) pass "doctor names the event that is missing" ;;
  *) fail "doctor does not say WHICH subscription is stale" ;;
esac

# and it must not invent a problem on a current install: same fixture, upgraded.
session_start "$H5" "$H5/.rabadon" "$H5/proj" s-up-6 >/dev/null
DOUT2="$(cd "$H5/proj" && env HOME="$H5" RABADON_DIR="$H5/.rabadon" node "$ROOTDIR/hooks/manage.mjs" doctor 2>&1)"
case "$DOUT2" in
  *"global hooks healthy"*) pass "doctor is green again once the install is current" ;;
  *) fail "doctor stays red on an install that is fully subscribed: $(printf '%s' "$DOUT2" | grep -i hook | head -2)" ;;
esac

printf 'hook_upgrade: %d passed, %d failed\n' "$PASSN" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
