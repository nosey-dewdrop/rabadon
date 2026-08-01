#!/usr/bin/env bash
# version_test.sh — one version, said the same way in every place that says it.
#
# Measured on 2026-08-01, before this test existed:
#   package.json               0.2.0   <- the source of truth
#   native/version.h           0.2.0
#   npm/<4 platform packages>  0.2.0
#   optionalDependencies pins  0.2.0
#   rabadon-gate   --version   0.2.0   (reads version.h)
#   rabadon-budget --version   0.1.0   <- hardcoded literal, a release stale
#   rabadon-drift  --version   0.1.0   <- hardcoded literal, a release stale
#   git tag: none. npm: never published. The "v0.4/v0.5/v0.6" in the session
#   notes were session labels, never a product version.
#
# And `touch native/version.h && make native/rabadon-gate` answered
# "up to date": version.h was a prerequisite of no rule at all, so the one
# instruction prepare-release prints after a bump ("rebuild so the binary
# reports the new version: make all") was false. The bump would have shipped
# a binary announcing the previous release, and `rabadon doctor` would have
# reported drift that `make` could not clear.
#
# The checker below is a single function run against the real tree AND against
# eight mutated copies of it, each mutating exactly one version site, and each
# of those eight must FAIL. A drift test that cannot fail is not a drift test;
# it is a line in a log that says everything is fine.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CHECK="$TMP/check.py"

# ---------------------------------------------------------------------------
# the checker. argv: <root> [bindir]. prints one DRIFT line per disagreement,
# exit 1 if there was any. python3, not grep: BSD grep has no -P and answers
# an unsupported pattern with exit 2, which a shell reads as "no match" — a
# checker that reports clean because it never ran.
# ---------------------------------------------------------------------------
cat > "$CHECK" <<'PY'
import json, os, re, subprocess, sys

root = sys.argv[1]
bindir = sys.argv[2] if len(sys.argv) > 2 else None
problems = []
def P(m): problems.append(m)

NATIVE = os.path.join(root, 'native')

# 1. the source of truth. positive assertion first: package.json must actually
#    carry a semver. every check below compares against it, so if this is
#    missing every one of them would compare against None and agree.
pkg = json.load(open(os.path.join(root, 'package.json'), encoding='utf8'))
want = pkg.get('version')
if not want or not re.fullmatch(r'\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?', str(want)):
    print(f'DRIFT package.json: version {want!r} is not a semver — there is no source of truth')
    sys.exit(1)

# 2. native/version.h, the string the C++ core compiles in.
vh = os.path.join(NATIVE, 'version.h')
m = re.search(r'#\s*define\s+RABADON_VERSION\s+"([^"]*)"', open(vh, encoding='utf8').read())
if not m:
    P('native/version.h: no RABADON_VERSION define — the C++ core has no version to be in lockstep with')
elif m.group(1) != want:
    P(f'native/version.h: RABADON_VERSION "{m.group(1)}" != package.json {want}')

# 3. the platform packages. discovered from the directory, never a hand-kept
#    list: a fifth platform added to npm/ must be checked the day it appears,
#    not the day someone remembers to add it here.
npmdir = os.path.join(root, 'npm')
plats = sorted(d for d in os.listdir(npmdir)
               if os.path.isfile(os.path.join(npmdir, d, 'package.json')))
if not plats:
    P('npm/: no platform packages found — the platform arm of this check is vacuous')
for p in plats:
    o = json.load(open(os.path.join(npmdir, p, 'package.json'), encoding='utf8'))
    if o.get('version') != want:
        P(f'npm/{p}/package.json: version {o.get("version")!r} != package.json {want}')
    if o.get('name') != f'@rabadon/{p}':
        P(f'npm/{p}/package.json: name {o.get("name")!r} != @rabadon/{p}')

# 4. the pins that decide which platform package npm actually installs. a pin
#    at the old version installs a binary from the previous release next to
#    this release's wrapper, which is the drift nobody sees until it runs.
pins = pkg.get('optionalDependencies') or {}
if set(pins) != {f'@rabadon/{p}' for p in plats}:
    P(f'optionalDependencies {sorted(pins)} does not cover the platform packages {plats}')
for k, v in sorted(pins.items()):
    if v != want:
        P(f'optionalDependencies["{k}"]: {v!r} != package.json {want}')

srcs = sorted(f for f in os.listdir(NATIVE) if f.endswith(('.cpp', '.h')))
def read(f): return open(os.path.join(NATIVE, f), encoding='utf8', errors='replace').read()

# 5. no source may hardcode what version.h already says. two sweeps, because
#    one line-shaped rule is easy to walk around:
#      a) a line that both handles --version and writes output must write
#         RABADON_VERSION, not a literal;
#      b) any string literal shaped like a version banner ("rabadon-x 1.2.3")
#         is a hardcode wherever it sits.
#    paired with a positive: at least one source must print RABADON_VERSION,
#    otherwise renaming the macro empties both sweeps and they pass forever.
OUT = re.compile(r'\b(printf|fprintf|puts|fputs|cout)\b')
BANNER = re.compile(r'"[^"]*\brabadon-[a-z]+ \d+\.\d+\.\d+')
via_macro = 0
for f in srcs:
    if f == 'version.h':
        continue
    for i, line in enumerate(read(f).splitlines(), 1):
        if '--version' in line and OUT.search(line):
            if 'RABADON_VERSION' in line:
                via_macro += 1
            else:
                P(f'native/{f}:{i}: --version writes a hardcoded version instead of RABADON_VERSION: {line.strip()}')
        elif BANNER.search(line):
            P(f'native/{f}:{i}: hardcoded version banner: {BANNER.search(line).group(0)}"')
if via_macro == 0:
    P('no native source prints RABADON_VERSION — the hardcode sweep has nothing to hold sources to')

# 6. version.h must be a prerequisite of every binary that compiles it in.
#    make does not read #include lines. a rule that omits version.h answers a
#    version bump with "up to date" and ships the previous version's string.
mk = re.sub(r'\\\n\s*', ' ', open(os.path.join(root, 'Makefile'), encoding='utf8').read())
rules = {}
for line in mk.splitlines():
    r = re.match(r'^(native/rabadon-[A-Za-z0-9_-]+)\s*:\s*(.*)$', line)
    if r:
        rules[r.group(1)] = r.group(2).split()
includers = [f for f in srcs if f.endswith('.cpp')
             and re.search(r'#\s*include\s+"version\.h"', read(f))]
if not includers:
    P('no native source includes version.h — nothing is in lockstep with it')
for f in includers:
    target = 'native/rabadon-' + f[:-4]
    prereqs = rules.get(target)
    if prereqs is None:
        P(f'Makefile: no rule for {target}, which includes version.h')
    elif 'native/version.h' not in prereqs:
        P(f'Makefile: {target} includes version.h but does not list it as a prerequisite — a version bump will not rebuild it')

# 7. the docs a stranger reads carry no version literal at all. prepare-release
#    sets package.json, version.h, the platform packages and the pins; it does
#    not touch prose, so a number typed into a doc can only ever go stale. the
#    doctor sample in quickstart.md said 0.2.0 and would have kept saying it.
#    this is a NEGATIVE claim, so it is worthless without proof that the sweep
#    can see a literal when there is one: the counted bytes below, and the
#    mutated-doc arm in the driver.
SEMVER = re.compile(r'(?<![\w.])v?\d+\.\d+\.\d+(?![\w.])')
docs = [os.path.join(root, f) for f in ('README.md', 'SPEC.md')]
dd = os.path.join(root, 'docs')
if os.path.isdir(dd):
    docs += [os.path.join(dd, f) for f in sorted(os.listdir(dd)) if f.endswith('.md')]
docs = [d for d in docs if os.path.isfile(d)]
doc_bytes = 0
for d in docs:
    t = open(d, encoding='utf8', errors='replace').read()
    doc_bytes += len(t)
    for i, line in enumerate(t.splitlines(), 1):
        for s in SEMVER.finditer(line):
            P(f'{os.path.relpath(d, root)}:{i}: a version typed into prose ({s.group(0)}) — '
              f'nothing bumps it, so it can only go stale: {line.strip()[:70]}')
if doc_bytes < 10000:
    P(f'the docs sweep read only {doc_bytes} bytes across {len(docs)} file(s) — it is not reading the docs')

# 8. what the built binaries actually say when a stranger asks. a binary that
#    refuses --version (exit != 0) makes no version claim and is not judged;
#    a binary that answers must answer with this version.
if bindir:
    answered = 0
    for name in sorted(os.listdir(bindir)):
        p = os.path.join(bindir, name)
        if not name.startswith('rabadon-') or '.' in name:
            continue
        if not (os.path.isfile(p) and os.access(p, os.X_OK)):
            continue
        try:
            r = subprocess.run([p, '--version'], capture_output=True, text=True, timeout=20)
        except Exception as e:
            P(f'{name} --version: {e}')
            continue
        if r.returncode != 0:
            continue
        answered += 1
        said = (r.stdout or '').strip()
        if said != f'{name} {want}':
            P(f'{name} --version says "{said}", package.json says {want}')
    if answered == 0:
        P('no built binary answered --version — the binary arm of this check proved nothing')

for m in problems:
    print('DRIFT ' + m)
print(f'checked {len(plats)} platform package(s), {len(includers)} version.h includer(s), against {want}')
sys.exit(1 if problems else 0)
PY

# ---------------------------------------------------------------------------
# fixture: a copy of every file the checker reads, so a mutation can be proven
# to be caught without ever touching the real tree.
# ---------------------------------------------------------------------------
fixture() {
  d="$1"; mkdir -p "$d/native" "$d/npm"
  cp "$ROOT/package.json" "$ROOT/Makefile" "$d/"
  cp "$ROOT"/native/*.cpp "$ROOT"/native/*.h "$d/native/"
  for p in "$ROOT"/npm/*/; do
    n="$(basename "$p")"
    [ -f "$p/package.json" ] || continue
    mkdir -p "$d/npm/$n"; cp "$p/package.json" "$d/npm/$n/"
  done
  cp "$ROOT/README.md" "$ROOT/SPEC.md" "$d/"
  mkdir -p "$d/docs"; cp "$ROOT"/docs/*.md "$d/docs/"
}
# assert a mutated copy is REFUSED, and refused for the stated reason.
must_fail() {  # $1 = fixture dir, $2 = what was mutated, $3 = grep needle
  o="$(python3 "$CHECK" "$1" 2>&1)"; rc=$?
  if [ $rc -eq 0 ]; then
    bad "mutating $2 must be caught — the checker passed it"
  elif printf '%s' "$o" | grep -q "$3"; then
    ok "mutating $2 is caught, and named: $(printf '%s' "$o" | grep -m1 "$3" | cut -c1-96)"
  else
    bad "mutating $2 failed, but not for the stated reason"; printf '%s\n' "$o" | sed 's/^/    | /'
  fi
}

echo "rabadon version lockstep"
echo ""

# --- A: the real tree, including the binaries it built ---------------------
OUT="$(python3 "$CHECK" "$ROOT" "$ROOT/native" 2>&1)"; RC=$?
if [ $RC -eq 0 ]; then
  ok "the tree agrees with itself: $(printf '%s' "$OUT" | tail -1)"
else
  bad "the tree does not agree with itself"; printf '%s\n' "$OUT" | sed 's/^/    | /'
fi

# --- B: package.json alone moves -------------------------------------------
B="$TMP/b"; fixture "$B"
python3 - "$B/package.json" <<'PY'
import json,sys
p=sys.argv[1]; o=json.load(open(p)); o['version']='9.9.9'
open(p,'w').write(json.dumps(o,indent=2)+'\n')
PY
must_fail "$B" "package.json (bumped alone)" "native/version.h"

# --- C: version.h alone moves ----------------------------------------------
C="$TMP/c"; fixture "$C"
python3 - "$C/native/version.h" <<'PY'
import re,sys
p=sys.argv[1]; t=open(p).read()
open(p,'w').write(re.sub(r'(#define RABADON_VERSION ")[^"]+(")', r'\g<1>9.9.9\g<2>', t))
PY
must_fail "$C" "native/version.h" "RABADON_VERSION"

# --- D: one platform package moves -----------------------------------------
D="$TMP/d"; fixture "$D"
python3 - "$D" <<'PY'
import json,os,sys
d=sys.argv[1]
plat=sorted(os.listdir(os.path.join(d,'npm')))[0]
p=os.path.join(d,'npm',plat,'package.json'); o=json.load(open(p)); o['version']='9.9.9'
open(p,'w').write(json.dumps(o,indent=2)+'\n')
PY
must_fail "$D" "one npm platform package" "npm/.*package.json: version"

# --- E: the pin that decides which platform package gets installed ----------
E="$TMP/e"; fixture "$E"
python3 - "$E/package.json" <<'PY'
import json,sys
p=sys.argv[1]; o=json.load(open(p))
k=sorted(o['optionalDependencies'])[0]; o['optionalDependencies'][k]='9.9.9'
open(p,'w').write(json.dumps(o,indent=2)+'\n')
PY
must_fail "$E" "an optionalDependencies pin" "optionalDependencies"

# --- F: the Makefile stops rebuilding on a version bump --------------------
F="$TMP/f"; fixture "$F"
python3 - "$F/Makefile" <<'PY'
import sys
p=sys.argv[1]; t=open(p).read()
open(p,'w').write(t.replace(' native/version.h',''))
PY
must_fail "$F" "the Makefile prerequisite on version.h" "will not rebuild it"

# --- G: a source hardcodes the version again -------------------------------
G="$TMP/g"; fixture "$G"
printf '\n// reintroduced by hand\n// printf("rabadon-budget 9.9.9\\n");\n' >> "$G/native/budget.cpp"
must_fail "$G" "a hardcoded version banner in a source" "hardcoded version banner"

# --- Ha: a version typed back into the docs --------------------------------
HA="$TMP/ha"; fixture "$HA"
printf '\nInstall the current release, 0.1.9, and run it.\n' >> "$HA/docs/quickstart.md"
must_fail "$HA" "a version typed into the docs" "typed into prose"

# --- Hb: the docs sweep must be reading real files, not an empty list -------
HB="$TMP/hb"; fixture "$HB"
rm -f "$HB/README.md" "$HB/SPEC.md" "$HB"/docs/*.md
must_fail "$HB" "removing the docs the sweep reads" "it is not reading the docs"

# --- H: a built binary announces a version nobody else says ----------------
H="$TMP/h"; fixture "$H"
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\necho "rabadon-gate 9.9.9"\n' > "$TMP/fakebin/rabadon-gate"
chmod +x "$TMP/fakebin/rabadon-gate"
O="$(python3 "$CHECK" "$H" "$TMP/fakebin" 2>&1)"; RC=$?
if [ $RC -ne 0 ] && printf '%s' "$O" | grep -q 'rabadon-gate --version says "rabadon-gate 9.9.9"'; then
  ok "a binary announcing a version nobody else says is caught, and quoted back"
else
  bad "a drifted binary must be caught"; printf '%s\n' "$O" | sed 's/^/    | /'
fi

# --- I: an empty bindir must not read as agreement -------------------------
mkdir -p "$TMP/emptybin"
O="$(python3 "$CHECK" "$H" "$TMP/emptybin" 2>&1)"; RC=$?
if [ $RC -ne 0 ] && printf '%s' "$O" | grep -q "no built binary answered"; then
  ok "an unbuilt tree is reported, not read as agreement"
else
  bad "zero binaries answering --version must not pass"; printf '%s\n' "$O" | sed 's/^/    | /'
fi

# --- J: make itself, empirically. the textual rule above says the Makefile
#        lists version.h; this says make ACTS on it. `make -q` only asks, it
#        never builds. skipped (loudly) on an unbuilt tree, where -q would
#        answer "out of date" for a reason that has nothing to do with this.
TARGETS="$(python3 - "$ROOT" <<'PY'
import os,re,sys
n=os.path.join(sys.argv[1],'native')
for f in sorted(os.listdir(n)):
    if f.endswith('.cpp') and re.search(r'#\s*include\s+"version\.h"', open(os.path.join(n,f),encoding='utf8',errors='replace').read()):
        print('native/rabadon-'+f[:-4])
PY
)"
if (cd "$ROOT" && make -q $TARGETS >/dev/null 2>&1); then
  touch "$ROOT/native/version.h"
  if (cd "$ROOT" && make -q $TARGETS >/dev/null 2>&1); then
    bad "make answers 'up to date' after version.h changed — a bump would ship the old string"
  else
    ok "make rebuilds $(printf '%s' "$TARGETS" | wc -w | tr -d ' ') binaries when version.h changes (was: 'up to date')"
  fi
else
  echo "  skip - make -q arm: the tree is not built (run make first); the textual rule above still held"
fi

echo ""
echo "version: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
