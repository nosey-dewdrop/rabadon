// rabadon core — the reliability runtime for AI agent pipelines.
//
// One primitive. You declare a pipeline as a chain of steps; rabadon RUNS it and
// CHECKS ITSELF while running. It is the layer that holds the pieces together so
// the pipeline stays true to its purpose without the builder babysitting it.
//
// The four pains from the launch post map to four guarantees, all here:
//   1. runaway loops burn tokens   -> .bound({...}) — a run without a bound is a
//                                     construction error; the loop cannot start.
//   2. pipelines break silently    -> step.correct[] — named checks compare a
//                                     step's output against intent; a failing
//                                     check does NOT pass silently, it is recorded.
//   3. loops give birth to loops   -> the same bound, in the depth dimension.
//   4. the pipeline loses its goal -> .goal(fn) — a scored number; drift = the
//                                     score falling below a floor.
//
// rabadon does not predict the future and it does not wait for the error to
// surface at the end. Every step is checked BEFORE its output flows to the next
// step, so a fault is caught where it is born, not eight steps downstream.
//
// Zero dependencies. Deterministic. The verdict of a run is data, not a claim.

/**
 * A named check on a step's output. It receives (output, input, ctx) and returns
 * either true (pass) or a string/object describing what silently went wrong.
 * A check must never throw for a normal failure — it returns the reason.
 * @typedef {(output:any, input:any, ctx:object) => (true | string | {ok:boolean, why?:string})} Check
 */

/** Normalize a check's return into { ok, why }. */
function readCheck(result, name) {
  if (result === true) return { ok: true };
  if (result === false) return { ok: false, why: `${name} returned false` };
  if (typeof result === 'string') return { ok: false, why: result };
  if (result && typeof result === 'object' && 'ok' in result) {
    return { ok: !!result.ok, why: result.ok ? undefined : (result.why || `${name} failed`) };
  }
  // A check that returns undefined/null is treated as a silent pass would be the
  // exact bug rabadon exists to kill — so we FAIL CLOSED and say so.
  return { ok: false, why: `${name} returned no verdict (fail-closed)` };
}

/** Run every check on a step's output; return the list of failures (empty = clean). */
async function runChecks(step, out, input, ctx) {
  const fails = [];
  for (let c = 0; c < step.correct.length; c++) {
    const name = step.correct[c].checkName || `check#${c}`;
    let verdict;
    try {
      verdict = readCheck(await step.correct[c](out, input, ctx), name);
    } catch (err) {
      verdict = { ok: false, why: `${name} threw: ${String(err && err.message || err).slice(0, 160)}` };
    }
    if (!verdict.ok) fails.push({ check: name, why: verdict.why });
  }
  return fails;
}

class Pipeline {
  constructor() {
    this._steps = [];
    this._bound = null;     // { maxSteps, maxTokens, maxDepth }
    this._goal = null;      // { score: fn, floor: number }
  }

  /**
   * Declare one step of the pipeline.
   * @param {string} name
   * @param {(input:any, ctx:object) => any} run   the actual work (may be async)
   * @param {{ correct?: Check[], cost?: (output:any, input:any) => number }} [opts]
   *   correct: named checks run on this step's output, BEFORE it flows onward.
   *   cost:    optional token/unit cost of this step, counted against the bound.
   */
  step(name, run, opts = {}) {
    if (typeof name !== 'string' || !name) throw new Error('rabadon: step needs a name');
    if (typeof run !== 'function') throw new Error(`rabadon: step "${name}" needs a run function`);
    const correct = opts.correct || [];
    for (const c of correct) {
      if (typeof c !== 'function') throw new Error(`rabadon: step "${name}" has a non-function check`);
    }
    // repair: when this step's checks fail, rabadon does not just stop — it hands
    // the failing output + the exact reasons back to a repair function to REWRITE
    // it, then re-checks. This is the self-healing loop: diagnose -> stop -> repair
    // -> re-run, bounded by maxRepairs so the fixer can never run away either.
    // Signature: repair(brokenOutput, input, fails[], ctx) -> a new output.
    if (opts.repair != null && typeof opts.repair !== 'function') {
      throw new Error(`rabadon: step "${name}" repair must be a function (brokenOutput, input, fails, ctx) => newOutput`);
    }
    this._steps.push({ name, run, correct, cost: opts.cost || null, repair: opts.repair || null });
    return this;
  }

  /**
   * Bound the run. THIS IS NOT OPTIONAL for a loop: .run() refuses to start
   * without a bound, so an unbounded runaway can never be written by accident.
   * @param {{ maxSteps?: number, maxTokens?: number, maxDepth?: number }} b
   */
  bound(b = {}) {
    const clean = {};
    for (const k of ['maxSteps', 'maxTokens', 'maxDepth', 'maxRepairs']) {
      if (b[k] != null) {
        if (!(Number.isFinite(b[k]) && b[k] > 0)) throw new Error(`rabadon: bound.${k} must be a positive number`);
        clean[k] = b[k];
      }
    }
    if (Object.keys(clean).length === 0) throw new Error('rabadon: .bound({}) must set at least one of maxSteps/maxTokens/maxDepth/maxRepairs');
    this._bound = clean;
    return this;
  }

  /**
   * Pin the pipeline's purpose to a number. After each step the score is measured;
   * if it drops below the floor, the run stops for DRIFT — the pipeline lost its goal.
   * @param {(state:{input:any, output:any, step:string}) => number} score  0..1 or any scale
   * @param {number} floor
   */
  goal(score, floor) {
    if (typeof score !== 'function') throw new Error('rabadon: .goal needs a score function');
    if (!Number.isFinite(floor)) throw new Error('rabadon: .goal needs a numeric floor');
    this._goal = { score, floor };
    return this;
  }

  /**
   * Run the pipeline on one input. Returns a full verdict object — never throws
   * for a pipeline-level failure (bad output, runaway, drift). It only throws for
   * a CONSTRUCTION error (no bound, no steps) so those surface loud at dev time.
   * @returns {Promise<Verdict>}
   */
  async run(input) {
    if (this._steps.length === 0) throw new Error('rabadon: pipeline has no steps');
    if (!this._bound) throw new Error('rabadon: .run() refused — no .bound() set. An unbounded pipeline is a runaway waiting to happen; declare maxSteps/maxTokens/maxDepth.');

    const trace = [];
    const ctx = { tokens: 0, depth: 0, input };
    let cur = input;
    let stopped = null; // { reason, detail }

    for (let i = 0; i < this._steps.length; i++) {
      const step = this._steps[i];
      ctx.depth = i + 1;

      // --- guarantee #1/#3: bound BEFORE doing the work (pre-action gate). ---
      const b = this._bound;
      if (b.maxSteps != null && i >= b.maxSteps) { stopped = { reason: 'RUNAWAY', detail: `maxSteps=${b.maxSteps} reached before "${step.name}"` }; break; }
      if (b.maxDepth != null && ctx.depth > b.maxDepth) { stopped = { reason: 'RUNAWAY', detail: `maxDepth=${b.maxDepth} exceeded at "${step.name}"` }; break; }
      if (b.maxTokens != null && ctx.tokens >= b.maxTokens) { stopped = { reason: 'RUNAWAY', detail: `maxTokens=${b.maxTokens} spent before "${step.name}" (spent ${ctx.tokens})` }; break; }

      // --- run the step ---
      let out;
      try {
        out = await step.run(cur, ctx);
      } catch (err) {
        stopped = { reason: 'THREW', detail: `step "${step.name}" threw: ${String(err && err.message || err).slice(0, 200)}` };
        trace.push({ step: step.name, ok: false, threw: true, why: stopped.detail });
        break;
      }

      // count cost against the bound (so the NEXT step's gate sees it)
      if (step.cost) { try { ctx.tokens += Number(step.cost(out, cur)) || 0; } catch { /* cost is advisory */ } }

      // --- guarantee #2: correctness checks BEFORE the output flows onward. ---
      let checkFails = await runChecks(step, out, cur, ctx);

      // --- self-healing: diagnose -> stop -> repair -> re-check, bounded. ---
      // If the step declared a repair fn and its checks failed, rabadon does not
      // give up at the first break — it hands the broken output and the exact
      // failure reasons to repair() to rewrite, then re-checks. It keeps doing
      // this up to maxRepairs, so the fixer itself can never run away. The point
      // of rabadon: it doesn't only catch the break, it walks the pipeline back
      // to a working one.
      const repairs = [];
      if (checkFails.length && step.repair && this._bound.maxRepairs) {
        for (let attempt = 1; attempt <= this._bound.maxRepairs && checkFails.length; attempt++) {
          let fixed;
          try {
            fixed = await step.repair(out, cur, checkFails, ctx);
          } catch (err) {
            repairs.push({ attempt, ok: false, why: `repair threw: ${String(err && err.message || err).slice(0, 160)}` });
            break;
          }
          const reFails = await runChecks(step, fixed, cur, ctx);
          repairs.push({ attempt, ok: reFails.length === 0, fixedFrom: checkFails.map((f) => f.check), remaining: reFails.map((f) => f.why) });
          out = fixed;
          checkFails = reFails;
        }
      }

      const stepRecord = { step: step.name, ok: checkFails.length === 0, tokens: ctx.tokens };
      if (checkFails.length) stepRecord.fails = checkFails;
      if (repairs.length) stepRecord.repairs = repairs;

      // --- guarantee #4: goal score after the step; drift = score below floor. ---
      if (this._goal) {
        let s;
        try { s = Number(this._goal.score({ input, output: out, step: step.name })); } catch { s = NaN; }
        stepRecord.goalScore = s;
        if (Number.isFinite(s) && s < this._goal.floor) {
          stepRecord.drift = true;
          trace.push(stepRecord);
          stopped = { reason: 'DRIFT', detail: `goalScore ${s} fell below floor ${this._goal.floor} at "${step.name}"` };
          cur = out;
          break;
        }
      }

      trace.push(stepRecord);

      // A silent drop is a fault. If repair was available it already tried; if it
      // still fails, rabadon STOPS so nothing broken propagates downstream. A step
      // that had no repair fn stops on the first failure (fail-closed by default).
      if (checkFails.length) {
        const repaired = step.repair ? ` (repair tried ${stepRecord.repairs ? stepRecord.repairs.length : 0}x, still failing)` : '';
        stopped = { reason: 'CHECK_FAILED', detail: `${step.name}: ${checkFails.map(f => f.check).join(', ')}${repaired}` };
        cur = out;
        break;
      }

      cur = out;
    }

    const ok = stopped === null;
    return {
      ok,
      verdict: ok ? 'PASS' : stopped.reason,
      detail: ok ? 'all steps passed, on-goal, within bounds' : stopped.detail,
      output: cur,
      tokensSpent: ctx.tokens,
      depth: ctx.depth,
      trace,
    };
  }
}

/**
 * @typedef {object} Verdict
 * @property {boolean} ok
 * @property {'PASS'|'RUNAWAY'|'CHECK_FAILED'|'DRIFT'|'THREW'} verdict
 * @property {string} detail
 * @property {any} output
 * @property {number} tokensSpent
 * @property {number} depth
 * @property {Array} trace
 */

/** Give a check a stable name so the verdict is readable. Optional but recommended. */
export function named(name, fn) {
  fn.checkName = name;
  return fn;
}

/** Start a new pipeline. */
export function pipeline() {
  return new Pipeline();
}

export default { pipeline, named };
