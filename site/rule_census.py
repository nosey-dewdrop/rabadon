#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rule_census.py — the guard-rule census, re-runnable.

WHAT THIS IS
    site/rule_census.json answers one question for every guard rule on this
    machine: driven through the real gate binary, standing in its own project,
    with a command the rule's own deny/match pattern was written to refuse —
    does the rule actually refuse it, or is it structurally incapable of ever
    firing?  The first census was a one-off that lived in an agent's head; the
    page it produced could be read but not checked.  This is the same
    measurement as a script, which is the only form in which a published number
    can be argued with.

WHY TWO BINARIES
    A census is a measurement of one build.  Three repairs landed on 3 August
    (protectedPaths absolute-vs-relative, the pipe as a full-line surface, and
    guard reach walking up to the git root / $HOME) and the published census
    predates all three, so the page described a gate that no longer existed.
    Comparing a fresh run against a published old number measures the clock as
    much as the code.  So both binaries are built and driven, probe by probe,
    back to back in one pass: OLD then NEW on the same rule before moving to
    the next.  The old binary reproducing the published figure is what makes
    the new figure worth printing.

HOW A RULE IS JUDGED
    A PreToolUse hook event on stdin:
        {"hook_event_name":"PreToolUse","session_id":...,"cwd":<probe_cwd>,
         "tool_name":<probe_tool>,"tool_input":{...}}
    and only the exit code and the `Rule: <id>` line on stderr are read.
      exit 2, refusing id == the rule           -> fires
      refused by something else, but the rule
        DOES refuse when it stands alone in a
        scratch guard                           -> shadowed
      no refusal even standing alone            -> cannot-fire

SAFETY, MEASURED NOT ASSUMED
    "A PreToolUse verdict executes nothing" is TRUE of the tool command — the
    gate judges the command, it never runs it, asserted below with a canary
    file a probe asks to delete.  It is FALSE of the gate as a whole: on a
    `git push` PreToolUse event, in a project whose guard carries a pushGate,
    with lastCodeEdit > lastTestVerified, gate.cpp FORKS A SHELL and runs the
    project's own test command before deciding.  Six projects on this machine
    are in that state.  Every probe therefore runs under a wall-clock timeout
    and is killed as a process group, any probe refused by `push-gate` is
    recorded as an anomaly rather than a verdict, and the git-push allow twins
    are withheld from both runs — driving one would execute `cargo test`,
    `go test ./...` or `bin/rspec`, and would move lastTestVerified BETWEEN the
    two binaries so that the second was asked a different question.

FIXTURE PREMISE — checked before any green is believed
    * ENFORCE vs WATCH.  With no `enabled` file the gate records the verdict
      and exits 0, so every probe reads as "did not fire" and the census is a
      census of nothing that looks exactly like a census.  RABADON_DIR is
      pointed at a scratch home that HAS an `enabled` file, and a known-firing
      control probe must exit 2 before the run starts.
    * The scratch home also keeps ~7,000 probe events out of the real ledger,
      which the published field numbers are computed from.
    * macOS symlinks /tmp -> /private/tmp and /var -> /private/var.  Every
      scratch path is realpath()'d before use, never compared raw.
    * /tmp, /var/tmp and /var/folders are exempt from the delete-coverage law
      (pathres.h machine_temp_roots).  That law is a BASELINE law and can only
      ever shadow a guard rule, never keep one from firing, so a scratch lab
      under /private/tmp is safe for the stands-alone second pass — it can only
      make a rule MORE likely to answer in its own name.  The guard-reach
      fixture is the opposite case and may NOT live there; see below.
    * State is per project: <cwd>/.rabadon/state.json, one file per project,
      written by the gate on every event.  Every probe gets its own session id
      so no probe inherits another's actionCount, cmdRepeat or drift counters.

WHAT THE NUMBER COUNTS
    Rules, not events.  A rule that refuses twice is one rule.  And a rule is
    keyed by (guard, id), never by (project, id): three separate checkouts of
    one project on this machine each carry a rule called `no-force-push-main`,
    and keying on the project name silently merges 16 of the 430 away.

    The project was named here by name until 16 August, and it is a withheld
    one. This file is served from the directory it helps redact, so an example
    written into its own prose is published on the domain and in the public
    repository — the same door site/redact.py already warns about, entered
    through documentation. Illustrations here stay generic.

WHAT IS MEASURED IS NOT WHAT IS PUBLISHED
    The census is taken on this machine, over this machine's guard files, so
    every record it builds carries an absolute path and the name of the
    repository the rule governs.  That is the correct input and a disclosure as
    output: site/rule_census.json is served at
    https://rabadon.noseydewdrop.com/rule_census.json, and it went out with 1058
    absolute home paths and the names of eleven private repositories, one of
    which discloses a health context by its name alone.  So the file is written
    through site/redact.py — the same module site/field_stats.py publishes
    field.jsonl through — and the write path is the ONLY way out: publish()
    sanitizes, then re-reads its own output and refuses to leave it on disk if
    anything survived.  The unredacted census is still needed (it is the
    baseline the next run repeats), so it is kept OUTSIDE the repository, in
    ~/.rabadon/census/, next to the ledger, where nothing deploys from.

USAGE
    python3 site/rule_census.py                 # measure, write JSON + report
    python3 site/rule_census.py --dry-run       # print the plan, drive nothing
    python3 site/rule_census.py --baseline P    # read the baseline census from P
    python3 site/rule_census.py --keep          # leave the worktrees in place
    python3 site/rule_census.py --republish     # re-emit the published file
                                                # through the redactor, without
                                                # re-measuring anything
"""

import collections
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import identity
import redact

HOME = os.path.expanduser("~")
REPO = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CENSUS_IN = os.path.join(REPO, "site", "rule_census.json")
CENSUS_OUT = CENSUS_IN
# the census as measured: absolute paths, every project, nothing dropped. It is
# the baseline the next run reads (a probe is only repeatable if the record that
# holds it survives), and it is exactly what may not be published — so it lives
# beside the ledger in ~/.rabadon, outside the repository and outside the
# directory `vercel deploy` uploads.
FULL_OUT = os.path.join(HOME, ".rabadon", "census", "rule_census.full.json")
REPORT_OUT = os.path.join(HOME, "damla_projects_2026", "reports",
                          time.strftime("%Y-%m-%d", time.gmtime()) + "-kural-sayimi-yeniden.txt")

OLD_TREE = "/tmp/census-old"
NEW_TREE = "/tmp/census-new"
OLD_GATE = OLD_TREE + "/native/rabadon-gate"
NEW_GATE = NEW_TREE + "/native/rabadon-gate"
OLD_COMMIT = "b384d6a714f1e24991d4d493cc2142a6b184225e"

PROBE_TIMEOUT = 20          # seconds; a push-gate suite run must not be waited on
CONTROL_CWD = HOME
CONTROL_CMD = "git push --force origin main"
CONTROL_RULE = "no-force-push-main"

# ---------------------------------------------------------------------------
# the scratch rabadon home: ENFORCE mode, and the ledger kept out of the real one
# ---------------------------------------------------------------------------
RDIR = os.path.realpath(tempfile.mkdtemp(prefix="census-rdir-"))
os.makedirs(os.path.join(RDIR, "spool"), exist_ok=True)
with open(os.path.join(RDIR, "enabled"), "w") as f:
    f.write("on\n")

ENV = dict(os.environ)
ENV["RABADON_DIR"] = RDIR
ENV["RABADON_NOTIFY"] = "0"
ENV["HOME"] = HOME          # the guard walk is bounded by HOME; it must be the real one
ENV["LC_ALL"] = "C"

RULE_RE = re.compile(r"^Rule: (\S+)", re.M)


# ---------------------------------------------------------------------------
# the two builds. NOT in this repo: a census takes minutes and other sessions
# compile here the whole time, so building the binary under measurement in the
# tree somebody is editing measures whichever save landed last.
# ---------------------------------------------------------------------------
def worktrees():
    for tree, ref in ((OLD_TREE, OLD_COMMIT), (NEW_TREE, "HEAD")):
        if not os.path.isdir(tree):
            subprocess.check_call(["git", "-C", REPO, "worktree", "add", "--detach", tree, ref])
        gate = os.path.join(tree, "native", "rabadon-gate")
        if not os.access(gate, os.X_OK):
            subprocess.check_call(["make", "-C", tree, "native/rabadon-gate"])


def drop_worktrees():
    for tree in (OLD_TREE, NEW_TREE):
        subprocess.call(["git", "-C", REPO, "worktree", "remove", "--force", tree])


def drive(gate, cwd, tool, tool_input, sid):
    """One PreToolUse event -> (exit_code, refusing_rule_id, stderr, seconds)."""
    ev = json.dumps({
        "hook_event_name": "PreToolUse",
        "session_id": sid,
        "cwd": cwd,
        "tool_name": tool,
        "tool_input": tool_input,
    }, ensure_ascii=False)
    t0 = time.time()
    p = subprocess.Popen([gate], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                         stderr=subprocess.PIPE, env=ENV, start_new_session=True)
    try:
        _, err = p.communicate(ev.encode("utf-8"), timeout=PROBE_TIMEOUT)
        rc = p.returncode
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(p.pid), signal.SIGKILL)
        except Exception:
            pass
        p.communicate()
        return (-9, "TIMEOUT", "", time.time() - t0)
    err = err.decode("utf-8", "replace")
    m = RULE_RE.search(err)
    return (rc, m.group(1) if m else None, err, time.time() - t0)


def bash_input(cmd):
    return {"command": cmd}


def edit_input(path):
    return {"file_path": path}


# ---------------------------------------------------------------------------
# pattern_names_a_pipe — the python twin of rules.h, for CLASSIFYING a dead rule
# (the verdict itself always comes from the binary, never from this function)
# ---------------------------------------------------------------------------
def pattern_names_a_pipe(pat):
    in_class = negated = False
    i = 0
    while i < len(pat):
        c = pat[i]
        if c == "\\":
            if i + 1 < len(pat) and pat[i + 1] == "|":
                return True
            i += 2
            continue
        if c == "[" and not in_class:
            in_class = True
            negated = i + 1 < len(pat) and pat[i + 1] == "^"
        elif c == "]" and in_class:
            in_class = False
        elif c == "|" and in_class and not negated:
            return True
        i += 1
    return False


def py_search(pattern, text):
    try:
        return re.search(pattern, text) is not None
    except re.error:
        return None


# ---------------------------------------------------------------------------
# probes
# ---------------------------------------------------------------------------
def load_census():
    """The baseline is read from GIT, not from the working file.

    This script writes site/rule_census.json, so reading the working copy makes
    the second run a measurement of the first one's output: the probes are
    already filled in, the probe=null repair silently does nothing, and the
    bookkeeping quietly stops being true. The committed blob is the fixed
    point. `--baseline <path>` overrides it.

    ~/.rabadon/census/rule_census.full.json comes FIRST, because the committed
    blob is now the redacted one: the rules whose project is withheld are not in
    it, and a baseline that has lost those rules produces a census that has lost
    them too, one run after another, with nothing anywhere saying so. The full
    file is what the previous run measured, it never leaves this machine, and it
    is the only honest baseline. If it is absent (a fresh clone), the published
    file is used and the run covers what the published file still holds.
    """
    for i, a in enumerate(sys.argv):
        if a == "--baseline" and i + 1 < len(sys.argv):
            with open(sys.argv[i + 1], encoding="utf-8") as f:
                return json.load(f)
    if os.path.exists(FULL_OUT):
        with open(FULL_OUT, encoding="utf-8") as f:
            return json.load(f)
    try:
        blob = subprocess.check_output(
            ["git", "-C", NEW_TREE, "show", "HEAD:site/rule_census.json"],
            stderr=subprocess.DEVNULL)
        return json.loads(blob.decode("utf-8"))
    except Exception:
        with open(CENSUS_IN, encoding="utf-8") as f:
            return json.load(f)


# ---------------------------------------------------------------------------
# what leaves the machine
# ---------------------------------------------------------------------------
def sanitize(census):
    """The measured census in, the publishable census out, plus the tally.

    Two operations, and they are not interchangeable:

      REWRITE for paths.  `/Users/<account>/damla_projects_2026/x` becomes
      `~/damla_projects_2026/x`.  The record survives; only the machine it was
      taken on stops being identifiable.  redact.unhome handles the truncated
      spelling too, which is the one that walked past the last redactor.

      DROP for names.  A record whose project or path names a repository on the
      withheld list is removed whole, because there is no rewrite that keeps it:
      the name IS the disclosure, and a census row carrying it says this person
      has a repository about that.  Damla's standing rule is that health
      material never reaches a public surface.  The terms themselves are not in
      this repository; see site/redact.py.

    Every drop is counted, keyed by the section it came out of, and the counts
    are written into the published file.  A census that quietly holds records
    back is a different lie from the one it was fixing: it still reads as "every
    guard rule on this machine", and it no longer is.

    The walk is generic on purpose.  The census has eleven nested record lists
    today and the last three were added by two different repairs; a sanitizer
    that names the lists it knows about is a sanitizer that misses the next one,
    which is precisely how this file came to publish 1058 home paths while the
    page beside it claimed otherwise."""
    withheld = collections.Counter()

    # Depth first, and the order matters. A record is dropped for what IT says,
    # not for what something nested three levels inside it says: the entry for
    # `guard reach from a subdirectory` carries a list of the project roots the
    # fixture walked, one of which is on the withheld list, and checking the
    # outer record first threw away a whole measured mechanism to hide one row
    # of a table inside it. So the inner list is pruned first and the outer
    # record is judged on what is left of it — which is how a redaction stays a
    # redaction instead of quietly becoming a deletion.
    # TWO PASSES, AND THE ORDER IS THE WHOLE CORRECTNESS ARGUMENT. This used to
    # be one pass that cleaned each record BEFORE asking whether to withhold it,
    # so `withhold_reason` was handed a blob the scrub had already emptied of
    # every term it looks for. It never fired: the census published 0 withheld
    # where 3 were owed, and all four fixture rules survived with their names
    # quietly rubbed out. A pass that keeps the record and erases the evidence
    # is not a redaction — it is a cover-up with a counter stuck at zero. That
    # is also what `redact.clean`'s own docstring assumes is already done: the
    # withheld names are "handled one layer up — a whole RECORD carrying one was
    # dropped".
    #
    # So: decide first, on the ORIGINAL text; rewrite only what survives.
    def prune(node, where):
        """Drop the records that may not be published, judged on what they say
        before anything is scrubbed.

        Inner lists are pruned first so an outer record is judged on what is
        LEFT of it: the entry for `guard reach from a subdirectory` carries a
        list of the project roots the fixture walked, one of which is withheld,
        and judging the outer record first threw away a whole measured
        mechanism to hide one row of a table inside it."""
        if isinstance(node, dict):
            return {k: prune(v, where + "." + str(k)) for k, v in node.items()}
        if isinstance(node, list):
            out = []
            for item in node:
                if isinstance(item, (dict, list)):
                    item = prune(item, where)
                    if redact.withhold_reason(json.dumps(item, ensure_ascii=False)):
                        withheld[where.lstrip(".")] += 1
                        continue
                out.append(item)
            return out
        return node

    def identify(node, measured):
        """Rewrite every `project` value to the identity of the project, using
        the guard PATH that sits beside it in the same record.

        The identity written here is the RAW directory name, not the published
        spelling: pass 4 has to be able to read it and judge it. Pass 5 is what
        turns it into what a reader sees.

        A declared name is only ever mapped away when it is not itself some
        guard's directory. If two different projects genuinely disagree —
        one declaring the name the other lives under — the safe answer is to
        leave both alone and let a human see two names, because the danger in
        this pass is a project quietly absorbing another one's rules."""
        rules = measured.get("rules") or []
        locations = {identity.from_guard_path(r.get("guard")) for r in rules
                     if isinstance(r, dict)}
        locations.discard(None)
        name_map = {}
        for r in rules:
            if not isinstance(r, dict):
                continue
            declared, where = r.get("project"), identity.from_guard_path(r.get("guard"))
            if not declared or not where or declared == where:
                continue
            if declared in locations:
                continue          # a real project of its own; do not absorb it
            name_map[declared] = where

        def walk(n):
            if isinstance(n, dict):
                out = {}
                for k, v in n.items():
                    if k == "project" and isinstance(v, str) and v:
                        out[k] = name_map.get(v, v)
                    else:
                        out[k] = walk(v)
                return out
            if isinstance(n, list):
                return [walk(v) for v in n]
            return n

        return walk(node)

    def finalise(node):
        """The published spelling, and the rows that are now one row.

        Runs after the second decision, so nothing here can hide a name from
        it: by the time this pass turns a label into `(withheld)` or `(lab)`,
        the record has already been judged on the name itself."""
        def walk(n):
            if isinstance(n, dict):
                return {k: (identity.published_label(v)
                            if k == "project" and isinstance(v, str) and v
                            else walk(v))
                        for k, v in n.items()}
            if isinstance(n, list):
                return [walk(v) for v in n]
            return n

        done = walk(node)

        # by_project is one ROW per project, so two spellings collapsing means
        # two rows for one project. They are counts; they add.
        rows = done.get("by_project")
        if isinstance(rows, list):
            merged = {}
            for row in rows:
                if not isinstance(row, dict) or "project" not in row:
                    continue
                seen = merged.get(row["project"])
                if seen is None:
                    merged[row["project"]] = dict(row)
                    continue
                for k, v in row.items():
                    if isinstance(v, (int, float)) and not isinstance(v, bool):
                        seen[k] = seen.get(k, 0) + v
            if len(merged) != len(rows):
                print("  identity: %d project row(s) merged into %d — two "
                      "spellings of one project were being counted twice"
                      % (len(rows), len(merged)))
            done["by_project"] = sorted(
                merged.values(),
                key=lambda p: (-p.get("cannot_fire", 0), -p.get("total", 0)))
        return done

    def scrub(node):
        """Rewrite what survived: the home path to `~`, the account name out,
        and a withheld term out of free text that merely mentions one."""
        if isinstance(node, dict):
            return {redact.clean(k, 0): scrub(v) for k, v in node.items()}
        if isinstance(node, list):
            return [scrub(v) for v in node]
        if isinstance(node, str):
            # no length clip here: unlike a ledger label, a census field is a
            # pattern or a probe, and half a regex is not a shorter regex.
            return redact.clean(node, 0)
        return node

    # THIRD PASS: the project column carries an IDENTITY, not a nickname.
    #
    # Until now a rule was published under the `project` key its guard file
    # declares about itself. That key is a preference, not a fact: 10 of the 63
    # guards on this machine declare a name their directory does not have, and
    # four of those are a second spelling of a project the ledger already spells
    # the other way (`idea garden` beside `idea-garden`, `message-in-a-bottle`
    # beside `messageinabottle`). The census published both, so one project was
    # counted as two and the allowlist asked the operator to decide twice about
    # the same repository. Two more guards declare a name their directory has
    # nothing to do with, which published a SECOND name for a project nobody had
    # decided to publish once.
    #
    # Where a project lives is a fact, and the published file carries the guard
    # path beside every rule — so a reader can check this mapping without the
    # machine it was made on. That is the whole reason it is allowed to happen
    # here rather than being asserted.
    #
    # It runs THIRD, after the withhold decision and after the scrub, and the
    # order is not cosmetic. Running it before prune would hand withhold_reason
    # a name that had already been rewritten, which is the exact two-passes bug
    # described above, one layer along.
    # FIVE PASSES, AND EACH ONE EXISTS BECAUSE THE PASS BEFORE IT COULD NOT KNOW
    # WHAT THE PASS AFTER IT LEARNS.
    #
    #   1 prune     decide, on the ORIGINAL text (see above)
    #   2 scrub     rewrite what survived
    #   3 identify  resolve the project column to an identity
    #   4 prune     decide AGAIN, because identify ADDED information
    #   5 finalise  the published spelling, and merge rows that are now one row
    #
    # Pass 4 is not belt-and-braces. It is the fix for a live leak this work
    # found: two guards declare a nickname their directory does not have, both
    # directories are on the operator's private withhold list, and both
    # nicknames are not — the list is written in directory names. Pass 1 dropped
    # every rule record for those two projects, and their aggregate rows in
    # by_project survived, published under the nicknames, saying how many rules
    # each withheld project has. Nothing in the record carried a path, so
    # nothing in the record could be judged. Resolving the nickname to the
    # directory is the moment that becomes knowable, so the decision has to be
    # taken again right there.
    #
    # The map for pass 3 is built from the census as MEASURED, not from what
    # survived pass 1 — a guard whose records were all withheld still knows what
    # its own directory is called, and that is precisely the mapping needed to
    # catch the row that got away.
    clean = finalise(prune(identify(scrub(prune(census, "")), census), "identity"))
    total = sum(withheld.values())
    clean["withheld_from_publication"] = {
        "records": total,
        "by_section": dict(sorted(withheld.items())),
        "note": ("This file is the census as PUBLISHED, and it is smaller than the census as "
                 "measured. Absolute home paths are rewritten to ~. Records naming a repository "
                 "whose name is itself private information — a health context, or unreleased work "
                 "unrelated to this one — are dropped whole rather than path-rewritten, because "
                 "the name is the disclosure. %d record(s) were withheld on those grounds; the "
                 "headline counts above are the counts as MEASURED, so headline minus withheld is "
                 "what this file lists. The terms are not printed here: printing them would "
                 "publish exactly what withholding them protects. They are in site/redact.py, "
                 "which is also the redactor site/field_stats.py publishes field.jsonl through, "
                 "and native/publish_redaction_test.sh fails if either file ever carries one "
                 "again." % total),
        "terms": len(redact.SENSITIVE_PROJECTS),
        "generator": "site/rule_census.py -> site/redact.py",
    }
    return clean, withheld


def publish(census):
    """Write both files: the measured one where nothing deploys from, the
    redacted one where everything does. There is no third path — a caller that
    wants the census on disk gets it through here, so a new section cannot be
    added to the JSON and reach the site unfiltered.

    The refusal at the end reads the bytes that were actually written rather
    than the object that was meant to be written. A redactor that is asked
    whether it redacted is not evidence."""
    os.makedirs(os.path.dirname(FULL_OUT), exist_ok=True)
    with open(FULL_OUT, "w", encoding="utf-8") as f:
        json.dump(census, f, ensure_ascii=False, indent=1)
    os.chmod(FULL_OUT, 0o600)

    pub, withheld = sanitize(census)
    blob = json.dumps(pub, ensure_ascii=False, indent=1)
    why = redact.leaks(blob)
    if why:
        raise SystemExit("REFUSING TO PUBLISH site/rule_census.json: " + why)
    tmp = CENSUS_OUT + ".tmp.%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(blob)
    os.replace(tmp, CENSUS_OUT)
    with open(CENSUS_OUT, encoding="utf-8") as f:
        why = redact.leaks(f.read())
    if why:
        os.unlink(CENSUS_OUT)
        raise SystemExit("REFUSING TO PUBLISH site/rule_census.json: " + why + " (file removed)")
    print("wrote %s (%d bytes, unredacted, mode 600)" % (FULL_OUT, os.path.getsize(FULL_OUT)))
    print("wrote %s (%d bytes, %d record(s) withheld: %s)"
          % (CENSUS_OUT, len(blob), sum(withheld.values()),
             ", ".join("%s=%d" % kv for kv in sorted(withheld.items())) or "none"))
    return pub


def repair_missing_probes(old):
    """The published census recorded probe=null for the 14 protectedPaths rules
    it judged dead — the file path it drove is not in the rule record.  Twelve
    of them are recoverable verbatim from protection_actually_lost
    (`file_that_is_no_longer_protected`); the two that a sibling rule covers are
    not listed there and are re-derived from the pattern.  Every re-derived
    probe is checked with `re` against the project-relative spelling before it
    is sent, exactly as the first census checked its own.
    """
    lost = {}
    pal = old.get("protection_actually_lost") or {}
    for e in pal.get("dead_and_uncovered") or []:
        lost[(e["project"], e["id"])] = e.get("file_that_is_no_longer_protected")

    # the two dead-but-covered rules: no file recorded, derived from the pattern
    DERIVED = {
        ("rabadon", "anti-path-frozen"): "bin/rabadon.mjs",
        ("rabadon", "release-workflow-needs-test-gate"): ".github/workflows/release.yml",
    }

    filled = []
    for r in old["rules"]:
        if r.get("probe"):
            continue
        key = (r["project"], r["id"])
        groot = os.path.dirname(os.path.dirname(r["guard"]))
        probe = lost.get(key)
        source = "recovered from protection_actually_lost"
        if probe and probe.endswith("/"):
            probe = probe + "x"          # a directory prefix needs a file under it
            source = "recovered from protection_actually_lost (+ file under the named directory)"
        if not probe:
            rel = DERIVED.get(key)
            if rel is None:
                raise SystemExit("no probe and no way to derive one: %s %s" % key)
            probe = os.path.join(groot, rel)
            source = "re-derived from the pattern"
        rel = probe[len(groot) + 1:] if probe.startswith(groot + "/") else None
        r["probe"] = probe
        r["probe_source"] = "generated (%s; the published census recorded null)" % source
        filled.append({
            "project": r["project"], "id": r["id"], "probe": probe,
            "relative": rel,
            "pattern_matches_relative": py_search(r["pattern"], rel) if rel else None,
            "pattern_matches_absolute": py_search(r["pattern"], probe),
            "source": source,
        })
    return filled


# ---------------------------------------------------------------------------
# the stands-alone second pass: dead rule, or one a neighbour catches first?
# ---------------------------------------------------------------------------
class Lab(object):
    def __init__(self):
        self.root = os.path.realpath(tempfile.mkdtemp(prefix="census-lab-"))
        self.n = 0

    def alone(self, rule, gate):
        """Put this one rule in an empty guard at a scratch project root and ask
        it the same question.  For a protectedPaths rule the probe path is
        rebased onto the scratch root so the rule keeps the same relationship to
        its project that it had in the real one."""
        self.n += 1
        proj = os.path.join(self.root, "p%d" % self.n)
        os.makedirs(os.path.join(proj, ".rabadon"), exist_ok=True)
        entry = {"id": rule["id"], "why": rule.get("why") or ""}
        if rule["kind"] == "bash":
            entry["deny"] = rule["pattern"]
            guard = {"project": rule["project"], "bash": [entry],
                     "protectedPaths": [], "disabled": []}
        else:
            entry["match"] = rule["pattern"]
            guard = {"project": rule["project"], "bash": [],
                     "protectedPaths": [entry], "disabled": []}
        with open(os.path.join(proj, ".rabadon", "guard.json"), "w", encoding="utf-8") as f:
            json.dump(guard, f, ensure_ascii=False)

        if rule["kind"] == "bash":
            return drive(gate, proj, "Bash", bash_input(rule["probe"]),
                         "alone%d" % self.n)
        groot = os.path.dirname(os.path.dirname(rule["guard"]))
        p = rule["probe"]
        rel = p[len(groot) + 1:] if p.startswith(groot + "/") else os.path.basename(p)
        target = os.path.join(proj, rel)
        return drive(gate, proj, "Edit", edit_input(target), "alone%d" % self.n)


# ---------------------------------------------------------------------------
# allow twins — the author writing down what the rule must NOT catch.
# The repairs WIDEN what a rule is matched against (a second path spelling, and
# the whole line for pipe rules), so the other direction has to be re-measured
# too: a rule that starts refusing honest work costs more than one that never
# fires.
# ---------------------------------------------------------------------------
GIT_PUSH = re.compile(r"\bgit\s+push\b")


def allow_twins(guards):
    """Returns (runnable, withheld). A twin is WITHHELD when driving it would
    make the gate fork the project's own test suite: a `git push` PreToolUse
    event, in a guard carrying a pushGate, is not a judgement — gate.cpp RUNS
    the suite and decides on the real result. Six projects on this machine are
    in the state where that happens. Running those twins would execute
    `cargo test`, `go test ./...` and `bin/rspec` on a machine other agents are
    compiling on, and it would also move lastTestVerified BETWEEN the two
    binaries, so the second binary would be asked a different question than the
    first. Withheld, named, and counted separately."""
    out, withheld = [], []
    for g in sorted(guards):
        try:
            with open(g, encoding="utf-8") as f:
                raw = f.read()
            gd = json.loads(raw)
        except Exception:
            continue
        has_pushgate = '"pushGate"' in raw
        root = os.path.dirname(os.path.dirname(g))
        for sec, tool in (("bash", "Bash"), ("protectedPaths", "Edit")):
            for r in gd.get(sec) or []:
                if not isinstance(r, dict):
                    continue
                for a in (r.get("allow") or []):
                    rec = {"project": gd.get("project"), "guard": g,
                           "id": r.get("id"), "kind": sec, "tool": tool,
                           "cwd": root, "twin": a, "root": root}
                    if (tool == "Bash" and has_pushgate and GIT_PUSH.search(a)
                            and "--dry-run" not in a):
                        rec["withheld_because"] = ("a git-push PreToolUse event at a pushGate "
                                                   "guard makes the gate fork and RUN the "
                                                   "project's test suite")
                        withheld.append(rec)
                    else:
                        out.append(rec)
    return out, withheld


# ---------------------------------------------------------------------------
def main():
    dry = "--dry-run" in sys.argv
    if not dry:
        worktrees()
    old = load_census()
    rules = old["rules"]
    guards = sorted(set(r["guard"] for r in rules))
    filled = repair_missing_probes(old)

    if not dry:
        for gate in (OLD_GATE, NEW_GATE):
            if not os.access(gate, os.X_OK):
                raise SystemExit("build first, in a worktree: %s" % gate)

    print("rules=%d guards=%d probes_repaired=%d" % (len(rules), len(guards), len(filled)))
    if dry:
        for f in filled:
            print("  repaired probe", f["project"], f["id"], f["probe"],
                  "rel_match=%s abs_match=%s" % (f["pattern_matches_relative"],
                                                 f["pattern_matches_absolute"]))
        return

    # ---- fixture premise 1: are we in ENFORCE?  a WATCH run reads as a census
    # of nothing, because block() records the verdict and exits 0.
    rc, rid, err, _ = drive(NEW_GATE, CONTROL_CWD, "Bash", bash_input(CONTROL_CMD), "ctl")
    enforce = (rc == 2 and rid == CONTROL_RULE)
    watch_marker = "would have blocked" in err
    if not enforce:
        raise SystemExit("NOT ENFORCE (exit=%s rule=%s watch=%s) — refusing to publish a "
                         "census of nothing" % (rc, rid, watch_marker))
    print("enforce state: ENFORCE (control %s exit=2)" % CONTROL_RULE)

    # ---- fixture premise 2: a PreToolUse verdict does not run the tool command
    canary = os.path.realpath(tempfile.mkdtemp(prefix="census-canary-"))
    os.makedirs(os.path.join(canary, ".rabadon"), exist_ok=True)
    with open(os.path.join(canary, ".rabadon", "guard.json"), "w") as f:
        json.dump({"project": "canary", "bash": [{"id": "unrelated",
                   "deny": "zzzz-never-matches", "why": "n/a"}],
                   "protectedPaths": [], "disabled": []}, f)
    with open(os.path.join(canary, "CANARY"), "w") as f:
        f.write("alive\n")
    drive(NEW_GATE, canary, "Bash", bash_input("rm -rf %s/CANARY" % canary), "canary")
    executes_nothing = os.path.exists(os.path.join(canary, "CANARY"))
    print("judging is not running: canary %s" % ("ALIVE" if executes_nothing else "DELETED"))
    if not executes_nothing:
        raise SystemExit("the gate executed the probe — stop")

    lab = Lab()
    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    results = {}
    anomalies = []

    # ---- the census.  OLD and NEW on the SAME rule, back to back.
    for i, r in enumerate(rules):
        tool = r["probe_tool"]
        ti = bash_input(r["probe"]) if tool == "Bash" else edit_input(r["probe"])
        rec = {}
        for tag, gate in (("old", OLD_GATE), ("new", NEW_GATE)):
            rc, rid, err, secs = drive(gate, r["probe_cwd"], tool, ti,
                                       "rc%s%d" % (tag, i))
            if rid in ("push-gate", "TIMEOUT") or secs > 5:
                anomalies.append({"project": r["project"], "id": r["id"], "binary": tag,
                                  "refused_by": rid, "seconds": round(secs, 2),
                                  "note": "the push gate forks the project's suite on a "
                                          "PreToolUse git-push event"})
            rec[tag] = {"exit": rc, "rule": rid}
        results[(r["guard"], r["id"])] = rec
        if (i + 1) % 100 == 0:
            print("  %d/%d" % (i + 1, len(rules)))

    # ---- the stands-alone pass, for anything that did not answer in its own name
    for r in rules:
        key = (r["guard"], r["id"])
        for tag, gate in (("old", OLD_GATE), ("new", NEW_GATE)):
            rec = results[key][tag]
            if rec["exit"] == 2 and rec["rule"] == r["id"]:
                rec["verdict"] = "fires"
                continue
            arc, arid, _, _ = lab.alone(r, gate)
            rec["alone_exit"], rec["alone_rule"] = arc, arid
            rec["verdict"] = "shadowed" if (arc == 2 and arid == r["id"]) else "cannot-fire"

    finished = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    # ---- allow twins, both binaries
    twins, twins_withheld = allow_twins(guards)
    over = {"old": [], "new": []}
    for i, t in enumerate(twins):
        ti = bash_input(t["twin"]) if t["tool"] == "Bash" else edit_input(t["twin"])
        for tag, gate in (("old", OLD_GATE), ("new", NEW_GATE)):
            rc, rid, _, _ = drive(gate, t["cwd"], t["tool"], ti, "tw%s%d" % (tag, i))
            if rc == 2:
                over[tag].append(dict(t, exit=rc, refused_by=rid))
    # and the same protectedPaths twins spelled the way a real event spells them
    over_abs = {"old": [], "new": []}
    abs_twins = []
    for i, t in enumerate(twins):
        if t["tool"] != "Edit" or t["twin"].startswith("/"):
            continue
        abs_twins.append(t)
        target = os.path.join(t["root"], t["twin"])
        for tag, gate in (("old", OLD_GATE), ("new", NEW_GATE)):
            rc, rid, _, _ = drive(gate, t["cwd"], "Edit", edit_input(target),
                                  "ta%s%d" % (tag, i))
            if rc == 2:
                over_abs[tag].append(dict(t, probe=target, exit=rc, refused_by=rid))

    # ---- guard reach, re-measured: the repair that cannot show up per rule
    #
    # The fixture may NOT live in the system temp area. project_root() falls
    # back to cwd when nothing above holds a `.git`, and /private/tmp is inside
    # no repository and outside $HOME, so there the bound and the start are the
    # same place and the walk cannot take a step BY DESIGN -- walking up from
    # /private/tmp to / would apply a stranger's rules to this work. A fixture
    # built there measures the absence of a bound, not the reach of the guard,
    # and reads as "the repair did nothing". It is built inside the checked-out
    # worktree instead, which has a `.git` (a file, in a worktree -- project_root
    # stat()s the name, so a file counts).
    reach = {}
    rroot = os.path.realpath(os.path.join(NEW_TREE, ".censusreach-%d" % os.getpid()))
    os.makedirs(os.path.join(rroot, ".rabadon"), exist_ok=True)
    os.makedirs(os.path.join(rroot, "src", "deep"), exist_ok=True)
    with open(os.path.join(rroot, ".rabadon", "guard.json"), "w") as f:
        json.dump({"project": "reach", "bash": [{"id": "reach-no-yarn",
                   "deny": r"\byarn\b", "why": "this project is npm only"}],
                   "protectedPaths": [], "disabled": []}, f)
    for tag, gate in (("old", OLD_GATE), ("new", NEW_GATE)):
        reach[tag] = {}
        for where, cwd in (("root", rroot), ("one_down", os.path.join(rroot, "src")),
                           ("two_down", os.path.join(rroot, "src", "deep"))):
            rc, rid, _, _ = drive(gate, cwd, "Bash", bash_input("yarn add x"),
                                  "reach%s%s" % (tag, where))
            reach[tag][where] = {"exit": rc, "rule": rid}
    shutil.rmtree(rroot, ignore_errors=True)

    # ---- assemble
    out_rules = []
    for r in rules:
        key = (r["guard"], r["id"])
        new = results[key]["new"]
        oldv = results[key]["old"]
        nr = dict(r)
        nr["verdict"] = new["verdict"]
        nr["gate_exit"] = new["exit"]
        nr["refused_by"] = new["rule"]
        nr["mechanism"] = None
        nr["mechanism_note"] = None
        if new["verdict"] == "shadowed":
            nr["mechanism"] = "shadowed"
            nr["mechanism_note"] = ("The rule is capable — it refuses this command when it "
                                    "stands alone in a guard of its own — but an earlier rule "
                                    "in the same guard catches the same command first, so this "
                                    "id can never appear in a refusal.")
        elif new["verdict"] == "cannot-fire":
            if r["kind"] == "protectedPaths":
                nr["mechanism"] = "protectedPaths-absolute"
                nr["mechanism_note"] = (
                    "gate.cpp matches protectedPaths against the file_path the event carries "
                    "and against the path relative to the project the guard governs. A rule "
                    "that still cannot fire matches neither spelling.")
            elif pattern_names_a_pipe(r["pattern"]):
                nr["mechanism"] = "pipe"
                nr["mechanism_note"] = (
                    "The pattern spells a pipe. rules.h now offers the whole line as an extra "
                    "surface to exactly these patterns; one that still cannot fire is not "
                    "failing on the pipe.")
            else:
                nr["mechanism"] = "unclassified"
                nr["mechanism_note"] = "No known mechanism accounts for this one."
        nr["verdict_at_" + OLD_COMMIT[:7]] = oldv["verdict"]
        nr["refused_by_at_" + OLD_COMMIT[:7]] = oldv["rule"]
        nr["changed"] = (oldv["verdict"] != new["verdict"])
        out_rules.append(nr)

    def tally(rs):
        return {
            "total": len(rs),
            "can_fire": sum(1 for x in rs if x["verdict"] == "fires"),
            "cannot_fire": sum(1 for x in rs if x["verdict"] == "cannot-fire"),
            "shadowed": sum(1 for x in rs if x["verdict"] == "shadowed"),
            "undecided": sum(1 for x in rs if x["verdict"] not in
                             ("fires", "cannot-fire", "shadowed")),
            "guards": len(guards),
            "bash": sum(1 for x in rs if x["kind"] == "bash"),
            "protectedPaths": sum(1 for x in rs if x["kind"] == "protectedPaths"),
        }

    head = tally(out_rules)
    old_head = {
        "can_fire": sum(1 for k in results if results[k]["old"]["verdict"] == "fires"),
        "cannot_fire": sum(1 for k in results if results[k]["old"]["verdict"] == "cannot-fire"),
        "shadowed": sum(1 for k in results if results[k]["old"]["verdict"] == "shadowed"),
    }

    mech = {}
    for x in out_rules:
        if x["mechanism"]:
            mech.setdefault(x["mechanism"], []).append(x)
    by_mech = []
    for m, xs in sorted(mech.items(), key=lambda kv: -len(kv[1])):
        by_mech.append({"mechanism": m, "count": len(xs), "note": xs[0]["mechanism_note"]})

    projects = {}
    for x in out_rules:
        p = projects.setdefault(x["project"], {"project": x["project"], "total": 0,
                                               "fires": 0, "cannot_fire": 0, "shadowed": 0,
                                               "bash": 0, "protectedPaths": 0, "incident": 0})
        p["total"] += 1
        p["fires"] += x["verdict"] == "fires"
        p["cannot_fire"] += x["verdict"] == "cannot-fire"
        p["shadowed"] += x["verdict"] == "shadowed"
        p[x["kind"]] += 1
        p["incident"] += bool(x.get("incident_authored"))
    by_project = sorted(projects.values(), key=lambda p: (-p["cannot_fire"], -p["total"]))

    dead = [x for x in out_rules if x["verdict"] == "cannot-fire"]
    covered, uncovered = [], []
    for x in dead:
        sib = [y for y in out_rules if y["guard"] == x["guard"] and y["id"] != x["id"]
               and y["verdict"] == "fires" and y["kind"] == x["kind"]
               and results[(x["guard"], x["id"])]["new"]["rule"] == y["id"]]
        if sib:
            covered.append({"project": x["project"], "id": x["id"], "covered_by": sib[0]["id"]})
        else:
            uncovered.append({"project": x["project"], "id": x["id"], "pattern": x["pattern"],
                              "why": x["why"], "file_that_is_no_longer_protected": x["probe"]})

    inc = [x for x in out_rules if x.get("incident_authored")]
    incident = {
        "total": len(inc),
        "can_fire": sum(1 for x in inc if x["verdict"] == "fires"),
        "cannot_fire": sum(1 for x in inc if x["verdict"] == "cannot-fire"),
        "dead": [{"project": x["project"], "id": x["id"], "mechanism": x["mechanism"],
                  "why": x["why"], "pattern": x["pattern"], "probe": x["probe"]}
                 for x in inc if x["verdict"] == "cannot-fire"],
        "note": ("A rule marked authoredBy: incident was written because something really "
                 "happened. A dead one means that thing can happen again."),
    }

    census = {
        "generated_utc": finished,
        # the commit the BINARY was built from, read out of the worktree it was
        # built in -- not the main repo's HEAD, which other sessions move while
        # a measurement is running.
        "gate_commit": subprocess.check_output(
            ["git", "-C", NEW_TREE, "rev-parse", "HEAD"]).decode().strip(),
        "method": (
            "Re-run of the census at the repaired gate. Every rule was judged by the real gate "
            "binary, standing in its own project, with the SAME probe the first census used — "
            "the probe is stored beside the rule so the measurement can be repeated. Each probe "
            "was driven through TWO binaries back to back in the same pass: the commit the "
            "published census was measured at (" + OLD_COMMIT[:7] + ") and HEAD, so the "
            "difference is the code and not the clock. A rule that did not answer in its own "
            "name got a second pass, alone in a scratch guard, to separate a dead rule from one "
            "a neighbour catches first. The tool command is never executed — every probe is a "
            "PreToolUse event on stdin, asserted with a canary file the gate was asked to delete "
            "and did not — but the gate is not inert either: on a git-push event at a guard "
            "carrying a push gate it forks a shell and runs the project's own suite, so those "
            "twins are withheld and named rather than driven. The generator is "
            "site/rule_census.py."),
        "headline": head,
        "by_mechanism": by_mech,
        "mechanisms_tested_and_not_found": mechanisms_not_found(old, reach),
        "protection_actually_lost": {
            "note": ("A dead rule id does not always mean a dead protection: some have a second "
                     "rule in the same guard that catches the file anyway. The rest have nothing "
                     "behind them."),
            "dead_but_covered_by_a_sibling": covered,
            "dead_and_uncovered": uncovered,
        },
        "incident_authored": incident,
        "over_fires": {
            "note": ("The other direction: rules that refuse work they were never written about. "
                     "An allow twin is the author writing down what the rule must NOT catch. "
                     "Every twin on this machine was re-run against BOTH binaries, because the "
                     "repairs widen what a rule is matched against and a rule that starts "
                     "refusing honest work costs more than one that never fires. The 26 ordinary "
                     "and 50 benign commands are carried forward from the first census and were "
                     "not re-run here."),
            "allow_twins_checked": len(twins),
            "allow_twins_withheld": len(twins_withheld),
            "allow_twins_withheld_note": (
                "A git-push twin at a pushGate guard is not a judgement: gate.cpp forks a shell "
                "and RUNS the project's suite before deciding, so driving it executes cargo "
                "test / go test / bin/rspec and moves lastTestVerified between the two binaries. "
                "Withheld from both runs so both binaries answer the same question."),
            "allow_twins_withheld_list": [
                {"project": t["project"], "id": t["id"], "command": t["twin"]}
                for t in twins_withheld],
            "allow_twins_refused": len(over["new"]),
            "allow_twins_refused_at_" + OLD_COMMIT[:7]: len(over["old"]),
            "absolute_spelling_twins_checked": len(abs_twins),
            "absolute_spelling_twins_refused": len(over_abs["new"]),
            "absolute_spelling_twins_refused_at_" + OLD_COMMIT[:7]: len(over_abs["old"]),
            "confirmed": [{"project": t["project"], "id": t["id"], "command": t["twin"],
                           "exit": t["exit"], "refused_by": t["refused_by"]}
                          for t in over["new"]],
            "confirmed_absolute_spelling": [
                {"project": t["project"], "id": t["id"], "probe": t["probe"],
                 "exit": t["exit"], "refused_by": t["refused_by"]} for t in over_abs["new"]],
        },
        "by_project": by_project,
        "rules": out_rules,
        "comparison": {
            "old_gate_commit": OLD_COMMIT,
            "old_binary_path": OLD_GATE,
            "new_binary_path": NEW_GATE,
            "measured_between_utc": [started, finished],
            "published_headline_at_old_commit": old.get("headline"),
            "old_binary_remeasured": old_head,
            "new_binary_measured": {"can_fire": head["can_fire"],
                                    "cannot_fire": head["cannot_fire"],
                                    "shadowed": head["shadowed"]},
            "enforce_state": "ENFORCE",
            "guard_reach": reach,
            "probe_anomalies": anomalies,
            "probes_repaired": filled,
        },
    }

    publish(census)

    write_report(census, results, out_rules, old, over, over_abs, reach, anomalies,
                 filled, twins, twins_withheld)
    print("wrote %s" % REPORT_OUT)
    if "--keep" not in sys.argv:
        drop_worktrees()


def mechanisms_not_found(old, reach):
    """Carried forward from the first census, with the one entry the repairs
    changed re-measured rather than re-asserted."""
    out = []
    for m in (old.get("mechanisms_tested_and_not_found") or []):
        if m.get("mechanism", "").startswith("guard reach"):
            m = dict(m)
            m["result"] = (
                "REPAIRED at this commit. Re-measured with the same fixture shape, built inside "
                "a checked-out worktree so it sits under a `.git` (a fixture in the system temp "
                "area measures the deliberate absence of a bound, not the reach of the guard): "
                "at the project root old=%s new=%s; one directory down old=%s new=%s; two down "
                "old=%s new=%s. It never appeared in the per-rule census either way, because it "
                "switches every rule in a guard off at once rather than one rule." % (
                    reach["old"]["root"]["rule"], reach["new"]["root"]["rule"],
                    reach["old"]["one_down"]["rule"], reach["new"]["one_down"]["rule"],
                    reach["old"]["two_down"]["rule"], reach["new"]["two_down"]["rule"]))
            m["evidence"] = "site/rule_census.py section 'guard reach'; native/guard_subdir_test.sh"
        out.append(m)
    return out


def write_report(census, results, out_rules, old, over, over_abs, reach, anomalies,
                 filled, twins, twins_withheld):
    h = census["headline"]
    c = census["comparison"]
    L = []
    A = L.append
    A("KURAL SAYIMI, YENIDEN — 430 kural, iki ikili, ayni dakika")
    A("=" * 72)
    A("")
    A("generated_utc      : %s" % census["generated_utc"])
    A("measured between   : %s .. %s (UTC)" % tuple(c["measured_between_utc"]))
    A("old gate commit    : %s   binary %s" % (c["old_gate_commit"], c["old_binary_path"]))
    A("new gate commit    : %s   binary %s" % (census["gate_commit"], NEW_GATE))
    A("enforce state      : %s (control probe refused, exit 2 — not a WATCH census)" %
      c["enforce_state"])
    A("")
    A("1. ESKI vs YENI — ayni probe, iki ikili, ayni gecis")
    A("-" * 72)
    pub = c["published_headline_at_old_commit"] or {}
    ob = c["old_binary_remeasured"]
    A("                        published(%s)   old binary re-run   new binary" % OLD_COMMIT[:7])
    A("  can_fire              %-16s %-19s %s" %
      (pub.get("can_fire"), ob["can_fire"], h["can_fire"]))
    A("  cannot_fire           %-16s %-19s %s" %
      (pub.get("cannot_fire"), ob["cannot_fire"], h["cannot_fire"]))
    A("  shadowed              %-16s %-19s %s" %
      (pub.get("shadowed"), ob["shadowed"], h["shadowed"]))
    A("  total                 %-16s %-19s %s" % (pub.get("total"), h["total"], h["total"]))
    A("")
    A("  delta can_fire (old binary -> new binary): %+d" % (h["can_fire"] - ob["can_fire"]))
    A("")
    A("2. VERDICT DEGISENLER — kural kural")
    A("-" * 72)
    changed = [x for x in out_rules if x["changed"]]
    if not changed:
        A("  none. no rule changed verdict between the two binaries.")
    for x in changed:
        k = (x["guard"], x["id"])
        A("  %-22s %-42s %s -> %s" % (x["project"], x["id"],
                                      results[k]["old"]["verdict"], x["verdict"]))
        A("      kind=%s  refused_by old=%s new=%s" %
          (x["kind"], results[k]["old"]["rule"], x["refused_by"]))
    A("")
    A("3. HALA OLU — 3 Agustos onarimlarinin duzeltmesi gereken ve duzelmeyen")
    A("-" * 72)
    still = [x for x in out_rules
             if x["verdict"] == "cannot-fire"
             and results[(x["guard"], x["id"])]["old"]["verdict"] == "cannot-fire"]
    if not still:
        A("  none. every rule that was dead at %s can fire at HEAD." % OLD_COMMIT[:7])
    for x in still:
        A("  %-22s %-42s kind=%s mechanism=%s" %
          (x["project"], x["id"], x["kind"], x["mechanism"]))
        A("      pattern : %s" % x["pattern"])
        A("      probe   : %s" % x["probe"])
        A("      exit=%s refused_by=%s" % (x["gate_exit"], x["refused_by"]))
        A("      why still dead: %s" % x["mechanism_note"])
    A("")
    A("4. AGIRLIK — mekanizmaya gore")
    A("-" * 72)
    for m in census["by_mechanism"]:
        A("  %-26s %d" % (m["mechanism"], m["count"]))
    A("")
    A("5. TERS YON — allow twins (kurallarin refuse ETMEMESI gerekenler)")
    A("-" * 72)
    A("  literal spelling : %d twins driven, refused old=%d new=%d" %
      (census["over_fires"]["allow_twins_checked"], len(over["old"]), len(over["new"])))
    A("  absolute spelling: %d twins driven, refused old=%d new=%d" %
      (census["over_fires"]["absolute_spelling_twins_checked"],
       len(over_abs["old"]), len(over_abs["new"])))
    A("  withheld         : %d git-push twins at pushGate guards — driving one makes the gate" %
      len(twins_withheld))
    A("                     fork and RUN the project's suite (cargo test / go test / bin/rspec),")
    A("                     which is execution AND moves state between the two binaries.")
    for t in twins_withheld:
        A("      withheld  %-18s %-34s %r" % (t["project"], t["id"], t["twin"]))
    for t in over["new"]:
        A("    NEW refuses  %-18s %-34s %r -> %s" %
          (t["project"], t["id"], t["twin"], t["refused_by"]))
    for t in over_abs["new"]:
        A("    NEW refuses (abs) %-14s %-34s %s -> %s" %
          (t["project"], t["id"], t["probe"], t["refused_by"]))
    A("")
    A("6. GUARD REACH — kural basina gorunmeyen onarim")
    A("-" * 72)
    for tag in ("old", "new"):
        for where in ("root", "one_down", "two_down"):
            r = reach[tag][where]
            A("  %-4s %-9s exit=%s rule=%s" % (tag, where, r["exit"], r["rule"]))
    A("")
    A("7. PROBE ANOMALILERI")
    A("-" * 72)
    if not anomalies:
        A("  none. no probe reached the push gate and no probe timed out.")
    for a in anomalies:
        A("  %s" % json.dumps(a, ensure_ascii=False))
    A("")
    A("8. YENIDEN URETILEN PROBE'LAR (yayinlanan sayimda probe=null idi)")
    A("-" * 72)
    for f in filled:
        A("  %-18s %-38s %s" % (f["project"], f["id"], f["probe"]))
        A("      relative=%s  pattern~relative=%s  pattern~absolute=%s  (%s)" %
          (f["relative"], f["pattern_matches_relative"], f["pattern_matches_absolute"],
           f["source"]))
    A("")
    with open(REPORT_OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")


def republish():
    """Re-emit the census that is already on disk through publish().

    Nothing is measured and nothing is repaired: same records, same verdicts,
    same numbers, run through the write path a full census run uses. It exists
    because the leak is in the file that is being served RIGHT NOW, and the
    honest fix for that cannot be "wait for the next census" — a census takes
    two builds and several thousand probes, and the file stays public the whole
    time.

    The baseline it reads is the same one load_census() reads, so the FIRST
    republish on this machine reads the unredacted file that was published (and
    keeps it, at ~/.rabadon/census/, as the baseline for the next real run),
    and every one after that reads that private copy."""
    census = load_census()
    publish(census)


if __name__ == "__main__":
    if "--republish" in sys.argv:
        republish()
    else:
        main()
