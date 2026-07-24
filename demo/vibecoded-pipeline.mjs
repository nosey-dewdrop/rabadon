// DEMO — rabadon on a vibecoded pipeline that looks right and silently breaks.
//
// This is the exact vibecoding failure mode: an LLM (or a tired human) writes a
// data pipeline that runs clean on the happy path, passes a glance, and ships —
// then silently corrupts real-world input in production. Nothing throws. No red.
// It just quietly produces wrong output, the way Damla's pipelines "ended up
// wrong in ways I hadn't imagined."
//
// The pipeline: take raw user records -> normalize -> compute a summary.
// It has THREE bugs a vibecoder ships without noticing:
//   1. normalize() drops records with a falsy id (id === 0 is a real id!) — a
//      classic truthiness bug. Silent data loss.
//   2. summarize() divides by the count AFTER the drop, so the average is over
//      the wrong denominator — a silently wrong number, no crash.
//   3. nothing bounds the retry the caller does, so on a transient it spins.
//
// rabadon wraps the SAME pipeline, unchanged, and:
//   - DIAGNOSES: a check compares output to intent (no record may vanish; the
//     average must be over the real population) and catches the silent break.
//   - STOPS: the bad output never flows onward.
//   - REPAIRS: a repair fn rewrites the broken step to the correct logic, rabadon
//     re-checks, and the pipeline reaches a correct result — bounded so the fixer
//     can't run away.
//
// No API key, no network — deterministic, so the demo is reproducible and the
// number is real. (The repair here is a coded fix; the same slot takes an LLM
// repair for the general vibecoding case — see NOTE at the bottom.)

import { pipeline, named } from '../core/rabadon.mjs';

// ---- the raw input (real-world: ids start at 0, one record has a null score) ----
const RAW = [
  { id: 0, name: 'ada',  score: 80 },   // id 0 is REAL — the truthiness bug eats it
  { id: 1, name: 'lin',  score: 90 },
  { id: 2, name: 'mel',  score: null },  // missing score — must be handled, not silently 0
  { id: 3, name: 'rio',  score: 70 },
];

// ---- the vibecoded pipeline (buggy, but looks fine) ----
const vibecoded = {
  // BUG 1: `if (r.id)` drops id === 0. Ships green on data whose ids start at 1.
  normalize: (rows) => rows.filter((r) => r.id).map((r) => ({ ...r, name: r.name.trim() })),
  // BUG 2: averages over rows.length but counts null score as 0 in the sum, so the
  // mean is silently dragged down and computed over the wrong denominator.
  summarize: (rows) => {
    const sum = rows.reduce((a, r) => a + (r.score || 0), 0);
    return { count: rows.length, avgScore: sum / rows.length };
  },
};

// ---- the INTENT, expressed as cheap named checks (this is the "right check"
//      Damla could never get right by hand — here it's one honest line each) ----
const noRecordVanishes = named('noRecordVanishes', (out, input) =>
  out.length === input.length ? true
    : `normalize dropped ${input.length - out.length} record(s): ids ${input.filter((r) => !out.some((o) => o.id === r.id)).map((r) => r.id).join(',')} vanished silently`);

const avgOverRealPopulation = named('avgOverScoredPopulation', (out, input) => {
  const scored = input.filter((r) => typeof r.score === 'number');
  const want = scored.reduce((a, r) => a + r.score, 0) / scored.length;
  return Math.abs(out.avgScore - want) < 1e-9 ? true
    : `avgScore=${out.avgScore} but the true average over scored records is ${want} (null scores must not count as 0, denominator must be the scored count)`;
});

// ---- the CORRECT logic the repair installs (diagnose -> repair -> re-check) ----
const repairNormalize = () => (rows) => rows.map((r) => ({ ...r, name: r.name.trim() })); // keep id 0
const repairSummarize = () => (rows) => {
  const scored = rows.filter((r) => typeof r.score === 'number');
  const sum = scored.reduce((a, r) => a + r.score, 0);
  return { count: rows.length, avgScore: sum / scored.length };
};

// ---- run the SAME pipeline twice: once raw (to show the silent break), once
//      wrapped in rabadon (to show diagnose -> stop -> repair -> correct). ----

console.log('=== rabadon on a vibecoded pipeline (looks fine, silently breaks) ===\n');

// 1) what ships without rabadon — no error, wrong answer
const rawNorm = vibecoded.normalize(RAW);
const rawOut = vibecoded.summarize(rawNorm);
console.log('WITHOUT rabadon (what a vibecoder ships):');
console.log(`  records in: ${RAW.length}, records out: ${rawNorm.length}   <- ada (id 0) silently gone`);
console.log(`  avgScore reported: ${rawOut.avgScore}   <- wrong, and nothing crashed\n`);

// 2) the same pipeline, wrapped — rabadon diagnoses, stops, repairs, re-checks
let normFn = vibecoded.normalize;
let sumFn = vibecoded.summarize;

const result = await pipeline()
  .step('normalize', (rows) => normFn(rows), {
    correct: [noRecordVanishes],
    repair: () => { normFn = repairNormalize(); return normFn(RAW); },
  })
  .step('summarize', (rows) => sumFn(rows), {
    correct: [avgOverRealPopulation],
    repair: (broken, rows) => { sumFn = repairSummarize(); return sumFn(rows); },
  })
  .bound({ maxSteps: 5, maxRepairs: 2 })
  .run(RAW);

console.log('WITH rabadon (same pipeline, wrapped):');
for (const t of result.trace) {
  const fixed = t.repairs ? `  -> DIAGNOSED break, REPAIRED (${t.repairs.length}x), now ${t.ok ? 'correct' : 'still broken'}` : '  -> clean';
  console.log(`  step "${t.step}"${fixed}`);
  if (t.repairs) for (const r of t.repairs) console.log(`       repair #${r.attempt}: ${r.ok ? 'FIXED' : 'still: ' + (r.remaining || []).join('; ')}`);
}
console.log(`\n  verdict: ${result.verdict}`);
console.log(`  final output: count=${result.output.count}, avgScore=${result.output.avgScore}   <- correct (ada kept, null not counted as 0)`);
console.log(`\n>>> rabadon didn't just CATCH the silent break — it walked the pipeline back to a working one. <<<`);

// NOTE: the repair fns here install a coded fix so the demo is deterministic and
// needs no key. For the general vibecoding case, the same `repair` slot takes an
// LLM call: repair(broken, input, fails) -> ask the model "this step produced
// `broken`; the checks failed because `fails`; rewrite the step to satisfy them",
// then rabadon re-checks the LLM's fix and only accepts it if the checks pass —
// bounded by maxRepairs so a bad fixer can't run away. The guarantee (a fix is
// only accepted if it provably passes the intent checks) is identical.
