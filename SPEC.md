# rabadon spec v2

rabadon is a supervision runtime for coding agents. Part I of this document
fixes the end state — what the finished thing is — so that every session
builds toward one architecture instead of resetting into daily versions.
Part II specifies the three contracts that make it agent-agnostic.

Status markers are law here: **[proven]** = running, tested, measured on this
machine; **[building]** = code exists, not yet complete; **[ahead]** = not
started. Nothing public ever claims more than its marker.

---

# Part I — the end state

## What the finished thing is?

One native binary that sits between a coding agent and the world. It enforces
the project's law deterministically on every action, keeps the session locked
to its declared goal, stops runaway loops, and repairs what breaks — then
re-verifies the repair through the same gates before letting it through.
Local-first: nothing leaves the machine. Fail-closed for the work, fail-open
for its own bugs. Every claim it makes about itself comes from its own ledger.

Where the field stands: tracers (Langfuse, Braintrust) watch and never stop;
the one inline gate (Galileo) blocks but never repairs. rabadon's position is
the full loop — catch at attempt time, stop, repair, re-verify, continue —
with the overhead measured in single-digit milliseconds because the hot path
is deterministic C++, never a model.

## The six pillars

1. **One binary.** `rabadon` is a single static C++ executable, zero runtime
   dependencies, installed with one command. Gate, session kernel, drift,
   verify, loop, task engine, stats, ui server, doctor, init — all inside.
   Median per-event overhead under 5ms [proven for gate: 2.1ms vs 101ms node;
   building for the rest — engine JS still exists and is being retired].

2. **The law writes itself.** The builder does not hand-author rules. Law is
   compiled: from the project's own law files (`rabadon guard`), from
   incidents (rules born with `authoredBy: incident`), from fleet distillation
   (packs mined from rules that independently appear across projects), and
   from a per-project goal contract (`promise.json`). Every rule carries its
   provenance and its why. [proven in pieces: incident-authored rules, the
   battle-common pack, promise.json exist; the loop that makes hand-written
   law obsolete is the product]

3. **Enforcement in the moment, not in the post-mortem.** Violations are
   refused at attempt time with the reason written to the agent so it
   self-corrects: guard rules [proven], loop-stop [proven], test-tamper
   [proven], scope fan-out [proven], goal-drift **inside** the session
   [building — today drift speaks at session end; it moves into the gate].
   A session cannot silently leave its pipeline.

4. **Repair that cannot be gamed.** Catch → repair (any model) → re-verify
   through the same gates plus the project's OWN test suite as the oracle
   [proven: verify kernel 7/7, behavior gate 4/4, live repair accepted in
   16s] → only then continue. `repairs accepted` is the honest counter; it
   only counts real breakage, never demos.

5. **The ledger is the product's word.** Every event spools locally,
   drill-tagged, aggregated by `rabadon stats` and the local ui. The public
   benchmark page is generated from the real ledger and reproducible by
   anyone who runs the suite [ahead — numbers exist, the generated page does
   not]. Data never leaves the machine.

6. **Fleet, then strangers.** One builder, all repos, one law distribution,
   one dashboard [proven at 48 repos]. Then the same binary on a stranger's
   machine producing its first real catch [ahead].

## The gates?

Progress is measured by gates, not by dates or version numbers. A gate is
passed when its number is real on this machine's ledger.

- **G1 — kernel.** The engine is one binary: zero node in any hook path, the
  4,000 lines of engine JS retired or ported, suite green, bench republished.
- **G2 — the founder stops writing law.** Seven consecutive days of real work
  in which no rule is hand-written anywhere in the fleet — every new rule
  machine-authored — and goal-drift is blocked mid-session with counted
  events on real sessions.
- **G3 — repair is real.** `repairs accepted > 0` on real, non-demo breakage,
  verified by the broken project's own suite.
- **G4 — first stranger.** One external builder installs rabadon and gets one
  real catch on their machine.
- **G5 — the benchmark.** A public, reproducible numbers page: overhead in
  ms, catches, repairs, drift events — generated from the ledger.

Every commit from here names the gate it serves.

---

# Part II — the contracts

This part specifies the three contracts that make rabadon agent-agnostic:
any runtime that can execute a subprocess before/after an action can
implement them. Claude Code hooks are one binding, not the product.

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
