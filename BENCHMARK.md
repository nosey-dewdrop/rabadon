# rabadon — the numbers, measured not claimed

rabadon is a local, fail-closed gate that sits on every coding-agent action
(as a PreToolUse hook), stops a bad call before it spends, and carries a bounded
repair loop plus its own ledger — one budget, on-machine, no data leaves.

Every figure below was reproduced on this machine this session by
`bench/reproduce.sh`. Nothing here is hand-written or rounded up. Where a
counter is 0 it says 0 — that is the honest state, not a gap hidden.

Machine: Apple M2, arm64, macOS (Darwin 24.2.0). Toolchain: Apple clang 17.0.0,
node v26.5.0, python 3.14.6. Reproduce all of it:
`RABADON_NOTIFY=0 bench/reproduce.sh`.

Markers: `[proven]` runs on real projects here, `[building]` proven in-suite
but not yet on real breakage, `[ahead]` not built.

---

## 1. Gate latency — the hook tax on every action  `[proven]`

The gate runs on every coding-agent tool call (PreToolUse hook), on the
critical path, so it has to be cheap. `native/bench.py` builds a scratch project
with one guard rule, feeds the same hook events to two gates, first proves
verdict parity (identical exit codes — a fast wrong gate is worthless), then
times each over 40 runs per case.

- native — `native/rabadon-gate` (the C++ core)
- node — `hooks/gate.mjs` (the legacy Node gate)

Parity held: native == node on both verdicts (allow=0, deny=2). It only holds
because the harness now ARMS the isolated home it benchmarks in. `RABADON_DIR`
relocates the whole rabadon home, mode flags included, so a fresh temp home
starts in WATCH — where the native gate records a deny and exits 0 while the
node gate, which has no watch mode, exits 2. That read as a parity break for as
long as the isolation existed; it was an unset switch, and a bench that leaves
it unset is timing a gate nobody runs.

| gate   | case  | median    | p95       | n  |
|--------|-------|-----------|-----------|----|
| native | allow | 2.29 ms   | 3.36 ms   | 40 |
| native | deny  | 2.33 ms   | 2.53 ms   | 40 |
| node   | allow | 100.77 ms | 112.49 ms | 40 |
| node   | deny  | 102.00 ms | 125.23 ms | 40 |

Median hook tax drops from ~101 ms (node process startup dominates) to 2.3 ms
(native) — 44x faster at the median. Medians are stable run to run (five runs
this session: native allow 2.44 / 2.36 / 2.31 / 2.26 / 2.29 ms, node allow
100.49 / 99.87 / 99.88 / 100.78 / 100.77 ms). The native p95 is noisier on a
laptop (scheduler / spawn jitter) — the median is the robust number.

Every latency figure in README.md and docs/ is this table's number. There is no
second source, and there is no rounding in either direction.

One path is deliberately not 2.3 ms: a `git push` after code changed since the
last green test run makes the gate run the project's suite inside that same
hook call. That is bounded by `pushGate.timeoutSec` (default 900 s), and the
installed hook ceiling sits above it at 960 s on purpose — if the outer timeout
fired first, the action would be neither allowed with a verdict nor refused
with a reason.

Command: `RABADON_NOTIFY=0 make bench`.

---

## 2. Correctness — node == native parity, and the native suite  `[proven]`

`native/postuse_test.sh` pipes identical hook JSON into BOTH the node oracle
(`node hooks/gate.mjs`) and the native gate (`native/rabadon-gate`) and asserts
the SAME verdict (exit code) + state.json + spool. 13 of those cases are
explicit node-vs-native differentials:

- 9 dual-engine `differential()` cases (equal exit / state / spool),
- 3 BR2 asserts (exit-2 on both, stderr names all 5 dirs on both, stderr
  byte-identical node==native),
- 1 BR11 twin-dedupe (node==native).

Result: 13/13 node-vs-native cases produced the same verdict + state + spool
= 100% parity, 0 divergences.

Suite totals, reconfirmed this session:

| suite                | result           | node==native? |
|----------------------|------------------|---------------|
| `postuse_test.sh`    | 53 ok, 0 fail    | yes — 13 differential cases |
| `pushgate_test.sh`   | 9 ok, 0 fail     | no — native-only push-gate proof (invokes node 0 times) |

`pushgate_test.sh` is a native-only push-gate proof, NOT a node==native
differential — `grep -cE 'node ' native/pushgate_test.sh` = 0. Its 9 passing
cases are native-behavior proofs (a hanging suite is killed and the push
blocked, etc.), not oracle-parity comparisons.

Commands:
`RABADON_NOTIFY=0 ./native/postuse_test.sh` → `gate postuse: 53 ok, 0 fail`
`RABADON_NOTIFY=0 ./native/pushgate_test.sh` → `gate push: 9 ok, 0 fail`

---

## 3. The ledger — rabadon's own word about what it caught  `[proven]`

`rabadon usage --days 30` aggregates the local spool (`~/.rabadon/spool/`). It
excludes its own drills, demos and self-tests at emit — 3,495 events in this
window — so a tool that counts its own test runs as catches never happens here.
59 projects, one machine, real work:

| view                    | actions gated | caught before happening | would have caught (watch) | checks failed | loops stopped |
|-------------------------|---------------|-------------------------|---------------------------|---------------|---------------|
| all projects (30 days)  | 15,188        | 61                      | 68                        | 314           | 2             |

Biggest signal, by project:

| project     | actions gated | caught before happening | checks failed | loops stopped |
|-------------|---------------|-------------------------|---------------|---------------|
| stitchu     | 4,196         | 43                      | 107           | 2             |
| rabadon     | 3,640         | 12                      | 112           | 0             |
| (home)      | 2,162         | 3                       | 27            | 0             |

What was caught on stitchu (verbatim rule ids from the ledger): `push-gate` 14x
(code edited after the last passing test run), `no-rm-rf-outside-project` 9x,
`no-wrangler-deploy` 6x, `generated-web-html` 5x, `ctest-tail-hides-verdict` 3x,
`loop-stop` 2x, `test-tamper` 2x (assertions being removed from
`test_style.cpp` while the suite was red), `golden-reference` 1x,
`no-force-push-main` 1x.

### The repair counter, split — and what the split cost

This page used to carry one number called **repairs accepted**, and it was 0,
and that was reported as honesty. It was worse than a wrong number: it was one
bucket holding four different events, because `REPAIR_OK` is emitted by the
push gate when a suite goes green, by the gate when a new rule is written, and
by the repair path whether or not any test file was hash-locked while the fix
was re-checked. Counting those together means the headline can grow without a
single line of code ever being repaired.

Split by what actually happened:

| bucket                                        | 30 days |
|-----------------------------------------------|---------|
| repairs **held** — fix re-checked with test files hash-locked | **0** |
| repairs unverified — nothing was locked, so nothing witnessed it | 3 |
| push gates passed — a suite ran green, nothing was repaired    | 0 |
| rules written — law was authored, nothing was repaired         | 1 |

The three that used to read as "repairs accepted" are all unverified, all on
stitchu. The number that sells the product — a fix proven against test files
that provably did not move — is still **0**, and it stays on this page as 0
until it isn't.

Command: `RABADON_NOTIFY=0 rabadon usage --days 30`.

Note: the bench harness writes to an ISOLATED spool (`RABADON_DIR` per run), so
bench drills do not inflate this ledger. The stable facts this page rests on:
node/native parity held, stitchu is the largest real signal, and repairs-held is
0 across the board.

---

## 4. Where rabadon sits (only repo-backed claims)

| tool                | integration        | can stop a bad call?                     | can repair it? | scope              |
|---------------------|--------------------|------------------------------------------|----------------|--------------------|
| Langfuse            | wrap client        | no — passive by design ("only logs")     | no             | tracing / evals    |
| Braintrust          | wrap client        | no — passive tracer                      | no             | tracing / evals    |
| Galileo             | inline gate        | yes — block / canned override            | no             | one call           |
| **rabadon**         | wrap / hooks / CLI | **yes — inline, fail-closed, pre-spend** `[proven]` | **bounded, re-checked — proven in-suite, 0 on real breakage** `[building]` | session + pipeline, one budget, local-only |

Passive tracers (Langfuse, Braintrust) wrap the client and watch; they cannot
stop a bad call and cannot repair it. Galileo's inline gate CAN stop a call
(block or canned override) but does not repair. rabadon is inline, fail-closed,
pre-spend on real projects (61 real catches in 30 days: stitchu 43, rabadon 12,
drills excluded), overhead is deterministic C++ at 2.3 ms. The repair loop is
proven in the test suite but has held 0 hash-locked repairs on real breakage so
far.

---

## 5. Not yet — the next gate

**repairs held = 0.** `[building]`

That number is 0 on every project here, drills included. The repair path is
proven in-suite (a real repair is accepted, a gamed repair is rejected and the
loop fails closed) but has never held a hash-locked repair on real, non-demo
breakage. The 3 the ledger does carry are unverified — the anti-tamper check
had no test file to hold, so nothing witnessed them, so they do not count. G3 —
the first HELD repair on real breakage, moving that counter above 0 — is the
next gate. It stays 0 on this page until it isn't.

---

## Reproduce everything

```
RABADON_NOTIFY=0 bench/reproduce.sh
```

Numbers vary slightly with machine load. The reproducible facts: 2.3 ms native
gate median, 44x median gap over node, 13/13 node==native parity + 53/0 and
9/0 native suites, 55 real catches on stitchu+rabadon in 30 days (drills
excluded), and repairs-held = 0.
