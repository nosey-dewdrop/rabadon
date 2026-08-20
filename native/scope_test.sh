#!/usr/bin/env bash
# scope_test.sh — a red in one directory must not refuse work in its neighbour.
#
# WHAT THIS PROVES
#   A net verdict used to be a portable object. `<dir>/.rabadon/net.json` said
#   green or red and said nothing about WHICH tree it was about, so the gate
#   read whatever net.json happened to sit next to the cwd and refused on it.
#   Two ways that goes wrong, both measured before the fix:
#
#     - copy A's net.json into sibling B  -> B is refused on a suite that
#       never ran in B
#     - rename the directory the verdict was written in -> the stale verdict
#       still fires in a tree that no longer exists under that name
#
#   The verdict now carries "root", and red-base fires only when that root is
#   the project the session is standing in. A verdict with NO root is legacy
#   and still fires: silently disarming every installed machine on upgrade is
#   the worse failure.
#
# WHAT IT DELIBERATELY DOES NOT CLAIM
#   Inside one worktree the verdict still travels — a red at the repo root
#   refuses in a subdirectory of the same repo. That is not the leak; that is
#   the feature. A directory that is NOT a git worktree has no subtree, so its
#   verdict governs itself and nothing below it.
#
# HERMETIC: rabadon is default-off, so the gate is dormant unless something
# opts in. This gives the run its own HOME and RABADON_DIR — a test that reads
# the developer's real switch is not a test.
set -u
export RABADON_NOTIFY=0
LAB="$(mktemp -d)"
export HOME="$LAB/home"; mkdir -p "$HOME/.rabadon"
export RABADON_DIR="$HOME/.rabadon"; printf 'enforce\n' > "$RABADON_DIR/mode"
BIN="$(cd "$(dirname "$0")" && pwd)/rabadon-gate"
[ -x "$BIN" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   - $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
cleanup(){ rm -rf "$LAB"; }
trap cleanup EXIT

echo "scope: a verdict is about a tree, and says which"

# a real git worktree with a red net verdict of its own
mkrepo(){ # $1=path
  mkdir -p "$1" && ( cd "$1" && git init -q . && git config user.email t@t && git config user.name t \
    && echo x > f.txt && git add -A && git commit -qm init )
  mkdir -p "$1/.rabadon"
}
verdict(){ # $1=dir  $2=verdict  $3=root  (empty root = legacy object)
  if [ -z "$3" ]; then
    printf '{"ts":%s,"level":3,"kind":"t","cmd":"true","verdict":"%s","exit":1,"dur_ms":1,"tail":"boom"}\n' \
      "$(python3 -c 'import time;print(int(time.time()*1000))')" "$2" > "$1/.rabadon/net.json"
  else
    printf '{"ts":%s,"root":"%s","level":3,"kind":"t","cmd":"true","verdict":"%s","exit":1,"dur_ms":1,"tail":"boom"}\n' \
      "$(python3 -c 'import time;print(int(time.time()*1000))')" "$3" "$2" > "$1/.rabadon/net.json"
  fi
}
edit_ev(){ printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"sc1","tool_use_id":"s%s","tool_name":"Bash","tool_input":{"command":"echo hi"}}' "$1" "$RANDOM"; }
run(){ edit_ev "$1" | "$BIN" >/dev/null 2>&1; echo $?; }

A="$LAB/a"; B="$LAB/b"
mkrepo "$A"; mkrepo "$B"
RA="$(cd "$A" && pwd -P)"; RB="$(cd "$B" && pwd -P)"

# --- 1: a red verdict about THIS tree still refuses -------------------------
verdict "$A" red "$RA"
[ "$(run "$A")" = "2" ] && ok "a red about this tree still refuses (the feature is not amputated)" \
                        || bad "a red about this tree should refuse"

# --- 2: the same red, copied into the neighbour, must NOT refuse ------------
cp "$A/.rabadon/net.json" "$B/.rabadon/net.json"
rc="$(run "$B")"
[ "$rc" = "0" ] && ok "A's red does not refuse in sibling B (the leak, closed)" \
                || bad "A's red still refuses in B (exit $rc) — a verdict leaked across projects"

# --- 3: B's own red still refuses B ----------------------------------------
verdict "$B" red "$RB"
[ "$(run "$B")" = "2" ] && ok "B's own red refuses B" || bad "B's own red should refuse B"

# --- 4: a stale verdict from a renamed directory must not refuse ------------
C="$LAB/c"; mkrepo "$C"
verdict "$C" red "$(cd "$C" && pwd -P)"
mv "$C" "$LAB/c2"
rc="$(run "$LAB/c2")"
[ "$rc" = "0" ] && ok "a verdict written under the old name does not refuse under the new one" \
                || bad "stale verdict from the pre-rename path still fires (exit $rc)"

# --- 5: legacy verdict with no root still fires (no silent disarm) ----------
D="$LAB/d"; mkrepo "$D"
verdict "$D" red ""
[ "$(run "$D")" = "2" ] && ok "a legacy verdict with no root still refuses — upgrade does not disarm" \
                        || bad "legacy rootless verdict stopped refusing: every installed machine would go quiet"

# --- 6: inside one worktree the verdict still travels ----------------------
# The gate reads net.json from the cwd it was handed; it does not walk up to
# find one. What "travels" is the ROOT: a verdict sitting in a subdirectory
# whose root is the repo root matches and fires, because it is about this tree.
# Scoping the verdict must not amputate that — a project is one project.
mkdir -p "$D/sub/deeper/.rabadon"
verdict "$D/sub/deeper" red "$(cd "$D" && pwd -P)"
[ "$(run "$D/sub/deeper")" = "2" ] && ok "in a subdir, a verdict rooted at the repo root still refuses" \
                                   || bad "a verdict about this worktree stopped firing inside it — scope fix became amputation"

# --- 7: a NON-repo directory's verdict governs itself, not a subtree --------
# project_root() falls back to the directory itself here, and a directory that
# is not a worktree has no subtree to govern.
E="$LAB/e"; mkdir -p "$E/.rabadon" "$E/child"
verdict "$E" red "$(cd "$E" && pwd -P)"
[ "$(run "$E")" = "2" ] && ok "a fallback root refuses in its own directory" \
                        || bad "a fallback root should refuse in its own directory"
rc="$(run "$E/child")"
[ "$rc" = "0" ] && ok "a fallback root does not refuse in a child directory" \
                || bad "a non-repo directory's verdict reached into a child (exit $rc)"

# --- 8: green stays green ---------------------------------------------------
F="$LAB/f"; mkrepo "$F"
verdict "$F" green "$(cd "$F" && pwd -P)"
[ "$(run "$F")" = "0" ] && ok "a green verdict refuses nothing" || bad "green should not refuse"

echo "  pass $PASS   fail $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
