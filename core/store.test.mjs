// store tests — the trace layer must reconstruct EXACTLY what the spool says.
// A store that miscounts a catch is worse than no store: it is the silent
// corruption rabadon exists to kill, applied to rabadon's own ledger.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readEvents, indexRuns, aggregate, scanFleet, projectOf, kindOf, markDrills } from './store.mjs';

const T0 = Date.parse('2026-07-27T10:00:00Z');
const day = new Date(T0).toISOString().slice(0, 10);

function writeSpool(lines) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-store-'));
  fs.writeFileSync(path.join(dir, `${day}.jsonl`), lines.map((l) => JSON.stringify(l)).join('\n') + '\n');
  return dir;
}

const ev = (seq, run, pipe, evName, extra = {}) => ({ v: 1, seq, ts: T0 + seq * 1000, run, pipe, ev: evName, ...extra });

test('readEvents: reads, sorts, respects the day window, counts bad lines', () => {
  const dir = writeSpool([
    ev(2, 'r1', 'p:do', 'STEP_START', { step: 's1' }),
    ev(1, 'r1', 'p:do', 'RUN_START', { steps: ['s1'] }),
  ]);
  fs.appendFileSync(path.join(dir, `${day}.jsonl`), 'NOT JSON\n');
  const { events, unparseable } = readEvents({ days: 7, spoolDir: dir, now: T0 + 10000 });
  assert.equal(events.length, 2);
  assert.equal(events[0].ev, 'RUN_START'); // sorted by ts/seq
  assert.equal(unparseable, 1);

  const old = readEvents({ days: 7, spoolDir: dir, now: T0 + 30 * 86400000 });
  assert.equal(old.events.length, 0, 'events outside the window must not leak in');
});

test('projectOf / kindOf: pipe naming law', () => {
  assert.equal(projectOf('stitchu:session'), 'stitchu');
  assert.equal(projectOf('stitchu:do'), 'stitchu');
  assert.equal(kindOf('stitchu:session'), 'session');
  assert.equal(kindOf('stitchu:do'), 'do');
  assert.equal(kindOf('llm-repair-live'), 'pipeline');
});

test('indexRuns: a full break->repair->pass trace reconstructs exactly', () => {
  const events = [
    ev(1, 'r1', 'demo', 'RUN_START', { steps: ['normalize', 'summarize'], bound: { maxSteps: 5 } }),
    ev(2, 'r1', 'demo', 'STEP_START', { step: 'normalize' }),
    ev(3, 'r1', 'demo', 'CHECK_FAIL', { step: 'normalize', fails: [{ check: 'noDrop', why: 'dropped 1' }] }),
    ev(4, 'r1', 'demo', 'REPAIR_START', { step: 'normalize', attempt: 1 }),
    ev(5, 'r1', 'demo', 'REPAIR_OK', { step: 'normalize', attempt: 1 }),
    ev(6, 'r1', 'demo', 'STEP_OK', { step: 'normalize' }),
    ev(7, 'r1', 'demo', 'STEP_START', { step: 'summarize' }),
    ev(8, 'r1', 'demo', 'STEP_OK', { step: 'summarize' }),
    ev(9, 'r1', 'demo', 'RUN_DONE', { verdict: 'PASS' }),
  ];
  const runs = indexRuns(events, { now: T0 + 60000 });
  assert.equal(runs.length, 1);
  const r = runs[0];
  assert.equal(r.verdict, 'PASS');
  assert.equal(r.bound.maxSteps, 5);
  assert.equal(r.steps.length, 2);
  assert.equal(r.steps[0].name, 'normalize');
  assert.equal(r.steps[0].status, 'repaired');
  assert.equal(r.steps[0].fails.length, 1);
  assert.equal(r.steps[0].repairs.length, 1);
  assert.equal(r.steps[1].status, 'ok');
  assert.equal(r.counts.checkFails, 1);
  assert.equal(r.counts.repairsOk, 1);
  assert.equal(r.durMs, 8000);
});

test('indexRuns: a BLOCKED stop is a catch inside a live session, not a verdict', () => {
  const events = [
    ev(1, 's1', 'stitchu:session', 'STEP_START', { step: 'Bash' }),
    ev(2, 's1', 'stitchu:session', 'STOP', { reason: 'BLOCKED', detail: 'no-force-push-main — refused' }),
  ];
  const live = indexRuns(events, { now: T0 + 60000 })[0];
  assert.equal(live.verdict, 'LIVE', 'recent session with no RUN_DONE is live');
  assert.equal(live.counts.blocked, 1);
  assert.equal(live.steps.find((s) => s.status === 'blocked').fails[0].why, 'no-force-push-main — refused');

  const stale = indexRuns(events, { now: T0 + 2 * 3600000 })[0];
  assert.equal(stale.verdict, 'OPEN', 'an abandoned session is open, not live');
});

test('indexRuns: a real STOP reason becomes the verdict', () => {
  const events = [
    ev(1, 'r2', 'demo', 'RUN_START', { steps: ['a'] }),
    ev(2, 'r2', 'demo', 'STEP_START', { step: 'a' }),
    ev(3, 'r2', 'demo', 'CHECK_FAIL', { step: 'a', fails: [{ check: 'c', why: 'broken' }] }),
    ev(4, 'r2', 'demo', 'STOP', { reason: 'CHECK_FAILED', detail: 'a: c' }),
    ev(5, 'r2', 'demo', 'RUN_DONE', { verdict: 'CHECK_FAILED' }),
  ];
  const r = indexRuns(events)[0];
  assert.equal(r.verdict, 'CHECK_FAILED');
  assert.equal(r.stopDetail, 'a: c');
  assert.equal(r.steps[0].status, 'broke');
});

test('aggregate: the ledger counts match the events one for one', () => {
  const events = [
    ev(1, 'r1', 'alpha:session', 'STEP_START', { step: 'Bash' }),
    ev(2, 'r1', 'alpha:session', 'STOP', { reason: 'BLOCKED', detail: 'rule-x — no' }),
    ev(3, 'r1', 'alpha:session', 'CHECK_FAIL', { step: 'Bash', fails: [{ check: 'loop-stop', why: '3rd time' }] }),
    ev(4, 'r2', 'beta', 'STEP_START', { step: 's' }),
    ev(5, 'r2', 'beta', 'REPAIR_OK', { step: 's', attempt: 1 }),
  ];
  const { totals, projects } = aggregate(events);
  assert.equal(totals.gated, 2);
  assert.equal(totals.blocked, 1);
  assert.equal(totals.checkFails, 1);
  assert.equal(totals.repairsOk, 1);
  assert.equal(totals.runs, 2);
  assert.equal(totals.projects, 2);
  const alpha = projects.find((p) => p.project === 'alpha');
  assert.equal(alpha.loopsStopped, 1);
  assert.equal(alpha.blockedRules[0].rule, 'rule-x');
  assert.equal(alpha.blockedRules[0].n, 1);
});

test('aggregate + indexRuns: drill events are excluded from the ledger and drill runs are marked', () => {
  const events = [
    ev(1, 'd1', 'alpha:session', 'STEP_START', { step: 'Bash', drill: true }),
    ev(2, 'd1', 'alpha:session', 'STOP', { reason: 'BLOCKED', detail: 'rule-x — drill', drill: true }),
    ev(3, 'r1', 'alpha:session', 'STEP_START', { step: 'Bash' }),
  ];
  const { totals } = aggregate(events);
  assert.equal(totals.gated, 1, 'the drill STEP_START must not count');
  assert.equal(totals.blocked, 0, 'a self-test block is NOT a catch');
  assert.equal(totals.drills, 2);
  const runs = indexRuns(events);
  assert.equal(runs.find((r) => r.id === 'd1').drill, true);
  assert.ok(!runs.find((r) => r.id === 'r1').drill);
});

test('markDrills: historic fleet drills, demo pipes and scratch projects are labeled — a real catch outside the drill window survives', () => {
  const events = [
    // the fleet drill signature: echo marker + the synthetic force-push right after
    ev(1, 'm1', 'arnica:session', 'STEP_START', { step: 'bash: echo fleet-77659-arnica' }),
    ev(2, 'b1', 'arnica:session', 'CHECK_FAIL', { step: 'Bash', fails: [{ check: 'force-push-main', why: 'command matched deny rule: git push --force origin main' }] }),
    ev(3, 'b1', 'arnica:session', 'STOP', { reason: 'BLOCKED', detail: 'command matched deny rule: git push --force origin main' }),
    // demo + scratch pipes
    ev(4, 'd1', 'vibecoded-demo', 'REPAIR_OK', { step: 'summarize', attempt: 1 }),
    ev(5, 't1', 'tmp.MoDcJQS3mw:session', 'STOP', { reason: 'BLOCKED', detail: 'x' }),
    // a REAL catch on the same project, 3 hours after the drill — must survive
    { v: 1, seq: 9, ts: T0 + 3 * 3600000, run: 'r9', pipe: 'arnica:session', ev: 'STOP', reason: 'BLOCKED', detail: 'protected file: pin.json' },
  ];
  markDrills(events);
  assert.equal(events[0].drill, true, 'the marker itself');
  assert.equal(events[1].drill, true, 'the paired synthetic block');
  assert.equal(events[2].drill, true);
  assert.equal(events[3].drill, true, 'demo pipe');
  assert.equal(events[4].drill, true, 'scratch project');
  assert.ok(!events[5].drill, 'the real catch 3h later is NOT eaten');

  const { totals } = aggregate(events);
  assert.equal(totals.blocked, 1, 'the ledger keeps exactly the one real catch');
  assert.equal(totals.repairsOk, 0, 'a demo repair is not a repair credit');
});

test('scanFleet: finds guarded projects, reads their state, attaches last activity', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rabadon-fleet-'));
  const mk = (name, { guard = true, hooks = false, off = false, nest = false } = {}) => {
    const dir = nest ? path.join(root, '00_currently_on_working', name) : path.join(root, name);
    fs.mkdirSync(path.join(dir, '.rabadon'), { recursive: true });
    if (guard) fs.writeFileSync(path.join(dir, '.rabadon', 'guard.json'), JSON.stringify({ project: name, bash: [{ id: 'a', deny: 'x', why: 'w' }], protectedPaths: [], pushGate: { run: 'npm test' } }));
    if (hooks) { fs.mkdirSync(path.join(dir, '.claude'), { recursive: true }); fs.writeFileSync(path.join(dir, '.claude', 'settings.json'), JSON.stringify({ hooks: { PreToolUse: [{ hooks: [{ type: 'command', command: 'node /x/gate.mjs' }] }] } })); }
    if (off) fs.writeFileSync(path.join(dir, '.rabadon', 'off'), 'x');
    return dir;
  };
  mk('guarded', { hooks: true });
  mk('paused', { off: true });
  mk('nested', { nest: true });
  fs.mkdirSync(path.join(root, 'unguarded'));

  const fleet = scanFleet([root], { events: [ev(1, 'r', 'guarded:session', 'STEP_START', { step: 'Bash' })] });
  assert.equal(fleet.length, 3, 'only guarded projects appear');
  const g = fleet.find((p) => p.project === 'guarded');
  assert.equal(g.rules, 1);
  assert.equal(g.hooks, true);
  assert.equal(g.pushGate, true);
  assert.equal(g.lastActivity, T0 + 1000);
  assert.equal(fleet.find((p) => p.project === 'paused').off, true);
  assert.ok(fleet.find((p) => p.project === 'nested'), 'nested working dir is scanned');
});
