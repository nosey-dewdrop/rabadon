#!/usr/bin/env bash
# R3 acceptance — the semantic signature (tier 1).
#
# WRITTEN BEFORE THE CODE and red on the day it is written. That is the correct
# state: tier 1 does not exist yet. Turning it green is R3's job.
#
# WHAT R3 IS.
# Tier 0 (native/moves.h: sig_bash / sig_edit) is exact-after-spelling. It
# relativises, masks scratch paths, squeezes runs of whitespace to one space,
# and hashes. That is a deliberate promise — tier 0 never claims a match it did
# not literally see — and it is also the hole: an agent that writes the same fix
# with one space removed, or with the identifiers renamed, produces a different
# 16-hex signature and walks straight past the `repeat` detector in
# native/signals.h. Nothing in the record says the two moves were the same
# attempt, so nothing downstream can ever say it either.
#
# Tier 1 closes that hole with a token-sequence winnowing k-gram fingerprint
# over the edit text — the MOSS technique: thirty years old, pure C++,
# microseconds, no dependency. Identifiers are locally renamed to their position
# before hashing, so `foo(x)` and `bar(y)` land on the same shape. Overlap above
# threshold is a SEMANTIC repeat, and its confidence is fractional because a
# shape match is weaker evidence than a hash match and the ledger has to say so.
#
# THE CASCADE, WHICH IS THE WHOLE SAFETY ARGUMENT.
# Tier 0 first. If tier 0's hashes match, the work is done and tier 1 is never
# consulted. Tier 1 runs only where tier 0 said nothing, and it may only ADD.
# It may not silence a tier-0 hit, may not lower a tier-0 confidence, may not
# move an exit code, may not print. Still silent mode, exactly as in R2: a
# detector whose false positive rate has never been measured does not act.
# Tier 2 (AST / tree-sitter) is NOT written this round.
#
# SO THIS FILE ASSERTS FOUR THINGS:
#   1. tier 1 catches what tier 0 structurally cannot — and, far more expensive,
#      stays quiet on honest work that merely resembles a repeat
#   2. tier 1 is additive: every tier-0 verdict is byte-identical with the
#      feature on and off, exit codes included, stdout still empty
#   3. the added latency is MEASURED with a two-armed run, not estimated
#   4. the existing suite did not regress
#
# CLAIM 1c IS NOT PADDING, AND IT IS WHY THERE ARE THREE OF IT.
# Law 1: the expensive failure of this product is a false positive, not a miss.
# A fingerprint over token shapes is much looser than a hash, so the honest-work
# direction gets three distinct fixtures — an unrelated addition, a real bugfix
# that changes one operator (structurally almost identical to what it replaces,
# and the single hardest case for a shape fingerprint), and a large edit that
# shares only boilerplate with the one before it. A later loosening of the
# threshold has to argue with these three cases, not with a number.
#
# THE KILL SWITCH: RABADON_SEM=0.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

GATE="$ROOT/native/rabadon-gate"

PASS_N=0; FAIL_N=0; C1_FAIL=0
pass() { printf 'PASS  %s\n' "$1"; PASS_N=$((PASS_N + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL_N=$((FAIL_N + 1)); }
note() { printf '      %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

[ -x "$GATE" ] || { printf 'FAIL  no gate binary — run make first\n'; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'FAIL  python3 required\n'; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rbr3.XXXXXX")"
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
    ${SEM_ENV:-} "$GATE" 2>/dev/null
}

bash_pre()  { ev PreToolUse  Bash "$1" "{\"command\":$(jstr "$2")}" >/dev/null; }
bash_post() { ev PostToolUse Bash "$1" "{\"command\":$(jstr "$2")}" "$3" >/dev/null; }
edit_pre()  { ev PreToolUse  Edit "$1" "{\"file_path\":$(jstr "$NEW_PROJ/$2"),\"old_string\":\"\",\"new_string\":$(jstr "$3")}" >/dev/null; }

# ---------------------------------------------------------------------------
# Reading the spool, exactly the way reports/R2/accept.sh does: SIGNAL lines are
# the only place a silent round is allowed to leave a trace, so they are the
# only place this file is allowed to look.

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

# total number of ledger events in this sandbox's spool, of any kind. The
# vacuity guard: reports/R2/accept.sh and reports/R1.2/accept.sh both learned
# that "nothing fired" and "nothing ran" print the same on a green line. If the
# spool is empty the gate never saw the fixture and the assertion below proved
# nothing, so it must be red, not green.
nevents() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import os,sys,glob
n=0
for f in glob.glob(os.path.join(sys.argv[1],"*.jsonl")):
    for line in open(f):
        if line.strip(): n+=1
print(n)
PY
}

# The semantic hits only: "<name> <conf>" per line. A hit counts as semantic if
# it says so in its name or in its ledger clause. The exact spelling is R3's to
# pick — this file refuses to pin it harder than "the ledger can be read back
# and it says the match was a shape match, not a hash match", because a signal
# nobody can tell apart from tier 0 in the ledger is not a separable signal.
sem_hits() {
  python3 - "$NEW_HOME/.rabadon/spool" <<'PY'
import json,os,sys,glob
out=[]
for f in glob.glob(os.path.join(sys.argv[1],"*.jsonl")):
    for line in open(f):
        line=line.strip()
        if not line: continue
        try: e=json.loads(line)
        except Exception: continue
        if e.get("ev")!="SIGNAL": continue
        name=(e.get("signal") or e.get("name") or "")
        why=(e.get("why") or "")
        tier=e.get("tier")
        blob=(name+" "+why).lower()
        if "semantic" in blob or tier in (1,"1"):
            out.append("%s %s" % (name, e.get("conf")))
print("\n".join(out))
PY
}
sem_fired() { [ -n "$(sem_hits)" ]; }

# ---------------------------------------------------------------------------
head_ "CLAIM 1 — tier 1 catches what tier 0 structurally cannot"

# Every fixture below writes THREE spellings, not two. Tier 0's `repeat` needs
# REPEAT_MIN=3 (native/signals.h: "a second attempt is debugging"), and tier 1
# is not allowed to be LOOSER than tier 0 — a semantic detector that fires on
# the second attempt would flag ordinary debugging, which is the exact failure
# that got the SWE-agent-era loop detectors ripped out.

# --- 1a same edit, different spacing --------------------------------------
# squeeze() in native/moves.h collapses RUNS of whitespace but does not delete
# whitespace, so "x = a + b" and "x = a+b" squeeze to different strings and hash
# to different 16-hex signatures. Tier 0 is blind here by construction. This is
# the cheapest possible escape from the repeat detector and an agent finds it by
# accident.
sandbox
edit_pre s-1a src/calc.js 'function total(a, b) { const x = a + b; return x; }'
edit_pre s-1a src/calc.js 'function total(a, b) { const x = a+b; return x; }'
edit_pre s-1a src/calc.js 'function total(a,b){ const x  =  a + b; return x; }'
if sem_fired; then
  pass "1a three spacings of one edit are a semantic repeat"
  # fractional confidence: a shape match is weaker evidence than a hash match
  # and the ledger line has to carry that, otherwise R4's promotion ladder has
  # nothing to sort by.
  SEMCONF="$(sem_hits | awk 'NR==1{print $2}')"
  if python3 -c 'import sys; c=float(sys.argv[1]); sys.exit(0 if 0.0<c<1.0 else 1)' "$SEMCONF" 2>/dev/null; then
    pass "1a the semantic hit carries fractional confidence ($SEMCONF)"
  else
    fail "1a semantic confidence is not fractional: [$SEMCONF]"
  fi
elif [ "$(nevents)" -eq 0 ] 2>/dev/null; then
  fail "1a the spool is empty — the gate never saw the fixture, nothing was tested"
else
  fail "1a no semantic repeat on three spacings of one edit — fired: [$(fired)]"
fi

# --- 1b same structure, locally renamed identifiers ------------------------
# The other half of the hole, and the more damning one: the agent rewrites the
# identical fix with different names. Every byte of the text differs, so tier 0
# cannot match it in principle, no matter how good its normalisation gets.
# Local renaming before fingerprinting is what makes these one shape.
sandbox
edit_pre s-1b src/handler.js 'function run(items) { const out = foo(x); return out; }'
edit_pre s-1b src/handler.js 'function exec(rows) { const res = bar(y); return res; }'
edit_pre s-1b src/handler.js 'function go(list) { const val = baz(z); return val; }'
if sem_fired; then
  pass "1b the same shape under renamed identifiers is a semantic repeat"
elif [ "$(nevents)" -eq 0 ] 2>/dev/null; then
  fail "1b the spool is empty — the gate never saw the fixture, nothing was tested"
else
  fail "1b no semantic repeat on a locally-renamed rewrite — fired: [$(fired)]"
fi

# --- 1c THE EXPENSIVE DIRECTION: honest work must stay quiet ---------------
# Three fixtures, not one. See the header. A false positive here is the failure
# that gets the product uninstalled, and a shape fingerprint is exactly the kind
# of rule that produces one.

# 1c-i an unrelated function added after a real fix. Same file, same language,
# same house style — everything a naive similarity score rewards — but the two
# edits are not the same attempt at anything.
sandbox
edit_pre s-1ci src/util.js 'function parseDate(s) { return new Date(Date.parse(s)); }'
edit_pre s-1ci src/util.js 'function slugify(s) { return s.toLowerCase().replace(/\s+/g, "-"); }'
edit_pre s-1ci src/util.js 'function clamp(n, lo, hi) { return Math.min(hi, Math.max(lo, n)); }'
if sem_fired; then
  fail "1c-i an unrelated function was called a semantic repeat: [$(sem_hits | tr '\n' ' ')]"
elif [ "$(nevents)" -eq 0 ] 2>/dev/null; then
  fail "1c-i the spool is empty — nothing was tested, so nothing was cleared"
else
  pass "1c-i adding unrelated functions is not a semantic repeat"
fi

# 1c-ii a real bugfix that changes ONE operator. This is the hardest honest case
# in the file: token-for-token it is nearly identical to the line it replaces,
# so a shape fingerprint sees maximum overlap — and yet it is the single most
# valuable move an agent makes. If tier 1 flags this, tier 1 punishes fixing
# bugs and must not ship at any threshold.
sandbox
edit_pre s-1cii src/math.js 'export function span(lo, hi) { return hi + lo; }'
edit_pre s-1cii src/math.js 'export function span(lo, hi) { return hi - lo; }'
bash_pre  s-1cii 'npm test'
bash_post s-1cii 'npm test' '14 passed, 0 failed'
if sem_fired; then
  fail "1c-ii an operator-level bugfix was called a semantic repeat: [$(sem_hits | tr '\n' ' ')]"
elif [ "$(nevents)" -eq 0 ] 2>/dev/null; then
  fail "1c-ii the spool is empty — nothing was tested, so nothing was cleared"
else
  pass "1c-ii a bugfix that changes one operator is not a semantic repeat"
fi

# 1c-iii a large edit that shares only BOILERPLATE with the one before it —
# the same imports, the same export wrapper, the same error-handling frame, and
# a completely different body. Winnowing over k-grams will find real overlap
# here, and the threshold has to be high enough that shared scaffolding is not
# mistaken for a repeated attempt. Every codebase is mostly scaffolding.
sandbox
edit_pre s-1ciii src/api.js 'import { client } from "./client"; import { log } from "./log";
export async function listUsers(q) {
  try { const r = await client.get("/users", { params: q }); return r.data; }
  catch (e) { log.error(e); throw e; }
}'
edit_pre s-1ciii src/api.js 'import { client } from "./client"; import { log } from "./log";
export async function uploadInvoice(file, meta) {
  const form = new FormData();
  form.append("file", file);
  form.append("meta", JSON.stringify(meta));
  try { const r = await client.post("/invoices", form); return r.data.id; }
  catch (e) { log.error(e); throw e; }
}'
edit_pre s-1ciii src/api.js 'import { client } from "./client"; import { log } from "./log";
export async function reconcileLedger(from, to) {
  const rows = [];
  for (let d = from; d <= to; d++) { rows.push(await client.get("/ledger/" + d)); }
  try { return rows.reduce((acc, r) => acc + r.data.total, 0); }
  catch (e) { log.error(e); throw e; }
}'
if sem_fired; then
  fail "1c-iii shared boilerplate was called a semantic repeat: [$(sem_hits | tr '\n' ' ')]"
elif [ "$(nevents)" -eq 0 ] 2>/dev/null; then
  fail "1c-iii the spool is empty — nothing was tested, so nothing was cleared"
else
  pass "1c-iii three large edits sharing only boilerplate are not a semantic repeat"
fi

C1_FAIL="$FAIL_N"

# ---------------------------------------------------------------------------
head_ "CLAIM 2 — tier 1 only ADDS; every tier-0 verdict is unchanged"

# The cascade's safety argument, held from the outside. Tier 0 is the shipped
# behaviour of a tool people already run; R3 is allowed to widen what the ledger
# knows and nothing else.

# 2a the tier-0 repeat still fires, identically, with tier 1 on and off.
# Three identical failing runs of one command: this is the fixture tier 0 was
# built for (native/signals.h REPEAT_MIN=3 plus at least two failures), so it is
# the one that would show a cascade wired backwards — tier 1 running first and
# swallowing the hash match.
saw_repeat() { case " $1 " in *" repeat "*) return 0;; *) return 1;; esac; }
t0_repeat_run() {
  sandbox
  for i in 1 2 3; do
    bash_pre  s-t0 'npm run build'
    bash_post s-t0 'npm run build' 'Error: cannot find module x'
  done
}
SEM_ENV=""            ; t0_repeat_run; ON_FIRED="$(fired)";  ON_EV="$(nevents)"
SEM_ENV="RABADON_SEM=0"; t0_repeat_run; OFF_FIRED="$(fired)"; OFF_EV="$(nevents)"
SEM_ENV=""
if [ "${OFF_EV:-0}" -eq 0 ] 2>/dev/null || [ "${ON_EV:-0}" -eq 0 ] 2>/dev/null; then
  fail "2a both spools are empty — the comparison compared nothing"
elif ! saw_repeat "$OFF_FIRED"; then
  fail "2a the tier-0 repeat did not fire even with tier 1 OFF — fired: [$OFF_FIRED]"
  note "this is a tier-0 regression, not an R3 result: the baseline moved"
elif saw_repeat "$ON_FIRED"; then
  pass "2a the tier-0 repeat still fires with tier 1 on (on:[$ON_FIRED] off:[$OFF_FIRED])"
else
  fail "2a tier 1 SWALLOWED a tier-0 hit: on=[$ON_FIRED] off=[$OFF_FIRED]"
  note "the cascade is backwards — tier 0 answers first and tier 1 may not overrule it"
fi

# 2b exit codes and stdout, feature on vs off. stdout is a hook's permission
# channel: a silent round that prints is not silent, and printing there can
# change what the agent is allowed to do.
cmp_pair() { # cmp_pair <label> <command>
  local label="$1" cmd="$2" on_out off_out on_rc off_rc
  SEM_ENV=""; sandbox
  on_out="$(ev PreToolUse Bash s-x "{\"command\":$(jstr "$cmd")}")"; on_rc=$?
  SEM_ENV="RABADON_SEM=0"; sandbox
  off_out="$(ev PreToolUse Bash s-x "{\"command\":$(jstr "$cmd")}")"; off_rc=$?
  SEM_ENV=""
  if [ "$on_rc" = "$off_rc" ]; then
    pass "2b exit code identical with tier 1 on and off — $label -> $on_rc"
  else
    fail "2b tier 1 moved the verdict for $label: on=$on_rc off=$off_rc"
  fi
  if [ -z "$on_out" ]; then
    pass "2b stdout is empty with tier 1 on — $label"
  else
    fail "2b tier 1 wrote to stdout for $label: [$on_out]"
    note "stdout is the permission channel; R3 is still a silent round"
  fi
}
cmp_pair "an allowed command" 'echo hello'
cmp_pair "a refused command"  'git push --force origin main'

# 2c the semantic fixture itself must not print or move a code. This is the one
# path where tier 1 definitely has something to say, so it is where a stray
# printf would land.
SEM_ENV=""; sandbox
SEMOUT=""
SEMOUT="$SEMOUT$(ev PreToolUse Edit s-2c "{\"file_path\":$(jstr "$NEW_PROJ/src/calc.js"),\"old_string\":\"\",\"new_string\":$(jstr 'const x = a + b;')}")"; RC1=$?
SEMOUT="$SEMOUT$(ev PreToolUse Edit s-2c "{\"file_path\":$(jstr "$NEW_PROJ/src/calc.js"),\"old_string\":\"\",\"new_string\":$(jstr 'const x = a+b;')}")"; RC2=$?
SEMOUT="$SEMOUT$(ev PreToolUse Edit s-2c "{\"file_path\":$(jstr "$NEW_PROJ/src/calc.js"),\"old_string\":\"\",\"new_string\":$(jstr 'const x  =  a + b;')}")"; RC3=$?
if [ -z "$SEMOUT" ] && [ "$RC1" = 0 ] && [ "$RC2" = 0 ] && [ "$RC3" = 0 ]; then
  pass "2c a firing semantic detector writes nothing to stdout and allows the edit"
else
  fail "2c the semantic path printed [$SEMOUT] / rc $RC1,$RC2,$RC3"
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 3 — the added latency is MEASURED, not estimated"

# KOSU-RABADON.md, R3: "kademe 1'in eklediği gecikme gate_bench ile ölçülür,
# tahmin edilmez; mevcut fixture setinde medyan artışı 500 µs altında."
#
# THE ASSERTION IS UNCHANGED: tier 1 adds less than 500 us to the median of this
# fixture set. Two arms, same fixtures, tier 1 ON against tier 1 OFF. What
# changed on 23 Aug is the RULER, and only the ruler.
#
# WHY THE OLD RULER WAS THROWN OUT. It timed the whole subprocess — fork + exec +
# dyld + main() — and divided by the event count. About 2.3 ms of a 4.2 ms call
# is process startup (PROFIL.md), it carries all of the machine's scheduler
# noise, and 500 us is far below it. On ONE UNCHANGED BINARY four consecutive
# runs printed "adds 1741.6 us" and "5198.8 us" against the 500 us budget in two
# of them and passed in the other two — 14/0, 13/1, 13/1, 14/0 out of identical
# code. The R3 implementation run saw the same both ways: -362/-433/-270 us on
# the finished feature and -64/+92/+206/+608 us on a tree where tier 1 was not
# even built. A number that swings ±5 ms cannot decide a 500 us question in
# either direction, so the green was worth exactly as much as the red: nothing.
#
# THE NEW RULER measures main() from the inside, the same way reports/R1.3's
# GOAL 4 was fixed. A COPY of the shipped native/gate.cpp is patched under a
# mktemp dir with one probe — a steady_clock stamp at the top of main() and an
# atexit handler that appends the elapsed microseconds to a file — and compiled
# there with c++ -std=c++17 -O2. native/ is never touched. The probe is
# registered FIRST so, atexit being LIFO, it fires LAST and the state flush is
# inside the window; it reads the clock before it writes, so its own write is
# outside it; and it costs the same on both arms, so it cannot move a delta.
# The two arms are INTERLEAVED CALL BY CALL over the same fixture text, so
# machine drift lands on both arms in the same millisecond instead of being
# charged to whichever arm ran while the box was busy.
#
# THE PROOF THAT THIS IS NOT A LOOSENING — the planted regression. A second copy
# of the same source was built with a 300 us busy-wait on the TIER-1 PATH ONLY
# (immediately inside `if (!isBash && rbsem::enabled()) {`, so arm B pays it and
# arm A does not). 300 us is far under the old ruler's noise floor and far over
# this one's. Measured on 23 Aug on a box under load average 78:
#
#   OLD end-to-end ruler, its exact procedure, 5 runs each binary:
#     clean   : -492.5  -526.4  +861.7  -13862.6  +230.9 us   -> 1 of 5 RED on
#               code with nothing wrong with it
#     planted : +1662.6  +783.9  +2438.3  +867.0  +530.2 us
#     The two bands OVERLAP (clean reaches +862, planted comes down to +530) and
#     the clean band alone spans 14.7 ms. A verdict drawn from that says nothing
#     about the 300 us: the old ruler cannot resolve the plant in either
#     direction, it only reports the machine.
#   NEW in-process ruler, 600 interleaved pairs, 3 runs each binary:
#     clean   : +119.8  +70.3  +166.6 us
#     planted : +381.4  +433.1  +491.8 us
#     Disjoint, 3 of 3, with 214.8 us of clear air between the worst clean run
#     and the best planted one. The separation is 300 us minus this ruler's own
#     drift, which is what a working instrument looks like.
#   Note the planted binary still reads UNDER the 500 us budget, and that is the
#   correct verdict, not a miss: 300 us of extra work on top of ~61 us really is
#   inside the budget the plan wrote. The instrument's job is to RESOLVE the
#   quantity; the budget's job is to decide what is too much. Before 23 Aug the
#   first job was not being done at all.

BUDGET_US=500

### the in-process instrument ###############################################
PROBE_DIR="$WORK/probe"; PGATE="$PROBE_DIR/rabadon-gate-probe"; PROBE_OK=0
mkdir -p "$PROBE_DIR" && cp "$ROOT"/native/*.h "$PROBE_DIR"/ 2>/dev/null
python3 - "$ROOT/native/gate.cpp" "$PROBE_DIR/gate_probe.cpp" <<'PY' 2>"$WORK/patch.log"
import sys
src = open(sys.argv[1]).read()
PROBE = r'''
// ---- in-process probe, added to a COPY under a mktemp dir by reports/R3/accept.sh ----
#include <chrono>
static std::chrono::steady_clock::time_point g_rbp_t0;
static void rbprobe_dump() {
  const char* p = getenv("RABADON_PROBE_OUT");
  if (!p || !*p) return;
  const double us = std::chrono::duration<double, std::micro>(
      std::chrono::steady_clock::now() - g_rbp_t0).count();
  char buf[64];
  const int n = snprintf(buf, sizeof buf, "%.1f\n", us);
  const int fd = open(p, O_WRONLY | O_APPEND | O_CREAT, 0644);
  if (fd < 0) return;
  ssize_t w = write(fd, buf, (size_t)n); (void)w;
  close(fd);
}
// Registered first => runs last (atexit is LIFO), so the gate's own atexit
// writes are inside the window.
static void rbprobe_begin() { g_rbp_t0 = std::chrono::steady_clock::now(); atexit(rbprobe_dump); }
// ---- end probe ----

'''
a = "int main(int argc, char** argv) {"
assert src.count(a) == 1, "main() anchor is not unique"
open(sys.argv[2], "w").write(src.replace(a, PROBE + a + "\n  rbprobe_begin();"))
PY
if [ -s "$PROBE_DIR/gate_probe.cpp" ] && \
   ${CXX:-c++} -std=c++17 -O2 -I "$PROBE_DIR" -o "$PGATE" "$PROBE_DIR/gate_probe.cpp" 2>"$WORK/probe.log"; then
  PROBE_OK=1
fi

cat > "$WORK/timer.py" <<'PY'
import json, os, statistics, subprocess, sys
# gate  homeOFF projOFF  homeON projON  outOFF outON  iters
gate, hA, pA, hB, pB, oA, oB, iters = sys.argv[1:9]
# The fixture set: the same edit shapes claim 1 drives, which is what "mevcut
# fixture seti" means here — tier 1's cost is only paid on edits tier 0 missed,
# so a set of unrelated commands would measure the wrong thing and flatter it.
# This list is byte-for-byte the one the end-to-end version used; the fixtures
# did not move, the clock did.
TEXTS = [
    'function total(a, b) { const x = a + b; return x; }',
    'function total(a, b) { const x = a+b; return x; }',
    'function total(a,b){ const x  =  a + b; return x; }',
    'function run(items) { const out = foo(x); return out; }',
    'function exec(rows) { const res = bar(y); return res; }',
    'function go(list) { const val = baz(z); return val; }',
    'function parseDate(s) { return new Date(Date.parse(s)); }',
    'function slugify(s) { return s.toLowerCase().replace(/\\s+/g, "-"); }',
    'function clamp(n, lo, hi) { return Math.min(hi, Math.max(lo, n)); }',
    'export function span(lo, hi) { return hi + lo; }',
    'export function span(lo, hi) { return hi - lo; }',
    'import { client } from "./client";\nexport async function listUsers(q) {\n  try { const r = await client.get("/users", { params: q }); return r.data; }\n  catch (e) { throw e; }\n}',
]
def env(home, off, probe):
    e = dict(os.environ)
    e["HOME"] = home
    e["RABADON_DIR"] = os.path.join(home, ".rabadon")
    e["RABADON_NOTIFY"] = "0"
    if off: e["RABADON_SEM"] = "0"          # arm A: tier 1 off, the kill switch
    if probe: e["RABADON_PROBE_OUT"] = probe
    else: e.pop("RABADON_PROBE_OUT", None)  # warm-up calls are not recorded
    return e
def fire(proj, home, off, probe, i, t):
    ev = {"hook_event_name": "PreToolUse", "session_id": "bench",
          "cwd": proj, "tool_name": "Edit",
          "tool_input": {"file_path": os.path.join(proj, "src", "f%d.js" % (i % 3)),
                         "old_string": "", "new_string": t}}
    subprocess.run([gate], input=json.dumps(ev), capture_output=True,
                   text=True, env=env(home, off, probe), timeout=60)
# Both sandboxes are warmed before EITHER is timed: page cache, the session
# file and the fingerprint file all exist by the time the clock matters, so
# neither arm is measured on a cold tree.
for _ in range(2):
    for i, t in enumerate(TEXTS):
        fire(pA, hA, True, None, i, t); fire(pB, hB, False, None, i, t)
# Interleaved call by call, same text on both arms in the same millisecond.
for _ in range(int(iters)):
    for i, t in enumerate(TEXTS):
        fire(pA, hA, True, oA, i, t); fire(pB, hB, False, oB, i, t)
a = [float(x) for x in open(oA)]; b = [float(x) for x in open(oB)]
if not a or not b:
    print("n=0")
else:
    print("%.1f %.1f %d" % (statistics.median(a), statistics.median(b), min(len(a), len(b))))
PY

# 50 iterations x 12 fixtures = 600 timed calls per arm. The count is not
# decoration: at 300 samples per arm the delta on one unchanged binary still
# moved ±150 us run to run, and at 600 it moved ±50. The planted regression
# above was resolved at 600, not at 300.
ITERS=50
if [ "$PROBE_OK" != 1 ]; then
  fail "3 the in-process instrument did not build — this claim was NOT measured"
  note "$(tail -3 "$WORK/probe.log" "$WORK/patch.log" 2>/dev/null | tr '\n' ' ')"
  note "a claim that cannot be measured is red, never skipped"
else
  sandbox; H_OFF="$NEW_HOME"; P_OFF="$NEW_PROJ"
  sandbox; H_ON="$NEW_HOME";  P_ON="$NEW_PROJ"
  R3OUT="$(python3 "$WORK/timer.py" "$PGATE" "$H_OFF" "$P_OFF" "$H_ON" "$P_ON" \
            "$WORK/t.off" "$WORK/t.on" "$ITERS" 2>/dev/null)"
  # vacuity guard: no samples means no measurement, and a missing measurement
  # must not read as a fast one. NEW_HOME is the ON arm's, so nevents covers it.
  SAMP="$(printf '%s' "$R3OUT" | awk '{print $3}')"
  if [ -z "$R3OUT" ] || [ "${SAMP:-0}" -lt "$ITERS" ] 2>/dev/null || [ "$(nevents)" -lt 1 ] 2>/dev/null; then
    fail "3 the latency arms did not produce a measurement (out=[$R3OUT])"
    note "an unmeasurable delta is red: the plan forbids estimating this number"
  else
    MED_OFF="$(printf '%s' "$R3OUT" | awk '{print $1}')"
    MED_ON="$(printf '%s' "$R3OUT" | awk '{print $2}')"
    DELTA="$(python3 -c 'import sys;print("%.1f"%(float(sys.argv[1])-float(sys.argv[2])))' "$MED_ON" "$MED_OFF")"
    note "in-process main(), tier 1 OFF : ${MED_OFF} us"
    note "in-process main(), tier 1 ON  : ${MED_ON} us"
    note "${SAMP} interleaved pairs over the 12 fixtures, process startup excluded"
    note "added by tier 1               : ${DELTA} us   (budget ${BUDGET_US} us)"
    # THE CEILING: 500 us, and it is not this file's number to pick. It is
    # KOSU-RABADON.md's R3 line, quoted at the top of this claim — "mevcut
    # fixture setinde medyan artışı 500 µs altında". It is carried over
    # unchanged from the end-to-end version so the assertion is identical; only
    # the ruler under it was replaced. For scale, the quantity it bounds is
    # 61 us median in-process (p90 84 us), of which the fingerprint compute is
    # 1.9 us and the rest is the sidecar's syscalls — so the budget sits about
    # 8x above the thing it is guarding, and the ruler above resolves the gap.
    if python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= float(sys.argv[2]) else 1)' "$DELTA" "$BUDGET_US"; then
      pass "3 tier 1 adds ${DELTA} us to the median, under the ${BUDGET_US} us budget"
    else
      fail "3 tier 1 adds ${DELTA} us to the median, over the ${BUDGET_US} us budget"
    fi
  fi
fi

# ---------------------------------------------------------------------------
head_ "CLAIM 4 — the suite did not regress"

# 21/0 is the number moves_test.sh prints today. A semantic tier that touches
# moves.h and signals.h is exactly the change that quietly breaks the record it
# reads from, so the number is pinned rather than eyeballed.
MT_OUT="$(./native/moves_test.sh 2>&1 | tail -1)"
if [ -z "$MT_OUT" ]; then
  fail "4 native/moves_test.sh printed nothing — the suite did not run"
elif [ "$MT_OUT" = "moves: 21 passed, 0 failed" ]; then
  pass "4 native/moves_test.sh: 21 passed, 0 failed"
else
  fail "4 native/moves_test.sh regressed or changed shape: [$MT_OUT]"
fi

# ---------------------------------------------------------------------------
printf '\n== R3 acceptance: %d green, %d red\n' "$PASS_N" "$FAIL_N"
# Claim 1c is "nothing fires when it should not", and with no tier 1 built,
# nothing fires at all — so its greens are free until 1a and 1b are green. The
# same is true of claim 2 (a feature that does nothing cannot change a verdict)
# and claim 3 (a feature that does nothing costs nothing). Say so, or a
# half-built round reads as almost finished.
if [ "$C1_FAIL" -gt 0 ]; then
  printf '      NOTE: claim 1 had %d red, so claim 1c, claim 2 and claim 3 proved nothing\n' "$C1_FAIL"
  printf '      this run — a tier that does not exist cannot fire wrongly, cannot move a\n'
  printf '      verdict, and cannot cost a microsecond.\n'
fi
[ "$FAIL_N" -gt 0 ] && { printf 'R3 NOT ACCEPTED\n'; exit 1; }
printf 'R3 ACCEPTED\n'
exit 0
