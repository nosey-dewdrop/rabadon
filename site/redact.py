#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# redact.py — the one place that decides what may not leave this machine.
#
# WHY IT EXISTS AS A FILE
#   site/field_stats.py already did this work: home paths rewritten to `~`, the
#   account name replaced, records matching a sensitive-terms list dropped and
#   COUNTED, and a final refusal if anything survived. site/field.jsonl went out
#   clean because of it. site/rule_census.json went out with 1058 absolute home
#   paths and the names of a dozen private repositories, because it is written
#   by a different script and that script had no redactor — while the page
#   publishing both files declared, in schema.org, that home paths are rewritten
#   and sensitive records are dropped and counted. One of the two files made the
#   claim true and the other made it false.
#
#   So the redactor is no longer a section of one generator. It is a module both
#   generators import, and the rule is: a file under site/ is written through
#   this module or it is not published.
#
# THE THREE THINGS IT REDACTS
#   1. Absolute home paths, INCLUDING truncated ones (the gate clips its labels
#      by byte budget, and a clip lands mid-account-name).
#   2. The account name itself, whole or as a searchable prefix.
#   3. The PROJECT NAME. This is the one field_stats.py did not treat as
#      identifying and it is the sharpest of the three: a repository named
#      after a condition is not a path, it is a health context, and it
#      discloses one whether or not the path around it was rewritten, because
#      the name is what a reader searches. Damla's standing rule is that health
#      material never reaches a public surface, and a directory name is a
#      surface. A record naming one of these is DROPPED, not rewritten, and the
#      number dropped is published, because a silent drop is its own untruth:
#      it turns "here is everything" into "here is everything we chose".
#
# THE LIST IS NOT IN THIS FILE, AND THAT IS THE POINT.
#   This repository is public and `vercel deploy` uploads the whole of site/ —
#   https://rabadon.noseydewdrop.com/build.py answers 200. A list of private
#   repository names written here would be published twice over, on GitHub and
#   on the domain, annotated with the reason each one is private. That is a
#   worse disclosure than the one it closes.
#
#   So the terms are read from a file the operator owns, outside the tree:
#   ~/.rabadon/redact/projects.txt, beside the ledger, one term per line.
#   $RABADON_REDACT_TERMS overrides the path, which is how the tests get a list
#   of their own without one existing on the machine running them. No file means
#   no name-based withholding — the home-path and account-name rules still hold,
#   and a machine with no private repositories has nothing to name.
#
#   Published files state HOW MANY records were withheld, never which term did
#   it. The count is the honest part: a filter that hides its own size turns
#   "here is everything" into "here is what was chosen", silently.
import os
import re

HOME = os.path.expanduser("~")
USER = os.path.basename(HOME)
HOMES = os.path.dirname(HOME)   # the directory home directories live in

# somebody else's home, in output this machine merely relayed: a CI log from a
# foreign repository carries /home/runner, a foreign macOS path carries
# /Users/<name>. Neither is this operator's, and neither belongs on the page.
FOREIGN_HOME = re.compile(r"/(?:Users|home)/[^/\s'\"]*")

# what a rewritten home path is spelled as in every published file.
PLACEHOLDER = "~"

# how much of an account name has to survive before it counts as leaked. Four
# characters is enough to search on, so four characters is a leak.
PREFIX = 4

# sensitive CONTENT: the text of a command or a diagnosis, whatever the repo is
# called. Unchanged from field_stats.py, which is where it was written.
SENSITIVE = re.compile(
    r"kanser|onkolo|kemoterapi|biyopsi|tan[ıi]\s*kondu|hasta(l[ıi]k|ne)|"
    r"tc\s*kimlik|iban|password|passwd|secret|api[_-]?key|token=|bearer\s",
    re.I)

# sensitive NAMES: a repository name is data about its author, in two classes
# and under one rule — a record naming one is withheld, never rewritten.
#
#   HEALTH. A directory called after a condition, a clinic, a medicine or a body
#   log discloses a health context on its own, with no path around it and no
#   command text beside it. Damla's standing rule is that health material never
#   reaches a public surface, and a name is a surface.
#
#   PRIVATE AND UNRELATED. Unreleased work that has nothing to do with this
#   repository. site/build.py already carried the sentence "names of unreleased
#   projects do not go on a public page"; it was true of the page and false of
#   the two JSON files the page links.
#
# Matching is substring and case-insensitive, so a term also catches the longer
# names built on it (`<term>-showcase`, `~/projects/<term>/ios`). Deliberate: a
# name that appears as part of a longer name still discloses the short one.
TERMS_FILE = (os.environ.get("RABADON_REDACT_TERMS")
              or os.path.join(HOME, ".rabadon", "redact", "projects.txt"))


def load_terms(path=None):
    """The withheld names, read off disk. Missing file -> empty tuple."""
    path = path or TERMS_FILE
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return ()
    out = []
    for line in lines:
        line = line.split("#", 1)[0].strip()
        if line:
            out.append(line)
    return tuple(out)


SENSITIVE_PROJECTS = load_terms()

# An empty list must match NOTHING. re.compile("") matches every string, so a
# machine with no terms file would have withheld its entire census — the failure
# that looks like a working redactor right up until somebody reads the output.
_PROJECT_RE = (re.compile("|".join(re.escape(p) for p in SENSITIVE_PROJECTS), re.I)
               if SENSITIVE_PROJECTS else None)


def unhome(s):
    """Rewrite every absolute home path to `~`, INCLUDING a truncated one.

    The details being redacted here were already clipped by the gate that wrote
    them, and a clip lands wherever the byte budget ran out — often in the
    middle of the account name. `replace(HOME, "~")` matches a whole string and
    a half of a path is not that string, so `/Users/<first four>` walked past the
    rewrite, past the account-name replacement, and past the check that was
    supposed to refuse the write, because the name that check searches for had
    been cut in half two steps earlier. Two records shaped exactly like that
    were published.

    So the longest prefix of HOME that is actually present is what gets
    replaced, down to the directory homes live in; then anything else shaped
    like somebody's home directory goes the same way."""
    s = s.replace(HOME, PLACEHOLDER)
    for n in range(len(HOME) - 1, len(HOMES), -1):
        if HOME[:n] in s:
            s = s.replace(HOME[:n], PLACEHOLDER)
    return FOREIGN_HOME.sub(PLACEHOLDER, s)


def leaks(blob):
    """What must never appear in a published file. Returns the reason, or ""
    — the write is refused on any of these rather than trimmed, because a rule
    that quietly edits its way out of a leak cannot be checked."""
    if HOMES + "/" in blob:
        return "an absolute home path survived redaction"
    for n in range(len(USER), PREFIX - 1, -1):
        if USER[:n] in blob:
            return "the account name survives redaction (%d of %d characters)" % (n, len(USER))
    hit = _PROJECT_RE.search(blob) if _PROJECT_RE else None
    if hit:
        return "a withheld project name survived the drop (%d characters)" % len(hit.group(0))
    return ""


def names_a_sensitive_project(blob):
    """True when this text names a repository whose NAME is the disclosure.
    Used to DROP a record; there is no rewrite that keeps it."""
    return bool(_PROJECT_RE and _PROJECT_RE.search(blob))


def withhold_reason(blob):
    """Why this record may not be published, or "" if it may be.

    One function so the census and the ledger extractor withhold on the same
    grounds: sensitive content first (what the command said), then a sensitive
    project name (what the repository is called)."""
    if SENSITIVE.search(blob):
        return "sensitive content"
    if names_a_sensitive_project(blob):
        return "sensitive project name"
    return ""


def clean(s, limit=400):
    if not s:
        return ""
    s = unhome(s).replace(USER, "home")
    return s[:limit] if limit else s


def project_of(pipe):
    # sessions started in the home directory are named after the DIRECTORY,
    # which is the operator's account name, not a project. Project names are
    # published on purpose; an account name is not one.
    p = (pipe or "-").split(":")[0]
    return "home" if p == USER else p
