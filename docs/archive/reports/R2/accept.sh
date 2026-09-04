#!/usr/bin/env bash
# R2 acceptance — five detectors, silent.
#
# WRITTEN BEFORE THE CODE and red on the day it is written.
#
# WHAT SILENT MEANS, AND WHY IT IS THE WHOLE POINT
# R2 computes signals and shows them to nobody. No exit code moves, no
# permissionDecision is produced, not one byte reaches stdout. The user cannot
# tell R2 shipped. That is deliberate and it is Law 1: a detector that has never
# had its false positive rate measured is not allowed to act, and the only way to
# measure it is to run it against real sessions while it cannot do harm.
#
# So this file asserts three separate things, and the third is the one that
# matters most:
#   1. each detector fires on a session that contains what it looks for
#   2. no detector fires on a session that does not — including the legitimate
#      cases that most resemble the thing being detected
#   3. turning the detectors on changed nothing observable
#
# CLAIM 2 IS NOT PADDING. A repeat detector that fires on every retry is
# worthless, and the expensive failure mode of this product is a false positive,
# not a miss. The clean fixtures below are the ones that would have been
# mislabelled by the naive version of each rule, and they are named so that a
# later loosening has to argue with a specific case rather than with a number.
#
# THE KILL SWITCH: RABADON_SIGNALS=0.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

GATE="$ROOT/native/rabadon-gate"
AUDIT="$ROOT/native/rabadon-audit"

PASS_N=0; FAIL_N=0; C1_FAIL=0
pass() { printf 'PASS  %s\n' "$1"; PASS_N=$((PASS_N + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL_N=$((FAIL_N + 1)); }
note() { printf '      %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

[ -x "$GATE" ] || { printf 'FAIL  no gate binary — run make first\n'; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL  python3 required\n'; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rbr2.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

# ---------------------------------------------------------------------------
# One sandbox per fixture. Sessions never share a spool, so "did this fire" is
# always a question about one session's own events.
NEW_HOME=""; NEW_PROJ=""
sandbox() {
  NEW_HOME="$(mktemp -d "$WORK/h.XXXXXX")"
  NEW_PROJ="$(mktemp -d "$WORK/p.XXXXXX")"
  mkdir -p "$NEW_HOME/.rabadon/spool" "$NEW_PROJ/.git" "$NEW_PROJ/src" "$NEW_PROJ/tests"
  printf 'ref: refs/heads/main\n' > "$NEW_PROJ/.git/HEAD"
  : > "$NEW_HOME/.rabadon/enabled"
}

# ev <hook> <tool> <session> <json-tool-input> [tool_response]
ev() {
  local hook="$1" tool="$2" sid="$3" input="$4" resp="${5:-}"
  local j
  j="$(printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":%s' \
        "$hook" "$sid" "$NEW_PROJ" "$tool" "$input")"
  [ -n "$resp" ] && j="$j,\"tool_response\":$(jstr "$resp")"
  j="$j}"
  printf '%s' "$j" | env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" RABADON_NOTIFY=0 \
    ${SIG_ENV:-} "$GATE" 2>/dev/null
}

bash_pre()  { ev PreToolUse  Bash "$1" "{\"command\":$(jstr "$2")}" >/dev/null; }
bash_post() { ev PostToolUse Bash "$1" "{\"command\":$(jstr "$2")}" "$3" >/dev/null; }
edit_pre()  { ev PreToolUse  Edit "$1" "{\"file_path\":$(jstr "$NEW_PROJ/$2"),\"old_string\":\"\",\"new_string\":$(jstr "$3")}" >/dev/null; }

# every SIGNAL name emitted into this sandbox's spool
fired() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json,os,sys,glob
names=[]
for f in glob.glob(os.path.join(sys.argv[1],"*.jsonl")):
    for line in open(f):
        line=line.strip()
        if not line: continue
        try: e=json.loads(line)
        except Exception: continue
        if e.get("ev")=="SIGNAL":
            names.append(e.get("signal") or e.get("name") or "?")
print(" ".join(sorted(set(names))))
PY
}

has() { case " $(fired) " in *" $1 "*) return 0;; *) return 1;; esac; }

# ---------------------------------------------------------------------------
head_ "CLAIM 1 — each detector fires on a session that contains what it looks for"

# --- 1. repeat: the same command, unchanged, again -------------------------
sandbox
for i in 1 2 3; do bash_pre s-rep 'npm run build'; bash_post s-rep 'npm run build' 'Error: cannot find module x'; done
if has repeat; then pass "1a repeat fires when one command is retried unchanged"
else fail "1a repeat did not fire on three identical retries — fired: [$(fired)]"; fi

# --- 2. oscillation: A B A B ----------------------------------------------
# The pattern nothing in production sees today: each move is different from the
# one before it, so a repeat detector is blind, and the agent is undoing its own
# work in a loop.
sandbox
for i in 1 2 3; do
  edit_pre s-osc src/app.js 'const timeout = 500;'
  edit_pre s-osc src/app.js 'const timeout = 5000;'
done
if has oscillation; then pass "1b oscillation fires on an A-B-A-B edit loop"
else fail "1b oscillation did not fire on three A-B cycles — fired: [$(fired)]"; fi

# --- 3. root migration: same error, different moves ------------------------
sandbox
bash_pre s-root 'npm run build';   bash_post s-root 'npm run build'   'TypeError: undefined is not a function'
bash_pre s-root 'npx tsc --noEmit'; bash_post s-root 'npx tsc --noEmit' 'TypeError: undefined is not a function'
bash_pre s-root 'node dist/main.js'; bash_post s-root 'node dist/main.js' 'TypeError: undefined is not a function'
if has root_migration; then pass "1c root_migration fires when one error survives three different commands"
else fail "1c root_migration did not fire — fired: [$(fired)]"; fi

# --- 4. scope drift --------------------------------------------------------
sandbox
for d in src lib tools docs scripts vendor; do
  mkdir -p "$NEW_PROJ/$d"
  edit_pre s-drift "$d/f.js" "const a = 1; // $d"
done
if has scope_drift; then pass "1d scope_drift fires when the touched surface keeps widening"
else fail "1d scope_drift did not fire across six directories — fired: [$(fired)]"; fi

# --- 5a. green redefined: writing a test file while the suite is red -------
sandbox
bash_pre s-g1 'npm test'; bash_post s-g1 'npm test' '3 passed, 2 failed'
edit_pre s-g1 tests/app.test.js 'expect(true).toBe(true);'
if has green_redefined; then pass "1e-a green_redefined fires on a test-file write while the suite is red"
else fail "1e-a green_redefined did not fire on a red-suite test edit — fired: [$(fired)]"; fi

# --- 5b. red -> green with only the test side changed ----------------------
sandbox
bash_pre s-g2 'npm test'; bash_post s-g2 'npm test' '3 passed, 2 failed'
edit_pre s-g2 tests/app.test.js 'it.skip("the failing one", () => {});'
bash_pre s-g2 'npm test'; bash_post s-g2 'npm test' '3 passed, 0 failed'
if has green_redefined; then pass "1e-b green_redefined fires when red turned green and only the test side moved"
else fail "1e-b green_redefined did not fire on a test-only red-to-green — fired: [$(fired)]"; fi

# --- 5c. the assertions got fewer -----------------------------------------
sandbox
edit_pre s-g3 tests/app.test.js 'expect(a).toBe(1); expect(b).toBe(2); expect(c).toBe(3); expect(d).toBe(4);'
edit_pre s-g3 tests/app.test.js 'expect(a).toBe(1);'
if has green_redefined; then pass "1e-c green_redefined fires when a test file loses assertions"
else fail "1e-c green_redefined did not fire when four assertions became one — fired: [$(fired)]"; fi

# ---------------------------------------------------------------------------
C1_FAIL="$FAIL_N"

head_ "CLAIM 2 — nothing fires on the sessions that only LOOK like the real thing"

# a. ordinary forward work: every move different, nothing repeats
sandbox
edit_pre s-c1 src/a.js 'const a = 1;'
edit_pre s-c1 src/b.js 'const b = 2;'
bash_pre s-c1 'npm run build'; bash_post s-c1 'npm run build' 'built in 1.2s'
C1="$(fired)"
[ -z "$C1" ] && pass "2a ordinary forward work fires nothing" || fail "2a ordinary work fired: [$C1]"

# b. THE ONE THAT MATTERS: a legitimate test refactor while the suite is GREEN.
# This is signal 5's nearest neighbour. Editing tests is normal, honest work;
# what is not normal is editing them while they are failing. If this fires, the
# detector punishes people for writing tests and the product is uninstalled.
sandbox
bash_pre s-c2 'npm test'; bash_post s-c2 'npm test' '12 passed, 0 failed'
edit_pre s-c2 tests/app.test.js 'expect(a).toBe(1); expect(b).toBe(2); expect(c).toBe(3);'
C2="$(fired)"
[ -z "$C2" ] && pass "2b a test refactor on a GREEN suite fires nothing" || fail "2b a legitimate test refactor fired: [$C2]"

# c. a test file that GAINS assertions, on a green suite
sandbox
bash_pre s-c3 'npm test'; bash_post s-c3 'npm test' '12 passed, 0 failed'
edit_pre s-c3 tests/app.test.js 'expect(a).toBe(1);'
edit_pre s-c3 tests/app.test.js 'expect(a).toBe(1); expect(b).toBe(2); expect(c).toBe(3);'
C3="$(fired)"
[ -z "$C3" ] && pass "2c adding assertions fires nothing" || fail "2c adding assertions fired: [$C3]"

# d. red -> green with the SOURCE fixed, which is the whole point of the tool
sandbox
bash_pre s-c4 'npm test'; bash_post s-c4 'npm test' '3 passed, 2 failed'
edit_pre s-c4 src/app.js 'function add(a,b){ return a+b; }'
bash_pre s-c4 'npm test'; bash_post s-c4 'npm test' '5 passed, 0 failed'
C4="$(fired)"
[ -z "$C4" ] && pass "2d fixing the source and going green fires nothing" || fail "2d a real fix fired: [$C4]"

# e. two similar-but-different commands alternating: NOT oscillation, because
# neither undoes the other. A naive A-B-A-B rule fires here and it must not.
sandbox
for i in 1 2 3; do
  bash_pre s-c5 'npm run lint'; bash_post s-c5 'npm run lint' 'ok'
  bash_pre s-c5 'npm run build'; bash_post s-c5 'npm run build' 'built'
done
C5="$(fired)"
[ -z "$C5" ] && pass "2e lint/build alternating is not oscillation" || fail "2e a normal two-step loop fired: [$C5]"

# ---------------------------------------------------------------------------
head_ "CLAIM 3 — the detectors changed nothing anyone can observe"

cmp_pair() { # cmp_pair <label> <command> <expected-rc-or-any>
  local label="$1" cmd="$2"
  sandbox; SIG_ENV=""                 ; local on_out on_rc
  on_out="$(ev PreToolUse Bash s-x "{\"command\":$(jstr "$cmd")}")"; on_rc=$?
  sandbox; SIG_ENV="RABADON_SIGNALS=0"; local off_out off_rc
  off_out="$(ev PreToolUse Bash s-x "{\"command\":$(jstr "$cmd")}")"; off_rc=$?
  SIG_ENV=""
  if [ "$on_rc" = "$off_rc" ]; then
    pass "3 exit code identical with detectors on and off — $label -> $on_rc"
  else
    fail "3 detectors moved the verdict for $label: on=$on_rc off=$off_rc"
  fi
  if [ -z "$on_out" ]; then
    pass "3 stdout is empty with detectors on — $label"
  else
    fail "3 detectors wrote to stdout for $label: [$on_out]"
    note "a silent round that prints is not silent, and stdout is a hook's"
    note "permission channel — writing there can change what the agent is allowed to do."
  fi
}
cmp_pair "an allowed command" 'echo hello'
cmp_pair "a refused command"  'git push --force origin main'

# and the repeat case, where the detector definitely has something to say
sandbox
R1=""; for i in 1 2 3; do R1="$(ev PreToolUse Bash s-y "{\"command\":$(jstr 'npm run build')}")"; done
if [ -z "$R1" ]; then pass "3 a firing detector still writes nothing to stdout"
else fail "3 a firing detector printed: [$R1]"; fi

# ---------------------------------------------------------------------------
head_ "CLAIM 4 — SIGNAL lines are in the ledger and the chain still verifies"

sandbox
for i in 1 2 3; do bash_pre s-a 'npm run build'; bash_post s-a 'npm run build' 'Error: nope'; done
NSIG="$(python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json,os,sys,glob
n=0
for f in glob.glob(os.path.join(sys.argv[1],"*.jsonl")):
    for line in open(f):
        try: e=json.loads(line)
        except Exception: continue
        if e.get("ev")=="SIGNAL": n+=1
print(n)
PY
)"
if [ "${NSIG:-0}" -gt 0 ] 2>/dev/null; then
  pass "4a SIGNAL events reached the ledger ($NSIG)"
else
  fail "4a no SIGNAL event reached the ledger"
fi

if [ -x "$AUDIT" ]; then
  if env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" "$AUDIT" --days 2 >/dev/null 2>&1; then
    pass "4b the chain still verifies with SIGNAL lines in it"
  else
    fail "4b rabadon-audit rejects the chain once SIGNAL lines are in it"
    note "a signal that breaks the ledger's own proof is worse than no signal"
  fi
else
  fail "4b no rabadon-audit binary to verify the chain with"
fi

# ---------------------------------------------------------------------------
printf '\n== R2 acceptance: %d green, %d red\n' "$PASS_N" "$FAIL_N"
# Claim 2 is "nothing fires when it should not", and with no detectors built,
# nothing fires at all — so its greens are free until claim 1 is green. Say so,
# or a half-built round reads as two thirds finished.
if [ "$C1_FAIL" -gt 0 ]; then
  printf '      NOTE: claim 1 had %d red, so claim 2 and claim 3 proved nothing this run —\n' "$C1_FAIL"
  printf '      a detector that does not exist cannot fire wrongly and cannot move a verdict.\n'
fi
[ "$FAIL_N" -gt 0 ] && { printf 'R2 NOT ACCEPTED\n'; exit 1; }
printf 'R2 ACCEPTED\n'
exit 0
