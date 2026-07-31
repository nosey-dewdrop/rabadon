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
// gate runs on every tool call, native decides in 2.3ms (BENCHMARK.md), a node
// shim is 50-80ms cold, npx is worse and fragile. The path is resolved from
// THIS file's location, so it is correct for npm -g, npm link, and git clones
// alike.
//
// Used by `rabadon init` (one project) and `rabadon fleet` (all of them) —
// one merge implementation, not two that drift apart.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PKG_DIR = path.resolve(HERE, '..');

// Where a native binary actually is. `npm i -g rabadon` — the paved road, the
// one line of the README everybody runs — does NOT put the binaries in
// <pkg>/native. It puts them in the prebuilt platform package, which npm places
// either under this package's node_modules or hoisted as a sibling. This file
// knew only <pkg>/native, so on a prebuilt install `rabadon doctor` reported
// "native binaries missing" with all sixteen sitting right there, `rabadon init`
// exited 3 and wrote no hooks at all, and nothing was ever guarded. Proven by
// packing both tarballs and installing them into a clean prefix, 31.07.
//
// native/rabadon-cli.sh already resolved all three locations; the JS half is
// what disagreed with it. Both now answer the same question the same way, and
// the order is the same: a local build wins, because someone who ran `make` in
// a clone means the thing they just compiled.
const PLATFORM = (() => {
  const o = { darwin: 'darwin', linux: 'linux' }[process.platform];
  const c = { arm64: 'arm64', x64: 'x64' }[process.arch];
  return o && c ? `${o}-${c}` : null;
})();

export const NATIVE_DIRS = [
  path.join(PKG_DIR, 'native'),
  ...(PLATFORM
    ? [path.join(PKG_DIR, 'node_modules', '@rabadon', PLATFORM),
       path.resolve(PKG_DIR, '..', '@rabadon', PLATFORM)]
    : []),
];

// The resolved path of one native binary, or — when it exists nowhere — the
// source-build path, which is the one every "not built yet" message should name.
export function nativeBin(name) {
  for (const d of NATIVE_DIRS) {
    const p = path.join(d, name);
    if (fs.existsSync(p)) return p;
  }
  return path.join(NATIVE_DIRS[0], name);
}

export const NATIVE_DIR = NATIVE_DIRS[0];
export const GATE_BIN = nativeBin('rabadon-gate');
export const DRIFT_BIN = nativeBin('rabadon-drift');
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

// Claude Code's hook `timeout` is SECONDS (default 600). Two hooks, two
// ceilings, because they do two different jobs — and each ceiling sits ABOVE
// the gate's own internal cap on purpose. If the outer timeout fires first the
// fail-closed promise decays into an unattributed kill: the action is neither
// allowed with a verdict nor refused with a reason. rabadon's own bounded
// timer has to be the one that wins.
//   PreToolUse   2.3ms for an ordinary call, but the push-gate branch RUNS the
//                project's suite before it opens (native/gate.cpp, pushGate
//                .timeoutSec, default 900s) — 960 leaves that timer first.
//   PostToolUse  no suite, but the incident brain is a bounded `claude -p`
//                capped at 90s — 120 leaves that timer first.
const PRE_TIMEOUT_SEC = 960;
const POST_TIMEOUT_SEC = 120;

function desiredHooks(gateCmd, driftCmd) {
  const bare = { hooks: [{ type: 'command', command: gateCmd }] };
  const matched = (timeout) => ({ matcher: TOOL_MATCHER, hooks: [{ type: 'command', command: gateCmd, timeout }] });
  return {
    SessionStart: [bare],
    UserPromptSubmit: [bare],
    Stop: [bare, { hooks: [{ type: 'command', command: driftCmd }] }],
    PreToolUse: [matched(PRE_TIMEOUT_SEC)],
    PostToolUse: [matched(POST_TIMEOUT_SEC)],
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
