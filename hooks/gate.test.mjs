// gate tests — the flagship surface, tested the way it is used: synthetic
// Claude Code hook JSON piped through the REAL binary, verdict read from the
// exit code, evidence read from the spool. No mocks of rabadon itself.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const GATE = path.join(path.dirname(new URL(import.meta.url).pathname), 'gate.mjs');

function world() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-gate-home-'));
  const proj = fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-gate-proj-'));
  fs.mkdirSync(path.join(proj, '.rabadon'), { recursive: true });
  return { home, proj };
}

function fire(home, event) {
  const r = spawnSync('node', [GATE], {
    input: JSON.stringify(event),
    encoding: 'utf8',
    timeout: 20000,
    env: { ...process.env, RABADON_DIR: home, RABADON_NOTIFY: '0', RABADON_JUDGE: '0' },
  });
  return { status: r.status, stderr: r.stderr || '', stdout: r.stdout || '' };
}

const spoolToday = (home) => {
  const f = path.join(home, 'spool', new Date().toISOString().slice(0, 10) + '.jsonl');
  try { return fs.readFileSync(f, 'utf8'); } catch { return ''; }
};

const guard = (proj, g) => fs.writeFileSync(path.join(proj, '.rabadon', 'guard.json'), JSON.stringify(g));

test('deny rule: the violating command is BLOCKED (exit 2), rule id in the feedback, catch in the spool', () => {
  const { home, proj } = world();
  guard(proj, { project: 'p', bash: [{ id: 'no-force-push-main', deny: 'git\\s+push[^|;&]*(--force|-f)\\b', why: 'history is shared' }] });
  const r = fire(home, { hook_event_name: 'PreToolUse', cwd: proj, session_id: 'real-abc', tool_name: 'Bash', tool_input: { command: 'git push --force origin main' } });
  assert.equal(r.status, 2, 'a matched deny rule must refuse the action');
  assert.match(r.stderr, /no-force-push-main/, 'the block names its rule so the user can disable exactly that');
  assert.match(r.stderr, /disabled\[\]/, 'the block names the override path');
  const spool = spoolToday(home);
  assert.ok(spool.includes('"BLOCKED"'), 'the catch is on the ledger');
  assert.ok(!spool.includes('"drill":true'), 'a real session is never tagged as a drill');
});

test('an allowed command passes (exit 0) and is gated on the ledger', () => {
  const { home, proj } = world();
  guard(proj, { project: 'p', bash: [{ id: 'x', deny: 'never-matches-anything-xyz', why: 'w' }] });
  const r = fire(home, { hook_event_name: 'PreToolUse', cwd: proj, session_id: 'real-abc', tool_name: 'Bash', tool_input: { command: 'echo hello' } });
  assert.equal(r.status, 0);
  assert.ok(spoolToday(home).includes('STEP_START'));
});

test('loop-stop: the same command with no code edit in between is refused on the 3rd run', () => {
  const { home, proj } = world();
  guard(proj, { project: 'p', bash: [] });
  const ev = { hook_event_name: 'PreToolUse', cwd: proj, session_id: 'real-loop', tool_name: 'Bash', tool_input: { command: 'npm run build' } };
  assert.equal(fire(home, ev).status, 0, '1st run flows');
  assert.equal(fire(home, ev).status, 0, '2nd run flows');
  const r3 = fire(home, ev);
  assert.equal(r3.status, 2, '3rd identical run is a loop, not progress');
  assert.match(r3.stderr, /loop-stop/);
});

test('test-tamper: while the suite is red, an edit that strips assertions from a test file is refused', () => {
  const { home, proj } = world();
  guard(proj, { project: 'p', testPaths: ['\\.test\\.mjs$'] });
  fs.writeFileSync(path.join(proj, '.rabadon', 'state.json'), JSON.stringify({ lastTestFail: Date.now(), lastTestPass: 0, sessions: {} }));
  const r = fire(home, {
    hook_event_name: 'PreToolUse', cwd: proj, session_id: 'real-tamper', tool_name: 'Edit',
    tool_input: {
      file_path: path.join(proj, 'core.test.mjs'),
      old_string: 'assert.equal(a, 1);\nassert.equal(b, 2);',
      new_string: 'assert.equal(a, 1);',
    },
  });
  assert.equal(r.status, 2, 'doctoring the thermometer must be refused');
  assert.match(r.stderr, /test-tamper/);
});

test('push gate (no runnable suite declared): push after an untested code edit is refused', () => {
  const { home, proj } = world();
  guard(proj, { project: 'p', bash: [], pushGate: { why: 'green before push' } });
  fs.writeFileSync(path.join(proj, '.rabadon', 'state.json'), JSON.stringify({ lastCodeEdit: Date.now(), lastTestPass: 0, sessions: {} }));
  const r = fire(home, { hook_event_name: 'PreToolUse', cwd: proj, session_id: 'real-push', tool_name: 'Bash', tool_input: { command: 'git push origin main' } });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /push-gate/);
});

test('drill tagging: fleet/doctor session ids mark every event drill:true so the ledger can exclude them', () => {
  const { home, proj } = world();
  guard(proj, { project: 'p', bash: [{ id: 'no-force-push-main', deny: 'git\\s+push[^|;&]*(--force|-f)\\b', why: 'w' }] });
  const r = fire(home, { hook_event_name: 'PreToolUse', cwd: proj, session_id: `doctor-${process.pid}`, tool_name: 'Bash', tool_input: { command: 'git push --force origin main' } });
  assert.equal(r.status, 2, 'the drill must still BLOCK (it verifies the gate bites)');
  const lines = spoolToday(home).trim().split('\n').map((l) => JSON.parse(l));
  assert.ok(lines.length > 0);
  for (const e of lines) assert.equal(e.drill, true, `every drill event carries the tag (got: ${JSON.stringify(e).slice(0, 80)})`);
});

test('twin delivery (global + project hooks): the duplicate tool_use_id is a no-op, one ledger entry only', () => {
  const { home, proj } = world();
  guard(proj, { project: 'p', bash: [{ id: 'no-force-push-main', deny: 'git\\s+push[^|;&]*(--force|-f)\\b', why: 'w' }] });
  const evt = { hook_event_name: 'PreToolUse', cwd: proj, session_id: 'real-twin', tool_use_id: 'toolu_same_call', tool_name: 'Bash', tool_input: { command: 'git push --force origin main' } };
  assert.equal(fire(home, evt).status, 2, 'the first delivery blocks');
  assert.equal(fire(home, evt).status, 0, 'the twin is swallowed, not double-judged');
  const blocked = spoolToday(home).split('\n').filter((l) => l.includes('"BLOCKED"'));
  assert.equal(blocked.length, 1, 'one catch on the ledger, not two');
  // a REAL retry of the same command gets a fresh tool_use_id — still judged
  const retry = fire(home, { ...evt, tool_use_id: 'toolu_new_call' });
  assert.equal(retry.status, 2, 'a genuine re-attempt is refused again, not deduped away');
});

test('red detector: "fail 0" in a green run is GREEN (measured count, not keyword sighting), fail 2 is red', () => {
  const { home, proj } = world();
  guard(proj, { project: 'p', bash: [] });
  // green run, JSON-escaped newlines exactly as Claude Code delivers them
  const green = fire(home, {
    hook_event_name: 'PostToolUse', cwd: proj, session_id: 'real-green', tool_use_id: 'toolu_g1',
    tool_name: 'Bash', tool_input: { command: 'npm test' },
    tool_response: { stdout: 'ℹ tests 52\nℹ pass 52\nℹ fail 0' },
  });
  assert.equal(green.status, 0, 'a fully green suite must never be called RED');
  const red = fire(home, {
    hook_event_name: 'PostToolUse', cwd: proj, session_id: 'real-red', tool_use_id: 'toolu_r1',
    tool_name: 'Bash', tool_input: { command: 'npm test' },
    tool_response: { stdout: 'ℹ tests 52\nℹ pass 50\nℹ fail 2' },
  });
  assert.equal(red.status, 2, 'a measured failure is fed back');
  assert.match(red.stderr, /RED/);
});

test('no guard file: the gate observes but never blocks', () => {
  const { home, proj } = world();
  const r = fire(home, { hook_event_name: 'PreToolUse', cwd: proj, session_id: 'real-noguard', tool_name: 'Bash', tool_input: { command: 'git push --force origin main' } });
  assert.equal(r.status, 0, 'no declared law = nothing to enforce (observe only)');
});

test('RABADON_OFF: the escape hatch silences everything instantly', () => {
  const { home, proj } = world();
  guard(proj, { project: 'p', bash: [{ id: 'r', deny: '.*', why: 'blocks everything' }] });
  const r = spawnSync('node', [GATE], {
    input: JSON.stringify({ hook_event_name: 'PreToolUse', cwd: proj, session_id: 's', tool_name: 'Bash', tool_input: { command: 'anything' } }),
    encoding: 'utf8', timeout: 20000,
    env: { ...process.env, RABADON_DIR: home, RABADON_OFF: '1', RABADON_NOTIFY: '0', RABADON_JUDGE: '0' },
  });
  assert.equal(r.status, 0, 'off is off — trust requires an instant, obvious exit');
});
