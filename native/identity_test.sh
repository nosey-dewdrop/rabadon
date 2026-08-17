#!/usr/bin/env bash
# identity_test.sh — a label is collapsed for an identity reason or not at all.
#
# WHAT IS BEING GUARDED HERE. site/identity.py exists because the gate writes
# `project = basename(cwd)` and a directory basename is not a project identity:
# the published column carried the home directory, a system scratch path,
# rabadon's own probe trees, the directory that contains the projects, and the
# residue of a scrubbed name — 72 "project" names of which a third named no
# project. Collapsing those is a correctness fix.
#
# It is also, from one step away, indistinguishable from the move this product
# exists to refuse: the same file, widened one prefix at a time, turns a red
# disclosure gate green without a single disclosure decision being made. So the
# rules are tested from BOTH sides here. Every collapse rule has a case that
# proves it fires, and — the half that matters — there are cases that prove it
# does NOT fire on an ordinary project name, that an unknown label survives as a
# name, and that the committed list cannot quietly grow into a blanket.
#
# The suite is red if a rule stops firing AND red if a rule starts firing on
# something it has no business touching.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
MOD="$REPO/site/identity.py"
[ -f "$MOD" ] || { echo "missing $MOD"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# the module is asked one question at a time, through the same entry point the
# generators use, so this suite cannot pass against a private helper.
id() { # id <label> [non-projects file] -> "kind name"
  RABADON_NON_PROJECTS="${2:-$REPO/site/non-projects.txt}" \
  python3 -c 'import sys, os; sys.path.insert(0, os.path.join(sys.argv[1], "site"));
import identity
k, n = identity.identity_of(sys.argv[2])
print(k, n)' "$REPO" "$1" 2>&1
}

want() { # want <label> <expected "kind name"> <description> [list]
  local got; got="$(id "$1" "${4:-}")"
  [ "$got" = "$2" ] && ok "$3" || bad "$3 (got: $got, wanted: $2)"
}

echo "identity: a label is collapsed for an identity reason, or not at all"

# ---------- 1. what a project name is, and that it is left alone ----------
# The first section is the one that can catch a filter growing into a blanket.
want "rabadon"                "project rabadon"      "an ordinary project name is a project, unchanged"
want "rabadon:session"        "project rabadon"      "the :session suffix is a pipe spelling, not part of the name"
want "damla_portfolio"        "project damla_portfolio" "an underscore is a real directory character and is NOT rewritten"
want "nosey-dewdrop.github.io" "project nosey-dewdrop.github.io" "a dot INSIDE a name is part of the name"
want "psikoloji-kitabi"       "project psikoloji-kitabi" "a name that resembles nothing on any list survives as a name"
want "not-a-name-anyone-knows" "project not-a-name-anyone-knows" \
     "an UNKNOWN label stays a project name: the fail-safe direction is 'in front of a human'"

# ---------- 2. one project, one spelling ----------
# `idea garden` and `just ballet` arrive from a guard file's self-declared
# `project` string, typed beside directories called `idea-garden`, `just-ballet`.
# Publishing both spellings counts one project twice.
want "idea garden"            "project idea-garden"  "a space becomes a dash: two spellings of one project collapse"
want "just ballet"            "project just-ballet"  "and the same for the second one"
want "  spaced  out  "        "project spaced-out"   "leading, trailing and repeated whitespace all normalise"

# ---------- 3. the residue of a redaction is not a name ----------
want "(withheld)"             "withheld (withheld)"  "the marker itself stays the marker"
want "(withheld)-showcase"    "withheld (withheld)"  "what a scrub left behind is residue, not a second project"
want "showcase-(withheld)"    "withheld (withheld)"  "wherever in the label the marker lands"

# ---------- 4. the markers survive a second pass ----------
# A generator that runs over its own output must not turn a marker into a name.
want "(lab)"                  "lab (lab)"            "(lab) re-resolves to itself"
want "(no project)"           "none (no project)"    "(no project) re-resolves to itself"

# ---------- 5. labels that name no project ----------
want "-"                      "none (no project)"    "a record with no project recorded says so"
want ""                       "none (no project)"    "and so does an empty label"
want "home"                   "none (no project)"    "the home directory is not a project"
want ".claude"                "none (no project)"    "a dot-directory is configuration, not a project"
want ".reachprobe"            "none (no project)"    "including a dotted probe tree"
want "tmp"                    "none (no project)"    "the system scratch area is not a project"

# ---------- 6. the laboratories: trees rabadon makes to exercise itself ----------
want "rbprobe.nqskoD"         "lab (lab)"            "a probe tree with an mktemp suffix"
want "rbd-toggle.IZCtM2"      "lab (lab)"            "and the other probe family"
want "rabadon-bench-475q9ra6" "lab (lab)"            "the bench harness's twelve scratch repos"
want "tmp.Xy12ab"             "lab (lab)"            "mktemp's own spelling"
want "A:session"              "lab (lab)"            "the repair harness's scratch repository"
want "vibecoded-demo"         "lab (lab)"            "the demo"
want "goose:session"          "fixture goose"        "a public repo visited to be measured keeps its name"

# ---------- 7. the committed list, and the fact that it is a LIST ----------
want "fixed" "lab (lab)" "a label the committed list speaks for, with its evidence beside it"

printf 'none  onlyhere\n' > "$T/list.txt"
want "onlyhere" "none (no project)" "a label resolves through the list it is actually given" "$T/list.txt"
want "fixed"    "project fixed"     "and NOT through a list that does not name it — no rule is baked into the code" "$T/list.txt"

: > "$T/empty.txt"
want "spool" "project spool" \
     "with an empty list every structural rule still holds and nothing else collapses" "$T/empty.txt"

# the format is checked, because a line that does not parse is a line that
# silently does nothing — the filter would look bigger than it is.
BADLINES="$(grep -vE '^[[:space:]]*(#|$)' "$REPO/site/non-projects.txt" \
            | grep -vcE '^(lab|none)[[:space:]]+[^[:space:]]+[[:space:]]*$' || true)"
[ "$BADLINES" = "0" ] \
  && ok "every line of site/non-projects.txt parses as <lab|none> <label>" \
  || bad "$BADLINES line(s) in site/non-projects.txt do not parse and do nothing"

# and it stays small enough to read. This is not a style rule: the list is the
# one place where "collapse it because the number is inconvenient" could hide,
# and the defence is that a human can read all of it in one sitting.
ENTRIES="$(grep -cE '^[[:space:]]*(lab|none)[[:space:]]' "$REPO/site/non-projects.txt" || true)"
[ "$ENTRIES" -le 20 ] \
  && ok "the committed list is $ENTRIES entries — small enough that every one can be argued" \
  || bad "the committed list has grown to $ENTRIES entries: that is a blanket, not a set of decisions"

# every entry carries a reason. A line with no comment above it is a collapse
# nobody has to justify, which is how a filter becomes a habit.
UNEXPLAINED="$(python3 - "$REPO/site/non-projects.txt" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
bad = 0
for i, line in enumerate(lines):
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    # walk back over blank lines to the nearest comment block
    j = i - 1
    while j >= 0 and not lines[j].strip():
        j -= 1
    if j < 0 or not lines[j].strip().startswith("#"):
        bad += 1
print(bad)
PY
)"
[ "$UNEXPLAINED" = "0" ] \
  && ok "every entry has its evidence written above it" \
  || bad "$UNEXPLAINED entr(y|ies) in site/non-projects.txt have no reason written above them"

# ---------- 8. identity comes from where a project LIVES ----------
# A guard file declares a `project` key about itself and the census published
# that key. It is a nickname: 10 of 63 guards on this machine declare a name
# that is not their directory's, and four of those are a second spelling of a
# project the ledger already names the other way.
GP="$(python3 -c 'import sys, os; sys.path.insert(0, os.path.join(sys.argv[1], "site"));
import identity; print(identity.from_guard_path(sys.argv[2]))' \
  "$REPO" "/x/y/idea-garden/.rabadon/guard.json")"
[ "$GP" = "idea-garden" ] \
  && ok "a guard's identity is the directory it lives in, not the name it declares" \
  || bad "from_guard_path gave '$GP', wanted 'idea-garden'"

# ---------- 9. and the whole point: it must be able to turn red ----------
# If site/identity.py stopped collapsing anything at all, every case in
# sections 2-7 above would fail. This asserts the inverse property in one line
# so the suite cannot pass by accident on a module that answers nothing: five
# labels, three identities — the home directory and a dot-directory and the
# scratch area are one answer, the two probe trees are another, and the project
# is itself.
N="$(python3 -c 'import sys, os; sys.path.insert(0, os.path.join(sys.argv[1], "site"));
import identity
labels = ["home", ".claude", "tmp", "rbprobe.x", "rabadon"]
print(len({identity.identity_of(x)[1] for x in labels}))' "$REPO")"
[ "$N" = "3" ] \
  && ok "five labels resolve to three identities — the module answers, it does not pass through" \
  || bad "five labels resolved to $N identities, wanted 3"

echo "identity: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] || exit 1
