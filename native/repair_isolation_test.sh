#!/bin/bash
# repair_isolation_test.sh — the isolated copy has to BE isolated.
#
# rabadon repair copies the repo to /tmp and re-runs the SAME check there. The
# whole verdict rests on one assumption: the check that runs in the copy reads
# the copy. A python project installed with `pip install -e .` breaks that
# assumption silently — the editable install writes an ABSOLUTE path into a
# .pth file in site-packages, the .pth is copied along with the venv, and the
# copy's interpreter dutifully imports the ORIGINAL tree.
#
# Measured on this machine before this test existed (real venv, real
# `pip install -e .`, honest proposer that fixed the source in the work copy):
#   the work copy's source read `return a + b` (fixed)
#   the work copy's import resolved to  /private/tmp/.../proj/src/demopkg/__init__.py
#   verdict: "the proposed fix did NOT turn the check green" — exit 2
# Safe, but BLIND: the proposal was blamed for a file it never touched, and the
# ledger recorded a REPAIR_FAIL whose stated reason was false. The opposite
# polarity is worse: the same anchor lets a check go green on code that is not
# in the held patch.
#
# So the anchor is not a repair problem, it is a precondition problem: exit 3,
# the same class as "no runnable check" and "proposer unavailable" — rabadon
# could not honestly attempt this, and nothing reaches the ledger.
#
# Cases (K2 — the POSITIVE control comes first, and it is not a toy):
#   1. a python project with a real venv, a real .pth, a pyvenv.cfg whose
#      `command =` line names the original path, and a console-script shim whose
#      shebang is the original absolute interpreter — but the .pth path is
#      RELATIVE, so the copy resolves inside itself. Normal flow, REPAIR_OK.
#      Without this case, "must refuse" could be satisfied by refusing always.
#   2. the same project, one byte-level difference: the .pth holds the ABSOLUTE
#      original path (what `pip install -e .` really writes). exit 3, the
#      message says the check resolves outside the isolated copy, and it NAMES
#      the file — a refusal you cannot act on is a refusal you cannot trust.
#   3. exit 3 claims nothing: the user's tree is untouched and no REPAIR_*
#      event reaches the spool.
#   4. an absolute symlink into the original tree (the `npm link` shape) is the
#      same escape in another ecosystem.
#   5. a bin/ shim whose shebang points at the original tree counts ONLY when
#      the check command actually invokes it. Case 1 already proved the
#      unreferenced shim does not trip the gate; this proves the referenced one
#      does. Both directions, or the rule is untested.
#   6. no scan ceiling: a monorepo's second venv is found behind 400 other files
#      and 6 levels of nesting. (repair already shipped one silent cap — the
#      hash-lock list stopped at 32 and a foreign repo sailed through as
#      VERIFIED. Not twice.) The same case pins the other edge: a .pth that is
#      NOT in a site-packages directory is inert and must not be flagged.
#   7. green repo with an anchor: still "nothing to repair". The gate must not
#      fire before there is something to isolate.
#
# Mutation-checked, both directions, measured not assumed:
#   scan deleted (`if (false)`)         -> 5 passed, 7 failed (cases 2-6)
#   scan made to fire unconditionally   -> 8 passed, 4 failed (case 1, and the
#     ledger count in case 3, which drops to 0 STARTs because the clean project
#     never got to attempt anything either)
set -u
cd "$(dirname "$0")/.."
REPAIR=./native/rabadon-repair
[ -x "$REPAIR" ] || { echo "repair_isolation_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }
say()  { printf '%s\n' "$1" | sed 's/^/    | /'; }

TMP=$(mktemp -d /tmp/rabadon-repair-iso.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export RABADON_DIR="$TMP/ledger"; mkdir -p "$RABADON_DIR/spool"

# a proposer that really fixes the source, in cwd (= the isolated work copy)
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'EOF'
#!/bin/bash
printf 'def add(a, b):\n    return a + b\n' > src/demopkg/__init__.py
echo done
EOF
chmod +x "$BIN/claude"
export RABADON_CLAUDE_BIN="$BIN/claude"

# A python project whose check runs through a REAL venv. $2 decides the single
# thing under test: how the .pth points at the source tree.
#   rel -> ../../../../src, resolved against site-packages, stays in the copy
#   abs -> /original/proj/src, exactly what `pip install -e .` writes
# Everything else is identical, including two decoys that MUST NOT trip the
# gate on their own: pyvenv.cfg's informational `command =` line and a
# console-script shim with an absolute shebang (every venv with pip has three).
mkpy() { # mkpy DIR rel|abs
  local d="$1" mode="$2"
  rm -rf "$d"; mkdir -p "$d/src/demopkg"
  printf 'def add(a, b):\n    return a - b  # BUG\n' > "$d/src/demopkg/__init__.py"
  cat > "$d/check.py" <<'EOF'
import demopkg
assert demopkg.add(2, 3) == 5, "add(2,3) must be 5"
print("ok")
EOF
  python3 -m venv --without-pip "$d/.venv" >/dev/null 2>&1 || return 1
  local sp; sp=$(echo "$d"/.venv/lib/python*/site-packages)
  [ -d "$sp" ] || return 1
  local real; real=$(cd "$d" && pwd -P)
  if [ "$mode" = abs ]; then printf '%s/src\n' "$real" > "$sp/__editable__.demopkg-0.1.0.pth"
  else                      printf '../../../../src\n' > "$sp/demopkg.pth"; fi
  printf '#!%s/.venv/bin/python3\nimport sys\nsys.exit(0)\n' "$real" > "$d/.venv/bin/demo-shim"
  chmod +x "$d/.venv/bin/demo-shim"
}

CHECK=".venv/bin/python check.py"
ESCAPE_MSG="resolves outside the isolated copy"

echo "repair isolation: the copy has to be the thing that gets checked"

# ---- 1. POSITIVE FIRST: relative .pth -> the copy checks the copy ----
P1="$TMP/p1"; mkpy "$P1" rel || { echo "repair_isolation_test: could not build a venv"; exit 1; }
OUT=$("$REPAIR" "$P1" --cmd "$CHECK" 2>&1); RC=$?
if [ $RC -eq 0 ]; then pass "self-contained venv: repair runs its normal course (exit 0)"
else fail "self-contained venv was blocked (rc=$RC)"; say "$OUT"; fi
if printf '%s' "$OUT" | grep -q "$ESCAPE_MSG"; then
  fail "self-contained venv falsely accused of escaping"; say "$OUT"
else pass "no false accusation: pyvenv.cfg's \`command =\` line and an absolute shim shebang do not trip the gate"; fi
ls "$P1/.rabadon/"repair-*.patch >/dev/null 2>&1 \
  && pass "self-contained venv: a patch was still held" || fail "no held patch in the clean case"

# ---- 2. the editable install: the same project, absolute .pth ----
P2="$TMP/p2"; mkpy "$P2" abs || exit 1
OUT=$("$REPAIR" "$P2" --cmd "$CHECK" 2>&1); RC=$?
if [ $RC -eq 3 ]; then pass "editable install (.pth holds the original path): exit 3"
else fail "editable install rc=$RC (expected 3)"; say "$OUT"; fi
if printf '%s' "$OUT" | grep -q "$ESCAPE_MSG"; then pass "the message says the check resolves outside the isolated copy"
else fail "no isolation message"; say "$OUT"; fi
if printf '%s' "$OUT" | grep -q "__editable__.demopkg-0.1.0.pth"; then pass "the refusal NAMES the file that anchors the check"
else fail "the refusal does not name the offending file"; say "$OUT"; fi

# ---- 3. exit 3 claims nothing ----
grep -q 'return a - b' "$P2/src/demopkg/__init__.py" && pass "exit 3: the user's tree is untouched" || fail "the tree was modified"
EV=$(cat "$RABADON_DIR/spool/"*.jsonl 2>/dev/null | grep -c '"ev":"REPAIR_START"' || true)
[ "$EV" -eq 1 ] && pass "exit 3: no repair attempt on the ledger (1 START, from case 1 only)" \
                || fail "ledger recorded $EV REPAIR_START (expected 1)"

# ---- 4. the same escape via an absolute symlink (npm link shape) ----
P4="$TMP/p4"; mkpy "$P4" rel || exit 1
mkdir -p "$P4/node_modules"; ln -s "$(cd "$P4" && pwd -P)/src" "$P4/node_modules/demopkg"
OUT=$("$REPAIR" "$P4" --cmd "$CHECK" 2>&1); RC=$?
if [ $RC -eq 3 ] && printf '%s' "$OUT" | grep -q "$ESCAPE_MSG"; then pass "absolute symlink into the original tree: exit 3"
else fail "symlink escape rc=$RC"; say "$OUT"; fi

# ---- 5. bin shim: fatal only when the check actually runs it ----
# case 1 already proved the unreferenced shim is ignored; this is the other half.
P5="$TMP/p5"; mkpy "$P5" rel || exit 1
OUT=$("$REPAIR" "$P5" --cmd ".venv/bin/demo-shim && $CHECK" 2>&1); RC=$?
if [ $RC -eq 3 ] && printf '%s' "$OUT" | grep -q "demo-shim"; then pass "a shim the check invokes, with an original-tree shebang: exit 3"
else fail "referenced shim rc=$RC"; say "$OUT"; fi

# ---- 6. no ceiling: a monorepo's second venv, behind 400 files, 6 levels down ----
# the anchor is in a real site-packages (services/api/.venv/...), not a decorative
# deep folder — a .pth outside site-packages is inert and must stay unflagged.
P6="$TMP/p6"; mkpy "$P6" rel || exit 1
DEEP="$P6/services/api/.venv/lib/python3.99/site-packages"; mkdir -p "$DEEP"
mkdir -p "$P6/vendor"
i=0; while [ $i -lt 400 ]; do printf 'x\n' > "$P6/vendor/filler-$i.txt"; i=$((i+1)); done
printf '%s/services/api/src\n' "$(cd "$P6" && pwd -P)" > "$DEEP/zz-late.pth"
printf 'inert\n' > "$P6/vendor/not-site-packages.pth"
OUT=$("$REPAIR" "$P6" --cmd "$CHECK" 2>&1); RC=$?
if [ $RC -eq 3 ] && printf '%s' "$OUT" | grep -q "zz-late.pth"; then pass "no scan ceiling: an anchor behind 400 files and 6 dirs is still found"
else fail "deep/late anchor missed (rc=$RC)"; say "$OUT"; fi

# ---- 7. the gate must not fire before there is something to isolate ----
P7="$TMP/p7"; mkpy "$P7" abs || exit 1
printf 'def add(a, b):\n    return a + b\n' > "$P7/src/demopkg/__init__.py"
OUT=$("$REPAIR" "$P7" --cmd "$CHECK" 2>&1); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "nothing to repair"; then pass "green repo with an anchor: still 'nothing to repair', no refusal"
else fail "green repo with an anchor rc=$RC"; say "$OUT"; fi

echo "repair isolation: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
