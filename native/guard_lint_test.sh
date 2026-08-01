#!/usr/bin/env bash
# guard_lint_test.sh — `rabadon lint` must see a typo WHERE TYPOS ACTUALLY ARE.
#
# docs/commands.md sells lint as the trust step: "Validate guard.json: unknown
# keys, uncompilable regex. Run this before trusting a hand-edited guard."
# `rabadon init` gates hook installation on the same check. So lint calling a
# file valid is the sentence a stranger acts on.
#
# The unknown-key walk only looked at depth 1. That caught a top-level typo
# ("protectedPathz") and was blind one level down, inside a rule object — which
# is where the author is actually typing. A rule written
#   { "id": "no-wrangler-deploy", "denies": "...", "why": "..." }
# is valid JSON, carries an id and a why, reads as enforced, and the gate
# ignores it completely: parse_rules keeps only rules whose pattern key is
# present and non-empty, and drops the rest without a word. Measured before the
# fix: gate exit 0 (allow) on `npx wrangler deploy`, lint "is valid", exit 0.
# That is the exact failure the command's own comment says it was built to end
# ("the gate would OBSERVE where the author meant it to BLOCK"), surviving one
# nesting level down.
#
# Two halves, both required (a negative assertion alone rots — rename the
# message and it passes forever):
#   POSITIVE — a broken rule makes lint exit non-zero AND print the rule's name.
#   NEGATIVE — every guard that is actually FINE still lints clean, including
#              this repo's own guard.json and the keys `pack import` and
#              incident-authoring stamp onto real rules (source, authoredBy,
#              incidentAt). A linter that cries wolf gets switched off.
#
# python3, never `grep -P`: BSD grep on macOS has no -P, exits 2, and the shell
# reads that as "no match" — a check that never runs and always passes.
set -u
cd "$(dirname "$0")/.."

BIN=./native/rabadon-gate
[ -x "$BIN" ] || { echo "guard lint: build first (make native/rabadon-gate)"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }

TMP=$(mktemp -d /tmp/rabadon-guard-lint.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
# lint reads <dir>/.rabadon/guard.json and nothing else, but keep the run out of
# the real home on principle: no suite may depend on whoever is at the machine.
export HOME="$TMP/home"; mkdir -p "$HOME"

# write a guard from stdin into a fresh project dir, echo the dir
guard() {
  d=$(mktemp -d "$TMP/proj.XXXXXX"); mkdir -p "$d/.rabadon"
  cat > "$d/.rabadon/guard.json"
  # every fixture must be VALID JSON — otherwise the test proves nothing about
  # a typo a JSON parser would have caught for free.
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$d/.rabadon/guard.json" \
    || { echo "  FIXTURE NOT VALID JSON: $d"; exit 1; }
  echo "$d"
}

OUT=""; RC=0
lint() { OUT=$("$BIN" --lint "$1" 2>&1); RC=$?; }

# assert lint refused AND named the rule. `says` is checked with python3 on the
# captured text so a pattern change fails loudly instead of silently matching.
says() { python3 -c "import sys; sys.exit(0 if sys.argv[1] in sys.stdin.read() else 1)" "$1" <<<"$OUT"; }

refused_naming() { # $1=rule name that must appear  $2=label
  if [ "$RC" -eq 0 ]; then bad "$2 — lint said valid (exit 0)"; return; fi
  if says "$1"; then ok "$2 — exit $RC and names \"$1\""
  else bad "$2 — exit $RC but never named \"$1\": $OUT"; fi
}

# ---------------------------------------------------------------- A. the fix
# A1 — the one-letter typo. "denies" instead of "deny".
A1=$(guard <<'EOF'
{
  "project": "lint-fixture",
  "bash": [
    { "id": "no-wrangler-deploy", "denies": "npx\\s+wrangler\\s+deploy", "why": "deploys go through CI" }
  ]
}
EOF
)
lint "$A1"; refused_naming "no-wrangler-deploy" 'bash rule with "denies" is refused'
says 'denies' && ok 'the message quotes the offending key ("denies")' \
               || bad "message should quote the unknown key: $OUT"

# A2 — the same typo one section over: "matches" for "match".
A2=$(guard <<'EOF'
{
  "project": "lint-fixture",
  "protectedPaths": [
    { "id": "core-frozen", "matches": "^src/core/.*", "why": "kernel subtree" }
  ]
}
EOF
)
lint "$A2"; refused_naming "core-frozen" 'protectedPaths rule with "matches" is refused'

# A3 — no pattern key at all. Valid JSON, has id and why, matches nothing.
A3=$(guard <<'EOF'
{
  "project": "lint-fixture",
  "bash": [
    { "id": "no-pattern-at-all", "why": "the author never wrote the regex" }
  ]
}
EOF
)
lint "$A3"; refused_naming "no-pattern-at-all" 'rule with no pattern key is refused'

# A4 — an unknown key ALONGSIDE a working deny. The rule fires, but the author
# thinks that extra key does something. It does not.
A4=$(guard <<'EOF'
{
  "project": "lint-fixture",
  "bash": [
    { "id": "no-prod-deploy", "deny": "deploy\\s+--prod", "why": "CI only", "severity": "high" }
  ]
}
EOF
)
lint "$A4"; refused_naming "no-prod-deploy" 'dead extra key next to a live deny is refused'

# A5 — mis-targeted key: a path key inside bash. The gate reads only "deny"
# here, so this rule is inert (postuse BR7 is the authoring side of the same
# mistake). It must not read as enforced.
A5=$(guard <<'EOF'
{
  "project": "lint-fixture",
  "bash": [
    { "id": "wrong-section", "match": "^src/core/.*", "why": "meant to be a path rule" }
  ]
}
EOF
)
lint "$A5"; refused_naming "wrong-section" 'a path key inside bash[] is refused'

# A6 — present but empty pattern. parse_rules drops an empty pattern, so the
# key being there is not the same as the rule existing.
A6=$(guard <<'EOF'
{
  "project": "lint-fixture",
  "bash": [
    { "id": "empty-deny", "deny": "", "why": "placeholder nobody filled in" }
  ]
}
EOF
)
lint "$A6"; refused_naming "empty-deny" 'rule with an empty deny pattern is refused'

# A7 — a broken rule with no id at all still has to be locatable.
A7=$(guard <<'EOF'
{
  "project": "lint-fixture",
  "bash": [
    { "denies": "npx\\s+wrangler\\s+deploy", "why": "no id either" }
  ]
}
EOF
)
lint "$A7"; refused_naming "bash[0]" 'an id-less broken rule is named by position'

# A8 — being in disabled[] does not make a typo disappear. The rule stays in
# the file and gets switched back on some day; lint reports the file as it is.
A8=$(guard <<'EOF'
{
  "project": "lint-fixture",
  "disabled": ["parked-rule"],
  "bash": [
    { "id": "parked-rule", "denies": "deploy\\s+--prod", "why": "parked, and typo'd" }
  ]
}
EOF
)
lint "$A8"; refused_naming "parked-rule" 'a disabled rule is still linted'

# ------------------------------------------------- B. it must not cry wolf
# The negative half. Each of these is a guard that is genuinely fine; a new
# check that fails them is worse than the hole it closed.
clean() { # $1=dir $2=label
  lint "$1"
  if [ "$RC" -eq 0 ] && says "is valid"; then ok "$2"
  else bad "$2 — exit $RC: $OUT"; fi
}

B1=$(guard <<'EOF'
{
  "project": "lint-fixture",
  "bash": [
    { "id": "no-force-push-main", "deny": "git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b", "why": "force-pushing a shared branch destroys history" }
  ],
  "protectedPaths": [
    { "id": "anti-path-frozen", "match": "^(bin/rabadon\\.mjs|index\\.html)$", "why": "frozen" }
  ],
  "codePaths": ["^src/"],
  "testPaths": ["_test\\.sh$"],
  "testCommand": "make\\s+test",
  "testPassPattern": "0 fail",
  "pushGate": { "why": "no push while red", "run": "make test", "timeoutSec": 600 },
  "network": "deny",
  "disabled": []
}
EOF
)
clean "$B1" 'a correct guard using every documented field still lints clean'

# B2 — the keys rabadon itself stamps onto rules must stay legal:
# `authoredBy`/`incidentAt` from incident authoring (gate.cpp), `source` from
# `rabadon pack import` (bin/rabadon.mjs). If lint rejected these, rabadon's
# own output would fail rabadon's own linter.
B2=$(guard <<'EOF'
{
  "project": "lint-fixture",
  "bash": [
    { "id": "from-a-pack", "deny": "deploy\\s+--prod", "why": "imported law", "source": "acme-pack" }
  ],
  "protectedPaths": [
    { "id": "release-workflow", "match": "^\\.github/workflows/release\\.(yml|yaml)$", "why": "publish pipeline", "authoredBy": "incident", "incidentAt": "2026-07-31T15:15:30Z" }
  ]
}
EOF
)
clean "$B2" 'rabadon-stamped rule keys (source/authoredBy/incidentAt) lint clean'

# B3 — REAL WORLD: this repo's own guard.json. The one file a regression here
# would break for the person running the suite.
clean "." "this repo's own .rabadon/guard.json lints clean"

# B3b — B3 above only proves something if that file is IN the repo. .gitignore
# carried `.rabadon/` — the whole directory — so guard.json was never committed:
# B3 was green on the author's machine and red in every clean clone, which is
# where a stranger runs it. Measured on a fresh clone of 787bbd9 before the fix:
#   FAIL - this repo's own .rabadon/guard.json lints clean
#          exit 1: rabadon lint: no guard at ./.rabadon/guard.json
# and because `make test` stops at the first red suite, that was suite 14 of 58
# — 44 suites never ran at all. A test that reads a file the repo does not ship
# is not testing the repo, it is testing one laptop.
#
# POSITIVE: the file B3 reads is tracked by git.
# NEGATIVE twin: the cheap way to make the positive pass is to un-ignore
# `.rabadon/` wholesale, and that directory also holds live session state —
# state.json is rewritten mid-run — so the twin fails the moment any of it gets
# committed. Without the twin, "fix" and "leak" are the same green.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git ls-files --error-unmatch .rabadon/guard.json >/dev/null 2>&1; then
    ok "the guard B3 reads is tracked — a clean clone has it too"
  else
    bad "B3 reads .rabadon/guard.json but git does not track it — B3 is green only on this machine"
  fi
  # asked of every .rabadon at every depth, not a hardcoded root list: the first
  # attempt at this fix used `.rabadon/*`, which has a slash and therefore
  # anchors to the repo root, and it silently un-ignored native/.rabadon,
  # site/.rabadon and reports/*/.rabadon — three more state.json and a
  # handoff.md. A root-only twin would have called that green.
  leaked=$(git ls-files -- '*.rabadon/*' | grep -v '^\.rabadon/guard\.json$' || true)
  if [ -z "$leaked" ]; then
    ok "the only tracked file under any .rabadon/ is the root guard (state stays local)"
  else
    bad "session state is tracked under .rabadon/: $(printf '%s' "$leaked" | tr '\n' ' ')"
  fi
else
  echo "  skip - git tracking arm: not a git work tree"
fi

# B4 — no rules at all is not a broken rule.
B4=$(guard <<'EOF'
{ "project": "lint-fixture", "bash": [], "protectedPaths": [] }
EOF
)
clean "$B4" 'empty rule arrays lint clean'

# ------------------------------------- C. what lint already caught, still caught
# The old behaviour is load-bearing; the new walk must not have replaced it.
C1=$(guard <<'EOF'
{ "project": "lint-fixture", "bashh": [ { "id": "x", "deny": "y", "why": "z" } ] }
EOF
)
lint "$C1"
{ [ "$RC" -ne 0 ] && says "bashh"; } && ok 'top-level key typo is still caught' \
  || bad "top-level typo regression — exit $RC: $OUT"

C2=$(guard <<'EOF'
{ "project": "lint-fixture", "bash": [ { "id": "bad-regex", "deny": "foo(", "why": "unbalanced" } ] }
EOF
)
lint "$C2"
{ [ "$RC" -ne 0 ] && says "bad-regex"; } && ok 'uncompilable regex is still caught' \
  || bad "uncompilable regex regression — exit $RC: $OUT"

lint "$TMP/nowhere"
[ "$RC" -ne 0 ] && ok 'a missing guard is still an error, not a pass' \
  || bad "missing guard should not exit 0"

# --------------------------------- D. lint agrees with the gate it speaks for
# The claim under all of this: "lint says valid" must mean "the gate enforces
# what you wrote". Drive the REAL gate with the same command against the same
# two guards and prove lint's verdict tracks the gate's behaviour.
RD="$TMP/rd"; mkdir -p "$RD"; : > "$RD/enabled"
fire() { # $1=project dir  $2=session id -> echoes the gate's exit code
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"%s","tool_use_id":"t-%s","tool_name":"Bash","tool_input":{"command":"npx wrangler deploy"}}' "$1" "$2" "$2" \
    | RABADON_DIR="$RD" "$BIN" >/dev/null 2>&1
  echo $?
}
D1=$(guard <<'EOF'
{ "project": "lint-fixture", "bash": [ { "id": "no-wrangler-deploy", "deny": "npx\\s+wrangler\\s+deploy", "why": "deploys go through CI" } ] }
EOF
)
lint "$D1"; rc_lint_ok=$RC
[ "$(fire "$D1" sD1)" = "2" ] && [ "$rc_lint_ok" -eq 0 ] \
  && ok 'the working rule: gate BLOCKS (exit 2) and lint says valid' \
  || bad "working rule: gate should block and lint pass (lint exit $rc_lint_ok)"

lint "$A1"; rc_lint_typo=$RC
[ "$(fire "$A1" sD2)" = "0" ] && [ "$rc_lint_typo" -ne 0 ] \
  && ok 'the typo rule: gate ALLOWS (exit 0) and lint now refuses to certify it' \
  || bad "typo rule: gate allows but lint exit $rc_lint_typo — lint is still lying"

# ------------------------------------- E. the binary under test must be current
# Everything above proves a source change. It proves NOTHING if `make` will not
# rebuild after that source changes. rules.h was listed as a prerequisite of no
# target at all, though gate.cpp and sandbox.cpp both include it: `make all`
# answered "Nothing to be done" with rules.h 1h41m newer than rabadon-sandbox.
# So an edit to the shared rule engine left exec enforcing the previous law
# while the gate enforced the new one — the exact divergence rules.h exists to
# end, reintroduced by the build. Same shape as the version.h hole the Makefile
# comment already describes; version_test.sh section J is the precedent for
# testing it this way. `make -q` only asks, it never builds.
RULES_TARGETS="$(python3 - <<'PY'
import os,re
for f in sorted(os.listdir('native')):
    if f.endswith('.cpp') and re.search(r'#\s*include\s+"rules\.h"', open(os.path.join('native',f),encoding='utf8',errors='replace').read()):
        print('native/rabadon-'+f[:-4])
PY
)"
if [ -z "$RULES_TARGETS" ]; then
  bad "no .cpp includes rules.h — this suite is looking at the wrong header"
elif unset MAKEFLAGS MFLAGS MAKELEVEL && make -q $RULES_TARGETS >/dev/null 2>&1; then
  cp -p native/rules.h "$TMP/rules.h.stamp"
  touch native/rules.h
  if unset MAKEFLAGS MFLAGS MAKELEVEL && make -q $RULES_TARGETS >/dev/null 2>&1; then
    bad "make answers 'up to date' after rules.h changed — the suite would test a stale binary"
  else
    ok "make rebuilds $(printf '%s' "$RULES_TARGETS" | wc -w | tr -d ' ') binaries when rules.h changes"
  fi
  # restore the mtime, or the next run skips this arm for a reason it caused
  # itself — a check that disables itself after one pass is this file's subject
  touch -r "$TMP/rules.h.stamp" native/rules.h
  unset MAKEFLAGS MFLAGS MAKELEVEL && make -q $RULES_TARGETS >/dev/null 2>&1 \
    && ok "the arm left the tree exactly as it found it (rules.h mtime restored)" \
    || bad "the make arm left the tree needing a rebuild"
else
  echo "  skip - make -q arm: the tree is not built (run make first)"
fi

echo "guard lint: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
