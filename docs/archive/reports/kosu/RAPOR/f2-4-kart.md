# f2-4-kardinalite — the silencer lock's cardinality now comes from the binary

## THE DEFECT, AS FOUND

`native/docs_truth_test.sh:170` held `SITUATIONS='env-off project-off
machine-silent machine-mode project-mode env-mode'`. That list was the fixture
AND the source of the number. A SEVENTH silencer compiled into
`native/gate.cpp` broke nothing: no situation was written for it, the derived
set stayed at six, and every set-equality assertion below went on proving six
things about a gate that had seven. The lock guarded 2026-08-26 and not the day
after.

## WHAT WAS DONE

Two commits, criterion first (CLAUDE.md non-negotiable 2).

1. `30fdc67` — `native/docs_truth_test.sh` only. New section 2b: the set of
   silencers the six situations actually produce (name / where / lifting
   command, normalized) must EQUAL, byte for byte and in all three columns,
   the set `rabadon-gate --silencers` declares. Two directions, two distinct
   refusals: a declared source no situation can build, and a silencer a
   situation produces that the table never declared (a second copy of the
   list). Watched red at this commit — the flag did not exist yet:
   `reports/kosu/RAPOR/f2-4-testonce.out`, `docs truth: 40 ok / 1 fail`.

2. `c8a2ad6` — `native/gate.cpp` only. `kSilencers[SIL_COUNT]`, one table of
   six silencer SOURCES with `<project>` / `$RABADON_DIR` templates, sitting
   next to `struct Muter`. `compute_state` builds EVERY muter it pushes from
   that table via `sil_muter()` — the three file/env muters directly, the three
   mode-layer muters through a `from` -> row mapping. No second copy. A mode
   layer with no row is still DISCLOSED (Promise 1: a hidden silencer is worse
   than a wrongly-labelled one) and is exactly what section 2b's second
   direction goes red on.

   `--silencers` prints that table, tab separated, stable order, and nothing
   else. It reads no project, no env and no file, and returns before any state
   is computed; the hot path has `argc == 1` and never reaches the line. It is
   in `kKnownFlags` and UNLISTED on `--help`, the same way `rabadon statusline`
   is unlisted on the CLI: nobody types it, a machine does. `native/rabadon-cli.sh`
   and `native/cli_test.sh` were not touched, and no product verb was added.

## THE EMPTY-GREEN ROUND (§8.2) — the only real proof of the above

`reports/kosu/RAPOR/f2-4-bosyesil.out`, verbatim, four steps in one file:

- a seventh row `TEMPORARY-SEVENTH / $RABADON_DIR/seventh / rm $RABADON_DIR/seventh`
  added to `kSilencers` and to `SilId`, nothing else touched (the diff is in the file)
- `make all` -> `BUILD=0`; `--silencers` prints SEVEN rows
- `./native/docs_truth_test.sh` -> **`docs truth: 41 ok / 1 fail`, `EXIT=1`**, and
  the refusal names the row: "the binary declares silencer source(s) no situation
  in this file builds: TEMPORARY-SEVENTH ..."
- note, in the same output: the OLD set-equality line still says
  "the table lists exactly the 6 silencer(s) the binary can report" — green.
  That line is the hole this card closed, photographed while it was open.
- `git checkout native/gate.cpp`, rebuild -> `docs truth: 42 ok / 0 fail`, `EXIT=0`.

## THE GATE, ALL OF IT

| command | result | file |
|---|---|---|
| `make all` | `BUILD=0` | f2-4-build.out |
| `./native/docs_truth_test.sh` | `EXIT=0`, **42 ok / 0 fail** (was 40; +2, none removed) | f2-4-docstruth.out |
| `./native/status_truth_test.sh` | `EXIT=0`, 162 ok / 0 fail (unchanged) | f2-4-statustruth.out |
| `./native/cli_test.sh` | `EXIT=0`, 315 passed / 0 failed, five-verb ceiling green | f2-4-cli.out |
| `make test` | `EXIT=0` | f2-4-maketest.out |
| `grep -cE '^[[:space:]]*ok\b' f2-4-maketest.out` | **3748** (baseline 3745, did not fall) | — |
| `grep -oE 'PASS \([0-9]+ checks?\)' … \| awk '{s+=$1}'` | **633** (baseline 633, exact) | — |
| `npm test` | pass 64 / fail 0 | f2-4-npmtest.out |
| `bash reports/R7/accept.sh` | 22 green / 4 red — see below | f2-4-r7accept.out |

The `ok` count moved 3745 -> 3748 = +2 from this card (docs truth 40 -> 42) and
+1 from `moves: 21 passed -> 22 passed`, which is commit `827baa7` (the f2-1
worker), not this card. Command that shows it:
`diff <(grep -oE '^[a-z_ -]+: [0-9]+ (ok|passed)' reports/kosu/RAPOR/f2-0-maketest.out) <(… f2-4-maketest.out)`.

## R7 ACCEPT — 22/4, and why it is not 23/3

- `2b` red as before, and LOWER, not raised: **2537.6 us -> 1239.1 us** median
  (ceiling 1000 us). Repair is out of scope (F3-S1).
- `6e`, `7b` red as before, unchanged.
- `8a` is a NEW red and is NOT from this card: `reports/R7/accept.sh` hardcodes
  `native/moves_test.sh 21 passed`, and commit `827baa7` (f2-1) took it to 22.
  Nothing in this card touches moves. Left alone deliberately — editing another
  worker's acceptance number is exactly the gate redefinition this project refuses.

## NOT VERIFIED

- Clean container / fresh clone: NOT run. Everything above is this mac (darwin
  24.2.0, arm64). `--silencers` reads no file and no env, so nothing about it is
  machine-shaped, but that is an argument, not a measurement.
- Hot-path timing was NOT measured directly for this diff. The argument is
  structural (`argc == 1` never reaches the branch; `sil_muter` runs only when a
  silencer is already in force, i.e. on the path that returns 0 immediately) and
  the only number in evidence is R7 2b's median, which fell.
- `native/gate_bench.sh` was not run.
- The equality in section 2b is over the three columns the SCREEN can show. A
  silencer that silences without ever reaching `s.muters` would be invisible to
  both surfaces; nothing here proves such a path does not exist.

## OUT OF CARD, NOTICED, NOT TOUCHED

- `reports/R7/accept.sh` 8a pins `moves` at 21 and is now red on 22 (above).
- `native/gate.cpp` kHelp does not list `--silencers`; `--wrong` is likewise in
  `kKnownFlags` and unlisted. If a rule ever says every known flag must be on
  the help screen, both are in scope, not just this one.
- `reports/kosu/RAPOR/f2-5-amd64.out`, `f2-5-nonroot.out`, `f2-1-once.out`,
  `f2-1-sonra.out` are untracked in the working tree — other workers' artifacts,
  left exactly as found.
