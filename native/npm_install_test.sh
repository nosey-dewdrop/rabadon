#!/bin/bash
# npm_install_test.sh — the paved road, walked end to end.
#
# `npm i -g rabadon` is the first line of the README and the only line most
# people will ever run. It installs a prebuilt platform package
# (@rabadon/<os>-<cpu>) holding the binaries; the main package ships sources and
# a Makefile as the fallback. Until 0.4 the JS half of the installer only ever
# looked in <pkg>/native, so on that exact path:
#     rabadon doctor -> "native binaries missing", telling you to run make
#     rabadon init   -> exit 3, no hooks written, nothing guarded
# with all sixteen binaries sitting in the platform package it had just
# installed. Every promise in the README was false for anyone who installed the
# published way, and no test noticed because no test installed the published
# way. This one does: pack, install into a clean prefix, and make the gate
# refuse a real command through the path the installer wrote.
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

command -v npm >/dev/null || { echo "npm_install: npm not present — SKIPPED (this suite proves the published install path; do not read a skip as a pass)"; exit 0; }
[ -x native/rabadon-gate ] || { echo "npm_install: build first (make)"; exit 1; }

case "$(uname -s)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) echo "npm_install: unsupported OS — SKIPPED"; exit 0 ;; esac
case "$(uname -m)" in arm64|aarch64) CPU=arm64 ;; x86_64|amd64) CPU=x64 ;; *) echo "npm_install: unsupported cpu — SKIPPED"; exit 0 ;; esac
PLAT="$OS-$CPU"
[ -d "npm/$PLAT" ] || { echo "npm_install: no npm/$PLAT package — SKIPPED"; exit 0; }

TMP=$(mktemp -d /tmp/rabadon-npm-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

echo "npm install: the published path ($PLAT)"

# 1) build the platform package the way release.yml does: manifest + binaries
mkdir -p "$TMP/plat"
cp "npm/$PLAT/package.json" "$TMP/plat/"
[ -f "npm/$PLAT/README.md" ] && cp "npm/$PLAT/README.md" "$TMP/plat/"
MAN=$(python3 - "$TMP/plat/package.json" "$ROOT/native" "$TMP/plat" <<'PY'
import json, shutil, sys, os
manifest, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
missing = []
for f in json.load(open(manifest))["files"]:
    s = os.path.join(src, f)
    if os.path.exists(s): shutil.copy2(s, os.path.join(dst, f))
    else: missing.append(f)
print(",".join(missing))
PY
)
[ -z "$MAN" ] && pass "the platform manifest names only binaries the build produces" \
  || fail "npm/$PLAT/package.json lists binaries that do not exist: $MAN"

(cd "$TMP/plat" && npm pack --pack-destination "$TMP" >/dev/null 2>&1) || { fail "npm pack (platform)"; echo "npm install: $ok passed, $bad failed"; exit 1; }
npm pack --pack-destination "$TMP" >/dev/null 2>&1 || { fail "npm pack (rabadon)"; echo "npm install: $ok passed, $bad failed"; exit 1; }

# 2) install both into a prefix that has never seen rabadon
mkdir -p "$TMP/prefix"
npm i -g --prefix "$TMP/prefix" "$TMP"/rabadon-"$OS"-"$CPU"-*.tgz "$TMP"/rabadon-[0-9]*.tgz >"$TMP/install.log" 2>&1 \
  && pass "npm i -g installs the package and its prebuilt platform binaries" \
  || { fail "npm i -g failed"; sed 's/^/    | /' "$TMP/install.log" | tail -8; }

RB="$TMP/prefix/bin/rabadon"
[ -x "$RB" ] && pass "the rabadon command is on the path" || fail "no bin/rabadon in the prefix"

export HOME="$TMP/home"; mkdir -p "$HOME/.claude" "$HOME/.rabadon"
export RABADON_NOTIFY=0
unset RABADON_DIR

# 3) doctor must not tell someone to build what they already installed
OUT=$("$RB" doctor 2>&1)
if printf '%s' "$OUT" | grep -q "native core built"; then pass "doctor finds the prebuilt binaries (was: 'native binaries missing')"
else fail "doctor does not see the prebuilt binaries"; printf '%s\n' "$OUT" | sed 's/^/    | /'; fi

# 4) init must actually wire the hooks
PROJ="$TMP/proj"; mkdir -p "$PROJ"; (cd "$PROJ" && git init -q 2>/dev/null)
(cd "$PROJ" && "$RB" init --no-llm >"$TMP/init.log" 2>&1)
RC=$?
[ $RC -eq 0 ] && pass "rabadon init exits 0 on a prebuilt install (was: exit 3)" || { fail "init exit $RC"; sed 's/^/    | /' "$TMP/init.log"; }

SET="$PROJ/.claude/settings.json"
[ -f "$SET" ] && pass "init wrote the project's settings.json" || fail "no settings.json — nothing was wired"

GATE=$(python3 - "$SET" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
for e in d.get("hooks", {}).get("PreToolUse", []):
    for h in e.get("hooks", []):
        if "rabadon-gate" in h.get("command", ""): print(h["command"]); raise SystemExit
PY
)
if [ -n "$GATE" ] && [ -x "$GATE" ]; then pass "the hook command points at a binary that EXISTS and is executable"
else fail "hook command is dead: '${GATE:-<none>}'"; fi

# 5) the whole point: a real refusal, through the path the installer wrote
if [ -n "$GATE" ] && [ -x "$GATE" ]; then
  touch "$HOME/.rabadon/enabled"
  printf '{"hook_event_name":"PreToolUse","session_id":"s-npm","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "$PROJ" \
    | "$GATE" >/dev/null 2>&1
  [ $? -eq 2 ] && pass "a force-push is REFUSED through the installed hook — the README's first promise holds" \
    || fail "the installed gate did not refuse a force-push"
fi

# 6) THE PREBUILT CLAIM, tested where it is actually made: a machine with no
# compiler. The package ships a postinstall that builds from source with
# clang++/g++ when no prebuilt platform package matches, which means every pass
# above is ambiguous — the binaries could have been compiled during install on a
# developer machine that has a toolchain. The README promises a prebuilt binary,
# and the person that promise is for does not have a compiler.
#
# So: a second clean prefix, installed with a PATH whose FIRST entry holds shims
# named cc, gcc, g++, clang, clang++, c++ and make. Each shim writes its own name
# to a log and exits 127. If anything tries to compile, the log says which tool
# and the install fails loudly instead of quietly succeeding for the wrong
# reason. An empty log is the proof, and `rabadon --version` printing a version
# is what it is proof OF.
mkdir -p "$TMP/nocc" "$TMP/prefix2"
: > "$TMP/nocc.log"
for t in cc gcc g++ clang clang++ c++ make cmake ld; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\necho "no compiler on this machine" >&2\nexit 127\n' \
    "$t" "$TMP/nocc.log" > "$TMP/nocc/$t"
  chmod +x "$TMP/nocc/$t"
done

if PATH="$TMP/nocc:$PATH" npm i -g --prefix "$TMP/prefix2" \
     "$TMP"/rabadon-"$OS"-"$CPU"-*.tgz "$TMP"/rabadon-[0-9]*.tgz >"$TMP/install2.log" 2>&1; then
  pass "npm i -g succeeds with every compiler on PATH replaced by a shim that refuses"
else
  fail "the install needs a compiler — the prebuilt claim does not hold"
  sed 's/^/    | /' "$TMP/install2.log" | tail -12
fi

if [ ! -s "$TMP/nocc.log" ]; then
  pass "nothing tried to compile: the shim log is empty"
else
  fail "the install reached for a compiler"; sed 's/^/    | /' "$TMP/nocc.log" | head -6
fi

RB2="$TMP/prefix2/bin/rabadon"
VER=$(PATH="$TMP/nocc:$PATH" "$RB2" --version 2>&1)
VRC=$?
PKGV=$(python3 -c 'import json;print(json.load(open("package.json"))["version"])')
if [ $VRC -eq 0 ] && printf '%s' "$VER" | grep -q "$PKGV"; then
  pass "rabadon --version on a compiler-free install prints $PKGV: $(printf '%s' "$VER" | head -1)"
else
  fail "rabadon --version exit $VRC on the compiler-free install: $(printf '%s' "$VER" | head -2 | tr '\n' ' ')"
fi

# and the binary it runs has to be a real one, not a shim or a shell fallback
BIN2=$(PATH="$TMP/nocc:$PATH" "$RB2" --version 2>&1 | sed -n 's/^  core: //p' | head -1)
if [ -n "$BIN2" ] && [ -x "$BIN2" ] && file "$BIN2" 2>/dev/null | grep -qi "executable"; then
  pass "the gate it found is a real executable shipped in the tarball: $(basename "$BIN2")"
else
  fail "could not confirm a prebuilt gate binary on the compiler-free install"
fi

echo "npm install: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
