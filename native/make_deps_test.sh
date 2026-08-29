#!/usr/bin/env bash
# make_deps_test.sh — the build must rebuild what changed. every rule, not one.
#
# WHY THIS FILE EXISTS (measured 2026-08-29, before it did):
#   Makefile:79 built native/rabadon-net from `native/net.cpp native/cli_help.h`
#   while native/net.cpp:50-51 includes testout.h and pathres.h. So:
#     touch native/pathres.h && make all   ->  rabadon-net mtime UNCHANGED
#                                              rabadon-gate mtime changed
#   pathres.h is the file D6's $HOME repair lives in. A phase that edits
#   pathres.h and runs `make all` gets a GREEN from a STALE binary. That is not
#   an inconvenience, it is a silent reward-hacking vector: it already happened
#   in F3, where MUTANT 2 answered 13 ok / 0 fail from a binary that had never
#   been rebuilt, and only a forced `touch` showed the real 11 ok / 2 fail.
#
#   native/version_test.sh already holds ONE header (version.h) from both ends.
#   The hole was that it held only that one. This file holds the WHOLE include
#   graph, textually and empirically, and it is the graph that gets swept, never
#   a hand-kept list: a header added to a source tomorrow is checked tomorrow.
#
# Two arms, because either alone is weak:
#   TEXT: every local header in a .cpp's transitive include closure must be a
#         prerequisite of the rule that builds it.
#   MAKE: touch a header, ask `make -q` (asks, never builds) whether every
#         binary that includes it is out of date. Mutation proof for this arm
#         runs on a throwaway tree whose Makefile has a prerequisite removed:
#         there, make must answer "up to date", and the arm must go red.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CHECK="$TMP/check.py"

# ---------------------------------------------------------------------------
# the checker. argv: <root> [--map]
#   default : print one MISSING line per rule/header disagreement, exit 1 if any
#   --map   : print "<target>\t<header>" for the whole closure, exit 0
# python3, not grep: this needs a transitive closure over #include lines, and a
# one-level grep would pass a rule that lists rules.h while missing baseline.h,
# which rules.h itself includes — exactly the shape of the run.cpp hole below.
# ---------------------------------------------------------------------------
cat > "$CHECK" <<'PY'
import os, re, sys

root = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else ''
NATIVE = os.path.join(root, 'native')

cache = {}
def closure(f):
    """every local header reachable from native/<f> through #include "..." """
    if f in cache:
        return cache[f]
    seen = set()
    cache[f] = seen           # placed before recursion: include cycles are legal
    p = os.path.join(NATIVE, f)
    if not os.path.isfile(p):
        return seen
    for line in open(p, encoding='utf8', errors='replace'):
        m = re.match(r'\s*#\s*include\s*"([^"]+)"', line)
        if m:
            h = os.path.basename(m.group(1))
            if h not in seen:
                seen.add(h)
                seen |= closure(h)
    return seen

mk = re.sub(r'\\\n\s*', ' ', open(os.path.join(root, 'Makefile'), encoding='utf8').read())
rules = []
for line in mk.splitlines():
    m = re.match(r'^(native/[A-Za-z0-9_-]+)\s*:\s*(.*)$', line)
    if not m:
        continue
    target, prereqs = m.group(1), m.group(2).split()
    srcs = [os.path.basename(x) for x in prereqs if x.endswith('.cpp')]
    if srcs:
        rules.append((target, srcs, {os.path.basename(x) for x in prereqs}))

if mode == '--map':
    for target, srcs, _ in rules:
        need = set()
        for s in srcs:
            need |= closure(s)
        for h in sorted(h for h in need if h.endswith('.h')):
            print(f'{target}\t{h}')
    sys.exit(0)

problems = []
edges = 0
for target, srcs, have in rules:
    need = set()
    for s in srcs:
        need |= closure(s)
    edges += len(need)
    for h in sorted(need - have):
        problems.append(
            f'{target}: {" ".join(sorted(srcs))} includes {h} but the rule does not list it '
            f'as a prerequisite — editing native/{h} answers make with "up to date" '
            f'and ships a stale binary')

# positives. a sweep that parsed nothing, or a graph with no edges, would print
# no problems and read as agreement. both are reported as failures instead.
if len(rules) < 15:
    problems.append(f'only {len(rules)} compile rule(s) parsed out of the Makefile — the sweep is not reading it')
if edges < 50:
    problems.append(f'the include graph has only {edges} edge(s) — the closure is not being computed')

for m in problems:
    print('MISSING ' + m)
print(f'checked {len(rules)} compile rule(s), {edges} source->header edge(s)')
sys.exit(1 if problems else 0)
PY

# ---------------------------------------------------------------------------
# fixture: Makefile + sources only. no binaries are copied; the MAKE arm below
# fabricates empty up-to-date targets, because `make -q` compares timestamps
# and never looks inside a file.
# ---------------------------------------------------------------------------
fixture() {
  d="$1"; mkdir -p "$d/native"
  cp "$ROOT/Makefile" "$d/"
  cp "$ROOT"/native/*.cpp "$ROOT"/native/*.h "$d/native/"
}
# make every compile target in the fixture exist and be newer than every source.
stamp_targets() {
  d="$1"
  sleep 1
  for t in $(python3 "$CHECK" "$d" --map | cut -f1 | sort -u); do
    : > "$d/$t"; chmod +x "$d/$t"
  done
}
mq() { (cd "$1" && unset MAKEFLAGS MFLAGS MAKELEVEL && shift && make -q "$@" >/dev/null 2>&1); }
# `touch` sets mtime to NOW, and NOW can land inside the same timestamp tick as
# a binary make just wrote. Measured on 2026-08-29 in the pre-phase worktree:
# native/gate_bench read "up to date" after touching baseline.h, a header it
# DOES list — a false red produced by the clock, not by the build. An arm that
# fails for a reason it invented is worth less than no arm, so the header is
# pushed to a fixed hour in the future instead, which no build can tie.
future_touch() { python3 -c 'import os,sys,time; t=time.time()+3600; os.utime(sys.argv[1],(t,t))' "$1"; }

echo "rabadon make dependency graph"
echo ""

# --- A: the real tree ------------------------------------------------------
OUT="$(python3 "$CHECK" "$ROOT" 2>&1)"; RC=$?
if [ $RC -eq 0 ]; then
  ok "every compile rule lists its whole include closure: $(printf '%s' "$OUT" | tail -1)"
else
  bad "a compile rule is missing a prerequisite its source includes"
  printf '%s\n' "$OUT" | sed 's/^/    | /'
fi

# --- B: a prerequisite removed by hand must be named -----------------------
B="$TMP/b"; fixture "$B"
python3 - "$B/Makefile" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert ' native/pathres.h' in t
open(p, 'w').write(t.replace(' native/pathres.h', '', 1))
PY
O="$(python3 "$CHECK" "$B" 2>&1)"; RC=$?
if [ $RC -ne 0 ] && printf '%s' "$O" | grep -q 'includes pathres.h but the rule does not list it'; then
  ok "removing one prerequisite is caught and named: $(printf '%s' "$O" | grep -m1 'pathres.h' | cut -c1-88)"
else
  bad "removing native/pathres.h from a rule must be caught"; printf '%s\n' "$O" | sed 's/^/    | /'
fi

# --- C: a TRANSITIVE prerequisite, one the source never names itself -------
#     run.cpp includes rules.h; rules.h includes baseline.h. a one-level check
#     passes that rule while an edit to baseline.h ships a stale rabadon-run.
C="$TMP/c"; fixture "$C"
python3 - "$C/Makefile" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert ' native/baseline.h' in t
open(p, 'w').write(t.replace(' native/baseline.h', ''))
PY
O="$(python3 "$CHECK" "$C" 2>&1)"; RC=$?
if [ $RC -ne 0 ] && printf '%s' "$O" | grep -q 'includes baseline.h'; then
  ok "a header reached only through another header is still required"
else
  bad "a transitive prerequisite must be required too"; printf '%s\n' "$O" | sed 's/^/    | /'
fi

# --- D: the sweep must not pass by reading nothing --------------------------
D="$TMP/d"; fixture "$D"
python3 - "$D/Makefile" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
open(p, 'w').write(re.sub(r'^native/[A-Za-z0-9_-]+\s*:.*$', 'unrelated:', t, flags=re.M))
PY
O="$(python3 "$CHECK" "$D" 2>&1)"; RC=$?
if [ $RC -ne 0 ] && printf '%s' "$O" | grep -q 'is not reading it'; then
  ok "a Makefile with no compile rules is reported, not read as agreement"
else
  bad "an unparsed Makefile must not pass"; printf '%s\n' "$O" | sed 's/^/    | /'
fi

# --- E: make itself, on the real tree. `make -q` asks, it never builds. -----
MAP="$TMP/map.tsv"
python3 "$CHECK" "$ROOT" --map > "$MAP"
HDRS="$(cut -f2 "$MAP" | sort -u)"
NH="$(printf '%s\n' "$HDRS" | wc -l | tr -d ' ')"
ALLT="$(cut -f1 "$MAP" | sort -u | tr '\n' ' ')"
if mq "$ROOT" $ALLT; then
  BADH=""; CHECKED=0
  for h in $HDRS; do
    deps="$(awk -F'\t' -v h="$h" '$2==h{print $1}' "$MAP" | tr '\n' ' ')"
    [ -n "$deps" ] || continue
    cp -p "$ROOT/native/$h" "$TMP/stamp.$h"
    future_touch "$ROOT/native/$h"
    for t in $deps; do
      CHECKED=$((CHECKED+1))
      if mq "$ROOT" "$t"; then BADH="$BADH $t<-$h"; fi
    done
    touch -r "$TMP/stamp.$h" "$ROOT/native/$h"
  done
  if [ -z "$BADH" ]; then
    ok "make rebuilds all $CHECKED (binary, header) pairs across $NH headers when the header changes"
  else
    bad "make answers 'up to date' after a header it compiles in changed:$BADH"
  fi
  if mq "$ROOT" $ALLT; then
    ok "the make arm left the tree exactly as it found it (header mtimes restored)"
  else
    bad "the make arm left the tree needing a rebuild"
  fi
else
  # A SKIP HERE IS THE SUITE GETTING QUIETLY SMALLER, so it is a failure.
  #
  # Measured, 2026-08-29 (F3b arbiter, §6 of reports/kosu/RAPOR/F3b-R.md): this
  # branch is not entered under `make test`, because the `test:` target depends
  # on `all`. Harmless today. But the day it IS entered — someone running this
  # file directly on a fresh clone, or a tree left out of date by a failed
  # build — arm E and its mutation proof simply stop running, the suite prints
  # fewer `ok` lines than it did yesterday, and it still exits 0. That is the
  # shape of the exact defect this file was written to catch: a green that came
  # from a check that did not happen. §8.2 — a counter that can drop a suite is
  # not a counter, and a suite that can shrink in silence is not a suite.
  #
  # Loud, not lenient (CLAUDE.md, Promise 1: if it cannot check, it says so —
  # it never goes quiet). The message names the arm that did not run and the
  # one command that fixes it.
  bad "make -q arm did NOT run: the tree is not built or is out of date, so the empirical half of this suite measured nothing — run \`make all\` and re-run this file"
fi

# --- F: MUTATION PROOF for arm E. same procedure, throwaway tree, one
#        prerequisite removed. make must answer "up to date" there, which is
#        exactly what arm E has to be able to see. an arm that cannot go red
#        is not an arm.
F="$TMP/f"; fixture "$F"
python3 - "$F/Makefile" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, 'w').write(t.replace(' native/pathres.h', ''))
PY
stamp_targets "$F"
FMAP="$TMP/fmap.tsv"; python3 "$CHECK" "$ROOT" --map > "$FMAP"   # the TRUE graph
DEPS="$(awk -F'\t' '$2=="pathres.h"{print $1}' "$FMAP" | tr '\n' ' ')"
if [ -z "$DEPS" ]; then
  bad "no binary includes pathres.h — the mutation arm has nothing to prove"
elif mq "$F" $DEPS; then
  future_touch "$F/native/pathres.h"
  if mq "$F" $DEPS; then
    ok "with the prerequisite removed, make really does answer 'up to date' after touching pathres.h — arm E can go red"
  else
    bad "the mutated tree still rebuilt — arm E's failure mode could not be reproduced"
  fi
else
  bad "the fixture tree did not start up to date — the mutation arm proved nothing"
fi

echo ""
echo "make deps: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
