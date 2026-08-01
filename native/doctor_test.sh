#!/bin/bash
# doctor_test.sh — the only self-service diagnostic, held to its own claim.
#
# `rabadon doctor` is what every failure path tells a stranger to run:
# scripts/build.mjs prints "diagnose with: rabadon doctor" when a source build
# dies halfway, and native/rabadon-cli.sh prints "diagnose: rabadon doctor"
# when a command's binary is not there. It was checking a hand-kept list of six
# names while the Makefile builds sixteen, so on a tree missing TEN of them it
# printed "ok native core built (6 binaries)" and "all green", exit 0.
#
# Two ways that lands on a real install:
#   - npm's source-build fallback runs `make all`; one late target fails on the
#     user's toolchain, make stops, and build.mjs exits 0 BY DESIGN (installing
#     fails open). 15 of 16 built, npm install "succeeded", doctor says all
#     green, and `rabadon export --otlp` — a README headline — is dead.
#   - when the absent one is rabadon-truth, repair loses hash-lock discovery
#     (native/repair.cpp shells out to rabadon-truth for the test-file list and
#     takes an empty list when it is not there), so the same test-gutting patch
#     the full build REJECTS is HELD, on a tree doctor just certified.
#
# This repo has fixed this exact class twice already: the Makefile `test:` list
# named 11 of 16 ("a clean checkout ran make test straight into a missing
# binary") and native/cli_test.sh discovers binaries by glob because "a
# hand-kept list is a gate the seventeenth binary walks around". So the cases
# below are not only "doctor sees ten absent binaries" — the last three are the
# seventeenth binary itself, from both directions, plus the walk-around that
# opens up the moment the derivation has nowhere to read from.
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

command -v node >/dev/null 2>&1 || { echo "doctor_test: needs node"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "doctor_test: needs python3"; exit 1; }

TMP=$(mktemp -d /tmp/rabadon-doctor-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

echo "doctor: what an install looks like when it is only half there"

# the subject list of the TEST is discovered too — writing sixteen names here
# would reproduce, one file over, the bug being tested.
ALL=""
for p in "$ROOT"/native/rabadon-*; do
  case "$p" in *.sh) continue ;; esac
  [ -x "$p" ] || continue
  n=$(basename "$p"); ALL="$ALL ${n#rabadon-}"
done
NALL=$(printf '%s\n' $ALL | wc -w | tr -d ' ')
if [ "$NALL" -ge 16 ]; then pass "the probe found $NALL built binaries to install into fake trees"
else fail "only $NALL binaries built — run make first, this run proves nothing"; echo "doctor: $ok passed, $bad failed"; exit 1; fi

# a fake install: hooks + manifest + Makefile + the cli shim, and whichever
# binaries the case wants. this is the layout `npm i` leaves behind.
mk() { # mk <dest> <binary short names...>
  D="$1"; shift
  mkdir -p "$D/native" "$D/hooks" "$D/home/.claude" "$D/home/.rabadon"
  cp "$ROOT"/hooks/*.mjs "$D/hooks/"
  cp "$ROOT/package.json" "$ROOT/Makefile" "$D/"
  cp "$ROOT/native/rabadon-cli.sh" "$D/native/"
  for b in "$@"; do cp "$ROOT/native/rabadon-$b" "$D/native/"; done
}
doc() { HOME="$1/home" RABADON_DIR="$1/home/.rabadon" RABADON_NOTIFY=0 "$1/native/rabadon-cli.sh" doctor 2>&1; }
has() { printf '%s' "$1" | grep -qF "$2"; }
# "N thing(s) to look at above." -> N ; "all green." -> 0. the count, not the
# exit code, is what cancels out this machine's own state (a missing `claude`
# CLI is one problem on every run, including the healthy one).
problems() { printf '%s' "$1" | python3 -c 'import re,sys
t=sys.stdin.read()
m=re.search(r"^\s*(\d+) thing", t, re.M)
print(m.group(1) if m else ("0" if "all green." in t else "-1"))'; }

# ---- 1. the healthy tree: the POSITIVE half, without which every "must not
#         print X" case below passes the day X is renamed ----
FULL="$TMP/full"; mk "$FULL" $ALL
OUT=$(doc "$FULL"); FULL_RC=$?; FULL_P=$(problems "$OUT")
has "$OUT" "native core built ($NALL/$NALL binaries)" \
  && pass "a complete tree: doctor says native core built ($NALL/$NALL binaries)" \
  || { fail "a complete tree: no \"native core built ($NALL/$NALL binaries)\" line"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }
has "$OUT" "absent" && fail "a complete tree: doctor reports something absent" \
  || pass "a complete tree: nothing reported absent"
[ "$FULL_P" -ge 0 ] && pass "the healthy run's problem count is readable ($FULL_P)" \
  || fail "could not read a problem count from the healthy run"

# ---- 2. the tree doctor used to certify: the six names the literal held ----
HALF="$TMP/half"; mk "$HALF" gate stats drift audit repair sandbox
OUT=$(doc "$HALF"); HALF_RC=$?; HALF_P=$(problems "$OUT")
[ "$HALF_RC" -ne 0 ] && pass "ten binaries absent: doctor exits non-zero ($HALF_RC)" \
  || { fail "ten binaries absent: doctor exited 0 — a half-built install certified"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }
has "$OUT" "all green" && fail "ten binaries absent: doctor still says \"all green\"" \
  || pass "ten binaries absent: doctor does not say \"all green\""
MISSED=""
for b in $ALL; do
  case " gate stats drift audit repair sandbox " in *" $b "*) continue ;; esac
  has "$OUT" "rabadon-$b" || MISSED="$MISSED rabadon-$b"
done
[ -z "$MISSED" ] && pass "every absent binary is named in the output (all ten)" \
  || { fail "absent but never named:$MISSED"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }
[ "$HALF_P" -gt "$FULL_P" ] && pass "the half tree reports more problems than the full one ($HALF_P > $FULL_P)" \
  || fail "half tree reported $HALF_P problems, full tree $FULL_P — the binaries add nothing"

# ---- 3. one binary short: the realistic npm case (make stopped on export) ----
ONE="$TMP/one"; ONELIST=""
for b in $ALL; do [ "$b" = "export" ] || ONELIST="$ONELIST $b"; done
mk "$ONE" $ONELIST
OUT=$(doc "$ONE"); ONE_RC=$?
[ "$ONE_RC" -ne 0 ] && pass "15 of 16 built: doctor exits non-zero ($ONE_RC)" \
  || fail "15 of 16 built: doctor exited 0 — \`rabadon export --otlp\` is dead and the install looks fine"
has "$OUT" "rabadon-export" && pass "15 of 16 built: the one absent binary is named" \
  || { fail "15 of 16 built: rabadon-export not named"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }

# ---- 4. the seventeenth binary, direction A: added to `all:` ----
# nobody who adds a binary has any reason to open hooks/manage.mjs. doctor must
# learn the new name from the same place `make` does.
S17="$TMP/s17"; mk "$S17" $ALL
printf '\nall: native/rabadon-seventeenth\n' >>"$S17/Makefile"
OUT=$(doc "$S17"); S17_RC=$?
has "$OUT" "rabadon-seventeenth" && pass "a seventeenth name in \`all:\` becomes a subject without editing manage.mjs" \
  || { fail "a binary added to \`all:\` walked around doctor"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }
[ "$S17_RC" -ne 0 ] && pass "the absent seventeenth makes doctor exit non-zero ($S17_RC)" \
  || fail "the absent seventeenth left doctor at exit 0"

# ---- 5. the seventeenth binary, direction B: a build rule, forgotten in `all:` ----
# a target the Makefile knows how to produce but `make all` never asks for is
# exactly the half-there binary this whole suite is about, so it counts too.
S18="$TMP/s18"; mk "$S18" $ALL
printf '\nnative/rabadon-eighteenth: native/eighteenth.cpp\n\t$(CXX) $(CXXFLAGS) -o $@ $<\n' >>"$S18/Makefile"
OUT=$(doc "$S18"); S18_RC=$?
has "$OUT" "rabadon-eighteenth" && pass "a binary rule missing from \`all:\` is still a subject" \
  || { fail "a Makefile rule outside \`all:\` walked around doctor"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }
[ "$S18_RC" -ne 0 ] && pass "the absent eighteenth makes doctor exit non-zero ($S18_RC)" \
  || fail "the absent eighteenth left doctor at exit 0"

# ---- 6. no Makefile: the derivation's own blind spot ----
# deriving the list from a file makes deleting that file the new walk-around.
# an empty subject list must read as "cannot certify", never as "all green".
NOMK="$TMP/nomk"; mk "$NOMK" $ALL; rm -f "$NOMK/Makefile"
OUT=$(doc "$NOMK"); NOMK_RC=$?
has "$OUT" "all green" && fail "no Makefile: doctor certified an install it could not check" \
  || pass "no Makefile: doctor does not say \"all green\""
[ "$NOMK_RC" -ne 0 ] && pass "no Makefile: doctor exits non-zero ($NOMK_RC)" \
  || fail "no Makefile: doctor exited 0 with nothing to check against"

# ---- 7. the published layout: binaries live in the platform package ----
# `npm i -g rabadon` puts them in @rabadon/<os>-<cpu>, not in <pkg>/native.
# doctor read only <pkg>/native once before and called a working install broken.
case "$(uname -s)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) OS="" ;; esac
case "$(uname -m)" in arm64|aarch64) CPU=arm64 ;; x86_64|amd64) CPU=x64 ;; *) CPU="" ;; esac
if [ -n "$OS" ] && [ -n "$CPU" ]; then
  PRE="$TMP/prebuilt"; mk "$PRE"
  mkdir -p "$PRE/node_modules/@rabadon/$OS-$CPU"
  for b in $ALL; do cp "$ROOT/native/rabadon-$b" "$PRE/node_modules/@rabadon/$OS-$CPU/"; done
  OUT=$(doc "$PRE")
  has "$OUT" "native core built ($NALL/$NALL binaries)" \
    && pass "prebuilt install: doctor finds all $NALL in @rabadon/$OS-$CPU" \
    || { fail "prebuilt install: doctor does not see the platform package"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }
else
  echo "  info unsupported platform for the prebuilt-layout case — skipped"
fi

# ---- 8. the postinstall build's own report, the other half of the same path ----
# scripts/build.mjs is what CREATES the half-built tree: `make` stops at the
# first failing target and build.mjs exits 0 on purpose (installing fails open).
# It judged "already built" on rabadon-gate alone — a one-name hand-kept list —
# so a reinstall would not even retry the targets that never got built. These
# trees carry no .cpp, so make fails immediately and no compile happens.
mkb() { # mkb <dest> <binary short names...>
  D="$1"; shift
  mk "$D" "$@"
  mkdir -p "$D/scripts"; cp "$ROOT/scripts/build.mjs" "$D/scripts/"
}
BFULL="$TMP/bfull"; mkb "$BFULL" $ALL
OUT=$(node "$BFULL/scripts/build.mjs" 2>&1); B_RC=$?
[ "$B_RC" -eq 0 ] && pass "postinstall on a complete tree exits 0" || fail "postinstall exited $B_RC on a complete tree"
has "$OUT" "already built ($NALL/$NALL)" && pass "postinstall on a complete tree: already built ($NALL/$NALL)" \
  || { fail "postinstall does not report the count it verified"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }
has "$OUT" "absent" && fail "postinstall on a complete tree reports something absent" \
  || pass "postinstall on a complete tree: nothing reported absent"

BONE="$TMP/bone"; BLIST=""
for b in $ALL; do [ "$b" = "export" ] || BLIST="$BLIST $b"; done
mkb "$BONE" $BLIST
OUT=$(node "$BONE/scripts/build.mjs" 2>&1); B1_RC=$?
[ "$B1_RC" -eq 0 ] && pass "postinstall still exits 0 with a binary missing (npm must not brick)" \
  || fail "postinstall exited $B1_RC — installing must fail open"
has "$OUT" "15 of 16 binaries built" && pass "postinstall names the count it actually got (15 of 16)" \
  || { fail "postinstall does not say how many binaries it produced"; printf '%s\n' "$OUT" | sed 's/^/    | /'; }
has "$OUT" "absent: rabadon-export" && pass "postinstall names the binary that is not there" \
  || fail "postinstall does not name the absent binary"
has "$OUT" "already built" && fail "postinstall called a 15-of-16 tree already built" \
  || pass "postinstall does not call a 15-of-16 tree already built"

echo "doctor: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
