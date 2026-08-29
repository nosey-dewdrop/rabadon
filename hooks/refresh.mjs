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

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { installHooks, RABADON_CMD_RE } from './install.mjs';

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

  let r;
  try { r = installHooks(dir); }
  catch { return null; }                    // unparseable / read-only: install.mjs's law, not ours to force
  if (!r.changed) return null;

  const after = subscribedEvents(settingsPath) || new Set();
  const added = [...after].filter((e) => !before.has(e)).sort();
  const detail = added.length ? `subscribed to ${added.join(', ')}` : 'repointed its entries';
  return `rabadon: this install was older than the binary — ${detail} in ${settingsPath}`
       + `\n        (your previous settings are in ${settingsPath}.bak-rabadon; the new events take effect in your NEXT session)`;
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
