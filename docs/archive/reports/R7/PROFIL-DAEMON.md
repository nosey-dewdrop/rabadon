# R7 GOAL 2b — the 1583–2063 µs, taken apart

Measurement only. No fix is proposed here and nothing under `native/` was
touched. Every number below is the output of a run whose command is written
next to it.

The operator's standing order: no new decision about the speed claim until the
2b number is decomposed into components. It is decomposed below, exactly,
with a **residual of 0.000 µs** — the buckets are disjoint and they add up to
the total, per request, not approximately.

---

## Method (so it can be re-run)

The established R1.3 instrument (`reports/R1.3/accept.sh` GOAL 4, reused by
`reports/R7/accept.sh` GOAL 2b): the **shipped source is copied to /tmp**, a
`steady_clock` stamp plus an `atexit` dump is patched into the **copy**, and the
copy is compiled there. `native/` is never modified. This round extends that
same instrument to three processes instead of one, and dumps **absolute
`CLOCK_MONOTONIC` nanoseconds** so the three streams can be lined up against
each other (macOS `steady_clock` is system-wide, so cross-process arithmetic is
valid).

Three patched copies, all under `/tmp/dprof/`:

| copy | source | stamps | dump env var |
|---|---|---|---|
| `cli/gate_probe.cpp` | `native/gate.cpp` | top of `main()`, either side of `rbgated::try_daemon(raw)` (gate.cpp:2574), `atexit` | `RABADON_CPROF_OUT` |
| `dmn/gate.cpp` | `native/gate.cpp` | top of `main()` (= `rb_gate_main` after the daemon's `#define`), dump on exit **and** on the return path | `RABADON_WPROF_OUT` |
| `dmn/gated_probe.cpp` | `native/gated.cpp` | after `accept()`, first instruction in the handler child, after `read_request`, before the worker `fork()`, after it, after `waitpid`, after the verdict `write` | `RABADON_DPROF_OUT` |

The worker dump needs the extra `_exit` hook because `run_worker()` ends in
`_exit(rb_gate_main(...))` and `_exit` does not run `atexit` handlers. Requests
are strictly serial, so line *N* of the client, daemon and worker files is the
same request; the analyser asserts the three line counts are equal.

    mkdir -p /tmp/dprof/cli /tmp/dprof/dmn
    cp native/*.h /tmp/dprof/cli/ ; cp native/*.h /tmp/dprof/dmn/
    python3 /tmp/dprof/patch_cli.py    native/gate.cpp  /tmp/dprof/cli/gate_probe.cpp
    python3 /tmp/dprof/patch_worker.py native/gate.cpp  /tmp/dprof/dmn/gate.cpp
    python3 /tmp/dprof/patch_dmn.py    native/gated.cpp /tmp/dprof/dmn/gated_probe.cpp
    c++ -std=c++17 -O2 -I cli -o cli/rabadon-gate-probe   cli/gate_probe.cpp
    c++ -std=c++17 -O2 -I dmn -o dmn/rabadon-gated-probe  dmn/gated_probe.cpp
    bash /tmp/dprof/run3.sh 300 r1      # one measurement round
    python3 /tmp/dprof/an3.py r1        # decomposition + counterfactuals
    python3 /tmp/dprof/spread.py r1 r2 r3 r4 r5 r6   # run-to-run table

`run3.sh` reproduces GOAL 2b's shape exactly — same sandbox (`$H/.rabadon`,
`$PJ/.git/HEAD`, `enabled`), same event (`echo hello world` PreToolUse), 60
untimed warm calls, then N timed calls with the daemon up — and adds two
control arms, **interleaved call by call** so machine drift lands on all three
in the same millisecond:

- **P** — patched client + patched daemon → the decomposition.
- **S** — patched client + the **shipped** `native/rabadon-gated` → the same
  total with no daemon-side probe in it, so the instrument's own cost is a
  measured number and not an assumption.
- **D** — patched client + a dead socket → today's in-process path (the client
  falls back and judges locally).

**Instrument overhead is +88 µs (5.3%)**: arm P 1651.3 µs vs arm S 1563.2 µs in
the same interleaved round. The component table below is arm P, so every daemon
bucket in it is at most that much generous; the conclusion does not depend on
it (see the counterfactuals).

Machine: Apple M2, 8 cores, 8 GB, macOS 15.2, `load averages: 2.4–2.9` during
the six reference rounds. Binaries at working-tree commit `26ea409`.

---

## The component table

Six rounds, 300 samples per arm each, **1800 requests pooled**. "median" is the
median of the six round-medians; "run-to-run" is the min..max of those six.

| # | bucket | what it is | median µs | % of total | p10 | p90 | run-to-run |
|---|---|---|---|---|---|---|---|
| 1 | `b1_client_pre_ipc` | client `main()` start → the socket call (arg checks, `fread` of the event off stdin) | **6.5** | 0.4% | 6.2 | 8.5 | 6.4..7.1 |
| 2a | `b2a_connect_to_accept` | client `socket()`+`connect()` → daemon's `accept()` returns | **16.9** | 1.1% | 12.7 | 21.8 | 16.2..18.6 |
| 2b | `b2b_handler_fork` | **fork #1** — `accept()` return → handler child's first instruction | **160.6** | 10.4% | 151.8 | 193.2 | 159.2..171.5 |
| 2c | `b2c_read_request` | `recvmsg` of the framed payload + the two SCM_RIGHTS fds | **3.4** | 0.2% | 2.9 | 5.6 | 3.2..4.1 |
| 2d | `b2d_pipe_and_parse` | `pipe()` + walking cwd/env out of the body | **2.8** | 0.2% | 2.5 | 3.8 | 2.8..3.1 |
| 3a | `b3b_worker_fork` | **fork #2** — pre-fork → worker's first instruction inside `rb_gate_main` (fork + env replace + `chdir` + 3× `dup2`) | **144.8** | 9.4% | 137.1 | 170.5 | 142.2..151.4 |
| 3b | `b3c_gate_main_judging` | **`rb_gate_main()` itself — the judging** | **1075.1** | **69.7%** | 1004.7 | 1334.4 | 1061.1..1133.9 |
| 3c | `b3d_exit_and_reap` | worker exit/teardown + handler's `waitpid` wakeup (contains the worker's own probe write) | **121.3** | 7.9% | 110.3 | 145.5 | 118.7..127.5 |
| 4a | `b4a_send_verdict` | handler `write()` of the verdict byte | **2.0** | 0.1% | 1.2 | 4.6 | 1.5..2.6 |
| 4b | `b4b_client_wake` | client's blocking `read()` returns | **6.7** | 0.4% | 5.3 | 9.4 | 6.4..7.2 |
| 5 | `b5_client_teardown` | `try_daemon` returns → the probe's `atexit` | **2.0** | 0.1% | 1.8 | 3.0 | 1.9..2.3 |
| | **TOTAL (= the 2b number)** | | **1542.3** | 100% | 1453.7 | 1916.9 | 1527.4..1651.3 |

**Residual (total − sum of the eleven buckets): 0.000 µs, max |residual| 0.000
µs over 1800 requests.** Nothing is unaccounted for.

The three requested buckets, rolled up:

| bucket asked for | µs | share |
|---|---|---|
| 1. client before any IPC | **6.5** | 0.4% |
| 2. the IPC round trip itself (connect, send, recv, verdict — transport only) | **31.8** | 2.1% |
| 3a. daemon plumbing: fork #1 + fork #2 + exit/reap | **426.7** | 27.7% |
| 3b. `rb_gate_main()` — the judging | **1075.1** | 69.7% |

### What the two forks actually cost

- fork #1 (handler): **160.6 µs**
- fork #2 (worker, incl. env replace + chdir + dup2): **144.8 µs**
- the same `fork()` measured from the **parent's** side (call → return, no child
  scheduling): **76.0 µs** — an independent second reading of the same event,
  consistent with the child-observed number once the child's first-schedule
  latency is included.
- **two forks = 305.4 µs = 19.8% of the 2b number.** Add the exit/reap they
  force (121.3 µs) and the daemon's process scaffolding is **426.7 µs, 27.7%**.

So the documented suspect (`native/gated.cpp:19-24`) is real and it is
expensive. It is also **not sufficient to explain the red**, which is the
finding this round exists to deliver:

| counterfactual (computed per request, then medianed — medians not added) | µs | vs the 1000 µs ceiling |
|---|---|---|
| total as measured | 1651.3 | OVER |
| if the second (worker) fork were free | 1490.8 | OVER |
| if **both** forks were free | 1312.6 | OVER |
| if **all** daemon scaffolding (both forks, all IPC, reap, verdict) were free | 1144.5 | OVER |
| the judging alone | 1133.9 | OVER |

(Counterfactual column is arm P, which carries the +88 µs instrument overhead;
subtracting it moves nothing across the line.)

**Deleting both forks and the entire IPC path leaves ~1144 µs and GOAL 2b is
still red.** The ceiling is missed by the judging, not by the daemon.

### And the daemon buys nothing inside `main()`

`native/gated.cpp:11-17` argues the warm worker inherits code pages, heap and
warm file cache copy-on-write. Measured, warm worker vs cold process, same
event, interleaved, six rounds:

| | µs |
|---|---|
| warm forked worker, `rb_gate_main()` | **1075.1** |
| cold process (arm D, daemon down), the same span | **1067.4** |
| delta | **+7.7 µs** — the warm worker is, if anything, marginally *slower* |

Per-round deltas: +28.1, +15.1, +23.9, +6.6, −8.8, +43.8 µs.

Arm totals in the same interleaved rounds: **daemon up 1563.2 µs (arm S) vs
daemon down 1121.3 µs (arm D)** — the daemon costs **+442 µs** on this ruler.
That reproduces deneme 3's +457 µs and now has a line-item explanation for it:
426.7 µs of scaffolding plus ~32 µs of transport.

This does **not** say the daemon is worthless end-to-end: the ~2.3 ms of
fork/exec/dyld it removes is outside this instrument's window by construction
(`reports/R7/accept.sh:18-31` forbids the end-to-end ruler for the <1 ms
claim). It says the daemon cannot move the number GOAL 2b reads.

---

## The spread: 1704.4 → 1583.2 → 2063.1 µs, and 4.98% → 1.92% → 3.51%

Four candidates were named. Here is what each one measured.

### RULED OUT — sample count too low

Bootstrap (2000 resamples) of the median, within a single round:

| n per arm | 95% CI of the arm-S median | width |
|---|---|---|
| 300 | 1545.8 .. 1589.2 µs | **43.4 µs (2.8%)** |
| 1000 | 1954.7 .. 1977.2 µs | **22.5 µs (1.1%)** |

Sampling error at n=300 is ±1.4%. The observed movement is ±30%, twenty times
larger. Confirming: two rounds at **n=1000** still differed by **6.5%** from
each other (1966.3 vs 2094.6 µs) — a 3.3× increase in samples cut the sampling
CI in half and left the run-to-run spread untouched. Between-round variance
exceeds sampling variance by an order of magnitude, so it is not sampling.

### RULED OUT — the interleave failing to cancel drift

Per-fifth medians of the three interleaved arms inside one round (r1):

    fifth 1  P=1719.3  S=1718.5  D=1160.3
    fifth 2  P=1724.8  S=1672.5  D=1158.7
    fifth 3  P=1545.0  S=1515.4  D=1064.8
    fifth 4  P=1548.5  S=1513.6  D=1080.2
    fifth 5  P=1718.7  S=1588.5  D=1149.9

The arms rise and fall **together**, so the interleave does cancel drift for
arm-vs-arm comparisons. (Per-call Pearson r between arms is ~0.05–0.13: the
drift lives on a seconds-scale, not per call, which is why block medians move
together and individual calls do not.) But GOAL 2b does not compare two arms —
it compares one absolute median to a fixed 1000 µs ceiling, and **an interleave
cannot cancel drift out of an absolute number.** The interleave is not broken;
it is irrelevant to 2b.

### CONFIRMED, and it is the whole effect — background load

Same binaries, same harness, same n, only the machine's load changed:

| round | 1-min load avg during the round | arm S median (daemon up) | arm D median (no daemon) |
|---|---|---|---|
| r2, r3, r4, r5 | 2.4 – 2.6 | 1477.1 / 1503.2 / 1508.6 / 1514.2 | 1059.8 – 1088.9 |
| r1, r6 | 2.9 | 1563.2 / 1565.6 | 1103.4 / 1121.3 |
| n1, n2 (n=1000) | 5.4 – 5.5 | **1966.3 / 2094.6** | 1349.2 / 1445.6 |
| load2 (2 spinners) | 8.0 | 2652.1 | 3718.7 |
| loadcc (a concurrent `c++ -O2` of the same file) | 8.4 | 3135.1 | 3267.3 |
| load (8 spinners, one per core) | 8+ | 5409.1 | 4240.1 |

The three sealed numbers — 1583.2, 1704.4, 2063.1 — sit exactly on that curve
between load ≈2.5 and load ≈5.5. **2063.1 µs is what this machine returns at
load ~5.5, reproduced twice (1966.3, 2094.6).** No other hypothesis is needed
to produce a 30% band, and this one produces it on demand.

Note that `reports/R7/accept.sh` compiles the probe with `c++ -O2` **immediately
before** GOAL 2b times 300 calls, and the `loadcc` row is exactly that
condition: a concurrent optimising compile of this same file doubles the
reading. Any other work on the box during an acceptance run lands directly in
the 2b number.

### CONFIRMED as an amplifier — fork cost variance under contention

The fork buckets are by far the most load-elastic part of the request:

| bucket | load 2.6 | load 8.0 (2 spinners) | 8 spinners | elasticity |
|---|---|---|---|---|
| `b2b_handler_fork` | 159.2 | 294.4 | **1308.9** | ×8.2 |
| `b3b_worker_fork` | 143.0 | 257.9 | **1272.0** | ×8.9 |
| `b3c_gate_main_judging` | 1061.1 | 1865.0 | 2560.3 | ×2.4 |
| `b3d_exit_and_reap` | 121.1 | 160.9 | 264.9 | ×2.2 |
| TOTAL | 1527.4 | 2690.9 | 5482.1 | ×3.6 |

So "fork cost variance under memory/CPU pressure" is real and it is the largest
multiplier in the request — but it is an amplifier of the load effect, not an
independent cause: at the loads the sealed runs actually saw (2.5–5.5) the forks
contribute ~305 µs of a ~1540 µs number and the judging still dominates.

### The 2c number (4.98% / 1.92% / 3.51%) — same cause, worse odds

2c is a difference of two medians, each carrying the run-to-run instability
above, divided by a denominator the daemon has already shrunk. With ±1.4%
sampling error on each arm at n=250 and a several-hundred-µs load band on top,
a 2–5% divergence is inside the instrument's own noise. **This round did not
re-measure 2c with more samples** — see NOT MEASURED.

### Verdict on the spread

The 2b **verdict** is not in question at any load this machine reached: the
quietest round measured on a near-idle box was **1477.1 µs**, still 48% over the
1000 µs ceiling, and the decomposition shows the judging alone is 1075 µs. The
2b **number** should be read as "≈1500 µs on an idle M2, rising to ≈2100 µs at
load 5.5, ≈2700 µs at load 8" — a single figure quoted to one decimal place is
false precision, and the three sealed figures differ from each other only in the
load they were taken under.

---

## NOT MEASURED

- **Where the 1075 µs of judging goes.** This round measured the judging as one
  bucket and stopped there. `reports/R1.3/PROFIL.md` has the last breakdown of
  `main()` (`save#1` ~165 µs, `last_ledger_mode` O(file) with a 32 KB tail
  window, `emit` ~160 µs), but that was a different tree at a different commit
  and it was NOT re-measured here. The single most important follow-up number
  is missing and I am not going to guess at it.
- **Whether the judging is cheaper for a smaller event or a smaller ledger.**
  One event shape (`echo hello world`, PreToolUse, allow path) was used, because
  that is what GOAL 2b uses. Refusal paths, other hooks and other tools are
  unmeasured.
- **2c re-measured with enough samples to be a number.** I diagnosed why it
  moves; I did not run the higher-n rounds that would give it a real value or a
  real confidence interval.
- **The loads under which the three sealed numbers were actually taken.**
  `accept.sh` records no load average, so the correlation above is between my
  rounds and my loads. That the sealed numbers *lie on* that curve is strong,
  but it is inference, not the same measurement. **NOT DIRECTLY VERIFIED.**
- **Thermal / DVFS state.** An M2 under sustained load clocks down. This is not
  distinguishable from "load" with the instruments used here, and no attempt was
  made to separate them.
- **Memory pressure specifically.** The load experiments were CPU spinners and a
  compiler. Memory pressure was never induced, so "fork cost under memory
  pressure" is confirmed only for CPU contention.
- **Any machine other than this one.** Every microsecond here belongs to one
  8-core M2 with 8 GB, macOS 15.2. Linux forks and schedules differently; the
  fork buckets in particular should not be assumed to transfer.
- **What the daemon saves end-to-end.** The ~2.3 ms of fork/exec/dyld it removes
  is outside this instrument's window on purpose, and the end-to-end ruler is
  forbidden for the <1 ms claim, so the daemon's real user-visible benefit is
  still unmeasured — as it was after deneme 3.
- **A serialised (one-fork or zero-fork) daemon.** The counterfactual columns
  above are arithmetic on measured buckets, not a build. Nobody has run a daemon
  with fewer forks, and a counterfactual is not a measurement.
- **`native/gate.cpp:720` `open_sock()`'s silent `strncpy` truncation.** Open
  since deneme 1, untouched again this round.

---

## Files

Probe sources, patch scripts, harness and raw dumps: `/tmp/dprof/`
(`patch_cli.py`, `patch_worker.py`, `patch_dmn.py`, `run3.sh`, `an3.py`,
`spread.py`, `out.<tag>/{cli.P,cli.S,cli.D,dmn,wrk,load.before,load.after}`).
Nothing under `native/`, `reports/R7/accept.sh`, any test, `PROJECT.md` or
`KOSU-RABADON*.md` was modified. Nothing was committed.
