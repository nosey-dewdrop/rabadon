// rabadon bus tests — the live stream proven over a real unix socket.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// isolate: point the bus at a temp dir BEFORE importing it
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-bus-test-'));
process.env.RABADON_DIR = tmp;
const { emitter, listen } = await import('./bus.mjs');

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

test('events flow pipeline -> socket -> watcher, in order, parsed', async () => {
  const got = [];
  const server = await listen((e) => got.push(e));

  const emit = emitter({ pipe: 'test-pipe' });
  emit('RUN_START', { steps: ['a', 'b'] });
  emit('STEP_START', { step: 'a' });
  emit('CHECK_FAIL', { step: 'a', fails: [{ check: 'c', why: 'broke' }] });
  emit('RUN_DONE', { verdict: 'CHECK_FAILED' });

  await wait(150); // connect + flush is async by design (never blocks the pipeline)
  emit.close();
  await server.close();

  assert.equal(got.length, 4, `watcher must receive all 4 events (got ${got.length})`);
  assert.deepEqual(got.map((e) => e.ev), ['RUN_START', 'STEP_START', 'CHECK_FAIL', 'RUN_DONE']);
  assert.equal(got[0].pipe, 'test-pipe');
  assert.equal(got[2].fails[0].why, 'broke');
  assert.ok(got.every((e) => e.run === got[0].run), 'all events carry the same run id');
});

test('no watcher: pipeline is unharmed and events land in the spool', async () => {
  const emit = emitter({ pipe: 'lonely-pipe' });
  emit('RUN_START', {});
  emit('RUN_DONE', { verdict: 'PASS' });
  await wait(50);
  emit.close();

  const spoolDir = path.join(tmp, 'spool');
  const files = fs.readdirSync(spoolDir);
  assert.ok(files.length >= 1, 'spool file must exist');
  const lines = fs.readFileSync(path.join(spoolDir, files[0]), 'utf8').trim().split('\n')
    .map((l) => JSON.parse(l)).filter((e) => e.pipe === 'lonely-pipe');
  assert.equal(lines.length, 2, 'both events must be in the spool even with nobody watching');
});

test('an unserializable detail cannot kill the pipeline', async () => {
  const emit = emitter({ pipe: 'cyclic' });
  const cyclic = {}; cyclic.self = cyclic;
  assert.doesNotThrow(() => emit('STEP_OK', { data: cyclic }));
  emit.close();
});
