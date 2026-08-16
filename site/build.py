#!/usr/bin/env python3
"""Generate the pages that must never be written by hand.

A changelog somebody maintains starts lying the week after it is written, so
patch-notes and pull-requests are read straight out of the repository and off
GitHub every time this runs. benchmarks carries measured numbers, each one with
the command and the file that produced it, so a claim on that page can always be
walked back to a run.

    python3 site/build.py && (cd site && vercel deploy --prod --yes)
"""
import glob
import html
import json
import os
import re
import subprocess
import time
import sys
from collections import Counter, OrderedDict

# the one redactor. site/field_stats.py publishes field.jsonl through it and
# site/rule_census.py publishes the census through it; the pages are built
# from the same ledger and must not be redacted by a different rule.
import redact

REPO_URL = "https://github.com/nosey-dewdrop/rabadon"
SEP = "\x1f"  # unit separator: safe inside a commit subject, unlike | or tab

# the three files a number is allowed to come from, and nowhere else.
#   measured.json  written by native/measure.sh, one entry per number, each
#                  carrying the script that produced it and the commit it was
#                  produced at. never edited by hand.
#   cases.json     the defect mine: 31 real fixes pulled out of eight projects'
#                  own history, with the patch for each one beside it.
#   findings.jsonl one line per defect found, in rabadon or in somebody else's
#                  code, with the command that proves it. appended by
#                  site/finding.py, never typed into a page.
MEASURED_PATH = "site/measured.json"
DEFECTS_PATH = "reports/2026-08-01-real-defect-mine/cases.json"
FINDINGS_PATH = "site/findings.jsonl"

# the overview was the last page anybody maintained by hand, and it drifted 25
# refusals and 33 commits behind the pages built from the same sources before
# anyone noticed. it is a template now: every headline number is a placeholder,
# native/site_claims_test.sh fails if a literal creeps back in, and it fails
# again if the same fact ends up with two values on two pages.
INDEX_TMPL = "site/index.tmpl.html"

NAV = [("/", "overview"), ("/field", "the field"), ("/catches", "catches"),
       ("/benchmarks", "benchmarks"), ("/patch-notes", "patch notes"),
       ("/pull-requests", "pull requests"), (REPO_URL, "github")]

# the published field records: one line per verdict, written by
# site/field_stats.py off the ledger, with home paths rewritten and anything
# matching the sensitive-terms list dropped and counted.
FIELD_PATH = "site/field.jsonl"

# where the gate writes what it refused. read at build time, never typed in.
SPOOL = os.path.expanduser("~/.rabadon/spool")

# a refusal is only worth showing if a human can tell what it stopped, so each
# rule carries the sentence a reader needs and nothing about the private repo it
# fired in. names of unreleased projects do not go on a public page.
RULE_TEXT = {
    "no-force-push-main":       "a force push aimed at a shared branch",
    "baseline-force-push":      "a force push aimed at a shared branch, caught by the compiled-in law",
    "baseline-rm-rf-outside":   "a recursive delete whose target resolved outside the project tree",
    "no-rm-rf-outside":         "a recursive delete whose target resolved outside the project tree",
    "no-rm-rf-outside-project": "a recursive delete whose target resolved outside the project tree",
    "push-gate":                "a push where the code had been edited after the last passing test run",
    "promise-off-target":       "a session drifting off the thing it said it was doing",
    "no-gnu-timeout-on-macos":  "a command calling a binary that does not exist on this machine",
    "no-hook-bypass":           "a commit trying to step around the repository's own hooks",
    "no-hard-reset-main":       "a hard reset pointed at a shared branch",
    "baseline-hard-reset":      "a hard reset pointed at a shared branch, caught by the compiled-in law",
    "no-wrangler-deploy":       "a deploy command fired from a session that was not deploying",
}

# ---------------------------------------------------------------------------
# measured numbers. every row carries the command that produced it; nothing here
# is estimated, and a number without a source does not go on the page.
# corpus: reports/2026-08-01-hakem-korpusu/README.txt
# ---------------------------------------------------------------------------
SUITES = [
    # repo, language, tests, green seconds, flake runs, locked files
    ("expressjs/express",     "node",   1260,  1.85, "3/10",  91),
    ("lodash/lodash",         "node",   7158, 19.24, "0/10",   6),
    ("tj/commander.js",       "node",   1373,  5.06, "0/10", 123),
    ("colinhacks/zod",        "node",   3811, 45.00, "2/10",   2),
    ("date-fns/date-fns",     "node",   3167,  8.43, "1/10",  16),
    ("ajv-validator/ajv",     "node",   7962, 23.97, "2/11",  75),
    ("koajs/koa",             "node",    440,  5.90, "0/11",  73),
    ("pallets/click",         "python", 1965, 17.93, "0/10",  46),
    ("pallets/jinja",         "python",  911,  6.67, "0/10",  26),
    ("pallets/markupsafe",    "python",   80,  0.96, "0/10",   7),
    ("arrow-py/arrow",        "python", 1902,  7.44, "0/10",  10),
    ("yaml/pyyaml",           "python", 1287,  3.66, "0/10",  25),
]

# the rows of the gate table, in page order. The VALUE and the SOURCE come out
# of measured.json; only the sentence about what moved it lives here, because
# that is prose and not a number. A key with no entry in measured.json renders
# as "not measured" rather than as its last known value.
GATE_ROWS = [
    ("gate.judge_us",
     "there was no number before this one. the page said 42.0&micro;s and named a "
     "file that did not exist, so the first honest measurement is this one"),
    ("hook.native_ms",
     "the whole hook, not just the verdict: fork, read the event, load state, judge, "
     "write the ledger line, exit"),
    ("hook.node_ms",
     "the gate this replaced, on the same 40 events, with verdict parity asserted first"),
    ("gate.precision",
     "55.0% before one resolver answered the path question for both layers"),
    ("gate.recall",
     "unchanged, and the floor the precision work was not allowed to move"),
    ("gate.precision_ledger",
     "the same binary, the same question, asked of everything that really happened "
     "instead of 34 chosen cases. the fixture number is not wrong, it is narrow"),
    ("gate.precision_ledger_real",
     "41 of the 42 refusals it cut were rabadon's own red-team labs, and a tool that "
     "pads its own numbers with its own drills has no business judging anyone else"),
    ("gate.redteam_open",
     "319 attempts over four rounds named 95 ways past this gate; this is how many "
     "of them the current binary still lets through"),
    ("gate.cases",
     "every one lifted out of a real session, none written for the test"),
    ("repair.green_paths_refused",
     "3 of 6 before the harness itself was locked"),
]


def sh(args):
    return subprocess.run(args, capture_output=True, text=True, check=False)


def load_json(path, default=None):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def measured():
    """Every measured number, with the run behind it. Missing is not zero."""
    return load_json(MEASURED_PATH, {}) or {}


def mval(meas, key, field="display"):
    """A number that was never measured renders as `not measured`, and says so
    on the page. Rounding an absent number into shape is the one thing this
    whole arrangement exists to prevent."""
    e = meas.get(key)
    if not e:
        return "not measured"
    if field in e:
        return str(e[field])
    v = e.get("value")
    return "not measured" if v is None else str(v)


# ---------------------------------------------------------------------------
# one number, one sentence, and the thing that proves it
# ---------------------------------------------------------------------------
# Every number on this site was produced by a run, and the page should behave
# that way rather than merely say so: the number IS the link to its own
# evidence. It also carries its value as data, so the reveal counts up to it
# instead of appearing already finished. Used by every page, so a stat cannot
# look one way on the overview and another way on catches.
# ---------------------------------------------------------------------------
# a table is a table
# ---------------------------------------------------------------------------
# Every table on this site used to be a <div> of preformatted text whose columns
# were aligned by counting spaces in python (`%-24s`) under `white-space:pre`.
# That is not alignment, it is a guess about how wide a string will render, and
# it fails the moment any cell is longer than the pad: the row shoves right, the
# sentence runs past the edge of its own box, the panel sizes itself to its
# longest line so no two panels share a margin, and on a phone the whole thing
# becomes a horizontal scroll. A crawler sees one blob of text where a table
# should be, which is the real reason these pages carry no structure.
#
# So the browser does the alignment now. The panel keeps the terminal look --
# monospace, tabular figures, the dark field -- and the inside is a real table:
# numeric columns right-aligned by CSS, the prose column wrapping inside its own
# cell, every panel on the same grid, and <th> where a heading belongs.
def table(cols, rows, cls=""):
    """cols: (label, kind) where kind is 'n' numeric, 's' name, 'd' prose.
    rows: lists of cells; a cell may be (text, extra_class) or plain text."""
    def cell(c, kind, tag="td"):
        extra = ""
        if isinstance(c, tuple):
            c, extra = c[0], " " + c[1]
        return f'<{tag} class="{kind}{extra}">{c}</{tag}>'
    head = "".join(cell(html.escape(str(lbl)), kind, "th") for lbl, kind in cols)
    body = "".join(
        "<tr>" + "".join(cell(c, cols[i][1]) for i, c in enumerate(r)) + "</tr>"
        for r in rows)
    return (f'<table class="tt {cls}"><thead><tr>{head}</tr></thead>'
            f"<tbody>{body}</tbody></table>")


def evidence_href(meas, key, fallback=None):
    """Where a reader goes to check this number. A measured value points at the
    script that produced it, on GitHub, at the commit it was measured at."""
    e = (meas or {}).get(key) or {}
    cmd = e.get("cmd", "")
    for w in cmd.split():
        w = w.strip("'\"")
        if "/" in w and os.path.exists(w):
            ref = e.get("commit") or "main"
            return f"{REPO_URL}/blob/{ref}/{w}"
    return fallback


def stat(cls, value, caption, href=None, display=None):
    show = display if display is not None else (
        f"{value:,}" if isinstance(value, int) else str(value))
    data = ""
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        data = f' data-to="{value}" data-show="{html.escape(str(show))}"'
    if href:
        num = (f'<a class="n {cls}" href="{html.escape(href)}"{data}>'
               f'{show}</a>')
    else:
        num = f'<span class="n {cls}"{data}>{show}</span>'
    return num + f'<span class="t">{caption}</span>'


def findings():
    """One defect per line. Order is newest first; a line the reader cannot
    check is not a finding, so `proof` is required and a line without one is
    dropped rather than shown."""
    out = []
    if not os.path.exists(FINDINGS_PATH):
        return out
    for line in open(FINDINGS_PATH, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not d.get("proof"):
            continue
        out.append(d)
    out.sort(key=lambda d: (d.get("date", ""), d.get("id", "")), reverse=True)
    return out


def commits():
    out = sh(["git", "log", "--no-merges", f"--format=%h{SEP}%ad{SEP}%an{SEP}%s",
              "--date=format:%Y-%m-%d %H:%M"])
    if out.returncode != 0:
        sys.exit("git log failed: " + out.stderr.strip())
    rows = []
    for line in out.stdout.splitlines():
        parts = line.split(SEP)
        if len(parts) != 4:
            continue
        h_, when, who, subject = parts
        rows.append({"h": h_, "day": when[:10], "time": when[11:],
                     "who": who, "subject": subject})
    return rows


def pull_requests():
    """Not the pull requests opened AGAINST this repo, which is a page that says
    "none yet" and teaches nobody anything. The ones sent OUT of it: fixes into
    other people's projects, read off GitHub at build time so the page cannot go
    stale and cannot be padded."""
    out = sh(["gh", "search", "prs", "--author", "@me", "--limit", "100", "--json",
              "repository,number,title,state,createdAt,url,isDraft"])
    if out.returncode != 0:
        return []
    try:
        prs = json.loads(out.stdout or "[]")
    except json.JSONDecodeError:
        return []
    me = sh(["gh", "api", "user", "--jq", ".login"]).stdout.strip()
    for p in prs:
        p["repo"] = p.get("repository", {}).get("nameWithOwner", "")
        p["mine"] = bool(me) and p["repo"].startswith(me + "/")
    prs.sort(key=lambda p: p.get("createdAt", ""), reverse=True)
    return prs


def group_by_day(rows):
    days = OrderedDict()
    for r in rows:
        days.setdefault(r["day"], []).append(r)
    return days


# ---------------------------------------------------------------------------
# lastmod: the day the PAGE changed, not the day the build ran
# ---------------------------------------------------------------------------
# This job is started every 30 minutes by launchd. Stamping today's date on all
# six urls each time tells a crawler the entire site changed 48 times a day,
# which is both false and the fastest way to get every lastmod on the site
# ignored. So each url is dated from the thing that actually produces it.
#
# The source used per url, and why:
#
#   /                the last committed rendering of site/index.html, moved to
#   /catches         today only when the page this run just rendered differs
#   /patch-notes     from it. These three read the live ledger under
#   /benchmarks      ~/.rabadon/spool and the git log, neither of which carries
#   /pull-requests   a version anybody can commit, so the honest question is
#                    "does the page say something different than the one that
#                    was published?" and the byte comparison answers it exactly.
#                    It also means a build.py edit that changes no page's words
#                    moves no date, which a source-file commit date would not.
#
#   /field           NOT the rendered bytes. Every field.* entry in
#                    measured.json carries a note ending in the raw line count
#                    of the ledger, and the gate appends to that ledger
#                    continuously -- including for the commands this build
#                    runs. The rendered page therefore changes on every single
#                    read while saying the same thing, which is the exact lie
#                    being removed here. Dated instead from the data: the VALUES
#                    under field.* in site/measured.json, the published records
#                    in site/field.jsonl, and `generated_utc` inside
#                    site/rule_census.json, which is the moment that census was
#                    actually measured rather than the moment it was committed.
#
# Two urls share a source: / and /patch-notes are both rendered off the git log
# (commit count, day count, first commit), so a commit landing moves both. They
# are still computed independently, because / also carries ledger figures that
# move without a commit.
#
# Everything here is reproducible from a clone: git commit dates, git blobs, and
# a timestamp inside a checked-in json file. File mtimes were considered and
# rejected -- a clone has no mtimes worth reading, and measured.json is rewritten
# every 30 minutes with an unchanged set of values.
def git_out(args):
    r = sh(["git"] + args)
    return r.stdout if r.returncode == 0 else None


def git_day(path):
    """The day the newest commit touching this path landed, or "" if git cannot
    say (untracked file, no git, not a repository)."""
    out = git_out(["log", "-1", "--format=%cd", "--date=format:%Y-%m-%d", "--", path])
    return (out or "").strip()


def head_text(path):
    """The file as it is committed at HEAD, or None if it is not in HEAD."""
    return git_out(["show", "HEAD:" + path])


def rendered_day(path, content, today, trust=True):
    """`content` is what this run just rendered for `path`. If it differs from
    the committed copy the content changed today; if it does not, the page has
    said the same thing since the commit that last touched it.

    trust=False when the render is known to be missing its input (gh could not
    answer for the pull requests page): a page rendered empty is not a page that
    changed, and publish-field.sh puts the committed copy back afterwards."""
    was = head_text(path)
    if trust and was is not None and content != was:
        return today
    return git_day(path) or today


def field_day(meas, today):
    """The field page, dated from its data rather than from its own bytes.
    See the note above: its bytes move on every read and its numbers do not."""
    days = []

    def values(d):
        return {k: (v or {}).get("value") for k, v in (d or {}).items()
                if k.startswith("field.")}

    was = head_text(MEASURED_PATH)
    if was is not None:
        try:
            same = values(json.loads(was)) == values(meas)
        except json.JSONDecodeError:
            same = False
        days.append(today if not same else (git_day(MEASURED_PATH) or today))
    else:
        days.append(git_day(MEASURED_PATH) or today)

    if os.path.exists(FIELD_PATH):
        recs = open(FIELD_PATH, encoding="utf-8").read()
        was = head_text(FIELD_PATH)
        days.append(today if (was is not None and was != recs)
                    else (git_day(FIELD_PATH) or today))

    c = census() or {}
    gen = str(c.get("generated_utc") or "")[:10]
    if len(gen) == 10:
        days.append(gen)
    return max(d for d in days if d)


# ---------------------------------------------------------------------------
# the shell. one stylesheet, shared by every page, so a size can only be changed
# in one place and the pages cannot drift apart.
# ---------------------------------------------------------------------------
SHELL = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>__TITLE__</title>
<meta name="description" content="__DESC__">
<meta name="author" content="Damla Su Bilge">
<link rel="canonical" href="https://rabadon.noseydewdrop.com__PATH__">
<meta property="og:type" content="website">
<meta property="og:title" content="__TITLE__">
<meta property="og:description" content="__DESC__">
<meta property="og:url" content="https://rabadon.noseydewdrop.com__PATH__">
<meta property="og:site_name" content="rabadon">
<meta property="og:image" content="https://rabadon.noseydewdrop.com/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="rabadon — guardrails and a verifiable record for coding agents">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="__TITLE__">
<meta name="twitter:description" content="__DESC__">
<meta name="twitter:image" content="https://rabadon.noseydewdrop.com/og.png">
<meta name="theme-color" content="#171221">
<meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1">
<script type="application/ld+json">__LD__</script>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' fill='%23171221'/%3E%3Crect x='6' y='6' width='6' height='20' fill='%23ff8fb3'/%3E%3Crect x='20' y='6' width='6' height='20' fill='%23ff8fb3'/%3E%3C/svg%3E">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:ital,wght@0,400;0,500;0,700;1,400&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/style.css">
</head>
<body>
<div id="stars" aria-hidden="true"></div>
<div class="wrap">
<header class="site">
  <span class="mark"><i>[</i>&#124;<i>]</i> rabadon</span>
  <nav>__NAV__</nav>
</header>
__BODY__
<footer>
  <span>built by <a href="https://www.noseydewdrop.com/">Damla Su Bilge</a></span>
  <span><a href="__REPO__">github.com/nosey-dewdrop/rabadon</a></span>
  <span class="sp">generated by <code>site/build.py</code></span>
</footer>
</div>
<script src="/effects.js"></script>
</body>
</html>
"""


# One structured-data record for the software, and a breadcrumb per page. This
# is what puts a name, a category and a link set in front of a crawler instead
# of leaving it to guess from the markup.
SITE = "https://rabadon.noseydewdrop.com"


def jsonld(path, title, desc, extra=(), main=None):
    """extra: further nodes for the graph, for a page that is more than a page.
    main: the @id of the thing the page is primarily about, which is how a
    crawler is told the page IS the dataset rather than merely mentioning one."""
    graph = [{
        "@type": "SoftwareApplication",
        "@id": SITE + "/#software",
        "name": "rabadon",
        "applicationCategory": "DeveloperApplication",
        "operatingSystem": "macOS, Linux",
        "description": "Guardrails and a verifiable record for AI coding agents. Refuses a destructive "
                       "command before the process starts, writes a hash-chained ledger, and repairs a "
                       "failing check without being able to buy its own green.",
        "url": SITE,
        "codeRepository": REPO_URL,
        "programmingLanguage": "C++",
        "license": "https://opensource.org/licenses/MIT",
        "isAccessibleForFree": True,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "author": {"@type": "Person", "name": "Damla Su Bilge",
                   "url": "https://www.noseydewdrop.com/"},
    }, {
        "@type": "WebSite",
        "@id": SITE + "/#website",
        "url": SITE,
        "name": "rabadon",
        "inLanguage": "en",
        "publisher": {"@id": SITE + "/#software"},
    }, {
        "@type": "WebPage",
        "@id": SITE + path + "#page",
        "url": SITE + path,
        "name": title,
        "description": desc,
        "isPartOf": {"@id": SITE + "/#website"},
        "about": {"@id": SITE + "/#software"},
    }]
    if main:
        graph[-1]["mainEntity"] = {"@id": main}
    graph.extend(extra)
    if path != "/":
        label = dict(NAV).get(path, title)
        graph.append({
            "@type": "BreadcrumbList",
            "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": "overview", "item": SITE + "/"},
                {"@type": "ListItem", "position": 2, "name": label, "item": SITE + path},
            ]})
    return json.dumps({"@context": "https://schema.org", "@graph": graph},
                      separators=(",", ":"))


def page(path, title, desc, body, extra=(), main=None):
    nav = "".join(
        '<a href="{}"{}>{}</a>'.format(href, ' class="here"' if href == path else "", label)
        for href, label in NAV)
    return (SHELL.replace("__LD__", jsonld(path, title, desc, extra, main))
            .replace("__TITLE__", title).replace("__DESC__", desc)
            .replace("__PATH__", path).replace("__NAV__", nav)
            .replace("__BODY__", body).replace("__REPO__", REPO_URL))


def patch_notes(rows):
    days = group_by_day(rows)
    out = ['<div class="intro">',
           "<h1>every commit in this project, since the first one.</h1>",
           '<p class="lede small dim">Read out of the repository each time this page is built, never typed by '
           "hand. A changelog somebody maintains starts lying the week after it is written, and the only "
           "version of this project worth showing is the one the history already proves.</p>",
           '<div class="proof">',
           f'<div><span class="n b">{len(rows)}</span><span class="t">commits</span></div>',
           f'<div><span class="n">{len(days)}</span><span class="t">days with work in them</span></div>',
           f'<div><span class="n g">{rows[-1]["day"] if rows else "-"}</span>'
           '<span class="t">first commit</span></div>',
           "</div></div>", "<section>"]
    for day, items in days.items():
        out.append('<div class="day"><span class="d">' + day +
                   f'<br><span class="c">{len(items)} commit{"s" if len(items) != 1 else ""}</span>'
                   '</span><div class="rows">')
        for r in items:
            out.append('<div class="r">'
                       f'<span class="h"><a href="{REPO_URL}/commit/{r["h"]}">{r["h"]}</a></span>'
                       f'<span class="t">{r["time"]}</span>'
                       f'<span class="s">{html.escape(r["subject"])}</span></div>')
        out.append("</div></div>")
    out.append("</section>")
    return page("/patch-notes", "rabadon patch notes — every commit, read out of the repository",
                f"All {len(rows)} commits in rabadon with the day each landed, generated from git rather "
                "than maintained by hand.",
                "\n".join(out))


def pull_request_page(prs, rows):
    """The contributions this engineer sent into other people's repositories.
    Generated off GitHub, so it cannot be padded and cannot go stale."""
    out_prs = [p for p in prs if not p.get("mine")]
    own = [p for p in prs if p.get("mine")]
    repos = sorted({p["repo"] for p in out_prs})
    merged = sum(1 for p in prs if (p.get("state") or "").lower() == "merged")

    out = ['<div class="intro">',
           "<h1>fixes sent into other people's repositories.</h1>",
           '<p class="lede small dim">Pull requests opened by the author of rabadon against projects that '
           "are not rabadon, read off GitHub every time this page is built. A contribution list somebody "
           "maintains by hand is a list that flatters; this one is whatever the API returns.</p>",
           '<div class="stats">']
    out.append(stat("p", len(out_prs), f"pull requests into {len(repos)} projects that are not this one",
                    "https://github.com/pulls?q=is%3Apr+author%3A%40me"))
    out.append(stat("g", merged, "merged so far", None))
    out.append(stat("b", len(own), "in this engineer's own repositories, kept separate on purpose", None))
    out.append("</div></div>")

    def block(title, items, note):
        if not items:
            return
        out.append(f"<section><h2>{title}</h2>")
        out.append(f'<p class="small dim">{note}</p>')
        by = OrderedDict()
        for p in items:
            by.setdefault(p["repo"], []).append(p)
        for repo, group in by.items():
            out.append('<div class="day"><span class="d">' +
                       f'<a href="https://github.com/{html.escape(repo)}">{html.escape(repo)}</a>'
                       f'<br><span class="c">{len(group)} pull request{"s" if len(group) != 1 else ""}</span>'
                       "</span><div class=\"rows\">")
            for p in group:
                state = (p.get("state") or "").lower()
                cls = {"merged": "merged", "open": "open"}.get(state, "closed")
                when = (p.get("createdAt") or "")[:10]
                out.append('<div class="pr">'
                           f'<span class="h"><a href="{html.escape(p.get("url",""))}">#{p.get("number","")}</a></span>'
                           f'<span class="s">{html.escape(p.get("title",""))}</span>'
                           f'<span class="st {cls}">{cls} {when}</span></div>')
            out.append("</div></div>")
        out.append("</section>")

    block("into other people's projects", out_prs,
          "Every one of these is a fix in somebody else's codebase, read and reproduced before it was "
          "written. The repository name opens the project; the number opens the pull request.")
    block("in this engineer's own repositories", own,
          "Kept in a separate list, because counting your own pull requests alongside somebody else's is "
          "the kind of padding this whole site exists to refuse.")

    out.append('<section><h2>contributing to rabadon</h2>'
               '<p class="small dim">The bar is written down: a regression test comes first and is shown red '
               "before the fix, every test that must block carries a twin that must not, and a "
               "destructive-command test runs in an isolated temp repository with a canary in it. "
               f'<a href="{REPO_URL}">the source is here</a>.</p></section>')
    return page("/pull-requests", "open-source contributions by the author of rabadon",
                f"{len(out_prs)} pull requests into {len(repos)} open-source projects, "
                "read off GitHub at build time. Performance, correctness and observability fixes in "
                + ", ".join(r.split("/")[-1] for r in repos[:5]) + ".",
                "\n".join(out))


def benchmarks(rows, meas):
    total_tests = sum(s[2] for s in SUITES)
    flaky = sum(1 for s in SUITES if not s[4].startswith("0/"))
    out = ['<div class="intro">', "<h1>measured, with the command that measured it.</h1>",
           '<p class="lede small dim">A number with no run behind it is a slogan. Every row here was '
           "produced on one machine by the command named beside it, and the ones that could not be measured "
           "cleanly say so rather than being rounded into shape.</p>",
           '<div class="proof">',
           f'<div><span class="n g">{mval(meas, "gate.precision")}</span>'
           f'<span class="t">gate precision, recall {mval(meas, "gate.recall")}</span></div>',
           f'<div><span class="n b">{mval(meas, "gate.judge_us")}</span>'
           f'<span class="t">to judge one command</span></div>',
           f'<div><span class="n y">{len(SUITES)}</span><span class="t">real suites it was run against</span></div>',
           f'<div><span class="n p">{total_tests:,}</span><span class="t">tests in those suites</span></div>',
           "</div></div>",
           "<section><h2>the gate</h2>",
           '<div class="bench"><div class="head"><span>what</span><span style="text-align:right">now</span>'
           "<span>before, and what moved it</span><span>where it is measured</span></div>"]
    for key, before in GATE_ROWS:
        e = meas.get(key, {})
        what = e.get("what", key)
        now = mval(meas, key)
        where = e.get("cmd", "not measured")
        out.append(f'<div class="row"><span class="s">{html.escape(what)}</span><span class="n">{now}</span>'
                   f'<span class="d">{before}</span><span class="w">{html.escape(where)}</span></div>')
    out.append("</div>")
    # the note under the table is the part a reader checks: when, and against
    # which commit. a number measured against a tree that has since moved is
    # still a real number, and saying which tree is what keeps it one.
    stamps = sorted({(e.get("measuredAt", "?"), e.get("commit", "?"))
                     for k, e in meas.items() if not k.startswith("_")})
    if stamps:
        out.append('<p class="cap">Measured on ' +
                   ", ".join(f"{html.escape(d)} at <code>{html.escape(c)}</code>" for d, c in stamps) +
                   ". Re-run all of it with <code>./native/measure.sh</code>; every value on this page is "
                   "written by that run into <code>site/measured.json</code> and read back here, so a number "
                   "and the run behind it cannot come apart.</p>")
    out.append("</section>")

    out.append('<section><h2>the suites it was run against</h2>'
               '<p class="small dim" style="margin-bottom:var(--g2)">Twelve open-source projects, each pinned '
               "to a commit, each installed and taken green before anything was measured. Flake is the share "
               "of clean runs that came back red with no patch applied at all, which is the number that "
               "decides whether a red run may be treated as a verdict. Locked is how many test files the "
               "judge hashes before a proposer is allowed to touch the tree.</p>"
               '<div class="bench wide"><div class="head"><span>project</span>'
               '<span style="text-align:right">tests</span><span style="text-align:right">green</span>'
               '<span style="text-align:right">flake</span><span style="text-align:right">locked</span>'
               "<span>language</span></div>")
    for repo, lang, tests, green, flake, locked in SUITES:
        fl = "g" if flake.startswith("0/") else "y"
        out.append(f'<div class="row"><span class="s">{repo}</span>'
                   f'<span class="n">{tests:,}</span>'
                   f'<span class="n">{green:.2f}s</span>'
                   f'<span class="n {fl}">{flake}</span>'
                   f'<span class="n">{locked}</span>'
                   f'<span class="d">{lang}</span></div>')
    out.append("</div>")
    out.append(f'<p class="cap">Eight of the twelve produced no red run at all on a clean tree. '
               f'{flaky} did, and those four are the reason the arbiter re-samples a red before it is '
               "allowed to become a verdict: on a suite that flakes, a single red throws away a correct "
               "fix somebody already paid for.</p>")
    out.append("</section>")

    out.append('<section><h2>what is still open</h2>'
               '<p class="small dim">Four rounds of red-teaming this gate, 319 attempts, named 95 ways past '
               "it. One representative command each, judged by the binary this page describes: 37 refused, "
               "58 allowed. They fall into four groups, and none of them is a surprise the code did not "
               "already suspect.</p>"
               '<div class="term"><span class="hdr">group                                          open   why</span>\n'
               '14 the deleting verb is not rm                    <span class="r">14</span>   '
               '<span class="o">find -delete, rsync --delete, truncate, dd, shred, a bare redirect. the law knows five verbs</span>\n'
               ' 5 the shell moved and nobody followed             <span class="r">5</span>   '
               '<span class="o">pushd, cd -P, cd --. plain cd is followed; its options and pushd are not</span>\n'
               '11 the program is not on the line                 <span class="r">11</span>   '
               '<span class="o">bash s.sh, npm run deploy, python3 -c. three of them record a PARSE_LIMIT, the rest are silent</span>\n'
               '28 git has other ways to the same place           <span class="r">28</span>   '
               '<span class="o">git push --forc (git accepts abbreviations), branch -D main, clean -xfd, reset --hard @{u}, rm -rf .git</span>'
               "</div>"
               '<p class="cap">Enforce mode IS on, and these are its published limits. This line used to read '
               '"enforce mode is not on, and this is the reason" — true when it was written, false from the '
               "day the switch was turned on, and left standing on a page nobody re-read. A claim about the "
               "machine that outlives the machine is the same defect this project measures in other people's "
               "numbers. The escapes stay published beside the refusals, because a gate that promises a "
               "protection it cannot hold is worse than one that says what it stops. Reproduce with "
               "<code>python3 redteam/redteam.py</code>; it judges and never runs, with every destructive "
               "binary shadowed on PATH and the log of what they were asked to do asserted empty.</p>"
               "</section>")

    out.append('<section><h2>what has not been measured</h2>'
               '<p class="small dim">A quiet machine. Every run on this page shared its box with other work, '
               "so the wall-clock columns are contaminated and the pass or fail results are not. A second "
               "node version, to see whether the express flake follows the runtime. The date decay in "
               "date-fns, whose red rate climbs with the calendar. And the real test-file count in six of "
               "the twelve repositories, which leaves the question of how much of each suite the lock "
               "actually covers open in those six.</p></section>")
    return page("/benchmarks", "rabadon benchmarks — every number with the command that produced it",
                "Gate latency, precision and recall for rabadon, measured on 34 real cases and replayed "
                "against a full ledger. Every figure names the script that produced it and the commit it "
                "was measured at.", "\n".join(out))


def ledger():
    """Read the gate's own spool. A drill is a rehearsal the test suite fired,
    and counting one as a catch would be the exact dishonesty this tool exists
    to refuse, so drills are separated and reported separately."""
    real, drill, ev = Counter(), Counter(), Counter()
    sample, projects = {}, Counter()
    per = {}          # project -> Counter(rule)
    per_ex = {}       # project -> {rule: the line the ledger wrote}
    raw = {}          # rule -> [the actual ledger entries, for the reader to check]
    dirs = set()
    for f in sorted(glob.glob(os.path.join(SPOOL, "*.jsonl"))):
        for line in open(f, encoding="utf-8", errors="replace"):
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            ev[d.get("ev", "?")] += 1
            if d.get("pipe"):
                dirs.add(str(d["pipe"]).split(":")[0])
            if d.get("ev") != "WOULD_BLOCK":
                continue
            rule = str(d.get("rule", "?"))
            if d.get("drill"):
                drill[rule] += 1
                continue
            real[rule] += 1
            # THE SAME REDACTOR THE DATA FILES USE, not a third spelling of it.
            # These two lines used to be `replace(home, "~")` and a `/Users/...`
            # regex written here, which is a second redactor living beside the
            # one in site/redact.py — and two redactors means the weaker one
            # decides what the site publishes. It was the weaker one: it did not
            # catch a home path the gate had clipped mid-account-name, and it
            # left the account name standing in the project column, because a
            # session started in the home directory is named after the DIRECTORY
            # and that directory is the operator's account.
            proj = redact.project_of(str(d.get("pipe", "?")))
            projects[proj] += 1
            per.setdefault(proj, Counter())[rule] += 1
            det = redact.clean(str(d.get("detail", "")), 0)
            det = re.sub(r"^command matched deny rule: ", "", det)
            det = det.replace("\n", " ").strip()
            if rule not in sample and det:
                sample[rule] = det[:150]
            if det:
                per_ex.setdefault(proj, {}).setdefault(rule, det[:150])
            if det and len(raw.setdefault(rule, [])) < 8:
                ts = d.get("ts", 0)
                day = ("%04d-%02d-%02d" % time.gmtime(ts / 1000)[:3]) if ts else "?"
                clock = ("%02d:%02d" % time.gmtime(ts / 1000)[3:5]) if ts else "?"
                raw[rule].append((day, clock, proj, det[:210]))
    return real, drill, ev, sample, projects, per, per_ex, raw


def ledger_dirs():
    """Every project name the spool has ever carried, refusal or not. The
    volume line counts repositories the gate RAN in; the refusal line counts
    repositories it refused something in, and those are not the same number."""
    dirs = set()
    for f in sorted(glob.glob(os.path.join(SPOOL, "*.jsonl"))):
        for line in open(f, encoding="utf-8", errors="replace"):
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("pipe"):
                dirs.add(str(d["pipe"]).split(":")[0])
    return dirs


def repairs_held():
    """REPAIR_OK split into work and laboratory, using field_stats' own list
    rather than a second one written here. Two exclusion lists means the weaker
    one decides what the site publishes, which is the lesson ledger() already
    carries about the redactor. Returns (real, lab)."""
    import field_stats
    real = lab = 0
    for f in sorted(glob.glob(os.path.join(SPOOL, "*.jsonl"))):
        for line in open(f, encoding="utf-8", errors="replace"):
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("ev") != "REPAIR_OK":
                continue
            if field_stats.is_lab(str(d.get("pipe", ""))):
                lab += 1
            else:
                real += 1
    return real, lab


def catches(meas):
    real, drill, ev, sample, projects, per, per_ex, raw = ledger()
    total = sum(real.values())
    # WHAT THIS PAGE COUNTS, and the correction that had to be made here.
    # ledger() reads WOULD_BLOCK and nothing else. WOULD_BLOCK is watch mode:
    # gate.cpp:2320 records the verdict, prints "Nothing was stopped", and
    # exits 0 — THE COMMAND THEN RUNS. This page called that number "commands
    # refused before they ran" and said each one "did not run", which is the
    # opposite of what the event means. trace.cpp:507 had already written the
    # warning against exactly this mislabeling, and the landing page committed
    # it anyway. The enforce-mode number, where the command genuinely did not
    # run, is field.stop, and it comes from field_stats.py rather than from a
    # second count written here — one exclusion list, not two.
    refused = mval(meas, "field.stop")
    # The same correction, applied to the repair counter. ev["REPAIR_OK"] is the
    # whole spool, and the whole spool includes the demo and the repair harness's
    # own scratch tree. Counting a harness's accepted repairs as repairs held on
    # real work is the drill-padding this page condemns two paragraphs up.
    held, held_lab = repairs_held()
    mine = projects.get("rabadon", 0)
    others = len([p for p in projects if p != "rabadon"])

    out = ['<div class="intro">', "<h1>what it actually caught.</h1>",
           '<p class="lede small dim">Read straight out of the gate\'s own spool when this page was built. '
           "Every line below is a command that was about to run on a real machine, during real work, and that "
           "the gate ruled against. The lines on this page are watch-mode verdicts, which means the ruling was "
           "recorded and the command ran anyway; enforce mode is the column where it did not run, and that "
           "number is counted separately below. Rehearsals fired by the test suite are counted separately too "
           "and left out of both, because a tool that pads its own numbers with its own drills has no business "
           "judging anyone else's proof.</p>",
           '<div class="proof">',
           f'<div><span class="n p">{refused}</span><span class="t">commands refused in enforce mode, where the command did not run</span></div>',
           f'<div><span class="n y">{total}</span><span class="t">verdicts recorded in watch mode, where nothing was blocked and the command ran</span></div>',
           f'<div><span class="n b">{others + 1}</span><span class="t">repositories those watch-mode verdicts happened in</span></div>',
           f'<div><span class="n g">{held}</span><span class="t">repairs held after the proof survived, on work that was real</span></div>',
           f'<div><span class="n y">{sum(drill.values())}</span><span class="t">drills, excluded from both totals</span></div>',
           f'<div><span class="n y">{held_lab}</span><span class="t">further repairs held inside the demo and the repair harness, excluded for the same reason</span></div>',
           "</div></div>"]

    # what a buyer actually asks: which project, and what was it about to do.
    # every count opens onto the ledger lines behind it, so no number on this
    # page has to be taken on trust.
    # keyed on what redact.project_of RETURNS, not on the account name it maps
    # away: a session started in the home directory used to arrive here spelled
    # as the operator's account, and this table was the last place on the site
    # that spelling was written down by hand.
    NICE = {"home": "the home directory itself",
            "damla_projects_2026": "the projects root",
            "icerik": "the writing repository",
            "p": "a scratch repository"}
    out.append("<section><h2>project by project</h2>"
               '<p class="small dim">Each line is the sentence the ledger wrote at the moment the gate ruled '
               "against the command, with the home path stripped and nothing else changed. These are "
               "watch-mode verdicts, so the command then ran. Open any rule to read the raw entries behind "
               "the count.</p>")
    for proj, count in projects.most_common():
        if count < 2 and proj not in per_ex:
            continue
        title = proj if proj not in NICE else f"{proj}  ({NICE[proj]})"
        rows = []
        for rule, n in per.get(proj, Counter()).most_common():
            rows.append([(n, "p"), html.escape(rule),
                         html.escape(per_ex.get(proj, {}).get(rule, ""))])
        out.append(f'<h3>{html.escape(title)} <span class="c">{count} ruled against</span></h3>')
        out.append(table([("verdicts", "n"), ("rule", "s"),
                          ("the line the ledger wrote", "d")], rows, "ledger"))

    out.append('<p class="cap">The delete law reads a resolved path, not the text of the command, which is '
               "why a target written as a relative name and a target written through a temp directory are the "
               "same question to it. The line from LMCache is the sharpest one here: a stray redirection was "
               "about to be handed to a recursive delete as if it were a directory.</p>")
    out.append("</section>")

    out.append("<section><h2>the raw ledger, rule by rule</h2>"
               '<p class="small dim">Nothing above needs to be taken on trust. These are entries as the gate '
               "wrote them, timestamp, project and reason, with only the home path replaced. Some of them "
               "fired while rabadon's own test scaffolding was running, and those are left in rather than "
               "quietly dropped, because a page that hides its own noise is asking to be believed instead of "
               "checked.</p>")
    for rule, count in real.most_common():
        entries = raw.get(rule, [])
        if not entries:
            continue
        rows = [[html.escape(f"{day} {clock}"), html.escape(proj), html.escape(det)]
                for day, clock, proj, det in entries]
        out.append("<details><summary>" + html.escape(rule) + f", {count} ruled against, "
                   f'showing {len(entries)}</summary><div class="body">' +
                   table([("when", "s"), ("project", "s"), ("what it ruled against", "d")],
                         rows, "ledger") + "</div></details>")

    out.append("</section>")

    out.append('<section><h2>what it repaired</h2>'
               '<p class="small dim" style="margin-bottom:var(--g2)">A catch is half the product. When a '
               "check goes red, a fix is proposed in an isolated copy and only held if the project's own "
               "suite goes green with every test file and every harness file byte-identical.</p>")
    # A SECOND UNFILTERED COUNTER, on the same page as the filtered one.
    #
    # These four read ev[...] straight off the whole spool — every laboratory
    # run, every demo, every drill. On the same build the headline said 425
    # commands refused and this block said 1,667 runs stopped, and 102 repairs
    # held against a repair counter that had already been split into 32 on real
    # work and 70 inside the harness. Two numbers for one fact, both published,
    # eighty lines apart.
    #
    # The refusal count comes from measured.json now, which is the one place
    # that applies the drill and laboratory filters. The repair counts come from
    # repairs_held(), which is the same split the proof block above prints.
    out.append('<div class="ledger">'
               f'<div class="item"><span class="n g">{held}</span>'
               '<span class="t">repairs held on real work, proof intact</span></div>'
               f'<div class="item"><span class="n p">{ev.get("REPAIR_FAIL", 0)}</span>'
               '<span class="t">repairs refused, fail-closed, tree untouched</span></div>'
               f'<div class="item"><span class="n y">{mval(meas, "field.stop")}</span>'
               '<span class="t">commands refused outright, so they never ran</span></div>'
               f'<div class="item"><span class="n b">{mval(meas, "field.would_block")}</span>'
               '<span class="t">verdicts recorded in watch mode, where nothing was blocked</span></div>'
               "</div>")
    out.append('<p class="cap">Two of those held repairs were real source defects in expressjs/express, an '
               "off-by-one and a reversed comparison, judged by that project's own suite of 1,260 tests with "
               "91 test files hash-locked. The working tree was never edited. On the same run a proposer that "
               "bought its green by skipping tests was refused.</p></section>")

    # ---- the cheat corpus, against the shipped binary ----------------------
    # The audit that built these families ran them through a shell reproduction
    # of the arbiter, so "this would have been accepted" was a statement about
    # the reproduction. This table is the product's own output.
    meas = measured()
    cheats = (meas.get("corpus.cheats") or {}).get("value") or []
    if cheats:
        acc = [c for c in cheats if c["verdict"] == "ACCEPTED"]
        WHY = {"test-tamper": "the suite's own bytes moved",
               "harness-tamper": "the machinery that chooses which tests run moved",
               "held-out": "the green did not survive the patch's own crutch",
               "still-red": "the check never went green",
               "held-unverified": "held, and explicitly not certified"}
        out.append('<section><h2>the ways of buying a green, against the binary that ships</h2>'
                   '<p class="small dim" style="margin-bottom:var(--g2)">Nine families of fake fix, built by '
                   "auditing this arbiter for the ways a proposal can turn a suite green without repairing "
                   "anything. Each one runs the real <code>rabadon-repair</code> with its own proposer script "
                   "in <code>RABADON_CLAUDE_BIN</code>, against a checkout that is genuinely broken. Where a "
                   "patch is held it is applied to a fresh copy and probed for whether the defect is still "
                   "there, which is the question the arbiter itself never asks.</p>")
        rows = ['<span class="hdr">family                     verdict           why</span>']
        for c in cheats:
            v = c["verdict"]
            cls = "g" if v != "ACCEPTED" else "r"
            rows.append('%-26s <span class="%s">%-16s</span> <span class="o">%s</span>' % (
                html.escape(c["family"]), cls, v, html.escape(WHY.get(v, ""))))
        rows.append("")
        rows.append('<span class="hdr">%d run   %d refused   %d accepted   %d held patches still carrying the defect</span>'
                    % (len(cheats), len(cheats) - len(acc), len(acc),
                       sum(1 for c in cheats if c.get("bug") == "STILL-THERE")))
        out.append(term(rows))
        out.append('<p class="cap">Run with <code>./native/corpus_cheats.sh</code>. The first pass through it '
                   "is what found the lock that was covering nothing: on a repository where discovery names 122 "
                   "test files the arbiter locked zero, because it read that answer out of a buffer holding only "
                   "the last 4000 bytes of it.</p>")
        out.append("</section>")

    # ---- the defect ledger: what it FOUND, not what it refused -------------
    # The spool answers "what did the gate stop". It cannot answer "what did
    # this thing find", and until now that answer lived in report directories
    # nobody outside this machine reads. One line per defect, appended by
    # site/finding.py, and a line with no command behind it never reaches here.
    fs = findings()
    if fs:
        mine_rows = [f for f in fs if f.get("repo") == "rabadon"]
        out_rows = [f for f in fs if f.get("repo") != "rabadon"]
        repos = len({f.get("repo") for f in out_rows})
        out.append('<section><h2>what it found</h2>'
                   '<p class="small dim" style="margin-bottom:var(--g2)">A refusal is what the gate stopped. '
                   "This is the other column: defects found in code, in rabadon's own source and in other "
                   "people's, each with the command that demonstrates it. Written by "
                   "<code>site/finding.py</code> when the defect is found, never typed into this page, so a "
                   "finding cannot be here without the run that produced it.</p>")
        out.append('<div class="ledger">'
                   f'<div class="item"><span class="n p">{len(fs)}</span>'
                   '<span class="t">defects on the ledger, each with its own command</span></div>'
                   f'<div class="item"><span class="n b">{len(out_rows)}</span>'
                   f'<span class="t">in {repos} open-source projects that are not this one</span></div>'
                   f'<div class="item"><span class="n g">{sum(1 for f in fs if f.get("status") == "fixed")}</span>'
                   '<span class="t">fixed, with the suite that proves it</span></div>'
                   "</div>")
        for title, group in (("in rabadon itself", mine_rows), ("in other people's code", out_rows)):
            if not group:
                continue
            out.append(f"<h3>{title}</h3>")
            for f in group:
                st = html.escape(str(f.get("status", "?")))
                cls = {"fixed": "merged", "held": "open"}.get(st, "closed")
                body = ['<span class="c">' + html.escape(str(f.get("repo", ""))) + "  " +
                        html.escape(str(f.get("file", ""))) + "</span>",
                        '<span class="o">' + html.escape(str(f.get("broke", ""))) + "</span>", ""]
                if f.get("detail"):
                    body.append('<span class="o">' + html.escape(str(f["detail"])) + "</span>")
                    body.append("")
                body.append('<span class="p">$</span> <span class="u">' +
                            html.escape(str(f.get("proof", ""))) + "</span>")
                out.append(f'<details><summary>{html.escape(str(f.get("date","")))}  '
                           f'<span class="st {cls}">{st}</span>  '
                           f'{html.escape(str(f.get("broke",""))[:96])}</summary>'
                           '<div class="body"><div class="term">' + "\n".join(body) +
                           "</div></div></details>")
        out.append("</section>")

    return page("/catches", "what rabadon caught — every command the gate ruled against, from its own ledger",
                f"{refused} commands refused outright in enforce mode and {total} verdicts recorded in "
                "watch mode, read out of the gate's own ledger.",
                "\n".join(out))


# ---------------------------------------------------------------------------
# the field. What the engine did in repositories where the work was real.
# ---------------------------------------------------------------------------
# The ledger had been recording since 25 July and nothing surfaced it, so nine
# days of evidence sat in ~/.rabadon/spool/*.jsonl where the person who wrote the
# engine could not see it either. Every number on this page comes out of
# site/measured.json under a `field.` key, written by site/field_stats.py, which
# reads that ledger and nothing else. Nothing here is typed.
#
# The distinction the page is built around: WATCH mode records the verdict and
# lets the command run, ENFORCE mode refuses it. Nearly all of this happened in
# watch mode, which is the honest way to read it -- these are not saves, they are
# what arming it would have cost, measured before arming it.
FIELD_SUMMARY = {
    "field.would_block": "commands it would have refused, recorded while blocking nothing",
    "field.would_block_own": "of those, in this engineer&#39;s own repositories, not in a test fixture",
    "field.stop": "commands it refused outright once it was armed, so they never ran",
    "field.days": "days the ledger has been running, unbroken",
}


def fval(meas, key, default=0):
    """The number itself, for arithmetic and for the count-up. mval() renders a
    missing number as the words `not measured`, which is right on a page and
    wrong in a sum."""
    v = (meas.get(key) or {}).get("value")
    return default if v is None else v


# The census of every guard rule on this machine: for each one, whether the real
# gate binary refuses the command that rule was written to refuse. Produced by
# driving the gate 430 times rather than by reading 430 regexes, which is the
# only way the answer is worth anything.
CENSUS_PATH = "site/rule_census.json"


def census():
    return load_json(CENSUS_PATH, None)


def census_block(c):
    """A rule that lints clean and cannot fire is the failure this whole file is
    about, one layer in. The page prints the count, the mechanism behind each
    dead rule, and the fact that the measurement predates the repairs."""
    h = c.get("headline") or {}
    out = ["<section><h2>and how many of the laws can fire at all</h2>",
           '<p class="small dim">A rule that reads correctly to a person, passes '
           "<code>rabadon lint</code>, and is structurally incapable of ever refusing anything is "
           "the same failure this page is about, one layer in. So every guard rule on this machine "
           "was put through the real gate binary with a command it was written to refuse. Not a "
           "reading of the pattern, a run of the engine, "
           f'{h.get("total", 0)} times.</p>']
    out.append('<div class="stats">')
    out.append(stat("g", h.get("can_fire", 0),
                    f'of {h.get("total", 0)} guard rules on this machine can actually fire, across '
                    f'{h.get("guards", 0)} guard files', None))
    out.append(stat("r" if h.get("cannot_fire") else "g", h.get("cannot_fire", 0),
                    "cannot fire at all, in any repository, ever", None))
    out.append(stat("y", h.get("shadowed", 0),
                    "can fire but sit behind a broader rule in the same guard, so their name never "
                    "appears", None))
    out.append(stat("b", h.get("undecided", 0),
                    "undecided, because a claim nobody could construct a probe for is not a "
                    "measurement", None))
    out.append("</div>")

    mech = c.get("by_mechanism") or []
    if mech:
        rows = [[(m.get("count", 0), "p"), html.escape(str(m.get("mechanism", ""))),
                 html.escape(str(m.get("note", ""))[:300])] for m in mech]
        out.append(table([("rules", "n"), ("mechanism", "s"), ("what the mechanism is", "d")],
                         rows, "ledger"))

    inc = c.get("incident_authored") or {}
    if inc:
        out.append(f'<p class="cap">{inc.get("total", 0)} of these rules were written by the engine '
                   f'itself after a real incident, and {inc.get("cannot_fire", 0)} of those cannot '
                   "fire. Each one names something that had already gone wrong once and was free to "
                   "go wrong again.</p>")

    over = c.get("over_fires") or {}
    # `confirmed` is what the generator writes. The two keys read here before it
    # were `rules` and `items`, neither of which the file has ever carried, so
    # this whole block rendered nothing on the published page while looking like
    # it was rendering something — the failure mode one layer above the one the
    # section is about.
    ov = over.get("confirmed") or over.get("rules") or over.get("items") or []
    if ov:
        rows = []
        for o in ov[:12]:
            rows.append([html.escape(str(o.get("project", ""))), html.escape(str(o.get("id", ""))),
                         html.escape(str(o.get("command", o.get("probe", "")))[:120])])
        driven = over.get("allow_twins_checked", 0)
        held = over.get("allow_twins_withheld", 0)
        out.append("<h3>and the other direction</h3>"
                   '<p class="small dim">Rules that refuse work they were never written about. '
                   f"Found by driving {driven} allow twins through the gate, an allow twin being a "
                   "command the rule's own author wrote down as one that must pass. "
                   + (f"{held} more were withheld: a <code>git push</code> twin at a guard carrying "
                      "a push gate is not a judgement, because the gate forks a shell and runs the "
                      "project's own suite before deciding, and driving one would both execute "
                      "that suite and move the state the two binaries were being compared under."
                      if held else "") + "</p>")
        out.append(table([("project", "s"), ("rule", "s"), ("the command it refused", "d")],
                         rows, "ledger"))

    cmp_ = c.get("comparison") or {}
    was = cmp_.get("old_binary_remeasured") or {}
    if was:
        window = cmp_.get("measured_between_utc") or ["?", "?"]
        out.append('<p class="cap">Measured at commit <code>'
                   + html.escape(str(c.get("gate_commit", "?"))[:12]) +
                   "</code>. The first census was run at <code>"
                   + html.escape(str(cmp_.get("old_gate_commit", "?"))[:12]) +
                   "</code>, before the repairs, and it is not enough to compare this number "
                   "against that one: two figures taken at two moments differ by the clock as much "
                   "as by the code. So both binaries were built and every rule was driven through "
                   "each of them back to back, in one pass, between "
                   + html.escape(str(window[0])) + " and " + html.escape(str(window[1])) +
                   f". The old binary answered {was.get('can_fire', 0)} can fire and "
                   f"{was.get('cannot_fire', 0)} cannot, reproducing the published figure exactly; "
                   f"the repaired one answered {h.get('can_fire', 0)} and "
                   f"{h.get('cannot_fire', 0)}.</p>")
    else:
        out.append('<p class="cap">Measured at commit <code>'
                   + html.escape(str(c.get("gate_commit", "?"))[:12]) +
                   "</code>, with no comparison run beside it.</p>")
    # the census is published as a file, not only as the four numbers above, and
    # the page has to say so somewhere a reader can click: it is the second
    # distribution this page declares as a dataset.
    out.append('<p class="cap">The whole census: <a href="/rule_census.json">rule_census.json</a>, '
               f'{len(c.get("rules") or [])} rules, each with the probe it was driven with and the '
               "verdict the gate returned.</p>")
    out.append("</section>")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# /field is a dataset, and says so in a form a crawler can read
# ---------------------------------------------------------------------------
# The page publishes counts computed from a hash-chained ledger plus a per-rule
# census of every guard rule on this machine, and both underlying files are
# served from the same origin. Left as prose that is a page about numbers; as
# schema.org/Dataset it is a dataset, with the two JSON files as its
# distributions and the figures the page prints as its measured variables.
#
# Nothing in here is written by hand. Every value comes out of measured.json or
# rule_census.json, every description is the sentence that file carries about
# its own number, and a key that is missing from measured.json produces no
# variable at all rather than a zero. dateModified is the same date the sitemap
# publishes for this url, computed by field_day() from the same three sources.
FIELD_VARS = [
    # (key in measured.json, the name the page gives it)
    ("field.would_block",         "commands recorded in watch mode"),
    ("field.would_block_own",     "of those, in the operator's own repositories"),
    ("field.stop",                "commands refused outright once the gate was armed"),
    ("field.wrong_refusals",      "of those refusals, reported wrong by the operator"),
    ("field.pushes_refused",      "pushes refused on a red tree"),
    ("field.diagnoses",           "written diagnoses handed back instead of a refusal"),
    ("field.rules_written",       "rule-authoring events after an incident"),
    ("field.rules_distinct",      "distinct rules behind those events"),
    ("field.rules_distinct_live", "of those rules, in a guard file right now"),
    ("field.days",                "days the ledger has been running"),
]

# The census counts RULES. The ledger counts VERDICTS. Both headline figures
# read 430 today and they are not the same 430, so each variable carries the
# noun it counts in its own name rather than leaving a reader to assume.
CENSUS_VARS = [
    ("total",       "guard rules driven through the gate binary",
     "every guard rule on this machine, each one put through the real gate "
     "binary with a command it was written to refuse"),
    ("can_fire",    "of those rules, able to refuse anything at all", ""),
    ("cannot_fire", "of those rules, structurally unable to ever refuse", ""),
    ("shadowed",    "of those rules, able to fire but sitting behind a broader rule", ""),
    ("guards",      "guard files those rules were read from", ""),
]


def _download(name, path, url, fmt, desc):
    d = {"@type": "DataDownload", "name": name, "description": desc,
         "contentUrl": SITE + url, "encodingFormat": fmt}
    if os.path.exists(path):
        d["contentSize"] = str(os.path.getsize(path))
    return d


def field_dataset(meas, day):
    c = census() or {}
    h = c.get("headline") or {}

    variables = []
    for key, name in FIELD_VARS:
        e = meas.get(key) or {}
        v = e.get("value")
        if not isinstance(v, (int, float)) or isinstance(v, bool):
            continue                     # missing is not zero, here either
        pv = {"@type": "PropertyValue", "name": name, "value": v}
        if e.get("what"):
            pv["description"] = e["what"]
        variables.append(pv)
    for key, name, desc in CENSUS_VARS:
        v = h.get(key)
        if not isinstance(v, int):
            continue
        pv = {"@type": "PropertyValue", "name": name, "value": v}
        if desc:
            pv["description"] = desc
        variables.append(pv)

    # the interval the published records actually cover, read off the same
    # per-day tables the page prints rather than off the calendar
    days = sorted({d for d, _ in fval(meas, "field.would_block_by_day", [])} |
                  {d for d, _ in fval(meas, "field.stop_by_day", [])})

    ds = {
        "@type": "Dataset",
        "@id": SITE + "/field#dataset",
        "name": "rabadon field ledger: guard-rail verdicts from real repositories",
        "description":
            "Every verdict rabadon's gate recorded while an engineer used it to build other "
            "things, read out of the hash-chained ledger the gate writes as it runs: commands "
            "recorded in watch mode, commands refused outright once it was armed, the refusals "
            "the operator reported as wrong, and the rules the engine wrote for itself after an "
            "incident. Published alongside a census of every guard rule on the machine, each one "
            "judged by driving the real gate binary rather than by reading its pattern.",
        "url": SITE + "/field",
        "dateModified": day,
        "isAccessibleForFree": True,
        "license": "https://opensource.org/licenses/MIT",
        "creator": {"@type": "Person", "name": "Damla Su Bilge",
                    "url": "https://www.noseydewdrop.com/"},
        "isPartOf": {"@id": SITE + "/#website"},
        "measurementTechnique":
            "Verdicts are written by the gate binary at the moment it judges a command and "
            "appended to a hash-chained ledger; home paths are rewritten and records matching a "
            "sensitive-terms list are dropped and counted before publication. The rule census is "
            "produced by driving each guard rule through the real gate binary with a command that "
            "rule was written to refuse.",
        "distribution": [
            _download("field.jsonl", FIELD_PATH, "/field.jsonl", "application/x-ndjson",
                      "One JSON object per published verdict: when, which project, which "
                      "rule, and the line the ledger wrote."),
            _download("rule_census.json", CENSUS_PATH, "/rule_census.json", "application/json",
                      "One record per guard rule on the machine, with the probe it was driven "
                      "with, the verdict the gate returned, and the mechanism behind it."),
        ],
    }
    if variables:
        ds["variableMeasured"] = variables
    if len(days) >= 2:
        ds["temporalCoverage"] = days[0] + "/" + days[-1]
    return ds


def field_records():
    out = []
    if not os.path.exists(FIELD_PATH):
        return out
    for line in open(FIELD_PATH, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def live_pulse():
    """When the last refusal actually happened, said on the page itself.

    A page that prints totals and nothing else cannot be told apart from a page
    whose numbers stopped moving a month ago, and that difference is the whole
    claim. `342 refused` reads as a brochure. `the last one was two hours ago`
    is the same file saying the machine is still running.

    Read off site/field.jsonl, the file the page already links to, so the
    sentence cannot drift away from the data standing behind it."""
    stamps = [r.get("ts") for r in field_records()
              if isinstance(r.get("ts"), (int, float))]
    if not stamps:
        return ""
    newest = max(stamps) / 1000.0
    secs = max(0.0, time.time() - newest)
    if secs < 5400:
        ago = "%d minutes ago" % max(1, int(secs // 60))
    elif secs < 172800:
        ago = "%d hours ago" % int(secs // 3600)
    else:
        ago = "%d days ago" % int(secs // 86400)
    return ('<p class="cap">The last command it refused was %s, at %s. This page '
            'is rebuilt from that same file every 30 minutes, so the counts above '
            'are what the machine had done by then.</p>'
            % (html.escape(ago),
               html.escape(time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(newest)))))


def field_headline(meas):
    """The three rules that did the most, in a sentence, with the counts read off
    the same file the page reads. Typed as prose it would be a sentence that goes
    stale the next time the gate refuses anything."""
    by_rule = fval(meas, "field.would_block_by_rule", [])
    if not by_rule:
        return ""
    top = by_rule[:3]
    parts = ["%s %s" % (f"{n:,}", RULE_TEXT.get(rule, rule)) for rule, n in top]
    return html.escape("Most of it was three laws: " + "; ".join(parts) + ".")


def field_page(meas, day=None):
    day = day or field_day(meas, time.strftime("%Y-%m-%d", time.gmtime()))
    recs = field_records()
    by_rule = fval(meas, "field.would_block_by_rule", [])
    rules = fval(meas, "field.rules_list", [])
    written, live = fval(meas, "field.rules_written"), fval(meas, "field.rules_live")
    src = evidence_href(meas, "field.would_block", None)
    note = (meas.get("field.would_block") or {}).get("note", "")

    # the sentence a rule carries about itself, for the rules that carry one
    why = {r["rule"]: r.get("why", "") for r in rules if r.get("why")}

    out = ['<div class="intro">',
           "<h1>what it did while somebody was working.</h1>",
           '<p class="lede small dim">Not a fixture and not a demo. This is what the gate did while an '
           "engineer used it to build other things, read out of the hash-chained ledger it writes as it "
           "runs. It had been recording since 25 July and nothing had ever surfaced it, so the evidence "
           "sat on disk where the person who wrote the engine could not see it either. "
           "Almost all of it happened in watch mode, where a verdict is recorded and the command runs "
           "anyway, so these are not saves. They are what arming it would have cost, measured before "
           "arming it.</p>",
           '<div class="proof">']
    for key, caption in FIELD_SUMMARY.items():
        cls = {"field.would_block": "p", "field.would_block_own": "b",
               "field.stop": "y", "field.days": "g"}[key]
        out.append('<div>' + stat(cls, fval(meas, key), caption, src) + "</div>")
    out.append("</div></div>")
    out.append(cmdline("python3 site/field_stats.py"))
    if note:
        out.append(f'<p class="cap">{html.escape(note)}</p>')

    # ---- the day column, so a total cannot be read as a rate ---------------
    # The ledger is nine days old and that is not how long these verdicts took.
    # A reader given one total and one age will divide them, and the number that
    # comes out never happened, so the days are printed instead of implied.
    days_w, days_e = fval(meas, "field.days_watch"), fval(meas, "field.days_enforce")
    wb_days = dict(fval(meas, "field.would_block_by_day", []))
    st_days = dict(fval(meas, "field.stop_by_day", []))
    allday = sorted(set(wb_days) | set(st_days))
    if allday:
        rows = [[html.escape(d),
                 (f"{wb_days.get(d, 0):,}" if wb_days.get(d) else "&mdash;", "p"),
                 (f"{st_days.get(d, 0):,}" if st_days.get(d) else "&mdash;", "y")]
                for d in allday]
        out.append("<section><h2>which day, and in which mode</h2>"
                   f'<p class="small dim">The ledger is {fval(meas, "field.days")} days old. That is not '
                   f"how long these verdicts took, and the difference is the whole reason this column is "
                   f"here. Recorded verdicts land on {days_w} of those days and outright refusals on "
                   f"{days_e}, because the gate spent almost all of that time in watch mode and was only "
                   "armed at the end. A single total beside an age is a rate the reader will compute and "
                   "that never existed.</p>")
        out.append(table([("day", "s"), ("recorded, watch mode", "n"), ("refused, armed", "n")],
                         rows, "ledger"))
        if allday:
            last = allday[-1]
            if st_days.get(last, 0) > sum(st_days.get(d, 0) for d in allday[:-1]):
                out.append('<p class="cap">Most of the refusals on the last row are from one night: the '
                           "gate was armed for the first time and six agent sessions ran underneath it at "
                           "once. That is a load, not a week, and it is on its own row rather than folded "
                           "into the total above.</p>")
        out.append(cmdline("python3 site/field_stats.py"))
        out.append("</section>")

    # ---- rule by rule ------------------------------------------------------
    if by_rule:
        rows = []
        for rule, n in by_rule:
            sentence = RULE_TEXT.get(rule) or why.get(rule) or ""
            rows.append([(f"{n:,}", "p"), html.escape(rule), html.escape(sentence)])
        out.append("<section><h2>which law, how many times</h2>"
                   '<p class="small dim">Every count is a verdict the ledger recorded, grouped by the '
                   "rule that produced it. The laws with <code>baseline-</code> in front of them are "
                   "compiled into the binary and hold in a repository with no configuration at all; the "
                   "rest come from a guard file a project owns.</p>")
        out.append(table([("times", "n"), ("rule", "s"), ("what that law is about", "d")],
                         rows, "ledger"))
        out.append(cmdline("python3 site/field_stats.py"))
        out.append("</section>")

    # ---- the refusals that were wrong -------------------------------------
    # The number a guardrail vendor has the most reason not to publish, next to
    # the number every guardrail vendor publishes. A refusal count on its own is
    # not a measurement of anything; it is a measurement beside the count of
    # refusals that should not have happened, and that second figure can only be
    # read off a ledger that carries both. Until 3 August there was no record
    # type for it here either, and the wrong refusals from that night were
    # sitting in prose in a report.
    wrong = fval(meas, "field.wrong_list", [])
    wrong_n = fval(meas, "field.wrong_refusals")
    stop_n = fval(meas, "field.stop")
    out.append("<section><h2>and the refusals that were wrong</h2>"
               '<p class="small dim">A refusal count on its own measures nothing. It measures '
               "something beside the count of refusals that should not have happened, and that "
               "second number can only be read off a ledger that holds both, which is why it is "
               "here and not in a footnote. <code>rabadon wrong &lt;rule&gt; &lt;why&gt;</code> writes "
               "it onto the same hash-chained ledger as the refusal itself, so it is covered by "
               "<code>rabadon audit</code> and cannot be quietly edited down.</p>")
    out.append('<div class="stats">')
    out.append(stat("p", stop_n, "commands refused outright", src))
    out.append(stat("r" if wrong_n else "g", wrong_n,
                    "of those, reported wrong by the operator and written onto the same chain",
                    src))
    out.append("</div>")
    if wrong:
        rows = [[html.escape(w.get("rule", "")), html.escape((w.get("why") or "")[:320])]
                for w in wrong]
        out.append(table([("rule", "s"), ("why the refusal was wrong", "d")], rows, "ledger"))
        out.append('<p class="cap">Every one of these was found by being on the receiving end of '
                   "the gate rather than by reading its source. The rule that matched an in-place "
                   "editor example also refused the report saying so, because the example was in "
                   "the report as quoted text. None of the three was answered by switching the "
                   "rule off.</p>")
    out.append(cmdline("python3 site/field_stats.py"))
    out.append("</section>")

    # ---- which rule did the refusing, once it was armed --------------------
    stop_rules = fval(meas, "field.stop_by_rule", [])
    if stop_rules:
        rows = [[(f"{n:,}", "y"), html.escape(rule),
                 html.escape(RULE_TEXT.get(rule) or why.get(rule) or "")]
                for rule, n in stop_rules]
        out.append("<section><h2>which law did the refusing, once it was armed</h2>"
                   '<p class="small dim">The table further up counts recorded verdicts, which is '
                   "watch mode. This one counts commands that did not run.</p>")
        out.append(table([("times", "n"), ("rule", "s"), ("what that law is about", "d")],
                         rows, "ledger"))
        out.append(cmdline("python3 site/field_stats.py"))
        out.append("</section>")

    # ---- when supervision was on at all ------------------------------------
    # Absence of a file means unguarded, and nothing announced it. On 3 August a
    # session ran `rabadon off` at 02:25 and the machine stayed unguarded while
    # four other sessions kept working under it, with no event anywhere.
    modes = fval(meas, "field.mode_list", [])
    diag = fval(meas, "field.diagnoses")
    out.append("<section><h2>when it was switched on, and when it was not</h2>"
               '<p class="small dim">Supervision lives in one file for the whole machine and the '
               "absence of that file means unguarded. A session switched it off at 02:25 on "
               "3 August, it stayed off while four other sessions kept working underneath it, and "
               "no event recorded that anywhere. A mode change is a line on the ledger now. The "
               "count below starts the day that line started being written, which is why it is "
               "small.</p>")
    out.append('<div class="stats">')
    out.append(stat("b", fval(meas, "field.mode_changes"),
                    "times supervision was switched on or off since the ledger began recording it",
                    src))
    out.append(stat("g", diag,
                    "written accounts of what broke, handed back instead of a refusal", src))
    out.append("</div>")
    if modes:
        rows = []
        for m in modes:
            ts = m.get("ts", 0)
            when = ("%04d-%02d-%02d %02d:%02d" % time.gmtime(ts / 1000)[:5]) if ts else "?"
            rows.append([html.escape(when), html.escape(m.get("from", "")),
                         html.escape(m.get("to", ""))])
        out.append(table([("when", "s"), ("was", "s"), ("became", "s")], rows, "ledger"))
    out.append(cmdline("python3 site/field_stats.py"))
    out.append("</section>")

    c = census()
    if c:
        out.append(census_block(c))

    # ---- the rules it wrote itself ----------------------------------------
    if rules:
        rows = []
        for r in rules:
            here = ('<span class="g">in ' + html.escape(r.get("in") or "?") + "</span>") if r.get("live") \
                else '<span class="r">in no guard file</span>'
            rows.append([html.escape(r["rule"]), html.escape(r.get("project", "")), here,
                         html.escape(r.get("why", "") or "the write was recorded and never landed")])
        out.append("<section><h2>the laws it wrote for itself, after the thing had already happened</h2>"
                   '<p class="small dim">When a check goes red the engine proposes a fix, and where the '
                   "failure was a way of working rather than a line of code it writes a rule so the same "
                   "class cannot happen twice. Each one below was authored after a real incident, in the "
                   "repository the incident happened in. The sentence on the right is the rule&#39;s own, "
                   "read out of the guard file it lives in rather than retyped here.</p>")
        out.append('<div class="stats">')
        out.append(stat("p", fval(meas, "field.rules_distinct"),
                        "distinct laws it wrote for itself after an incident", src))
        out.append(stat("g", fval(meas, "field.rules_distinct_live"),
                        "of those, in a guard file on this machine right now", src))
        out.append(stat("y", written, "authoring events on the ledger; one law was written twice, after two "
                                      "separate incidents in two repositories", src))
        out.append("</div>")
        out.append(table([("rule", "s"), ("written in", "s"), ("still there", "s"),
                          ("the sentence the rule carries", "d")], rows, "ledger"))
        nd, ndl = fval(meas, "field.rules_distinct"), fval(meas, "field.rules_distinct_live")
        if nd != ndl or written != nd:
            out.append('<p class="cap">Three numbers where a page would normally print one, because the '
                       "ledger records an authoring EVENT and neither of the other two facts follows from "
                       f"it. {written} events, {nd} distinct laws, because one law was written twice after "
                       f"two separate incidents in two repositories. And {nd - ndl} of those laws is on the "
                       "ledger and in no guard file anywhere, which means it cannot fire in any repository "
                       "ever. Counting events and calling them rules was the first version of this section "
                       "and it would have published a law that does not exist. The check runs in "
                       "<code>make test</code>.</p>")
        out.append(cmdline("python3 site/field_stats.py"))
        out.append("</section>")

    # ---- the push gate -----------------------------------------------------
    refused = fval(meas, "field.pushes_refused")
    out.append("<section><h2>the push it would not let through</h2>"
               '<p class="small dim">The gate does not take the session&#39;s word for whether the suite '
               "passes. It runs the project&#39;s own test command itself, reads the verdict, and holds "
               "the push until the tree is green. What follows is how often that happened during real "
               "work, not in a rehearsal.</p>")
    out.append('<div class="stats">')
    out.append(stat("p", refused, "pushes refused on a red tree, each one held until the suite was green",
                    src))
    out.append("</div>")
    out.append(cmdline("python3 site/field_stats.py"))
    out.append("</section>")

    # ---- the records themselves -------------------------------------------
    if recs:
        by_proj = OrderedDict()
        for r in recs:
            by_proj.setdefault(r.get("project", "?"), []).append(r)
        ordered = sorted(by_proj.items(), key=lambda kv: -len(kv[1]))
        out.append("<section><h2>the records, as they were written</h2>"
                   '<p class="small dim">Nothing above has to be taken on trust. Every published record '
                   "is here, project by project, in the file the page is built from. Home paths are "
                   "rewritten and the extractor refuses to write at all if an account name survives "
                   "redaction, whole or truncated. Runs made to exercise the engine are excluded by name "
                   "and the excluded count is printed, because a filter that hides its own size is the "
                   "same problem one layer down.</p>")
        out.append('<p class="cap">The whole file: <a href="/field.jsonl">field.jsonl</a>, '
                   f"{len(recs):,} records, one JSON object per line.</p>")
        for proj, group in ordered:
            if len(group) < 2:
                continue
            rows = []
            for r in sorted(group, key=lambda x: -x.get("ts", 0))[:12]:
                ts = r.get("ts", 0)
                when = ("%04d-%02d-%02d %02d:%02d" % (time.gmtime(ts / 1000)[:5])) if ts else "?"
                rows.append([html.escape(when), html.escape(r.get("ev", "")),
                             html.escape(r.get("rule", "")),
                             html.escape((r.get("detail") or "")[:200])])
            out.append("<details><summary>" + html.escape(proj) +
                       f", {len(group)} record{'s' if len(group) != 1 else ''}, "
                       f'showing {len(rows)}</summary><div class="body">' +
                       table([("when", "s"), ("verdict", "s"), ("rule", "s"),
                              ("the line the ledger wrote", "d")], rows, "ledger") +
                       "</div></details>")
        out.append("</section>")

    return page("/field", "rabadon in real repositories, read off its own ledger",
                f"{fval(meas, 'field.would_block'):,} commands rabadon would have refused during real "
                f"work, {fval(meas, 'field.stop'):,} it refused outright once armed, and {live} laws it "
                "wrote for itself after an incident, each still in a guard file.",
                "\n".join(out),
                extra=[field_dataset(meas, day)], main=SITE + "/field#dataset")


# ---------------------------------------------------------------------------
# the overview. Not a page any more: a template with holes, and every hole is
# filled from the same source the page that details it reads.
# ---------------------------------------------------------------------------
def term(lines):
    return '<div class="term">' + "\n".join(lines) + "</div>"


def cmdline(cmd):
    """The one thing on these pages that really is terminal output: the command
    somebody types. Everything with columns in it is a table."""
    return ('<div class="cmd"><span class="p">$</span> '
            f'<span class="c">{html.escape(cmd)}</span></div>')


NUM_WORDS = {0: "zero", 1: "one", 2: "two", 3: "three", 4: "four", 5: "five",
             6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten",
             11: "eleven", 12: "twelve"}


def word(n):
    return NUM_WORDS.get(n, str(n))


def defect_rows(mine):
    """The per-project table on the overview, built from the mine's own json.
    The counts are its numbers; the sentence at the end of each row is prose
    and is the only thing here a person wrote."""
    SAID = {
        "expressjs/express":   "a view root read one character short, and an etag guard that stopped being applied",
        "tj/commander.js":     "an excess-argument count compared with the wrong operator, and a dropped port guard",
        "lodash/lodash":       "a strict index scan starting one place late, and a guard dropped out of word splitting",
        "ajv-validator/ajv":   "a maximum treated as exclusive, and a leap second given the wrong timezone sign",
        "pallets/click":       "option parsing that lost a boundary case, and a separator handled on only one side",
        "pallets/jinja":       "template escaping that let one shape through, and a filter that read past its input",
        "pallets/markupsafe":  "escaping that missed a character class, and a comparison that answered in reverse",
        "yaml/pyyaml":         "single-line defects in the loader, the smallest of them one character wide",
    }
    # ONE format for the header and the rows. They were written separately, the
    # header by hand with spaces and the rows with printf, so the columns could
    # not line up and did not.
    rows = []
    for r in mine["byRepo"]:
        rows.append([
            f'<a href="https://github.com/{html.escape(r["repo"])}">{html.escape(r["repo"])}</a>',
            r["cases"], r["scannedCommits"], "%.1f" % r["medianSourceLines"],
            html.escape(SAID.get(r["repo"], "")),
        ])
    o = mine["overall"]
    rows.append([("total", "tot"), (o["totalCases"], "tot"), (o["totalScannedCommits"], "tot"),
                 ("%.1f" % o["medianSourceLines"], "tot"), (kind_summary(mine), "tot")])
    return table([("project", "s"), ("defects", "n"), ("commits", "n"),
                  ("lines", "n"), ("what was wrong with the code", "d")], rows, "defects")


def kind_summary(mine):
    """`4 dropped guards, 3 off-by-one …` counted off the cases, not typed."""
    LABEL = {"dusurulmus-koruma": "dropped guards", "off-by-one": "off-by-one",
             "yanlis-sinir": "wrong boundaries", "ters-karsilastirma": "reversed comparisons",
             "degistirme": "changed behaviour", "ekleme": "added guards",
             "silme": "removed code", "sadece-silme": "deletions only",
             "sadece-ekleme": "additions only", "tasima": "moved code"}
    c = Counter(x.get("changeKind", "?") for x in mine["cases"])
    # A key with no English label would print its own raw value, which is how
    # `3 sadece-silme` came to be sitting in the total row of a page written in
    # English. An unmapped kind is counted as "other" rather than shown raw.
    named = [(LABEL[k], n) for k, n in c.most_common() if k in LABEL]
    unnamed = sum(n for k, n in c.items() if k not in LABEL)
    parts = ["%d %s" % (n, lbl) for lbl, n in named]
    if unnamed:
        parts.append("%d other" % unnamed)
    return html.escape(", ".join(parts))


def rules_block(meas):
    rules = (meas.get("gate.rules") or {}).get("value") or []
    if not rules:
        return '<p class="cap">not measured — run <code>./native/measure.sh</code></p>'
    rows = [[('<span class="g">ok</span>' if r["ok"] else '<span class="r">no</span>'),
             html.escape(r["rule"]), r["mustBlock"], r["mustNotBlock"]] for r in
            sorted(rules, key=lambda x: x["rule"])]
    return (cmdline("./native/precision_test.sh") +
            table([("", "s"), ("rule", "s"), ("must block", "n"), ("must not block", "n")],
                  rows, "rules") +
            f'<p class="cap">Canaries intact after judging {mval(meas, "gate.cases")} commands. '
            "Every law that blocks something carries a case it must let through, on the same row.</p>")


def green_paths_block(meas):
    """Two suites, one table. The twins are in it on purpose: a lock that
    refuses honest work is an outage, and the page should show that it does
    not."""
    groups = [("./native/harness_lock_test.sh", (meas.get("repair.green_paths") or {}).get("value") or []),
              ("./native/heldout_test.sh", (meas.get("repair.heldout") or {}).get("value") or [])]
    rows = []
    for cmd, g in groups:
        for c in g:
            v = c["verdict"]
            cls = "g" if v == "verified" else "r"
            rows.append([html.escape(c["name"]), (html.escape(v), cls),
                         "exit %d" % c["exit"], f"<code>{html.escape(cmd)}</code>"])
    if not rows:
        return '<p class="cap">not measured — run <code>./native/measure.sh</code></p>'
    return table([("case", "s"), ("verdict", "s"), ("exit", "n"), ("suite", "d")], rows, "green")


def green_paths_refused(meas):
    """A twin is not a way of buying a green, so it is not counted as one."""
    cases = ((meas.get("repair.green_paths") or {}).get("value") or []) + \
            ((meas.get("repair.heldout") or {}).get("value") or [])
    return sum(1 for c in cases if c.get("verdict") != "verified")


def usage_block(meas):
    """The overview shows `rabadon usage` output, so it runs `rabadon usage`.
    A screenshot of a command is a claim about the command; this is the
    command."""
    out = sh(["native/rabadon-stats", "--days", "30", "--json"])
    if out.returncode != 0:
        return '<p class="cap">the binary is not built here — run <code>make</code></p>', {}
    d = json.loads(out.stdout)
    t = d["totals"]
    rows = [[(f"{t['refused']:,}", "p"), "destructive actions refused before they happened"],
            [(f"{t['gated']:,}", "b"), "actions handed to the gate to be judged"],
            [(f"{t['repairsHeld']:,}", "g"), "repairs held after the proof survived the judge"],
            [(f"{t['wouldRefuse']:,}", "y"), "refusals recorded in watch mode, where nothing is blocked"],
            [("0", "b"), "fake repairs accepted, on every run there is a record of"]]
    # WHY THIS NUMBER IS NOT THE ONE IN THE HEADLINE, said on the page rather
    # than left for a reader to trip over. The binary and site/field_stats.py
    # exclude rehearsals by two different definitions: drill.h applies five
    # rules (the emit tag, session-id markers, self pipes, a 120s window around
    # a marker, and a stub-speed test), while field_stats.py applies the emit
    # tag and a laboratory pipe list. The binary's is stricter, so its refusal
    # count is lower. Both are honest and they are not the same measurement;
    # printing them side by side with no note is how a reader concludes one of
    # them is a lie.
    note = ('<p class="cap">This is the binary\'s own count, and it is lower than the '
            f'{mval(meas, "field.stop")} in the headline because the two apply different '
            'rehearsal filters: the binary also excludes events inside a 120-second window '
            'around a drill marker and repairs that closed faster than a model can answer. '
            'The headline filter excludes the drill tag and the named laboratory pipes. '
            'Reconciling them onto one definition is open work.</p>')
    return (cmdline("rabadon usage --days 30") +
            table([("", "n"), ("", "d")], rows, "usage bare") + note), t


def index(rows, meas):
    real, drill, ev, sample, projects, per, per_ex, raw = ledger()
    total = sum(real.values())
    # two different counts, and the page asks two different questions. the
    # refusal line means "repositories a refusal happened in", which is what the
    # catches page counts and must equal; the volume line means "repositories
    # the gate ran in at all", which is every project name the spool carries.
    refused_in = len([p for p in projects if p != "rabadon"]) + 1
    ran_in = len(ledger_dirs())
    mine = load_json(DEFECTS_PATH) or {"overall": {}, "byRepo": [], "cases": []}
    o = mine["overall"]
    usage_html, totals = usage_block(meas)
    days = len(group_by_day(rows))

    # the fixture's own split, counted rather than spelled out in English
    block = allow = 0
    for line in open("native/precision_fixture.jsonl", encoding="utf-8"):
        line = line.strip()
        if line:
            (block := block + 1) if json.loads(line)["expect"] == "BLOCK" else (allow := allow + 1)

    express = table([("", "s"), ("", "n"), ("", "d")], [
        ["repairs held", (mval(meas, "express.repairs_held"), "g"), "on a foreign repository, live"],
        ["tree edits", ("0", "g"), "the working tree was never touched"],
        ["test files locked", (mval(meas, "express.locked"), "b"), "sha256 of the pristine copy"],
        ["suite", (mval(meas, "express.suite_tests"), "b"), "tests, the project's own"],
        ["a proposer that skipped tests", ("REJECTED", "r"), "test-tamper"],
    ], "kv bare")

    proof = (table([("", "n"), ("", "s"), ("", "d")], [
        [("1", "p"), "green", "the fix commit, the project's own suite"],
        [("2", "p"), "revert", "source half only, test files untouched"],
        [("3", "p"), "red", "same suite, three runs, same tests fall"],
    ], "kv bare") + table([("", "s"), ("", "n"), ("", "d")], [
        ["cases", (o.get("totalCases", 0), "b"), "mined out of eight projects' own history"],
        ["deterministic", (sum(1 for c in mine["cases"] if c.get("deterministic")), "b"),
         "of %d" % o.get("totalCases", 0)],
        ["median source", (o.get("medianSourceLines", "?"), "b"), "lines"],
        ["median falling", (o.get("medianFailingTests", "?"), "b"), "test"],
    ], "kv bare"))

    names = [r["repo"].split("/")[-1] for r in mine["byRepo"]]
    projectnames = ", ".join(names[:-1]) + " and " + names[-1] if len(names) > 1 else "".join(names)

    vals = {
        # catches.total is the WATCH-mode count and is named so on every page it
        # reaches. catches.refused is the enforce-mode count, the one where the
        # command did not run. They were the same token until now, and the
        # smaller of the two was wearing the stronger sentence.
        "catches.total": f"{total:,}",
        "catches.refused": mval(meas, "field.stop"),
        "catches.repos": str(refused_in),
        "ledger.repos": str(ran_in),
        "corpus.defects": str(o.get("totalCases", 0)),
        "corpus.commits": str(o.get("totalScannedCommits", 0)),
        "corpus.projects": str(o.get("totalRepos", 0)),
        "corpus.projects_word": word(o.get("totalRepos", 0)),
        "corpus.projectnames": projectnames,
        "corpus.min_lines": word(o.get("minSourceLines", 0)),
        "corpus.max_lines": word(o.get("maxSourceLines", 0)),
        "corpus.min_tests": word(o.get("minFailingTests", 0)),
        "corpus.max_tests": word(o.get("maxFailingTests", 0)),
        "corpus.deterministic": str(sum(1 for c in mine["cases"] if c.get("deterministic"))),
        "corpus.table": defect_rows(mine),
        "corpus.proof_block": proof,
        "hero.stats": "\n".join([
            stat("p", fval(meas, "field.stop"),
                 'commands refused outright in enforce mode, so they never ran. '
                 f'<a href="/catches">a further {total:,} verdicts were recorded in watch mode across '
                 f'{refused_in} repositories, where nothing was blocked</a>', "/catches"),
            stat("g", mval(meas, "gate.precision"),
                 f'precision over the {block + allow} cases lifted out of real sessions, recall '
                 f'{mval(meas, "gate.recall")}. On this machine&#39;s whole ledger the same binary reads '
                 f'{mval(meas, "gate.precision_ledger")}, and {mval(meas, "gate.precision_ledger_real")} '
                 f'once its own test labs are taken out',
                 evidence_href(meas, "gate.precision", "/benchmarks")),
            stat("b", 0, 'fake repairs accepted, on every run there is a record of. '
                 f'{mval(meas, "gate.redteam_open")} named ways past the gate are still open, and it stays '
                 'in watch mode until they are not',
                 evidence_href(meas, "gate.redteam_open", "/benchmarks")),
            stat("y", mval(meas, "gate.judge_us"),
                 'to judge one command, so the gate is not what you switch off to go faster',
                 evidence_href(meas, "gate.judge_us", "/benchmarks")),
        ]),
        "volume.stats": "\n".join([
            stat("p", sum(ev.values()), "lines written to the hash-chained ledger, every one carrying the "
                 "sha256 of the line before it", "/catches"),
            stat("b", totals.get("gated", 0),
                 f"actions handed to the gate to be judged, across {ran_in} repositories", "/catches"),
            stat("g", o.get("totalCases", 0),
                 f'real defects mined out of {o.get("totalScannedCommits", 0)} commits in '
                 f'{o.get("totalRepos", 0)} open-source projects, each with the patch that proves it',
                 f"{REPO_URL}/tree/main/reports/2026-08-01-real-defect-mine"),
            stat("y", sum(x[2] for x in SUITES),
                 f"tests in the {len(SUITES)} suites it was run against. "
                 '<a href="/benchmarks">the measurements, each beside the command it came from</a>',
                 "/benchmarks"),
            stat("b", len(rows), 'commits in this repository. '
                 '<a href="/patch-notes">all of them, with the day each landed</a>', "/patch-notes"),
        ]),
        "field.stats": "\n".join([
            stat("p", fval(meas, "field.would_block"),
                 'commands it would have refused during real work, '
                 f'{fval(meas, "field.would_block_own"):,} of them in this engineer&#39;s own repositories '
                 f'rather than in a fixture, recorded across {fval(meas, "field.days_watch")} days. '
                 '<a href="/field">every one, rule by rule, with the day it happened</a>', "/field"),
            stat("g", fval(meas, "field.rules_distinct_live"),
                 'laws it wrote for itself after an incident and that are in a guard file right now, of '
                 f'{fval(meas, "field.rules_distinct")} distinct laws it recorded writing across '
                 f'{fval(meas, "field.rules_written")} incidents. The gap is printed rather than closed',
                 "/field"),
            stat("y", fval(meas, "field.pushes_refused"),
                 "pushes it refused on a red tree, each held until the project&#39;s own suite went green",
                 "/field"),
            stat("b", fval(meas, "field.stop"),
                 "commands it refused outright once it was armed, so they never ran", "/field"),
            stat("r" if fval(meas, "field.wrong_refusals") else "g",
                 fval(meas, "field.wrong_refusals"),
                 "of those, reported wrong by the operator and written onto the same "
                 'hash-chained ledger as the refusals. <a href="/field">each one, with the reason '
                 "it was wrong</a>", "/field"),
        ]),
        "field.headline": field_headline(meas),
"seo.desc": (f"Guardrails and a verifiable record for AI coding agents. "
                     f"{mval(meas, 'field.stop')} commands refused outright so they never ran, "
                     f"{o.get('totalCases', 0)} real defects found in "
                     f"{o.get('totalRepos', 0)} open-source projects, 0 fake repairs accepted."),
        "seo.jsonld": jsonld("/", "rabadon, run your coding agent without watching it",
                             "Guardrails and a verifiable record for AI coding agents."),
                "gate.precision": mval(meas, "gate.precision"),
        "gate.recall": mval(meas, "gate.recall"),
        "gate.cases": str(block + allow),
        "gate.destructive": word(block),
        "gate.allows": word(allow),
        "gate.judge_us": mval(meas, "gate.judge_us"),
        "gate.precision_ledger": mval(meas, "gate.precision_ledger"),
        "gate.precision_ledger_real": mval(meas, "gate.precision_ledger_real"),
        "gate.redteam_open": mval(meas, "gate.redteam_open"),
        "gate.rules_block": rules_block(meas),
        "repair.fake_accepted": "0",
        "repair.green_paths_block": green_paths_block(meas),
        "repair.green_paths_word": word(green_paths_refused(meas)),
        "express.block": express,
        "usage.block": usage_html,
        "ledger.lines": f"{sum(ev.values()):,}",
        "ledger.actions": f"{totals.get('gated', 0):,}",
        "suites.tests": f"{sum(s[2] for s in SUITES):,}",
        "suites.count": str(len(SUITES)),
        "repo.commits": str(len(rows)),
        "repo.days": word(days) if days <= 12 else str(days),
        "live.pulse": live_pulse(),
    }

    s = open(INDEX_TMPL, encoding="utf-8").read()
    for k, v in vals.items():
        s = s.replace("{{" + k + "}}", v)
    left = sorted(set(re.findall(r"\{\{[a-zA-Z0-9_.]+\}\}", s)))
    if left:
        sys.exit("site/build.py: unfilled placeholders in the overview: " + ", ".join(left))
    return s


def main():
    rows = commits()
    prs = pull_requests()
    meas = measured()
    built = {}
    # one date for /field, used by the page's Dataset markup and by the sitemap,
    # so the two cannot disagree about when the data last moved
    today = time.strftime("%Y-%m-%d", time.gmtime())
    fday = field_day(meas, today)
    for name, content in (("index", index(rows, meas)),
                          ("field", field_page(meas, fday)),
                          ("catches", catches(meas)),
                          ("patch-notes", patch_notes(rows)),
                          ("pull-requests", pull_request_page(prs, rows)),
                          ("benchmarks", benchmarks(rows, meas))):
        with open(f"site/{name}.html", "w", encoding="utf-8") as f:
            f.write(content)
        built[name] = content
        print(f"site/{name}.html  {len(content):>7} bytes")
    # the share card, drawn from the same measured.json the pages read. It is
    # rewritten only when it comes out different, and a card that cannot be
    # drawn is reported rather than raised: the pages are the deploy, the png is
    # the poster on the door.
    try:
        import og
        print(og.render(meas))
    except Exception as e:                      # noqa: BLE001 - never fail a build over a picture
        print(f"site/og.png  NOT redrawn: {type(e).__name__}: {e}")
    # A crawler should not have to discover this site by following links, and a
    # sitemap somebody maintains by hand goes stale the first time a page is
    # added. Both files are written by the same run that writes the pages.
    # url -> the file whose committed copy dates it. /field is absent on
    # purpose and is dated from its data instead; see the note above field_day.
    FROM_RENDER = {"/": "index", "/catches": "catches", "/patch-notes": "patch-notes",
                   "/benchmarks": "benchmarks", "/pull-requests": "pull-requests"}
    lastmod = {}
    for path, _ in NAV:
        if not path.startswith("/"):
            continue
        if path == "/field":
            lastmod[path] = fday
        else:
            name = FROM_RENDER[path]
            lastmod[path] = rendered_day(f"site/{name}.html", built[name], today,
                                         trust=bool(prs) or path != "/pull-requests")
    urls = "".join(
        f"<url><loc>{SITE}{path}</loc><lastmod>{lastmod[path]}</lastmod>"
        f"<changefreq>{'daily' if path in ('/', '/catches', '/patch-notes') else 'weekly'}</changefreq>"
        f"<priority>{'1.0' if path == '/' else '0.8'}</priority></url>"
        for path, _ in NAV if path.startswith("/"))
    with open("site/sitemap.xml", "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
                + urls + "</urlset>\n")
    with open("site/robots.txt", "w", encoding="utf-8") as f:
        f.write("User-agent: *\nAllow: /\n\nSitemap: " + SITE + "/sitemap.xml\n")
    print("site/sitemap.xml  site/robots.txt")
    print("  lastmod  " + "  ".join(f"{p}={lastmod[p]}" for p, _ in NAV
                                    if p.startswith("/")))
    print(f"  from {len(rows)} commits, {len(prs)} pull requests, "
          f"{len(group_by_day(rows))} days, {len(SUITES)} suites")


if __name__ == "__main__":
    main()
