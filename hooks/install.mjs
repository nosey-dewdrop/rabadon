// rabadon hooks/install — merge the gate into a project's Claude Code
// settings WITHOUT clobbering anything that is already there.
//
// Every real Claude Code user already has a .claude/settings.json. An
// installer that bails (or worse, overwrites) on that file fails exactly the
// people it is for. Law here:
//   - existing hooks, permissions, everything: PRESERVED — gate entries are
//     APPENDED alongside them;
//   - before the first rabadon write to an existing file, a .bak-rabadon
//     copy is made;
//   - already installed -> no-op, reported as { changed: false } (idempotent);
//   - a statusLine is only set if the project has none.
//
// Used by `rabadon init` (one project) and `rabadon fleet` (all of them) —
// one merge implementation, not two that drift apart.

import fs from 'node:fs';
import path from 'node:path';

const HERE = path.dirname(new URL(import.meta.url).pathname);
export const GATE_PATH = path.resolve(path.join(HERE, 'gate.mjs'));
export const BIN_PATH = path.resolve(path.join(HERE, '..', 'bin', 'rabadon.mjs'));

/**
 * Merge the rabadon gate hooks into <dir>/.claude/settings.json.
 * @returns {{ settingsPath: string, changed: boolean, backedUp: boolean }}
 */
export function installHooks(dir, { gateCmd = `node ${GATE_PATH}`, statuslineCmd = `node ${BIN_PATH} statusline` } = {}) {
  const settingsPath = path.join(dir, '.claude', 'settings.json');
  let settings = {};
  let existed = false;
  if (fs.existsSync(settingsPath)) {
    existed = true;
    settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); // a corrupt file throws — caller decides, we never overwrite what we cannot read
  }

  if (JSON.stringify(settings.hooks || {}).includes('gate.mjs')) {
    return { settingsPath, changed: false, backedUp: false };
  }

  let backedUp = false;
  if (existed) {
    fs.copyFileSync(settingsPath, settingsPath + '.bak-rabadon');
    backedUp = true;
  } else {
    fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
  }

  settings.hooks = settings.hooks || {};
  const entry = { hooks: [{ type: 'command', command: gateCmd }] };
  const matched = { matcher: 'Bash|Edit|Write|MultiEdit|NotebookEdit', hooks: [{ type: 'command', command: gateCmd, timeout: 900 }] };
  for (const evName of ['SessionStart', 'UserPromptSubmit', 'Stop']) {
    settings.hooks[evName] = [...(settings.hooks[evName] || []), entry];
  }
  for (const evName of ['PreToolUse', 'PostToolUse']) {
    settings.hooks[evName] = [...(settings.hooks[evName] || []), matched];
  }
  if (!settings.statusLine) settings.statusLine = { type: 'command', command: statuslineCmd };

  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');

  // .rabadon/state.json is per-machine session state — never someone's diff noise
  try {
    const gi = path.join(dir, '.gitignore');
    const cur = fs.existsSync(gi) ? fs.readFileSync(gi, 'utf8') : '';
    if (!cur.includes('.rabadon/state.json')) fs.appendFileSync(gi, '\n.rabadon/state.json\n');
  } catch { /* a read-only gitignore must not stop the install */ }

  return { settingsPath, changed: true, backedUp };
}

export default { installHooks, GATE_PATH, BIN_PATH };
