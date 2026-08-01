#!/bin/bash
# other_repo_test.sh — the repo a push rewrites is not always the one the shell
# is standing in.
#
# THE HOLE. The force-push law's oldest fallback is "a push that names no
# refspec writes the current branch", and to answer that it has to read HEAD. It
# read it in one place: `project_root(cwd) + "/.git/HEAD"` — the repo the SHELL
# is in. `-C`, `--git-dir` and $GIT_DIR are precisely the words that make git
# operate on a DIFFERENT repo, so from a scratch branch all three of these
# force-updated main in a repo next door and the gate said nothing:
#
#     git -C ../other push --force origin                                ALLOW
#     git --git-dir=../other/.git --work-tree=../other push --force ...  ALLOW
#     GIT_DIR=../other/.git git push --force origin                      ALLOW
#
# while the same bare `git push --force origin` from a repo sitting on main was
# refused. BOTH LAYERS missed it together, and for different reasons: the
# compiled law resolved the branch in the wrong repo, and a project's deny regex
# needs the literal word `main`, which none of these three lines contains.
#
# The parser was already right. cmdtext.h stepped over `-C` and `--git-dir`
# exactly as git does — that is how it found `push` — and then threw the value
# away. The word that says WHICH REPO was read and discarded one function before
# the law that needed it.
#
# THE `cd` SIBLING IS THE SAME BUG. `cd ../other && git push --force origin`
# also exited 0: the cwd is tracked per segment but the root was resolved once
# per command line, from where the line started. One resolver, asked from the
# segment's own cwd, closes both.
#
# SECTION 0 MEASURES THE PREMISE against a real git with `--dry-run --porcelain`
# instead of quoting the manual. Every fact the fix rests on is a case there:
# the three spellings really do force-update main next door; `-C` repeats and
# CHAINS; `-C<dir>` attached is REJECTED by git, so there is no attached form to
# read; `--git-dir` is accepted attached and separate; a `-C` moves git before
# the path options are interpreted, in EITHER order; a linked worktree's `.git`
# is a FILE holding `gitdir: <path>` and git follows it; `git -C ''` is a no-op;
# and `-C` at a directory that is not there is fatal — git opens nothing, so
# there is no branch to protect.
#
# THE TWINS ARE WHERE THIS FIX EARNS ITS KEEP, and they are the reason it is not
# just "block more". Reading the wrong repo cut work in the other direction too:
# sitting on main, `git -C ../feat push --force origin` — force-pushing a
# feature branch in a repo next door, the most ordinary fixup there is — was
# REFUSED, because the law read main out of the shell's repo and refused a push
# that never touches it. Every must-block case below is paired with that.
#
# EVERYTHING IS ISOLATED (K4). One mktemp lab holds all of it. $HOME is
# redirected inside the lab and carries a canary. None of the repos the gate
# judges has a remote. The only real pushes are `--dry-run` against a bare repo
# this file created two lines earlier, inside the lab. The shell section runs
# with a FAKE git and a FAKE rm first on PATH that only record their argv. Every
# other section EXECUTES NOTHING: each command is handed to rabadon-gate on
# stdin as a PreToolUse event and only its exit code is read.
set -u
cd "$(dirname "$0")/.."
# overridable so the same file can be pointed at a pre-fix binary and shown red
GATE="${RABADON_GATE:-./native/rabadon-gate}"
[ -x "$GATE" ] || { echo "other_repo_test: build first (make)"; exit 1; }
export LC_ALL=C

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

LAB=$(mktemp -d "${TMPDIR:-/tmp}/rabadon-other-repo.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
REALGIT="$(command -v git)"
export HOME="$LAB/home"; mkdir -p "$HOME/.rabadon/spool" "$HOME/Documents"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
export GIT_CONFIG_NOSYSTEM=1
touch "$RABADON_DIR/enabled"                  # enforce
CANARY="$HOME/Documents/keep.txt"
echo "do not lose me" > "$CANARY"

# ---- the repos the gate judges (no remote anywhere, ever) -------------------
newrepo() { # newrepo <dir> <head-branch> <ref...>
  local d="$1" head="$2"; shift 2
  mkdir -p "$d/.git/refs/heads"
  printf 'ref: refs/heads/%s\n' "$head" > "$d/.git/HEAD"
  for b in "$@"; do
    mkdir -p "$d/.git/refs/heads/$(dirname "$b")"
    printf '4b825dc642cb6eb9a060e54bf8d69288fbee4904\n' > "$d/.git/refs/heads/$b"
  done
}

CWD="$LAB/cwd-scratch"; newrepo "$CWD" scratch scratch      # the shell's repo
ONMAIN="$LAB/cwd-main";  newrepo "$ONMAIN" main main         # for the twins
OTHER="$LAB/other";      newrepo "$OTHER" main main feat     # the repo next door
FEAT="$LAB/feat";        newrepo "$FEAT" feat feat           # hers, next door
mkdir -p "$OTHER/sub/deep"                                   # discovery walks up
BARE="$LAB/bare.git"; mkdir -p "$BARE/refs/heads"            # a bare repo IS the git dir
printf 'ref: refs/heads/main\n' > "$BARE/HEAD"
# a linked worktree: `.git` is a FILE, and HEAD lives where it points
WT="$LAB/wt"; mkdir -p "$WT" "$OTHER/.git/worktrees/wt"
printf 'gitdir: %s\n' "$OTHER/.git/worktrees/wt" > "$WT/.git"
printf 'ref: refs/heads/main\n' > "$OTHER/.git/worktrees/wt/HEAD"

# the same shapes against a project that HAS written deny rules. The four rules
# rabadon writes for a bare home: every one of them needs the literal word
# `main` or `master` in the text, and not one of the lines below carries it.
RULED="$LAB/ruled"; newrepo "$RULED" scratch scratch
mkdir -p "$RULED/.rabadon"
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

run() { # run <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"s-otherrepo","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> what the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-otherrepo","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}
blocks() { # blocks <cwd> <desc> <cmd>
  local rc; rc=$(run "$1" "$3")
  [ "$rc" = "2" ] && pass "refused: $2" || fail "NOT refused (exit $rc): $3"
}
allows() { # allows <cwd> <desc> <cmd>
  local rc; rc=$(run "$1" "$3")
  [ "$rc" = "0" ] && pass "allowed: $2" || fail "WRONGLY refused (exit $rc): $3"
}

# ---------------------------------------------------------------------------
# 0. the premise, measured against a real git: --dry-run, lab-local bare remote
# ---------------------------------------------------------------------------
echo "another repo: what git itself does with -C, --git-dir and \$GIT_DIR"
REAL="$LAB/real"; mkdir -p "$REAL"
"$REALGIT" init -q --bare "$REAL/remote.git"
"$REALGIT" init -q "$REAL/seed"
"$REALGIT" -C "$REAL/seed" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
"$REALGIT" -C "$REAL/seed" branch -M main
"$REALGIT" -C "$REAL/seed" push -q "$REAL/remote.git" main
# a bare repo made by `init` points HEAD at whatever this git calls its default
# branch; the clones below have to check something out
"$REALGIT" --git-dir="$REAL/remote.git" symbolic-ref HEAD refs/heads/main
"$REALGIT" clone -q "$REAL/remote.git" "$REAL/target" 2>/dev/null
"$REALGIT" clone -q "$REAL/remote.git" "$REAL/shell" 2>/dev/null
# the target's main is rewritten so a push of it is a REAL non-fast-forward
"$REALGIT" -C "$REAL/target" -c user.email=t@t -c user.name=t commit -q --allow-empty --amend -m rewritten
"$REALGIT" -C "$REAL/shell" checkout -q -b feat
SHELL_BRANCH="$("$REALGIT" -C "$REAL/shell" rev-parse --abbrev-ref HEAD)"
[ "$SHELL_BRANCH" = "feat" ] && pass "the shell's repo sits on feat: nothing here is about ITS head" \
                             || fail "the shell repo is on [$SHELL_BRANCH]"

forced() { # forced <desc> <command run inside $REAL/shell>
  local out
  out=$(cd "$REAL/shell" && eval "$1" 2>&1)
  case "$out" in
    *"refs/heads/main:refs/heads/main"*"forced update"*)
      pass "git itself force-updates main next door: $2" ;;
    *) fail "git did NOT report a forced main update ($2): $(printf '%s' "$out" | tr '\n' ' ')" ;;
  esac
}
forced '"$REALGIT" -C ../target push --dry-run --porcelain --force origin' "-C ../target"
forced '"$REALGIT" --git-dir=../target/.git --work-tree=../target push --dry-run --porcelain --force origin' "--git-dir= --work-tree="
forced '"$REALGIT" --git-dir=../target/.git push --dry-run --porcelain --force origin' "--git-dir= alone (a push needs no work tree)"
forced '"$REALGIT" --git-dir ../target/.git push --dry-run --porcelain --force origin' "--git-dir as a separate word"
forced 'GIT_DIR=../target/.git "$REALGIT" push --dry-run --porcelain --force origin' "GIT_DIR= in the environment"
forced 'cd ../target && "$REALGIT" push --dry-run --porcelain --force origin' "cd, the same bug one word over"

says() { # says <desc> <command> <expected substring>
  local out; out=$(cd "$REAL/shell" && eval "$2" 2>&1)
  case "$out" in
    *"$3"*) pass "git itself: $1" ;;
    *) fail "git said [$(printf '%s' "$out" | head -1)] not [$3] ($1)" ;;
  esac
}
says "-C repeats and chains, each relative to the last" \
     '"$REALGIT" -C .. -C target rev-parse --abbrev-ref HEAD' "main"
says "a -C moves git before --git-dir is interpreted" \
     '"$REALGIT" -C .. --git-dir=target/.git rev-parse --abbrev-ref HEAD' "main"
says "and in the other order too: the -C still applies" \
     '"$REALGIT" --git-dir=target/.git -C .. rev-parse --abbrev-ref HEAD' "main"
says "GIT_DIR is read relative to the -C'd directory as well" \
     'GIT_DIR=target/.git "$REALGIT" -C .. rev-parse --abbrev-ref HEAD' "main"
says "--git-dir on the line beats GIT_DIR in the environment" \
     'GIT_DIR=../shell/.git "$REALGIT" --git-dir=../target/.git rev-parse --abbrev-ref HEAD' "main"
says "there is NO attached -C form: git rejects it" \
     '"$REALGIT" -C../target rev-parse --abbrev-ref HEAD' "unknown option"
says "an empty -C is a no-op, not an error" \
     '"$REALGIT" -C "" rev-parse --abbrev-ref HEAD' "feat"
says "-C at a directory that is not there is fatal: git opens nothing" \
     '"$REALGIT" -C ../nope rev-parse --abbrev-ref HEAD' "cannot change to"
says "discovery walks UP from where -C landed" \
     'mkdir -p ../target/sub/deep; "$REALGIT" -C ../target/sub/deep rev-parse --abbrev-ref HEAD' "main"

# a linked worktree: `.git` is a FILE, and git follows the path inside it
"$REALGIT" -C "$REAL/target" worktree add -q "$REAL/wt" -b wtbranch 2>/dev/null
if [ -f "$REAL/wt/.git" ]; then
  pass "a linked worktree's .git is a FILE, not a directory"
  case "$(cat "$REAL/wt/.git")" in
    "gitdir: "*) pass "and it holds one line: gitdir: <path to the real git dir>" ;;
    *) fail "the .git file holds something else: $(cat "$REAL/wt/.git")" ;;
  esac
  says "git follows that file to find HEAD" '"$REALGIT" -C ../wt rev-parse --abbrev-ref HEAD' "wtbranch"
else
  fail "could not create a linked worktree to measure"
fi

# ---------------------------------------------------------------------------
# 1. the premise, measured again: the SHELL really hands git these argv
# ---------------------------------------------------------------------------
echo "another repo: the shell runs these lines (fake git, fake rm)"
mkdir -p "$LAB/fakebin" "$LAB/sandbox"
echo "do not lose me either" > "$LAB/sandbox/keep.txt"
for name in git rm; do
  cat > "$LAB/fakebin/$name" <<FAKE
#!/bin/sh
printf '$name' >> "$LAB/argv.log"
for a in "\$@"; do printf ' [%s]' "\$a" >> "$LAB/argv.log"; done
printf ' GIT_DIR=%s\n' "\${GIT_DIR:-}" >> "$LAB/argv.log"
exit 0
FAKE
  chmod +x "$LAB/fakebin/$name"
done
ran() { # ran <label> <command> <expected log line>
  : > "$LAB/argv.log"
  ( cd "$LAB/sandbox" && env PATH="$LAB/fakebin:$PATH" bash -c "$2" ) >/dev/null 2>&1
  if grep -qxF "$3" "$LAB/argv.log" 2>/dev/null; then
    pass "the shell runs it: $1"
  else
    fail "the shell did NOT run it ($1): log=[$(tr '\n' ';' < "$LAB/argv.log")]"
  fi
}
ran "the -C form" 'git -C ../other push --force origin' \
    'git [-C] [../other] [push] [--force] [origin] GIT_DIR='
ran "the --git-dir form" 'git --git-dir=../other/.git --work-tree=../other push --force origin' \
    'git [--git-dir=../other/.git] [--work-tree=../other] [push] [--force] [origin] GIT_DIR='
ran "the environment form" 'GIT_DIR=../other/.git git push --force origin' \
    'git [push] [--force] [origin] GIT_DIR=../other/.git'
[ -f "$LAB/sandbox/keep.txt" ] && pass "the fakes ran instead of the real git and rm: nothing was pushed or deleted" \
  || fail "a real rm ran in the lab"

# ---------------------------------------------------------------------------
# 2. must BLOCK: the shell is on `scratch`, the repo next door is on a shared branch
# ---------------------------------------------------------------------------
echo "another repo: refused when the repo GIT WILL USE is on a shared branch"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  blocks "$CWD" "$desc" "$cmd"
done <<EOF
the reported -C escape|git -C ../other push --force origin
the same, spelled absolute|git -C $OTHER push --force origin
the reported --git-dir escape|git --git-dir=../other/.git --work-tree=../other push --force origin
--git-dir with no work tree|git --git-dir=../other/.git push --force origin
--git-dir as a separate word|git --git-dir ../other/.git push --force origin
the reported \$GIT_DIR escape|GIT_DIR=../other/.git git push --force origin
a chained -C|git -C .. -C other push --force origin
-C before --git-dir, the git dir relative to it|git -C .. --git-dir=other/.git push --force origin
--git-dir before -C: the same repo either way|git --git-dir=other/.git -C .. push --force origin
GIT_DIR relative to the -C'd directory|GIT_DIR=other/.git git -C .. push --force origin
the short force flag|git -C ../other push -f origin
the force refspec with no branch named|git -C ../other push origin +HEAD
HEAD resolved in the OTHER repo|git -C ../other push --force origin HEAD
the @ shorthand in the other repo|git -C ../other push --force origin @
--all reads the other repo's refspace|git -C ../other push --all --force origin
--mirror reads the other repo's refspace|git -C ../other push --mirror origin
a config refspec plus a -C|git -C ../other -c push.default=matching push --force origin
discovery walks up from the -C'd subdirectory|git -C ../other/sub/deep push --force origin
a bare repo IS the git dir|git --git-dir=../bare.git push --force origin
a linked worktree's .git is a file that points at HEAD|git -C ../wt push --force origin
the same worktree named by its .git file|git --git-dir=../wt/.git push --force origin
the cd sibling of the same bug|cd ../other && git push --force origin
cd with an absolute path|cd $OTHER && git push --force origin
the escape inside sh -lc|sh -lc 'git -C ../other push --force origin'
the escape after an ordinary command|npm test && git -C ../other push --force origin
the escape in a brace group|{ git -C ../other push --force origin; }
the escape behind a git alias|git -c alias.x='push --force' -C ../other x origin
EOF

# the same lines where a project HAS written deny rules: the regexes spell out
# main and master, and none of these lines carries either word. Only the
# compiled law can see them, and this is where that shows.
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  blocks "$RULED" "$desc, with project deny rules present" "$cmd"
done <<'EOF'
the -C escape|git -C ../other push --force origin
the --git-dir escape|git --git-dir=../other/.git --work-tree=../other push --force origin
the $GIT_DIR escape|GIT_DIR=../other/.git git push --force origin
EOF

# the refusal is the compiled law's, it names the branch it found, and it names
# the repo it found it in — an operator told 'main' about a repo she is not
# standing in has to be told which repo that is.
D=$(detail "$CWD" "git -C ../other push --force origin")
case "$D" in
  *baseline-force-push*) pass "the refusal carries the force-push law's id" ;;
  *) fail "wrong rule refused it: $(printf '%s' "$D" | head -2 | tr '\n' ' ')" ;;
esac
case "$D" in
  *main*) pass "the message names the branch that repo is on" ;;
  *) fail "the message never names the branch: $(printf '%s' "$D" | head -3 | tr '\n' ' ')" ;;
esac
case "$D" in
  *"$OTHER"*) pass "the message names the repo the branch was read in" ;;
  *) fail "the message never names the other repo: $(printf '%s' "$D" | head -3 | tr '\n' ' ')" ;;
esac

# ---------------------------------------------------------------------------
# 3. must NOT BLOCK: the twins, and the first one is work the old law CUT
# ---------------------------------------------------------------------------
echo "another repo: the work this must not cut (the shell is on main, the target is not)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  allows "$ONMAIN" "$desc" "$cmd"
done <<EOF
force-pushing her own branch in the repo next door|git -C ../feat push --force origin
the same through --git-dir|git --git-dir=../feat/.git --work-tree=../feat push --force origin
the same through the environment|GIT_DIR=../feat/.git git push --force origin
--all where that refspace holds no shared branch|git -C ../feat push --all --force origin
--mirror where that refspace holds no shared branch|git -C ../feat push --mirror origin
HEAD resolved in a repo that is on her branch|git -C ../feat push --force origin HEAD
the cd sibling of the same twin|cd ../feat && git push --force origin
a lease into the other repo|git -C ../other push --force-with-lease origin
an ordinary push into the other repo|git -C ../other push origin
a push of a private branch by name|git -C ../other push --force origin my-branch
a read in the other repo|git -C ../other log --oneline -5
a status in the other repo|git -C ../other status --short
a fetch in the other repo|git -C ../other fetch --all
tags only, no branch written|git -C ../other push --tags --force origin
the words in a commit message|git commit -m "git -C ../other push --force origin is the bypass"
the words in an echo|echo "GIT_DIR=../other/.git git push --force origin"
a delete inside the project|rm -rf ./build
EOF

# and the twin that keeps the fallback alive: with no knob at all, the shell's
# own repo is still the answer, and on main it is still refused.
blocks "$ONMAIN" "no knob at all: the shell's own repo still decides" "git push --force origin"
blocks "$ONMAIN" "the shell's own repo, HEAD spelled out" "git push --force origin HEAD"
allows "$CWD" "the shell's own repo on a scratch branch still goes" "git push --force origin"
blocks "$CWD" "a branch written down is still read from the line" "git push --force origin main"
blocks "$CWD" "a -C does not excuse a branch written down" "git -C ../feat push --force origin main"
blocks "$CWD" "the delete law still sees a shared branch through a -C" "git -C ../feat push origin :main"
blocks "$CWD" "the hard-reset law is untouched" "git reset --hard origin/main"

# ---------------------------------------------------------------------------
# 4. the named limits, asserted rather than described
# ---------------------------------------------------------------------------
echo "another repo: what this cannot read, said out loud"
# a path the text does not contain: `$REPO` expands in a shell this text does
# not describe. Refusing on a guess is worse than missing one, so the fallback
# resolves nothing — and a branch the line WRITES DOWN is still refused.
allows "$CWD" "an unresolved \$REPO in -C: no branch can be resolved" "git -C \$REPO push --force origin"
blocks "$CWD" "the same line with the branch written down" "git -C \$REPO push --force origin main"
allows "$ONMAIN" "an unresolved \$REPO does not fall back to the shell's repo" "git -C \$REPO push --force origin"
# git itself refuses to start when -C cannot chdir, so there is no branch to protect
allows "$ONMAIN" "-C at a directory that is not there (git fatals before it opens a repo)" \
       "git -C ../nope push --force origin"
allows "$ONMAIN" "--git-dir at a path that is not there" "git --git-dir=../nope/.git push --force origin"
# ...but the strongest push keeps its stance: a mirror whose refspace cannot be
# read is the case where the remote gets emptied, and that stays refused.
blocks "$CWD" "a mirror into a repo that cannot be read is still refused" \
       "git -C \$REPO push --mirror origin"

# ---------------------------------------------------------------------------
# 5. judging is not running
# ---------------------------------------------------------------------------
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = "do not lose me" ] \
  && pass "the canary in the home dir survived judging every command above" || fail "the canary is gone"
[ -f "$LAB/sandbox/keep.txt" ] && pass "the canary in the lab survived" || fail "the lab canary is gone"
for R in "$CWD" "$ONMAIN" "$OTHER" "$FEAT" "$RULED"; do
  [ -z "$("$REALGIT" -C "$R" remote 2>/dev/null)" ] || fail "$R grew a remote"
done
pass "none of the judged repos has a remote: nothing could have left this machine"
[ -d /tmp ] && [ -d /etc ] && [ -d "$HOME" ] \
  && pass "/tmp, /etc and the home dir are still on the machine" || fail "the test ran what it judged"

echo "another repo: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
