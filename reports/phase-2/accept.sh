#!/usr/bin/env bash
# reports/phase-2/accept.sh — the gate for phase 2, written before phase 2 runs,
# by an agent that will not implement phase 2 (AGENTS-PROTOCOL.md, Kapı 1).
#
# ---------------------------------------------------------------------------
# WHAT PHASE 2 OWES
# ---------------------------------------------------------------------------
#   The cheat arm proves rabadon REFUSES fake fixes. A guard that refuses
#   everything scores exactly the same on that arm. The honest arm is the other
#   half of the claim: real repairs that rabadon must HOLD. Until now the honest
#   arm was four hand-written fixtures — a number that is a limit of patience,
#   not a property of the world.
#
#   Phase 2 replaces hand-writing with mining. native/mine_honest.sh walks a
#   real repository's own history, finds commits that touch source AND test,
#   reverts ONLY the source, and keeps a case only when the suite actually goes
#   RED and comes back GREEN on restore. The commit's own test is the witness;
#   the commit's own diff is the known-good fix.
#
#   Protocol, Faz 2, verbatim:
#     Kabul  : "her vaka için kaynak-only revert kırmızı, geri koyunca yeşil —
#               ikisi de loglanmış."
#     Rapor  : discards.txt written BY THE TOOL: scanned, kept, and eliminations
#               reason by reason, with max_hit.
#     Durma  : "eleme sayısı sıfırsa dur — filtre çalışmıyor."
#     Dışı   : native/heldout_test.sh and native/corpus_cheats.sh are sealed.
#
# ---------------------------------------------------------------------------
# WHAT THIS SCRIPT REFUSES TO ASSUME
# ---------------------------------------------------------------------------
#   1. It refuses to believe a case file. A directory full of plausible
#      artifacts is a claim, not a case. For a deterministic sample of cases
#      this script RE-RUNS THE WHOLE EXPERIMENT ITSELF: fresh scratch clone,
#      checkout the sha, prove green, reverse-apply the stored patch, demand
#      RED, restore, demand GREEN. A case that does not reproduce is not a
#      case; it is a fabricated case, and it fails this gate. This is the
#      strongest clause here and everything else is scaffolding around it.
#
#   2. It refuses to believe a number the implementing agent typed. Every count
#      is recomputed here: the kept count from `find <out> -name case.env`, the
#      elimination total from the per-reason rows, scanned from kept+discarded.
#      discards.txt is admissible only because mine_honest.sh writes it — so
#      mine_honest.sh's own bytes are PINNED below. Edit the miner and this
#      gate says so; the numbers it produced would otherwise describe a filter
#      nobody reviewed.
#
#   3. It refuses a zero elimination count, because the protocol says to. Zero
#      eliminations does not mean a clean repository, it means the filter did
#      not filter. Same for max_hit=yes: a run that hit a cap reports the shape
#      of the cap, not the shape of the data (Kapı 2). The cap must be off.
#
#   4. It refuses to touch, or let itself be blamed for touching, the mined
#      worktree. mine_honest.sh runs `git checkout --force` in the repository
#      it mines; a gate that did the same would race it and could destroy work.
#      Every re-run here happens in a throwaway `git clone --shared` under
#      $TMPDIR, with node_modules symlinked in read-only. The mined repository
#      is opened only with read-only plumbing (rev-parse, rev-list, log,
#      cat-file). If the scratch clone cannot be made, this script exits 2 —
#      it does NOT fall back to running in the real tree.
#
#   5. It refuses to let a flaky suite decide. Measured on this machine before
#      phase 2: express's suite is green (1265 passing) but flaked once in six
#      consecutive runs ("etag" / socket hang up). So GREEN is granted if any
#      of 3 attempts passes, and RED is granted only if TWO consecutive
#      attempts fail. A single spurious failure can therefore neither sink a
#      real case nor manufacture a fake one.
#
#   6. It refuses a red that is merely red. A fabricated case could ship any
#      failing log. The re-run's fresh failure output must name at least one of
#      the same FAILING TESTS the recorded red.log names. Same bug, or not the
#      same case. (Not an equal set: the flake in note 5 can add one failure to
#      either side. One name in common is the bar.)
#
#   7. It refuses to grade the phase on volume. There is a floor (below), and
#      above the floor extra cases buy nothing — they only add work, because
#      more cases mean more re-runs. Kapı 2 forbids handing an agent a target;
#      the floor here is the point below which the phase did not replace what
#      it was meant to replace.
#
# ---------------------------------------------------------------------------
# THE CONTRACT PHASE 2 MUST SATISFY (this is the spec; build to it)
# ---------------------------------------------------------------------------
#   A. WHERE. Cases live in, exactly:
#
#        reports/phase-2/honest-cases/
#
#      i.e. run the miner with OUT set to that absolute path. mine_honest.sh
#      refuses to write inside the repo it is MINING; the repo being mined is
#      express, not rabadon, so writing under reports/phase-2/ is allowed and
#      is required — the fixtures are the deliverable and they belong in git.
#      Case directories keep the miner's own naming: <commit-date>-<sha8>.
#      Anything else under honest-cases/ is ignored by this gate.
#
#   B. WHAT THE MINER WRITES, per case directory, all four, none empty:
#        case.env               sha= subject= check= source_files=
#                               source_file_count= test_files= expect=held
#        known-good-fix.patch   the source side of the commit
#        witness-test.patch     the test side of the commit
#        red.log               the recorded failure, verbatim
#
#   C. THE REPORT.
#        reports/phase-2/honest-cases/discards.txt   — written by the miner
#        reports/phase-2/discards.txt                — byte-identical copy,
#                                                      because AGENTS-PROTOCOL's
#                                                      devir kuralı puts it at
#                                                      reports/phase-N/
#        reports/phase-2/CLAIM.md                    — one page, non-empty.
#                                                      Read by humans. NOT
#                                                      evidence, and this gate
#                                                      never parses it.
#
#   D. WHAT WAS MINED. discards.txt must say:
#        check=npm test
#        repo=<a git repo whose root commit is express's:
#              9998490f93d3ad3d56c00d23c0aa13fac41c3f6b>
#        max_cases=0 and max_hit=no      (cap off; Kapı 2)
#        scan_depth>=400                 (the miner's own default; a shallower
#                                         scan is a smaller question, not a
#                                         faster answer)
#        discarded_total>=1              (Durma şartı)
#        scanned == kept + discarded_total
#        discarded_total == the five per-reason counts summed
#
#   E. HOW MANY. At least 4 cases, and every one of them must survive the
#      artifact clauses; the sampled ones must survive the re-run.
#
#      Why 4, and why not more: the honest arm it replaces was capped at four
#      hand-written fixtures, so anything below four is a regression dressed as
#      automation. Why not higher: this gate's author measured the yield before
#      writing this file, in a throwaway clone, at depth 400 —
#
#          scanned 400 · kept 4 · discarded 396
#            368 wrong shape · 28 nondeterministic
#            0 revert-would-not-apply · 0 checkout-failed · 0 did-not-go-red
#
#      The 28 are not a broken filter: node_modules on this machine is installed
#      for HEAD, so at older commits the suite is red before anything is
#      reverted, and the miner correctly refuses to call that a witness. Four is
#      what express plus one node_modules tree honestly yields. A higher floor
#      would block the phase on data the repository does not contain, which is
#      not a gate, it is a trap. If the implementer's run lands far from these
#      numbers, that is worth a paragraph in CLAIM.md either way.
#      (The four SHAs are deliberately NOT listed: run the miner, do not
#      transcribe an answer key.)
#
# ---------------------------------------------------------------------------
# THIS GATE WAS TESTED BEFORE IT WAS TRUSTED
# ---------------------------------------------------------------------------
#   Written 2026-08-20 and exercised the same day against a throwaway mined set
#   (produced in /tmp, deleted afterwards, never committed — the real run is the
#   implementer's). Full pass takes ~34 s. Deliberate cheats, all caught:
#     kept= edited by hand ............ caught by scanned == kept + discarded
#     a fifth case copied from a real one .. caught by the derived directory name
#     one case given another's red.log ..... caught by DIFFERENT-RED in the re-run
#     the fix patch replaced by a no-op ..... caught by REVERT-FAILED
#     one line appended to mine_honest.sh ... caught by the seal
#   None of those five is hypothetical; each was run and each printed a FAIL.
#
#   F. SEALED, per Faz 2 "Kapsam dışı" and Kapı 3. sha256 pinned below:
#        native/heldout_test.sh
#        native/corpus_cheats.sh
#        native/mine_honest.sh      <- sealed by THIS gate, additionally:
#                                      every number in discards.txt is only
#                                      worth reading because this exact filter
#                                      produced it.
#      If the miner genuinely has a bug, that is not something to work around.
#      Stop, write it and the evidence in reports/phase-2/discards.txt, and let
#      a human amend the miner in its own commit with its own justification
#      (CLAUDE.md non-negotiable 2, protocol Kapı 3).
#
# ---------------------------------------------------------------------------
# NOTES THE IMPLEMENTER WILL WANT (measured, not guessed)
# ---------------------------------------------------------------------------
#   - Run the miner with bash, not zsh. mine_honest.sh relies on unquoted word
#     splitting of its file lists ($srcfiles, $tf); zsh does not word-split by
#     default and every revert silently becomes "revert would not apply".
#     A run whose discards are ~all discarded_revert_would_not_apply is this.
#   - /tmp/express is a symlink to the real checkout; both paths are the same
#     repository, which is why clause D identifies the repo by its root commit
#     and not by its path.
#   - The suite is fast (~2 s), so re-running it is cheap; that is the only
#     reason clause 1 above is affordable.
#
# ---------------------------------------------------------------------------
# EXIT CODES
# ---------------------------------------------------------------------------
#   0  every clause held
#   1  a clause failed — the reason is printed, nothing is inferred
#   2  cannot run at all (no git, no npm, the mined repo is gone, no
#      node_modules to lend the scratch clone). NOT a pass, NOT a silent skip:
#      "I can't check this" is a designed state, per CLAUDE.md.
#
# USAGE
#   bash reports/phase-2/accept.sh [repo-root]

set -u

REPO="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO" || { echo "accept: cannot cd into $REPO"; exit 2; }

fail()  { echo "FAIL: $*"; exit 1; }
cannot(){ echo "CANNOT RUN: $*"; exit 2; }
ok()    { echo "  ok  $*"; }

P2="$REPO/reports/phase-2"
OUT="$P2/honest-cases"
MIN_CASES=4
EXPRESS_ROOT="9998490f93d3ad3d56c00d23c0aa13fac41c3f6b"
EXPECT_CHECK="npm test"
MIN_DEPTH=400
MAX_SAMPLE=8

echo "phase 2 acceptance — a mined case that does not reproduce is not a case"
echo "  repo: $REPO"

command -v git >/dev/null 2>&1 || cannot "git is absent; this gate re-runs git experiments"

SCRATCH=""
cleanup() { [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"; }
trap cleanup EXIT INT TERM

# --- clause: the sealed tools still hash the same -----------------------------
# name <TAB> sha256, captured 2026-08-20, before phase 2 started.
seal_check() {
  local rel="$1" want="$2" got
  [ -f "$REPO/$rel" ] || fail "$rel is GONE. it is sealed for this phase (Faz 2 kapsam dışı / Kapı 3)."
  got=$( (shasum -a 256 "$REPO/$rel" 2>/dev/null || sha256sum "$REPO/$rel" 2>/dev/null) | awk '{print $1}')
  [ -n "$got" ] || cannot "no shasum/sha256sum on this machine; cannot verify the seal on $rel"
  [ "$got" = "$want" ] || fail "$rel was MODIFIED during phase 2 (sha256 $got, sealed $want). \
Faz 2's kapsam dışı names it, Kapı 3 rejects the phase for it. If the change is genuinely \
needed, it is a separate commit with its own justification and human approval — not a \
side effect of making a gate pass."
}
seal_check native/heldout_test.sh   bd0a4bf1f3e2e32340ec4edc1f012eeeef737443b2b261d178f3568c8d9fd423
seal_check native/corpus_cheats.sh  98d688b1e6301e801f612d14cc53ef44f8b10d483a203882c99804dceb5a440b
seal_check native/mine_honest.sh    08e8c15db64be5f1945f8ff5137f08753f19bb5d971affb2f99249a9948879c8
ok "sealed: heldout_test.sh, corpus_cheats.sh, mine_honest.sh all unchanged"

# --- clause: Kapı 1 — this gate was written before the phase, and once --------
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  GATE_COMMITS=$(git -C "$REPO" log --oneline -- reports/phase-2/accept.sh | wc -l | tr -d ' ')
  [ "$GATE_COMMITS" = "1" ] || fail "git log -- reports/phase-2/accept.sh shows $GATE_COMMITS commit(s); \
Kapı 1 requires exactly one, made before the phase, by an agent that does not implement it. \
The gate was rewritten by whoever it was supposed to constrain."
  GATE_SHA=$(git -C "$REPO" log --format=%H -- reports/phase-2/accept.sh | head -1)
  GATE_FILES=$(git -C "$REPO" show --pretty= --name-only "$GATE_SHA" | grep -c . )
  [ "$GATE_FILES" = "1" ] || fail "the commit that introduced this gate ($GATE_SHA) touches \
$GATE_FILES files. Kapı 1's commit carries the gate and nothing else, or 'written before the \
phase' stops being checkable."
  ok "Kapı 1: one commit, one file — $(git -C "$REPO" log -1 --format=%h "$GATE_SHA")"
else
  cannot "$REPO is not a git repository; Kapı 1 cannot be verified here"
fi

# --- clause: the deliverables exist -------------------------------------------
[ -d "$OUT" ] || fail "$OUT does not exist. The contract fixes this path: the miner must be run \
with OUT=$OUT. Phase 2 has produced nothing to grade."
DISC="$OUT/discards.txt"
[ -f "$DISC" ] || fail "$DISC does not exist. That file is the miner's own elimination report and \
it is the ONLY admissible source for the numbers Kapı 2 demands."
[ -f "$P2/discards.txt" ] || fail "reports/phase-2/discards.txt does not exist. The devir kuralı \
puts discards.txt at reports/phase-N/; copy the miner's file there byte for byte."
cmp -s "$DISC" "$P2/discards.txt" || fail "reports/phase-2/discards.txt differs from the miner's \
$DISC. A hand-edited copy of a machine-written report is exactly the substitution Kapı 2 exists \
to catch."
[ -s "$P2/CLAIM.md" ] || fail "reports/phase-2/CLAIM.md is missing or empty (devir kuralı). It is \
read by humans and is not evidence, but a phase that cannot say what it did in one page did not \
finish."
ok "deliverables present: honest-cases/, discards.txt (both copies identical), CLAIM.md"

# --- clause: discards.txt is complete, self-consistent, and not capped --------
dget() { sed -n "s/^$1=//p" "$DISC" | head -1; }
for k in repo check scan_depth max_cases max_hit scanned kept discarded_total \
         discarded_wrong_shape discarded_revert_would_not_apply \
         discarded_checkout_failed discarded_did_not_go_red discarded_nondeterministic; do
  grep -q "^$k=" "$DISC" || fail "discards.txt has no '$k=' field. Kapı 2 requires the eliminations \
reason by reason; a missing field is a reason nobody counted."
done

D_REPO=$(dget repo); D_CHECK=$(dget check); D_DEPTH=$(dget scan_depth)
D_MAXC=$(dget max_cases); D_MAXHIT=$(dget max_hit)
D_SCANNED=$(dget scanned); D_KEPT=$(dget kept); D_DISC=$(dget discarded_total)
D_SHAPE=$(dget discarded_wrong_shape); D_NOREV=$(dget discarded_revert_would_not_apply)
D_CO=$(dget discarded_checkout_failed); D_NOTRED=$(dget discarded_did_not_go_red)
D_FLAKY=$(dget discarded_nondeterministic)

for v in "$D_DEPTH" "$D_MAXC" "$D_SCANNED" "$D_KEPT" "$D_DISC" "$D_SHAPE" "$D_NOREV" \
         "$D_CO" "$D_NOTRED" "$D_FLAKY"; do
  case "$v" in ''|*[!0-9]*) fail "discards.txt holds a non-numeric count: '$v'";; esac
done

[ "$D_CHECK" = "$EXPECT_CHECK" ] || fail "discards.txt says check='$D_CHECK'; the contract fixes \
'$EXPECT_CHECK'. A different check command means the red and the green in every case were judged \
by something this gate cannot re-run."

[ -d "$D_REPO" ] || cannot "the mined repository '$D_REPO' is not on this machine any more; the \
cases cannot be reproduced and nothing here can be verified"
MINED_ROOT=$(git -C "$D_REPO" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)
[ "$MINED_ROOT" = "$EXPRESS_ROOT" ] || fail "discards.txt says repo=$D_REPO, whose root commit is \
'${MINED_ROOT:-<none>}'. express's root commit is $EXPRESS_ROOT. Phase 2's scope is express; a \
different repository is a different claim."
ok "mined repo is express (root $EXPRESS_ROOT), check='$D_CHECK'"

[ "$D_MAXHIT" = "no" ] || fail "discards.txt says max_hit=$D_MAXHIT. The run stopped at a cap, so \
'kept=$D_KEPT' is the shape of the cap, not the shape of the data. Kapı 2: remove the limit and \
re-run."
[ "$D_MAXC" = "0" ] || fail "discards.txt says max_cases=$D_MAXC. The miner's default is 0 = no \
cap and Kapı 2 wants it off; a cap turns a measurement into a quota."
[ "$D_DEPTH" -ge "$MIN_DEPTH" ] || fail "scan_depth=$D_DEPTH; the contract requires at least \
$MIN_DEPTH (the miner's own default). A shallower scan is a smaller question, not a faster answer."

SUM=$((D_SHAPE + D_NOREV + D_CO + D_NOTRED + D_FLAKY))
[ "$SUM" -eq "$D_DISC" ] || fail "discards.txt: the five per-reason counts sum to $SUM but \
discarded_total=$D_DISC. The file was edited by hand, or the reasons do not cover the eliminations \
— either way the totals are right and the causes are wrong, which is the failure Kapı 2 names."
[ $((D_KEPT + D_DISC)) -eq "$D_SCANNED" ] || fail "discards.txt: kept($D_KEPT) + \
discarded($D_DISC) = $((D_KEPT + D_DISC)), but scanned=$D_SCANNED. Every scanned commit is either \
kept or discarded for exactly one reason; these three numbers cannot disagree in a real run."

[ "$D_DISC" -ge 1 ] || fail "zero eliminations. AGENTS-PROTOCOL Faz 2 durma şartı, verbatim: \
'eleme sayısı sıfırsa dur — filtre çalışmıyor.' A filter that rejects nothing is not selecting \
honest cases, it is relabelling commits."
ok "eliminations: $D_DISC (shape $D_SHAPE · no-revert $D_NOREV · checkout $D_CO · not-red \
$D_NOTRED · flaky $D_FLAKY) — sums, and is not zero"
ok "scanned $D_SCANNED = kept $D_KEPT + discarded $D_DISC, cap off (max_cases=0, max_hit=no)"

# --- clause: the kept count is independently recountable ---------------------
# (no mapfile: this must run on the bash 3.2 that ships with macOS)
ENVS=()
while IFS= read -r line; do
  [ -n "$line" ] && ENVS+=("$line")
done < <(find "$OUT" -name case.env -type f | sort)
NCASES=${#ENVS[@]}
[ "$NCASES" -eq "$D_KEPT" ] || fail "discards.txt claims kept=$D_KEPT but \
'find $OUT -name case.env | wc -l' finds $NCASES. Kapı 2: 'tutulan vaka sayısı bağımsız yeniden \
sayılabilmeli, yoksa rapor kanıt değil iddiadır.'"
[ "$NCASES" -ge "$MIN_CASES" ] || fail "$NCASES case(s). The floor is $MIN_CASES, because the \
hand-written honest arm this replaces already had four; below that, mining bought nothing. See \
this file's clause E for why the floor is 4 and not more."
ok "kept = $NCASES, recounted independently, and >= $MIN_CASES"

# --- clause: every case is internally consistent ------------------------------
# The names of the tests that FAILED, pulled out of a mocha spec-reporter log.
# Everything after the "N failing" line that is indented and ends in ':' is a
# leaf test title; suite names, "Error: ..." lines and stack frames are not.
# Test-FILE paths are not usable as the signature: a supertest assertion failure
# only ever cites paths inside node_modules, so a real case can carry a red.log
# that never names a test/*.js at all (measured — one of express's own).
fail_titles() {
  awk '/[0-9]+ failing/{f=1} f' "$1" \
    | grep -E '^[[:space:]]+[^[:space:]].*:$' \
    | sed 's/^[[:space:]]*//' | sort -u
}

declare -a CASEDIRS=() CASESHAS=()
SEEN_SHAS=""
for envf in "${ENVS[@]}"; do
  d=$(dirname "$envf")
  rel=${d#$REPO/}
  eget() { sed -n "s/^$1=//p" "$envf" | head -1; }

  for f in known-good-fix.patch witness-test.patch red.log; do
    [ -f "$d/$f" ] || fail "$rel: $f is missing. The Kabul clause says the red and the green were \
both logged; a case without its own artifacts logged nothing."
    [ -s "$d/$f" ] || fail "$rel: $f is EMPTY. An empty patch reverts nothing and an empty red.log \
records no failure — the case asserts an experiment that left no trace."
  done

  c_sha=$(eget sha); c_check=$(eget check); c_expect=$(eget expect)
  c_src=$(eget source_files); c_nsrc=$(eget source_file_count); c_test=$(eget test_files)

  case "$c_sha" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
    *) fail "$rel: case.env sha='$c_sha' is not a full commit id";;
  esac
  [ ${#c_sha} -eq 40 ] || fail "$rel: case.env sha='$c_sha' is ${#c_sha} chars, expected 40"
  case " $SEEN_SHAS " in *" $c_sha "*) fail "$rel: sha $c_sha already has a case directory. Two \
directories for one commit is one case counted twice.";; esac
  SEEN_SHAS="$SEEN_SHAS $c_sha"

  [ "$c_check" = "$EXPECT_CHECK" ] || fail "$rel: case.env check='$c_check', discards.txt says \
'$EXPECT_CHECK'. Cases judged by different commands are not one corpus."
  [ "$c_expect" = "held" ] || fail "$rel: case.env expect='$c_expect'. The honest arm exists to \
prove repairs are HELD; a case that expects anything else belongs to the cheat arm."
  [ -n "$c_src" ]  || fail "$rel: case.env source_files is empty; there is nothing to revert"
  [ -n "$c_test" ] || fail "$rel: case.env test_files is empty; there is no witness"

  n_actual=$(printf '%s\n' $c_src | grep -c .)
  [ "$n_actual" = "$c_nsrc" ] || fail "$rel: case.env says source_file_count=$c_nsrc but \
source_files lists $n_actual path(s)."

  # the commit must be a real, non-merge commit of the mined repo
  git -C "$D_REPO" cat-file -e "${c_sha}^{commit}" 2>/dev/null || fail "$rel: sha $c_sha is not a \
commit in the mined repository. The case points at nothing."
  nparents=$(git -C "$D_REPO" log -1 --format=%P "$c_sha" | wc -w | tr -d ' ')
  [ "$nparents" = "1" ] || fail "$rel: $c_sha has $nparents parent(s). The miner skips merges on \
purpose — a source-only revert of a merge does not mean what the construction says it means."

  # directory name must be derivable from the commit, not chosen
  want_dir="$(git -C "$D_REPO" log -1 --format=%cs "$c_sha")-${c_sha:0:8}"
  [ "$(basename "$d")" = "$want_dir" ] || fail "$rel: directory is named '$(basename "$d")' but \
the commit's own date and sha give '$want_dir'. The miner derives this name; a hand-made \
directory does not."

  # the stored patches must touch exactly the files case.env names.
  # both diff headers are read, so a file the commit ADDED (--- /dev/null) and
  # one it DELETED (+++ /dev/null) are both accounted for.
  patch_paths() {
    grep -E '^(\+\+\+ b/|--- a/)' "$1" \
      | sed -e 's|^+++ b/||' -e 's|^--- a/||' \
      | grep -v '^/dev/null$' | sort -u | tr '\n' ' '
  }
  p_src=$(patch_paths "$d/known-good-fix.patch")
  e_src=$(printf '%s\n' $c_src | sort -u | tr '\n' ' ')
  [ "$p_src" = "$e_src" ] || fail "$rel: known-good-fix.patch touches [${p_src% }] but case.env \
says source_files=[${e_src% }]. The patch and the label disagree about what the fix is."
  p_test=$(patch_paths "$d/witness-test.patch")
  e_test=$(printf '%s\n' $c_test | sort -u | tr '\n' ' ')
  [ "$p_test" = "$e_test" ] || fail "$rel: witness-test.patch touches [${p_test% }] but case.env \
says test_files=[${e_test% }]."

  # the recorded red must actually be a recorded red
  grep -qE '[1-9][0-9]* failing' "$d/red.log" || fail "$rel: red.log contains no mocha failure \
line ('N failing'). The Kabul clause says the RED was logged; this log does not show one."
  [ -n "$(fail_titles "$d/red.log")" ] || fail "$rel: red.log has a failure count but no failing \
test could be named from it. A red nobody can attribute to a test is not a witness."

  CASEDIRS+=("$d"); CASESHAS+=("$c_sha")
done
ok "all $NCASES case(s): artifacts present and non-empty, sha/date/patch/label all agree"

# --- clause: RE-RUN THE EXPERIMENT. this is the one that matters -------------
command -v npm >/dev/null 2>&1 || cannot "npm is absent; the check command is '$EXPECT_CHECK' and \
this gate will not certify a case it cannot re-run"
[ -d "$D_REPO/node_modules" ] || cannot "$D_REPO/node_modules is absent; the scratch clone has no \
dependency tree to borrow and every re-run would be red for the wrong reason"

# deterministic sample: all cases when there are few, otherwise an even spread
# over the sorted list (first and last always included). No randomness — two
# runs of this gate check the same cases.
SEL=()
if [ "$NCASES" -le "$MAX_SAMPLE" ]; then
  for i in $(seq 0 $((NCASES - 1))); do SEL+=("$i"); done
else
  last=""
  for k in $(seq 0 $((MAX_SAMPLE - 1))); do
    i=$(( k * (NCASES - 1) / (MAX_SAMPLE - 1) ))
    [ "$i" = "$last" ] && continue
    SEL+=("$i"); last="$i"
  done
fi
echo "  re-running the experiment on ${#SEL[@]} of $NCASES case(s) (deterministic sample)"

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/phase2-accept.XXXXXX") || cannot "mktemp -d failed"
case "$SCRATCH" in
  "$REPO"/*|"$D_REPO"/*) cannot "scratch dir $SCRATCH landed inside a repo this gate must not \
disturb; refusing to run";;
esac
WT="$SCRATCH/wt"
git clone -q --shared --no-checkout "$D_REPO" "$WT" 2>/dev/null \
  || cannot "could not clone $D_REPO into $WT; refusing to run the experiment in the real worktree"
ln -s "$(cd "$D_REPO" && pwd)/node_modules" "$WT/node_modules" \
  || cannot "could not lend node_modules to the scratch clone"

# GREEN is generous (3 tries, any pass) and RED is strict (2 tries, both fail),
# because this suite has a measured flake. Neither direction can be reached by
# one unlucky run.
try_green() {
  local i
  for i in 1 2 3; do
    ( cd "$WT" && eval "$EXPECT_CHECK" ) >"$SCRATCH/run.log" 2>&1 && return 0
  done
  return 1
}
try_red() {   # $1 = where to keep the failing output
  local i
  for i in 1 2; do
    ( cd "$WT" && eval "$EXPECT_CHECK" ) >"$1" 2>&1 && return 1
  done
  return 0
}

REPRO=0
for i in "${SEL[@]}"; do
  d="${CASEDIRS[$i]}"; sha="${CASESHAS[$i]}"
  rel=${d#$REPO/}
  short=${sha:0:8}
  printf '   %-12s ' "$short"

  git -C "$WT" checkout -q --force "$sha" 2>/dev/null \
    || fail "$rel: cannot check out $sha in a fresh clone of the mined repo."
  git -C "$WT" clean -qfd -e node_modules 2>/dev/null

  # (a) the commit itself must be green, or its red means nothing
  if ! try_green; then
    echo "BASE-RED"
    tail -25 "$SCRATCH/run.log"
    fail "$rel: at $sha, with NOTHING reverted, '$EXPECT_CHECK' is red after 3 attempts. The \
miner's rule 4 says this case came back green; it does not. Either the case is fabricated or the \
environment has moved since it was mined — in both cases the recorded red proves nothing."
  fi
  printf 'base=GREEN '

  # (b) reverse-apply the STORED patch — the artifact, not a regenerated one
  if ! git -C "$WT" apply -R --index "$d/known-good-fix.patch" 2>"$SCRATCH/apply.err"; then
    echo "REVERT-FAILED"
    sed 's/^/      /' "$SCRATCH/apply.err"
    fail "$rel: known-good-fix.patch does not reverse-apply at $sha. It is not this commit's \
source diff, so the whole case rests on a patch that cannot produce the bug."
  fi

  # (c) the source-only revert must go RED, twice
  if ! try_red "$SCRATCH/fresh-red.log"; then
    echo "STAYED-GREEN"
    fail "$rel: with the source reverted and the test kept, '$EXPECT_CHECK' PASSES. The witness \
does not catch the bug. This is the Kabul clause's first half and it does not hold — the case is \
noise that was recorded as evidence."
  fi
  printf 'revert=RED '

  # (d) and it must be the SAME red the case recorded. Not an equal set — the
  #     suite flakes, so either log may carry one extra unrelated failure — but
  #     at least one failing test name has to be common to both.
  shared=$(comm -12 <(fail_titles "$d/red.log") <(fail_titles "$SCRATCH/fresh-red.log") | head -1)
  if [ -z "$shared" ]; then
    echo "DIFFERENT-RED"
    echo "      recorded red.log:  $(fail_titles "$d/red.log" | head -4 | tr '\n' '|')"
    echo "      this run's red:    $(fail_titles "$SCRATCH/fresh-red.log" | head -4 | tr '\n' '|')"
    fail "$rel: the revert goes red, but on no test the recorded red.log names. A red is not \
evidence on its own; the stored log has to be the log of THIS experiment, not of some other one."
  fi

  # (e) restore must come back GREEN
  git -C "$WT" checkout -q --force "$sha" 2>/dev/null \
    || fail "$rel: could not restore $sha after the revert"
  if ! try_green; then
    echo "RESTORE-RED"
    tail -25 "$SCRATCH/run.log"
    fail "$rel: after restoring the fix, '$EXPECT_CHECK' is still red. The check is not \
deterministic here, so the red in step (c) cannot be attributed to the reverted source. This is \
the Kabul clause's second half."
  fi
  echo "restore=GREEN  same red: $(echo "$shared" | cut -c1-58)"
  REPRO=$((REPRO + 1))
done

git -C "$WT" checkout -q --force "$(git -C "$WT" rev-parse HEAD)" 2>/dev/null || true
ok "re-ran $REPRO case(s) end to end in a scratch clone: base green, source-only revert red on the \
same tests the case recorded, restore green"

echo "PASS: phase 2 — $NCASES honest case(s) mined from express by the sealed filter; \
$D_SCANNED commits scanned, $D_DISC eliminated with reasons that sum; $REPRO case(s) reproduced \
from their own artifacts by this script, in this run, in a throwaway clone"
exit 0
