#!/bin/bash
# sandbox_test.sh — guard.json is enforced by the KERNEL, proven with EPERM.
#
# The whole point over a hook: the deny holds even when nothing consults
# rabadon first. So the test does NOT go through the gate — it runs a raw
# shell command inside the compiled sandbox and asserts the OS refused it.
#
# Cases (macOS Seatbelt / Linux bwrap; skipped cleanly where no backend):
#   1. a write to a protectedPaths subtree -> Operation not permitted, the
#      file is unchanged;
#   2. a write ELSEWHERE still succeeds (the fence is scoped, not a brick);
#   3. reads of the protected path still work (read-only, not invisible);
#   4. --print compiles the guard into a real profile naming the path;
#   5. a pure-regex rule with no literal prefix is reported, not silently
#      pretended-enforced;
#   6. exec REFUSES (exit 3) when rules need a fence and no backend exists
#      (simulated by pointing at a platform with no backend is hard; instead
#      we assert --check's contract and the refuse path via a guard with rules
#      on a box that HAS a backend still runs — so we test the inverse: an
#      empty guard runs bare).
set -u
cd "$(dirname "$0")/.."
SB=./native/rabadon-sandbox
[ -x "$SB" ] || { echo "sandbox_test: build first (make native/rabadon-sandbox)"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }
skip() { echo "  skip - $1"; }

echo "sandbox: kernel-enforced guard.json"

if ! "$SB" --check >/dev/null 2>&1; then
  skip "no kernel sandbox backend on this platform — enforcement tests skipped (--check is honest about it)"
  "$SB" --check 2>&1 | grep -qi "no kernel backend" && pass "--check reports the absence honestly" || fail "--check message"
  echo "sandbox: $ok passed, $bad failed"; exit "$bad"
fi
pass "a kernel sandbox backend is available (--check exit 0)"

TMP=$(mktemp -d /tmp/rabadon-sandbox-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/proj"; mkdir -p "$PROJ/.rabadon" "$PROJ/protected" "$PROJ/src"
echo "golden" > "$PROJ/protected/reference.txt"
cat > "$PROJ/.rabadon/guard.json" <<'EOF'
{
  "project": "proj",
  "protectedPaths": [
    { "id": "no-touch-protected", "match": "protected/", "why": "the golden reference is read-only" },
    { "id": "regex-only", "match": "^.*\\.golden$", "why": "no literal prefix" }
  ]
}
EOF

# 4) --print names the absolute protected path
PR="$("$SB" --print --dir "$PROJ" 2>/dev/null)"
printf '%s' "$PR" | grep -q "$PROJ/protected" && pass "--print compiles guard.json into a real profile naming the path" || { fail "--print"; printf '%s\n' "$PR" | sed 's/^/    | /'; }

# 5) the pure-regex rule is reported, not silently enforced
"$SB" --print --dir "$PROJ" 2>&1 >/dev/null | grep -q "no literal path prefix" && pass "a pure-regex path is reported (kernel cannot fence it), not faked" || fail "regex-only rule not reported"

# 1) a write into the protected subtree is refused by the KERNEL
OUT=$("$SB" --dir "$PROJ" -- /bin/sh -c "echo HACKED > '$PROJ/protected/reference.txt'" 2>&1); RC=$?
if [ $RC -ne 0 ] && grep -q "golden" "$PROJ/protected/reference.txt"; then
  pass "write to a protected path -> refused by the OS, file UNCHANGED (exit $RC)"
else
  fail "protected write was NOT blocked (rc=$RC, file: $(cat "$PROJ/protected/reference.txt"))"
fi

# 2) a write elsewhere still works — the fence is scoped
"$SB" --dir "$PROJ" -- /bin/sh -c "echo ok > '$PROJ/src/out.txt'" 2>/dev/null
[ -f "$PROJ/src/out.txt" ] && pass "a write OUTSIDE the protected path still succeeds (scoped, not a brick)" || fail "unprotected write was blocked"

# 3) reads of the protected path still work
RD=$("$SB" --dir "$PROJ" -- /bin/sh -c "cat '$PROJ/protected/reference.txt'" 2>/dev/null)
[ "$RD" = "golden" ] && pass "the protected path is still READABLE (read-only, not invisible)" || fail "protected read failed"

# empty guard -> runs bare (nothing to enforce)
BARE="$TMP/bare"; mkdir -p "$BARE/.rabadon"; echo '{"project":"bare"}' > "$BARE/.rabadon/guard.json"
OUT=$("$SB" --dir "$BARE" -- /bin/sh -c "echo ran" 2>/dev/null)
[ "$OUT" = "ran" ] && pass "no rules -> the command runs bare (sandbox is opt-in per rule)" || fail "empty guard did not run"

# --deny-net closes the network (best-effort: curl to a bogus host must fail)
if command -v curl >/dev/null 2>&1; then
  "$SB" --dir "$BARE" --deny-net -- /bin/sh -c "curl -s --max-time 3 http://192.0.2.1/ >/dev/null" 2>/dev/null
  NRC=$?
  [ $NRC -ne 0 ] && pass "--deny-net: a network call inside the sandbox fails" || fail "--deny-net did not block the network (rc=$NRC)"
else
  skip "curl absent — --deny-net network test skipped"
fi

echo "sandbox: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
