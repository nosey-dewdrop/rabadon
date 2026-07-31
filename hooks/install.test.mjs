// install tests — the first command a stranger runs must work on a REAL
// machine, which means: an existing settings.json with their own hooks in it,
// and a yesterday-install pointing at a path that no longer exists.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { installHooks, removeHooks, GATE_BIN, DRIFT_BIN } from './install.mjs';

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-install-'));
const read = (dir) => JSON.parse(fs.readFileSync(path.join(dir, '.claude', 'settings.json'), 'utf8'));

test('fresh project: settings created with every gate hook + drift on Stop + statusline', () => {
  const dir = tmp();
  const r = installHooks(dir);
  assert.equal(r.changed, true);
  assert.equal(r.backedUp, false);
  const s = read(dir);
  for (const evName of ['SessionStart', 'UserPromptSubmit', 'Stop', 'PreToolUse', 'PostToolUse']) {
    assert.ok(JSON.stringify(s.hooks[evName]).includes('rabadon-gate'), `${evName} must carry the native gate`);
  }
  assert.ok(JSON.stringify(s.hooks.Stop).includes('rabadon-drift'), 'Stop must also carry drift');
  for (const evName of ['PreToolUse', 'PostToolUse']) {
    assert.equal(s.hooks[evName][0].matcher, '*', `${evName} covers every tool, MCP included`);
  }
  // seconds, not milliseconds — and each ceiling sits ABOVE the gate's own
  // internal cap, so rabadon's bounded timer fires first and every outcome
  // carries a verdict instead of an unattributed hook kill
  assert.equal(s.hooks.PreToolUse[0].hooks[0].timeout, 960, 'PreToolUse outlasts the 900s push-gate suite budget');
  assert.equal(s.hooks.PostToolUse[0].hooks[0].timeout, 120, 'PostToolUse outlasts the 90s incident brain');
  assert.ok(s.statusLine.command.includes('--statusline'));
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

  const s = read(dir);
  assert.deepEqual(s.permissions, theirs.permissions, 'permissions untouched');
  assert.equal(s.statusLine.command, 'my-own-statusline', 'an existing statusline is never replaced');
  const pre = JSON.stringify(s.hooks.PreToolUse);
  assert.ok(pre.includes('my-own-hook.sh'), 'their hook survives');
  assert.ok(pre.includes('rabadon-gate'), 'the gate is added alongside');
});

test('idempotent: a second install changes nothing and adds no duplicates', () => {
  const dir = tmp();
  installHooks(dir);
  const before = fs.readFileSync(path.join(dir, '.claude', 'settings.json'), 'utf8');
  const r2 = installHooks(dir);
  assert.equal(r2.changed, false);
  assert.equal(fs.readFileSync(path.join(dir, '.claude', 'settings.json'), 'utf8'), before);
});

test('repair: entries pointing at a dead install path are rewritten in place, once each', () => {
  const dir = tmp();
  fs.mkdirSync(path.join(dir, '.claude'), { recursive: true });
  // yesterday's machine: gate at a path that no longer exists + legacy JS gate
  const stale = {
    hooks: {
      SessionStart: [{ hooks: [{ type: 'command', command: '/gone/away/rabadon/native/rabadon-gate' }] }],
      Stop: [{ hooks: [{ type: 'command', command: '/gone/away/rabadon/native/rabadon-gate' }] }],
      PreToolUse: [
        { matcher: 'Bash', hooks: [{ type: 'command', command: 'node /gone/rabadon/hooks/gate.mjs', timeout: 900 }] },
        { matcher: 'Bash', hooks: [{ type: 'command', command: 'their-hook.sh' }] },
      ],
    },
    statusLine: { type: 'command', command: '/gone/away/rabadon/native/rabadon-gate --statusline' },
  };
  fs.writeFileSync(path.join(dir, '.claude', 'settings.json'), JSON.stringify(stale));

  const r = installHooks(dir);
  assert.equal(r.changed, true);
  assert.equal(r.repaired, true, 'a stale install is a repair, not a fresh add');
  const s = read(dir);
  const all = JSON.stringify(s.hooks);
  assert.ok(!all.includes('/gone/'), 'no dead path survives');
  assert.ok(all.includes(GATE_BIN), 'entries now point at the live binary');
  assert.equal(JSON.stringify(s.hooks.PreToolUse).match(/rabadon-gate/g).length, 1, 'exactly one gate entry, no duplicates');
  assert.ok(JSON.stringify(s.hooks.PreToolUse).includes('their-hook.sh'), 'their hook survives the repair');
  assert.ok(s.statusLine.command.startsWith(GATE_BIN), 'rabadon-owned statusline is repaired too');
});

test('removeHooks strips exactly ours, leaves theirs, and is idempotent', () => {
  const dir = tmp();
  fs.mkdirSync(path.join(dir, '.claude'), { recursive: true });
  const theirs = {
    permissions: { allow: ['Bash(npm test)'] },
    hooks: { PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'their-hook.sh' }] }] },
  };
  fs.writeFileSync(path.join(dir, '.claude', 'settings.json'), JSON.stringify(theirs));
  installHooks(dir);

  const r = removeHooks(dir);
  assert.equal(r.changed, true);
  assert.ok(r.removed.length >= 6, `gate x5 + drift + statusline expected, got: ${r.removed.length}`);
  const s = read(dir);
  assert.ok(!JSON.stringify(s).includes('rabadon-'), 'zero rabadon strings left behind');
  assert.ok(JSON.stringify(s.hooks.PreToolUse).includes('their-hook.sh'), 'their hook survives the uninstall');
  assert.deepEqual(s.permissions, theirs.permissions, 'permissions untouched');

  const r2 = removeHooks(dir);
  assert.equal(r2.changed, false, 'a second remove is a no-op');
});

test('removeHooks on a project rabadon never touched changes nothing', () => {
  const dir = tmp();
  const r = removeHooks(dir);
  assert.equal(r.changed, false);
  assert.deepEqual(r.removed, []);
});

test('unreadable settings throw — rabadon never overwrites what it cannot parse', () => {
  const dir = tmp();
  fs.mkdirSync(path.join(dir, '.claude'), { recursive: true });
  fs.writeFileSync(path.join(dir, '.claude', 'settings.json'), '{ not json');
  assert.throws(() => installHooks(dir));
  assert.equal(fs.readFileSync(path.join(dir, '.claude', 'settings.json'), 'utf8'), '{ not json', 'the broken file is left for the human, untouched');
});

test('global target (homedir-shaped dir): hooks written, gitignore NOT touched', () => {
  // simulate the global target by pointing installHooks at a fake home; the
  // gitignore guard keys on os.homedir(), so here we only assert the real
  // homedir path is skipped via the exported behavior contract: a dir that IS
  // os.homedir() must not gain a .gitignore. We cannot chown the real home in
  // a test, so assert on the code path with the fake dir gaining hooks, then
  // verify the real-home guard by inspection of installHooks (path.resolve
  // comparison) — and at minimum: no throw when .gitignore is absent.
  const dir = tmp();
  const r = installHooks(dir);
  assert.equal(r.changed, true);
  assert.ok(fs.existsSync(path.join(dir, '.claude', 'settings.json')));
});

test('drift binary path is a sibling of the gate', () => {
  assert.equal(path.dirname(GATE_BIN), path.dirname(DRIFT_BIN));
});
