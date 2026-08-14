#!/bin/bash
# publish_redaction_test.sh — a download the site serves may not carry the
# absolute home path of the machine that produced it, or the name of a
# repository whose name is itself private.
#
# THE FAILURE THIS EXISTS FOR. site/field.jsonl was written through a redactor
# and went out clean. site/rule_census.json is written by a different script,
# that script had no redactor, and it went out — publicly, at
# https://rabadon.noseydewdrop.com/rule_census.json — with 1058 occurrences of
# the operator's absolute home path and the names of eleven private
# repositories, one class of which discloses a health context by the name
# alone. site/field.html declared in schema.org, over BOTH files, that "home
# paths are rewritten and records matching a sensitive-terms list are dropped
# and counted before publication". The claim was true of one file and false of
# the other, and nothing on the machine could tell the difference, because the
# rule lived inside one of the two generators instead of in front of both.
#
# So this file checks the property, not the generator: whatever wrote it,
# whatever it is called, if it is served from site/ it gets read.
#
# SIX SECTIONS, AND THE FIRST TWO ARE THE ONES THAT MATTER.
#   1. THE SCANNER CAN GO RED. A synthetic site directory carrying a home path
#      and a withheld name must be reported, both of them, by name of file. A
#      check that has never been red is not a check, and this one is a grep —
#      the easiest kind of check to write in a form that can only pass.
#   2. THE GENERATOR REDACTS AT THE WRITE PATH. site/rule_census.py is driven,
#      in a copied repository under a fake home, over a census built here that
#      contains both kinds of leak. What it writes must be clean, must say HOW
#      MANY records it withheld, and the unredacted copy must land outside the
#      published directory — the census is the baseline for the next run, so a
#      redactor that simply deleted those rules would shrink the measurement a
#      little more every time it ran.
#   3. THE LEDGER EXTRACTOR APPLIES THE SAME RULE, from the same module.
#   4. NO TERMS FILE MEANS NO NAME MATCHING. re.compile("") matches every
#      string, so a machine without a terms list is one bug away from
#      withholding its entire census while looking like it worked.
#   5. A PROJECT KEY IS AN ABSOLUTE PATH IN ANOTHER ALPHABET, and is redacted
#      as one. The agent labels a session with its working directory spelled
#      `-Users-<account>-work-proj`, the gate stamps that on every record, and
#      three checks in a row read straight past it because all three were
#      looking for a slash. The refusal at the end of the write was the only
#      thing that saw it, and a refusal with no rewrite behind it does not close
#      a leak — it freezes the deploy that would have closed it.
#   6. THE REAL site/ IS CLEAN, and the claim on the page is backed by a
#      published count rather than by this sentence.
#
# WHAT COUNTS AS PUBLISHED. `vercel deploy` uploads the site directory as it
# stands, so the scan set is every file under site/ except what site/.vercelignore
# excludes. Deleting a line there does not narrow what this test reads by
# accident: it widens it.
#
# THE TERMS ARE NOT IN THIS REPOSITORY. They are in a file the operator owns
# ($RABADON_REDACT_TERMS, default ~/.rabadon/redact/projects.txt) because this
# repository is public and a committed list of private repository names is the
# disclosure it was written to prevent. Sections 1-5 write their own list and
# are therefore as red on a CI runner as they are here; section 6 can only
# check the names the machine it runs on knows about, and says so when there
# are none.
#
# $RABADON_REDACT_PY runs sections 2-5 against a different site/redact.py, which
# is how each case here was shown red against the module that shipped before it.
# Section 6 always reads the real one.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ---------------------------------------------------------------------------
# the scanner. one implementation, used by the synthetic fixtures and by the
# real site/, so section 5 cannot be passing for a different reason than
# section 1 is failing.
#   scan <dir> <home-path> <terms-file>  -> prints one line per finding
# ---------------------------------------------------------------------------
scan() {
  python3 - "$1" "$2" "$3" <<'PY'
import os, re, sys
root, home, terms_file = sys.argv[1], sys.argv[2], sys.argv[3]

terms = []
try:
    for line in open(terms_file, encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if line:
            terms.append(line)
except OSError:
    pass

# site/.vercelignore is the deploy's own answer to "what is published". It is
# read rather than restated: a second copy of the list is a second thing to
# forget to update.
ignore = []
try:
    for line in open(os.path.join(root, ".vercelignore"), encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if line:
            ignore.append(line.rstrip("/"))
except OSError:
    pass


def ignored(rel):
    parts = rel.split(os.sep)
    for pat in ignore:
        for p in parts:
            if p == pat or (pat.startswith("*") and p.endswith(pat[1:])) \
               or (pat.endswith("*") and p.startswith(pat[:-1])):
                return True
    return False


name_re = re.compile("|".join(re.escape(t) for t in terms), re.I) if terms else None

# the same home directory in the alphabet a project key is written in:
# /Users/<account>/work/proj -> -Users-<account>-work-proj. The gate stamps that
# key onto every record it writes, and a scan that only ever counted slashes
# read 300 of them as clean. See site/redact.py.
enc_home = re.sub(r"[^A-Za-z0-9]+", "-", home)

# and the account name ON ITS OWN, which is shorter than either path and is the
# string a reader actually searches. This file is served from the directory it
# guards — site/redact.py answers 200 on the domain — so a docstring that spells
# the name out is published as surely as a JSON record is, and no path check
# anywhere would have reported it.
account = os.path.basename(home.rstrip("/"))
if not account:                 # "" counts once per character; a scan that
    account = "\0"              # reports every byte reports nothing.

# A CI runner's account is a dictionary word. GitHub's macOS image is
# /Users/runner, so this scan counted every "runner" in published PROSE as a
# leaked account name — "the node runner's own 'i fail 0' line", and six more
# like it — and CI went red on every push with seven findings that were all the
# same English noun. None of the artifacts are even generated on the runner;
# they are built on the operator's machine and committed, so the name this check
# exists to catch is never the name the runner is called.
#
# That is worse than a missing check. A red that is always red is a red nobody
# reads, and a real leak would have arrived into the same seven lines of noise
# and been shipped. So the scan says out loud when it has nothing to look for,
# the way the withheld-terms branch below already does, instead of inventing a
# finding to look busy.
#
# THE GAP THIS LEAVES, stated rather than papered over: CI cannot check for an
# operator name it does not know, and the name must not be written into a public
# repository to teach it. So the bare-name check has teeth only where the name is
# real, which is the operator's own `make test` before the commit that publishes.
# CI still holds the two path checks, and those are what catch a raw /Users/<x>/
# string no matter whose it is.
GENERIC_ACCOUNTS = {"runner", "root", "ubuntu", "user", "admin", "build", "ci",
                    "vsts", "vagrant", "docker", "home"}
account_is_generic = account.lower() in GENERIC_ACCOUNTS
if account_is_generic:
    print("        (the account this runs as is %r, a generic CI account name that\n"
          "         occurs in ordinary prose. Counting it would report the word, not a\n"
          "         leak. The absolute-path and project-key checks below still hold, and\n"
          "         they are the ones that would catch a real operator path.)" % account)

found = 0
for dirpath, dirnames, filenames in os.walk(root):
    for fn in sorted(filenames):
        path = os.path.join(dirpath, fn)
        rel = os.path.relpath(path, root)
        if ignored(rel):
            continue
        try:
            blob = open(path, "rb").read().decode("utf-8", "replace")
        except OSError:
            continue
        n = blob.count(home)
        if n:
            print("%s: %d absolute home path(s)" % (rel, n))
            found += 1
        k = blob.count(enc_home)
        if k:
            print("%s: %d project key(s) carrying the home path" % (rel, k))
            found += 1
        a = 0 if account_is_generic else blob.count(account) - n - k
        if a > 0:
            print("%s: %d bare account name(s)" % (rel, a))
            found += 1
        if name_re:
            hits = {}
            for m in name_re.finditer(blob):
                hits[m.group(0).lower()] = hits.get(m.group(0).lower(), 0) + 1
            if hits:
                print("%s: withheld project name(s) %s"
                      % (rel, ", ".join("%s=%d" % kv for kv in sorted(hits.items()))))
                found += 1
sys.exit(1 if found else 0)
PY
}

# ---------------------------------------------------------------------------
echo "1. the scanner can go red"
# ---------------------------------------------------------------------------
FAKE="$T/fakesite"
mkdir -p "$FAKE/__pycache__"
# the fake account name may not be a prefix of any word the fixture uses:
# redact.leaks() refuses a published file that carries four or more leading
# characters of the account name, and a census is full of the word "probe".
# The first version of this fixture was called probeuser and the generator
# refused to write at all, which is the redactor working and the test lying.
FAKEHOME="$T/home/qzvtester"
mkdir -p "$FAKEHOME"
TERMS="$T/terms.txt"
# not `secretproj`: the CONTENT regex already refuses anything containing
# "secret", so a fixture named that way would be withheld for the wrong
# reason and section 4 would read as a pass with the name check dead.
printf '# fixture list\nhushproj\nhealthkeeper\nsoft_hush\n' > "$TERMS"

printf '{"probe_cwd": "%s/projects/x", "ok": 1}\n' "$FAKEHOME" > "$FAKE/leaky.json"
printf '{"project": "healthkeeper", "verdict": "fires"}\n' > "$FAKE/named.jsonl"
printf '{"project": "public-thing", "verdict": "fires"}\n' > "$FAKE/clean.jsonl"
printf 'binary junk %s\n' "$FAKEHOME" > "$FAKE/__pycache__/x.pyc"
printf '__pycache__/\n' > "$FAKE/.vercelignore"

OUT="$(scan "$FAKE" "$FAKEHOME" "$TERMS")"; RC=$?
if [ $RC -ne 0 ]; then ok "a leaky directory is reported (exit $RC)"
else bad "the scanner passed a directory carrying a home path and a withheld name"; fi
case "$OUT" in *"leaky.json: 1 absolute home path"*) ok "the home path is found, with the file named";;
  *) bad "the home path was not reported: $OUT";; esac
case "$OUT" in *"named.jsonl: withheld project name(s) healthkeeper=1"*) ok "the withheld name is found and counted";;
  *) bad "the withheld project name was not reported: $OUT";; esac
case "$OUT" in *clean.jsonl*) bad "a clean file was reported as a finding";;
  *) ok "the clean file is not reported — this is a scanner, not a refusal to publish";; esac
case "$OUT" in *x.pyc*) bad ".vercelignore was ignored: a file that is not uploaded was scanned";;
  *) ok ".vercelignore decides the scan set, so it cannot silently widen what is served";; esac

# ---------------------------------------------------------------------------
echo "2. the census generator redacts at the point of generation"
# ---------------------------------------------------------------------------
# an isolated copy of the generators. rule_census.py locates the repository from
# its own path and the full-census copy from $HOME, so both land under mktemp
# and the real site/ and the real ~/.rabadon are never touched.
mkdir -p "$T/repo/site"
for f in rule_census.py field_stats.py; do cp "$REPO/site/$f" "$T/repo/site/$f"; done
# $RABADON_REDACT_PY swaps in another redactor, which is how every case below
# was shown red before it was closed — the same handle native/*_test.sh give
# for the binaries ($RABADON_GATE_BIN, $RABADON_REPAIR_BIN). Section 5 always
# reads the real site/ with the real module.
cp "${RABADON_REDACT_PY:-$REPO/site/redact.py}" "$T/repo/site/redact.py"

python3 - "$T/repo/site/rule_census.json" "$FAKEHOME" <<'PY'
import json, sys
out, home = sys.argv[1], sys.argv[2]
rules = [
    # two rules that may be published, one of them carrying a home path that
    # has to survive as `~` rather than be dropped
    {"project": "rabadon", "guard": home + "/rabadon/.rabadon/guard.json",
     "id": "no-force-push-main", "probe": "git push --force origin main",
     "probe_cwd": home + "/rabadon", "verdict": "fires"},
    {"project": "public-thing", "guard": home + "/public-thing/.rabadon/guard.json",
     "id": "no-rm-rf-outside", "probe": "rm -rf /", "probe_cwd": home + "/public-thing",
     "verdict": "fires"},
    # one that may not: the project NAME is the disclosure
    {"project": "healthkeeper", "guard": home + "/healthkeeper/.rabadon/guard.json",
     "id": "protect-data", "probe": home + "/healthkeeper/data.csv",
     "probe_cwd": home + "/healthkeeper", "verdict": "fires"},
    # and one whose project is innocent but whose PATH names the same repository
    {"project": "notes", "guard": home + "/notes/.rabadon/guard.json",
     "id": "no-copy-out", "probe": "cp " + home + "/hushproj/x .",
     "probe_cwd": home + "/notes", "verdict": "fires"},
]
census = {
    "generated_utc": "2026-08-05T00:00:00Z",
    "headline": {"total": len(rules), "can_fire": len(rules), "cannot_fire": 0,
                 "shadowed": 0, "guards": len(rules)},
    "by_project": [{"project": r["project"], "total": 1} for r in rules],
    "rules": rules,
    "comparison": {"probe_anomalies": [], "new_binary_path": "/tmp/x/native/rabadon-gate"},
}
json.dump(census, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
PY

CENSUS="$T/repo/site/rule_census.json"
cp "$CENSUS" "$T/census.before.json"
GEN="$(HOME="$FAKEHOME" RABADON_REDACT_TERMS="$TERMS" \
       python3 "$T/repo/site/rule_census.py" --republish 2>&1)"
GRC=$?
if [ $GRC -eq 0 ]; then ok "site/rule_census.py --republish ran (exit 0)"
else bad "the generator exited $GRC: $GEN"; fi

if ! grep -q "$FAKEHOME" "$CENSUS" 2>/dev/null; then ok "no absolute home path in what it wrote"
else bad "the published census still carries the home path"; fi
if ! grep -qi "healthkeeper\|hushproj" "$CENSUS" 2>/dev/null; then
  ok "no withheld project name in what it wrote"
else bad "the published census still names a withheld project"; fi

python3 - "$CENSUS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
w = d.get("withheld_from_publication") or {}
ids = [r["id"] for r in d["rules"]]
problems = []
if w.get("records") != 3:
    problems.append("withheld count is %r, expected 3 (one rule by name, one rule by "
                    "path, one by_project row)" % w.get("records"))
if sorted(ids) != ["no-force-push-main", "no-rm-rf-outside"]:
    problems.append("wrong rules survived: %r" % ids)
if d["headline"]["total"] != 4:
    problems.append("the MEASURED headline moved: %r" % d["headline"])
if "~/rabadon" not in json.dumps(d):
    problems.append("a home path was dropped instead of rewritten to ~")
if not w.get("note"):
    problems.append("the file does not say why anything was withheld")
for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
if [ $? -eq 0 ]; then
  ok "3 records withheld and COUNTED, survivors rewritten to ~, measured headline unchanged"
else bad "the withheld bookkeeping does not hold"; fi

FULL="$FAKEHOME/.rabadon/census/rule_census.full.json"
if [ -f "$FULL" ] && grep -q "healthkeeper" "$FULL"; then
  ok "the unredacted census is kept outside site/ as the next run's baseline"
else bad "no full census at $FULL — the next run's baseline would be the redacted file"; fi
case "$(ls -l "$FULL" 2>/dev/null | cut -c1-10)" in -rw-------) ok "the full census is mode 600";;
  *) bad "the full census is world-readable: $(ls -l "$FULL" 2>/dev/null | cut -c1-10)";; esac
SCANOUT="$(scan "$T/repo/site" "$FAKEHOME" "$TERMS" 2>&1)"
if [ -z "$SCANOUT" ]; then ok "the scanner agrees with the generator on the file it just wrote"
else bad "the generator wrote a file its own scanner rejects:"; echo "$SCANOUT" | sed 's/^/          /'; fi

# and the refusal, which is the half that runs when redaction cannot reach:
python3 - "$T/repo/site" "$TERMS" "$FAKEHOME" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
os.environ["RABADON_REDACT_TERMS"] = sys.argv[2]
os.environ["HOME"] = sys.argv[3]
import redact
bad = []
if not redact.leaks(sys.argv[3] + "/x"):
    bad.append("leaks() does not refuse an absolute home path")
if not redact.leaks('{"project": "healthkeeper"}'):
    bad.append("leaks() does not refuse a withheld project name")
if redact.leaks('{"project": "public-thing", "cwd": "~/public-thing"}'):
    bad.append("leaks() refuses a clean record")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
if [ $? -eq 0 ]; then ok "the write is refused on anything redaction did not reach"
else bad "the refusal path does not hold"; fi

# ---------------------------------------------------------------------------
echo "3. the ledger extractor withholds by the same rule, from the same module"
# ---------------------------------------------------------------------------
python3 - "$T/repo/site/field.jsonl" "$FAKEHOME" <<'PY'
import json, sys
out, home = sys.argv[1], sys.argv[2]
rows = [
    {"ev": "STOP", "rule": "no-rm-rf-outside", "project": "rabadon", "ts": 1,
     "detail": "rm -r 'x' resolves to ~/rabadon/x"},
    {"ev": "STOP", "rule": "no-rm-rf-outside", "project": "healthkeeper", "ts": 2,
     "detail": "rm -r 'y'"},
    {"ev": "WOULD_BLOCK", "rule": "no-copy-out", "project": "notes", "ts": 3,
     "detail": "cp " + home + "/hushproj/x ."},
]
with open(out, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
json.dump({}, open(out.replace("field.jsonl", "measured.json"), "w", encoding="utf-8"))
PY
FS="$(HOME="$FAKEHOME" RABADON_REDACT_TERMS="$TERMS" \
      python3 "$T/repo/site/field_stats.py" --rewrite-published 2>&1)"
case "$FS" in *"3 records in, 1 published, 2 withheld"*) ok "2 of 3 records withheld: $FS";;
  *) bad "field_stats.py did not withhold the two named records: $FS";; esac
if ! grep -qi "healthkeeper\|hushproj\|$FAKEHOME" "$T/repo/site/field.jsonl"; then
  ok "the re-emitted field file carries neither name nor home path"
else bad "the re-emitted field file still carries a withheld name or a home path"; fi
python3 - "$T/repo/site/measured.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
v = (d.get("field.withheld") or {}).get("value")
print("field.withheld=%r" % v)
sys.exit(0 if v == 2 else 1)
PY
if [ $? -eq 0 ]; then ok "the count is published, not just applied"
else bad "measured.json does not carry the withheld count"; fi

# ---------------------------------------------------------------------------
echo "4. an empty terms list matches NOTHING"
# ---------------------------------------------------------------------------
# re.compile("") matches every string. A machine with no terms file must
# publish its census whole, not withhold all of it and call that redaction.
printf '# nothing but comments\n' > "$T/empty-terms.txt"
cp "$T/census.before.json" "$T/repo/site/rule_census.json"
rm -rf "$FAKEHOME/.rabadon/census"
HOME="$FAKEHOME" RABADON_REDACT_TERMS="$T/empty-terms.txt" \
  python3 "$T/repo/site/rule_census.py" --republish >/dev/null 2>&1
python3 - "$T/repo/site/rule_census.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
w = (d.get("withheld_from_publication") or {}).get("records")
print("rules=%d withheld=%r" % (len(d["rules"]), w))
sys.exit(0 if (len(d["rules"]) == 4 and w == 0) else 1)
PY
if [ $? -eq 0 ]; then ok "no terms file: every record published, nothing withheld"
else bad "an empty terms list withheld records — the empty-regex trap"; fi
if ! grep -q "$FAKEHOME" "$T/repo/site/rule_census.json"; then
  ok "home paths are still rewritten with no terms list at all"
else bad "the home-path rewrite depends on the terms file"; fi

# ---------------------------------------------------------------------------
echo "5. a project key is an absolute path, and is redacted as one"
# ---------------------------------------------------------------------------
# THE FAILURE THIS SECTION EXISTS FOR. The agent names a session after its
# working directory with every run of non-alphanumerics collapsed to a dash, and
# the gate stamps that key onto the records it writes:
#     /Users/<account>/work/rabadon  ->  -Users-<account>-work-rabadon
# Three hundred records in the ledger carry one. The home-path rewrite searches
# for a slash and there is no slash; the account-name replacement is only ever
# applied to free text; the project field went through untouched. What caught it
# was the refusal at the end of the write, with no rewrite behind it to fall
# back on — so `./scripts/publish-field.sh` stopped at the field_stats step and
# the sanitized files never reached the domain. A refusal with nothing behind it
# does not close a leak, it freezes the deploy that would have closed it.
python3 - "$T/repo/site" "$TERMS" "$FAKEHOME" <<'PY'
import os, re, sys
sys.path.insert(0, sys.argv[1])
os.environ["RABADON_REDACT_TERMS"] = sys.argv[2]
os.environ["HOME"] = sys.argv[3]
import redact

home = sys.argv[3]
acct = os.path.basename(home)
# spelled here rather than asked of the module: a redactor without the rule
# has no encode_key either, and a test that dies on the missing helper reports
# one traceback instead of the four properties that are actually broken.
enc = re.sub(r"[^A-Za-z0-9]+", "-", home)
bad = []


def want(got, expect, what):
    if got != expect:
        bad.append("%s: got %r, want %r" % (what, got, expect))


# the label. A home-directory session and its encoded twin are the SAME
# session, and a project column that spells it two ways counts two projects.
want(redact.project_of(enc), "home", "the encoded home directory")
want(redact.project_of(acct), "home", "the home directory by name")
want(redact.project_of(enc + "-work-rabadon"), "rabadon", "an encoded project path")
want(redact.project_of("rabadon"), "rabadon", "a plain basename")
# `-` is a record with no project recorded. Folding it into `home` would turn
# "not known" into a place: a redaction may hide a fact, never invent one.
want(redact.project_of("-"), "-", "a record with no project")
want(redact.project_of(None), "-", "a record with no project field at all")

# the refusal, on a key this machine has never seen. A foreign key relayed
# through this ledger names somebody who never agreed to be named, and the
# account-name check cannot see them because it knows exactly one name.
if not redact.leaks('{"project": "-Users-someoneelse-app"}'):
    bad.append("leaks() does not refuse a FOREIGN account name in key form")
if not redact.leaks('{"project": %r}' % enc):
    bad.append("leaks() does not refuse this machine's own key")
# and it may not fire on ordinary text that merely contains the words.
for clean_text in ('{"rule": "no-home-write-outside"}', '{"detail": "my-home-dir"}',
                   '{"project": "rabadon"}'):
    if redact.leaks(clean_text):
        bad.append("leaks() refuses clean text: %s -> %s" % (clean_text, redact.leaks(clean_text)))

# free text carries the key too — a detail that quotes a transcript path.
out = redact.clean("cat /tmp/x/" + enc + "/session.jsonl")
if acct in out:
    bad.append("clean() left the account name in an encoded path: %r" % out)

# a withheld name, spelled the way a key spells it. The operator writes the
# term the way the directory is named; if that name carries a separator the
# encoding rewrites, the literal term appears nowhere in the key.
if not redact.names_a_sensitive_project('{"project": "-Users-x-soft-hush"}'):
    bad.append("the term soft_hush is not matched against the key spelling soft-hush")
if redact.names_a_sensitive_project('{"project": "-Users-x-public-thing"}'):
    bad.append("a name that is on no list was matched in key form")

for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
if [ $? -eq 0 ]; then ok "the encoded key is rewritten, refused when foreign, and matched against the terms"
else bad "the project-key rules do not hold"; fi

# and the same thing end to end, through the extractor that publishes it. In a
# repository of its own: section 4 deliberately leaves a census published under
# an EMPTY terms list in $T/repo/site, and a scan of that directory would report
# section 4's fixture and call it this section's leak.
mkdir -p "$T/keyrepo/site"
for f in rule_census.py field_stats.py; do cp "$REPO/site/$f" "$T/keyrepo/site/$f"; done
cp "${RABADON_REDACT_PY:-$REPO/site/redact.py}" "$T/keyrepo/site/redact.py"
python3 - "$T/keyrepo/site/field.jsonl" "$FAKEHOME" <<'PY'
import json, os, re, sys
out, home = sys.argv[1], sys.argv[2]
enc = re.sub(r"[^A-Za-z0-9]+", "-", home)
rows = [
    {"ev": "STOP", "rule": "no-exit-code-after-pipe", "project": enc, "ts": 1,
     "detail": "git status --short; echo exit=$?"},
    {"ev": "STOP", "rule": "no-force-push", "project": enc + "-work-rabadon", "ts": 2,
     "detail": "git push --force"},
]
with open(out, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
json.dump({}, open(out.replace("field.jsonl", "measured.json"), "w", encoding="utf-8"))
PY
KEYOUT="$(HOME="$FAKEHOME" RABADON_REDACT_TERMS="$TERMS" \
          python3 "$T/keyrepo/site/field_stats.py" --rewrite-published 2>&1)"; KRC=$?
if [ $KRC -eq 0 ]; then ok "the extractor publishes records labelled with an encoded key (exit 0)"
else bad "the extractor still refuses its own records: $KEYOUT"; fi
python3 - "$T/keyrepo/site/field.jsonl" "$FAKEHOME" <<'PY'
import json, os, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
acct = os.path.basename(sys.argv[2])
problems = []
if len(rows) != 2:
    problems.append("%d record(s) published, expected 2 — they were dropped, not rewritten" % len(rows))
if acct in json.dumps(rows):
    problems.append("the account name is still in the published records")
labels = sorted(r.get("project", "") for r in rows)
if labels != ["home", "rabadon"]:
    problems.append("labels are %r, expected ['home', 'rabadon']" % labels)
for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
if [ $? -eq 0 ]; then ok "both records survive, relabelled home and rabadon, with no account name left"
else bad "the published records are wrong"; fi
SCANOUT="$(scan "$T/keyrepo/site" "$FAKEHOME" "$TERMS" 2>&1)"
if [ -z "$SCANOUT" ]; then ok "the scanner reads the key spelling too, and finds nothing"
else bad "the scanner still reports the file the extractor just wrote:"; echo "$SCANOUT" | sed 's/^/          /'; fi

# ---------------------------------------------------------------------------
echo "6. the real site/ carries neither, and the page's claim is backed by a count"
# ---------------------------------------------------------------------------
# $RABADON_SITE_DIR points the scan somewhere else, which is how this section
# was shown to be red before the sanitizer landed: run it against a copy of the
# files as they were published on 4 August and it reports 1058 home paths and
# eleven names, in the two files that carry them.
SITE_DIR="${RABADON_SITE_DIR:-$REPO/site}"
REAL_TERMS="${RABADON_REDACT_TERMS:-$HOME/.rabadon/redact/projects.txt}"
NTERMS=$(grep -v '^[[:space:]]*#' "$REAL_TERMS" 2>/dev/null | grep -c '[^[:space:]]' || true)
[ -n "$NTERMS" ] || NTERMS=0
if [ "$NTERMS" -eq 0 ]; then
  echo "        (no terms file on this machine: the name check has nothing to look for."
  echo "         the home-path check below still holds. $REAL_TERMS)"
fi
OUT="$(scan "$SITE_DIR" "$HOME" "$REAL_TERMS")"
if [ -z "$OUT" ]; then
  ok "every published artifact under $SITE_DIR is clean ($NTERMS term(s) checked)"
else
  bad "published artifacts under $SITE_DIR carry what may not be published:"
  echo "$OUT" | sed 's/^/          /'
fi

# the claim and the data, checked against each other. site/field.html says, in
# schema.org, that records are "dropped and counted": if the page says it, the
# files it links have to carry the count.
CLAIM="$REPO/site/field.html"
if grep -q "dropped and counted before publication" "$CLAIM" 2>/dev/null; then
  MISSING=""
  python3 -c "
import json,sys
d=json.load(open('$REPO/site/rule_census.json'))
sys.exit(0 if isinstance((d.get('withheld_from_publication') or {}).get('records'), int) else 1)" \
    || MISSING="$MISSING site/rule_census.json"
  python3 -c "
import json,sys
d=json.load(open('$REPO/site/measured.json'))
sys.exit(0 if isinstance((d.get('field.withheld') or {}).get('value'), int) else 1)" \
    || MISSING="$MISSING site/measured.json"
  if [ -z "$MISSING" ]; then
    ok "the page claims records are dropped and counted, and both published files state the count"
  else
    bad "the page claims records are dropped and counted; these do not state a count:$MISSING"
  fi
else
  ok "site/field.html makes no drop-and-count claim (nothing to back)"
fi

echo "7. a CI account name is a dictionary word, and is not a leak"
# This section exists because CI was red on every push for seven findings that
# were all the English noun "runner". GitHub's macOS image is /Users/runner, the
# artifacts under site/ are generated on the operator's machine and committed,
# and the scan counted the word in published prose as the account name. A check
# that is always red is a check nobody reads.
CIHOME="$T/home/runner"
mkdir -p "$CIHOME"
CIDIR="$T/ci-artifacts"
mkdir -p "$CIDIR"
# the exact shape of the false positive: the word in prose, no path anywhere
printf 'the node runner\x27s own line was not in it, so the runner is blamed\n' \
  > "$CIDIR/prose.txt"
OUT="$(scan "$CIDIR" "$CIHOME" "")"; RC=$?
if [ $RC -eq 0 ]; then ok "the word 'runner' in prose is not reported as an account name"
else bad "a generic CI account name still reports prose as a leak: $OUT"; fi

# THE TWIN THAT MUST STILL BLOCK. Same directory, same scan, but the home path
# itself is present — the finding CI must never lose while the noun is ignored.
printf 'built at %s/work/x\n' "$CIHOME" > "$CIDIR/leaky.txt"
OUT="$(scan "$CIDIR" "$CIHOME" "")"; RC=$?
if [ $RC -ne 0 ]; then ok "the absolute home path is still reported under a generic account"
else bad "a real home path was missed because the account name was generic"; fi
case "$OUT" in *"leaky.txt: 1 absolute home path"*) ok "and the file carrying it is still named";;
  *) bad "the home path finding lost its filename: $OUT";; esac
rm -f "$CIDIR/leaky.txt"

# and the check must keep its teeth where the name is real, which is the
# operator's own machine — a distinctive account is still counted in prose.
REALHOME="$T/home/qzvtester2"
mkdir -p "$REALHOME"
printf 'a note that names qzvtester2 with no path at all\n' > "$CIDIR/bare.txt"
OUT="$(scan "$CIDIR" "$REALHOME" "")"; RC=$?
if [ $RC -ne 0 ]; then ok "a distinctive account name on its own is still a finding"
else bad "the bare-account-name check lost its teeth entirely: $OUT"; fi

echo
echo "publish redaction: $pass passed, $fail failed"
[ $fail -eq 0 ]
