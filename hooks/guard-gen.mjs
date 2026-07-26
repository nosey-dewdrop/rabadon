// rabadon guard — rabadon writes the project's own guard rules.
//
// Reads the project's law files (RULES.md, ENV.md, CLAUDE.md — whatever
// exists), hands them to Claude (local Claude Code CLI, zero keys) and asks
// for MACHINE-CHECKABLE rules in a fixed schema. The output is written to
// ${project}/.rabadon/guard.json where hooks/gate.mjs enforces it
// deterministically on every tool call.
//
// The LLM runs ONCE, at authoring time, and its output is a reviewable file —
// enforcement itself is regex/state, <50ms, no model in the hot path.

import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';

const LAW_FILES = ['RULES.md', 'ENV.md', 'CLAUDE.md'];

const SCHEMA_PROMPT = `You are rabadon, a reliability runtime. Below are the LAW FILES of a software project. Extract the rules that can be enforced MECHANICALLY on a coding agent's tool calls, and return ONLY a JSON object (no fences, no prose) with this exact shape:

{
  "project": "<name>",
  "bash": [ { "id": "kebab-id", "deny": "<JS regex, case-insensitive, matched against the full bash command>", "why": "<one line: which law, why>" } ],
  "protectedPaths": [ { "id": "kebab-id", "match": "<JS regex matched against the file path being edited/written>", "why": "<one line>" } ],
  "codePaths": [ "<JS regex for paths that count as CODE (used to demand tests before push)>" ],
  "testCommand": "<JS regex matching the project's test command>",
  "testPassPattern": "<JS regex that appears in the test output ONLY when fully green>",
  "pushGate": { "why": "<the law that says tests must be green before push>", "testHint": "<human hint>", "run": "<the LITERAL shell command that builds and runs the full suite from the project root — rabadon executes this itself at the push gate>", "timeoutSec": 600 }
}

Rules for writing rules:
- Only include what the law files actually say. Do not invent policy.
- bash deny rules are for actions the laws forbid (e.g. force push, destructive resets, editing generated files via shell, bypassing a required step). Also always include: git push --force to main, rm -rf outside the project, git reset --hard on shared branches.
- protectedPaths are files the laws say must never be hand-edited (e.g. generated files) or must not change (e.g. golden references) — the agent should change the GENERATOR or the source, not these.
- Keep every regex simple and safe. Prefer false-negative over false-positive: a wrongly blocked legitimate action poisons trust in the gate.
- If the laws don't define something (e.g. no test command), omit that key entirely.

THE LAW FILES:
`;

function runClaude(prompt, timeoutMs = 180000) {
  return new Promise((resolve, reject) => {
    const child = execFile('claude', ['-p', '--output-format', 'text'],
      { timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024 },
      (err, stdout, stderr) => {
        if (err) reject(new Error((stderr || err.message).slice(0, 300)));
        else resolve(String(stdout).trim());
      });
    child.stdin.write(prompt);
    child.stdin.end();
  });
}

export async function generateGuard(projectDir) {
  const laws = [];
  for (const f of LAW_FILES) {
    const p = path.join(projectDir, f);
    if (fs.existsSync(p)) laws.push(`\n===== ${f} =====\n` + fs.readFileSync(p, 'utf8').slice(0, 12000));
  }
  if (!laws.length) throw new Error(`rabadon guard: no law files (${LAW_FILES.join('/')}) found in ${projectDir}`);

  const out = await runClaude(SCHEMA_PROMPT + laws.join('\n'));
  const jsonText = out.replace(/^```(?:json)?\s*|\s*```$/g, '');
  let guard;
  try { guard = JSON.parse(jsonText); } catch {
    throw new Error(`rabadon guard: model returned unparseable guard JSON: ${out.slice(0, 200)}`);
  }

  // validate every regex NOW — a broken rule must fail at authoring time,
  // not silently at gate time
  for (const r of [...(guard.bash || []), ...(guard.protectedPaths || [])]) {
    new RegExp(r.deny || r.match, 'i');
  }
  for (const p of guard.codePaths || []) new RegExp(p, 'i');
  if (guard.testCommand) new RegExp(guard.testCommand, 'i');
  if (guard.testPassPattern) new RegExp(guard.testPassPattern, 'i');

  guard.generatedBy = 'rabadon guard (claude code cli)';
  const dir = path.join(projectDir, '.rabadon');
  fs.mkdirSync(dir, { recursive: true });
  const guardPath = path.join(dir, 'guard.json');
  fs.writeFileSync(guardPath, JSON.stringify(guard, null, 2) + '\n');
  return { guardPath, guard };
}
