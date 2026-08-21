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

for b in rabadon-trace rabadon-stats rabadon-export rabadon-gate rabadon-sandbox rabadon-pipeline; do
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
# the branch is NAMED, because the probe below pushes `main` and a fixture that
# inherits the machine's default gets `master` on a GitHub runner. git then dies
# on the refspec before it ever looks for the remote, and the check that wanted
# to prove "no remote, so a missed block reaches nothing" proves nothing at all.
# v0.2.0 died on this same inheritance one file along.
git -C "$REPO" init -q -b main . 2>/dev/null \
  || { git -C "$REPO" init -q . && git -C "$REPO" symbolic-ref HEAD refs/heads/main; }
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

# arm C: WATCH. Same orphan shape, opposite fact — {CHECK_FAIL, WOULD_BLOCK},
# exit 0, and the command RUNS. Its own box, because it must not be added to
# the refusal counts the three readers are compared on.
WBOX=$(mktemp -d /tmp/rabadon-watch-box.XXXXXX)
RABADON_DIR="$WBOX" "$ROOT/native/rabadon-gate" --off >/dev/null 2>&1
printf '{"hook_event_name":"PreToolUse","session_id":"tracesuite-w","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$REPO" \
  | RABADON_DIR="$WBOX" "$ROOT/native/rabadon-gate" >/dev/null 2>&1
WRC=$?
[ $WRC -eq 0 ] && pass "rabadon-gate in WATCH mode did NOT stop the command (exit 0)" \
  || fail "watch-mode gate exit $WRC, expected 0 — this arm is not testing watch mode"

# ---- the three readers, over those bytes ------------------------------------
WBOX="$WBOX" python3 - "$ROOT" "$BOX" <<'PY'
import json, os, re, shutil, subprocess, sys, tempfile, time
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
    # the header. A run that called no model must not carry a model's byline.
    head = so.splitlines()[2] if len(so.splitlines()) > 2 else ""
    surface = "session" if rid.startswith("ng-") else "exec"
    if ("refused at the %s gate" % surface) in head and "no model call" in head:
        pas("the header names the surface the refusal came through (%s) and says no model call" % surface)
    else:
        bad_("header does not name the surface / the absent model call: %r" % head)
    if "claude -p" not in head and "$0" not in head:
        pas("the header prices no model call it never made")
    else:
        bad_("the header still bills a model over a run with no model event: %r" % head)
    # the verdict is on the STOP; it used to print as an unanswered "?"
    if re.search(r"verdict: BLOCKED", so):
        pas("the footer verdict reads BLOCKED, the reason the STOP carries")
    else:
        bad_("the footer verdict is not BLOCKED: %r" % (re.findall(r"verdict: \S+", so) or None))

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

# ---- arm C: a WATCH verdict is not a catch -----------------------------------
# The same {orphan CHECK_FAIL} shape with the opposite meaning. Left unhandled,
# the repair above would have printed "refused BEFORE it ran; the action never
# happened" over an action that ran, and CAUGHT 1 against usage's refused: 0.
wbox = os.environ["WBOX"]
wenv = dict(os.environ); wenv["RABADON_DIR"] = wbox
def wrun(binary, *args):
    p = subprocess.run([os.path.join(root, "native", binary)] + list(args),
                       capture_output=True, text=True, env=wenv)
    return p.returncode, p.stdout, p.stderr
wevs = []
for f in os.listdir(os.path.join(wbox, "spool")):
    if f.endswith(".jsonl"):
        wevs += [json.loads(l) for l in open(os.path.join(wbox, "spool", f), encoding="utf-8") if l.strip()]
kinds = sorted({e["ev"] for e in wevs})
if kinds == ["CHECK_FAIL", "WOULD_BLOCK"]:
    pas("watch mode wrote {CHECK_FAIL, WOULD_BLOCK} and no STOP — the shape with the opposite meaning")
else:
    bad_("watch mode wrote %r, expected CHECK_FAIL + WOULD_BLOCK" % kinds)
rc, wso, _ = wrun("rabadon-trace", "--last", "--no-color")
wcaught = sum(int(x) for x in CAUGHT.findall(wso))
wtotals = json.loads(wrun("rabadon-stats", "--json")[1])["totals"]
if wcaught == 0 and wtotals["refused"] == 0:
    pas("trace counts CAUGHT 0 for a watch verdict, exactly as usage counts refused 0")
else:
    bad_("trace CAUGHT %d vs usage refused %d on a watch run — a recorded verdict was sold as enforcement"
         % (wcaught, wtotals["refused"]))
if re.search(r"WOULD BLOCK 1", wso) and wtotals["wouldRefuse"] == 1:
    pas("the watch verdict is rendered as WOULD BLOCK 1, the same 1 usage reports as wouldRefuse")
else:
    bad_("watch verdict lost: trace %r, usage wouldRefuse=%d"
         % (re.findall(r"WOULD BLOCK \d+", wso), wtotals["wouldRefuse"]))
if "the action RAN" in wso and "NOT stopped" in wso:
    pas("the watch render says the action ran and nothing was stopped")
else:
    bad_("the watch render does not say the action ran")
# NEGATIVE, paired with the two positives above it.
if "never happened" in wso or "nothing to undo" in wso:
    bad_("the watch render claims the action never happened — it ran")
else:
    pas("the watch render makes no claim that the action was prevented")
if "baseline-force-push" in wso:
    pas("the watch render still names the rule that fired")
else:
    bad_("the watch render dropped the rule id")

# ---- arm D: the routed renderer must not draw a dead step green --------------
# The ONE fixture in this file, and it is written by hand because nothing ships
# that writes a tier ladder without a live proposer (route_test.sh writes its
# spool by hand for the same reason). render_routed's green row was reached by
# "not escalated", which is true of a step that escalated nowhere because it
# simply died: check failed, no climb, no STEP_OK. It printed "proven cheap".
rbox = tempfile.mkdtemp(prefix="rabadon-routed-box.")
os.makedirs(os.path.join(rbox, "spool"))
day = time.strftime("%Y-%m-%d", time.gmtime())
now = int(time.time() * 1000)
with open(os.path.join(rbox, "spool", day + ".jsonl"), "w", encoding="utf-8") as fh:
    for seq, ev in enumerate([
        '"ev":"RUN_START","arm":"routed","tiers":"haiku,sonnet","steps":1',
        '"ev":"STEP_START","step":"ship-it"',
        '"ev":"CHECK_FAIL","step":"ship-it","fails":[{"check":"testsuite","why":"FAIL testsuite [pytest]: the suite is RED"}]',
        '"ev":"STOP","reason":"BLOCKED","detail":"the step never passed"',
    ], 1):
        fh.write('{"v":1,"seq":%d,"ts":%d,"run":"routed-dead","pipe":"demo:do",%s}\n' % (seq, now + seq, ev))
renv = dict(os.environ); renv["RABADON_DIR"] = rbox
p = subprocess.run([os.path.join(root, "native", "rabadon-trace"), "routed-dead", "--no-color"],
                   capture_output=True, text=True, env=renv)
rso = p.stdout
if "CAUGHT" in rso and "testsuite" in rso:
    pas("the routed renderer draws a step that failed its check and never came back as CAUGHT")
else:
    bad_("the routed renderer lost the catch entirely: %r" % rso)
if "proven cheap" not in rso and "passed" not in rso:
    pas("...and does NOT draw it as proven cheap / passed")
else:
    bad_("a dead step renders green in the routed view: %r" % rso)

shutil.rmtree(rbox, ignore_errors=True)

print("  --- %d ok, %d failed" % (ok, bad))
sys.exit(1 if bad else 0)
PY
PYRC=$?

# ---------------------------------------------------------------------------
# arms E-I: the `saved:` line, over ledgers the REAL loop wrote.
#
# That line is the only sentence on this screen that makes a claim about steps
# which did not run and about money, and every number in it was assembled by
# hand from firstCaught+1 and a plan count. Over a run whose catch IS the last
# step it printed "steps 2–1" — a range that counts backwards — and the repaired
# arm ended with a hardcoded "the bug never reached step 10" on a plan that has
# one step. Both are numbers on the surface README says ends up in a screenshot,
# and neither is in the ledger.
#
# The producer is repair_proof.sh's, because it is the only one that writes a
# real REPAIR_OK / REPAIR_FAIL with no LLM in the room: rabadon-pipeline against a
# genuinely broken project, with the proposer scripted. The arbiter still
# decides — the honest proposer fixes the code, the cheat one neuters the test
# and is refused on the forbidden sha.
# ---------------------------------------------------------------------------
echo "trace: the saved: line, over real repair events"
SAVED=$(mktemp -d /tmp/rabadon-saved-line.XXXXXX)
mkdir -p "$SAVED/bin"
# The fix is a byte LONGER than the bug, and the suite below runs `python3 -B`:
# the two files are otherwise the same size and are written inside the same
# second, so CPython would have validated its own __pycache__/calc.pyc (mtime +
# size) and re-imported the BUG after a correct repair. The honest arm passed or
# failed on which side of a second boundary it landed.
cat > "$SAVED/bin/honest.sh" <<'EOF'
#!/bin/bash
cat >/dev/null                                  # the repair prompt, ignored
printf 'def add(a, b):\n    return a + b  # fixed\n' > calc.py   # fix the REAL bug
EOF
cat > "$SAVED/bin/cheat.sh" <<'EOF'
#!/bin/bash
cat >/dev/null
printf 'print("ok")\n' > test_calc.py           # neuter the test instead
EOF
# refused on the first attempt, proven on the second: the run is caught, keeps
# its repair budget, and FINISHES. rejected>0 AND repaired>0 at the same time.
cat > "$SAVED/bin/twotry.sh" <<'EOF'
#!/bin/bash
cat >/dev/null
if [ -e .attempted ]; then printf 'def add(a, b):\n    return a + b  # fixed\n' > calc.py
else touch .attempted; fi                       # attempt 1 changes nothing
EOF
chmod +x "$SAVED/bin"/*.sh

# <name> <honest|cheat|none> <declared steps>.  `none` is the zero-repair run:
# RABADON_MAX_REPAIRS=0, so the catch is written and no repair is ever proposed.
saved_scenario() {
  local name=$1 prop=$2 n=$3
  local d="$SAVED/$name" box="$SAVED/box-$name"
  mkdir -p "$d" "$box/spool"
  printf 'def add(a, b):\n    return a - b\n' > "$d/calc.py"     # the bug: subtracts
  printf 'import calc\nassert calc.add(2, 3) == 5\nprint("ok")\n' > "$d/test_calc.py"
  python3 - "$d" "$n" "$prop" <<'PY'
import json, sys
d, n, prop = sys.argv[1], int(sys.argv[2]), sys.argv[3]
h = 1469598103934665603                 # FNV-1a 64: what rabadon-verify hashes with
for b in open(d + "/test_calc.py", "rb").read():
    h = ((h ^ b) * 1099511628211) & 0xffffffffffffffff
steps = [{"id": "fix-add", "kind": "llm" if prop == "none" else "cmd", "do": "true",
          "contract": [{"type": "testsuite", "run": "python3 -B test_calc.py"},
                       {"type": "forbidden", "path": "test_calc.py", "sha": str(h)}]}]
for k in range(2, n + 1):               # steps AFTER the catch, so a range exists
    steps.append({"id": "step-%d" % k, "kind": "cmd", "do": "true",
                  "contract": [{"type": "fileExists", "path": "calc.py"}]})
# acceptance is the run's own definition of done, and the loop is fail-closed
# when it is absent: with an empty accept[] even the repaired arms would end
# CHECK_FAILED, which is not the run these arms claim to be about.
json.dump({"steps": steps,
           "accept": [{"type": "testsuite", "run": "python3 -B test_calc.py"}]},
          open(d + "/plan.json", "w"))
PY
  if [ "$prop" = none ]; then
    RABADON_DIR="$box" RABADON_MAX_REPAIRS=0 RABADON_PROPOSER=true \
      "$ROOT/native/rabadon-pipeline" "$d" "$d/plan.json" >/dev/null 2>&1
  else
    RABADON_DIR="$box" RABADON_MAX_REPAIRS="${4:-1}" RABADON_PROPOSER="$SAVED/bin/$prop.sh" \
      "$ROOT/native/rabadon-pipeline" "$d" "$d/plan.json" >/dev/null 2>&1
  fi
}

saved_scenario last-repaired  honest 1    # catch on the LAST step: no range exists
saved_scenario last-rejected  cheat  1
saved_scenario later-repaired honest 3    # catch on step 1 of 3: a range DOES exist
saved_scenario later-rejected cheat  3
saved_scenario no-repair      none   1    # a catch with zero REPAIR_* in the ledger
saved_scenario both           twotry 3 2  # refused once, then repaired, and it FINISHED

python3 - "$ROOT" "$SAVED" <<'PY'
import json, os, re, subprocess, sys
root, saved = sys.argv[1], sys.argv[2]
ok = bad = 0
def pas(m):
    global ok; ok += 1; print("  ok   - " + m)
def bad_(m):
    global bad; bad += 1; print("  FAIL - " + m)

def render(name):
    box = os.path.join(saved, "box-" + name)
    evs = []
    for f in os.listdir(os.path.join(box, "spool")):
        if f.endswith(".jsonl"):
            evs += [json.loads(l) for l in open(os.path.join(box, "spool", f), encoding="utf-8") if l.strip()]
    env = dict(os.environ); env["RABADON_DIR"] = box
    p = subprocess.run([os.path.join(root, "native", "rabadon-trace"), "--last", "--no-color"],
                       capture_output=True, text=True, env=env)
    return evs, p.stdout

def saved_line(so):
    for l in so.splitlines():
        if "saved:" in l:
            return l
    return ""

# The ledger has to hold the shape each arm claims to be about, or every
# assertion under it is vacuous: a run with no REPAIR_OK cannot test the
# repaired branch, and "no fake fix is printed" is free if nothing was caught.
SHAPE = {"last-repaired":  (["REPAIR_OK"],                1, 1),
         "last-rejected":  (["REPAIR_FAIL"],              1, 0),
         "later-repaired": (["REPAIR_OK"],                3, 3),
         "later-rejected": (["REPAIR_FAIL"],              3, 0),
         "no-repair":      ([],                           1, 0),
         "both":           (["REPAIR_FAIL", "REPAIR_OK"], 3, 3)}
out = {}
for name, (want, declared, finished) in SHAPE.items():
    evs, so = render(name)
    out[name] = so
    kinds = [e["ev"] for e in evs]
    n = max([e.get("steps", 0) for e in evs if e["ev"] == "RUN_START"] or [0])
    repairs = [k for k in kinds if k.startswith("REPAIR_") and k != "REPAIR_START"]
    # STEP_OK is what makes the negatives below non-vacuous: "no step is claimed
    # to have never run" is worth nothing unless the ledger shows steps running.
    done = kinds.count("STEP_OK")
    if not want:
        if not repairs and "CHECK_FAIL" in kinds and n == declared:
            pas("%s: the loop wrote a catch and ZERO REPAIR_OK/REPAIR_FAIL (%s)" % (name, ",".join(kinds)))
        else:
            bad_("%s: wanted a catch with no repair event, got %r (steps=%d)" % (name, kinds, n))
    elif repairs == want and "CHECK_FAIL" in kinds and n == declared and done == finished:
        pas("%s: the real loop wrote CHECK_FAIL + %s over a %d-step plan, %d step(s) OK"
            % (name, "+".join(want), declared, done))
    else:
        bad_("%s: wanted CHECK_FAIL + %s over %d steps with %d STEP_OK, got %r (steps=%d, ok=%d)"
             % (name, "+".join(want), declared, finished, kinds, n, done))

# ---- the headline each arm hangs on (positive first, K2) --------------------
for name, want in (("last-repaired", "REPAIRED 1"), ("later-repaired", "REPAIRED 1"),
                   ("last-rejected", "FAKE FIX REJECTED 1"), ("later-rejected", "FAKE FIX REJECTED 1"),
                   ("both", "REPAIRED 1"), ("both", "FAKE FIX REJECTED 1"),
                   ("no-repair", "REPAIRED 0")):
    if want in out[name]:
        pas("%s: the footer counts %s" % (name, want))
    else:
        bad_("%s: footer does not read %s: %r" % (name, want, re.findall(r"CAUGHT.*", out[name])))

# ---- the detail line is TRUE here: there is a REPAIR_FAIL in this run -------
# This is the positive half of the "no invented fake fix" assertion further
# down. Without it, renaming the sentence would make that negative pass forever.
for name in ("last-rejected", "later-rejected"):
    if "fake fix" in out[name] and "REPAIR_FAIL" in out[name]:
        pas("%s: the rejected repair is drawn as a fake fix -> REPAIR_FAIL, which is what the ledger says" % name)
    else:
        bad_("%s: a real REPAIR_FAIL is not rendered: %r" % (name, out[name]))

# ---- the range: forward when later steps exist, absent when they do not -----
for name in ("later-repaired", "later-rejected", "both"):
    if "steps 2–3" in out[name]:
        pas("%s: the saved: line names the steps that really follow the catch (steps 2–3)" % name)
    else:
        bad_("%s: the run has steps 2 and 3 after the catch, the line does not say so: %r"
             % (name, saved_line(out[name])))

# ---- a refused repair is not a STOP when a later attempt was accepted -------
# `both` was caught, had one fix REFUSED, took a proven one, and finished all
# three steps. The line branched on `rejected` first, so it printed "STOP, steps
# 2–3 NEVER ran on a blind base" over three STEP_OKs. The positive that holds
# this negative up is the line right below it: on the run that really did stop,
# the words are still there.
if "NEVER ran" not in out["both"] and "STOP" not in saved_line(out["both"]):
    pas("both: a refused attempt followed by a proven repair is not reported as a STOP")
else:
    bad_("both: the run finished 3 steps and the line still claims a STOP: %r" % saved_line(out["both"]))
if "NEVER ran" in saved_line(out["later-rejected"]):
    pas("later-rejected: the run that really stopped still says its steps NEVER ran")
else:
    bad_("later-rejected: a fail-closed run lost the words NEVER ran: %r" % saved_line(out["later-rejected"]))
if "a fake fix REFUSED, then a repair PROVEN" in out["both"]:
    pas("both: the line reports both halves — the refusal and the repair that passed")
else:
    bad_("both: the refused attempt is missing from the line: %r" % saved_line(out["both"]))
for name in ("last-repaired", "last-rejected"):
    if re.search(r"\bstep 1 of 1\b", saved_line(out[name])):
        pas("%s: with nothing after the catch the line says step 1 of 1, not a range" % name)
    else:
        bad_("%s: the catch is the last step, the line still invents a range: %r"
             % (name, saved_line(out[name])))

# ---- NEGATIVE 1: no range may count backwards ------------------------------
for name, so in sorted(out.items()):
    back = [(a, b) for a, b in re.findall(r"steps (\d+)–(\d+)", so) if int(a) > int(b)]
    if back:
        bad_("%s: a step range counts backwards: %r" % (name, back))
    else:
        pas("%s: every step range printed runs forwards" % name)

# ---- NEGATIVE 2: no step number that is not in the run ---------------------
# The general form of the hardcoded "step 10": every number the render attaches
# to the word step has to be inside 1..N for THAT run.
for name, so in sorted(out.items()):
    n = SHAPE[name][1]
    seen = set()
    for a, b in re.findall(r"steps? (\d+)(?:–(\d+))?", so):
        seen.add(int(a))
        if b:
            seen.add(int(b))
    outside = sorted(x for x in seen if x < 1 or x > n)
    if outside:
        bad_("%s: the render names step(s) %r over a %d-step run" % (name, outside, n))
    else:
        pas("%s: every step number on screen (%s) is a step this %d-step run really had"
            % (name, ",".join(str(x) for x in sorted(seen)) or "-", n))

# ---- NEGATIVE 3: the zero-repair run invents nothing ------------------------
# The four strings the discovery run found on a ledger with no REPAIR_* in it.
# Each one is asserted PRESENT on the rejected/repaired arms above, so this is
# not a check that passes by renaming.
for token in ("fake fix", "REPAIR_FAIL", "repaired", "step 10"):
    if token in out["no-repair"]:
        bad_("no-repair: %r is on screen over a run whose ledger has no REPAIR event" % token)
    else:
        pas("no-repair: %r never appears — nothing was proposed, so nothing is reported" % token)

print("  --- %d ok, %d failed" % (ok, bad))
sys.exit(1 if bad else 0)
PY
PY2RC=$?

# ---------------------------------------------------------------------------
# arm J: the A/B saving is an ACCUMULATIVE total, and it may not be claimed
#        over a ledger that is known to have lost a line.
#
# Every other number on this screen is convergent — one value per run that the
# newest event overwrites, so a lost line leaves a stale value that the next
# line for that run repairs, and a run missing its RUN_DONE prints "?" where a
# reader can see it. The saving is not: it is a DIFFERENCE of two sums folded
# with +=, so one missing line is a permanent offset nothing later corrects,
# and it is invisible — the sum still prints, only smaller.
#
# The loss is not hypothetical. chain.h fails OPEN on purpose: an emitter that
# cannot take the day file's cross-language lock writes its line to a sibling
# `<day>.unchained.jsonl` instead of appending unchained into a chained file.
# The fixture below is a two-arm A/B whose honest answer is "$0.6000 kept
# (30%)". Move ONE escalated STEP_TRY — $1.00, on the routed side — into that
# sibling, exactly as chain.h would, and the claim used to read "$1.6000 kept
# (80%)" at exit 0: 2.7x, in rabadon's own favour, on the surface README says
# ends up in a screenshot.
#
# Second source, same accumulator: the `.head` sidecar commits how many chained
# lines the file has, so a line lifted out and the chain re-stitched leaves a
# file shorter than its own commitment — the attack audit.cpp exists to convict.
# Both arrive as a smaller number and neither announces itself, so they are
# summed and the claim is refused until the ledger is reconciled.
echo "trace: the A/B saving is refused over a ledger that lost a line"

ABOX=$(mktemp -d /tmp/rabadon-accum-box.XXXXXX)
mkdir -p "$ABOX/spool"
ADAY=$(date -u +%Y-%m-%d)
python3 - "$ABOX/spool/$ADAY.jsonl" <<'PY3'
import sys, time
path = sys.argv[1]
now = int(time.time() * 1000)
def L(seq, run, ev):
    return '{"v":1,"seq":%d,"ts":%d,"run":"%s","pipe":"demo:do",%s}\n' % (seq, now + seq, run, ev)
rows = [
  L(1,"ab-control",'"ev":"RUN_START","arm":"control","tiers":"sonnet","steps":2'),
  L(2,"ab-control",'"ev":"STEP_START","step":"s1"'),
  L(3,"ab-control",'"ev":"STEP_TRY","step":"s1","tier":2,"tier_name":"sonnet","model":"claude-sonnet","tokens":100000,"usd_e6":1000000,"dur_ms":100'),
  L(4,"ab-control",'"ev":"STEP_OK","step":"s1","tier":2,"tier_name":"sonnet"'),
  L(5,"ab-control",'"ev":"STEP_START","step":"s2"'),
  L(6,"ab-control",'"ev":"STEP_TRY","step":"s2","tier":2,"tier_name":"sonnet","model":"claude-sonnet","tokens":100000,"usd_e6":1000000,"dur_ms":100'),
  L(7,"ab-control",'"ev":"STEP_OK","step":"s2","tier":2,"tier_name":"sonnet"'),
  L(8,"ab-control",'"ev":"RUN_DONE","verdict":"PASS"'),
  L(9,"ab-routed",'"ev":"RUN_START","arm":"routed","tiers":"haiku,sonnet","steps":2'),
  L(10,"ab-routed",'"ev":"STEP_START","step":"s1"'),
  L(11,"ab-routed",'"ev":"STEP_TRY","step":"s1","tier":1,"tier_name":"haiku","model":"claude-haiku","tokens":100000,"usd_e6":200000,"dur_ms":50'),
  L(12,"ab-routed",'"ev":"STEP_OK","step":"s1","tier":1,"tier_name":"haiku"'),
  L(13,"ab-routed",'"ev":"STEP_START","step":"s2"'),
  L(14,"ab-routed",'"ev":"STEP_TRY","step":"s2","tier":1,"tier_name":"haiku","model":"claude-haiku","tokens":100000,"usd_e6":200000,"dur_ms":50'),
  L(15,"ab-routed",'"ev":"ESCALATE","step":"s2","from":"haiku","to":"sonnet"'),
  L(16,"ab-routed",'"ev":"STEP_TRY","step":"s2","tier":2,"tier_name":"sonnet","model":"claude-sonnet","tokens":100000,"usd_e6":1000000,"dur_ms":100'),
  L(17,"ab-routed",'"ev":"STEP_OK","step":"s2","tier":2,"tier_name":"sonnet"'),
  L(18,"ab-routed",'"ev":"RUN_DONE","verdict":"PASS"'),
]
open(path, "w").write("".join(rows))
PY3

# --- J1 POSITIVE CONTROL: intact ledger, the claim IS made, and it is 30% ----
# Without this the two refusals below would also pass on a binary that simply
# never prints a saving.
AOUT=$(RABADON_DIR="$ABOX" ./native/rabadon-trace --no-color 2>&1)
if printf '%s' "$AOUT" | grep -q '\$0.6000 kept (30%)'; then
  pass "(J1) over the intact ledger the saving is claimed, and it is \$0.6000 kept (30%)"
else
  fail "(J1) the intact fixture does not print the honest saving: $(printf '%s' "$AOUT" | grep -i 'delta\|kept')"
fi
if printf '%s' "$AOUT" | grep -q "NOT RECONCILED"; then
  fail "(J1) an intact ledger was called unreconciled — the guard fires on a clean file"
else
  pass "(J1) ...and nothing on an intact ledger is called unreconciled"
fi

# --- J2: one event down chain.h's fail-open path -> no claim ----------------
python3 - "$ABOX/spool/$ADAY.jsonl" <<'PY3'
import sys
day = sys.argv[1]
keep, moved = [], []
for l in open(day).read().splitlines(True):
    (moved if '"seq":16' in l else keep).append(l)
open(day, "w").write("".join(keep))
# chain.h's exact fail-open shape: no prev, an "unlocked" marker, the sibling.
open(day.replace(".jsonl", ".unchained.jsonl"), "w").write(
    "".join(l.replace("}\n", ',"unlocked":true}\n') for l in moved))
PY3
touch "$ABOX/spool/$ADAY.jsonl"
AOUT2=$(RABADON_DIR="$ABOX" ./native/rabadon-trace "$ABOX/spool/$ADAY.jsonl" --no-color 2>&1)
if printf '%s' "$AOUT2" | grep -q "NOT RECONCILED"; then
  pass "(J2) one line in the .unchained sibling and the saving is refused, not recomputed"
else
  fail "(J2) a short ledger still claimed a saving: $(printf '%s' "$AOUT2" | grep -i 'delta\|kept')"
fi
# the NEGATIVE that gives J2 its teeth: the wrong number must be absent, and
# 80% is the specific wrong number this ledger produces.
if printf '%s' "$AOUT2" | grep -q "kept"; then
  fail "(J2) the word kept survives the refusal: $(printf '%s' "$AOUT2" | grep kept)"
else
  pass "(J2) ...and the words \"kept\" and the 80% claim are nowhere on screen"
fi
# the two arm rows still print — the refusal is about the DIFFERENCE, and
# hiding the evidence would be its own kind of lie.
if printf '%s' "$AOUT2" | grep -q "MEASURED A/B"; then
  pass "(J2) ...while the two arms themselves still render, marked, not hidden"
else
  fail "(J2) the refusal swallowed the whole A/B block"
fi

# --- J2b: the `--run` path reads BOTH files and is still short -------------
# The first cut of the guard exempted a sibling that this same render had read,
# on the reasoning that its lines were then inside the sums. They are not:
# candidates are collected newest-first and reversed, so the older sibling is
# concatenated FIRST, its STEP_TRY reaches render_routed before the STEP_START
# that opens the node, and it is dropped on arrival. With the exemption in, the
# whole suite above passed and `--run` — the path the docs teach — still printed
# "$1.6000 kept (80%)". So the sibling counts whether it was read or not.
touch "$ABOX/spool/$ADAY.unchained.jsonl"; sleep 1; touch "$ABOX/spool/$ADAY.jsonl"
AOUT2B=$(RABADON_DIR="$ABOX" ./native/rabadon-trace --run ab- --no-color 2>&1)
if printf '%s' "$AOUT2B" | grep -q "NOT RECONCILED" && ! printf '%s' "$AOUT2B" | grep -q "kept"; then
  pass "(J2b) --run reads the sibling too and STILL refuses — reading bytes is not folding them"
else
  fail "(J2b) --run claimed a saving over a ledger that fell open: $(printf '%s' "$AOUT2B" | grep -i 'kept\|RECONCIL')"
fi

# --- J3: the sidecar's absolute count is the other loss source --------------
# Restore the sibling's line, then commit a count HIGHER than the file holds:
# a line lifted out and the chain re-stitched. The sums look complete; the
# absolute number written under the same lock says they are not.
rm -f "$ABOX/spool/$ADAY.unchained.jsonl"
python3 - "$ABOX/spool/$ADAY.jsonl" <<'PY3'
import sys
day = sys.argv[1]
rows = open(day).read().splitlines(True)
rows.append('{"v":1,"seq":16,"ts":%s,"run":"ab-routed","pipe":"demo:do","ev":"STEP_TRY","step":"s2","tier":2,"tier_name":"sonnet","model":"claude-sonnet","tokens":100000,"usd_e6":1000000,"dur_ms":100,"prev":"genesis"}\n'
            % rows[0].split('"ts":')[1].split(',')[0])
rows.sort(key=lambda l: int(l.split('"seq":')[1].split(',')[0]))
open(day, "w").write("".join(rows))
PY3
# 1 chained line in the file (the one carrying prev), the sidecar swears 4.
printf '%s 4\n' "$(printf '0%.0s' $(seq 64))" > "$ABOX/spool/$ADAY.jsonl.head"
AOUT3=$(RABADON_DIR="$ABOX" ./native/rabadon-trace "$ABOX/spool/$ADAY.jsonl" --no-color 2>&1)
if printf '%s' "$AOUT3" | grep -q "sidecar commits"; then
  pass "(J3) a sidecar committing more lines than the file holds also refuses the claim"
else
  fail "(J3) the .head line count is not consulted before the money claim: $(printf '%s' "$AOUT3" | grep -i 'delta\|kept\|RECONCIL')"
fi

rm -rf "$ABOX"

# ---- K: the fail-open sibling must never stand in for its day ledger --------
# jsonls() sorts newest first with the path breaking ties, and
# "<day>.unchained.jsonl" > "<day>.jsonl", so two files touched in the same
# second (ordinary) put the sibling first and the no-run-id branch renders
# all.front() -- the sibling -- while the day's events stay invisible.
KBOX=$(mktemp -d); mkdir -p "$KBOX/spool"
KDAY=$(date -u +%Y-%m-%d)
python3 - "$KBOX/spool/$KDAY.jsonl" "$KBOX/spool/$KDAY.unchained.jsonl" <<'PYK'
import sys, time
day, sib = sys.argv[1], sys.argv[2]
ts = int(time.time() * 1000)
rows = []
rows.append('{"v":1,"seq":1,"ts":%d,"run":"k-real","pipe":"demo:do","ev":"RUN_START","prev":"genesis"}' % ts)
rows.append('{"v":1,"seq":2,"ts":%d,"run":"k-real","pipe":"demo:do","ev":"STEP_START","step":"s1"}' % ts)
rows.append('{"v":1,"seq":3,"ts":%d,"run":"k-real","pipe":"demo:do","ev":"STEP_TRY","step":"s1","tier":1,"tier_name":"haiku","model":"claude-haiku","tokens":10,"usd_e6":1000,"dur_ms":10}' % ts)
rows.append('{"v":1,"seq":4,"ts":%d,"run":"k-real","pipe":"demo:do","ev":"RUN_DONE","ok":true}' % ts)
open(day, "w").write("\n".join(rows) + "\n")
open(sib, "w").write('{"v":1,"seq":9,"ts":%d,"run":"k-orphan","pipe":"demo:do","ev":"STEP_TRY","step":"s9","tier":1,"tier_name":"haiku","model":"claude-haiku","tokens":1,"usd_e6":1,"dur_ms":1}\n' % ts)
PYK
# same mtime is the case that used to lose; force it so the tie-break decides
touch -t 202608011200 "$KBOX/spool/$KDAY.jsonl" "$KBOX/spool/$KDAY.unchained.jsonl"
KOUT=$(RABADON_DIR="$KBOX" ./native/rabadon-trace --no-color 2>&1)
if printf '%s' "$KOUT" | grep -q "k-real"; then
  pass "(K) the day ledger renders even when the sibling wins the mtime tie"
else
  fail "(K) the sibling was rendered instead of the day ledger: $(printf '%s' "$KOUT" | head -3)"
fi
if printf '%s' "$KOUT" | grep -q "k-orphan"; then
  fail "(K2) the sibling was concatenated into the day render"
else
  pass "(K2) the sibling is not rendered as a ledger of its own"
fi
rm -rf "$KBOX"

rm -rf "$BOX" "$REPO" "$WBOX" "$SAVED"
if [ $PYRC -ne 0 ]; then bad=$((bad+1)); fi
if [ $PY2RC -ne 0 ]; then bad=$((bad+1)); fi
echo "  --- $ok ok, $bad failed (shell arm)"
[ $bad -eq 0 ] || exit 1
exit 0
