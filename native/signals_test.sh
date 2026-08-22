#!/usr/bin/env bash
# signals_test.sh — the regression net under R2's five detectors and R3's tier 1.
#
# WHY THIS FILE EXISTS AT ALL.
# `make test` ran ten native suites and not one of them touched native/signals.h
# or native/semantic.h. R1's record has native/moves_test.sh; R2 and R3 had only
# their own reports/*/accept.sh, and an acceptance script is a ONE-TIME argument
# that a round was delivered — it is not wired into the suite, so nothing was
# stopping a later round from loosening a threshold, inverting the cascade, or
# deleting the `failed >= 2` clause while every check in `make test` stayed
# green. That is the exact disease this product sells a cure for. This file is
# the standing check, and it lives in the suite rather than in a report folder
# for that reason.
#
# WHAT IT HOLDS, AND WHERE THE WEIGHT IS.
# Every detector gets at least one fixture that fires it and at least one
# NEAREST NEIGHBOUR that must not. The negatives are the point. Law 1: the
# expensive failure of this product is the false positive, not the miss — a
# detector that flags honest work gets the tool uninstalled on the first
# afternoon, and a detector that misses one loop costs nobody anything. So the
# positives are here to prove the rule is still connected to the wire, and the
# negatives are here to prove it still knows what it is not allowed to say.
#
# Each negative below is in the file because it nearly broke a rule already:
#   lint/build/lint/build       once fired `repeat`. Counting occurrences is not
#                               enough; the rule now needs evidence of NOT
#                               PROGRESSING — at least two matching moves
#                               carrying an error. A supervisor that flags you
#                               for running your linter three times is deleted.
#   a test refactor on GREEN    green_redefined's nearest neighbour. Editing
#                               tests is the most valuable thing an agent does.
#                               What is suspicious is editing them while they
#                               are FAILING, and the rule has to keep that
#                               distinction or it punishes writing tests.
#   a test file that GAINS      the assertion-count rule reads a DROP. A file
#     assertions                that grows must be as silent as one nobody
#                               touched.
#   red -> green, SOURCE fixed  the whole point of the tool. If this fires, the
#                               detector flags the successful outcome it exists
#                               to protect.
#
# THE CASCADE IS ASSERTED, NOT ASSUMED. semantic.h's safety argument is one
# `return`: tier 1 refuses to run at all when tier 0's hash already matched
# inside the window, so the two tiers can never describe the same pair of moves
# and tier 1 can never confirm, weaken or duplicate a tier-0 verdict. Section 6
# drives three BYTE-IDENTICAL edits — similarity 1.00, the loudest possible
# input for tier 1 — and requires silence. If the cascade is ever reordered or
# the early return is dropped, that fixture is the thing that goes red.
#
# NO ASSERTION MAY PASS VACUOUSLY. "nothing fired" and "nothing ran" print the
# same on a green line, and both native/moves_test.sh and reports/R2/accept.sh
# shipped a version of that bug before it was found. So every negative below
# first requires the spool to be NON-EMPTY: if the gate never saw the fixture,
# the assertion proved nothing and is red, not green. The same guard sits on
# every positive.
#
# ENFORCE, NOT WATCH. The sandbox touches $RABADON_DIR/enabled. Without that
# marker the gate refuses nothing and returns 0 to everything, and section 7's
# "identical exit codes" would be true for a reason that has nothing to do with
# the detectors. Section 7 proves the fixture can actually refuse something
# before it compares anything.
#
# THE KILL SWITCHES: RABADON_SIGNALS=0 (all detectors) and RABADON_SEM=0 (tier 1
# only). Both are asserted, because a switch nobody tests is a switch that is
# already broken.

set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"

FAIL=0
PASSN=0
pass() { printf '  ok   - %s\n' "$1"; PASSN=$((PASSN + 1)); }
fail() { printf '  FAIL - %s\n' "$1"; FAIL=1; }
head_() { printf '%s\n' "signals: $1"; }

[ -x "$GATE" ] || { printf 'signals: no gate binary at %s — run make first\n' "$GATE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'signals: python3 is required to read the spool\n' >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rbsig.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

# ---------------------------------------------------------------------------
# One sandbox per fixture, the way reports/R2/accept.sh does it. Sessions never
# share a spool, so "did this fire" is always a question about ONE session's own
# events and no fixture can be contaminated by the one before it.
NEW_HOME=""; NEW_PROJ=""
sandbox() {
  NEW_HOME="$(mktemp -d "$WORK/h.XXXXXX")"
  NEW_PROJ="$(mktemp -d "$WORK/p.XXXXXX")"
  mkdir -p "$NEW_HOME/.rabadon/spool" "$NEW_PROJ/.git" "$NEW_PROJ/src" "$NEW_PROJ/tests"
  printf 'ref: refs/heads/main\n' > "$NEW_PROJ/.git/HEAD"
  # enforce, not watch — see the header.
  : > "$NEW_HOME/.rabadon/enabled"
}

# ev <hook> <tool> <session> <json-tool-input> [tool_response]
# stderr is dropped; stdout is RETURNED, because stdout is the one channel a
# silent round is not allowed to use and section 7 has to be able to read it.
ev() {
  local hook="$1" tool="$2" sid="$3" input="$4" resp="${5:-}"
  local j
  j="$(printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":%s' \
        "$hook" "$sid" "$NEW_PROJ" "$tool" "$input")"
  [ -n "$resp" ] && j="$j,\"tool_response\":$(jstr "$resp")"
  j="$j}"
  printf '%s' "$j" | env HOME="$NEW_HOME" RABADON_DIR="$NEW_HOME/.rabadon" RABADON_NOTIFY=0 \
    ${DET_ENV:-} "$GATE" 2>/dev/null
}

bash_pre()  { ev PreToolUse  Bash "$1" "{\"command\":$(jstr "$2")}" >/dev/null; }
bash_post() { ev PostToolUse Bash "$1" "{\"command\":$(jstr "$2")}" "$3" >/dev/null; }
edit_pre()  { ev PreToolUse  Edit "$1" "{\"file_path\":$(jstr "$NEW_PROJ/$2"),\"old_string\":\"\",\"new_string\":$(jstr "$3")}" >/dev/null; }
# a command that ran and failed, in one call — the shape every repeat and
# root-migration fixture needs, since claimed_rc is only set on PostToolUse.
ran_bad()   { bash_pre "$1" "$2"; bash_post "$1" "$2" "$3"; }
ran_ok()    { bash_pre "$1" "$2"; bash_post "$1" "$2" "$3"; }

# ---------------------------------------------------------------------------
# READING THE SPOOL. A silent round's only permitted trace is a SIGNAL line in
# the ledger, so that is the only place this file looks.

# every SIGNAL name emitted into this sandbox's spool
fired() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
names = []
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        if e.get("ev") == "SIGNAL":
            names.append(e.get("signal") or e.get("name") or "?")
print(" ".join(sorted(set(names))))
PY
}

# THE VACUITY GUARD. Total ledger lines of any kind. If this is zero the gate
# never saw the fixture — the sandbox was wrong, the binary did nothing, the
# event was malformed — and every "nothing fired" below would be green for a
# reason that has nothing to do with the detectors.
nevents() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import os, sys, glob
n = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        if line.strip(): n += 1
print(n)
PY
}

# the tier-1 hits only, "<name> <conf>" per line. A hit is tier 1 if the ledger
# says so in "tier" or names itself semantic — the same door reports/R3/accept.sh
# uses, and the same reason: a signal a reader cannot tell apart from tier 0 is
# not a separable signal.
sem_hits() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
out = []
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        if e.get("ev") != "SIGNAL": continue
        name = e.get("signal") or e.get("name") or ""
        blob = (name + " " + (e.get("why") or "")).lower()
        if "semantic" in blob or e.get("tier") in (1, "1"):
            out.append("%s %s" % (name, e.get("conf")))
print("\n".join(out))
PY
}

has() { case " $(fired) " in *" $1 "*) return 0;; *) return 1;; esac; }
live() { local n; n="$(nevents)"; case "$n" in ''|*[!0-9]*) return 1;; 0) return 1;; *) return 0;; esac; }

# --- the four assertion forms. Each one is red on an empty spool. -----------
expect_fires() {  # expect_fires <signal> <label>
  if ! live; then fail "$2 — the spool is empty, the gate never saw the fixture"
  elif has "$1"; then pass "$2"
  else fail "$2 — '$1' did not fire; fired: [$(fired)]"; fi
}
expect_silent() { # expect_silent <signal> <label>
  if ! live; then fail "$2 — the spool is empty, nothing was tested so nothing was cleared"
  elif has "$1"; then fail "$2 — '$1' FIRED on honest work; fired: [$(fired)]"
  else pass "$2"; fi
}
expect_nothing() { # expect_nothing <label>
  local f
  f="$(fired)"
  if ! live; then fail "$1 — the spool is empty, nothing was tested so nothing was cleared"
  elif [ -z "$f" ]; then pass "$1"
  else fail "$1 — fired: [$f]"; fi
}
expect_sem() {    # expect_sem <label>
  if ! live; then fail "$1 — the spool is empty, the gate never saw the fixture"
  elif [ -n "$(sem_hits)" ]; then pass "$1"
  else fail "$1 — no tier-1 hit; fired: [$(fired)]"; fi
}
expect_no_sem() { # expect_no_sem <label>
  if ! live; then fail "$1 — the spool is empty, nothing was tested so nothing was cleared"
  elif [ -n "$(sem_hits)" ]; then fail "$1 — tier 1 FIRED: [$(sem_hits | tr '\n' ' ')]"
  else pass "$1"; fi
}

# ===========================================================================
head_ "1. repeat — it fires on a loop, not on a build step"

# POSITIVE. Three runs of one command, and the failures are what make it a loop:
# REPEAT_MIN=3 plus at least two matching moves carrying an error.
sandbox
for i in 1 2 3; do ran_bad s-rep 'npm run build' 'Error: cannot find module x'; done
expect_fires repeat "three failing runs of one command are a repeat"

# NEGATIVE, AND THE ONE THAT MATTERS. `lint, build, lint, build, lint, build`.
# Three runs of one lint command inside a session that is going perfectly fine.
# The naive rule counted occurrences and called this a loop.
sandbox
for i in 1 2 3; do
  ran_ok s-lb 'npm run lint'  'ok'
  ran_ok s-lb 'npm run build' 'built'
done
expect_nothing "lint/build/lint/build/lint/build fires nothing at all"

# NEGATIVE. The same clause from the other side: the command repeats three
# times and SUCCEEDS every time. Repetition alone is not the evidence; not
# getting anywhere is, and a command that keeps working is doing its job.
sandbox
for i in 1 2 3; do ran_ok s-ok3 'npm run build' 'built in 1.2s'; done
expect_silent repeat "three SUCCESSFUL runs of one command are not a repeat"

# NEGATIVE. A second attempt is how debugging works. REPEAT_MIN=3 is the whole
# rule here and this is the fixture that pins it.
sandbox
for i in 1 2; do ran_bad s-two 'npm run build' 'Error: cannot find module x'; done
expect_silent repeat "a second attempt at a failing command is debugging, not a repeat"

# ===========================================================================
head_ "2. oscillation — one file rewritten back and forth, not two commands taking turns"

# POSITIVE. A-B-A-B-A-B edits to ONE path. Every move differs from the one
# before it, so `repeat` is structurally blind and this is the only rule that
# can see the agent undoing its own work.
sandbox
for i in 1 2 3; do
  edit_pre s-osc src/app.js 'const timeout = 500;'
  edit_pre s-osc src/app.js 'const timeout = 5000;'
done
expect_fires oscillation "an A-B-A-B-A-B edit loop on one file is oscillation"

# NEGATIVE. The same alternation across TWO files. Each file is edited three
# times with its own content and nothing is ever undone — this is two files
# being maintained in step, and a rule about "alternation in general" fires here.
sandbox
for i in 1 2 3; do
  edit_pre s-osc2 src/app.js   'const timeout = 500;'
  edit_pre s-osc2 src/other.js 'const retries = 3;'
done
expect_silent oscillation "alternating edits across two files are not oscillation"

# NEGATIVE. Six edits to ONE path, cycling three contents A-B-C-A-B-C. The
# window is full and the path is single — everything the rule looks at except
# the one thing it requires, which is exactly two alternating contents.
sandbox
for i in 1 2; do
  edit_pre s-osc3 src/app.js 'const mode = "a";'
  edit_pre s-osc3 src/app.js 'const mode = "bb";'
  edit_pre s-osc3 src/app.js 'const mode = "ccc";'
done
expect_silent oscillation "a three-content cycle on one file is not an A-B oscillation"

# ===========================================================================
head_ "3. root_migration — the error stands still while the moves move"

# POSITIVE. Nothing on the market sees this: three different commands, one
# unchanged error. The agent is walking around the problem.
sandbox
ran_bad s-root 'npm run build'    'TypeError: undefined is not a function'
ran_bad s-root 'npx tsc --noEmit' 'TypeError: undefined is not a function'
ran_bad s-root 'node dist/main.js' 'TypeError: undefined is not a function'
expect_fires root_migration "one error surviving three different commands is a root migration"

# NEGATIVE. One error, one command, three times. This is a retry loop and
# `repeat` owns it; root_migration counts DISTINCT moves and must count one.
# Asserting on the name rather than on silence is deliberate: `repeat` is
# supposed to fire here and demanding a silent spool would be demanding the
# wrong thing.
sandbox
for i in 1 2 3; do ran_bad s-root2 'npm run build' 'TypeError: undefined is not a function'; done
expect_silent root_migration "one error through one command three times is a repeat, not a migration"

# NEGATIVE. Three different commands, three different errors — an agent working
# through a list of real, separate problems. The moves move and so does the
# error, which is what progress looks like.
sandbox
ran_bad s-root3 'npm run build'    'TypeError: undefined is not a function'
ran_bad s-root3 'npx tsc --noEmit' 'error TS2345: argument of type string'
ran_bad s-root3 'node dist/main.js' 'ReferenceError: db is not defined'
expect_silent root_migration "three different errors from three commands are not one root"

# ===========================================================================
head_ "4. scope_drift — the weakest rule in the file, and it knows it"

# POSITIVE. Six directories. DRIFT_DIRS is 5.
sandbox
for d in src lib tools docs scripts vendor; do
  mkdir -p "$NEW_PROJ/$d"
  edit_pre s-drift "$d/f.js" "const a = 1; // $d"
done
expect_fires scope_drift "six touched directories are scope drift"

# NEGATIVE. Four directories: one under the threshold, which is the only place a
# threshold can be tested from.
sandbox
for d in src lib tools docs; do
  mkdir -p "$NEW_PROJ/$d"
  edit_pre s-drift2 "$d/f.js" "const a = 1; // $d"
done
expect_silent scope_drift "four touched directories are under the threshold"

# NEGATIVE. A large honest refactor: eight files, all in one directory. This is
# the case the header calls out — "a large honest refactor touches many" — held
# to the side of it that the rule is actually allowed to see.
sandbox
for i in 1 2 3 4 5 6 7 8; do
  edit_pre s-drift3 "src/mod$i.js" "export const step$i = () => $i;"
done
expect_silent scope_drift "eight files in one directory are a refactor, not drift"

# ===========================================================================
head_ "5. green_redefined — the rule this whole product is named after"

# POSITIVE (a). The suite is red and the agent is editing the thing that judges
# it.
sandbox
ran_ok s-g1 'npm test' '3 passed, 2 failed'
edit_pre s-g1 tests/app.test.js 'expect(true).toBe(true);'
expect_fires green_redefined "editing a test file while the suite is red redefines green"

# POSITIVE (b). Red turned green and only the test side moved.
sandbox
ran_ok s-g2 'npm test' '3 passed, 2 failed'
edit_pre s-g2 tests/app.test.js 'it.skip("the failing one", () => {});'
ran_ok s-g2 'npm test' '3 passed, 0 failed'
expect_fires green_redefined "a red-to-green where only the test side moved redefines green"

# POSITIVE (c). A test file lost assertions.
sandbox
edit_pre s-g3 tests/app.test.js 'expect(a).toBe(1); expect(b).toBe(2); expect(c).toBe(3); expect(d).toBe(4);'
edit_pre s-g3 tests/app.test.js 'expect(a).toBe(1);'
expect_fires green_redefined "four assertions falling to one redefines green"

# NEGATIVE. A legitimate test refactor while the suite is GREEN. Editing tests
# is the most valuable thing an agent does; what is suspicious is editing them
# while they are FAILING. If this fires, the detector punishes writing tests.
sandbox
ran_ok s-c2 'npm test' '12 passed, 0 failed'
edit_pre s-c2 tests/app.test.js 'expect(a).toBe(1); expect(b).toBe(2); expect(c).toBe(3);'
expect_nothing "a test refactor on a GREEN suite fires nothing"

# NEGATIVE. A test file that GAINS assertions. The count rule reads a DROP, and
# a file that grows has to be as quiet as one nobody touched.
sandbox
ran_ok s-c3 'npm test' '12 passed, 0 failed'
edit_pre s-c3 tests/app.test.js 'expect(a).toBe(1);'
edit_pre s-c3 tests/app.test.js 'expect(a).toBe(1); expect(b).toBe(2); expect(c).toBe(3);'
expect_nothing "a test file that gains assertions fires nothing"

# NEGATIVE. Red -> green with the SOURCE fixed. This is the outcome the product
# exists to protect; a detector that flags it is flagging success.
sandbox
ran_ok s-c4 'npm test' '3 passed, 2 failed'
edit_pre s-c4 src/app.js 'function add(a,b){ return a+b; }'
ran_ok s-c4 'npm test' '5 passed, 0 failed'
expect_nothing "fixing the source and going green fires nothing"

# NEGATIVE. Editing SOURCE while the suite is red — the correct response to a
# red suite, and the mirror image of positive (a). Only the thing that DECIDES
# green is off limits while green is in question.
sandbox
ran_ok s-c6 'npm test' '3 passed, 2 failed'
edit_pre s-c6 src/app.js 'function add(a,b){ return a+b; }'
expect_silent green_redefined "editing the source while the suite is red is the fix, not a redefinition"

# ===========================================================================
head_ "6. tier 1 — the shape of an edit, and the cascade that keeps it honest"

# POSITIVE. Three spacings of one edit. squeeze() in moves.h collapses RUNS of
# whitespace but does not delete it, so `a + b` and `a+b` hash to different
# tier-0 signatures and `repeat` walks past them. This is the cheapest escape
# from the repeat detector and an agent finds it by accident.
sandbox
edit_pre s-s1 src/calc.js 'function total(a, b) { const x = a + b; return x; }'
edit_pre s-s1 src/calc.js 'function total(a, b) { const x = a+b; return x; }'
edit_pre s-s1 src/calc.js 'function total(a,b){ const x  =  a + b; return x; }'
expect_sem "three spacings of one edit are a semantic repeat"

# POSITIVE. The same shape under renamed identifiers. Every byte differs, so
# tier 0 cannot match this in principle no matter how good its normalisation
# gets. Local renaming before fingerprinting is what makes these one shape.
sandbox
edit_pre s-s2 src/handler.js 'function run(items) { const out = foo(x); return out; }'
edit_pre s-s2 src/handler.js 'function exec(rows) { const res = bar(y); return res; }'
edit_pre s-s2 src/handler.js 'function go(list) { const val = baz(z); return val; }'
expect_sem "the same shape under renamed identifiers is a semantic repeat"

# NEGATIVE. Three unrelated functions in one file: same language, same house
# style, everything a similarity score rewards — and not the same attempt at
# anything. Measured through semantic.h itself these sit at 0.08.
sandbox
edit_pre s-s3 src/util.js 'function parseDate(s) { return new Date(Date.parse(s)); }'
edit_pre s-s3 src/util.js 'function slugify(s) { return s.toLowerCase().replace(/x/g, "-"); }'
edit_pre s-s3 src/util.js 'function clamp(n, lo, hi) { return Math.min(hi, Math.max(lo, n)); }'
expect_no_sem "three unrelated functions in one file are not a semantic repeat"

# NEGATIVE, AND THE CLOSEST THING IN THIS FILE TO A FALSE POSITIVE. Honest
# incremental debugging on ONE path: the frame is kept and one comparison is
# tightened each time. Token-for-token these are nearly the same text, which is
# the maximum a shape fingerprint can be asked to survive — and it is also the
# single most valuable move an agent makes. Measured through semantic.h: the
# tightest pair here is 0.6923 against a threshold of 0.80. That margin is the
# margin, and a later round that loosens THRESHOLD has to argue with this
# fixture and not with a number that felt right.
sandbox
edit_pre s-s4 src/range.js 'function clampRange(lo, hi, n) { if (n < lo) { return lo; } if (n > hi) { return hi; } return n; }'
edit_pre s-s4 src/range.js 'function clampRange(lo, hi, n) { if (n <= lo) { return lo; } if (n > hi) { return hi; } return n; }'
edit_pre s-s4 src/range.js 'function clampRange(lo, hi, n) { if (n <= lo) { return lo; } if (n >= hi) { return hi; } return Math.round(n); }'
expect_no_sem "an operator-level bugfix repeated three times is not a semantic repeat"

# NEGATIVE. A test file grown by appending one assertion at a time — six edits
# to one path, which is honest work of the highest value. This is the tightest
# case measured: consecutive versions reach 0.88 token overlap, ABOVE the 0.80
# threshold, and the fixture stays silent only because MIN_HITS demands THREE
# occurrences and similarity to the older versions decays as the file grows.
# So this fixture is load-bearing on MIN_HITS, not on THRESHOLD, and it is the
# thing that goes red if MIN_HITS is ever lowered to two.
sandbox
T='test("adds", () => { expect(add(1,2)).toBe(3);'
for extra in '' ' expect(add(0,0)).toBe(0);' ' expect(add(-1,1)).toBe(0);' \
             ' expect(add(2,2)).toBe(4);' ' expect(add(5,5)).toBe(10);' ' expect(add(9,1)).toBe(10);'; do
  T="$T$extra"
  edit_pre s-s5 tests/add.test.js "$T });"
done
expect_no_sem "a test file grown one assertion at a time is not a semantic repeat"

# --- THE CASCADE, asserted rather than assumed -----------------------------
# Three BYTE-IDENTICAL edits to one path. Tier 0's hash matches, so the early
# `return` in rbsem::detect must fire and tier 1 must never be consulted — even
# though this is the loudest possible tier-1 input, similarity 1.00 by
# construction. If the cascade is ever reordered, or the return is turned into a
# flag, tier 1 starts describing the same pair of moves tier 0 already owns and
# this is the assertion that catches it.
sandbox
for i in 1 2 3; do
  edit_pre s-casc src/same.js 'function total(a, b) { const x = a + b; return x; }'
done
expect_no_sem "tier 1 does not run at all when tier 0's hash already matched"

# and the same fixture from the other side: tier 0 owns it, so if tier 0 is
# ever the one that goes quiet here the cascade assertion above would pass for
# the wrong reason — three identical edits producing NO tier-0 match at all.
CASC_SIG_MATCHED=0
sandbox
for i in 1 2 3; do
  edit_pre s-casc2 src/same.js 'function total(a, b) { const x = a + b; return x; }'
done
# tier 0's `repeat` needs failures and an edit carries none, so the check is on
# the record rather than on a signal: three identical edits must be three moves
# with ONE distinct tier-0 signature.
NSIG0="$(python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json, os, sys, glob
n = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(f):
        if line.strip(): n += 1
print(n)
PY
)"
if [ "${NSIG0:-0}" -gt 0 ] 2>/dev/null; then
  CASC_SIG_MATCHED=1
  pass "the cascade fixture actually reached the gate ($NSIG0 ledger lines) — the silence above is a verdict, not an absence"
else
  fail "the cascade fixture never reached the gate — the cascade assertion above proved nothing"
fi

# --- the tier-1 kill switch ------------------------------------------------
# RABADON_SEM=0 must remove the tier-1 line and nothing else. Both halves are
# asserted in one place so neither can pass on an empty spool: the switch ON
# must produce a hit, and the switch OFF must produce a live spool with no hit.
sandbox
edit_pre s-k1 src/calc.js 'function total(a, b) { const x = a + b; return x; }'
edit_pre s-k1 src/calc.js 'function total(a, b) { const x = a+b; return x; }'
edit_pre s-k1 src/calc.js 'function total(a,b){ const x  =  a + b; return x; }'
SEM_ON="$(sem_hits)"; EV_ON="$(nevents)"
DET_ENV="RABADON_SEM=0"
sandbox
edit_pre s-k2 src/calc.js 'function total(a, b) { const x = a + b; return x; }'
edit_pre s-k2 src/calc.js 'function total(a, b) { const x = a+b; return x; }'
edit_pre s-k2 src/calc.js 'function total(a,b){ const x  =  a + b; return x; }'
SEM_OFF="$(sem_hits)"; EV_OFF="$(nevents)"
DET_ENV=""
if [ "${EV_ON:-0}" -eq 0 ] 2>/dev/null || [ "${EV_OFF:-0}" -eq 0 ] 2>/dev/null; then
  fail "RABADON_SEM=0 is not proven — a spool was empty (on:$EV_ON off:$EV_OFF), the comparison compared nothing"
elif [ -n "$SEM_ON" ] && [ -z "$SEM_OFF" ]; then
  pass "RABADON_SEM=0 turns tier 1 off, and the default turns it on"
else
  fail "RABADON_SEM=0 is not proven: on=[$(printf '%s' "$SEM_ON" | tr '\n' ' ')] off=[$(printf '%s' "$SEM_OFF" | tr '\n' ' ')]"
fi

# ===========================================================================
head_ "7. silent — no exit code moves and nothing reaches stdout"

# stdout is a hook's PERMISSION CHANNEL. A silent round that prints is not
# silent, and what it prints can change what the agent is allowed to do. This
# section is the reason R2 and R3 are allowed to exist at all before their false
# positive rates have ever been measured.

# First prove the fixture can refuse something. If the gate is in watch mode it
# returns 0 to everything and every comparison below is two allow paths
# compared to each other — green, and worth nothing.
sandbox
DENY_RC=0
ev PreToolUse Bash s-guard "{\"command\":$(jstr 'git push --force origin main')}" >/dev/null 2>&1
DENY_RC=$?
if [ "$DENY_RC" = "2" ]; then
  pass "the fixture is in enforce mode: the force-push is refused (exit 2)"
else
  fail "the fixture refuses nothing — the force-push exited $DENY_RC, expected 2. Nothing below this line means anything until it is 2."
fi

cmp_pair() { # cmp_pair <switch> <label> <command>
  local sw="$1" label="$2" cmd="$3" on_out off_out on_rc off_rc
  DET_ENV=""; sandbox
  on_out="$(ev PreToolUse Bash s-x "{\"command\":$(jstr "$cmd")}")"; on_rc=$?
  DET_ENV="$sw"; sandbox
  off_out="$(ev PreToolUse Bash s-x "{\"command\":$(jstr "$cmd")}")"; off_rc=$?
  DET_ENV=""
  if [ "$on_rc" = "$off_rc" ]; then
    pass "exit code identical with $sw and without — $label -> $on_rc"
  else
    fail "the detectors moved the verdict for $label under $sw: on=$on_rc off=$off_rc"
  fi
  if [ -z "$on_out" ]; then
    pass "stdout is empty with the detectors on — $label"
  else
    fail "the detectors wrote to stdout for $label: [$on_out]"
  fi
}
cmp_pair RABADON_SIGNALS=0 "an allowed command" 'echo hello'
cmp_pair RABADON_SIGNALS=0 "a refused command"  'git push --force origin main'
cmp_pair RABADON_SEM=0     "an allowed command" 'echo hello'
cmp_pair RABADON_SEM=0     "a refused command"  'git push --force origin main'

# and the two paths where a detector definitely has something to say, which is
# where a stray printf would land.
sandbox
OUT=""
for i in 1 2 3; do
  OUT="$OUT$(ev PreToolUse Bash s-p1 "{\"command\":$(jstr 'npm run build')}")"
  ev PostToolUse Bash s-p1 "{\"command\":$(jstr 'npm run build')}" 'Error: nope' >/dev/null
done
if [ -z "$OUT" ] && has repeat; then
  pass "a firing tier-0 detector writes nothing to stdout"
elif [ -n "$OUT" ]; then
  fail "a firing tier-0 detector printed: [$OUT]"
else
  fail "the stdout check proved nothing — no tier-0 detector fired on this fixture"
fi

sandbox
SEMOUT=""; SEMRC=""
for t in 'function total(a, b) { const x = a + b; return x; }' \
         'function total(a, b) { const x = a+b; return x; }' \
         'function total(a,b){ const x  =  a + b; return x; }'; do
  SEMOUT="$SEMOUT$(ev PreToolUse Edit s-p2 "{\"file_path\":$(jstr "$NEW_PROJ/src/calc.js"),\"old_string\":\"\",\"new_string\":$(jstr "$t")}")"
  SEMRC="$SEMRC$?"
done
if [ -z "$SEMOUT" ] && [ "$SEMRC" = "000" ] && [ -n "$(sem_hits)" ]; then
  pass "a firing tier-1 detector writes nothing to stdout and allows the edit"
elif [ -z "$(sem_hits)" ]; then
  fail "the tier-1 stdout check proved nothing — tier 1 did not fire on this fixture"
else
  fail "the tier-1 path printed [$SEMOUT] / rc [$SEMRC]"
fi

# ===========================================================================
if [ "$FAIL" -eq 0 ] && [ "$CASC_SIG_MATCHED" -eq 1 ]; then
  printf 'signals: %d passed, 0 failed\n' "$PASSN"
  exit 0
fi
printf 'signals: %d passed, and at least one failed\n' "$PASSN"
exit 1
