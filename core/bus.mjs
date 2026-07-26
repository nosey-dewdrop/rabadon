// rabadon bus — the live event stream.
//
// A pipeline that checks itself but can't be SEEN checking itself is still a
// black box. The bus is how rabadon becomes real-time: every step, check,
// break and repair is pushed OUT of the running process the moment it
// happens, over a unix domain socket, to any attached `rabadon watch`.
//
// Design constraints (in order):
//   1. The bus must NEVER slow down or break the pipeline it observes.
//      Every send is fire-and-forget; a dead/missing watcher costs nothing.
//   2. No silent loss. If events can't be delivered they are still appended
//      to a local spool file, and the number of socket drops is COUNTED and
//      reported — rabadon does not get to lie about its own delivery.
//   3. Zero dependencies. node:net + node:fs only.
//
// Topology: `rabadon watch` OWNS the socket (server). Pipelines are clients:
// they try to connect once, push newline-delimited JSON while they run, and
// silently fall back to spool-only if nobody is watching.

import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

export const RABADON_DIR = process.env.RABADON_DIR || path.join(os.homedir(), '.rabadon');
export const SOCK_PATH = process.env.RABADON_SOCK || path.join(RABADON_DIR, 'rabadon.sock');
export const SPOOL_DIR = path.join(RABADON_DIR, 'spool');

/** Event vocabulary. Fixed and small on purpose — the watch UI renders these. */
export const EV = Object.freeze({
  RUN_START: 'RUN_START',       // a bounded run began
  STEP_START: 'STEP_START',     // a step's work is about to run
  STEP_OK: 'STEP_OK',           // step output passed all checks, flowing onward
  CHECK_FAIL: 'CHECK_FAIL',     // a named check caught a break (before it flowed)
  REPAIR_START: 'REPAIR_START', // rabadon is rewriting the broken output
  REPAIR_OK: 'REPAIR_OK',       // repaired output re-passed the checks
  REPAIR_FAIL: 'REPAIR_FAIL',   // repair attempt did not survive re-check
  STOP: 'STOP',                 // run stopped: RUNAWAY | CHECK_FAILED | DRIFT | THREW
  RUN_DONE: 'RUN_DONE',         // run finished with a verdict
});

function ensureDirs() {
  fs.mkdirSync(SPOOL_DIR, { recursive: true });
}

let seqCounter = 0;

/**
 * Create an emitter bound to one run of one pipeline.
 * Returns emit(ev, fields) — synchronous from the caller's point of view,
 * never throws, never blocks the pipeline.
 */
export function emitter({ pipe = 'pipeline', run = null } = {}) {
  const runId = run || `${Date.now().toString(36)}-${process.pid.toString(36)}-${(++seqCounter).toString(36)}`;
  ensureDirs();

  const spoolPath = path.join(SPOOL_DIR, `${new Date().toISOString().slice(0, 10)}.jsonl`);
  let sock = null;
  let sockUp = false;
  let dropped = 0;          // events not delivered to a live watcher
  const preBuffer = [];     // events emitted while the connect is in flight

  // One connection attempt per run. If the watcher isn't there, we spool only.
  try {
    sock = net.connect(SOCK_PATH);
    sock.on('connect', () => {
      sockUp = true;
      for (const line of preBuffer.splice(0)) sock.write(line);
    });
    sock.on('error', () => { sockUp = false; sock = null; dropped += preBuffer.length; preBuffer.length = 0; });
    sock.on('close', () => { sockUp = false; sock = null; });
    sock.unref(); // the socket must never keep the pipeline process alive
  } catch {
    sock = null;
  }

  let seq = 0;

  function emit(ev, fields = {}) {
    const event = { v: 1, seq: ++seq, ts: Date.now(), run: runId, pipe, ev, ...fields };
    let line;
    try {
      line = JSON.stringify(event) + '\n';
    } catch {
      // an unserializable detail must not kill the pipeline; strip to the frame
      line = JSON.stringify({ v: 1, seq, ts: event.ts, run: runId, pipe, ev, unserializable: true }) + '\n';
    }
    // spool first — the spool is the source of truth, the socket is the live view
    try { fs.appendFileSync(spoolPath, line); } catch { /* disk trouble must not stop the run */ }
    if (sock && sockUp) {
      try {
        const ok = sock.write(line);
        if (!ok) dropped++; // kernel buffer full: the live view lost it, the spool has it
      } catch { dropped++; sockUp = false; }
    } else if (sock && !sockUp) {
      preBuffer.push(line);
      if (preBuffer.length > 1000) { preBuffer.shift(); dropped++; }
    } else {
      dropped++;
    }
    return event;
  }

  emit.runId = runId;
  emit.stats = () => ({ dropped, live: sockUp });
  emit.close = () => { try { sock && sock.end(); } catch { /* already gone */ } };
  return emit;
}

/**
 * Start the watch server (used by `rabadon watch`). Owns the socket.
 * onEvent(event, meta) is called for every parsed event from every pipeline.
 * Returns { close }.
 */
export function listen(onEvent) {
  ensureDirs();
  // a stale socket file from a killed watcher would block bind — remove it,
  // but only if nothing is actually listening on it
  if (fs.existsSync(SOCK_PATH)) {
    const probe = net.connect(SOCK_PATH);
    const stale = new Promise((resolve) => {
      probe.on('error', () => resolve(true));   // nobody home -> stale file
      probe.on('connect', () => { probe.end(); resolve(false); });
    });
    return stale.then((isStale) => {
      if (!isStale) throw new Error(`rabadon watch: another watcher already owns ${SOCK_PATH}`);
      fs.unlinkSync(SOCK_PATH);
      return bind(onEvent);
    });
  }
  return Promise.resolve(bind(onEvent));
}

function bind(onEvent) {
  const server = net.createServer((conn) => {
    let buf = '';
    conn.on('data', (chunk) => {
      buf += chunk;
      let nl;
      while ((nl = buf.indexOf('\n')) !== -1) {
        const line = buf.slice(0, nl);
        buf = buf.slice(nl + 1);
        if (!line.trim()) continue;
        try { onEvent(JSON.parse(line)); } catch { onEvent({ v: 1, ev: 'UNPARSEABLE', raw: line.slice(0, 200) }); }
      }
    });
    conn.on('error', () => { /* a pipeline dying mid-line is normal, not our error */ });
  });
  server.listen(SOCK_PATH);
  return {
    close: () => new Promise((r) => server.close(() => { try { fs.unlinkSync(SOCK_PATH); } catch { } r(); })),
  };
}

export default { emitter, listen, EV, SOCK_PATH, RABADON_DIR };
