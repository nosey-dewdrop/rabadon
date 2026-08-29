#!/usr/bin/env bash
# 3-skip-mutasyon.sh — F3d card 2's mutation proof, one procedure per repair.
#
# Every repaired branch is FORCED to fire, and the suite must then either go
# RED or ANNOUNCE the skip with a name and a number. Silence is the failure
# being repaired, so silence here means the repair did not take.
#
# Nothing below edits a suite. The branches are forced from the outside — a
# PATH with the tool removed, a shim that lies about `id -u`, a source file
# touched so the tree goes out of date — and everything is put back.
set -u
cd "$(dirname "$0")/../../../.."
echo "== F3d card 2: mutation proof for every repaired skip branch =="
echo

SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT

# A PATH WITH ONE COMMAND GENUINELY ABSENT. The first version of this put a
# shim that exits 127 at the front of PATH — and `command -v <name>` still
# found the shim, so every suite took the arm it was supposed to skip and blew
# up for the wrong reason (measured: redbase_scope 4 ok / 5 FAIL, and none of
# the five was the skip). A symlink farm is the only honest form: every
# executable on the real PATH is linked into one directory, minus the name
# being hidden, and that directory becomes the whole PATH.
hide() {  # hide <name>... -> prints a PATH in which those names do not exist
  d="$SHIM/farm-$(printf '%s-' "$@")"
  if [ ! -d "$d" ]; then
    mkdir -p "$d"
    old_ifs=$IFS; IFS=:
    for p in $PATH; do
      [ -d "$p" ] || continue
      for f in "$p"/*; do
        [ -x "$f" ] && [ ! -d "$f" ] || continue
        b="$(basename "$f")"
        hidden=0
        for n in "$@"; do [ "$b" = "$n" ] && hidden=1; done
        [ "$hidden" = 1 ] && continue
        [ -e "$d/$b" ] || ln -s "$f" "$d/$b" 2>/dev/null
      done
    done
    IFS=$old_ifs
  fi
  printf '%s' "$d"
}

run() {  # run <label> <file> [env assignments...]
  label="$1"; f="$2"; shift 2
  out="$(env "$@" "./native/$f" 2>&1)"; rc=$?
  echo "--- $label"
  echo "    file : native/$f"
  echo "    exit : $rc"
  echo "    last : $(printf '%s' "$out" | tail -1)"
  printf '%s\n' "$out" | grep -E '^  (SKIP|FAIL)' | sed 's/^/    /'
  echo
}

# 1 + 2 — the two branches that became FAILURES: an out-of-date tree.
echo "### 1/2. version_test.sh and guard_lint_test.sh: an out-of-date tree is RED, not a skip"
echo "before (built tree):"
run "version_test.sh, tree built"    version_test.sh
run "guard_lint_test.sh, tree built" guard_lint_test.sh
echo "mutation: touch native/gate.cpp — the tree is now out of date"
touch native/gate.cpp
run "version_test.sh, tree stale"    version_test.sh
run "guard_lint_test.sh, tree stale" guard_lint_test.sh
echo "revert: make all"
make all >/dev/null 2>&1
run "version_test.sh, restored"      version_test.sh

# 3 — blind_switch: the root branch, forced with a shim that says id -u == 0.
echo "### 3. blind_switch_test.sh: the root branch announces instead of vanishing"
d="$SHIM/rootish"; mkdir -p "$d"
printf '#!/bin/sh\nif [ "$1" = -u ]; then echo 0; else exec /usr/bin/id "$@"; fi\n' > "$d/id"
chmod +x "$d/id"
run "blind_switch, id -u lies 0" blind_switch_test.sh "PATH=$d:$PATH"

# 4 — discovery_scope: pytest removed.
echo "### 4. discovery_scope_test.sh: no pytest"
run "discovery_scope, python3 hidden" discovery_scope_test.sh "PATH=$(hide python3 pytest)"

# 5 — redbase_scope: node removed. This is the one that used to make the WHOLE
#     suite disappear with exit 0 and no summary line at all.
echo "### 5. redbase_scope_test.sh: no node — the whole suite, announced with its number"
run "redbase_scope, node hidden" redbase_scope_test.sh "PATH=$(hide node)"

# 6 — unknown_wrapper: caffeinate removed.
echo "### 6. unknown_wrapper_test.sh: no caffeinate"
run "unknown_wrapper, caffeinate hidden" unknown_wrapper_test.sh "PATH=$(hide caffeinate)"

# 7 — usage_order: no live transcript. HOME is where it looks for one.
echo "### 7. usage_order_test.sh: no real transcript on this machine"
h="$SHIM/emptyhome"; mkdir -p "$h"
run "usage_order, empty HOME" usage_order_test.sh "HOME=$h"

# 8 — wrapper_exec: a wrapper binary that is not on this machine. Its skip is
#     driven by `command -v`, so hiding any listed wrapper fires it.
echo "### 8. wrapper_exec_test.sh: a wrapper binary missing"
run "wrapper_exec, caffeinate hidden" wrapper_exec_test.sh "PATH=$(hide caffeinate)"   # only caffeinate: hiding env/arch too broke an
            # unrelated sandbox-exec arm, which would be my artefact, not the branch

# 9 — sandbox and script_wrapper: NOT FORCED HERE, and said so rather than
#     faked. sandbox's branch needs a machine with no kernel sandbox backend
#     (this is macOS, Seatbelt is always present); script_wrapper's needs a
#     machine with no usable pty. Neither can be produced from outside without
#     editing the suite, which would prove the edit and not the branch. The
#     static half of the repair — the counter and the summary — is held by
#     native/silent_skip_test.sh for both files.
echo "### 9. sandbox_test.sh, script_wrapper_test.sh: BRANCH NOT FORCED — I could not"
echo "    reproduce 'no kernel backend' or 'no usable pty' on this machine from"
echo "    outside the suite. Measured here only statically. NOT VERIFIED."
echo
echo "== done =="
