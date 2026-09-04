#!/usr/bin/env bash
# R7 acceptance — speed (a persistent daemon) and the two-armed proof.
#
# R7 has two halves and this file refuses to let either one carry the other.
#
#   SPEED. Most of the gate's wall clock is process startup: ~2.3 ms of a 4.2 ms
#   call is fork/exec/dyld (reports/R1.3/PROFIL.md). A persistent daemon
#   (rabadon-gated, unix socket) plus a thin client removes exactly that, so
#   judging costs the judging. If the daemon is absent the client falls back to
#   today's path — fail-SAME, not fail-open.
#
#   PROOF. One task set, two arms: A is the agent alone, B is the agent plus the
#   accumulation engine. The harness is REUSED (SWE-smith, or Terminal-Bench /
#   Harbor), never written here, and its full repo name and commit hash are
#   written under reports/R7/ or this script fails — see GOAL 4.
#
# ---------------------------------------------------------------------------
# HOW THE < 1 ms CLAIM IS MEASURED, AND WHY NOT END-TO-END.
#
# Every budget claim in this file is measured by the instrument that makes the
# claim, and here that instrument is the IN-PROCESS probe of
# reports/R1.3/accept.sh (GOAL 4): a COPY of the shipped gate source is patched
# under /tmp with a steady_clock stamp at the top of main() and an atexit dump,
# and compiled there; native/ is never touched. End-to-end wall clock CANNOT
# settle this question, and not by a little: process spawn is ~2.3 ms of the
# 4.2 ms call, which is precisely the quantity the daemon deletes, so an
# end-to-end ruler would spend more than half its reading on the thing under
# test and its ±150 us noise floor would swamp a 1 ms ceiling. The R1.3
# planted-regression proof is the standard: that ruler caught a deliberate
# 150 us regression 7 of 7 while the end-to-end ruler missed it 3 of 8. No
# number below is asserted against a ceiling unless the probe produced it.
#
# The same reasoning is why GOAL 2c exists. R1.3 closed with a residual ~4%
# length dependence (3.5-4.9%, `last_ledger_mode()`'s whole-file fallback,
# +78.7 us, reports/R1.3/PROFIL.md) under a 10% ceiling. When the daemon removes
# process spawn the DENOMINATOR shrinks, so that percentage GROWS. KOSU-RABADON
# says R7 re-measures it in its own acceptance. That re-measurement is only
# meaningful with the daemon up, so it is bound to the daemon here.
#
# NO ASSERTION MAY PASS VACUOUSLY. A missing daemon, a missing harness name, a
# missing JSONL or an empty ledger is RED, never a skip. Where a file merely
# existing would be enough to go green, the check reads its CONTENT.
# ---------------------------------------------------------------------------
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; cd "$ROOT"
GATE="$ROOT/native/rabadon-gate"
GATED="$ROOT/native/rabadon-gated"
AUDITBIN="$ROOT/native/rabadon-audit"   # GOAL 3 requires it; see the CEVAP block there
RD="$ROOT/reports/R7"
P_N=0; F_N=0
pass(){ printf 'PASS  %s\n' "$1"; P_N=$((P_N+1)); }
fail(){ printf 'FAIL  %s\n' "$1"; F_N=$((F_N+1)); }
note(){ printf '      %s\n' "$1"; }
head_(){ printf '\n== %s\n' "$1"; }
# WAITING FOR THE SOCKET (operator CEVAP, reports/kosu/6.operator.md).
# The old readiness loop was `for _ in $(seq 50); do [ -S "$SOCK" ] && break; done`
# with no sleep in it: measured, that whole loop is ~2-3 ms, most of it the
# $(seq 50) fork. A daemon needs 21.8-22.6 ms just to bind, and a minimal
# reference daemon whose FIRST act is bind+listen still lost 10 of 10 tries to
# that loop, with the socket appearing ~300 ms later. So the loop was timing a
# race, not testing a daemon. The requirement does NOT loosen: the socket is
# still MANDATORY and its absence is still red -- only the wait becomes real,
# and it stays CAPPED. `sleep 0.1` is fractional on GNU and BSD userland; on a
# strict POSIX sleep that rejects it, the fallback ticks a whole second, which
# makes the cap slower, never absent.
sock_bekle(){ # $1 = socket path; 0 if it appeared inside the cap (10 s)
  local i=0
  while [ "$i" -lt 100 ]; do
    [ -S "$1" ] && return 0
    sleep 0.1 2>/dev/null || sleep 1
    i=$((i+1))
  done
  [ -S "$1" ]
}
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
jstr(){ python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }
[ -x "$GATE" ] || { echo "FAIL no gate binary — build first (make)"; echo "R7 NOT ACCEPTED"; exit 1; }

sb(){ H="$(mktemp -d "$W/h.XXXXXX")"; PJ="$(mktemp -d "$W/p.XXXXXX")"
  mkdir -p "$H/.rabadon/spool" "$PJ/.git"; printf 'ref: refs/heads/main\n' >"$PJ/.git/HEAD"; : >"$H/.rabadon/enabled"; }
ev(){ printf '{"hook_event_name":"PreToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
  "$1" "$PJ" "$(jstr "$2")"; }

############################################################################
head_ "GOAL 1 — the daemon and the thin client exist at all"
# Three separate claims. A binary that exists but never binds a socket is not a
# daemon, and a client that runs the gate unconditionally is not a client.

if [ -x "$GATED" ]; then
  pass "1a rabadon-gated exists and is executable"
  GATED_OK=1
else
  fail "1a no rabadon-gated binary — the persistent daemon is not built"
  note "this is the whole speed half of R7; without it GOALs 2 and 3 measure nothing"
  GATED_OK=0
fi

GSRC=""
for c in native/gated.cpp native/daemon.cpp native/gated.h; do [ -f "$c" ] && GSRC="$c" && break; done
if [ -n "$GSRC" ] && grep -q 'AF_UNIX' "$GSRC" && grep -qE '\blisten\s*\(' "$GSRC"; then
  pass "1b $GSRC binds and listens on a unix socket (a daemon, not a one-shot)"
else
  fail "1b no daemon source that binds AF_UNIX and listens"
  note "searched native/gated.cpp, native/daemon.cpp, native/gated.h"
fi

# The client must PREFER the socket and FALL BACK to today's in-process path.
# Fail-open (allow on daemon absence) is the one outcome that is worse than no
# daemon at all, so the check demands the fallback be visible in the source.
CSRC=""
for c in native/gate.cpp native/gated_client.h native/client.h; do
  [ -f "$c" ] && grep -q 'RABADON_GATED_SOCK\|rabadon-gated.sock\|gated.sock' "$c" && CSRC="$c" && break
done
if [ -n "$CSRC" ]; then
  pass "1c a thin client path referencing the daemon socket exists ($CSRC)"
else
  fail "1c nothing in the gate reaches for a daemon socket — there is no thin client"
fi

############################################################################
head_ "GOAL 2 — with the daemon up, the gate's median is under 1 ms (in-process)"
# CEILING: 1000 us, from KOSU-RABADON R7 ("daemon acikken kapi medyani < 1 ms").
# Measured with the R1.3 in-process probe and nothing else — see the header.
# The probe is deliberately NOT built when the daemon is absent: building it
# would patch a copy of a gate source that has no daemon in it, and a median
# taken from that binary would be a number about today's gate wearing R7's
# label. A goal that cannot be measured is red, never skipped.
SOCK="$W/rabadon-gated.sock"
DAEMON_UP=0
if [ "$GATED_OK" = 1 ]; then
  sb; DH="$H"; DPJ="$PJ"
  env HOME="$DH" RABADON_DIR="$DH/.rabadon" RABADON_GATED_SOCK="$SOCK" "$GATED" >"$W/gated.log" 2>&1 &
  DPID=$!
  sock_bekle "$SOCK" && DAEMON_UP=1
  if [ "$DAEMON_UP" = 1 ]; then pass "2a the daemon started and its socket is listening"
  else fail "2a rabadon-gated did not produce a listening socket at $SOCK"; note "$(tail -2 "$W/gated.log" 2>/dev/null | tr '\n' ' ')"; fi
  kill "$DPID" 2>/dev/null
else
  fail "2a the daemon cannot be started — it does not exist"
fi

if [ "$DAEMON_UP" != 1 ]; then
  fail "2b the < 1 ms median was NOT measured: no daemon to measure with"
  note "ceiling is 1000 us in-process; the instrument is the R1.3 probe (header)"
  fail "2c the residual length dependence was NOT re-measured under the daemon"
  note "R1.3 closed at 3.5-4.9% under a 10% ceiling with process spawn IN the"
  note "denominator; the daemon removes spawn, so the same absolute cost reads as"
  note "a LARGER percentage. The plan requires R7 to re-read it. Unread today."
else
  # Build the R1.3 probe against the daemon-aware gate source and take a median
  # over 300 warmed calls with the daemon up.
  PROBE_DIR="$W/probe"; PGATE="$PROBE_DIR/rabadon-gate-probe"; PROBE_OK=0
  mkdir -p "$PROBE_DIR" && cp native/*.h "$PROBE_DIR"/ 2>/dev/null
  python3 - native/gate.cpp "$PROBE_DIR/gate_probe.cpp" <<'PY' 2>/dev/null
import sys
src = open(sys.argv[1]).read()
PROBE = r'''
// ---- in-process probe, added to a COPY under /tmp by reports/R7/accept.sh ----
#include <chrono>
static std::chrono::steady_clock::time_point g_rbp_t0;
static void rbprobe_dump() {
  const char* p = getenv("RABADON_PROBE_OUT");
  if (!p || !*p) return;
  const double us = std::chrono::duration<double, std::micro>(
      std::chrono::steady_clock::now() - g_rbp_t0).count();
  char buf[64];
  const int n = snprintf(buf, sizeof buf, "%.1f\n", us);
  const int fd = open(p, O_WRONLY | O_APPEND | O_CREAT, 0644);
  if (fd < 0) return;
  ssize_t w = write(fd, buf, (size_t)n); (void)w;
  close(fd);
}
static void rbprobe_begin() { g_rbp_t0 = std::chrono::steady_clock::now(); atexit(rbprobe_dump); }
// ---- end probe ----

'''
a = "int main(int argc, char** argv) {"
assert src.count(a) == 1, "main() anchor is not unique"
open(sys.argv[2], "w").write(src.replace(a, PROBE + a + "\n  rbprobe_begin();"))
PY
  if [ -s "$PROBE_DIR/gate_probe.cpp" ] && \
     ${CXX:-c++} -std=c++17 -O2 -I "$PROBE_DIR" -o "$PGATE" "$PROBE_DIR/gate_probe.cpp" 2>"$W/probe.log"; then PROBE_OK=1; fi

  if [ "$PROBE_OK" != 1 ]; then
    fail "2b the in-process instrument did not build — the median was NOT measured"
    note "$(tail -3 "$W/probe.log" 2>/dev/null | tr '\n' ' ')"
    fail "2c the residual length dependence was NOT re-measured (no instrument)"
  else
    env HOME="$DH" RABADON_DIR="$DH/.rabadon" RABADON_GATED_SOCK="$SOCK" "$GATED" >>"$W/gated.log" 2>&1 &
    DPID=$!; sock_bekle "$SOCK"
    sb; EVX="$(ev speed 'echo hello world')"; O="$W/med"
    for _ in $(seq 60);  do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK" "$PGATE" >/dev/null 2>&1; done
    for _ in $(seq 300); do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK" RABADON_PROBE_OUT="$O" "$PGATE" >/dev/null 2>&1; done
    MED="$(python3 -c "
import statistics,sys
v=[float(x) for x in open(sys.argv[1])] if __import__('os').path.exists(sys.argv[1]) else []
print(f'{statistics.median(v):.1f}' if v else 'NONE')" "$O")"
    if [ "$MED" = NONE ]; then
      fail "2b the probe produced no samples — the median was NOT measured"
    else
      note "in-process median with the daemon up: ${MED} us over 300 samples"
      note "ceiling = 1000 us (KOSU-RABADON R7); instrument = R1.3 in-process probe"
      if [ "$(python3 -c "print(1 if float('$MED')<1000.0 else 0)")" = 1 ]; then
        pass "2b the gate's median is ${MED} us with the daemon up, under the 1000 us ceiling"
      else
        fail "2b the gate's median is ${MED} us with the daemon up, ceiling is 1000 us"
      fi
    fi

    # 2c — re-measure the residual length dependence, daemon up. Same shape as
    # R1.3 GOAL 6: two sandboxes, one seeded to 50 events and one to 400, BOTH
    # seeded before EITHER is timed, then interleaved call by call so drift
    # lands on both arms in the same millisecond.
    sb; HA="$H"; PA="$PJ"; EVA="$(ev d 'echo hello world')"
    sb; HB="$H"; PB="$PJ"; EVB="$(ev d 'echo hello world')"
    for _ in $(seq 50);  do printf '%s' "$EVA" | env HOME="$HA" RABADON_DIR="$HA/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK" "$PGATE" >/dev/null 2>&1; done
    for _ in $(seq 400); do printf '%s' "$EVB" | env HOME="$HB" RABADON_DIR="$HB/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK" "$PGATE" >/dev/null 2>&1; done
    OA="$W/l50"; OB="$W/l400"
    for _ in $(seq 250); do
      printf '%s' "$EVA" | env HOME="$HA" RABADON_DIR="$HA/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK" RABADON_PROBE_OUT="$OA" "$PGATE" >/dev/null 2>&1
      printf '%s' "$EVB" | env HOME="$HB" RABADON_DIR="$HB/.rabadon" RABADON_NOTIFY=0 RABADON_GATED_SOCK="$SOCK" RABADON_PROBE_OUT="$OB" "$PGATE" >/dev/null 2>&1
    done
    R="$(python3 -c "
import statistics,sys,os
def r(p):
    return [float(x) for x in open(p)] if os.path.exists(p) else []
a,b=r(sys.argv[1]),r(sys.argv[2])
if not a or not b: print('NONE'); raise SystemExit
ma,mb=statistics.median(a),statistics.median(b)
print(f'{ma:.1f} {mb:.1f} {abs(mb-ma)/min(ma,mb)*100:.2f}')" "$OA" "$OB")"
    kill "$DPID" 2>/dev/null
    if [ "$R" = NONE ]; then
      fail "2c the length-dependence re-measurement produced no samples"
    else
      read -r M50 M400 PCT <<<"$R"
      note "50-event session: ${M50} us   400-event session: ${M400} us   divergence ${PCT}%"
      note "R1.3 closed this at 3.5-4.9% WITH process spawn in the denominator"
      # The number must be RECORDED, not just printed, because the plan asks R7
      # to carry it forward. A run that prints and forgets proves nothing later.
      if [ -f "$RD/LENGTH.md" ] && grep -qE '[0-9]+\.[0-9]+%' "$RD/LENGTH.md"; then
        pass "2c the residual length dependence is re-measured (${PCT}%) and written to reports/R7/LENGTH.md"
      else
        fail "2c measured ${PCT}% but reports/R7/LENGTH.md does not record it"
      fi
    fi
  fi
fi

############################################################################
head_ "GOAL 3 — with the daemon down, behaviour is byte-identical to today"
# fail-SAME, not fail-open. Three surfaces, compared against the SAME gate run
# with no daemon variable set at all: exit code, ledger lines, refusal text.
if [ "$GATED_OK" != 1 ] || [ -z "$CSRC" ]; then
  fail "3a exit codes with the daemon down are UNCOMPARED — there is no client path to compare"
  fail "3b ledger lines with the daemon down are UNCOMPARED"
  fail "3c refusals with the daemon down are UNCOMPARED"
  note "with no client, 'the daemon is down' is indistinguishable from today by"
  note "construction, and a comparison that cannot fail is not evidence"
elif [ ! -x "$AUDITBIN" ]; then
  # NOT A SKIP. `prev` is blanked in the comparison below, and the only thing
  # that buys that signal back is the in-arm audit. Without the binary GOAL 3
  # would go green on a chain nobody checked, so it is RED instead.
  fail "3a exit codes with the daemon down are UNCOMPARED — native/rabadon-audit is missing, run make"
  fail "3b ledger lines with the daemon down are UNCOMPARED"
  fail "3c refusals with the daemon down are UNCOMPARED"
  note "GOAL 3 blanks the chain's prev field and pays for it with an INTACT audit"
  note "inside each arm; with no auditor that payment cannot be made"
else
  DEAD="$W/definitely-not-a-socket.sock"
  # IDENTITY, NOT BEHAVIOUR (operator CEVAP, reports/kosu/6.operator.md).
  # Two runs of the same command differ in fields that name the RUN rather than
  # describe what the gate DID, and no honest implementation can make them
  # match: the runId is "ng-<ms>-<pid>" (native/gate.cpp:2738) and a pid cannot
  # be pinned; `pipe` is the sandbox directory's basename (gate.cpp:2737); and
  # the refusal text prints the real project path. Those are blanked HERE, in
  # the instrument. They are NOT blanked in the gate: normalising a path inside
  # the product would print the user a directory that does not exist.
  # STILL COMPARED, byte for byte: exit code, `ev`, mode, rule, the refusal
  # text itself, and the NUMBER and ORDER of ledger lines.
  #
  # THE CHAIN FIELDS (operator CEVAP, reports/kosu/7.operator.md — option (d)).
  # `prev` is the SHA-256 of the previous line in its UNNORMALISED form
  # (native/chain.h:191,200-204: the hash is taken over `chained`, the raw line),
  # so it commits to that line's real `ts`/`run`/`pipe`. Those differ between any
  # two runs by construction, therefore `prev` differs, therefore no honest
  # implementation can make two runs match on it. Demanding it is demanding that
  # time not pass. The `.head` sidecar is `<64hex> <line count>`; only its hash
  # moves. Both are blanked here, NARROWLY:
  #   - only a 64-hex `prev` is blanked. "genesis" and a MISSING prev stay
  #     visible, because a prev that vanishes is a real behavioural signal.
  #   - only the leading hash of `.head` is blanked. THE COUNTER STAYS, so a run
  #     that writes a different number of chained lines still diverges. (The
  #     `^[0-9a-f]{64} ` anchor cannot match a ledger line: those start with `{`.)
  # WHAT THIS WOULD OTHERWISE HIDE, and how it is bought back: blinding `prev`
  # hides the chain's LINK ARITHMETIC — a prev computed correctly but taken from
  # the WRONG line would slip through. So GOAL 3 now runs rabadon-audit inside
  # EACH arm (see `denetle` below) and requires INTACT. The blinding above is
  # valid ONLY with that check; stop asking two runs to share a hash they cannot
  # share, and instead prove the chain is sound WITHIN each run. That is a
  # strengthening, not a loosening.
  #
  # REJECTED, permanently: computing the chain over the NORMALISED line to make
  # it deterministic. It measures as deterministic, and it is forbidden — the
  # chain would then not commit to ts/run/path, so an attacker could rewrite a
  # timestamp and the ledger would still verify. Destroying the product's
  # tamper-evidence to pass a test is the exact move this project exists to
  # refuse.
  kimliksiz(){ sed -E -e "s|$H|SBHOME|g" -e "s|$PJ|SBPROJ|g" \
                      -e 's/"ts":[0-9]+/"ts":T/g' \
                      -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z?/TS/g' \
                      -e 's/"run":"ng-[0-9]+-[0-9]+"/"run":"RUN"/g' \
                      -e 's/"pipe":"[^"]*"/"pipe":"PIPE"/g' \
                      -e 's/"prev":"[0-9a-f]{64}"/"prev":"PREV"/g' \
                      -e 's/^[0-9a-f]{64} /HASH /'; }
  # MANDATORY (same CEVAP, clause 3): verify THIS arm's spool in place, before
  # anything is compared. Writes a single verdict token so the audit's own
  # output — which is full of per-run hashes — never enters the comparison.
  denetle(){ # $1 = arm tag
    local o r
    o="$(env HOME="$H" RABADON_DIR="$H/.rabadon" "$AUDITBIN" --days 2 2>&1)"; r=$?
    if [ "$r" -eq 0 ] && printf '%s' "$o" | grep -q 'verdict: INTACT'; then
      printf 'INTACT' > "$W/zincir.$1"
    else
      printf 'BROKEN(rc=%s)' "$r" > "$W/zincir.$1"
      printf '%s\n' "$o" > "$W/zincir.$1.out"
    fi
  }
  run3(){ # $1 = extra env, $2 = command, $3 = arm tag
    sb; local out rc
    out="$(printf '%s' "$(ev s7 "$2")" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 $1 "$GATE" 2>"$W/e3")"; rc=$?
    denetle "$3"
    { printf '%s\n%s\n' "$rc" "$out"; cat "$W/e3"
      ls "$H"/.rabadon/spool/* >/dev/null 2>&1 && cat "$H"/.rabadon/spool/*
    } | kimliksiz
  }
  for CMD in 'echo hello world' 'rm -rf /' 'git commit --no-verify -m x'; do
    rm -f "$W"/zincir.A "$W"/zincir.B "$W"/zincir.A.out "$W"/zincir.B.out
    A="$(run3 '' "$CMD" A)"; B="$(run3 "RABADON_GATED_SOCK=$DEAD" "$CMD" B)"
    ZA="$(cat "$W/zincir.A" 2>/dev/null)"; ZB="$(cat "$W/zincir.B" 2>/dev/null)"
    if [ "$ZA" != INTACT ] || [ "$ZB" != INTACT ]; then
      fail "3-[$CMD] the hash chain is not INTACT inside the run (daemon up: ${ZA:-NOT RUN}, daemon down: ${ZB:-NOT RUN})"
      note "prev is blanked in the comparison, so the chain's link arithmetic is"
      note "proven HERE or not at all — a broken chain cannot be a green"
      cat "$W"/zincir.A.out "$W"/zincir.B.out 2>/dev/null | head -6 | sed 's/^/      /'
    elif [ -z "$A" ]; then
      fail "3-[$CMD] the baseline run produced nothing — an empty comparison is not a green"
    elif [ "$A" = "$B" ]; then
      pass "3-[$CMD] chain INTACT in both arms; exit code, ledger lines and refusal text are byte-identical with the daemon down"
    else
      fail "3-[$CMD] behaviour diverges when the daemon is down — this is not fail-SAME"
      diff <(printf '%s\n' "$A") <(printf '%s\n' "$B") | head -6 | sed 's/^/      /'
    fi
  done
fi

############################################################################
head_ "GOAL 4 — the harness is named, exactly, with its commit"
# Terminal-Bench names four different things. Without the full repo name AND the
# commit, none of the five numbers is comparable to anything, so an unnamed
# harness fails the whole round rather than degrading it.
KNOWN='laude-institute/terminal-bench|harbor-framework/terminal-bench-2|harbor-framework/harbor|alibaba/terminal-bench-pro|SWE-bench/SWE-smith|swesmith/SWE-smith'
if [ -d "$RD" ]; then pass "4a reports/R7/ exists"; else fail "4a reports/R7/ does not exist — nowhere for the evidence to land"; fi
HFILE=""
for f in "$RD"/HARNESS.md "$RD"/harness.json "$RD"/HARNESS.txt; do [ -f "$f" ] && HFILE="$f" && break; done
if [ -n "$HFILE" ] && grep -qE "$KNOWN" "$HFILE"; then
  pass "4b the harness is named by full repo: $(grep -oE "$KNOWN" "$HFILE" | head -1)"
else
  fail "4b no reports/R7/HARNESS.md naming a known harness by org/repo"
  note "one of: laude-institute/terminal-bench, harbor-framework/terminal-bench-2,"
  note "harbor-framework/harbor, alibaba/terminal-bench-pro, SWE-smith"
fi
if [ -n "$HFILE" ] && grep -qE '\b[0-9a-f]{40}\b' "$HFILE"; then
  pass "4c the harness commit hash is pinned (40 hex)"
else
  fail "4c no 40-hex commit hash for the harness — 'Terminal-Bench' alone points at four repos"
fi
# Cursor's 25.06 preparation, and its own honest label. Without it the agent
# finds the answer in the git history and BOTH arms inflate, which does not show
# up as a bug — it shows up as two good-looking numbers.
if [ -n "$HFILE" ] && grep -qi 'git' "$HFILE" && grep -qiE 'egress|network' "$HFILE" && grep -qi 'best.effort' "$HFILE"; then
  pass "4d the Cursor preparation is recorded: .git cleaned, egress closed, labelled best-effort"
else
  fail "4d the .git-cleaning / egress-closing preparation is not recorded (with its best-effort label)"
fi

############################################################################
head_ "GOAL 5 — the raw run lands here, and can be re-run"
# THE RUN IS NAMED, NOT GUESSED. This was `ls "$RD"/*.jsonl | head -1`, which
# picked whatever sorted first among THREE jsonl files here — ab_run.jsonl and two
# deliberately INVALID ones. It happened to pick the right file ('.' sorts before
# '_'), but that is luck, not a rule: a new jsonl with an alphabetically earlier
# name would silently point the whole of GOALs 5 and 6 at the wrong data and the
# acceptance would still print numbers. Named explicitly; a missing file is red.
JL="$RD/ab_run.jsonl"
if [ -n "$JL" ] && [ -s "$JL" ]; then
  pass "5a raw JSONL is under reports/R7/ and is not empty ($(basename "$JL"))"
else
  fail "5a no non-empty *.jsonl under reports/R7/ — a summary is not the evidence"
fi
if [ -n "$JL" ] && [ -s "$JL" ]; then
  S="$(python3 - "$JL" <<'PY'
import json,sys,collections
arms=collections.defaultdict(set)
n=0
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    try: r=json.loads(line)
    except Exception: continue
    n+=1
    a=str(r.get("arm","")).upper()
    t=r.get("task") or r.get("task_id") or r.get("instance_id")
    if a and t: arms[a].add(str(t))
ok = set(arms)>={"A","B"} and min((len(v) for v in arms.values()), default=0)>=2
print("OK" if ok else "BAD", n, len(arms.get("A",())), len(arms.get("B",())))
PY
)"
  read -r VERD NREC NA NB <<<"$S"
  note "records: $NREC   distinct tasks — arm A: $NA, arm B: $NB"
  if [ "$VERD" = OK ]; then
    pass "5b both arms are present per-task in the raw records (A:$NA tasks, B:$NB tasks)"
  else
    fail "5b the JSONL is not a two-armed per-task record (A:$NA tasks, B:$NB tasks)"
  fi
else
  fail "5b no JSONL to check for two arms"
fi
# bench/reproduce.sh already exists for other numbers, so its mere existence is
# a vacuous green here. It must actually re-run THIS run.
if [ -f bench/reproduce.sh ] && grep -qiE 'R7|two.arm|arm B' bench/reproduce.sh; then
  pass "5c bench/reproduce.sh re-runs the two-armed run"
else
  fail "5c bench/reproduce.sh exists but says nothing about R7's two-armed run"
fi

############################################################################
head_ "GOAL 6 — the five numbers, each of them, from the raw data"
FIVE="$W/five"
if [ -n "$JL" ] && [ -s "$JL" ]; then
  python3 - "$JL" >"$FIVE" 2>/dev/null <<'PY'
import json,sys,collections
rows=[]
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    try: rows.append(json.loads(line))
    except Exception: pass
def arm(a): return [r for r in rows if str(r.get("arm","")).upper()==a]
out={}
for a in ("A","B"):
    R=arm(a)
    if not R: continue
    fixed=[r for r in R if "heldout_pass" in r]
    out[f"fix_{a}"]=(sum(1 for r in fixed if r["heldout_pass"])/len(fixed)*100) if fixed else None
    out[f"heldout_{a}"]=len(fixed)
    tk=[r.get("tokens") for r in R if isinstance(r.get("tokens"),(int,float))]
    out[f"tok_{a}"]=sum(tk) if tk else None
    iv=[r.get("interventions") for r in R if isinstance(r.get("interventions"),(int,float))]
    out[f"iv_{a}"]=sum(iv) if iv else None
    fp=[r.get("false_positive") for r in R if r.get("false_positive") is not None]
    out[f"fp_{a}"]=(sum(1 for x in fp if x)/len(fp)*100) if fp else None
    cs=[r.get("total_cost_usd") for r in R if isinstance(r.get("total_cost_usd"),(int,float))]
    out[f"cost_{a}"]=sum(cs) if cs else None
est=[r.get("estimated_saved") for r in arm("B") if isinstance(r.get("estimated_saved"),(int,float))]
out["est"]=sum(est) if est else None
for k,v in out.items():
    print(k, "NONE" if v is None else f"{v:.4f}")
PY
fi
g(){ awk -v k="$1" '$1==k{print $2}' "$FIVE" 2>/dev/null; }
have(){ v="$(g "$1")"; [ -n "$v" ] && [ "$v" != NONE ]; }

if have fix_A && have fix_B && [ "$(g heldout_A)" != 0 ] && [ "$(g heldout_B)" != 0 ]; then
  pass "6a real fix rate from a HELD-OUT test: A $(g fix_A)% / B $(g fix_B)% ($(g heldout_A)+$(g heldout_B) judged)"
else
  fail "6a no held-out fix rate in the raw data (field 'heldout_pass' per task, both arms)"
  note "the agent's own test does not count — that is the metric it is optimising"
fi
if have tok_A && have tok_B; then pass "6b tokens spent: A $(g tok_A) / B $(g tok_B)"
else fail "6b token totals are missing from the raw data"; fi
if have iv_A && have iv_B; then pass "6c human interventions: A $(g iv_A) / B $(g iv_B)"
else fail "6c human intervention counts are missing from the raw data"; fi
if have fp_A && have fp_B; then pass "6d false positive rate: A $(g fp_A)% / B $(g fp_B)%"
else fail "6d false positive rates are missing from the raw data"; fi
# 6e compares rabadon's OWN saving claim against the harness's MEASURED cost.
# Both sides are DOLLARS. Until turn 20 the right-hand side was `tok_A - tok_B`,
# a TOKEN count: the check compared a dollar figure to a token figure, and it
# printed pass() on every value because it carried no threshold. A check that
# cannot turn red is not a check. Fixed under operator CEVAP 2 of turn 19.
# The two sides come from DIFFERENT sources and this is what keeps 6e honest:
#   est  = rabadon's claim, produced by its own counter (`saved_usd`)
#   real = cost_A - cost_B, measured by the harness off the CLI stream
# Deriving `real` from rabadon's own numbers would make it a tautology; it is not.
if have est && have cost_A && have cost_B; then
  DEV="$(python3 -c "
e=float('$(g est)'); real=float('$(g cost_A)')-float('$(g cost_B)')
print('NODIFF' if real==0 else f'{abs(e-real)/abs(real)*100:.1f}')")"
  if [ "$DEV" = NODIFF ]; then
    fail "6e the two arms cost the same dollars — the counter cannot be validated against a zero difference"
  elif [ "$(python3 -c "print(1 if float('$DEV')<=50.0 else 0)")" = 1 ]; then
    pass "6e counter validation: claim \$$(g est) vs measured difference \$$(python3 -c "print(round(float('$(g cost_A)')-float('$(g cost_B)'),4))"), deviation ${DEV}% (limit 50%)"
  else
    fail "6e counter validation FAILED: rabadon claims \$$(g est) saved, the measured cost difference is \$$(python3 -c "print(round(float('$(g cost_A)')-float('$(g cost_B)'),4))") — deviation ${DEV}%, over the 50% limit"
  fi
else
  fail "6e counter validation impossible: no 'estimated_saved' total on arm B, or no per-arm total_cost_usd"
  DEV=""
fi

############################################################################
head_ "GOAL 7 — the falsification conditions are checkable, and checked"
# These are the plan's own conditions, written before the result was seen. They
# are part of THIS round: a run that cannot evaluate them has not tested the
# thesis, it has only produced numbers.
if have fix_A && have fix_B && have tok_A && have tok_B; then
  V="$(python3 -c "
fa,fb=float('$(g fix_A)'),float('$(g fix_B)'); ta,tb=float('$(g tok_A)'),float('$(g tok_B)')
print('IMPROVED' if (fb>fa or tb<ta) else 'FLAT')")"
  if [ "$V" = IMPROVED ]; then
    pass "7a falsification 1 evaluated: arm B improves on fix rate or net tokens — the injection thesis stands"
  else
    fail "7a falsification 1 TRIGGERED: arm B improves neither real fix rate nor net tokens"
    note "per KOSU-RABADON, the injection thesis is wrong; the accumulation engine"
    note "goes silent and the product position is rethought. The M3 piece still ships."
  fi
else
  fail "7a falsification 1 is UNCHECKABLE — the numbers it needs are not in the data"
fi
if [ -n "${DEV:-}" ] && [ "$DEV" != NODIFF ]; then
  if [ "$(python3 -c "print(1 if float('$DEV')<=50.0 else 0)")" = 1 ]; then
    pass "7b falsification 2 evaluated: counter deviates ${DEV}%, at or under 50% — the dollar line may be published"
  else
    fail "7b falsification 2 TRIGGERED: counter deviates ${DEV}% from the measured cost difference (limit 50%)"
    note "the dollar line comes out of the closing line, the README and the landing"
    note "page the same day; only the error count stays until the formula is refixed"
  fi
else
  fail "7b falsification 2 is UNCHECKABLE — no deviation could be computed"
fi

############################################################################
head_ "GOAL 8 — nothing already standing fell over"
if OUT="$(./native/moves_test.sh 2>&1)" && printf '%s' "$OUT" | grep -q 'moves: 22 passed, 0 failed'; then
  pass "8a native/moves_test.sh 22/0"
else
  fail "8a native/moves_test.sh is not 22 passed / 0 failed: $(printf '%s' "$OUT" | tail -1)"
fi
if OUT="$(./native/signals_test.sh 2>&1)" && printf '%s' "$OUT" | grep -q 'signals: 39 passed, 0 failed'; then
  pass "8b native/signals_test.sh 39/0"
else
  fail "8b native/signals_test.sh is not 39 passed / 0 failed: $(printf '%s' "$OUT" | tail -1)"
fi
if OUT="$(./reports/R2/accept.sh 2>&1)" && printf '%s' "$OUT" | grep -q 'R2 acceptance: 19 green, 0 red'; then
  pass "8c reports/R2/accept.sh 19 green, 0 red"
else
  fail "8c reports/R2/accept.sh is not 19 green / 0 red: $(printf '%s' "$OUT" | grep 'acceptance:' | tail -1)"
fi

printf '\n== R7 acceptance: %d green, %d red\n' "$P_N" "$F_N"
[ "$F_N" -gt 0 ] && { printf 'R7 NOT ACCEPTED\n'; exit 1; }
printf 'R7 ACCEPTED\n'; exit 0
