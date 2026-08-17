#!/bin/bash
# field_census_test.sh — a rule the ledger says was written has to still exist.
#
# The ledger records REPAIR_OK with `step: new gate: <id>` the moment the engine
# authors a rule after an incident, and site/field_stats.py counts those events.
# Counting the EVENT and printing it as "rules the engine wrote itself" quietly
# assumes the write landed. One of them did not: the ledger carries
# `release-workflow-needs-test-gate`, and that id appears in no guard.json on
# this machine. It was going to be published as one of twelve live rules while
# being a rule that cannot fire, in any repository, ever — which is the exact
# shape of claim this whole project exists to refuse.
#
# So the census is not "how many did it write". It is "how many of the ones it
# says it wrote are in a guard file right now", and the gap is printed rather
# than closed by rounding.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

FAKEHOME="$T/censushome"
mkdir -p "$FAKEHOME/.rabadon/spool" "$T/repo/site"
cp "$REPO/site/field_stats.py" "$T/repo/site/field_stats.py"
# the redactor moved out of field_stats.py into site/redact.py so the census
# generator could publish through the same one; the isolated site/ needs both
# files or the script under test cannot import itself into existence.
cp "$REPO/site/redact.py" "$T/repo/site/redact.py"
# field_stats.py imports site/identity.py to answer what a project label
# denotes; a fixture without it tests an ImportError, not a generator.
cp "$REPO/site/identity.py" "$T/repo/site/identity.py"
cp "$REPO/site/non-projects.txt" "$T/repo/site/non-projects.txt"

# three rules the ledger says were authored after an incident
python3 - "$FAKEHOME/.rabadon/spool/2026-08-03.jsonl" <<'PY'
import json, sys
rows = [
    {"ev": "REPAIR_OK", "pipe": "alpha:session", "ts": 1, "step": "new gate: rule-that-lives",
     "repair_kind": "rule"},
    {"ev": "REPAIR_OK", "pipe": "beta:session", "ts": 2, "step": "new gate: rule-in-a-nested-repo",
     "repair_kind": "rule"},
    {"ev": "REPAIR_OK", "pipe": "alpha:session", "ts": 3, "step": "new gate: rule-that-never-landed",
     "repair_kind": "rule"},
]
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY

# two guard files carry two of them. the third exists nowhere.
mkdir -p "$FAKEHOME/alpha/.rabadon" "$FAKEHOME/nest/beta/.rabadon"
cat > "$FAKEHOME/alpha/.rabadon/guard.json" <<'JSON'
{"project":"alpha","bash":[{"id":"rule-that-lives","deny":"x","why":"w","authoredBy":"incident"}]}
JSON
cat > "$FAKEHOME/nest/beta/.rabadon/guard.json" <<'JSON'
{"project":"beta","bash":[{"id":"rule-in-a-nested-repo","deny":"y","why":"w","authoredBy":"incident"}]}
JSON

echo "field census — a rule that was written and is not there is not a rule"
echo

OUT="$T/run.log"
HOME="$FAKEHOME" python3 "$T/repo/site/field_stats.py" --write >"$OUT" 2>&1 || {
  bad "field_stats.py exited non-zero"; sed -n '1,20p' "$OUT"; }

MJ="$T/repo/site/measured.json"
if [ ! -f "$MJ" ]; then
  bad "no measured.json was written"
else
  python3 - "$MJ" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
out = []

rules = (d.get("field.rules_list") or {}).get("value")
if rules is None:
    out.append("FAIL no field.rules_list")
else:
    by = {r["rule"]: r for r in rules}
    if len(rules) != 3:
        out.append("FAIL field.rules_list has %d entries, expected 3" % len(rules))
    else:
        out.append("OK   all three authoring events are still listed")
    for name, want in (("rule-that-lives", True),
                       ("rule-in-a-nested-repo", True),
                       ("rule-that-never-landed", False)):
        r = by.get(name)
        if r is None:
            out.append("FAIL %s is missing from field.rules_list" % name)
        elif "live" not in r:
            out.append("FAIL %s carries no `live` verdict" % name)
        elif bool(r["live"]) != want:
            out.append("FAIL %s: live=%s, expected %s" % (name, r["live"], want))
        else:
            out.append("OK   %-24s live=%s" % (name, r["live"]))
    nested = by.get("rule-in-a-nested-repo") or {}
    if nested.get("live") and nested.get("in") != "beta":
        out.append("FAIL nested guard not attributed to its project: in=%r" % nested.get("in"))
    elif nested.get("live"):
        out.append("OK   a guard two directories down was found and attributed")

live = (d.get("field.rules_live") or {}).get("value")
if live is None:
    out.append("FAIL no field.rules_live number")
elif live != 2:
    out.append("FAIL field.rules_live is %r, expected 2" % live)
else:
    out.append("OK   field.rules_live = 2 of 3")

written = (d.get("field.rules_written") or {}).get("value")
if written != 3:
    out.append("FAIL field.rules_written is %r, expected 3 -- the count of what it WROTE must not shrink" % written)
else:
    out.append("OK   field.rules_written still counts every authoring event")

print("\n".join(out))
sys.exit(1 if any(l.startswith("FAIL") for l in out) else 0)
PY
  rc=$?
  if [ $rc -eq 0 ]; then ok "the census separates written from live"
  else bad "the census does not hold"; fi
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
