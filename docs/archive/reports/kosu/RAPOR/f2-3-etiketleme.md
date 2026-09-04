# f2-3-etiketleme — per-signal measurement and hand-labelling on the frozen corpus

Scope note (S7 / §4.12): every claim below is layer (a) only — **what rabadon
WROTE DOWN**. Nothing here claims a signal caught, saved or prevented anything.
No counterfactual number appears (§4.6). Whether an agent's behaviour would have
changed is F3's question, not this card's.

Task 0 commit: `9cba3cd` (accept.sh 8a, 21 -> 22, alone in its commit).
Measurement script: `reports/kosu/RAPOR/f2-3-olcum.py`.
Raw output: `reports/kosu/RAPOR/f2-3-olcum.out`.
R7 run: `reports/kosu/RAPOR/f2-3-r7accept.out`.

---

## 0. The acceptance deviation this phase caused, and its fix

`reports/R7/accept.sh:543` pinned `native/moves_test.sh` at exactly
`moves: 21 passed, 0 failed`. Commit `827baa7` added CLAIM 8 (the reader counts
and names every export line it could not parse), required by acceptance item
F2-S5/d. Count went 21 -> 22, **no assertion deleted, renamed, skipped or
weakened** — `git show 827baa7 -- native/moves_test.sh` is additions only.

Fixed in its own commit `9cba3cd`: constant 21 -> 22. **Exact equality kept**;
`>=` was NOT used, because equality is the thing that catches an assertion being
removed later.

Proof, `bash reports/R7/accept.sh`:

    == R7 acceptance: 23 green, 3 red
    red names: 2b, 6e, 7b

The red set is back to `{2b,6e,7b}` — the same set as before this phase, not
grown (§8.3).

**`8b` carries the identical trap and is named out loud here:**
`reports/R7/accept.sh:548` pins `native/signals_test.sh` at exactly
`signals: 39 passed, 0 failed`. It is GREEN today and was NOT touched. The next
assertion added to `native/signals_test.sh` will turn `8b` red the same way `8a`
went red, and it must be updated the same way — number moved, equality kept, own
commit, measured reason.

---

## 1. The corpus itself (S4)

Source: **the frozen snapshot** `~/.rabadon-korpus-snapshot-20260826/sessions/`,
read-only, not one byte written. The live ring was NOT used: a number taken from
a live ring cannot be reproduced tomorrow and a referee cannot re-run it.

Command: `python3 reports/kosu/RAPOR/f2-3-olcum.py /tmp/f23bin/rabadon-audit ~/.rabadon-korpus-snapshot-20260826`

| | measured |
|---|---|
| sessions (`*.moves.bin`) | **34** |
| records on disk (read through `rabadon-audit --export`) | **527** |
| ring header `count` summed over the 34 files | **654** |
| **LOST to the 200-record ring cap** | **127** |
| unparsable export lines | **0** / 527 |
| date range | 2026-08-22 18:22 UTC -> 2026-08-26 03:48 UTC |

The 127 is one session's loss: `286fd71d-2e67-43-57b7234bb75e.moves.bin` has
`hdr.count = 327` (`0x147`) and keeps 200. Header layout read directly:
8-byte magic `RBMV1\0\0\0`, then `u64` total-ever-written.

**The live ring is worse and is reported as such.** The card states the live
directory held 933 written against 527 retained — a 406 (43.5%) loss. **THAT
PAIR WAS NOT RE-MEASURED HERE**: this card is forbidden from reading the live
ring, so 933/406/43.5% are carried over from the card and are **DOĞRULANMADI**
by me. The 654/527/127 figures above ARE mine and are re-runnable.

Read door: `./native/rabadon-audit --export <file>` (copy used:
`/tmp/f23bin/rabadon-audit`, taken from `native/rabadon-audit` before any
parallel build could touch it). 527/527 lines parse as JSON — the F2-1 export
repair holds on the whole frozen corpus.

---

## 2. Per-signal n and hand-labelling (S2, S1)

Five detectors exist in `native/signals.h`: `repeat`, `oscillation`,
`root_migration`, `scope_drift`, `green_redefined`.

`n` = number of moves that COMPLETED a pattern, replayed over every prefix of
every session, which is how `rbsig::detect()` is called in production.

| signal | n | hand-labelled | correct | wrong | false-positive rate | live? |
|---|---|---|---|---|---|---|
| `repeat` | **0** | — | — | — | **ÖLÇÜLMEDİ** | **NO** |
| `oscillation` | **0** | — | — | — | **ÖLÇÜLMEDİ** | **NO** |
| `root_migration` | **0** | — | — | — | **ÖLÇÜLMEDİ** | **NO** |
| `scope_drift` | **17** | **17 / 17** | **0** | **17** | **100.0% (17/17)** | **NO** |
| `green_redefined` | **0** | — | — | — | **ÖLÇÜLMEDİ** | **NO** |

**Not one of the five may go live.** Four because they were never measured
(n = 0), one because its measured false-positive rate is 100%, twenty times the
5% ceiling (§4.3).

### Why each n = 0 — the reason is MEASURED, not assumed (S1)

A zero is not a pass. Each of these was traced to the exact threshold that was
never reached, over the whole 527-record corpus.

- **`repeat`** needs `seen >= 3` in a 20-move window AND `failed >= 2`.
  Measured maximum anywhere in the corpus: `(seen=3, failed=0)`, at
  `286fd71d-2e67-43-57b7234bb75e.moves.bin` seq 253. Exactly **1** prefix in
  527 ever reached `seen >= 3`, and its repeated command kept succeeding.
  Cause: the corpus contains no failing retry loop.
- **`oscillation`** needs 6 consecutive edits to ONE path alternating between
  two contents. Measured maximum edits to one path anywhere: **5**
  (`hooks/manage.mjs`, seqs 159–163, session `286fd71d`). One short of the
  threshold, and those five were not an A-B-A-B alternation.
- **`root_migration`** needs one `err_sig` surviving `>= 3` distinct move
  signatures. The corpus has 20 records with a non-empty `err_sig`; the measured
  maximum distinct signatures sharing one `err_sig` is **1**
  (`err_sig f8d295da5349d083`, session `286fd71d`). Cause: errors in this corpus
  did not recur across different attempts.
- **`green_redefined`** needs a move with `suite == 0` (a RED suite) for
  sub-rules (a) and (b), or a fall in `asserts` on one path for (c). Measured
  `suite` distribution over all 527 records: `{-1: 526, 1: 1}` — **there is not
  a single red suite in the corpus**. `asserts` distribution:
  `{-1: 495, 0: 30, 2: 1, 1: 1}`, and no path ever shows a fall between two
  edits. n = 0 for all three sub-rules.

  Honesty note on this one: (a)/(b)/(c) call `rbclass::classify()`, whose source
  file is outside this card's read list. The script therefore evaluated the
  **classify-independent superset** — the classify test dropped, which can only
  ADD firings. The superset is **empty (0)**, so the true count is 0 and the
  missing classify cannot change it. This is the only signal whose n=0 rests on
  a superset argument, and it is stated rather than hidden.

Fixtures are irrelevant to this table and are not mixed into it. The detectors
fire 39/39 in `native/signals_test.sh`; that measures the code, not the world.
**A detector that fires in its own fixture and never in three days of real
sessions is UNMEASURED, and unmeasured does not ship.**

### The 17 `scope_drift` firings, hand-labelled one by one

All 17 come from **one** session:
`~/.rabadon-korpus-snapshot-20260826/sessions/286fd71d-2e67-43-57b7234bb75e.moves.bin`
(200 records, seq 127–324). Rule: `>= 5` distinct directories touched by edits,
re-checked on every later edit — so once the 5th directory is touched, it fires
on every subsequent edit move for the rest of the session.

Directory #5 was reached at seq 159 (`hooks/`). Firings, in order:

| # | seq | path edited | label |
|---|---|---|---|
| 1–5 | 159,160,161,162,163 | `rabadon/hooks/manage.mjs` | FALSE POSITIVE |
| 6–7 | 170,171 | `rabadon/reports/kosu/RAPOR/f1a-3-doctor.md` | FALSE POSITIVE |
| 8 | 198 | `rabadon/reports/kosu/RAPOR/f1a-5-adim-sayisi-ve-cursor.md` | FALSE POSITIVE |
| 9 | 206 | `rabadon/reports/kosu/RAPOR/f1a-tutanak.md` | FALSE POSITIVE |
| 10–11 | 207,208 | `rabadon/reports/kosu/DURUM.md` | FALSE POSITIVE |
| 12–14 | 209,210,211 | `rabadon/reports/kosu/UYANDIGINDA.md` | FALSE POSITIVE |
| 15 | 271 | `rabadon/reports/kosu/KAPI.md` | FALSE POSITIVE |
| 16 | 318 | `rabadon/reports/kosu/SAPMA-KARARLARI.md` | FALSE POSITIVE |
| 17 | 319 | `rabadon/reports/kosu/UYANDIGINDA.md` | FALSE POSITIVE |

**Labelling criterion, stated so it can be argued with:** a firing is a TRUE
POSITIVE if the edit it names was off the session's goal. The session's own
`goalPrompt` is EMPTY in
`~/.rabadon-korpus-snapshot-20260826/sessions/286fd71d-...json`, so intent could
not be read from the record and external ground truth was used: the rabadon git
history in the session's own time window.

    cd ~/damla_projects_2026/rabadon && git log --since=2026-08-25 \
      --until=2026-08-26T08:00 --oneline -- <path>

Every path named above lands in at least one real commit inside that window
(`site/redact.py` 1, `site/field_stats.py` 1, `.github/workflows/ci.yml` 1,
`hooks/manage.mjs` 2, `native/doctor_test.sh` 1, `reports/kosu/DURUM.md` 4,
`UYANDIGINDA.md` 4, `KAPI.md` 4, `SAPMA-KARARLARI.md` 3,
`RAPOR/f1a-tutanak.md` 1), across 19 commits in the window. The session was one
orchestrated multi-card run whose work spans `site/`, `reports/kosu/RAPOR/`,
`.github/workflows/`, `native/`, `hooks/` and `reports/kosu/` — six directories
by design. **`scope_drift` counted the design and called it drift.**

`native/signals.h` already says this rule "is the weakest rule here and is known
to be." The measurement agrees: **0 correct out of 17, a 100% false-positive
rate.** Reported plainly, not spun.

---

## 3. Three terrains, measured separately

Sessions were assigned to a project root by pulling every absolute path and
`cd` target out of the `raw` field and walking up to the enclosing `.git`.
Terrain was then MEASURED on that root, not asserted:

    find $ROOT -name package.json -not -path '*/node_modules/*' | wc -l
    find $ROOT -mindepth 2 -maxdepth 4 -name .git | wc -l
    find $ROOT -path '*/node_modules/*' -name package.json -maxdepth 6 | wc -l
    find $ROOT \( -name package-lock.json -o -name yarn.lock -o -name pnpm-lock.yaml \) | grep -vc node_modules

| terrain | root | pkg.json | nested repos | installed pkgs | lockfiles | sessions | records | edit-moves | `scope_drift` n | FP rate |
|---|---|---|---|---|---|---|---|---|---|---|
| (i) single-package small repo | `damla_projects_2026/rabadon` | 5 (1 real + 4 publish stubs) | 0 | **0** | **0** | 5 | 211 | 27 | **17** | **100% (17/17)** |
| (ii) monorepo | — | — | — | — | — | — | — | — | **ÖLÇÜLMEDİ** | **ÖLÇÜLMEDİ** |
| (iii) large dependency tree | `/Users/damummyphus` | 407 | 69 | **3895** | 90 | 22 | 300 | 5 | **0** | **ÖLÇÜLMEDİ** |

`repeat`, `oscillation`, `root_migration` and `green_redefined` are n = 0 on
**all three** terrains; the per-terrain split adds nothing to them and is not
padded out with zeros pretending to be results.

**Terrain (ii), monorepo: ÖLÇÜLMEDİ, with the reason.** The only candidate is
`damla_projects_2026/stitchu` (7 sessions, 16 records), which measures 2
`package.json`, 2 nested repos, 2 installed packages — that is a small repo, not
a monorepo. And those 16 records contain **0 edit moves with a path**, so no
signal in the file could fire on them under any threshold. No monorepo terrain
is present in the frozen corpus. Nothing is invented to fill the row.

**Terrain (iii) is a zero, not a clean bill.** 300 records but only **5** edit
moves with a path across 22 sessions — these were read-and-search sessions. The
detectors need edit moves; 5 is not a sample. `scope_drift` n = 0 there is
**ÖLÇÜLMEDİ, not 0% false positives**, and it is written that way in the table.

**Worst terrain is the criterion:** terrain (i), 100% false positives on
`scope_drift`. That is the number that governs, and it is twenty times the 5%
ceiling.

Caveat on attribution, stated because it bounds the table: `raw` text is
retained only for the newest 50 moves per session (`MOVES_RAW = 50`), so 313 of
527 records carry raw text. The two largest sessions (200 and 114 records) were
attributed from their newest 50 moves. The firing session `286fd71d` also
attributes 27 of its edit paths to `rabadon/` directly, which is independent
confirmation for the terrain that carries all 17 firings.

---

## 4. What was NOT verified

- The live-ring loss pair (933 written / 527 retained / 406 lost / 43.5%) —
  carried from the card, **DOĞRULANMADI**, forbidden ground for this card.
- `rbclass::classify()` behaviour — source file outside the read list.
  `green_redefined` n = 0 rests on the classify-independent superset being
  empty, which is sound but is not the same as running the real function.
- `make all` / `make test` were NOT run (a parallel worker was building in the
  same tree; a concurrent build would be a race). The binaries used are the
  ones already compiled, copied to `/tmp/f23bin/` before use.
- `bash reports/R7/accept.sh` was run **once**, for task 0 only.
- The detectors were replayed by a python re-implementation of
  `rbsig::detect()` copied from `native/signals.h` at `9cba3cd`, not by the
  compiled `rabadon-gate`. `rabadon-gate` computes signals in silent mode and
  prints nothing, and `rabadon-audit --help` shows no signals subcommand, so
  there is no binary path that emits them. The thresholds were copied, not
  chosen, but **the re-implementation itself is not test-covered.**
- No signal was measured against a session where a human agreed in advance what
  the correct answer was. The `scope_drift` labels rest on git history as proxy
  ground truth, which is evidence, not certainty.

## 5. Noticed outside this card, not touched

- `reports/R7/accept.sh:548` (`8b`, `signals: 39 passed, 0 failed`) is the same
  exact-equality trap as `8a`. Green today, will fall red on the next added
  assertion.
- `reports/R7/accept.sh:552` (`8c`) pins `reports/R2/accept.sh` at
  `19 green, 0 red` — a third instance of the same pattern. Green today.
- The 200-record ring cap threw away 127 of 654 records (19.4%) in the frozen
  snapshot, all from one session. Any measurement of a long session is
  measuring its tail.
- The gate resolved the project root to `/Users/damummyphus` — the home
  directory is itself a git repo — for 22 of 34 sessions. That is why terrain
  (iii) exists at all, and it means `scope_drift`'s directory count runs against
  a tree holding 69 nested repos.
