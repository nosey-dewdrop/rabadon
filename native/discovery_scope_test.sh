#!/usr/bin/env bash
# discovery_scope_test.sh — WHOSE tests are these, and WHICH tree is this?
#
# Three questions decide whether the net supervises the user's project or an
# arbitrary pile of other people's code that happens to sit under it. All three
# were answered wrong, and all three were measured on 2026-08-29 before a line
# of this file existed (reports/kosu/SAPMA-KARARLARI.md D6):
#
#   1. WHOSE TESTS. truth.cpp's skip_dir() skips `.venv` and `venv` but not
#      `site-packages`. On macOS `pip install --user` installs into
#      ~/Library/Python/3.9/lib/python/site-packages, which starts with no dot
#      and lives in no venv — so pytz's own tests were counted as the user's
#      suite and a project with ZERO tests of its own was called level 3 SUITE.
#      The difference between the two cases was one dot character.
#      repair.cpp:487 and classify.h:82 already skip site-packages; truth.cpp
#      was the one list that did not, and the two lists had drifted apart.
#
#   2. WHICH TREE. pathres.h's project_root() walks up until it finds a `.git`.
#      A home directory that is itself a dotfiles repo therefore becomes the
#      root of every project under it that has no `.git` of its own. Measured:
#      `rabadon-truth $HOME` reported 20705 code files / 2850 test files as ONE
#      project, and a red verdict written with root=$HOME governs every sibling
#      directory beneath it. A home is where projects live; it is not a project.
#
#   3. WHAT COUNTS AS EVIDENCE. net.cpp granted the "this run executed no
#      tests, so it proves nothing" exemption only when the runner exited 0.
#      pytest exits 5 when it collected nothing, so the one runner the exemption
#      was written for never received it and an empty run was recorded RED.
#      The refusal that follows is a FALSE REJECT, which CLAUDE.md counts as the
#      same severity as a missed catch.
#
# Every widening here has a twin that must NOT move, because the cheap way to
# pass 1 is to skip more directories and the cheap way to pass 2 is to stop
# walking up: `src/Library/` is a real project directory (adding `Library` to
# skip_dir would blind it), a plain `tests/` directory is still discovered, and
# a real git root below $HOME still wins over $HOME.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TRUTH="$HERE/rabadon-truth"
NET="$HERE/rabadon-net"
[ -x "$TRUTH" ] || { echo "build first: make native/rabadon-truth"; exit 1; }
[ -x "$NET" ]   || { echo "build first: make native/rabadon-net"; exit 1; }

PASS=0; FAIL=0; SKIP=0; SKIPA=0
ok()   { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
# An arm that cannot run HERE is announced with its NAME and its NUMBER, and
# the count reaches the summary line. A skip that increments nothing is the
# suite getting smaller in silence, and every counter downstream reads the
# smaller number as health. native/silent_skip_test.sh holds this over the
# whole directory. $1 = arm, $2 = assertions not run, $3 = why.
skip() { SKIP=$((SKIP+1)); SKIPA=$((SKIPA+$2)); echo "  SKIP - $1: $2 assertion(s) did NOT run — $3"; }

T="$(mktemp -d "${TMPDIR:-/tmp}/rabadon-scope.XXXXXX")"
trap 'rm -rf "$T"' EXIT

lvl()  { "$TRUTH" "$1" --json | sed -n 's/.*"level":\([0-9]*\).*/\1/p'; }
jstr() { sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" "$1"; }
# BRE only: `\?` is a GNU extension and BSD sed drops the whole expression,
# which returned an empty exit code and made this arm prove nothing.
jnum() { sed -n "s/.*\"$2\":\([-0-9][0-9]*\).*/\1/p" "$1"; }

# a python project with exactly one .py of its own and no test of its own
lay() { # lay <dir> <path-of-the-foreign-test>
  mkdir -p "$1/.git" "$1/$(dirname "$2")"
  printf 'x = 1\n' > "$1/app.py"
  printf 'def test_x(): assert 1\n' > "$1/$2"
}

echo "discovery scope: whose tests, which tree"

# ---------- 1. WHOSE TESTS ----------

# the case that is right today and must stay right — a dotted venv is skipped,
# and this is the arm that catches a "fix" that deletes skip_dir wholesale
d="$T/venv"; lay "$d" ".venv/lib/python3.11/site-packages/numpy/tests/test_np.py"
[ "$(lvl "$d")" = "1" ] \
  && ok "a test inside .venv/.../site-packages is NOT the project's suite (level 1 SYNTAX)" \
  || bad "the .venv case regressed: level $(lvl "$d") — a dependency's tests became the project's"

# the case that is wrong today: same file, one dot less on the path
d="$T/userlib"; lay "$d" "Library/Python/3.9/lib/python/site-packages/pytz/tests/test_tz.py"
l="$(lvl "$d")"
[ "$l" != "3" ] \
  && ok "a test inside Library/.../site-packages is NOT the project's suite (fell to level $l)" \
  || bad "pip install --user's target was read as the project's own test suite (level 3)"

# and it is site-packages that decides it, not the word Library
d="$T/bare"; lay "$d" "lib/python3.11/site-packages/six/tests/test_six.py"
l="$(lvl "$d")"
[ "$l" != "3" ] \
  && ok "site-packages is skipped wherever it sits, with no venv above it (fell to level $l)" \
  || bad "a bare site-packages was read as the project's own test suite (level 3)"

# debian ships the same directory under another name
d="$T/dist"; lay "$d" "usr/lib/python3/dist-packages/attr/tests/test_attr.py"
l="$(lvl "$d")"
[ "$l" != "3" ] \
  && ok "dist-packages, the debian spelling of the same directory, is skipped too (fell to level $l)" \
  || bad "dist-packages was read as the project's own test suite (level 3)"

# THE TWIN. `Library` is an ordinary directory name and a real project may be
# built out of one. Adding it to skip_dir is the cheap way to pass the case
# above and it costs a real user their entire suite. If this arm goes red, that
# is what happened.
d="$T/reallib"; mkdir -p "$d/.git" "$d/src/Library/tests"
printf 'x = 1\n' > "$d/src/Library/app.py"
printf 'def test_real(): assert 1\n' > "$d/src/Library/tests/test_real.py"
[ "$(lvl "$d")" = "3" ] && "$TRUTH" "$d" --json | grep -q 'src/Library/tests/test_real.py' \
  && ok "a real src/Library/ project is still discovered and still locked (skip_dir did not eat the name)" \
  || bad "src/Library/ went blind: the project's own tests are no longer discovered"

# and the ordinary case is untouched
d="$T/plain"; lay "$d" "tests/test_plain.py"
[ "$(lvl "$d")" = "3" ] && "$TRUTH" "$d" --json | grep -q 'tests/test_plain.py' \
  && ok "an ordinary tests/ directory is still the project's suite" \
  || bad "the ordinary case broke: a plain tests/ directory is no longer discovered"

# ---------- 2. WHICH TREE ----------
# $HOME here is a fixture home that is itself a git repo — the shape the real
# machine is in (`ls ~/.git` exists), reproduced without touching it.
H="$T/home"; mkdir -p "$H/.git"
mkdir -p "$H/proj"; printf 'x = 1\n' > "$H/proj/app.py"
HOME="$H" "$NET" "$H/proj" --cap-ms 20000 >/dev/null 2>&1
R="$(jstr "$H/proj/.rabadon/net.json" root)"
[ "$R" != "$(cd "$H" && pwd -P)" ] \
  && ok "a project under a git-repo \$HOME does not inherit \$HOME as its root (root=$R)" \
  || bad "\$HOME was chosen as the project root: every sibling under it shares one verdict"
[ "$R" = "$(cd "$H/proj" && pwd -P)" ] \
  && ok "it falls back to the directory itself, which governs no sibling" \
  || bad "the fallback root is neither \$HOME nor the directory itself: $R"

# THE TWIN. Refusing $HOME must not turn into refusing to walk up at all: a
# real git root below $HOME still wins from a subdirectory.
mkdir -p "$H/g/.git" "$H/g/sub"; printf 'x = 1\n' > "$H/g/sub/app.py"
HOME="$H" "$NET" "$H/g/sub" --cap-ms 20000 >/dev/null 2>&1
R2="$(jstr "$H/g/sub/.rabadon/net.json" root)"
[ "$R2" = "$(cd "$H/g" && pwd -P)" ] \
  && ok "a real git root below \$HOME still wins from a subdirectory (root=$R2)" \
  || bad "the walk up stopped too early: expected $H/g, got $R2"

# ---------- 3. WHAT COUNTS AS EVIDENCE ----------
if python3 -m pytest --version >/dev/null 2>&1; then
  d="$T/empty-suite"; mkdir -p "$d/.git" "$d/tests"; printf 'x = 1\n' > "$d/app.py"
  [ "$(lvl "$d")" = "3" ] \
    && ok "premise: a python project with a tests/ directory is a level 3 SUITE" \
    || bad "premise broken: the empty-suite fixture is level $(lvl "$d"), not 3"
  "$NET" "$d" --cap-ms 60000 >/dev/null 2>&1
  N="$d/.rabadon/net.json"
  V="$(jstr "$N" verdict)"; X="$(jnum "$N" exit)"
  [ "$X" = "5" ] \
    && ok "premise: pytest collected nothing and exited 5 (not 0 — that is the whole bug)" \
    || bad "premise broken: the empty pytest run exited $X, so this arm proves nothing"
  [ "$V" = "inconclusive" ] \
    && ok "a run that executed no tests is INCONCLUSIVE, whatever the runner's exit code was" \
    || bad "an empty pytest run was recorded '$V' — a false reject, and red-base then refuses everything"
else
  skip "empty-run waiver arm" 1 "pytest is not installed here, so the empty run cannot be produced"
fi

# THE TWIN. The exemption is for runs that executed nothing, not for runs that
# failed. A suite that really goes red must still be red.
if python3 -m pytest --version >/dev/null 2>&1; then
  d="$T/red-suite"; mkdir -p "$d/.git" "$d/tests"; printf 'x = 1\n' > "$d/app.py"
  printf 'def test_broken(): assert 0\n' > "$d/tests/test_broken.py"
  "$NET" "$d" --cap-ms 60000 >/dev/null 2>&1
  V="$(jstr "$d/.rabadon/net.json" verdict)"
  [ "$V" = "red" ] \
    && ok "a suite that really fails is still RED — the exemption did not swallow the catch" \
    || bad "a genuinely failing suite was recorded '$V': the net stopped catching anything"
fi

echo ""
echo "discovery scope: $PASS ok, $FAIL fail, $SKIP skipped ($SKIPA assertion(s) not run)"
[ "$FAIL" -eq 0 ]
