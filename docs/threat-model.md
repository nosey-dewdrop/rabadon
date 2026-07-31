# rabadon threat model

This document is deliberately honest about what rabadon stops and what it does
not. A security tool that overclaims loses trust the first time it is caught. So
here is the exact line between the hard boundary and the advice.

## The three surfaces

rabadon enforces at three places of different strength:

1. **The kernel sandbox** (`rabadon exec`) — a real OS boundary.
2. **The hook** (`PreToolUse`/`PostToolUse`) — advice the agent could be
   prompted around.
3. **The hash-chained ledger** — makes tampering evident, not impossible.

## What the kernel fences

Under `rabadon exec`, the guard is compiled into an OS policy (macOS Seatbelt,
Linux bubblewrap). Inside that sandbox:

- **Writes to `protectedPaths`** with a literal path prefix fail with `EPERM` —
  even from a subprocess, even if no hook ran, even if the agent never asked
  rabadon.
- **The network is denied** when the guard says `"network":"deny"` — the process
  simply cannot reach it.

This is the hard boundary. It does not depend on the agent's cooperation. If the
guard asks for enforcement and no sandbox backend is available, `rabadon exec`
**refuses to run** (exit 3) rather than run unprotected — the one place rabadon
fails closed instead of open.

## What only the hook advises

Outside `rabadon exec`, in a normal Claude Code session, the gate runs as a
hook. The hook sees the command or file path Claude Code hands it and refuses on
a match. This catches the ordinary case — a raw Bash command the matcher sees,
an edit to a protected path the agent asks about — and refuses it before it
happens, with the reason fed back so the agent self-corrects.

But a hook is **advice**. It only sees what it is handed, and it only stops an
agent that routes its action through the tool call the hook is attached to.

## Bypass vectors rabadon does NOT stop

State these plainly. In a plain hooked session (no `rabadon exec`):

- **A subprocess the agent spawns.** If the agent runs a command that itself
  spawns another process which does the destructive write, the hook saw only the
  outer command. The kernel fence would stop the write; the hook alone does not.
- **An MCP tool that writes files directly.** An MCP server can touch the
  filesystem through its own code path, not the Bash tool. The `PreToolUse` hook
  covers MCP tool calls it is handed, but a tool that writes as a side effect of
  some other operation is not something the hook can inspect. Only the kernel
  fence stops that write.
- **A pure-regex protected path with no literal prefix.** `protectedPaths`
  becomes a kernel fence only for the literal head of the pattern. A match that
  starts with a metacharacter (e.g. `".*secret.*"`) has no literal prefix the
  kernel can anchor — `rabadon exec` reports that it skipped it, and **the hook
  still checks it**, but there is no kernel fence behind it.
- **An agent prompted around the hook.** Because the hook's refusal is text fed
  to the agent, an agent that has been instructed to work around gates can, in
  principle, restructure its actions to avoid the matcher. Hooks constrain a
  cooperative agent; they are not a jail for an adversarial one.

## The ledger: tamper-evident, not tamper-proof

Every event carries `prev` = the SHA-256 of the previous line. Beside each day
file sits a `.head` sidecar, written under the same `flock` as the line it
commits to, holding two facts:

    <sha256 of the last chained line> <number of chained lines>

**The sidecar is the authority.** `rabadon audit` judges the day file against
it, and every verdict below is one question asked six ways — does the file still
agree with the commitment written beside it?

| What was done to the ledger | Verdict |
| --- | --- |
| a line edited, reordered, or a byte changed | BREAK, named by file and line |
| the tail truncated | BREAK — the head hash no longer matches |
| a line deleted from the middle | BREAK |
| a line deleted and the chain **re-stitched** around the hole | BREAK — the chain verifies, the committed line count does not |
| **every `prev` stripped out** | BREAK — a stripped chain is not an unverified one |
| a single `prev` removed from a chained file | BREAK — that link was cut out |
| the `.head` sidecar deleted, day file kept | BREAK — a chaining writer always leaves one |
| the day file deleted whole, sidecar kept | BREAK — the orphan sidecar convicts it |
| a file with no sidecar and no `prev` anywhere | **UNVERIFIABLE**, exit 2 — never "intact" |

Exit codes are the honest three: `0` every file verified against its sidecar,
`1` at least one break, `2` nothing proven broken but something cannot be
verified. "I don't know" never exits 0.

**What this does not do, plainly.** The sidecar sits on the same disk with the
same permissions as the ledger it commits to. There is no external anchor — no
key the writer lacks, no remote append-only log. So:

- Anyone who can write **both** the day file and its `.head` can rewrite a whole
  day and the audit will say INTACT. What the chain and the count buy you is
  that *partial* tampering — the realistic case, someone editing a line or
  deleting an inconvenient event — cannot pass. All-or-nothing is the price of
  a local-only ledger with no server.
- A file with no sidecar and no `prev` on any line is genuinely ambiguous: a
  pre-chain legacy writer and an attacker who stripped both halves look
  identical. rabadon reports it as unverifiable rather than guessing, which is
  why the verdict can be PARTIAL.
- Detection only happens against a reader who actually runs `rabadon audit`.

Pre-0.4 sidecars carry no line count. Their files are reported unverifiable
until the next event of that day rewrites the sidecar in the current format.

## The honest summary

- The **sandbox** is the hard boundary. If you need a write or a network call
  truly prevented, run the command under `rabadon exec`.
- The **hook** is advice: it stops the ordinary, cooperative case at attempt
  time and coaches the agent, but it can be routed around and only sees what it
  is handed.
- The **ledger** makes tampering evident, not impossible.

This honesty is the point. Use `rabadon exec` for the actions that must not
happen; use the hook for everyday supervision and the coaching loop; use the
audit to know if the record was touched.
