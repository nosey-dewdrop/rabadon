#!/usr/bin/env python3
"""repair_census.py — account for every REPAIR_START in the ledger.

WHY THIS EXISTS
    The ledger records that a repair was ATTEMPTED far more often than it
    records how the attempt ENDED. Before this ran, `rabadon stats` counted
    attempts whose outcome nobody could name. This walks the spool and says,
    for each REPAIR_START: it held, it did not hold and here is the class, or
    the ledger does not say — and when the ledger does not say, that is the
    answer, written down, not a gap to be filled in.

THE ONE RULE
    A classification without a pointer to the line that proves it is an
    opinion. Every row here names the exact day file and line number of the
    closing event, so anybody can open that line and disagree.

WHY THE WINDOW COMES FROM THE GATE, NOT FROM ME
    The historical window is the set of byte prefixes pinned inside
    reports/phase-1/accept.sh, which was written by a different agent before
    this phase started. If this tool picked its own window it could pick a
    flattering one — end the scan before a bad week, or extend it into events
    this phase itself emitted. It reads the gate's pins instead, so the window
    is not ours to choose.

USAGE
    python3 scripts/repair_census.py [--spool DIR] [--out DIR]
"""

import argparse
import hashlib
import json
import os
import re
import sys

TERMINAL_EVS = {"REPAIR_OK", "REPAIR_FAIL", "REPAIR_FLAKY", "REPAIR_CLOSE"}
CLASSES = ["REPAIR_FAIL", "FLAKY", "test-tamper", "harness-tamper",
           "proposer-empty", "timeout"]
DIST_KEYS = ["held"] + CLASSES + ["unclassified"]

# first match wins, and the order is the whole point: "proposer timed out" is a
# timeout, not an empty proposer. Bucketing a specific reason into the generic
# REPAIR_FAIL keeps the count right and makes the reason wrong.
MARKERS = (("test-tamper", "test-tamper"),
           ("harness-tamper", "harness-tamper"),
           ("timed out", "timeout"),
           ("timeout", "timeout"),
           ("flaky", "FLAKY"),
           ("proposer", "proposer-empty"))


def classify(ev, why):
    """(outcome, class) from a closing event's own fields."""
    if ev == "REPAIR_OK":
        return "held", "-"
    if ev == "REPAIR_FLAKY":
        return "not-held", "FLAKY"
    w = (why or "").lower()
    for needle, cls in MARKERS:
        if needle in w:
            return "not-held", cls
    return "not-held", "REPAIR_FAIL"


def read_pins(gate_path):
    """The sealed window, taken from the gate that will judge this table."""
    pins = []
    with open(gate_path, encoding="utf-8") as fh:
        inside = False
        for line in fh:
            s = line.strip()
            if s == "cat >\"$PIN_FILE\" <<'PINS'":
                inside = True
                continue
            if inside:
                if s == "PINS":
                    break
                m = re.match(r"^(\S+)\s+(\d+)\s+([0-9a-f]{64})$", s)
                if m:
                    pins.append((m.group(1), int(m.group(2)), m.group(3)))
    if not pins:
        sys.exit("could not read the pinned window out of %s — refusing to "
                 "invent one" % gate_path)
    return pins


def records(blob):
    for i, raw in enumerate(blob.split(b"\n"), 1):
        if not raw.strip():
            continue
        try:
            o = json.loads(raw.decode("utf-8", "replace"))
        except Exception:
            continue
        if isinstance(o, dict):
            yield i, o


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--spool", default=os.path.join(
        os.environ.get("RABADON_DIR", os.path.expanduser("~/.rabadon")), "spool"))
    ap.add_argument("--out", default=os.path.join(here, "reports", "phase-1"))
    ap.add_argument("--gate", default=os.path.join(here, "reports", "phase-1", "accept.sh"))
    args = ap.parse_args()

    pins = read_pins(args.gate)
    os.makedirs(args.out, exist_ok=True)

    starts = {}       # (file, line) -> record
    terminals = {}    # (file, line) -> record
    verified = 0
    for name, size, sha in pins:
        path = os.path.join(args.spool, name)
        if not os.path.exists(path):
            sys.exit("pinned ledger file %s is missing; nothing can be counted" % name)
        with open(path, "rb") as fh:
            blob = fh.read(size)
        got = hashlib.sha256(blob).hexdigest()
        if got != sha:
            sys.exit("%s no longer hashes to its pinned prefix. history was "
                     "rewritten; every number below would be void." % name)
        verified += 1
        for i, o in records(blob):
            ev = o.get("ev")
            if ev == "REPAIR_START":
                starts[(name, i)] = o
            elif ev in TERMINAL_EVS:
                terminals[(name, i)] = o

    # One closing event closes one repair. Each terminal takes the NEAREST
    # PRECEDING unmatched start in the same day file with the same run and
    # attempt. Pairing on `step` instead would be wrong: gate.cpp opens with
    # step "diagnose" and can close with step "new gate: <id>".
    pairing = {}
    consumed = set()
    for (tname, tline) in sorted(terminals):
        t = terminals[(tname, tline)]
        key = (t.get("run"), t.get("attempt"))
        cands = [(sn, sl) for (sn, sl), s in starts.items()
                 if sn == tname and sl < tline
                 and (s.get("run"), s.get("attempt")) == key
                 and (sn, sl) not in consumed]
        if cands:
            pick = max(cands)
            consumed.add(pick)
            pairing[pick] = (tname, tline)

    counts = dict((k, 0) for k in DIST_KEYS)
    rows = []
    for key in sorted(starts):
        sname, sline = key
        s = starts[key]
        run, attempt = str(s.get("run")), str(s.get("attempt"))
        if key not in pairing:
            rows.append([sname, str(sline), run, attempt, "unclassified", "-", "-", "-"])
            counts["unclassified"] += 1
            continue
        ename, eline = pairing[key]
        t = terminals[(ename, eline)]
        outcome, cls = classify(t.get("ev"), t.get("why"))
        rows.append([sname, str(sline), run, attempt, outcome, cls, ename, str(eline)])
        counts["held" if outcome == "held" else cls] += 1

    cls_path = os.path.join(args.out, "classified.tsv")
    with open(cls_path, "w", encoding="utf-8") as fh:
        fh.write("start_file\tstart_line\trun\tattempt\toutcome\tclass\tev_file\tev_line\n")
        for r in rows:
            fh.write("\t".join(r) + "\n")

    dist_path = os.path.join(args.out, "distribution.tsv")
    with open(dist_path, "w", encoding="utf-8") as fh:
        fh.write("key\tcount\n")
        for k in DIST_KEYS:
            fh.write("%s\t%d\n" % (k, counts[k]))

    print("scanned %d pinned day file(s), every prefix hashed as sealed" % verified)
    print("REPAIR_START ....... %d" % len(starts))
    print("closed ............. %d" % len(pairing))
    print("UNCLASSIFIED ....... %d" % counts["unclassified"])
    print()
    for k in DIST_KEYS:
        print("  %-16s %d" % (k, counts[k]))
    print()
    print("wrote %s" % os.path.relpath(cls_path, here))
    print("wrote %s" % os.path.relpath(dist_path, here))
    if counts["unclassified"] == 0:
        print("NOTE: zero unclassified on this ledger would be a bug in this tool,"
              " not a clean result.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
