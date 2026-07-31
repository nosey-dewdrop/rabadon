// rabadon guard — rabadon writes the project's own guard rules.
//
// Gathers the project's EVIDENCE and hands it to Claude (local Claude Code
// CLI, zero keys), asking for MACHINE-CHECKABLE rules in a fixed schema.
// Evidence comes in two ranks:
//   LAW   — files that state policy (RULES.md, ENV.md, CLAUDE.md, AGENTS.md,
//           CONTRIBUTING, README). Deny rules may only come from these.
//   FACTS — manifests and CI (package.json, pyproject.toml, Cargo.toml,
//           go.mod, Makefile, workflow files). Test plumbing (testCommand,
//           testPaths, pushGate.run) is derived from these, never invented.
// A stranger's repo almost never has CLAUDE.md — but it always has a README,
// a manifest, and CI. Authoring must work there, not only at home.
//
// The output is written to ${project}/.rabadon/guard.json where the gate
// enforces it deterministically on every tool call. The LLM runs ONCE, at
// authoring time, and its output is a reviewable file — enforcement itself
// is regex/state, <50ms, no model in the hot path.

import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';

// policy-bearing files, in priority order; matched case-insensitively so
// express's Readme.md and a stray readme.rst both count
const LAW_NAMES = [
  'RULES.md', 'ENV.md', 'CLAUDE.md', 'AGENTS.md', '.cursorrules',
  'CONTRIBUTING.md', 'CONTRIBUTING.rst', 'CONTRIBUTING',
  'README.md', 'README.rst', 'README.markdown', 'README',
];

// fact-bearing files: manifests and build entrypoints
const FACT_NAMES = [
  'package.json', 'pyproject.toml', 'setup.cfg', 'tox.ini', 'noxfile.py',
  'Cargo.toml', 'go.mod', 'Makefile', 'CMakeLists.txt', 'justfile',
];

const PER_FILE_CAP = 12000;
const TOTAL_CAP = 48000;

function findCaseInsensitive(dir, wanted, entries) {
  const lower = wanted.toLowerCase();
  const hit = entries.find((e) => e.toLowerCase() === lower);
  return hit ? path.join(dir, hit) : null;
}

/**
 * Collect the evidence a real repo actually has. Returns
 * { law: [{name, text}], facts: [{name, text}] } — both possibly empty.
 * Exported so it can be tested without an LLM in the room.
 */
export function collectEvidence(projectDir) {
  let entries = [];
  try { entries = fs.readdirSync(projectDir); } catch { /* unreadable dir -> empty evidence */ }

  const seen = new Set();
  const read = (p) => {
    const key = path.resolve(p);
    if (seen.has(key)) return null;
    seen.add(key);
    try {
      const st = fs.statSync(p);
      if (!st.isFile()) return null;
      return fs.readFileSync(p, 'utf8').slice(0, PER_FILE_CAP);
    } catch { return null; }
  };

  const law = [];
  for (const name of LAW_NAMES) {
    const p = findCaseInsensitive(projectDir, name, entries);
    if (!p) continue;
    const base = name.replace(/\.(md|rst|markdown)$/i, '').toLowerCase();
    if (law.some((l) => l.base === base)) continue; // one README, one CONTRIBUTING
    const text = read(p);
    if (text) law.push({ name: path.basename(p), base, text });
  }
  // nested conventions: .github/CONTRIBUTING.md, docs/CONTRIBUTING.md
  if (!law.some((l) => l.base === 'contributing')) {
    for (const sub of ['.github', 'docs']) {
      const subDir = path.join(projectDir, sub);
      let subEntries = [];
      try { subEntries = fs.readdirSync(subDir); } catch { continue; }
      const p = findCaseInsensitive(subDir, 'CONTRIBUTING.md', subEntries);
      const text = p && read(p);
      if (text) { law.push({ name: path.join(sub, path.basename(p)), base: 'contributing', text }); break; }
    }
  }

  const facts = [];
  for (const name of FACT_NAMES) {
    const p = findCaseInsensitive(projectDir, name, entries);
    const text = p && read(p);
    if (text) facts.push({ name: path.basename(p), text });
  }
  // CI workflows carry the project's real test command; take the two most
  // test-shaped ones
  const wfDir = path.join(projectDir, '.github', 'workflows');
  let wf = [];
  try { wf = fs.readdirSync(wfDir).filter((f) => /\.ya?ml$/i.test(f)); } catch { /* no CI */ }
  wf.sort((a, b) => {
    const rank = (f) => (/test/i.test(f) ? 0 : /^ci\./i.test(f) || /(^|[^a-z])ci([^a-z]|$)/i.test(f) ? 1 : 2);
    return rank(a) - rank(b) || a.localeCompare(b);
  });
  for (const f of wf.slice(0, 2)) {
    const text = read(path.join(wfDir, f));
    if (text) facts.push({ name: `.github/workflows/${f}`, text: text.slice(0, 6000) });
  }

  return { law, facts };
}

const SCHEMA_PROMPT = `You are rabadon, a reliability runtime. Below is the EVIDENCE of a software project, in two ranks: LAW FILES (explicit policy: rules, agent instructions, contributing guides, README) and PROJECT FACTS (manifests and CI config — what the project mechanically is). Extract the rules that can be enforced MECHANICALLY on a coding agent's tool calls, and return ONLY a JSON object (no fences, no prose) with this exact shape:

{
  "project": "<name>",
  "bash": [ { "id": "kebab-id", "deny": "<JS regex, case-insensitive, matched against the full bash command>", "why": "<one line: which evidence, why>" } ],
  "protectedPaths": [ { "id": "kebab-id", "match": "<JS regex matched against the file path being edited/written>", "why": "<one line>" } ],
  "codePaths": [ "<JS regex for paths that count as CODE (used to demand tests before push)>" ],
  "testPaths": [ "<JS regex for TEST files — used to catch test-tampering while the suite is red>" ],
  "testCommand": "<JS regex matching the project's test command>",
  "testPassPattern": "<JS regex that appears in the test output ONLY when fully green>",
  "pushGate": { "why": "<the evidence that says tests must be green before push>", "testHint": "<human hint>", "run": "<the LITERAL shell command that builds and runs the full suite from the project root — rabadon executes this itself at the push gate>", "timeoutSec": 600 }
}

Rules for writing rules:
- Behavioral deny rules come from LAW FILES only. Do not invent policy the laws do not state. Also always include: git push --force to main, rm -rf outside the project, git reset --hard on shared branches.
- Test plumbing (codePaths, testPaths, testCommand, testPassPattern, pushGate) is DERIVED from PROJECT FACTS: the manifest's test script, the CI workflow's test job, the visible test directories. Use the command the project itself runs. This is derivation, not invention.
- protectedPaths are files the evidence marks as generated, vendored, or never-hand-edited (e.g. a lockfile the docs say is tool-managed, golden/snapshot references, generated dirs). The agent should change the GENERATOR or the source, not these. When the evidence marks nothing, leave the list empty.
- Keep every regex simple and safe. Prefer false-negative over false-positive: a wrongly blocked legitimate action poisons trust in the gate.
- If the evidence does not establish something (e.g. no discoverable test command), omit that key entirely.

THE EVIDENCE:
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
  const { law, facts } = collectEvidence(projectDir);
  if (!law.length && !facts.length) {
    throw new Error(`rabadon guard: no evidence found in ${projectDir} (no README/CONTRIBUTING/CLAUDE.md/AGENTS.md, no manifest, no CI)`);
  }

  let body = '';
  const append = (header, items) => {
    if (!items.length) return;
    body += `\n===== ${header} =====\n`;
    for (const { name, text } of items) {
      if (body.length >= TOTAL_CAP) break;
      body += `\n--- ${name} ---\n` + text.slice(0, TOTAL_CAP - body.length) + '\n';
    }
  };
  append('LAW FILES (explicit policy)', law);
  append('PROJECT FACTS (manifests + CI — derive test plumbing from these)', facts);

  const out = await runClaude(SCHEMA_PROMPT + body);
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
  guard.evidence = [...law.map((l) => l.name), ...facts.map((f) => f.name)];
  const dir = path.join(projectDir, '.rabadon');
  fs.mkdirSync(dir, { recursive: true });
  const guardPath = path.join(dir, 'guard.json');
  fs.writeFileSync(guardPath, JSON.stringify(guard, null, 2) + '\n');
  return { guardPath, guard };
}
