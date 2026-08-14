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

# The suites below stub `claude` and assert the judge path runs. RABADON_JUDGE=0
# switches that path off, and it is a perfectly ordinary thing to have exported
# — this repo's own ~/.claude/settings.json sets it, so the maintainer's shell
# carries it. Inherited here it turned 17 passing cases into failures and this
# page reported `44 ok, 17 fail` on a tree whose gate was fine. A reproduction
# script that reads the environment is not reproducing anything; the harness
# owns this variable, so it is cleared for the whole run.
unset RABADON_JUDGE

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

line "done"
printf 'BENCHMARK.md holds the figures these commands reproduce.\n'
printf 'No git add / commit / push was run — the human reviews and commits.\n'
