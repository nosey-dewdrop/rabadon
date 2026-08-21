#!/usr/bin/env python3
"""What a stranger is told when they mistype a verb.

Driven by native/cli_test.sh section 6; kept in its own file so the SAME
assertions can be pointed at an older dispatcher as a negative control. A check
that has never been observed to fail is not a check, and this one guards a list
that had already gone stale once.

argv[1] = the dispatcher to probe, argv[2] = the tab-separated report to write.

Nothing here writes the expected verbs down. They are parsed out of the `case`
arms of the dispatcher itself, for the same reason section 1b parses the binary
map: the string this replaces was a second copy of the verb list, and a second
copy is only ever correct on the day it is typed.
"""
import os
import re
import subprocess
import sys

CLI = os.path.abspath(sys.argv[1])
REPORT = sys.argv[2]
ROOT = os.getcwd()

out = []


def rec(good, msg):
    out.append(("PASS" if good else "FAIL") + "\t" + msg)


def finish():
    open(REPORT, "w").write("\n".join(out) + "\n")
    sys.exit(0)


# ---- the arms, read out of the dispatcher ----
# An arm tagged `#unlisted` routes but is deliberately not advertised. That tag
# is the only place the distinction is recorded, so the dispatcher stays the one
# source of truth for both halves of the question.
src = open(CLI, encoding="utf-8").read()
head = 'case "$VERB" in'
if head not in src:
    rec(False, "the dispatcher has no `%s` block — the verb parser needs rewriting" % head)
    finish()
block = src[src.index(head) + len(head):src.rindex("esac")]

listed, unlisted = [], []
for line in block.splitlines():
    m = re.match(r"^  ([a-z0-9|_-]+)\)", line)
    if not m:
        continue
    labels = [x for x in m.group(1).split("|") if x and not x.startswith("-")]
    (unlisted if "#unlisted" in line else listed).extend(labels)
expected, unlisted = set(listed), set(unlisted)

rec(len(expected) >= 20,
    "the dispatcher's case list parsed to %d advertisable verbs to check against" % len(expected)
    if len(expected) >= 20 else
    "only %d verbs parsed out of the case arms (%s) — every assertion below would be "
    "vacuous, fix the parser" % (len(expected), " ".join(sorted(expected))))
if len(expected) < 20:
    finish()

# ---- the message ----
env = dict(os.environ, RABADON_NOTIFY="0")
p = subprocess.run([CLI, "zzqq"], stdin=subprocess.DEVNULL, capture_output=True,
                   timeout=30, env=env, cwd=ROOT)
msg = p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")

rec(p.returncode == 1,
    "an unrecognised verb exits 1" if p.returncode == 1
    else "an unrecognised verb exited %d" % p.returncode)
rec('"zzqq"' in msg,
    "the message quotes the word it did not understand" if '"zzqq"' in msg
    else "the message never says which word was rejected")

# The verbs the message OFFERS, taken from its command block only. A plain word
# search over the whole message would count words out of the prose tail and call
# the list complete when it is not.
offered = set()
grab = False
for line in msg.splitlines():
    s = line.strip()
    if s.startswith("commands:"):
        grab = True
        continue
    if grab:
        if not s or s.startswith("run `rabadon help`"):
            grab = False
            continue
        offered.update(w for w in s.split() if re.fullmatch(r"[a-z0-9_-]+", w))

# POSITIVE FIRST. Everything below is an absence claim, and an absence claim on
# its own is passed by a message that lists nothing at all — or by a probe whose
# block parser silently matched zero lines. This is the assertion that makes the
# rest mean something.
rec(len(offered) >= 20,
    "the message offers a command list (%d verbs parsed out of it)" % len(offered)
    if len(offered) >= 20 else
    "only %d verbs could be read out of the message — the rest of section 6 would "
    "pass on an empty list. Message was:\n%s" % (len(offered), msg))
if len(offered) < 20:
    finish()

# POSITIVE — the half of the product the stale string dropped. Named one by one
# because "the sets are equal" further down would also be satisfied by a
# dispatcher that had lost these verbs entirely.
SEEING = ["usage", "lens", "report", "trace", "audit", "replay", "drill", "export"]
missing = [v for v in SEEING if v not in offered]
rec(not missing,
    "the message names the whole `seeing what happened` half: " + " ".join(SEEING)
    if not missing else
    "the message still hides %s — that is what a newcomer came for" % " ".join(missing))

# NEGATIVE, paired to the positive above: the five verbs no surface documents.
# `spin` is the sharp one, it starts headless claude sessions in the reader's repo.
undocumented = ["guard", "fleet", "spin", "pack", "statusline"]
named = [v for v in undocumented if v in offered]
rec(not named,
    "the message advertises none of the undocumented verbs: " + " ".join(undocumented)
    if not named else
    "the message still points a stranger at %s, which no doc explains" % " ".join(named))

# THE CONTRACT: what is offered is exactly what routes. Both directions, because
# each one is a different failure — a verb offered but not routed is a lie, and a
# verb routed but not offered is the hidden half this whole section is about.
rec(offered == expected,
    "the message's verb set equals the dispatcher's case list (%d verbs)" % len(expected)
    if offered == expected else
    "message vs dispatcher disagree — offered but does not route: [%s]; routes but is "
    "not offered: [%s]" % (" ".join(sorted(offered - expected)),
                           " ".join(sorted(expected - offered - unlisted))))

# ---- every advertised verb is explained SOMEWHERE a reader can reach ----
docs = ""
for root, _, files in os.walk(os.path.join(ROOT, "docs")):
    for f in files:
        docs += open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
readme = open(os.path.join(ROOT, "README.md"), encoding="utf-8", errors="replace").read()
helptext = subprocess.run([CLI, "help"], stdin=subprocess.DEVNULL, capture_output=True,
                          timeout=30, env=env, cwd=ROOT).stdout.decode("utf-8", "replace")
# T2 cut the main screen to five commands and moved the rest under `rabadon dev`,
# which has its own help. The law this section enforces is unchanged — a verb the
# unknown-verb message offers must be EXPLAINED SOMEWHERE A READER CAN REACH —
# and `rabadon dev --help` is now one of those places. Reading only the main
# screen would rule the move itself a defect; the threshold below stays where it
# was, because both screens together still list far more than fifteen verbs.
helptext += subprocess.run([CLI, "dev", "--help"], stdin=subprocess.DEVNULL,
                           capture_output=True, timeout=30, env=env,
                           cwd=ROOT).stdout.decode("utf-8", "replace")

# A verb owns the left column of a help line; the same rule section 1b uses, so
# "lens" appearing inside an example sentence does not count as being listed.
help_listed = set()
for line in helptext.splitlines():
    if not line.startswith("  ") or not line.strip():
        continue
    for alt in re.split(r"\s{2,}", line.strip())[0].split("|"):
        words = alt.split()
        if words:
            help_listed.add(words[0])

rec(len(help_listed) >= 15,
    "`rabadon help` lists %d verbs to check the message against" % len(help_listed)
    if len(help_listed) >= 15 else
    "only %d verbs parsed out of `rabadon help` — the documentation check would be weak"
    % len(help_listed))

undoc = sorted(v for v in offered
               if v not in help_listed
               and ("rabadon %s" % v) not in docs
               and ("rabadon %s" % v) not in readme)
rec(not undoc,
    "every verb the message offers is named in `rabadon help`, docs/ or README.md"
    if not undoc else
    "the message offers %s, which appears in no help screen, no doc and no README — "
    "the exact defect this section exists to catch" % " ".join(undoc))

# ---- did you mean ----
# `usag` is the real report: a dropped letter, not a wrong command.
p2 = subprocess.run([CLI, "usag"], stdin=subprocess.DEVNULL, capture_output=True,
                    timeout=30, env=env, cwd=ROOT)
m2 = p2.stdout.decode("utf-8", "replace") + p2.stderr.decode("utf-8", "replace")
hint = [l for l in m2.splitlines() if l.startswith("did you mean:")]
rec(bool(hint) and "usage" in hint[0],
    "`rabadon usag` suggests `usage`: %s" % (hint[0] if hint else "")
    if hint and "usage" in hint[0] else
    "`rabadon usag` offered no correction (%s)" % (hint[0] if hint else "no hint line"))
rec(bool(hint) and "export" not in hint[0],
    "the correction is a near match, not the whole list"
    if hint and "export" not in hint[0] else
    "the `did you mean` line is just the command list again")

# ---- the rejected word is data, never pattern and never code ----
# The suggestion matcher puts the user's word inside a `case` pattern
# (`case "$v" in "$typed"*`), which is the shape that turns a typo into a glob if
# the quotes are ever dropped. `*` would then match every verb and the correction
# would silently become the whole list; the substitution form is the sharper one.
for word, forbidden, why in (
        ("*", "did you mean:", "a glob matched every verb instead of being taken literally"),
        ("ex$(id)", "uid=", "the shell EXECUTED the rejected word")):
    pw = subprocess.run([CLI, word], stdin=subprocess.DEVNULL, capture_output=True,
                        timeout=30, env=env, cwd=ROOT)
    txt = pw.stdout.decode("utf-8", "replace") + pw.stderr.decode("utf-8", "replace")
    # positive first: the word came back verbatim, so the absence below is about
    # how it was handled and not about the probe having missed the message.
    rec('"%s"' % word in txt,
        "`rabadon '%s'` is echoed back verbatim" % word if '"%s"' % word in txt
        else "`rabadon '%s'` did not quote the word back; the check below is vacuous" % word)
    rec(forbidden not in txt,
        "`rabadon '%s'` treats it as data, not %s"
        % (word, "a pattern" if word == "*" else "code")
        if forbidden not in txt else "`rabadon '%s'`: %s" % (word, why))

# ---- nothing that used to route now falls into the unknown branch ----
# Before this change `*)` delegated to bin/rabadon.mjs, so every verb that file
# implements reached it. `*)` no longer delegates, which turns a missing arm into
# a verb that answers "unknown command" for a command that exists.
js = open(os.path.join(ROOT, "bin", "rabadon.mjs"), encoding="utf-8").read()
js_verbs = sorted(set(re.findall(r"cmd === '([a-z]+)'", js)))
rec(len(js_verbs) >= 10,
    "bin/rabadon.mjs implements %d verbs that must still route" % len(js_verbs)
    if len(js_verbs) >= 10 else
    "only %d verbs parsed out of bin/rabadon.mjs — the routing check would be weak"
    % len(js_verbs))
orphans = [v for v in js_verbs if v not in expected and v not in unlisted]
rec(not orphans,
    "every verb bin/rabadon.mjs implements still has an arm: " + " ".join(js_verbs)
    if not orphans else
    "%s is implemented but has no arm — it now answers `unknown command` for a "
    "command that exists" % " ".join(orphans))

finish()
