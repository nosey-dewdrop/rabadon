# rabadon spec v1

rabadon is a policy gate for coding agents. This document specifies the three
contracts that make it agent-agnostic: any runtime that can execute a
subprocess before/after an action can implement them. Claude Code hooks are
one binding, not the product.

## 1. Gate contract

The gate is a subprocess. One event in on stdin, one verdict out via exit code.

```
stdin   one JSON event (schemas below)
exit 0  allow — the action proceeds
exit 2  intervene — the action is refused (pre-action) or challenged
        (post-action); stderr carries the reason, written TO THE AGENT,
        so the agent can self-correct. The reason always names the rule id
        and the user override path.
other   gate error — the runtime MUST treat this as allow (fail-open):
        a broken gate must never break the builder's work.
```

Latency budget: a gate implementation SHOULD stay under 150ms for the
deterministic path. LLM judgment is permitted only outside the per-action hot
path (incidents, periodic drift checks).

## 2. Event schema (v1)

Events are single-line JSON. Producers append them to a local spool
(`~/.rabadon/spool/YYYY-MM-DD.jsonl`) and push them, fire-and-forget, over a
local unix socket to any attached viewer. Nothing leaves the machine.

```json
{ "v": 1, "seq": 3, "ts": 1785072099611, "run": "<run id>",
  "pipe": "<project>:session", "ev": "CHECK_FAIL",
  "step": "Bash", "fails": [{ "check": "<rule id>", "why": "<reason>" }] }
```

`ev` vocabulary (fixed): `RUN_START`, `STEP_START`, `STEP_OK`, `CHECK_FAIL`,
`REPAIR_START`, `REPAIR_OK`, `REPAIR_FAIL`, `STOP`, `RUN_DONE`.
A `STOP` with `"reason": "BLOCKED"` is a catch: something was refused before
it happened. Unknown fields MUST be preserved; unknown `ev` values MUST be
rendered generically, never dropped.

## 3. Guard schema (v1)

The guard is the project's law, machine-checkable, stored at
`<project>/.rabadon/guard.json`. It is authored — by rabadon itself from the
project's law files, by an incident diagnosis, or by a human — and every rule
carries its own justification.

```json
{
  "project": "name",
  "bash":           [{ "id": "kebab-id", "deny": "<regex over the full command>", "why": "<one line>" }],
  "protectedPaths": [{ "id": "kebab-id", "match": "<regex over the file path>", "why": "<one line>" }],
  "codePaths":      ["<regex: what counts as code (arms the push gate)>"],
  "testPaths":      ["<regex: what counts as a test file (arms the tamper detector)>"],
  "testCommand":    "<regex matching a test invocation>",
  "testPassPattern":"<regex present in output ONLY when fully green>",
  "pushGate":       { "why": "<the law>", "run": "<literal command rabadon executes itself>", "timeoutSec": 600 },
  "disabled":       ["rule-id"]
}
```

Semantics an implementation MUST provide on top of the guard:

- **loop-stop** — the same non-read-only command run a 3rd time with no code
  edit in between is refused.
- **scope fan-out** — edits spreading across a 5th top-level directory in one
  session are challenged once.
- **test-tamper** — while the suite is red, an edit that weakens a test file
  (skip markers added, assertions removed) is refused.
- **push gate** — if `pushGate.run` is declared, the implementation runs it
  itself at push time and decides on the REAL result; it never trusts a claim.
- **fail-open for itself, fail-closed for the work** — gate bugs allow;
  rule matches refuse.
- **escape hatches** — a project-level off switch and per-rule `disabled[]`
  are mandatory; every refusal message MUST name its rule id and the override.

## 4. Bindings

- **Claude Code**: hooks (`PreToolUse`/`PostToolUse`/`UserPromptSubmit`/
  `SessionStart`/`Stop`) → `hooks/gate.mjs`. Reference implementation.
- **Any other agent/runtime**: implement the gate contract around your action
  loop. If your agent shells out, the minimal binding is wrapping the shell.

Versioning: breaking changes to any schema bump `v`. Consumers MUST ignore
versions they do not understand rather than fail.
