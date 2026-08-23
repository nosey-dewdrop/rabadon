# The counter — what rabadon saved you, and how that number is made

One line, printed once, when the session closes:

    rabadon: 2 hata zinciri kesildi, 1'i anında düzeltildi, tahmini 0.36 $ kurtarıldı.

That sentence is the whole of rabadon's third claim, and it is also the
cheapest place in this product to lie. Nobody can audit a dollar figure the way
they can audit a refusal — so the only thing holding this one up is that every
digit is derived from the ledger and can be re-derived in front of you:

    rabadon usage --explain

An inflated counter deletes the product. An honest one sells it. Law 5.

## The formula

```
saved_usd = median(uncut_chain_lengths) * chains_cut * avg_call_usd
            - inject_usd - repair_usd
```

This file is not a description of the code. `reports/R6/accept.sh` holds the
code to this exact string and reads it out of this file — if the two ever
disagree, the acceptance goes red, which is the only way a published formula
stays true.

## Every term, and where it is measured

**`chains_cut`** — a repeat / oscillation / root-migration sequence in this
session that ENDED, either because rabadon injected the history the agent could
not see (`INJECT`) or because rabadon refused the next move (`STOP`). Read off
the ledger, never off anybody's word. A refusal that did not end a flagged
sequence — a protected path, a budget cap — is not a chain cut and is not
counted; that is where a counter inflates without a single wrong digit being
typed.

**`fixed_instantly`** — of those cut chains, the ones where, in the **3 moves
after the injection that produced a result**, the same `err_sig` never came back
and, where a suite ran, it was green. Edits do not count toward those three:
an edit observes nothing, so a counter that let edits fill the window would let
an agent "fix" a chain by typing three times.

The agent SAYING it fixed something is not evidence. `claimed_rc` is a claim.
A session where the agent writes *"fixed it — all good, build clean"* and the
same `TypeError` returns two moves later counts as **not fixed**.

**`median(uncut_chain_lengths)`** — MEASURED, never a constant. A chain is a run
of consecutive moves carrying the same error signature; a chain "ran to
completion uncut" when the session it lived in was never injected into and never
blocked. Those lengths come off the move rings already on disk. Fewer than
**3** of them (`MIN_HISTORY`) and no dollar figure is printed at all — the line
says `ölçüm birikiyor` instead. There is no fallback coefficient, because a
fallback coefficient is a number somebody made up.

**`avg_call_usd`** — this session's real cost divided by this session's
assistant calls, read from the agent's own local transcript
(`~/.claude/projects/*.jsonl`). **Nothing goes to the network**, for this or for
anything else in this file.

**`inject_usd`** — what rabadon's own injected characters cost the user. They
cannot be told apart inside the transcript, so they are charged at the **UPPER
bound**: **400** characters per injection (`rbinject::MAX_CHARS`, the Law 6
ceiling), 4 characters per token, priced as input. No rounding into our own
column, ever.

**`repair_usd`** — the repair arm's tokens, when there was an arm, off its own
`COST` ledger lines.

## Prices: four classes, offline

Prices come from a snapshot of the LiteLLM table — the same table `ccusage`
prices from — cached on disk at `$RABADON_DIR/prices.json` and read from there.
`rabadon usage --json` prints the path. You can open it, diff it, and correct
it; rabadon never refreshes it over the network.

There are **four separate price classes**, and keeping them separate is not a
detail:

| class | claude-sonnet-4-5, $/Mtok |
|---|---|
| input | 3.00 |
| output | 15.00 |
| cache write | 3.75 |
| **cache read** | **0.30** |

In a long agent session most of the token volume is **cache read**, at a tenth
of the input price. A counter that folds cache read into input reports a number
several times too large — and it reports it in our own favour. `reports/R6`
computes both answers and requires the right one.

## When the counter does not know, it says so

These are the product, not edge cases:

| situation | what is printed |
|---|---|
| no session transcript | the chain counts, and **no dollar figure** |
| the model's price will not resolve | the chain counts, and **no dollar figure** |
| fewer than 3 measured uncut chains | `ölçüm birikiyor` — no invented coefficient |
| net negative | the negative, at the precision it takes to be non-zero |
| zero interventions | `rabadon: bu oturumda müdahale yok` — zero dollars is never printed as "saved" |

A net-negative session is one rabadon did not pay for. Printing it is the reason
the positive number is worth anything.

Every estimated number carries the word **tahmini** / **estimated**.

rabadon cannot see which plan the session was billed on, and it does not guess.
It prices from the **API list price** table, so on a subscription the figure is
theoretical at list price (Law 7). That basis is stated where the derivation
lives — `usage --explain` prints it as `basis: API list price (api_list)` and
`usage --json` carries `.counter.prices.basis`. The closing line itself is not
qualified beyond `tahmini`; changing that one advertised sentence is a decision
for a human, not for this file.

## Where it runs

At session close (`SessionEnd`, and `Stop` for agents that send no `SessionEnd`)
— **never on the hot path**. The counter walks the ledger and this project's
move rings, which is affordable exactly because it happens once, when nobody is
waiting on a tool call. `reports/R6` claim 6c asserts the invariant directly:
the cost of a `PreToolUse` may not grow with the size of the ledger.

No new CLI verb was opened for it. The surface is five verbs, and the counter
lives inside `usage`:

```
rabadon usage            the week
rabadon usage --explain  every number, re-derived, citing the ledger lines
rabadon usage --json     the same data, machine-readable (.counter.*)
```
