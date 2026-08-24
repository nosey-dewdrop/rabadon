# R7 — residual length dependence, re-measured with the daemon up

Measured 2026-08-24 by `reports/R7/accept.sh` GOAL 2c. Every number below is
copied from the run, not computed by hand (Law 7); the raw run is
`reports/R7/accept.out`.

## Instrument

The R1.3 in-process probe: a COPY of `native/gate.cpp` patched under `/tmp`
with a `steady_clock` stamp at the top of `main()` and an `atexit` dump, built
there. `native/` is never touched. Two sandboxes are seeded — one to 50
events, one to 400 — BOTH before EITHER is timed, then the two are called
interleaved, one after the other, 250 times each, so clock drift and machine
load land on both arms in the same millisecond.

## Numbers

| session length | in-process median |
|---|---|
| 50 events  | 1665.8 us |
| 400 events | 1748.8 us |

**Divergence: 4.98%.**

Companion number from GOAL 2b, same run, same instrument: the overall
in-process median with the daemon up is **1704.4 us over 300 samples**,
against R7's 1000 us ceiling. That is RED. See `reports/R7/DENEMELER.md`
deneme 4.

## What it means, honestly

R1.3 closed this at 3.5–4.9% under a 10% ceiling, with process spawn IN the
denominator. The prediction written into `accept.sh` was that removing spawn
shrinks the denominator, so the same absolute cost must read as a LARGER
percentage. It did not grow the way that prediction implies — 4.98% sits at
the top of R1.3's band, not above it.

The reason is visible in the 2b number and should not be spun into good news:
the denominator did not shrink. The median under the daemon is 1704.4 us,
which is not a post-spawn cost. `native/gated.cpp` forks TWICE per request,
so the design that was measured re-pays a process cost the daemon was
supposed to delete. Until that is addressed, 2c's percentage is being taken
against a denominator that still contains process creation, and it is
therefore NOT the re-measurement R1.3 asked for. The number is recorded
because the plan requires it to be carried forward; it is not evidence that
the length dependence is under control.

Address named, not fixed here: `reports/R1.3/PROFIL.md:229,277` puts
`save#2` at ~165 us and attributes the residual to `last_ledger_mode()`'s
whole-file fallback being O(file).
