#!/usr/bin/env bash
# guard_delete_test.sh — THE LAW IS NOT SCRATCH.
#
# WHAT WAS MEASURED. F3f went looking for a reported false positive in
# `no-shell-rewrite-of-guard-or-promise` and found the opposite defect in the
# same rule. Against the REAL binary, with the live rule copied verbatim into a
# fixture (reports/kosu/kanit/f3f/k4-rm-probe.txt):
#
#     mv .rabadon/guard.json /tmp/x     -> rc=2  REFUSED
#     rm .rabadon/guard.json            -> rc=0  ALLOWED
#     rm -f .rabadon/guard.json         -> rc=0  ALLOWED
#     rm .rabadon/promise.json          -> rc=0  ALLOWED
#
# and the rule's own regex MATCHES all four (checked directly against the
# pattern). So the refusal was not lost in the pattern; it was suppressed after
# the match, by native/rules.h `all_targets_disposable`.
#
# That suppression is right and was measured right: a rule that spells a path
# reads a SPELLING, so `rm -rf /tmp/proj1-build` looked like "outside the
# project" to nine of twenty refusals in precision_fixture.jsonl while the
# compiled law underneath resolved the same target and allowed it. The fix was
# to let the resolver answer: if every target of a delete lands inside the
# project, the path rule was answering a different question.
#
# It is wrong for exactly two files. `.rabadon/guard.json` and
# `.rabadon/promise.json` are inside the project BY CONSTRUCTION — they are the
# project's own copy of the law — so "the target is contained" is not evidence
# that deleting them is disposable, it is the definition of the thing the rule
# was authored for (incident 2026-08-03). The suppression turned the rule's
# whole `rm` arm off, silently, and left `mv` refusing so that nothing looked
# broken.
#
# So the narrowing here narrows a SUPPRESSION: it can only ever make the gate
# refuse more, never less, and the second arm below proves the original false
# positive the suppression exists for is still suppressed.
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOTDIR="$(cd "$HERE/.." && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"

PASSN=0; FAIL=0
pass() { printf '  ok   - %s\n' "$1"; PASSN=$((PASSN + 1)); }
fail() { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }
[ -x "$GATE" ] || { printf 'guard_delete: no gate binary at %s — run make first\n' "$GATE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'guard_delete: python3 is required\n' >&2; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/rbgd.XXXXXX")"
trap 'rm -rf "$T"' EXIT
RD="$T/rd"; mkdir -p "$RD"; : > "$RD/enabled"
P="$T/proj"; mkdir -p "$P/.rabadon" "$P/.git"
printf 'ref: refs/heads/main\n' > "$P/.git/HEAD"

# The rule under test is copied out of the LIVE guard.json by a JSON reader, so
# this suite cannot drift away from what is actually enforced, and cannot be
# made green by editing a copy of the rule.
python3 - "$ROOTDIR/.rabadon/guard.json" "$P/.rabadon/guard.json" <<'PY'
import json, sys
src = json.load(open(sys.argv[1]))
rule = [r for r in src.get("bash", []) if r.get("id") == "no-shell-rewrite-of-guard-or-promise"]
extra = [r for r in src.get("bash", []) if r.get("id") == "no-rm-rf-outside"]
assert rule, "no-shell-rewrite-of-guard-or-promise is gone from the live guard.json"
assert extra, "no-rm-rf-outside is gone from the live guard.json"
json.dump({"project": "gd", "bash": rule + extra, "protectedPaths": []},
          open(sys.argv[2], "w"), indent=2)
PY
# the scratch directory the suppression exists to protect
mkdir -p "$T/scratchproj/build" "$T/scratchproj/.git"
printf 'ref: refs/heads/main\n' > "$T/scratchproj/.git/HEAD"

verdict() { # verdict <cwd> <command> -> ALLOW|REFUSE
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"gd","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$1" "$2" \
    | env RABADON_DIR="$RD" RABADON_JUDGE=0 RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1
  [ "$?" = "2" ] && printf 'REFUSE' || printf 'ALLOW'
}

echo "guard_delete: deleting the law is not deleting scratch"

# ---------------------------------------------------------------------------
# ARM 1 — the law itself. Every one of these must be REFUSED.
while IFS='|' read -r cmd label; do
  [ -n "$cmd" ] || continue
  v="$(verdict "$P" "$cmd")"
  [ "$v" = "REFUSE" ] && pass "refused: $label" \
                      || fail "ALLOWED: $label — the rule's rm arm is suppressed again"
done <<'CMDS'
rm .rabadon/guard.json|rm of the project's own guard.json
rm -f .rabadon/guard.json|rm -f of the guard
rm ./.rabadon/guard.json|the same file spelled with ./
rm .rabadon/promise.json|rm of the promise
rm -rf .rabadon/guard.json .rabadon/promise.json|both at once
mv .rabadon/guard.json /tmp/x|mv, which was refused all along
CMDS

# ---------------------------------------------------------------------------
# ARM 2 — THE TWIN ARM. The false positive the suppression was built for has to
# stay suppressed, or this is not a narrowing, it is a revert. Deleting real
# scratch inside a project must still be allowed.
while IFS='|' read -r cmd label; do
  [ -n "$cmd" ] || continue
  v="$(verdict "$T/scratchproj" "$cmd")"
  [ "$v" = "ALLOW" ] && pass "still allowed: $label" \
                     || fail "REFUSED: $label — the narrowing became a false positive"
done <<'CMDS'
rm -rf build|the project's own build directory
rm -rf ./build|the same, spelled with ./
rm -f README.md|an ordinary file in the tree
CMDS

# ---------------------------------------------------------------------------
# ARM 3 — the read-only shapes stay read-only. §4.3: a false positive kills the
# product, and the reported one for this rule is checked here every run rather
# than in a report nobody re-runs.
while IFS='|' read -r cmd label; do
  [ -n "$cmd" ] || continue
  v="$(verdict "$P" "$cmd")"
  [ "$v" = "ALLOW" ] && pass "read-only stays allowed: $label" \
                     || fail "FALSE POSITIVE: $label"
done <<'CMDS'
cat .rabadon/guard.json|cat
grep -n "deny" .rabadon/guard.json|grep -n
grep -in "deny" .rabadon/guard.json|grep with an -i flag
git diff .rabadon/guard.json|git diff
python3 -m json.tool .rabadon/guard.json|python3 reading it
sed -n '1,5p' .rabadon/guard.json|sed WITHOUT -i
CMDS

# ---------------------------------------------------------------------------
# ARM 4 — a delete OUTSIDE the project is still refused by the rule that owns
# that job, so nothing here traded one hole for another.
v="$(verdict "$T/scratchproj" 'rm -rf /etc/somewhere')"
[ "$v" = "REFUSE" ] && pass "a recursive delete outside the project is still refused" \
                    || fail "a delete outside the project got through"

printf 'guard_delete: %d passed, %d failed\n' "$PASSN" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
