#!/usr/bin/env bash
# probe-exec.sh — F3i's measuring stick. Same sandbox as f3h/probe.sh (a project
# under $HOME, NOT under a machine temp root, and an EMPTY bash[] so the answer
# is about the compiled binary and never about a regex in a JSON file), with one
# addition that changes what the number means: after the verdict is read, the
# shape is actually RUN in a fresh copy of the sandbox and the law is looked for.
#
# A shape that is ALLOWed but leaves .rabadon/guard.json where it was is not a
# hole. A shape that is ALLOWed and leaves the law GONE is the class this
# product has to name on its own screen. Two columns, one line per shape:
#
#   ALLOW   GONE    ls -a | xargs rm -rf
#   ALLOW   THERE   ls | xargs rm -rf
#
# Every sandbox project is literally named `proj`, so `cd .. && rm -rf proj` is
# spelled the way an agent would spell it rather than through a substitution the
# gate is documented not to guess at.
#
# usage:  bash reports/kosu/kanit/f3i/probe-exec.sh <<'EOF'
#         ls -a | xargs rm -rf
#         EOF
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
GATE="${RABADON_GATE:-$ROOT/native/rabadon-gate}"
[ -x "$GATE" ] || { echo "build first: make" >&2; exit 1; }

T="$(mktemp -d "$HOME/.rb-f3i-probe.XXXXXX")"
cleanup() { chmod -R u+rwX "$T" 2>/dev/null; /bin/rm -rf "$T"; }
trap cleanup EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"

mkproj() { # mkproj <dir>
  rm -rf "$1"; mkdir -p "$1/.rabadon" "$1/.git" "$1/build"
  printf 'ref: refs/heads/main\n' > "$1/.git/HEAD"
  printf '{"project":"probe","bash":[],"protectedPaths":[]}\n' > "$1/.rabadon/guard.json"
  printf '{"promise":"x"}\n' > "$1/.rabadon/promise.json"
  printf 'x\n' > "$1/README.md"; printf 'x\n' > "$1/a.txt"
}

n=0
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  case "$cmd" in \#*) continue ;; esac
  n=$((n+1))
  # --- arm 1: what does the gate say?
  mkdir -p "$T/v$n"; P="$T/v$n/proj"; mkproj "$P"
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"probe","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$P" "$cmd" \
    | env RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
  if [ "$?" = "2" ]; then V=REFUSE; else V="ALLOW "; fi
  # --- arm 2: run it for real, in a copy nobody has judged, and look for the law
  mkdir -p "$T/e$n"; Q="$T/e$n/proj"; mkproj "$Q"
  ( cd "$Q" && eval "$cmd" ) >/dev/null 2>&1
  if [ -s "$Q/.rabadon/guard.json" ]; then E="THERE"; else E="GONE "; fi
  printf '%s  %s  %s\n' "$V" "$E" "$cmd"
done
