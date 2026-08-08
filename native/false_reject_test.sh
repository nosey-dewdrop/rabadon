#!/bin/bash
# false_reject_test.sh — a repair may only be refused for something the PROPOSAL
# did. Two ways rabadon was refusing correct work for something rabadon did.
#
# WHY THIS CLASS IS THE EXPENSIVE ONE. Every other check in this repository hunts
# the miss: a fake fix that buys a green. This file hunts the opposite, and the
# opposite costs more. The product's sentence is that a held repair really was
# verified, and a verdict is worth exactly what its noise floor allows. A judge
# that refuses correct work at random is not stricter than one that does not. It
# is louder, and a reader cannot tell the two apart from the outside.
#
# ---------------------------------------------------------------------------
# ONE — THE ISOLATED COPY CACHED THE SOURCE IT REPLACED
# ---------------------------------------------------------------------------
# Read out of the work directory of a run that had just been rejected:
#
#     work/calc.py                     ->  return a + b     (the correct fix)
#     cd work && python3 -c 'import calc; print(calc.add(2,3))'
#                                      ->  -1               (the bug)
#     rm -rf __pycache__ && same again ->  5                (the fix)
#
# rabadon copied the project, let a proposer write a correct fix into the copy,
# re-ran the project's own check there, watched it fail, and recorded
# REPAIR_FAIL. The fix was right. The interpreter never read it.
#
# It needed three things at once, which is why a red-team round that was
# explicitly hunting holes walked past it:
#   1. CPython validates a .pyc against the source mtime AND SIZE, at one second
#      of resolution.
#   2. `cp -R` preserves mtime, so the copy inherits the exact timestamp the
#      .pyc recorded and never looks newer than its own cache.
#   3. `a - b` -> `a + b` is the same number of bytes.
# Miss one and the cache is invalidated and the fix is seen. Hit all three inside
# the same second and every field the cache checks still agrees.
#
# Measured on a three-line fixture, twelve runs, proposer that touches no stdin:
# NINE false rejections out of twelve before the fix, zero out of twelve after.
# Zero out of twelve when the fix changed the byte count, zero out of twelve with
# bytecode writing disabled — two controls, one mechanism.
#
# ---------------------------------------------------------------------------
# TWO — THE PROPOSER INHERITED THE OPERATOR'S STDIN
# ---------------------------------------------------------------------------
# The prompt reaches the proposer as an argument, so nothing in the repair path
# ever needed stdin. run_shell redirected fd 1 and fd 2 into its pipe and left
# fd 0 alone. A proposer that reads stdin therefore blocks on whatever the caller
# happened to hand rabadon, until the wall clock fires, and the run is written to
# the ledger as REPAIR_FAIL why="proposer timed out".
#
# Nothing was proposed, so nothing was rejected. Worse, the SAME proposal passes
# when the caller's stdin is already closed: run it from a script and the repair
# is held, run it from a terminal or behind a pipe and the identical repair is
# refused. That is the shape that kept it invisible, and it is also the reason it
# matters more than the timeout it produced — a judgement that depends on how its
# caller was invoked is not deterministic, and deterministic is the whole claim.
#
#   RABADON_REPAIR_BIN=/path/to/old ./native/false_reject_test.sh   # show it red
#
# The old binary needs its siblings beside it: rabadon-repair finds rabadon-truth
# in its own directory, and a copy alone in /tmp discovers no test files, locks
# nothing, and produces a DIFFERENT refusal that looks like the same one. Case 3
# checks for that explicitly rather than trusting the reader to notice.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
REPAIR="${RABADON_REPAIR_BIN:-$HERE/rabadon-repair}"
[ -x "$REPAIR" ] || { echo "build first: make native/rabadon-repair"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

ROOT="$(mktemp -d /tmp/rabadon-falsereject.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT
export RABADON_DIR="$ROOT/ledger"; mkdir -p "$RABADON_DIR/spool"
export RABADON_DRILL=1

echo "false rejection — a correct fix refused for something rabadon did"
echo

# The bug and its fix are the same byte length on purpose. That is condition 3,
# and it is not a contrivance: it is what a one-character fix looks like.
mk_repo() {
  local d="$1"; mkdir -p "$d"
  printf 'def add(a, b):\n    return a - b\n' > "$d/calc.py"
  cat > "$d/test_calc.py" <<'EOF'
import calc
assert calc.add(2, 3) == 5, "add(2,3) must be 5"
print("ok")
EOF
  # the pre-check an operator runs before asking for a repair, which is where the
  # .pyc comes from. Without this line there is no cache to go stale.
  ( cd "$d" && python3 test_calc.py >/dev/null 2>&1 )
  [ -d "$d/__pycache__" ] || { echo "  (this python writes no __pycache__; the case cannot be built)"; return 1; }
}

# an honest proposal, plus the mtime put back. Restoring the timestamp forces the
# same-second collision that happens on its own three times in four; a test that
# samples a race goes green on a broken binary whenever the race goes the other
# way, which is the same as not having the test.
mk_honest() {
  cat > "$1" <<'PROPOSER'
#!/bin/bash
printf 'def add(a, b):\n    return a + b\n' > calc.py
# Stamp the source with the timestamp the CACHE is holding, read out of the .pyc
# header rather than off the file. The current source mtime is nearly the same
# number and only nearly: it left this case green about one run in ten, and a
# test that is red nine times in ten clears a broken binary whenever somebody is
# unlucky. The header is what actually decides, so the header is what is matched.
#
# On a binary that clears the cache there is no header to read and this is a
# no-op: the same proposal, judged on its merits, which is the point.
python3 -c "
import glob, os, struct
p = glob.glob('__pycache__/*.pyc')
if p:
    mt = struct.unpack('<4sIII', open(p[0], 'rb').read(16))[2]
    os.utime('calc.py', (mt, mt))
"
PROPOSER
  chmod +x "$1"
}

mk_cheat() {
  printf '#!/bin/bash\nprintf "print(\\"ok\\")\\n" > test_calc.py\n' > "$1"
  chmod +x "$1"
}

run() {   # run <dir> <proposer> -> OUT, RC
  OUT=$(cd "$1" && RABADON_CLAUDE_BIN="$2" "$REPAIR" "$1" \
        --cmd "python3 test_calc.py" --timeout 30 2>&1); RC=$?
}

# ---------------------------------------------------------------------------
echo "1. an honest fix behind a stale cache is VERIFIED, not refused"
# ---------------------------------------------------------------------------
H="$ROOT/honest"
if mk_repo "$H"; then
  mk_honest "$ROOT/honest.sh"
  run "$H" "$ROOT/honest.sh"
  if [ "$RC" -eq 0 ] && grep -q "VERIFIED" <<< "$OUT"; then
    ok "the correct fix is held (exit 0)"
  else
    bad "a correct fix was refused (exit $RC) — the arbiter re-ran cached bytecode"
    sed 's/^/        /' <<< "$OUT" | tail -12
  fi
  if grep -q "return a - b" "$H/calc.py"; then
    ok "the fix is HELD, not applied — the operator's tree still carries the bug"
  else
    bad "the repair edited the tree; a held repair is a patch, not a commit"
  fi
else
  bad "could not build the stale-cache fixture"
fi

# ---------------------------------------------------------------------------
echo "2. a proposer that reads stdin is not a failed repair"
# ---------------------------------------------------------------------------
# stdin is a pipe that stays open, which is what a terminal and a piped caller
# both hand it. On the binary that inherited fd 0 this case does not fail fast:
# it eats the whole proposer timeout and lands in the ledger as a repair that
# was tried and refused.
S="$ROOT/stdin"
if mk_repo "$S"; then
  cat > "$ROOT/reads-stdin.sh" <<'EOF'
#!/bin/bash
cat >/dev/null
printf 'def add(a, b):\n    return a + b\n' > calc.py
EOF
  chmod +x "$ROOT/reads-stdin.sh"
  T0=$(date +%s)
  OUT=$(cd "$S" && sleep 25 | RABADON_CLAUDE_BIN="$ROOT/reads-stdin.sh" "$REPAIR" "$S" \
        --cmd "python3 test_calc.py" --timeout 10 2>&1); RC=$?
  T1=$(date +%s)
  if grep -q "proposer timed out" <<< "$OUT"; then
    bad "the proposer hung on the caller's stdin and the run was recorded as a failed repair ($((T1-T0))s)"
  elif [ "$RC" -eq 0 ] && grep -q "VERIFIED" <<< "$OUT"; then
    ok "the proposal ran and was held, whatever the caller left on stdin"
  else
    bad "the run neither held nor timed out (exit $RC)"
    sed 's/^/        /' <<< "$OUT" | tail -10
  fi
else
  bad "could not build the stdin fixture"
fi

# ---------------------------------------------------------------------------
echo "3. neither fix bought a false ACCEPTANCE"
# ---------------------------------------------------------------------------
# Case 1 deletes files from the isolated copy and case 2 changes what the
# proposer is handed. The whole product is an argument about what may not be
# touched, so a proposal that neuters the test has to be refused exactly as
# before. Trading a false rejection for a false acceptance is the worse trade.
C="$ROOT/cheat"
if mk_repo "$C"; then
  mk_cheat "$ROOT/cheat.sh"
  run "$C" "$ROOT/cheat.sh"
  if [ "$RC" -ne 0 ] && grep -q "hash-locked test file" <<< "$OUT"; then
    ok "a test-neutering proposal is still rejected (exit $RC, by the test lock)"
  else
    bad "the cheat was not rejected by the test lock (exit $RC)"
    sed 's/^/        /' <<< "$OUT" | tail -12
  fi
  # and the lock has to have been BUILT. A binary invoked away from its siblings
  # cannot reach rabadon-truth, discovers no test files, locks nothing, and is
  # caught one surface out by the harness rule instead. It says so on stderr
  # rather than going quiet, and that sentence is the difference between "the
  # lock held" and "there was no lock".
  if grep -q "could not read a testFiles list" <<< "$OUT"; then
    bad "nothing was hash-locked: rabadon-truth was unreadable from this binary's directory"
  else
    ok "the test-file lock was actually built, not merely unviolated"
  fi
  if grep -q "import calc" "$C/test_calc.py"; then
    ok "the rejected run left the test file as it found it"
  else
    bad "the rejected run left the neutered test in the tree"
  fi
else
  bad "could not build the cheat fixture"
fi

# ---------------------------------------------------------------------------
echo "4. the purge takes bytecode and nothing else"
# ---------------------------------------------------------------------------
# Two ways to get this wrong. Delete too much and the patch handed to the
# operator carries deletions they never proposed. Match on the name rather than
# the kind and a source file called cache.py goes with it, along with anything
# living under a directory whose name merely contains the word.
K="$ROOT/keep"
if mk_repo "$K"; then
  mkdir -p "$K/pycache_notes"
  printf 'notes that must survive\n' > "$K/pycache_notes/README.txt"
  printf 'KEEP_ME = 1\n' > "$K/cache.py"
  printf 'not really bytecode\n' > "$K/vendor.pyc.txt"
  mk_honest "$ROOT/honest2.sh"
  run "$K" "$ROOT/honest2.sh"
  PATCH=$(ls "$K"/.rabadon/repair-*.patch 2>/dev/null | tail -1)
  if [ "$RC" -eq 0 ] && [ -n "$PATCH" ]; then
    if grep -qE '^(\-\-\-|\+\+\+).*(__pycache__|\.pyc)' "$PATCH"; then
      bad "the patch handed to the operator contains cache files"
      grep -E '^(\-\-\-|\+\+\+)' "$PATCH" | sed 's/^/        /'
    else
      ok "the patch names only source, no cache file appears in it"
    fi
  else
    bad "no patch was written to compare (exit $RC)"
  fi
  MISSING=""
  for f in pycache_notes/README.txt cache.py vendor.pyc.txt; do
    [ -f "$K/$f" ] || MISSING="$MISSING $f"
  done
  [ -z "$MISSING" ] && ok "nothing merely named like a cache was removed from the tree" \
                    || bad "the tree lost files:$MISSING"
else
  bad "could not build the keep fixture"
fi

echo
echo "  pass $pass   fail $fail"
[ "$fail" -eq 0 ] && echo "  false rejection: GREEN" || echo "  false rejection: RED"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
