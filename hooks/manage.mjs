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
import { installHooks, installCursorHooks, removeHooks, removeCursorHooks, missingSubscriptions, GATE_BIN, DRIFT_BIN, nativeBin, missingCore, NATIVE_DIRS, RABADON_CMD_RE } from './install.mjs';

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
  // OFF ON A FIRST INSTALL, and the number is the reason. red-base refuses any
  // action while the project's own suite is red — the product's core story,
  // and its worst-behaved rule on 29 days of real traffic: 65 refusals across
  // only 13 sessions and 6 days (26 in one day, 17 in one session), a 15 %
  // operator-declared wrong rate, and a suite that went green again within 25
  // events in 7 of the 65. That is not a guard firing on distinct mistakes; it
  // is a rule that can jam a debugging session in a loop, which is how a tool
  // gets uninstalled by lunch on day one.
  //
  // It stays compiled in and one word away: delete the id from `disabled` when
  // you want work to stop while the base is red. Shipping it ON by default and
  // letting a stranger discover it mid-debug is the trade this project is not
  // willing to make.
  disabled: ['red-base'],
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

  // 1b) the repair arm's consent, decided ONCE, here — R5.
  //
  // A tool that asks before every action is a tool whose question gets answered
  // "yes" without being read, so the repair arm's permission is a POLICY in
  // rabadon's home rather than a prompt at signal time. It is deliberately not
  // asked interactively: `rabadon init` has to produce a working install with
  // no questions asked, and the default it writes — "ask" — cannot spend a cent
  // on its own. Changing it is one line in one file, and that file is named on
  // the way out.
  //
  // Home, not the project: "may rabadon call a model while I am asleep" is a
  // fact about the operator, not about a repo, and it must not change because
  // you cloned something that ships a config.
  const rbHome = process.env.RABADON_DIR || path.join(os.homedir(), '.rabadon');
  const cfgFile = path.join(rbHome, 'config.json');
  let repairMode = 'ask';
  try {
    fs.mkdirSync(rbHome, { recursive: true });
    if (fs.existsSync(cfgFile)) {
      // never overwrite a decision the operator already made
      const cur = JSON.parse(fs.readFileSync(cfgFile, 'utf8'));
      repairMode = (cur.repair && cur.repair.mode) || 'ask';
      if (!cur.repair || !cur.repair.mode) {
        cur.repair = { ...(cur.repair || {}), mode: 'ask' };
        fs.writeFileSync(cfgFile, JSON.stringify(cur, null, 2) + '\n');
      }
    } else {
      fs.writeFileSync(cfgFile, JSON.stringify({ repair: { mode: 'ask' } }, null, 2) + '\n');
    }
  } catch (e) {
    // a policy that could not be written is no reason to leave the project
    // unguarded — but it must never read as "written". With no file the arm
    // falls back to "ask", which is the same safe answer.
    console.error(`rabadon init: could not write ${cfgFile} (${e.message}) — the repair arm stays on "ask".`);
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
  console.log(`    ${cfgFile}   — repair.mode = "${repairMode}"  (ask | auto-propose | off)`);
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
  console.log('');
  console.log('  the repair arm (the one place rabadon may call a model), set once, in config.json:');
  console.log('    "ask"           default. one line when the same error survives a third different');
  console.log('                    move after two hints; it runs on `rabadon repair --approve`.');
  console.log('    "auto-propose"  for unattended runs. runs without asking and NEVER touches your');
  console.log('                    tree — the patch waits at .rabadon/repair-<ts>.patch until you');
  console.log('                    type `rabadon repair --apply`.');
  console.log('    "off"           the arm is not there. the signals still reach the ledger.');
  // THE LAST THING ON THE SCREEN, and the three questions every rabadon message
  // answers: what state you are in, why it is that state, and the ONE command
  // that comes next. Everything above named the two commands that CHANGE the
  // mode and never said which mode this install is standing in — so somebody who
  // follows the README to the letter ends up with a guard that refuses nothing
  // and a screen that says "done". A guard whose own installer prints a green it
  // has not earned is the failure this product exists to refuse.
  //
  // `rabadon on` is not run here on purpose: the default stays watch, and the
  // operator turns enforcement on themselves, once they have seen what it would
  // have refused.
  console.log('');
  console.log('  right now: WATCH — every action is recorded and nothing is refused.');
  console.log('             watch is the default: the rules prove themselves on your own');
  console.log('             work first, and enforcing is your call, not ours.');
  console.log('  next:      rabadon on       start refusing (rabadon off returns to watch)');
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

  // the OTHER file init wrote. Stripping .claude only meant a Cursor user ran
  // the command the install screen calls "take it all back out" and stayed
  // wired on all five events — with a success message on their screen. Same
  // shape of line as the .claude half: which file, and what came out of it.
  const cr = removeCursorHooks(dir);
  if (cr.changed) {
    console.log(`rabadon remove: stripped ${cr.removed.length} rabadon hook(s) from ${cr.hooksPath}${cr.deleted ? ' — the file held nothing else, so it is gone' : ''}`);
    for (const x of cr.removed) console.log(`    - ${x}`);
  } else if (fs.existsSync(cr.hooksPath)) {
    console.log(`rabadon remove: no rabadon hooks found in ${cr.hooksPath} — nothing to strip.`);
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

function pkgJson() {
  try { return JSON.parse(fs.readFileSync(path.join(PKG_ROOT, 'package.json'), 'utf8')); }
  catch { return {}; }
}
function pkgVersion() { return pkgJson().version || '?'; }

// realpath or the path itself: /tmp vs /private/tmp, npm-bin symlinks, and a
// clone reached through a symlinked home all make two spellings of one file,
// and "is this mine" is a question about the file, not about the spelling.
function realOr(p) { try { return fs.realpathSync(p); } catch { return p; } }
const isUnder = (p, root) => p === root || p.startsWith(root + path.sep);

function cmdDoctor() {
  let problems = 0;
  const ok = (s) => console.log(`  ok   ${s}`);
  const warn = (s) => { console.log(`  WARN ${s}`); problems++; };
  // Every WARN answers three questions or it is a line that sends a stranger to
  // the issue tracker: WHAT happened (the warn text), WHY it matters, and the
  // ONE command to run next.
  const why = (s) => console.log(`       why:  ${s}`);
  const run = (s) => console.log(`       run:  ${s}`);

  console.log(`rabadon doctor — ${PKG_ROOT}`);
  console.log('');

  // 0) the node that runs the hooks, against the floor package.json declares.
  //    Read from engines.node, never typed here — one place says what is
  //    supported, and it is the same one npm reads. This is first because
  //    everything below runs under it: a node under the floor does not fail at
  //    install time, it fails at the first tool call of a live session, and a
  //    hook that cannot start is a session that is not being guarded at all.
  const eng = (pkgJson().engines || {}).node;
  if (eng) {
    const m = String(eng).match(/(\d+)/);
    const floor = m ? Number(m[1]) : null;
    const cur = Number(process.versions.node.split('.')[0]);
    if (floor !== null && cur < floor) {
      warn(`node ${process.versions.node} is below engines.node "${eng}" — this install needs node ${floor} or newer`);
      why('the hooks run under THIS node on every tool call; below the floor they die mid-session and the gate goes quiet while the install still looks fine');
      run(`nvm install ${floor} && nvm use ${floor}   (or upgrade node system-wide, then re-run: rabadon doctor)`);
    } else {
      ok(`node ${process.versions.node} (satisfies engines.node "${eng}")`);
    }
  }

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

    // 1b) present is not the same as runnable. A tarball unpacked without the
    //     mode bits, a hostile umask, a copy through a filesystem that drops
    //     the x bit: the file IS there, so every "is it missing" check above
    //     passes and the failure waits for the first person to run it.
    const noexec = core.names.map(nativeBin).filter((p) => {
      if (!fs.existsSync(p)) return false;
      try { fs.accessSync(p, fs.constants.X_OK); return false; } catch { return true; }
    });
    if (noexec.length) {
      warn(`${noexec.length} native binary/binaries present but not executable`);
      for (const p of noexec) console.log(`         ${p}`);
      why('nothing reports them missing — the file exists — so this install passes every "is it there" check and fails only when the command is actually run');
      run(`chmod +x ${noexec.join(' ')}`);
    }
  }

  // 2) version lockstep — and the other half of the permission class: a binary
  //    the OS itself refuses to execute (quarantine on macOS, a mode the file
  //    system reports one way and enforces another, a wrong-arch download).
  //    Only the gate is probed: it runs on every tool call, and doctor must not
  //    start sixteen processes to answer a question about one.
  if (fs.existsSync(GATE_BIN)) {
    const r = spawnSync(GATE_BIN, ['--version'], { encoding: 'utf8' });
    if (r.error) {
      warn(`${path.basename(GATE_BIN)} is on disk but the OS refused to run it (${r.error.code || r.error.message}) — not executable here`);
      why('a downloaded binary can be quarantined or carry the wrong architecture; the gate then fails to start on every tool call, which reads as "rabadon does nothing"');
      run(process.platform === 'darwin'
        ? `xattr -dr com.apple.quarantine ${PKG_ROOT} && chmod +x ${GATE_BIN}`
        : `chmod +x ${GATE_BIN}`);
    } else {
      const v = (r.stdout || '').trim();
      const pv = `rabadon-gate ${pkgVersion()}`;
      if (v === pv) ok(`version ${pkgVersion()} (binary matches package.json)`);
      else warn(`version drift: binary says "${v}", package.json says "${pkgVersion()}" — rebuild (make)`);
    }
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

  // 4b) which `rabadon` the user actually types. Everything doctor prints is
  //     about THIS tree; if the command on PATH is another one, the whole report
  //     describes an install nobody runs. Two shapes, both common: an old
  //     `npm i -g` left beside a fresh clone (two on PATH), and a PATH entry
  //     that points somewhere else entirely (one, foreign).
  const mineRoot = realOr(PKG_ROOT);
  const onPath = [];
  for (const d of (process.env.PATH || '').split(path.delimiter)) {
    if (!d) continue;
    const p = path.join(d, 'rabadon');
    try { fs.accessSync(p, fs.constants.X_OK); } catch { continue; }
    const real = realOr(p);
    if (!onPath.some((s) => s.real === real)) onPath.push({ p, real });
  }
  if (onPath.length === 0) {
    console.log('  info no `rabadon` on PATH — this tree works when called by full path (npm i -g adds the short one)');
  } else if (onPath.length > 1) {
    warn(`${onPath.length} different \`rabadon\` commands on your PATH — the one that runs is ${onPath[0].p}`);
    for (const s of onPath) console.log(`         ${s.p}${s.real !== s.p ? ` -> ${s.real}` : ''}`);
    why('two installs means the version you type, the rules it reads and the binary it runs can all differ from the tree you are looking at — including this report');
    run(`npm rm -g rabadon && npm i -g ${PKG_ROOT}   (leaves exactly one, this one)`);
  } else if (!isUnder(onPath[0].real, mineRoot)) {
    warn(`the \`rabadon\` on your PATH is a different install — ${onPath[0].real}, not this one (${PKG_ROOT})`);
    why('what you type is not what you built: changes, rebuilds and guard edits here never reach the command your shell actually runs');
    run(`npm i -g ${PKG_ROOT}   (points the short command at this tree)`);
  } else {
    ok(`\`rabadon\` on PATH is this install (${onPath[0].p})`);
  }

  // 5) global hooks health: every rabadon hook command points at a file that
  //    exists AND belongs to this install.
  const gs = path.join(os.homedir(), '.claude', 'settings.json');
  if (fs.existsSync(gs)) {
    try {
      const s = JSON.parse(fs.readFileSync(gs, 'utf8'));
      const cmds = new Set();
      const walk = (o) => { if (Array.isArray(o)) o.forEach(walk); else if (o && typeof o === 'object') { if (o.command && RABADON_CMD_RE.test(o.command)) cmds.add(o.command); Object.values(o).forEach(walk); } };
      walk(s.hooks || {}); if (s.statusLine) walk(s.statusLine);
      if (cmds.size === 0) console.log('  info global settings has no rabadon hooks (run `rabadon init --global`)');
      else {
        // A hook command is an ABSOLUTE path, written once and never revisited.
        // Two ways a previous install survives in it: the path is gone (dead),
        // or the path still resolves — into somebody else's tree (stale). The
        // second one is the silent one: nothing is missing, so a check that only
        // asks "does this file exist" certifies it.
        const roots = [mineRoot, ...NATIVE_DIRS.map(realOr)];
        const dead = [], stale = [];
        for (const c of cmds) {
          const bin = c.split(' ')[0];
          if (!fs.existsSync(bin)) { dead.push(bin); continue; }
          const r = realOr(bin);
          if (!roots.some((root) => isUnder(r, root))) stale.push(bin);
        }
        // ...and a third way, the one both of those miss: the paths are all
        // current and the EVENT SET is old. Measured 2026-08-29 on this
        // machine — the file was written 26 Aug, the binary had learned
        // PostToolUseFailure that morning, and doctor said "all green" at an
        // install that could not see a single failing command. `shipped but
        // not installed` is invisible to any check that only follows paths.
        const missingSubs = missingSubscriptions(gs) || [];
        if (dead.length === 0 && stale.length === 0 && missingSubs.length === 0)
          ok(`global hooks healthy (${cmds.size} rabadon command(s), all from this install)`);
        if (missingSubs.length) {
          warn(`${missingSubs.length} subscription(s) this install writes are NOT registered — the settings file is older than the binary`);
          missingSubs.forEach((m) => console.log(`         ${m}`));
          why('the agent only delivers events you are subscribed to, so anything rabadon learned since this file was written never reaches it — the repo is fixed and this machine is not');
          run('rabadon init --global   (re-registers them; the file is backed up first, and a session start does it on its own)');
        }
        if (dead.length) {
          warn(`${dead.length} global hook command(s) point at a path that does not exist — a removed install's leftovers`);
          dead.forEach((d) => console.log(`         ${d}`));
          why('Claude Code runs these on every tool call and gets nothing back, so the session looks supervised and is not');
          run('rabadon init --global   (rewrites the rabadon entries; the file is backed up first)');
        }
        if (stale.length) {
          warn(`${stale.length} global hook command(s) belong to a different rabadon install`);
          stale.forEach((d) => console.log(`         ${d}`));
          why('left behind by an earlier install: your sessions run THAT tree\'s binary, THAT tree\'s version and THAT tree\'s rules, so nothing you fix or upgrade here reaches them');
          run('rabadon init --global   (repoints the rabadon entries at this install; the file is backed up first)');
        }
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
