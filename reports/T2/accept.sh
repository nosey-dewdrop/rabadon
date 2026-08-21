#!/usr/bin/env bash
# T2 acceptance test — "the surface narrows".
#
# Written BEFORE the round is implemented, by a session that is not allowed to
# implement it (protocol Gate 1). It is RED on the day it is written and that is
# the correct state: nothing has been moved yet. Turning it green is the round's
# job, and the only honest way to turn it green is to move the verbs.
#
# Run from anywhere: it locates the repo root from its own location.
#   reports/T2/accept.sh   -> exit 0 = every claim holds, exit 1 = at least one red
#
# It reads reports/T2/baseline.txt, which was measured on the same commit this
# file was written on. Every list and every number this test compares against
# comes out of that file; nothing is typed twice. If baseline.txt is edited to
# lower a number or shorten a list, that is exactly the reward hack protocol
# section 6.2 names, and `git log -- reports/T2/` shows it in one line.
#
# WHAT "still works" MEANS HERE, said out loud so nobody argues about it later.
# Claim 2 asserts the moved verbs are REACHABLE under `rabadon dev <verb>`, not
# that each one does its job. Each verb is invoked with --help, inside a throwaway
# HOME / RABADON_DIR / cwd, under a wall-clock cap. Verbs like remove, init and
# repair do real work, and `serve` binds a port and blocks; an acceptance test
# that let them do that would be a destructive test. So the assertion is narrow
# and precise: the dispatcher ROUTES the verb — it does not answer "unknown
# command". Whether each verb still behaves is what `make test` is for, and
# claim 3 asserts that number did not drop.
#
# UPDATED 2026-08-21, before implementation, in its own commit and by a session
# that still cannot implement the round. The protocol's "25 CLI verbs" was
# written from memory and was wrong; the dispatcher has 43 verb tokens. The
# human decision that followed WIDENS this test, it does not soften it:
#   - the moved set went from 27 to 29 (status and toggle join it),
#   - status and toggle were struck off claim 1c's allowance, so the surface is
#     now judged against three permitted extras instead of five,
#   - the five #unlisted verbs stay out of scope but gained a regression claim.
# Nothing that was asserted before is asserted more weakly now. The full reason
# is in PROTOCOL-T1-T8.md section T2 and reports/T2/discards.txt items 1 and 2.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

BASELINE="$HERE/baseline.txt"

PASS_N=0
FAIL_N=0

pass() { printf 'PASS  %s\n' "$1"; PASS_N=$((PASS_N + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL_N=$((FAIL_N + 1)); }
note() { printf '      %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

[ -f "$BASELINE" ] || { printf 'FAIL  missing %s — T2 cannot be judged without the number measured before it\n' "$BASELINE"; exit 1; }

# --- baseline readers -------------------------------------------------------
# KEY=<number> lines from section 1, KEY=<list> lines from section 5. Read with
# grep rather than sourced: baseline.txt is a report, not a shell script, and
# sourcing it would let a stray line in it run code.
bnum() {
  v="$(grep -E "^$1=[0-9]+$" "$BASELINE" | head -n1 | cut -d= -f2 || true)"
  [ -n "$v" ] || { printf 'FAIL  baseline.txt has no %s= line\n' "$1" >&2; exit 1; }
  printf '%s' "$v"
}
blist() {
  v="$(grep -E "^$1=" "$BASELINE" | head -n1 | cut -d= -f2- || true)"
  [ -n "$v" ] || { printf 'FAIL  baseline.txt has no %s= line\n' "$1" >&2; exit 1; }
  printf '%s' "$v"
}

BASE_PASSED="$(bnum MAKE_TEST_PASSED)"
BASE_CPP="$(bnum CPP_COUNT)"
BASE_TESTFILES="$(bnum TEST_FILE_COUNT)"
BASE_MKSCRIPTS="$(bnum MAKEFILE_TEST_SCRIPTS)"

BASE_MOVED_N="$(bnum MOVED_COUNT)"

SURFACE="$(blist LIST_SURFACE)"
DISPATCH_LISTED="$(blist LIST_DISPATCHER_LISTED)"
DISPATCH_UNLISTED="$(blist LIST_DISPATCHER_UNLISTED)"
MOVED="$(blist LIST_MOVED_29)"
UNLISTED_KEEP="$(blist LIST_UNLISTED_KEEP)"

# --- the moved list is checked before it is used ----------------------------
# The whole test hangs off one list, so the list is the thing worth attacking:
# drop `serve` from it and 2a goes green without serve ever moving. Three
# guards, all before any probe runs, all fatal rather than merely red — a test
# judging the wrong list is worse than no test.
#   (i)  the count is the number the human decided, 29, not "however many words
#        happen to be on the line today";
#   (ii) the line really does have that many words;
#   (iii) it is exactly LIST_DISPATCHER_LISTED minus LIST_SURFACE, recomputed
#        here, so a verb cannot be dropped from the target without also being
#        deleted from the dispatcher inventory measured before the round.
sortu() { printf '%s\n' $1 | sort -u | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//'; }

if [ "$BASE_MOVED_N" -ne 29 ]; then
  printf 'FAIL  baseline.txt says MOVED_COUNT=%s; the human decision of 2026-08-21 is 29 verbs\n' "$BASE_MOVED_N" >&2
  printf '      see PROTOCOL-T1-T8.md section T2 and reports/T2/discards.txt item 1\n' >&2
  exit 1
fi
MOVED_WORDS="$(printf '%s' "$MOVED" | wc -w | tr -d ' ')"
if [ "$MOVED_WORDS" -ne "$BASE_MOVED_N" ]; then
  printf 'FAIL  LIST_MOVED_29 has %s verbs, MOVED_COUNT says %s — the list was edited\n' "$MOVED_WORDS" "$BASE_MOVED_N" >&2
  exit 1
fi
DERIVED=""
for v in $DISPATCH_LISTED; do
  case " $SURFACE " in *" $v "*) continue ;; esac
  DERIVED="$DERIVED $v"
done
if [ "$(sortu "$DERIVED")" != "$(sortu "$MOVED")" ]; then
  printf 'FAIL  LIST_MOVED_29 is not LIST_DISPATCHER_LISTED minus LIST_SURFACE\n' >&2
  printf '      derived: %s\n' "$(sortu "$DERIVED")" >&2
  printf '      stored:  %s\n' "$(sortu "$MOVED")" >&2
  exit 1
fi

# --- entry point ------------------------------------------------------------
# The repo's own dispatcher, not whatever `rabadon` on PATH happens to be. On
# this machine /opt/homebrew/bin/rabadon is a symlink INTO this repo, so the two
# are the same thing today — but a test that silently judged some other install
# would be worthless the first time that stopped being true.
if [ -x "$ROOT/native/rabadon-cli.sh" ]; then
  RABADON="$ROOT/native/rabadon-cli.sh"
elif [ -x "$ROOT/bin/rabadon" ]; then
  RABADON="$ROOT/bin/rabadon"
else
  printf 'FAIL  no rabadon entry point found in this repo (looked for native/rabadon-cli.sh, bin/rabadon)\n'
  exit 1
fi

# --- capped, isolated invocation -------------------------------------------
# No `timeout(1)` on stock macOS, so the cap is hand-rolled. LAB redirects HOME,
# RABADON_DIR and cwd so that a verb which does real work does it to a temp tree
# and not to Damla's machine.
LAB="$(mktemp -d -t rabadon-t2-lab)"
mkdir -p "$LAB/home" "$LAB/work"
cleanup() { rm -rf "$LAB"; }
trap cleanup EXIT

CAP_OUT="$LAB/out.txt"
CAP_RC=0
run_capped() {  # run_capped <seconds> <cmd...>
  secs="$1"; shift
  : > "$CAP_OUT"
  (
    cd "$LAB/work" || exit 127
    HOME="$LAB/home" \
    RABADON_DIR="$LAB/home/.rabadon" \
    RABADON_HOME="$LAB/home/.rabadon" \
    TMPDIR="$LAB/tmp" \
    NO_COLOR=1 \
    "$@" </dev/null
  ) > "$CAP_OUT" 2>&1 &
  cpid=$!
  i=0
  limit=$((secs * 10))
  while kill -0 "$cpid" 2>/dev/null && [ "$i" -lt "$limit" ]; do
    command sleep 0.1
    i=$((i + 1))
  done
  if kill -0 "$cpid" 2>/dev/null; then
    kill -9 "$cpid" 2>/dev/null || true
    set +e; wait "$cpid" 2>/dev/null; set -e
    CAP_RC=124
  else
    set +e; wait "$cpid"; CAP_RC=$?; set -e
  fi
}

# The one string this test is really looking for. The dispatcher's miss branch
# prints `rabadon: unknown command "x"`; the JS path and the binaries have their
# own spellings. Any of them means the verb did not route.
UNKNOWN_RE='unknown command|unknown verb|unknown subcommand|not a rabadon command|no such command|command not found|is not recognized'

# ---------------------------------------------------------------------------
# CLAIM 1 — `rabadon --help` shows FIVE verbs, and the moved ones are not on it.
#
# "Five" is five TABLE ROWS in the protocol: init / on|off / usage / repair /
# doctor, which is six tokens because on and off share a row. That is what is
# counted.
#
# HOW A VERB IS DETECTED IN THE HELP TEXT: the leading word of an indented line,
# e.g. "  usage [--days N]   what was refused". Prose is not searched, because
# `do`, `on`, `run` and `report` are ordinary English words and grepping for them
# in sentences would fail a correct implementation. Example lines are not
# searched either, because they begin with the word "rabadon". A moved verb named
# inside an example such as `rabadon dev usage --days 7` is fine and stays fine.
# ---------------------------------------------------------------------------
head_ "CLAIM 1 — rabadon --help shows five verbs, and no moved verb"

run_capped 20 "$RABADON" --help
HELP_TXT="$LAB/help.txt"
cp "$CAP_OUT" "$HELP_TXT"
HELP_RC="$CAP_RC"

if [ "$HELP_RC" -ne 0 ]; then
  fail "1_ rabadon --help exited $HELP_RC"
  note "output head:"
  head -n 5 "$HELP_TXT" | sed 's/^/      | /'
fi

# The command column of the help screen, and nothing else.
#
# A command line looks like "  <names>   <description>": indented, and the names
# are separated from the prose by a run of two or more spaces. Three exclusions,
# each for a defect this parser hit on the CURRENT help text:
#   - a wrapped description line ("...judged before they run.") has no 2+ space
#     run inside it, so it is skipped — otherwise the word "run" in a sentence
#     would read as the verb `run`;
#   - a line whose first word is "rabadon" is an example, not a listing, so
#     `rabadon dev usage --days 7` under "examples" is allowed and stays allowed;
#   - the names field is cut at " [" or " <", so "budget [cap] [dir]" is the one
#     verb `budget` and not three words.
# Aliases sharing a row ("on | off | toggle") all count: the current help writes
# on and off that way, and reading only the first would have failed a correct
# implementation for a formatting choice.
HELP_TOKENS="$(awk '
  /^[ \t]+[a-z]/ {
    line = $0
    sub(/^[ \t]+/, "", line)
    if (line ~ /^rabadon([ \t]|$)/) next
    names = line
    if (match(names, /  +/)) {
      names = substr(names, 1, RSTART - 1)
    } else if (names ~ /[ \t]/) {
      next        # prose continuation: no description column, more than one word
    }
    if (match(names, / [[<]/)) names = substr(names, 1, RSTART - 1)
    n = split(names, parts, /[ \t|,]+/)
    for (i = 1; i <= n; i++)
      if (parts[i] ~ /^[a-z][a-z0-9_-]*$/) print parts[i]
  }' "$HELP_TXT" | sort -u)"

in_list() { # in_list <needle> <space separated haystack>
  for _w in $2; do [ "$_w" = "$1" ] && return 0; done
  return 1
}

# 1a. every surface token is advertised.
missing_surface=""
for v in $SURFACE; do
  in_list "$v" "$HELP_TOKENS" || missing_surface="$missing_surface $v"
done
if [ -z "$missing_surface" ]; then
  pass "1a all six surface tokens are in --help (init, on, off, usage, repair, doctor)"
else
  fail "1a --help does not advertise:$missing_surface"
fi

# 1b. no moved verb is advertised. This is the claim with teeth: moving the code
#     but leaving the verb on the help screen is the round not done.
still_listed=""
for v in $MOVED; do
  in_list "$v" "$HELP_TOKENS" && still_listed="$still_listed $v"
done
if [ -z "$still_listed" ]; then
  pass "1b none of the $BASE_MOVED_N moved verbs is still advertised in --help"
else
  fail "1b --help still advertises moved verbs:$still_listed"
  note "these must appear only under 'rabadon dev', if at all"
fi

# 1c. the surface is EXACTLY five rows and not one more. Counted over the verb
#     universe recorded in the baseline, so a word this test has never heard of
#     cannot inflate the count; and the allowance below is named, not hidden.
#
#     ALLOWED BESIDES THE FIVE, and this list is deliberately three words long:
#       dev                    the new door the moved verbs go behind
#       help, version          every CLI has them and neither is a product verb
#
#     status and toggle USED to be allowed here, on the reading that the T2
#     table named neither so T2 decided neither. The human decision of
#     2026-08-21 settled it the other way: both are inside the 29 that move, so
#     both must be off the help screen. They are not exempt and nothing else is
#     added to this line. Widening ALLOWANCE is the cheapest way to fake 1c, and
#     `git log -p -- reports/T2/accept.sh` shows the widening in one hunk.
#
#     ONE THING THE IMPLEMENTING SESSION WILL HIT, so it is written here rather
#     than discovered as a surprise: `fleet` is marked #unlisted in the
#     dispatcher and IS NEVERTHELESS ON THE HELP SCREEN today —
#         $ ./native/rabadon-cli.sh --help | grep -n fleet
#         19:  fleet [root]        install the hooks across every git repo under root
#     The #unlisted comment governs the dispatcher's derived verb list, not the
#     hand-written help text, and the two had drifted. So 1c is red on `fleet`
#     as well, and that is not a contradiction of discards.txt item 2: item 2
#     says do not MOVE the five, and 2c enforces that they keep working exactly
#     where they work today. Deleting one advertising line from the help text is
#     not moving a verb — it is the literal content of T2 ("the surface goes
#     down to five"). guard, pack, spin and statusline are genuinely absent from
#     the help text; fleet was the only drifted one.
ALLOWANCE="dev help version"
UNIVERSE="$DISPATCH_LISTED $DISPATCH_UNLISTED dev"
surface_found=""
for t in $HELP_TOKENS; do
  in_list "$t" "$UNIVERSE" || continue
  in_list "$t" "$ALLOWANCE" && continue
  surface_found="$surface_found $t"
done
surface_found="$(printf '%s\n' $surface_found | sort -u | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//')"
surface_want="$(printf '%s\n' $SURFACE | sort -u | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//')"
if [ "$surface_found" = "$surface_want" ]; then
  pass "1c the advertised product surface is exactly the five rows (6 tokens: $surface_found)"
else
  fail "1c the advertised product surface is not the five rows"
  note "want: $surface_want"
  note "got:  ${surface_found:-(none)}"
  note "allowed alongside, uncounted: $ALLOWANCE"
fi

# ---------------------------------------------------------------------------
# CLAIM 2 — every moved verb still routes under `rabadon dev <verb>`.
#
# One list, 29 verbs, checked above before a single probe ran. It is not typed
# here; it comes out of baseline.txt, which derived it from the case arms of
# native/rabadon-cli.sh.
#
#   2a  all 29 route under `rabadon dev`
#   2b  the count actually probed was 29 — so a shortened list is red, not
#       quietly green with a smaller n
#   2c  the 5 #unlisted verbs did not REGRESS. Different claim, different shape:
#       T2 does not move them (discards.txt item 2), so requiring them under
#       `dev` would be requiring work the human ruled out of scope. What is
#       required is that they still answer on the path they answer on today.
#
# See the header for what "routes" means and why it is not "works".
# ---------------------------------------------------------------------------
head_ "CLAIM 2 — moved verbs still reachable under 'rabadon dev <verb>'"

# First, the door itself. If `dev` does not exist there is no point running 29
# probes that all say the same thing.
run_capped 20 "$RABADON" dev
DEV_RC="$CAP_RC"
DEV_OUT="$(cat "$CAP_OUT")"
if printf '%s' "$DEV_OUT" | grep -qiE "$UNKNOWN_RE"; then
  fail "2_ 'rabadon dev' itself is not a command yet"
  note "got: $(printf '%s' "$DEV_OUT" | head -n1)"
  DEV_EXISTS=0
else
  pass "2_ 'rabadon dev' is a command (exit $DEV_RC)"
  DEV_EXISTS=1
fi

# probe <verb> <prefix-args...> — did the dispatcher ROUTE it? Appends to
# bad.txt / slow.txt rather than returning, so the caller can report one line
# for a whole group. Exit 124 (killed at the cap) counts as routed: `serve`
# binds a port and blocks, and blocking is proof it was not rejected.
probe() {
  pv="$1"; shift
  run_capped 15 "$RABADON" "$@" --help
  pout="$(cat "$CAP_OUT")"
  if printf '%s' "$pout" | grep -qiE "$UNKNOWN_RE"; then
    printf '%s\n' "$pv" >> "$LAB/bad.txt"
  elif [ "$CAP_RC" -eq 127 ]; then
    printf '%s\n' "$pv" >> "$LAB/bad.txt"
  elif [ "$CAP_RC" -eq 124 ]; then
    printf '%s\n' "$pv" >> "$LAB/slow.txt"
  fi
}

flat() { tr '\n' ' ' < "$1" | sed -e 's/  */ /g' -e 's/ $//'; }

PROBED_N=0
if [ "$DEV_EXISTS" -eq 1 ]; then
  : > "$LAB/bad.txt"; : > "$LAB/slow.txt"
  for v in $MOVED; do
    probe "$v" dev "$v"
    PROBED_N=$((PROBED_N + 1))
  done
  if [ ! -s "$LAB/bad.txt" ]; then
    pass "2a all $PROBED_N moved verbs route under 'rabadon dev'"
    [ -s "$LAB/slow.txt" ] && note "routed but had to be capped (long-running, expected): $(flat "$LAB/slow.txt")"
  else
    fail "2a these do not route under 'rabadon dev': $(flat "$LAB/bad.txt")"
  fi
else
  fail "2a not run: 'rabadon dev' does not exist (all $BASE_MOVED_N moved verbs unreachable)"
  note "moved: $MOVED"
fi

# 2b. the arithmetic, said out loud. 2a reads "all N route" and N is whatever
#     the loop happened to iterate; if the list ever shrinks, "all 3 route" is
#     a true sentence and a green line. So the number is asserted separately
#     against the number the human decided.
if [ "$PROBED_N" -eq "$BASE_MOVED_N" ]; then
  pass "2b the number of verbs actually probed is $PROBED_N, the decided $BASE_MOVED_N"
else
  fail "2b probed $PROBED_N verbs, the decision says $BASE_MOVED_N must move"
fi

# 2c. REGRESSION ONLY, and the difference from 2a is the point. fleet, guard,
#     pack, spin and statusline are explicitly out of T2's scope: they are
#     already invisible (no --help row, no README entry), so moving them buys
#     nothing and would mean editing bin/rabadon.mjs, which is marked
#     never-edit. The claim is therefore NOT "they are under dev". It is "they
#     still answer where they answer today" — measured today, on this commit,
#     all five route. If T2's refactor breaks one of them in passing, that is a
#     regression and this line goes red.
: > "$LAB/bad.txt"; : > "$LAB/slow.txt"
UNLISTED_N=0
for v in $UNLISTED_KEEP; do
  probe "$v" "$v"
  UNLISTED_N=$((UNLISTED_N + 1))
done
if [ "$UNLISTED_N" -ne 5 ]; then
  fail "2c LIST_UNLISTED_KEEP has $UNLISTED_N verbs, it is the five #unlisted arms"
elif [ ! -s "$LAB/bad.txt" ]; then
  pass "2c the $UNLISTED_N #unlisted verbs still route on their own path (not moved, not broken)"
  [ -s "$LAB/slow.txt" ] && note "routed but had to be capped: $(flat "$LAB/slow.txt")"
else
  fail "2c #unlisted verbs REGRESSED — they route today and do not any more: $(flat "$LAB/bad.txt")"
  note "T2 does not move these; it must not break them either"
fi

# ---------------------------------------------------------------------------
# CLAIM 4 — rabadon-pipeline exists, rabadon-loop does not.
#   (numbered after the protocol's own list; claim 3 runs last because it is the
#    five-minute one and its log is the last thing anybody wants to scroll past)
# ---------------------------------------------------------------------------
head_ "CLAIM 4 — the binary is rabadon-pipeline, and rabadon-loop is gone"

if [ -x "$ROOT/native/rabadon-pipeline" ]; then
  pass "4a native/rabadon-pipeline is built and executable"
else
  fail "4a native/rabadon-pipeline does not exist (or is not executable)"
fi

if [ -e "$ROOT/native/rabadon-loop" ]; then
  fail "4b native/rabadon-loop still exists"
  note "if this is a stale artifact of an earlier build, 'make clean && make' settles it —"
  note "but a shipped tree that still carries the old name has not finished the rename"
else
  pass "4b native/rabadon-loop is gone"
fi

# 4c. the name, not just the file. A rename that leaves the Makefile, the npm
#     platform packages and the release workflow still naming rabadon-loop is a
#     rename that breaks on the next clean build or the next publish. Docs and
#     records are excluded: reports/, the protocol and the changelog are where
#     the OLD name is supposed to survive, as history.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  loop_refs="$(git -C "$ROOT" ls-files \
    | grep -v -e '^reports/' -e '^PROTOCOL-T1-T8\.md$' -e '^CHANGELOG\.md$' -e '^docs/' -e '^site/' \
    | tr '\n' '\0' \
    | xargs -0 grep -nI 'rabadon-loop' 2>/dev/null || true)"
  if [ -z "$loop_refs" ]; then
    pass "4c no build file, package or script still names rabadon-loop"
  else
    fail "4c the name rabadon-loop survives in files that are built or shipped"
    printf '%s\n' "$loop_refs" | sed 's/^/      /'
  fi
else
  note "4c skipped: not a git checkout"
fi

# ---------------------------------------------------------------------------
# CLAIM 5 (anti reward-hacking, protocol section 6.2) — NOTHING WAS DELETED.
#
# T2's own words: "Hicbir kod silinmez." The cheapest way to make claims 1 and 4
# green is to delete the verbs and their tests instead of moving them, and the
# test count in claim 3 is only one of the two places that would show. These are
# the other one.
# ---------------------------------------------------------------------------
head_ "CLAIM 5 — nothing was deleted (loop.cpp was RENAMED, not removed)"

if [ -f "$ROOT/native/pipeline.cpp" ]; then
  pass "5a native/pipeline.cpp exists"
else
  fail "5a native/pipeline.cpp does not exist"
fi
if [ -f "$ROOT/native/loop.cpp" ]; then
  fail "5b native/loop.cpp still exists — the rename did not happen"
else
  pass "5b native/loop.cpp is gone (renamed)"
fi

for f in $(blist LIST_MOVED_CPP_KEEP); do
  if [ -f "$ROOT/native/$f" ]; then
    pass "5c native/$f still on disk (moved under dev, not deleted)"
  else
    fail "5c native/$f was DELETED — T2 moves it under dev, it does not remove it"
  fi
done

now_cpp="$(ls "$ROOT"/native/*.cpp 2>/dev/null | wc -l | tr -d ' ')"
if [ "$now_cpp" -ge "$BASE_CPP" ]; then
  pass "5d native/*.cpp count did not drop ($now_cpp >= baseline $BASE_CPP)"
else
  fail "5d native/*.cpp count dropped: $now_cpp < baseline $BASE_CPP"
  note "a rename keeps the count; a deletion lowers it"
fi

now_tests="$(ls "$ROOT"/native/*_test.sh 2>/dev/null | wc -l | tr -d ' ')"
if [ "$now_tests" -ge "$BASE_TESTFILES" ]; then
  pass "5e native/*_test.sh file count did not drop ($now_tests >= baseline $BASE_TESTFILES)"
else
  fail "5e test FILE count dropped: $now_tests < baseline $BASE_TESTFILES"
  note "checked as a count, not by name: loop_test.sh may legitimately become pipeline_test.sh"
fi

now_mk="$(awk '/^test: all$/{i=1;next} i && /^[a-zA-Z][a-zA-Z0-9_.-]*:/{exit} i' "$ROOT/Makefile" \
  | grep -oE '\./native/[a-z0-9_]+\.sh' | wc -l | tr -d ' ')"
if [ "$now_mk" -ge "$BASE_MKSCRIPTS" ]; then
  pass "5f the Makefile test target still invokes $now_mk scripts (>= baseline $BASE_MKSCRIPTS)"
else
  fail "5f the Makefile test target invokes $now_mk scripts, baseline was $BASE_MKSCRIPTS"
  note "dropping a script from the target hides its tests without deleting the file"
fi

# 5g. the other half of section 6.2: skipped tests. A suite that still exists but
#     is short-circuited passes 5e and lowers claim 3 in a way that is easy to
#     explain away. Named here so it has to be explained on purpose.
skip_hits="$(grep -rnE '^[[:space:]]*(exit 0|return 0)[[:space:]]*#[[:space:]]*(skip|todo|disabled)|GTEST_SKIP|SKIP_ALL=1' \
  "$ROOT"/native/*_test.sh 2>/dev/null || true)"
if [ -z "$skip_hits" ]; then
  pass "5g no test suite short-circuits itself with a skip marker"
else
  fail "5g a test suite short-circuits itself"
  printf '%s\n' "$skip_hits" | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
# CLAIM 3 — `make test` is green AND its number did not drop.
#
# Run last: it takes about six minutes. Counted with the exact command written
# into baseline.txt, over a fresh log. Rising is fine; falling is the red.
# ---------------------------------------------------------------------------
head_ "CLAIM 3 — make test is green and the count did not drop (baseline $BASE_PASSED)"

MT_LOG="$(mktemp -t rabadon-t2-maketest)"
MT_START=$(date +%s)
set +e
make -C "$ROOT" test > "$MT_LOG" 2>&1
MT_RC=$?
set -e
MT_SECS=$(( $(date +%s) - MT_START ))

if [ "$MT_RC" -eq 0 ]; then
  pass "3a make test exited 0 (${MT_SECS}s)"
else
  fail "3a make test exited $MT_RC (${MT_SECS}s)"
  note "last lines:"
  tail -n 15 "$MT_LOG" | sed 's/^/      | /'
fi

NOW_PASSED="$(grep -oE '[0-9]+ (passed|ok), *[0-9]+ failed' "$MT_LOG" \
  | grep -oE '^[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo 0)"
NOW_FAILED="$(grep -oE '[0-9]+ (passed|ok), *[0-9]+ failed' "$MT_LOG" \
  | grep -oE '[0-9]+ failed' | grep -oE '^[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo 0)"
NOW_PASSED="${NOW_PASSED:-0}"
NOW_FAILED="${NOW_FAILED:-0}"

if [ "$NOW_PASSED" -ge "$BASE_PASSED" ]; then
  pass "3b make test passing count did not drop: $NOW_PASSED >= baseline $BASE_PASSED"
else
  fail "3b make test passing count DROPPED: $NOW_PASSED < baseline $BASE_PASSED (-$((BASE_PASSED - NOW_PASSED)))"
  note "per-suite breakdown is in reports/T2/baseline.txt section 1 — diff it against:"
  note "$MT_LOG"
fi

if [ "$NOW_FAILED" -eq 0 ]; then
  pass "3c no suite reported a failure ($NOW_FAILED failed)"
else
  fail "3c suites reported $NOW_FAILED failures"
  grep -nE '[0-9]+ (passed|ok), *[1-9][0-9]* failed' "$MT_LOG" | sed 's/^/      /'
fi
note "full log: $MT_LOG"

# ---------------------------------------------------------------------------
printf '\n== T2 acceptance: %d green, %d red\n' "$PASS_N" "$FAIL_N"
if [ "$FAIL_N" -gt 0 ]; then
  printf 'T2 NOT ACCEPTED\n'
  exit 1
fi
printf 'T2 ACCEPTED\n'
exit 0
