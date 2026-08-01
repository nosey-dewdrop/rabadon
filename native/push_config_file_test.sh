#!/bin/bash
# push_config_file_test.sh — the push refspec git reads from a FILE.
#
# THE HOLE. The force-push law learned to read `remote.<name>.push` and
# `push.default`, and it read them from ONE place: the `-c key=value` pairs on
# the command line. baseline.h said so out loud:
#
#   NAMED LIMIT: the same two keys can also be set in .git/config,
#   ~/.gitconfig or /etc/gitconfig, and none of those are in this command
#   line. This law judges what the LINE says.
#
# The reason given for the limit was that reading only the repo's file would
# report the other two as absent. That is an argument for reading all three, not
# for reading none. Two ordinary commands, one turn apart, and the fallback the
# law depends on answers the wrong question:
#
#   git config remote.origin.push refs/heads/scratch:refs/heads/main
#   git push --force origin
#
# Measured against THIS gate before the fix, from a repo sitting on `scratch`:
# both lines exit 0. The second one force-updates main. The `push.default
# matching` spelling of the same two commands also exits 0.
#
# WHAT REAL GIT DOES. Measured against git 2.39.5 with `push --dry-run
# --porcelain --force`, in a scratch repo whose remote is a bare repo in the
# same mktemp root, HEAD on `feat`, main rewritten so it is a real
# non-fast-forward. Each line is the reason a case below expects what it
# expects:
#
#   .git/config remote.origin.push=<feat>:<main>   feat -> main. The file
#                                                  supplies the refspec, HEAD is
#                                                  never asked.
#   .git/config push.default=matching              + main -> main (forced).
#   ~/.gitconfig remote.origin.push=<feat>:<main>  feat -> main. The global file
#                                                  decides too.
#   global AND repo both set remote.origin.push    BOTH refspecs are pushed. The
#                                                  key ACCUMULATES across files;
#                                                  a reader that let the repo
#                                                  file replace the global one
#                                                  would have read half of it.
#   -c ...=<feat>:<topic> over a file <feat>:<main>  BOTH are pushed. The command
#                                                  line accumulates with the
#                                                  files as well, so reading the
#                                                  line ALONE read the harmless
#                                                  half of that pair.
#   push.default: global=matching, repo=simple     NOT matching. push.default is
#                                                  single-valued and the repo
#                                                  file wins, so the last value
#                                                  in git's file order is the
#                                                  answer, not any value.
#   [remote.ORIGIN] push = ...                     USED for origin. In a FILE the
#                                                  deprecated dotted section form
#                                                  lower-cases the subsection —
#                                                  the opposite of `-c
#                                                  remote.ORIGIN.push`, which is
#                                                  a different remote (measured
#                                                  in push_refspec_test.sh).
#   a `#` before push = ...                        not a value.
#   [include] path = <file with the refspec>       feat -> main. git splices the
#                                                  included file in place.
#   [includeIf "gitdir:/"] path = <same>           feat -> main.
#   [includeIf "gitdir:/nowhere/"] path = <same>   NOT applied.
#   .git/config.worktree with the refspec          feat -> main, but ONLY with
#                                                  extensions.worktreeConfig set;
#                                                  without it the file is ignored.
#   remote.pushDefault=backup                      the refspec read is
#                                                  remote.backup.push.
#   branch.<cur>.remote=backup                     same, one rank lower:
#                                                  pushRemote beats pushDefault
#                                                  beats branch.<cur>.remote.
#
# ONE THING IS DELIBERATELY OVER-REFUSED, AND IT IS THE `includeIf` CONDITION.
# Evaluating `gitdir:`/`onbranch:` needs a wildmatch this repo does not have, and
# it will not grow a second glob engine for it. So an includeIf is FOLLOWED and
# its condition is not evaluated: a conditional include that binds a push
# refspec onto a shared branch is refused even when its condition is false. The
# twin below fixes the price of that choice — an includeIf carrying an ordinary
# identity refuses nothing, which is what every real one carries.
#
# WHAT IS STILL NOT READ, NAMED AND NOT GUESSED AT: the process environment.
# `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n` bind config from the environment, and an
# env prefix on the command itself (`GIT_CONFIG_GLOBAL=x git push ...`) rebinds
# which files git reads. The gate's own environment IS consulted for
# GIT_CONFIG_SYSTEM/GIT_CONFIG_GLOBAL/XDG_CONFIG_HOME/HOME, because that is the
# environment the shell running the command inherits — a per-command prefix is
# not, and is the next thing to close.
#
# NOTHING HERE IS EXECUTED, AND THE SETUP ASSUMES THE OPPOSITE.
# Every must-block case below is a real force-push. The run is built so that a
# TOTAL failure of the gate — every case allowed, and something then running
# them — still costs nothing:
#   * PATH is prefixed with a shim dir holding fake `git` and `rm`. They run
#     nothing, append their argv to a log, and exit 111. The log is asserted
#     EMPTY at the end, which is the proof that judging is not running.
#   * the repos under judgement are mktemp'd and have NO REMOTE, asserted at the
#     end with the real git, so a force-push has nowhere to land.
#   * HOME is redirected into the same mktemp root and a canary file is written
#     inside it, then read back at the end. The global-config cases WRITE to that
#     redirected HOME, so a machine's real ~/.gitconfig is never touched.
#   * the "system" layer is a file in the same mktemp root, named by
#     GIT_CONFIG_SYSTEM. Nothing here writes to /etc.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
CXX="${CXX:-clang++}"
[ -x "$GATE" ] || { echo "push_config_file_test: build first (make)"; exit 1; }

FAIL=0
PASSN=0
pass() { PASSN=$((PASSN+1)); echo "  ok   $1"; }
bad()  { FAIL=1; echo "  FAIL $1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbpushcfg.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# ---- the blast shield ------------------------------------------------------
SHIM="$ROOT/shim"; mkdir -p "$SHIM"
RANLOG="$ROOT/ran.log"
: > "$RANLOG"
for TOOL in git rm; do
  cat > "$SHIM/$TOOL" <<SH
#!/bin/sh
printf '%s %s\n' "$TOOL" "\$*" >> "$RANLOG"
exit 111
SH
  chmod +x "$SHIM/$TOOL"
done

# built with the REAL git, before the shim goes on PATH; the real paths are kept
# so the canary checks at the end are not answered by the shim, and so this
# file's OWN housekeeping never touches the shim — the shim's log is evidence
# about the gate, and a test that swept its own scratch through it would be
# answering that question with its own noise.
REALGIT="$(command -v git)"
REALRM="$(command -v rm)"

# Two repos that differ ONLY in which branch is checked out. Every must-block
# case is judged in both, because the bug is that the verdict came from HEAD.
mkrepo() { # mkrepo <dir> <branch-to-sit-on>
  "$REALGIT" init -q "$1"
  "$REALGIT" -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
  "$REALGIT" -C "$1" branch -M main
  if [ "$2" != "main" ]; then "$REALGIT" -C "$1" checkout -q -b "$2"; fi
  cp "$1/.git/config" "$1/.git/config.base"   # the pristine file, restored per case
  # no `git remote add` anywhere in this file, on purpose.
}
ON_MAIN="$ROOT/on-main"; mkrepo "$ON_MAIN" main
ON_FEAT="$ROOT/on-feat"; mkrepo "$ON_FEAT" feat
MAIN_HEAD="$("$REALGIT" -C "$ON_MAIN" rev-parse HEAD)"
FEAT_HEAD="$("$REALGIT" -C "$ON_FEAT" rev-parse HEAD)"

# A LINKED WORKTREE, where the repo's config is not where the repo is. Its .git
# is a FILE pointing at .git/worktrees/<name>, and that directory holds only the
# worktree's own config — the shared one is reached through the `commondir`
# pointer beside it. A reader that stopped at <gitdir>/config would find nothing
# here and fall straight back to HEAD, which is the bug this file is about, one
# directory over. The branch checked out here is `linked`, so the fallback
# ALLOWS and only the config can refuse.
WT="$ROOT/linked"
WT_OK=1
"$REALGIT" -C "$ON_MAIN" worktree add -q -b linked "$WT" >/dev/null 2>&1 || WT_OK=0

export HOME="$ROOT/home"
mkdir -p "$HOME/Documents"
echo "do not lose me" > "$HOME/Documents/canary.txt"
export XDG_CONFIG_HOME="$ROOT/xdg"
export GIT_CONFIG_SYSTEM="$ROOT/etc-gitconfig"
export RABADON_DIR="$ROOT/rhome"; mkdir -p "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"
export RABADON_NOTIFY=0
export PATH="$SHIM:$PATH"

# every judgement gets its own session id. the gate refuses the SAME command a
# third time in one session (loop-stop), which would answer these cases with the
# wrong rule.
SEQ="$ROOT/seq"; echo 0 > "$SEQ"
sid() { local n; n=$(( $(cat "$SEQ") + 1 )); echo "$n" > "$SEQ"; echo "pcfg$n"; }

judge() { # judge <cwd> <command> -> exit code
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(sid)" "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
why() { # why <cwd> <command> -> the refusal text, for eyeballing
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(sid)" "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" 2>&1 | tr '\n' ' '
}

# ---- where a config value is put -------------------------------------------
# Every layer git reads, written as the file git would read it from. The repo
# file is restored from its pristine copy first, so no case inherits another's.
put() { # put <layer> <printf-body>
  local layer="$1" body="${2:-}" r
  for r in "$ON_MAIN" "$ON_FEAT"; do
    cp "$r/.git/config.base" "$r/.git/config"
    "$REALRM" -f "$r/.git/config.worktree"
  done
  "$REALRM" -f "$HOME/.gitconfig" "$XDG_CONFIG_HOME/git/config" "$GIT_CONFIG_SYSTEM" "$ROOT/inc.cfg"
  case "$layer" in
    none)   : ;;
    repo)   for r in "$ON_MAIN" "$ON_FEAT"; do printf '%b' "$body" >> "$r/.git/config"; done ;;
    global) printf '%b' "$body" > "$HOME/.gitconfig" ;;
    xdg)    mkdir -p "$XDG_CONFIG_HOME/git"; printf '%b' "$body" > "$XDG_CONFIG_HOME/git/config" ;;
    system) printf '%b' "$body" > "$GIT_CONFIG_SYSTEM" ;;
    worktree)
      for r in "$ON_MAIN" "$ON_FEAT"; do
        printf '[extensions]\n\tworktreeConfig = true\n' >> "$r/.git/config"
        printf '%b' "$body" > "$r/.git/config.worktree"
      done ;;
    worktree-no-ext)   # the same file with the extension NOT set: git ignores it
      for r in "$ON_MAIN" "$ON_FEAT"; do printf '%b' "$body" > "$r/.git/config.worktree"; done ;;
    include)
      printf '%b' "$body" > "$ROOT/inc.cfg"
      for r in "$ON_MAIN" "$ON_FEAT"; do
        printf '[include]\n\tpath = %s\n' "$ROOT/inc.cfg" >> "$r/.git/config"; done ;;
    includeif)
      printf '%b' "$body" > "$ROOT/inc.cfg"
      for r in "$ON_MAIN" "$ON_FEAT"; do
        printf '[includeIf "gitdir:/"]\n\tpath = %s\n' "$ROOT/inc.cfg" >> "$r/.git/config"; done ;;
    *) bad "put: unknown layer $layer" ;;
  esac
}

blocks_any_head() { # blocks_any_head NAME LAYER BODY CMD
  put "$2" "$3"
  local a b
  a="$(judge "$ON_MAIN" "$4")"
  b="$(judge "$ON_FEAT" "$4")"
  if [ "$a" = "2" ] && [ "$b" = "2" ]; then pass "$1"
  elif [ "$a" = "2" ]; then bad "$1: refused on main, ALLOWED on a feature branch — HEAD decided, and the file was not read"
  elif [ "$b" = "2" ]; then bad "$1: refused on a feature branch, allowed on main"
  else bad "$1: allowed from both heads (exit $a/$b)"; fi
}
blocks_on_feat() { # blocks_on_feat NAME LAYER BODY CMD
  put "$2" "$3"
  local b; b="$(judge "$ON_FEAT" "$4")"
  if [ "$b" = "2" ]; then pass "$1"; else bad "$1: allowed (exit $b)"; fi
}
allows_on_feat() { # allows_on_feat NAME LAYER BODY CMD
  put "$2" "$3"
  local b; b="$(judge "$ON_FEAT" "$4")"
  if [ "$b" != "2" ]; then pass "$1"
  else bad "$1: refused, and refusing it cuts real work: $(why "$ON_FEAT" "$4")"; fi
}
blocks_on_main() { # blocks_on_main NAME LAYER BODY CMD
  put "$2" "$3"
  local a; a="$(judge "$ON_MAIN" "$4")"
  if [ "$a" = "2" ]; then pass "$1"; else bad "$1: allowed (exit $a)"; fi
}

R2M='refs/heads/x:refs/heads/main'
R2T='refs/heads/x:refs/heads/topic'

# ---------------------------------------------------------------------------
# unit: the ONE reader, asked what git will see for a key in this repo
# ---------------------------------------------------------------------------
cat > "$ROOT/probe.cpp" <<'CPP'
#include <cstdio>
#include <iostream>
#include <string>
#include <vector>
#include "gitcfg.h"
// argv[1] is the GIT DIR (what pathres.h resolves for the line), argv[2] the key.
int main(int argc, char** argv) {
  if (argc < 3) return 2;
  std::string cmd((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
  while (!cmd.empty() && cmd[cmd.size()-1] == '\n') cmd.erase(cmd.size()-1);
  rbtext::Parsed p = rbtext::parse(cmd);
  if (p.degraded) { printf("DEGRADED\n"); return 0; }
  for (size_t i = 0; i < p.segs.size(); i++) {
    const std::vector<rbtext::Word>& t = p.segs[i].words;
    const size_t ci = rbtext::command_index(t);
    if (ci >= t.size() || !rbtext::name_is(rbtext::base_of(t[ci].text), "git")) continue;
    size_t sub = 0;
    if (!rbtext::git_subcommand(t, ci, sub)) continue;
    std::vector<rbgitcfg::Value> vals;
    rbgitcfg::values(t, ci, sub, argv[1], argv[2], vals);
    printf("values=%zu", vals.size());
    for (size_t k = 0; k < vals.size(); k++) printf(" [%s]", vals[k].text.c_str());
    printf("\n");
  }
  return 0;
}
CPP
UNIT_OK=1
"$CXX" -std=c++17 -O1 -Wall -Wextra -I "$HERE" -o "$ROOT/probe" "$ROOT/probe.cpp" 2>"$ROOT/cc.log" || UNIT_OK=0

u_cfg() { # u_cfg NAME LAYER BODY KEY CMD EXPECTED
  put "$2" "$3"
  if [ "$UNIT_OK" = "0" ]; then bad "$1: probe did not compile"; return; fi
  local out; out="$(printf '%s' "$5" | "$ROOT/probe" "$ON_FEAT/.git" "$4")"
  if [ "$out" = "$6" ]; then pass "$1"; else bad "$1: got <$out>, want <$6>"; fi
}

echo "== unit: the value git will see, from the files and then the line =="
if [ "$UNIT_OK" = "0" ]; then
  echo "  (probe did not compile)"; sed -n '1,12p' "$ROOT/cc.log" | sed 's/^/         /'
fi
u_cfg "the repo file is read" repo "[remote \"origin\"]\n\tpush = $R2M\n" \
  "remote.origin.push" "git push --force origin" "values=1 [$R2M]"
u_cfg "the global file is read" global "[remote \"origin\"]\n\tpush = $R2M\n" \
  "remote.origin.push" "git push --force origin" "values=1 [$R2M]"
u_cfg "section and variable fold in a file" repo "[REMOTE \"origin\"]\n\tPUSH = $R2M\n" \
  "remote.origin.push" "git push --force origin" "values=1 [$R2M]"
u_cfg "a quoted subsection keeps its case" repo "[remote \"ORIGIN\"]\n\tpush = $R2M\n" \
  "remote.origin.push" "git push --force origin" "values=0"
u_cfg "the dotted section form folds the subsection" repo "[remote.ORIGIN]\n\tpush = $R2M\n" \
  "remote.origin.push" "git push --force origin" "values=1 [$R2M]"
u_cfg "a commented line is not a value" repo "[remote \"origin\"]\n\t# push = $R2M\n\t; push = $R2M\n" \
  "remote.origin.push" "git push --force origin" "values=0"
u_cfg "a trailing comment is cut off the value" repo "[remote \"origin\"]\n\tpush = $R2M # why\n" \
  "remote.origin.push" "git push --force origin" "values=1 [$R2M]"
u_cfg "a quoted value keeps what is inside it" repo "[remote \"origin\"]\n\tpush = \"$R2M\"\n" \
  "remote.origin.push" "git push --force origin" "values=1 [$R2M]"
u_cfg "a # inside quotes is not a comment" repo "[remote \"origin\"]\n\tpush = \"refs/heads/x:refs/heads/ma#in\"\n" \
  "remote.origin.push" "git push --force origin" "values=1 [refs/heads/x:refs/heads/ma#in]"
# measured both ways, because the indent is part of the value: with the
# continuation line indented, real git answers `refs/heads/x: refs/heads/main` —
# the tab became ONE space — and flush against the margin it answers the joined
# string. A reader that copied the tab through, or dropped it, would answer a
# different destination than git for the same file.
u_cfg "a continued line, indented, keeps one space" repo "[remote \"origin\"]\n\tpush = refs/heads/x:\\\\\n\trefs/heads/main\n" \
  "remote.origin.push" "git push --force origin" "values=1 [refs/heads/x: refs/heads/main]"
u_cfg "a continued line, flush, is one value" repo "[remote \"origin\"]\n\tpush = refs/heads/x:\\\\\nrefs/heads/main\n" \
  "remote.origin.push" "git push --force origin" "values=1 [refs/heads/x:refs/heads/main]"
u_cfg "the file value and the -c value accumulate" repo "[remote \"origin\"]\n\tpush = $R2M\n" \
  "remote.origin.push" "git -c remote.origin.push=$R2T push --force origin" \
  "values=2 [$R2M] [$R2T]"
u_cfg "the key is multi-valued inside one file" repo "[remote \"origin\"]\n\tpush = $R2T\n\tpush = $R2M\n" \
  "remote.origin.push" "git push --force origin" "values=2 [$R2T] [$R2M]"
u_cfg "an included file is read in place" include "[remote \"origin\"]\n\tpush = $R2M\n" \
  "remote.origin.push" "git push --force origin" "values=1 [$R2M]"
u_cfg "a variable outside the section is not it" repo "[notremote \"origin\"]\n\tpush = $R2M\n" \
  "remote.origin.push" "git push --force origin" "values=0"
u_cfg "a bare key is true" repo "[extensions]\n\tworktreeConfig\n" \
  "extensions.worktreeConfig" "git push --force origin" "values=1 [true]"

# push.default is single-valued: git's file order decides, and the answer is the
# LAST value, not any value. Measured: global=matching + repo=simple -> not
# matching.
echo
echo "== unit: single-valued push.default, in git's file order =="
put none
printf '[push]\n\tdefault = matching\n' > "$HOME/.gitconfig"
printf '[push]\n\tdefault = simple\n' >> "$ON_FEAT/.git/config"
if [ "$UNIT_OK" = "0" ]; then bad "push.default order: probe did not compile"; else
  OUT="$(printf 'git push --force origin' | "$ROOT/probe" "$ON_FEAT/.git" "push.default")"
  [ "$OUT" = "values=2 [matching] [simple]" ] \
    && pass "global then repo, in that order — the repo file is last and wins" \
    || bad "push.default order: got <$OUT>, want <values=2 [matching] [simple]>"
fi

# ---------------------------------------------------------------------------
# e2e: the real binary
# ---------------------------------------------------------------------------
echo
echo "== e2e: the reported escape — two ordinary commands, one turn apart =="
blocks_any_head "repo config names the refspec" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "git push --force origin"
blocks_any_head "repo config, no remote operand" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "git push --force"
blocks_any_head "repo config, -f short form" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "git push -f origin"
blocks_any_head "repo config push.default=matching" \
  repo "[push]\n\tdefault = matching\n" "git push --force origin"
blocks_any_head "repo config, key folded in the file" \
  repo "[REMOTE \"origin\"]\n\tPUSH = $R2M\n" "git push --force origin"
blocks_any_head "repo config, dotted section form" \
  repo "[remote.ORIGIN]\n\tpush = $R2M\n" "git push --force origin"
blocks_any_head "repo config, second value is the dangerous one" \
  repo "[remote \"origin\"]\n\tpush = $R2T\n\tpush = $R2M\n" "git push --force origin"
blocks_any_head "the line's -c does not hide the file's value" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "git -c remote.origin.push=$R2T push --force origin"

echo
echo "== e2e: every file git reads, not just the repo's =="
blocks_any_head "~/.gitconfig names the refspec" \
  global "[remote \"origin\"]\n\tpush = $R2M\n" "git push --force origin"
blocks_any_head "~/.gitconfig push.default=matching" \
  global "[push]\n\tdefault = matching\n" "git push --force origin"
blocks_any_head "the XDG file names the refspec" \
  xdg "[remote \"origin\"]\n\tpush = $R2M\n" "git push --force origin"
blocks_any_head "the system file names the refspec" \
  system "[remote \"origin\"]\n\tpush = $R2M\n" "git push --force origin"
blocks_any_head "an include splices it in" \
  include "[remote \"origin\"]\n\tpush = $R2M\n" "git push --force origin"
blocks_any_head "an includeIf splices it in" \
  includeif "[remote \"origin\"]\n\tpush = $R2M\n" "git push --force origin"
blocks_any_head "the worktree file, with the extension" \
  worktree "[remote \"origin\"]\n\tpush = $R2M\n" "git push --force origin"

echo
echo "== e2e: which remote a push with no operand is pushing to =="
blocks_any_head "remote.pushDefault picks the remote" \
  repo "[remote \"backup\"]\n\tpush = $R2M\n[remote]\n\tpushDefault = backup\n" "git push --force"
blocks_on_feat "branch.<cur>.remote picks the remote" \
  repo "[remote \"backup\"]\n\tpush = $R2M\n[branch \"feat\"]\n\tremote = backup\n" "git push --force"
blocks_on_feat "branch.<cur>.pushRemote outranks pushDefault" \
  repo "[remote \"backup\"]\n\tpush = $R2M\n[remote \"safe\"]\n\tpush = $R2T\n[remote]\n\tpushDefault = safe\n[branch \"feat\"]\n\tpushRemote = backup\n" \
  "git push --force"

echo
echo "== e2e: the same escapes through the layers the parser already flattens =="
blocks_any_head "config refspec inside sh -lc" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "sh -lc 'git push --force origin'"
blocks_any_head "config refspec behind a git alias" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "git -c alias.x='push --force' x origin"
blocks_any_head "config refspec after &&" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "npm test && git push --force origin"

echo
echo "== e2e: the legitimate twin of every case above still runs =="
allows_on_feat "a config refspec onto a topic branch" \
  repo "[remote \"origin\"]\n\tpush = $R2T\n" "git push --force origin"
allows_on_feat "the same refspec with no --force" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "git push origin"
allows_on_feat "the same refspec with a lease" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "git push --force-with-lease origin"
allows_on_feat "push.default=matching with no --force" \
  repo "[push]\n\tdefault = matching\n" "git push origin"
allows_on_feat "a quoted subsection is case-sensitive" \
  repo "[remote \"ORIGIN\"]\n\tpush = $R2M\n" "git push --force origin"
allows_on_feat "a config for another remote" \
  repo "[remote \"backup\"]\n\tpush = $R2M\n" "git push --force origin"
allows_on_feat "a commented-out refspec is not a refspec" \
  repo "[remote \"origin\"]\n\t# push = $R2M\n" "git push --force origin"
allows_on_feat "a push variable in another section" \
  repo "[notremote \"origin\"]\n\tpush = $R2M\n" "git push --force origin"
allows_on_feat "the worktree file without the extension" \
  worktree-no-ext "[remote \"origin\"]\n\tpush = $R2M\n" "git push --force origin"
allows_on_feat "an includeIf carrying an identity" \
  includeif "[user]\n\temail = me@example.com\n" "git push --force origin"
allows_on_feat "pushDefault to a remote whose refspec is a topic" \
  repo "[remote \"backup\"]\n\tpush = $R2T\n[remote]\n\tpushDefault = backup\n" "git push --force"
allows_on_feat "writing the config is not pushing it" \
  none "" "git config remote.origin.push $R2M"
allows_on_feat "reading the config back" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "git config --get remote.origin.push"
allows_on_feat "an ordinary push with the file in place" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "git push origin feature/mine"
allows_on_feat "a force-push of her own branch, spelled out" \
  repo "[remote \"origin\"]\n\tpush = $R2T\n" "git push --force origin feature/mine"
allows_on_feat "a delete of the project's own build output" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "rm -rf node_modules"
allows_on_feat "the words in a commit message" \
  repo "[remote \"origin\"]\n\tpush = $R2M\n" "git commit -m 'git push --force origin was the bypass'"

echo
echo "== e2e: a file that does NOT supply a refspec still falls back to HEAD =="
blocks_on_main "push.default=simple, on main"  repo "[push]\n\tdefault = simple\n"  "git push --force origin"
allows_on_feat "push.default=simple, on feat"  repo "[push]\n\tdefault = simple\n"  "git push --force origin"
blocks_on_main "push.default=current, on main" repo "[push]\n\tdefault = current\n" "git push --force origin"
allows_on_feat "push.default=current, on feat" repo "[push]\n\tdefault = current\n" "git push --force origin"
put none
printf '[push]\n\tdefault = matching\n' > "$HOME/.gitconfig"
for r in "$ON_MAIN" "$ON_FEAT"; do printf '[push]\n\tdefault = simple\n' >> "$r/.git/config"; done
GOT="$(judge "$ON_FEAT" "git push --force origin")"
[ "$GOT" != "2" ] \
  && pass "repo=simple beats global=matching, on feat — the LAST value decides, not any value" \
  || bad "repo=simple beats global=matching: refused on feat, so a global value overrode the repo's"

echo
echo "== e2e: a linked worktree, whose config is not where its .git is =="
if [ "$WT_OK" = "0" ]; then
  bad "the linked worktree could not be created, so the commondir path is unproven"
else
  put repo "[remote \"origin\"]\n\tpush = $R2M\n"
  GOT="$(judge "$WT" "git push --force origin")"
  [ "$GOT" = "2" ] && pass "the shared config decides a push judged from a worktree" \
    || bad "worktree: allowed (exit $GOT) — <gitdir>/config is not where the shared file is"
  MSG="$(why "$WT" "git push --force origin")"
  case "$MSG" in
    *"shared branch 'main'"*) pass "and it still names the branch, from the worktree" ;;
    *) bad "worktree refusal does not name the branch: $MSG" ;;
  esac
  put none
  GOT="$(judge "$WT" "git push --force origin")"
  [ "$GOT" != "2" ] && pass "with no config, the worktree's own branch is hers to force" \
    || bad "worktree: refused with no config, and refusing it cuts real work"
fi

echo
echo "== e2e: an empty or absent file is not a value =="
allows_on_feat "no config anywhere"        none "" "git push --force origin"
allows_on_feat "an empty repo config body" repo "\n\n" "git push --force origin"
allows_on_feat "a section with no variable" repo "[remote \"origin\"]\n" "git push --force origin"

echo
echo "== e2e: the plain spellings did not stop working =="
put none
GOT="$(judge "$ON_FEAT" "git push --force origin main")"
[ "$GOT" = "2" ] && pass "plain force-push" || bad "plain force-push: allowed"
GOT="$(judge "$ON_FEAT" "git push origin +main")"
[ "$GOT" = "2" ] && pass "the + refspec" || bad "the + refspec: allowed"
GOT="$(judge "$ON_MAIN" "git push --force origin")"
[ "$GOT" = "2" ] && pass "force-push from main" || bad "force-push from main: allowed"
GOT="$(judge "$ON_FEAT" "git push --force origin")"
[ "$GOT" != "2" ] && pass "force-push of a feature branch" || bad "force-push of a feature branch: refused"

# ---------------------------------------------------------------------------
# the refusal has to say WHERE the value came from
# ---------------------------------------------------------------------------
echo
echo "== the message names the file, not just the branch =="
put repo "[remote \"origin\"]\n\tpush = $R2M\n"
MSG="$(why "$ON_FEAT" "git push --force origin")"
case "$MSG" in
  *"remote.origin.push"*".git/config"*) pass "the refusal names the key and the file it was read from" ;;
  *) bad "the refusal does not name where the refspec came from: $MSG" ;;
esac
put global "[push]\n\tdefault = matching\n"
MSG="$(why "$ON_FEAT" "git push --force origin")"
case "$MSG" in
  *"push.default"*"gitconfig"*) pass "the matching refusal names push.default and the file" ;;
  *) bad "the matching refusal does not name where it came from: $MSG" ;;
esac

# ---------------------------------------------------------------------------
# judging is not running
# ---------------------------------------------------------------------------
echo
echo "== canaries =="
if [ -s "$RANLOG" ]; then
  bad "something EXECUTED while being judged:"; sed 's/^/         /' "$RANLOG"
else
  pass "the fake git/rm on PATH were never called (judging is not running)"
fi
[ "$(cat "$HOME/Documents/canary.txt" 2>/dev/null)" = "do not lose me" ] \
  && pass "the redirected HOME still holds its canary file" \
  || bad "the canary under HOME was touched"
[ "$("$REALGIT" -C "$ON_MAIN" rev-parse HEAD 2>/dev/null)" = "$MAIN_HEAD" ] \
  && [ "$("$REALGIT" -C "$ON_FEAT" rev-parse HEAD 2>/dev/null)" = "$FEAT_HEAD" ] \
  && pass "both judged repos still point at the same commit" \
  || bad "a judged repo moved"
[ -z "$("$REALGIT" -C "$ON_MAIN" remote 2>/dev/null)$("$REALGIT" -C "$ON_FEAT" remote 2>/dev/null)" ] \
  && pass "neither judged repo ever had a remote to force-push to" \
  || bad "a judged repo grew a remote"

echo
if [ "$FAIL" = "0" ]; then echo "PASS ($PASSN checks)"; else echo "FAIL ($PASSN checks passed)"; fi
exit $FAIL
