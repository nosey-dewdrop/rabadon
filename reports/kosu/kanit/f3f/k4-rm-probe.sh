#!/usr/bin/env bash
# why does `rm .rabadon/guard.json` come back ALLOW when `mv` comes back REFUSE?
# nothing here EXECUTES any candidate; each string is only shown to the gate.
set -u
HERE="$(cd "$(dirname "$0")/../../../.." && pwd)"
GATE="$HERE/native/rabadon-gate"
T="$(mktemp -d "${TMPDIR:-/tmp}/rbk4r.XXXXXX")"; trap 'rm -rf "$T"' EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"
P="$T/proj"; mkdir -p "$P/.rabadon" "$P/.git"
printf 'ref: refs/heads/main\n' > "$P/.git/HEAD"
python3 - "$HERE/.rabadon/guard.json" "$P/.rabadon/guard.json" <<'PY'
import json, sys
src = json.load(open(sys.argv[1]))
rule = [r for r in src.get("bash", []) if r.get("id") == "no-shell-rewrite-of-guard-or-promise"]
json.dump({"project": "k4", "bash": rule, "protectedPaths": []}, open(sys.argv[2], "w"), indent=2)
PY
for c in "rm .rabadon/guard.json" "rm -f .rabadon/guard.json" "rm ./.rabadon/guard.json" \
         "/bin/rm .rabadon/guard.json" "mv .rabadon/guard.json /tmp/x" "rm .rabadon/promise.json"; do
  OUT="$(python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"k4","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$P" "$c" \
    | env RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" 2>&1)"
  RC=$?
  printf '%-34s rc=%s  %s\n' "$c" "$RC" "$(printf '%s' "$OUT" | grep -m1 -oE 'Rule: [a-z-]+|would have blocked[^\n]*' || echo '(no rule line)')"
done
echo
echo "-- the same strings against the deny regex alone (python re, ERE-ish):"
python3 - "$HERE/.rabadon/guard.json" <<'PY'
import json, re, sys
src = json.load(open(sys.argv[1]))
rule = [r for r in src["bash"] if r["id"] == "no-shell-rewrite-of-guard-or-promise"][0]
rx = re.compile(rule["deny"])
for c in ["rm .rabadon/guard.json", "rm -f .rabadon/guard.json", "mv .rabadon/guard.json /tmp/x"]:
    m = rx.search(c)
    print("   %-34s regex=%s" % (c, "MATCH" if m else "no match"))
PY
