#!/bin/bash
# trace_test.sh — the REPORTING leg, over the shape the ENFORCEMENT leg writes.
#
# trace had no suite at all. cli_test.sh drives the binary over a hand-typed
# spool and route_test.sh over another one; both fixtures were written by
# someone who already knew what trace reads, so both begin with STEP_START.
# The two programs that actually write refusals into the ledger do not.
#
#   rabadon-gate     one run per PROCESS (`ng-<ms>-<pid>`), and the refusal
#                    RETURNS at the block — the STEP_START lives further down,
#                    on the allow path. A refused run holds {CHECK_FAIL, STOP}.
#   rabadon-sandbox  emits the same two events and contains no STEP_START at all.
#
# trace built its step list from STEP_START alone and attached a catch only
# `if(cur)`, so over a real refusal the catch was structurally orphaned and
# dropped: `CAUGHT 0` on the one surface README calls the one that ends up in a
# screenshot, while `rabadon usage` said "1 refused before they happened" and
# `rabadon export --otlp` shipped ERROR spans over the identical bytes. A
# stranger who follows the quickstart, earns their first catch and runs
# `rabadon trace` was shown nothing.
#
# So this suite refuses fixtures. Every event it asserts on is written by the
# real binaries, and the three readers are then compared over the SAME spool.
#
# SAFETY (the command under test is `git push --force origin main`): it is
# driven inside a throwaway `git init` repo that has NO remote, with the global
# and system git config detached and the terminal prompt disabled. Case 0 below
# proves the harness is inert by running that push with rabadon nowhere near it
# and asserting git itself refuses — so if a block ever fails to fire, nothing
# leaves the machine.
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD

for b in rabadon-trace rabadon-stats rabadon-export rabadon-gate rabadon-sandbox; do
  [ -x "./native/$b" ] || { echo "trace_test: build first (make native/$b)"; exit 1; }
done

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

echo "trace: a refusal is a caught step"

# ---------------------------------------------------------------------------
# the isolated world. BOX is the whole rabadon home (RABADON_DIR), so the spool
# under test is BOX/spool and this suite can never read or write the operator's.
# REPO is named, not `mktemp -d` bare: an unnamed macOS temp dir is `tmp.XXXX`,
# and drill.h rule 3 excludes every pipe whose project starts with `tmp.` — the
# fixture would have been classified as rabadon's own drill and all three
# readers would honestly report zero.
# ---------------------------------------------------------------------------
BOX=$(mktemp -d /tmp/rabadon-refusal-box.XXXXXX)
REPO=$(mktemp -d /tmp/rabadon-refusal-repo.XXXXXX)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
git -C "$REPO" init -q .
git -C "$REPO" commit -q --allow-empty -m base --author="t <t@t>" 2>/dev/null \
  || GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
     git -C "$REPO" commit -q --allow-empty -m base

# ---- 0. the harness is inert (K4: the blast radius, measured, not assumed) ---
REMOTES=$(git -C "$REPO" remote)
[ -z "$REMOTES" ] && pass "the throwaway repo has no remote (\`git remote\` is empty)" \
  || fail "the throwaway repo HAS a remote: $REMOTES — the force-push probe is not inert"
BARE=$(git -C "$REPO" push --force origin main 2>&1); BRC=$?
if [ $BRC -ne 0 ] && printf '%s' "$BARE" | grep -qi "does not appear to be a git repository\|repository not found\|No such"; then
  pass "with rabadon absent, git itself refuses the push (rc=$BRC) — a missed block reaches nothing"
else
  fail "the raw push did not fail locally (rc=$BRC): $BARE"
fi

# ---- write the ledger with the REAL enforcement binaries --------------------
RABADON_DIR="$BOX" "$ROOT/native/rabadon-gate" --on >/dev/null 2>&1

# arm A: the hook. a PreToolUse event, exactly the JSON Claude Code sends.
printf '{"hook_event_name":"PreToolUse","session_id":"tracesuite-a","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$REPO" \
  | RABADON_DIR="$BOX" "$ROOT/native/rabadon-gate" >/dev/null 2>&1
GRC=$?
[ $GRC -eq 2 ] && pass "rabadon-gate REFUSED the force-push (exit 2) — the ledger below is a real refusal" \
  || fail "rabadon-gate exit $GRC, expected 2 — no refusal was written, every assertion below would be vacuous"

# arm B: exec. the other writer, and the one with no STEP_START in the file.
( cd "$REPO" && RABADON_DIR="$BOX" "$ROOT/native/rabadon-sandbox" --dir "$REPO" -- git push --force origin main ) >/dev/null 2>&1
SRC=$?
[ $SRC -eq 2 ] && pass "rabadon-sandbox REFUSED the same command (exit 2)" \
  || fail "rabadon-sandbox exit $SRC, expected 2"

# ---- the three readers, over those bytes ------------------------------------
RABADON_DIR="$BOX" python3 - "$ROOT" "$BOX" <<'PY'
import json, os, re, subprocess, sys
root, box = sys.argv[1], sys.argv[2]
ok = bad = 0
def pas(m):
    global ok; ok += 1; print("  ok   - " + m)
def bad_(m):
    global bad; bad += 1; print("  FAIL - " + m)

env = dict(os.environ); env["RABADON_DIR"] = box
def run(binary, *args):
    p = subprocess.run([os.path.join(root, "native", binary)] + list(args),
                       capture_output=True, text=True, env=env)
    return p.returncode, p.stdout, p.stderr

spool = os.path.join(box, "spool")
files = [os.path.join(spool, f) for f in os.listdir(spool) if f.endswith(".jsonl")]
lines = []
for f in files:
    lines += [json.loads(l) for l in open(f, encoding="utf-8") if l.strip()]

# ---- the SHAPE this suite exists for: no STEP_START anywhere ----------------
runs = {}
for e in lines:
    runs.setdefault(e["run"], []).append(e["ev"])
refusals = {r: evs for r, evs in runs.items() if "CHECK_FAIL" in evs}
if len(refusals) == 2:
    pas("the two real binaries wrote 2 refused runs: " + ", ".join(sorted(refusals)))
else:
    bad_("expected 2 refused runs in the spool, found %d (%r)" % (len(refusals), runs))
starts = [r for r, evs in refusals.items() if "STEP_START" in evs]
if not starts:
    pas("neither refused run contains a STEP_START — this IS the shape trace could not read")
else:
    bad_("a refused run carries a STEP_START (%r); the fixture no longer reproduces the defect" % starts)

# ---- reader 1: trace, per run ----------------------------------------------
CAUGHT = re.compile(r"CAUGHT (\d+)")
trace_total = 0
for rid, evs in sorted(refusals.items()):
    rc, so, se = run("rabadon-trace", rid, "--no-color")
    nums = CAUGHT.findall(so)
    n = sum(int(x) for x in nums)
    trace_total += n
    if rc == 0 and n == 1:
        pas("`rabadon trace %s` renders CAUGHT 1 over a {CHECK_FAIL, STOP} run" % rid)
    else:
        bad_("`rabadon trace %s` rendered CAUGHT %s (rc=%d) — the catch was dropped" % (rid, nums or "0", rc))
    # what the check said has to be ON the screen, not merely counted
    if "baseline-force-push" in so:
        pas("the rule that fired is named in the render (baseline-force-push)")
    else:
        bad_("the render never names the rule; docs/commands.md promises \"what the check said\"")
    if "force-push to shared branch" in so:
        pas("the check's own why is rendered")
    else:
        bad_("the check's why is missing from the render")
    step = "Bash" if rid.startswith("ng-") else "exec"
    if re.search(r"^\s+\S*\s*\d+\s+%s\b" % re.escape(step), so, re.M):
        pas("the caught step is drawn as a step, named %r" % step)
    else:
        bad_("no step row for %r in the render" % step)
    # NEGATIVE, and it is only allowed here because the POSITIVE line above it
    # is asserted: the refusal must not be dressed as a rejected repair.
    if "REPAIR_FAIL" in so or "fake fix" in so:
        bad_("the render invents a repair that never happened (\"fake fix ... REPAIR_FAIL\")")
    else:
        pas("no repair is invented: nothing was proposed, so nothing was rejected")
    if re.search(r"refused|never ran", so, re.I):
        pas("the render says the action was refused before it ran")
    else:
        bad_("the render never says the action was stopped before it ran")

# ---- reader 2: usage/stats --------------------------------------------------
rc, so, se = run("rabadon-stats", "--json")
stats_refused = json.loads(so)["totals"]["refused"] if rc == 0 else -1
rc2, human, _ = run("rabadon-stats")
m = re.search(r"([\d,]+) refused before they happened", human)
human_refused = int(m.group(1).replace(",", "")) if m else -1
if stats_refused == human_refused == 2:
    pas("`rabadon usage` counts 2 refused before they happened (json and the printed line agree)")
else:
    bad_("usage: json=%d printed=%d, expected 2 and 2" % (stats_refused, human_refused))

# ---- reader 3: export -------------------------------------------------------
rc, so, se = run("rabadon-export", "--otlp")
spans = [s for r in json.loads(so)["resourceSpans"] for ss in r["scopeSpans"] for s in ss["spans"]]
def attr(s, k):
    for a in s.get("attributes", []):
        if a["key"] == k:
            return list(a["value"].values())[0]
    return None
err = [s for s in spans if s.get("status", {}).get("code") == 2]
err_stop = [s for s in err if attr(s, "rabadon.ev") == "STOP"]
if len(err) == 4 and len(err_stop) == 2:
    pas("`rabadon export --otlp` ships 4 ERROR spans = 2 refusals x {CHECK_FAIL, STOP}")
else:
    bad_("export: %d ERROR spans, %d of them STOP — expected 4 and 2" % (len(err), len(err_stop)))
if err_stop and all(s["status"]["message"] == "baseline-force-push" for s in err_stop):
    pas("every exported refusal carries the rule id as its span status message")
else:
    bad_("an exported refusal lost its rule id: %r" % [s.get("status") for s in err_stop])

# ---- THE CONTRACT: one predicate, three readers -----------------------------
# README: "all three readers run the identical predicate, from one file". A
# refusal is one refusal on every surface. export represents it as the PAIR of
# ERROR spans it wrote (CHECK_FAIL + STOP), so the refusal count there is the
# ERROR spans that are STOPs — the same event stats counts.
if trace_total == stats_refused == len(err_stop):
    pas("trace CAUGHT (%d) == usage refused (%d) == export refusal spans (%d)"
        % (trace_total, stats_refused, len(err_stop)))
else:
    bad_("the three readers disagree over identical bytes: trace=%d usage=%d export=%d"
         % (trace_total, stats_refused, len(err_stop)))

print("  --- %d ok, %d failed" % (ok, bad))
sys.exit(1 if bad else 0)
PY
PYRC=$?

rm -rf "$BOX" "$REPO"
if [ $PYRC -ne 0 ]; then bad=$((bad+1)); fi
echo "  --- $ok ok, $bad failed (shell arm)"
[ $bad -eq 0 ] || exit 1
exit 0
