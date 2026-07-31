// version.h — one source of truth for the rabadon version string, bumped in
// lockstep with package.json. `rabadon doctor` compares the binary's
// --version against package.json and warns on drift.
#pragma once
#define RABADON_VERSION "0.2.0"
