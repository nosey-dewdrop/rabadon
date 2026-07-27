// install tests — the first command a stranger runs must work on a REAL
// machine, which means: an existing settings.json with their own hooks in it.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { installHooks } from './install.mjs';

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-install-'));

test('fresh project: settings created with every gate hook + statusline', () => {
  const dir = tmp();
  const r = installHooks(dir);
  assert.equal(r.changed, true);
  assert.equal(r.backedUp, false);
  const s = JSON.parse(fs.readFileSync(r.settingsPath, 'utf8'));
  for (const evName of ['SessionStart', 'UserPromptSubmit', 'Stop', 'PreToolUse', 'PostToolUse']) {
    assert.ok(JSON.stringify(s.hooks[evName]).includes('gate.mjs'), `${evName} must carry the gate`);
  }
  assert.ok(s.statusLine.command.includes('statusline'));
  assert.ok(fs.readFileSync(path.join(dir, '.gitignore'), 'utf8').includes('.rabadon/state.json'));
});

test('existing settings: user hooks and permissions PRESERVED, gate appended, backup made', () => {
  const dir = tmp();
  fs.mkdirSync(path.join(dir, '.claude'), { recursive: true });
  const theirs = {
    permissions: { allow: ['Bash(npm test)'] },
    statusLine: { type: 'command', command: 'my-own-statusline' },
    hooks: { PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'my-own-hook.sh' }] }] },
  };
  fs.writeFileSync(path.join(dir, '.claude', 'settings.json'), JSON.stringify(theirs));

  const r = installHooks(dir);
  assert.equal(r.changed, true);
  assert.equal(r.backedUp, true);
  assert.ok(fs.existsSync(r.settingsPath + '.bak-rabadon'), 'the original must be recoverable');

  const s = JSON.parse(fs.readFileSync(r.settingsPath, 'utf8'));
  assert.deepEqual(s.permissions, theirs.permissions, 'permissions untouched');
  assert.equal(s.statusLine.command, 'my-own-statusline', 'an existing statusline is never replaced');
  const pre = JSON.stringify(s.hooks.PreToolUse);
  assert.ok(pre.includes('my-own-hook.sh'), 'their hook survives');
  assert.ok(pre.includes('gate.mjs'), 'the gate is added alongside');
});

test('idempotent: a second install changes nothing and adds no duplicates', () => {
  const dir = tmp();
  installHooks(dir);
  const before = fs.readFileSync(path.join(dir, '.claude', 'settings.json'), 'utf8');
  const r2 = installHooks(dir);
  assert.equal(r2.changed, false);
  assert.equal(fs.readFileSync(path.join(dir, '.claude', 'settings.json'), 'utf8'), before);
});

test('unreadable settings throw — rabadon never overwrites what it cannot parse', () => {
  const dir = tmp();
  fs.mkdirSync(path.join(dir, '.claude'), { recursive: true });
  fs.writeFileSync(path.join(dir, '.claude', 'settings.json'), '{ not json');
  assert.throws(() => installHooks(dir));
  assert.equal(fs.readFileSync(path.join(dir, '.claude', 'settings.json'), 'utf8'), '{ not json', 'the broken file is left for the human, untouched');
});
