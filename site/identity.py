#!/usr/bin/env python3
"""identity.py — which PROJECT a record is about, as distinct from which
DIRECTORY it was taken in.

THE DEFECT THIS MODULE NAMES. The gate writes `project = basename(cwd)`
(native/gate.cpp), and every published `project` field descends from that
string. A directory basename is not a project identity, and the published
column proved it: on 2026-08-17 the allowlist check found 72 distinct
"project" names under site/, of which a third were not projects at all — the
operator's home directory, rabadon's own probe trees, a system scratch path,
a dot-directory, the directory that CONTAINS the projects, and the residue
left behind after a withheld name was scrubbed out of a longer one.

So the count of names awaiting a disclosure decision was inflated by a data
defect, and triaging 72 strings would have been triaging the defect rather
than the disclosure.

WHAT THIS MODULE IS ALLOWED TO DO, AND WHAT IT IS NOT. It collapses labels
for IDENTITY reasons only: two spellings of one project, a label that names
no project, a marker that is not a name. It may never collapse a label
because collapsing it makes a count smaller. The difference is not a matter
of intention — it is testable, and native/identity_test.sh is where it is
tested: every rule below is a rule about what the string DENOTES, each one
has to be stated before it can fire, and a label no rule can speak for stays
exactly as it was, off-list and awaiting a human.

WHAT IT CANNOT DO, STATED PLAINLY. A ledger record carries no path — only the
basename. So `reports` cannot be resolved to the repository it is a directory
of, because two different `reports` directories exist on this machine and the
record does not say which one it was. History is not recoverable here; the fix
for that is at the source, in the gate, and it only helps records written after
it. Every label this module leaves alone it leaves alone honestly.

THREE MARKERS, NOT NAMES. A label that denotes no project is published as one
of the constants below rather than dropped, because a record whose project is
unknown is still a record, and deleting the column would turn "we cannot say"
into "there was nothing". They are constants on purpose: a distinct marker per
lab tree would publish how many lab trees exist.

  python3 site/identity.py            # print how every label in the ledger and
                                      # the site artifacts resolves, with reasons
"""

import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))

# the three things a label can denote that are not a project name.
WITHHELD = "(withheld)"        # redaction took the name out; see site/redact.py
LAB = "(lab)"                  # a tree rabadon made to exercise itself
NO_PROJECT = "(no project)"    # a real directory that is not a project root
MARKERS = (WITHHELD, LAB, NO_PROJECT)

# ---------------------------------------------------------------------------
# the laboratories, moved here from site/field_stats.py
#
# They were a private set inside the statistics generator, so the two other
# things that publish a project name — site/rule_census.py and the allowlist
# check — never saw them. One filter that three generators disagree about is
# the same failure site/redact.py was pulled out of field_stats.py to fix.
# ---------------------------------------------------------------------------

# `<name>:session` is a real session in a repo called <name>; everything here is
# a harness, a demo or a scratch tree.
# "A:session" is the scratch repository the repair harness builds: 50 REPAIR_OK
# in a single day (2026-08-05), every one with an empty detail, interleaved with
# REPAIR_FAIL — the shape of a suite walking its cases, not of work.
LAB_EXACT = {"vibecoded-demo", "llm-repair-live", "do-test:do", "do-test", "A:session"}

# prefixes, and every one of them names a tree rabadon itself creates:
#   tmp.        mktemp's own spelling
#   rabadon-    the bench harness — `rabadon-bench-<8 random chars>`, 12 of them,
#               246 records each, identical to the record
#   test-       a suite's scratch repo
#   scratch     the same, spelled out
#   rbprobe     the guard-reach probes of 2026-08-02: `git push --force origin
#               unstable`, `git reset --hard origin/unstable` — commands typed at
#               a probe, never at work
#   rbd-        the `rbd-do` / `rbd-toggle` probes; the ledger's own step text
#               says `cd /tmp/rbd-do && node fizzbuzz.js`
LAB_PREFIX = ("tmp.", "rabadon-", "test-", "scratch", "rbprobe", "rbd-")

# the fixtures the engine was proven against. Real repositories, but visited to
# BE measured, so they are reported separately from the operator's own work.
FIXTURE = {"express:session", "goose:session", "crush:session"}

# a system scratch root, which is where a mktemp tree lands and never a project.
SCRATCH_ROOTS = {"tmp", "temp", "var", "private", "folders"}

# `home` is what site/redact.py rewrites a session started in the HOME DIRECTORY
# to (from the account name, and from the dash-encoded absolute path — both
# spellings, because they were the same session all along). A home directory is
# not a project, and the label was never a name; it was a redaction.
#
# `~` is the same directory in the OTHER spelling redact.py produces — the one
# unhome() leaves in a path. The machine-wide guard lives at `~/.rabadon/
# guard.json`, so reading a project identity off that path gives `~`, and seven
# rules were published under it as though the home directory were a repository.
HOME_LABEL = "home"
HOME_PATH_LABEL = "~"

# a record with no project recorded. It is not a place and it must never be
# folded into one — a redaction may hide a fact, never invent one.
UNRECORDED = "-"

# the file for what no rule above can speak for: a label that IS a real
# directory but is not a project root, named one per line with the evidence.
# It is public and committed for the same reason site/published-projects.txt is:
# a filter nobody can read is indistinguishable from a filter that was tuned
# until the number looked better.
NON_PROJECTS = os.environ.get("RABADON_NON_PROJECTS",
                              os.path.join(HERE, "non-projects.txt"))

_WS = re.compile(r"\s+")


def load_non_projects(path=None):
    """{label: kind} from the committed list. `kind` is `lab` or `none`.

    A missing file means the list is empty, and an empty list means every label
    is judged by the structural rules alone. That is the fail-SAFE direction
    here, and it is the opposite of the allowlist's: an unknown label stays a
    project name, so it stays off-list, so it stays in front of a human. The
    danger in this file is a label being collapsed, never a label surviving."""
    out = {}
    try:
        with open(path or NON_PROJECTS, encoding="utf-8") as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if not line:
                    continue
                parts = line.split(None, 1)
                if len(parts) != 2:
                    continue
                kind, label = parts[0].strip(), parts[1].strip()
                if kind in ("lab", "none") and label:
                    out[label] = kind
    except OSError:
        return out
    return out


def spelling(label):
    """One project, one spelling.

    Whitespace becomes a dash and nothing else is touched. The rule is that
    narrow on purpose: `damla_portfolio` is the name of a real directory and
    rewriting the underscore would publish a name that exists nowhere. A SPACE
    is different — no directory in this ledger has one. A space only ever
    arrives from a guard file's self-declared `project` string (`idea garden`,
    `just ballet`), typed by a human next to a directory called `idea-garden`,
    `just-ballet`. Those are two spellings of one project, and publishing both
    counts one project twice."""
    return _WS.sub("-", (label or "").strip())


def from_guard_path(path):
    """The identity of the project a guard file governs: where it LIVES.

    `<root>/.rabadon/guard.json` -> `<root>`'s basename.

    A guard file also carries a `project` key it declares about itself, and
    that key is what the census published until now. It is a nickname, not an
    identity: of the 63 guards on this machine, 10 declare a name that is not
    their directory's, and 4 of those are a second spelling of a project the
    ledger already names the other way. Two more declare a name their directory
    does not have at all, which published a name for a project under a second
    name nobody had decided about.

    Where a project lives is a fact; what its config calls it is a preference.
    The identity is the fact — and the published census carries the guard path
    beside every rule, so a reader can check this one without the machine."""
    if not path:
        return None
    return os.path.basename(os.path.dirname(os.path.dirname(path)))


def identity_of(pipe, non_projects=None):
    """(kind, name) for a recorded label.

    kind is one of:
      project   a project identity; `name` is its one spelling
      fixture   a public repository visited to be measured
      withheld  a name redaction removed; `name` is the marker
      lab       a tree rabadon made to exercise itself
      none      a real directory that is not a project

    The order of the rules is the argument. The withheld marker is checked
    first because what is left after a scrub is residue and must never be read
    as a name; the laboratories before the general case because a lab tree can
    be spelled like anything.
    """
    np = load_non_projects() if non_projects is None else non_projects
    raw = (pipe or UNRECORDED)
    label = raw.split(":")[0]

    # 1. no project recorded.
    if not label or label == UNRECORDED:
        return ("none", NO_PROJECT)

    # 2. the residue of a redaction is not a name. site/redact.py replaces a
    #    withheld term wherever it occurs, so a directory called
    #    `<withheld>-showcase` comes out of the scrub as `(withheld)-showcase` —
    #    a string that names a project ("there is a second repository, and it is
    #    the showcase for the withheld one") while looking like it named none.
    #    One marker for every withheld project, never a distinct one each:
    #    distinct labels would publish HOW MANY there are.
    if WITHHELD in label:
        return ("withheld", WITHHELD)

    # 3. the markers survive a second pass unchanged, so a generator that runs
    #    twice over its own output does not turn a marker into a project name.
    if label in MARKERS:
        return ({LAB: "lab", NO_PROJECT: "none"}.get(label, "withheld"), label)

    # 4. the home directory, under any of its spellings — the account-name fold
    #    site/redact.py performs, and the `~` an unhomed path leaves behind.
    if label in (HOME_LABEL, HOME_PATH_LABEL):
        return ("none", NO_PROJECT)

    # 5. a dot-directory is configuration or state — `.claude`, `.reachprobe`.
    #    No project root on this machine is named with a leading dot, and a
    #    session run inside a tool's own state directory is not a project's.
    if label.startswith("."):
        return ("none", NO_PROJECT)

    # 6. the system scratch area itself.
    if label in SCRATCH_ROOTS:
        return ("none", NO_PROJECT)

    # 7. the fixtures, judged on the whole pipe as they always were.
    if raw in FIXTURE or label in {f.split(":")[0] for f in FIXTURE}:
        return ("fixture", spelling(label))

    # 8. the laboratories.
    if raw in LAB_EXACT or label in LAB_EXACT:
        return ("lab", LAB)
    if any(label.startswith(p) for p in LAB_PREFIX):
        return ("lab", LAB)

    # 9. what the structural rules cannot speak for, decided in a committed
    #    file with the evidence written beside it.
    kind = np.get(label)
    if kind == "lab":
        return ("lab", LAB)
    if kind == "none":
        return ("none", NO_PROJECT)

    # 10. a project, in one spelling.
    return ("project", spelling(label))


def project_label(pipe, non_projects=None):
    """The string a published record carries in its `project` field."""
    return identity_of(pipe, non_projects)[1]


def published_label(pipe, non_projects=None):
    """REDACTION FIRST, IDENTITY SECOND, and the order is the whole argument.

    site/redact.py decides whether a name may leave this machine at all: it
    folds the two spellings of the home directory together and replaces a name
    on the operator's private withhold list with a marker. This module then
    decides what the surviving label DENOTES.

    Running them the other way round would ask "is this a project?" of a string
    that has not been through the withhold list yet, and any label this module
    rewrote — a spelling normalised, a lab collapsed — would reach redact.py in
    a spelling the private list was not written in. The withheld name would
    walk out under a label that looks tidy. Every generator that publishes a
    project name calls THIS function, so there is one order and it is this one."""
    from redact import project_of      # local: identity.py stands alone in tests
    return project_label(project_of(pipe), non_projects)


def is_lab(pipe):
    """Kept for site/field_stats.py, which screened labs by this name long
    before this module existed. Same question, one implementation."""
    return identity_of(pipe)[0] == "lab"


def resolve_all(labels):
    """{label: (kind, name)} for an iterable of labels, one load of the list."""
    np = load_non_projects()
    return {lab: identity_of(lab, np) for lab in labels}


def main():
    """Print how every label that reaches a published artifact resolves.

    This is the audit surface: the collapse is only legitimate if a human can
    read the whole of it, so the whole of it prints — every label, its verdict,
    and which rule spoke for it."""
    import collections
    import glob
    import json

    labels = collections.Counter()
    for path in sorted(glob.glob(os.path.join(os.path.expanduser("~"),
                                              ".rabadon", "spool", "*.jsonl"))):
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    labels[json.loads(line).get("pipe")] += 1
                except ValueError:
                    continue

    np = load_non_projects()
    by_kind = collections.defaultdict(list)
    for lab, n in labels.items():
        kind, name = identity_of(lab, np)
        by_kind[kind].append((n, lab, name))

    total = sum(labels.values())
    print("%d ledger record(s), %d distinct label(s)" % (total, len(labels)))
    for kind in ("project", "fixture", "withheld", "lab", "none"):
        rows = sorted(by_kind.get(kind, []), reverse=True)
        print("\n%-8s %d label(s), %d record(s)"
              % (kind, len(rows), sum(r[0] for r in rows)))
        for n, lab, name in rows:
            arrow = "" if name == (lab or "").split(":")[0] else "  ->  " + name
            print("   %7d  %s%s" % (n, lab, arrow))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
