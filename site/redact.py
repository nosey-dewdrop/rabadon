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
#   4. The PROJECT KEY, which is number 1 written in an alphabet the rewrite in
#      number 1 does not read. See below.
#
# A PROJECT KEY IS AN ABSOLUTE PATH IN ANOTHER ENCODING
#   The agent names a session after its working directory with every run of
#   non-alphanumerics collapsed to a single dash:
#
#       /Users/<account>/damla_projects_2026/rabadon
#         ->  -Users-<account>-damla-projects-2026-rabadon
#
#   The gate copies that key onto the records it writes, and 300 records in this
#   ledger carry one. Every rule above walked past them. `unhome` searches for a
#   slash and there is no slash. The account-name replacement in `clean` would
#   have caught it and is only ever applied to free text. `project_of` passed the
#   field through untouched, because a key is not a path as far as it could tell.
#
#   What stopped the publish was the refusal at the end — it read the account
#   name, whole, in the field a reader sees first, and would not write the file.
#   That is the check working with nothing behind it: a refusal with no rewrite
#   to fall back on halts the deploy every time it runs. This is the rewrite.
#
#   The encoding is LOSSY and the label here is honest about it. A directory
#   called `my-app` and a path `my/app` produce the same key, so the last segment
#   of a stripped key is a label, not a name. It is the right label anyway,
#   because it is the one the same project carries on its other 25,000 records
#   (`rabadon`, never `damla-projects-2026-rabadon`), and a project column that
#   spells one repository two ways is counting two projects.
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
# foreign repository carries a Linux home under the CI account, a foreign macOS
# path carries /Users/<name>. Neither is this operator's, and neither belongs on
# the page.
#
# The example on that first line used to be spelled out literally, and on a
# Linux CI runner that spelling IS the runner's own home directory, so
# publish_redaction_test.sh read this comment as a leaked absolute home path and
# failed the build on the file that does the redacting. The check was right: a
# comment in this file is served at /redact.py exactly like a JSON record is.
# Naming the shape instead of the path costs the reader nothing.
FOREIGN_HOME = re.compile(r"/(?:Users|home)/[^/\s'\"]*")

# the same home directory, dash-encoded (see A PROJECT KEY, above).
_KEY_RUN = re.compile(r"[^A-Za-z0-9]+")


def encode_key(path):
    """A path spelled the way a project key spells it."""
    return _KEY_RUN.sub("-", path)


# anybody's encoded home, this machine's included, and a truncated one with it:
# `[A-Za-z0-9]+` stops at the next dash, so it matches the account name whether
# the label was clipped mid-name or not.
#
# The lookbehind is the difference between a redaction and a corruption. Without
# it `-home-` matches inside `my-home-dir` and inside any rule id that has the
# word in the middle, and free text starts coming out mangled. A key stands
# alone or follows a path separator; it never begins mid-word.
FOREIGN_KEY = re.compile(r"(?<![A-Za-z0-9])-(?:Users|home)-[A-Za-z0-9]+")

ENCODED_HOME = encode_key(HOME)     # -Users-<account>, on this machine

# a project key that is an encoded ABSOLUTE path: a leading dash, then a name.
# `-` on its own is a record with no project, not a path, and it stays that way.
_ENCODED_KEY = re.compile(r"^-[A-Za-z0-9]")

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

# the same names as a project key spells them. A term written `some_name` does
# not appear anywhere in `-Users-<account>-some-name`, because the encoding
# rewrote the very separator the term was written with — so the list is compiled
# a second time in the key alphabet and matched against the text in that
# alphabet. The operator writes a name the way the directory is named; the
# redactor is what has to know about the other spelling.
#
# The examples in this file are placeholders on purpose. site/redact.py is
# served from the directory it guards (the domain answers 200 for it), so a
# withheld name written here as an illustration is published twice over —
# on the domain and in the public repository — annotated with the reason it
# was withheld. That is the disclosure the list was moved off the tree to
# avoid, arriving through the door marked documentation.
_PROJECT_KEY_RE = (re.compile("|".join(re.escape(encode_key(p)) for p in SENSITIVE_PROJECTS), re.I)
                   if SENSITIVE_PROJECTS else None)


def _project_hit(blob):
    """The withheld name this text carries, in either spelling, or None."""
    m = _PROJECT_RE.search(blob) if _PROJECT_RE else None
    if m:
        return m.group(0)
    m = _PROJECT_KEY_RE.search(encode_key(blob)) if _PROJECT_KEY_RE else None
    return m.group(0) if m else None


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
    s = FOREIGN_HOME.sub(PLACEHOLDER, s)
    # and the same path dash-encoded, which is how it reaches free text too:
    # a record's detail can quote ~/.claude/projects/-Users-<account>/…, and
    # that spelling was surviving into published bytes with the account name
    # intact while the slash spelling two characters away was being rewritten.
    s = s.replace(ENCODED_HOME, PLACEHOLDER)
    return FOREIGN_KEY.sub(PLACEHOLDER, s)


def leaks(blob):
    """What must never appear in a published file. Returns the reason, or ""
    — the write is refused on any of these rather than trimmed, because a rule
    that quietly edits its way out of a leak cannot be checked."""
    if HOMES + "/" in blob:
        return "an absolute home path survived redaction"
    for n in range(len(USER), PREFIX - 1, -1):
        if USER[:n] in blob:
            return "the account name survives redaction (%d of %d characters)" % (n, len(USER))
    # a home path in the key alphabet. This one refuses on ANY account name, not
    # only this machine's: a foreign key relayed through this ledger (a CI log,
    # a transcript from another laptop) names somebody who never agreed to be
    # named, and the account-name loop above cannot see them because it only
    # knows one name.
    key = FOREIGN_KEY.search(blob)
    if key:
        return "an absolute home path survived redaction, in project-key form (%s)" % key.group(0)
    hit = _project_hit(blob)
    if hit:
        return "a withheld project name survived the drop (%d characters)" % len(hit)
    return ""


def names_a_sensitive_project(blob):
    """True when this text names a repository whose NAME is the disclosure.
    Used to DROP a record; there is no rewrite that keeps it."""
    return _project_hit(blob) is not None


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
    """The project label on a record, with nothing identifying left in it.

    Three spellings arrive here and only the first was ever handled.

      `rabadon`            a basename, which is what the gate writes when the
                           session tells it one.
      `<account>`          a session started in the home DIRECTORY, named after
                           the directory, which is the account name and not a
                           project. Project names are published on purpose; an
                           account name is not one.
      `-Users-<account>`   the working directory dash-encoded, whole, account
      `-Users-<account>-   name and all. 300 records in this ledger. This is
       work-rabadon`       the spelling that reached the refusal check with the
                           name intact and stopped the deploy.

    This file is served from the same directory it redacts, so the examples
    above are written with a placeholder and not with the name on this machine.

    The third is rewritten the way the first two are, because it is a path and
    paths are rewritten here; the encoded home comes off and the last segment
    of what remains is the label. What is left of an encoded home is nothing,
    so a home-directory session lands on `home` from either spelling — which is
    the point: the two were the same session all along.
    """
    p = (pipe or "-").split(":")[0]
    # `-` is what a record with no project recorded carries, and it is not an
    # encoded path. Folding it into `home` would turn "not known" into a place,
    # which is the one thing a redaction may never do — it is free to hide a
    # fact and never free to invent one.
    if _ENCODED_KEY.match(p):
        rest = FOREIGN_KEY.sub("", p.replace(ENCODED_HOME, ""), count=1).strip("-")
        p = rest.rsplit("-", 1)[-1] if rest else USER
    return "home" if p == USER else p
