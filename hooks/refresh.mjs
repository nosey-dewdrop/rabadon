// rabadon hooks/refresh — THE UPGRADE PATH FOR A MACHINE THAT IS ALREADY
// INSTALLED.
//
// The most expensive defect class this product can have is "shipped but not
// installed": a repair lands in the repo, every suite is green, and the
// machines that already run rabadon never receive it. Measured on 2026-08-29:
// hooks/install.mjs had been subscribing to PostToolUseFailure since that
// morning, and this machine's ~/.claude/settings.json — written 26 Aug 20:17
// and never rewritten — still subscribed to five events. So a Bash call that
// exited non-zero produced STEP_START and no STEP_OK, no err_sig, and the
// "same error came back" signal the product exists for could not fire. The
// binary was new; the subscription was three days old. Nothing in the product
// noticed, because nothing in the product ever looked.
//
// `rabadon init` already repairs it — installHooks() computes `healthy` against
// what it would write TODAY, so a missing event makes it rewrite. The hole was
// never the merge; it was that nobody re-runs the installer. An upgrade path
// that depends on the user knowing to re-run it is not an upgrade path.
//
// So the gate calls this file at SessionStart, and it is deliberately the
// smallest thing that can close that gap:
//
//   - it refreshes ONLY settings files that ALREADY contain rabadon entries.
//     Self-healing must never become self-installing: a project the user chose
//     not to guard stays unguarded, and a machine where rabadon was removed
//     stays removed.
//   - it calls installHooks(), the ONE settings-merge implementation, so the
//     upgrade can never drift from the install. Every future event added to
//     desiredHooks() reaches every installed machine by this same path, with
//     no second list to keep in sync.
//   - it reports what changed, per event, on stdout. A tool that rewrites the
//     user's settings.json behind their back and says nothing is worse than
//     one that is stale (Promise 1: it never goes quiet).
//   - it never throws and always exits 0. This runs inside a hook; a refresh
//     that fails must cost the session nothing.
//
// Not a product verb: there is no `rabadon refresh` and the five-verb ceiling
// (native/cli_test.sh) is untouched. This is an internal entry point the gate
// spawns, in the same way it spawns rabadon-truth.

// WHAT THIS FILE GOT WRONG, MEASURED 2026-08-30, AND WHAT IT COST.
//
// installHooks() writes the absolute path of WHICHEVER BINARY IS RUNNING —
// install.mjs resolves GATE_BIN from its own location, which is correct for an
// installer (you are installing the thing you just unpacked) and catastrophic
// for a self-heal (you are upgrading somebody else's install, from a copy).
// The arbiter reproduced it deterministically: a rabadon-gate compiled in a
// throwaway `git worktree`, one SessionStart, a decoy HOME already pointing at
// the canonical clone — and six hook entries plus rabadon-drift moved to the
// worktree's paths. Remove the worktree and the operator's brake names a file
// that does not exist. It stayed that way for days and cost her ten hours.
//
// The whole diagnosis is one sentence: THE SIX POISONED ENTRIES EACH NEEDED A
// NEW EVENT AND NONE OF THEM NEEDED A NEW ADDRESS. An upgrade is about events.
// So:
//
//   1. a registered rabadon command whose binary EXISTS is carried through
//      verbatim, whoever is running. Self-heal adds subscriptions; it does not
//      relocate installs.
//   2. the one case that must write an address — the registered binary is gone,
//      so the install is already dead — writes the canonical install path, and
//      ONLY if that path is durable. A copy under a git worktree or under the
//      temp directory is refused, out loud, with the command that repairs it.
//      Writing it would hand the user a hook that dies silently tomorrow, which
//      Promise 1 forbids and which is exactly the damage above.
//   3. every repoint is announced with its OLD and NEW address. The old line
//      said "repointed its entries" only when `added.length` was 0; in the
//      field both happened at once, so the destructive half printed NOTHING.
//   4. what it writes, it verifies: a command left naming an absent binary is
//      reported rather than left to be discovered by a session going quiet.
//
// Pinned by native/selfheal_path_test.sh against the real shipped binary.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { installHooks, RABADON_CMD_RE, GATE_BIN, DRIFT_BIN } from './install.mjs';

const PKG_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// WHY A PATH MAY NOT BE WRITTEN INTO SOMEBODY'S SETTINGS, or null if it may.
// Two shapes, both of them measured on this run:
//   - a git worktree marks itself by making `.git` a FILE (`gitdir: ...`)
//     instead of a directory. That is the shape that did the damage.
//   - anything under the temp directory is by definition swept.
// A plain clone and an `npm i -g` tree are neither, so the ordinary user is
// unaffected. Deliberately NOT a heuristic on the name: a directory called
// "worktree" is fine, and a real worktree called "rabadon" is not.
function notDurable(p) {
  const real = (x) => { try { return fs.realpathSync(x); } catch { return path.resolve(x); } };
  const tmp = real(os.tmpdir());
  const rp = real(p);
  if (rp === tmp || rp.startsWith(tmp + path.sep)) return `it is under the temp directory (${tmp})`;
  try {
    if (fs.statSync(path.join(PKG_DIR, '.git')).isFile())
      return 'it is inside a git worktree, which goes away when the work does';
  } catch { /* no .git at all: an npm install, which is durable */ }
  return null;
}

// The rabadon commands this settings file ALREADY registers, by binary name.
// Ownership is read the way install.mjs writes it — the command names a rabadon
// binary — so somebody else's hook is never mistaken for ours.
function registeredCmds(settingsPath) {
  let s;
  try { s = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch { return {}; }
  if (!s || typeof s !== 'object') return {};
  const out = {};
  const take = (c) => {
    if (typeof c !== 'string' || !RABADON_CMD_RE.test(c)) return;
    const argv0 = c.split(' ')[0];
    const base = path.basename(argv0);
    if ((base === 'rabadon-gate' || base === 'rabadon-drift') && !out[base]) out[base] = argv0;
  };
  for (const arr of Object.values(s.hooks || {}))
    if (Array.isArray(arr))
      for (const entry of arr) for (const h of (entry && entry.hooks) || []) take(h && h.command);
  return out;
}

// Every rabadon command left in the file that names a binary which is not
// there. What we write, we check: a hook pointing at an absent file is a
// session that goes quiet, and going quiet is the one thing rabadon may never do.
function deadCommands(settingsPath) {
  let s;
  try { s = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch { return []; }
  const dead = [];
  for (const arr of Object.values((s && s.hooks) || {}))
    if (Array.isArray(arr))
      for (const entry of arr)
        for (const h of (entry && entry.hooks) || []) {
          const c = h && h.command;
          if (typeof c === 'string' && RABADON_CMD_RE.test(c) && !fs.existsSync(c.split(' ')[0]))
            dead.push(c.split(' ')[0]);
        }
  return [...new Set(dead)];
}

// Which events this settings file currently has a rabadon command under.
// Read the same way install.mjs writes ownership — by the command naming a
// rabadon binary, never by position, so somebody else's hook is never ours.
function subscribedEvents(settingsPath) {
  let s;
  try { s = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); }
  catch { return null; }                    // absent or unreadable: not ours to rewrite
  if (!s || typeof s !== 'object') return null;
  const events = new Set();
  for (const [ev, arr] of Object.entries(s.hooks || {})) {
    if (!Array.isArray(arr)) continue;
    for (const entry of arr)
      for (const h of (entry && entry.hooks) || [])
        if (h && typeof h.command === 'string' && RABADON_CMD_RE.test(h.command)) events.add(ev);
  }
  return events;
}

// Bring one target's rabadon entries up to what this install would write today.
// Returns a human line when something actually changed, null otherwise.
export function refreshTarget(dir) {
  const settingsPath = path.join(dir, '.claude', 'settings.json');
  const before = subscribedEvents(settingsPath);
  // No rabadon entries here (or no readable file) => this is not an install of
  // ours. Do nothing: an upgrade may not create an installation.
  if (!before || before.size === 0) return null;

  // WHICH ADDRESS THIS UPGRADE WILL CARRY. Default: the one already registered.
  // Not the one we are running from — that is the whole defect.
  const reg = registeredCmds(settingsPath);
  const alive = (p) => !!p && fs.existsSync(p);
  let gateCmd = reg['rabadon-gate'];
  let repoint = null;

  if (alive(gateCmd)) {
    // The install works. Nothing about an event subscription requires moving it.
  } else {
    // The registered binary is gone, so this install is ALREADY dead and doing
    // nothing leaves it dead. This is the only case allowed to write a path,
    // and it may only write a durable one.
    const why = notDurable(GATE_BIN);
    if (why || !fs.existsSync(GATE_BIN)) {
      const reason = why || `it is not there either (${GATE_BIN})`;
      return `rabadon: this install points at a binary that is gone (${gateCmd || 'unknown'}) and I will NOT repoint it`
           + ` to ${GATE_BIN} — ${reason}.`
           + `\n        A hook naming a file that will not exist tomorrow dies without saying so, which is worse than being stale.`
           + `\n        Nothing was changed in ${settingsPath}. Fix it from your real install: \`rabadon init\``;
    }
    repoint = { from: gateCmd || '(none registered)', to: GATE_BIN };
    gateCmd = GATE_BIN;
  }

  // rabadon-drift travels with the gate: an install has one address, not two.
  // Prefer what is registered, else the gate's own sibling, else the resolved
  // one — and the sibling is what makes the drift-on-Stop upgrade land at the
  // CANONICAL directory rather than at whoever happened to run.
  let driftCmd = reg['rabadon-drift'];
  if (!alive(driftCmd)) {
    const sibling = path.join(path.dirname(gateCmd), 'rabadon-drift');
    driftCmd = alive(sibling) ? sibling : DRIFT_BIN;
  }

  let r;
  try { r = installHooks(dir, { gateCmd, driftCmd, statuslineCmd: `${gateCmd} --statusline` }); }
  catch { return null; }                    // unparseable / read-only: install.mjs's law, not ours to force
  if (!r.changed) return null;

  const after = subscribedEvents(settingsPath) || new Set();
  const added = [...after].filter((e) => !before.has(e)).sort();

  // EVERY HALF OF THE CHANGE IS ANNOUNCED, INDEPENDENTLY. The old code chose
  // one sentence with a ternary on `added.length`, so the run that both
  // subscribed and repointed — the run that happened in the field — reported
  // only the harmless half.
  const parts = [];
  if (added.length) parts.push(`subscribed to ${added.join(', ')}`);
  if (repoint) parts.push(`repointed rabadon-gate from ${repoint.from} to ${repoint.to}`);
  if (!parts.length) parts.push('rewrote its entries to the shape this version installs');

  let line = `rabadon: this install was older than the binary — ${parts.join('; ')} in ${settingsPath}`
           + `\n        (your previous settings are in ${settingsPath}.bak-rabadon; the new events take effect in your NEXT session)`;

  const dead = deadCommands(settingsPath);
  if (dead.length)
    line += `\n        WARNING: ${dead.length} rabadon hook(s) in that file name a binary that is not there (${dead.join(', ')})`
          + `\n        — this machine is registered but blind. Run \`rabadon init\` from your install.`;
  return line;
}

// The two places a rabadon install can live for this session: the machine-wide
// one and this project's own. Both are refreshed, because either one carrying
// the subscription is enough for the agent to deliver the event — and either
// one being stale is enough to make the OTHER one's freshness invisible.
export function refresh(projectDir) {
  const targets = [os.homedir()];
  if (projectDir && path.resolve(projectDir) !== path.resolve(os.homedir())) targets.push(path.resolve(projectDir));
  const lines = [];
  for (const t of targets) {
    let line = null;
    try { line = refreshTarget(t); } catch { /* a refresh never costs the session */ }
    if (line) lines.push(line);
  }
  return lines;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try { for (const l of refresh(process.argv[2] || process.cwd())) console.log(l); }
  catch { /* exit 0 regardless: see header */ }
  process.exit(0);
}
