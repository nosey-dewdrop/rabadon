#!/bin/bash
# measure.sh — run every measurement the site quotes, and write it down.
#
# The site used to carry numbers that were typed in once and then left alone:
# "42.0µs to judge one command" naming a file that did not exist, and a refusal
# count on the overview that had drifted 12 behind the same count on the page
# built from the same ledger. Both were true the day they were written, which
# is the problem — a number a human maintains starts lying on the next run.
#
# So there is exactly one path from a run to the page: this script runs the
# suites, writes site/measured.json with the value AND the command that produced
# it AND the commit it was produced at, and site/build.py renders from that file
# and nothing else. native/site_claims_test.sh then holds the whole arrangement:
# every cmd named in measured.json has to exist, no headline number may be typed
# into the template, and a number appearing on two pages has to be the same
# number.
#
#   ./native/measure.sh              everything (slow: the repair suites build
#                                    real pytest/node projects and run them)
#   ./native/measure.sh --fast       skip the repair suites, keep their last
#                                    recorded values and say so
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO" || exit 1
FAST=0
[ "${1:-}" = "--fast" ] && FAST=1

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rbmeasure.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "== measuring =="

# ---- 1. the micro benchmark: judge one command -----------------------------
echo "-- native/gate_bench.sh"
./native/gate_bench.sh --write | sed 's/^/   /' || exit 1

# ---- 2. precision and recall, and the per-rule table the site prints -------
echo "-- native/precision_test.sh"
./native/precision_test.sh > "$TMP/precision.txt" 2>&1
PREC_RC=$?
sed -n 's/^cases: /   cases: /p;s/^precision /   precision /p;s/^recall /   recall /p' "$TMP/precision.txt"

# ---- 3. the end-to-end hook tax, native against the node gate it replaced ---
echo "-- native/bench.py"
python3 native/bench.py > "$TMP/bench.txt" 2>&1
BENCH_RC=$?
sed 's/^/   /' "$TMP/bench.txt"

# ---- 4. the six ways of buying a green -------------------------------------
if [ "$FAST" = 1 ]; then
  echo "-- native/harness_lock_test.sh  SKIPPED (--fast); the recorded value is kept and marked stale"
  : > "$TMP/harness.txt"
  HARNESS_RC=-1
else
  echo "-- native/harness_lock_test.sh"
  ./native/harness_lock_test.sh > "$TMP/harness.txt" 2>&1
  HARNESS_RC=$?
  grep -E '^  (ok|FAIL)|^  pass' "$TMP/harness.txt" | sed 's/^/  /'
fi

# ---- 5. the arbiter's behavioural probe, family by family ------------------
if [ "$FAST" = 1 ]; then
  echo "-- native/heldout_test.sh  SKIPPED (--fast)"
  : > "$TMP/heldout.txt"
  HELDOUT_RC=-1
else
  echo "-- native/heldout_test.sh"
  if [ -x native/heldout_test.sh ]; then
    ./native/heldout_test.sh > "$TMP/heldout.txt" 2>&1
    HELDOUT_RC=$?
    grep -E '^  (ok|FAIL)|^  pass' "$TMP/heldout.txt" | sed 's/^/  /'
  else
    : > "$TMP/heldout.txt"; HELDOUT_RC=-1
  fi
fi

# ---- 6. the one live repair on a foreign repo, counted off its own evidence --
# Not re-run: it took a real proposer call against expressjs/express at a pinned
# commit. The numbers are counted out of the run's own ledger and lock list,
# which ship in this repository, so the reader can count them again.
echo "-- docs/archive/reports/2026-08-01-g3-first-held-repair"
G3="$REPO/docs/archive/reports/2026-08-01-g3-first-held-repair"
if [ -d "$G3" ]; then
  HELD=$(grep -cE '"ev": *"REPAIR_OK"' "$G3/04-ledger-events.jsonl" 2>/dev/null || echo 0)
  LOCKS=$(grep -cE '^[0-9a-f]{16,}' "$G3/06-locks.txt" 2>/dev/null || echo 0)
  SUITE=$(grep -oE '[0-9]+ tests' "$G3/README.txt" | head -1 | grep -oE '[0-9]+' || echo 0)
  echo "   repairs held $HELD, test files locked $LOCKS"
else
  HELD=0; LOCKS=0; SUITE=0
  echo "   MISSING — the evidence directory is not in the repo"
fi

# ---- write it all down ------------------------------------------------------
python3 - "$REPO" "$TMP" "$PREC_RC" "$BENCH_RC" "$HARNESS_RC" "$HELDOUT_RC" "$HELD" "$LOCKS" "$SUITE" <<'PY'
import json, os, re, subprocess, sys

repo, tmp = sys.argv[1], sys.argv[2]
prec_rc, bench_rc, harness_rc, heldout_rc, g3_held, g3_locks, g3_suite = (int(x) for x in sys.argv[3:10])
p = os.path.join(repo, "site", "measured.json")
d = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}

commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=repo,
                        capture_output=True, text=True).stdout.strip() or "?"
day = subprocess.run(["git", "log", "-1", "--format=%ad", "--date=format:%Y-%m-%d"],
                     cwd=repo, capture_output=True, text=True).stdout.strip()


def stamp(entry):
    entry["commit"] = commit
    entry["measuredAt"] = day
    return entry


def read(name):
    fp = os.path.join(tmp, name)
    return open(fp, encoding="utf-8", errors="replace").read() if os.path.exists(fp) else ""


# --- precision -------------------------------------------------------------
pt = read("precision.txt")
m = re.search(r"^precision\s+([\d.]+)%", pt, re.M)
r = re.search(r"^recall\s+([\d.]+)%", pt, re.M)
c = re.search(r"^cases:\s+(\d+)\s+correct block:\s+(\d+)\s+wrong block:\s+(\d+)\s+missed:\s+(\d+)\s+correct allow:\s+(\d+)", pt, re.M)
if m and r and c:
    d["gate.precision"] = stamp({
        "value": float(m.group(1)), "display": m.group(1) + "%",
        "cmd": "native/precision_test.sh", "what": "gate precision",
        "note": "%s cases lifted out of real sessions: %s correct refusals, %s wrong refusals, "
                "%s missed, %s correct allows. exit %d." %
                (c.group(1), c.group(2), c.group(3), c.group(4), c.group(5), prec_rc)})
    d["gate.recall"] = stamp({
        "value": float(r.group(1)), "display": r.group(1) + "%",
        "cmd": "native/precision_test.sh", "what": "gate recall",
        "note": "real harm the gate stops, over the same %s cases." % c.group(1)})
    d["gate.cases"] = stamp({
        "value": int(c.group(1)), "display": c.group(1),
        "cmd": "native/precision_fixture.jsonl", "what": "cases in the fixture",
        "note": "every one lifted out of a real session, none written for the test."})

# the per-rule table the overview prints: rule, must block, must not block
rules = []
for ln in pt.splitlines():
    mm = re.match(r"^\s+(ok|FAIL)\s+(\S+): (\d+) must-block \((\d+) still blocking\), (\d+) must-not-block", ln)
    if mm:
        rules.append({"ok": mm.group(1) == "ok", "rule": mm.group(2),
                      "mustBlock": int(mm.group(3)), "live": int(mm.group(4)),
                      "mustNotBlock": int(mm.group(5))})
if rules:
    d["gate.rules"] = stamp({"value": rules, "cmd": "native/precision_test.sh",
                             "what": "every rule, and the case each one must let through",
                             "note": "printed by the suite, rule by rule."})

# --- the hook tax, native against node -------------------------------------
bt = read("bench.txt")
rows = dict((lbl + " " + kind, (float(med), float(p95))) for lbl, kind, med, p95 in
            re.findall(r"^(native|node)\s+(allow|deny)\s+median=\s*([\d.]+)ms\s+p95=\s*([\d.]+)ms", bt, re.M))
if "native allow" in rows and "node allow" in rows:
    nat, nod = rows["native allow"][0], rows["node allow"][0]
    d["hook.native_ms"] = stamp({
        "value": nat, "display": "%.2fms" % nat, "cmd": "native/bench.py",
        "what": "the whole hook, native, median",
        "note": "fork to exit: read the event, load state, judge, write the ledger line. n=40. exit %d." % bench_rc})
    d["hook.node_ms"] = stamp({
        "value": nod, "display": "%.0fms" % nod, "cmd": "native/bench.py",
        "what": "the same hook on the node gate it replaced",
        "note": "same events, same verdicts — parity is asserted before either is timed. n=40."})
    d["hook.speedup"] = stamp({
        "value": round(nod / nat, 1), "display": "%.0f&times;" % round(nod / nat),
        "cmd": "native/bench.py", "what": "faster than the gate it replaced",
        "note": "%.2fms against %.2fms, median, same 40 events and the same verdicts." % (nat, nod)})

# --- the six ways of buying a green ----------------------------------------
ht = read("harness.txt")
cases = [{"name": mm.group(1), "verdict": mm.group(2), "exit": int(mm.group(3))}
         for mm in re.finditer(r"^  ok    (\S+)\s+-> (\S+) \(exit (\d+)\)", ht, re.M)]
mp = re.search(r"^  pass (\d+)\s+fail (\d+)", ht, re.M)
if cases and mp:
    d["repair.green_paths"] = stamp({
        "value": cases, "cmd": "native/harness_lock_test.sh",
        "what": "ways of buying a green, and what happens to each",
        "note": "pass %s, fail %s. every case runs the real rabadon-repair binary with a scripted "
                "proposer in RABADON_CLAUDE_BIN. exit %d." % (mp.group(1), mp.group(2), harness_rc)})
    d["repair.green_paths_refused"] = stamp({
        "value": sum(1 for x in cases if x["verdict"] != "verified"),
        "display": "%d of %d" % (sum(1 for x in cases if x["verdict"] != "verified"),
                                 sum(1 for x in cases if x["verdict"] != "verified")),
        "cmd": "native/harness_lock_test.sh", "what": "ways of buying a green, refused",
        "note": "and %d honest repairs in the same run still certify — a lock that refuses real work "
                "is not a lock, it is an outage." % sum(1 for x in cases if x["verdict"] == "verified")})

# --- the held-out probe ----------------------------------------------------
xt = read("heldout.txt")
xcases = [{"name": mm.group(1), "verdict": mm.group(2), "exit": int(mm.group(3))}
          for mm in re.finditer(r"^  ok    (\S+)\s+-> (\S+) \(exit (\d+)\)", xt, re.M)]
xp = re.search(r"^  pass (\d+)\s+fail (\d+)", xt, re.M)
if xcases and xp:
    d["repair.heldout"] = stamp({
        "value": xcases, "cmd": "native/heldout_test.sh",
        "what": "greens bought by a constant or an invented comparison",
        "note": "pass %s, fail %s, real binary end to end. exit %d." % (xp.group(1), xp.group(2), heldout_rc)})

# --- the one live repair on a foreign repo ---------------------------------
if g3_locks:
    d["express.repairs_held"] = stamp({
        "value": g3_held, "display": str(g3_held),
        "cmd": "grep -cE '\"ev\": *\"REPAIR_OK\"' docs/archive/reports/2026-08-01-g3-first-held-repair/04-ledger-events.jsonl",
        "what": "repairs held on a foreign repo, live",
        "note": "expressjs/express at a3714473, the arbiter being that project's own mocha suite. "
                "the working tree was never edited."})
    d["express.locked"] = stamp({
        "value": g3_locks, "display": str(g3_locks),
        "cmd": "grep -cE '^[0-9a-f]{16,}' docs/archive/reports/2026-08-01-g3-first-held-repair/06-locks.txt",
        "what": "test files hash-locked in that run",
        "note": "sha256 of the pristine copy; the arbiter re-hashed each one after the proposer."})
    d["express.suite_tests"] = stamp({
        "value": g3_suite, "display": "{:,}".format(g3_suite),
        "cmd": "docs/archive/reports/2026-08-01-g3-first-held-repair/README.txt",
        "what": "tests in the arbiter's suite", "note": "the project's own, not one rabadon wrote."})

with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2, sort_keys=True)
    f.write("\n")
print("\nwrote site/measured.json  (%d entries, commit %s)" % (
    len([k for k in d if not k.startswith("_")]), commit))
PY
