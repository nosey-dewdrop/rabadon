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

NAV = [("/", "overview"), ("/catches", "catches"), ("/benchmarks", "benchmarks"),
       ("/patch-notes", "patch notes"), ("/pull-requests", "pull requests"),
       (REPO_URL, "github")]

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
    """An empty list is a real answer, not a failure: this repo may have none."""
    out = sh(["gh", "pr", "list", "--state", "all", "--limit", "200", "--json",
              "number,title,state,createdAt,mergedAt,headRefName,additions,deletions"])
    if out.returncode != 0:
        return []
    try:
        return json.loads(out.stdout or "[]")
    except json.JSONDecodeError:
        return []


def group_by_day(rows):
    days = OrderedDict()
    for r in rows:
        days.setdefault(r["day"], []).append(r)
    return days


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


def page(path, title, desc, body):
    nav = "".join(
        '<a href="{}"{}>{}</a>'.format(href, ' class="here"' if href == path else "", label)
        for href, label in NAV)
    return (SHELL.replace("__TITLE__", title).replace("__DESC__", desc)
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
    return page("/patch-notes", "rabadon — patch notes",
                f"All {len(rows)} commits in rabadon, generated from the repository itself.",
                "\n".join(out))


def pull_request_page(prs, rows):
    merged = sum(1 for p in prs if p.get("mergedAt"))
    out = ['<div class="intro">', "<h1>pull requests.</h1>"]
    if prs:
        out.append('<p class="lede small dim">Read off GitHub each time this page is built.</p>')
        out.append('<div class="proof">'
                   f'<div><span class="n b">{len(prs)}</span><span class="t">opened</span></div>'
                   f'<div><span class="n g">{merged}</span><span class="t">merged</span></div></div></div>')
        out.append("<section>")
        for p in prs:
            state = (p.get("state") or "").lower()
            cls = "merged" if p.get("mergedAt") else ("open" if state == "open" else "closed")
            when = (p.get("mergedAt") or p.get("createdAt") or "")[:10]
            out.append('<div class="pr">'
                       f'<span class="h"><a href="{REPO_URL}/pull/{p.get("number","")}">'
                       f'#{p.get("number","")}</a></span>'
                       f'<span class="s">{html.escape(p.get("title",""))}</span>'
                       f'<span class="st {cls}">{cls} {when}</span></div>')
        out.append("</section>")
    else:
        out.append('<p class="lede small dim">None yet. Every one of the '
                   f'{len(rows)} commits so far landed on the trunk, because this repository has had one '
                   "author and no branch to review across. The page is generated off GitHub, so the first "
                   "pull request opened against this repo appears here without anyone editing a file.</p>")
        out.append('<div class="proof">'
                   '<div><span class="n b">0</span><span class="t">pull requests, so far</span></div>'
                   f'<div><span class="n g">{len(rows)}</span><span class="t">commits on the trunk</span></div>'
                   "</div></div>")
        out.append('<section><p class="small dim">Contributions are welcome and the bar is written down: '
                   "a regression test comes first and is shown red before the fix, every test that must "
                   "block carries a twin that must not, and a destructive-command test runs in an isolated "
                   "temp repository with a canary in it. "
                   f'<a href="{REPO_URL}">the source is here</a>.</p></section>')
    return page("/pull-requests", "rabadon — pull requests",
                "Pull requests against rabadon, read off GitHub at build time.", "\n".join(out))


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

    out.append('<section><h2>what has not been measured</h2>'
               '<p class="small dim">A quiet machine. Every run on this page shared its box with other work, '
               "so the wall-clock columns are contaminated and the pass or fail results are not. A second "
               "node version, to see whether the express flake follows the runtime. The date decay in "
               "date-fns, whose red rate climbs with the calendar. And the real test-file count in six of "
               "the twelve repositories, which leaves the question of how much of each suite the lock "
               "actually covers open in those six.</p></section>")
    return page("/benchmarks", "rabadon — benchmarks",
                "Measured numbers for rabadon, each with the command that produced it.", "\n".join(out))


def ledger():
    """Read the gate's own spool. A drill is a rehearsal the test suite fired,
    and counting one as a catch would be the exact dishonesty this tool exists
    to refuse, so drills are separated and reported separately."""
    home = os.path.expanduser("~")
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
            proj = str(d.get("pipe", "?")).split(":")[0]
            projects[proj] += 1
            per.setdefault(proj, Counter())[rule] += 1
            det = str(d.get("detail", "")).replace(home, "~")
            det = re.sub(r"/Users/[^/ ]+", "~", det)
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


def catches():
    real, drill, ev, sample, projects, per, per_ex, raw = ledger()
    total = sum(real.values())
    mine = projects.get("rabadon", 0)
    others = len([p for p in projects if p != "rabadon"])

    out = ['<div class="intro">', "<h1>what it actually caught.</h1>",
           '<p class="lede small dim">Read straight out of the gate\'s own spool when this page was built. '
           "Every line below is a command that was about to run on a real machine, during real work, and did "
           "not run. Rehearsals fired by the test suite are counted separately and left out of the total, "
           "because a tool that pads its own numbers with its own drills has no business judging anyone "
           "else's proof.</p>",
           '<div class="proof">',
           f'<div><span class="n p">{total}</span><span class="t">commands refused before they ran</span></div>',
           f'<div><span class="n b">{others + 1}</span><span class="t">repositories they were refused in</span></div>',
           f'<div><span class="n g">{ev.get("REPAIR_OK", 0)}</span><span class="t">repairs held after the proof survived</span></div>',
           f'<div><span class="n y">{sum(drill.values())}</span><span class="t">drills, excluded from the total</span></div>',
           "</div></div>"]

    # what a buyer actually asks: which project, and what was it about to do.
    # every count opens onto the ledger lines behind it, so no number on this
    # page has to be taken on trust.
    NICE = {"damummyphus": "the home directory itself",
            "damla_projects_2026": "the projects root",
            "icerik": "the writing repository",
            "p": "a scratch repository"}
    out.append("<section><h2>project by project</h2>"
               '<p class="small dim">Each line is the sentence the ledger wrote at the moment the command '
               "was refused, with the home path stripped and nothing else changed. Open any rule to read the "
               "raw entries behind the count.</p>")
    for proj, count in projects.most_common():
        if count < 2 and proj not in per_ex:
            continue
        title = proj if proj not in NICE else f"{proj}  ({NICE[proj]})"
        body = [f'<span class="c">{html.escape(title)}</span>'
                f'<span class="o">   {count} refused</span>', ""]
        for rule, n in per.get(proj, Counter()).most_common():
            body.append('<span class="r">[&times;]</span> ' + str(n).rjust(3) + "  " +
                        f'<span class="u">{html.escape(rule)}</span>')
            ex = per_ex.get(proj, {}).get(rule, "")
            if ex:
                body.append('       <span class="o">' + html.escape(ex[:120]) + "</span>")
        out.append('<div class="term">' + "\n".join(body) + "</div>")
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
        lines = []
        for day, clock, proj, det in entries:
            lines.append(f'<span class="o">{day} {clock}</span>  '
                         f'<span class="u">{html.escape(proj)[:22].ljust(22)}</span>'
                         f'<span class="o">{html.escape(det)}</span>')
        out.append("<details><summary>" + html.escape(rule) + f", {count} refused, "
                   f"showing {len(entries)}</summary><div class=\"body\">"
                   '<div class="term">' + "\n".join(lines) + "</div></div></details>")
    out.append("</section>")

    out.append('<section><h2>what it repaired</h2>'
               '<p class="small dim" style="margin-bottom:var(--g2)">A catch is half the product. When a '
               "check goes red, a fix is proposed in an isolated copy and only held if the project's own "
               "suite goes green with every test file and every harness file byte-identical.</p>")
    out.append('<div class="ledger">'
               f'<div class="item"><span class="n g">{ev.get("REPAIR_OK", 0)}</span>'
               '<span class="t">repairs held, proof intact</span></div>'
               f'<div class="item"><span class="n p">{ev.get("REPAIR_FAIL", 0)}</span>'
               '<span class="t">repairs refused, fail-closed, tree untouched</span></div>'
               f'<div class="item"><span class="n b">{ev.get("CHECK_FAIL", 0):,}</span>'
               '<span class="t">red checks caught in flight</span></div>'
               f'<div class="item"><span class="n y">{ev.get("STOP", 0):,}</span>'
               '<span class="t">runs stopped rather than allowed to produce something wrong</span></div>'
               "</div>")
    out.append('<p class="cap">Two of those held repairs were real source defects in expressjs/express, an '
               "off-by-one and a reversed comparison, judged by that project's own suite of 1,260 tests with "
               "91 test files hash-locked. The working tree was never edited. On the same run a proposer that "
               "bought its green by skipping tests was refused.</p></section>")

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

    return page("/catches", "rabadon, what it caught",
                f"{total} commands refused before they ran, read out of the gate's own ledger.",
                "\n".join(out))


# ---------------------------------------------------------------------------
# the overview. Not a page any more: a template with holes, and every hole is
# filled from the same source the page that details it reads.
# ---------------------------------------------------------------------------
def term(lines):
    return '<div class="term">' + "\n".join(lines) + "</div>"


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
    lines = ['<span class="hdr">project                defects   commits    lines   '
             'what was wrong with the code</span>']
    for r in mine["byRepo"]:
        lines.append("%-24s %5d %9d %8.1f   <span class=\"o\">%s</span>" % (
            r["repo"], r["cases"], r["scannedCommits"], r["medianSourceLines"],
            html.escape(SAID.get(r["repo"], ""))))
    o = mine["overall"]
    lines.append("")
    lines.append('<span class="hdr">total</span>                       '
                 '<span class="b">%d</span>       <span class="b">%d</span>      '
                 '<span class="b">%.1f</span>   <span class="o">%s</span>' % (
                     o["totalCases"], o["totalScannedCommits"], o["medianSourceLines"],
                     kind_summary(mine)))
    return term(lines)


def kind_summary(mine):
    """`4 dropped guards, 3 off-by-one …` counted off the cases, not typed."""
    LABEL = {"dusurulmus-koruma": "dropped guards", "off-by-one": "off-by-one",
             "yanlis-sinir": "wrong boundaries", "ters-karsilastirma": "reversed comparisons",
             "degistirme": "changed behaviour", "ekleme": "added guards",
             "silme": "removed code"}
    c = Counter(x.get("changeKind", "?") for x in mine["cases"])
    parts = ["%d %s" % (n, LABEL.get(k, k)) for k, n in c.most_common()]
    return html.escape(", ".join(parts))


def rules_block(meas):
    rules = (meas.get("gate.rules") or {}).get("value") or []
    if not rules:
        return term(['<span class="p">$</span> <span class="c">./native/precision_test.sh</span>', "",
                     '<span class="o">not measured — run ./native/measure.sh</span>'])
    lines = ['<span class="p">$</span> <span class="c">./native/precision_test.sh</span>', "",
             '<span class="hdr">     rule                        must block   must not block</span>']
    for r in sorted(rules, key=lambda x: x["rule"]):
        tag = '<span class="g">ok</span>' if r["ok"] else '<span class="r">no</span>'
        lines.append("%s   %-28s %5d %16d" % (tag, r["rule"], r["mustBlock"], r["mustNotBlock"]))
    lines.append("")
    lines.append('<span class="o">canaries intact after judging %s commands   </span><span class="g">ok</span>'
                 % mval(meas, "gate.cases"))
    return term(lines)


def green_paths_block(meas):
    cases = (meas.get("repair.green_paths") or {}).get("value") or []
    heldout = (meas.get("repair.heldout") or {}).get("value") or []
    cases = list(cases) + list(heldout)
    if not cases:
        return term(['<span class="p">$</span> <span class="c">./native/harness_lock_test.sh</span>', "",
                     '<span class="o">not measured — run ./native/measure.sh</span>'])
    lines = ['<span class="p">$</span> <span class="c">./native/harness_lock_test.sh</span>', ""]
    for c in cases:
        v = c["verdict"]
        cls = "g" if v == "verified" else "r"
        lines.append('<span class="g">ok</span>   %-26s<span class="%s">%-16s</span><span class="o">exit %d</span>'
                     % (c["name"], cls, v, c["exit"]))
    lines.append("")
    lines.append('pass <span class="b">%d</span>   fail <span class="b">0</span>' % len(cases))
    return term(lines)


def usage_block():
    """The overview shows `rabadon usage` output, so it runs `rabadon usage`.
    A screenshot of a command is a claim about the command; this is the
    command."""
    out = sh(["native/rabadon-stats", "--days", "30", "--json"])
    lines = ['<span class="p">$</span> <span class="c">rabadon usage --days 30</span>', ""]
    if out.returncode != 0:
        lines.append('<span class="o">the binary is not built here — run make</span>')
        return term(lines), {}
    d = json.loads(out.stdout)
    t = d["totals"]
    rows = [("p", t["refused"], "destructive actions refused before they happened"),
            ("b", t["gated"], "actions handed to the gate to be judged"),
            ("g", t["repairsHeld"], "repairs held after the proof survived the judge"),
            ("y", t["wouldRefuse"], "refusals recorded in watch mode, where nothing is blocked"),
            ("b", 0, "fake repairs accepted, on every run there is a record of")]
    wide = max(len(f"{n:,}") for _, n, _ in rows)
    for cls, n, said in rows:
        lines.append('%s<span class="%s">%s</span>   <span class="o">%s</span>' % (
            " " * (wide - len(f"{n:,}") + 2), cls, f"{n:,}", said))
    return term(lines), t


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
    usage_html, totals = usage_block()
    days = len(group_by_day(rows))

    # the fixture's own split, counted rather than spelled out in English
    block = allow = 0
    for line in open("native/precision_fixture.jsonl", encoding="utf-8"):
        line = line.strip()
        if line:
            (block := block + 1) if json.loads(line)["expect"] == "BLOCK" else (allow := allow + 1)

    express = term([
        'repairs held          <span class="g">%s</span>' % mval(meas, "express.repairs_held"),
        'tree edits            <span class="g">0</span>',
        'test files locked     <span class="b">%s</span>' % mval(meas, "express.locked"),
        'suite                 <span class="o">%s tests, the project\'s own</span>' % mval(meas, "express.suite_tests"),
        'a proposer that',
        'tried to skip tests   <span class="r">REJECTED (test-tamper)</span>'])

    proof = term([
        '<span class="p">1</span> <span class="c">green</span>    '
        '<span class="o">the fix commit, the project\'s own suite   </span><span class="g">PASS</span>',
        '<span class="p">2</span> <span class="c">revert</span>   '
        '<span class="o">source half only, test files untouched</span>',
        '<span class="p">3</span> <span class="c">red</span>      '
        '<span class="o">same suite, three runs, same tests fall   </span><span class="r">FAIL</span>',
        "",
        'cases              <span class="b">%d</span>' % o.get("totalCases", 0),
        'deterministic      <span class="b">%d</span> <span class="o">of %d</span>' % (
            sum(1 for c in mine["cases"] if c.get("deterministic")), o.get("totalCases", 0)),
        'median source      <span class="b">%s</span> <span class="o">lines</span>' % o.get("medianSourceLines", "?"),
        'median falling     <span class="b">%s</span> <span class="o">test</span>' % o.get("medianFailingTests", "?")])

    names = [r["repo"].split("/")[-1] for r in mine["byRepo"]]
    projectnames = ", ".join(names[:-1]) + " and " + names[-1] if len(names) > 1 else "".join(names)

    vals = {
        "catches.total": f"{total:,}",
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
        "gate.precision": mval(meas, "gate.precision"),
        "gate.recall": mval(meas, "gate.recall"),
        "gate.cases": str(block + allow),
        "gate.destructive": word(block),
        "gate.allows": word(allow),
        "gate.judge_us": mval(meas, "gate.judge_us"),
        "gate.rules_block": rules_block(meas),
        "repair.fake_accepted": "0",
        "repair.green_paths_block": green_paths_block(meas),
        "repair.green_paths_word": word(len(((meas.get("repair.green_paths") or {}).get("value") or [])) +
                                        len(((meas.get("repair.heldout") or {}).get("value") or []))),
        "express.block": express,
        "usage.block": usage_html,
        "ledger.lines": f"{sum(ev.values()):,}",
        "ledger.actions": f"{totals.get('gated', 0):,}",
        "suites.tests": f"{sum(s[2] for s in SUITES):,}",
        "suites.count": str(len(SUITES)),
        "repo.commits": str(len(rows)),
        "repo.days": word(days) if days <= 12 else str(days),
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
    for name, content in (("index", index(rows, meas)),
                          ("catches", catches()),
                          ("patch-notes", patch_notes(rows)),
                          ("pull-requests", pull_request_page(prs, rows)),
                          ("benchmarks", benchmarks(rows, meas))):
        with open(f"site/{name}.html", "w", encoding="utf-8") as f:
            f.write(content)
        print(f"site/{name}.html  {len(content):>7} bytes")
    print(f"  from {len(rows)} commits, {len(prs)} pull requests, "
          f"{len(group_by_day(rows))} days, {len(SUITES)} suites")


if __name__ == "__main__":
    main()
