#!/usr/bin/env bash
# reports/phase-3/accept.sh — the gate for phase 3, written BEFORE phase 3 runs,
# by an agent that will not implement phase 3 (AGENTS-PROTOCOL.md, Kapı 1).
#
# ===========================================================================
# WHAT PHASE 3 OWES
# ===========================================================================
#   AGENTS-PROTOCOL.md, "Faz 3 — kapsam düzeltmesi", verbatim:
#
#     Kapsam    : netRed kökle birlikte yazılsın, kök eşleşmezse red-base
#                 ateşlemesin. project_root() cwd'ye düştüyse red-base devre
#                 dışı. Check'in üçüncü hali could-not-run. Mod katmanlı:
#                 env -> proje -> makine. ~/.rabadon/enabled + mode.last tek
#                 dosyaya insin.
#     Kapsam dışı: repair.cpp, korpus, ui/.
#     Kabul     : bir dizin kırmızıyken komşu dizinde ateşlemediğini gösteren
#                 yeni test.
#     Rapor     : mevcut testlerden kaçı kırıldı ve neden.
#     Durma     : mevcut bir test kırılıyorsa dur — silme, zayıflatma.
#
#   THE BUG, MEASURED BEFORE THIS FILE WAS WRITTEN, not quoted from the
#   protocol. Everything below was run against the binaries in native/ on
#   2026-08-20 and the exit codes are transcribed:
#
#     gate.cpp:1949  netRed is read from `cwd + "/.rabadon/net.json"` and
#                    nothing else. The verdict does not say which tree it is
#                    about, so ANY red verdict sitting at that path is acted on.
#     net.cpp:147    rabadon-net writes `<dir>/.rabadon/net.json` with exactly
#                    {ts, level, kind, cmd, verdict, exit, dur_ms, tail}.
#                    There is no root, no repo, no identity of any kind.
#
#   Two sibling repos A (really broken) and B (really green), both checked by
#   the real rabadon-net, RABADON_DIR on a scratch dir with the switch on:
#
#     PreToolUse `git commit -m wip` in A ...................... exit 2   right
#     PreToolUse `git commit -m wip` in B ...................... exit 0   right
#     cp A/.rabadon/net.json B/.rabadon/net.json, then in B .... exit 2   WRONG
#     mv A A2, then PreToolUse in A2 ........................... exit 2   WRONG
#
#   That is the whole of it. A red verdict is a portable object: it refuses work
#   in whatever directory it is standing in, including a directory that has
#   never been checked and a directory that no longer exists under that name.
#   The protocol calls this "kapsam" — scope — and it is right: the gate is
#   refusing outside the tree the evidence came from.
#
#   The rest of the phase is the same disease in the other three state files.
#   The mode is machine-global with exactly one project-level word (`.rabadon/on`
#   can only turn supervision ON, never off), so one machine setting governs
#   every repo on the disk. `~/.rabadon/enabled` and `~/.rabadon/mode.last` are
#   two files holding one fact, and they disagree the moment anyone touches
#   either with `rm`. And a check that CANNOT RUN is filed under the same word
#   as a check that ran and timed out, so "rabadon has no idea" and "rabadon
#   asked and got no answer" are one state with one name.
#
# ===========================================================================
# WHAT THIS SCRIPT REFUSES TO ASSUME
# ===========================================================================
#   1. It refuses to accept a test file as evidence. The protocol's Kabul is a
#      NEW TEST, and this gate does require one (clause 7). But the acceptance
#      itself is measured HERE: this script builds the two-directory layout
#      itself, runs the real rabadon-net to produce real verdicts from real
#      failing and passing suites, drives the real rabadon-gate with real
#      PreToolUse events, and reads the exit codes. If the implementer's new
#      test is theatre, clause 2 still fails. If clause 2 passes and the new
#      test is missing, clause 7 still fails. Neither can carry the other.
#
#   2. It refuses to grep C++ for a promise. Every clause below that could have
#      been written as `grep -q root native/net.cpp` is instead written as "run
#      the binary and look at what it wrote / what it did", because a comment
#      satisfies the grep and a comment refuses nothing. The only greps in this
#      file are over the OUTPUT of a program and over the Makefile's `test:`
#      recipe, which is a list of commands, not prose.
#
#   3. It refuses to touch the machine's live supervision. `~/.rabadon` on this
#      machine is running and watching the session that writes this file: it
#      holds a spool with 48 day-files, a live socket, a state.json and a
#      net.json from 03:50 today. Every gate invocation in this script sets
#      RABADON_DIR and HOME into a throwaway lab under $TMPDIR, exactly as
#      native/pushgate_test.sh does, and the script REFUSES TO START (exit 2)
#      if the lab cannot be made. Nothing here reads or writes the real one.
#
#   4. It refuses to believe "make test is green" without the count. Green is
#      cheap if you are allowed to delete the test that was red. Today's numbers
#      are measured, twice, and pinned below; a run with fewer test scripts or
#      fewer assertions fails no matter what the exit code says.
#
#   5. It refuses to let the phase weaken the tests it is most tempted to
#      weaken. Five test files are pinned by sha256 (clause 8). If one of them
#      genuinely has to change, that is a separate commit with a human's reason
#      on it (protocol Kapı 3, CLAUDE.md non-negotiable 1) — and this gate says
#      so out loud instead of shrugging.
#
#   6. It refuses to over-block in the name of scope. Every restrictive clause
#      has a twin that fails if the implementer "fixes" the leak by simply
#      switching red-base off. A red in its own directory must STILL stop the
#      next action (2.1, 3.1, 5.1); a verdict with no root at all must still
#      fire (2.6); a verdict inside its own worktree must still fire (3.3).
#      Deleting the feature does not pass this file.
#
# ===========================================================================
# THE CONTRACT PHASE 3 MUST SATISFY — this is the spec, build to it
# ===========================================================================
#
#   A. THE VERDICT CARRIES ITS ROOT.
#      rabadon-net gains ONE field in `<dir>/.rabadon/net.json`:
#
#          "root":"<absolute path of rbpath::project_root(dir), symlink-resolved>"
#
#      The name is `root`, spelled exactly that way, because this gate reads it.
#      Everything else in the object keeps its current name and meaning.
#
#   B. THE RULE red-base FIRES BY.
#      At PreToolUse, red-base may fire only when
#
#          net.json has no "root"           -> fire   (legacy verdict, see D)
#          root == project_root(cwd)        -> fire
#          anything else                    -> DO NOT FIRE
#
#      compared after symlink resolution on both sides. That single rule is the
#      whole of "kök eşleşmezse ateşlemesin" AND, in the only form that does not
#      contradict a sealed test, the whole of "project_root() cwd'ye düştüyse
#      red-base devre dışı" — see D.
#
#   C. THE THIRD STATE.
#      `verdict` gains the value `could-not-run`, spelled exactly that way.
#      It is written when there is nothing to run (net.cpp's level==0 / empty
#      cmd path, which today writes `inconclusive` with the tail "no runnable
#      check found in this project"). It never refuses anything.
#      `inconclusive` STAYS, and keeps meaning "we ran it and got no usable
#      answer" — a check that blows its budget is still `inconclusive`
#      (native/net_test.sh:89 asserts this and is sealed). The point of the
#      third state is to TELL THE TWO APART, not to rename one of them.
#
#   D. WHY B IS NOT THE LITERAL SECOND SENTENCE OF THE PROTOCOL, and this is the
#      one place this gate knowingly reads the protocol rather than transcribing
#      it — so it is written down instead of buried.
#
#      "project_root() cwd'ye düştüyse red-base devre dışı" read literally means
#      "if cwd is not inside any git worktree, red-base never fires".
#      native/redbase_test.sh — the file that proves red-base works at all —
#      runs its entire fixture in `mktemp -d` directories that are NOT git
#      repositories. Measured: `git rev-parse --show-toplevel` fails there, and
#      project_root() therefore falls back to cwd for every single one of that
#      file's ~25 assertions. The literal reading turns that whole file red.
#      Protocol Faz 3 Durma says: if an existing test breaks, STOP. So the
#      literal reading makes the phase impossible by construction.
#
#      The rule in B produces the SAFE half of that sentence with no
#      contradiction, because a fallback root is a root that can only ever equal
#      its own directory:
#
#        - fallback root, cwd IS that directory -> match -> fires
#          (redbase_test.sh's world, untouched — and clause 3.1 keeps it)
#        - fallback root, cwd is a CHILD of it  -> project_root(child)==child
#          != root -> does not fire (clause 3.2). A directory that is not a
#          repository has no subtree, so its verdict governs nothing but itself.
#        - real repo root, cwd anywhere in that worktree -> match -> fires
#          (clause 3.3). Inside one project the verdict still travels, which is
#          the difference between a scope fix and an amputation.
#
#      If the implementer believes the literal reading is required anyway, that
#      is a CHALLENGE to the protocol (CLAUDE.md, "If PROJECT.md itself is
#      wrong"): stop, write it in reports/phase-3/discards.txt with the exit
#      codes, and let a human amend AGENTS-PROTOCOL.md in its own commit. Do not
#      resolve it by editing redbase_test.sh.
#
#   E. THE MODE IS LAYERED: env -> project -> machine. First one that speaks
#      wins; nothing below it is consulted.
#
#          env      RABADON_MODE=enforce|watch      (highest)
#          project  <cwd>/.rabadon/mode             one word, one line
#          machine  <RABADON_DIR>/mode              one word, one line
#
#      - An unrecognised RABADON_MODE value must NOT be read as "watch". A
#        switch that cannot be read enforces and says so — that law already
#        exists in gate.cpp:1760 ("blind") and this only extends it (5.7).
#      - An override is for THIS shell / THIS project. Reading RABADON_MODE must
#        never rewrite the machine file (5.8). A layer that corrupts the layer
#        beneath it is worse than no layer.
#      - The legacy per-project `<cwd>/.rabadon/on` keeps working (5.9), and so
#        does `<cwd>/.rabadon/off` and RABADON_OFF=1 — none of those is in
#        scope and other suites hold them.
#      - `silent` is deliberately NOT required of the env layer. RABADON_OFF=1
#        and `<RABADON_DIR>/silent` already say it, and inventing a fourth way
#        to switch a guard off is not a scope fix. If the implementer supports
#        RABADON_MODE=silent anyway, nothing here objects.
#
#   F. ONE FILE FOR THE MODE.
#      `<RABADON_DIR>/enabled` and `<RABADON_DIR>/mode.last` collapse into
#
#          <RABADON_DIR>/mode      first line is exactly one of:
#                                  enforce | watch | silent
#
#      After the collapse the gate creates NEITHER `enabled` NOR `mode.last`,
#      not from the CLI (`--on`/`--off`/`--silent`) and not from a hook event.
#      Two things must survive it, and they are the reason this is a clause and
#      not a chore:
#
#        - MIGRATION (6.5). An installed user has `enabled` and no `mode`. If
#          the new build reads that as "no mode file, therefore watch", every
#          existing install is silently unsupervised after an upgrade. A dir
#          holding only the legacy `enabled` must still ENFORCE.
#        - THE RECORD (6.6). `mode.last` existed for one reason: to catch
#          supervision being switched off with `rm` instead of `rabadon off`,
#          and to put a MODE line with "outOfBand":true on the hash-chained
#          ledger (gate.cpp:530 note_mode; native/mode_wrong_test.sh). Measured
#          today: it works. Collapsing to one file removes the second copy the
#          comparison was made against — the ledger's own last MODE line is the
#          remaining source, and the spool is already open on that code path.
#          Losing this is not a side effect of the collapse; it is the collapse
#          done wrong.
#
#      `<RABADON_DIR>/silent` is left alone. The protocol names two files and
#      this gate does not extend it.
#
#   G. THE PAPERWORK (devir kuralı + Rapor + Durma).
#          reports/phase-3/CLAIM.md      non-empty, one page, read by humans
#          reports/phase-3/discards.txt  non-empty, and carrying a line the
#                                        machine can read:
#
#                                            broken_tests=<N>
#
#                                        followed by, for each one, which test
#                                        and why. N must be 0 to pass: the
#                                        protocol's Durma is "if an existing
#                                        test breaks, STOP", so a truthful
#                                        non-zero N is a correct report AND a
#                                        failed acceptance. Both at once. That
#                                        is the intended shape of this gate.
#
# ===========================================================================
# WHAT THIS GATE DOES **NOT** CHECK, and why — no silent gaps
# ===========================================================================
#   - THE LIVE MACHINE'S OWN net.json. `~/.rabadon/net.json` on this machine
#     right now holds a REAL verdict:
#
#       {"level":3,"cmd":"python3 -m pytest -q","verdict":"inconclusive",
#        "exit":-1,"dur_ms":120035,"tail":"check exceeded its 120000ms budget"}
#
#     Something ran rabadon-net against the home directory. It came back
#     inconclusive, so nothing was refused. Had it come back RED, every session
#     whose cwd is $HOME would have been refused on the strength of a pytest run
#     that belongs to no project. ($HOME here IS a git repo — a dotfiles repo —
#     so project_root does not even fall back, and clause B's root match would
#     hold and FIRE.) Whether "the directory that holds rabadon's own state is
#     not a project rabadon supervises" should be a rule is a real question and
#     the protocol does not answer it. No clause is written for it, because
#     (a) inventing the rule is not this file's job and (b) checking it honestly
#     would mean touching the real ~/.rabadon, which point 3 above forbids.
#     Written here so it is on the record instead of lost.
#
#   - PERFORMANCE. Every clause here adds a stat() or a string compare to the
#     hot path; none of it is timed. native/gate_bench.sh exists and CLAUDE.md
#     asks for the number in the session log. That belongs in CLAIM.md, not in
#     an exit code, so this gate does not pretend to measure it.
#
#   - THE JS SIDE. core/, hooks/ and ui/ carry their own suites; `make test`
#     covers what it covers and this gate pins that, no more. ui/ is out of
#     scope for the phase anyway.
#
#   - CONCURRENCY. Two sessions in two repos at once is the situation this whole
#     phase is about, and nothing here runs two gates in parallel. The clauses
#     are sequential and single-flight.
#
# ===========================================================================
# TODAY'S NUMBERS — measured on 2026-08-20, twice, before this file was written
# ===========================================================================
#     make test                       exit 0, both runs
#     scripts in the `test:` recipe   94, all named in TESTS_TODAY below
#     "ok" assertion lines            3322, both runs, byte-identical totals
#     total output lines              4178, both runs
#   The assertion floor is a FLOOR, not an equality: adding tests is the point.
#   Both runs agreeing is why it is safe to pin at all — a flaky number pinned
#   as a floor is a gate that fails honest work.
#
#   Runtime of this script: the behavioural clauses take ~15 s; `make test` at
#   the end takes ~5 min. It is last on purpose, so a broken behaviour fails
#   fast and nobody waits five minutes to learn it.
#
# ===========================================================================
# EXIT CODES
# ===========================================================================
#   0  every clause held
#   1  a clause failed — the reason is printed, nothing is inferred
#   2  cannot run at all (no bash/git/node/make, binaries not built, no lab).
#      NOT a pass and NOT a silent skip: "I cannot check this" is a designed
#      state (CLAUDE.md, Promise 1).
#
# USAGE
#   bash reports/phase-3/accept.sh [repo-root]

set -u

REPO="${1:-$(cd "$(dirname "$0")/../.." && pwd -P)}"
cd "$REPO" || { echo "accept: cannot cd into $REPO"; exit 2; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
sec()  { printf '\n== %s\n' "$1"; }
die2() { printf 'accept: CANNOT RUN — %s\n' "$1"; exit 2; }

# ---------------------------------------------------------------------------
# 0. can this even run?  (exit 2, never a quiet pass)
# ---------------------------------------------------------------------------
sec "0. premises"

for t in git node make mktemp awk sed grep; do
  command -v "$t" >/dev/null 2>&1 || die2 "$t is not on PATH"
done
if   command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"
elif command -v shasum    >/dev/null 2>&1; then SHA="shasum -a 256"
else die2 "no sha256sum and no shasum: the seal cannot be read"; fi

GATE="$REPO/native/rabadon-gate"
NET="$REPO/native/rabadon-net"
[ -x "$GATE" ] || die2 "native/rabadon-gate is not built (make native/rabadon-gate)"
[ -x "$NET"  ] || die2 "native/rabadon-net is not built (make native/rabadon-net)"
[ -f "$REPO/Makefile" ] || die2 "no Makefile at $REPO"

LAB="$(mktemp -d 2>/dev/null)" || die2 "mktemp -d failed: no scratch space"
LAB="$(cd "$LAB" && pwd -P)" || die2 "cannot resolve the lab path"
case "$LAB" in
  ""|"/"|"$HOME"|"$HOME"/.rabadon*) die2 "refusing to use $LAB as a lab" ;;
esac
cleanup() { chmod -R u+w "$LAB" 2>/dev/null; rm -rf "$LAB"; }
trap cleanup EXIT INT TERM

# Everything from here runs with HOME and RABADON_DIR inside the lab. The real
# ~/.rabadon is live and is supervising this session; it is never named again.
export HOME="$LAB/home"
export GIT_CONFIG_GLOBAL="$LAB/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export RABADON_JUDGE=0
mkdir -p "$HOME" || die2 "cannot make a fake HOME in the lab"
: > "$GIT_CONFIG_GLOBAL"
echo "  lab: $LAB (HOME and RABADON_DIR both redirected here)"

# --- the two things every clause is built out of ----------------------------

# mkproj <dir> <tag> <returns>   a real git repo with a real node suite.
#   returns=1 -> the suite passes.  returns=2 -> it fails, printing BOOM-<tag>.
mkproj() {
  mkdir -p "$1/src" || return 1
  git init -q "$1" >/dev/null 2>&1 || return 1
  printf '{"name":"p%s","scripts":{"test":"node test.js"}}' "$2" > "$1/package.json"
  printf 'const a=require("./src/a.js");if(a()!==1){console.error("BOOM-%s");process.exit(1)}console.log("ok")\n' \
    "$2" > "$1/test.js"
  printf 'module.exports = () => %s;\n' "$3" > "$1/src/a.js"
}

# fire <cwd> <rabadon-dir> [ENV=VAL ...]   one PreToolUse `git commit`, exit code
fire() {
  local c="$1" rd="$2"; shift 2
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"acc3","tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' "$c" \
    | env RABADON_DIR="$rd" "$@" "$GATE" >/dev/null 2>&1
  echo $?
}
# same, but hands back what the gate SAID
firetext() {
  local c="$1" rd="$2"; shift 2
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","session_id":"acc3","tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' "$c" \
    | env RABADON_DIR="$rd" "$@" "$GATE" 2>&1
}
# the product's own way to set the machine mode, so these clauses do not depend
# on which file the machine mode lives in (that is clause 6's business).
machine_on()  { RABADON_DIR="$1" "$GATE" --on  >/dev/null 2>&1; }
machine_off() { RABADON_DIR="$1" "$GATE" --off >/dev/null 2>&1; }

jfield() { grep -o "\"$2\":\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed 's/.*":"//; s/"$//'; }
realpath_of() { (cd "$1" 2>/dev/null && pwd -P); }

# the shared fixture: two neighbouring repos, one really broken, one really fine
RD="$LAB/rdir"; mkdir -p "$RD"
machine_on "$RD"
A="$LAB/work/a"; B="$LAB/work/b"
mkproj "$A" A 2 || die2 "could not build the broken fixture repo"
mkproj "$B" B 1 || die2 "could not build the healthy fixture repo"
"$NET" "$A" >/dev/null 2>&1
"$NET" "$B" >/dev/null 2>&1
[ -f "$A/.rabadon/net.json" ] || die2 "rabadon-net wrote no verdict for the broken repo"
[ -f "$B/.rabadon/net.json" ] || die2 "rabadon-net wrote no verdict for the healthy repo"
grep -q '"verdict":"red"'   "$A/.rabadon/net.json" || die2 "the broken fixture did not come back red: $(cat "$A/.rabadon/net.json")"
grep -q '"verdict":"green"' "$B/.rabadon/net.json" || die2 "the healthy fixture did not come back green: $(cat "$B/.rabadon/net.json")"
ok "premise: two neighbouring repos, checked for real — A red, B green"

# ---------------------------------------------------------------------------
# 1. the verdict says which tree it is about          (contract A)
# ---------------------------------------------------------------------------
sec "1. netRed is written together with its root"

AROOT="$(jfield "$A/.rabadon/net.json" root)"
if [ -n "$AROOT" ]; then
  ok "rabadon-net writes a \"root\" field into net.json"
else
  bad "net.json carries no \"root\": $(cat "$A/.rabadon/net.json")"
fi

case "$AROOT" in
  /*) ok "the root is an absolute path ($AROOT)" ;;
  "") bad "no root to judge" ;;
  *)  bad "the root is not absolute: '$AROOT' — a relative root names a different tree from every cwd" ;;
esac

WANT="$(realpath_of "$A")"
GOT=""; [ -n "$AROOT" ] && GOT="$(realpath_of "$AROOT")"
if [ -n "$GOT" ] && [ "$GOT" = "$WANT" ]; then
  ok "and it resolves to the tree that was actually checked"
else
  bad "the recorded root is not the checked tree: root='$AROOT' -> '$GOT', expected '$WANT'"
fi

# ---------------------------------------------------------------------------
# 2. THE PROTOCOL'S ACCEPTANCE, driven here and not delegated to a test file
#    "bir dizin kırmızıyken komşu dizinde ateşlemediğini gösteren"
# ---------------------------------------------------------------------------
sec "2. a red in one directory does not refuse work in its neighbour"

E="$(fire "$A" "$RD")"
[ "$E" = "2" ] && ok "2.1 the real red still stops the next action in its OWN directory (exit 2)" \
               || bad "2.1 red-base no longer fires where it should: exit $E — the feature was removed, not scoped"

E="$(fire "$B" "$RD")"
[ "$E" = "0" ] && ok "2.2 the healthy neighbour is not refused while it is green (exit 0)" \
               || bad "2.2 a green repo was refused: exit $E"

cp "$A/.rabadon/net.json" "$B/.rabadon/net.json"
E="$(fire "$B" "$RD")"
if [ "$E" = "0" ]; then
  ok "2.3 A's verdict, standing in B's directory, refuses NOTHING (exit 0)"
else
  bad "2.3 the neighbour was blocked by A's verdict: exit $E — a verdict is still a portable object"
fi
rm -f "$B/.rabadon/net.json"

mv "$A" "$LAB/work/a2" 2>/dev/null
A2="$LAB/work/a2"
if [ -f "$A2/.rabadon/net.json" ]; then
  E="$(fire "$A2" "$RD")"
  if [ "$E" = "0" ]; then
    ok "2.4 a verdict whose tree has been renamed out from under it refuses nothing (exit 0)"
  else
    bad "2.4 a stale verdict for a path that no longer exists still refused work: exit $E"
  fi
else
  bad "2.4 could not stage the rename case"
fi

# the twin: fix it for real, re-check for real, and the refusal must come back
# to being about THIS tree — this is what stops "just disable red-base".
printf 'module.exports = () => 2;\n' > "$A2/src/a.js"
"$NET" "$A2" >/dev/null 2>&1
if grep -q '"verdict":"red"' "$A2/.rabadon/net.json" 2>/dev/null; then
  E="$(fire "$A2" "$RD")"
  [ "$E" = "2" ] && ok "2.5 re-checked in its new home, the same red refuses again (exit 2)" \
                 || bad "2.5 a freshly measured red in the very directory it was measured in did not fire: exit $E"
else
  bad "2.5 could not re-measure the red after the rename: $(cat "$A2/.rabadon/net.json" 2>/dev/null)"
fi
printf 'module.exports = () => 1;\n' > "$A2/src/a.js"
"$NET" "$A2" >/dev/null 2>&1
E="$(fire "$A2" "$RD")"
[ "$E" = "0" ] && ok "2.5b and a real pass clears it, with no flag and no restart (exit 0)" \
               || bad "2.5b the refusal survived a green check: exit $E — the session is wedged"

# backwards compatibility, and the reason redbase_test.sh keeps passing:
# a verdict with NO root is a legacy verdict, not a foreign one.
LEG="$LAB/work/legacy"; mkproj "$LEG" L 2 || die2 "could not build the legacy fixture"
mkdir -p "$LEG/.rabadon"
printf '{"ts":9999999999999,"level":3,"kind":"suite","cmd":"npm test --silent","verdict":"red","exit":1,"dur_ms":1,"tail":"LEGACY-BOOM"}' \
  > "$LEG/.rabadon/net.json"
E="$(fire "$LEG" "$RD")"
[ "$E" = "2" ] && ok "2.6 a verdict written before this phase (no root at all) still fires (exit 2)" \
               || bad "2.6 every pre-existing verdict was silently disarmed: exit $E"

OUT="$(firetext "$LEG" "$RD")"
case "$OUT" in *red-base*) ok "2.6b the refusal still names the rule" ;;
                        *) bad "2.6b the refusal no longer names red-base: $OUT" ;; esac

# ---------------------------------------------------------------------------
# 3. a root that fell back to cwd governs itself and nothing else  (contract D)
# ---------------------------------------------------------------------------
sec "3. a fallback root has no subtree"

ND="$LAB/nonrepo"                 # deliberately NOT a git repository
mkdir -p "$ND/src"
printf '{"name":"nr","scripts":{"test":"node test.js"}}' > "$ND/package.json"
printf 'const a=require("./src/a.js");if(a()!==1){console.error("BOOM-NR");process.exit(1)}console.log("ok")\n' > "$ND/test.js"
printf 'module.exports = () => 2;\n' > "$ND/src/a.js"
if git -C "$ND" rev-parse --show-toplevel >/dev/null 2>&1; then
  die2 "the lab is inside a git worktree; the fallback clauses cannot be staged"
fi
"$NET" "$ND" >/dev/null 2>&1
if grep -q '"verdict":"red"' "$ND/.rabadon/net.json" 2>/dev/null; then
  E="$(fire "$ND" "$RD")"
  [ "$E" = "2" ] && ok "3.1 a project that is not a git repo is still supervised in its own dir (exit 2)" \
                 || bad "3.1 supervision was switched off for every non-git project: exit $E (this is redbase_test.sh's world)"
else
  bad "3.1 could not measure a red in the non-repo fixture: $(cat "$ND/.rabadon/net.json" 2>/dev/null)"
fi

mkdir -p "$ND/sub/.rabadon"
cp "$ND/.rabadon/net.json" "$ND/sub/.rabadon/net.json"
E="$(fire "$ND/sub" "$RD")"
[ "$E" = "0" ] && ok "3.2 but its verdict does not reach a child directory (exit 0)" \
               || bad "3.2 a fallback root governed a subtree it never checked: exit $E"

# the twin: inside a REAL worktree the verdict still travels, or this is an
# amputation rather than a scope fix.
mkdir -p "$A2/pkg/.rabadon"
printf 'module.exports = () => 2;\n' > "$A2/src/a.js"
"$NET" "$A2" >/dev/null 2>&1
cp "$A2/.rabadon/net.json" "$A2/pkg/.rabadon/net.json"
E="$(fire "$A2/pkg" "$RD")"
[ "$E" = "2" ] && ok "3.3 inside one real worktree the verdict still applies from a subdirectory (exit 2)" \
               || bad "3.3 the fix over-blocks: a repo's own red stopped working from its own subdir: exit $E"
printf 'module.exports = () => 1;\n' > "$A2/src/a.js"
"$NET" "$A2" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# 4. the third state                                        (contract C)
# ---------------------------------------------------------------------------
sec "4. could-not-run is its own state"

NOCHK="$LAB/nothing"; mkdir -p "$NOCHK"
printf 'just a file\n' > "$NOCHK/README"
PRINTED="$("$NET" "$NOCHK" --print 2>/dev/null)"
if printf '%s' "$PRINTED" | grep -q '"verdict":"could-not-run"'; then
  ok "4.1 a project with nothing to run is COULD-NOT-RUN, not inconclusive"
else
  bad "4.1 no third state: $PRINTED"
fi
if grep -q '"verdict":"could-not-run"' "$NOCHK/.rabadon/net.json" 2>/dev/null; then
  ok "4.1b and that is what lands on disk, not only on stdout"
else
  bad "4.1b net.json disagrees with --print: $(cat "$NOCHK/.rabadon/net.json" 2>/dev/null)"
fi
TAIL="$(jfield "$NOCHK/.rabadon/net.json" tail)"
[ -n "$TAIL" ] && ok "4.1c and it still says WHY in plain language: $TAIL" \
               || bad "4.1c could-not-run with an empty tail — the user is told a word, not a reason"

# it must refuse nothing. staged in a real repo so the root matches and the only
# thing standing between this and a refusal is the verdict itself.
CNR="$LAB/work/cnr"; mkproj "$CNR" C 1 || die2 "could not build the could-not-run fixture"
"$NET" "$CNR" >/dev/null 2>&1
CNRROOT="$(jfield "$CNR/.rabadon/net.json" root)"
{
  printf '{"ts":9999999999999,"level":0,"kind":"none","cmd":"","verdict":"could-not-run","exit":-1,"dur_ms":0,"tail":"no runnable check found in this project"'
  [ -n "$CNRROOT" ] && printf ',"root":"%s"' "$CNRROOT"
  printf '}'
} > "$CNR/.rabadon/net.json"
E="$(fire "$CNR" "$RD")"
[ "$E" = "0" ] && ok "4.2 could-not-run refuses nothing — not knowing is not evidence (exit 0)" \
               || bad "4.2 the new state wedges the session: exit $E"

# and inconclusive must NOT have been renamed away: a check that blew its budget
# ran, and "it ran and told me nothing" is a different fact from "there was
# nothing to run". native/net_test.sh:89 is sealed on this.
TMO="$LAB/timeout"; mkdir -p "$TMO"
printf 'x = 1\n' > "$TMO/app.py"
printf 'test:\n\tsleep 30\n' > "$TMO/Makefile"
RABADON_NET_CAP_MS=800 "$NET" "$TMO" >/dev/null 2>&1
if grep -q '"verdict":"inconclusive"' "$TMO/.rabadon/net.json" 2>/dev/null; then
  ok "4.3 a check that blows its budget is still INCONCLUSIVE — the two states are told apart"
else
  bad "4.3 inconclusive was renamed rather than split: $(cat "$TMO/.rabadon/net.json" 2>/dev/null)"
fi
grep -q '"verdict":"green"' "$TMO/.rabadon/net.json" 2>/dev/null \
  && bad "4.3b a timed-out check was called green" \
  || ok "4.3b and a timed-out check is never green"

# ---------------------------------------------------------------------------
# 5. the mode is layered: env -> project -> machine          (contract E)
# ---------------------------------------------------------------------------
sec "5. env beats project beats machine"

M="$LAB/work/mode"; mkproj "$M" M 2 || die2 "could not build the mode fixture"
"$NET" "$M" >/dev/null 2>&1
grep -q '"verdict":"red"' "$M/.rabadon/net.json" || die2 "the mode fixture did not go red"
RM="$LAB/rmode"; mkdir -p "$RM"

machine_on "$RM"
E="$(fire "$M" "$RM")"
[ "$E" = "2" ] && ok "5.1 machine=enforce, no overrides: the red refuses (exit 2)" \
               || bad "5.1 machine enforce did not enforce: exit $E"

E="$(fire "$M" "$RM" RABADON_MODE=watch)"
[ "$E" = "0" ] && ok "5.2 RABADON_MODE=watch overrides an enforcing machine (exit 0)" \
               || bad "5.2 the env layer does not exist: exit $E"

printf 'watch\n' > "$M/.rabadon/mode"
E="$(fire "$M" "$RM")"
[ "$E" = "0" ] && ok "5.3 a project can say watch even when the machine says enforce (exit 0)" \
               || bad "5.3 the project layer cannot turn supervision down: exit $E"

E="$(fire "$M" "$RM" RABADON_MODE=enforce)"
[ "$E" = "2" ] && ok "5.5 env beats project: RABADON_MODE=enforce over a watching project (exit 2)" \
               || bad "5.5 the project layer outranked the env layer: exit $E"
rm -f "$M/.rabadon/mode"

machine_off "$RM"
E="$(fire "$M" "$RM")"
[ "$E" = "0" ] && ok "5.4a machine=watch, no overrides: nothing is refused (exit 0)" \
               || bad "5.4a a watching machine refused an action: exit $E"

E="$(fire "$M" "$RM" RABADON_MODE=enforce)"
[ "$E" = "2" ] && ok "5.4b RABADON_MODE=enforce turns it on for this shell alone (exit 2)" \
               || bad "5.4b the env layer cannot turn supervision UP: exit $E"

printf 'enforce\n' > "$M/.rabadon/mode"
E="$(fire "$M" "$RM")"
[ "$E" = "2" ] && ok "5.6 project beats machine in the other direction too (exit 2)" \
               || bad "5.6 a project could not turn supervision up: exit $E"
rm -f "$M/.rabadon/mode"

machine_on "$RM"
E="$(fire "$M" "$RM" RABADON_MODE=bananas)"
[ "$E" = "2" ] && ok "5.7 an unreadable RABADON_MODE does not weaken the gate — it enforces (exit 2)" \
               || bad "5.7 any typo in RABADON_MODE switched supervision off: exit $E"

# an override is for one shell. it must not rewrite the machine's own setting.
fire "$M" "$RM" RABADON_MODE=watch >/dev/null
STILL="$(fire "$M" "$RM")"
[ "$STILL" = "2" ] && ok "5.8 an env override does not rewrite the machine's setting (still enforcing)" \
                   || bad "5.8 RABADON_MODE=watch permanently disarmed the machine: exit $STILL"

# the legacy per-project switch is not in scope and must keep working
machine_off "$RM"
: > "$M/.rabadon/on"
E="$(fire "$M" "$RM")"
[ "$E" = "2" ] && ok "5.9 the legacy per-project .rabadon/on still forces enforce (exit 2)" \
               || bad "5.9 .rabadon/on stopped working: exit $E"
rm -f "$M/.rabadon/on"

# ---------------------------------------------------------------------------
# 6. enabled + mode.last collapse into one file              (contract F)
# ---------------------------------------------------------------------------
sec "6. one file holds the mode"

RC="$LAB/rcollapse"; mkdir -p "$RC"
check_collapsed() { # <label> <expected word>
  local lbl="$1" want="$2" first=""
  if [ -f "$RC/mode" ]; then
    first="$(head -1 "$RC/mode" | tr -d ' \r\n')"
    [ "$first" = "$want" ] \
      && ok "6.$lbl <RABADON_DIR>/mode says '$want'" \
      || bad "6.$lbl <RABADON_DIR>/mode says '$first', expected '$want'"
  else
    bad "6.$lbl there is no <RABADON_DIR>/mode file at all"
  fi
  [ -e "$RC/enabled" ]  && bad "6.$lbl the old 'enabled' file was written anyway"  || ok "6.$lbl no 'enabled' file"
  [ -e "$RC/mode.last" ] && bad "6.$lbl the old 'mode.last' file was written anyway" || ok "6.$lbl no 'mode.last' file"
}
RABADON_DIR="$RC" "$GATE" --on     >/dev/null 2>&1; check_collapsed "1 (--on)"     enforce
RABADON_DIR="$RC" "$GATE" --off    >/dev/null 2>&1; check_collapsed "2 (--off)"    watch
RABADON_DIR="$RC" "$GATE" --silent >/dev/null 2>&1; check_collapsed "3 (--silent)" silent

# a hook event must not resurrect either file
RABADON_DIR="$RC" "$GATE" --on >/dev/null 2>&1
fire "$B" "$RC" >/dev/null
if [ -e "$RC/enabled" ] || [ -e "$RC/mode.last" ]; then
  bad "6.4 a hook event re-created enabled/mode.last: $(ls "$RC" | tr '\n' ' ')"
else
  ok "6.4 a hook event writes neither of the two old files"
fi

STATUS="$(RABADON_DIR="$RC" "$GATE" --status 2>&1)"
case "$STATUS" in
  *"$RC/mode"*) ok "6.4b --status names the collapsed file it read the mode from" ;;
  *)            bad "6.4b --status still points the user at the old file: $STATUS" ;;
esac

# MIGRATION. An installed user has 'enabled' and no 'mode'. If that reads as
# watch, every existing install goes unsupervised on upgrade, silently.
RLEG="$LAB/rlegacy"; mkdir -p "$RLEG"; : > "$RLEG/enabled"
printf 'module.exports = () => 2;\n' > "$M/src/a.js"
"$NET" "$M" >/dev/null 2>&1
if grep -q '"verdict":"red"' "$M/.rabadon/net.json"; then
  E="$(fire "$M" "$RLEG")"
  [ "$E" = "2" ] && ok "6.5 a dir holding only the legacy 'enabled' still ENFORCES — no silent disarm on upgrade" \
                 || bad "6.5 upgrading disarms every existing install: exit $E with only 'enabled' present"
else
  bad "6.5 could not stage the migration case"
fi

# THE RECORD mode.last existed for. Supervision removed by hand must still land
# on the hash-chained ledger as an out-of-band MODE line.
ROB="$LAB/roob"; mkdir -p "$ROB"
RABADON_DIR="$ROB" "$GATE" --on >/dev/null 2>&1
fire "$M" "$ROB" >/dev/null                       # the gate observes: enforce
rm -f "$ROB/mode" "$ROB/enabled" "$ROB/silent"    # switched off with rm, not with `rabadon off`
fire "$M" "$ROB" >/dev/null                       # the gate observes: watch
if grep -rl '"ev":"MODE"' "$ROB/spool" >/dev/null 2>&1 && \
   grep -rh '"ev":"MODE"' "$ROB/spool" 2>/dev/null | grep -q '"outOfBand":true'; then
  ok "6.6 supervision removed with rm still leaves an out-of-band MODE line on the ledger"
else
  bad "6.6 the collapse threw away the out-of-band record: $(grep -rho '\"ev\":\"[A-Z_]*\"' "$ROB/spool" 2>/dev/null | sort -u | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 7. the new test the protocol asks for                      (Kabul)
# ---------------------------------------------------------------------------
sec "7. a named test carries this into the suite"

# The 94 scripts the `test:` recipe ran on 2026-08-20, one per line. A quoted
# here-doc and a `while read`, NOT `for t in $LIST`: phase 2's gate was bitten by
# exactly this — zsh does not word-split an unquoted parameter, so a list held in
# a variable silently becomes ONE item and every check over it passes vacuously.
TODAY="$LAB/tests_today.txt"
cat > "$TODAY" <<'EOF'
native/agents_test.sh
native/arch_wrapper_test.sh
native/assign_prefix_test.sh
native/audit_test.sh
native/baseline_test.sh
native/blind_switch_test.sh
native/budget_test.sh
native/bypass_test.sh
native/claims_test.sh
native/cli_test.sh
native/cmdtext_test.sh
native/contract_test.sh
native/delete_verbs_test.sh
native/discovery_language_test.sh
native/discovery_test.sh
native/doctor_test.sh
native/drift_test.sh
native/export_drop_test.sh
native/export_test.sh
native/false_reject_test.sh
native/fd_dup_test.sh
native/field_census_test.sh
native/field_redaction_test.sh
native/gate_promise_test.sh
native/git_alias_test.sh
native/git_verbs_test.sh
native/glob_escape_test.sh
native/guard_allow_twin_test.sh
native/guard_deny_twin_test.sh
native/guard_lint_test.sh
native/guard_reach_test.sh
native/guard_subdir_test.sh
native/harness_lock_test.sh
native/head_ref_test.sh
native/heldout_test.sh
native/heredoc_reach_test.sh
native/identity_test.sh
native/lamp_test.sh
native/lease_force_test.sh
native/ledger_day_test.sh
native/ledger_utf8_test.sh
native/lens_test.sh
native/llm_proposer_test.sh
native/lock_coverage_test.sh
native/long_option_prefix_test.sh
native/loop_body_test.sh
native/loop_test.sh
native/mirror_push_test.sh
native/mode_wrong_test.sh
native/net_test.sh
native/npm_install_test.sh
native/other_repo_test.sh
native/partial_ref_test.sh
native/path_answer_test.sh
native/postuse_test.sh
native/precision_test.sh
native/promise_law_test.sh
native/publish_redaction_test.sh
native/publish_test.sh
native/push_config_file_test.sh
native/push_delete_test.sh
native/push_refspec_test.sh
native/pushgate_forge_test.sh
native/pushgate_test.sh
native/redbase_test.sh
native/regression_demo.sh
native/repair_isolation_test.sh
native/repair_session_test.sh
native/reserved_word_test.sh
native/route_test.sh
native/rule_census_test.sh
native/run_test.sh
native/sandbox_test.sh
native/script_wrapper_test.sh
native/serve_test.sh
native/session_fanout_test.sh
native/session_test.sh
native/shell_cwd_test.sh
native/shell_function_test.sh
native/short_cluster_test.sh
native/sigpipe_test.sh
native/site_claims_test.sh
native/stats_test.sh
native/temp_root_glob_test.sh
native/testverdict_test.sh
native/trace_test.sh
native/truth_level_order_test.sh
native/truth_test.sh
native/unknown_wrapper_test.sh
native/verify_test.sh
native/version_test.sh
native/watch_test.sh
native/wrapper_exec_test.sh
native/xcrun_wrapper_test.sh
EOF
N_TODAY="$(wc -l < "$TODAY" | tr -d ' ')"
[ "$N_TODAY" = "94" ] || die2 "this gate's own pinned list is $N_TODAY long, not 94 — it was edited"

RECIPE="$LAB/recipe.txt"
awk '/^test: all$/{f=1; next} f && /^[^\t#]/ {exit} f && /^\t/ {print}' "$REPO/Makefile" \
  | sed 's/^\t//; s/^\.\///' | grep -E '\.sh$' | sort -u > "$RECIPE"
N_NOW="$(wc -l < "$RECIPE" | tr -d ' ')"

MISSING=""
while IFS= read -r t; do
  [ -n "$t" ] || continue
  grep -qxF "$t" "$RECIPE" || MISSING="$MISSING $t(recipe)"
  [ -f "$REPO/$t" ]        || MISSING="$MISSING $t(file)"
done < "$TODAY"
[ -z "$MISSING" ] && ok "7.1 all 94 of today's test scripts are still in the recipe and still on disk" \
                  || bad "7.1 a test left the suite:$MISSING"

if [ "$N_NOW" -ge 95 ]; then
  ok "7.2 the recipe runs $N_NOW scripts — at least one NEW one was added (Kabul)"
else
  bad "7.2 the recipe still runs $N_NOW scripts: the protocol's Kabul is a NEW test, and none was added"
fi

grep -vxF -f "$TODAY" "$RECIPE" > "$LAB/newtests.txt"
if [ -s "$LAB/newtests.txt" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -x "$REPO/$f" ]; then
      bad "7.3 the new test $f is not executable"
    elif ( cd "$REPO" && "./$f" >"$LAB/newtest.log" 2>&1 ); then
      ok "7.3 the new test $f runs standalone and passes"
    else
      bad "7.3 the new test $f fails on its own: $(tail -3 "$LAB/newtest.log" | tr '\n' ' ')"
    fi
  done < "$LAB/newtests.txt"
else
  bad "7.3 no new test script to run"
fi

# ---------------------------------------------------------------------------
# 8. nothing was weakened to get there                       (Kapı 3, CLAUDE.md 1)
# ---------------------------------------------------------------------------
sec "8. the tempting tests are sealed"

sealed_check() { # <path> <sha>
  local got
  got="$($SHA "$REPO/$1" 2>/dev/null | awk '{print $1}')"
  if [ -z "$got" ]; then bad "8. $1 is gone"
  elif [ "$got" = "$2" ]; then ok "8. $1 unchanged"
  else bad "8. $1 CHANGED ($got). If it is genuinely wrong: its own commit, its own reason, a human's approval — not this phase's diff."
  fi
}
sealed_check native/redbase_test.sh   b362ea8ebd27ddbcbfd23978266b89b136ff97953e72b7006721dc4b37e87ee5
sealed_check native/net_test.sh       3de4840cd455d2bdb48733b2fc6f4cdd1291bab076942179fc0a33cca5c1d861
sealed_check native/mode_wrong_test.sh 819eb5af8ad6ff4d2c1b23c01c79d0d94ee27dade54fb802c4b3c69be33bd4fa
sealed_check native/other_repo_test.sh 807967aa93d8190051d386d0a22bb2a8b45bfed4c97739caae741a687443549a
sealed_check native/guard_subdir_test.sh 5162c293342f28d5e282f44b4039d5fedf96f507ed5de6375b05c32044eb3983

# ---------------------------------------------------------------------------
# 9. the paperwork the devir kuralı asks for                 (contract G)
# ---------------------------------------------------------------------------
sec "9. CLAIM.md and discards.txt"

CL="$REPO/reports/phase-3/CLAIM.md"
DC="$REPO/reports/phase-3/discards.txt"
[ -s "$CL" ] && ok "9.1 reports/phase-3/CLAIM.md exists and is not empty" \
             || bad "9.1 reports/phase-3/CLAIM.md is missing or empty"

if [ -s "$DC" ]; then
  ok "9.2 reports/phase-3/discards.txt exists and is not empty"
  BT="$(grep -oE '^broken_tests=[0-9]+' "$DC" | head -1 | cut -d= -f2)"
  if [ -z "$BT" ]; then
    bad "9.3 discards.txt carries no machine-readable 'broken_tests=<N>' line — the Rapor is prose, not a number"
  elif [ "$BT" = "0" ]; then
    ok "9.3 discards.txt reports broken_tests=0"
  else
    bad "9.3 discards.txt reports broken_tests=$BT — the protocol's Durma is STOP, so this is a correct report AND a failed acceptance"
  fi
else
  bad "9.2 reports/phase-3/discards.txt is missing or empty — 'mevcut testlerden kaçı kırıldı ve neden' is a required field"
fi

# Kapı 1: this file was committed once, before the implementation.
GL="$(cd "$REPO" && git log --oneline -- reports/phase-3/accept.sh 2>/dev/null | wc -l | tr -d ' ')"
if [ "$GL" = "1" ]; then
  ok "9.4 reports/phase-3/accept.sh has exactly one commit (Kapı 1)"
elif [ "$GL" = "0" ]; then
  bad "9.4 reports/phase-3/accept.sh is not committed — the gate is not sealed"
else
  bad "9.4 reports/phase-3/accept.sh has $GL commits: the gate was edited after it was written"
fi

# ---------------------------------------------------------------------------
# 10. make test — last, because it costs five minutes        (contract, note 4)
# ---------------------------------------------------------------------------
sec "10. make test, green, and no smaller than it was"

if [ "$FAIL" -ne 0 ]; then
  printf '  ----  SKIPPED: %d clause(s) already failed, so the phase is not accepted\n' "$FAIL"
  printf '        either way and the five minutes buy nothing. This is not a pass\n'
  printf '        and not a silent skip: it is announced, and the exit code below\n'
  printf '        is 1 regardless. Fix the clauses above, then re-run this file.\n'
  printf '\n---------------------------------------------------------------\n'
  printf 'phase 3 acceptance: %d ok, %d failed (make test not reached)\n' "$PASS" "$FAIL"
  exit 1
fi

MT="$LAB/maketest.log"
( cd "$REPO" && make test ) > "$MT" 2>&1
MTE=$?
[ "$MTE" = "0" ] && ok "10.1 make test exits 0" \
                 || bad "10.1 make test exits $MTE: $(grep -iE 'FAIL' "$MT" | tail -3 | tr '\n' ' ')"

OKS="$(grep -cE '^[[:space:]]+ok([[:space:]]|$)' "$MT")"
if [ "$OKS" -ge 3322 ]; then
  ok "10.2 $OKS assertions passed (floor 3322, measured twice today)"
else
  bad "10.2 the suite shrank: $OKS assertions, was 3322. Assertions were removed or skipped to reach green."
fi

# ---------------------------------------------------------------------------
printf '\n---------------------------------------------------------------\n'
printf 'phase 3 acceptance: %d ok, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  printf 'PASS — a red in one directory does not refuse work in its neighbour.\n'
  exit 0
fi
printf 'FAIL — phase 3 is not accepted. Nothing above was inferred; every line\n'
printf '       is an exit code or a file this script read for itself.\n'
exit 1
