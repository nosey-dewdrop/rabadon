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
if (cmd !== 'watch') {
  console.error(`rabadon: unknown command "${cmd}" (only: watch)`);
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
