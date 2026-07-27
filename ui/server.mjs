// rabadon ui — the dashboard server.
//
// What Langfuse/Braintrust/Galileo sell as "the platform" is, at its core,
// this surface: your traces, your catches, your numbers, on one screen. The
// difference here is the law rabadon already lives by: EVERYTHING IS LOCAL.
// The server binds 127.0.0.1, reads the spool on your disk, and streams live
// events from the same files the pipelines already write. No account, no
// upload, no "your data helps us improve".
//
// Zero dependencies: node:http + node:fs. The page is one HTML file worth of
// inline code (ui/page.mjs); the API is read-only over core/store.mjs.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { SPOOL_DIR } from '../core/bus.mjs';
import { readEvents, indexRuns, aggregate, scanFleet } from '../core/store.mjs';
import { page } from './page.mjs';

const json = (res, code, body) => {
  const s = JSON.stringify(body);
  res.writeHead(code, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(s) });
  res.end(s);
};

/**
 * Tail the spool directory: replay the last `replay` events of today, then
 * push every newly appended line the moment it lands. Returns { close }.
 */
export function tailSpool(spoolDir, onEvent, { replay = 100 } = {}) {
  const offsets = new Map(); // file -> bytes already consumed

  const todayFile = () => path.join(spoolDir, new Date().toISOString().slice(0, 10) + '.jsonl');

  const consume = (file, { emit = true } = {}) => {
    let stat;
    try { stat = fs.statSync(file); } catch { return; }
    const from = offsets.get(file) || 0;
    if (stat.size <= from) { if (stat.size < from) offsets.set(file, 0); return; }
    let fd;
    try {
      fd = fs.openSync(file, 'r');
      const buf = Buffer.alloc(stat.size - from);
      fs.readSync(fd, buf, 0, buf.length, from);
      offsets.set(file, stat.size);
      if (!emit) return;
      for (const line of buf.toString('utf8').split('\n')) {
        if (!line.trim()) continue;
        try { onEvent(JSON.parse(line)); } catch { /* a torn line will complete on the next append */ }
      }
    } finally {
      if (fd !== undefined) fs.closeSync(fd);
    }
  };

  // replay the tail of today so the feed is not empty on open
  try {
    const file = todayFile();
    const lines = fs.readFileSync(file, 'utf8').trim().split('\n').filter(Boolean);
    offsets.set(file, fs.statSync(file).size);
    for (const line of lines.slice(-replay)) {
      try { onEvent(JSON.parse(line), { replay: true }); } catch { }
    }
  } catch { /* no spool yet — fine, the watcher below will catch the first event */ }

  let watcher = null;
  try {
    fs.mkdirSync(spoolDir, { recursive: true });
    watcher = fs.watch(spoolDir, () => consume(todayFile()));
  } catch { }
  // fs.watch can miss appends on some filesystems; a slow poll is the honest backstop
  const poll = setInterval(() => consume(todayFile()), 2000);
  poll.unref();

  return {
    close: () => { try { watcher && watcher.close(); } catch { } clearInterval(poll); },
  };
}

/**
 * Start the dashboard. Local only.
 * @param {{ port?: number, spoolDir?: string, roots?: string[] }} opts
 */
export function createUiServer({ port = 8484, spoolDir = SPOOL_DIR, roots = [process.cwd()] } = {}) {
  const clients = new Set(); // SSE responses

  const tail = tailSpool(spoolDir, (event, meta = {}) => {
    if (meta.replay) return; // replay is served per-connection, not broadcast
    const frame = `data: ${JSON.stringify(event)}\n\n`;
    for (const res of clients) { try { res.write(frame); } catch { clients.delete(res); } }
  });

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const days = Math.max(1, Math.min(90, Number(url.searchParams.get('days')) || 7));

    if (url.pathname === '/') {
      const body = page();
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(body);
      return;
    }

    if (url.pathname === '/api/summary') {
      const { events, unparseable } = readEvents({ days, spoolDir });
      const { totals, projects } = aggregate(events);
      json(res, 200, { days, totals, projects, unparseable, spoolDir, generatedAt: Date.now() });
      return;
    }

    if (url.pathname === '/api/runs') {
      const { events } = readEvents({ days, spoolDir });
      let runs = indexRuns(events);
      const project = url.searchParams.get('project');
      const kind = url.searchParams.get('kind');
      if (project) runs = runs.filter((r) => r.project === project);
      if (kind) runs = runs.filter((r) => r.kind === kind);
      json(res, 200, { days, count: runs.length, runs: runs.slice(0, 200) });
      return;
    }

    if (url.pathname === '/api/run') {
      const { events } = readEvents({ days: 90, spoolDir });
      const id = url.searchParams.get('id');
      const run = indexRuns(events).find((r) => r.id === id);
      if (!run) { json(res, 404, { error: 'run not found in the spool window' }); return; }
      json(res, 200, { run, events: events.filter((e) => e.run === id) });
      return;
    }

    if (url.pathname === '/api/fleet') {
      const { events } = readEvents({ days: 30, spoolDir });
      json(res, 200, { roots, fleet: scanFleet(roots, { events }) });
      return;
    }

    if (url.pathname === '/api/live') {
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
      res.write(': rabadon live\n\n');
      // per-connection replay so a fresh tab sees the recent past immediately
      try {
        const file = path.join(spoolDir, new Date().toISOString().slice(0, 10) + '.jsonl');
        const lines = fs.readFileSync(file, 'utf8').trim().split('\n').filter(Boolean).slice(-60);
        for (const line of lines) res.write(`data: ${line}\n\n`);
      } catch { }
      clients.add(res);
      req.on('close', () => clients.delete(res));
      return;
    }

    json(res, 404, { error: 'unknown path' });
  });

  return new Promise((resolve, reject) => {
    server.on('error', reject);
    server.listen(port, '127.0.0.1', () => {
      resolve({
        server,
        port: server.address().port,
        close: () => new Promise((r) => { tail.close(); for (const c of clients) { try { c.end(); } catch { } } server.close(() => r()); }),
      });
    });
  });
}

export default { createUiServer, tailSpool };
