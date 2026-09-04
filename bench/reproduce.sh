#!/usr/bin/env bash
# Reproduce every number on BENCHMARK.md, in order.
#
# Runs the exact commands the page cites and prints the same figures:
#   1. gate latency  — native C++ gate vs legacy node gate (make bench)
#   2. node==native parity + native suites (postuse, pushgate)
#   3. the ledger (rabadon stats --days 30)
#
# Read-only except for build artifacts. RABADON_NOTIFY=0 on every command so no
# macOS notification ever fires. Does NOT commit, add, or push — the human does.
set -u

export RABADON_NOTIFY=0

# The suites below stub `claude` and assert the judge path runs. Inherited from
# the maintainer's shell this variable once turned 17 passing cases into
# failures and this page reported `44 ok, 17 fail` on a tree whose gate was
# fine. A reproduction script that reads the environment is not reproducing
# anything.
#
# `unset` was the right fix while the judge defaulted to ON. It defaults to OFF
# now, so unset would mean those cases quietly assert nothing — the same bug
# with the sign flipped. State the value, in both directions.
export RABADON_JUDGE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

line() { printf '\n===== %s =====\n' "$1"; }

# Toolchain the numbers were taken on (printed for the reader to compare).
line "machine + toolchain"
printf 'uname   : %s\n' "$(uname -sm)"
printf 'node    : %s\n' "$(node --version 2>/dev/null || echo 'n/a')"
printf 'python3 : %s\n' "$(python3 --version 2>/dev/null || echo 'n/a')"
printf 'clang++ : %s\n' "$(clang++ --version 2>/dev/null | head -1 || echo 'n/a')"

# 1. Gate latency. make bench builds the native gate if needed, then runs
#    native/bench.py: same hook events into both gates, verdict parity first,
#    then median/p95 over 40 runs per case.
line "1. gate latency  (native C++ gate vs legacy node gate, 40 runs/case)"
RABADON_NOTIFY=0 make bench

# 2. node==native parity + native suites. postuse pipes identical hook JSON into
#    BOTH node oracle and native gate and asserts same verdict+state+spool
#    (13 node==native differential cases). pushgate is a native-only push proof.
line "2a. postuse suite  (node==native differential; expect 61 ok, 0 fail)"
RABADON_NOTIFY=0 ./native/postuse_test.sh | tail -1

line "2b. pushgate suite (native-only push proof; expect 11 ok, 0 fail)"
RABADON_NOTIFY=0 ./native/pushgate_test.sh | tail -1

line "2c. pushgate node invocations  (expect 0 — it is native-only)"
printf 'node invocations in pushgate_test.sh: %s\n' \
  "$(grep -cE 'node ' native/pushgate_test.sh)"

# 3. The ledger. Read-only aggregation of ~/.rabadon/spool. The tool already
#    excludes its own self-drills/demos at emit; this prints the full report so
#    the reader can see stitchu/rabadon (real) vs rabadon-bench-* (synthetic).
#    This said `stats`, which routed to a retired JS reader printing a counter
#    BENCHMARK.md no longer has — reproducing a page against a different engine.
line "3. ledger  (rabadon usage --days 30; repairs HELD must read 2 — express, 91 files locked)"
RABADON_NOTIFY=0 node bin/rabadon.mjs usage --days 30

# 4. R7's two-armed run (arm A: the agent alone; arm B: the agent + rabadon).
#    This one is NOT read-only and NOT free: it clones SWE-smith mirror repos,
#    builds a venv per task and spends real agent sessions, so it is opt-in.
#    Set R7_RUN=1 to actually re-run it. Without that it only reports the state
#    of the raw record, which is what the numbers are read from.
line "4. R7 two-armed run  (arm A vs arm B on SWE-smith; raw record + re-run)"
R7_JSONL="$ROOT/docs/archive/reports/R7/ab_run.jsonl"
if [ "${R7_RUN:-0}" = 1 ]; then
  printf 're-running the two-armed run (this spends agent sessions)...\n'
  RABADON_NOTIFY=0 "$ROOT/docs/archive/reports/R7/ab_run.sh"
else
  printf 'skipped the re-run (set R7_RUN=1 to spend the sessions and redo it).\n'
  printf 'harness  : docs/archive/reports/R7/ab_run.sh\n'
  printf 'pre-reg  : docs/archive/reports/R7/ON-KAYIT.md   (frozen before the run)\n'
fi
if [ -s "$R7_JSONL" ]; then
  python3 - "$R7_JSONL" <<'PY'
import json,sys,collections
rows=[]
for l in open(sys.argv[1]):
    l=l.strip()
    if not l: continue
    try: rows.append(json.loads(l))
    except Exception: pass
by=collections.defaultdict(list)
for r in rows: by[str(r.get("arm","?")).upper()].append(r)
print(f'raw records: {len(rows)}')
for a in sorted(by):
    R=by[a]; fixed=[r for r in R if "heldout_pass" in r]
    rate=(sum(1 for r in fixed if r["heldout_pass"])/len(fixed)*100) if fixed else float("nan")
    tok=sum(r.get("tokens",0) or 0 for r in R)
    print(f'  arm {a}: {len(R)} tasks | held-out fix rate {rate:.1f}% | tokens {tok}')
PY
else
  printf 'no raw record yet at docs/archive/reports/R7/ab_run.jsonl — the run has not produced rows.\n'
fi

line "done"
printf 'BENCHMARK.md holds the figures these commands reproduce.\n'
printf 'No git add / commit / push was run — the human reviews and commits.\n'
