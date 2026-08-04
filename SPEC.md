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

1. **One command install, native core.** `rabadon` installs with
   `npm i -g rabadon`: prebuilt zero-dependency C++ binaries per platform
   (`@rabadon/<os>-<cpu>` optional deps), with a source-build fallback. Gate,
   session kernel, drift, verify, loop, task engine, stats, audit, repair,
   sandbox, export, doctor, init — all native. Median per-event overhead under
   5ms [proven for gate: 2.3ms vs 101ms node]. [proven: prebuilt packaging +
   provenance workflow wired; first npm publish pending the maintainer]

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

4. **Repair that cannot be gamed.** Catch → repair (`claude -p`) proposes in
   an isolated copy → re-verify by re-running the project's OWN check with
   every test file hash-locked → a green, tamper-free result becomes a HELD
   patch the human applies, never an auto-edit [proven: session repair loop
   13/13, verify kernel 7/7, fake/test-weakening fixes rejected]. `repairs
   accepted` only counts real breakage fixed and re-verified, never demos.

5. **The ledger is the product's word, and it is verifiable.** Every event
   spools locally and is hash-chained to the one before it, so `rabadon audit`
   can prove the record was not edited after the fact [proven: tamper
   detection 9/9], and `rabadon export --otlp` renders it in any OpenTelemetry
   backend [proven 7/7]. Drills are tagged at emit and excluded from every
   number. Data never leaves the machine. [building: the local ui dashboard is
   a stub; `rabadon watch` is the live surface]

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
- **G3 — repair is real.** `repairs held > 0` on real, non-demo breakage,
  verified by the broken project's own suite while its test files were
  hash-locked. Accepted-but-unwitnessed does not clear this gate.
  **[proven 2026-08-01: `repairs held 2`.** expressjs/express @ a3714473, its own
  mocha suite (1260 tests) as the arbiter, 91 test files hash-locked; two injected
  source bugs — an off-by-one in `lib/request.js`, a flipped comparison in
  `lib/response.js` — each came back as a held patch that is the exact inverse,
  the tree never edited. The same path refused a proposer that bought the green by
  skipping the failing test, and the held counter did not move. Raw evidence, and
  the rung that had to be repaired to get there:
  `reports/2026-08-01-g3-first-held-repair/`.**]
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
  "sess": "<session id>", "call": "<tool call id>",
  "step": "Bash", "fails": [{ "check": "<rule id>", "why": "<reason>" }],
  "prev": "<sha256 of the previous event line in this day-file>" }
```

**Identity: `sess` and `call`.** Neither is decoration and neither can be
reconstructed from the rest of the line. `run` is per *process* — 75,126 live
events carried 75,126 distinct run ids, zero reuse — and `pipe` is spelled
`<project>:session` but is the *directory*, so it holds every session and every
subagent that has ever run there. `sess` is the session id and is what a reader
must key a trace off; `call` is the id of the tool call an event belongs to, the
same value on the event that opens it and the event that closes it, and it is
the only thing that says a `STEP_START` and a `STEP_OK` are two ends of one
call. Both are OPTIONAL and both are ABSENT rather than empty when a producer
has no answer — an event outside any tool call (a session start, a stop) is not
a member of a nameless call, and `""` would make all of them look like one.
A reader MUST tolerate their absence and say so rather than guess: rabadon's own
exporter falls back to the pipe for a trace and marks the span
`rabadon.export.trace_basis: pipe`, and leaves an unpaired event a point in time
rather than inventing a width for it.

`ev` vocabulary (fixed): `RUN_START`, `STEP_START`, `STEP_OK`, `CHECK_FAIL`,
`WOULD_BLOCK`, `REPAIR_START`, `REPAIR_OK`, `REPAIR_FAIL`, `STOP`, `RUN_DONE`.
A `STOP` with `"reason": "BLOCKED"` is a catch: something was refused before it
happened; it also carries `"rule"` (the id) and `"sid"` (session id). A
`WOULD_BLOCK` is the watch-mode counterpart — the same verdict, recorded but
not enforced. Unknown fields MUST be preserved; unknown `ev` values MUST be
rendered generically, never dropped. A reader that decides what to render from
a hardcoded list of verbs breaks this the day anyone extends the vocabulary,
and it breaks quietly — `rabadon export --otlp` carried an eight-name
allow-list that dropped every unknown `ev` *and* two of the ten above,
`STEP_OK` and `REPAIR_START`, which this project's own binaries emit. The G3
proof ledger — 5 `REPAIR_START`, 2 `REPAIR_OK`, 3 `REPAIR_FAIL` — left the
machine as five spans: repairs that finish without ever starting. Held by
`native/export_test.sh` arms 8 and 9, as a COUNT of events in against spans
out, so a filter cannot return under a longer list.

**Hash chain (tamper-evidence).** Each event carries `prev` = the SHA-256 of
the entire previous event line in the same day-file (`"genesis"` for the
first). A verifier (`rabadon audit`) re-walks the chain and reports any line
whose `prev` does not match, by file and line number. A `.head` sidecar holds
the hash of the last chained line so truncation cannot hide. Lines written by
producers that predate the chain (or that do not implement it) carry no `prev`
and MUST be tolerated as *unchained* — counted and reported, never silently
trusted.

**Serialization is NOT part of the contract.** A line is JSON. This spec fixes
no byte layout: no compact separators, no key order, no "the bytes rabadon's
own printf emits". A producer using a stock serializer writes `"prev": "..."`
with a space, and its chain is exactly as valid. Every reader — audit, export,
usage, the chain writer's own line count — MUST therefore parse the line, and
MUST NOT decide by substring-matching `"key":"`. This is not a style note: the
byte match made `rabadon audit` answer *TAMPER-EVIDENT BREAK, the chain was
stripped out* over a ledger whose every `prev` was the correct SHA-256, and
made `rabadon export --otlp` render zero spans over ten real events. A verifier
whose true predicate is "these bytes came from me" does not verify a chain, it
fingerprints an emitter — and it converts Part II's agent-agnostic promise into
a false accusation against the first stranger who honours it. Held by
`native/audit_test.sh` arms (g)/(h) and `native/export_test.sh` arm 7.

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
  "network":        "deny",
  "disabled":       ["rule-id"]
}
```

`protectedPaths` and `network` are also the source for kernel enforcement:
`rabadon exec -- <cmd>` compiles them into an OS sandbox (macOS Seatbelt,
Linux bubblewrap) so a forbidden write or denied network call fails with
`EPERM` even when the hook is bypassed. A `match` regex with no literal path
prefix cannot be kernel-fenced (the hook still checks it) and MUST be reported,
never silently treated as enforced.

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
