#!/bin/bash
# path_answer_test.sh — "is this path outside the project tree" gets ONE answer.
#
# The gate refuses a Bash command through two layers. The compiled-in delete law
# (baseline.h) resolves its target: it follows `..`, follows a symlink, computes
# where a glob lands, and knows the machine's temp area is scratch and not
# somebody's data. The project's own deny rules (guard.json -> rules.h) are
# regexes, and a regex reads the SPELLING. So the same question got two answers:
#
#     rm -rf /tmp/proj-build && cmake -B /tmp/proj-build ...
#     baseline.h  -> /private/tmp/proj-build, disposable, allow
#     guard.json  -> the text starts with "/", allow-list says "/Users/u/work",
#                    no match, REFUSE
#
# Nine of the twenty refusals in native/precision_fixture.jsonl are that one
# disagreement, and every one of them cut an agent cleaning up its own scratch.
# The rule was not wrong about danger; it was never given the path. This suite
# holds the fixed shape from both sides:
#
#   MUST NOT BLOCK  a delete whose targets all land in the machine's temp area,
#                   under BOTH layers, however the path is spelled: through a
#                   symlink, through $TMPDIR, through a glob, through `..`.
#   MUST BLOCK      a delete that lands anywhere else, under BOTH layers, even
#                   when the spelling says temp: a symlink out of /tmp, a glob
#                   that climbs out with `..`, the shared temp root itself, and
#                   $HOME — including when TMPDIR is set to $HOME or / to try to
#                   make the whole machine look disposable.
#
# Every must-not-block case has a must-block twin one character away, because a
# suite that only proves refusals got rarer is the suite you write when you are
# about to delete the product.
#
# NOTHING HERE IS EXECUTED. Each command is handed to rabadon-gate on stdin as a
# PreToolUse event and only its exit code is read: the gate is a judge, it never
# runs what it judges. Belt and braces anyway, because the list below contains
# real recursive deletes of a home directory:
#   - the whole lab is one mktemp dir, and HOME is redirected inside it
#   - the lab repo has NO remote and one commit
#   - `rm`, `git` and `rmdir` are shadowed on PATH by stand-ins that write a
#     line to a log and exit 0, so a gate that failed to block still deletes
#     nothing
#   - canary files sit in every directory the list names, and are checked at the
#     end together with the "nothing ran" log
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
[ -x "$GATE" ] || { echo "FAIL: $GATE not built (run make)"; exit 1; }

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# ---- the lab: everything this suite can reach is under one mktemp root -------
LAB="$(mktemp -d "${TMPDIR:-/tmp}/rbpath.XXXXXX")"
cleanup() { /bin/rm -rf "$LAB"; }
trap cleanup EXIT

export HOME="$LAB/home"
mkdir -p "$HOME/Documents" "$HOME/work/archive/proj5"
echo "do not lose me" > "$HOME/Documents/keep.txt"
echo "do not lose me" > "$HOME/work/archive/proj5/keep.txt"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
mkdir -p "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"          # enforce

# stand-ins for every binary in the list below. If judging ever turned into
# running, this is what it would land on.
RANLOG="$LAB/ran.log"
: > "$RANLOG"
BIN="$LAB/bin"; mkdir -p "$BIN"
for prog in rm rmdir git shred unlink; do
  cat > "$BIN/$prog" <<SH
#!/bin/sh
echo "$prog \$*" >> "$RANLOG"
exit 0
SH
  chmod +x "$BIN/$prog"
done

# the project the guard belongs to: a repo with one commit and no remote
PROJ="$LAB/proj"
mkdir -p "$PROJ/.rabadon" "$PROJ/src"
echo "do not lose me" > "$PROJ/src/keep.txt"
git init -q "$PROJ"
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first

# The rule shape that produced the nine refusals, copied from the ledger: a
# hand-written regex that excludes the project's own absolute path and calls
# everything else outside. It is NOT rewritten by this suite and NOT deleted by
# the fix — it is the rule a real project wrote, and it has to keep working.
cat > "$PROJ/.rabadon/guard.json" <<'JSON'
{
  "project": "proj1",
  "bash": [
    { "id": "no-rm-rf-outside-project", "deny": "rm\\s+(-\\w*[rf]\\w*\\s+)+(/(?!Users/u/work/proj1)\\S*|~(?!/work/proj1)\\S*|\\$HOME\\S*)", "why": "project rule" }
  ],
  "protectedPaths": [], "disabled": []
}
JSON

# the same commands with no guard.json at all: only the compiled-in laws
BARE="$LAB/bare"
mkdir -p "$BARE"
git init -q "$BARE"

# scratch the temp-area cases name, plus the two symlinks that decide whether
# the answer comes from the spelling or the destination
SCRATCH="$LAB/scratch"
mkdir -p "$SCRATCH/build/out" "$SCRATCH/dl"
echo scratch > "$SCRATCH/build/out/f.txt"
ln -s "$SCRATCH/build" "$SCRATCH/link-in"        # a symlink that stays in temp
ln -s "$HOME/Documents" "$SCRATCH/link-out"      # a symlink that leaves it
REALTMP=$(cd /tmp && pwd -P)                     # /private/tmp on macOS

json() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }

# run <cwd> <command> [VAR=VAL...]
run() {
  local cwd="$1" cmd="$2"; shift 2
  printf '{"hook_event_name":"PreToolUse","session_id":"s-path","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$cwd" "$(json "$cmd")" \
  | env PATH="$BIN:/usr/bin:/bin" HOME="$HOME" RABADON_DIR="$RABADON_DIR" \
        RABADON_NOTIFY=0 "$@" "$GATE" >/dev/null 2>&1
  echo $?
}

# the rule id a refusal carries, so a case cannot pass by being refused for
# some other reason than the one it is about
rule_of() {
  local cwd="$1" cmd="$2"; shift 2
  printf '{"hook_event_name":"PreToolUse","session_id":"s-path","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$cwd" "$(json "$cmd")" \
  | env PATH="$BIN:/usr/bin:/bin" HOME="$HOME" RABADON_DIR="$RABADON_DIR" \
        RABADON_NOTIFY=0 "$@" "$GATE" 2>&1 | sed -n 's/^Rule: //p' | head -1
}

CASES=0
# both <desc> <cmd> <expected-rc> : the SAME command through both layers
both() {
  local desc="$1" cmd="$2" want="$3"
  CASES=$((CASES+1))
  local a b
  a=$(run "$PROJ" "$cmd")
  b=$(run "$BARE" "$cmd")
  if [ "$a" = "$want" ]; then pass "guard.json  $desc"
  else fail "guard.json  $desc (rc=$a want=$want) :: $cmd"; fi
  if [ "$b" = "$want" ]; then pass "compiled-in $desc"
  else fail "compiled-in $desc (rc=$b want=$want) :: $cmd"; fi
}

echo "== one answer: must NOT block (a delete that lands in machine scratch) =="
both "its own scratch files, several at once"  "rm -rf $REALTMP/proj1-out /tmp/dump.csv /tmp/build.log" 0
both "a scratch build dir before rebuilding"   "rm -rf /tmp/proj1-build && cmake -S $PROJ/engine -B /tmp/proj1-build" 0
both "one scratch file, rm -f"                 "rm -f /tmp/case-eu38.dat" 0
both "a scratch dir the next command remakes"  "rm -rf /tmp/fp && mkdir -p /tmp/fp/dxf" 0
both "a pid file after killing the process"    "rm -f /tmp/proj1-serve.pid" 0
both "one scratch html file"                   "rm -f /tmp/live-probe.html" 0
both "a glob one level under the temp root"    "rm -f $SCRATCH/dl/*" 0
both "an anchored glob at the temp root"       "rm -f /tmp/shot*.png" 0
both "a scratch output dir, rewritten next"    "rm -rf /tmp/proj1-fix/after2" 0
both "the temp dir named through \$TMPDIR"     "rm -rf \$TMPDIR/proj1-scratch" 0
both "a symlink that points back into scratch" "rm -rf $SCRATCH/link-in" 0
both "scratch reached by climbing back down"   "rm -rf /tmp/a/../proj1-out" 0
both "the mktemp dir this suite is running in" "rm -rf $SCRATCH/build/out" 0

echo
echo "== the twin: must block (the same shapes, landing somewhere else) =="
both "a home directory named through \$HOME"   "rm -rf \$HOME/Documents" 2
both "a glob that climbs out of the temp root" "rm -rf /tmp/*/../../Users/u/proj1" 2
both "a system library dir"                    "rm -rf /usr/local/lib" 2
both "the shared temp root itself"             "rm -rf /tmp" 2
both "the shared temp root, as it resolves"    "rm -rf $REALTMP" 2
both "every entry of the shared temp root"     "rm -rf /tmp/*" 2
both "a symlink in scratch pointing at \$HOME" "rm -rf $SCRATCH/link-out" 2
both "another project tree under the home dir" "rm -rf ~/work/archive/proj5" 2
both "climbing out of the temp dir with .."    "rm -rf /tmp/../etc" 2

echo
echo "== TMPDIR is the environment, and the environment is what an agent sets =="
for HOSTILE in "TMPDIR=$HOME" "TMPDIR=/" "TMPDIR=/Users"; do
  CASES=$((CASES+1))
  for W in "$PROJ" "$BARE"; do
    L=$([ "$W" = "$PROJ" ] && echo "guard.json " || echo "compiled-in")
    RC=$(run "$W" "rm -rf \$HOME/Documents" "$HOSTILE")
    [ "$RC" = "2" ] && pass "$L \$HOME/Documents still refused with $HOSTILE" \
                    || fail "$L $HOSTILE opened the home dir (rc=$RC)"
    RC=$(run "$W" "rm -rf /tmp/*/../../Users/u/proj1" "$HOSTILE")
    [ "$RC" = "2" ] && pass "$L the climb-out still refused with $HOSTILE" \
                    || fail "$L $HOSTILE opened the climb-out (rc=$RC)"
    RC=$(run "$W" "rm -rf /usr/local/lib" "$HOSTILE")
    [ "$RC" = "2" ] && pass "$L /usr/local/lib still refused with $HOSTILE" \
                    || fail "$L $HOSTILE opened /usr/local/lib (rc=$RC)"
  done
done

echo
echo "== the project's own rule is still the project's own rule =="
# The fix gives the rule a resolved path. It must not give it a different
# ANCHOR: a delete inside this project's tree is still outside the tree the
# rule named, and the rule still refuses it and still says so by id.
R=$(rule_of "$PROJ" "rm -rf $PROJ/src")
case "$R" in
  no-rm-rf-outside-project*) pass "the hand-written rule still fires, by its own id" ;;
  *) fail "the project's rule stopped firing on its own anchor (rule='$R')" ;;
esac
# and an unknown variable is still waived, not guessed at
RC=$(run "$BARE" "rm -rf \$TARGET/build")
[ "$RC" = "0" ] && pass "an unknown \$VAR is still waived, not guessed" \
                || fail "the resolver guessed where \$TARGET lands (rc=$RC)"

echo
echo "== judging is not running =="
[ ! -s "$RANLOG" ] && pass "no deleter was ever executed (ran.log empty)" \
                   || fail "something ran: $(head -3 "$RANLOG")"
for C in "$HOME/Documents/keep.txt" "$HOME/work/archive/proj5/keep.txt" \
         "$PROJ/src/keep.txt" "$SCRATCH/build/out/f.txt"; do
  [ -f "$C" ] && [ "$(cat "$C")" = "do not lose me" ] || [ "$(cat "$C")" = "scratch" ] \
    && pass "canary intact: ${C#$LAB/}" || fail "canary lost: $C"
done
[ -d /tmp ] && [ -d /etc ] && [ -d /usr/local ] \
  && pass "/tmp, /etc and /usr/local are still on the machine" \
  || fail "the suite ran what it judged"

echo
echo "cases: $CASES   assertions: $((PASS+FAIL))   pass: $PASS   fail: $FAIL"
[ "$FAIL" = "0" ] && { echo "PASS"; exit 0; }
echo "FAIL: the two layers do not give one answer to 'where does this path land'."
exit 1
