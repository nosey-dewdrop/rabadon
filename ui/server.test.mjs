// ui server tests — the dashboard must show EXACTLY what the spool says,
// serve it locally, and push a newly landed event to an open live stream.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createUiServer } from './server.mjs';

const T0 = Date.now() - 60000;
const day = new Date().toISOString().slice(0, 10);
const ev = (seq, run, pipe, evName, extra = {}) => ({ v: 1, seq, ts: T0 + seq * 1000, run, pipe, ev: evName, ...extra });

function seedSpool() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-ui-'));
  const lines = [
    ev(1, 'r1', 'demo:do', 'RUN_START', { steps: ['s1'] }),
    ev(2, 'r1', 'demo:do', 'STEP_START', { step: 's1' }),
    ev(3, 'r1', 'demo:do', 'CHECK_FAIL', { step: 's1', fails: [{ check: 'c', why: 'broken' }] }),
    ev(4, 'r1', 'demo:do', 'REPAIR_OK', { step: 's1', attempt: 1 }),
    ev(5, 'r1', 'demo:do', 'STEP_OK', { step: 's1' }),
    ev(6, 'r1', 'demo:do', 'RUN_DONE', { verdict: 'PASS' }),
  ];
  fs.writeFileSync(path.join(dir, `${day}.jsonl`), lines.map((l) => JSON.stringify(l)).join('\n') + '\n');
  return dir;
}

test('ui: page serves, api matches the spool, live stream pushes an appended event', async () => {
  const spoolDir = seedSpool();
  const ui = await createUiServer({ port: 0, spoolDir, roots: [spoolDir] });
  const base = `http://127.0.0.1:${ui.port}`;

  try {
    // the page
    const html = await fetch(base + '/').then((r) => r.text());
    assert.match(html, /rabadon/);
    assert.match(html, /the ledger/);

    // the ledger numbers come from the spool, one for one
    const sum = await fetch(base + '/api/summary?days=7').then((r) => r.json());
    assert.equal(sum.totals.gated, 1);
    assert.equal(sum.totals.checkFails, 1);
    assert.equal(sum.totals.repairsOk, 1);
    assert.equal(sum.projects[0].project, 'demo');

    // runs carry the reconstructed trace
    const runs = await fetch(base + '/api/runs?days=7').then((r) => r.json());
    assert.equal(runs.count, 1);
    assert.equal(runs.runs[0].verdict, 'PASS');
    assert.equal(runs.runs[0].steps[0].status, 'repaired');

    // single-run endpoint
    const one = await fetch(base + '/api/run?id=r1').then((r) => r.json());
    assert.equal(one.run.id, 'r1');
    assert.equal(one.events.length, 6);

    // fleet endpoint answers (empty here — the tmp root has no guarded projects)
    const fleet = await fetch(base + '/api/fleet').then((r) => r.json());
    assert.deepEqual(fleet.fleet, []);

    // live: open the stream, then append an event to the spool; it must arrive
    const res = await fetch(base + '/api/live');
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';
    const readUntil = (pred, ms) => new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('live event did not arrive in time. got: ' + buf.slice(-300))), ms);
      (async () => {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          buf += decoder.decode(value, { stream: true });
          if (pred(buf)) { clearTimeout(timer); resolve(); return; }
        }
      })().catch(reject);
    });

    await readUntil((b) => b.includes('"run":"r1"'), 3000); // replay arrives first

    const fresh = ev(7, 'r2', 'live-proof', 'RUN_START', { steps: ['x'] });
    fs.appendFileSync(path.join(spoolDir, `${day}.jsonl`), JSON.stringify(fresh) + '\n');
    await readUntil((b) => b.includes('"pipe":"live-proof"'), 5000);
    reader.cancel();
  } finally {
    await ui.close();
  }
});
