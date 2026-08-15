#!/usr/bin/env node
// rabadon manage — init / remove / doctor, the lifecycle verbs.
//
// These are glue (settings surgery + process checks), not engine, so they live
// in JS — and here, NOT in bin/rabadon.mjs, which is anti-path (never edited).
// rabadon-cli.sh routes `init`/`remove`/`uninstall`/`doctor` here.
//
// Laws honored:
//   - installHooks/removeHooks in hooks/install.mjs are the ONE settings-merge
//     implementation (repair-aware, backup-first, native-path);
//   - init falls open when authoring is unavailable (--no-llm / no claude CLI)
//     by writing a safe baseline guard, then lints it;
//   - init/remove take --global to target ~/.claude/settings.json;
//   - nothing here ever fabricates a success it did not verify.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { installHooks, installCursorHooks, removeHooks, GATE_BIN, DRIFT_BIN, nativeBin, missingCore, RABADON_CMD_RE } from './install.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = path.resolve(HERE, '..');

// The safe baseline: the same four laws the home guard ships with — force-push,
// rm -rf outside the tree, hard-reset main, hook bypass. Zero project-specific
// knowledge, so it is always correct to write; `rabadon guard` refines it later.
const BASELINE = {
  bash: [
    { id: 'no-force-push-main', deny: 'git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b', why: 'force-pushing a shared branch destroys history' },
    { id: 'no-rm-rf-outside', deny: 'rm\\s+-\\w*[rf]\\w*\\s+(/(?!tmp)|~/(?!\\.)|\\$HOME)', why: 'recursive delete outside a project is unrecoverable' },
    { id: 'no-hard-reset-main', deny: 'git\\s+reset\\s+--hard\\s+(origin/)?(main|master)\\b', why: 'rewrite shared state via commits, not resets' },
    { id: 'no-hook-bypass', deny: 'git\\s+(commit|push)[^|;&]*--no-verify', why: 'bypassing hooks bypasses every gate at once' },
  ],
  protectedPaths: [],
};

function writeBaseline(dir, name) {
  const guardDir = path.join(dir, '.rabadon');
  fs.mkdirSync(guardDir, { recursive: true });
  const guard = { project: name, ...BASELINE, generatedBy: 'rabadon init --no-llm (baseline; run `rabadon guard` to author project rules)' };
  fs.writeFileSync(path.join(guardDir, 'guard.json'), JSON.stringify(guard, null, 2) + '\n');
  return path.join(guardDir, 'guard.json');
}

function hasClaude() {
  return spawnSync('command', ['-v', 'claude'], { shell: true, stdio: 'ignore' }).status === 0;
}

function gateExists() {
  return fs.existsSync(GATE_BIN);
}

function lint(dir) {
  if (!gateExists()) return { ok: false, out: 'gate not built' };
  const r = spawnSync(GATE_BIN, ['--lint', dir], { encoding: 'utf8' });
  return { ok: r.status === 0, out: (r.stdout || '') + (r.stderr || '') };
}

async function cmdInit(args) {
  const noLlm = args.includes('--no-llm');
  const global = args.includes('--global');
  const posArg = args.find((a) => !a.startsWith('-'));
  const dir = global ? os.homedir() : (posArg ? path.resolve(posArg) : process.cwd());
  const name = path.basename(dir === os.homedir() ? os.homedir() : dir);

  if (!gateExists()) {
    console.error('rabadon init: the native core is not built — cannot guard yet.');
    console.error(`  build it: (cd ${PKG_ROOT} && make)   then re-run \`rabadon init\`.`);
    console.error('  diagnose: rabadon doctor');
    process.exit(3);
  }

  // 1) guard
  const guardFile = path.join(dir, '.rabadon', 'guard.json');
  if (fs.existsSync(guardFile)) {
    console.log(`rabadon init: guard already present (${guardFile}) — keeping it.`);
  } else if (global) {
    // the home guard is the machine baseline; author nothing project-specific
    writeBaseline(dir, name);
    console.log(`rabadon init: wrote the baseline home guard (${guardFile}).`);
  } else if (noLlm || !hasClaude()) {
    writeBaseline(dir, name);
    console.log(`rabadon init: wrote a baseline guard (${guardFile}).`);
    if (!noLlm) console.log('  (the claude CLI was not found — author project-specific rules later with `rabadon guard`.)');
  } else {
    try {
      const { generateGuard } = await import('./guard-gen.mjs');
      const { guardPath, guard } = await generateGuard(dir);
      console.log(`rabadon init: authored ${guardPath} (${(guard.bash || []).length} bash + ${(guard.protectedPaths || []).length} path rules).`);
    } catch (e) {
      writeBaseline(dir, name);
      console.log(`rabadon init: authoring failed (${String(e.message).slice(0, 120)}) — wrote a baseline guard instead. Refine it with \`rabadon guard\`.`);
    }
  }

  // 2) lint what we are about to enforce
  const lr = lint(dir);
  if (!lr.ok) {
    console.error(`rabadon init: the guard has problems — ${lr.out.trim()}`);
    console.error('  hooks were NOT installed. Fix the guard and re-run.');
    process.exit(1);
  }

  // 3) hooks
  let r;
  try { r = installHooks(dir); }
  catch (e) {
    console.error(`rabadon init: ${path.join(dir, '.claude', 'settings.json')} could not be parsed (${e.message}) — rabadon will not overwrite a file it cannot read.`);
    process.exit(1);
  }

  // 3b) Cursor, when this is a project rather than the global target. Wiring an
  // agent the operator may not use costs one small file and removes the single
  // most common reason somebody closes the tab: looking for their own editor and
  // not finding it. Nothing here is Cursor-specific below the config — the same
  // binary reads both payloads.
  let cur = null;
  if (!global) {
    try { cur = installCursorHooks(dir); }
    catch { /* an unwritable .cursor must not fail an otherwise good install */ }
  }

  // 4) the closing block — what got wired, how to see it, how to stop it
  const where = r.settingsPath;
  console.log('');
  console.log(`rabadon init — done${global ? ' (global)' : ''}.`);
  console.log('');
  console.log('  wired in:');
  console.log(`    ${guardFile}   — the law, REVIEW it (deny rules + protected paths)`);
  console.log(`    ${where}   — gate hooks merged${r.backedUp ? ` (original: ${path.basename(where)}.bak-rabadon)` : ''}${r.repaired ? ' [repaired a stale install]' : ''}`);
  if (cur && cur.changed) console.log(`    ${cur.hooksPath}   — the same gate, for Cursor${cur.backedUp ? ' (original: hooks.json.bak-rabadon)' : ''}`);
  console.log('');
  console.log('  see it work in 30 seconds:');
  console.log('    rabadon drill        one tagged test event through the real gate');
  console.log('    rabadon usage        the ledger — drills excluded by design');
  console.log('');
  console.log('  from here:');
  console.log(`    claude               work normally in ${dir === os.homedir() ? 'any project' : dir} — the session is supervised`);
  console.log('    rabadon on|off       enforce, or pause to watch-only');
  console.log('    rabadon remove       take it all back out (add --global here if you used it)');
  console.log('');
  console.log('  disable exactly one rule with  "disabled": ["<rule-id>"]  in .rabadon/guard.json.');
  process.exit(0);
}

function cmdRemove(args) {
  const global = args.includes('--global');
  const purge = args.includes('--purge');
  const posArg = args.find((a) => !a.startsWith('-'));
  const dir = global ? os.homedir() : (posArg ? path.resolve(posArg) : process.cwd());

  let r;
  try { r = removeHooks(dir); }
  catch (e) {
    console.error(`rabadon remove: ${path.join(dir, '.claude', 'settings.json')} could not be parsed (${e.message}) — left untouched.`);
    process.exit(1);
  }
  if (r.changed) {
    console.log(`rabadon remove: stripped ${r.removed.length} rabadon hook(s) from ${r.settingsPath}`);
    for (const x of r.removed) console.log(`    - ${x}`);
    console.log(`  (original backed up: ${path.basename(r.settingsPath)}.bak-rabadon)`);
  } else {
    console.log(`rabadon remove: no rabadon hooks found in ${r.settingsPath} — nothing to strip.`);
  }

  if (purge) {
    const rd = path.join(dir, '.rabadon');
    if (fs.existsSync(rd)) { fs.rmSync(rd, { recursive: true, force: true }); console.log(`  purged ${rd}`); }
  }
  console.log('');
  console.log('  the ledger at ~/.rabadon/spool is yours and was left in place.');
  console.log('  fully uninstall the CLI with:  npm rm -g rabadon');
  process.exit(0);
}

function pkgVersion() {
  try { return JSON.parse(fs.readFileSync(path.join(PKG_ROOT, 'package.json'), 'utf8')).version; }
  catch { return '?'; }
}

function cmdDoctor() {
  let problems = 0;
  const ok = (s) => console.log(`  ok   ${s}`);
  const warn = (s) => { console.log(`  WARN ${s}`); problems++; };

  console.log(`rabadon doctor — ${PKG_ROOT}`);
  console.log('');

  // 1) binaries — the subject list comes from the Makefile (see coreBinaries in
  //    install.mjs), so a binary added to the build is one doctor checks for.
  const core = missingCore();
  if (core.names.length === 0) {
    // An empty subject list would make every check below vacuous — "nothing
    // absent" out of "nothing looked at" is the same false green by another
    // route, so it is a problem, not a pass.
    warn(`cannot tell what the native core is: no binary targets found in ${core.makefile}`);
    console.log('       doctor cannot certify this install — reinstall the package (npm i -g rabadon)');
  } else {
    const missing = core.missing;
    if (missing.length === 0) ok(`native core built (${core.names.length}/${core.names.length} binaries)`);
    else {
      warn(`native core INCOMPLETE: ${missing.length} of ${core.names.length} binaries absent`);
      for (let i = 0; i < missing.length; i += 4)
        console.log(`         absent: ${missing.slice(i, i + 4).join('  ')}`);
      console.log('       each one is a command that fails when you run it, not when you install it');
      const cxx = ['clang++', 'g++', 'c++'].find((c) => spawnSync(c, ['--version'], { stdio: 'ignore' }).status === 0);
      console.log(cxx
        ? `       build them: (cd ${PKG_ROOT} && make)`
        : `       no C++ compiler found — install one first:\n         macOS: xcode-select --install\n         debian: sudo apt install g++ make`);
    }
  }

  // 2) version lockstep
  if (fs.existsSync(GATE_BIN)) {
    const v = (spawnSync(GATE_BIN, ['--version'], { encoding: 'utf8' }).stdout || '').trim();
    const pv = `rabadon-gate ${pkgVersion()}`;
    if (v === pv) ok(`version ${pkgVersion()} (binary matches package.json)`);
    else warn(`version drift: binary says "${v}", package.json says "${pkgVersion()}" — rebuild (make)`);
  }

  // 3) sandbox backend
  if (fs.existsSync(nativeBin('rabadon-sandbox'))) {
    const sc = spawnSync(nativeBin('rabadon-sandbox'), ['--check'], { encoding: 'utf8' });
    if (sc.status === 0) ok((sc.stdout || '').trim().replace(/^rabadon sandbox:\s*/, 'kernel sandbox: '));
    else warn('no kernel sandbox backend (rabadon exec falls back to hook-only enforcement)');
  }

  // 4) claude CLI (guard authoring + repair proposer)
  if (hasClaude()) ok('claude CLI present (guard authoring + repair proposer available)');
  else warn('claude CLI not found — `rabadon guard`/`rabadon repair` need it; deny rules still work without it');

  // 5) global hooks health: every rabadon hook command points at a file that exists
  const gs = path.join(os.homedir(), '.claude', 'settings.json');
  if (fs.existsSync(gs)) {
    try {
      const s = JSON.parse(fs.readFileSync(gs, 'utf8'));
      const cmds = new Set();
      const walk = (o) => { if (Array.isArray(o)) o.forEach(walk); else if (o && typeof o === 'object') { if (o.command && RABADON_CMD_RE.test(o.command)) cmds.add(o.command); Object.values(o).forEach(walk); } };
      walk(s.hooks || {}); if (s.statusLine) walk(s.statusLine);
      if (cmds.size === 0) console.log('  info global settings has no rabadon hooks (run `rabadon init --global`)');
      else {
        const dead = [...cmds].filter((c) => { const bin = c.split(' ')[0]; return !fs.existsSync(bin); });
        if (dead.length === 0) ok(`global hooks healthy (${cmds.size} rabadon command(s), all present)`);
        else { warn(`global hooks point at ${dead.length} missing path(s) — run \`rabadon init --global\` to repair`); dead.forEach((d) => console.log(`         ${d}`)); }
      }
    } catch { warn(`global settings.json is not valid JSON (${gs})`); }
  }

  // 6) spool size + retention
  const spool = path.join(process.env.RABADON_DIR || path.join(os.homedir(), '.rabadon'), 'spool');
  if (fs.existsSync(spool)) {
    let bytes = 0, files = 0;
    for (const f of fs.readdirSync(spool)) { if (f.endsWith('.jsonl')) { bytes += fs.statSync(path.join(spool, f)).size; files++; } }
    const keep = process.env.RABADON_SPOOL_DAYS || '30';
    ok(`ledger: ${files} day-file(s), ${(bytes / 1024 / 1024).toFixed(1)} MB (retention: ${keep} days, pruned on session start)`);
  }

  console.log('');
  console.log(problems === 0 ? '  all green.' : `  ${problems} thing(s) to look at above.`);
  process.exit(problems === 0 ? 0 : 1);
}

const [verb, ...rest] = process.argv.slice(2);
if (verb === 'init') await cmdInit(rest);
else if (verb === 'remove' || verb === 'uninstall') cmdRemove(rest);
else if (verb === 'doctor') cmdDoctor();
else { console.error(`rabadon manage: unknown verb "${verb}"`); process.exit(2); }
