#!/usr/bin/env bash
# moves_test.sh — R1 acceptance: the move record.
#
# WRITTEN BEFORE THE CODE, and red on the day it is written. That is the correct
# state: there is no move record yet. Turning it green is R1's job, and the only
# honest way to turn it green is to record moves.
#
# WHAT R1 IS, AND WHAT IT IS NOT.
# R1 records. It does not detect, it does not inject, it does not block. No
# signal is computed here and no exit code changes. The reason for that order is
# in KOSU-RABADON.md: a signal cannot be validated against a record that does not
# exist, and a false positive can never be traced back to its cause if the moves
# that produced it were never written down. So this file asserts two things and
# nothing else: that what gets written is right, and that writing it changed
# nothing a user can observe.
#
# THE STORAGE CONTRACT THIS FILE PINS DOWN.
# The record lives in the session's own file, <project>/.rabadon/sessions/*.json,
# under the key "moves": a JSON array, oldest first, each entry
#   {"seq":int,"ts":int,"tool":str,"path":str,"sig":str,
#    "raw":str,"claimed_rc":int,"err_sig":str,"suite":int}
# capped at MOVES_CAP entries, with "raw" carried only for the newest MOVES_RAW.
# `seq` counts every move the session ever made and NEVER resets — it is the
# only field that can still order two moves after eviction has thrown the older
# one away.
#
# `claimed_rc` is named claimed for the reason lastTestPass is: PostToolUse hands
# over a tool_response string, not an exit status. It is the session's claim
# about its own work, and the name has to say so wherever it is read.
#
# THE KILL SWITCH.  RABADON_MOVES=0 turns recording off. Claim 7 runs the same
# commands with it on and off and compares exit codes byte for byte. If R1 can
# change what the gate decides, R1 is not a recorder.

set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
# the export door the reader below goes through (R1.3)
export RB_AUDIT="${RABADON_AUDIT:-$HERE/rabadon-audit}"

MOVES_CAP=200
MOVES_RAW=50

FAIL=0
PASSN=0
pass() { printf '  ok   - %s\n' "$1"; PASSN=$((PASSN + 1)); }
fail() { printf '  FAIL - %s\n' "$1"; FAIL=1; }

[ -x "$GATE" ] || { printf 'moves: no gate binary at %s — run make first\n' "$GATE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'moves: python3 is required to read the session file\n' >&2; exit 1; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbmoves.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

export HOME="$ROOT/home"
export RABADON_DIR="$ROOT/home/.rabadon"
export RABADON_NOTIFY=0
mkdir -p "$RABADON_DIR/spool"
# enforce, not watch. Without this marker the gate refuses nothing and returns 0
# to everything, which would make claim 6's "identical exit codes" assertion
# true for a reason that has nothing to do with the move record.
touch "$RABADON_DIR/enabled"

PROJ="$ROOT/proj"
mkdir -p "$PROJ/.git"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"

jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

# ---------------------------------------------------------------------------
# drivers. Every one of them throws away stdout/stderr and returns the exit
# code, because an exit code is the only thing a hook's caller reads.

pre_bash() { # pre_bash <session> <command>
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$PROJ" "$(jstr "$2")" | "$GATE" >/dev/null 2>&1
  echo $?
}

pre_edit() { # pre_edit <session> <path> <new_string>
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":%s,"old_string":"","new_string":%s}}' \
    "$1" "$PROJ" "$(jstr "$2")" "$(jstr "$3")" | "$GATE" >/dev/null 2>&1
  echo $?
}

post_bash() { # post_bash <session> <command> <tool_response>
  printf '{"hook_event_name":"PostToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s},"tool_response":%s}' \
    "$1" "$PROJ" "$(jstr "$2")" "$(jstr "$3")" | "$GATE" >/dev/null 2>&1
  echo $?
}

# moves_json <session-hint> -> the "moves" array of the session file that has one
# Sessions are keyed by a sanitised id plus a hash, so the file is found by
# content rather than by reconstructing the key here — reimplementing
# session_key() in bash would be a second copy of a rule that can drift.
moves_py() { # moves_py <session-id> <python-expr over `m` (the moves list)>
  python3 - "$RABADON_DIR" "$PROJ" "$1" "$2" <<'PY'
import json, os, sys
rabdir, proj, sid, expr = sys.argv[1:5]
moves = []
for base in (os.path.join(proj, ".rabadon", "sessions"),
             os.path.join(rabdir, "sessions")):
    if not os.path.isdir(base):
        continue
    for fn in os.listdir(base):
        if not fn.endswith(".json"):
            continue
        try:
            with open(os.path.join(base, fn)) as fh:
                d = json.load(fh)
        except Exception:
            continue
        mv = d.get("moves")
        if isinstance(mv, list) and mv:
            moves.extend(mv)
    # R1.2: the record moved out of the session object into an append-only log
    # beside it. This is the READER learning where the record lives; not one
    # assertion below changed, and reports/R1.2/accept.sh proves that by
    # comparing the assertion texts against the previous commit.
    # R1.3: the record on disk is fixed-width binary so the hot path never parses
    # text. Reading it is what `rabadon audit --export` is for, and this reader
    # goes through exactly that door — the same one a human uses. Not one
    # assertion below changed; reports/R1.3/accept.sh proves that by comparing
    # assertion texts against the previous commit.
    import subprocess, glob
    exp = os.environ.get("RB_AUDIT", "")
    for base in (os.path.join(proj, ".rabadon", "sessions"),
                 os.path.join(rabdir, "sessions")):
        for fn in glob.glob(os.path.join(base, "*.moves.bin")):
            try:
                out = subprocess.run([exp, "--export", fn], capture_output=True, text=True).stdout
            except Exception:
                continue
            for line in out.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    moves.append(json.loads(line))
                except Exception:
                    pass
moves.sort(key=lambda x: x.get("seq", 0))
m = moves
try:
    print(eval(expr))
except Exception as e:
    print("ERR:%s" % e)
PY
}

sig_of_last() { moves_py "$1" 'm[-1]["sig"] if m else "NONE"'; }

fresh() { rm -rf "$PROJ/.rabadon" "$RABADON_DIR/sessions"; }

echo "moves: the session writes down what it did, and nothing else changes"

# ---------------------------------------------------------------------------
# CLAIM 1 — normalisation collapses spelling, not meaning.

fresh; pre_bash s-w1 'npm    run     build' >/dev/null
A="$(sig_of_last s-w1)"
fresh; pre_bash s-w2 'npm run build' >/dev/null
B="$(sig_of_last s-w2)"
if [ "$A" != "NONE" ] && [ "$A" = "$B" ]; then
  pass "the same command written with different whitespace has one signature"
else
  fail "whitespace changed the signature: '$A' vs '$B'"
fi

fresh; pre_bash s-d1 'npm run build' >/dev/null
C="$(sig_of_last s-d1)"
fresh; pre_bash s-d2 'npm run test' >/dev/null
D="$(sig_of_last s-d2)"
if [ "$C" != "NONE" ] && [ "$C" != "$D" ]; then
  pass "two different commands have two signatures"
else
  fail "two different commands collapsed to one signature: '$C'"
fi

# A scratch directory is a fresh name every run. If it survives into the
# signature, the SAME retry looks new every single time and repetition can never
# be seen — which is the entire failure this record exists to make visible.
fresh; pre_bash s-t1 'cat /tmp/abc123/x' >/dev/null
E="$(sig_of_last s-t1)"
fresh; pre_bash s-t2 'cat /tmp/def456/x' >/dev/null
F="$(sig_of_last s-t2)"
if [ "$E" != "NONE" ] && [ "$E" = "$F" ]; then
  pass "two runs of one command through different scratch dirs share a signature"
else
  fail "the scratch directory leaked into the signature: '$E' vs '$F'"
fi

# and the other direction: a number is not noise. A port IS the command.
fresh; pre_bash s-p1 'node server.js --port 3000' >/dev/null
G="$(sig_of_last s-p1)"
fresh; pre_bash s-p2 'node server.js --port 8080' >/dev/null
H="$(sig_of_last s-p2)"
if [ "$G" != "NONE" ] && [ "$G" != "$H" ]; then
  pass "two different ports are two different commands"
else
  fail "the port was normalised away: '$G' = '$H'"
fi

# ---------------------------------------------------------------------------
# CLAIM 2 — an Edit is recorded with the file it touched.

fresh; pre_edit s-e1 "$PROJ/src/app.js" 'const x = 1;' >/dev/null
P="$(moves_py s-e1 'm[-1]["path"] if m else "NONE"')"
T="$(moves_py s-e1 'm[-1]["tool"] if m else "NONE"')"
if [ "$T" = "Edit" ]; then
  pass "an Edit is recorded as an Edit"
else
  fail "the Edit's tool came back as '$T'"
fi
case "$P" in
  src/app.js) pass "the path is recorded relative to the project root" ;;
  "$PROJ"/*)  fail "the path is absolute ('$P') — it will not match across machines" ;;
  *)          fail "the Edit's path came back as '$P'" ;;
esac

# ---------------------------------------------------------------------------
# CLAIM 3 — PostToolUse lands on the move that PreToolUse opened.

fresh
pre_bash s-rc 'npm test' >/dev/null
SEQ_BEFORE="$(moves_py s-rc 'm[-1]["seq"] if m else -1')"
post_bash s-rc 'npm test' '1 failed, 3 passed' >/dev/null
SEQ_AFTER="$(moves_py s-rc 'm[-1]["seq"] if m else -1')"
if [ "$SEQ_BEFORE" = "$SEQ_AFTER" ] && [ "$SEQ_BEFORE" != "-1" ]; then
  pass "PostToolUse completes the move PreToolUse opened, it does not add a second one"
else
  fail "PostToolUse changed the newest seq from '$SEQ_BEFORE' to '$SEQ_AFTER'"
fi

RC="$(moves_py s-rc 'm[-1]["claimed_rc"] if m else "NONE"')"
if [ "$RC" != "NONE" ] && [ "$RC" != "-1" ]; then
  pass "the completed move carries a claimed_rc (it is a claim, and it is named one)"
else
  fail "claimed_rc is still unknown after PostToolUse: '$RC'"
fi

# a failing suite is a red suite, and the record has to say so or Law 3's
# contrast pair cannot be built later.
SU="$(moves_py s-rc 'm[-1]["suite"] if m else "NONE"')"
if [ "$SU" = "0" ]; then
  pass "a failing test run is recorded as a red suite"
else
  fail "the suite field after '1 failed, 3 passed' came back as '$SU', expected 0"
fi

fresh
pre_bash s-gr 'npm test' >/dev/null
# The green phrase matters. The classifier requires EVIDENCE of a pass — a
# counted zero or an explicit green phrase — and treats "the pattern did not
# match" as unknown rather than as green. '4 passed in 0.12s' says neither, and
# is left unknown on purpose. Asserting green on it here would have meant
# loosening the classifier to satisfy a test, which is the move this repo names
# and refuses. So the fixture speaks the classifier's language instead.
post_bash s-gr 'npm test' '12 passed, 0 failed' >/dev/null
SU2="$(moves_py s-gr 'm[-1]["suite"] if m else "NONE"')"
if [ "$SU2" = "1" ]; then
  pass "a passing test run is recorded as a green suite"
else
  fail "the suite field after '4 passed' came back as '$SU2', expected 1"
fi

# a command that is not a test run must leave the suite unknown rather than
# guessing green. Guessing green here is the exact false-green this tool exists
# to refuse.
fresh
pre_bash s-nt 'ls -la' >/dev/null
post_bash s-nt 'ls -la' 'total 8' >/dev/null
SU3="$(moves_py s-nt 'm[-1]["suite"] if m else "NONE"')"
if [ "$SU3" = "-1" ]; then
  pass "a command that is not a test run leaves the suite unknown, it does not guess green"
else
  fail "'ls -la' set the suite to '$SU3'"
fi

# ---------------------------------------------------------------------------
# CLAIM 4 — the error signature buckets the error, not the run.

fresh
pre_bash s-er 'node build.js' >/dev/null
post_bash s-er 'node build.js' 'File "/tmp/aaa/app.py", line 42, in main
TypeError: unsupported operand type(s)' >/dev/null
ES1="$(moves_py s-er 'm[-1]["err_sig"] if m else "NONE"')"
fresh
pre_bash s-er2 'node build.js' >/dev/null
post_bash s-er2 'node build.js' 'File "/tmp/bbb/app.py", line 97, in main
TypeError: unsupported operand type(s)' >/dev/null
ES2="$(moves_py s-er2 'm[-1]["err_sig"] if m else "NONE"')"
if [ "$ES1" != "NONE" ] && [ -n "$ES1" ] && [ "$ES1" = "$ES2" ]; then
  pass "one error reached through two paths and two line numbers has one err_sig"
else
  fail "the same error produced two signatures: '$ES1' vs '$ES2'"
fi

fresh
pre_bash s-ok 'ls' >/dev/null
post_bash s-ok 'ls' 'a.txt  b.txt' >/dev/null
ES3="$(moves_py s-ok 'm[-1]["err_sig"] if m else "NONE"')"
if [ "$ES3" = "" ]; then
  pass "output with no error in it carries no err_sig"
else
  fail "a clean run was given an err_sig: '$ES3'"
fi

# ---------------------------------------------------------------------------
# CLAIM 5 — the buffer is a ring, and seq outlives eviction.

fresh
N=$((MOVES_CAP + 15))
i=0
while [ "$i" -lt "$N" ]; do
  pre_bash s-ring "echo move-$i" >/dev/null
  i=$((i + 1))
done
LEN="$(moves_py s-ring 'len(m)')"
if [ "$LEN" = "$MOVES_CAP" ]; then
  pass "after $N moves the record holds exactly $MOVES_CAP"
else
  fail "after $N moves the record holds $LEN, expected $MOVES_CAP"
fi

LAST_SEQ="$(moves_py s-ring 'm[-1]["seq"]')"
if [ "$LAST_SEQ" = "$((N - 1))" ] || [ "$LAST_SEQ" = "$N" ]; then
  pass "seq kept counting past the cap (newest seq $LAST_SEQ after $N moves)"
else
  fail "seq restarted or skipped: newest is '$LAST_SEQ' after $N moves"
fi

# A positive integer, checked as one. `!= "0"` alone would be satisfied by the
# string "ERR:list index out of range", which is what an empty record returns —
# a vacuous pass in an acceptance test is the false green this product refuses.
FIRST_SEQ="$(moves_py s-ring 'm[0]["seq"]')"
case "$FIRST_SEQ" in
  ''|*[!0-9]*) fail "the oldest surviving seq is not a number: '$FIRST_SEQ' — the record is empty or malformed" ;;
  0)           fail "the oldest move is still seq 0 — nothing was evicted" ;;
  *)           pass "the oldest move was evicted, not the newest (oldest surviving seq $FIRST_SEQ)" ;;
esac

# Same trap: "0 moves carry raw text" satisfies `<= 50` while proving nothing.
# The record must be non-empty AND raw must be capped AND raw must actually be
# carried for the newest moves, or a passing number here means nothing.
RAWN="$(moves_py s-ring 'sum(1 for x in m if x.get("raw"))')"
case "$RAWN" in
  ''|*[!0-9]*) fail "raw-text count came back as '$RAWN'" ;;
  0)           fail "no move carries raw text at all — the diagnosis text of R4 has nothing to quote" ;;
  *) if [ "$RAWN" -le "$MOVES_RAW" ]; then
       pass "raw text is carried for $RAWN moves, at or under the cap of $MOVES_RAW"
     else
       fail "raw text is carried for $RAWN moves, cap is $MOVES_RAW — the session file will grow without bound"
     fi ;;
esac

# ---------------------------------------------------------------------------
# CLAIM 6 — recording is side-effect free.
#
# The commands below are chosen to cover both verdicts: one the gate lets
# through, one it refuses. A recorder that only preserves the allow path is not
# proven, because the refusal path is where the product's value and its risk
# both live.

echo "moves: recording changes nothing the caller can see"

ALLOW_CMD='echo hello'
DENY_CMD='git push --force origin main'

# First prove the fixture can actually refuse something. If this is 0, every
# comparison below is comparing two allow paths and claim 6 is worthless.
fresh
DENY_RC="$(pre_bash s-guard "$DENY_CMD")"
if [ "$DENY_RC" = "2" ]; then
  pass "the fixture is in enforce mode: the force-push is refused (exit 2)"
else
  fail "the fixture refuses nothing — '$DENY_CMD' exited $DENY_RC, expected 2. Claim 6 below cannot mean anything until this is 2."
fi

for cmd in "$ALLOW_CMD" "$DENY_CMD"; do
  fresh
  ON="$(pre_bash s-cmp "$cmd")"
  fresh
  OFF="$(RABADON_MOVES=0 pre_bash s-cmp "$cmd")"
  if [ "$ON" = "$OFF" ]; then
    pass "exit code is identical with the record on and off: '$cmd' -> $ON"
  else
    fail "the record changed the verdict for '$cmd': on=$ON off=$OFF"
  fi
done

# The kill switch is only meaningful if the switch's ON position writes. Assert
# both halves in one place so neither can pass on an empty record.
fresh
pre_bash s-on 'echo hi' >/dev/null
ON_LEN="$(moves_py s-on 'len(m)')"
fresh
RABADON_MOVES=0 pre_bash s-off 'echo hi' >/dev/null
OFF_LEN="$(moves_py s-off 'len(m)')"
if [ "$ON_LEN" = "1" ] && [ "$OFF_LEN" = "0" ]; then
  pass "RABADON_MOVES=0 writes no moves, and the default writes one"
else
  fail "kill switch is not proven: default wrote $ON_LEN move(s) (expected 1), RABADON_MOVES=0 wrote $OFF_LEN (expected 0)"
fi

# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  printf 'moves: %d passed, 0 failed\n' "$PASSN"
  exit 0
fi
printf 'moves: %d passed, and at least one failed\n' "$PASSN"
exit 1
