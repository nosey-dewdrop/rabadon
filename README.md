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

## Run it

```sh
node core/rabadon.test.mjs      # 16 proofs the four guarantees actually fire
node demo/vibecoded-pipeline.mjs # a real broken pipeline, diagnosed + repaired end to end
```

Zero dependencies. Deterministic. The verdict of a run is data, not a claim.

## Status

Day 1. The core (`core/rabadon.mjs`) runs, self-checks, and self-heals — proven by 16 passing tests and a working demo. Next: an LLM-backed repair slot (the coded repair in the demo becomes an `claude-opus-4-8` call — "this step produced X, the checks failed because Y, rewrite it", and rabadon only accepts the fix if it provably passes the same intent checks).
