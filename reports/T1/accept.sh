#!/usr/bin/env bash
# T1 acceptance test — "the project says what it is".
#
# Written BEFORE the round is implemented, by a session that is not allowed to
# implement it (protocol Gate 1). It is expected to be RED on the day it is
# written. Turning it green is the round's job, and the only honest way to turn
# it green is to change the documents it reads.
#
# Run from anywhere: it locates the repo root from its own location.
#   reports/T1/accept.sh   -> exit 0 = all five claims hold, exit 1 = at least one red

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

PASS_N=0
FAIL_N=0

pass() { printf 'PASS  %s\n' "$1"; PASS_N=$((PASS_N + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL_N=$((FAIL_N + 1)); }
note() { printf '      %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

README="$ROOT/README.md"
BENCH="$ROOT/BENCHMARK.md"
PKG="$ROOT/package.json"

for f in "$README" "$BENCH" "$PKG"; do
  [ -f "$f" ] || { printf 'FAIL  missing required file: %s\n' "$f"; exit 1; }
done

# ---------------------------------------------------------------------------
# CLAIM 1 — the repair number is ONE number, everywhere, with one meaning.
#
# Correct value: 2, and the qualification is identical wherever it appears:
# 2 on PLANNED breakage (expressjs/express @ a3714473, its own mocha suite as
# arbiter, 91 test files hash-locked) and 0 on UNPLANNED breakage.
#
# What must not survive: any bare "repairs held = 0" reading, and any
# "0 on real breakage" phrasing sitting in a planned-repair context, where it
# reads as a contradiction of the 2 rather than as the unplanned-breakage fact.
# ---------------------------------------------------------------------------
head_ "CLAIM 1 — repair count is a single, consistently qualified number (2 planned / 0 unplanned)"

# 1a. No bare-zero repair readings left in either file.
zero_re='repairs?[[:space:]_-]*held[^0-9]{0,40}\b0\b|\b0\b[[:space:]]+repairs?[[:space:]_-]*held|held[[:space:]]+0[[:space:]]+hash-locked[[:space:]]+repairs|repairs-held[[:space:]]*(is|=|:)[[:space:]]*0'
# A sentence that narrates the move itself ("has since gone 0 -> 2") is not a
# zero reading; it is the correction. Exempted.
zero_hits="$(grep -nEi "$zero_re" "$README" "$BENCH" \
  | grep -vE '0[[:space:]]*(->|-->|→|to)[[:space:]]*2' || true)"
if [ -z "$zero_hits" ]; then
  pass "1a no bare \"repairs held = 0\" reading remains in README.md / BENCHMARK.md"
else
  fail "1a a bare \"repairs held = 0\" reading still remains"
  printf '%s\n' "$zero_hits" | sed 's/^/      /'
fi

# 1b. "0 on real breakage" must not remain: "real" is the word that collides
#     with the 2 (those two were real repairs, on a real foreign project).
#     The honest word for what is still 0 is "unplanned".
realzero_hits="$(grep -nEi '\b0\b[^.]{0,20}on[[:space:]]+real[[:space:]]+breakage|real[[:space:]]+breakage[^.]{0,30}\b0\b' "$README" "$BENCH" || true)"
if [ -z "$realzero_hits" ]; then
  pass "1b no \"0 on real breakage\" phrasing left in a planned-repair context"
else
  fail "1b \"0 on real breakage\" still sits next to the repair claim"
  printf '%s\n' "$realzero_hits" | sed 's/^/      /'
fi

# 1c. Every numeric reading of "repairs held" that carries a bare count reads 2.
#     (Numbers that are plainly not the counter — dates, hashes, test totals —
#     are skipped; a bare small integer on such a line is the counter.)
bad_held="$(python3 - "$README" "$BENCH" <<'PY'
import re, sys
pat = re.compile(r"repairs?[\s_-]*held", re.I)
num = re.compile(r"(?<![\w.@/-])(\d{1,3})(?![\w.%/-])")
for path in sys.argv[1:]:
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        if not pat.search(line):
            continue
        if re.search(r"0\s*(->|-->|→|to)\s*2", line):
            continue  # narrates the correction, not a reading
        counts = [int(n) for n in num.findall(line)]
        if re.search(r"\btwo\b", line, re.I):
            counts.append(2)   # the number spelled out is still the number
        if counts and 2 not in counts:
            print(f"{path}:{i}: {line.rstrip()}")
PY
)"
if [ -z "$(printf '%s' "$bad_held" | tr -d '[:space:]')" ]; then
  pass "1c every numeric \"repairs held\" reading shows 2"
else
  fail "1c a numeric \"repairs held\" reading shows something other than 2"
  printf '%s\n' "$bad_held" | sed 's/^/      /'
fi

# 1e. The same zero written without the words "repairs held" — BENCHMARK.md §3
#     still argues the number that sells the product "is still 0" four lines
#     under a table that reads 2. One number means one number in prose too.
prose_zero="$(grep -nEi '(fix|repair)[^.]{0,90}(is )?still[[:space:]]+\**0\**|stays on this page as 0|as 0 until' "$README" "$BENCH" || true)"
if [ -z "$prose_zero" ]; then
  pass "1e no prose still argues the repair number is 0"
else
  fail "1e prose still argues the repair number is 0"
  printf '%s\n' "$prose_zero" | sed 's/^/      /'
fi

# 1d. The qualification travels with the number, in BOTH files: planned/planted
#     breakage carries the 2, and unplanned breakage is explicitly 0.
for f in "$README" "$BENCH"; do
  b="$(basename "$f")"
  if grep -qEi '(planned|planted)' "$f"; then
    pass "1d $b says the 2 are on planned/planted breakage"
  else
    fail "1d $b never qualifies the 2 as planned/planted breakage"
  fi
  if grep -qEi 'unplanned[^.]{0,60}\b0\b|\b0\b[^.]{0,60}unplanned' "$f"; then
    pass "1d $b states unplanned breakage = 0"
  else
    fail "1d $b does not state \"0 on unplanned breakage\""
    note "expected a sentence pairing the word 'unplanned' with 0, e.g. \"0 on unplanned breakage\""
  fi
done

# ---------------------------------------------------------------------------
# CLAIM 2 — README carries no install command for a package that is not published.
# ---------------------------------------------------------------------------
head_ "CLAIM 2 — no unpublished install command in README"

install_hits="$(grep -nE 'npm[[:space:]]+(i|install)[[:space:]]+-g[[:space:]]+rabadon' "$README" || true)"
if [ -z "$install_hits" ]; then
  pass "2a README has no \`npm i -g rabadon\` / \`npm install -g rabadon\`"
else
  fail "2a README still tells the reader to install an unpublished package"
  printf '%s\n' "$install_hits" | sed 's/^/      /'
fi

status_hits="$(grep -nEi 'portable[^.]{0,20}npm i -g[^.]{0,40}install with prebuilt binaries' "$README" || true)"
if [ -z "$status_hits" ]; then
  pass "2b Status section no longer claims \"portable \`npm i -g\` install with prebuilt binaries\""
else
  fail "2b Status section still claims the portable \`npm i -g\` install"
  printf '%s\n' "$status_hits" | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
# CLAIM 3 — "Supervise your coding agent" is gone from the repo.
#
# Excluded: .git/, reports/ (this test and the round's own records quote the
# string in order to forbid it) and PROTOCOL-T1-T8.md (the spec that orders its
# removal, quoted there three times). node_modules/ is build output.
# ---------------------------------------------------------------------------
head_ "CLAIM 3 — \"Supervise your coding agent\" removed repo-wide"

# Searched over git-TRACKED files: that is what "the repo" means to a reader who
# clones it. Untracked local state (.rabadon/sessions/*.json records the very
# grep that looks for the phrase) is not shipped and is not evidence.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  sup_hits="$(git -C "$ROOT" ls-files \
    | grep -v -e '^reports/' -e '^PROTOCOL-T1-T8\.md$' \
    | tr '\n' '\0' \
    | xargs -0 grep -nIi 'Supervise your coding agent' 2>/dev/null || true)"
else
  sup_hits="$(grep -rniI 'Supervise your coding agent' "$ROOT" \
    --exclude-dir=.git \
    --exclude-dir=.rabadon \
    --exclude-dir=reports \
    --exclude-dir=node_modules \
    --exclude=PROTOCOL-T1-T8.md || true)"
fi
if [ -z "$sup_hits" ]; then
  pass "3 the phrase \"Supervise your coding agent\" appears nowhere outside .git/, reports/ and the protocol"
else
  fail "3 the phrase \"Supervise your coding agent\" is still in the repo"
  printf '%s\n' "$sup_hits" | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
# CLAIM 4 — the canonical sentence is in README.md and package.json, and the
# keywords say what the product is.
#
# Canonical: rabadon catches your coding agent's error before it compounds, and
# fixes it. Checked by its two load-bearing halves rather than by exact string
# equality, so punctuation/typography cannot make a true document read false —
# but BOTH halves are required.
# ---------------------------------------------------------------------------
head_ "CLAIM 4 — canonical sentence + honest keywords"

# First real paragraph of the README: skip the H1, badges, blank lines, images.
first_para="$(awk '
  /^[[:space:]]*$/ { next }
  /^#/ { next }
  /^!\[/ { next }
  /^\[!\[/ { next }
  /^<sub>/ { next }
  { print; exit }
' "$README")"

if printf '%s' "$first_para" | grep -qiE "coding agent" \
   && printf '%s' "$first_para" | grep -qiE "before it compounds" \
   && printf '%s' "$first_para" | grep -qiE "fix(es)? it"; then
  pass "4a README's first paragraph is the canonical sentence"
else
  fail "4a README's first paragraph is not the canonical sentence"
  note "got: ${first_para:0:160}"
fi

desc="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["description"])' "$PKG")"
if printf '%s' "$desc" | grep -qiE "coding agent" \
   && printf '%s' "$desc" | grep -qiE "before it compounds" \
   && printf '%s' "$desc" | grep -qiE "fix(es)? it"; then
  pass "4b package.json description is aligned with the canonical sentence"
else
  fail "4b package.json description is not aligned with the canonical sentence"
  note "got: ${desc:0:160}"
fi

# keywords: parsed as JSON, never grepped.
kw_report="$(python3 - "$PKG" <<'PY'
import json, sys
kw = json.load(open(sys.argv[1])).get("keywords", [])
kw = [str(k).strip().lower() for k in kw]
banned  = ["guardrails", "sandbox", "pipeline"]
require = ["compound-error", "agent-recovery"]
for b in banned:
    print(("FAIL" if b in kw else "PASS"), f"keyword {b!r} must be absent")
for r in require:
    print(("PASS" if r in kw else "FAIL"), f"keyword {r!r} must be present")
print("INFO keywords =", ", ".join(kw) if kw else "(none)")
PY
)"
while IFS= read -r line; do
  case "$line" in
    PASS*) pass "4c ${line#PASS }" ;;
    FAIL*) fail "4c ${line#FAIL }" ;;
    INFO*) note "${line#INFO }" ;;
  esac
done <<< "$kw_report"

# ---------------------------------------------------------------------------
# CLAIM 5 — `make test` is green. Actually run it; report the tail either way.
# ---------------------------------------------------------------------------
head_ "CLAIM 5 — make test is green"

MT_LOG="$(mktemp -t rabadon-t1-maketest)"
MT_START=$(date +%s)
set +e
make test > "$MT_LOG" 2>&1
MT_RC=$?
set -e
MT_SECS=$(( $(date +%s) - MT_START ))

if [ "$MT_RC" -eq 0 ]; then
  pass "5 \`make test\` exited 0 (${MT_SECS}s)"
else
  fail "5 \`make test\` exited $MT_RC (${MT_SECS}s)"
fi
note "last lines of \`make test\`:"
tail -n 15 "$MT_LOG" | sed 's/^/      | /'
note "full log: $MT_LOG"

# ---------------------------------------------------------------------------
printf '\n== T1 acceptance: %d green, %d red\n' "$PASS_N" "$FAIL_N"
if [ "$FAIL_N" -gt 0 ]; then
  printf 'T1 NOT ACCEPTED\n'
  exit 1
fi
printf 'T1 ACCEPTED\n'
exit 0
