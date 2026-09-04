#!/usr/bin/env bash
# rule_cost_test.sh — A USER'S OWN RULE MUST NOT BE ABLE TO HANG THEIR SESSION.
#
# WHY THIS FILE EXISTS. `rx_test` compiles a project's deny pattern with
# std::regex, which backtracks and has no step limit. A pattern like `(a+)+b`
# — written by accident far more often than by malice — turns a long command
# into seconds of CPU on the hot path, and the hot path is every tool call the
# agent makes. Measured 2026-09-03 with that rule in guard.json: a
# 100k-character command cost 5.18s, while the same command against the
# compiled laws alone cost 0.02s. The cost was entirely the user's rule.
#
# The bound is on the INPUT, not the engine: a prefix and a tail window, so a
# dangerous verb sitting after a huge paste is still seen. This suite holds
# both halves — the cost, and the fact that nothing was weakened to get it.
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
FAIL=0; PASSN=0
pass() { printf '  ok   %s\n' "$1"; PASSN=$((PASSN + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; FAIL=1; }
[ -x "$GATE" ] || { echo "rule-cost: no gate binary at $GATE — run make first" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "rule-cost: python3 required" >&2; exit 1; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbcost.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
HOMEDIR="$ROOT/home"; PROJ="$ROOT/proj"
mkdir -p "$HOMEDIR/.rabadon/spool" "$PROJ/.rabadon" "$PROJ/.git"
: > "$HOMEDIR/.rabadon/enabled"
printf 'ref: refs/heads/main\n' > "$PROJ/.git/HEAD"
# a guard carrying BOTH a catastrophic pattern and a real one, because the
# question is whether the bound costs the real one anything.
cat > "$PROJ/.rabadon/guard.json" <<'J'
{"project":"proj","testCommand":"true","bash":[
  {"id":"redos-bait","deny":"(a+)+b","why":"a pattern that backtracks"},
  {"id":"no-force","deny":"git\\s+push\\s+--force","why":"no force pushes"}]}
J

# judge <command> -> "<exit> <seconds>". Fresh session id every call: loop-stop
# refuses a third identical command and its exit 2 would read as a rule firing.
judge() {
  python3 - "$GATE" "$PROJ" "$HOMEDIR" "$1" <<'PY'
import json, subprocess, sys, os, time, random
G, P, H, cmd = sys.argv[1:5]
e = {"hook_event_name": "PreToolUse", "session_id": "s%d" % random.randrange(10**9),
     "cwd": P, "tool_name": "Bash", "tool_input": {"command": cmd}}
env = dict(os.environ, HOME=H, RABADON_DIR=H + "/.rabadon", RABADON_NOTIFY="0")
t = time.time()
try:
    r = subprocess.run([G], input=json.dumps(e), capture_output=True, text=True, env=env, timeout=30)
    print("%d %.2f" % (r.returncode, time.time() - t))
except subprocess.TimeoutExpired:
    print("timeout 30.00")
PY
}

echo "rule-cost: a backtracking rule cannot own the hot path"
BIG="$(python3 -c 'print("echo " + "a"*100000)')"
# BEST OF THREE, and the reason is not flakiness-tolerance. The question this
# asks is whether the INPUT BOUND holds — a property of the code — and a single
# sample answers a different question: whether this machine was busy for one
# second. Measured on the author's idle machine the bound costs 1.5-2.2s against
# a 3s limit; under a parallel `make test` the same binary sampled 3.2s, 9.9s
# and 25.3s while `rabadon-gate` itself, timed directly, never left 0.02s.
# Scheduler noise was being read as a regression. Three tries, the fastest kept:
# a bound that is actually broken cannot produce one fast run, and a machine
# under load usually can. The limit itself is NOT relaxed.
BEST=""
for _ in 1 2 3; do
  read -r rc secs <<<"$(judge "$BIG")"
  [ "$rc" = "timeout" ] && continue
  if [ -z "$BEST" ] || python3 -c "import sys; sys.exit(0 if float('$secs') < float('$BEST') else 1)"; then
    BEST="$secs"
  fi
  python3 -c "import sys; sys.exit(0 if float('$secs') < 3.0 else 1)" && break
done
if [ -z "$BEST" ]; then
  bad "a 100k-character command never returned — the session is hung"
else
  python3 -c "import sys; sys.exit(0 if float('$BEST') < 3.0 else 1)" \
    && pass "a 100k-character command against a backtracking rule returned in ${BEST}s (<3s, best of 3)" \
    || bad "a 100k-character command took ${BEST}s at its fastest of 3 — the bound is not holding"
fi

echo "rule-cost: and nothing was weakened to get it"
read -r rc secs <<<"$(judge 'git push --force origin main')"
[ "$rc" = "2" ] && pass "the real deny rule still refuses (exit 2, ${secs}s)" \
                || bad "the real deny rule did not fire (exit $rc) — the bound cut a rule"
# the tail window: a dangerous verb AFTER a huge paste must still be seen, or
# the bound would be a hole rather than a limit.
TAIL="$(python3 -c 'print("echo " + "x"*60000 + "; git push --force origin main")')"
read -r rc secs <<<"$(judge "$TAIL")"
[ "$rc" = "2" ] && pass "a dangerous verb after a 60k paste is still refused (${secs}s)" \
                || bad "a verb past the prefix window was missed (exit $rc) — the bound is a hole"
read -r rc secs <<<"$(judge 'echo hello')"
[ "$rc" != "2" ] && pass "an ordinary command is still allowed" \
                 || bad "an ordinary command was refused"

# THE SUITE MUST BE ABLE TO GO RED. If the gate answered nothing at all, every
# check above would pass vacuously.
read -r rc secs <<<"$(judge 'rm -rf /')"
[ "$rc" = "2" ] && pass "the harness can observe a refusal at all" \
                || bad "the harness saw no refusal even for \`rm -rf /\` — the checks above prove nothing"

echo
[ "$FAIL" = "0" ] && echo "rule cost: $PASSN passed, 0 failed" || echo "rule cost: FAILED"
exit $FAIL
