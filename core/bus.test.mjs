// rabadon bus tests — the live stream proven over a real unix socket.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFile } from 'node:child_process';

// isolate: point the bus at a temp dir BEFORE importing it
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-bus-test-'));
process.env.RABADON_DIR = tmp;
const { emitter, listen, jsSpoolPath } = await import('./bus.mjs');

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
  // .jsonl only: a chained day file is not alone in the spool any more, it sits
  // beside its .head sidecar, and JSON.parse on "<sha256> <count>" throws.
  const files = fs.readdirSync(spoolDir).filter((f) => f.endsWith('.jsonl'));
  assert.ok(files.length >= 1, 'spool file must exist');
  const lines = files.flatMap((f) => fs.readFileSync(path.join(spoolDir, f), 'utf8').trim().split('\n'))
    .map((l) => JSON.parse(l)).filter((e) => e.pipe === 'lonely-pipe');
  assert.equal(lines.length, 2, 'both events must be in the spool even with nobody watching');
});

test('an unserializable detail cannot kill the pipeline', async () => {
  const emit = emitter({ pipe: 'cyclic' });
  const cyclic = {}; cyclic.self = cyclic;
  assert.doesNotThrow(() => emit('STEP_OK', { data: cyclic }));
  emit.close();
});

// --------------------------------------------------------------------------
// The spool is the ledger `rabadon audit` verifies, and audit exit 0 is the
// artifact rabadon asks to be judged on. The bus is a writer of that ledger, so
// it owes the same proof the C++ writers owe: prev on every line, and a .head
// sidecar committing the last hash and the line count under the same lock.
//
// Before this, emit() did a bare appendFileSync into the CHAINED day file. One
// run of the documented public API took a fresh install from INTACT/exit 0 to
// PARTIAL/exit 2, on a file that can never be cleaned again.

/** Verify a chained file the way native/audit.cpp does, independently of the
 * code under test: prev of each line = sha256 of the whole previous line, and
 * the sidecar commits the last hash plus the count. Returns null when clean. */
function verifyChain(file) {
  const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
  let last = 'genesis', chained = 0;
  for (let i = 0; i < lines.length; i++) {
    const prev = JSON.parse(lines[i]).prev;
    if (!prev) return `line ${i + 1} carries no prev`;
    if (prev !== last) return `line ${i + 1} prev=${String(prev).slice(0, 12)} expected=${last.slice(0, 12)}`;
    last = crypto.createHash('sha256').update(lines[i]).digest('hex');
    chained++;
  }
  const [hash, count] = fs.readFileSync(file + '.head', 'utf8').trim().split(' ');
  if (hash !== last) return 'head sidecar does not match the last line';
  if (Number(count) !== chained) return `head commits ${count} line(s), the file has ${chained}`;
  return null;
}

test('the verifier itself can fail: a doctored copy is caught', () => {
  const emit = emitter({ pipe: 'verifier-selftest' });
  emit('RUN_START', {}); emit('STEP_OK', { step: 'a' }); emit('RUN_DONE', { verdict: 'PASS' });
  emit.close();

  const file = jsSpoolPath();
  assert.equal(verifyChain(file), null, 'the real spool must verify clean first');

  // a check that cannot fail proves nothing. edit one byte in a copy and demand
  // a complaint — and demand that a stripped prev is caught too, because
  // "no unchained lines" is the negative half of what this file asserts.
  const copy = path.join(tmp, 'doctored.jsonl');
  const body = fs.readFileSync(file, 'utf8');
  fs.writeFileSync(copy, body.replace('"STEP_OK"', '"STEP_0K"'));
  fs.copyFileSync(file + '.head', copy + '.head');
  assert.ok(verifyChain(copy), 'one edited character must be caught');

  fs.writeFileSync(copy, body.split('\n').filter(Boolean)
    .map((l, i) => (i === 1 ? JSON.stringify({ ...JSON.parse(l), prev: undefined }) : l)).join('\n') + '\n');
  assert.match(verifyChain(copy), /carries no prev/, 'a stripped prev must be caught');
});

test('every event the bus spools is chained, and the sidecar commits it', () => {
  const emit = emitter({ pipe: 'chained-pipe' });
  for (const ev of ['RUN_START', 'STEP_START', 'STEP_OK', 'RUN_DONE']) emit(ev, { step: 's' });
  emit.close();

  const file = jsSpoolPath();
  assert.equal(verifyChain(file), null, `the bus spool must verify: ${verifyChain(file)}`);

  const mine = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean)
    .map((l) => JSON.parse(l)).filter((e) => e.pipe === 'chained-pipe');
  assert.equal(mine.length, 4, 'all four events are on disk — chaining is not allowed to mean dropping');
  assert.ok(mine.every((e) => typeof e.prev === 'string' && e.prev.length > 0), 'every one carries prev');

  // and nothing was smuggled into the file the C++ writers flock
  const native = path.join(tmp, 'spool', new Date().toISOString().slice(0, 10) + '.jsonl');
  assert.equal(fs.existsSync(native), false, 'the bus must not write into the flock-held chained day file');
});

test('concurrent node writers do not break the chain', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-bus-race-'));
  const busUrl = new URL('./bus.mjs', import.meta.url).href;
  const child = `import('${busUrl}').then(m=>{const e=m.emitter({pipe:'race'});for(let i=0;i<6;i++)e('STEP_OK',{step:'s'+i});e.close();})`;

  await Promise.all([0, 1, 2, 3].map(() => new Promise((resolve, reject) => {
    execFile(process.execPath, ['-e', child], { env: { ...process.env, RABADON_DIR: dir } },
      (err) => (err ? reject(err) : resolve()));
  })));

  const day = new Date().toISOString().slice(0, 10);
  const file = path.join(dir, 'spool', `${day}.js.jsonl`);
  assert.equal(verifyChain(file), null, `4 processes x 6 events must leave one valid chain: ${verifyChain(file)}`);
  const n = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).length;
  assert.equal(n, 24, `all 24 events must be chained, not failed open (got ${n})`);
  assert.equal(fs.existsSync(path.join(dir, 'spool', `${day}.js.unchained.jsonl`)), false,
    'nothing should have failed open: the lock is uncontended for microseconds at a time');
});
