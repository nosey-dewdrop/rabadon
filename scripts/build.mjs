// rabadon postinstall build — compile the native core from source when no
// prebuilt platform package is available.
//
// Law of this script:
//   - if a prebuilt @rabadon/<os>-<cpu> package is installed: do NOTHING
//     (prebuilts are the paved road; source build is the fallback);
//   - if the binaries are already built and current: do NOTHING (idempotent);
//   - if compilation fails or no compiler exists: print the exact fix and
//     EXIT 0 — `npm install` must never brick a dependency tree over an
//     optional binary. The point of guarding (rabadon init / the gate) fails
//     CLOSED with the same doctor message; installing fails OPEN.

import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { missingCore } from '../hooks/install.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const NATIVE = path.join(ROOT, 'native');

const plat = () => {
  const os = { darwin: 'darwin', linux: 'linux' }[process.platform];
  const cpu = { arm64: 'arm64', x64: 'x64' }[process.arch];
  return os && cpu ? `${os}-${cpu}` : null;
};

const prebuiltDirs = () => {
  const p = plat();
  return p
    ? [path.join(ROOT, 'node_modules', '@rabadon', p), path.join(ROOT, '..', '@rabadon', p)]
    : [];
};

function findCompiler() {
  for (const cxx of ['clang++', 'g++', 'c++']) {
    const r = spawnSync(cxx, ['--version'], { stdio: 'ignore' });
    if (r.status === 0) return cxx;
  }
  return null;
}

function main() {
  // 1) prebuilt present -> nothing to build
  if (prebuiltDirs().some((d) => fs.existsSync(path.join(d, 'rabadon-gate')))) {
    console.log('rabadon: prebuilt platform binaries found — no source build needed.');
    return;
  }

  // 2) already built and newer than every source -> nothing to do.
  //    "built" is the WHOLE core (derived from the Makefile), not rabadon-gate
  //    alone: a build that stopped on a late target leaves gate in place, and
  //    on that evidence this script used to declare the core built and skip the
  //    rebuild that would have finished it.
  const core = missingCore();
  if (core.names.length === 0) {
    console.error('');
    console.error(`rabadon: no Makefile at ${core.makefile} — nothing to build the native core from.`);
    console.error('  reinstall the package (npm i -g rabadon), then: rabadon doctor');
    console.error('');
    return; // exit 0 by design — see law at the top
  }
  const gate = path.join(NATIVE, 'rabadon-gate');
  if (fs.existsSync(gate) && core.missing.length === 0) {
    const built = fs.statSync(gate).mtimeMs;
    const stale = fs.readdirSync(NATIVE)
      .filter((f) => f.endsWith('.cpp') || f.endsWith('.h'))
      .some((f) => fs.statSync(path.join(NATIVE, f)).mtimeMs > built);
    if (!stale) {
      console.log(`rabadon: native binaries already built (${core.names.length}/${core.names.length}).`);
      return;
    }
  }

  // 3) build from source
  const cxx = findCompiler();
  if (!cxx) {
    console.error(
      [
        '',
        'rabadon: no C++ compiler found — the native core was NOT built.',
        '  macOS:  xcode-select --install',
        '  debian: sudo apt install g++ make',
        '  fedora: sudo dnf install gcc-c++ make',
        "  then:   run 'rabadon doctor' (it rebuilds and verifies)",
        '',
        'npm install itself succeeded; rabadon will refuse to guard until built.',
        '',
      ].join('\n'),
    );
    return; // exit 0 by design — see law at the top
  }

  // `make` stops at the FIRST target that fails, so a build that dies late
  // leaves a usable-looking tree: 15 of 16 binaries, npm install exit 0, and
  // every command belonging to the missing one dead at first use. Whatever make
  // says, the count below is measured from disk afterwards and named.
  let failed = false;
  try {
    execFileSync('make', ['all', `CXX=${cxx}`], { cwd: ROOT, stdio: 'inherit' });
  } catch {
    failed = true;
  }
  const after = missingCore();
  const n = after.names.length;
  if (after.missing.length === 0) {
    console.log(`rabadon: native core built with ${cxx} (${n}/${n} binaries).`);
    return;
  }
  console.error(
    [
      '',
      failed
        ? `rabadon: source build FAILED (compiler: ${cxx}) — ${n - after.missing.length} of ${n} binaries built.`
        : `rabadon: make reported success but only ${n - after.missing.length} of ${n} binaries are present.`,
      `  absent: ${after.missing.join('  ')}`,
      '  each one is a command that fails when you run it, not when you install it',
      '  diagnose with: rabadon doctor',
      '  or build manually: make all   (from the rabadon package directory)',
      '',
      'npm install itself succeeded; rabadon will refuse to guard until built.',
      '',
    ].join('\n'),
  );
  // exit 0 by design — see law at the top
}

main();
