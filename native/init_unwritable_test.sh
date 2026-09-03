#!/bin/bash
# init_unwritable_test.sh — `rabadon init` when the disk says no.
#
# Measured 2026-09-03, before this suite: `rabadon init` in a directory the user
# cannot write printed a raw Node stack trace —
#
#     node:fs:1651
#     Error: EACCES: permission denied, mkdir '.../.rabadon'
#         at Object.mkdirSync (node:fs:1651:26)
#         at writeBaseline (file:///.../hooks/manage.mjs:55:6)
#     Node.js v26.5.0
#
# — and exited 1. Nothing in those nine lines tells the operator what happened
# to their project: is it guarded? half-guarded? The one fact that matters —
# NOTHING was installed, this tree is NOT protected — is the one fact the trace
# does not carry, and a stranger reading it concludes the tool is broken rather
# than that their directory is read-only. This is the same class the product
# refuses everywhere else: a screen that leaves the operator wrong about the
# state they are in.
#
# This suite is written on the AXIS, not on the incident. The incident was a
# read-only directory; the axis is "the guard could not be written", which a
# full disk, a root-owned checkout and a read-only mount all reach through the
# same call. Every case asserts the same three things, so a future path that
# fails differently fails here too:
#   1. exit 3 — init's existing "cannot guard yet" code, NOT 1 and NOT 0
#   2. no Node stack trace on any stream
#   3. the words that make it actionable: the path, and that nothing was installed
#
# Isolation: every case runs under its own mktemp tree with HOME and RABADON_DIR
# inside it. Nothing touches the real ~/.claude, ~/.cursor or ~/.rabadon.
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

command -v node >/dev/null 2>&1 || { echo "init_unwritable_test: needs node"; exit 1; }
[ -x "$ROOT/native/rabadon-gate" ] || {
  echo "init_unwritable_test: native/rabadon-gate is not built — init exits 3 before reaching"
  echo "                      the guard write, which would make every case below pass vacuously"
  echo "                      run: (cd $ROOT && make)"
  exit 1; }

# Running as root defeats the whole suite: root writes through mode 555, so
# every case would take the SUCCESS path and report green. Refuse, loudly.
if [ "$(id -u)" = "0" ]; then
  echo "init_unwritable_test: running as root — mode 555 does not stop root, so every"
  echo "                      case here would pass without exercising the failure path."
  exit 1
fi

TMP=$(mktemp -d /tmp/rabadon-initunwritable-test.XXXXXX)
# the read-only dirs must be made writable again or rm -rf cannot descend
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

echo "init on an unwritable tree: one actionable line, exit 3, no stack trace"

# a project with a HOME of its own; $1 names the case.
newproj() { d="$TMP/$1"; mkdir -p "$d/home" "$d/proj"; printf '%s' "$d"; }
rbinit() { ( cd "$1/proj" && HOME="$1/home" RABADON_DIR="$1/home/.rabadon" RABADON_NOTIFY=0 \
    node "$ROOT/hooks/manage.mjs" init --no-llm 2>&1 ); }

# The three assertions every unwritable case makes. $1 = case label,
# $2 = captured output, $3 = exit code, $4 = the path that must be named.
assert_clean_refusal() {
  local label="$1" out="$2" rc="$3" want_path="$4"

  [ "$rc" -eq 3 ] && pass "$label: exits 3 (init's \"cannot guard yet\" code)" \
    || { fail "$label: exited $rc, want 3; why: 1 is indistinguishable from a lint failure and 0 would claim an install that did not happen; run: chmod 555 a dir and run node hooks/manage.mjs init --no-llm in it"; printf '%s\n' "$out" | sed 's/^/    | /'; }

  # A stack trace is recognisable by any of these: node's internal frame paths,
  # an `at <fn> (...)` frame line, or the version footer it prints on a crash.
  if printf '%s' "$out" | grep -Eq '^[[:space:]]*at .*\(|node:internal/|node:fs:[0-9]|^Node\.js v'; then
    fail "$label: printed a Node stack trace; why: nine lines of internal frames tell the operator nothing they can act on and read as a broken tool rather than a read-only directory; run: node hooks/manage.mjs init --no-llm in an unwritable dir"
    printf '%s\n' "$out" | sed 's/^/    | /'
  else
    pass "$label: no Node stack trace on any stream"
  fi

  printf '%s' "$out" | grep -qF -- "$want_path" \
    && pass "$label: names the path it could not write" \
    || { fail "$label: never names $want_path; why: without the path the operator cannot tell WHICH directory to fix; run: node hooks/manage.mjs init --no-llm in an unwritable dir"; printf '%s\n' "$out" | sed 's/^/    | /'; }

  # the one fact the stack trace did not carry
  printf '%s' "$out" | grep -Eqi 'nothing was installed|not guarded|NOT guarded' \
    && pass "$label: says the project is NOT guarded" \
    || { fail "$label: never says the project is unguarded; why: this is the only fact that changes what the operator does next, and its absence is what the old stack trace was guilty of; run: node hooks/manage.mjs init --no-llm in an unwritable dir"; printf '%s\n' "$out" | sed 's/^/    | /'; }

  printf '%s' "$out" | grep -qi 'init' \
    && pass "$label: the message is attributed to rabadon init" \
    || fail "$label: the error does not name the command that produced it"

  # It must also name a NEXT COMMAND. "it broke" without "do this" is the same
  # dead end as the stack trace, one line shorter.
  printf '%s' "$out" | grep -Eqi 're-run|another directory|writable-dir|free some space|remount|permissions' \
    && pass "$label: names what to do next" \
    || { fail "$label: no next step; why: an error the operator cannot act on is a stack trace with better grammar; run: node hooks/manage.mjs init --no-llm in an unwritable dir"; printf '%s\n' "$out" | sed 's/^/    | /'; }
}

# ---- A. the project root is read-only: .rabadon cannot even be created ----
A=$(newproj a)
chmod 555 "$A/proj"
A_OUT=$(rbinit "$A"); A_RC=$?
assert_clean_refusal "read-only project root" "$A_OUT" "$A_RC" "$A/proj"
# and it left no half-install behind
[ ! -e "$A/proj/.claude" ] && pass "read-only project root: no .claude was written" \
  || fail "read-only project root: .claude exists; why: hooks pointing at a guard that was never written is worse than no install"

# ---- B. .rabadon exists but is read-only: mkdir succeeds, the WRITE fails ----
# A different syscall on the same axis. The old code crashed in mkdirSync; this
# case crashes one line later in writeFileSync, and must land identically.
B=$(newproj b)
mkdir -p "$B/proj/.rabadon"
chmod 555 "$B/proj/.rabadon"
B_OUT=$(rbinit "$B"); B_RC=$?
assert_clean_refusal "read-only .rabadon dir" "$B_OUT" "$B_RC" "$B/proj/.rabadon"
chmod u+w "$B/proj/.rabadon"
[ ! -e "$B/proj/.rabadon/guard.json" ] && pass "read-only .rabadon dir: no partial guard.json was left" \
  || fail "read-only .rabadon dir: a guard.json exists after a failed write"

# ---- C. THE OTHER SIDE OF THE AXIS: a writable tree still installs ----
# Without this, a fix that makes init refuse everything would pass A and B.
C=$(newproj c)
C_OUT=$(rbinit "$C"); C_RC=$?
[ "$C_RC" -eq 0 ] && pass "writable project: init still exits 0 (the refusal is not blanket)" \
  || { fail "writable project: init exited $C_RC on a perfectly good directory; why: a guard that refuses to install anywhere is not a fix; run: node hooks/manage.mjs init --no-llm in a fresh dir"; printf '%s\n' "$C_OUT" | sed 's/^/    | /'; }
[ -f "$C/proj/.rabadon/guard.json" ] && pass "writable project: the guard was actually written" \
  || fail "writable project: no .rabadon/guard.json; why: exit 0 without a guard on disk is the false green this product exists to refuse"

# ---- D. the DIAGNOSIS follows errno, and is never guessed ----
#
# A and B both fail with EACCES, so a message that hardcodes "not writable"
# passes them while lying to everybody else: the same catch is reached by a
# read-only mount (EROFS) and a full disk (ENOSPC), and telling somebody with a
# full disk to fix their permissions sends them to debug the wrong machine.
# ENOSPC cannot be provoked here without filling a real disk, so the mapping is
# exercised directly — same module, same function, a faked errno.
diag() {
  DIAGCODE="$1" node --input-type=module -e "
    import fs from 'node:fs';
    // the errno comes from the environment on purpose: process.argv is rewritten
    // below so manage.mjs sees its verb, which would clobber an errno parked there.
    const code = process.env.DIAGCODE;
    fs.mkdirSync = () => { const e = new Error('synthetic'); e.code = code; throw e; };
    fs.writeFileSync = () => { const e = new Error('synthetic'); e.code = code; throw e; };
    process.argv = [process.argv[0], 'manage', 'init', '--no-llm', process.env.DIAGDIR];
    await import('$ROOT/hooks/manage.mjs');
  " 2>&1
}
# The harness itself is held first. Every assertion below is "the output does NOT
# say permissions", which an EMPTY output passes. Measured while writing this
# suite: the errno was passed in argv, manage.mjs overwrote argv before the throw,
# every case ran with the errno 'manage' — and all six assertions were green.
DIAG_SELF=$(DIAGDIR="$TMP/selfcheck" diag "EROFS")
printf '%s' "$DIAG_SELF" | grep -q 'could not write the guard' \
  && pass "diagnosis harness: the faked errno really reaches init's error path" \
  || { fail "diagnosis harness: init's message never appeared, so every diagnosis case below would pass on empty output; why: a vacuous green here hides the whole errno table; run: the diag() helper in this file"; printf '%s\n' "$DIAG_SELF" | sed 's/^/    | /'; }
printf '%s' "$DIAG_SELF" | grep -q 'EROFS\|read-only filesystem' \
  && pass "diagnosis harness: the errno arrives intact (not clobbered by argv)" \
  || { fail "diagnosis harness: EROFS did not survive the call — the errno is being lost before the throw; why: this exact bug made six assertions pass vacuously; run: the diag() helper in this file"; printf '%s\n' "$DIAG_SELF" | sed 's/^/    | /'; }
E=$(newproj e)
export DIAGDIR="$E/proj"
for pair in "EROFS:read-only filesystem" "ENOSPC:disk is full" "EDQUOT:quota"; do
  code=${pair%%:*}; want=${pair#*:}
  OUT=$(DIAGDIR="$E/proj" diag "$code")
  printf '%s' "$OUT" | grep -qi -- "$want" \
    && pass "diagnosis: $code is reported as \"$want\", not as a permission problem" \
    || { fail "diagnosis: $code was not diagnosed as \"$want\"; why: the wrong cause sends the operator to fix the wrong thing; run: provoke $code during rabadon init"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }
  printf '%s' "$OUT" | grep -qi 'not writable by this user' \
    && fail "diagnosis: $code was blamed on permissions; why: this is the assumption the errno table exists to remove" \
    || pass "diagnosis: $code is not blamed on permissions"
done
# an errno the table has never heard of must describe the failure WITHOUT
# inventing a cause — silence about the reason beats a confident wrong reason.
OUT=$(DIAGDIR="$E/proj" diag "ENOTQUITEREAL")
printf '%s' "$OUT" | grep -Eqi 'not writable by this user|disk is full|read-only filesystem' \
  && { fail "diagnosis: an unknown errno was given one of the known causes; why: a fabricated diagnosis is worse than none"; printf '%s\n' "$OUT" | sed 's/^/    | /'; } \
  || pass "diagnosis: an unknown errno invents no cause"
printf '%s' "$OUT" | grep -q 'ENOTQUITEREAL' \
  && pass "diagnosis: an unknown errno is still reported verbatim" \
  || { fail "diagnosis: the unknown errno was swallowed; why: with no cause named, the raw code is the only thing left to search for"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }
unset DIAGDIR

# ---- E. isolation: nothing above reached the real home ----
REAL_TOUCHED=""
for p in "$HOME/.rabadon/config.json" "$HOME/.claude/settings.json" "$HOME/.cursor/hooks.json"; do
  [ -e "$p" ] && [ "$p" -nt "$TMP" ] && REAL_TOUCHED="$REAL_TOUCHED $p"
done
[ -z "$REAL_TOUCHED" ] && pass "no file under the real \$HOME was modified by this suite" \
  || fail "this suite modified real files:$REAL_TOUCHED"

echo "init on an unwritable tree: $ok ok / $bad fail"
[ "$bad" -eq 0 ]
