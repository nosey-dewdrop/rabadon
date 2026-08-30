#!/usr/bin/env bash
# law_blind_test.sh — THE ANNOUNCEMENT MUST EQUAL THE BEHAVIOUR.
#
# Two phases in a row wrote "the open class is declared" on a card while the
# product's own `blind spots:` screen said nothing about it. A declaration that
# only exists in a report is not a declaration; Promise 1 is that rabadon does
# not go quiet about what it cannot check, and the screen is where that promise
# is kept or broken.
#
# So the declaration is compiled in (kLawBlind in native/gate.cpp), printed on
# the screen, and printable on its own (`rabadon-gate --law-blind`). This file
# holds the three ways it could still be a lie:
#
#   1. DECLARED BUT FALSE — a shape on the list that the gate actually refuses,
#      or that does not destroy the law when it runs. Then the product is
#      confessing to a hole it does not have, and the count is theatre.
#      Checked by RUNNING each declared shape in a fresh sandbox: the verdict
#      comes from the shipped binary, and GONE/THERE comes from looking for
#      .rabadon/guard.json afterwards. Every declared row must be ALLOW + GONE.
#   2. SCREEN AND TABLE DISAGREE — the number a user reads is typed by hand
#      somewhere else and drifts the day the table grows. Checked by parsing
#      the number and the class names back off the real SessionStart screen.
#   3. VACUOUS — an empty table would satisfy 1 and 2 forever. Checked with a
#      floor on the count, a floor on the number of distinct classes, and a
#      control set of shapes that the gate DOES refuse and that therefore may
#      not appear on the list.
#   4. UNDER-COUNTED — added 2026-08-30 (F3j), and it is the one that actually
#      went wrong. Arms 1-3 are all the SAME direction: everything declared is
#      really blind. None of them can see a shape that is really blind and is
#      NOT declared. The arbiter produced EIGHT more ALLOW + GONE shapes on
#      2026-08-30 and this suite stayed 10 passed / 0 failed — the exact class
#      F2-S14 closed for `--silencers`, back on a different table. So the lock
#      is now EQUALITY over a committed corpus (native/lawblind_corpus.txt):
#      { corpus shapes measured ALLOW + GONE } == { shapes declared }.
#      Both directions, both able to go red. The corpus is wider than the
#      answer on purpose — the shapes that come back REFUSED or harmless are
#      what stops the lock from being a restatement of the table.
#
# MEASURED, 2026-08-30 (F3i): 7 shapes, 2 classes, all seven ALLOW + GONE.
#   bash reports/kosu/kanit/f3i/probe-exec.sh   (the same two-column reading)
# RE-MEASURED, 2026-08-30 (F3j), over the corpus, same two-column reading:
#   36 candidate shapes -> 21 ALLOW + GONE, 10 REFUSED, 5 allowed but harmless.
#   raw reading: reports/kosu/kanit/f3j-k3-korpus-olcum.out
#   The 7 above are a SUBSET of the 21. The old number is not deleted; it was
#   right about what it looked at and wrong about how much it looked at.
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL - %s\n' "$1"; }

# NOT under a machine temp root: baseline-rm-rf-outside's temp carve-out would
# change the reading, and this suite is about the law rule, not that one.
T="$(mktemp -d "$HOME/.rb-lawblind.XXXXXX")"
cleanup() { chmod -R u+rwX "$T" 2>/dev/null; /bin/rm -rf "$T"; }
trap cleanup EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"

mkproj() { # mkproj <parent> -> creates <parent>/proj, echoes it
  rm -rf "$1"; mkdir -p "$1/proj/.rabadon" "$1/proj/.git" "$1/proj/build"
  printf 'ref: refs/heads/main\n'                         > "$1/proj/.git/HEAD"
  printf '{"project":"lb","bash":[],"protectedPaths":[]}\n' > "$1/proj/.rabadon/guard.json"
  printf '{"promise":"x"}\n'                              > "$1/proj/.rabadon/promise.json"
  printf 'x\n' > "$1/proj/README.md"
  echo "$1/proj"
}

verdict() { # verdict <proj> <cmd>  -> REFUSE|ALLOW
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"lb","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$1" "$2" \
    | env HOME="$T" RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
  [ "$?" = "2" ] && echo REFUSE || echo ALLOW
}

echo "law_blind: the blind-spots screen must equal what the binary really allows"

# ---------------------------------------------------------------------------
# The declaration itself.
DECL="$T/decl.tsv"
if ! "$GATE" --law-blind > "$DECL" 2>/dev/null; then
  bad "BLOCKED: \`$GATE --law-blind\` did not succeed — there is no declaration to check"
  printf 'law_blind: %d passed, %d failed\n' "$PASS" "$FAIL"; exit 1
fi
N="$(grep -c . "$DECL" || true)"
CLASSES="$(cut -f2 "$DECL" | sort -u)"
NC="$(printf '%s\n' "$CLASSES" | grep -c . || true)"

# 3a — VACUITY FLOOR. Everything below is set arithmetic and would pass on an
# empty set, so the floor comes first.
[ "$N" -ge 21 ] \
  && ok "the binary declares $N blind shapes (>=21; an empty table would make every arm below vacuous)" \
  || bad "only $N shapes declared — 21 were measured ALLOW+GONE on 2026-08-30, so this is a shrink, not a fix"
[ "$NC" -ge 4 ] \
  && ok "and $NC distinct classes (>=4: the walk that never names the law, the tree removed from outside, the tree moved away, the root deleted by its own name)" \
  || bad "only $NC class(es) declared, expected at least 4"

# ---------------------------------------------------------------------------
# 1 — DECLARED BUT FALSE. Each row is judged by the gate and then actually run.
i=0; badrows=""
while IFS="$(printf '\t')" read -r SHAPE KLASS; do
  [ -n "${SHAPE:-}" ] || continue
  i=$((i+1))
  P="$(mkproj "$T/v$i")"
  V="$(verdict "$P" "$SHAPE")"
  Q="$(mkproj "$T/e$i")"
  ( cd "$Q" && eval "$SHAPE" ) >/dev/null 2>&1
  if [ -s "$Q/.rabadon/guard.json" ]; then E=THERE; else E=GONE; fi
  [ "$V" = "ALLOW" ] && [ "$E" = "GONE" ] || badrows="$badrows
    [$V $E] $SHAPE"
  [ -n "${KLASS:-}" ] || badrows="$badrows
    [no class] $SHAPE"
done < "$DECL"
[ "$i" = "$N" ] \
  && ok "all $N declared rows were read back with a class beside them" \
  || bad "read $i rows out of $N — the declaration does not parse as shape<TAB>class"
[ -z "$badrows" ] \
  && ok "every declared shape is really ALLOW and really leaves .rabadon/guard.json GONE" \
  || bad "declared shapes that the binary does NOT actually let through, or that do not destroy the law:$badrows"

# ---------------------------------------------------------------------------
# 3b — CONTROL. Shapes the gate refuses may not be on a list of things it says
# it cannot see. Without this arm the table could be padded to any length.
overclaim=""; controlseen=0
for c in "rm -rf .rabadon" "rm .rabadon/guard.json" "find . -path '*/.rabadon/*' -delete"; do
  P="$(mkproj "$T/c$controlseen")"; controlseen=$((controlseen+1))
  V="$(verdict "$P" "$c")"
  [ "$V" = "REFUSE" ] || bad "control: \`$c\` was $V — the fixture cannot tell refusal from allowance"
  cut -f1 "$DECL" | grep -Fqx "$c" && overclaim="$overclaim $c"
done
[ "$controlseen" = 3 ] && ok "control: three shapes that the gate really refuses were exercised" \
                       || bad "control set did not run"
[ -z "$overclaim" ] \
  && ok "and none of them appears on the blind list — the count is not padded with refused shapes" \
  || bad "these REFUSED shapes are declared blind:$overclaim"

# ---------------------------------------------------------------------------
# 4 — THE EQUALITY. THE ONE ARM THAT LOOKS THE OTHER WAY.
#
# Everything above asks "is what you declared true". This asks "is what is true
# declared". Same reading, same shipped binary, same two columns — applied to a
# corpus that nobody promised was blind. Whatever comes back ALLOW + GONE is
# blind whether or not the table admits it, and a product that stays quiet about
# it is breaking Promise 1 in the direction that costs the user something.
CORPUS="$HERE/lawblind_corpus.txt"
if [ ! -s "$CORPUS" ]; then
  bad "BLOCKED: no corpus at $CORPUS — the equality lock has nothing to measure over"
else
  MEAS="$T/measured.txt"; : > "$MEAS"
  seen=0; refused=0; harmless=0
  while IFS= read -r S; do
    case "$S" in ''|'#'*) continue ;; esac
    seen=$((seen+1))
    P="$(mkproj "$T/q$seen")"
    V="$(verdict "$P" "$S")"
    Q="$(mkproj "$T/w$seen")"
    ( cd "$Q" && eval "$S" ) >/dev/null 2>&1
    if [ -s "$Q/.rabadon/guard.json" ]; then E=THERE; else E=GONE; fi
    if [ "$V" = "ALLOW" ] && [ "$E" = "GONE" ]; then printf '%s\n' "$S" >> "$MEAS"
    elif [ "$V" = "REFUSE" ]; then refused=$((refused+1))
    else harmless=$((harmless+1)); fi
  done < "$CORPUS"

  # 4a — THE CORPUS IS NOT A COPY OF THE ANSWER. If every line came back blind
  # the "equality" below would be an identity and would never move again.
  [ "$seen" -ge 30 ] \
    && ok "the corpus offers $seen candidate shapes to measure (>=30)" \
    || bad "the corpus is only $seen lines — too narrow to be evidence of anything"
  [ "$refused" -ge 5 ] && [ "$harmless" -ge 2 ] \
    && ok "and it is genuinely mixed: $refused of them the gate REFUSES, $harmless are allowed but leave the law standing" \
    || bad "the corpus is not mixed ($refused refused, $harmless harmless) — it is a restatement of the table, not a test of it"

  # 4b — EVERY SHAPE THE BINARY REALLY LETS THROUGH IS ON THE LIST.
  # This is the assertion that was missing. It fails today by fourteen.
  undeclared=""
  while IFS= read -r S; do
    [ -n "$S" ] || continue
    cut -f1 "$DECL" | grep -Fqx "$S" || undeclared="$undeclared
    $S"
  done < "$MEAS"
  NB="$(grep -c . "$MEAS" || true)"
  [ -z "$undeclared" ] \
    && ok "all $NB shapes measured ALLOW+GONE are declared — the screen is not under-counting" \
    || bad "measured ALLOW+GONE and NOT declared — the user is told a smaller number than the truth:$undeclared"

  # 4c — AND NOTHING IS DECLARED THAT THE CORPUS CANNOT SEE. Without this a row
  # could be hidden from 4b simply by leaving it out of the corpus, and the
  # equality would quietly become a subset again.
  uncovered=""
  while IFS= read -r S; do
    [ -n "$S" ] || continue
    grep -Fqx "$S" "$CORPUS" || uncovered="$uncovered
    $S"
  done < <(cut -f1 "$DECL")
  [ -z "$uncovered" ] \
    && ok "every declared shape is in the corpus, so every declared shape is re-measured each run" \
    || bad "declared but outside the corpus — these rows are never re-measured:$uncovered"

  # 4d — THE TWO SETS ARE THE SAME SET, stated once, as a set.
  if diff <(sort "$MEAS") <(cut -f1 "$DECL" | sort) >/dev/null 2>&1; then
    ok "DECLARED == MEASURED-BLIND over the corpus ($NB shapes) — the announcement is the behaviour"
  else
    bad "DECLARED != MEASURED-BLIND:"
    diff <(sort "$MEAS") <(cut -f1 "$DECL" | sort) | sed 's/^/       /'
  fi
fi

# ---------------------------------------------------------------------------
# 2 — THE SCREEN. Parse the number and the classes back off a real SessionStart.
SP="$(mkproj "$T/screen")"
SCR="$T/screen.out"
printf '{"hook_event_name":"SessionStart","cwd":"%s","session_id":"lbscr"}' "$SP" \
  | env HOME="$T" RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" > "$SCR" 2>&1
grep -q "blind spots:" "$SCR" \
  && ok "the session screen still prints a \`blind spots:\` block" \
  || bad "no blind spots block on the screen — the declaration is invisible to the user again"
SCRN="$(sed -n 's/.*- \([0-9][0-9]*\) measured shapes DESTROY.*/\1/p' "$SCR" | head -1)"
[ "${SCRN:-}" = "$N" ] \
  && ok "the screen says $SCRN shapes and the binary declares $N — same number, one source" \
  || bad "the screen says '${SCRN:-nothing}' and --law-blind declares $N — the count is typed twice"
missing=""
while IFS= read -r k; do
  [ -n "$k" ] || continue
  grep -Fq "$k" "$SCR" || missing="$missing
    $k"
done <<EOF
$CLASSES
EOF
[ -z "$missing" ] \
  && ok "every declared class is named on the screen, not just counted" \
  || bad "classes declared but never printed for the user:$missing"
grep -Fq "commit .rabadon/ to git" "$SCR" \
  && ok "and the screen answers the third question every refusal owes: what the user does next" \
  || bad "the screen names the hole and gives the user nothing to do about it"

printf 'law_blind: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
