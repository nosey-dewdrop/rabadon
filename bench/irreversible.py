#!/usr/bin/env python3
"""How often does the gate stop something that cannot be undone?

THE ONLY CLASS WHERE "I WOULD HAVE NOTICED ANYWAY" IS NOT AN ANSWER.
Most of what a guard refuses is recoverable: a bad commit message, an action on
a red test base, a command whose output hides the verdict. Annoying, worth
refusing, and undoable — so nobody installs a tool for it, and anyone can write
those rules in a shell function in an afternoon.

The claim that survives that test is narrower: a force-push to main, a delete
that reaches outside the project, a reflog expiry, an in-place rewrite of source
with no backup, an edit that switches off the guard watching the session. Once
those run, the state is gone. This script counts only those, and separates the
operator's real work from throwaway sandboxes, because a guard measured on its
own test harness is measuring itself.

Reads the local ledger only. Usage: python3 bench/irreversible.py [--since D]
"""
import json, glob, os, sys, collections, datetime

# Rules whose subject cannot be restored by re-running something.
IRREVERSIBLE = {
    "no-rm-rf-outside", "baseline-rm-rf-outside", "baseline-delete-not-rm",
    "baseline-law-unmade", "baseline-truncating-redirect", "baseline-reflog-drop",
    "no-force-push-main", "push-gate", "guard-weaken",
    "no-shell-rewrite-of-guard-or-promise", "no-blind-inplace-source-rewrite",
    "anti-path-frozen", "no-wrangler-deploy", "no-shell-write-protected-path",
    "promise-anti-path",
}
# A refusal whose target is a scratch tree is the tool exercising itself.
SANDBOX = ("/tmp/", "/private/tmp", "_kum", "redteam", "rbpack", "hakem",
           "sandbox", "_f3g", "probe", "rbd_", "rbmeas", "k21")

SPOOL = os.path.expanduser(os.environ.get("RABADON_SPOOL", "~/.rabadon/spool"))
since = sys.argv[sys.argv.index("--since") + 1] if "--since" in sys.argv else None

real, lab, days, allday = [], 0, set(), set()
for f in sorted(glob.glob(os.path.join(SPOOL, "*.jsonl"))):
    for line in open(f, errors="replace"):
        if not line.strip():
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        if not d.get("ts"):
            continue
        day = datetime.datetime.fromtimestamp(d["ts"] / 1000).strftime("%Y-%m-%d")
        if since and day < since:
            continue
        if d.get("ev") in ("STEP_START", "STOP"):
            allday.add(day)
        if d.get("ev") != "STOP" or d.get("rule") not in IRREVERSIBLE:
            continue
        blob = str(d.get("detail", "")) + str(d.get("pipe", ""))
        if any(m in blob for m in SANDBOX):
            lab += 1
        else:
            real.append(d); days.add(day)

if not allday:
    print("no traffic in the ledger" + (f" since {since}" if since else "")); sys.exit(0)
span = len(allday)
print("days with traffic: %d    irreversible refusals: %d  (%d on real work, %d in sandboxes)"
      % (span, len(real) + lab, len(real), lab))
if real:
    print("rate on real work: %.1f per week, across %d distinct days" % (len(real) / (span / 7), len(days)))
    print("\n  %-36s %s" % ("rule", "count"))
    for r, n in collections.Counter(d.get("rule") for d in real).most_common():
        print("  %-36s %5d" % (r, n))
else:
    print("nothing irreversible was refused on real work in this window")
