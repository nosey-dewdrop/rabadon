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

import fs from 'node:fs';
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

if (process.argv.includes('--version') || process.argv.includes('-v')) {
  console.log(JSON.parse(fs.readFileSync(new URL('../package.json', import.meta.url), 'utf8')).version);
  process.exit(0);
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

if (cmd === 'stats' || cmd === 'usage') {
  // The catch ledger. This used to read the spool HERE, through core/store.mjs
  // — a FOURTH reader beside rabadon-stats, rabadon-export and rabadon-trace,
  // with its own drill logic and its own arithmetic. drill.h says in as many
  // words that a fourth reader either calls the shared predicate or it is a bug,
  // and this one was: it printed `repairs accepted`, the single bucket
  // BENCHMARK.md §3 retired for holding four different events under one name, so
  // `rabadon usage` and `node bin/rabadon.mjs stats` told different stories
  // about the same bytes — and bench/reproduce.sh was calling THIS one to
  // reproduce a page that cites the other. It also did not answer to `usage` at
  // all, the name README and docs/commands.md give it. One reader, native; the
  // JS engine is retired (CLAUDE.md, EMEKLİLİK KURALI).
  const { spawnSync } = await import('node:child_process');
  const statsBin = path0.join(path0.dirname(new URL(import.meta.url).pathname), '..', 'native', 'rabadon-stats');
  if (!fs.existsSync(statsBin)) {
    console.error('rabadon usage: native engine not built — run `make` in the rabadon repo first.');
    process.exit(1);
  }
  const r = spawnSync(statsBin, process.argv.slice(3), { stdio: 'inherit' });
  process.exit(r.status ?? 1);
}

if (cmd === 'init') {
  // one command into any project: guard rules authored + hooks MERGED into
  // whatever settings the project already has (never clobbered, backed up).
  const fs = await import('node:fs');
  const dir = process.argv[3] ? path0.resolve(process.argv[3]) : process.cwd();
  const { installHooks } = await import('../hooks/install.mjs');
  const { generateGuard } = await import('../hooks/guard-gen.mjs');
  const guardFile = path0.join(dir, '.rabadon', 'guard.json');
  if (fs.existsSync(guardFile)) {
    process.stdout.write(`rabadon init: guard already present (${guardFile}) — keeping it.\n`);
  } else {
    process.stdout.write(`rabadon init: authoring guard rules for ${dir}…\n`);
    try {
      const { guardPath, guard } = await generateGuard(dir);
      process.stdout.write(`written: ${guardPath} (${(guard.bash || []).length} bash + ${(guard.protectedPaths || []).length} path rules)\n`);
    } catch (e) {
      // authoring needs the claude CLI and can fail transiently — a stranger's
      // first minute gets a clean next step, never a raw stack
      console.error(`rabadon init: could not author the guard (${String(e.message).slice(0, 200)})`);
      console.error(`  retry \`rabadon init\`, or write ${guardFile} by hand (schema: SPEC.md §3) — hooks were NOT installed, nothing was changed.`);
      process.exit(1);
    }
  }
  let r;
  try { r = installHooks(dir); }
  catch (e) { console.error(`rabadon init: ${path0.join(dir, '.claude', 'settings.json')} could not be parsed (${e.message}) — fix it, rabadon will not overwrite a file it cannot read.`); process.exit(1); }
  process.stdout.write(r.changed
    ? `hooks merged into: ${r.settingsPath}${r.backedUp ? ` (original backed up: ${path0.basename(r.settingsPath)}.bak-rabadon)` : ''}\n`
    : `hooks already installed: ${r.settingsPath}\n`);
  process.stdout.write(`REVIEW the guard, then just run \`claude\` in ${dir} — the session is supervised. \`rabadon stats\` shows the ledger.\n`);
  process.exit(0);
}

if (cmd === 'statusline') {
  // rabadon's presence in the Claude Code terminal — a symbol, not a report
  // (the owner's law). Standing guard = a lilac star. The moment rabadon
  // catches something, the star SPINS for a few seconds, then settles back to
  // a still star — motion, not an alarm colour (Damla's call: no orange, the
  // * turns). Gray = off. The statusline still never lists a catch or grows;
  // the spin IS the whole signal, and catches still announce themselves inline.
  const fs = await import('node:fs');
  let input = '';
  try { input = fs.readFileSync(0, 'utf8'); } catch { }
  let info = {};
  try { info = JSON.parse(input); } catch { }
  const dir = (info.workspace && info.workspace.current_dir) || info.cwd || process.cwd();
  const project = path0.basename(dir);
  const model = (info.model && info.model.display_name) || '';
  const LILAC = '\x1b[38;5;141m', GRAY = '\x1b[38;5;245m', R = '\x1b[0m';
  const off = process.env.RABADON_OFF === '1' || fs.existsSync(path0.join(dir, '.rabadon', 'off'));

  // did rabadon catch (or start repairing) something in the last few seconds?
  // reads only the tail of today's spool so the statusline stays instant.
  const SPIN_MS = 5000;
  function caughtRecently() {
    try {
      const rdir = process.env.RABADON_DIR || path0.join(process.env.HOME || '', '.rabadon');
      const f = path0.join(rdir, 'spool', new Date().toISOString().slice(0, 10) + '.jsonl');
      const size = fs.statSync(f).size;
      const from = Math.max(0, size - 32768);
      const fd = fs.openSync(f, 'r');
      const buf = Buffer.alloc(size - from);
      fs.readSync(fd, buf, 0, buf.length, from);
      fs.closeSync(fd);
      const tag = `"${project}:session"`;
      let last = 0;
      for (const l of buf.toString('utf8').split('\n')) {
        if (!l.includes(tag)) continue;
        let e; try { e = JSON.parse(l); } catch { continue; }
        const isCatch = (e.ev === 'STOP' && e.reason === 'BLOCKED') || e.ev === 'CHECK_FAIL' || e.ev === 'REPAIR_START';
        if (isCatch && e.ts > last) last = e.ts;
      }
      return last > 0 && (Date.now() - last) < SPIN_MS;
    } catch { return false; }
  }

  // a star caught mid-rotation — cycles each render, reads as a spin
  const FRAMES = ['✶', '✷', '✸', '✹'];
  const spinning = !off && caughtRecently();
  const star = spinning ? FRAMES[Math.floor(Date.now() / 100) % FRAMES.length] : '*';
  const seg = off ? `${GRAY}* rabadon off${R}` : `${LILAC}${star} rabadon${R}`;
  process.stdout.write(`${GRAY}${model}${model ? ' · ' : ''}${project}${R}  ${seg}\n`);
  process.exit(0);
}

if (cmd === 'do') {
  // the motor: task in, gate-verified output out. `rabadon do "<task>" [dir]`
  const task = process.argv[3];
  if (!task || task.startsWith('--')) { console.error('rabadon do: usage — rabadon do "<task>" [dir]'); process.exit(1); }
  const dir = path0.resolve(process.argv[4] && !process.argv[4].startsWith('--') ? process.argv[4] : process.cwd());
  // the motor is native now (C++ language law). This dispatches to the binary:
  // plan (one model call) then the gate-verified loop. The JS engine is retired.
  const { spawnSync } = await import('node:child_process');
  const doBin = path0.join(path0.dirname(new URL(import.meta.url).pathname), '..', 'native', 'rabadon-do');
  if (!fs.existsSync(doBin)) { console.error('rabadon do: native engine not built — run `make` in the rabadon repo first.'); process.exit(1); }
  const r = spawnSync(doBin, [task, dir], { stdio: 'inherit' });
  process.exit(r.status ?? 1);
}

if (cmd === 'exec') {
  // The second binding — proof the spec is agent-agnostic. Any runtime that
  // shells out can route commands through the SAME gate the Claude Code hooks
  // use: `rabadon exec -- <cmd...>`. Pre-gated by the project's guard; the
  // action and its verdict land on the same spool/stream.
  const cp = await import('node:child_process');
  const sep = process.argv.indexOf('--');
  const argv = sep === -1 ? process.argv.slice(3) : process.argv.slice(sep + 1);
  if (!argv.length) { console.error('rabadon exec: usage — rabadon exec -- <command...>'); process.exit(1); }
  const command = argv.join(' ');
  const gate = path0.resolve(path0.join(path0.dirname(new URL(import.meta.url).pathname), '..', 'hooks', 'gate.mjs'));
  const pre = cp.spawnSync('node', [gate], {
    input: JSON.stringify({ hook_event_name: 'PreToolUse', cwd: process.cwd(), session_id: `exec-${process.pid}`, tool_name: 'Bash', tool_input: { command } }),
    encoding: 'utf8',
  });
  if (pre.status === 2) { process.stderr.write(pre.stderr); process.exit(2); }
  const run = cp.spawnSync(argv[0], argv.slice(1), { stdio: 'inherit', shell: false });
  cp.spawnSync('node', [gate], {
    input: JSON.stringify({ hook_event_name: 'PostToolUse', cwd: process.cwd(), session_id: `exec-${process.pid}`, tool_name: 'Bash', tool_input: { command }, tool_response: `exit=${run.status}` }),
    encoding: 'utf8',
  });
  process.exit(run.status || 0);
}

if (cmd === 'spin') {
  // DEVRIDAIM — the work itself keeps turning. If the project has an open
  // front (red tests / unfinished goal), rabadon LAUNCHES the worker itself:
  // a headless Claude session inside the project, which means the project's
  // own gate supervises every move it makes. After each spin rabadon runs
  // the REAL test suite and decides: green -> done, red -> next spin, up to
  // --max spins. No summaries. The job either finishes or stops at a bound.
  const fs = await import('node:fs');
  const cp = await import('node:child_process');
  const dir = path0.resolve(process.argv[3] && !process.argv[3].startsWith('--') ? process.argv[3] : process.cwd());
  const maxSpins = Number(process.argv[process.argv.indexOf('--max') + 1]) || 3;
  const guardFile = path0.join(dir, '.rabadon', 'guard.json');
  let guard = null;
  try { guard = JSON.parse(fs.readFileSync(guardFile, 'utf8')); } catch { }

  const runTests = () => {
    if (!guard || !guard.pushGate || !guard.pushGate.run) return { ran: false };
    try {
      const out = cp.execSync(guard.pushGate.run, { cwd: dir, encoding: 'utf8', timeout: (guard.pushGate.timeoutSec || 900) * 1000, stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 16 * 1024 * 1024 });
      return { ran: true, green: guard.testPassPattern ? new RegExp(guard.testPassPattern, 'i').test(out) : true, out };
    } catch (e) {
      return { ran: true, green: false, out: String((e.stdout || '') + (e.stderr || '')) };
    }
  };

  let status = runTests();
  if (!status.ran) { process.stdout.write('rabadon spin: no pushGate.run in the guard — nothing I can verify, nothing I will spin.\n'); process.exit(1); }
  if (status.green) { process.stdout.write('rabadon spin: suite is GREEN — no open front here.\n'); process.exit(0); }

  let handoff = '';
  try { handoff = fs.readFileSync(path0.join(dir, '.rabadon', 'handoff.md'), 'utf8'); } catch { }

  for (let spin = 1; spin <= maxSpins; spin++) {
    process.stdout.write(`spin ${spin}/${maxSpins}: suite RED — launching the worker (supervised by this project's own gate)…\n`);
    const failTail = status.out.split('\n').filter((l) => /fail|error|\*\*\*/i.test(l)).slice(-12).join('\n');
    const task = [
      'You are the worker inside rabadon devridaim, continuing this project unattended.',
      'The test suite is RED. Fix the CODE so the suite passes. Laws:',
      '- never weaken or skip a test; never touch pinned reference files;',
      '- decisions the project reserves for its owner (re-pins, scope changes) are NOT yours — if the only fix is such a decision, stop and say exactly that;',
      '- make the smallest correct fix, run the suite yourself, and finish.',
      handoff ? `\n## where the last session stood\n${handoff.slice(0, 2000)}` : '',
      `\n## failing output\n${failTail}`,
      `\n## the suite command\n${guard.pushGate.run}`,
    ].join('\n');
    try {
      cp.execSync('claude -p --permission-mode acceptEdits --allowedTools "Read,Edit,Write,Bash,Grep,Glob"', {
        cwd: dir, input: task, stdio: ['pipe', 'inherit', 'inherit'], timeout: 30 * 60000,
      });
    } catch { /* worker ended non-zero — the suite is the judge, not the exit code */ }
    status = runTests();
    if (status.green) {
      process.stdout.write(`spin ${spin}: suite GREEN — the cycle closed the front.\n`);
      process.exit(0);
    }
  }
  process.stdout.write(`rabadon spin: still RED after ${maxSpins} spin(s) — bounded stop, front stays open (this is fail-closed, not failure to try).\n`);
  process.exit(1);
}

if (cmd === 'pack') {
  // Guard packs — the ecosystem mechanism. `pack export` distills a project's
  // guard (including incident-authored rules) into a shareable, sanitized
  // pack; `pack import` merges one into a project's guard. Rules carry their
  // origin. Code can be copied; a growing library of battle-authored rules
  // cannot.
  const fs = await import('node:fs');
  const sub = process.argv[3];
  if (sub === 'export') {
    const dir = path0.resolve(process.argv[4] || process.cwd());
    const g = JSON.parse(fs.readFileSync(path0.join(dir, '.rabadon', 'guard.json'), 'utf8'));
    const sane = (r) => !/\/Users\/|\/home\/|damummyphus/i.test(JSON.stringify(r)); // no machine-specific paths leave
    const pack = {
      rabadonPack: 1,
      name: `${g.project || path0.basename(dir)}-pack`,
      exportedAt: new Date().toISOString(),
      bash: (g.bash || []).filter(sane),
      protectedPaths: (g.protectedPaths || []).filter(sane),
      testPaths: g.testPaths || [],
      notes: 'rules carry their own why; review before importing — a guard is law, not decoration',
    };
    process.stdout.write(JSON.stringify(pack, null, 2) + '\n');
    process.exit(0);
  }
  if (sub === 'import') {
    const file = process.argv[4];
    const dir = path0.resolve(process.argv[5] || process.cwd());
    const pack = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (pack.rabadonPack !== 1) { console.error('rabadon pack: not a v1 pack'); process.exit(1); }
    for (const r of [...(pack.bash || []), ...(pack.protectedPaths || [])]) new RegExp(r.deny || r.match, 'i'); // must compile
    const guardFile = path0.join(dir, '.rabadon', 'guard.json');
    const g = fs.existsSync(guardFile) ? JSON.parse(fs.readFileSync(guardFile, 'utf8')) : { project: path0.basename(dir), bash: [], protectedPaths: [] };
    let added = 0;
    for (const [key, list] of [['bash', pack.bash || []], ['protectedPaths', pack.protectedPaths || []]]) {
      g[key] = g[key] || [];
      for (const r of list) {
        if (!g[key].some((x) => x.id === r.id)) { g[key].push({ ...r, source: pack.name }); added++; }
      }
    }
    if (pack.testPaths && pack.testPaths.length && !(g.testPaths || []).length) g.testPaths = pack.testPaths;
    fs.mkdirSync(path0.dirname(guardFile), { recursive: true });
    fs.writeFileSync(guardFile, JSON.stringify(g, null, 2) + '\n');
    process.stdout.write(`rabadon pack: ${added} rule(s) from "${pack.name}" merged into ${guardFile}\nREVIEW the guard — imported law is still law.\n`);
    process.exit(0);
  }
  console.error('rabadon pack: usage — pack export [dir] | pack import <pack.json> [dir]');
  process.exit(1);
}

if (cmd === 'fleet') {
  // The whole fleet, one command. For every git project under <root>:
  //   - author a guard (Claude from the project's own law files; an honest
  //     baseline if it has none),
  //   - MERGE the gate hooks into .claude/settings.json (never clobber —
  //     existing settings are backed up first),
  //   - verify end-to-end with a synthetic event,
  //   - run a first-catch drill so the gate is SEEN working in minute one.
  const fs = await import('node:fs');
  const cp = await import('node:child_process');
  const { SPOOL_DIR } = await import('../core/bus.mjs');
  const root = path0.resolve(process.argv[3] || process.cwd());
  const gate = path0.resolve(path0.join(path0.dirname(new URL(import.meta.url).pathname), '..', 'hooks', 'gate.mjs'));
  const gateCmd = `node ${gate}`;
  const EXCLUDE = /_archive|\.audit-clones|node_modules|\.parked|rabadon$/;

  const projects = fs.readdirSync(root)
    .map((d) => path0.join(root, d))
    .filter((p) => { try { return fs.statSync(p).isDirectory() && fs.existsSync(path0.join(p, '.git')) && !EXCLUDE.test(p); } catch { return false; } });
  // include nested working dir if present
  const nest = path0.join(root, '00_currently_on_working');
  if (fs.existsSync(nest)) {
    for (const d of fs.readdirSync(nest)) {
      const p = path0.join(nest, d);
      try { if (fs.statSync(p).isDirectory() && fs.existsSync(path0.join(p, '.git')) && !EXCLUDE.test(p)) projects.push(p); } catch { }
    }
  }
  process.stdout.write(`rabadon fleet: ${projects.length} git projects under ${root}\n\n`);

  const BASELINE = {
    bash: [
      { id: 'no-force-push-main', deny: 'git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b', why: 'baseline: force-pushing a shared branch destroys history' },
      { id: 'no-rm-rf-outside', deny: 'rm\\s+-\\w*[rf]\\w*\\s+(/(?!tmp)|~/(?!\\.)|\\$HOME)', why: 'baseline: recursive delete outside the project is unrecoverable' },
      { id: 'no-hard-reset-main', deny: 'git\\s+reset\\s+--hard\\s+(origin/)?(main|master)\\b', why: 'baseline: rewrite shared state via commits, not resets' },
      { id: 'no-hook-bypass', deny: 'git\\s+(commit|push)[^|;&]*--no-verify', why: 'baseline: bypassing hooks bypasses every gate at once' },
    ],
    protectedPaths: [],
  };

  const results = [];
  for (const p of projects) {
    const name = path0.basename(p);
    const guardFile = path0.join(p, '.rabadon', 'guard.json');
    let guardHow = 'kept';
    try {
      if (!fs.existsSync(guardFile)) {
        const hasLaws = ['RULES.md', 'ENV.md', 'CLAUDE.md'].some((f) => fs.existsSync(path0.join(p, f)));
        if (hasLaws) {
          const { generateGuard } = await import('../hooks/guard-gen.mjs');
          await generateGuard(p);
          guardHow = 'authored';
        } else {
          fs.mkdirSync(path0.dirname(guardFile), { recursive: true });
          fs.writeFileSync(guardFile, JSON.stringify({ project: name, ...BASELINE, generatedBy: 'rabadon fleet (baseline)' }, null, 2) + '\n');
          guardHow = 'baseline';
        }
      }
      // merge hooks into settings.json without clobbering (shared installer)
      const { installHooks } = await import('../hooks/install.mjs');
      installHooks(p, { gateCmd });

      // end-to-end verify + first-catch drill against the project's OWN top rule
      const g = JSON.parse(fs.readFileSync(guardFile, 'utf8'));
      const marker = `fleet-${process.pid}-${name}`;
      cp.execSync(`node ${gate}`, { input: JSON.stringify({ hook_event_name: 'PreToolUse', cwd: p, session_id: marker, tool_name: 'Bash', tool_input: { command: `echo ${marker}` } }), stdio: ['pipe', 'pipe', 'pipe'], timeout: 15000 });
      const landed = fs.readFileSync(path0.join(SPOOL_DIR, new Date().toISOString().slice(0, 10) + '.jsonl'), 'utf8').includes(marker);
      let drill = '-';
      const rule = (g.bash || [])[0];
      if (rule) {
        // a drill is a fake command that MATCHES the rule — proof the gate bites here
        const sample = rule.id.includes('force') ? 'git push --force origin main'
          : rule.id.includes('wrangler') ? 'npx wrangler deploy'
          : rule.id.includes('reset') ? 'git reset --hard origin/main'
          : rule.id.includes('no-verify') || rule.id.includes('bypass') ? 'git commit --no-verify -m x'
          : null;
        if (sample) {
          try {
            cp.execSync(`node ${gate}`, { input: JSON.stringify({ hook_event_name: 'PreToolUse', cwd: p, session_id: marker, tool_name: 'Bash', tool_input: { command: sample } }), stdio: ['pipe', 'pipe', 'pipe'], timeout: 15000 });
            drill = 'MISSED';
          } catch { drill = `BLOCKED (${rule.id})`; }
        }
      }
      // clean drill counters so real sessions start fresh
      try { fs.unlinkSync(path0.join(p, '.rabadon', 'state.json')); } catch { }
      results.push({ name, guardHow, e2e: landed ? 'ok' : 'FAIL', drill });
      process.stdout.write(`  ${name.padEnd(24)} guard:${guardHow.padEnd(9)} e2e:${landed ? 'ok  ' : 'FAIL'} drill:${drill}\n`);
    } catch (e) {
      results.push({ name, error: String(e.message).slice(0, 60) });
      process.stdout.write(`  ${name.padEnd(24)} ERROR: ${String(e.message).slice(0, 80)}\n`);
    }
  }
  const ok = results.filter((r) => r.e2e === 'ok').length;
  process.stdout.write(`\nfleet done: ${ok}/${projects.length} projects under guard.\n`);
  process.exit(0);
}

if (cmd === 'doctor') {
  // end-to-end self-check: a supervisor that silently fails open is worse
  // than none. Verifies every link of its own chain, loudly.
  const fs = await import('node:fs');
  const os = await import('node:os');
  const cp = await import('node:child_process');
  const { SPOOL_DIR } = await import('../core/bus.mjs');
  const dir = process.cwd();
  let fail = 0;
  const check = (name, ok, hint) => { process.stdout.write(`  ${ok ? 'OK  ' : 'FAIL'}  ${name}${ok ? '' : ` — ${hint}`}\n`); if (!ok) fail++; };

  check('node >= 18', Number(process.versions.node.split('.')[0]) >= 18, `found ${process.versions.node}`);
  let hasClaude = true;
  try { cp.execSync('claude --version', { stdio: 'pipe', timeout: 15000 }); } catch { hasClaude = false; }
  check('claude cli (guard authoring, diagnosis, drift judge)', hasClaude, 'install claude code or set RABADON_JUDGE=0');
  try { fs.mkdirSync(SPOOL_DIR, { recursive: true }); fs.accessSync(SPOOL_DIR, fs.constants.W_OK); check('spool writable', true); } catch { check('spool writable', false, SPOOL_DIR); }

  let guardOk = null;
  try {
    const g = JSON.parse(fs.readFileSync(path0.join(dir, '.rabadon', 'guard.json'), 'utf8'));
    guardOk = true;
    for (const r of [...(g.bash || []), ...(g.protectedPaths || [])]) new RegExp(r.deny || r.match, 'i');
    check(`guard.json valid (${(g.bash || []).length} bash + ${(g.protectedPaths || []).length} path rules)`, true);
  } catch (e) { if (guardOk !== null) check('guard.json valid', false, e.message.slice(0, 80)); else check('guard.json present', false, 'run `rabadon init` or `rabadon guard`'); }

  let hooksOk = false;
  try {
    const st = JSON.parse(fs.readFileSync(path0.join(dir, '.claude', 'settings.json'), 'utf8'));
    hooksOk = JSON.stringify(st.hooks || {}).includes('gate.mjs');
  } catch { }
  check('hooks installed in this project', hooksOk, 'run `rabadon init` (or add gate.mjs hooks to .claude/settings.json)');

  // fire a synthetic event through the REAL gate binary and verify it lands in the spool
  const gate = path0.join(path0.dirname(new URL(import.meta.url).pathname), '..', 'hooks', 'gate.mjs');
  const marker = `doctor-${process.pid}`;
  try {
    cp.execSync(`node ${gate}`, { input: JSON.stringify({ hook_event_name: 'PreToolUse', cwd: dir, session_id: marker, tool_name: 'Bash', tool_input: { command: `echo ${marker}` } }), stdio: ['pipe', 'pipe', 'pipe'], timeout: 15000 });
    const today = path0.join(SPOOL_DIR, new Date().toISOString().slice(0, 10) + '.jsonl');
    const landed = fs.readFileSync(today, 'utf8').includes(marker);
    check('gate end-to-end (synthetic event through the real binary -> spool)', landed, 'event did not land in the spool');
  } catch (e) { check('gate end-to-end', false, String(e.message).slice(0, 80)); }

  process.stdout.write(fail ? `\n${fail} problem(s) — rabadon may be failing open.\n` : `\nall clear — rabadon is standing guard here.\n`);
  process.exit(fail ? 1 : 0);
}

if (cmd === 'ui') {
  // the dashboard — what the hosted platforms sell, standing on YOUR disk.
  // `rabadon ui [--port N] [--root DIR]...`  then open the printed URL.
  const { createUiServer } = await import('../ui/server.mjs');
  const portIdx = process.argv.indexOf('--port');
  const port = portIdx !== -1 ? Number(process.argv[portIdx + 1]) : 8484;
  const roots = [];
  for (let i = 3; i < process.argv.length; i++) {
    if (process.argv[i] === '--root' && process.argv[i + 1]) roots.push(path0.resolve(process.argv[++i]));
  }
  if (!roots.length) roots.push(process.cwd());
  try {
    const ui = await createUiServer({ port, roots });
    process.stdout.write(`rabadon ui — http://127.0.0.1:${ui.port}\n`);
    process.stdout.write(`  local only: reads ~/.rabadon/spool, binds 127.0.0.1, nothing leaves this machine.\n`);
    process.stdout.write(`  fleet roots: ${roots.join(', ')}\n`);
  } catch (e) {
    console.error(`rabadon ui: ${e.message}${String(e.message).includes('EADDRINUSE') ? ' — another ui is already running; open it, or pass --port' : ''}`);
    process.exit(1);
  }
} else if (cmd === 'off' || cmd === 'on') {
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

if (cmd === 'watch') {
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
} else if (cmd !== 'ui') {
  console.error(`rabadon: unknown command "${cmd}" (watch | ui | do "<task>" [dir] | guard [dir] | init [dir] | fleet [root] | spin [dir] | exec -- <cmd> | pack export|import | stats [--days N] | doctor | statusline | off | on)`);
  process.exit(1);
}
