#!/usr/bin/env bash
# selfheal_path_test.sh — SELF-HEAL MAY NOT MOVE A WORKING BRAKE.
#
# WHAT WAS MEASURED, AND WHY THIS FILE EXISTS.
#
# The arbiter reproduced this deterministically on 2026-08-30
# (reports/kosu/KARARLAR.md · F3i · (3)): a rabadon-gate compiled inside a
# throwaway git worktree, given ONE SessionStart with a decoy $HOME whose
# ~/.claude/settings.json already pointed at the CANONICAL install, rewrote
# six hook entries — both rabadon-gate AND rabadon-drift — to the worktree's
# own absolute paths. The worktree was then removed and the operator's live
# brake pointed at a binary that did not exist. It cost her ten hours and it
# was silent for days.
#
# The mechanism, read out of the source rather than guessed:
#   gate.cpp:refresh_hook_subscriptions()  ->  <self_dir>/../hooks/refresh.mjs
#   hooks/refresh.mjs                      ->  installHooks(dir)
#   hooks/install.mjs                      ->  GATE_BIN = nativeBin(...) which
#                                              resolves from THIS FILE's own
#                                              location.
# So the path written is whichever binary happens to be running. An upgrade
# path that relocates the install every time somebody compiles a copy is not
# an upgrade path; it is a way to lose the guard.
#
# Two things this suite pins, and the second one is the one that was missing:
#
#   A. SELF-HEAL DOES NOT REPOINT A LIVE COMMAND. Upgrading an install is about
#      EVENTS, not about addresses: the six poisoned entries in the field each
#      needed a new event subscription and none of them needed a new path. So
#      an existing rabadon command whose binary EXISTS is carried through
#      verbatim, byte for byte, whoever is running.
#
#   B. IT NEVER WRITES AN EPHEMERAL PATH. In the one case where it must write
#      an address — the registered binary is gone, so the install is already
#      dead — it writes the canonical install path and only if that path is
#      durable. A path under a git worktree or under the temp directory is
#      refused OUT LOUD, because a hook that names a binary which will not
#      exist tomorrow is the silent death Promise 1 forbids.
#
# And the third defect the arbiter named, which is why CLAIM 5 exists:
# refresh.mjs:80 announced "repointed its entries" ONLY when no event had been
# added. In the field both happened at once, so the destructive half of the
# change was never printed. Every repoint is now announced with its OLD and NEW
# address, independent of what else happened.
#
# Everything below drives the REAL shipped binary against fixture homes. No
# claim reads the source of the thing it tests.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOTDIR="$(cd "$HERE/.." && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL - %s\n' "$1"; }

# NO SILENT SKIP: an unanswerable claim is red, not absent.
[ -x "$GATE" ] || { printf 'selfheal_path: no gate binary at %s — run make first\n' "$GATE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'selfheal_path: python3 is required\n' >&2; exit 1; }
command -v node    >/dev/null 2>&1 || { printf 'selfheal_path: node is required (the installer is JS)\n' >&2; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/rbshp.XXXXXX")"
trap 'rm -rf "$T"' EXIT
while [ "$T" != "${T//\/\///}" ]; do T="${T//\/\///}"; done
# MEASURED WHILE WRITING THIS SUITE, 2026-08-30, and it is a real property of
# the product, not a fixture detail: hooks/refresh.mjs runs its body only when
# `import.meta.url === file://${process.argv[1]}`. On macOS /tmp is a symlink to
# /private/tmp, so node's import.meta.url comes back resolved while argv[1] does
# not, the guard is false, and self-heal does NOTHING AT ALL. A fixture staged
# under the unresolved path would therefore have proved the defect absent by
# accident. Resolve once, here, so every arm below drives real code.
T="$(cd "$T" && pwd -P)"

echo "selfheal_path: an upgrade may not move a working install"

# ---------------------------------------------------------------------------
# THE FIXTURE. A home that self-heal genuinely WANTS to rewrite: it carries
# rabadon entries (self-heal refuses a home that has none, so an empty fixture
# would prove nothing) and it is missing PostToolUseFailure and the drift hook
# on Stop, so `changed` is true and the upgrade really runs. The command it
# registers is the caller's choice — that is the whole subject of this suite.
mkhome() { # mkhome <dir> <gate-command-to-register>
  rm -rf "$1"; mkdir -p "$1/.claude" "$1/proj/.git"
  printf 'ref: refs/heads/main\n' > "$1/proj/.git/HEAD"
  python3 -c '
import json, sys
home, gate = sys.argv[1], sys.argv[2]
ev  = lambda: [{"hooks": [{"type": "command", "command": gate}]}]
evm = lambda t: [{"matcher": "*", "hooks": [{"type": "command", "command": gate, "timeout": t}]}]
json.dump({"model": "opus",
           "hooks": {"SessionStart": ev(), "UserPromptSubmit": ev(), "Stop": ev(),
                     "PreToolUse": evm(960), "PostToolUse": evm(120)},
           "statusLine": {"type": "command", "command": "/somebody/elses/statusline.sh"}},
          open(home + "/.claude/settings.json", "w"), indent=2)' "$1" "$2"
}

# every rabadon command string in a settings file, one per line, sorted unique
rabadon_cmds() { # rabadon_cmds <settings.json>
  python3 -c '
import json, re, sys
try: d = json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
RE = re.compile(r"rabadon-(gate|drift)")
out = set()
for ev, arr in (d.get("hooks") or {}).items():
    for e in arr:
        for h in (e.get("hooks") or []):
            c = h.get("command") or ""
            if RE.search(c): out.add(c)
sl = ((d.get("statusLine") or {}).get("command") or "")
if RE.search(sl): out.add(sl)
print("\n".join(sorted(out)))' "$1"
}

# the DIRECTORIES those commands live in, sorted unique. This is the quantity
# the defect moved: an upgrade legitimately ADDS a command (rabadon-drift on
# Stop was missing from every pre-2026-08-29 install), so byte equality of the
# whole set is the wrong law and would forbid the repair. What may never change
# is WHERE they point.
rabadon_dirs() { # rabadon_dirs <settings.json>
  rabadon_cmds "$1" | while IFS= read -r c; do
    [ -n "$c" ] || continue
    p="${c%% *}"
    printf '%s\n' "$(dirname "$p")"
  done | sort -u
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

# one SessionStart from a chosen binary, against a chosen home. Fresh
# RABADON_DIR every time so the 6-hour refresh stamp never suppresses the run
# (the exact artefact that let F3g clear self-heal by mistake).
session_start() { # session_start <binary> <home> <tag>
  local rd="$T/rd-$3"; rm -rf "$rd"; mkdir -p "$rd"; : > "$rd/enabled"
  printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s"}' "$3" "$2/proj" \
    | env HOME="$2" RABADON_DIR="$rd" RABADON_NOTIFY=0 RABADON_JUDGE=0 "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# A SECOND INSTALL THAT LOOKS EXACTLY LIKE A GIT WORKTREE BUILD.
# Not a real `git worktree add`: this suite must run in a clean container with
# no network and must never touch the repository it is testing. What it
# reproduces is the SHAPE the arbiter measured — a package directory whose
# `.git` is a FILE (which is precisely how git marks a worktree), carrying its
# own hooks/ and its own copy of the binary.
WT="$T/wt"
mkdir -p "$WT/native" "$WT/hooks"
printf 'gitdir: /somewhere/.git/worktrees/wt\n' > "$WT/.git"
cp "$HERE/rabadon-gate" "$HERE/rabadon-drift" "$WT/native/"
cp "$ROOTDIR/hooks/refresh.mjs" "$ROOTDIR/hooks/install.mjs" "$WT/hooks/"
cp "$ROOTDIR/Makefile" "$WT/Makefile"
WT_GATE="$WT/native/rabadon-gate"
[ -x "$WT_GATE" ] || { echo "selfheal_path: could not stage the worktree copy" >&2; exit 1; }

# CLAIM 0 — the staged copy is genuinely a SECOND, DIFFERENT address running
# the same code. Without this every claim below could pass because nothing ran.
if [ "$WT_GATE" != "$GATE" ] && cmp -s "$WT_GATE" "$GATE"; then
  ok "the staged copy is the same binary at a different absolute path"
else
  bad "the staged copy is not a faithful second address of the shipped binary"
fi

# ---------------------------------------------------------------------------
# CLAIM 1 — THE TEN-HOUR DEFECT. Canonical install registered, worktree binary
# runs one SessionStart: the registered command must come out UNCHANGED.
H="$T/h1"; mkhome "$H" "$GATE"
BEFORE_DIRS="$(rabadon_dirs "$H/.claude/settings.json")"
OUT1="$(session_start "$WT_GATE" "$H" wt1)"
AFTER_CMDS="$(rabadon_cmds "$H/.claude/settings.json")"
AFTER_DIRS="$(rabadon_dirs "$H/.claude/settings.json")"
case "$AFTER_CMDS" in
  *"$WT/native/"*) bad "a worktree binary wrote its own path into the home settings — B2 reproduces" ;;
  *)               ok  "a worktree binary did not write its own path into the home settings" ;;
esac
if [ "$AFTER_DIRS" = "$BEFORE_DIRS" ]; then
  ok "the install still points at exactly the directory it pointed at before"
else
  bad "the install was relocated: [$(echo $BEFORE_DIRS)] -> [$(echo $AFTER_DIRS)]"
fi
case "$AFTER_CMDS" in
  *"$GATE"*) ok "the registered gate command survived byte for byte" ;;
  *) bad "the command the operator had registered is gone: [$AFTER_CMDS]" ;;
esac

# CLAIM 2 — AND IT STILL UPGRADED. A self-heal that protects the address by
# doing nothing at all is not a fix, it is a removal. The event set must still
# have caught up, and rabadon-drift must still have arrived on Stop.
AFTER_EV="$(events_with_rabadon "$H/.claude/settings.json")"
case " $AFTER_EV " in
  *" PostToolUseFailure "*) ok "the event subscription still caught up (PostToolUseFailure arrived)" ;;
  *) bad "nothing was upgraded at all: $AFTER_EV" ;;
esac
case "$AFTER_CMDS" in
  *rabadon-drift*) ok "rabadon-drift was registered too, at the canonical address" ;;
  *) bad "rabadon-drift never arrived — the upgrade half was lost with the repoint" ;;
esac
# and the drift binary it named has to be the canonical one, not the worktree's
case "$AFTER_CMDS" in
  *"$WT/native/rabadon-drift"*) bad "rabadon-drift was registered at the worktree address" ;;
  *) ok "no worktree address reached rabadon-drift either" ;;
esac

# CLAIM 3 — SOMEBODY ELSE'S THINGS SURVIVED. The live file this defect damaged
# is SHARED; its statusLine belongs to another tool.
if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("statusLine", {}).get("command") == "/somebody/elses/statusline.sh"
              and d.get("model") == "opus" else 1)' "$H/.claude/settings.json"; then
  ok "the foreign statusLine and unrelated keys were left alone"
else
  bad "self-heal took over a statusLine that was not rabadon's"
fi

# ---------------------------------------------------------------------------
# CLAIM 4 — THE CANONICAL BINARY BEHAVES THE SAME WAY. The law is "do not move
# a live install", not "worktrees are special": running from the canonical
# address must also leave the registered command alone.
H2="$T/h2"; mkhome "$H2" "$GATE"
B2D="$(rabadon_dirs "$H2/.claude/settings.json")"
session_start "$GATE" "$H2" c1 >/dev/null
A2="$(rabadon_cmds "$H2/.claude/settings.json")"
A2D="$(rabadon_dirs "$H2/.claude/settings.json")"
[ "$A2D" = "$B2D" ] \
  && ok "the canonical binary left the install where it was" \
  || bad "the canonical binary relocated the install: [$(echo $B2D)] -> [$(echo $A2D)]"
case "$A2" in
  *"$GATE"*) ok "the canonical binary left the registered gate command in place" ;;
  *)         bad "the canonical binary dropped the registered gate command: [$A2]" ;;
esac
case " $(events_with_rabadon "$H2/.claude/settings.json") " in
  *" PostToolUseFailure "*) ok "the canonical binary performed the event upgrade" ;;
  *) bad "the canonical binary upgraded nothing" ;;
esac

# ---------------------------------------------------------------------------
# CLAIM 5 — A REPOINT IS ANNOUNCED, WITH BOTH ADDRESSES. refresh.mjs:80 printed
# "repointed its entries" only when NO event had been added, so in the field —
# where both happened — the destructive half was never printed at all. A dead
# registered path is the one case where an address MUST be rewritten, so it is
# also the case that must speak.
#
# The claims below read the SELF-HEAL LINE ONLY, not the whole session card.
# The card's own blind-spot block already contains the words "PostToolUseFailure"
# and "refuse", so an assertion against the full screen passes without the
# self-heal path saying anything at all — measured while writing this file.
# The self-heal message is a BLOCK: a headline plus indented continuation lines
# (where the backup path and the next command live). Taking only the headline
# would let "names the command the human runs next" fail on a message that says
# it perfectly well one line down.
heal_line() {
  printf '%s\n' "$1" | awk '
    /^rabadon: this install/ { inblk = 1; print; next }
    inblk && /^        / { print; next }
    { inblk = 0 }'
}

H3="$T/h3"; mkhome "$H3" "/nonexistent/elsewhere/native/rabadon-gate"
OUT3="$(session_start "$GATE" "$H3" c2)"
L3="$(heal_line "$OUT3")"
A3="$(rabadon_cmds "$H3/.claude/settings.json")"
case "$A3" in
  *"$GATE"*) ok "a DEAD registered path is repaired to the running canonical install" ;;
  *)         bad "a dead registered path was left dead: [$A3]" ;;
esac
case "$L3" in
  *"/nonexistent/elsewhere/native/rabadon-gate"*) ok "the announcement names the OLD address" ;;
  *) bad "the address changed and the old one was never printed: [$L3]" ;;
esac
case "$L3" in
  *"$GATE"*) ok "the announcement names the NEW address" ;;
  *) bad "the address changed and the new one was never printed: [$L3]" ;;
esac
# and it says it BOTH ways at once: this run also added PostToolUseFailure, the
# exact combination that silenced the old message.
case "$L3" in
  *PostToolUseFailure*) ok "the same line reports the event upgrade as well — both halves, not one" ;;
  *) bad "the event upgrade went unmentioned when a repoint happened in the same run: [$L3]" ;;
esac

# ---------------------------------------------------------------------------
# CLAIM 6 — AN EPHEMERAL ADDRESS IS REFUSED, OUT LOUD. Dead registered path AND
# the only binary available is a worktree copy: writing it would hand the user a
# hook that names a file which will not exist tomorrow. Refuse, and say why.
H4="$T/h4"; mkhome "$H4" "/nonexistent/elsewhere/native/rabadon-gate"
OUT4="$(session_start "$WT_GATE" "$H4" wt2)"
L4="$(heal_line "$OUT4")"
A4="$(rabadon_cmds "$H4/.claude/settings.json")"
case "$A4" in
  *"$WT/native/"*) bad "a worktree address was written into a settings file — the ten-hour defect, second door" ;;
  *)               ok  "no worktree address was written even when the registered one was dead" ;;
esac
case "$L4" in
  *"will NOT repoint"*) ok "the refusal is spoken, not silent (Promise 1)" ;;
  *) bad "self-heal declined to repair and said nothing about it: [$L4]" ;;
esac
case "$L4" in
  *"$WT"*) ok "the refusal names the address it refused to write" ;;
  *) bad "the refusal never says which address was rejected: [$L4]" ;;
esac
case "$L4" in
  *"rabadon init"*) ok "the refusal names the one command the human runs next (CLAUDE.md quality bar)" ;;
  *) bad "the refusal leaves the user with a dead install and no next step: [$L4]" ;;
esac

# ---------------------------------------------------------------------------
# CLAIM 7 — WHAT IT WRITES, IT VERIFIES. A hook naming a binary that is not
# there dies without a word, which is worse than being stale. Every rabadon
# command left in every settings file this suite touched has to resolve to a
# file that exists.
missing=0
for f in "$H/.claude/settings.json" "$H2/.claude/settings.json" \
         "$H3/.claude/settings.json"; do
  # H4 is deliberately absent: its registered path was already dead and
  # self-heal correctly refused to invent a durable replacement it does not
  # have. That home is repaired by `rabadon init`, which is what its refusal
  # line says. Asserting it here would push self-heal into writing the
  # ephemeral path this suite exists to forbid.
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    p="${c%% *}"; p="${p%\"}"; p="${p#\"}"
    [ -e "$p" ] || { missing=$((missing+1)); printf '       dead: %s (in %s)\n' "$p" "$f"; }
  done <<EOF
$(rabadon_cmds "$f")
EOF
done
[ "$missing" = "0" ] \
  && ok "every rabadon command self-heal left behind names a binary that exists" \
  || bad "$missing rabadon command(s) name a binary that is not there"

# ---------------------------------------------------------------------------
# CLAIM 8 — STILL IDEMPOTENT. The protection must not turn into a rewrite on
# every session; that would be a permanent cost bought with a one-time fix.
cp "$H/.claude/settings.json" "$T/h1.snap"
session_start "$WT_GATE" "$H" wt3 >/dev/null
cmp -s "$H/.claude/settings.json" "$T/h1.snap" \
  && ok "a second session from the same copy changes nothing" \
  || bad "the second session rewrote settings.json again"

# ---------------------------------------------------------------------------
# CLAIM 9 — NOT-DURABLE IS A FAMILY, NOT A SHAPE.
#
# WHAT WAS MEASURED, 2026-08-30 (reports/kosu/KARARLAR.md · F3j · AÇIK SORU 2).
# The arbiter took CLAIM 6's protection, staged the running copy under
# /private/tmp instead of under a worktree, and self-heal REPOINTED — it wrote
# an address into a settings file that macOS sweeps. Root cause: notDurable()
# tested exactly one string, os.tmpdir(), which on this machine resolves to
# /var/folders/<...>/T. So /tmp, /private/tmp and /var/tmp — the directories the
# system actually empties — were all outside the check. That is the same class
# of damage as the ten-hour defect, through a second door.
#
# CLAIM 6 could not have caught it: its worktree fixture lives under $TMPDIR, so
# BOTH arms fired at once and neither was isolated. Every fixture below is
# deliberately staged with NO .git at all, so the worktree arm cannot answer for
# the durability arm.
#
# THE LAW THIS PINS IS THE PROPERTY, NOT THE LIST. A system scratch directory
# marks itself in the filesystem — world-writable plus the sticky bit, mode
# 1777 — and no install directory is ever that. The roots below are discovered
# by MEASURING that property on the machine the suite runs on, not by reciting
# names, and one of them is built by this suite specifically so that it appears
# in no list anywhere in the product. A protection that only holds for the roots
# somebody remembered to type is a shape; this one has to hold for a root it has
# never seen.
#
# CLAIM 9d is the lock that keeps the fix honest: a DURABLE copy must still be
# accepted. Without it, "refuse everything" would pass every assertion above
# while quietly deleting the repair CLAIM 5 exists for.

DUR="$(mktemp -d "$HOME/.rbshp-dur.XXXXXX")"   # durable: $HOME is not swept
STAGED=""                                       # every dir created outside $T
trap 'rm -rf "$T" "$DUR"; for d in $STAGED; do rm -rf "$d"; done' EXIT

# A package directory that is a faithful second address of the shipped install:
# native/ + hooks/, and NO .git, so only the durability arm can speak.
stage_pkg() { # stage_pkg <dir>  -> prints the gate path
  rm -rf "$1"; mkdir -p "$1/native" "$1/hooks"
  cp "$HERE/rabadon-gate" "$HERE/rabadon-drift" "$1/native/"
  cp "$ROOTDIR/hooks/refresh.mjs" "$ROOTDIR/hooks/install.mjs" "$1/hooks/"
  printf '%s/native/rabadon-gate\n' "$1"
}

# The scratch roots THIS MACHINE presents, measured. Nothing is assumed to
# exist: a platform without /var/tmp simply contributes fewer roots, and the
# count assertion below is what keeps that from becoming a silent skip.
SYS_SCRATCH="$(python3 -c '
import os
seen, out = set(), []
for c in ("/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp", "/dev/shm"):
    try: rp = os.path.realpath(c)
    except OSError: continue
    if rp in seen or not os.path.isdir(rp): continue
    try: m = os.stat(rp).st_mode
    except OSError: continue
    if (m & 0o1000) and (m & 0o0002):   # sticky AND world-writable
        seen.add(rp); out.append(rp)
print("\n".join(out))')"
N_SCRATCH="$(printf '%s' "$SYS_SCRATCH" | grep -c . || true)"

if [ "$N_SCRATCH" -ge 2 ]; then
  ok "the machine presents $N_SCRATCH world-writable sticky scratch root(s) to test against"
else
  bad "found $N_SCRATCH sticky scratch roots — this suite cannot prove the family on this platform"
fi

# A scratch root THE PRODUCT HAS NEVER HEARD OF: same filesystem property, a
# name that appears in no source file, and located under $HOME so that no
# ancestor of it is a temp directory. If the fix is a list, this one gets past.
UNLISTED="$DUR/nowhere-named-this"
mkdir -p "$UNLISTED" && chmod 1777 "$UNLISTED"
if python3 -c '
import os, sys
m = os.stat(sys.argv[1]).st_mode
sys.exit(0 if (m & 0o1000) and (m & 0o0002) else 1)' "$UNLISTED"; then
  ok "an unlisted scratch root was constructed under \$HOME with the same 1777 property"
else
  bad "could not construct the unlisted scratch root — its arm below proves nothing"
fi

# --- every scratch root refuses, out loud, one assertion each ----------------
i=0
for R in $SYS_SCRATCH "$UNLISTED"; do
  [ -n "$R" ] || continue
  i=$((i+1))
  PKG="$R/rbshp-pkg-$$-$i"
  STAGED="$STAGED $PKG"
  G="$(stage_pkg "$PKG")"
  [ -x "$G" ] || { bad "could not stage a copy under $R"; continue; }
  HN="$T/h9-$i"; mkhome "$HN" "/nonexistent/elsewhere/native/rabadon-gate"
  O="$(session_start "$G" "$HN" "s9$i")"
  L="$(heal_line "$O")"
  A="$(rabadon_cmds "$HN/.claude/settings.json")"
  case "$A" in
    *"$PKG"*) bad "an address under $R was written into settings — the swept-root door is open" ;;
    *)        ok  "no address under $R was written into settings" ;;
  esac
  case "$L" in
    *"will NOT repoint"*) ok "the refusal for $R is spoken, not silent (Promise 1)" ;;
    *) bad "self-heal declined to repoint from $R and said nothing: [$L]" ;;
  esac
done

# --- THE LOCK. A DURABLE copy is still accepted. ----------------------------
DPKG="$DUR/durable-install"
DG="$(stage_pkg "$DPKG")"
H9="$T/h9d"; mkhome "$H9" "/nonexistent/elsewhere/native/rabadon-gate"
O9="$(session_start "$DG" "$H9" s9d)"
L9="$(heal_line "$O9")"
A9="$(rabadon_cmds "$H9/.claude/settings.json")"
case "$A9" in
  *"$DPKG/native/rabadon-gate"*) ok "a DURABLE copy outside the repo IS accepted — the repair still works" ;;
  *) bad "a durable install was refused: self-heal now protects the address by deleting the fix: [$A9]" ;;
esac
case "$L9" in
  *"will NOT repoint"*) bad "a durable address was announced as refused: [$L9]" ;;
  *) ok "no refusal was printed for the durable copy" ;;
esac

printf 'selfheal_path: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
