// DEMO — the LLM repair slot, LIVE. Requires ANTHROPIC_API_KEY.
//
// A vibecoded "summarize user feedback" step drops every record whose id is 0
// and mislabels the sentiment counts (same class of silent bug as the coded
// demo — but this time the REPAIR is a real Claude call, not a hand-written
// fix). rabadon: catches the break with the intent checks -> hands the broken
// output + the exact failures to claude-opus-4-8 -> re-runs the SAME checks on
// the model's output -> accepts only if they pass. The LLM gets no free pass.
//
//   node demo/llm-repair-live.mjs

import { pipeline, named } from '../index.mjs';
import { claudeRepair } from '../repair/claude.mjs';

if (!process.env.ANTHROPIC_API_KEY) {
  console.error('ANTHROPIC_API_KEY missing — this demo makes ONE real Claude call.');
  process.exit(1);
}

const FEEDBACK = [
  { id: 0, text: 'love it', sentiment: 'positive' },   // id 0 — the truthiness trap
  { id: 1, text: 'broken on ios', sentiment: 'negative' },
  { id: 2, text: 'fine i guess', sentiment: 'neutral' },
  { id: 3, text: 'best app ever', sentiment: 'positive' },
];

// the vibecoded step: filter(r => r.id) silently eats id 0, and the "positive
// rate" is computed over the post-drop count — wrong number, no crash.
const buggySummarize = (rows) => {
  const kept = rows.filter((r) => r.id);
  const pos = kept.filter((r) => r.sentiment === 'positive').length;
  return { total: kept.length, positive: pos, positiveRate: pos / kept.length };
};

const nothingDropped = named('nothingDropped', (out, input) =>
  out.total === input.length ? true : `total=${out.total} but input had ${input.length} records — something was silently dropped`);

const rateOverTruePopulation = named('rateOverTruePopulation', (out, input) => {
  const truePos = input.filter((r) => r.sentiment === 'positive').length;
  const want = truePos / input.length;
  return Math.abs(out.positiveRate - want) < 1e-9 ? true
    : `positiveRate=${out.positiveRate} but the true rate is ${want} (${truePos}/${input.length})`;
});

let usage = null;
const repair = claudeRepair({ onUsage: (u) => { usage = u; } });

console.log('=== rabadon + LIVE claude-opus-4-8 repair ===\n');
const t0 = Date.now();

const result = await pipeline('llm-repair-live')
  .step('summarize', buggySummarize, { correct: [nothingDropped, rateOverTruePopulation], repair })
  .bound({ maxSteps: 3, maxRepairs: 1 })
  .run(FEEDBACK);

const secs = ((Date.now() - t0) / 1000).toFixed(1);

console.log(`verdict: ${result.verdict}`);
console.log(`output:  ${JSON.stringify(result.output)}`);
console.log(`trace:   ${JSON.stringify(result.trace, null, 2)}`);
if (usage) console.log(`\nrepair spend (REAL, from the API): in=${usage.input_tokens} out=${usage.output_tokens} tokens, ${secs}s`);
console.log(result.ok
  ? '\n>>> the break was caught by the checks, REWRITTEN by Claude, and the fix re-passed the SAME checks. <<<'
  : '\n>>> repair did not satisfy the checks — rabadon failed closed, nothing broken flowed onward. <<<');
