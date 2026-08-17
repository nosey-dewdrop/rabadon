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
#
# That redactor now lives in site/redact.py rather than here. It was written in
# this file and it worked in this file: field.jsonl went out clean. The census
# in site/rule_census.json is written by a different script, that script had no
# redactor, and it went out with 1058 absolute home paths — while the page
# linking both files claimed the rule held for the whole dataset. A rule that
# protects the file it happens to be written inside is not a rule, so it is a
# module now, and both generators import it.
import collections, glob, json, os, sys, time

import identity
import redact
# the laboratories and the project label both moved to site/identity.py. They
# were private to this file, so the two other generators that publish a project
# name — site/rule_census.py and site/build.py — could not see either one, which
# is the same failure the redactor was pulled out of this file to fix.
from identity import (FIXTURE, LAB_EXACT, LAB_PREFIX,  # noqa: F401
                      is_lab, published_label)
from redact import (SENSITIVE, USER, clean, leaks, project_of,  # noqa: F401
                    unhome, withhold_reason)

HOME = os.path.expanduser("~")
SPOOL = os.path.join(HOME, ".rabadon", "spool", "*.jsonl")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# LAB_EXACT, LAB_PREFIX, FIXTURE and is_lab() are imported above. They lived
# here, as a private set inside one of the three generators that publish a
# project name, and the other two therefore disagreed with this one: the
# allowlist check counted rabadon's own probe trees as projects awaiting a
# disclosure decision, because nothing outside this file had ever heard of the
# list. They are in site/identity.py now, beside the rest of the question they
# were half of — what does this label denote — and the reason each entry is on
# the list is written there.


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
            # WHERE A GUARD LIVES, NOT WHAT IT CALLS ITSELF. This read the
            # guard's self-declared `project` key first and fell back to the
            # directory. That key is a nickname: 10 of the 63 guards on this
            # machine declare a name their directory does not have, and four of
            # those are a second spelling of a project the ledger already names
            # the other way — so the same project was published twice, under two
            # names, and counted as two. Two more declare a name their directory
            # has nothing to do with, which published a second name for a project
            # nobody had decided to publish once.
            proj = published_label(identity.from_guard_path(path))
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

    # DRILLS ARE NOT FIELD EVENTS, and this file was the one that forgot.
    #
    # The gate stamps `"drill": true` on every event a test suite fires, and
    # site/build.py has counted those separately from the start, on the page
    # that says "a tool that pads its own numbers with its own drills has no
    # business judging anyone else's proof". This file, which writes the
    # PUBLISHED site/field.jsonl and every field.* number in measured.json, had
    # no drill filter at all — is_lab() screens by PIPE NAME, and a drill fired
    # inside a real project carries a real project's pipe.
    #
    # Measured: 206 drill-flagged STOP/WOULD_BLOCK events in the ledger, and all
    # 206 were published in site/field.jsonl with the flag stripped — 19.5% of
    # the 1058 published records. Among them a `test-tamper` STOP against
    # discourse, rendered on the live site as a field catch in somebody else's
    # repository. It was a rehearsal.
    #
    # The count is printed rather than quietly applied, the same way the
    # laboratory exclusion prints its own size, because a filter that hides how
    # much it removed is the thing this whole page refuses.
    drills = [r for r in rows if r.get("drill")]
    rows = [r for r in rows if not r.get("drill")]
    _drill_verdicts = sum(1 for r in drills if r.get("ev") in ("STOP", "WOULD_BLOCK"))
    print("excluded as drills fired by the test suites: %d line(s), %d of them verdicts"
          % (len(drills), _drill_verdicts))

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
    by_proj = collections.Counter(published_label(r.get("pipe")) for r in wb)

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
                "project": published_label(r.get("pipe")),
                "ts": r.get("ts", 0),
                "kind": r.get("repair_kind", ""),
            })
    rules.sort(key=lambda x: x["ts"])

    # written is one number, still there is another, and the page prints both.
    here = live_rules()
    for r in rules:
        r["live"] = r["rule"] in here
        r["in"], r["why"] = here.get(r["rule"], ("", ""))

    # AND A RULE ID IS FREE TEXT, so it goes through the redactor like free text.
    #
    # The engine names a rule after what it is about, and one of them is named
    # after a withheld project: the id ends in the repository's name. The id was
    # published verbatim here — no `project` field carried the name, so the
    # allowlist could not see it, and withhold_reason is applied to field.jsonl's
    # records but never to this list. It reached site/measured.json and
    # site/field.html and survived every publish.
    #
    # It was found on 2026-08-17 and fixed IN THE ARTIFACT: the name was edited
    # out of the two published files and the generator was left as it was, so
    # the next `--write` put it straight back. This is the same fix applied to
    # the cause. The lookup above runs FIRST and on the raw id, because `here`
    # is keyed by what the guard files actually call the rule.
    for r in rules:
        r["rule"] = clean(r["rule"], 0)
    n_live = sum(1 for r in rules if r["live"])

    # AND THE COUNT OF EVENTS IS NOT THE COUNT OF RULES. The ledger records one
    # line per authoring event, and `no-gnu-timeout-on-macos` was authored twice
    # after two separate incidents in two repositories. Publishing the event
    # count as "rules it wrote itself" is the same defect one layer along from
    # the one this file was just taught to catch: counting the record instead of
    # the thing. Both are kept, and the page prints the distinct one.
    ids = {r["rule"] for r in rules}
    ids_live = {r["rule"] for r in rules if r["live"]}
    n_ids, n_ids_live = len(ids), len(ids_live)

    # THE NUMBER THIS IS ALL JUDGED ON. Anybody can publish how many commands
    # they refused. That figure means nothing on its own; it means something
    # beside the count of refusals that were WRONG, and a vendor can only publish
    # the second one if it is on the same tamper-evident ledger as the first.
    # Until 3 August there was no record type for it, so three wrong refusals
    # that night ended up as prose in a report.
    wrong = evs(rows, "WRONG_REFUSAL")
    wrong_by_rule = collections.Counter(r.get("rule") or "-" for r in wrong)

    # and every time supervision was switched on or off. On 3 August at 02:25 a
    # session ran `rabadon off`, the machine was unguarded from then on, and four
    # other sessions kept working underneath it with no way to know.
    modes = evs(rows, "MODE")

    # which rule did the outright refusing. by_rule above covers watch mode only,
    # so the armed half of the record had no breakdown at all.
    stop_by_rule = collections.Counter(r.get("rule") or r.get("reason") or "-" for r in stop)

    # diagnoses: the gate handing back a written account of what broke, which is
    # the half of the product that is not a refusal.
    diagnoses = evs(field, "CHECK_FAIL")

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
    print("RULES THE ENGINE WROTE ITSELF after an incident: %d authoring events, %d distinct rules, "
          "%d of those still in a guard file" % (len(rules), n_ids, n_ids_live))
    for r in rules:
        print("    %-34s %-10s %s" % (r["rule"], r["project"],
                                      ("live in " + r["in"]) if r["live"] else "NOT IN ANY GUARD FILE"))
    print()
    print("push-gate: %d pushes refused on a red tree, %d released once the suite was green"
          % (len(pg_fail), len(pg_ok)))
    print()
    print("WRONG REFUSALS reported by the operator: %d" % len(wrong))
    for r in wrong:
        print("    %-34s %s" % (r.get("rule", "-"), clean(r.get("why", ""))[:110]))
    print("SUPERVISION SWITCHED: %d time(s)" % len(modes))
    print("DIAGNOSES handed back: %d" % len(diagnoses))

    if "--write" not in sys.argv:
        return

    # the published records. anything sensitive is dropped and counted.
    #
    # "Sensitive" is now two things, and the second one is the one this file
    # used to publish. Sensitive CONTENT is what the command said. A sensitive
    # PROJECT NAME is what the repository is called, and a name is data about
    # its author on its own: a repository named after a condition discloses a
    # health context with no path around it and no command text beside it, and
    # the name outlives the path. Rewriting the path under
    # such a record leaves the disclosure standing, so the record is dropped —
    # and counted by reason, because two different withholdings collapsed into
    # one number cannot be argued with.
    pub, withheld = [], collections.Counter()
    for r in wb + stop:
        p = {
            "ev": r.get("ev"),
            "rule": r.get("rule") or r.get("reason") or "",
            "project": published_label(r.get("pipe")),
            "ts": r.get("ts", 0),
            "detail": clean(r.get("detail", "")),
        }
        # the raw record catches what the ledger held; the rendered one catches
        # what would actually have gone out.
        why = (withhold_reason(json.dumps(r, ensure_ascii=False))
               or withhold_reason(json.dumps(p, ensure_ascii=False)))
        if why:
            withheld[why] += 1
            continue
        pub.append(p)
    dropped = sum(withheld.values())
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
            "list were dropped from the published file (%s)."
            % (len(rows), len(files), dropped,
               ", ".join("%d %s" % (n, k) for k, n in sorted(withheld.items())) or "none"))
    for key, val, what in (
        ("field.would_block", len(wb), "commands watch mode recorded a verdict on and let through"),
        ("field.would_block_own", len(wb_own), "of those, in the operator's own repositories"),
        ("field.stop", len(stop), "commands enforce mode refused outright"),
        ("field.rules_written", len(rules), "rules the engine wrote itself after an incident"),
        ("field.rules_live", n_live, "of those, in a guard file on this machine right now"),
        ("field.rules_distinct", n_ids, "distinct rules behind those events; one was authored twice"),
        ("field.rules_distinct_live", n_ids_live, "distinct rules that are in a guard file right now"),
        ("field.pushes_refused", len(pg_fail), "pushes refused on a red tree until the suite was green"),
        ("field.days", len(files), "days the ledger has been running"),
        # the ledger is nine days old and that is NOT how long these verdicts
        # took. WOULD_BLOCK appears on three of those nine days, and pairing a
        # total with the age of the file invites a rate that never existed.
        ("field.days_watch", len(wb_days), "days that carry a recorded watch-mode verdict"),
        ("field.days_enforce", len(stop_days), "days that carry an outright refusal"),
        ("field.wrong_refusals", len(wrong),
         "refusals reported wrong by the operator, on the same chain as the refusals"),
        ("field.diagnoses", len(diagnoses),
         "written accounts of what broke, handed back instead of a refusal"),
        ("field.mode_changes", len(modes), "times supervision was switched on or off"),
        # the size of the filter, published beside what the filter let through.
        # a drop nobody can count is indistinguishable from a record that never
        # existed, and that is a different untruth from the one redaction fixes.
        ("field.withheld", dropped,
         "records withheld from the published file: sensitive content, or a repository whose "
         "NAME is itself the disclosure"),
    ):
        d[key] = {"value": val, "cmd": "python3 site/field_stats.py", "what": what, "note": note}
    d["field.rules_list"] = {"value": rules, "cmd": "python3 site/field_stats.py",
                             "what": "the rules, with the repository each incident happened in",
                             "note": note}
    d["field.wrong_by_rule"] = {"value": wrong_by_rule.most_common(12),
                                "cmd": "python3 site/field_stats.py",
                                "what": "which rule was wrong, how many times", "note": note}
    d["field.wrong_list"] = {"value": [{"rule": r.get("rule", ""), "why": clean(r.get("why", "")),
                                        "ts": r.get("ts", 0)} for r in sorted(
                                            wrong, key=lambda x: x.get("ts", 0), reverse=True)],
                             "cmd": "python3 site/field_stats.py",
                             "what": "each wrong refusal with the reason it was wrong", "note": note}
    d["field.stop_by_rule"] = {"value": stop_by_rule.most_common(12),
                               "cmd": "python3 site/field_stats.py",
                               "what": "which rule refused outright, how many times", "note": note}
    d["field.mode_list"] = {"value": [{"from": r.get("from", ""), "to": r.get("to", ""),
                                       "ts": r.get("ts", 0)} for r in sorted(
                                           modes, key=lambda x: x.get("ts", 0), reverse=True)][:20],
                            "cmd": "python3 site/field_stats.py",
                            "what": "when supervision was switched on or off", "note": note}
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


def rewrite_published():
    """Apply today's rule to the file that went out under yesterday's.

    The rule itself lives in main()'s publish loop, which is the point of
    generation and the only place a NEW record can be born. This is the other
    half of closing a leak that has already happened: site/field.jsonl on disk
    was written before project names counted as identifying, and waiting for
    the next `--write` means the file stays wrong until then. Same filter, same
    module, applied to the records already published — nothing is re-measured,
    so no field number moves.

        python3 site/field_stats.py --rewrite-published
    """
    fp = os.path.join(REPO, "site", "field.jsonl")
    keep, withheld = [], collections.Counter()
    n = 0
    with open(fp, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            n += 1
            why = withhold_reason(line)
            if why:
                withheld[why] += 1
                continue
            r = json.loads(line)
            r["detail"] = clean(r.get("detail", ""))
            r["project"] = published_label(r.get("project"))
            keep.append(r)
    dropped = sum(withheld.values())
    bad = [(p, leaks(json.dumps(p, ensure_ascii=False))) for p in keep]
    bad = [(p, why) for p, why in bad if why]
    if bad:
        print("REFUSING TO WRITE: %s, in %d record(s)" % (bad[0][1], len(bad)))
        print("  first:", json.dumps(bad[0][0], ensure_ascii=False)[:300])
        sys.exit(1)
    with open(fp, "w", encoding="utf-8") as f:
        for p in keep:
            f.write(json.dumps(p, ensure_ascii=False) + "\n")

    mp = os.path.join(REPO, "site", "measured.json")
    d = json.load(open(mp, encoding="utf-8")) if os.path.exists(mp) else {}
    prev = (d.get("field.withheld") or {}).get("value", 0)
    d["field.withheld"] = {
        "value": prev + dropped,
        "cmd": "python3 site/field_stats.py",
        "what": ("records withheld from the published file: sensitive content, or a repository "
                 "whose NAME is itself the disclosure"),
        "note": ("%d of these were withheld when site/field.jsonl was re-emitted through "
                 "site/redact.py (%s); the rest were withheld at generation." % (
                     dropped,
                     ", ".join("%d %s" % (c, k) for k, c in sorted(withheld.items())) or "none")),
    }
    with open(mp, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, sort_keys=True)
        f.write("\n")
    print("site/field.jsonl: %d records in, %d published, %d withheld (%s)"
          % (n, len(keep), dropped,
             ", ".join("%d %s" % (c, k) for k, c in sorted(withheld.items())) or "none"))


if "--rewrite-published" in sys.argv:
    rewrite_published()
else:
    main()
