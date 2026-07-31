#!/usr/bin/env node
// prepare-release — keep every version in lockstep before a publish.
//
//   node scripts/prepare-release.mjs 0.3.0    -> set the version everywhere
//   node scripts/prepare-release.mjs --check 0.3.0
//                                             -> assert everything already ==
//   node scripts/prepare-release.mjs --check  -> assert all versions AGREE
//
// Files kept in sync: package.json, native/version.h, the four
// npm/<platform>/package.json (and the main package's optionalDependencies
// pins). A publish with a drifted version is the classic supply-chain
// footgun; this makes drift a hard error, in CI and locally.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PLATFORMS = ['darwin-arm64', 'darwin-x64', 'linux-x64', 'linux-arm64'];

const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const writeJson = (p, o) => fs.writeFileSync(p, JSON.stringify(o, null, 2) + '\n');

function versionH() {
  const p = path.join(ROOT, 'native', 'version.h');
  const m = fs.readFileSync(p, 'utf8').match(/#define RABADON_VERSION "([^"]+)"/);
  return { path: p, version: m ? m[1] : null };
}
function setVersionH(v) {
  const { path: p } = versionH();
  fs.writeFileSync(p, fs.readFileSync(p, 'utf8').replace(/(#define RABADON_VERSION ")[^"]+(")/, `$1${v}$2`));
}

const args = process.argv.slice(2);
const check = args.includes('--check');
const target = args.find((a) => !a.startsWith('-'));

const pkgPath = path.join(ROOT, 'package.json');
const pkg = readJson(pkgPath);

if (check) {
  const want = target || pkg.version;
  const found = [];
  found.push(['package.json', pkg.version]);
  found.push(['native/version.h', versionH().version]);
  for (const plat of PLATFORMS) {
    const pp = path.join(ROOT, 'npm', plat, 'package.json');
    found.push([`npm/${plat}`, readJson(pp).version]);
  }
  for (const [k, v] of Object.entries(pkg.optionalDependencies || {}))
    found.push([`optionalDependencies["${k}"]`, v]);

  const bad = found.filter(([, v]) => v !== want);
  if (bad.length) {
    console.error(`version drift (want ${want}):`);
    for (const [k, v] of bad) console.error(`  ${k}: ${v}`);
    process.exit(1);
  }
  console.log(`all versions == ${want}`);
  process.exit(0);
}

if (!target) { console.error('usage: prepare-release <version> | --check [version]'); process.exit(2); }

pkg.version = target;
for (const plat of PLATFORMS) pkg.optionalDependencies[`@rabadon/${plat}`] = target;
writeJson(pkgPath, pkg);
setVersionH(target);
for (const plat of PLATFORMS) {
  const pp = path.join(ROOT, 'npm', plat, 'package.json');
  const o = readJson(pp);
  o.version = target;
  writeJson(pp, o);
}
console.log(`set version ${target} across package.json, native/version.h, and ${PLATFORMS.length} platform packages.`);
console.log('rebuild so the binary reports the new version:  make all');
