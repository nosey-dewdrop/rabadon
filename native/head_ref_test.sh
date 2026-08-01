#!/bin/bash
# head_ref_test.sh — `HEAD` is not a branch name, it is the ref the repo resolves.
#
# The force-push law reads the refspec and asks shared_branch() whether the
# destination is main/master/trunk/develop. shared_branch() is a NAME
# comparison: it strips a `+`, a `refs/heads/` prefix and a remote prefix, and
# compares what is left against four words. `HEAD` and `@` survive every one of
# those strips untouched, because they need none — they are not names. So the
# law read the word HEAD, found it in none of the four, and allowed:
#
#     git push --force origin HEAD     on main   ALLOW
#     git push --force origin @        on main   ALLOW
#     git push -f origin HEAD          on main   ALLOW
#     git push origin +HEAD            on main   ALLOW
#
# while the same push written with the branch spelled out was refused. git's own
# manual is what makes this a hole and not a curiosity: "git push origin HEAD —
# A handy way to push the current branch to the same name on the remote." On
# main, `HEAD` IS main.
#
# The law already knew this. With NO refspec at all — `git push --force origin`
# — it reads .git/HEAD, resolves the current branch and refuses on main. Writing
# the word `HEAD` where the refspec goes turned that resolution off: the
# argument was present, so nothing had to be resolved, so nothing was.
#
# THE COLON IS THE OTHER HALF, AND IT GOES THE OTHER WAY. `main:HEAD` does NOT
# force-push the remote's default branch. Measured against git itself:
#
#     git push --dry-run --porcelain origin main:HEAD
#       -> refs/heads/main:refs/heads/HEAD   [new branch]
#
# A destination written after a colon is taken literally, so `HEAD` there is a
# branch called HEAD that git will CREATE, and creating a branch is not
# rewriting a shared one. Only the colon-less refspec is the ref the repo
# resolves. A fix that reads the word `HEAD` anywhere in the refspec would have
# refused an ordinary, harmless push — which is why this file measures git
# rather than reasoning about it, and why the resolution is scoped to push.
#
# AND IT IS SCOPED TO PUSH FOR A SECOND REASON. In `git reset --hard HEAD` the
# same word names a COMMIT, not a destination branch. Resolving it there would
# turn the most ordinary line in git into a refusal on every shared branch. The
# hard-reset law is deliberately left reading names.
#
# SECTION 1 EXECUTES A SHELL, ON PURPOSE, so the premise is measured and not
# asserted. It runs with a FAKE `git` and a FAKE `rm` first on PATH that record
# their argv and do nothing else, inside one mktemp lab, whose repo has NO
# REMOTE and whose $HOME is redirected inside the lab with a canary in it. If
# the fakes were somehow not found, the real git would have no remote to push
# to and the real rm would only see paths this test made seconds earlier. The
# one place real git runs it is read-only: `symbolic-ref` and `rev-parse`, which
# is git answering, in its own words, what HEAD and @ point at.
#
# EVERY OTHER SECTION EXECUTES NOTHING: each command is handed to rabadon-gate
# on stdin as a PreToolUse event and only its exit code is read. The canaries at
# the bottom are the proof.
#
# Every must-BLOCK case below has its must-NOT-BLOCK twin, and the twin that
# matters most is the same command on a branch that is nobody else's:
# `git push --force origin HEAD` on `feat` is a developer force-pushing her own
# branch, which is the ordinary way to fix up a review. A fix that blocks HEAD
# because it is spelled HEAD cuts that work. The block has to depend on what
# HEAD resolves to, and the twins are how that is held.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "head_ref_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

LAB=$(mktemp -d /tmp/rabadon-head-ref-test.XXXXXX)
trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"; mkdir -p "$HOME/.rabadon/spool" "$HOME/Documents"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
touch "$RABADON_DIR/enabled"                  # enforce
CANARY="$HOME/Documents/keep.txt"
echo "do not lose me" > "$CANARY"

# TWO projects, because the escape was reported through both layers. `bare` has
# no guard.json: the three compiled laws alone, the fresh-install path. `ruled`
# carries the four rules rabadon writes for a bare home — deny REGEXES, which
# spell out main and master and therefore cannot see HEAD at all. If the
# compiled law refuses it in both, the refusal does not depend on a project
# having written rules.
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

run() { # run <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"s-headref","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> what the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-headref","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}

# ---------------------------------------------------------------------------
# 1. the premise, measured: the shell really runs it, and git really resolves it
# ---------------------------------------------------------------------------
echo "head as a refspec: what the shell runs and what git resolves (fake git, fake rm, no remote)"
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
ran "the bare HEAD refspec" 'git push --force origin HEAD' 'git [push] [--force] [origin] [HEAD]'
ran "the @ shorthand"       'git push --force origin @'    'git [push] [--force] [origin] [@]'
ran "the short force flag"  'git push -f origin HEAD'      'git [push] [-f] [origin] [HEAD]'
ran "the force refspec"     'git push origin +HEAD'        'git [push] [origin] [+HEAD]'
[ -f "$LAB/sandbox/keep.txt" ] && pass "the fakes ran instead of the real git and rm: nothing was pushed or deleted" \
  || fail "a real rm ran in the lab"

# real git, read-only, no remote, no push: git's own answer for what HEAD names.
# This is the whole argument in one line — if HEAD did not resolve to the
# current branch, there would be nothing here to refuse.
REALREPO="$LAB/realrepo"
git init -q "$REALREPO" 2>/dev/null
git -C "$REALREPO" symbolic-ref HEAD refs/heads/main 2>/dev/null
git -C "$REALREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one 2>/dev/null
if [ -d "$REALREPO/.git" ]; then
  H=$(git -C "$REALREPO" symbolic-ref HEAD 2>/dev/null)
  A=$(git -C "$REALREPO" rev-parse --symbolic-full-name @ 2>/dev/null)
  [ "$H" = "refs/heads/main" ] && pass "git itself: HEAD is refs/heads/main in this repo" \
                               || fail "git says HEAD is [$H], not refs/heads/main"
  [ "$A" = "refs/heads/main" ] && pass "git itself: @ is the same ref as HEAD" \
                               || fail "git says @ is [$A], not refs/heads/main"
  R=$(git -C "$REALREPO" remote 2>/dev/null)
  [ -z "$R" ] && pass "the real repo has no remote: a push here could not reach anything" \
              || fail "the lab repo grew a remote: [$R]"
else
  fail "could not create a real git repo to ask"
fi

# ---------------------------------------------------------------------------
# 2. must BLOCK: on a shared branch, HEAD is that branch
# ---------------------------------------------------------------------------
echo "head as a refspec: refused while HEAD is on a shared branch"
for BR in main master trunk develop; do
  on_branch "$BR"
  while IFS='|' read -r desc cmd; do
    [ -z "$desc" ] && continue
    RC=$(run "$BARE" "$cmd")
    [ "$RC" = "2" ] && pass "refused on $BR (no guard.json): $desc" || fail "NOT refused on $BR ($RC): $cmd"
  done <<'EOF'
the bare HEAD refspec|git push --force origin HEAD
the @ shorthand|git push --force origin @
the short force flag with HEAD|git push -f origin HEAD
the force refspec form of HEAD|git push origin +HEAD
the force refspec form of @|git push origin +@
HEAD behind a git global option|git -C . push --force origin HEAD
HEAD inside a shell string|bash -c 'git push --force origin HEAD'
HEAD in a brace group|{ git push --force origin HEAD; }
HEAD in the then branch|if true; then git push --force origin @; fi
HEAD after an ordinary command|npm test && git push --force origin HEAD
EOF
done

# the same commands where a project HAS written deny rules. The regexes below
# spell out main and master, so they cannot match HEAD; only the compiled law
# can, and this is where that shows.
on_branch main
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$RULED" "$cmd")
  [ "$RC" = "2" ] && pass "refused with project deny rules present: $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
the bare HEAD refspec|git push --force origin HEAD
the @ shorthand|git push --force origin @
EOF

# the refusal is the compiled law's, and it names the branch HEAD turned out to be
on_branch main
D=$(detail "$BARE" "git push --force origin HEAD")
case "$D" in
  *baseline-force-push*) pass "the refusal carries the force-push law's id" ;;
  *) fail "wrong rule refused it: $(printf '%s' "$D" | head -2 | tr '\n' ' ')" ;;
esac
case "$D" in
  *main*) pass "the message names the branch HEAD resolved to, not the word HEAD" ;;
  *) fail "message never names the branch: $(printf '%s' "$D" | head -3 | tr '\n' ' ')" ;;
esac
LEDGER=$(grep -h '"rule":"baseline-force-push"' "$RABADON_DIR/spool/"*.jsonl 2>/dev/null | tail -1)
[ -n "$LEDGER" ] && pass "the refusal is on the ledger under the baseline id" \
                 || fail "no baseline-force-push event on the ledger"

# ---------------------------------------------------------------------------
# 3. must ALLOW, twin by twin: the block depends on what HEAD resolves TO
# ---------------------------------------------------------------------------
echo "head as a refspec: the work this must not cut (HEAD on a branch that is hers)"
for BR in feat my-branch feature/login release-notes; do
  on_branch "$BR"
  while IFS='|' read -r desc cmd; do
    [ -z "$desc" ] && continue
    RC=$(run "$BARE" "$cmd")
    [ "$RC" = "0" ] && pass "allowed on $BR: $desc" || fail "WRONGLY refused on $BR ($RC): $cmd"
  done <<'EOF'
the bare HEAD refspec, force-pushing her own branch|git push --force origin HEAD
the @ shorthand on her own branch|git push --force origin @
the short force flag on her own branch|git push -f origin HEAD
the force refspec form on her own branch|git push origin +HEAD
HEAD in a brace group on her own branch|{ git push --force origin HEAD; }
HEAD after an ordinary command on her own branch|npm test && git push --force origin HEAD
EOF
done

echo "head as a refspec: the work this must not cut (the word HEAD elsewhere)"
on_branch main
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$BARE" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<'EOF'
the safe force with HEAD|git push --force-with-lease origin HEAD
the safe force with the @ shorthand|git push --force-with-lease origin @
an ordinary push of HEAD, no force|git push origin HEAD
the most ordinary line in git|git reset --hard HEAD
a hard reset one commit back|git reset --hard HEAD~1
a hard reset two commits back|git reset --hard HEAD^^
a hard reset to the ref, not the branch name|git reset --hard @
a diff against HEAD|git diff HEAD --stat
a log against HEAD|git log HEAD~5..HEAD --oneline
HEAD as a commit message|git commit -m "git push --force origin HEAD is what broke it"
HEAD echoed as a string|echo "git push --force origin HEAD"
a branch whose name merely starts with HEAD|git push --force origin HEADless
a branch whose name merely ends with HEAD|git push --force origin subHEAD
a literal branch named HEAD, spelled in full|git push --force origin refs/heads/HEAD
EOF

# The measured one. `main:HEAD` names a branch git will CREATE on the remote —
# `git push --dry-run --porcelain origin main:HEAD` answers
# `refs/heads/main:refs/heads/HEAD  [new branch]`. A destination after a colon
# is a name, and creating a branch called HEAD rewrites nobody's history. A fix
# that saw the word HEAD anywhere in the refspec would refuse this.
for BR in main feat; do
  on_branch "$BR"
  for CMD in "git push --force origin main:HEAD" "git push --force origin feat:HEAD" "git push --force origin HEAD:my-branch"; do
    RC=$(run "$BARE" "$CMD")
    [ "$RC" = "0" ] && pass "allowed on $BR: a destination after a colon is a name — $CMD" \
                    || fail "WRONGLY refused on $BR ($RC): $CMD"
  done
done

# and the twin that keeps the colon reading honest in the other direction:
# HEAD:main still names main, and still goes.
on_branch feat
RC=$(run "$BARE" "git push --force origin HEAD:main")
[ "$RC" = "2" ] && pass "refused: HEAD:main names main as the destination, from any branch" \
                || fail "NOT refused ($RC): the colon form to main"

# detached HEAD: .git/HEAD holds a sha, so HEAD is on no branch and names no
# destination. git itself refuses this push for the same reason ("You are not
# currently on a branch"), so there is nothing here for the law to protect.
printf '4b825dc642cb6eb9a060e54bf8d69288fbee4904\n' > "$BARE/.git/HEAD"
RC=$(run "$BARE" "git push --force origin HEAD")
[ "$RC" = "0" ] && pass "allowed: with a detached HEAD the refspec names no branch" \
                || fail "WRONGLY refused ($RC): detached HEAD"
on_branch main

# ---------------------------------------------------------------------------
# 4. the resolution belongs to push and did not leak into the other two laws
# ---------------------------------------------------------------------------
echo "head as a refspec: the resolution is scoped to push"
on_branch main
RC=$(run "$BARE" "git reset --hard HEAD")
[ "$RC" = "0" ] && pass "the hard-reset law still reads HEAD as a commit, on main" \
                || fail "WRONGLY refused ($RC): a hard reset to HEAD on main"
RC=$(run "$BARE" "git reset --hard origin/main")
[ "$RC" = "2" ] && pass "the hard-reset law still refuses the shared branch by name" \
                || fail "NOT refused ($RC): a hard reset onto the shared branch"
RC=$(run "$BARE" "rm -rf ./build")
[ "$RC" = "0" ] && pass "the delete law is untouched: a build dir still goes" \
                || fail "WRONGLY refused ($RC): rm -rf ./build"

# ---------------------------------------------------------------------------
# 5. judging is not running
# ---------------------------------------------------------------------------
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = "do not lose me" ] \
  && pass "the canary in the home dir survived judging every command above" || fail "the canary is gone"
[ -f "$LAB/sandbox/keep.txt" ] && pass "the canary in the lab survived" || fail "the lab canary is gone"
[ -z "$(git -C "$REALREPO" remote 2>/dev/null)" ] \
  && pass "the lab repo still has no remote: nothing left this machine" || fail "a remote appeared"
[ -d /tmp ] && [ -d /etc ] && [ -d "$HOME" ] \
  && pass "/tmp, /etc and the home dir are still on the machine" || fail "the test ran what it judged"

echo "head as a refspec: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
