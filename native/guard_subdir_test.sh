#!/bin/bash
# guard_subdir_test.sh — a project's law has to hold everywhere in the project.
#
# The guard is loaded with read_file(cwd + "/.rabadon/guard.json"): the EXACT
# directory the session is standing in, with no walk toward the project root. A
# session started in the project root gets the project's rules. A session started
# one directory down gets none of them, and the only thing still standing there
# is the law compiled into the binary.
#
# Measured in a real repository on 3 August, from its `engine` subdirectory:
#
#   git add <a copyrighted never-push directory>   ALLOWED   (rule never loaded)
#   git add -A                                     ALLOWED   (rule never loaded)
#   ctest --test-dir build -N                      ALLOWED   (rule never loaded)
#   wrangler deploy                                ALLOWED   (rule never loaded)
#
# Four rules, three of them written by the engine itself after real incidents,
# all of them silently absent one `cd` away from where they were authored. An
# agent working in `src/` is the normal case, not the edge case, so this is the
# ordinary condition rather than a corner of it.
#
# The compiled baseline is unaffected because it resolves paths per segment. The
# guard was the one layer still reading a single directory, and it is the layer
# the operator writes their own rules into.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
[ -x "$GATE" ] || { echo "  build first: make native/rabadon-gate"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# NOT mktemp: /tmp, /var/tmp and /var/folders are exempt from the coverage law by
# design, and a fixture built there measures the carve-out instead of the rule.
T="$(cd "$HERE/.." && pwd)/.subdirtest-$$"
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT

PROJ="$T/proj"
mkdir -p "$PROJ/.git" "$PROJ/.rabadon" "$PROJ/engine/deep/deeper" "$T/rd/spool"
export RABADON_DIR="$T/rd"
: > "$RABADON_DIR/enabled"     # ENFORCE, so a refusal is exit 2

cat > "$PROJ/.rabadon/guard.json" <<'JSON'
{
  "project": "proj",
  "testCommand": "\\bctest\\b",
  "bash": [
    {"id": "no-blanket-add", "deny": "git\\s+add\\s+(-A|--all|\\.)",
     "why": "this repository holds untracked directories that must never be staged wholesale",
     "allow": "git add engine/main.cpp"},
    {"id": "no-deploy-from-here", "deny": "\\bwrangler\\s+deploy\\b",
     "why": "deploys happen from the release workflow and not from a session",
     "allow": "wrangler tail"}
  ],
  "protectedPaths": [
    {"id": "generated-html", "match": "web/.*\\.html$",
     "why": "these files are generated; editing them by hand loses the change on the next build",
     "allow": "web/index.tmpl.html"}
  ]
}
JSON

# one command through the real gate, with the session standing in $1
probe() {
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >"$T/out" 2>"$T/err"
  echo $?
}
probe_write() {
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' \
    "$1" "$2" | "$GATE" >"$T/out" 2>"$T/err"
  echo $?
}

echo "guard reach — a project's law holds in the whole project"
echo

# ---------------------------------------------------------------------------
# 1. the rules hold at the root. this is the part that already worked.
# ---------------------------------------------------------------------------
echo "1. at the project root (this already held)"
for c in "git add -A" "wrangler deploy"; do
  rc=$(probe "$PROJ" "$c")
  if [ "$rc" -ne 0 ]; then ok "refused at root: $c"
  else bad "ALLOWED at root: $c"; fi
done

echo
# ---------------------------------------------------------------------------
# 2. and one directory down, and three down
# ---------------------------------------------------------------------------
echo "2. from a subdirectory, where an agent actually works"
for d in "$PROJ/engine" "$PROJ/engine/deep" "$PROJ/engine/deep/deeper"; do
  short="${d#$PROJ/}"
  for c in "git add -A" "wrangler deploy"; do
    rc=$(probe "$d" "$c")
    if [ "$rc" -ne 0 ]; then ok "refused in $short: $c"
    else bad "ALLOWED in $short: $c  — the project's guard was never loaded"; fi
  done
done

echo
# ---------------------------------------------------------------------------
# 3. protectedPaths too, since it is read from the same file
# ---------------------------------------------------------------------------
echo "3. the file rules travel with it"
rc=$(probe_write "$PROJ/engine" "$PROJ/web/page.html")
if [ "$rc" -ne 0 ]; then ok "refused a generated file from a subdirectory"
else bad "ALLOWED a generated file from a subdirectory"; fi

echo
# ---------------------------------------------------------------------------
# 4. and it must not reach where there is no project
# ---------------------------------------------------------------------------
# Walking up to find a guard is only correct while the walk stops at the project.
# If it climbed past the repository it would apply one project's private rules to
# another project's work, which is a worse failure than the one being fixed.
echo "4. the walk stops at the project"
OUTSIDE="$T/outside"
mkdir -p "$OUTSIDE/.git/refs" "$OUTSIDE/sub"
rc=$(probe "$OUTSIDE/sub" "wrangler deploy")
if [ "$rc" -eq 0 ]; then ok "a different repository does not inherit this project's rules"
else bad "REFUSED in an unrelated repository — the walk climbed past the project root"
     sed -n '1,3p' "$T/err" | sed 's/^/        /'; fi

# and the allow twins still pass everywhere, so the fix did not become a blanket
echo
echo "5. the allow twins still pass, at the root and below"
for d in "$PROJ" "$PROJ/engine/deep"; do
  short="${d#$PROJ}"; short="${short:-/}"
  rc=$(probe "$d" "git add engine/main.cpp")
  if [ "$rc" -eq 0 ]; then ok "honest work still passes in ${short}"
  else bad "the twin was refused in ${short}"; sed -n '1,3p' "$T/err" | sed 's/^/        /'; fi
done

echo
# ---------------------------------------------------------------------------
# 6. a project that is not a git repository
# ---------------------------------------------------------------------------
# The first fix walked up from cwd to project_root(), and project_root() finds
# the nearest ancestor holding `.git` and otherwise falls back to cwd itself. So
# in a directory that is not a git repository the bound and the start were the
# same place and the walk never took a step -- which is exactly the shape of the
# three directories that needed it most on this machine, none of which is its own
# repository. Where there is no git root the walk is bounded by the home
# directory instead, and it still never leaves it.
echo "6. a project that is not a git repository at all"
NOGIT="$T/nogit"
mkdir -p "$NOGIT/.rabadon" "$NOGIT/sub/deeper"
cat > "$NOGIT/.rabadon/guard.json" <<'JSON'
{
  "project": "nogit",
  "bash": [{"id": "nogit-no-deploy", "deny": "\\bwrangler\\s+deploy\\b",
            "why": "deploys do not happen from a session here",
            "allow": "wrangler tail"}]
}
JSON
for d in "$NOGIT" "$NOGIT/sub" "$NOGIT/sub/deeper"; do
  short="${d#$NOGIT}"; short="${short:-/}"
  rc=$(probe "$d" "wrangler deploy")
  if [ "$rc" -ne 0 ]; then ok "refused in ${short} of a non-git project"
  else bad "ALLOWED in ${short} of a non-git project — the walk never started"; fi
done
rc=$(probe "$NOGIT/sub" "wrangler tail")
if [ "$rc" -eq 0 ]; then ok "the twin still passes in a non-git project"
else bad "the twin was refused in a non-git project"; fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
