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
import sys
from collections import Counter, OrderedDict

REPO_URL = "https://github.com/nosey-dewdrop/rabadon"
SEP = "\x1f"  # unit separator: safe inside a commit subject, unlike | or tab

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

GATE = [
    ("judge one command", "42.0&micro;s", "54.0&micro;s before the command was parsed once instead of twice",
     "native/gate_bench.sh"),
    ("gate precision", "100.0%", "55.0% before one resolver answered the path question for both layers",
     "native/precision_test.sh"),
    ("gate recall", "100.0%", "unchanged, and the floor the precision work was not allowed to move",
     "native/precision_test.sh"),
    ("cases in the fixture", "34", "every one lifted out of a real session, none written for the test",
     "native/precision_fixture.jsonl"),
    ("ways of buying a green, refused", "6 of 6", "3 of 6 before the harness itself was locked",
     "native/harness_lock_test.sh"),
]


def sh(args):
    return subprocess.run(args, capture_output=True, text=True, check=False)


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


def benchmarks(rows):
    total_tests = sum(s[2] for s in SUITES)
    flaky = sum(1 for s in SUITES if not s[4].startswith("0/"))
    out = ['<div class="intro">', "<h1>measured, with the command that measured it.</h1>",
           '<p class="lede small dim">A number with no run behind it is a slogan. Every row here was '
           "produced on one machine by the command named beside it, and the ones that could not be measured "
           "cleanly say so rather than being rounded into shape.</p>",
           '<div class="proof">',
           f'<div><span class="n g">100.0%</span><span class="t">gate precision, recall 100.0%</span></div>',
           f'<div><span class="n b">42.0&micro;s</span><span class="t">to judge one command</span></div>',
           f'<div><span class="n y">{len(SUITES)}</span><span class="t">real suites it was run against</span></div>',
           f'<div><span class="n p">{total_tests:,}</span><span class="t">tests in those suites</span></div>',
           "</div></div>",
           "<section><h2>the gate</h2>",
           '<div class="bench"><div class="head"><span>what</span><span style="text-align:right">now</span>'
           "<span>before, and what moved it</span><span>where it is measured</span></div>"]
    for what, now, before, where in GATE:
        out.append(f'<div class="row"><span class="s">{what}</span><span class="n">{now}</span>'
                   f'<span class="d">{before}</span><span class="w">{where}</span></div>')
    out.append("</div></section>")

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
    for f in sorted(glob.glob(os.path.join(SPOOL, "*.jsonl"))):
        for line in open(f, encoding="utf-8", errors="replace"):
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            ev[d.get("ev", "?")] += 1
            if d.get("ev") != "WOULD_BLOCK":
                continue
            rule = str(d.get("rule", "?"))
            if d.get("drill"):
                drill[rule] += 1
                continue
            real[rule] += 1
            projects[str(d.get("pipe", "?")).split(":")[0]] += 1
            if rule not in sample:
                det = str(d.get("detail", "")).replace(home, "~")
                det = re.sub(r"/Users/[^/ ]+", "~", det)
                det = re.sub(r"^command matched deny rule: ", "", det)
                sample[rule] = det.replace("\n", " ")[:150]
    return real, drill, ev, sample, projects


def catches():
    real, drill, ev, sample, projects = ledger()
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

    out.append("<section><h2>by rule</h2>")
    out.append('<div class="tbl catches"><div class="head"><span>rule</span>'
               '<span>times</span><span>what it stopped</span></div>')
    for rule, count in real.most_common():
        out.append(f'<div class="row"><span class="s">{html.escape(rule)}</span>'
                   f'<span class="n">{count}</span>'
                   f'<span class="d">{html.escape(RULE_TEXT.get(rule, "a command the compiled-in laws refuse"))}</span></div>')
    out.append("</div>")
    out.append(f'<p class="cap">{mine} of them fired inside this repository, which is the one being built all '
               f"day. The rest fired in {others} other repositories on the same machine, and those are not "
               "named here because they are not released yet.</p></section>")

    out.append('<section><h2>a refusal, as it was written down</h2>'
               '<p class="small dim">The ledger keeps the reason, not just the verdict, because a refusal '
               "nobody can read is a refusal that gets switched off. These are real entries with the home "
               "path stripped out.</p>")
    for rule in ("baseline-rm-rf-outside", "push-gate", "no-hook-bypass", "baseline-hard-reset",
                 "baseline-force-push"):
        if rule in sample and sample[rule].strip():
            out.append('<div class="term"><span class="r">[&times;]</span> '
                       f'<span class="c">{html.escape(rule)}</span>\n'
                       f'    <span class="o">{html.escape(sample[rule])}</span></div>')
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
    return page("/catches", "rabadon, what it caught",
                f"{total} commands refused before they ran, read out of the gate's own ledger.",
                "\n".join(out))


def main():
    rows = commits()
    prs = pull_requests()
    for name, content in (("catches", catches()),
                          ("patch-notes", patch_notes(rows)),
                          ("pull-requests", pull_request_page(prs, rows)),
                          ("benchmarks", benchmarks(rows))):
        with open(f"site/{name}.html", "w", encoding="utf-8") as f:
            f.write(content)
        print(f"site/{name}.html  {len(content):>7} bytes")
    print(f"  from {len(rows)} commits, {len(prs)} pull requests, "
          f"{len(group_by_day(rows))} days, {len(SUITES)} suites")


if __name__ == "__main__":
    main()
