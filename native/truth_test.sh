#!/usr/bin/env bash
# rabadon-truth proof — the ladder must pick the STRONGEST runnable truth, and it
# must refuse to call a non-check a check. The subtle case is the npm stub: a
# package.json whose "test" script is `echo "no test specified" && exit 1` looks
# like a suite to a naive matcher, and treating it as one would light the net
# green on a repository that verifies nothing.
set -u
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-truth"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-truth"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

lvl(){ "$BIN" "$1" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["level"])'; }
kind(){ "$BIN" "$1" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["kind"])'; }
runof(){ "$BIN" "$1" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["run"])'; }

# ---- 1: a real npm test script is a SUITE ----
d="$TMP/npm-real"; mkdir -p "$d"; echo 'console.log(1)' > "$d/a.js"
printf '{"scripts":{"test":"vitest run","build":"vite build"}}' > "$d/package.json"
[ "$(lvl "$d")" = "3" ] && ok "package.json scripts.test -> level 3 SUITE" || bad "npm test not level 3"

# ---- 2: the npm STUB is not a suite (the whole point) ----
d="$TMP/npm-stub"; mkdir -p "$d"; echo 'console.log(1)' > "$d/a.js"
printf '{"scripts":{"test":"echo \\"Error: no test specified\\" && exit 1"}}' > "$d/package.json"
l="$(lvl "$d")"
[ "$l" != "3" ] && ok "the npm 'no test specified' stub is REFUSED as a suite (fell to level $l)" \
  || bad "the npm stub was accepted as a real test suite"

# ---- 3: build beats syntax when both exist ----
d="$TMP/tsproj"; mkdir -p "$d/src"; echo 'export const a=1' > "$d/src/a.ts"
printf '{}' > "$d/tsconfig.json"
[ "$(lvl "$d")" = "2" ] && [ "$(kind "$d")" = "build" ] \
  && ok "tsconfig.json -> level 2 BUILD (typecheck), not syntax" || bad "tsconfig not level 2"

# ---- 4: a Makefile test target is a suite; 'all' alone is only a build ----
d="$TMP/mk1"; mkdir -p "$d"; printf 'test:\n\techo hi\n' > "$d/Makefile"; echo 'int main(){}' > "$d/m.cpp"
[ "$(lvl "$d")" = "3" ] && ok "Makefile 'test:' target -> level 3 SUITE" || bad "makefile test not level 3"
d="$TMP/mk2"; mkdir -p "$d"; printf 'all:\n\techo hi\n' > "$d/Makefile"; echo 'int main(){}' > "$d/m.cpp"
[ "$(lvl "$d")" = "2" ] && ok "Makefile with only 'all:' -> level 2 BUILD" || bad "makefile all not level 2"

# ---- 5: bare python falls to SYNTAX, and the command is real ----
d="$TMP/py"; mkdir -p "$d"; printf 'x = 1\n' > "$d/app.py"
[ "$(lvl "$d")" = "1" ] && ok "bare python sources -> level 1 SYNTAX" || bad "python not level 1"
( cd "$d" && eval "$(runof "$d")" >/dev/null 2>&1 ) \
  && ok "the SYNTAX command actually runs green on healthy sources" || bad "syntax command failed on good code"
printf 'def broken(\n' > "$d/app.py"
( cd "$d" && eval "$(runof "$d")" >/dev/null 2>&1 ) \
  && bad "the SYNTAX command stayed green on a file that cannot parse" \
  || ok "the SYNTAX command goes RED on a file that cannot parse (a rung that cannot fail is not a rung)"

# ---- 6: no code at all -> NONE, and a non-zero exit says so ----
d="$TMP/empty"; mkdir -p "$d"; echo "# just notes" > "$d/README.md"
[ "$(lvl "$d")" = "0" ] && ok "a folder with no code -> level 0 NONE" || bad "empty folder not level 0"
"$BIN" "$d" >/dev/null 2>&1 && bad "level 0 should exit non-zero" || ok "level 0 exits non-zero (callers can branch on it)"

# ---- 7: test files are collected so the arbiter can LOCK them ----
d="$TMP/locked"; mkdir -p "$d/tests"; echo 'x=1' > "$d/app.py"; echo 'def test_x(): assert 1' > "$d/tests/test_x.py"
"$BIN" "$d" --json | grep -q 'tests/test_x.py' \
  && ok "test files are listed for the forbidden-sha lock (a fix cannot weaken its own judge)" \
  || bad "test files not collected"

# ---- 8: vendored noise never becomes the project's truth ----
d="$TMP/noise"; mkdir -p "$d/node_modules/pkg"; printf '{"scripts":{"test":"jest"}}' > "$d/node_modules/pkg/package.json"
echo 'console.log(1)' > "$d/index.js"
[ "$(lvl "$d")" = "1" ] \
  && ok "a package.json inside node_modules is ignored (level 1, not a borrowed suite)" \
  || bad "vendored package.json leaked into detection (level $(lvl "$d"))"

echo ""
echo "truth: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
