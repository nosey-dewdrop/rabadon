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

  // 2) already built and newer than every source -> nothing to do
  const gate = path.join(NATIVE, 'rabadon-gate');
  if (fs.existsSync(gate)) {
    const built = fs.statSync(gate).mtimeMs;
    const stale = fs.readdirSync(NATIVE)
      .filter((f) => f.endsWith('.cpp') || f.endsWith('.h'))
      .some((f) => fs.statSync(path.join(NATIVE, f)).mtimeMs > built);
    if (!stale) {
      console.log('rabadon: native binaries already built.');
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

  try {
    execFileSync('make', ['all', `CXX=${cxx}`], { cwd: ROOT, stdio: 'inherit' });
    console.log(`rabadon: native core built with ${cxx}.`);
  } catch {
    console.error(
      [
        '',
        `rabadon: source build FAILED (compiler: ${cxx}).`,
        "  diagnose with: rabadon doctor",
        '  or build manually: make all   (from the rabadon package directory)',
        '',
        'npm install itself succeeded; rabadon will refuse to guard until built.',
        '',
      ].join('\n'),
    );
    // exit 0 by design — see law at the top
  }
}

main();
