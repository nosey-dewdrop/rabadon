#!/usr/bin/env bash
# machine_intact_test.sh — THE OPERATOR'S MACHINE IS A GATE.
#
# WHY THIS EXISTS. This run damaged the machine it was built on three times, and
# every one of the three was invisible to `make test` while it was happening:
#
#   B1  the shipped native/rabadon-gate lost its execute bit (-rw-r--r--), so
#       every hook exited 126 and the brake saw nothing for hours. The operator's
#       own words: "it did not even record the force push."
#   B1' worse, and found later: the same binary was for a while a SEVENTEEN BYTE
#       `#!/bin/sh` + `exit 0` stub, with the real one moved aside. All six hooks
#       in ~/.claude/settings.json pointed at it, so rabadon answered `exit 0`
#       to everything — installed, certified, and blind. `make` does not repair
#       this: the stub's mtime is newer than the sources, so make says "up to
#       date". A check that only asks "does the binary exist" passes on a stub.
#   B2  self-heal wrote a deleted worktree's absolute path into the operator's
#       GLOBAL ~/.claude/settings.json, and every Stop for days printed
#       "No such file or directory".
#
# Not one phase of this run ever asked "what did my change do to her OTHER
# sessions". So the question stops being manners and becomes a gate: three
# things are measured, and if any of the three moved, `make test` is RED.
#
#   1. the twenty shipped artifacts: mode, size, sha256 — and each one is a REAL
#      executable, not a stub with the right name.
#   2. ~/.claude/settings.json: byte for byte. It is a SHARED file on this
#      machine, carrying hooks and a statusLine that are not rabadon's.
#   3. the live brake (~/.rabadon/mode, ~/.rabadon/enabled): as the operator
#      left it. Not "on" — HERS. §3.4 makes that switch her pen, so this suite
#      only ever compares; it never sets, never creates, never removes.
#
# HOW IT MEASURES A RUN RATHER THAN A MOMENT. Wired into `make test` TWICE:
# `record` right after the build, plain (verify) at the very end. The record arm
# writes a manifest to the temp directory; the verify arm re-measures and diffs.
# A verify arm that finds no manifest is RED, not absent — otherwise the day
# somebody drops the record line the gate would certify every run as clean.
#
# It writes NOTHING outside the temp directory, and it reads $HOME directly on
# purpose: the subject is the operator's machine, not whatever RABADON_DIR the
# surrounding suite happens to have set.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOTDIR="$(cd "$HERE/.." && pwd)"
MODE="${1:-verify}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL - %s\n' "$1"; }

command -v shasum >/dev/null 2>&1 && HASH='shasum -a 256' || HASH='sha256sum'
command -v ${HASH%% *} >/dev/null 2>&1 || { echo "machine_intact: no sha256 tool" >&2; exit 1; }

# The manifest is keyed by HOME so the mutation proof (which runs the whole
# two-arm dance against a fixture home) can never collide with the real run.
KEY="$(printf '%s' "${HOME:-nohome}" | $HASH | cut -c1-16)"
MAN="${TMPDIR:-/tmp}/rabadon-machine-intact-$KEY.tsv"

hash_of() { $HASH "$1" 2>/dev/null | cut -d' ' -f1; }
mode_of() { # portable octal mode
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then stat -f '%Lp' "$1"; else stat -c '%a' "$1"; fi
}
size_of() {
  if stat -f '%z' "$1" >/dev/null 2>&1; then stat -f '%z' "$1"; else stat -c '%s' "$1"; fi
}

# THE SHIPPED SET, GLOBBED, NEVER LISTED. A hand-kept list is a gate the
# twenty-first binary walks around — the same lesson native/cli_test.sh learned
# when a stubbed `rabadon-gate.gercek` appeared beside the real one.
shipped() { ls "$ROOTDIR"/native/rabadon-* 2>/dev/null | sort; }

# WHAT THIS MACHINE LOOKS LIKE RIGHT NOW, one line per subject.
snapshot() {
  for f in $(shipped); do
    printf 'bin\t%s\t%s\t%s\t%s\n' "$(basename "$f")" "$(mode_of "$f")" "$(size_of "$f")" "$(hash_of "$f")"
  done
  local s="${HOME:-/nonexistent}/.claude/settings.json"
  if [ -f "$s" ]; then printf 'settings\t%s\t%s\n' "$(size_of "$s")" "$(hash_of "$s")"
  else printf 'settings\tABSENT\tABSENT\n'; fi
  local m="${HOME:-/nonexistent}/.rabadon/mode"
  printf 'brake-mode\t%s\n' "$([ -f "$m" ] && tr -d '\n' < "$m" || echo ABSENT)"
  printf 'brake-enabled\t%s\n' "$([ -e "${HOME:-/nonexistent}/.rabadon/enabled" ] && echo PRESENT || echo ABSENT)"
}

# ---------------------------------------------------------------------------
# POINT-IN-TIME CLAIMS. These need no baseline: a stub is a stub on its own
# evidence. They run on BOTH arms, because B1' appeared halfway through a run.
point_in_time() {
  local n=0 stubs=0 unx=0 tiny=0
  for f in $(shipped); do
    n=$((n+1))
    local b; b="$(basename "$f")"
    # execute bits: all three. B1 was -rw-r--r-- and every hook died with 126.
    case "$(mode_of "$f")" in
      *[1357]*) : ;;
      *) unx=$((unx+1)); printf '       not executable: %s (%s)\n' "$b" "$(mode_of "$f")" ;;
    esac
    [ -x "$f" ] || { unx=$((unx+1)); printf '       -x says no: %s\n' "$b"; }

    # SIZE FLOOR. The stub that disarmed this machine was 17 bytes. The smallest
    # honest artifact in this tree is ~40 kB and the smallest script ~16 kB, so
    # 1024 is three orders of margin below the truth and two above the lie.
    local sz; sz="$(size_of "$f")"
    if [ "$sz" -lt 1024 ]; then
      tiny=$((tiny+1)); printf '       %s is %s bytes — that is a stub, not a build\n' "$b" "$sz"
    fi

    # AND IT MUST BE THE RIGHT KIND OF FILE. `#!/bin/sh` + `exit 0` has a
    # perfectly good name, a perfectly good mtime, and exits 0 on everything.
    # Anything the build COMPILES (i.e. not a *.sh) must carry a real
    # executable header. Read the magic directly: `file` is not on the bar of
    # "a machine that has only git and a shell".
    local magic; magic="$(head -c 4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "$b" in
      *.sh)
        case "$magic" in 23*) : ;; *) stubs=$((stubs+1)); printf '       %s is not a script (%s)\n' "$b" "$magic" ;; esac ;;
      *)
        # cffaedfe/cefaedfe Mach-O, cafebabe/bebafeca fat, 7f454c46 ELF
        case "$magic" in
          cffaedfe|cefaedfe|cafebabe|bebafeca|7f454c46) : ;;
          *) stubs=$((stubs+1)); printf '       %s has no executable header (%s) — SHIPPED BINARY IS A STUB\n' "$b" "$magic" ;;
        esac ;;
    esac
  done
  [ "$n" -ge 20 ] \
    && ok "$MODE: all $n shipped artifacts are present (never fewer than the twenty that ship)" \
    || bad "$MODE: only $n shipped artifacts found — the build is incomplete"
  [ "$unx"   = "0" ] && ok "$MODE: every shipped artifact is executable (B1: the gate once was not)" \
                     || bad "$MODE: $unx shipped artifact(s) cannot be executed — every hook calling one exits 126"
  [ "$tiny"  = "0" ] && ok "$MODE: no shipped artifact is small enough to be a stub" \
                     || bad "$MODE: $tiny shipped artifact(s) are stub-sized"
  [ "$stubs" = "0" ] && ok "$MODE: every compiled artifact carries a real executable header, not a shell stub" \
                     || bad "$MODE: $stubs shipped artifact(s) are not what they claim to be"

  # And the gate must actually ANSWER. A binary can be real, executable and
  # still be the wrong program; --version is the cheapest proof it is ours.
  local v; v="$("$ROOTDIR/native/rabadon-gate" --version 2>/dev/null | head -1)"
  [ -n "$v" ] \
    && ok "$MODE: the shipped rabadon-gate answers --version ($v)" \
    || bad "$MODE: the shipped rabadon-gate answers nothing — this is the exit-0 stub signature"
}

echo "machine_intact [$MODE]: what did this run do to the operator's other sessions?"
point_in_time

case "$MODE" in
  record)
    snapshot > "$MAN" || { bad "could not write the manifest at $MAN"; }
    [ -s "$MAN" ] \
      && ok "record: the machine baseline is on disk ($(wc -l < "$MAN" | tr -d ' ') subjects)" \
      || bad "record: the baseline manifest is empty — the verify arm would have nothing to compare"
    ;;
  verify)
    # A MISSING MANIFEST IS RED. If this arm quietly passed when the record arm
    # had not run, deleting one Makefile line would silently retire the gate —
    # the `pgrep -c` lesson, and the reason §3.8/3 exists.
    if [ ! -s "$MAN" ]; then
      bad "verify: no baseline at $MAN — the record arm never ran, so this gate measured NOTHING"
    else
      NOW="$(snapshot)"
      D="$(diff <(cat "$MAN") <(printf '%s\n' "$NOW") || true)"

      B_BEFORE="$(grep '^bin	' "$MAN" || true)"
      B_NOW="$(printf '%s\n' "$NOW" | grep '^bin	' || true)"
      if [ "$B_BEFORE" = "$B_NOW" ]; then
        ok "verify: all twenty shipped artifacts came through the run with the same mode, size and hash"
      else
        bad "verify: a shipped artifact changed during the run — mode/size/hash moved"
        diff <(printf '%s\n' "$B_BEFORE") <(printf '%s\n' "$B_NOW") | sed 's/^/       /'
      fi

      S_BEFORE="$(grep '^settings	' "$MAN" || true)"
      S_NOW="$(printf '%s\n' "$NOW" | grep '^settings	' || true)"
      if [ "$S_BEFORE" = "$S_NOW" ]; then
        ok "verify: \$HOME/.claude/settings.json is byte for byte what it was before the run"
      else
        bad "verify: THE RUN REWROTE THE OPERATOR'S SHARED settings.json — [$S_BEFORE] -> [$S_NOW]"
      fi

      K_BEFORE="$(grep '^brake-' "$MAN" || true)"
      K_NOW="$(printf '%s\n' "$NOW" | grep '^brake-' || true)"
      if [ "$K_BEFORE" = "$K_NOW" ]; then
        ok "verify: the live brake is exactly as the operator left it ($(printf '%s' "$K_NOW" | tr '\n\t' '; '))"
      else
        bad "verify: THE RUN MOVED THE OPERATOR'S BRAKE — [$K_BEFORE] -> [$K_NOW]"
      fi

      [ -z "$D" ] \
        && ok "verify: nothing at all moved on this machine during the run" \
        || ok "verify: the diff above is the complete list of what moved"
      rm -f "$MAN"
    fi
    ;;
  *)
    bad "unknown arm '$MODE' — this suite takes 'record' or 'verify'"
    ;;
esac

printf 'machine_intact [%s]: %d passed, %d failed\n' "$MODE" "$PASS" "$FAIL"
[ "$FAIL" = "0" ] || exit 1
