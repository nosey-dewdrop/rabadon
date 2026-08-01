#!/bin/bash
# lease_force_test.sh — a lease is not an excuse for an explicit force.
#
# The push law read the option walk as two independent booleans. `--force` and
# `-f` set `force`; any token beginning `--force-with-lease` (or
# `--force-if-includes`) set `lease`; and the refusal was gated on
#
#     if (!noForce && force && (!lease || mirror))
#
# so writing a lease ANYWHERE on the line switched the law off, whatever else
# the line said. Both of these exited 0 on `main` with no guard.json — the
# fresh-install path, the path the compiled floor exists for:
#
#     git push --force-with-lease --force origin main      ALLOW
#     git push --force-if-includes --force origin main     ALLOW
#
# while `git push --force origin main`, the same push minus a word that is
# supposed to make it SAFER, exited 2.
#
# THE HANDED-OVER DIAGNOSIS WAS THAT git RESOLVES THESE LAST-ONE-WINS, so the
# hole was the ORDER of the two tokens and the fix was to find the last
# force-ish word on the line. That is measured below, and it is FALSE. Against
# git 2.39.5, real pushes, into a bare repo this file creates, with a lease that
# is genuinely STALE (a second clone pushed a commit the first has never seen):
#
#     --force-with-lease                 ! [rejected] main -> main (stale info)
#     --force-with-lease --force         + ...  main -> main (forced update)
#     --force --force-with-lease         + ...  main -> main (forced update)
#     -f --force-with-lease              + ...  main -> main (forced update)
#     --force-if-includes                ! [rejected] main -> main (fetch first)
#     --force-if-includes --force        + ...  main -> main (forced update)
#     --force-with-lease origin +main    + ...  main -> main (forced update)
#
# The remote lost the other clone's commit in every line marked `forced update`,
# and this file reads that back by sha rather than trusting the porcelain.
#
# So `--force` beats a lease IN EITHER ORDER — it is not a last-one-wins option
# pair at all. `--force` sets a transport flag while `--force-with-lease`
# populates a compare-and-swap entry, and a forced ref update is not asked to
# clear the CAS. A fix built on the POSITION of the last force-ish token would
# have refused `--force-with-lease --force` and gone on allowing
# `--force --force-with-lease`, which is the line measured above destroying a
# commit. The law does not need the order. It needs to stop treating the lease
# as an excuse at all: an explicit unconditional force (`--force`, `-f`,
# `--mirror`, or a leading `+` on the refspec) is a force, and the lease written
# beside it changes nothing.
#
# TWO FACTS KEEP THAT FROM OVER-BLOCKING, and both are measured above.
# `--force-with-lease` ALONE is refused by git when the remote has moved, which
# is exactly what makes it the spelling the gate's own advice recommends, so it
# must keep going. And `--force-if-includes` alone is refused too — it is inert
# without a lease, not a force — so it must keep going as well. Only the
# COMBINATION is refused, and every must-block case below has its must-not-block
# twin: the same spellings on a branch that is nobody else's, an ordinary push,
# a lease alone, and the same words as prose.
#
# WHAT RUNS AND WHAT DOES NOT. Section 1 executes, on purpose, so the premise is
# measured and not asserted, and it is the only section that does. It runs
# inside one mktemp lab: $HOME is redirected under that lab with a canary file
# in it, git's global and system config are pointed away from the machine's, the
# shell half runs with FAKE `git` and `rm` first on PATH that only record their
# argv, and the git half pushes to a BARE REPO CREATED BY mktemp four lines
# earlier. Nothing in it can reach a network remote or a real repo.
#
# Every other section executes NOTHING: each command is handed to rabadon-gate
# on stdin as a PreToolUse event and only its exit code is read. The projects it
# judges hold a `.git/HEAD` file and no remote, so a total failure of the gate
# still has nothing to push to. The canaries at the bottom are the proof.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "lease_force_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

LAB=$(mktemp -d "${TMPDIR:-/tmp}/rabadon-lease-force-test.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"; mkdir -p "$HOME/.rabadon/spool" "$HOME/Documents"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
touch "$RABADON_DIR/enabled"                  # enforce
CANARY="$HOME/Documents/keep.txt"
echo "do not lose me" > "$CANARY"

# TWO projects, because a hole reported through the compiled floor has to be
# closed there and not by a project's rules. `bare` has no guard.json at all:
# the three compiled laws alone. `ruled` carries the four rules rabadon writes
# for a bare home, whose force regex happens to match the substring `--force`
# inside `--force-with-lease` — so a pass there proves nothing on its own, and
# it is the `bare` column that carries the argument.
BARE="$LAB/bare"; mkdir -p "$BARE/.git"
RULED="$LAB/ruled"; mkdir -p "$RULED/.git" "$RULED/.rabadon"
cat > "$RULED/.rabadon/guard.json" <<'JSON'
{
  "project": "ruled",
  "bash": [
    { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b", "why": "force-pushing a shared branch destroys history" },
    { "id": "no-rm-rf-outside", "deny": "rm\\s+-\\w*[rf]\\w*\\s+(/(?!tmp)|~/(?!\\.)|\\$HOME)", "why": "recursive delete outside a project is unrecoverable" },
    { "id": "no-hard-reset-main", "deny": "git\\s+reset\\s+--hard\\s+(origin/)?(main|master)\\b", "why": "rewrite shared state via commits, not resets" },
    { "id": "no-hook-bypass", "deny": "git\\s+(commit|push)[^|;&]*--no-verify", "why": "bypassing hooks bypasses every gate at once" }
  ],
  "protectedPaths": [], "disabled": []
}
JSON

on_branch() {                                  # on_branch <name>
  printf 'ref: refs/heads/%s\n' "$1" > "$BARE/.git/HEAD"
  printf 'ref: refs/heads/%s\n' "$1" > "$RULED/.git/HEAD"
}
on_branch main

run() { # run <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"s-leaseforce","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> what the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-leaseforce","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}

# ---------------------------------------------------------------------------
# 1. the premise, measured: the shell runs it, and git really overrides the
#    lease with --force in BOTH orders
# ---------------------------------------------------------------------------
echo "lease and force: what the shell runs (fake git, fake rm)"
mkdir -p "$LAB/fakebin" "$LAB/sandbox"
echo "do not lose me either" > "$LAB/sandbox/keep.txt"
for name in git rm; do
  cat > "$LAB/fakebin/$name" <<FAKE
#!/bin/sh
printf '$name' >> "$LAB/argv.log"
for a in "\$@"; do printf ' [%s]' "\$a" >> "$LAB/argv.log"; done
printf '\n' >> "$LAB/argv.log"
exit 0
FAKE
  chmod +x "$LAB/fakebin/$name"
done

ran() { # ran <label> <command> <expected argv line>
  : > "$LAB/argv.log"
  ( cd "$LAB/sandbox" && env PATH="$LAB/fakebin:$PATH" bash -c "$2" ) >/dev/null 2>&1
  if grep -qxF "$3" "$LAB/argv.log" 2>/dev/null; then
    pass "the shell runs it: $1"
  else
    fail "the shell did NOT run it ($1): log=[$(tr '\n' ';' < "$LAB/argv.log")]"
  fi
}
ran "the lease then the force"  'git push --force-with-lease --force origin main' \
    'git [push] [--force-with-lease] [--force] [origin] [main]'
ran "the force then the lease"  'git push --force --force-with-lease origin main' \
    'git [push] [--force] [--force-with-lease] [origin] [main]'
ran "if-includes then force"    'git push --force-if-includes --force origin main' \
    'git [push] [--force-if-includes] [--force] [origin] [main]'
[ -f "$LAB/sandbox/keep.txt" ] && pass "the fakes ran instead of the real git and rm: nothing was pushed or deleted" \
  || fail "a real rm ran in the lab"

# ---- real git, real pushes, entirely inside the lab ------------------------
# The remote is a bare repo mktemp'd into $LAB. $HOME is already redirected into
# $LAB and git's global/system config are pointed away from this machine's, so
# no credential helper, no insteadOf rewrite and no url alias from the operator's
# gitconfig can be read here. There is no network remote to reach.
echo "lease and force: what git does with a STALE lease (real pushes, lab-local bare remote)"
if ! command -v git >/dev/null 2>&1; then
  fail "no git on PATH: the premise of this suite cannot be measured"
else
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null

# build_lab -> prints a lab dir whose worktree `a` holds a STALE lease:
# clone `b` has pushed a commit to the shared bare remote that `a` has never
# fetched, and `a` has since committed something of its own. That is the exact
# state --force-with-lease exists to protect, so it is the only state in which
# the lease and the force can be told apart.
build_lab() {
  local L; L=$(mktemp -d "$LAB/git.XXXXXX")
  git init -q --bare "$L/remote.git" || return 1
  git init -q "$L/a" || return 1
  git -C "$L/a" config user.email t@t; git -C "$L/a" config user.name t
  git -C "$L/a" symbolic-ref HEAD refs/heads/main
  echo a > "$L/a/a"; git -C "$L/a" add a; git -C "$L/a" commit -qm one
  git -C "$L/a" remote add origin "$L/remote.git"
  git -C "$L/a" push -q -u origin main
  git clone -q "$L/remote.git" "$L/b"
  git -C "$L/b" config user.email t@t; git -C "$L/b" config user.name t
  echo b > "$L/b/b"; git -C "$L/b" add b; git -C "$L/b" commit -qm "two from B"
  git -C "$L/b" push -q origin main
  echo c > "$L/a/c"; git -C "$L/a" add c; git -C "$L/a" commit -qm "divergent from A"
  echo "$L"
}

# git_pushes <label> <expect: LOST|HELD> <push args...>
# runs the push for real and reads the remote's tip back by sha. `LOST` means
# the bare remote no longer points at the commit clone B pushed.
git_pushes() {
  local label="$1" expect="$2"; shift 2
  local L; L=$(build_lab) || { fail "could not build a git lab for: $label"; return; }
  local before after
  before=$(git -C "$L/remote.git" rev-parse main)
  ( cd "$L/a" && eval git push "$@" ) >/dev/null 2>&1
  after=$(git -C "$L/remote.git" rev-parse main)
  local got; if [ "$before" = "$after" ]; then got=HELD; else got=LOST; fi
  if [ "$got" = "$expect" ]; then
    if [ "$expect" = LOST ]; then pass "git: $label — the remote LOST the other clone's commit"
    else pass "git: $label — the lease HELD, the remote is intact"; fi
  else
    fail "git: $label — expected $expect, measured $got"
  fi
  rm -rf "$L"
}

# the two that must keep going: alone, each of these is refused BY GIT.
git_pushes "--force-with-lease alone"          HELD --force-with-lease origin main
git_pushes "--force-if-includes alone"         HELD --force-if-includes origin main
# and the combinations, which are unconditional force pushes whatever the order
git_pushes "--force-with-lease then --force"   LOST --force-with-lease --force origin main
git_pushes "--force then --force-with-lease"   LOST --force --force-with-lease origin main
git_pushes "-f then --force-with-lease"        LOST -f --force-with-lease origin main
git_pushes "--force-if-includes then --force"  LOST --force-if-includes --force origin main
git_pushes "a lease with a + refspec"          LOST --force-with-lease origin +main
fi

# ---------------------------------------------------------------------------
# 2. must BLOCK: a lease beside an explicit force, on a shared branch
# ---------------------------------------------------------------------------
echo "lease and force: refused on a shared branch (no guard.json, compiled floor alone)"
for BR in main master trunk develop; do
  on_branch "$BR"
  while IFS='|' read -r desc cmd; do
    [ -z "$desc" ] && continue
    C=${cmd//BR/$BR}
    RC=$(run "$BARE" "$C")
    [ "$RC" = "2" ] && pass "refused on $BR: $desc" || fail "NOT refused on $BR ($RC): $C"
  done <<'EOF'
the lease written before the force|git push --force-with-lease --force origin BR
the lease written after the force|git push --force --force-with-lease origin BR
the lease before the short force flag|git push --force-with-lease -f origin BR
the lease after the short force flag|git push -f --force-with-lease origin BR
a lease carrying a ref name|git push --force-with-lease=BR --force origin BR
a lease carrying a ref and an expected sha|git push --force-with-lease=BR:deadbeef --force origin BR
if-includes before the force|git push --force-if-includes --force origin BR
if-includes after the force|git push --force --force-if-includes origin BR
both lease spellings and a force|git push --force-with-lease --force-if-includes --force origin BR
a lease with the force refspec|git push --force-with-lease origin +BR
a lease with the force refspec, spelled in full|git push --force-with-lease origin +refs/heads/BR
a lease and a force in a short cluster|git push --force-with-lease -fu origin BR
a lease and a force with no refspec at all|git push --force-with-lease --force origin
a lease and a force naming no remote either|git push --force-with-lease --force
a lease against a mirror|git push --force-with-lease --mirror origin
a lease against the whole refspace|git push --all --force-with-lease --force origin
a lease and a force behind a git global option|git -C . push --force-with-lease --force origin BR
a lease and a force inside a shell string|bash -c 'git push --force-with-lease --force origin BR'
a lease and a force in a brace group|{ git push --force-with-lease --force origin BR; }
a lease and a force in the then branch|if true; then git push --force --force-with-lease origin BR; fi
a lease and a force after an ordinary command|npm test && git push --force-with-lease --force origin BR
EOF
done

# the same lines where the project HAS written rules. Both layers, one hole.
on_branch main
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$RULED" "$cmd")
  [ "$RC" = "2" ] && pass "refused with guard.json too: $desc" || fail "NOT refused with guard.json ($RC): $cmd"
done <<'EOF'
the lease written before the force|git push --force-with-lease --force origin main
the lease written after the force|git push --force --force-with-lease origin main
if-includes before the force|git push --force-if-includes --force origin main
EOF

# the sentence has to tell the operator the thing they got wrong. Someone who
# WROTE a lease and is refused anyway needs to be told the --force is what
# cancelled it, not to "use --force-with-lease" — advice they already followed.
OUT=$(detail "$BARE" "git push --force-with-lease --force origin main")
case "$OUT" in
  *baseline-force-push*) pass "the refusal names the rule id" ;;
  *) fail "the refusal does not name baseline-force-push: $OUT" ;;
esac
case "$OUT" in
  *"cancels the lease"*) pass "the refusal says the force cancels the lease, not 'use --force-with-lease'" ;;
  *) fail "the refusal gives advice the operator already followed: $OUT" ;;
esac

# ---------------------------------------------------------------------------
# 3. must NOT block: the lease alone is the spelling the gate recommends
# ---------------------------------------------------------------------------
echo "lease and force: the work this must not cut"
on_branch main
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$BARE" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<'EOF'
the lease alone, the safe form|git push --force-with-lease origin main
the lease alone with no refspec|git push --force-with-lease origin
the lease alone naming a ref|git push --force-with-lease=main origin main
the lease alone naming a ref and a sha|git push --force-with-lease=main:deadbeef origin main
if-includes alone, inert without a lease|git push --force-if-includes origin main
both lease spellings, no force|git push --force-with-lease --force-if-includes origin main
the lease alongside an upstream flag|git push --force-with-lease -u origin main
the lease in a short cluster with no f|git push --force-with-lease -qu origin main
the lease over every branch, no force|git push --all --force-with-lease origin
if-includes over every branch, no force|git push --all --force-if-includes origin
an ordinary push|git push origin main
an ordinary push with no refspec|git push
an upstream push|git push --set-upstream origin main
a lease as a commit message|git commit -m "git push --force-with-lease --force origin main is what broke it"
a lease echoed as a string|echo "git push --force-with-lease --force origin main"
a lease as a grep pattern|grep -r "force-with-lease --force" ./docs
EOF

# the twin that matters most: the same spelling on a branch that is hers.
# Force-pushing your own branch is how a review gets fixed up, and the lease
# beside it is a person being careful. A law that refuses the word --force
# cuts that.
for BR in feat my-branch damla/wip release-2; do
  on_branch "$BR"
  while IFS='|' read -r desc cmd; do
    [ -z "$desc" ] && continue
    C=${cmd//BR/$BR}
    RC=$(run "$BARE" "$C")
    [ "$RC" = "0" ] && pass "allowed on $BR: $desc" || fail "WRONGLY refused on $BR ($RC): $C"
  done <<'EOF'
the lease and the force on her own branch|git push --force-with-lease --force origin BR
the force and the lease on her own branch|git push --force --force-with-lease origin BR
if-includes and the force on her own branch|git push --force-if-includes --force origin BR
the force refspec on her own branch|git push --force-with-lease origin +BR
a lease and a force with no refspec, on her own branch|git push --force-with-lease --force origin
EOF
done
on_branch main

# ---------------------------------------------------------------------------
# 4. the change is scoped to the push law
# ---------------------------------------------------------------------------
echo "lease and force: the other two laws are untouched"
RC=$(run "$BARE" "git reset --hard HEAD"); [ "$RC" = "0" ] \
  && pass "a hard reset to HEAD still goes" || fail "WRONGLY refused ($RC): git reset --hard HEAD"
RC=$(run "$BARE" "git reset --hard origin/main"); [ "$RC" = "2" ] \
  && pass "a hard reset onto the shared branch is still refused" || fail "NOT refused ($RC)"
RC=$(run "$BARE" "rm -rf ./build"); [ "$RC" = "0" ] \
  && pass "a build dir still goes" || fail "WRONGLY refused ($RC): rm -rf ./build"
RC=$(run "$BARE" "git push origin :main"); [ "$RC" = "2" ] \
  && pass "the branch-delete law is still its own law" || fail "NOT refused ($RC): a shared-branch delete"

# silencing the force law by id still silences it, lease or no lease — an
# operator who rewrites her own trunk asked for that and did not stop asking
# because she also wrote a lease.
QUIET="$LAB/quiet"; mkdir -p "$QUIET/.git" "$QUIET/.rabadon"
printf 'ref: refs/heads/main\n' > "$QUIET/.git/HEAD"
printf '{"project":"quiet","bash":[],"protectedPaths":[],"disabled":["baseline-force-push"]}\n' \
  > "$QUIET/.rabadon/guard.json"
RC=$(run "$QUIET" "git push --force-with-lease --force origin main"); [ "$RC" = "0" ] \
  && pass "disabled[] still silences the force law" || fail "disabled[] ignored ($RC)"
RC=$(run "$QUIET" "git push origin :main"); [ "$RC" = "2" ] \
  && pass "and silencing the force law did not silence the delete law" || fail "NOT refused ($RC)"

# ---------------------------------------------------------------------------
# 5. judging is not running
# ---------------------------------------------------------------------------
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = "do not lose me" ] \
  && pass "the canary in the home dir survived judging every command above" || fail "the canary is gone"
[ -f "$LAB/sandbox/keep.txt" ] && pass "the canary in the lab survived" || fail "the lab canary is gone"
[ -z "$(git -C "$BARE" remote 2>/dev/null)" ] \
  && pass "the judged project still has no remote: nothing left this machine" || fail "a remote appeared"
[ -d /tmp ] && [ -d /etc ] && [ -d "$HOME" ] \
  && pass "/tmp, /etc and the home dir are still on the machine" || fail "the test ran what it judged"

echo "lease and force: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
