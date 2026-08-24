# CHALLENGE 2 — GOAL 3 is still unpassable, in ONE field, and it is outside my authorisation

Raised 2026-08-24, tur 7. Evidence is `reports/R7/accept.out` from the sealed
run of `reports/R7/accept.sh` at commit ba231d6.

**Status: NOT fixed. No file was changed for this. It needs an operator
decision of its own** — the operator's CEVAP (`reports/kosu/6.operator.md`)
authorised exactly three fields (`run`, `pipe`, sandbox path) and explicitly
forbade blanket chain-hash blinding. What follows is outside that list, so I
stopped instead of widening my own mandate.

## What the authorised fix DID achieve

After identity normalisation, all three GOAL 3 commands now agree byte for
byte on exit code, `ev`, `mode`, `rule`, refusal text, `seq`, and the number
and order of ledger lines. The whole STOP record is identical except one
field:

    ...,"rule":"baseline-rm-rf-outside",...,"prev":"47bbbbad29fe23..."
    ...,"rule":"baseline-rm-rf-outside",...,"prev":"359ef055d3fa34..."

So fail-SAME as a BEHAVIOUR is now demonstrated by the sealed script. This
also confirms, with the sealed instrument, the two fail-opens closed in
deneme 3 — the item the operator queued.

## The residual, with its mechanism

Two surfaces, one cause.

1. **`"prev"` in every ledger line after the first.** `native/chain.h:191`
   computes it as `rbsha::hex(chained)` over the PREVIOUS line's raw,
   **un-normalised** body. That body contains the real `ts` and the real
   `run` — both of which the script already normalises, and has normalised
   since before this session. So `prev` is a hash of exactly the bytes we
   have agreed cannot match. It can never be equal across two runs, for any
   implementation. Line 1 is fine (`prev` = `"genesis"` in both arms); every
   line after it diverges.

2. **The `spool/*.head` sidecar**, which `run3` also cats. `chain.h`
   writes it as `<sha-of-last-line> <line-count>`. Same cause.

This is the SAME CLASS of defect the operator just ruled on — an identity-
derived field being compared as if it were behaviour — in a DIFFERENT field
that was not on the authorised list.

## One correction to the record

The operator forbade `s/^[0-9a-f]{64} /HASH /` on the grounds that it would
blanket-blind the chain hash and destroy the line-count/order comparison.
Measured, that pattern does not do what either the challenger or the ruling
assumed:

- It does **not** match ledger lines at all. Ledger lines are JSON and carry
  the hash as a `"prev":"..."` field, never as a leading prefix.
- The only thing it matches is the `.head` sidecar, whose format is
  `<64hex> <count>` — and it replaces only the hash, **leaving the count in
  place**. So the specific pattern the ruling forbade would in fact have
  PRESERVED the line-count comparison the ruling wanted protected.

I am reporting this rather than acting on it. The ruling stands until the
operator changes it.

## What a decision would have to choose between

**(a) Normalise `prev` and the `.head` hash too** (`s/"prev":"[0-9a-f]{64}"/"prev":"PREV"/g`
plus the sidecar's leading hash, count kept). Costs nothing in signal: `prev`
is a pure function of preceding line content, and that content is already
compared directly, field by field, after normalisation. A chain break cannot
hide behind this — it would have to show up as a difference in the line
bodies, which ARE compared. This is the smallest change that makes GOAL 3
decidable.

**(b) Stop catting the `.head` sidecar and compare line count explicitly**,
leaving `prev` normalised as in (a). Slightly more code, same signal.

**(c) Leave it.** Then GOAL 3 stays red forever, for a reason that has
nothing to do with whether the daemon fails SAME — and R7 cannot be accepted
by any implementation.

My recommendation is **(a)**, in accept.sh's own commit, with the line count
and order still compared and no other field touched. But (a) is exactly the
move the current ruling forbids, so it is the operator's call, not mine.

## What is NOT in dispute

The 1000 us ceiling. GOAL 2b now has its first number from the sealed
instrument — **1704.4 us**, red — and that is a fact about the gate, not
about this file. Nothing here proposes touching the ceiling.
