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
//   3. Zero dependencies. node: builtins only (net, fs, crypto).
//   4. Whatever it writes to the spool must be PROVABLE. The spool is the
//      ledger `rabadon audit` verifies, and audit exit 0 is the artifact you
//      put in front of someone. The bus is not allowed to cost that.
//
// Topology: `rabadon watch` OWNS the socket (server). Pipelines are clients:
// they try to connect once, push newline-delimited JSON while they run, and
// silently fall back to spool-only if nobody is watching.

import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';

export const RABADON_DIR = process.env.RABADON_DIR || path.join(os.homedir(), '.rabadon');
export const SOCK_PATH = process.env.RABADON_SOCK || path.join(RABADON_DIR, 'rabadon.sock');
export const SPOOL_DIR = path.join(RABADON_DIR, 'spool');

// ---------------------------------------------------------------------------
// The ledger protocol, JS side. native/chain.h is the specification; this is the
// second implementation of it, and it must agree byte for byte or `rabadon
// audit` will call an honest file tampered.
//
// Why a second implementation instead of calling the first one: chain.h holds
// flock(2) on the day file for the whole read-head -> append -> rewrite-head
// sequence, and Node has no flock — not in `fs`, and macOS ships no flock(1) to
// shell out to. A JS writer in the SAME file could therefore interleave with
// gate/repair/loop, and an interleave does not merely lose an event: the next
// chained line's prev stops matching, which audit reports as a BREAK. A false
// accusation of tampering is worse than the bug this replaced.
//
// So the JS bus owns its own day file, `<day>.js.jsonl`, chained by the same
// rules and committed by the same `<day>.js.jsonl.head` sidecar. One writer per
// chained file — which is what chain.h's rule actually protects. audit walks
// every *.jsonl in the spool, so the file is verified, not merely tolerated,
// and core/store.mjs reads every *.jsonl too, so replay still sees the events.
//
// Mutual exclusion between concurrent NODE writers is a lock file taken with
// O_EXCL, the one atomic primitive both ends of that race share. If it cannot
// be taken, we do exactly what chain.h does when flock fails: record the line in
// `<day>.unchained.jsonl`, outside the chain and outside the chained file, so
// the day's proof is never damaged by our own fail-open.

const LOCK_STALE_MS = 5000;   // a lock older than this belonged to a killed writer
const LOCK_WAIT_MS = 250;     // total time to fight for the lock before failing open

const sha256hex = (s) => crypto.createHash('sha256').update(s).digest('hex');

/** Sleep synchronously. emit() is synchronous by contract; it cannot await. */
function sleepSync(ms) {
  try { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); } catch { /* no SAB: spin-free fallback */ }
}

/** Mirror of chain.h read_head(): "<sha256> <count>", count -1 = pre-0.4. */
function readHead(headPath) {
  let prev = 'genesis', count = -1;
  let h;
  try { h = fs.readFileSync(headPath, 'utf8').split('\n')[0]; } catch { return { prev, count }; }
  const sp = h.indexOf(' ');
  const hash = sp === -1 ? h : h.slice(0, sp);
  if (hash.length !== 64) return { prev, count };
  prev = hash;
  if (sp === -1) return { prev, count };
  const c = h.slice(sp + 1).trim();
  if (c && /^[0-9]+$/.test(c)) count = Number(c);
  return { prev, count };
}

/** Mirror of chain.h count_chained_lines(): a line is chained when it carries a
 * non-empty top-level `prev`. Read as JSON, not as a byte suffix — SPEC §2 fixes
 * neither spacing nor key order. */
function countChainedLines(spoolPath) {
  let body;
  try { body = fs.readFileSync(spoolPath, 'utf8'); } catch { return 0; }
  let n = 0;
  for (const line of body.split('\n')) {
    if (!line) continue;
    try { const p = JSON.parse(line).prev; if (typeof p === 'string' && p !== '') n++; } catch { /* not ours to judge */ }
  }
  return n;
}

function acquireLock(lockPath) {
  const deadline = Date.now() + LOCK_WAIT_MS;
  for (;;) {
    try { fs.closeSync(fs.openSync(lockPath, 'wx')); return true; } catch { /* held, or unwritable */ }
    try {
      const st = fs.statSync(lockPath);
      if (Date.now() - st.mtimeMs > LOCK_STALE_MS) { fs.unlinkSync(lockPath); continue; }
    } catch { /* it vanished under us, or the dir is unwritable — the deadline decides */ }
    if (Date.now() >= deadline) return false;
    sleepSync(2);
  }
}

const unchainedSibling = (spoolPath) => spoolPath.replace(/\.jsonl$/, '.unchained.jsonl');

/**
 * Append one event to the chained day file and return the exact line written
 * (newline included) so the caller can fan the same bytes to the socket.
 * Never throws: a ledger that kills the pipeline it observes is not a ledger.
 */
export function chainedAppend(spoolPath, event) {
  const lockPath = spoolPath + '.lock';
  if (!acquireLock(lockPath)) {
    const line = safeStringify({ ...event, unlocked: true }, event) + '\n';
    try { fs.appendFileSync(unchainedSibling(spoolPath), line); } catch { /* disk trouble must not stop the run */ }
    return line;
  }
  try {
    const headPath = spoolPath + '.head';
    let { prev, count } = readHead(headPath);
    if (count < 0) count = prev === 'genesis' ? 0 : countChainedLines(spoolPath);
    // prev goes on LAST, the same place chain.h puts it. Nothing reads it
    // positionally, but a ledger two implementations write should look like one.
    const chained = safeStringify({ ...event, prev }, event, prev);
    fs.appendFileSync(spoolPath, chained + '\n');
    // the sidecar is written under the same lock as the line it commits to, so
    // anything the two disagree about happened AFTER emit.
    fs.writeFileSync(headPath, `${sha256hex(chained)} ${count + 1}\n`);
    return chained + '\n';
  } catch {
    return '';   // disk trouble must not stop the run
  } finally {
    try { fs.unlinkSync(lockPath); } catch { /* already gone */ }
  }
}

/** JSON.stringify that cannot throw: an unserializable detail costs the detail,
 * not the event, and never the run. */
function safeStringify(full, frame, prev) {
  try { return JSON.stringify(full); } catch { /* cyclic or a throwing toJSON */ }
  const { v, seq, ts, run, pipe, ev } = frame;
  const stripped = { v, seq, ts, run, pipe, ev, unserializable: true };
  if (prev !== undefined) stripped.prev = prev;
  if (full.unlocked) stripped.unlocked = true;
  return JSON.stringify(stripped);
}

/** The day file this process's events chain into. Its own, by writer: chain.h
 * holds a flock over `<day>.jsonl` that no Node process can join. */
export const jsSpoolPath = (day = new Date().toISOString().slice(0, 10)) =>
  path.join(SPOOL_DIR, `${day}.js.jsonl`);

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

  const spoolPath = jsSpoolPath();
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
    // spool first — the spool is the source of truth, the socket is the live
    // view. It goes in CHAINED (prev + .head sidecar, chain.h's protocol), or
    // into the .unchained sibling if the lock could not be taken. It never goes
    // in bare: an unprovable line beside provable ones costs the whole file its
    // verdict, and prev cannot be retro-fitted afterwards without rewriting the
    // file — the exact edit `rabadon audit` exists to convict.
    const line = chainedAppend(spoolPath, event) || safeStringify(event, event) + '\n';
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
