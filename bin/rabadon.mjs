#!/usr/bin/env node
// rabadon watch — the live terminal view.
//
// Run `rabadon watch` in one terminal; run your pipelines anywhere else on the
// machine. Every step, check, break and repair lands here the moment it
// happens — pushed over a unix socket, not polled from a file.
//
// Color = pipeline state (same law as the landing):
//   blue  = flowing (a step running inside its bound)
//   warm  = broken  (a check caught something)
//   lilac = rabadon intervening (repair in flight)
//   green = repaired / passed
//
// Zero dependencies. ANSI only.

import path0 from 'node:path';
import { listen, SOCK_PATH } from '../core/bus.mjs';

const C = {
  reset: '\x1b[0m', dim: '\x1b[2m', bold: '\x1b[1m',
  blue: '\x1b[38;5;75m',    // flowing
  warm: '\x1b[38;5;209m',   // broken
  lilac: '\x1b[38;5;141m',  // rabadon intervening
  green: '\x1b[38;5;114m',  // repaired / pass
  gray: '\x1b[38;5;245m',
};
const noColor = !process.stdout.isTTY || process.env.NO_COLOR;
const paint = (color, s) => (noColor ? s : color + s + C.reset);

function hms(ts) {
  const d = new Date(ts || Date.now());
  return d.toTimeString().slice(0, 8) + '.' + String(d.getMilliseconds()).padStart(3, '0');
}

const pipeWidth = { w: 10 };
function fmtPipe(pipe) {
  const p = String(pipe || '?');
  if (p.length > pipeWidth.w) pipeWidth.w = Math.min(p.length, 24);
  return p.slice(0, 24).padEnd(pipeWidth.w);
}

function fmtBound(b) {
  if (!b) return '';
  return Object.entries(b).map(([k, v]) => `${k}=${v}`).join(' ');
}

function render(e) {
  const t = paint(C.dim, hms(e.ts));
  const p = paint(C.gray, fmtPipe(e.pipe));
  const runTag = paint(C.dim, (e.run || '').slice(-6));
  let line;
  switch (e.ev) {
    case 'RUN_START':
      line = paint(C.blue, `▶ run start`) + paint(C.dim, `  [${(e.steps || []).join(' → ')}]  bound{${fmtBound(e.bound)}}`);
      break;
    case 'STEP_START':
      line = paint(C.blue, `→ ${e.step}`) + (e.tokens != null ? paint(C.dim, `  (spent: ${e.tokens} tok${e.calls != null ? `, ${e.calls} calls` : ''})`) : '');
      break;
    case 'CHECK_FAIL':
      line = paint(C.warm, `✗ BROKE  ${e.step}`) + paint(C.warm, `  ${(e.fails || []).map((f) => `${f.check}: ${f.why}`).join(' | ')}`);
      break;
    case 'REPAIR_START':
      line = paint(C.lilac, `⟲ repair #${e.attempt}  ${e.step}`) + paint(C.dim, `  fixing: ${(e.fixing || []).join(', ')}`);
      break;
    case 'REPAIR_OK':
      line = paint(C.green, `✓ repaired  ${e.step}`) + paint(C.dim, `  (attempt ${e.attempt})`);
      break;
    case 'REPAIR_FAIL':
      line = paint(C.warm, `✗ repair failed  ${e.step}`) + paint(C.dim, `  ${e.why || (e.remaining || []).join('; ')}`);
      break;
    case 'STEP_OK':
      line = paint(C.green, `✓ ${e.step}`) + (e.repaired ? paint(C.lilac, '  (repaired)') : '') + paint(C.dim, `  tokens=${e.tokens ?? '?'}`);
      break;
    case 'STOP':
      line = paint(C.warm, `■ STOP ${e.reason}`) + paint(C.dim, `  ${e.detail || ''}`);
      break;
    case 'RUN_DONE':
      line = (e.verdict === 'PASS' ? paint(C.green, `● PASS`) : paint(C.warm, `● ${e.verdict}`)) + paint(C.dim, `  tokens=${e.tokens ?? 0} depth=${e.depth ?? 0}`);
      break;
    default:
      line = paint(C.dim, `${e.ev} ${JSON.stringify(e).slice(0, 120)}`);
  }
  process.stdout.write(`${t}  ${p} ${runTag}  ${line}\n`);
}

const cmd = process.argv[2] || 'watch';

if (cmd === 'guard') {
  // rabadon writes the guard rules for a project from its own law files.
  const { generateGuard } = await import('../hooks/guard-gen.mjs');
  const dir = process.argv[3] ? path0.resolve(process.argv[3]) : process.cwd();
  process.stdout.write(`rabadon guard: reading law files in ${dir}, asking claude to write the rules…\n`);
  const { guardPath, guard } = await generateGuard(dir);
  process.stdout.write(`written: ${guardPath}\n`);
  process.stdout.write(`  bash rules: ${(guard.bash || []).length}, protected paths: ${(guard.protectedPaths || []).length}, pushGate: ${guard.pushGate ? 'yes' : 'no'}\n`);
  process.stdout.write(`REVIEW IT — the gate enforces exactly what is in that file.\n`);
  process.exit(0);
}

if (cmd === 'stats') {
  // The catch ledger: numbers from the spool, not claims. Every line here is
  // backed by a jsonl event with a timestamp.
  const fs = await import('node:fs');
  const { SPOOL_DIR } = await import('../core/bus.mjs');
  const days = Number(process.argv[process.argv.indexOf('--days') + 1]) || 7;
  const cutoff = Date.now() - days * 86400000;
  const perProject = new Map();
  let files = [];
  try { files = fs.readdirSync(SPOOL_DIR).filter((f) => f.endsWith('.jsonl')); } catch { }
  for (const f of files) {
    for (const line of fs.readFileSync(path0.join(SPOOL_DIR, f), 'utf8').split('\n')) {
      if (!line.trim()) continue;
      let e; try { e = JSON.parse(line); } catch { continue; }
      if (e.ts < cutoff) continue;
      const proj = String(e.pipe || '?').replace(/:session$/, '');
      if (!perProject.has(proj)) perProject.set(proj, { gated: 0, blocked: new Map(), loops: 0, repairsOk: 0, checkFails: 0, runs: new Set() });
      const s = perProject.get(proj);
      if (e.run) s.runs.add(e.run.slice(0, 8));
      if (e.ev === 'STEP_START') s.gated++;
      if (e.ev === 'CHECK_FAIL') { s.checkFails++; for (const fl of e.fails || []) { if (fl.check === 'loop-stop') s.loops++; } }
      if (e.ev === 'STOP' && e.reason === 'BLOCKED') {
        const rule = String(e.detail || '').slice(0, 60);
        s.blocked.set(rule, (s.blocked.get(rule) || 0) + 1);
      }
      if (e.ev === 'REPAIR_OK') s.repairsOk++;
    }
  }
  process.stdout.write(`rabadon stats — last ${days} day(s), source: ${SPOOL_DIR}\n\n`);
  if (!perProject.size) process.stdout.write('  (no events yet)\n');
  for (const [proj, s] of perProject) {
    const blockedTotal = [...s.blocked.values()].reduce((a, b) => a + b, 0);
    process.stdout.write(`  ${proj}\n`);
    process.stdout.write(`    actions gated:            ${s.gated}\n`);
    process.stdout.write(`    caught before happening:  ${blockedTotal}\n`);
    for (const [rule, n] of s.blocked) process.stdout.write(`      ${n}x  ${rule}\n`);
    process.stdout.write(`    checks failed (caught):   ${s.checkFails}${s.loops ? `  (loops stopped: ${s.loops})` : ''}\n`);
    process.stdout.write(`    repairs accepted:         ${s.repairsOk}\n\n`);
  }
  process.exit(0);
}

if (cmd === 'init') {
  // one command into any project: guard rules authored + hooks installed.
  const fs = await import('node:fs');
  const dir = process.argv[3] ? path0.resolve(process.argv[3]) : process.cwd();
  const gate = path0.join(path0.dirname(new URL(import.meta.url).pathname), '..', 'hooks', 'gate.mjs');
  const gateCmd = `node ${path0.resolve(gate)}`;
  const settingsPath = path0.join(dir, '.claude', 'settings.json');
  if (fs.existsSync(settingsPath)) {
    console.error(`rabadon init: ${settingsPath} already exists — add the hooks manually (gate: ${gateCmd}) so nothing of yours is overwritten.`);
    process.exit(1);
  }
  const { generateGuard } = await import('../hooks/guard-gen.mjs');
  process.stdout.write(`rabadon init: authoring guard rules for ${dir}…\n`);
  const { guardPath, guard } = await generateGuard(dir);
  fs.mkdirSync(path0.dirname(settingsPath), { recursive: true });
  const hook = [{ hooks: [{ type: 'command', command: gateCmd }] }];
  const matched = [{ matcher: 'Bash|Edit|Write|MultiEdit|NotebookEdit', hooks: [{ type: 'command', command: gateCmd }] }];
  fs.writeFileSync(settingsPath, JSON.stringify({
    hooks: { SessionStart: hook, UserPromptSubmit: hook, PreToolUse: matched, PostToolUse: matched, Stop: hook },
  }, null, 2) + '\n');
  try { fs.appendFileSync(path0.join(dir, '.gitignore'), '\n.rabadon/state.json\n'); } catch { }
  process.stdout.write(`written: ${guardPath} (${(guard.bash || []).length} bash + ${(guard.protectedPaths || []).length} path rules)\n`);
  process.stdout.write(`written: ${settingsPath}\n`);
  process.stdout.write(`REVIEW the guard, then just run \`claude\` in ${dir} — the session is supervised.\n`);
  process.exit(0);
}

if (cmd === 'off' || cmd === 'on') {
  const fs = await import('node:fs');
  const dir = path0.join(process.cwd(), '.rabadon');
  const offFile = path0.join(dir, 'off');
  if (cmd === 'off') {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(offFile, new Date().toISOString() + '\n');
    process.stdout.write('rabadon: OFF for this project (supervision + observation paused). `rabadon on` to resume.\n');
  } else {
    try { fs.unlinkSync(offFile); } catch { }
    process.stdout.write('rabadon: ON — the session is supervised again.\n');
  }
  process.exit(0);
}

if (cmd !== 'watch') {
  console.error(`rabadon: unknown command "${cmd}" (watch | guard [dir] | init [dir] | stats [--days N] | off | on)`);
  process.exit(1);
}

const banner = [
  '',
  `  ${paint(C.bold, 'rabadon watch')} ${paint(C.dim, '— live view of every checked pipeline on this machine')}`,
  `  ${paint(C.dim, `socket: ${SOCK_PATH}`)}`,
  `  ${paint(C.dim, 'waiting for pipelines… (run one anywhere; it will appear here the moment it starts)')}`,
  '',
].join('\n');

listen(render)
  .then(() => process.stdout.write(banner + '\n'))
  .catch((err) => { console.error(`rabadon watch: ${err.message}`); process.exit(1); });
