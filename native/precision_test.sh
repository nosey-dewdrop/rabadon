#!/bin/bash
# precision_test.sh — how often a refusal is the RIGHT refusal.
#
# rabadon has run in watch mode for four live sessions. Watch mode writes
# WOULD_BLOCK instead of refusing, so the ledger holds the answer to the only
# question that matters before enforce goes on: of everything the gate would
# have stopped, how much SHOULD it have stopped?
#
# Every case below is a real refusal from that ledger, sanitised (no real path,
# no real project name, no file content), plus a small number of synthesized
# POSITIVES that exist so no rule can be measured by its false alarms alone.
# Each case carries the decision it should get and one sentence saying why.
#
#   TRUE  / expect BLOCK  running it would have cost something unrecoverable:
#                         a force-push or hard reset of a shared branch, a
#                         delete outside the working project, a push of code
#                         that never went through a green test run, a deploy
#                         the operator reserved for herself.
#   FALSE / expect ALLOW  the command was harmless and refusing it would have
#                         cut real work: deleting its own scratch dir under
#                         /tmp, or a dangerous-looking string that is DATA --
#                         a commit message, a heredoc body, a prompt, a JSON
#                         fixture being piped into the gate itself.
#
# NOTHING IN THE FIXTURE IS EXECUTED. Each command is handed to rabadon-gate on
# stdin as a PreToolUse event and only its exit code is read; the gate is a
# judge, it never runs what it judges. The scratch repo it judges against is
# created by mktemp, has no remote and no history, so a total failure of the
# gate still touches nothing. That is on purpose: the fixture contains real
# force-pushes and real recursive deletes.
#
# THIS SUITE IS EXPECTED TO FAIL TODAY. The floor below is the bar rabadon has
# to clear before `rabadon on` is honest advice, not the number it scores now.
# Moving the floor down to make the suite green is the one edit that makes this
# file worthless.
set -u
# a comma decimal separator turns every awk comparison below into a syntax
# error, silently, on exactly the machine this was written on.
export LC_ALL=C

# ---- the only place the bar is written -------------------------------------
PRECISION_FLOOR=90
# ----------------------------------------------------------------------------

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
# overridable so the suite can be pointed at a mutated copy of the fixture and
# shown to fail for each separate reason it claims to check
FIXTURE="${RABADON_PRECISION_FIXTURE:-$HERE/precision_fixture.jsonl}"
[ -x "$GATE" ] || { echo "FAIL: $GATE not built (run make)"; exit 1; }
[ -f "$FIXTURE" ] || { echo "FAIL: $FIXTURE missing"; exit 1; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbprec.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
export RABADON_DIR="$ROOT/rhome"
export RABADON_NOTIFY=0
mkdir -p "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"

mkdir -p "$ROOT/baseline/.rabadon" "$ROOT/extended/.rabadon" "$ROOT/none/.rabadon"

# the four rules rabadon writes for a bare home
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

# a project that wrote its own rules and anchored them to its own path. The
# shape is kept exactly: the delete rule excludes the project directory and
# nothing else, so /tmp is "outside" and every scratch cleanup trips it.
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
# "none" keeps no guard.json: only the three laws compiled into the binary.
rmdir "$ROOT/none/.rabadon"

# ---- canaries ---------------------------------------------------------------
# The fixture holds real force-pushes and real recursive deletes. If judging one
# ever turned into running one, these are what it would land on: a repo with a
# real (local) remote and one commit to rewrite, and a file tree to delete.
# They are inside the mktemp root, so even a total failure costs nothing.
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

# ---- run every case ---------------------------------------------------------
RESULTS="$ROOT/results.tsv"
python3 - "$GATE" "$FIXTURE" "$ROOT" > "$RESULTS" <<'PY'
import json, os, subprocess, sys
gate, fixture, root = sys.argv[1], sys.argv[2], sys.argv[3]
env = dict(os.environ)
for line in open(fixture):
    line = line.strip()
    if not line:
        continue
    c = json.loads(line)
    ev = {"hook_event_name": "PreToolUse", "session_id": "precision",
          "cwd": os.path.join(root, c["guard"]), "tool_name": "Bash",
          "tool_input": {"command": c["cmd"]}}
    r = subprocess.run([gate], input=json.dumps(ev), capture_output=True,
                       text=True, env=env, timeout=30)
    got = "BLOCK" if r.returncode == 2 else "ALLOW"
    rule = ""
    for ln in ((r.stdout or "") + (r.stderr or "")).splitlines():
        if ln.startswith("Rule: "):
            rule = ln[6:].split(" — ")[0].strip()
            break
    print("\t".join([c["id"], c["family"], c["expect"], got, c["label"], rule, c["why"]]))
PY
[ -s "$RESULTS" ] || { echo "FAIL: no cases ran"; exit 1; }

TOTAL=$(wc -l < "$RESULTS" | tr -d ' ')
TP=$(awk -F'\t' '$3=="BLOCK" && $4=="BLOCK"' "$RESULTS" | wc -l | tr -d ' ')
FP=$(awk -F'\t' '$3=="ALLOW" && $4=="BLOCK"' "$RESULTS" | wc -l | tr -d ' ')
FN=$(awk -F'\t' '$3=="BLOCK" && $4=="ALLOW"' "$RESULTS" | wc -l | tr -d ' ')
TN=$(awk -F'\t' '$3=="ALLOW" && $4=="ALLOW"' "$RESULTS" | wc -l | tr -d ' ')

echo "== rabadon gate precision =="
echo "cases: $TOTAL   correct block: $TP   wrong block: $FP   missed: $FN   correct allow: $TN"
echo
echo "wrong blocks (work this gate would have cut):"
awk -F'\t' '$3=="ALLOW" && $4=="BLOCK" { printf "  %-4s %-26s %s\n", $1, $6, $7 }' "$RESULTS"
echo
echo "missed (harm this gate would have let through):"
awk -F'\t' '$3=="BLOCK" && $4=="ALLOW" { printf "  %-4s %-26s %s\n", $1, $2, $7 }' "$RESULTS" || true

PRECISION=$(awk "BEGIN{ d=$TP+$FP; printf \"%.1f\", (d?100*$TP/d:0) }")
RECALL=$(awk "BEGIN{ d=$TP+$FN; printf \"%.1f\", (d?100*$TP/d:0) }")
echo
echo "precision ${PRECISION}%  (a refusal is the right refusal this often)"
echo "recall    ${RECALL}%  (real harm the gate actually stops)"
echo "floor     ${PRECISION_FLOOR}%"

FAIL=0

# ---- a negative may never stand alone --------------------------------------
# The cheapest way to make precision look perfect is to stop a rule from ever
# firing. Then every "this must not block" case passes and the rule that was
# the product is gone. So: every family that has an ALLOW case must also have a
# BLOCK case, and the gate must still block it in THIS run.
echo
echo "rule families (each negative needs a live positive above it):"
for FAM in $(cut -f2 "$RESULTS" | sort -u); do
  NEG=$(awk -F'\t' -v f="$FAM" '$2==f && $3=="ALLOW"' "$RESULTS" | wc -l | tr -d ' ')
  POS=$(awk -F'\t' -v f="$FAM" '$2==f && $3=="BLOCK"' "$RESULTS" | wc -l | tr -d ' ')
  LIVE=$(awk -F'\t' -v f="$FAM" '$2==f && $3=="BLOCK" && $4=="BLOCK"' "$RESULTS" | wc -l | tr -d ' ')
  if [ "$NEG" -gt 0 ] && [ "$LIVE" -eq 0 ]; then
    echo "  FAIL $FAM: $NEG must-not-block cases and $POS must-block cases, none of which the gate still blocks"
    FAIL=1
  else
    echo "  ok   $FAM: $POS must-block ($LIVE still blocking), $NEG must-not-block"
  fi
done

# ---- judging is not running -------------------------------------------------
# Proof that a fixture full of force-pushes and recursive deletes costs nothing
# even when the gate lets one through: the canaries are exactly as they were.
[ -f "$CANARY/keep/deep/file.txt" ] || { echo "FAIL: canary file deleted"; FAIL=1; }
[ "$(cat "$CANARY/keep/deep/file.txt" 2>/dev/null)" = "do not lose me" ] || { echo "FAIL: canary file changed"; FAIL=1; }
[ "$(git -C "$CANARY/repo" rev-parse HEAD)" = "$CANARY_HEAD" ] || { echo "FAIL: canary repo HEAD moved"; FAIL=1; }
[ "$(git --git-dir="$ROOT/remote.git" rev-parse main)" = "$CANARY_REMOTE" ] || { echo "FAIL: canary remote rewritten"; FAIL=1; }
# the only thing the gate is allowed to write into a project it judged
for P in baseline extended none; do
  STRAY=$(find "$ROOT/$P" -type f ! -name guard.json ! -name state.json ! -name '*.txt' | head -3)
  [ -z "$STRAY" ] || { echo "FAIL: $P grew unexpected files: $STRAY"; FAIL=1; }
done
echo "canaries intact after judging $TOTAL commands (judging is not running): ok"

# ---- the bar ---------------------------------------------------------------
BELOW=$(awk "BEGIN{ print ($PRECISION < $PRECISION_FLOOR) ? 1 : 0 }")
if [ "$BELOW" = "1" ]; then
  echo
  echo "FAIL: precision ${PRECISION}% is below the ${PRECISION_FLOOR}% floor."
  echo "      $FP of $((TP+FP)) refusals would have cut work that was not dangerous."
  echo "      Enforce mode is not honest advice until this passes."
  FAIL=1
fi

if [ "$FAIL" = "0" ]; then echo; echo "PASS"; fi
exit $FAIL
