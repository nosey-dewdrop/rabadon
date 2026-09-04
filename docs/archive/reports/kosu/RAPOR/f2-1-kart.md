# f2-1-export-onarimi — `rabadon audit --export` emitted invalid JSON

Base commit named by the card: `49fd73d`.
Work commits: `827baa7` (criterion), `96f493a` (fix).

## What was broken

`native/audit.cpp` printed the move record with a raw `printf` and dropped the
recorded bytes into `"path"`, `"raw"`, `"sig"`, `"err_sig"`, `"tool"` and
`"prev"` without escaping anything. A move holds whatever the agent typed, so a
command with a double quote, a Windows path with a backslash, a diff with a
newline or a tab, or a colour escape at `0x1b` ended the JSON string early or
put an illegal control character inside it.

This is the only door out of the fixed-width binary ring. `native/moves_test.sh`
reads through it, and so does any human studying a session.

## (a) Measured BEFORE the fix — `reports/kosu/RAPOR/f2-1-once.out`

Command: `python3 /tmp/f2_1_measure.py` (exports every `*.moves.bin` in the
frozen snapshot with the pre-fix binary and runs `json.loads` on each line).

    corpus: ~/.rabadon-korpus-snapshot-20260826/sessions   34 *.moves.bin files
    total exported lines            608
    lines that FAIL json.loads      281
    lines that parse                327/608

The card reported 280. The real number is **281**. Written as measured.

## (b) The fix

`jesc()` in `native/audit.cpp`, applied to every string field:

- `"` `\` and the C0 controls become `\"` `\\` `\n` `\r` `\t` `\b` `\f`, and
  `\u00XX` for the rest of `< 0x20`;
- well-formed UTF-8 passes through as itself (overlong forms, surrogates and
  out-of-range codepoints are rejected as not-well-formed);
- a byte that is **not** part of well-formed UTF-8 is emitted as `\u00XX` of the
  byte's own value. The fixed-width `Rec` fields guarantee these exist, because
  `put()` truncates `path[140]` / `raw[96]` at a byte boundary and can cut a
  multi-byte character in half. The parser then yields `U+0080..U+00FF`, one
  codepoint per byte, so the original byte is recoverable with a latin-1 encode.
  **Escaped, never dropped** — no `U+FFFD` substitution, which would destroy it.

## (c) Measured AFTER the fix — `reports/kosu/RAPOR/f2-1-sonra.out`

    total exported lines            527
    lines that FAIL json.loads      0
    lines that parse                527/527

### The line count moved 608 -> 527. That is not data loss, and it was verified.

`608` was PHYSICAL LINES of the broken exporter: an unescaped `\n` inside `raw`
split one record across several output lines. `527` is the record count the ring
headers themselves commit to (`min(hdr.count, CAP)` summed over all 34 files),
and `--export` now prints exactly that, per file, with zero mismatches.

Byte-for-byte check, in the same report file: all 527 records were unpacked
straight out of the binary with `struct` and each `path` / `raw` / `sig` /
`err_sig` compared against the bytes recovered from the JSON.

    records compared against the raw binary fields:            527
    fields whose bytes do not round-trip out of the JSON:      0

## (d) The reader's silent swallower — `native/moves_test.sh`

The `except Exception: continue` / `pass` handlers in `moves_py()` dropped
unparsable lines without a sound, so every claim in that file ran on whatever
happened to survive and still reported `ok`. That is the false green this repo
exists to refuse, and it is why a bug affecting 281 of 608 corpus lines was
invisible to a suite that read the exporter on every single assertion.

The handlers still keep the run alive, but each now records what it dropped —
by file name, with the exception text and the first 160 characters of the line —
into `$RB_SWALLOW_LOG`. Three sites now report instead of swallowing, plus one
that was not guarded at all before: a non-zero exit from `rabadon-audit --export`
(`export-exit`) was previously invisible because only `.stdout` was read.

New CLAIM 8 reads the log. Zero is the only passing number; anything else fails
the suite and prints each swallowed line by name.

**No existing assertion was deleted, weakened, renamed or skipped.** The count
went 21 -> 22.

## (e) Proof the new counter can actually fall red — `f2-1-bosyesil.out`

A temporary fixture move whose command contains double quotes, a tab and a
newline was inserted before CLAIM 8 and run against the **unfixed** exporter:

    pre_bash s-poison 'echo "he said \"hi\"" && printf "a\tb\n"'

Result — the suite went RED and named the line:

    FAIL - the reader swallowed 1 export line(s)/file(s) it could not parse
           swallowed: export-line s-poison-b6a76a5771fd.moves.bin:
           Expecting ',' delimiter: line 1 column 91 (char 90) |
           {"seq":0,...,"raw":"echo "he said \"hi\"" && printf "a\tb\n"",...
    moves: 21 passed, and at least one failed
    EXIT=1

The probe was reverted; the suite returns to `22 passed, 0 failed`. The counter
is not decorative and it is not stuck green.

## Gate — `reports/kosu/RAPOR/f2-1-kapi.out`

| check | floor | measured | verdict |
|---|---|---|---|
| `make all` | 0 | 0 | ok |
| `./native/moves_test.sh` | 0 | 0 (22 passed, 0 failed) | ok |
| `make test` | 0 | 0 | ok |
| `grep -cE '^[[:space:]]*ok\b'` | 3745 | **3748** | did not fall |
| summed `PASS (N checks)` | 633 | **633** | held |
| `npm test` | 64/0 | 64 pass, 0 fail | ok |
| `reports/R7/accept.sh` | 23 green / 3 red | **22 green / 4 red** | see CHALLENGE |

The one literal `FAIL` string inside `make test` output is line 4272:
`regression_demo.sh` quoting what rabadon reports about a fixture's red suite.
That suite's own verdict on the next line is `regression: 4 passed, 0 failed`.

---

# CHALLENGE — R7 `8a` pins a count that acceptance (d) requires to change

**I did not fix this, because the file is outside this card's write list and
because it is an acceptance criterion (CLAUDE.md non-negotiable 2: criteria
change first, in their own commit, or not at all). It needs a human diff.**

`reports/R7/accept.sh:543`:

```sh
if OUT="$(./native/moves_test.sh 2>&1)" && printf '%s' "$OUT" | grep -q 'moves: 21 passed, 0 failed'; then
```

This is an **exact-equality** baseline on the assertion count. This card's
acceptance (d) orders a new assertion and says the number may only grow
("sayı yalnız ARTAR"). The two instructions cannot both be satisfied: any added
assertion turns `8a` red.

Red set before: `{2b, 6e, 7b}`. Red set after: `{2b, 6e, 7b, 8a}`. It grew, and
the growth is mine.

**What I refused to do.** The two ways to keep `8a` green are (i) print the ok
line without incrementing `PASSN`, or (ii) fold the swallow check into an
existing assertion so the total stays 21. Both make the check pass without the
value existing — the exact move this product refuses. I did neither.

**Proposed diff, for a human, in its own commit:**

```diff
-if OUT="$(./native/moves_test.sh 2>&1)" && printf '%s' "$OUT" | grep -q 'moves: 21 passed, 0 failed'; then
+# a floor, not an equality: this guard exists to catch moves_test.sh going RED or
+# LOSING assertions, and an exact count also fires on a suite that gained one.
+if OUT="$(./native/moves_test.sh 2>&1)" \
+   && N="$(printf '%s' "$OUT" | sed -n 's/^moves: \([0-9]*\) passed, 0 failed$/\1/p')" \
+   && [ -n "$N" ] && [ "$N" -ge 22 ]; then
```

Rationale: `8a` sits under "GOAL 8 — nothing already standing fell over". A
gained assertion is not something falling over. A floor detects every failure the
equality detects (red suite, deleted assertions) and stops firing on growth.
Raising `21` to `22` verbatim would work today and re-break on the next card.

**Note on `2b`:** measured `1827.7 us` against a `1000 us` ceiling on this
machine, inside the `1218-2537 us` band the card documents. Out of scope for this
card (F3-S1), not touched.

---

## NOT VERIFIED

- **Clean machine / fresh clone.** Everything ran on this box. I exported HEAD to
  `/tmp` and ran `make test` there, and it produced FOUR failures that do NOT
  reproduce in the real repo: `node --test` was red (no `node_modules` in a
  `git archive` export) and four `fdtest` redirection cases failed because the
  repo path itself was under `/tmp`, which `mask_scratch()` treats as a scratch
  root. Those are artifacts of my isolation, not findings — but it means the
  reference-container claim is UNVERIFIED by me.
- The `\u00XX` recovery path for invalid UTF-8 is proven by construction and by
  the 527-record round-trip, but the frozen corpus may contain no truncated
  multi-byte character at all. I did not confirm that branch was exercised by
  real data.
- I did not measure the export's speed. It is not the hot path (moves.h says so
  explicitly), but `jesc()` copies every field and I put no number on it.
- `make test` was run once, not repeatedly. `2b` is known load-dependent on this
  machine; other timing-sensitive checks may be too.

## Noticed, outside this card, NOT touched

- **`bin/rabadon.mjs` has the same class of bug, unfixed.** DOĞRULANMADI — I did
  not open the file (write list forbids it, read list does not include it); this
  is from the card's own prohibition list plus the fact that the JS gate is a
  second writer to the same ledger. Worth a card: if the JS side also prints
  unescaped JSON, the corpus has a second source of unparsable lines.
- The shared working tree is live. During this card another worker's uncommitted
  `native/gate.cpp` was present, `make all` rebuilt their binary from it, and
  `make test` went red on `--silencers` before their `c8a2ad6` landed. A worker
  running the full gate is measuring other workers' in-flight source. The
  `ok` floor of 3745 is not attributable to one card under these conditions —
  3748 today includes f2-4's additions as well as my +1.
- `reports/R7/accept.sh` contains at least one more exact-equality baseline of
  the same shape (`8b native/signals_test.sh 39/0`). It will break the same way
  the first time anyone adds an assertion to `signals_test.sh`.
