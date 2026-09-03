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

ok=0; bad=0; SKIP=0; SKIPA=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }
# An arm that cannot run HERE is announced with its NAME and its NUMBER, and
# the count reaches the summary line. A skip that increments nothing is the
# suite getting smaller in silence, and every counter downstream reads the
# smaller number as health. native/silent_skip_test.sh holds this over the
# whole directory. $1 = arm, $2 = assertions not run, $3 = why.
skip() { SKIP=$((SKIP+1)); SKIPA=$((SKIPA+$2)); echo "  SKIP - $1: $2 assertion(s) did NOT run — $3"; }

echo "sandbox: kernel-enforced guard.json"

# ---------------------------------------------------------------------------
# THE LAW COMES FIRST — and it is the same law the hook enforces.
#
# exec used to compile ONLY protectedPaths and network into a kernel policy.
# It never read the bash deny rules, so a command the gate refused with exit 2
# ran to completion through exec with exit 0 and left nothing in the ledger —
# exec was a SUBSET of the gate while being sold as the harder boundary. These
# cases run BEFORE the backend check on purpose: a refusal is a decision about
# the command, not about whether a kernel fence happens to be available, so it
# must hold on a box with no sandbox backend at all.
# ---------------------------------------------------------------------------
# absolute, because two cases below run from inside an isolated temp repo
SBABS="$PWD/native/rabadon-sandbox"
LAWDIR=$(mktemp -d /tmp/rabadon-exec-law.XXXXXX)
LAWHOME=$(mktemp -d /tmp/rabadon-exec-home.XXXXXX)
BASEDIR=$(mktemp -d /tmp/rabadon-exec-base.XXXXXX)
mkdir -p "$LAWDIR/.rabadon" "$LAWDIR/bin"
cat > "$LAWDIR/.rabadon/guard.json" <<'GUARD'
{"project":"exec-law","bash":[{"id":"no-wrangler-deploy","deny":"npx\\s+wrangler\\s+deploy","why":"deploys go through CI, never a live session"}],"protectedPaths":[]}
GUARD
# a stand-in on PATH: if the rule ever fails to fire, the test SEES the command
# run instead of quietly passing because the real binary happened to be absent
printf '#!/bin/sh\necho DEPLOY-ESCAPED\n' > "$LAWDIR/bin/npx"; chmod +x "$LAWDIR/bin/npx"

lawrun() { PATH="$LAWDIR/bin:$PATH" RABADON_DIR="$LAWHOME" RABADON_NOTIFY=0 "$SB" --dir "$LAWDIR" -- "$@"; }

OUT=$(lawrun /bin/sh -c 'npx wrangler deploy' 2>&1); RC=$?
if [ $RC -eq 2 ] && ! printf '%s' "$OUT" | grep -q "DEPLOY-ESCAPED"; then
  pass "a guard deny rule refuses through exec (exit 2, the command never ran)"
else
  fail "exec ran a command the guard forbids (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    | /' | head -5
fi
printf '%s' "$OUT" | grep -q "no-wrangler-deploy" && pass "the refusal names the rule id and its reason" || fail "refusal did not name the rule"

# a refusal nobody can audit is not evidence
LEDGER=$(cat "$LAWHOME/spool/"*.jsonl 2>/dev/null || true)
if printf '%s' "$LEDGER" | grep -q '"ev":"STOP"' && printf '%s' "$LEDGER" | grep -q '"rule":"no-wrangler-deploy"'; then
  pass "the exec refusal is written to the ledger (CHECK_FAIL + STOP, rule named)"
else
  fail "exec left no ledger trace"; printf '%s\n' "$LEDGER" | sed 's/^/    | /' | head -5
fi
if [ -x ./native/rabadon-audit ]; then
  RABADON_DIR="$LAWHOME" ./native/rabadon-audit --days 1 2>&1 | grep -q "INTACT" \
    && pass "exec writes through the SAME hash chain (audit: INTACT)" || fail "exec broke the ledger chain"
fi

# The three compiled-in laws must reach exec too, with no guard rule involved.
#
# This case runs from INSIDE an isolated, remote-less temp repo, and that is
# not tidiness. The first version ran it from the suite's own cwd — the real
# rabadon checkout — and when the law failed to fire, exec really did run
# `git push --force origin main` against the real remote. It printed
# "Everything up-to-date" because local and origin happened to be identical,
# which is luck, not a safeguard. A suite that proves a destructive command is
# refused must be written so that a FAILURE to refuse is also harmless.
git -C "$BASEDIR" init -q 2>/dev/null || true
OUT=$(cd "$BASEDIR" && RABADON_DIR="$LAWHOME" RABADON_NOTIFY=0 "$SBABS" --dir "$BASEDIR" -- /bin/sh -c 'git push --force origin main' 2>&1); RC=$?
[ $RC -eq 2 ] && pass "a baseline law (force-push to a shared branch) refuses through exec, with no guard.json at all" \
  || { fail "baseline law did not reach exec (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    | /' | head -4; }

# the same law, reached WITHOUT a shell wrapper — argv straight to git
OUT=$(cd "$BASEDIR" && RABADON_DIR="$LAWHOME" RABADON_NOTIFY=0 "$SBABS" --dir "$BASEDIR" -- git push --force origin main 2>&1); RC=$?
[ $RC -eq 2 ] && pass "the same law fires on bare argv too (no shell to unwrap)" \
  || { fail "baseline law missed bare argv (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    | /' | head -4; }

# disabled[] is the user's override and it must still work through exec
cat > "$LAWDIR/.rabadon/guard.json" <<'GUARD'
{"project":"exec-law","disabled":["no-wrangler-deploy"],"bash":[{"id":"no-wrangler-deploy","deny":"npx\\s+wrangler\\s+deploy","why":"deploys go through CI, never a live session"}],"protectedPaths":[]}
GUARD
OUT=$(lawrun /bin/sh -c 'npx wrangler deploy' 2>&1); RC=$?
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q "DEPLOY-ESCAPED"; then
  pass "disabled[] still silences a rule through exec (the fix did not swallow the override)"
else
  fail "disabled[] ignored by exec (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    | /' | head -4
fi

# regression: ordinary work must still run, or nobody will use exec at all
OUT=$(RABADON_DIR="$LAWHOME" RABADON_NOTIFY=0 "$SB" --dir "$BASEDIR" -- /bin/sh -c 'echo ordinary-work' 2>&1); RC=$?
if [ $RC -eq 0 ] && [ "$OUT" = "ordinary-work" ]; then
  pass "an unforbidden command still runs through exec (exit 0)"
else
  fail "exec blocked ordinary work (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/    | /' | head -4
fi

rm -rf "$LAWDIR" "$LAWHOME" "$BASEDIR"

if ! "$SB" --check >/dev/null 2>&1; then
  skip "kernel enforcement arm" 9 "no kernel sandbox backend on this platform; --check says so out loud, and these 9 assertions were not judged here"
  # HARDENED, not loosened (F1b). The shipped line is
  #   sandbox.cpp:365  "rabadon sandbox: NO usable kernel backend — %s"
  # and this assertion used to look for "no kernel backend", case-insensitively.
  # a74e7d8 (2026-07-31) changed the product string and left the test behind, so
  # this arm has been red for 27 days on every machine WITHOUT a kernel backend
  # (the clean container; macOS never reaches it, Seatbelt is always present).
  # The expectation now names the string the product actually ships, verbatim
  # and case-sensitively: strictly FEWER strings satisfy it than before.
  "$SB" --check 2>&1 | grep -q "rabadon sandbox: NO usable kernel backend" && pass "--check reports the absence honestly" || fail "--check message"
  echo "sandbox: $ok passed, $bad failed, $SKIP skipped ($SKIPA assertion(s) not run)"; exit "$bad"
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

# 0) THE FENCE MUST ACTUALLY START. A backend that fails to launch produces a
# non-zero exit and an unchanged file — which is exactly what a kernel refusal
# looks like from the outside. Without this check the refusal test below passes
# on a sandbox that never ran, and the suite reports kernel enforcement it never
# performed. That false pass is how "1 passed, 0 failed" hid a broken linux
# backend through every release.
SANE=$("$SB" --dir "$PROJ" -- /bin/sh -c "echo sane" 2>"$TMP/sane.err"); SRC=$?
if [ "$SANE" = "sane" ]; then
  pass "the sandbox launches and runs a command under enforcement (exit 0)"
else
  fail "the fence never started (rc=$SRC) — every refusal below would be a FALSE pass"
  sed 's/^/    | /' "$TMP/sane.err" | head -5
fi

# 1) a write into the protected subtree is refused by the KERNEL
OUT=$("$SB" --dir "$PROJ" -- /bin/sh -c "echo HACKED > '$PROJ/protected/reference.txt'" 2>&1); RC=$?
if [ $RC -ne 0 ] && grep -q "golden" "$PROJ/protected/reference.txt"; then
  pass "write to a protected path -> refused by the OS, file UNCHANGED (exit $RC)"
else
  fail "protected write was NOT blocked (rc=$RC, file: $(cat "$PROJ/protected/reference.txt"))"
fi

# 2) a write elsewhere still works — the fence is scoped
"$SB" --dir "$PROJ" -- /bin/sh -c "echo ok > '$PROJ/src/out.txt'" 2>"$TMP/w.err"
[ -f "$PROJ/src/out.txt" ] && pass "a write OUTSIDE the protected path still succeeds (scoped, not a brick)" \
  || { fail "unprotected write was blocked"; sed 's/^/    | /' "$TMP/w.err" | head -5; }

# 3) reads of the protected path still work
RD=$("$SB" --dir "$PROJ" -- /bin/sh -c "cat '$PROJ/protected/reference.txt'" 2>"$TMP/r.err")
[ "$RD" = "golden" ] && pass "the protected path is still READABLE (read-only, not invisible)" \
  || { fail "protected read failed"; sed 's/^/    | /' "$TMP/r.err" | head -5; }

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
  skip "--deny-net network arm" 1 "curl is not on this machine, so no request could be attempted"
fi

# THE KERNEL MATCHES ITS OWN CANONICAL PATH, so a fence naming a symlink fences
# nothing. Measured 2026-09-03 by an outside reviewer: with `work` a symlink to
# the real project, an absolute protectedPath under `work/` emitted a plausible
# `(deny file-write* (subpath ".../work/secrets"))`, --print looked right, and
# the write went through at exit 0 — the one SILENT failure on the surface the
# docs call the hard boundary. Ordinary triggers, not exotic: /tmp is
# /private/tmp on macOS, $TMPDIR is under /private/var, a home on a mounted
# volume, ~/Documents under iCloud. The relative form was always safe (the
# project dir is realpath'd at the call site); only the absolute one was not.
#
# Driven from python so the lab is built and judged in one place: the shell
# version of this fixture quietly mis-set its own paths and reported a hole
# that the same scenario, built correctly, does not have.
if "$SB" --check >/dev/null 2>&1; then
  SBABS="$(cd "$(dirname "$SB")" && pwd)/$(basename "$SB")"
  SLOUT="$(python3 - "$SBABS" <<'PYEOF'
import os, sys, json, subprocess, tempfile, shutil
SB = sys.argv[1]
SL = tempfile.mkdtemp()
try:
    for d in ("store/proj/secrets", "store/proj/.rabadon", "rhome/.rabadon/spool"):
        os.makedirs(os.path.join(SL, d))
    open(os.path.join(SL, "rhome/.rabadon/enabled"), "w").close()
    os.symlink(os.path.join(SL, "store/proj"), os.path.join(SL, "work"))
    key = os.path.join(SL, "store/proj/secrets/key.txt")
    open(key, "w").write("TOPSECRET\n")
    guard = {"project": "proj", "testCommand": "true",
             "protectedPaths": [{"id": "s", "match": "^" + SL + "/work/secrets/.*", "why": "ro"}]}
    open(os.path.join(SL, "store/proj/.rabadon/guard.json"), "w").write(json.dumps(guard))
    env = dict(os.environ, HOME=SL + "/rhome", RABADON_DIR=SL + "/rhome/.rabadon", RABADON_NOTIFY="0")
    proj, work = SL + "/store/proj", SL + "/work"
    pr = subprocess.run([SB, "--print", "--", "true"], cwd=proj, env=env, capture_output=True, text=True)
    resolved = os.path.realpath(proj) + "/secrets"
    print("PROFILE_RESOLVED", "yes" if resolved in pr.stdout else "no")
    subprocess.run([SB, "--", "sh", "-c", "echo pwned > " + key], cwd=proj, env=env, capture_output=True, text=True)
    print("AFTER_REAL", open(key).read().strip())
    subprocess.run([SB, "--", "sh", "-c", "echo pwned > " + work + "/secrets/key.txt"], cwd=work, env=env, capture_output=True, text=True)
    print("AFTER_LINK", open(key).read().strip())
    ok = os.path.join(SL, "store/proj/ok.txt")
    subprocess.run([SB, "--", "sh", "-c", "echo fine > " + ok], cwd=proj, env=env, capture_output=True, text=True)
    print("UNPROTECTED", open(ok).read().strip() if os.path.exists(ok) else "MISSING")
finally:
    shutil.rmtree(SL, ignore_errors=True)
PYEOF
)"
  case "$SLOUT" in *"PROFILE_RESOLVED yes"*) pass "the emitted profile names the resolved path, not the symlink" ;;
    *) fail "the profile still carries the unresolved path" ;; esac
  case "$SLOUT" in *"AFTER_REAL TOPSECRET"*) pass "a write through the REAL path is refused when the fence names the symlink" ;;
    *) fail "the protected file was overwritten — the kernel fence named a path it never sees" ;; esac
  case "$SLOUT" in *"AFTER_LINK TOPSECRET"*) pass "and a write through the SYMLINK path is refused too" ;;
    *) fail "the protected file was overwritten through the symlink" ;; esac
  case "$SLOUT" in *"UNPROTECTED fine"*) pass "an unprotected write in the same project still runs" ;;
    *) fail "the fence refused a write it was never asked to refuse" ;; esac
else
  skip "the symlinked-fence arm" 4 "no kernel sandbox backend on this platform"
fi

echo "sandbox: $ok passed, $bad failed, $SKIP skipped ($SKIPA assertion(s) not run)"
[ "$bad" -eq 0 ]
