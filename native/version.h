// version.h — the one source of truth for the rabadon version string. Never
// bumped by hand: `node scripts/prepare-release.mjs <version>` sets it here,
// in package.json, in the four npm/<platform>/package.json, and in the four
// optionalDependencies pins, together.
//
// What checks it, and what each check does NOT cover:
//   native/version_test.sh  every manifest, every source, the Makefile rules
//                           and every built binary that answers --version, at
//                           `make test` time. this is the one that is total.
//   rabadon doctor          asks ONE binary (rabadon-gate) for --version and
//                           compares it to package.json. it is an install
//                           sanity check on a user's machine, not a lockstep
//                           check: rabadon-budget and rabadon-drift printed a
//                           hardcoded 0.1.0 for a whole release and doctor
//                           reported all green, because it never asked them.
//   .github/workflows/release.yml
//                           prepare-release --check against the git tag, at
//                           publish time. last line of defence, not first.
//
// Every rule whose source #includes this file must list it as a prerequisite
// in the Makefile — make does not read #include lines, and a rule that omits
// it answers a version bump with "up to date". version_test.sh asserts that
// both textually and by asking `make -q` after touching this file.
#pragma once
#define RABADON_VERSION "0.2.3-rc.1"
