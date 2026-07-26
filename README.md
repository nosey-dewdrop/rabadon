# rabadon

The reliability runtime for AI-agent pipelines. It runs your pipeline **and checks itself while running**: it bounds runaway loops, verifies each step's output against what you actually intended, and when a step breaks it doesn't just stop — it repairs the pipeline and continues.

Born from one recurring failure across 20+ solo projects: the imaginative work was never the problem, the plumbing was. Pipelines broke silently. Loops didn't stop and burned tokens. The checks I kept adding were never the right ones. rabadon is the layer that holds the pieces together so the pipeline stays true to its purpose without the builder babysitting it.

## The problem, concretely

An LLM (or a tired human) writes a data pipeline that runs clean on the happy path, passes a glance, and ships. Then in production it silently corrupts real input. Nothing throws. No red. It just quietly produces the wrong answer.

```
WITHOUT rabadon (what a vibecoder ships):
  records in: 4, records out: 3   <- ada (id 0) silently gone
  avgScore reported: 53.33        <- wrong, and nothing crashed
```

## What rabadon does

Wrap the same pipeline. rabadon diagnoses the silent break, stops it before it flows downstream, repairs the step, re-checks, and continues.

```
WITH rabadon (same pipeline, wrapped):
  step "normalize"  -> DIAGNOSED break, REPAIRED, now correct
  step "summarize"  -> DIAGNOSED break, REPAIRED, now correct
  verdict: PASS
  final output: count=4, avgScore=80   <- correct (ada kept, null not counted as 0)
```

## Four guarantees, one primitive

You declare a pipeline as a chain of steps; rabadon runs it and enforces all four while it runs:

| Pain (from real projects) | Guarantee |
|---|---|
| Loops don't stop, burn tokens | `.bound({ maxTokens, maxDepth, maxRepairs })` — a run **won't start** without a bound. Runaway is impossible by construction. |
| Pipelines break silently | `step.correct[]` — named checks compare each step's output to intent, **before** it flows onward. A silent drop is caught, not passed. |
| The pipeline loses its purpose | `.goal(score, floor)` — drift is a number falling below a floor; the run stops. |
| It caught the break but then what? | `step.repair` — diagnose → stop → **repair** → re-check, bounded so the fixer can't run away either. |

```js
import { pipeline, named } from './core/rabadon.mjs'

const result = await pipeline()
  .step('normalize', rows => normalize(rows), {
    correct: [named('noRecordVanishes', (out, inp) =>
      out.length === inp.length ? true : `dropped ${inp.length - out.length} record(s) silently`)],
    repair: () => correctNormalize(inp),
  })
  .step('summarize', rows => summarize(rows), {
    correct: [named('avgOverRealPopulation', ...)],
    repair: () => correctSummarize(rows),
  })
  .bound({ maxSteps: 5, maxRepairs: 2 })
  .run(input)

// result.verdict: 'PASS' | 'RUNAWAY' | 'CHECK_FAILED' | 'DRIFT' | 'THREW'
// result.trace:   what happened at every step, including repairs
```

## Where it sits

Most reliability tools only **watch** a live pipeline (Langfuse, Braintrust, Arize Phoenix — passive tracers). One **stops** it (Galileo — active, inline). rabadon is active **and repairs**: it walks the pipeline back to a working one, not just to a red light. It sits as a synchronous gate — output can't flow to the next step until it passes — which is the only shape that can actually intervene, not just log after the fact.

## One line into existing code: `wrap()`

You don't have to rewrite your pipeline as rabadon steps. Wrap the client you already use — the adoption surface of the passive tracers, with the inline gate they don't have:

```js
import { session } from 'rabadon'

const s = session({ maxCalls: 50, maxTokens: 200_000, maxRepairs: 2 })
const claude = s.wrap(new Anthropic(), {
  correct: [named('non-empty', out => responseText(out).length > 0 || 'empty completion')],
  repair: claudeRepair(),   // optional: a real LLM rewrites the broken output
})

// use `claude` exactly like before — every call is now gated:
//  - the budget is enforced BEFORE the spend (a runaway loop cannot pass it)
//  - checks run on the response BEFORE it flows onward (fail-closed)
//  - a broken response is repaired, re-checked, and only then released
```

`mode: 'observe'` gives you the Langfuse behavior (log, don't block) for day one in an existing codebase; `mode: 'block'` (default) is the real gate.

## Watch it live: `rabadon watch`

Run your pipelines anywhere on the machine; watch every step, break and repair land in another terminal the moment it happens — pushed over a unix socket, not polled from a file:

```
16:00:33.370  llm-repair-live  ▶ run start  [summarize]  bound{maxSteps=3 maxRepairs=1}
16:00:33.371  llm-repair-live  → summarize
16:00:33.371  llm-repair-live  ✗ BROKE  summarize  nothingDropped: total=3 but input had 4 records
16:00:33.371  llm-repair-live  ⟲ repair #1  summarize  fixing: nothingDropped
16:00:33.778  llm-repair-live  ✓ repaired  summarize
16:00:33.778  llm-repair-live  ● PASS
```

Events are also spooled to `~/.rabadon/spool/` so nothing is lost when nobody is watching, and dropped live events are counted, never hidden.

## The LLM repair slot

`repair/claude.mjs` — the piece none of the field has. When a step's checks fail, the broken output and the exact failure reasons go to `claude-opus-4-8` ("this step produced X, the checks failed because Y, rewrite it"). The model's fix is re-run through the SAME intent checks and accepted only if they pass — the LLM gets no free pass, its real token spend counts against the same session budget, and an unfixable break still fails closed. Zero dependencies: raw fetch, bounded retries, 401/400 never retried.

## Where the shape comes from (verified against the field)

| Tool | Integration | Can stop a bad call? | Can repair it? |
|---|---|---|---|
| Langfuse | `observeOpenAI(client)` wrap | no — passive by design ([their words](https://langfuse.com/blog/2024-09-langfuse-proxy)) | no |
| Braintrust | `wrapOpenAI(client)` wrap | no — "only logs" (their docs) | no |
| Galileo | inline `invoke_protect` call | yes — block or canned override | no |
| **rabadon** | **one-line wrap** | **yes — inline, fail-closed** | **yes — bounded, re-checked** |

## Run it

```sh
npm test                          # every guarantee proven: core, wrap, live bus
node demo/vibecoded-pipeline.mjs  # a broken pipeline diagnosed + repaired end to end
node bin/rabadon.mjs watch        # live terminal view (run the demo in another terminal)
node demo/llm-repair-live.mjs     # LIVE Claude repair (needs ANTHROPIC_API_KEY)
```

Zero dependencies. Deterministic. The verdict of a run is data, not a claim.

## Status

In development, building in public. Proven so far, by running code: the core primitive (bound/check/goal/repair), the one-line `wrap()` gate for Anthropic/OpenAI clients with a shared pre-spend budget, the live `rabadon watch` event stream, and fail-closed behavior end to end — including against a real API auth failure, which was caught, not retried, and stopped the flow. The LLM repair slot is written and wired; its first live repair run is the next proof.
