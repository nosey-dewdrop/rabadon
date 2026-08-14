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
//   (fail-open for the gate's own bugs, loudly logged — blocking the builder's work
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

const SID = String(ev.session_id || 'default').slice(0, 16);

// Drill events (rabadon's own synthetic checks: fleet verification, doctor
// self-test) are tagged at EMIT time so no ledger downstream can ever count
// rabadon testing itself as a real catch. The ledger's honesty is the product.
const isDrill = /^(fleet|doctor)-/.test(String(ev.session_id || ''));
const emit0 = emitter({ pipe: `${project}:session` });
const emit = (evName, fields = {}) => emit0(evName, isDrill ? { ...fields, drill: true } : fields);
emit.close = emit0.close;
function loadState() {
  let st;
  try { st = JSON.parse(fs.readFileSync(statePath, 'utf8')); } catch { st = {}; }
  st.sessions = st.sessions || {};
  // per-session counters (loop, trail, fanout, goal) — two parallel sessions
  // in one project must not poison each other's counters
  st.s = st.sessions[SID] = st.sessions[SID] || {};
  // keep at most 4 sessions of history
  const sids = Object.keys(st.sessions);
  if (sids.length > 4) for (const k of sids.slice(0, sids.length - 4)) delete st.sessions[k];
  return st;
}
function saveState(s) {
  try { fs.mkdirSync(path.dirname(statePath), { recursive: true }); fs.writeFileSync(statePath, JSON.stringify(s)); } catch { /* state is advisory */ }
}

// the unix-socket connect is async; give the live view a beat to receive
// before the hook process dies (the spool already has it either way)
const flush = () => new Promise((r) => setTimeout(r, 60));

// remember the session's last moves so a diagnosis knows WHERE it is —
// "which gate is the problem at" needs the trail, not just the crash
function remember(state, summary) {
  state.s.recent = [...(state.s.recent || []), { t: Date.now(), s: summary.slice(0, 120) }].slice(-30);
  state.s.actionCount = (state.s.actionCount || 0) + 1;
}

// which model answers, when one is asked at all. Twin of env_or + the two call
// sites in native/gate.cpp — both names default to what used to be hard-coded
// here, so this moves no behaviour by itself. RABADON_MODEL is NOT reused: it
// belongs to the per-tier proposer, and one name for two jobs sends the judge
// to the wrong model without saying so.
function modelArgs(envName, fallback) {
  const m = process.env[envName] || fallback;
  return m ? ['--model', m] : [];
}

// the incident brain: local Claude Code CLI, bounded, structured verdict.
// Runs ONLY on an incident (red tests) — never in the per-action hot path.
async function diagnose({ goal, recent, failOutput, cmd }) {
  const { execFile } = await import('node:child_process');
  const prompt = [
    'You are rabadon, a reliability runtime supervising a live coding session. The test suite just went RED.',
    'Diagnose from the evidence and return ONLY a JSON object, no fences, no prose:',
    '{ "where": "<which step/gate of the work this belongs to, one short phrase>",',
    '  "cause": "<root cause in one sentence, from the evidence — never invent>",',
    '  "fix": "<the concrete next action to fix it, one sentence>",',
    '  "newRule": { "id": "kebab-id", "deny": "<JS regex over bash commands>", "why": "<one line>" } | { "id": "kebab-id", "match": "<JS regex over file paths>", "why": "<one line>" } | null }',
    'newRule: ONLY if this class of mistake could have been caught BEFORE it happened by blocking a command or an edit; otherwise null. Prefer null over a rule that could block legitimate work.',
    '',
    `## session goal\n${goal}`,
    `## last moves\n${recent.map((r) => `- ${r.s}`).join('\n')}`,
    `## the test command\n${cmd}`,
    `## failing output (tail)\n${failOutput}`,
  ].join('\n');
  const out = await new Promise((resolve, reject) => {
    const child = execFile('claude', ['-p', '--output-format', 'text', ...modelArgs('RABADON_DIAGNOSE_MODEL', '')],
      { timeout: 90000, maxBuffer: 4 * 1024 * 1024 },
      (err, stdout, stderr) => err ? reject(new Error((stderr || err.message).slice(0, 200))) : resolve(String(stdout).trim()));
    child.stdin.write(prompt);
    child.stdin.end();
  });
  try { return JSON.parse(out.replace(/^```(?:json)?\s*|\s*```$/g, '')); } catch { return null; }
}

// fast drift judge: haiku-class, single small verdict, ~seconds.
async function driftJudge(goal, recent) {
  const { execFile } = await import('node:child_process');
  const prompt = [
    'You are rabadon, supervising a coding session. Verdict only, JSON only, no fences:',
    '{ "onTrack": true|false, "anchor": "<if off track: ONE sentence steering the work back to the goal; else empty>" }',
    'Judge conservatively: refactors, tests, and setup that SERVE the goal are on-track. Only flag work that belongs to a different task.',
    `## the session goal\n${goal}`,
    `## the last moves\n${recent.map((r) => `- ${r.s}`).join('\n')}`,
  ].join('\n');
  const out = await new Promise((resolve, reject) => {
    const child = execFile('claude', ['-p', '--output-format', 'text', ...modelArgs('RABADON_JUDGE_MODEL', 'claude-haiku-4-5')],
      { timeout: 30000, maxBuffer: 1024 * 1024 },
      (err, stdout, stderr) => err ? reject(new Error((stderr || err.message).slice(0, 150))) : resolve(String(stdout).trim()));
    child.stdin.write(prompt);
    child.stdin.end();
  });
  try { return JSON.parse(out.replace(/^```(?:json)?\s*|\s*```$/g, '')); } catch { return null; }
}

function notify(title, body) {
  // native macOS notification — the catch reaches the builder even when the
  // terminal is buried. fire-and-forget, never blocks, no-op elsewhere.
  if (process.platform !== 'darwin' || process.env.RABADON_NOTIFY === '0') return;
  try {
    const { spawn } = require('node:child_process');
  } catch { }
  import('node:child_process').then(({ spawn }) => {
    const esc = (x) => String(x).replace(/["\\]/g, '');
    spawn('osascript', ['-e', `display notification "${esc(body).slice(0, 120)}" with title "rabadon" subtitle "${esc(title).slice(0, 60)}"`], { detached: true, stdio: 'ignore' }).unref();
  }).catch(() => { });
}

async function block(rule, detail) {
  emit('CHECK_FAIL', { step: ev.tool_name, fails: [{ check: rule.id || 'guard', why: `${detail} — ${rule.why || ''}` }] });
  emit('STOP', { reason: 'BLOCKED', detail });
  notify(`${project}: caught`, `${rule.id || 'guard'} — ${detail}`);
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

// Global (~/.claude) and project settings can BOTH register this gate; Claude
// Code then delivers the SAME event twice. The twin must be a no-op — one
// verdict, one ledger entry, one loop-tick — or every count doubles and
// loop-stop fires at 2 instead of 3. Tool events carry a unique tool_use_id:
// twins share it, a REAL re-run of the same command gets a fresh one — so the
// dedupe is exact, never a content heuristic that could eat loop-stop's food.
// Non-tool events (Stop/SessionStart/…) have no id; they dedupe on a 2s time
// bucket, which only ever collides with a genuine twin.
{
  const st0 = loadState();
  st0.s.recentEv = st0.s.recentEv || [];
  let dedupeKey = null;
  if (ev.tool_use_id) dedupeKey = `${hookEvent}:${ev.tool_use_id}`;
  else if (!['PreToolUse', 'PostToolUse'].includes(hookEvent)) dedupeKey = `${hookEvent}:${Math.floor(Date.now() / 2000)}`;
  if (dedupeKey) {
    if (st0.s.recentEv.includes(dedupeKey)) process.exit(0);
    st0.s.recentEv = [...st0.s.recentEv, dedupeKey].slice(-12);
    saveState(st0);
  }
}

// ---------- PreToolUse: the gate ----------
if (hookEvent === 'PreToolUse') {
  const state = loadState();

  if (guard) {
    // Bash command rules
    if (ev.tool_name === 'Bash' && typeof toolInput.command === 'string') {
      const cmd = toolInput.command;
      // agents write `git -C /path push --force` — global git options between
      // "git" and the subcommand slide past every `git\s+push` rule (caught
      // live on the first wild repo, 31.07). A rule fires on the raw command
      // OR on the git-global-stripped form; raw is tried first, so this can
      // only catch more, never less. Mirrors strip_git_globals in gate.cpp.
      const normCmd = cmd.replace(
        /\b(git)((?:\s+(?:-C\s+\S+|-c\s+\S+|--git-dir(?:=\S+|\s+\S+)|--work-tree(?:=\S+|\s+\S+)|--no-pager|-P|--paginate))+)\s+/gi,
        '$1 ');
      const cmdHits = (pat) => {
        const re = new RegExp(pat, 'i');
        return re.test(cmd) || (normCmd !== cmd && re.test(normCmd));
      };
      for (const rule of guard.bash || []) {
        try {
          if (cmdHits(rule.deny)) await block(rule, `command matched deny rule: ${cmd.slice(0, 160)}`);
        } catch { /* a broken regex must not take the gate down */ }
      }
      // push gate: tests must be green since the last code edit. rabadon does
      // not just SAY it — if the guard declares the literal test command
      // (pushGate.run), rabadon RUNS it right here and opens the gate itself
      // on green. Telling is a warning; solving is the product.
      if (guard.pushGate && cmdHits('\\bgit\\s+push\\b') && !/--dry-run/.test(cmd)) {
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
              notify(`${project}: hallettim`, 'push istendi, testleri kendim koştum — yeşil, kapıyı açtım');
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

  // --- test-tamper: the classic agent cheat, caught the moment it is typed.
  // Tests are RED and the very next edit touches a TEST file in a way that
  // weakens it (skip markers added, assertions removed) — that is not a fix,
  // that is doctoring the thermometer. Deterministic, no LLM, zero latency.
  if (['Edit', 'Write', 'MultiEdit'].includes(ev.tool_name) && (state.lastTestFail || 0) > (state.lastTestPass || 0)) {
    const file = toolInput.file_path || '';
    const isTestFile = guard && guard.testPaths
      ? (guard.testPaths || []).some((p) => { try { return new RegExp(p, 'i').test(file); } catch { return false; } })
      : /test/i.test(file);
    if (isTestFile) {
      const oldS = String(toolInput.old_string || '');
      const newS = String(toolInput.new_string ?? toolInput.content ?? '');
      const SKIP = /\b(it|test|describe)\.(skip|todo)\b|\bxit\(|\bxdescribe\(|DISABLED_|GTEST_SKIP|@unittest\.skip|pytest\.mark\.skip/;
      // method-call styles count too: assert.equal(...), expect(x).toBe(...) —
      // the node:assert style slipped the old pattern (assert\w* cannot cross '.')
      const count = (str) => (str.match(/\b(assert|expect|require)(\.\w+)?\s*\(|\b(EXPECT_|ASSERT_|assert_eq)\w*!?\s*\(/g) || []).length;
      const addsSkip = SKIP.test(newS) && !SKIP.test(oldS);
      const dropsAsserts = oldS && count(newS) < count(oldS);
      if (addsSkip || dropsAsserts) {
        await block({ id: 'test-tamper', why: 'tests are RED and this edit weakens the test instead of fixing the code' },
          `${addsSkip ? 'a skip marker is being added to' : 'assertions are being removed from'} ${path.basename(file)} while the suite is red — fix the CODE; if the test itself is truly wrong, say so to the user and change it with the suite green`);
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
    const editedBetween = (state.lastCodeEdit || 0) > (state.s.lastCmdTs || 0);
    if (state.s.lastCmd === cmd && !editedBetween) state.s.cmdRepeat = (state.s.cmdRepeat || 1) + 1;
    else state.s.cmdRepeat = 1;
    state.s.lastCmd = cmd;
    state.s.lastCmdTs = Date.now();
    saveState(state);
    if (state.s.cmdRepeat >= 3) {
      await block({ id: 'loop-stop', why: 'the same command has now run 3x with no code change in between — a loop, not progress' },
        `looping on: ${cmd.slice(0, 120)} — change the code or the approach before running it again`);
    }
  }


  const label = ev.tool_name === 'Bash'
    ? `bash: ${String(toolInput.command || '').slice(0, 80)}`
    : `${ev.tool_name.toLowerCase()}: ${path.basename(toolInput.file_path || toolInput.pattern || toolInput.url || '') || '?'}`;
  remember(state, label);
  saveState(state);
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
      state.s.touchedDirs = Array.from(new Set([...(state.s.touchedDirs || []), top]));
      if (state.s.touchedDirs.length >= 5 && !state.s.fanoutWarned) {
        state.s.fanoutWarned = true;
        saveState(state);
        emit('CHECK_FAIL', { step: 'scope', fails: [{ check: 'scope-fanout', why: `session has now edited files in ${state.s.touchedDirs.length} top-level dirs: ${state.s.touchedDirs.join(', ')}` }] });
        await flush();
        emit.close();
        process.stderr.write(`rabadon: scope fan-out — this session has edited files across ${state.s.touchedDirs.length} top-level directories (${state.s.touchedDirs.join(', ')}). If the task really spans all of them, say so and continue; otherwise rein the change back to the area the task started in.\n`);
        process.exit(2);
      }
    }
    saveState(state);

    // --- guarantee #4 at the session level: ACTIVE RE-ANCHOR. Every 12th
    // action a fast judge compares the last moves against the captured goal;
    // if the session is drifting, the anchor is fed back (non-blocking — the
    // edit already happened, the NEXT move gets the correction). Fast model,
    // bounded, skipped entirely with RABADON_JUDGE=0.
    if (process.env.RABADON_JUDGE !== '0' && state.s.goalPrompt && (state.s.actionCount || 0) > 0 && state.s.actionCount % 12 === 0) {
      try {
        // caught here, not by the outer handler — see the diagnose call below:
        // a judge that failed still spent the wall-clock, and the native twin
        // records it, so this one has to as well or the two ledgers disagree.
        const t0 = Date.now();
        let verdict = null;
        try { verdict = await driftJudge(state.s.goalPrompt, (state.s.recent || []).slice(-12)); }
        catch { verdict = null; }
        // twin of the LLM_CALL in native/gate.cpp: the ledger says money was
        // spent and how long the session waited, never an invented USD — the
        // -p text stream carries no usage, so cost comes from the transcript in
        // `rabadon lens`, where it is measured instead of guessed.
        emit('LLM_CALL', {
          purpose: 'drift',
          model: process.env.RABADON_JUDGE_MODEL || 'claude-haiku-4-5',
          ms: Date.now() - t0,
          ok: !!verdict,
        });
        if (verdict && verdict.onTrack === false && verdict.anchor) {
          emit('CHECK_FAIL', { step: 'goal', fails: [{ check: 'goal-drift', why: verdict.anchor.slice(0, 200) }] });
          await flush();
          emit.close();
          process.stderr.write(`rabadon re-anchor: the session goal is "${state.s.goalPrompt.slice(0, 120)}". ${verdict.anchor}\n`);
          process.exit(2);
        }
      } catch { /* judge unavailable -> stay silent, never stall the session */ }
    }
    await done('STEP_OK', { step: `edited: ${path.basename(file)}` });
  } else if (ev.tool_name === 'Bash') {
    const cmd = String(toolInput.command || '');
    // tool_response is often a JSON object; stringifying it escapes newlines
    // to literal \n — unescape so line-anchored patterns see real lines
    const out = (typeof ev.tool_response === 'string' ? ev.tool_response : JSON.stringify(ev.tool_response || ''))
      .replace(/\\r?\\n/g, '\n');
    const isTest = guard && guard.testCommand ? new RegExp(guard.testCommand, 'i').test(cmd) : /ctest|--test|npm test/.test(cmd);
    if (isTest) {
      // red = a MEASURED failure, never a keyword sighting: the word "fail"
      // appears in a green run too ("fail 0") — its own diagnosis engine
      // caught this detector doing exactly that (2026-07-27, live)
      const failCount = out.match(/\bfail(?:ed|ures)?\s*[:= ]\s*(\d+)/i);
      const passed = guard && guard.testPassPattern
        ? new RegExp(guard.testPassPattern, 'i').test(out)
        : failCount ? Number(failCount[1]) === 0
        : /100% tests passed|0 failed|all tests passed/i.test(out);
      state.lastTestRun = now;
      if (passed) { state.lastTestPass = now; state.lastTestFail = 0; }
      else state.lastTestFail = now;
      saveState(state);
      if (passed) await done('STEP_OK', { step: 'tests: GREEN' });

      // --- INCIDENT LOOP: see the problem live -> say WHICH gate it belongs
      // to -> produce the fix -> AUTHOR A NEW GATE so this class of break is
      // caught pre-action next time. The guard grows out of real incidents.
      emit('CHECK_FAIL', { step: 'tests', fails: [{ check: 'test-run', why: 'test run is RED' }] });
      let advice = '';
      const failSig = out.split('\n').filter((l) => /fail/i.test(l)).join('|').slice(0, 300);
      const sameIncident = state.lastDiagSig === failSig && (now - (state.lastDiagAt || 0)) < 15 * 60000;
      if (process.env.RABADON_JUDGE !== '0' && !sameIncident) {
        state.lastDiagSig = failSig; state.lastDiagAt = now; saveState(state);
        emit('REPAIR_START', { step: 'diagnose', attempt: 1, fixing: ['red-tests'] });
        try {
          // The call is caught HERE, not by the outer handler, so a timed-out
          // or missing `claude` still lands one LLM_CALL with ok:false. The
          // native twin returns an empty verdict on the same failure and emits
          // either way; if this one only recorded successes, the two engines
          // would write different ledgers for an identical incident, and the
          // spend a user most wants to see is the spend that bought nothing.
          const diagT0 = Date.now();
          let diag = null;
          try { diag = await diagnose({
            goal: state.s.goalPrompt || '(no goal captured)',
            recent: (state.s.recent || []).slice(-15),
            failOutput: out.slice(-4000),
            cmd,
          }); } catch { diag = null; }
          emit('LLM_CALL', {
            purpose: 'diagnose',
            model: process.env.RABADON_DIAGNOSE_MODEL || '(account default)',
            ms: Date.now() - diagT0,
            ok: !!diag,
          });
          if (diag) {
            advice = `\nrabadon diagnosis:\n  where: ${diag.where}\n  cause: ${diag.cause}\n  fix:   ${diag.fix}\n`;
            notify(`${project}: sorun buldum`, `${diag.where} — ${diag.cause}`.slice(0, 150));
            if (diag.newRule && guard) {
              try {
                new RegExp(diag.newRule.deny || diag.newRule.match, 'i'); // must compile
                const target = diag.newRule.deny ? 'bash' : 'protectedPaths';
                const fullGuard = JSON.parse(fs.readFileSync(guardPath, 'utf8'));
                if (!(fullGuard[target] || []).some((r) => r.id === diag.newRule.id)) {
                  fullGuard[target] = [...(fullGuard[target] || []), { ...diag.newRule, authoredBy: 'incident', incidentAt: new Date().toISOString() }];
                  fs.writeFileSync(guardPath, JSON.stringify(fullGuard, null, 2) + '\n');
                  emit('REPAIR_OK', { step: `new gate: ${diag.newRule.id}`, attempt: 1 });
                  notify(`${project}: yeni kapı`, `bu hata sınıfı artık üretilmeden yakalanacak: ${diag.newRule.id}`);
                  advice += `  new gate installed: ${diag.newRule.id} — this class of break is now caught BEFORE it happens.\n`;
                }
              } catch { /* an invalid rule is dropped, never installed */ }
            }
          }
        } catch { emit('REPAIR_FAIL', { step: 'diagnose', attempt: 1, why: 'diagnosis unavailable' }); }
      }
      await flush();
      emit.close();
      // exit 2 on PostToolUse = feedback to the agent (the action already ran);
      // the diagnosis lands in the session the moment the red is seen
      process.stderr.write(`rabadon: tests are RED.${advice || ' Fix the failure before moving on.'}\n`);
      process.exit(2);
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
  if (!state.s.goalPrompt || (Date.now() - (state.s.goalTs || 0)) > 6 * 3600 * 1000) {
    state.s.goalPrompt = String(ev.prompt || '').slice(0, 400);
    state.s.goalTs = Date.now();
    // a new goal resets the drift trackers — a new task may legitimately live elsewhere
    state.s.touchedDirs = [];
    state.s.fanoutWarned = false;
    saveState(state);
    emit('RUN_START', { steps: [`goal: ${state.s.goalPrompt.slice(0, 100)}`], bound: {} });
    await flush();
  }
  await done(null);
}

// ---------- SessionStart / Stop: bracket the session on the live view ----------
else if (hookEvent === 'SessionStart') {
  const st = loadState();
  st.s.touchedDirs = []; st.s.fanoutWarned = false; st.s.cmdRepeat = 0; st.s.lastCmd = null; st.s.actionCount = 0;
  saveState(st);
  // DEVRIDAIM injection: SessionStart stdout becomes session context — the
  // new session opens already knowing where the last one stood.
  try {
    const h = path.join(cwd, '.rabadon', 'handoff.md');
    const stat = fs.statSync(h);
    if (Date.now() - stat.mtimeMs < 7 * 86400000) {
      process.stdout.write(fs.readFileSync(h, 'utf8'));
    }
  } catch { /* no handoff yet — first cycle */ }
  await done('RUN_START', { steps: [guard ? `guard: ${(guard.bash || []).length} bash + ${(guard.protectedPaths || []).length} path rules` : 'NO GUARD (observe only)'], bound: guard ? { pushGate: !!guard.pushGate, loopStop: 3, fanout: 5 } : { loopStop: 3, fanout: 5 } });
}
else if (hookEvent === 'Stop') {
  // token ledger — REAL usage from the session transcript, read incrementally
  // from the last byte offset (never the whole file twice).
  try {
    const tp = ev.transcript_path;
    if (tp && fs.existsSync(tp)) {
      const st2 = loadState();
      const size = fs.statSync(tp).size;
      const from = (st2.s.tsOffset && st2.s.tsOffset <= size) ? st2.s.tsOffset : 0;
      if (size > from) {
        const fd = fs.openSync(tp, 'r');
        const buf = Buffer.alloc(size - from);
        fs.readSync(fd, buf, 0, buf.length, from);
        fs.closeSync(fd);
        let inTok = 0, outTok = 0;
        for (const line of buf.toString('utf8').split('\n')) {
          const m = line.match(/"usage":\{[^}]*"output_tokens":(\d+)/);
          if (m) {
            outTok += Number(m[1]);
            const mi = line.match(/"input_tokens":(\d+)/);
            if (mi) inTok += Number(mi[1]);
          }
        }
        st2.s.tsOffset = size;
        st2.s.tokensOut = (st2.s.tokensOut || 0) + outTok;
        st2.s.tokensIn = (st2.s.tokensIn || 0) + inTok;
        saveState(st2);
        emit('STEP_OK', { step: `tokens this session: ${st2.s.tokensOut} out / ${st2.s.tokensIn} in`, tokens: st2.s.tokensOut });
      }
    }
  } catch { /* ledger must never break the turn */ }

  // DEVRIDAIM — the cycle must survive the session. Every turn-end, distill
  // the session's state into .rabadon/handoff.md; SessionStart injects it, so
  // the NEXT session (tomorrow, after a crash, after compact) starts where
  // this one stood. Deterministic, from the trail — no model, no cost.
  try {
    const st = loadState();
    const today = path.join(process.env.RABADON_DIR || path.join(process.env.HOME || '', '.rabadon'), 'spool', new Date().toISOString().slice(0, 10) + '.jsonl');
    let caught = [];
    try {
      for (const line of fs.readFileSync(today, 'utf8').split('\n')) {
        if (!line.includes(`"${project}:session"`)) continue;
        try { const e = JSON.parse(line); if (e.ev === 'STOP' && e.reason === 'BLOCKED') caught.push(String(e.detail || '').split('\n')[0].slice(0, 90)); } catch { }
      }
    } catch { }
    const tests = (st.lastTestFail || 0) > (st.lastTestPass || 0)
      ? `RED (since ${new Date(st.lastTestFail).toLocaleTimeString()})`
      : st.lastTestPass ? `green (last pass ${new Date(st.lastTestPass).toLocaleTimeString()})` : 'not run this cycle';
    const moves = (st.s.recent || []).slice(-8).map((r) => `- ${r.s}`).join('\n') || '- (none recorded)';
    const handoff = [
      `# rabadon devridaim — ${project}`,
      `updated: ${new Date().toISOString()}`,
      '',
      `## goal (as captured from the session)`,
      st.s.goalPrompt || '(no goal captured)',
      '',
      `## tests`, tests,
      '',
      `## caught today (blocked before happening)`,
      ...(caught.slice(-6).map((c) => `- ${c}`).length ? caught.slice(-6).map((c) => `- ${c}`) : ['- none']),
      '',
      `## last moves`, moves,
      '',
      `## for the next session`,
      `- if tests are RED above: that is the open front — start there.`,
      `- the guard is law (.rabadon/guard.json); rules born from incidents carry authoredBy: incident.`,
      '',
    ].join('\n');
    fs.writeFileSync(path.join(cwd, '.rabadon', 'handoff.md'), handoff);
  } catch { /* devridaim must never break the turn */ }
  await done('RUN_DONE', { verdict: 'SESSION_TURN_DONE', tokens: 0, depth: 0 });
}
else {
  await done(null);
}
