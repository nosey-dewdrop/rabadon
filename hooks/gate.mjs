#!/usr/bin/env node
// rabadon gate — live supervision of a Claude Code work session.
//
// Install this as a PreToolUse/PostToolUse/Stop hook in a project and every
// tool call the coding agent makes passes through rabadon BEFORE it runs:
//   - the project's guard rules (${project}/.rabadon/guard.json — written by
//     `rabadon guard`, i.e. by rabadon itself from the project's own law
//     files) are enforced deterministically, <50ms, on every action;
//   - a violation is BLOCKED at the moment it is attempted (exit 2), and the
//     reason is fed back to the agent so it corrects itself;
//   - every action, block and verdict streams to `rabadon watch` live.
//
// This is the Galileo two-layer shape (cheap deterministic gate on every
// action, LLM only where it belongs) applied to the coding agent itself:
// the builder drinks tea, the session cannot silently go off the rails.
//
// Contract with Claude Code hooks:
//   stdin  = one JSON event {hook_event_name, cwd, tool_name, tool_input, ...}
//   exit 0 = allow;  exit 2 = BLOCK, stderr is shown to the agent as feedback.
//   The gate itself must never crash the session: an internal error allows
//   (fail-open for the gate's own bugs, loudly logged — blocking Damla's work
//   because rabadon has a bug would make rabadon the problem it exists to kill).

import fs from 'node:fs';
import path from 'node:path';
import { emitter } from '../core/bus.mjs';

function readStdin() {
  return new Promise((resolve) => {
    let buf = '';
    process.stdin.on('data', (d) => (buf += d));
    process.stdin.on('end', () => resolve(buf));
    setTimeout(() => resolve(buf), 2000); // a hook must never hang the session
  });
}

const raw = await readStdin();
let ev;
try { ev = JSON.parse(raw); } catch { process.exit(0); }

const cwd = ev.cwd || process.cwd();
const project = path.basename(cwd);
const guardPath = path.join(cwd, '.rabadon', 'guard.json');
const statePath = path.join(cwd, '.rabadon', 'state.json');

// escape hatches — trust at scale requires an instant, obvious OFF switch:
//   RABADON_OFF=1 in the env, or a `.rabadon/off` file in the project
//   (`rabadon off` / `rabadon on` manage it). Observation stops too: off is off.
if (process.env.RABADON_OFF === '1' || fs.existsSync(path.join(cwd, '.rabadon', 'off'))) {
  process.exit(0);
}

let guard = null;
try { guard = JSON.parse(fs.readFileSync(guardPath, 'utf8')); } catch { /* no guard = observe only */ }
// per-rule disable: guard.disabled = ["rule-id", ...] — every block message
// names its rule id precisely so the user can silence THAT rule, not the product
const disabled = new Set((guard && guard.disabled) || []);
if (guard) {
  guard.bash = (guard.bash || []).filter((r) => !disabled.has(r.id));
  guard.protectedPaths = (guard.protectedPaths || []).filter((r) => !disabled.has(r.id));
}

const emit = emitter({ pipe: `${project}:session` });

function loadState() {
  try { return JSON.parse(fs.readFileSync(statePath, 'utf8')); } catch { return {}; }
}
function saveState(s) {
  try { fs.mkdirSync(path.dirname(statePath), { recursive: true }); fs.writeFileSync(statePath, JSON.stringify(s)); } catch { /* state is advisory */ }
}

// the unix-socket connect is async; give the live view a beat to receive
// before the hook process dies (the spool already has it either way)
const flush = () => new Promise((r) => setTimeout(r, 60));

async function block(rule, detail) {
  emit('CHECK_FAIL', { step: ev.tool_name, fails: [{ check: rule.id || 'guard', why: `${detail} — ${rule.why || ''}` }] });
  emit('STOP', { reason: 'BLOCKED', detail });
  await flush();
  emit.close();
  // stderr goes back to the agent as the reason — this is the self-correction loop
  process.stderr.write(`rabadon BLOCKED this action.\nRule: ${rule.id || 'guard'} — ${rule.why || ''}\n${detail}\nAdjust the approach instead of retrying the same action.\n(user override: add "${rule.id || 'guard'}" to disabled[] in .rabadon/guard.json, or \`rabadon off\` to pause supervision)\n`);
  process.exit(2);
}

async function done(evName, fields) {
  if (evName) { emit(evName, fields); await flush(); }
  emit.close();
  process.exit(0);
}

const toolInput = ev.tool_input || {};
const hookEvent = ev.hook_event_name;

// ---------- PreToolUse: the gate ----------
if (hookEvent === 'PreToolUse') {
  const state = loadState();

  if (guard) {
    // Bash command rules
    if (ev.tool_name === 'Bash' && typeof toolInput.command === 'string') {
      const cmd = toolInput.command;
      for (const rule of guard.bash || []) {
        try {
          if (new RegExp(rule.deny, 'i').test(cmd)) await block(rule, `command matched deny rule: ${cmd.slice(0, 160)}`);
        } catch { /* a broken regex must not take the gate down */ }
      }
      // push gate: tests must be green since the last code edit. rabadon does
      // not just SAY it — if the guard declares the literal test command
      // (pushGate.run), rabadon RUNS it right here and opens the gate itself
      // on green. Telling is a warning; solving is the product.
      if (guard.pushGate && /\bgit\s+push\b/.test(cmd) && !/--dry-run/.test(cmd)) {
        const editedSince = state.lastCodeEdit || 0;
        const testedAt = state.lastTestPass || 0;
        if (editedSince > testedAt) {
          if (guard.pushGate.run) {
            emit('REPAIR_START', { step: 'push-gate', attempt: 1, fixing: ['tests-not-green'] });
            const { execSync } = await import('node:child_process');
            let out = '', green = false;
            try {
              out = execSync(guard.pushGate.run, {
                cwd, encoding: 'utf8', timeout: (guard.pushGate.timeoutSec || 900) * 1000,
                stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 16 * 1024 * 1024,
              });
              green = guard.testPassPattern ? new RegExp(guard.testPassPattern, 'i').test(out) : true;
            } catch (e) {
              out = String((e.stdout || '') + (e.stderr || e.message || ''));
              green = false;
            }
            if (green) {
              state.lastTestPass = Date.now(); state.lastTestRun = Date.now();
              saveState(state);
              emit('REPAIR_OK', { step: 'push-gate', attempt: 1 });
              // fall through: the push is now legitimately allowed
            } else {
              emit('REPAIR_FAIL', { step: 'push-gate', attempt: 1, why: 'tests not green' });
              // show the FAILURES, not whatever happened to be at the tail
              const failLines = out.split('\n').filter((l) => /fail|error|\*\*\*|tests passed/i.test(l)).slice(-15).join('\n');
              await block({ id: 'push-gate', why: guard.pushGate.why || 'tests must be green before push' },
                `rabadon ran the tests itself (${guard.pushGate.run}) — NOT GREEN.\n${failLines || out.slice(-800)}\nFix the failure; rabadon will re-run the suite on your next push attempt.`);
            }
          } else {
            await block({ id: 'push-gate', why: guard.pushGate.why || 'tests must be green before push' },
              `code was edited after the last passing test run — run: ${guard.pushGate.testHint || 'the test suite'} first`);
          }
        }
      }
    }

    // protected paths (Edit/Write/MultiEdit/NotebookEdit)
    if (['Edit', 'Write', 'MultiEdit', 'NotebookEdit'].includes(ev.tool_name)) {
      const file = toolInput.file_path || toolInput.notebook_path || '';
      for (const rule of guard.protectedPaths || []) {
        try {
          if (new RegExp(rule.match, 'i').test(file)) await block(rule, `protected file: ${file}`);
        } catch { /* ignore broken rule */ }
      }
    }
  }

  // --- loop-stop: rabadon's founding guarantee, applied to the session. ---
  // The same bash command re-run with NO code change in between is an agent
  // spinning in place ("loops that were meant to proofread didn't stop").
  // Three identical spins -> stopped, with the reason fed back.
  const READ_ONLY = /^(git\s+(status|diff|log|show|branch)|ls|cat|head|tail|grep|rg|find|pwd|wc|echo|which|node\s+--check)\b/;
  if (ev.tool_name === 'Bash' && typeof toolInput.command === 'string' && !READ_ONLY.test(toolInput.command.trim())) {
    const cmd = toolInput.command.trim();
    const editedBetween = (state.lastCodeEdit || 0) > (state.lastCmdTs || 0);
    if (state.lastCmd === cmd && !editedBetween) state.cmdRepeat = (state.cmdRepeat || 1) + 1;
    else state.cmdRepeat = 1;
    state.lastCmd = cmd;
    state.lastCmdTs = Date.now();
    saveState(state);
    if (state.cmdRepeat >= 3) {
      await block({ id: 'loop-stop', why: 'the same command has now run 3x with no code change in between — a loop, not progress' },
        `looping on: ${cmd.slice(0, 120)} — change the code or the approach before running it again`);
    }
  }


  const label = ev.tool_name === 'Bash'
    ? `bash: ${String(toolInput.command || '').slice(0, 80)}`
    : `${ev.tool_name.toLowerCase()}: ${path.basename(toolInput.file_path || toolInput.pattern || toolInput.url || '') || '?'}`;
  await done('STEP_START', { step: label });
}

// ---------- PostToolUse: observe + track session state ----------
else if (hookEvent === 'PostToolUse') {
  const state = loadState();
  const now = Date.now();

  if (['Edit', 'Write', 'MultiEdit'].includes(ev.tool_name)) {
    const file = toolInput.file_path || '';
    const isCode = guard && guard.codePaths
      ? (guard.codePaths || []).some((p) => { try { return new RegExp(p, 'i').test(file); } catch { return false; } })
      : true;
    if (isCode) state.lastCodeEdit = now;

    // --- scope fan-out: "the pipeline loses its own purpose", session form. ---
    // A task that started in one area and is now touching its 5th top-level
    // directory is drifting. Once per session: the observation is fed back to
    // the agent (PostToolUse exit 2 = feedback, not a block) so it either
    // justifies the spread or reins itself in.
    const rel = path.relative(cwd, file);
    const top = rel.startsWith('..') ? null : rel.split(path.sep)[0];
    if (top) {
      state.touchedDirs = Array.from(new Set([...(state.touchedDirs || []), top]));
      if (state.touchedDirs.length >= 5 && !state.fanoutWarned) {
        state.fanoutWarned = true;
        saveState(state);
        emit('CHECK_FAIL', { step: 'scope', fails: [{ check: 'scope-fanout', why: `session has now edited files in ${state.touchedDirs.length} top-level dirs: ${state.touchedDirs.join(', ')}` }] });
        await flush();
        emit.close();
        process.stderr.write(`rabadon: scope fan-out — this session has edited files across ${state.touchedDirs.length} top-level directories (${state.touchedDirs.join(', ')}). If the task really spans all of them, say so and continue; otherwise rein the change back to the area the task started in.\n`);
        process.exit(2);
      }
    }
    saveState(state);
    await done('STEP_OK', { step: `edited: ${path.basename(file)}` });
  } else if (ev.tool_name === 'Bash') {
    const cmd = String(toolInput.command || '');
    const out = typeof ev.tool_response === 'string' ? ev.tool_response : JSON.stringify(ev.tool_response || '');
    const isTest = guard && guard.testCommand ? new RegExp(guard.testCommand, 'i').test(cmd) : /ctest|--test|npm test/.test(cmd);
    if (isTest) {
      const passed = guard && guard.testPassPattern
        ? new RegExp(guard.testPassPattern, 'i').test(out)
        : /100% tests passed|0 failed|pass 1?\d+\n.*fail 0/i.test(out);
      state.lastTestRun = now;
      if (passed) state.lastTestPass = now;
      saveState(state);
      await done(passed ? 'STEP_OK' : 'CHECK_FAIL', passed
        ? { step: 'tests: GREEN' }
        : { step: 'tests', fails: [{ check: 'test-run', why: 'test command ran but did not report green' }] });
    } else {
      await done('STEP_OK', { step: `ran: ${cmd.slice(0, 80)}` });
    }
  } else {
    await done(null);
  }
}

// ---------- UserPromptSubmit: pin the session's goal ----------
else if (hookEvent === 'UserPromptSubmit') {
  const state = loadState();
  if (!state.goalPrompt || (Date.now() - (state.goalTs || 0)) > 6 * 3600 * 1000) {
    state.goalPrompt = String(ev.prompt || '').slice(0, 400);
    state.goalTs = Date.now();
    // a new goal resets the drift trackers — a new task may legitimately live elsewhere
    state.touchedDirs = [];
    state.fanoutWarned = false;
    saveState(state);
    emit('RUN_START', { steps: [`goal: ${state.goalPrompt.slice(0, 100)}`], bound: {} });
    await flush();
  }
  await done(null);
}

// ---------- SessionStart / Stop: bracket the session on the live view ----------
else if (hookEvent === 'SessionStart') {
  const st = loadState();
  st.touchedDirs = []; st.fanoutWarned = false; st.cmdRepeat = 0; st.lastCmd = null;
  saveState(st);
  await done('RUN_START', { steps: [guard ? `guard: ${(guard.bash || []).length} bash + ${(guard.protectedPaths || []).length} path rules` : 'NO GUARD (observe only)'], bound: guard ? { pushGate: !!guard.pushGate, loopStop: 3, fanout: 5 } : { loopStop: 3, fanout: 5 } });
}
else if (hookEvent === 'Stop') {
  await done('RUN_DONE', { verdict: 'SESSION_TURN_DONE', tokens: 0, depth: 0 });
}
else {
  await done(null);
}
