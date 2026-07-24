// Proof that the core actually enforces its four guarantees. Run: node core/rabadon.test.mjs
import { pipeline, named } from './rabadon.mjs';

let pass = 0, fail = 0;
function ok(cond, label) {
  if (cond) { pass++; console.log(`  ok   ${label}`); }
  else { fail++; console.log(`  FAIL ${label}`); }
}

// --- guarantee #2: a silently dropped feature is caught, not passed. ---
{
  const r = await pipeline()
    .step('draft', (spec) => ({ features: spec.want.filter((f) => f !== 'ruffle') }), {
      correct: [named('noSilentDrop', (out, inp) => {
        const dropped = inp.want.filter((f) => !out.features.includes(f));
        return dropped.length ? `silently dropped: ${dropped.join(', ')}` : true;
      })],
    })
    .bound({ maxSteps: 4 })
    .run({ want: ['collar', 'ruffle', 'pocket'] });
  ok(r.verdict === 'CHECK_FAILED', 'silent drop -> CHECK_FAILED');
  ok(r.detail.includes('ruffle') === false && r.trace[0].fails[0].why.includes('ruffle'), 'the dropped feature is named in the trace');
}

// --- guarantee #1: an unbounded pipeline refuses to run (construction error). ---
{
  let threw = false;
  try { await pipeline().step('x', (i) => i).run(1); } catch (e) { threw = /no \.bound/.test(e.message); }
  ok(threw, 'no bound -> run refuses to start');
}

// --- guarantee #1/#3: a runaway is stopped at the bound, before the work. ---
{
  const r = await pipeline()
    .step('a', (i) => i + 1)
    .step('b', (i) => i + 1)
    .step('c', (i) => i + 1)
    .bound({ maxSteps: 2 })
    .run(0);
  ok(r.verdict === 'RUNAWAY', 'maxSteps -> RUNAWAY');
  ok(r.trace.length === 2, 'stopped exactly at the bound (2 steps ran, not 3)');
}

// --- guarantee #4: goal drift stops the run. ---
{
  const r = await pipeline()
    .step('onGoal', () => ({ q: 0.9 }))
    .step('drifts', () => ({ q: 0.2 }))
    .step('never', () => ({ q: 0.9 }))
    .goal(({ output }) => output.q, 0.5)
    .bound({ maxSteps: 9 })
    .run(null);
  ok(r.verdict === 'DRIFT', 'score below floor -> DRIFT');
  ok(r.trace.length === 2 && r.trace[1].drift === true, 'drift caught at the step it happened, run halts');
}

// --- happy path: everything passes -> PASS with the real output. ---
{
  const r = await pipeline()
    .step('double', (n) => n * 2, { correct: [named('positive', (o) => o > 0 || 'not positive')] })
    .step('inc', (n) => n + 1)
    .bound({ maxSteps: 5 })
    .run(21);
  ok(r.verdict === 'PASS' && r.output === 43, 'clean run -> PASS with correct output');
}

// --- self-healing: a broken step is diagnosed, repaired, and the run continues. ---
{
  let repairCalls = 0;
  const r = await pipeline()
    .step('draft', (spec) => ({ features: spec.want.filter((f) => f !== 'ruffle') }), {
      correct: [named('noSilentDrop', (out, inp) => {
        const dropped = inp.want.filter((f) => !out.features.includes(f));
        return dropped.length ? `dropped: ${dropped.join(', ')}` : true;
      })],
      // the fixer: put back whatever the checks said was dropped
      repair: (broken, inp, fails) => {
        repairCalls++;
        return { features: inp.want.slice() }; // restore all
      },
    })
    .bound({ maxSteps: 4, maxRepairs: 3 })
    .run({ want: ['collar', 'ruffle', 'pocket'] });
  ok(r.verdict === 'PASS', 'broken step -> repaired -> PASS (not just stopped)');
  ok(repairCalls === 1, 'repair ran exactly once and fixed it');
  ok(r.output.features.includes('ruffle'), 'the dropped feature is back in the output');
  ok(r.trace[0].repairs && r.trace[0].repairs[0].ok === true, 'the repair is recorded in the trace');
}

// --- repair is bounded: a fixer that can't fix gives up at maxRepairs, no runaway. ---
{
  let tries = 0;
  const r = await pipeline()
    .step('x', (i) => i, {
      correct: [named('never', () => 'always broken')],
      repair: (b) => { tries++; return b; }, // repair that never actually fixes
    })
    .bound({ maxSteps: 2, maxRepairs: 3 })
    .run(1);
  ok(r.verdict === 'CHECK_FAILED', 'unfixable step -> still stops (does not loop forever)');
  ok(tries === 3, 'repair tried exactly maxRepairs=3 times then gave up');
  ok(/repair tried 3x/.test(r.detail), 'the verdict says repair was attempted and still failed');
}

// --- fail-closed: a check that returns nothing is a FAILURE, not a silent pass. ---
{
  const r = await pipeline()
    .step('x', (i) => i, { correct: [named('sloppy', () => { /* returns undefined */ })] })
    .bound({ maxSteps: 2 })
    .run(1);
  ok(r.verdict === 'CHECK_FAILED', 'check with no verdict -> fail-closed');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
