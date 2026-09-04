# f1d-B-kilit — the status claim, locked against the real gate

**yapılan** — `native/status_truth_test.sh` (new, chmod +x). 16-cell matrix
(mode {watch,enforce} × `<proj>/.rabadon/off` × `RABADON_OFF=1` ×
`<RABADON_DIR>/silent`), 3 claims per cell (`status`, `on`, `off`), each claim
checked against the real `native/rabadon-gate` exit code + output byte count for
the same PreToolUse event, plus `--statusline` agreement, plus the §4.8
disclosure triple. Hermetic (mktemp project + mktemp RABADON_DIR + mktemp HOME),
needs only git and a shell. Section C is the routing pin. Commit: see below.

**ölçülen** — `make all` → exit 0 (`make: Nothing to be done for 'all'`).
`bash native/status_truth_test.sh; echo "EXIT=$?"` → **17 ok / 77 fail, EXIT=1**
(verbatim: `reports/kosu/RAPOR/f1d-2-bosyesil.out`). The two named FAILs are on
lines 67 and 68 of that file: `[mode=enforce projoff=yes RABADON_OFF=no
silent=no] status — the screen claims ON but the real gate answered exit 0 with
0 bytes` and `... status/lamp — status says ON but --statusline says "off"`.
Positive control GREEN (a cell really got gate exit 2), hermeticity GREEN,
routing pin GREEN 4/4 (bin → `native/rabadon-cli.sh`; `on|off|status)` arm →
`nbin gate`, no `rabadon.mjs`; `toggle)` arm same; no npm script routes a
supervision verb to the anti-path).

**yapılamayan** — nothing wired into `Makefile` (card forbids it); the suite is
run by hand until another commit adds it. No fix attempted — the red is the
deliverable.

**kart dışı fark edilen (DOKUNMA)** — (1) `--status` (gate.cpp ~2535) consults
only `<RABADON_DIR>/mode|enabled|silent` and never `RABADON_OFF` or
`<cwd>/.rabadon/off`, and when `mode` exists it ignores `silent` entirely — that
is the ON-vs-0-bytes gap. (2) `--statusline` (gate.cpp ~2421) reads
`enabled`/`.rabadon/on` and never `<RABADON_DIR>/mode`, so with mode=enforce and
no muters the lamp says "watch" while `status` says ON — a THIRD reading of the
same instant. (3) neither surface reads `RABADON_MODE` or `<cwd>/.rabadon/mode`,
which the event path does. (4) `rabadon on` unlinks `silent`, so the silent
muter is lifted by a command whose screen never mentions it.
