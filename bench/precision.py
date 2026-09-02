#!/usr/bin/env python3
"""What the gate refused, and how often the operator said it was wrong.

THE ONE NUMBER A STRANGER ASKS FOR. Latency says the gate is cheap; the ledger
says how much it did. Neither answers "will it get in my way", and that is the
question that decides whether a guard survives its first afternoon. rabadon
already records both halves: a STOP is a refusal that happened, and
`rabadon wrong <rule> "<why>"` writes a WRONG_REFUSAL — the operator, after the
fact, saying that refusal should not have fired. The rate is the quotient.

Reads only the local ledger. No network, no model call, no arguments.
Usage: python3 bench/precision.py [--since YYYY-MM-DD]
"""
import json, glob, os, sys, collections, datetime

SPOOL = os.path.expanduser(os.environ.get("RABADON_SPOOL", "~/.rabadon/spool"))
since = None
if "--since" in sys.argv:
    since = sys.argv[sys.argv.index("--since") + 1]

stops = collections.Counter(); wrongs = collections.Counter()
by_day = collections.defaultdict(lambda: [0, 0])
examples = {}
for f in sorted(glob.glob(os.path.join(SPOOL, "*.jsonl"))):
    for line in open(f, errors="replace"):
        if not line.strip():
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        ev = d.get("ev")
        if ev not in ("STOP", "WRONG_REFUSAL") or not d.get("ts"):
            continue
        day = datetime.datetime.fromtimestamp(d["ts"] / 1000).strftime("%Y-%m-%d")
        if since and day < since:
            continue
        rule = d.get("rule", "?")
        if ev == "STOP":
            stops[rule] += 1; by_day[day][0] += 1
            examples.setdefault(rule, str(d.get("detail", ""))[:88].replace("\n", " "))
        else:
            wrongs[rule] += 1; by_day[day][1] += 1

S, W = sum(stops.values()), sum(wrongs.values())
if not S:
    print("no refusals in the ledger" + (f" since {since}" if since else "")); sys.exit(0)

label = f"since {since}" if since else f"{len(by_day)} days"
print(f"refusals {label}: {S}    declared wrong by the operator: {W}    "
      f"false-positive rate: {100*W/S:.1f}%")
print("\n  %-34s %8s %7s %6s" % ("rule", "refused", "wrong", "rate"))
for rule, n in stops.most_common():
    w = wrongs.get(rule, 0)
    print("  %-34s %8d %7d %5.0f%%   %s" % (rule, n, w, 100*w/n, examples.get(rule, "")[:52]))
extra = [r for r in wrongs if r not in stops]
if extra:
    print("\n  wrong refusals whose rule no longer refuses (renamed or retired):")
    for r in extra:
        print("    %-32s %d" % (r, wrongs[r]))
