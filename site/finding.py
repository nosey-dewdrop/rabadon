#!/usr/bin/env python3
"""Append one defect to site/findings.jsonl. Nothing writes that file by hand.

A defect that lives in a report directory is a defect nobody outside this
machine will ever read. The catches page already builds itself from the gate's
own spool; this is the other half of the same idea for the things rabadon FINDS
rather than refuses, in its own source and in other people's.

One line per defect, and five fields are not optional:

    repo    where it lives (rabadon, or owner/name for somebody else's code)
    file    the file the defect is in
    broke   what was actually wrong, in a sentence a reader can check
    proof   the command that demonstrates it. a finding without one is an
            opinion, and site/build.py drops it rather than showing it
    status  found · fixed · held · wontfix · reported

    python3 site/finding.py --repo rabadon --file native/gate.cpp \
        --broke "the Bash decision site was a second copy of judge_command" \
        --proof "./native/gate_bench.sh" --status fixed

    python3 site/finding.py --from-mine     # seed the 31 upstream defects
    python3 site/finding.py --list
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
PATH = os.path.join(REPO, "site", "findings.jsonl")
MINE = os.path.join(REPO, "reports", "2026-08-01-real-defect-mine", "cases.json")
STATUSES = ("found", "fixed", "held", "wontfix", "reported")


def today():
    """The repository's clock, not the wall's: a finding is dated by the commit
    it landed beside, so a re-run of this script cannot move it."""
    out = subprocess.run(["git", "log", "-1", "--format=%ad", "--date=format:%Y-%m-%d"],
                         cwd=REPO, capture_output=True, text=True)
    return out.stdout.strip() or "0000-00-00"


def slug(s, n=48):
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return s[:n].strip("-")


def load():
    rows = []
    if os.path.exists(PATH):
        for line in open(PATH, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#"):
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return rows


def save(rows):
    # sorted by date then id so the file has one canonical order and a re-seed
    # produces no diff at all when nothing changed
    rows.sort(key=lambda d: (d.get("date", ""), d.get("id", "")))
    with open(PATH, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True, ensure_ascii=False) + "\n")


def add(rows, rec, replace=True):
    """Same id twice is an update, not a duplicate: a finding that was `found`
    on Tuesday and `fixed` on Wednesday is one defect with two states, and
    printing it twice would inflate the count this file exists to be honest
    about."""
    for i, r in enumerate(rows):
        if r["id"] == rec["id"]:
            if replace:
                rec["date"] = r.get("date", rec["date"])   # first sighting wins
                rows[i] = rec
                return "updated"
            return "kept"
    rows.append(rec)
    return "added"


def from_mine(rows):
    """The 31 upstream defects, read out of the mine's own json. Each one is a
    real fix a maintainer shipped, with the source half rolled back and the
    project's own test left alone, so the proof is the project's own suite."""
    if not os.path.exists(MINE):
        sys.exit("missing " + MINE)
    d = json.load(open(MINE, encoding="utf-8"))
    n = 0
    for c in d["cases"]:
        rec = {
            "id": c["key"],
            "date": d.get("generatedAt", "")[:10] or today(),
            "repo": c["repo"],
            "file": ", ".join(c.get("sourceFiles", [])) or "?",
            "broke": c.get("subject", "").strip(),
            "proof": "git apply docs/archive/reports/2026-08-01-real-defect-mine/%s && <the project's own suite>"
                     % c.get("patch", ""),
            "status": "reported",
            "detail": "%d source line(s), %d test(s) fall, deterministic over three runs. "
                      "upstream fix %s. the test that catches it was written by the same engineer "
                      "in the same commit and was never touched." % (
                          c.get("sourceLines", 0), c.get("failingTests", 0), c.get("fixSha", "")[:12]),
        }
        if add(rows, rec) != "kept":
            n += 1
    return n


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo")
    ap.add_argument("--file", dest="fil")
    ap.add_argument("--broke")
    ap.add_argument("--proof")
    ap.add_argument("--status", choices=STATUSES)
    ap.add_argument("--detail", default="")
    ap.add_argument("--id")
    ap.add_argument("--date")
    ap.add_argument("--from-mine", action="store_true")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()

    rows = load()

    if a.list:
        for r in sorted(rows, key=lambda d: (d.get("date", ""), d.get("id", ""))):
            print("%-11s %-9s %-24s %s" % (r.get("date"), r.get("status"),
                                           r.get("repo"), r.get("broke", "")[:78]))
        print("\n%d findings in %s" % (len(rows), os.path.relpath(PATH, REPO)))
        return

    if a.from_mine:
        n = from_mine(rows)
        save(rows)
        print("seeded %d from the defect mine; %d findings total" % (n, len(rows)))
        return

    missing = [k for k in ("repo", "fil", "broke", "proof", "status") if not getattr(a, k)]
    if missing:
        ap.error("required: --" + ", --".join("file" if m == "fil" else m for m in missing))

    rec = {
        "id": a.id or (slug(a.repo) + "-" + slug(a.fil.split("/")[-1]) + "-" + slug(a.broke, 32)),
        "date": a.date or today(),
        "repo": a.repo,
        "file": a.fil,
        "broke": a.broke,
        "proof": a.proof,
        "status": a.status,
        "detail": a.detail,
    }
    what = add(rows, rec)
    save(rows)
    print("%s %s  (%d findings)" % (what, rec["id"], len(rows)))


if __name__ == "__main__":
    main()
