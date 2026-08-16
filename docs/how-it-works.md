# How rabadon works

rabadon is a native C++ core with zero runtime dependencies, hooked into Claude
Code. On every tool action, Claude Code hands the gate one JSON event; the gate
decides, deterministically, in about a millisecond. This document is the
mechanism: the hooks, the gate contract, the ledger, the modes, and the two
enforcement boundaries.

## The five Claude Code hooks

`rabadon init` merges these into `.claude/settings.json`. Each is a subprocess
Claude Code invokes at a defined moment.

- **`PreToolUse`** — before any tool runs. Carries the tool name and its input
  (for Bash, the command; for edits, the file path). This is where a forbidden
  action is refused before it happens. Matches **every** tool — Bash, file
  edits, and MCP tools alike.
- **`PostToolUse`** — after a tool runs. Carries the tool name, input, and
  result. This is where a real check can catch a break the moment it lands.
- **`SessionStart`** — at the start of a session. Where rabadon prunes the spool
  past its retention window and seeds session state.
- **`UserPromptSubmit`** — when you submit a prompt. Carries the prompt; feeds
  session-goal and drift tracking.
- **`Stop`** — when the session ends. Fires the gate and, separately, the drift
  check.

Claude Code hooks are one **binding**, not the product. rabadon's gate is a
generic subprocess contract; any runtime that can run a subprocess before or
after an action can implement it.

## The gate contract

The gate is a subprocess. One event in on stdin, one verdict out via exit code.

```
stdin   one JSON event
exit 0  allow — the action proceeds
exit 2  block — the action is refused (pre-action) or challenged (post-action).
        stderr carries the reason, written TO THE AGENT so it can self-correct.
        The reason always names the rule id and the override path.
other   gate error — the runtime treats this as allow (fail-open): a broken
        gate must never break the user's work.
```

Because the reason is fed back to the agent on stderr, a refusal is not a dead
end — the agent reads "Rule X — Y" and corrects course.

## The hash-chained spool

Every event is appended to a local, append-only spool at
`~/.rabadon/spool/YYYY-MM-DD.jsonl`, one JSON object per line. Each line carries
a `prev` field = the SHA-256 of the previous line in the same day file. A
`.head` sidecar holds the hash of the last chained line, so a truncated file
cannot hide. This makes tampering **evident**: `rabadon audit` re-walks the
chain and names any broken link by file and line.

An event looks like:

```json
{ "v": 1, "seq": 3, "ts": 1785072099611, "run": "<run id>",
  "pipe": "<project>:session", "ev": "CHECK_FAIL",
  "step": "Bash", "fails": [{ "check": "<rule id>", "why": "<reason>" }],
  "prev": "<sha256 of the previous line>" }
```

### Event vocabulary

- `RUN_START` / `RUN_DONE` — a supervised run opened and closed.
- `STEP_START` / `STEP_OK` — a tool action began and completed cleanly.
- `CHECK_FAIL` — a check failed on an action.
- `STOP` — the run was stopped; `"reason":"BLOCKED"` marks a real catch
  (something refused before it happened).
- `WOULD_BLOCK` — watch-mode verdict: a rule matched but nothing was stopped.
- `REPAIR_OK` / `REPAIR_FAIL` — the repair loop held a verified patch, or failed
  closed.

Unknown fields are preserved; unknown `ev` values are rendered generically,
never dropped.

## Modes: watch / on / off

Mode is one flag (`~/.rabadon/enabled`) the gate reads, so it is deterministic
in any shell.

- **watch** (`rabadon off`) — every rule still runs and every verdict is
  recorded as a `WOULD_BLOCK` event, but nothing is stopped. Watch is not a
  crippled enforce; it is a full dry run you can read a week later.
- **on** (`rabadon on`) — enforce. A rule match refuses the action (exit 2).
- The bare `rabadon` toggles enforce <-> watch.

## Drill exclusion

`rabadon drill` fires a synthetic dangerous command through the real gate so you
can see a refusal on demand. It is tagged at emit (`drill:true`, plus a
`drill-` run marker) and excluded from every number in `rabadon usage`,
`rabadon report`, and `rabadon export`. The ledger only ever counts real
catches.

## Fail-open for itself, fail-closed for the work

Two failure directions, deliberately opposite:

- **Fail-open for rabadon itself.** A bug in rabadon must never block your
  session. Any gate error (a crash, a non-2 non-0 exit) is treated by the
  runtime as allow.
- **Fail-closed for the work.** A rule match refuses. And a gate that was
  signal-killed mid-decision must not silently become an allow — the gate
  ignores `SIGPIPE` so a broken pipe cannot turn a block into a pass exactly
  when someone is watching.

## Kernel sandbox vs hook enforcement

There are two enforcement boundaries, and they are not the same strength:

- **The hook** is advice. It sees the command or path Claude Code hands it and
  refuses on a match. An action that never reaches the hook (a subprocess the
  agent spawns, an MCP tool writing files directly) is not seen.
- **The kernel sandbox** (`rabadon exec`) is the hard boundary. It compiles
  `protectedPaths` and network denies from the same `guard.json` into an OS
  policy — macOS Seatbelt, Linux bubblewrap — so a forbidden write fails with
  `EPERM` even if nothing asked rabadon first.

The honest split between what each can and cannot stop is in
[threat-model.md](threat-model.md).

## Measured latency

The hot path is deterministic C++, never a model. The native gate decides in
**3.1 ms** at the median — 3.14 ms to allow, 3.20 ms to refuse, n=40 — against
the legacy Node gate's 101 ms, a 44x median gap that is mostly process startup.
The hook timeout it runs inside is measured in seconds, so supervision is
effectively free on the critical path. Every figure here comes out of
[BENCHMARK.md](../BENCHMARK.md) and nowhere else. Reproduce the measurement
yourself:

```
make bench
```

(LLM judgment, when used, lives outside the per-action hot path — in guard
authoring and the repair proposer, never in the gate decision.)
