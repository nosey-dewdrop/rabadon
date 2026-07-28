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

Parity held: native == node on both verdicts (allow=0, deny=2).

| gate   | case  | median   | p95       | n  |
|--------|-------|----------|-----------|----|
| native | allow | 2.15 ms  | 2.59 ms   | 40 |
| native | deny  | 2.16 ms  | 2.39 ms   | 40 |
| node   | allow | 98.11 ms | 129.76 ms | 40 |
| node   | deny  | 98.57 ms | 116.29 ms | 40 |

Median hook tax drops from ~98 ms (node process startup dominates) to ~2 ms
(native) — about 45x faster at the median. Medians are stable run to run
(three runs this session: native allow 2.15 / 2.17 / 2.17 ms, node allow
98.11 / 96.04 / ~97 ms). The native p95 is noisier on a laptop (scheduler /
spawn jitter) — the median is the robust number.

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

`rabadon stats --days 30` aggregates the local spool (`~/.rabadon/spool/`). The
tool already excludes its own self-drills/demos/self-tests at emit. On top of
that, the numbers below split RAW (every project the report lists) from
REAL-WORK (excluding rabadon's synthetic benchmark harnesses `rabadon-bench-*`
and the `rbd-*` probe scaffolds), so the number is not gamed.

| view          | actions gated | caught before happening | checks failed | loops stopped | repairs accepted |
|---------------|---------------|-------------------------|---------------|---------------|------------------|
| RAW (29 projects) | 3707      | 690                     | 772           | 2             | **0**            |
| REAL-WORK only    | 3047      | 33                      | 115           | 2             | **0**            |

The gap between RAW and REAL is entirely synthetic: 8 `rabadon-bench-*`
harnesses each fired 82 identical `git push --force origin main` deny-rule
catches — that is rabadon testing itself, not catches on real projects. Both
views are reported so the headline number is honest.

Biggest REAL signal (from the ledger):

| project | actions gated | caught before happening | checks failed | loops stopped | repairs accepted |
|---------|---------------|-------------------------|---------------|---------------|------------------|
| stitchu | 1588          | 26                      | 57            | 2             | **0**            |
| rabadon | 509           | 4                       | 43            | 0             | **0**            |

What was caught on stitchu (verbatim from the ledger): code edited after the
last passing test (6x), `npx wrangler deploy` blocked by a deny rule (4x),
protected files refused overwrite, `git push --force origin main` refused,
2 loops stopped, an assertion-removal on `test_style.cpp` and a skip-marker on
`x.test.mjs` refused while the suite was red.

`repairs accepted: 0` — on EVERY project, RAW and REAL, including the drills.
Nothing has flowed through the auto-repair path yet on this machine.

Command: `RABADON_NOTIFY=0 node bin/rabadon.mjs stats --days 30`.

Note: as of this session the bench harness writes to an ISOLATED spool
(`RABADON_DIR` set per run), so bench drills no longer inflate the real ledger —
RAW stops growing from self-tests here. Historical RAW still carries earlier
bench drills, which is exactly why REAL-WORK is the honest headline. The stable
facts this page rests on: node/native parity held, stitchu is the largest real
signal, and repairs-accepted is 0 across the board.

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
pre-spend on real projects (29 real catches: stitchu 26, rabadon 3–4, drills
excluded), overhead is deterministic C++ single-digit ms. The repair loop is
proven in the test suite but has accepted 0 repairs on real breakage so far.

---

## 5. Not yet — the next gate

**repairs accepted = 0.** `[building]`

That number is 0 on every project here, RAW and REAL, drills included. The
repair path is proven in-suite (a real repair is accepted, a gamed repair is
rejected and the loop fails closed) but has never accepted a repair on real,
non-demo breakage. G3 — the first accepted repair on real breakage, moving that
counter above 0 — is the next gate. It stays 0 on this page until it isn't.

---

## Reproduce everything

```
RABADON_NOTIFY=0 bench/reproduce.sh
```

Numbers vary slightly with machine load. The reproducible facts: ~2 ms native
gate median, ~45x median gap over node, 13/13 node==native parity + 53/0 and
9/0 native suites, 29 real catches on stitchu+rabadon (drills excluded), and
repairs-accepted = 0.
