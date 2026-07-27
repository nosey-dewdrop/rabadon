// do engine tests — the deterministic spine of the motor.
//
// The LLM plans and repairs; everything that DECIDES is mechanical and lives
// here: the contract checker (pass/fail is a measurement, never an opinion)
// and the plan parser. If these are right, a wrong plan can never produce a
// silently wrong "done" — it can only fail loudly at a gate.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { checkContract, parseJson } from './do.mjs';

function tmpProject() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-do-'));
  fs.writeFileSync(path.join(dir, 'hello.txt'), 'hello rabadon\nline two\n');
  return dir;
}

test('contract cmd: exit 0 passes, non-zero fails with the tail of the output', () => {
  const dir = tmpProject();
  assert.deepEqual(checkContract([{ type: 'cmd', run: 'true' }], dir), []);
  const fails = checkContract([{ type: 'cmd', run: 'ls no-such-file-anywhere' }], dir);
  assert.equal(fails.length, 1);
  assert.match(fails[0].why, /exit!=0/);
});

test('contract cmd + passPattern: exit 0 is NOT enough — the pattern must appear', () => {
  const dir = tmpProject();
  assert.deepEqual(checkContract([{ type: 'cmd', run: 'cat hello.txt', passPattern: 'hello rabadon' }], dir), []);
  const fails = checkContract([{ type: 'cmd', run: 'cat hello.txt', passPattern: 'ALL TESTS GREEN' }], dir);
  assert.equal(fails.length, 1);
  assert.match(fails[0].why, /pass pattern/);
});

test('contract fileExists / fileContains', () => {
  const dir = tmpProject();
  assert.deepEqual(checkContract([
    { type: 'fileExists', path: 'hello.txt' },
    { type: 'fileContains', path: 'hello.txt', pattern: 'line two' },
  ], dir), []);
  const fails = checkContract([
    { type: 'fileExists', path: 'missing.txt' },
    { type: 'fileContains', path: 'hello.txt', pattern: 'not-in-there' },
  ], dir);
  assert.equal(fails.length, 2);
});

test('contract: an unknown type fails CLOSED, never passes silently', () => {
  const fails = checkContract([{ type: 'llm-judge', prompt: 'is it good?' }], tmpProject());
  assert.equal(fails.length, 1);
  assert.match(fails[0].why, /unknown contract type/);
});

test('contract: a missing file in fileContains fails with the reason, not a crash', () => {
  const fails = checkContract([{ type: 'fileContains', path: 'nope.txt', pattern: 'x' }], tmpProject());
  assert.equal(fails.length, 1);
});

test('parseJson: plain, fenced, and garbage', () => {
  assert.deepEqual(parseJson('{"a":1}'), { a: 1 });
  assert.deepEqual(parseJson('```json\n{"a":1}\n```'), { a: 1 });
  assert.equal(parseJson('the model wrote prose instead'), null);
});
