// rabadon do — the motor. Task in, verified output out.
//
// The failure this kills, in the builder's words: a 10-step pipeline hits a
// fault at one gate, the flow says "continue" anyway, and the final output is
// ECLECTIC — half old plan, half improvisation, coherent to nobody. rabadon's
// job is to foresee that moment AT THE GATE WHERE IT IS BORN and pivot there,
// in the background, so the only thing the builder ever sees is the output
// they asked for.
//
// Architecture (token-frugal by construction):
//   PLAN    one LLM call. The task is decomposed into steps; EVERY step gets a
//           MECHANICAL contract (command exits green / file exists / pattern
//           present). No LLM judges a contract — checks are free forever.
//   RUN     deterministic runner. cmd steps cost zero tokens; work steps are
//           the actual labor (headless claude, narrow instruction).
//   GATE    after every step its contract runs BEFORE anything flows onward.
//           A broken contract cannot leak downstream — the eclectic output is
//           structurally impossible, not hopefully avoided.
//   PIVOT   on a broken gate: one repair attempt (LLM, given the exact
//           contract failure). Still broken: ONE replan of the remaining
//           steps from the point of deviation. Bounded; then fail-closed.
//   ACCEPT  the task-level contract runs at the end. "Done" is a measurement.
//
// Remove the LLM and what remains: the runner, the contract engine, the gate
// semantics, the bounds, the event stream. That is the moat test passing.

import fs from 'node:fs';
import path from 'node:path';
import { execSync, execFile } from 'node:child_process';
import { emitter } from '../core/bus.mjs';

const PLAN_PROMPT = (task, dir, tree) => `You are rabadon's planner. Decompose the task into a pipeline whose every step is verifiable BY MACHINE. Return ONLY JSON, no fences:

{ "steps": [ { "id": "s1", "kind": "cmd" | "work",
    "do": "<kind=cmd: the literal shell command. kind=work: a narrow, self-contained instruction for a coding agent>",
    "contract": [ { "type": "cmd", "run": "<shell command>", "passPattern": "<regex that appears ONLY on success; omit to accept exit 0>" }
                | { "type": "fileExists", "path": "<relative path>" }
                | { "type": "fileContains", "path": "<relative path>", "pattern": "<regex>" } ] } ],
  "accept": [ <same contract shapes — the TASK-level definition of done> ] }

Laws:
- 3 to 10 steps. Prefer kind=cmd (zero cost) wherever a shell command can do the job; kind=work only where judgment/writing code is unavoidable.
- EVERY step gets at least one contract, and contracts must be mechanical — a human or model must never be needed to decide pass/fail.
- accept[] must capture what the user actually asked for, not a proxy.
- Steps run in the project directory: ${dir}
- Project files (top level): ${tree}

THE TASK: ${task}`;

function runClaude(prompt, { cwd, timeoutMs = 20 * 60000, worker = false } = {}) {
  return new Promise((resolve, reject) => {
    const args = ['-p', '--output-format', 'text'];
    if (worker) { args.push('--permission-mode', 'acceptEdits', '--allowedTools', 'Read,Edit,Write,Bash,Grep,Glob'); }
    const child = execFile('claude', args, { cwd, timeout: timeoutMs, maxBuffer: 8 * 1024 * 1024 },
      (err, stdout, stderr) => err ? reject(new Error((stderr || err.message).slice(0, 300))) : resolve(String(stdout).trim()));
    child.stdin.write(prompt);
    child.stdin.end();
  });
}

function checkContract(contract, dir) {
  const fails = [];
  for (const c of contract || []) {
    try {
      if (c.type === 'cmd') {
        let out = '';
        try { out = execSync(c.run, { cwd: dir, encoding: 'utf8', timeout: 10 * 60000, stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 16 * 1024 * 1024 }); }
        catch (e) { fails.push({ check: c.run, why: `exit!=0: ${String((e.stdout || '') + (e.stderr || '')).slice(-300)}` }); continue; }
        if (c.passPattern && !new RegExp(c.passPattern, 'im').test(out)) fails.push({ check: c.run, why: `pass pattern "${c.passPattern}" absent. tail: ${out.slice(-200)}` });
      } else if (c.type === 'fileExists') {
        if (!fs.existsSync(path.join(dir, c.path))) fails.push({ check: `fileExists ${c.path}`, why: 'missing' });
      } else if (c.type === 'fileContains') {
        const body = fs.readFileSync(path.join(dir, c.path), 'utf8');
        if (!new RegExp(c.pattern, 'im').test(body)) fails.push({ check: `fileContains ${c.path}`, why: `pattern "${c.pattern}" absent` });
      } else {
        fails.push({ check: JSON.stringify(c).slice(0, 60), why: 'unknown contract type (fail-closed)' });
      }
    } catch (e) {
      fails.push({ check: JSON.stringify(c).slice(0, 60), why: String(e.message).slice(0, 120) });
    }
  }
  return fails;
}

const parseJson = (t) => { try { return JSON.parse(t.replace(/^```(?:json)?\s*|\s*```$/g, '')); } catch { return null; } };

export async function runDo(task, dir, { maxReplans = 2 } = {}) {
  const emit = emitter({ pipe: `${path.basename(dir)}:do` });
  const log = (m) => process.stdout.write(m + '\n');
  const tree = fs.readdirSync(dir).filter((f) => !f.startsWith('.')).slice(0, 40).join(', ');

  log(`plan: deriving the pipeline from the task (one model call)…`);
  let plan = parseJson(await runClaude(PLAN_PROMPT(task, dir, tree), { cwd: dir, timeoutMs: 5 * 60000 }));
  if (!plan || !Array.isArray(plan.steps) || !plan.steps.length) throw new Error('rabadon do: planner returned no usable pipeline');
  fs.mkdirSync(path.join(dir, '.rabadon'), { recursive: true });
  fs.writeFileSync(path.join(dir, '.rabadon', 'do-plan.json'), JSON.stringify({ task, ...plan }, null, 2));
  emit('RUN_START', { steps: plan.steps.map((s) => s.id), bound: { maxRepairsPerStep: 1, maxReplans } });
  log(`plan: ${plan.steps.length} steps [${plan.steps.map((s) => `${s.id}:${s.kind}`).join(' ')}] — written to .rabadon/do-plan.json`);

  let replans = 0;
  let queue = [...plan.steps];
  const done = [];

  while (queue.length) {
    const step = queue.shift();
    emit('STEP_START', { step: step.id });
    log(`${step.id} (${step.kind}): ${String(step.do).slice(0, 90)}`);

    const execStep = async (instr) => {
      if (step.kind === 'cmd') {
        try { execSync(instr, { cwd: dir, encoding: 'utf8', timeout: 15 * 60000, stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 16 * 1024 * 1024 }); }
        catch { /* the contract is the judge, not the exit code */ }
      } else {
        await runClaude(`You are one step inside a rabadon pipeline. Do EXACTLY this step, nothing beyond it:\n${instr}\n\nContext: overall task = "${task}". Steps already completed: ${done.map((d) => d.id).join(', ') || 'none'}. Work in the current directory. When the step is done, stop.`, { cwd: dir, worker: true });
      }
    };

    await execStep(step.do);
    let fails = checkContract(step.contract, dir);

    if (fails.length) {
      // THE GATE CAUGHT THE DEVIATION — this is the eclectic moment, killed here.
      emit('CHECK_FAIL', { step: step.id, fails });
      emit('REPAIR_START', { step: step.id, attempt: 1, fixing: fails.map((f) => f.check) });
      log(`  ✗ gate ${step.id}: ${fails[0].why.slice(0, 100)} — pivoting (repair)`);
      await runClaude(`You are rabadon's repair inside a pipeline. Step "${step.id}" (${step.do}) violated its contract:\n${fails.map((f) => `- ${f.check}: ${f.why}`).join('\n')}\nFix the project state so the contract passes. Smallest correct fix. Do not touch anything beyond this step's scope.`, { cwd: dir, worker: true });
      fails = checkContract(step.contract, dir);
      emit(fails.length ? 'REPAIR_FAIL' : 'REPAIR_OK', { step: step.id, attempt: 1 });
    }

    if (fails.length) {
      if (replans >= maxReplans) {
        emit('STOP', { reason: 'CHECK_FAILED', detail: `${step.id} still broken after repair; replan budget spent` });
        emit('RUN_DONE', { verdict: 'CHECK_FAILED' });
        emit.close();
        throw new Error(`rabadon do: gate ${step.id} would not pass and the replan budget is spent — stopped fail-closed, nothing eclectic was produced.`);
      }
      replans++;
      log(`  ⟲ pivot: replanning the remaining pipeline from ${step.id} (${replans}/${maxReplans})`);
      const replan = parseJson(await runClaude(
        PLAN_PROMPT(task, dir, tree) + `\n\nIMPORTANT: steps ${done.map((d) => d.id).join(', ') || '(none)'} are DONE and must not be repeated. Step "${step.id}" failed its contract: ${fails.map((f) => f.why).join('; ')}. Plan ONLY the remaining path to done, taking the failure into account.`,
        { cwd: dir, timeoutMs: 5 * 60000 }));
      if (!replan || !Array.isArray(replan.steps) || !replan.steps.length) throw new Error('rabadon do: replan failed');
      queue = [...replan.steps];
      if (replan.accept) plan.accept = replan.accept;
      continue;
    }

    emit('STEP_OK', { step: step.id });
    done.push(step);
  }

  const acceptFails = checkContract(plan.accept, dir);
  if (acceptFails.length) {
    emit('STOP', { reason: 'CHECK_FAILED', detail: `acceptance: ${acceptFails.map((f) => f.check).join(', ')}` });
    emit('RUN_DONE', { verdict: 'CHECK_FAILED' });
    emit.close();
    throw new Error(`rabadon do: all steps passed their gates but the ACCEPTANCE contract failed: ${acceptFails.map((f) => `${f.check} (${f.why})`).join('; ')} — reporting honest failure, not an eclectic success.`);
  }
  emit('RUN_DONE', { verdict: 'PASS' });
  emit.close();
  log(`accept: PASS — the output is the one that was asked for. (${done.length} steps, ${replans} pivot(s))`);
}
