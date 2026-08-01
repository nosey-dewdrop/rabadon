#!/bin/bash
# push_delete_test.sh — a push that DELETES a shared branch is not a force-push,
# and it is worse.
#
# The push law read one refspec shape: `if (!s.empty() && s[0] == '+') force =
# true;`. That is the force refspec. A refspec whose SOURCE side is empty does
# not rewrite the destination ref, it removes it, and it starts with ':':
#
#     git push origin :main            the ref is gone from the remote
#     git push origin :refs/heads/main the same, spelled out
#     git push --delete origin main    git's own words for the same operation
#     git push -d origin main          the short switch for it
#
# shared_branch() was already right about all four — it splits at the colon and
# answers on the DESTINATION side, so it said "main" for `:main` the whole time.
# It was never asked. `force` stayed false, the `if (force && !lease)` walk
# returned before the branch name was consulted, and every spelling above exited
# 0 on the fresh-install path AND under a project guard.json, because the deny
# regex a project writes hunts for `--force|-f` and there is no `-f` in a
# deletion either. Both layers, one hole.
#
# A force-push replaces history other people have; a delete removes the branch
# and every unmerged commit reachable only from it, and there is no reflog on
# the remote to walk back through. So it is refused under its OWN id,
# `baseline-branch-delete`, and not folded into the force-push law: a repo that
# silenced `baseline-force-push` because one person force-pushes their own trunk
# did not thereby agree to have that trunk deleted. Section 6 holds that apart.
#
# THE CLUSTERED SPELLINGS ARE HERE TOO, AND THEY ARE NOT THIS LAW'S DOING.
# Short options bundle: `-fd` is --force --delete and `-fq` is --force --quiet,
# and git accepts both (section 1 measures that against a real git). None of
# that is read in baseline.h. cmdtext.h splits a cluster into the options it
# stands for before any law sees the words, so `-d` and `-f` arrive as their own
# tokens and the law compares tokens, once. The cases below are the JOINT proof
# that the two halves meet: the parser splits and the law then judges. The split
# itself is held from its own side by native/short_cluster_test.sh.
#
# SECTION 1 EXECUTES A SHELL, ON PURPOSE, so the premise is measured and not
# asserted: a FAKE `git` and a FAKE `rm` first on PATH record their argv and do
# nothing else, and a REAL git is asked whether these spellings even parse. It
# all happens inside one mktemp lab whose repo HAS NO REMOTE, with $HOME pointed
# inside that lab and a canary in it. If the fakes were somehow not found, the
# real git has nowhere to push to and the real rm can only see paths this file
# made seconds earlier.
#
# EVERY OTHER SECTION EXECUTES NOTHING: each command is handed to rabadon-gate
# on stdin as a PreToolUse event and only its exit code is read. The canaries at
# the bottom are the proof.
#
# The must-ALLOW list is longer than the must-BLOCK list on purpose. Deleting a
# remote branch is ORDINARY WORK — it is what you do after a PR merges — and a
# law that cannot tell `:main` from `:feature/x` would refuse the most common
# cleanup an agent performs. Every blocked spelling below has a twin that is the
# same spelling aimed at a branch nobody shares.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "push_delete_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

LAB=$(mktemp -d /tmp/rabadon-pushdel-test.XXXXXX)
trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"; mkdir -p "$HOME/.rabadon/spool" "$HOME/Documents"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
touch "$RABADON_DIR/enabled"                  # enforce
CANARY="$HOME/Documents/keep.txt"
echo "do not lose me" > "$CANARY"

# no guard.json: the compiled floor, judged alone — the fresh-install path
PROJ="$LAB/proj"; mkdir -p "$PROJ/.git" "$PROJ/build"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"

# and a project that DID write rules, with the four a bare `rabadon init`
# authors. None of them mentions a deletion, which is the point: this is the
# second layer the escape walked through, not a different one.
GPROJ="$LAB/guarded"; mkdir -p "$GPROJ/.git" "$GPROJ/.rabadon"
printf 'ref: refs/heads/main\n' > "$GPROJ/.git/HEAD"
cat > "$GPROJ/.rabadon/guard.json" <<'JSON'
{
  "project": "guarded",
  "bash": [
    { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b", "why": "force-pushing a shared branch destroys history" },
    { "id": "no-rm-rf-outside", "deny": "rm\\s+-\\w*[rf]\\w*\\s+(/(?!tmp)|~/(?!\\.)|\\$HOME)", "why": "recursive delete outside a project is unrecoverable" },
    { "id": "no-hard-reset-main", "deny": "git\\s+reset\\s+--hard\\s+(origin/)?(main|master)\\b", "why": "rewrite shared state via commits, not resets" },
    { "id": "no-hook-bypass", "deny": "git\\s+(commit|push)[^|;&]*--no-verify", "why": "bypassing hooks bypasses every gate at once" }
  ],
  "protectedPaths": [], "disabled": []
}
JSON

run() { # run <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"s-pushdel","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> what the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-pushdel","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}

# ---------------------------------------------------------------------------
# 1. the premise, measured: these are spellings a shell hands to git and git
#    accepts, not shapes invented to make a parser look bad
# ---------------------------------------------------------------------------
echo "push-delete: what the shell runs and what git accepts (no remote, fake git, nothing pushed)"
mkdir -p "$LAB/fakebin"
SBOX="$LAB/sandbox"
git init -q "$SBOX"
git -C "$SBOX" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
SBOX_HEAD=$(git -C "$SBOX" rev-parse HEAD)
echo "do not lose me either" > "$SBOX/keep.txt"

# a REAL git, in a repo with NO remote: exit 129 is "unknown switch", i.e. git
# never heard of this spelling. Anything else means the options parsed and git
# got as far as looking for a remote called `norem`, which does not exist.
parses() { # parses <label> <argv...>
  out=$(cd "$SBOX" && git push "$@" 2>&1); rc=$?
  if [ "$rc" != "129" ] && ! printf '%s' "$out" | grep -qi 'unknown \(switch\|option\)'; then
    pass "real git accepts the spelling: git push $*"
  else
    fail "git rejected the spelling (rc=$rc): git push $* -> $(printf '%s' "$out" | head -1)"
  fi
}
parses norem :main
parses --delete norem main
parses -d norem main
parses -fq norem main
[ "$(git -C "$SBOX" rev-parse HEAD)" = "$SBOX_HEAD" ] || fail "the probe moved the lab repo's HEAD"
[ -d "$SBOX/.git/refs/remotes" ] && [ -n "$(ls -A "$SBOX/.git/refs/remotes" 2>/dev/null)" ] \
  && fail "the probe created a remote ref" || pass "the probe repo still has no remote: nothing left the machine"

for name in git rm; do
  cat > "$LAB/fakebin/$name" <<FAKE
#!/bin/sh
# records what a real $name would have been given, and does nothing else
printf '$name' >> "$LAB/argv.log"
for a in "\$@"; do printf ' [%s]' "\$a" >> "$LAB/argv.log"; done
printf '\n' >> "$LAB/argv.log"
exit 0
FAKE
  chmod +x "$LAB/fakebin/$name"
done

ran() { # ran <label> <command> <expected argv line>
  : > "$LAB/argv.log"
  ( cd "$SBOX" && env PATH="$LAB/fakebin:$PATH" bash -c "$2" ) >/dev/null 2>&1
  if grep -qxF "$3" "$LAB/argv.log" 2>/dev/null; then
    pass "the shell runs it: $1"
  else
    fail "the shell did NOT run it ($1): log=[$(tr '\n' ';' < "$LAB/argv.log")]"
  fi
}
ran "the empty-source refspec" 'git push origin :main'         'git [push] [origin] [:main]'
ran "the delete switch"        'git push --delete origin main' 'git [push] [--delete] [origin] [main]'
ran "the short delete switch"  'git push -d origin main'       'git [push] [-d] [origin] [main]'
ran "a bundled force"          'git push -fq origin main'      'git [push] [-fq] [origin] [main]'
[ -f "$SBOX/keep.txt" ] && pass "the fakes ran instead of the real git and rm: nothing was pushed or deleted" \
  || fail "a real rm ran in the lab"

# ---------------------------------------------------------------------------
# 2. must BLOCK: a shared branch removed from the remote, in every spelling
# ---------------------------------------------------------------------------
echo "push-delete: refused (no guard.json — the compiled floor alone)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused: $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
the empty-source refspec|git push origin :main
the same, on master|git push origin :master
the destination spelled in full|git push origin :refs/heads/main
the delete switch|git push --delete origin main
the delete switch after the remote|git push origin --delete develop
the short delete switch|git push -d origin trunk
delete and force together|git push -fd origin main
a global option in front|git -C /tmp/elsewhere push origin :main
wrapped in a shell string|sh -lc 'git push origin :main'
behind a reserved word|{ git push --delete origin main; }
after an unrelated green step|npm test && git push origin :main
a bundled force flag|git push -fq origin main
a bundled force flag, other order|git push -qf origin master
EOF

echo "push-delete: refused with a guard.json whose own rules say nothing about deletion"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$GPROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused (guarded project): $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
the empty-source refspec|git push origin :main
the delete switch|git push --delete origin main
EOF

# ---------------------------------------------------------------------------
# 3. must ALLOW: deleting a remote branch is what you do after a merge
# ---------------------------------------------------------------------------
echo "push-delete: allowed (the twin of every refusal above)"
for CWD in "$PROJ" "$GPROJ"; do
  while IFS='|' read -r desc cmd; do
    [ -z "$desc" ] && continue
    RC=$(run "$CWD" "$cmd")
    [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC) in $(basename "$CWD"): $cmd"
  done <<'EOF'
delete your own merged branch|git push origin :feature/my-branch
the delete switch on your own branch|git push --delete origin my-branch
the short switch on your own branch|git push -d origin experiment
deleting a branch merely named after main|git push origin :main-backup
deleting a tag, not a branch|git push origin :refs/tags/v1.2.0
an ordinary push to main|git push origin main
an ordinary push to a feature branch|git push origin feature/x
setting upstream|git push -u origin feature/x
a quiet push with no force in the bundle|git push -qn origin main
pushing HEAD onto main the normal way|git push origin HEAD:main
the deletion as a commit message|git commit -m "git push origin :main is how you delete it"
the deletion as prose in an echo|echo "never run git push --delete origin main"
EOF
done

# a heredoc BODY carries the deletion as data. It needs a real newline, so it
# cannot ride in the table above.
RC=$(run "$PROJ" "$(printf 'cat >> notes.md <<%sEOT%s\nnever run git push origin :main\nEOT\n' "'" "'")")
[ "$RC" = "0" ] && pass "allowed: the deletion inside a heredoc body" || fail "WRONGLY refused ($RC): heredoc body"

# --force-with-lease is judged by the compiled floor here only. The guarded
# project's OWN deny regex matches `--force` inside `--force-with-lease` and
# refuses it — that is that project's rule being blunt, not this law, and it
# behaved exactly the same before this file existed.
RC=$(run "$PROJ" "git push --force-with-lease origin main")
[ "$RC" = "0" ] && pass "allowed: --force-with-lease is the safe form" || fail "WRONGLY refused ($RC): --force-with-lease"

# ---------------------------------------------------------------------------
# 4. the refusal says what it is, and lands on the ledger under its own id
# ---------------------------------------------------------------------------
echo "push-delete: the refusal names the right law"
OUT=$(detail "$PROJ" "git push origin :main")
case "$OUT" in
  *baseline-branch-delete*) pass "the refusal carries the branch-delete law's id" ;;
  *) fail "wrong or missing rule id in: $(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-160)" ;;
esac
case "$OUT" in
  *delet*) pass "the refusal says the branch is being deleted, not force-pushed" ;;
  *) fail "the refusal does not mention deletion: $(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-160)" ;;
esac
LEDGER=$(grep -h '"rule":"baseline-branch-delete"' "$RABADON_DIR/spool/"*.jsonl 2>/dev/null | tail -1)
[ -n "$LEDGER" ] && pass "the refusal is written to the ledger under its own id" \
                 || fail "no baseline-branch-delete event on the ledger"

# the force-push law still answers for a force-push: the new id did not eat it
OUTF=$(detail "$PROJ" "git push --force origin main")
case "$OUTF" in
  *baseline-force-push*) pass "a real force-push still carries the force-push id" ;;
  *) fail "force-push lost its own id: $(printf '%s' "$OUTF" | tr '\n' ' ' | cut -c1-160)" ;;
esac

# ---------------------------------------------------------------------------
# 5. watch mode records it instead of refusing (same as every other law)
# ---------------------------------------------------------------------------
rm -f "$RABADON_DIR/enabled"
RC=$(run "$PROJ" "git push origin :main")
WB=$(grep -h '"ev":"WOULD_BLOCK"' "$RABADON_DIR/spool/"*.jsonl 2>/dev/null | tail -1)
if [ "$RC" = "0" ] && [ -n "$WB" ]; then pass "watch mode: exit 0, WOULD_BLOCK on the ledger"
else fail "watch mode: rc=$RC would_block=${WB:+yes}"; fi
touch "$RABADON_DIR/enabled"

# ---------------------------------------------------------------------------
# 6. the two laws are two switches — silencing one must not silence the other
# ---------------------------------------------------------------------------
echo "push-delete: disabled[] by id, one law at a time"
DPROJ="$LAB/disabled-delete"; mkdir -p "$DPROJ/.git" "$DPROJ/.rabadon"
printf 'ref: refs/heads/main\n' > "$DPROJ/.git/HEAD"
printf '{ "project": "d", "disabled": ["baseline-branch-delete"] }\n' > "$DPROJ/.rabadon/guard.json"
RC=$(run "$DPROJ" "git push origin :main")
[ "$RC" = "0" ] && pass "disabled[]: baseline-branch-delete silenced by id" || fail "silenced delete: rc=$RC"
RC=$(run "$DPROJ" "git push --force origin main")
[ "$RC" = "2" ] && pass "silencing the delete law leaves the force-push law standing" || fail "force-push went quiet too: rc=$RC"

FPROJ="$LAB/disabled-force"; mkdir -p "$FPROJ/.git" "$FPROJ/.rabadon"
printf 'ref: refs/heads/main\n' > "$FPROJ/.git/HEAD"
printf '{ "project": "f", "disabled": ["baseline-force-push"] }\n' > "$FPROJ/.rabadon/guard.json"
RC=$(run "$FPROJ" "git push --force origin main")
[ "$RC" = "0" ] && pass "disabled[]: baseline-force-push still silenced by id" || fail "silenced force: rc=$RC"
RC=$(run "$FPROJ" "git push origin :main")
[ "$RC" = "2" ] && pass "a repo that allows force-pushing main did NOT agree to main being deleted" \
                || fail "silencing force-push also silenced the delete law: rc=$RC"

# ---------------------------------------------------------------------------
# 7. judging is not running
# ---------------------------------------------------------------------------
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = "do not lose me" ] \
  && pass "canary in \$HOME intact: judging a deletion is not performing one" \
  || fail "canary in \$HOME lost or changed"
[ "$(git -C "$SBOX" rev-parse HEAD)" = "$SBOX_HEAD" ] \
  && pass "the lab repo's HEAD never moved" || fail "the lab repo's HEAD moved"
[ -f "$SBOX/keep.txt" ] || fail "the lab file was deleted"

echo "push delete: $ok ok, $bad fail"
[ $bad -eq 0 ]
