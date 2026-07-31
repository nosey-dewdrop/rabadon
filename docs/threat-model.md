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

Every event carries `prev` = the SHA-256 of the previous line, with a `.head`
sidecar. Editing, truncating, or reordering the spool breaks the chain, and
`rabadon audit` names the broken link by file and line. This makes tampering
**evident** — you will know. It does not make the ledger **immutable**: anyone
with write access to `~/.rabadon/spool` can rewrite history; the chain only
guarantees the rewrite is detectable, and only against a reader who runs
`rabadon audit`.

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
