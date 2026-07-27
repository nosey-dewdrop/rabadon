// The first live LLM repair, as a replayable property — not a story.
//
// demo/fixtures/live-repair-2026-07-26.jsonl is the UNEDITED spool of the run
// where a real Claude call repaired a broken summarize step on this machine
// (2026-07-26 16:10, via the local Claude Code CLI, no API key). This test
// replays it through the same trace layer the dashboard uses and pins the
// facts the README cites. If the fixture and the claims ever drift apart,
// this goes red — the pitch cannot outrun the evidence.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { indexRuns } from '../core/store.mjs';

const FIXTURE = path.join(path.dirname(new URL(import.meta.url).pathname), 'fixtures', 'live-repair-2026-07-26.jsonl');

test('the committed live-repair spool replays to: caught -> repaired by a real LLM in ~11s -> re-checked -> PASS', () => {
  const events = fs.readFileSync(FIXTURE, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  assert.equal(events.length, 7, 'the fixture is the complete run, nothing added, nothing removed');

  const run = indexRuns(events)[0];
  assert.equal(run.verdict, 'PASS');
  assert.equal(run.pipe, 'llm-repair-live');
  assert.deepEqual(run.bound, { maxSteps: 3, maxRepairs: 1 }, 'the repair ran under a bound, not on hope');

  const step = run.steps.find((s) => s.name === 'summarize');
  assert.equal(step.status, 'repaired');
  assert.equal(step.fails.length, 2, 'two silent corruptions were caught before flowing');
  assert.match(step.fails[0].why, /silently dropped/);
  assert.equal(step.repairs.length, 1);
  assert.equal(step.repairs[0].ok, true);

  // the repair took real model time — this is what separates a live LLM fix
  // from a scripted one: 10.886s between REPAIR_START and REPAIR_OK
  const started = events.find((e) => e.ev === 'REPAIR_START').ts;
  const fixed = events.find((e) => e.ev === 'REPAIR_OK').ts;
  const durMs = fixed - started;
  assert.ok(durMs > 5000 && durMs < 60000, `repair duration ${durMs}ms — model-scale, not script-scale`);
});
