#!/usr/bin/env bash
# published_allowlist_test.sh — a project name is published because somebody
# decided it may be, never because nobody noticed.
#
# WHY THIS FILE EXISTS. site/redact.py withholds names on a PRIVATE list at
# ~/.rabadon/redact/projects.txt, kept outside the tree on purpose: committing a
# list of private repository names to a public repo publishes exactly what the
# list is meant to hide. That design is correct and it stays. Its consequence is
# not: the check becomes default-ALLOW, and it cannot run anywhere but one
# machine. CI has no private list, so name-based withholding does nothing there
# and publish_redaction_test.sh's section 6 passes on BLINDNESS.
#
# Measured 2026-08-17, before this file existed: 58 distinct project names were
# published in site/ artifacts and ZERO were on the private list. The one leak
# that was caught (`no-blanket-add-stitchu`) was caught only because that term
# happened to be listed, and only on the operator's box.
#
# So the question is inverted here, against site/published-projects.txt, which
# is PUBLIC and committed: not "is this name secret" but "was this name
# allowed". CI can enforce that without ever learning a private name.
#
# The last case runs the checker against the REAL site/ and is expected to be
# red until the operator has triaged the list. That is the point of it: an
# allowlist seeded with everything already published would be a check that
# cannot turn red.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
CHECK="$REPO/site/allowlist.py"
[ -f "$CHECK" ] || { echo "missing $CHECK"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

echo "published allowlist: a name is published by decision, not by default"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/site"

# a fixture the checker can read: one allowed name, one that is not.
printf '{"rules":[{"project":"rabadon","id":"a"},{"project":"hushproj","id":"b"}]}\n' \
  > "$T/site/rule_census.json"
printf '{"project":"rabadon","ok":1}\n{"project":"soft_hush","ok":1}\n' \
  > "$T/site/field.jsonl"
printf 'rabadon\n' > "$T/allow.txt"

run() { RABADON_SITE_DIR="$T/site" RABADON_ALLOWLIST="$1" python3 "$CHECK" 2>&1; }
rc()  { RABADON_SITE_DIR="$T/site" RABADON_ALLOWLIST="$1" python3 "$CHECK" >/dev/null 2>&1; echo $?; }

# ---------- 1. it can turn red, which is the only reason to have it ----------
OUT="$(run "$T/allow.txt")"
[ "$(rc "$T/allow.txt")" = "1" ] \
  && ok "an off-list project name fails the check (exit 1)" \
  || bad "an off-list name passed: the check cannot turn red"
case "$OUT" in *hushproj*) ok "and the offending name is NAMED, so the human knows what to decide";;
  *) bad "the failure does not say which name: $OUT";; esac
case "$OUT" in *soft_hush*) ok "it reads the JSONL artifact too, not only the JSON one";;
  *) bad "a name that appears only in field.jsonl was missed";; esac
case "$OUT" in *rabadon*) bad "an allowed name was reported as an offender";;
  *) ok "the allowed name is not reported — this is a decision gate, not a name census";; esac

# ---------- 2. it goes green when every name is decided ----------
printf 'rabadon\nhushproj\nsoft_hush\n' > "$T/allow-all.txt"
[ "$(rc "$T/allow-all.txt")" = "0" ] \
  && ok "with every published name on the list the check passes (exit 0)" \
  || bad "a fully decided artifact still failed: $(run "$T/allow-all.txt")"

# ---------- 3. comments and blanks are not names ----------
printf '# a comment\n\nrabadon   \n\thushproj\nsoft_hush # trailing\n' > "$T/allow-cmt.txt"
[ "$(rc "$T/allow-cmt.txt")" = "0" ] \
  && ok "comments, blank lines and surrounding space are not part of a name" \
  || bad "the list parser choked on comments or whitespace"

# ---------- 4. a missing list FAILS CLOSED ----------
# The failure mode that would make this whole file decorative: no list read as
# "everything is allowed". Then a deleted or misspelled path would publish the
# lot and report success.
[ "$(rc "$T/nope.txt")" = "1" ] \
  && ok "a missing allowlist allows NOTHING — it fails closed, not open" \
  || bad "a missing allowlist passed: the gate opens when its own config vanishes"

# ---------- 5. an empty list is not a wildcard either ----------
: > "$T/empty.txt"
[ "$(rc "$T/empty.txt")" = "1" ] \
  && ok "an empty allowlist allows nothing either" \
  || bad "an empty allowlist passed everything"

# ---------- 6. the real site/, which is the whole point ----------
REALRC=$(cd "$REPO" && python3 "$CHECK" >/dev/null 2>&1; echo $?)
REALOUT=$(cd "$REPO" && python3 "$CHECK" --list 2>&1 | grep -E "off-list$")
if [ "$REALRC" = "0" ]; then
  ok "every project name published under site/ is on the allowlist"
else
  bad "site/ publishes project names nobody decided to publish: $REALOUT"
  echo "          triage them: python3 site/allowlist.py --list"
  echo "          a name that may be public goes in site/published-projects.txt"
  echo "          with its reason; the rest belong on the private withhold list."
fi

echo ""
echo "published allowlist: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
