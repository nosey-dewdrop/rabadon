#!/bin/bash
# discovery_test.sh — the lock can only cover what discovery found, and
# discovery was quietly missing whole suites.
#
# rabadon-truth walks a repo and names the files the arbiter must hash-lock. The
# corpus audit counted what it found against what is really on disk and the gap
# was not small: colinhacks/zod, 170 test files on disk, 2 discovered.
# date-fns/date-fns, 253 on disk, 16 discovered, and not one of the 16 was a real
# test file. Three separate silent bounds did it, and none of them said a word.
#
#   DEPTH. The walk stopped at depth 4. zod keeps its suite at
#   packages/zod/src/v4/classic/tests/*.test.ts, which is deeper than that, so
#   the walk turned around before it ever saw a test.
#
#   NAME. The patterns were test_ at the front, or _test. / .test. / .spec.
#   inside the name, or a test/ or tests/ directory on the path. date-fns names
#   every one of its files `test.ts` and puts it beside the function it tests,
#   src/addDays/test.ts, so the name matches nothing and the path matches
#   nothing.
#
#   COUNT. The list stopped at 512 files and the walk stopped after 20000
#   entries, both without a word. A cap nobody is told about is the same class of
#   bug as the one that took repair's lock list to 32 and let a foreign repo
#   through as VERIFIED.
#
# Every case here has a twin, because widening discovery is how you start
# hash-locking source files and refusing honest repairs: a fix that edits
# lib/latest.py must not be read as a test because the word test is in the path
# of something else.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
TRUTH="$HERE/rabadon-truth"
[ -x "$TRUTH" ] || { echo "build first: make native/rabadon-truth"; exit 1; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rabadon-discovery.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# $1 dir -> prints the discovered test files, one per line
found() { "$TRUTH" "$1" --json 2>/dev/null | python3 -c 'import json,sys; [print(x) for x in json.load(sys.stdin).get("testFiles",[])]'; }
capped() { "$TRUTH" "$1" --json 2>/dev/null | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin).get("discoveryCapped",[])))'; }

echo "discovery — the lock can only cover what this finds"
echo

# ---------------------------------------------------------------------------
# 1. DEPTH: a monorepo suite, the shape zod has
# ---------------------------------------------------------------------------
D="$ROOT/deep"
mkdir -p "$D/packages/zed/src/v4/classic/tests" "$D/packages/zed/src/v4/classic"
cat > "$D/package.json" <<'EOF'
{ "name": "deep", "version": "1.0.0", "private": true, "scripts": { "test": "true" } }
EOF
echo "export const add = (a,b) => a+b;" > "$D/packages/zed/src/v4/classic/add.ts"
for f in string number object array; do
  echo "test('$f', () => {});" > "$D/packages/zed/src/v4/classic/tests/$f.test.ts"
done
N=$(found "$D" | grep -c "classic/tests/")
if [ "$N" -eq 4 ]; then ok "a suite six directories down is discovered (4 of 4)"
else bad "a suite six directories down: found $N of 4"; found "$D" | sed 's/^/        /' | head -5; fi
if found "$D" | grep -q "classic/add.ts"; then bad "the source file beside it was read as a test"
else ok "the source file beside it is NOT read as a test"; fi

# ---------------------------------------------------------------------------
# 2. NAME: the file is called test.ts and sits next to what it tests, date-fns
# ---------------------------------------------------------------------------
N2="$ROOT/named"
mkdir -p "$N2/src/addDays" "$N2/src/subDays" "$N2/src/addHours" "$N2/src/subHours" "$N2/src/latest"
cat > "$N2/package.json" <<'EOF'
{ "name": "named", "version": "1.0.0", "private": true, "scripts": { "test": "true" } }
EOF
for f in addDays subDays addHours subHours; do
  echo "export function $f() {}" > "$N2/src/$f/index.ts"
  echo "test('$f', () => {});"   > "$N2/src/$f/test.ts"
done
# the twin: a source file whose own name contains the word, and a directory
# called latest. Neither is a test and widening the pattern must not take them.
echo "export const latest = 1;" > "$N2/src/latest/index.ts"
echo "export const contest = 1;" > "$N2/src/latest/contest.ts"
F2=$(found "$N2")
G2=$(printf '%s\n' "$F2" | grep -c "/test.ts$")
if [ "$G2" -eq 4 ]; then ok "a suite whose files are all named test.ts is discovered (4 of 4)"
else bad "files named test.ts: found $G2 of 4"; printf '%s\n' "$F2" | sed 's/^/        /' | head -5; fi
if printf '%s\n' "$F2" | grep -qE "contest.ts|latest/index.ts"; then
  bad "a source file was read as a test because its name contains the word"
else ok "contest.ts and latest/index.ts are not read as tests"; fi

# the twin that matters most, and the one a real repo caught: ONE file called
# test.py is not a convention, it is a stray, and locking it refuses a fix to
# something that was never a test. jinja has exactly this shape --
# examples/basic/test.py, plus src/jinja2/tests.py which is SOURCE (the `is
# defined` tests the template language exposes). Both were being locked.
S1="$ROOT/stray"
mkdir -p "$S1/src/pkg" "$S1/examples/basic" "$S1/tests"
cat > "$S1/package.json" <<'EOF'
{ "name": "stray", "version": "1.0.0", "private": true, "scripts": { "test": "true" } }
EOF
echo "export const x = 1;" > "$S1/src/pkg/index.ts"
echo "export const tests = {};" > "$S1/src/pkg/tests.ts"
echo "console.log('demo');"    > "$S1/examples/basic/test.ts"
echo "test('real', () => {});" > "$S1/tests/real.test.ts"
FS=$(found "$S1")
if printf '%s\n' "$FS" | grep -qE "examples/basic/test.ts|src/pkg/tests.ts"; then
  bad "a stray test.ts and a source module called tests.ts were locked as tests"
  printf '%s\n' "$FS" | sed 's/^/        /'
else ok "one stray test.ts is not a convention, and tests.ts is source: neither is locked"; fi
if printf '%s\n' "$FS" | grep -q "tests/real.test.ts"; then ok "the real suite in the same repo is still discovered"
else bad "the real suite was lost"; fi

# ---------------------------------------------------------------------------
# 3. COUNT: a suite past the list cap has to SAY it was capped
# ---------------------------------------------------------------------------
B="$ROOT/big"
mkdir -p "$B/tests"
cat > "$B/package.json" <<'EOF'
{ "name": "big", "version": "1.0.0", "private": true, "scripts": { "test": "true" } }
EOF
i=0
while [ "$i" -lt 620 ]; do echo "test('t$i', () => {});" > "$B/tests/case_$i.test.js"; i=$((i+1)); done
NB=$(found "$B" | wc -l | tr -d ' ')
CAP=$(capped "$B")
if [ "$NB" -ge 620 ]; then
  ok "a 620-file suite is discovered whole ($NB)"
elif printf '%s' "$CAP" | grep -q "."; then
  ok "a capped walk SAYS it was capped (discoveryCapped: $CAP, found $NB)"
else
  bad "found $NB of 620 and said nothing about a cap"
fi

# a normal repo must not claim it was capped
CAP2=$(capped "$N2")
if [ -z "$CAP2" ]; then ok "an ordinary repo reports no cap"
else bad "an ordinary repo claims discoveryCapped: $CAP2"; fi

echo
echo "  pass $pass   fail $fail"
[ "$fail" -eq 0 ] && echo "  discovery: GREEN" || echo "  discovery: RED"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
