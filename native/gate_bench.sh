#!/bin/bash
# gate_bench.sh — the number the site says, and the run that produces it.
#
# "42.0µs to judge one command" was on the benchmarks page for weeks with
# native/gate_bench.sh named underneath it as the source. This file did not
# exist. Nobody could have checked the number, which is the one thing this
# project sells, so it is measured here instead of quoted.
#
# The measurement is rbrules::judge_command over the 34 cases of
# native/precision_fixture.jsonl — real commands lifted out of real sessions,
# judged against the same three guard contexts precision_test.sh builds
# (a bare-install guard, a project that wrote its own rules, and no guard at
# all so only the compiled-in laws answer).
#
# PARITY FIRST, and the number is refused without it. Every case is judged twice:
# once by the real rabadon-gate binary as a PreToolUse hook, once in process by
# gate_bench. If a single verdict differs the run fails and prints no timing at
# all — a fast judge that answers differently from the shipped one is a
# measurement of something nobody runs.
#
# NOTHING IN THE FIXTURE IS EXECUTED. The fixture holds real force-pushes and
# real recursive deletes; both judges are handed the text and read only a
# verdict. HOME is redirected into the mktemp root, the root carries canaries —
# a file tree, a repo with one commit and a real (local) remote — and they are
# checked afterwards, so a total failure of both judges still costs nothing.
#
#   ./native/gate_bench.sh            measure and print
#   ./native/gate_bench.sh --write    also update site/measured.json
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
GATE="$HERE/rabadon-gate"
BENCH="$HERE/gate_bench"
FIXTURE="${RABADON_PRECISION_FIXTURE:-$HERE/precision_fixture.jsonl}"
RUNS="${RABADON_BENCH_RUNS:-200}"
WRITE=0
[ "${1:-}" = "--write" ] && WRITE=1

[ -x "$GATE" ]  || { echo "build first: make native/rabadon-gate"; exit 1; }
[ -x "$BENCH" ] || { echo "build first: make native/gate_bench"; exit 1; }
[ -f "$FIXTURE" ] || { echo "missing fixture: $FIXTURE"; exit 1; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbbench.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
export RABADON_DIR="$ROOT/home/.rabadon"
export RABADON_NOTIFY=0
mkdir -p "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"

mkdir -p "$ROOT/baseline/.rabadon" "$ROOT/extended/.rabadon" "$ROOT/none"
cat > "$ROOT/baseline/.rabadon/guard.json" <<'JSON'
{
  "project": "proj0",
  "bash": [
    { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b", "why": "force-pushing a shared branch destroys history" },
    { "id": "no-rm-rf-outside", "deny": "rm\\s+-\\w*[rf]\\w*\\s+(/(?!tmp)|~/(?!\\.)|\\$HOME)", "why": "recursive delete outside a project is unrecoverable" },
    { "id": "no-hard-reset-main", "deny": "git\\s+reset\\s+--hard\\s+(origin/)?(main|master)\\b", "why": "rewrite shared state via commits, not resets" },
    { "id": "no-hook-bypass", "deny": "git\\s+(commit|push)[^|;&]*--no-verify", "why": "bypassing hooks bypasses every gate at once" }
  ],
  "protectedPaths": [], "disabled": []
}
JSON
cat > "$ROOT/extended/.rabadon/guard.json" <<'JSON'
{
  "project": "proj1",
  "bash": [
    { "id": "no-force-push-main", "deny": "git\\s+push(?=[\\s\\S]*(--force\\b|\\s-f\\b))(?=[\\s\\S]*\\b(main|master)\\b)", "why": "project rule" },
    { "id": "no-rm-rf-outside-project", "deny": "rm\\s+(-\\w*[rf]\\w*\\s+)+(/(?!Users/u/work/proj1)\\S*|~(?!/work/proj1)\\S*|\\$HOME\\S*)", "why": "project rule" },
    { "id": "no-hard-reset-shared-branch", "deny": "git\\s+reset\\s+--hard\\s+(origin/)?(main|master)\\b", "why": "project rule" },
    { "id": "no-wrangler-deploy", "deny": "wrangler\\s+(deploy|publish)\\b", "why": "project rule" }
  ],
  "protectedPaths": [], "disabled": []
}
JSON

# ---- canaries: judging is not running --------------------------------------
CANARY="$ROOT/canary"
mkdir -p "$CANARY/keep/deep"
echo "do not lose me" > "$CANARY/keep/deep/file.txt"
git init -q --bare "$ROOT/remote.git"
git init -q "$CANARY/repo"
git -C "$CANARY/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
git -C "$CANARY/repo" remote add origin "$ROOT/remote.git"
git -C "$CANARY/repo" push -q origin HEAD:main
CANARY_HEAD=$(git -C "$CANARY/repo" rev-parse HEAD)
CANARY_REMOTE=$(git --git-dir="$ROOT/remote.git" rev-parse main)

# ---- the cases, base64 so a quote or a newline survives the pipe ------------
python3 - "$FIXTURE" > "$ROOT/cases.tsv" <<'PY'
import base64, json, sys
for line in open(sys.argv[1], encoding='utf-8'):
    line = line.strip()
    if not line:
        continue
    c = json.loads(line)
    print("%s\t%s\t%s" % (c["id"], c["guard"],
                          base64.b64encode(c["cmd"].encode()).decode()))
PY
[ -s "$ROOT/cases.tsv" ] || { echo "FAIL: no cases read from $FIXTURE"; exit 1; }

# ---- verdicts from the SHIPPED binary, as a hook ---------------------------
python3 - "$GATE" "$FIXTURE" "$ROOT" > "$ROOT/gate.tsv" <<'PY'
import json, os, subprocess, sys
gate, fixture, root = sys.argv[1], sys.argv[2], sys.argv[3]
for line in open(fixture, encoding='utf-8'):
    line = line.strip()
    if not line:
        continue
    c = json.loads(line)
    ev = {"hook_event_name": "PreToolUse", "session_id": "bench",
          "cwd": os.path.join(root, c["guard"]), "tool_name": "Bash",
          "tool_input": {"command": c["cmd"]}}
    r = subprocess.run([gate], input=json.dumps(ev), capture_output=True,
                       text=True, timeout=60)
    print("%s\t%s" % (c["id"], "BLOCK" if r.returncode == 2 else "ALLOW"))
PY

# ---- verdicts + timing from judge_command, in process ----------------------
"$BENCH" "$ROOT" --runs "$RUNS" < "$ROOT/cases.tsv" > "$ROOT/bench.tsv" || {
  echo "FAIL: gate_bench did not run"; exit 1; }

# ---- parity, before any number is printed ----------------------------------
MISMATCH=$(python3 - "$ROOT/gate.tsv" "$ROOT/bench.tsv" <<'PY'
import sys
g = dict(l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip())
bad = []
for l in open(sys.argv[2]):
    if l.startswith("#"):
        continue
    f = l.rstrip("\n").split("\t")
    if len(f) < 2:
        continue
    if g.get(f[0]) != f[1]:
        bad.append("%s: rabadon-gate=%s judge_command=%s" % (f[0], g.get(f[0]), f[1]))
print("\n".join(bad))
PY
)
NCASES=$(grep -vc '^#' "$ROOT/bench.tsv")
if [ -n "$MISMATCH" ]; then
  echo "PARITY FAIL — the in-process judge and the shipped gate disagree:"
  echo "$MISMATCH" | sed 's/^/  /'
  echo "no timing is printed: a benchmark of a judge nobody runs is not a measurement."
  exit 1
fi
echo "parity: judge_command == rabadon-gate on all $NCASES fixture verdicts"

get() { grep "^# $1	" "$ROOT/bench.tsv" | cut -f2; }
MED=$(get median_us); P95=$(get p95_us); MIN=$(get min_us); MAX=$(get max_us); MEAN=$(get mean_us)
BLOCKS=$(awk -F'\t' '$2=="BLOCK"' "$ROOT/bench.tsv" | grep -vc '^#')

echo
printf 'judge one command   median %sµs   p95 %sµs   mean %sµs   (min %s, max %s)\n' \
       "$MED" "$P95" "$MEAN" "$MIN" "$MAX"
printf '  over %s real cases, %s of them refusals, %s judgements each\n' "$NCASES" "$BLOCKS" "$RUNS"
echo
echo "the slowest cases (µs, median of $RUNS):"
grep -v '^#' "$ROOT/bench.tsv" | sort -t"$(printf '\t')" -k4 -n -r | head -5 | \
  awk -F'\t' '{ printf "  %-5s %-6s %-26s %8.1f\n", $1, $2, $3, $4/1000 }'

# ---- canaries ---------------------------------------------------------------
CFAIL=0
[ -f "$CANARY/keep/deep/file.txt" ] || { echo "FAIL: canary file deleted"; CFAIL=1; }
[ "$(cat "$CANARY/keep/deep/file.txt" 2>/dev/null)" = "do not lose me" ] || { echo "FAIL: canary changed"; CFAIL=1; }
[ "$(git -C "$CANARY/repo" rev-parse HEAD)" = "$CANARY_HEAD" ] || { echo "FAIL: canary repo HEAD moved"; CFAIL=1; }
[ "$(git --git-dir="$ROOT/remote.git" rev-parse main)" = "$CANARY_REMOTE" ] || { echo "FAIL: canary remote rewritten"; CFAIL=1; }
echo
echo "canaries intact after judging $NCASES commands (judging is not running): ok"
[ "$CFAIL" = 0 ] || exit 1

if [ "$WRITE" = 1 ]; then
  python3 - "$REPO" "$MED" "$P95" "$NCASES" "$RUNS" <<'PY'
import json, os, sys
repo, med, p95, ncases, runs = sys.argv[1:6]
p = os.path.join(repo, "site", "measured.json")
d = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
d["gate.judge_us"] = {
    "value": float(med),
    "display": med + "&micro;s",
    "cmd": "native/gate_bench.sh",
    "what": "to judge one command",
    "note": "median over %s real cases from native/precision_fixture.jsonl, %s judgements each, p95 %sµs. "
            "in process, the same rbrules::judge_command the gate calls, verdict parity with the shipped "
            "binary asserted on all %s before the timer is read." % (ncases, runs, p95, ncases),
}
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2, sort_keys=True)
    f.write("\n")
print("wrote site/measured.json  gate.judge_us = %sµs" % med)
PY
fi
