// guard-gen evidence collection — the wild-repo contract.
// A stranger's repo has no CLAUDE.md; authoring must still find its law
// (README/CONTRIBUTING/AGENTS.md) and its facts (manifest, CI). No LLM here:
// collectEvidence is pure filesystem and is tested as such.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { collectEvidence, generateGuard } from './guard-gen.mjs';

function mkrepo(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'guardgen-'));
  for (const [rel, text] of Object.entries(files)) {
    const p = path.join(dir, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, text);
  }
  return dir;
}

test('express-shaped repo: case-insensitive Readme.md + manifest + CI found', () => {
  const dir = mkrepo({
    'Readme.md': '# express',
    'package.json': '{"name":"express","scripts":{"test":"mocha"}}',
    '.github/workflows/ci.yml': 'jobs: {test: {}}',
    '.github/workflows/codeql.yml': 'jobs: {analyze: {}}',
  });
  const { law, facts } = collectEvidence(dir);
  assert.deepEqual(law.map((l) => l.name), ['Readme.md']);
  assert.ok(facts.some((f) => f.name === 'package.json'));
  assert.ok(facts.some((f) => f.name === '.github/workflows/ci.yml'));
});

test('AGENTS.md and CONTRIBUTING.md rank as law, before README', () => {
  const dir = mkrepo({
    'AGENTS.md': 'agent law',
    'CONTRIBUTING.md': 'contrib law',
    'README.md': 'readme',
    'go.mod': 'module github.com/cli/cli',
  });
  const { law, facts } = collectEvidence(dir);
  assert.deepEqual(law.map((l) => l.name), ['AGENTS.md', 'CONTRIBUTING.md', 'README.md']);
  assert.deepEqual(facts.map((f) => f.name), ['go.mod']);
});

test('one README, one CONTRIBUTING — no duplicates across extensions', () => {
  const dir = mkrepo({
    'README.md': 'md readme',
    'README.rst': 'rst readme',
    'CONTRIBUTING.rst': 'rst contrib',
  });
  const { law } = collectEvidence(dir);
  assert.equal(law.filter((l) => l.base === 'readme').length, 1);
  assert.equal(law.filter((l) => l.base === 'contributing').length, 1);
});

test('nested .github/CONTRIBUTING.md is found when top-level is absent', () => {
  const dir = mkrepo({
    'README.md': 'readme',
    '.github/CONTRIBUTING.md': 'hidden contrib',
  });
  const { law } = collectEvidence(dir);
  assert.ok(law.some((l) => l.name === path.join('.github', 'CONTRIBUTING.md')));
});

test('workflows are capped at two, test-shaped first', () => {
  const dir = mkrepo({
    'Cargo.toml': '[package]\nname = "ripgrep"',
    '.github/workflows/release.yml': 'release',
    '.github/workflows/ci.yml': 'ci',
    '.github/workflows/tests.yaml': 'tests',
    '.github/workflows/lint.yml': 'lint',
  });
  const { facts } = collectEvidence(dir);
  const wf = facts.filter((f) => f.name.startsWith('.github/workflows/'));
  assert.equal(wf.length, 2);
  assert.equal(wf[0].name, '.github/workflows/tests.yaml');
  assert.equal(wf[1].name, '.github/workflows/ci.yml');
});

test('empty dir yields empty evidence and generateGuard refuses before any LLM', async () => {
  const dir = mkrepo({});
  const { law, facts } = collectEvidence(dir);
  assert.equal(law.length + facts.length, 0);
  await assert.rejects(() => generateGuard(dir), /no evidence found/);
});
