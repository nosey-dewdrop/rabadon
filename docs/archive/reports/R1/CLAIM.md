# R1 — CLAIM

**Round:** R1, the move record.
**Date:** 2026-08-22.
**Proof command:** `./native/moves_test.sh` → `moves: 21 passed, 0 failed`.
**Regression:** `make test` → exit 0, **2036 passing, 0 failing** (R0 baseline 2015; the 21 new ones are this round's).

## What was built

`native/moves.h` plus three wiring points in `native/gate.cpp`. The session now
carries `moves` — the last 200 things it did, oldest first, raw text on the
newest 50 — in its own file under `.rabadon/sessions/`. Tier-0 signature:
whitespace collapsed, project root stripped, scratch directories masked,
**numbers kept** (`--port 3000` and `--port 8080` are different commands, and
masking digits would collapse the one difference that matters).

No detection. No injection. No branch in gate.cpp reads `moves` to decide
anything. `RABADON_MOVES=0` turns it off.

## The one number that is worse, said plainly

Recording is free of side effects on the **verdict**. It is **not free in
latency**, and the round does not get to claim otherwise.

Measured on this machine, 250 invocations per arm, same event, warm:

| arm | ms/call |
|---|---|
| recording off (`RABADON_MOVES=0`) | 4.58 |
| recording on, empty ring | 6.04 |
| recording on, ring full (200 moves) | **6.36** |

**+1.78 ms, about +39%, at a full ring.**

Cause is known and is mine: the recorder calls `stt.save()` immediately rather
than at the end of the branch, because every refusal path returns early and a
record that only survives the allow path is a record of the wrong half of the
session. So a full session file — 200 moves, 50 of them carrying raw text — is
serialised and written on every tool event, and on some paths written twice.

**This is not comparable to the 3.1 ms median in BENCHMARK.md.** That is a
different harness on a different fixture; the honest comparison is the two arms
above, measured against each other, minutes apart, on one box. No published
number is restated or revised on the strength of this measurement.

Against KOSU-RABADON.md's target for the accumulation engine — under 1 ms — the
recorder as written does not meet it, and R1 was not the round that was supposed
to. R7 is (daemon, persistent process, no per-event process start). Booked there,
with the cheaper fix named so it is not rediscovered: make `save()` dirty-tracked
so one event writes the session file once instead of twice, and measure again
before assuming the daemon fixes it.

## Decisions taken, so they are arguable later

**The suite verdict reuses the existing classifier.** Whether a command was a
test run, and whether it passed, is answered in exactly one place in gate.cpp —
the one with the hard-won exceptions (a stated `EXIT=0` outranks a loose failure
word; a self-counted zero outranks it too; a crash string cancels a green). R1
stamps that verdict onto the move rather than computing a second opinion beside
it. A second answer to one question is a hole, and the weaker answer is the one
the signals would end up reading.

The cost of that choice, accepted knowingly: the default recogniser for "is this
a test run" is `ctest|--test|npm test`, so `pytest -q` is not one unless the
project's guard says so. Moves from unrecognised test commands keep `suite = -1`.
Widening that recogniser is a change to the classifier and belongs to whoever
owns it, not to the recorder.

**`claimed_rc` is inferred from output text and named for what it is.**
PostToolUse carries no exit status. The field is a claim the session makes about
its own work, and the name says so at every read site.

**A missing key reads as unknown, not as zero.** A session file written by an
older build has no `suite` or `claimed_rc`; `get_num` returns 0 for an absent
key, and 0 means *green* and *succeeded*. Reading absence as success would
invent results nobody measured, so both are forced back to -1 when the key is
not in the text.

## Two tests that were wrong, and were fixed rather than satisfied

**`moves_test.sh` passed three assertions vacuously** on the first run: "raw
carried for at most 50" and "oldest seq is not 0" are both satisfied by having
no moves at all, and the fixture was in watch mode, so "identical exit codes with
recording on and off" was comparing two allow paths that both returned 0 and
refused nothing. All three now require the record to be non-empty, and a guard
assertion fails loudly if the force-push ever stops exiting 2.

**One assertion was wrong about the product, not the code.** It expected
`4 passed in 0.12s` to be recorded as a green suite. The classifier deliberately
requires *evidence* of a pass and treats "the pattern did not match" as unknown.
Loosening it would have been weakening a check to satisfy a test I wrote an hour
earlier. The fixture now speaks the classifier's language instead.

## What was changed outside R1's own files, and why

`native/postuse_test.sh` — the differential against the retiring node gate — now
excludes `moves` and `nextSeq`, in its own commit ahead of the code, with the
reason in the file. That file compares parity of *meaning* (same verdict, same
shared facts) and already drops the leaked `s` alias and `recentEv` for the same
kind of reason. R1's record is state the node engine never had and never will;
comparing it would assert that the surviving engine may not learn anything the
retired one did not know. The record is asserted in full by `moves_test.sh` — the
assertion moved, it was not dropped.

`Makefile` — `native/moves.h` added to the gate's prerequisites. It was missing,
which means an edit to the header would have answered `make` with "up to date"
and shipped the previous binary. This repo has been bitten by exactly that twice
before (see the comments above the `rabadon-gate` and `rabadon-sandbox` rules).

## NOT VERIFIED

- Any of this on Linux, or on a clean machine. macOS only.
- The latency numbers on a fast disk or under a different filesystem. One box,
  one run of 250 per arm, no repetition across boots.
- Behaviour when two sessions write moves concurrently. The session file is
  single-writer by design (that is why per-session files exist), but R1 did not
  test the fan-out case; `native/session_fanout_test.sh` covers the layout, not
  the record.
- Cursor's dialect. The recorder reads the normalised `HookEvent`, so it should
  follow for free, and "should" is not a measurement.
- Whether 200 and 50 are the right caps. They are asserted, not justified by
  data; R2 is the round that will have the data.

## NEXT

R2 — five detectors over this record, silent mode: computed, written to the
spool, shown to nobody. The point of the silence is to measure the false
positive rate before anything is allowed to enforce (Law 1).
