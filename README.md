# rabadon

Supervise your coding agent. rabadon stands at the gate of a live Claude Code session and enforces your project's own laws deterministically, **before** every action: the force-push is refused before it rewrites history, the loop is stopped on its third identical spin, the assertion-strip is refused while the suite is red, the untested push doesn't leave the machine. Underneath sits a reliability runtime for any AI-agent pipeline: bounded budgets enforced pre-spend, named checks on every step's output, and a bounded, re-checked repair slot.

Born from one recurring failure across 20+ solo projects: the imaginative work was never the problem, the plumbing was. Pipelines broke silently. Loops didn't stop and burned tokens. The checks I kept adding were never the right ones. rabadon is the layer that holds the pieces together so the work stays true to its purpose without the builder babysitting it.

Everything is local, by law: events go over a unix socket into `~/.rabadon/spool/` on your machine. No account, no upload, nothing leaves.

## Try it (not on npm yet — clone and link)

```sh
git clone https://github.com/nosey-dewdrop/rabadon && cd rabadon
npm test          # zero dependencies; every guarantee proven before you trust it
npm link          # `rabadon` becomes a global command

cd your-project
rabadon init      # authors guard rules from YOUR law files (CLAUDE.md / RULES.md),
                  # merges hooks into your existing .claude/settings.json —
                  # nothing of yours is overwritten (a .bak-rabadon is made)
claude            # work normally — the session is supervised
rabadon stats     # the ledger: what was caught, backed by timestamped events
```

Built in, on every session, no configuration:
- **loop-stop** — the same command run 3x with no code change in between is a loop, not progress; refused.
- **test-tamper** — while the suite is red, an edit that weakens a test file (skip added, assertions removed) is refused. Fix the code, not the thermometer.
- **push gate** — if your laws demand green tests before push, rabadon runs the suite itself at push time and decides on the real result, never on a claim.
- **scope fan-out** — a task spreading across a 5th top-level directory gets challenged once.

Escape hatches are first-class: `rabadon off` pauses everything instantly, and every refusal names its rule id so you can disable exactly that rule (`"disabled": ["rule-id"]` in `.rabadon/guard.json`).

From week one on the author's machine, all replayable from the spool: a mid-session `wrangler deploy` refused by a project's own deny rule, pinned reference files protected from overwrite, red-suite test edits refused. rabadon's own synthetic drills are tagged at emit and excluded from every ledger number — self-tests are not catches.

## The dashboard: `rabadon ui`

The surface the hosted platforms sell — traces, catch ledger, live feed — standing on your own disk:

```sh
rabadon ui --root ~/code    # then open http://127.0.0.1:8484
```

- **the ledger** — actions gated, caught before happening, breaks caught, repairs accepted; every number backed by a timestamped event in the spool, drills excluded.
- **traces** — every run reconstructed step by step: what broke, what was repaired, what verdict closed it. The same shape Langfuse/Braintrust call a trace; the vocabulary here is what the gate *did*, not what the model said.
- **live** — events stream in the moment they land, from every pipeline, session and motor run on the machine.
- **fleet** — every project standing under guard: rules, hooks, push gate, state.

Local only: binds `127.0.0.1`, reads `~/.rabadon/spool/`, nothing leaves the machine.

---

## The engine underneath

The session guard is one binding of a smaller thing: a runtime that runs work in bounded, checked, repairable steps. Any runtime that can execute a subprocess can implement the same gate contract — see `SPEC.md`.

### Four guarantees, one primitive

```js
import { pipeline, named } from 'rabadon'

const result = await pipeline()
  .step('normalize', rows => normalize(rows), {
    correct: [named('noRecordVanishes', (out, inp) =>
      out.length === inp.length ? true : `dropped ${inp.length - out.length} record(s) silently`)],
    repair: () => correctNormalize(inp),
  })
  .bound({ maxSteps: 5, maxRepairs: 2 })   // a run WON'T START without a bound
  .goal(score, 0.8)                        // drift = a number falling below a floor
  .run(input)

// result.verdict: 'PASS' | 'RUNAWAY' | 'CHECK_FAILED' | 'DRIFT' | 'THREW'
// result.trace:   what happened at every step, including repairs
```

| Pain (from real projects) | Guarantee |
|---|---|
| Loops don't stop, burn tokens | `.bound({...})` — enforced **before** the spend, runaway impossible by construction |
| Pipelines break silently | `step.correct[]` — named checks gate each output **before** it flows onward |
| The pipeline loses its purpose | `.goal(score, floor)` — drift is measured, the run stops |
| Caught the break, then what? | `step.repair` — diagnose → stop → repair → **re-check**, bounded |

Run the end-to-end demo: `node demo/vibecoded-pipeline.mjs` — a really-broken pipeline (silent id-0 drop, wrong denominator) diagnosed, stopped, repaired, verdict PASS. Its repair fns are coded fixes so the demo is deterministic and key-free; the LLM slot does the general case (below).

### One line into existing code: `wrap()`

```js
import { session } from 'rabadon'

const s = session({ maxCalls: 50, maxTokens: 200_000, maxRepairs: 2 })
const claude = s.wrap(new Anthropic(), {
  correct: [named('non-empty', out => responseText(out).length > 0 || 'empty completion')],
  repair: claudeRepair(),   // optional: a real LLM rewrites the broken output
})
// use `claude` exactly like before — every call is now gated:
//  - the budget is enforced BEFORE the spend
//  - checks run on the response BEFORE it flows onward (fail-closed)
//  - a broken response is repaired, re-checked, and only then released
```

Fail-closed also means **no un-gated side door**: a wrapped client refuses the spend surfaces the gate cannot count or check (`responses`, `embeddings`, `batches`, `beta`, `stream: true`) instead of letting them silently bypass the budget. `mode: 'observe'` lets everything flow for day one — but loudly, on the record. Tool-calling responses count as payload (`responseText` serializes `tool_use`/`tool_calls`), so agentic traffic doesn't fail-close on a text check.

### The motor: `rabadon do`

Task in, gate-verified output out. You don't declare steps — you state the task, and rabadon plans, runs, gates and pivots until done or an honest stop:

```sh
rabadon do "make the failing suite green without weakening any test" ~/code/my-project
```

**PLAN** — one model call decomposes the task; every step gets a MECHANICAL contract (command exits green / file exists / pattern present). No LLM ever judges pass/fail. **RUN** — deterministic runner; shell steps cost zero tokens. **GATE** — each contract runs before anything flows onward. **PIVOT** — one repair, then one bounded replan. **ACCEPT** — the task-level contract decides "done" as a measurement, not a claim.

First real run, on this repo: `rabadon do` added the `--version` flag to its own CLI — 6-step plan (1 work + 5 mechanical), 0 pivots, acceptance PASS in 59s, suite green after.

### Watch it live: `rabadon watch`

Every step, break and repair lands in another terminal the moment it happens — pushed over a unix socket, not polled. This is the actual transcript of the first live LLM repair on this machine (2026-07-26; the unedited spool of this run is committed at `demo/fixtures/live-repair-2026-07-26.jsonl` and pinned by `demo/live-repair-evidence.test.mjs`):

```
16:10:23.407  llm-repair-live  ▶ run start  [summarize]  bound{maxSteps=3 maxRepairs=1}
16:10:23.407  llm-repair-live  → summarize
16:10:23.407  llm-repair-live  ✗ BROKE  summarize  nothingDropped: total=3 but input had 4 records — something was silently dropped | rateOverTruePopulation: positiveRate=0.33… but the true rate is 0.5 (2/4)
16:10:23.407  llm-repair-live  ⟲ repair #1  summarize  fixing: nothingDropped, rateOverTruePopulation
16:10:34.293  llm-repair-live  ✓ repaired  summarize  (attempt 1)
16:10:34.294  llm-repair-live  ● PASS
```

10.9 seconds of real model time between `repair #1` and `repaired` — a live Claude call through the local Claude Code CLI (no API key needed), its fix re-run through the same intent checks before acceptance.

### The LLM repair slot

`repair/claude.mjs` (API) and `repair/claude-code.mjs` (local CLI, zero setup). When a step's checks fail, the broken output and the exact failure reasons go to the model; the fix is re-run through the SAME checks and accepted only if they pass. The model gets no free pass, its spend counts against the same session budget, and an unfixable break still fails closed.

Honest lineage: Guardrails' ReAsk and Instructor's `max_retries` re-ask the model when a single structured output fails validation — real prior art. rabadon generalizes the move past the single-output case: any pipeline step or session action, bounded by the shared budget, fail-closed when the fix doesn't pass.

## Where it sits (verified against the field)

| Tool | Integration | Can stop a bad call? | Can repair it? | Scope |
|---|---|---|---|---|
| Langfuse | `observeOpenAI(client)` wrap | no — passive by design ([their words](https://langfuse.com/blog/2024-09-langfuse-proxy)) | no | tracing |
| Braintrust | `wrapOpenAI(client)` wrap | no — "only logs" (their docs) | no | tracing/evals |
| Galileo | inline `invoke_protect` | yes — block or canned override | no | one call |
| Guardrails AI | validator wrap | yes — validation failure | re-ask, single output | one output |
| Instructor | patched client | yes — schema failure | retries, single output | one output |
| **rabadon** | **wrap / hooks / CLI** | **yes — inline, fail-closed, pre-spend** | **yes — any step or session action, bounded, re-checked** | **pipeline + session, one budget** |

What nobody else in this table does: supervise a live coding-agent session (loop-stop, test-tamper, push gate) and hold one pre-spend budget across a whole session — locally, with the ledger on your own disk.

## Run it

```sh
npm test                          # core, wrap, bus, store, ui, gate, do, repair evidence
node demo/vibecoded-pipeline.mjs  # broken pipeline diagnosed + repaired end to end
node bin/rabadon.mjs watch        # live terminal view
node bin/rabadon.mjs ui           # the dashboard on 127.0.0.1:8484
node demo/llm-repair-live.mjs     # LIVE Claude repair (Claude Code CLI or ANTHROPIC_API_KEY)
```

## Status

In development, building in public. Proven so far, by running code committed here: the session gate (deny rules, loop-stop, test-tamper, push gate — tested through the real binary), the core primitive, the `wrap()` gate with pre-spend budget and no un-gated side door, one live LLM repair (fixture-committed, test-pinned), one real `rabadon do` task closed end to end, and the local dashboard. The ledger excludes rabadon's own drills by construction. Not on npm yet; no external user yet — the first catch on a stranger's machine is the next proof this README will cite.
