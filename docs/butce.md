# butce.md — what the move record costs, and what it is allowed to cost

Every number here is measured on this repo's own machine and is reproducible with
the command printed beside it. Nothing in this file is a target; they are
observations, and where an observation is bad it says so.

## The shape

The move record is an append-only log, one file per session:

    <project>/.rabadon/sessions/<key>.moves.jsonl

One line per move. A completion — PostToolUse learning the exit claim, the error
signature, the suite verdict — is **another line with the same `seq`**, never an
edit of the line already on disk. The reader lets the later line win. Append-only
means append-only; a log you edit in place is a file with extra steps and a
torn-write window.

## Why it is a log and not an object

R1 stored the moves inside the session JSON. Recording one 200-byte fact meant
serialising the whole object and replacing the file through a temp and a rename.
At 200 moves that is roughly 60 KB of write per tool event, and it measured:

| arm | median |
|---|---|
| recording off | 4.636 ms |
| recording on (R1 storage) | 6.207 ms |
| **cost** | **+1571 µs** |

The between-rounds gate allows 300 µs. R1.1 tried dirty-tracking the write and
bought nothing (5.674 → 5.784 ms) because the measured path only wrote once
anyway. R1.2 changed the storage instead.

    reports/R1.2/accept.sh   # goal 4 measures this, 3 runs per arm, median

## The caps, and who enforces them

    CAP      = 200 moves     the newest, by seq
    RAW_KEEP = 50            moves that carry their raw text
    RAW_CLIP = 200 chars     per move

**The reader enforces them, not the file.** Any reader — the gate, R2's
detectors, a test — is handed the newest 200 moves with raw text on the newest
50. Between compactions the file on disk may hold more lines than that, and that
is exactly what makes an append cheap: nothing has to be rewritten to keep the
record bounded.

`seq` never resets. It is the only field that can still order two moves after
eviction has thrown the older one away.

## Compaction — at SessionEnd, never on the hot path

Trigger: the `Stop` / `SessionEnd` hook. Nothing else compacts, and no tool event
ever does.

What it does: rewrites the log as exactly what a reader would have been handed —
the newest 200 moves, raw on the newest 50 — through a temp file and a rename, so
a crash mid-compaction leaves the **old** log intact rather than half of a new
one. This is the one operation here that is not an append, and it is the one
place the cost does not matter, because the agent has already stopped.

Bound after compaction: **200 lines**, of which at most 50 carry raw text of at
most 200 characters. A compacted log is therefore a few tens of KB, and a session
that never ends cleanly grows by roughly one line per tool event until it does.

## Durability: no fsync, on purpose

`append_move()` opens with `O_APPEND`, writes once, closes. **It does not
fsync.**

The reasoning, stated so it can be argued with:

- fsync on every tool event would hand back the millisecond this round exists to
  remove. The gate runs on every action a developer's agent takes; a supervisor
  that is felt is a supervisor that is uninstalled.
- What is at risk is a **diagnostic record**, not the user's source and not the
  chained ledger. `~/.rabadon/spool/` — the thing `rabadon audit` verifies and the
  thing the counter will be derived from — is unchanged by this round and keeps
  its own durability behaviour.
- The honest cost is real: a crash or a power loss can lose the tail of the log.

So the tail is not *assumed* intact, it is *checked*. Every line carries `prev`,
the first 16 hex of the SHA-256 of the line before it. On load:

- a line whose `prev` does not match the previous line's hash means a line is
  **missing or was edited** — the record has a known hole rather than a quiet lie.
  Under `RABADON_MOVES_STRICT=1` the gate says so on stderr; otherwise it carries
  the hole forward silently, because a broken diagnostic record is not a reason to
  refuse the user's command.
- a half-written final line (no closing `}`) is **dropped**, not fatal. A torn
  record must never stop the gate from judging the next command.

That is the trade in one sentence: rabadon does not promise the move record
survives a crash; it promises it will never tell you something that did not
happen.
