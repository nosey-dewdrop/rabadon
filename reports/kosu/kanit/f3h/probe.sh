#!/usr/bin/env bash
# probe.sh — F3h's measuring stick. A project sandbox under $HOME (NOT under a
# machine temp root, where the scope law's carve-out would inflate the reading),
# an EMPTY bash[] so the answer is about the binary and never about a regex in
# a JSON file, and one line of output per shape: REFUSE or ALLOW.
#
#   bash reports/kosu/kanit/f3h/probe.sh <<'EOF'
#   rm -rf .rabadon
#   mkdir -p .rabadon
#   EOF
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
GATE="${RABADON_GATE:-$ROOT/native/rabadon-gate}"
[ -x "$GATE" ] || { echo "build first: make" >&2; exit 1; }

T="$(mktemp -d "$HOME/.rb-f3h-probe.XXXXXX")"
cleanup() { chmod -R u+rwX "$T" 2>/dev/null; /bin/rm -rf "$T"; }
trap cleanup EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"
P="$T/proj"; mkdir -p "$P/.rabadon" "$P/.git" "$P/build" "$P/.rabadonx" "$P/notrabadon"
printf 'ref: refs/heads/main\n' > "$P/.git/HEAD"
printf '{"project":"probe","bash":[],"protectedPaths":[]}\n' > "$P/.rabadon/guard.json"
printf '{"promise":"x"}\n' > "$P/.rabadon/promise.json"
printf 'x\n' > "$P/README.md"; printf 'x\n' > "$P/log.txt"; printf 'x\n' > "$P/a.txt"
: > "$P/.rabadon-backup"
# A leftover project somewhere else on the disk, for the exit-door arm.
L="$T/leftover"; mkdir -p "$L/.rabadon"; printf '{}\n' > "$L/.rabadon/guard.json"
export PROBE_PROJ="$P" PROBE_LEFTOVER="$L"

CWD="${PROBE_CWD:-$P}"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  case "$cmd" in \#*) continue ;; esac
  cmd="${cmd//@P/$P}"; cmd="${cmd//@L/$L}"
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"probe","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$CWD" "$cmd" \
    | env RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
  if [ "$?" = "2" ]; then printf 'REFUSE  %s\n' "$cmd"; else printf 'ALLOW   %s\n' "$cmd"; fi
done
