#!/usr/bin/env python3
"""allowlist.py — refuse to publish a project name nobody decided to publish.

THE HOLE THIS CLOSES. site/redact.py withholds names on a PRIVATE list kept at
~/.rabadon/redact/projects.txt, deliberately outside this tree. That makes the
check default-ALLOW and unenforceable off the operator's machine: CI has no
such file, so name-based withholding does nothing there and the suite goes
green on blindness. Measured 2026-08-17: 58 distinct project names were
published in site/ artifacts and zero of them were on the private list.

So this module asks the opposite question — not "is this name secret?" but
"was this name allowed?" — against site/published-projects.txt, which is
public and committed. A name that nobody has decided about is a failure, not a
default publish. CI can enforce it without learning a private name.

  python3 site/allowlist.py            # scan site/, exit 1 if anything is off-list
  python3 site/allowlist.py --list     # print the names found and their verdict
  RABADON_SITE_DIR=... RABADON_ALLOWLIST=...  point it at a fixture

KNOWN LIMIT, with a number rather than an adjective: this reads the project
name a record DECLARES — the `project` field of the JSON and JSONL artifacts,
which are the sources the HTML pages are rendered from. It does not tokenize
free text, so a name embedded inside an identifier is out of scope here: the
one real leak found on 2026-08-17 was the rule id `no-blanket-add-stitchu`,
where the project name was part of the id and no `project` field carried it.
That class is caught by redact.py's content pass, and only where the private
list has the term. Closing it against an allowlist means tokenizing every
identifier, which needs its own decision about what a token is.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SITE_DIR = os.environ.get("RABADON_SITE_DIR", HERE)
ALLOWLIST = os.environ.get("RABADON_ALLOWLIST",
                           os.path.join(HERE, "published-projects.txt"))

# the artifacts that DECLARE a project per record. The HTML pages are rendered
# from these, so covering the sources covers the pages.
SOURCES = ("measured.json", "rule_census.json", "field.jsonl")


def load_allowed(path=ALLOWLIST):
    """The names that may be published. Missing file means nothing is allowed —
    fail closed, because an absent allowlist must not read as 'publish
    everything'."""
    allowed = set()
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if line:
                    allowed.add(line)
    except FileNotFoundError:
        return allowed
    return allowed


def _collect(node, found):
    """Every value of a `project` key, at any depth."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "project" and isinstance(v, str) and v:
                found[v] = found.get(v, 0) + 1
            else:
                _collect(v, found)
    elif isinstance(node, list):
        for item in node:
            _collect(item, found)


def names_in(site_dir=None):
    """{project name: how many records declare it} across the artifacts."""
    site_dir = site_dir or SITE_DIR
    found = {}
    for name in SOURCES:
        path = os.path.join(site_dir, name)
        if not os.path.isfile(path):
            continue
        if name.endswith(".jsonl"):
            with open(path, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        _collect(json.loads(line), found)
                    except ValueError:
                        continue
        else:
            try:
                with open(path, encoding="utf-8") as f:
                    _collect(json.load(f), found)
            except ValueError:
                continue
    return found


def offenders(site_dir=None, allowlist=None):
    """{name: count} for every published project name that is not allowed."""
    allowed = load_allowed(allowlist or ALLOWLIST)
    return {n: c for n, c in names_in(site_dir).items() if n not in allowed}


def main(argv):
    show_all = "--list" in argv
    found = names_in()
    allowed = load_allowed()
    bad = {n: c for n, c in found.items() if n not in allowed}

    if show_all:
        for name, count in sorted(found.items(), key=lambda kv: (-kv[1], kv[0])):
            mark = "allowed" if name in allowed else "OFF-LIST"
            print("%-9s %6d  %s" % (mark, count, name))
        print("\n%d name(s) found, %d allowed, %d off-list"
              % (len(found), len(found) - len(bad), len(bad)))

    if not bad:
        if not show_all:
            print("allowlist: %d project name(s) published, all of them allowed."
                  % len(found))
        return 0

    print("allowlist: %d project name(s) are published without a decision to "
          "publish them." % len(bad))
    print("  the artifacts scanned : %s" % ", ".join(SOURCES))
    print("  the allowlist         : %s" % ALLOWLIST)
    for name, count in sorted(bad.items(), key=lambda kv: (-kv[1], kv[0])):
        print("    %6d record(s)  %s" % (count, name))
    print("  Each one is a disclosure decision. Add the names that may be "
          "public to the allowlist, with the reason; make redact.py withhold "
          "the rest.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
