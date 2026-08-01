#!/bin/bash
# partial_ref_test.sh — `heads/main` IS `refs/heads/main`, and the law stopped
# reading one level short of the spelling git also accepts.
#
# dest_name() in native/baseline.h already knew the ref could be written out in
# full: it strips a leading `refs/heads/` before it compares the name. What it
# did next was split on the FIRST '/' and read the left half as a REMOTE:
#
#     const size_t slash = r.find('/');
#     if (slash != string::npos) {
#       const string remote = r.substr(0, slash);
#       if (remote != "origin" && remote != "upstream") return "";
#
# So `heads/main` handed the word `heads` to that test, `heads` is not a remote
# anybody has, and the function answered "" — no branch here, nothing to judge.
# git does not read it that way. A partially qualified ref is resolved through
# the refs/ search order (gitrevisions(7): `$GIT_DIR/<refname>`, then
# `refs/<refname>`, then refs/tags, refs/heads, refs/remotes), and rule two
# turns `heads/main` into `refs/heads/main` before anything else is tried.
# There are two spellings of the heads namespace and the law knew one.
#
# SIX SPELLINGS WALKED THROUGH IT, not the three that were reported:
#     git push origin :heads/main            the branch, removed from the remote
#     git push --delete origin heads/main    the same, in git's own switch
#     git push -d origin heads/main          the short switch
#     git push --force origin heads/main     history rewritten under everyone
#     git push --force origin main:heads/main  the same, destination written out
#     git reset --hard heads/main            local work discarded onto it
# The last one is the same function answering a different law: the hard-reset
# rule calls shared_branch() on its operands too, so the hole was never only
# about pushing.
#
# BOTH LAYERS, ONE HOLE — but not the same half. Measured against the four
# rules a bare `rabadon init` writes: the FORCE spellings are caught by that
# project's deny regex (`\bmain\b` matches after a '/'), and the DELETE
# spellings are not, because that regex hunts for `--force|-f` and a deletion
# carries neither. So the delete forms exited 0 through both layers at once,
# and the force forms exited 0 on the fresh-install path this file's section 2
# runs — the path baseline.h exists for.
#
# AND THE FIX CLOSED A FALSE REFUSAL THAT WAS ALREADY THERE. The remote-prefix
# walk ran AFTER the `refs/heads/` strip, so `refs/heads/origin/main` — a branch
# literally NAMED `origin/main` — had its own name eaten and was judged as
# `main`. Section 1 measures what git does with it: `*  refs/heads/origin/main:
# refs/heads/origin/main  [new branch]`. Creating a branch rewrites nobody's
# history, and the gate was refusing it. Once the namespace prefix is written
# down, what follows it is the branch name verbatim, so no remote is looked for
# in a name that already said which namespace it is in.
#
# THE NAMESPACE IS NOT STRIPPED BLINDLY, and section 1 measures why. `tags/main`
# is refs/TAGS/main, a different namespace with the same last word:
# `git push origin :tags/main` answers "unable to delete 'tags/main': remote ref
# does not exist" and does not touch the branch, and `git push origin
# main:tags/main` reports `[new branch]` for refs/heads/tags/main. A fix that
# read the last path component would refuse both. Only `heads/` and
# `refs/heads/` name the branch namespace, and only those two are stripped.
#
# SECTION 1 EXECUTES, ON PURPOSE, so the premise is measured and not asserted.
# It runs a REAL git with --dry-run --porcelain against a bare remote this file
# created seconds earlier inside its own mktemp lab, and reads back that the
# remote's refs did not move; and it runs a REAL bash with a FAKE git and a FAKE
# rm first on PATH that only record their argv. $HOME points inside the lab and
# holds a canary. If every fake were somehow missed, the real git has no remote
# but the throwaway bare repo and the real rm can only see paths made here.
#
# EVERY OTHER SECTION EXECUTES NOTHING: each command is handed to rabadon-gate
# on stdin as a PreToolUse event and only its exit code is read.
set -u
cd "$(dirname "$0")/.."
GATE=./native/rabadon-gate
[ -x "$GATE" ] || { echo "partial_ref_test: build first (make)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

LAB=$(mktemp -d /tmp/rabadon-partialref-test.XXXXXX)
trap 'rm -rf "$LAB"' EXIT
export HOME="$LAB/home"; mkdir -p "$HOME/.rabadon/spool" "$HOME/Documents"
export RABADON_DIR="$HOME/.rabadon"
export RABADON_NOTIFY=0
export GIT_CONFIG_SYSTEM=/dev/null                # no machine-wide git config
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"       # and none but the lab's own
touch "$RABADON_DIR/enabled"                      # enforce
CANARY="$HOME/Documents/keep.txt"
echo "do not lose me" > "$CANARY"

# no guard.json: the compiled floor, judged alone — the fresh-install path
PROJ="$LAB/proj"; mkdir -p "$PROJ/.git" "$PROJ/build"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"

# and a project that DID write rules — the four a bare `rabadon init` authors.
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
  printf '{"hook_event_name":"PreToolUse","session_id":"s-partialref","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
detail() { # detail <cwd> <command> -> what the gate prints
  printf '{"hook_event_name":"PreToolUse","session_id":"s-partialref","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1
}

# ---------------------------------------------------------------------------
# 1. the premise, measured against a real git: `heads/main` is refs/heads/main,
#    `tags/main` is not, and `refs/heads/origin/main` is a branch of its own
# ---------------------------------------------------------------------------
echo "partial-ref: what git resolves (real git, --dry-run, a bare remote made here)"
REMOTE="$LAB/remote.git"; WORK="$LAB/work"
git init -q --bare "$REMOTE"
git init -q "$WORK"
git -C "$WORK" config user.email t@t
git -C "$WORK" config user.name t
git -C "$WORK" commit -q --allow-empty -m one
git -C "$WORK" branch -M main
git -C "$WORK" remote add origin "$REMOTE"
git -C "$WORK" commit -q --allow-empty -m two
git -C "$WORK" push -q origin main
git -C "$WORK" branch feature
git -C "$WORK" push -q origin feature
git -C "$WORK" reset -q --hard HEAD~1                 # main now DIVERGES from the remote
git -C "$WORK" commit -q --allow-empty -m two-divergent
git -C "$WORK" branch "origin/main"                   # a branch literally named origin/main
REM_MAIN_BEFORE=$(git -C "$REMOTE" rev-parse refs/heads/main)
REM_FEAT_BEFORE=$(git -C "$REMOTE" rev-parse refs/heads/feature)

dry() { git -C "$WORK" push --dry-run --porcelain "$@" 2>&1 | grep -v '^To \|^Done$' | tr '\n' '|'; }
says() { # says <label> <expected substring> <argv...>
  local label="$1" want="$2"; shift 2
  local out; out=$(dry "$@")
  case "$out" in
    *"$want"*) pass "git itself: $label" ;;
    *) fail "git itself: $label — wanted [$want], got [$out]" ;;
  esac
}
says "origin :heads/main deletes refs/heads/main"        ':refs/heads/main	[deleted]'  origin ':heads/main'
says "--delete origin heads/main deletes refs/heads/main" ':refs/heads/main	[deleted]' --delete origin 'heads/main'
says "--force origin heads/main force-updates main"      'refs/heads/main:refs/heads/main' --force origin 'heads/main'
says "--force origin heads/main is a FORCED update"      '(forced update)'                --force origin 'heads/main'
says "--force origin main:heads/main lands on main"      'refs/heads/main:refs/heads/main' --force origin 'main:heads/main'
says "heads/feature is the feature branch, not main"     'refs/heads/feature:refs/heads/feature' --force origin 'heads/feature'
says ":heads/feature deletes the feature branch"         ':refs/heads/feature	[deleted]' origin ':heads/feature'
# the namespace that must NOT be stripped: tags/ is not heads/
says ":tags/main touches no branch"        "unable to delete 'tags/main'" origin ':tags/main'
says "main:tags/main CREATES refs/heads/tags/main" 'refs/heads/main:refs/heads/tags/main	[new branch]' --force origin 'main:tags/main'
# the name whose own slash is not a remote prefix
says "refs/heads/origin/main is a NEW branch of its own" 'refs/heads/origin/main:refs/heads/origin/main	[new branch]' --force origin 'refs/heads/origin/main'
says "heads/origin/main is that same new branch"         'refs/heads/origin/main:refs/heads/origin/main	[new branch]' --force origin 'heads/origin/main'

SFN=$(git -C "$WORK" rev-parse --symbolic-full-name heads/main 2>&1)
[ "$SFN" = "refs/heads/main" ] && pass "git itself: rev-parse heads/main is refs/heads/main" \
                               || fail "git says heads/main is [$SFN]"
SFT=$(git -C "$WORK" rev-parse --symbolic-full-name tags/main 2>&1 || true)
[ "$SFT" = "refs/heads/main" ] && fail "tags/main resolved to the branch — the namespaces are not distinct here" \
                               || pass "git itself: tags/main is NOT refs/heads/main ($(printf '%s' "$SFT" | head -1 | cut -c1-40))"

[ "$(git -C "$REMOTE" rev-parse refs/heads/main)" = "$REM_MAIN_BEFORE" ] \
  && pass "the dry-run probes moved nothing: remote main is where it was" \
  || fail "the probe MOVED refs/heads/main on the lab remote"
[ "$(git -C "$REMOTE" rev-parse refs/heads/feature)" = "$REM_FEAT_BEFORE" ] \
  && pass "the dry-run probes deleted nothing: remote feature is still there" \
  || fail "the probe removed refs/heads/feature on the lab remote"

# and the shell really does hand these words to git
mkdir -p "$LAB/fakebin"
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
  ( cd "$WORK" && env PATH="$LAB/fakebin:$PATH" bash -c "$2" ) >/dev/null 2>&1
  grep -qxF "$3" "$LAB/argv.log" 2>/dev/null \
    && pass "the shell runs it: $1" \
    || fail "the shell did NOT run it ($1): log=[$(tr '\n' ';' < "$LAB/argv.log")]"
}
ran "the partially qualified delete" 'git push origin :heads/main'      'git [push] [origin] [:heads/main]'
ran "the partially qualified force"  'git push --force origin heads/main' 'git [push] [--force] [origin] [heads/main]'
ran "the partially qualified reset"  'git reset --hard heads/main'      'git [reset] [--hard] [heads/main]'

# ---------------------------------------------------------------------------
# 2. must BLOCK: every spelling that lands on refs/heads/<shared>
# ---------------------------------------------------------------------------
echo "partial-ref: refused (no guard.json — the compiled floor alone)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused: $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
the branch deleted, partially qualified|git push origin :heads/main
the same, on master|git push origin :heads/master
the delete switch, partially qualified|git push --delete origin heads/main
the short delete switch|git push -d origin heads/trunk
the force push, partially qualified|git push --force origin heads/main
the short force flag|git push -f origin heads/develop
the force refspec marker|git push origin +heads/main
the destination after a colon|git push --force origin main:heads/main
the destination after a colon, delete side|git push origin :heads/main
a bundled force flag|git push -fq origin heads/main
delete and force together|git push -fd origin heads/main
a global option in front|git -C /tmp/elsewhere push --force origin heads/main
wrapped in a shell string|sh -lc 'git push origin :heads/main'
behind a reserved word|{ git push --force origin heads/main; }
after an unrelated green step|npm test && git push origin :heads/main
the hard reset onto the same ref|git reset --hard heads/main
the hard reset, on master|git reset --hard heads/master
EOF

echo "partial-ref: refused in a project whose four rules never mention the spelling"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$GPROJ" "$cmd")
  [ "$RC" = "2" ] && pass "refused (guarded project): $desc" || fail "NOT refused ($RC): $cmd"
done <<'EOF'
the delete its deny regex cannot see (no -f in a deletion)|git push origin :heads/main
the delete switch, same blind spot|git push --delete origin heads/main
the short delete switch|git push -d origin heads/main
the hard reset its regex reads as neither main nor origin/main|git reset --hard heads/main
EOF

# ---------------------------------------------------------------------------
# 3. must ALLOW: the twin of every refusal above
# ---------------------------------------------------------------------------
# THE COMPILED FLOOR IS THE ONE ON TRIAL HERE. Every force-flavoured allow below
# is judged in the unguarded project only, because the guarded project's OWN
# deny regex — `git\s+push[^|;&]*(--force|-f)\b[^|;&]*\b(main|master)\b` — sees
# the word `main` after a slash, after a hyphen and inside `--force-with-lease`,
# and refuses `heads/main-backup`, `heads/not-main`, `main:tags/main` and the
# lease. That is that project's rule being blunt with its own text, it answered
# exactly the same way before this file existed, and section 3b proves it is
# that rule and not this law by reading the id off the refusal.
echo "partial-ref: allowed (the twin of every refusal above)"
for CWD in "$PROJ" "$GPROJ"; do
  while IFS='|' read -r desc cmd; do
    [ -z "$desc" ] && continue
    RC=$(run "$CWD" "$cmd")
    [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC) in $(basename "$CWD"): $cmd"
  done <<'EOF'
deleting your own merged branch, partially qualified|git push origin :heads/feature/x
the delete switch on your own branch|git push --delete origin heads/experiment
the short delete switch on your own branch|git push -d origin heads/experiment
deleting a branch merely named after main, partially qualified|git push origin :heads/main-backup
an ordinary push to the same ref, no force|git push origin heads/main
deleting a tag under its short spelling|git push origin :tags/v1.2.0
a hard reset onto your own branch, partially qualified|git reset --hard heads/my-branch
a hard reset onto a local ref one commit back|git reset --hard HEAD~1
the spelling as a commit message|git commit -m "git push origin :heads/main is how you delete it"
EOF
done

echo "partial-ref: allowed by the compiled floor (no guard.json)"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  RC=$(run "$PROJ" "$cmd")
  [ "$RC" = "0" ] && pass "allowed: $desc" || fail "WRONGLY refused ($RC): $cmd"
done <<'EOF'
force-pushing your own branch, partially qualified|git push --force origin heads/my-branch
the lease, which is the safe form|git push --force-with-lease origin heads/main
a branch merely named after main|git push --force origin heads/main-backup
a branch whose name ends in main|git push --force origin heads/not-main
a tag namespace that only ENDS in main|git push --force origin main:tags/main
a branch literally named origin/main, created not rewritten|git push --force origin refs/heads/origin/main
the same branch, partially qualified|git push --force origin heads/origin/main
deleting that branch, whose name is not main|git push origin :refs/heads/origin/main
the spelling as prose in an echo|echo "never run git push --force origin heads/main"
EOF

# 3b. the four cases the guarded project refuses are refused by ITS rule, by id
echo "partial-ref: what the guarded project refuses there, it refuses with its own regex"
while IFS='|' read -r desc cmd; do
  [ -z "$desc" ] && continue
  case "$(detail "$GPROJ" "$cmd")" in
    *no-force-push-main*) pass "the project's own deny rule, not this law: $desc" ;;
    *) fail "expected the project's no-force-push-main to be the refuser: $cmd" ;;
  esac
done <<'EOF'
the lease, caught by --force inside --force-with-lease|git push --force-with-lease origin heads/main
a branch named after main, caught by the regex word boundary|git push --force origin heads/main-backup
a tag namespace ending in main|git push --force origin main:tags/main
a branch literally named origin/main|git push --force origin refs/heads/origin/main
EOF

# a heredoc BODY carries the spelling as data. It needs a real newline, so it
# cannot ride in the table above.
RC=$(run "$PROJ" "$(printf 'cat >> notes.md <<%sEOT%s\nnever run git push origin :heads/main\nEOT\n' "'" "'")")
[ "$RC" = "0" ] && pass "allowed: the spelling inside a heredoc body" || fail "WRONGLY refused ($RC): heredoc body"

# ---------------------------------------------------------------------------
# 4. the refusal names the branch git would have written, not the words typed
# ---------------------------------------------------------------------------
echo "partial-ref: the refusal names the right law and the right branch"
OUT=$(detail "$PROJ" "git push origin :heads/main")
case "$OUT" in
  *baseline-branch-delete*) pass "the delete spelling carries the branch-delete law's id" ;;
  *) fail "wrong or missing rule id in: $(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-160)" ;;
esac
case "$OUT" in
  *"'main'"*) pass "the refusal prints the branch as 'main', not as 'heads/main'" ;;
  *) fail "the refusal does not name main: $(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-160)" ;;
esac
OUTF=$(detail "$PROJ" "git push --force origin heads/main")
case "$OUTF" in
  *baseline-force-push*) pass "the force spelling carries the force-push law's id" ;;
  *) fail "wrong or missing rule id in: $(printf '%s' "$OUTF" | tr '\n' ' ' | cut -c1-160)" ;;
esac
OUTR=$(detail "$PROJ" "git reset --hard heads/main")
case "$OUTR" in
  *baseline-hard-reset*) pass "the reset spelling carries the hard-reset law's id" ;;
  *) fail "wrong or missing rule id in: $(printf '%s' "$OUTR" | tr '\n' ' ' | cut -c1-160)" ;;
esac

# ---------------------------------------------------------------------------
# 5. the three laws stay three switches under this spelling too
# ---------------------------------------------------------------------------
echo "partial-ref: disabled[] by id, one law at a time"
DPROJ="$LAB/disabled-delete"; mkdir -p "$DPROJ/.git" "$DPROJ/.rabadon"
printf 'ref: refs/heads/main\n' > "$DPROJ/.git/HEAD"
printf '{ "project": "d", "disabled": ["baseline-branch-delete"] }\n' > "$DPROJ/.rabadon/guard.json"
RC=$(run "$DPROJ" "git push origin :heads/main")
[ "$RC" = "0" ] && pass "disabled[]: the delete law is silenced by id under this spelling too" || fail "silenced delete: rc=$RC"
RC=$(run "$DPROJ" "git push --force origin heads/main")
[ "$RC" = "2" ] && pass "silencing the delete law leaves the force-push law standing" || fail "force-push went quiet too: rc=$RC"

# ---------------------------------------------------------------------------
# 6. judging is not running
# ---------------------------------------------------------------------------
[ -f "$CANARY" ] && [ "$(cat "$CANARY")" = "do not lose me" ] \
  && pass "canary in \$HOME intact: judging a push is not performing one" \
  || fail "canary in \$HOME lost or changed"
[ "$(git -C "$REMOTE" rev-parse refs/heads/main)" = "$REM_MAIN_BEFORE" ] \
  && pass "the lab remote's main never moved" || fail "the lab remote's main moved"
git -C "$REMOTE" rev-parse -q --verify refs/heads/feature >/dev/null \
  && pass "the lab remote's feature branch is still there" || fail "the lab remote lost a branch"

echo "partial ref: $ok ok, $bad fail"
[ $bad -eq 0 ]
