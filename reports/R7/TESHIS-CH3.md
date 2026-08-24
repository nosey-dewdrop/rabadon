# TESHIS-CH3 — what CHALLENGE-3 asks for, and what it blocks

Tur 11 (2026-08-24). Question put to this round: read `reports/R7/CHALLENGE-3.md`,
report exactly what it demands and whether it blocks — specifically whether it
touches accept.sh GOAL 5/6/7.

**Answer up front: it does not block GOAL 5/6/7. It does not intersect
`reports/R7/accept.sh` at a single line.**

## 1. The file

`reports/R7/CHALLENGE-3.md`, 68 lines, raised tur 8, `Status: OPEN`.

## 2. What it demands, exactly

One thing, and it is documentary, not technical. `KOSU-RABADON-2.md:63-69`
("Mimari kural — soket yolu (24.08)") ends with the sentence

> yol uzunluğu sınırı R7 testinde assert edilir

("the path-length limit is asserted in the R7 test"). At the time it was
written no such assertion existed anywhere. CHALLENGE-3 demands that the
sentence be made true or deleted, via a **human-approved diff to
KOSU-RABADON-2.md, in its own commit**. Its proposed diff (lines 52-63) is
written but explicitly NOT applied. It states it does not touch the invariants
block.

## 3. What has changed since it was raised (the challenge text is now stale)

The technical half is closed. `native/sock_path_test.sh` now exists — born RED
in commit `7d344ee` ("the socket-path-length check that was claimed to exist —
RED") and today it is GREEN:

```
$ ./native/sock_path_test.sh
  ok   - (a) nothing is delivered to the truncated socket path
  ok   - (b) the reason is on stderr — the caller can tell this from 'no watcher'
  ok   - (c) the gate still ran and exited cleanly (rc=0) — spool-only, not dead
sock_path_test: 3 ok
```

It is wired into the default runner — `Makefile:856`, under the `test:` target
(`Makefile:104`), with the incident written above it as a comment. So it is
not an orphan test; `make test` runs it.

What is still open is only the sentence in KOSU-RABADON-2.md, which is *still*
false in a second, smaller way: the assertion lives in `native/sock_path_test.sh`
and in `make test`, **not** in "the R7 test" (`reports/R7/accept.sh`), which
still has no line about it. Document and tree still disagree. CHALLENGE-3
stays OPEN — but as a doc fix awaiting a human, with the risk itself covered.

## 4. Does it intersect accept.sh — and GOAL 5/6/7?

No. Evidence, re-run this round on today's tree:

```
$ grep -niE 'sun_path|ENAMETOOLONG|104|108|path.*(length|len|too long)' reports/R7/accept.sh
>>> no match
$ grep -n 'sock_path_test' reports/R7/accept.sh
>>> no match
```

The GOALs CHALLENGE-3 was suspected of blocking depend on one artifact and one
only — a two-armed per-task JSONL under `reports/R7/`:

| GOAL | accept.sh | what it needs | socket content |
|---|---|---|---|
| 5a/5b/5c | 387-425 | `reports/R7/*.jsonl`, non-empty, arms A and B ≥2 tasks each; `bench/reproduce.sh` naming the R7 two-armed run | none |
| 6a-6e | 431-489 | fields in that same JSONL: `heldout_pass`, token totals, intervention counts, FP rates, `estimated_saved` | none |
| 7a/7b | 492-521 | `fix_A/fix_B/tok_A/tok_B` and `DEV`, all derived from GOAL 6 | none |

`JL="$(ls "$RD"/*.jsonl ...)"` at `accept.sh:387` is the single upstream fact;
every one of the ten reds below falls out of it being empty. The only
length-related work anywhere in accept.sh is GOAL 2c (`accept.sh:145`,
`210-241`), which is *ledger* length dependence — a different quantity, as
CHALLENGE-3 itself says at its lines 24-25.

**Verdict: CHALLENGE-3 blocks the A1 documentation step, nothing else. It is
not in the way of the two-armed run. Treating it as the thing standing in
front of GOAL 5/6/7 is a misread — the thing standing there is the missing
JSONL.**

## 5. Acceptance this round (unchanged, 14 green / 12 red)

```
$ ./reports/R7/accept.sh
== R7 acceptance: 14 green, 12 red
R7 NOT ACCEPTED
```

Correction to `DENEMELER.md`: the count of reds sitting in GOAL 5/6/7 is
**ten**, not nine — 5a 5b 5c, 6a 6b 6c 6d 6e, 7a 7b. The other two are 2b
(median 1273.3 µs vs a 1000 µs ceiling) and 4d (the .git-cleaning /
egress-closing preparation is unrecorded).

## NOT VERIFIED

- Nothing here was run in a clean container; all of it is this macOS machine.
  `sock_path_test.sh` picks CAP=104 on Darwin and 108 elsewhere, but the
  Linux branch has never executed.
- Whether a human has *seen* CHALLENGE-3 is unknown. "Awaiting human approval"
  is the file's own status line, not an observed fact about a human.
- The proposed diff at CHALLENGE-3:52-63 was not applied and was not tested
  for whether it still applies cleanly to today's KOSU-RABADON-2.md.
- No two-armed run was attempted this round, so the ten GOAL 5/6/7 reds are
  diagnosed by reading accept.sh, not by producing data and watching them turn.
