// rabadon store — the trace layer over the spool.
//
// The spool (~/.rabadon/spool/*.jsonl) is the source of truth: every event any
// pipeline, session gate or motor run ever emitted, one JSON line each. The
// store turns that flat stream into what an observability product actually
// shows: RUNS (trace = one run's steps, gates, repairs, verdict) and LEDGERS
// (per-project counts that are backed by timestamped events, not claims).
//
// This is the same shape Langfuse/Braintrust call a "trace": a root (the run)
// with ordered spans (the steps) and their outcomes. The difference is the
// vocabulary — theirs records what an LLM said; ours records what the gate
// DID: caught, blocked, repaired, stopped.
//
// Deterministic, zero dependencies, read-only over the spool. Nothing here
// ever writes; the store cannot lie about data it cannot touch.

import fs from 'node:fs';
import path from 'node:path';
import { SPOOL_DIR } from './bus.mjs';

/** Read every event of the last `days` days, oldest first. Bad lines are
 * counted, not silently dropped — the store reports its own losses. */
export function readEvents({ days = 7, spoolDir = SPOOL_DIR, now = Date.now() } = {}) {
  const cutoff = now - days * 86400000;
  const events = [];
  let unparseable = 0;
  let files = [];
  try { files = fs.readdirSync(spoolDir).filter((f) => f.endsWith('.jsonl')).sort(); } catch { }
  for (const f of files) {
    // file name = YYYY-MM-DD; skip whole files older than the window
    const day = Date.parse(f.slice(0, 10));
    if (Number.isFinite(day) && day + 86400000 < cutoff) continue;
    let body = '';
    try { body = fs.readFileSync(path.join(spoolDir, f), 'utf8'); } catch { continue; }
    for (const line of body.split('\n')) {
      if (!line.trim()) continue;
      try {
        const e = JSON.parse(line);
        if (e.ts >= cutoff) events.push(e);
      } catch { unparseable++; }
    }
  }
  events.sort((a, b) => (a.ts - b.ts) || ((a.seq || 0) - (b.seq || 0)));
  return { events, unparseable };
}

/** Project name from a pipe id: "stitchu:session" -> "stitchu", "x:do" -> "x". */
export function projectOf(pipe) {
  return String(pipe || '?').replace(/:(session|do)$/, '');
}

/** Kind of a pipe: how this run came to exist. */
export function kindOf(pipe) {
  const p = String(pipe || '');
  if (p.endsWith(':session')) return 'session'; // a supervised Claude Code session
  if (p.endsWith(':do')) return 'do';           // the motor: rabadon do "<task>"
  return 'pipeline';                            // a wrapped/declared pipeline
}

/**
 * Group a flat event stream into runs (traces).
 * A run = every event sharing one `run` id. Steps are reconstructed in order;
 * checks, repairs and stops attach to the step they happened at.
 */
export function indexRuns(events, { now = Date.now() } = {}) {
  const byRun = new Map();
  for (const e of events) {
    const id = e.run || `?-${e.pipe}`;
    if (!byRun.has(id)) {
      byRun.set(id, {
        id, pipe: e.pipe, project: projectOf(e.pipe), kind: kindOf(e.pipe),
        start: e.ts, end: e.ts, verdict: null, stopDetail: null,
        steps: [], stepIndex: new Map(),
        counts: { events: 0, checkFails: 0, repairsOk: 0, repairsFailed: 0, blocked: 0 },
        bound: null, plannedSteps: null, goal: null,
      });
    }
    const r = byRun.get(id);
    r.counts.events++;
    if (e.ts < r.start) r.start = e.ts;
    if (e.ts > r.end) r.end = e.ts;

    const step = (name) => {
      const key = String(name || '?');
      if (!r.stepIndex.has(key)) {
        const s = { name: key, status: 'ran', fails: [], repairs: [], ts: e.ts };
        r.stepIndex.set(key, s);
        r.steps.push(s);
      }
      return r.stepIndex.get(key);
    };

    switch (e.ev) {
      case 'RUN_START':
        r.bound = e.bound || null;
        r.plannedSteps = e.steps || null;
        r.goal = e.goal || null;
        break;
      case 'STEP_START': step(e.step).status = 'running'; break;
      case 'STEP_OK': { const s = step(e.step); s.status = s.repairs.some((x) => x.ok) ? 'repaired' : 'ok'; break; }
      case 'CHECK_FAIL': {
        const s = step(e.step);
        s.status = 'broke';
        for (const f of e.fails || []) s.fails.push({ check: f.check, why: f.why, ts: e.ts });
        r.counts.checkFails += (e.fails || []).length || 1;
        break;
      }
      case 'REPAIR_START': step(e.step).status = 'repairing'; break;
      case 'REPAIR_OK': {
        const s = step(e.step);
        s.repairs.push({ attempt: e.attempt, ok: true, ts: e.ts });
        s.status = 'repaired';
        r.counts.repairsOk++;
        break;
      }
      case 'REPAIR_FAIL': {
        const s = step(e.step);
        s.repairs.push({ attempt: e.attempt, ok: false, why: e.why || (e.remaining || []).join('; '), ts: e.ts });
        s.status = 'broke';
        r.counts.repairsFailed++;
        break;
      }
      case 'STOP':
        if (e.reason === 'BLOCKED') {
          r.counts.blocked++;
          // a blocked action is a step-level catch inside a session run
          const s = step(e.step || 'gate');
          s.status = 'blocked';
          s.fails.push({ check: 'gate', why: String(e.detail || 'blocked'), ts: e.ts });
        } else {
          r.verdict = e.reason;
          r.stopDetail = e.detail || null;
        }
        break;
      case 'RUN_DONE':
        r.verdict = e.verdict || r.verdict;
        break;
    }
  }

  const runs = [...byRun.values()];
  for (const r of runs) {
    r.stepIndex = undefined; // internal
    r.durMs = r.end - r.start;
    if (!r.verdict) {
      // a session with recent activity is live; an abandoned one is open-ended
      r.verdict = now - r.end < 30 * 60000 ? 'LIVE' : 'OPEN';
    }
  }
  runs.sort((a, b) => b.end - a.end);
  return runs;
}

/** The ledger: per-project counts, every number backed by spool events. */
export function aggregate(events) {
  const perProject = new Map();
  const totals = { gated: 0, blocked: 0, checkFails: 0, repairsOk: 0, runs: 0, projects: 0 };
  const runSets = new Map();
  for (const e of events) {
    const proj = projectOf(e.pipe);
    if (!perProject.has(proj)) {
      perProject.set(proj, { project: proj, gated: 0, blocked: 0, blockedRules: new Map(), checkFails: 0, loopsStopped: 0, repairsOk: 0, runs: 0, lastTs: 0 });
      runSets.set(proj, new Set());
    }
    const s = perProject.get(proj);
    if (e.ts > s.lastTs) s.lastTs = e.ts;
    if (e.run) runSets.get(proj).add(e.run);
    if (e.ev === 'STEP_START') { s.gated++; totals.gated++; }
    if (e.ev === 'CHECK_FAIL') {
      const n = (e.fails || []).length || 1;
      s.checkFails += n; totals.checkFails += n;
      for (const f of e.fails || []) if (f.check === 'loop-stop') s.loopsStopped++;
    }
    if (e.ev === 'STOP' && e.reason === 'BLOCKED') {
      s.blocked++; totals.blocked++;
      const rule = String(e.detail || '?').split(' — ')[0].slice(0, 80);
      s.blockedRules.set(rule, (s.blockedRules.get(rule) || 0) + 1);
    }
    if (e.ev === 'REPAIR_OK') { s.repairsOk++; totals.repairsOk++; }
  }
  const projects = [...perProject.values()].map((s) => ({
    ...s,
    runs: runSets.get(s.project).size,
    blockedRules: [...s.blockedRules.entries()].map(([rule, n]) => ({ rule, n })).sort((a, b) => b.n - a.n),
  })).sort((a, b) => b.lastTs - a.lastTs);
  totals.runs = projects.reduce((a, p) => a + p.runs, 0);
  totals.projects = projects.length;
  return { totals, projects };
}

/** Scan the machine for guarded projects: everything with .rabadon/guard.json
 * under the given roots (one level deep + a 00_currently_on_working nest). */
export function scanFleet(roots, { events = [] } = {}) {
  const lastByProject = new Map();
  for (const e of events) {
    const p = projectOf(e.pipe);
    if (!lastByProject.has(p) || e.ts > lastByProject.get(p)) lastByProject.set(p, e.ts);
  }
  const out = [];
  const seen = new Set();
  const scanDir = (dir) => {
    const guardFile = path.join(dir, '.rabadon', 'guard.json');
    if (!fs.existsSync(guardFile) || seen.has(dir)) return;
    seen.add(dir);
    const name = path.basename(dir);
    let guard = null;
    try { guard = JSON.parse(fs.readFileSync(guardFile, 'utf8')); } catch { }
    let hooks = false;
    try { hooks = JSON.stringify(JSON.parse(fs.readFileSync(path.join(dir, '.claude', 'settings.json'), 'utf8')).hooks || {}).includes('gate.mjs'); } catch { }
    out.push({
      project: name, dir,
      rules: guard ? (guard.bash || []).length + (guard.protectedPaths || []).length : 0,
      pushGate: !!(guard && guard.pushGate && guard.pushGate.run),
      disabled: guard ? (guard.disabled || []).length : 0,
      hooks,
      off: fs.existsSync(path.join(dir, '.rabadon', 'off')),
      lastActivity: lastByProject.get(name) || null,
      guardValid: !!guard,
    });
  };
  for (const root of roots) {
    let entries = [];
    try { entries = fs.readdirSync(root); } catch { continue; }
    for (const d of entries) {
      const p = path.join(root, d);
      try { if (fs.statSync(p).isDirectory()) scanDir(p); } catch { }
    }
    const nest = path.join(root, '00_currently_on_working');
    try {
      for (const d of fs.readdirSync(nest)) {
        const p = path.join(nest, d);
        try { if (fs.statSync(p).isDirectory()) scanDir(p); } catch { }
      }
    } catch { }
  }
  out.sort((a, b) => (b.lastActivity || 0) - (a.lastActivity || 0) || a.project.localeCompare(b.project));
  return out;
}

export default { readEvents, indexRuns, aggregate, scanFleet, projectOf, kindOf };
