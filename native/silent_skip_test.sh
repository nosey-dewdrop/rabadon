#!/usr/bin/env bash
# silent_skip_test.sh — a suite may not get smaller without saying so.
#
# WHY THIS FILE EXISTS, MEASURED
# 2026-08-29, the F3c arbiter, by hand: `make all` then `native/version_test.sh`
# printed **13 passed**. A single `touch native/gate.cpp` and the same file
# printed **11 passed, EXIT=0**. Two assertions — and their mutation proof —
# stopped running, the suite said nothing about it, and it stayed green. One of
# the three legs of the F1e-C gate can therefore shrink by 15% because somebody
# touched a source file, and every counter downstream (DURUM.md's "TEST SAYACI",
# the arbiter's own `grep -cE '^[[:space:]]*ok\b'`) reads the smaller number as
# health.
#
# That is not a bug in version_test.sh. It is a CLASS: `grep -c 'echo "  skip'`
# over native/ found 9 such branches in 8 files on the day this was written.
#
# THE RULE THIS FILE HOLDS (§8.2, and CLAUDE.md's Promise 1: if it cannot check,
# it says so — it never goes quiet):
#
#   A branch that does not run may be RED, or it may be ANNOUNCED WITH A NAME
#   AND A NUMBER. It may not be silent. Concretely, and this is what is checked
#   mechanically below:
#
#     RULE 1 — every line that announces a skip must COUNT it on that same line.
#              The sanctioned form is one line:
#                  skipped() { SKIP=$((SKIP+1)); echo "  SKIP - ..."; }
#              An `echo "  skip - ..."` that increments nothing is a suite
#              shrinking in silence, and it is exactly the shape measured above.
#     RULE 2 — a file that can skip must PRINT that counter. A number kept in a
#              variable nobody echoes is not an announcement.
#
# native/lock_coverage_test.sh already worked this way before this file existed
# (`echo "  pass $pass   fail $fail   skip $skipped"`, and it refuses to print
# GREEN when the two cases that carry its claim were both skipped). It is the
# model, not the exception.
#
# WHAT THIS FILE DOES NOT CLAIM. It is static: it reads the shell source, it
# does not run the eleven suites in every environment. It cannot see a branch
# that vanishes without printing anything at all. That hole is named, not
# hidden — see the NOT COVERED note at the bottom.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SWEEP="$TMP/sweep.py"

# ---------------------------------------------------------------------------
# the sweep. argv: <dir of *_test.sh>. prints one SILENT/UNREPORTED line per
# offence and a `sites=N files=M` census line; exit 1 if there was any offence.
#
# python3 and not grep: this has to look at a line and at the whole file at
# once (rule 2), and BSD grep answers an unsupported pattern with exit 2, which
# a shell reads as "no match" — a checker that reports clean because it never
# ran is the same defect this file is about.
# ---------------------------------------------------------------------------
cat > "$SWEEP" <<'PY'
import os, re, sys

d = sys.argv[1]
problems = []

# a line that PRINTS a skip announcement. The message must start with the word
# (leading spaces and dashes allowed), so `it.skip(...)` inside a fixture, a
# prose comment about skipping, and `--no-skip` in a command line are not hits.
ANNOUNCE = re.compile(r'(?:echo|printf)\s+.{0,4}["\'][\s\-]*(?:[Ss][Kk][Ii][Pp])')
# the same line must move a counter: VAR=$((VAR+1)) in any spelling.
COUNTS   = re.compile(r'(\w+)\s*=\s*\$\(\(\s*\1\s*\+\s*1\s*\)\)')

files = sorted(f for f in os.listdir(d) if f.endswith('_test.sh'))
sites = 0
hit_files = set()
for f in files:
    path = os.path.join(d, f)
    src = open(path, encoding='utf8', errors='replace').read()
    lines = src.splitlines()
    counters = set()
    for i, line in enumerate(lines, 1):
        s = line.strip()
        if s.startswith('#'):
            continue
        if not ANNOUNCE.search(line):
            continue
        sites += 1
        hit_files.add(f)
        m = COUNTS.search(line)
        if not m:
            problems.append(
                f'SILENT native/{f}:{i}: announces a skip and counts nothing — '
                f'the suite gets smaller and still exits 0: {s[:90]}')
        else:
            counters.add(m.group(1))
    # RULE 2: the counter has to reach the reader.
    for c in sorted(counters):
        # any echo/printf that mentions the variable and is NOT the helper line
        shown = False
        for i, line in enumerate(lines, 1):
            if line.strip().startswith('#'):
                continue
            if not re.search(r'(?:echo|printf)\b', line):
                continue
            if COUNTS.search(line):
                continue          # that is the helper itself, not a report
            if re.search(r'[$][{]?' + re.escape(c) + r'\b', line):
                shown = True
                break
        if not shown:
            problems.append(
                f'UNREPORTED native/{f}: skips are counted into ${c} but nothing '
                f'ever prints it — a number no reader sees is not an announcement')

for p in problems:
    print(p)
print(f'sites={sites} files={len(hit_files)} scanned={len(files)}')
sys.exit(1 if problems else 0)
PY

echo "silent skips: a suite may not shrink without saying so"
echo ""

# --- A: the real tree ------------------------------------------------------
OUT="$(python3 "$SWEEP" "$ROOT/native" 2>&1)"; RC=$?
CENSUS="$(printf '%s' "$OUT" | tail -1)"
if [ $RC -eq 0 ]; then
  ok "every skip in native/ is counted and reported: $CENSUS"
else
  bad "a skip announcement in native/ is silent or unreported"
  printf '%s\n' "$OUT" | sed 's/^/    | /'
fi

# --- B: the sweep is not vacuous -------------------------------------------
# A negative claim ("no silent skips") is worth nothing from a regex that
# matches nothing. If the announcement shape ever changes, this goes red before
# arm A goes quietly green.
SITES="$(printf '%s' "$CENSUS" | sed -n 's/.*sites=\([0-9]*\).*/\1/p')"
if [ -n "$SITES" ] && [ "$SITES" -ge 5 ]; then
  ok "the sweep can see skip announcements at all: $SITES site(s) found"
else
  bad "the sweep found $SITES skip site(s) — it is not matching the announcement shape any more"
fi

# --- C: MUTATION PROOF, built in. The sweep is run against a planted pair:
#        one silent skip, one counted-and-reported skip. It must flag exactly
#        the first. A check that cannot fail is a line in a log.
#
# THE PLANTS ARE ASSEMBLED, NOT PASTED. If the offending line were written
# literally in this file, this file would be its own first offender and the
# sweep would have to be taught to look away from one path — a sweep with an
# exemption is the hole it is looking for. `$W` holds the word instead.
M="$TMP/mut"; mkdir -p "$M"; W=skip
cat > "$M/silent_test.sh" <<EOF
#!/usr/bin/env bash
PASS=0
ok() { PASS=\$((PASS+1)); echo "  ok   - \$1"; }
if [ -x /nonexistent ]; then ok "ran"; else echo "  $W - the tool is missing"; fi
echo "silent: \$PASS passed"
EOF
cat > "$M/good_test.sh" <<EOF
#!/usr/bin/env bash
PASS=0; SKIP=0
ok()      { PASS=\$((PASS+1)); echo "  ok   - \$1"; }
${W}ped() { SKIP=\$((SKIP+1)); echo "  ${W} - \$1"; }
if [ -x /nonexistent ]; then ok "ran"; else ${W}ped "arm A: 1 assertion did NOT run"; fi
echo "good: \$PASS passed, \$SKIP ${W}ped"
EOF
MO="$(python3 "$SWEEP" "$M" 2>&1)"; MRC=$?
if [ $MRC -ne 0 ] \
   && printf '%s' "$MO" | grep -q 'SILENT native/silent_test.sh' \
   && ! printf '%s' "$MO" | grep -q 'native/good_test.sh'; then
  ok "a planted silent skip is caught and the counted one is left alone"
else
  bad "the sweep did not separate a silent skip from a counted one"
  printf '%s\n' "$MO" | sed 's/^/    | /'
fi

# --- D: rule 2 can fire on its own. A counter that is incremented and never
#        printed must be caught, or "counted" degrades into "counted somewhere".
N="$TMP/unrep"; mkdir -p "$N"
cat > "$N/quiet_test.sh" <<EOF
#!/usr/bin/env bash
PASS=0; SKIP=0
ok()      { PASS=\$((PASS+1)); echo "  ok   - \$1"; }
${W}ped() { SKIP=\$((SKIP+1)); echo "  ${W} - \$1"; }
if [ -x /nonexistent ]; then ok "ran"; else ${W}ped "arm A"; fi
echo "quiet: \$PASS passed"
EOF
NO="$(python3 "$SWEEP" "$N" 2>&1)"; NRC=$?
if [ $NRC -ne 0 ] && printf '%s' "$NO" | grep -q 'UNREPORTED native/quiet_test.sh'; then
  ok "a skip counter that nothing prints is caught as unreported"
else
  bad "an uncounted-to-the-reader skip must not pass"
  printf '%s\n' "$NO" | sed 's/^/    | /'
fi

# NOT COVERED, on purpose and in writing: this file reads source, so a branch
# that runs no assertions and prints nothing at all is invisible to it. The
# only tool that sees that one is a per-suite assertion count pinned from
# outside, and nothing in this repo has one yet.
echo ""
echo "silent skip: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
