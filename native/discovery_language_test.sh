#!/bin/bash
# discovery_language_test.sh — discovery decided what to lock by the file's
# LANGUAGE, and a suite written in a language nobody listed was not protected.
#
# native/truth.cpp counted source files against a fixed extension list
# (js/ts/py/c/cpp/h/go/rs/swift/java) and any file outside it fell through with
# `continue` — eleven lines ABOVE the rule that says a file under tests/ is part
# of the suite. So the location rule never ran for those files. Ruby and Tcl are
# not on the list, and measured against three real repos on 3 August:
#
#   redis       229 .tcl under tests/ on disk, 0 locked. 255 files WERE locked
#               and not one was a redis test — they came from deps/jemalloc,
#               C headers named test_hooks.h in a vendored dependency.
#   rails       1290 *_test.rb on disk, 0 locked. The 20 that were locked were
#               .js, one of them actioncable/rollup.config.test.js, a build
#               config.
#   discourse   3373 *_spec.rb on disk, 0 locked.
#
# That is 4892 real test files across three repos with nothing holding them, and
# `discoveryCapped` was [] on all three — the empty array that is supposed to
# mean "I saw everything". A lock list full of a vendored dependency's headers
# is worse than an empty one: it reports coverage that does not exist.
#
# Every widening here has a twin, because the way this fix goes wrong is by
# hash-locking source and refusing an honest repair. `lib/latest.rb` has the
# word test in it and is not a test; a compiled .so sitting in tests/ is a build
# artifact, not a check.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
TRUTH="$HERE/rabadon-truth"
[ -x "$TRUTH" ] || { echo "build first: make native/rabadon-truth"; exit 1; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rabadon-lang.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

found() { "$TRUTH" "$1" --json 2>/dev/null | python3 -c 'import json,sys; [print(x) for x in json.load(sys.stdin).get("testFiles",[])]'; }

# locked <dir> <relpath> — the file must be in the lock list
locked() {
  if found "$1" | grep -qx "$2"; then ok "locks $2"; else bad "locks $2 — NOT in the lock list"; fi
}
# free <dir> <relpath> — the file must NOT be in the lock list
free_() {
  if found "$1" | grep -qx "$2"; then bad "leaves $2 free — it was LOCKED (honest edits now refused)"; else ok "leaves $2 free"; fi
}

mk() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-x}" > "$1"; }

echo "discovery — a suite is found by where it lives, not what language it is"
echo

# ---------------------------------------------------------------------------
# 1. RUBY, the rails shape: test/**/*_test.rb
R="$ROOT/rails"
mk "$R/Rakefile" "task :test"
mk "$R/lib/user.rb"
mk "$R/lib/latest.rb"                      # twin: 'test' inside 'latest'
mk "$R/app/models/contest.rb"              # twin: 'test' inside 'contest'
mk "$R/actionpack/test/abstract/translation_test.rb"
mk "$R/actionmailbox/test/migrations_test.rb"
echo "-- ruby / rails"
locked "$R" "actionpack/test/abstract/translation_test.rb"
locked "$R" "actionmailbox/test/migrations_test.rb"
free_  "$R" "lib/latest.rb"
free_  "$R" "app/models/contest.rb"
free_  "$R" "lib/user.rb"

# ---------------------------------------------------------------------------
# 2. RUBY, the discourse shape: spec/**/*_spec.rb
#    `_spec.` was never a pattern — only `.spec.` was — so rspec's own naming
#    convention matched nothing.
D="$ROOT/discourse"
mk "$D/Gemfile" "gem 'rails'"
mk "$D/app/models/topic.rb"
mk "$D/spec/models/topic_spec.rb"
mk "$D/spec/requests/admin_spec.rb"
echo "-- ruby / rspec"
locked "$D" "spec/models/topic_spec.rb"
locked "$D" "spec/requests/admin_spec.rb"
free_  "$D" "app/models/topic.rb"

# ---------------------------------------------------------------------------
# 3. TCL, the redis shape: tests/**/*.tcl, a language on no list anywhere.
#    The suite is found because of WHERE it is. The .so beside it is a build
#    artifact and locking it would refuse an honest rebuild; the vendored
#    dependency's C header named test_hooks.h is not this project's check.
S="$ROOT/redis"
mk "$S/Makefile" "test:"
mk "$S/src/server.c"
mk "$S/tests/unit/type/list.tcl"
mk "$S/tests/integration/replication.tcl"
mk "$S/tests/assets/default.conf" "port 6379"      # a test config IS the check
mk "$S/tests/modules/hooks.so"                     # twin: build artifact
mk "$S/tests/helpers/.gitignore" "*.so"            # twin: dotfile config
echo "-- tcl / redis"
locked "$S" "tests/unit/type/list.tcl"
locked "$S" "tests/integration/replication.tcl"
locked "$S" "tests/assets/default.conf"
free_  "$S" "tests/modules/hooks.so"
free_  "$S" "tests/helpers/.gitignore"
free_  "$S" "src/server.c"

# ---------------------------------------------------------------------------
# 4. PHP, and a language this file does not name. The rule is the location, so
#    a suite in a language nobody thought of is still found.
P="$ROOT/php"
mk "$P/composer.json" '{"name":"x/y"}'
mk "$P/src/Handler.php"
mk "$P/tests/Feature/ExampleTest.php"
mk "$P/tests/Unit/parser.exs"                      # elixir, named by no pattern
echo "-- php / a language nobody listed"
locked "$P" "tests/Feature/ExampleTest.php"
locked "$P" "tests/Unit/parser.exs"
free_  "$P" "src/Handler.php"

# ---------------------------------------------------------------------------
# 5. The project's own law still wins: guard.json testPaths names a file whose
#    extension is on no list, and it is locked because the repo said so.
G="$ROOT/guarded"
mk "$G/package.json" '{"name":"g"}'
mk "$G/index.js"
mk "$G/checks/smoke.bats"
mk "$G/checks/README.md"
mkdir -p "$G/.rabadon"
printf '%s\n' '{"testPaths":["^checks/.*\\.bats$"]}' > "$G/.rabadon/guard.json"
echo "-- the repo's own testPaths"
locked "$G" "checks/smoke.bats"
free_  "$G" "checks/README.md"

# ---------------------------------------------------------------------------
# 6. A document under a test directory is read by people, not by the runner.
#    Locking it refuses an honest doc edit and buys no protection.
M="$ROOT/docs"
mk "$M/go.mod" "module m"
mk "$M/main.go"
mk "$M/test/README.md" "# how to run the suite"
mk "$M/test/cases_test.go"
echo "-- documents are not checks"
locked "$M" "test/cases_test.go"
free_  "$M" "test/README.md"

echo
printf 'discovery-language: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
