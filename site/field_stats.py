#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# field_stats.py — what the engine did in real repositories, read off its own ledger.
#
# The ledger has been recording since 25 July and nothing surfaced it, so nine
# days of evidence sat in ~/.rabadon/spool/*.jsonl where the person who built it
# could not see it either. Every number the site prints about the field comes
# from this file, and this file reads one source: the hash-chained ledger the
# gate writes as it runs.
#
#   python3 site/field_stats.py            print it
#   python3 site/field_stats.py --write    also update site/measured.json and
#                                          site/field.jsonl
#
# TWO THINGS IT REFUSES TO DO.
#
# It does not count its own laboratories. `vibecoded-demo`, `do-test`, the
# mktemp scratch repos and the express/crush/goose fixtures are runs made to
# exercise the engine, and counting them as field evidence is the measured party
# choosing the sample. They are excluded by name and the count of what was
# excluded is PRINTED, because a filter that hides its own size is the same
# problem one layer down.
#
# It does not publish text it has not looked at. Commands carry absolute paths
# and whatever the operator typed. Home is rewritten to `~`, and any record
# matching the sensitive-terms list is dropped from the published file — with
# the number of drops printed, never silently.
import collections, glob, json, os, re, sys, time

HOME = os.path.expanduser("~")
SPOOL = os.path.join(HOME, ".rabadon", "spool", "*.jsonl")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# runs made to exercise the engine. `<name>:session` is a real session in a repo
# called <name>; everything here is a harness, a demo or a scratch tree.
LAB_EXACT = {"vibecoded-demo", "llm-repair-live", "do-test:do", "do-test"}
LAB_PREFIX = ("tmp.", "rabadon-", "test-", "scratch")
# the fixtures the engine was proven against. real repositories, but visited to
# BE measured, so they are reported separately from the operator's own work.
FIXTURE = {"express:session", "goose:session", "crush:session"}

SENSITIVE = re.compile(
    r"kanser|onkolo|kemoterapi|biyopsi|tan[ıi]\s*kondu|hasta(l[ıi]k|ne)|"
    r"tc\s*kimlik|iban|password|passwd|secret|api[_-]?key|token=|bearer\s",
    re.I)


def is_lab(pipe):
    if pipe in LAB_EXACT:
        return True
    return any(pipe.startswith(p) for p in LAB_PREFIX)


USER = os.path.basename(HOME)
HOMES = os.path.dirname(HOME)   # the directory home directories live in

# somebody else's home, in output this machine merely relayed: a CI log from a
# foreign repository carries /home/runner, a foreign macOS path carries
# /Users/<name>. Neither is this operator's, and neither belongs on the page.
FOREIGN_HOME = re.compile(r"/(?:Users|home)/[^/\s'\"]*")

# how much of an account name has to survive before it counts as leaked. Four
# characters is enough to search on, so four characters is a leak.
PREFIX = 4


def unhome(s):
    """Rewrite every absolute home path to `~`, INCLUDING a truncated one.

    The details being redacted here were already clipped by the gate that wrote
    them, and a clip lands wherever the byte budget ran out — often in the
    middle of the account name. `replace(HOME, "~")` matches a whole string and
    a half of a path is not that string, so `/Users/damu` walked past the
    rewrite, past the account-name replacement, and past the check that was
    supposed to refuse the write, because the name that check searches for had
    been cut in half two steps earlier. Two records shaped exactly like that
    were published.

    So the longest prefix of HOME that is actually present is what gets
    replaced, down to the directory homes live in; then anything else shaped
    like somebody's home directory goes the same way."""
    s = s.replace(HOME, "~")
    for n in range(len(HOME) - 1, len(HOMES), -1):
        if HOME[:n] in s:
            s = s.replace(HOME[:n], "~")
    return FOREIGN_HOME.sub("~", s)


def leaks(blob):
    """What must never appear in the published file. Returns the reason, or ""
    — the write is refused on any of these rather than trimmed, because a rule
    that quietly edits its way out of a leak cannot be checked."""
    if HOMES + "/" in blob:
        return "an absolute home path survived redaction"
    for n in range(len(USER), PREFIX - 1, -1):
        if USER[:n] in blob:
            return "the account name survives redaction (%d of %d characters)" % (n, len(USER))
    return ""


def clean(s):
    if not s:
        return ""
    s = unhome(s).replace(USER, "home")
    return s[:400]


def project_of(pipe):
    # sessions started in the home directory are named after the DIRECTORY,
    # which is the operator's account name, not a project. Project names are
    # published on purpose; an account name is not one.
    p = (pipe or "-").split(":")[0]
    return "home" if p == USER else p


def live_rules():
    """Every rule id that is in a guard file on this machine right now, and the
    project whose guard holds it.

    The ledger records `new gate: <id>` the moment the engine authors a rule
    after an incident, and counting those events is how many rules it WROTE. It
    is not how many exist. `release-workflow-needs-test-gate` is on the ledger
    and is in no guard.json anywhere — the event was recorded, the write never
    landed, and a rule that is not in a guard file cannot fire in any repository
    ever. Publishing it inside a total of twelve would have been a claim with
    nothing behind it, on the page that exists to say claims need something
    behind them.

    Guards live beside the project they govern, so this walks the home tree to
    the depth projects actually sit at rather than trusting a list."""
    out = {}
    pats = [os.path.join(HOME, ".rabadon", "guard.json")]
    pats += [os.path.join(HOME, *(["*"] * d), ".rabadon", "guard.json") for d in (1, 2, 3)]
    for pat in pats:
        for path in sorted(glob.glob(pat)):
            try:
                g = json.load(open(path, encoding="utf-8"))
            except Exception:
                continue
            proj = project_of(g.get("project") or os.path.basename(os.path.dirname(os.path.dirname(path))))
            for r in g.get("bash") or []:
                rid = r.get("id")
                if rid:
                    # the sentence comes off the rule itself. a rule explains
                    # what it is for in its own file, and retyping that
                    # explanation onto a page is how the page and the rule start
                    # disagreeing.
                    out.setdefault(rid, (proj, clean(r.get("why", ""))))
    return out


def load():
    rows, files, bad = [], sorted(glob.glob(SPOOL)), 0
    for f in files:
        with open(f, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    rows.append(json.loads(line))
                except Exception:
                    bad += 1
    return rows, files, bad


def main():
    rows, files, bad = load()
    lab = [r for r in rows if is_lab(r.get("pipe", ""))]
    field = [r for r in rows if not is_lab(r.get("pipe", ""))]
    own = [r for r in field if r.get("pipe", "") not in FIXTURE]

    def evs(src, name):
        return [r for r in src if r.get("ev") == name]

    # WOULD_BLOCK: watch mode recorded the verdict and let the command through.
    # This is the number that answers "what would enforce mode have done".
    wb = evs(field, "WOULD_BLOCK")
    wb_own = evs(own, "WOULD_BLOCK")
    by_rule = collections.Counter(r.get("rule") or r.get("reason") or "-" for r in wb)
    by_proj = collections.Counter(project_of(r.get("pipe")) for r in wb)

    # STOP: enforce mode refused and the command never ran.
    stop = evs(field, "STOP")

    # and WHEN, because the two modes did not run for the same length of time.
    # Watch mode has been recording since 25 July; enforce mode was armed on
    # 3 August. Printing a single STOP total beside "nine days" invites the
    # reader to divide one by the other and get a rate that never existed, and
    # a day column is the cheapest possible way to make that impossible.
    def by_day(src):
        c = collections.Counter()
        for r in src:
            ts = r.get("ts", 0)
            c[("%04d-%02d-%02d" % time.gmtime(ts / 1000)[:3]) if ts else "?"] += 1
        return sorted(c.items())

    stop_days, wb_days = by_day(stop), by_day(wb)

    # REPAIR_OK with a rule step: the engine wrote a NEW rule after an incident,
    # so the same class cannot happen twice. The step carries the rule's name.
    rules = []
    for r in evs(field, "REPAIR_OK"):
        step = str(r.get("step") or "")
        if step.startswith("new gate: "):
            rules.append({
                "rule": step[len("new gate: "):],
                "project": project_of(r.get("pipe")),
                "ts": r.get("ts", 0),
                "kind": r.get("repair_kind", ""),
            })
    rules.sort(key=lambda x: x["ts"])

    # written is one number, still there is another, and the page prints both.
    here = live_rules()
    for r in rules:
        r["live"] = r["rule"] in here
        r["in"], r["why"] = here.get(r["rule"], ("", ""))
    n_live = sum(1 for r in rules if r["live"])

    # push-gate: the engine ran the suite itself and refused the push until green.
    pg_fail = [r for r in evs(field, "REPAIR_FAIL") if r.get("step") == "push-gate"]
    pg_ok = [r for r in evs(field, "REPAIR_OK") if r.get("step") == "push-gate"]

    print("ledger: %d lines, %d day files, %d lines that were not JSON" % (len(rows), len(files), bad))
    print("excluded as laboratory runs: %d lines (%s)"
          % (len(lab), ", ".join(sorted({r.get("pipe", "") for r in lab})) or "none"))
    print("fixtures reported separately: %s" % ", ".join(sorted(FIXTURE)))
    print()
    print("WOULD_BLOCK (watch mode: verdict recorded, command allowed) %d" % len(wb))
    print("  of those, in the operator's own repositories: %d" % len(wb_own))
    for rule, n in by_rule.most_common(10):
        print("    %-32s %4d" % (rule, n))
    print("  by project:", dict(by_proj.most_common(8)))
    print()
    print("STOP (enforce mode: the command did not run) %d" % len(stop))
    print()
    print("RULES THE ENGINE WROTE ITSELF after an incident: %d written, %d still in a guard file"
          % (len(rules), n_live))
    for r in rules:
        print("    %-34s %-10s %s" % (r["rule"], r["project"],
                                      ("live in " + r["in"]) if r["live"] else "NOT IN ANY GUARD FILE"))
    print()
    print("push-gate: %d pushes refused on a red tree, %d released once the suite was green"
          % (len(pg_fail), len(pg_ok)))

    if "--write" not in sys.argv:
        return

    # the published records. anything sensitive is dropped and counted.
    pub, dropped = [], 0
    for r in wb + stop:
        blob = json.dumps(r, ensure_ascii=False)
        if SENSITIVE.search(blob):
            dropped += 1
            continue
        pub.append({
            "ev": r.get("ev"),
            "rule": r.get("rule") or r.get("reason") or "",
            "project": project_of(r.get("pipe")),
            "ts": r.get("ts", 0),
            "detail": clean(r.get("detail", "")),
        })
    pub.sort(key=lambda x: x["ts"], reverse=True)
    leak = [(p, leaks(json.dumps(p, ensure_ascii=False))) for p in pub]
    leak = [(p, why) for p, why in leak if why]
    if leak:
        print("REFUSING TO WRITE: %s, in %d record(s)" % (leak[0][1], len(leak)))
        print("  first:", json.dumps(leak[0][0], ensure_ascii=False)[:300])
        sys.exit(1)
    with open(os.path.join(REPO, "site", "field.jsonl"), "w", encoding="utf-8") as f:
        for p in pub:
            f.write(json.dumps(p, ensure_ascii=False) + "\n")

    mp = os.path.join(REPO, "site", "measured.json")
    d = json.load(open(mp, encoding="utf-8")) if os.path.exists(mp) else {}
    note = ("read from the hash-chained ledger the gate writes as it runs "
            "(~/.rabadon/spool/*.jsonl, %d lines over %d day files). runs made to "
            "exercise the engine are excluded by name and the excluded count is "
            "printed; the three proving-ground repositories are reported separately. "
            "home paths are rewritten to ~ and %d record(s) matching the sensitive-terms "
            "list were dropped from the published file."
            % (len(rows), len(files), dropped))
    for key, val, what in (
        ("field.would_block", len(wb), "commands watch mode recorded a verdict on and let through"),
        ("field.would_block_own", len(wb_own), "of those, in the operator's own repositories"),
        ("field.stop", len(stop), "commands enforce mode refused outright"),
        ("field.rules_written", len(rules), "rules the engine wrote itself after an incident"),
        ("field.rules_live", n_live, "of those, in a guard file on this machine right now"),
        ("field.pushes_refused", len(pg_fail), "pushes refused on a red tree until the suite was green"),
        ("field.days", len(files), "days the ledger has been running"),
        # the ledger is nine days old and that is NOT how long these verdicts
        # took. WOULD_BLOCK appears on three of those nine days, and pairing a
        # total with the age of the file invites a rate that never existed.
        ("field.days_watch", len(wb_days), "days that carry a recorded watch-mode verdict"),
        ("field.days_enforce", len(stop_days), "days that carry an outright refusal"),
    ):
        d[key] = {"value": val, "cmd": "python3 site/field_stats.py", "what": what, "note": note}
    d["field.rules_list"] = {"value": rules, "cmd": "python3 site/field_stats.py",
                             "what": "the rules, with the repository each incident happened in",
                             "note": note}
    d["field.stop_by_day"] = {"value": stop_days, "cmd": "python3 site/field_stats.py",
                              "what": "refusals per day, so a total cannot be read as a rate",
                              "note": note}
    d["field.would_block_by_day"] = {"value": wb_days, "cmd": "python3 site/field_stats.py",
                                     "what": "recorded verdicts per day, watch mode", "note": note}
    d["field.would_block_by_rule"] = {"value": by_rule.most_common(12),
                                      "cmd": "python3 site/field_stats.py",
                                      "what": "which rule, how many times", "note": note}
    with open(mp, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, sort_keys=True)
        f.write("\n")
    print()
    print("wrote site/measured.json (field.*) and site/field.jsonl — %d published, %d dropped as sensitive"
          % (len(pub), dropped))


main()
