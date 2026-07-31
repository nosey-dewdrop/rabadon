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
//   - already installed AND healthy -> no-op, reported as { changed: false };
//   - already installed but pointing at a dead or different location -> the
//     rabadon entries (and only those) are rewritten in place: install REPAIRS;
//   - a statusLine is only set if the project has none (a rabadon-owned
//     statusLine pointing elsewhere is repaired like a hook);
//   - removeHooks() strips exactly what installHooks() writes — uninstall is a
//     first-class operation, not manual settings surgery.
//
// The commands written are the NATIVE binaries by absolute install path: the
// gate runs on every tool call inside a 900ms hook budget — native is ~1ms,
// a node shim is 50-80ms cold, npx is worse and fragile. The path is resolved
// from THIS file's location, so it is correct for npm -g, npm link, and git
// clones alike.
//
// Used by `rabadon init` (one project) and `rabadon fleet` (all of them) —
// one merge implementation, not two that drift apart.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const NATIVE_DIR = path.resolve(HERE, '..', 'native');
export const GATE_BIN = path.join(NATIVE_DIR, 'rabadon-gate');
export const DRIFT_BIN = path.join(NATIVE_DIR, 'rabadon-drift');
// legacy JS gate path — still recognized (and replaced) when found in settings
export const GATE_PATH = path.join(HERE, 'gate.mjs');
export const BIN_PATH = path.resolve(HERE, '..', 'bin', 'rabadon.mjs');

// One definition of "this is ours": every command rabadon has ever written
// into a settings.json, past (JS gate, mjs statusline) and present (native).
export const RABADON_CMD_RE = /rabadon-(gate|drift)|rabadon[\\/]hooks[\\/]gate\.mjs|rabadon\.mjs['" ]+statusline/;

// PreToolUse/PostToolUse cover EVERY tool — Bash and file edits, but also MCP
// tools, Task/subagents, notebooks. The gate ignores what it has no law for;
// coverage is decided here, policy is decided in guard.json.
const TOOL_MATCHER = '*';

const isOurs = (cmd) => typeof cmd === 'string' && RABADON_CMD_RE.test(cmd);

function stripOurs(settings) {
  // Remove every rabadon-owned hook command; drop entries/events left empty.
  const removed = [];
  const hooks = settings.hooks || {};
  for (const evName of Object.keys(hooks)) {
    if (!Array.isArray(hooks[evName])) continue;
    hooks[evName] = hooks[evName]
      .map((entry) => {
        if (!entry || !Array.isArray(entry.hooks)) return entry;
        const kept = entry.hooks.filter((h) => {
          const ours = h && h.type === 'command' && isOurs(h.command);
          if (ours) removed.push(`${evName}: ${h.command}`);
          return !ours;
        });
        return kept.length === entry.hooks.length ? entry : { ...entry, hooks: kept };
      })
      .filter((entry) => !entry || !Array.isArray(entry.hooks) || entry.hooks.length > 0);
    if (hooks[evName].length === 0) delete hooks[evName];
  }
  if (settings.statusLine && isOurs(settings.statusLine.command)) {
    removed.push(`statusLine: ${settings.statusLine.command}`);
    delete settings.statusLine;
  }
  return removed;
}

function desiredHooks(gateCmd, driftCmd) {
  const bare = { hooks: [{ type: 'command', command: gateCmd }] };
  const matched = { matcher: TOOL_MATCHER, hooks: [{ type: 'command', command: gateCmd, timeout: 900 }] };
  return {
    SessionStart: [bare],
    UserPromptSubmit: [bare],
    Stop: [bare, { hooks: [{ type: 'command', command: driftCmd }] }],
    PreToolUse: [matched],
    PostToolUse: [matched],
  };
}

function readSettings(settingsPath) {
  if (!fs.existsSync(settingsPath)) return { settings: {}, existed: false };
  // a corrupt file throws — caller decides, we never overwrite what we cannot read
  return { settings: JSON.parse(fs.readFileSync(settingsPath, 'utf8')), existed: true };
}

/**
 * Merge the rabadon gate hooks into <dir>/.claude/settings.json.
 * Pass os.homedir() as dir to target the user-global settings.
 * @returns {{ settingsPath: string, changed: boolean, backedUp: boolean, repaired: boolean }}
 */
export function installHooks(dir, { gateCmd = GATE_BIN, driftCmd = DRIFT_BIN, statuslineCmd = `${GATE_BIN} --statusline` } = {}) {
  const settingsPath = path.join(dir, '.claude', 'settings.json');
  const { settings, existed } = readSettings(settingsPath);

  // Healthy = our entries are present exactly as we would write them today,
  // and the binary they point at exists. Anything else gets repaired.
  const want = desiredHooks(gateCmd, driftCmd);
  const currentHooksJson = JSON.stringify(settings.hooks || {});
  const healthy =
    Object.entries(want).every(([evName, entries]) =>
      entries.every((e) => (settings.hooks?.[evName] || []).some((x) => JSON.stringify(x) === JSON.stringify(e)))) &&
    fs.existsSync(gateCmd.split(' ')[0]);
  if (healthy) return { settingsPath, changed: false, backedUp: false, repaired: false };

  let backedUp = false;
  if (existed) {
    fs.copyFileSync(settingsPath, settingsPath + '.bak-rabadon');
    backedUp = true;
  } else {
    fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
  }

  const hadOurs = RABADON_CMD_RE.test(currentHooksJson) || (settings.statusLine && isOurs(settings.statusLine.command));
  stripOurs(settings); // repair = strip our old entries, then append fresh ones

  settings.hooks = settings.hooks || {};
  for (const [evName, entries] of Object.entries(want)) {
    settings.hooks[evName] = [...(settings.hooks[evName] || []), ...entries];
  }
  if (!settings.statusLine) settings.statusLine = { type: 'command', command: statuslineCmd };

  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');

  // .rabadon/state.json is per-machine session state — never someone's diff
  // noise. Skipped for the global target: ~/.gitignore is not ours to touch.
  if (path.resolve(dir) !== path.resolve(os.homedir())) {
    try {
      const gi = path.join(dir, '.gitignore');
      const cur = fs.existsSync(gi) ? fs.readFileSync(gi, 'utf8') : '';
      if (!cur.includes('.rabadon/state.json')) fs.appendFileSync(gi, '\n.rabadon/state.json\n');
    } catch { /* a read-only gitignore must not stop the install */ }
  }

  return { settingsPath, changed: true, backedUp, repaired: !!hadOurs };
}

/**
 * Strip every rabadon-owned hook and statusLine from <dir>/.claude/settings.json.
 * Pass os.homedir() as dir to target the user-global settings.
 * @returns {{ settingsPath: string, changed: boolean, removed: string[] }}
 */
export function removeHooks(dir) {
  const settingsPath = path.join(dir, '.claude', 'settings.json');
  const { settings, existed } = readSettings(settingsPath);
  if (!existed) return { settingsPath, changed: false, removed: [] };

  const removed = stripOurs(settings);
  if (removed.length === 0) return { settingsPath, changed: false, removed };

  fs.copyFileSync(settingsPath, settingsPath + '.bak-rabadon');
  if (settings.hooks && Object.keys(settings.hooks).length === 0) delete settings.hooks;
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');
  return { settingsPath, changed: true, removed };
}

export default { installHooks, removeHooks, GATE_BIN, DRIFT_BIN, NATIVE_DIR, GATE_PATH, BIN_PATH, RABADON_CMD_RE };
