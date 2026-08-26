#!/bin/bash
# docs_truth_test.sh — the docs' claims about SILENT, held against what the real
# gate binary does in the same instant.
#
# WHY THIS FILE EXISTS.
# `native/status_truth_test.sh` locked the SCREEN: it proves `rabadon status`
# names every silencer in force, says where it is, and prints a command that
# really lifts it. Nothing locked the PAGE. On 2026-08-26 the screen was correct
# and `docs/commands.md` still carried the pre-F1d description of the same
# feature: a table of THREE silencers when the binary reports SIX, a removal
# command for the machine silencer (`rm ~/.rabadon/silent`) that does not remove
# it, and three sentences about `off`/`on`/`status` that the binary contradicts.
# The same wrong removal command was in `docs/faq.md` and `docs/uninstall.md`.
#
# A guard's docs are part of the guard. A reader who follows an escape door that
# does not open stops looking, stays unsupervised, and believes they fixed it —
# the same failure as a screen that lies, printed on a page instead.
#
# THE FIVE INVARIANTS.
#
#   1. THE TABLE IS EXECUTED, NOT READ. Every row of the silencer table in
#      docs/commands.md is set up for real in a fresh sandbox, confirmed SILENT
#      through the real native/rabadon-gate (exit 0 AND zero bytes), then the
#      row's own "the one command that removes it" is run VERBATIM and the same
#      event is asked again. Still silent = FAIL. The number of rows executed is
#      derived from the FILE, so adding a row to the table adds a test. A removal
#      command this file cannot execute is a FAIL, never a silent skip.
#
#   2. SET EQUALITY. The set of rows in the table must EQUAL the set of
#      silencers the binary can actually report. The binary's set is DERIVED:
#      six situations are built, each is confirmed silent, and the name and
#      location are read off the screen's own `silenced by:` line. A row the
#      binary cannot produce is red, and a silencer the binary reports that the
#      table does not list is red. (On 2026-08-26 the table had 3 and the binary
#      reported 6.)
#
#   3. SCREEN = PAGE, BYTE FOR BYTE. For each silencer, the command the screen
#      prints on its `next:` line and the command the table prints in its last
#      column must be the same bytes.
#
#      NORMALIZATION, exhaustively, because a loose normalizer is an empty
#      green: only two substitutions are applied to what the screen printed, and
#      both are the sandbox showing through —
#        <the cell's mktemp project dir>  ->  <project>
#        <the cell's mktemp RABADON_DIR>  ->  $RABADON_DIR
#      and on the page side, markdown code markers (`) are stripped because they
#      are formatting, not content. NOTHING ELSE. No case folding, no whitespace
#      squeezing, no path canonicalisation. One remaining byte of difference is
#      a FAIL.
#
#   4. THE BEHAVIOUR-CLAIM REGISTRY. docs/commands.md, docs/faq.md and
#      docs/uninstall.md each carry a NARROW block marked
#      `<!-- rabadon:claims-begin -->` / `<!-- rabadon:claims-end -->`. Inside
#      those blocks, any line matching a fixed claim grammar
#      (`does NOT`, `will report`, `reports the`, `never`, `always`, `is not`)
#      must have a row in docs/claims.tsv, and that row must name a check this
#      file can RUN against the real binary. Both directions are red: an
#      unregistered claim line, and a registry row whose line is no longer in
#      the doc (a stale registry).
#
#      SCOPE, on purpose narrow: this is not a prose auditor. What it does is
#      take sentences about OBSERVABLE CLI BEHAVIOUR out of free text and bind
#      each one to a command that runs. The registry's `expect` column is the
#      measurement the sentence was written against; the machine proves the
#      measurement still comes out that way, and that no claim line escaped the
#      registry. A human still reads the sentence.
#
#   5. The three sentences at docs/commands.md that were measured false on
#      2026-08-26 are corrected, not deleted, and the correction carries the
#      measurement. That is a property of the page, enforced here by 4: the
#      corrected sentences are exactly the ones that must be registered.
#
# HERMETIC AND OFFLINE. git + POSIX shell only — no node, no python3, no jq, no
# network. Every cell gets its own mktemp project, its own mktemp RABADON_DIR
# and its own mktemp HOME; section H checks the operator's real ~/.rabadon was
# never written.
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

CLI="$ROOT/native/rabadon-cli.sh"
GATE="${RABADON_GATE:-$ROOT/native/rabadon-gate}"
DOC="docs/commands.md"
TSV="docs/claims.tsv"
CLAIM_DOCS="docs/commands.md docs/faq.md docs/uninstall.md"
CLAIM_RE='does NOT|will report|reports the|never|always|is not'

# ---- preflight: BLOCKED, never skipped ------------------------------------
if [ ! -x "$GATE" ]; then
  echo "  FAIL - BLOCKED: the gate binary is not there, so no page can be checked against anything; why: every assertion in this file compares a documented command to what $GATE really does, and without it they would all pass vacuously; run: (cd $ROOT && make all)"
  echo "docs truth: 0 ok / 1 fail"; exit 1
fi
if [ ! -f "$CLI" ]; then
  echo "  FAIL - BLOCKED: $CLI is missing; why: the dispatcher is the surface every documented \`rabadon <verb>\` lands on, so a documented command cannot be run without it; run: git status --porcelain native/rabadon-cli.sh"
  echo "docs truth: 0 ok / 1 fail"; exit 1
fi
for f in $DOC $CLAIM_DOCS; do
  [ -f "$f" ] || { echo "  FAIL - BLOCKED: $f is missing; why: this suite locks that page's claims and cannot lock a page it cannot read; run: git status --porcelain $f"; echo "docs truth: 0 ok / 1 fail"; exit 1; }
done
command -v git >/dev/null 2>&1 || {
  echo "  FAIL - BLOCKED: git is not on PATH; why: every cell is a real git repo because the gate's rules are repo-scoped; run: git --version"
  echo "docs truth: 0 ok / 1 fail"; exit 1; }

TMP=$(mktemp -d /tmp/rabadon-docstruth.XXXXXX) || exit 1
trap 'rm -rf "$TMP"' EXIT
STAMP="$TMP/.stamp"; : > "$STAMP"

ESC=$(printf '\033')
plain() { printf '%s\n' "$1" | sed "s/${ESC}\[[0-9;]*m//g"; }

CELLN=0
PROJ=""; RD=""; HOMEDIR=""
CELL_ENVOFF=no; CELL_ENVMODE=unset
SAW_ENFORCE=0

# ---- the sandbox ----------------------------------------------------------
# A brand new project + RABADON_DIR + HOME per probe. Fresh every time because
# `rabadon on`/`off` MUTATE the mode file and unlink the silent marker: reusing
# a cell would measure the previous probe.
new_cell() {
  CELLN=$((CELLN+1))
  PROJ="$TMP/c$CELLN/proj"; RD="$TMP/c$CELLN/rabadon"; HOMEDIR="$TMP/c$CELLN/home"
  mkdir -p "$PROJ" "$RD" "$HOMEDIR" || return 1
  git init -q "$PROJ" >/dev/null 2>&1 || return 1
  # the base is ENFORCE, so "the silence lifted" is visible as a real refusal
  # rather than as the absence of one.
  printf 'enforce\n' > "$RD/mode" || return 1
  CELL_ENVOFF=no; CELL_ENVMODE=unset
  return 0
}

cellenv() {
  CELLENV=(HOME="$HOMEDIR" RABADON_DIR="$RD" RABADON_NOTIFY=0)
  if [ "$CELL_ENVOFF" = yes ]; then CELLENV+=(RABADON_OFF=1); fi
  if [ "$CELL_ENVMODE" != unset ]; then CELLENV+=(RABADON_MODE="$CELL_ENVMODE"); fi
  return 0
}

cli() { cellenv; ( cd "$PROJ" && env "${CELLENV[@]}" bash "$CLI" "$@" 2>&1 ); }

# one real PreToolUse event, through the real binary, in the cell's cwd.
EVENT_CMD='git push --force origin main'
gate_probe() {
  ev=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$PROJ" "$EVENT_CMD")
  cellenv
  GOUT=$(printf '%s' "$ev" | ( cd "$PROJ" && env "${CELLENV[@]}" "$GATE" 2>&1 )); GRC=$?
  GBYTES=$(printf '%s' "$GOUT" | wc -c | tr -d ' ')
  [ "$GRC" -eq 2 ] && SAW_ENFORCE=1
  return 0
}
is_silent() { [ "$GRC" -eq 0 ] && [ "$GBYTES" -eq 0 ]; }

# THE SIX SITUATIONS. This list is the fixture; the NAMES and the LOCATIONS and
# the ESCAPE COMMANDS are never typed here — they are read off the binary's own
# screen below. `machine-silent` is entered through the product's own door
# (`rabadon-gate --silent`) and not by touching the file, because that door
# writes the mode file too, and a fixture that only touches the file would let
# `rm <the file>` look like it works.
SITUATIONS='env-off project-off machine-silent machine-mode project-mode env-mode'

apply_situation() {
  case "$1" in
    env-off)        CELL_ENVOFF=yes ;;
    project-off)    mkdir -p "$PROJ/.rabadon" && : > "$PROJ/.rabadon/off" ;;
    machine-silent) cellenv; ( cd "$PROJ" && env "${CELLENV[@]}" "$GATE" --silent ) >/dev/null 2>&1 ;;
    machine-mode)   printf 'silent\n' > "$RD/mode" ;;
    project-mode)   mkdir -p "$PROJ/.rabadon" && printf 'silent\n' > "$PROJ/.rabadon/mode" ;;
    env-mode)       CELL_ENVMODE=silent ;;
    *)              return 1 ;;
  esac
  return 0
}

# the two substitutions of invariant 3, and nothing else.
norm() { printf '%s\n' "$1" | sed -e "s|$PROJ|<project>|g" -e "s|$RD|\$RABADON_DIR|g"; }
# markdown formatting is not content.
uncode() { printf '%s\n' "$1" | tr -d '`'; }
trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

screen_muters() { plain "$1" | sed -n 's/^[[:space:]]*silenced by:[[:space:]]*//p'; }
screen_nexts()  { plain "$1" | sed -n 's/^[[:space:]]*next:[[:space:]]*//p'; }

# THE INTERPRETER for a documented removal command. Four shapes, and anything
# else is a FAIL: "this suite cannot run the command the page tells the reader
# to run" is the same defect as the command not working.
RUN_BAD=""
run_doc_cmd() {
  _c="$1"
  case "$_c" in
    "unset RABADON_OFF")  CELL_ENVOFF=no ;;
    "unset RABADON_MODE") CELL_ENVMODE=unset ;;
    "rabadon off")        cli off >/dev/null 2>&1 ;;
    "rm <project>/"*)     rm -f "$PROJ/${_c#rm <project>/}" || RUN_BAD="rm-failed[$_c]" ;;
    'rm $RABADON_DIR/'*)  rm -f "$RD/${_c#rm \$RABADON_DIR/}" || RUN_BAD="rm-failed[$_c]" ;;
    "rm ~/.rabadon/"*)    rm -f "$RD/${_c#rm ~/.rabadon/}" || RUN_BAD="rm-failed[$_c]" ;;
    *)                    RUN_BAD="unrecognised[$_c]" ;;
  esac
  return 0
}

echo "docs truth: the silencer table, executed against the real gate"
echo

# ==========================================================================
# 2a. DERIVE the binary's silencer set. Names/locations/commands come from the
#     screen, never from this file.
# ==========================================================================
BIN="$TMP/binset.tsv"; : > "$BIN"
for SIT in $SITUATIONS; do
  if ! new_cell || ! apply_situation "$SIT"; then
    fail "BLOCKED: [$SIT] the sandbox could not be built; why: a situation that never got set up would let every row matched to it pass on nothing; run: mktemp -d && git init -q"
    continue
  fi
  gate_probe
  if ! is_silent; then
    fail "BLOCKED: [$SIT] the binary is not silenced by this situation (gate exit $GRC / $GBYTES bytes); why: this suite derives the documented set from the states the binary really goes dormant in, and a situation that does not silence cannot anchor a row; run: printf '{\"hook_event_name\":\"PreToolUse\",\"cwd\":\"$PROJ\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$EVENT_CMD\"}}' | RABADON_DIR=$RD $GATE"
    continue
  fi
  SCREEN=$(cli status)
  MUTERS=$(screen_muters "$SCREEN")
  NEXTS=$(screen_nexts "$SCREEN")
  NM=$(printf '%s\n' "$MUTERS" | grep -c .)
  if [ "$NM" -ne 1 ]; then
    fail "BLOCKED: [$SIT] the screen listed $NM silencers, expected exactly 1; why: this situation is built to put ONE silencer in force so the row it anchors is unambiguous, and $NM means the fixture and the binary disagree about what is in force; run: (cd $PROJ && RABADON_DIR=$RD bash native/rabadon-cli.sh status)"
    continue
  fi
  M=$(norm "$MUTERS"); N=$(norm "$(printf '%s\n' "$NEXTS" | head -1)")
  BNAME=$(printf '%s' "$M" | sed 's/ (\([^()]*\))$//')
  BLOC=$(printf '%s' "$M" | sed -n 's/.* (\([^()]*\))$/\1/p')
  if [ -z "$BLOC" ]; then
    fail "BLOCKED: [$SIT] could not read a location out of the screen's line \"$M\"; why: the disclosure format is \`silenced by: <name> (<where>)\` and a line this parser cannot split cannot be compared to a table cell; run: (cd $PROJ && RABADON_DIR=$RD bash native/rabadon-cli.sh status)"
    continue
  fi
  printf '%s\t%s\t%s\t%s\n' "$BNAME" "$BLOC" "$N" "$SIT" >> "$BIN"
  pass "[$SIT] the binary reports \"$BNAME\" at \"$BLOC\", next: $N"
done

BINCOUNT=$(grep -c . "$BIN")
if [ "$BINCOUNT" -eq 0 ]; then
  fail "BLOCKED: not one silencer could be derived from the binary; why: everything below compares the page against this set, and an empty set makes every comparison pass on nothing — the empty green this file exists to refuse; run: (cd $ROOT && make all) then bash native/docs_truth_test.sh"
fi

echo

# ==========================================================================
# 1 + 2b + 3. Parse the table, then execute it.
# ==========================================================================
# The table is found by CONTENT — the heading that introduces the silencers and
# the first pipe table under it — never by line number: a test pinned to
# docs/commands.md:81 goes green the moment someone adds a paragraph above it.
DOCROWS="$TMP/docrows.tsv"
awk -F'|' '
  /^###[ \t].*silencers/ { hit=1; next }
  hit && /^\|/ {
    intab=1
    if (NF < 5) next
    what=$2; where=$3; cmd=$5
    gsub(/^[ \t]+|[ \t]+$/, "", what)
    gsub(/^[ \t]+|[ \t]+$/, "", where)
    gsub(/^[ \t]+|[ \t]+$/, "", cmd)
    if (what == "what") next
    if (what ~ /^-*:?-*$/) next
    print what "\t" where "\t" cmd
    next
  }
  intab && !/^\|/ { exit }
' "$DOC" > "$DOCROWS"

DOCCOUNT=$(grep -c . "$DOCROWS")
echo "docs truth: every row of the $DOC table, set up and then lifted"
if [ "$DOCCOUNT" -eq 0 ]; then
  fail "BLOCKED: no silencer rows could be parsed out of $DOC; why: this suite derives its row count from the page, so zero rows would mean zero assertions and a green that measured nothing; run: grep -n 'silencers' $DOC"
else
  pass "$DOCCOUNT silencer row(s) parsed out of $DOC (the row count is the page's, not this file's)"
fi

# 2b. set equality, by (name, location).
MISSING=""; EXTRA=""
while IFS="$(printf '\t')" read -r BN BL BC BS; do
  [ -z "$BN" ] && continue
  if ! awk -F'\t' -v n="$BN" -v l="$BL" '{
        w=$1; h=$2; gsub(/`/,"",w); gsub(/`/,"",h)
        if (w==n && h==l) found=1 } END { exit !found }' "$DOCROWS"; then
    MISSING="$MISSING [$BN @ $BL]"
  fi
done < "$BIN"
while IFS="$(printf '\t')" read -r DW DH DC; do
  [ -z "$DW" ] && continue
  dw=$(uncode "$DW"); dh=$(uncode "$DH")
  if ! awk -F'\t' -v n="$dw" -v l="$dh" '$1==n && $2==l { found=1 } END { exit !found }' "$BIN"; then
    EXTRA="$EXTRA [$dw @ $dh]"
  fi
done < "$DOCROWS"

if [ -z "$MISSING" ] && [ -z "$EXTRA" ]; then
  pass "set equality: the table lists exactly the $BINCOUNT silencer(s) the binary can report"
else
  [ -n "$MISSING" ] && fail "BLOCKED: the binary can report silencer(s) $DOC does not list:$MISSING; why: a silencer nobody documented is indistinguishable from a broken guard — the reader sees a dead gate, finds nothing on the page, and rips the tool out; run: bash native/docs_truth_test.sh"
  [ -n "$EXTRA" ] && fail "BLOCKED: $DOC lists silencer(s) the binary never reports:$EXTRA; why: the reader is sent to check a switch that does not exist while the real one keeps them silent; run: bash native/docs_truth_test.sh"
fi

# 1 + 3. Execute every documented row.
ROWN=0
while IFS="$(printf '\t')" read -r DW DH DC; do
  [ -z "$DW" ] && continue
  ROWN=$((ROWN+1))
  dw=$(uncode "$DW"); dh=$(uncode "$DH"); dc=$(uncode "$DC")
  LBL="row $ROWN \"$dw\""

  # exact match first; then a looser match on the location's first token, so a
  # row whose NAME is wrong is still executed instead of being skipped — being
  # unable to run a documented command must never be the quiet outcome.
  SIT=$(awk -F'\t' -v n="$dw" -v l="$dh" '$1==n && $2==l { print $4; exit }' "$BIN")
  MATCH=exact
  if [ -z "$SIT" ]; then
    lh=${dh%% *}
    SIT=$(awk -F'\t' -v l="$lh" '$2==l { print $4; exit }' "$BIN")
    MATCH=loose
  fi
  if [ -z "$SIT" ]; then
    fail "BLOCKED: $LBL — no state of the real binary matches this row (where: \"$dh\"), so its removal command cannot be run; why: an unexecutable row is an unchecked row, and an unchecked row is exactly where a dead escape door hides; run: (cd $PROJ && RABADON_DIR=$RD bash native/rabadon-cli.sh status)"
    continue
  fi
  [ "$MATCH" = loose ] && fail "BLOCKED: $LBL — matched the binary only by location, not by name: the page says \"$dw\" and the screen says \"$(awk -F'\t' -v s="$SIT" '$4==s{print $1;exit}' "$BIN")\"; why: two names for one silencer means the sentence a user greps for is not the sentence the product prints; run: bash native/docs_truth_test.sh"

  # 3. byte for byte against the screen's own next: line.
  BNEXT=$(awk -F'\t' -v s="$SIT" '$4==s { print $3; exit }' "$BIN")
  if [ "$dc" = "$BNEXT" ]; then
    pass "$LBL — the page's command and the screen's \`next:\` are the same bytes: $dc"
  else
    fail "BLOCKED: $LBL — the page says \`$dc\` and the screen says \`$BNEXT\`; why: the product hands a dormant operator one command and the manual hands them another, so one of the two surfaces is wrong and the reader has no way to tell which; run: bash native/docs_truth_test.sh"
  fi

  # 1. set it up, prove it is silent, run the page's command, ask again.
  if ! new_cell || ! apply_situation "$SIT"; then
    fail "BLOCKED: $LBL — the sandbox could not be built; run: mktemp -d && git init -q"
    continue
  fi
  gate_probe
  if ! is_silent; then
    fail "BLOCKED: $LBL — the fixture did not silence the gate before the command was run (exit $GRC / $GBYTES bytes); why: lifting a silence that was never there is the empty green this file refuses; run: bash native/docs_truth_test.sh"
    continue
  fi
  RUN_BAD=""
  run_doc_cmd "$dc"
  if [ -n "$RUN_BAD" ]; then
    fail "BLOCKED: $LBL — this suite could not execute the documented command: $RUN_BAD; why: the only commands rabadon may hand a dormant operator are \`unset RABADON_OFF\`, \`unset RABADON_MODE\`, \`rabadon off\` and \`rm <path>\`, and anything else is a sentence the reader cannot run; run: bash native/docs_truth_test.sh"
    continue
  fi
  gate_probe
  if is_silent; then
    fail "BLOCKED: $LBL — after running the page's own command (\`$dc\`) the SAME event through the SAME binary is still exit 0 with 0 bytes, the SILENT signature; why: the manual prints an escape door that does not open, so the reader follows it, sees no change, and stays unguarded believing they fixed it; run: printf '{\"hook_event_name\":\"PreToolUse\",\"cwd\":\"$PROJ\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$EVENT_CMD\"}}' | RABADON_DIR=$RD $GATE"
  else
    pass "$LBL — \`$dc\` really lifted the silence (gate now exit $GRC / $GBYTES bytes)"
  fi
done < "$DOCROWS"

echo

# ==========================================================================
# 4. The behaviour-claim registry.
# ==========================================================================
echo "docs truth: every behaviour claim in a marked block is bound to a live check"

# the executable checks. A name this dispatcher does not know prints
# UNKNOWN-CHECK, which can match no expectation, so a made-up check is red.
claim_off_probe() {
  new_cell && apply_situation "$1" || { echo SANDBOX-FAIL; return 0; }
  cli off >/dev/null 2>&1
  gate_probe
  if is_silent; then echo silent; else echo live; fi
}
claim_check() {
  case "$1" in
    off-removes-machine-silent-file)
        new_cell && apply_situation machine-silent || { echo SANDBOX-FAIL; return 0; }
        cli off >/dev/null 2>&1
        if [ -e "$RD/silent" ]; then echo present; else echo removed; fi ;;
    rm-silent-file-alone-leaves-it-silent)
        new_cell && apply_situation machine-silent || { echo SANDBOX-FAIL; return 0; }
        rm -f "$RD/silent"
        gate_probe
        if is_silent; then echo silent; else echo live; fi ;;
    off-leaves-env-off-silent)      claim_off_probe env-off ;;
    off-leaves-project-off-silent)  claim_off_probe project-off ;;
    off-leaves-project-mode-silent) claim_off_probe project-mode ;;
    off-leaves-env-mode-silent)     claim_off_probe env-mode ;;
    on-claim-under-silencer)
        new_cell && apply_situation project-off || { echo SANDBOX-FAIL; return 0; }
        _s=$(plain "$(cli on)")
        case "$_s" in
          *SILENT*)          echo SILENT ;;
          *"ON —"*|*"ON -"*) echo ON ;;
          *WATCH*)           echo WATCH ;;
          *)                 echo UNREADABLE ;;
        esac ;;
    status-discloses-silencer)
        new_cell && apply_situation project-off || { echo SANDBOX-FAIL; return 0; }
        _s=$(plain "$(cli status)")
        _r=""
        printf '%s\n' "$_s" | grep -q '^[[:space:]]*silenced by:' && _r="named"
        printf '%s\n' "$_s" | grep -qF "$PROJ/.rabadon/off" && _r="$_r+located"
        printf '%s\n' "$_s" | grep -q '^[[:space:]]*next:' && _r="$_r+next"
        echo "$_r" ;;
    off-is-watch-not-silence)
        new_cell || { echo SANDBOX-FAIL; return 0; }
        cli off >/dev/null 2>&1
        gate_probe
        if is_silent; then echo silent; else echo live; fi ;;
    silencer-count) echo "$BINCOUNT" ;;
    *) echo UNKNOWN-CHECK ;;
  esac
  return 0
}

# every claim line in every marked block, as "file<TAB>key<TAB>text".
FOUND="$TMP/found.tsv"; : > "$FOUND"
MARKED_FILES=0
for F in $CLAIM_DOCS; do
  BLK=$(awk '/rabadon:claims-begin/{inb=1;next} /rabadon:claims-end/{inb=0;next} inb' "$F")
  if [ -z "$BLK" ]; then
    fail "BLOCKED: $F has no <!-- rabadon:claims-begin --> block; why: the registry only sees marked blocks, so an unmarked page can carry any claim about the gate with nothing holding it to the binary; run: grep -n 'rabadon:claims' $F"
    continue
  fi
  MARKED_FILES=$((MARKED_FILES+1))
  while IFS= read -r L; do
    T=$(trim "$L")
    [ -z "$T" ] && continue
    K=$(printf '%s' "$T" | cksum | awk '{print $1}')
    printf '%s\t%s\t%s\n' "$F" "$K" "$T" >> "$FOUND"
  done <<EOF
$(printf '%s\n' "$BLK" | grep -E "$CLAIM_RE")
EOF
done

if [ "$MARKED_FILES" -lt 3 ]; then
  fail "BLOCKED: only $MARKED_FILES of 3 docs carry a marked claim block; why: all three said \`rm ~/.rabadon/silent\` on 2026-08-26 and the registry has to cover all three or the same wrong sentence survives on the pages it is not watching; run: grep -ln 'rabadon:claims-begin' $CLAIM_DOCS"
fi

NFOUND=$(grep -c . "$FOUND"); NFOUND=${NFOUND:-0}
if [ "$NFOUND" -eq 0 ]; then
  fail "BLOCKED: no claim line was found inside any marked block; why: the registry would then be checked against nothing and every row below would pass vacuously; run: grep -nE '$CLAIM_RE' $CLAIM_DOCS"
else
  pass "$NFOUND behaviour-claim line(s) found inside the marked blocks"
fi

if [ ! -f "$TSV" ]; then
  fail "BLOCKED: $TSV does not exist; why: the registry IS the binding between a sentence about the gate and a command that proves it, and without the file every marked claim is free text again; run: ls -l $TSV"
else
  # registry -> doc (stale rows) and each row's check actually run.
  NROWS=0; NRUN=0
  while IFS="$(printf '\t')" read -r RF RK RT RC RE; do
    case "$RF" in '#'*|'') continue ;; esac
    NROWS=$((NROWS+1))
    if ! awk -F'\t' -v f="$RF" -v k="$RK" '$1==f && $2==k { found=1 } END { exit !found }' "$FOUND"; then
      fail "BLOCKED: $TSV has a row for $RF key $RK (\"$RT\") that is no longer a claim line in that doc; why: a stale registry is a green for a sentence nobody is reading any more, and it hides the day the real sentence changed; run: grep -nE '$CLAIM_RE' $RF"
      continue
    fi
    GOT=$(claim_check "$RC"); NRUN=$((NRUN+1))
    if [ "$GOT" = "$RE" ]; then
      pass "$RF:$RK — \`$RC\` still answers \"$RE\", so \"$(printf '%s' "$RT" | cut -c1-58)\" stands on a measurement"
    else
      fail "BLOCKED: $RF:$RK — the check \`$RC\` behind \"$RT\" answered \"$GOT\", the registry records \"$RE\"; why: the page's sentence was written against a measurement that no longer comes out that way, so either the binary changed or the sentence was never true; run: bash native/docs_truth_test.sh"
    fi
  done < "$TSV"
  if [ "$NROWS" -eq 0 ]; then
    fail "BLOCKED: $TSV holds no rows; why: an empty registry passes every claim line it is asked about and measures nothing; run: cat $TSV"
  elif [ "$NRUN" -eq "$NROWS" ]; then
    pass "$TSV holds $NROWS registered claim(s), and this suite ran the check behind every one"
  else
    fail "BLOCKED: $TSV holds $NROWS rows but only $NRUN check(s) were run; why: the rest were skipped as stale above, so those sentences went unmeasured in a run that would otherwise look complete; run: bash native/docs_truth_test.sh"
  fi

  # doc -> registry (unregistered claims).
  UNREG=""
  while IFS="$(printf '\t')" read -r FF FK FT; do
    [ -z "$FF" ] && continue
    if ! awk -F'\t' -v f="$FF" -v k="$FK" '$1==f && $2==k { found=1 } END { exit !found }' "$TSV"; then
      UNREG="$UNREG
           $FF:$FK  $(printf '%s' "$FT" | cut -c1-70)"
    fi
  done < "$FOUND"
  if [ -z "$UNREG" ]; then
    pass "no unregistered behaviour claim in any marked block"
  else
    fail "BLOCKED: these claim lines are not in $TSV:$UNREG
         why: a sentence about what the gate does, with nothing that runs behind
         it, is how docs/commands.md kept describing the pre-F1d gate for a week
         while the suite stayed green.
         next: add a row to $TSV (file, key, text, check, expected) or take the
         sentence out of the marked block, then re-run bash native/docs_truth_test.sh"
  fi
fi

echo

# ---- P. the positive control ---------------------------------------------
if [ "$SAW_ENFORCE" -eq 1 ]; then
  pass "positive control: at least one probe got a REAL refusal (gate exit 2), so the instrument works"
else
  fail "BLOCKED: not one of the $CELLN cells produced gate exit 2, so no probe here ever saw the gate act; why: every 'the silence lifted' assertion in this file is satisfied by a gate that returns 0 to everything, and a suite that cannot see a block cannot see a missing one either; run: (cd $ROOT && make all) then bash native/docs_truth_test.sh"
fi

# ---- H. hermeticity -------------------------------------------------------
REAL_TOUCHED=""
for p in "$HOME/.rabadon/mode" "$HOME/.rabadon/enabled" "$HOME/.rabadon/silent" "$HOME/.rabadon/mode.last"; do
  [ -e "$p" ] && [ "$p" -nt "$STAMP" ] && REAL_TOUCHED="$REAL_TOUCHED $p"
done
[ -z "$REAL_TOUCHED" ] && pass "no file under the real ~/.rabadon was written by this suite" \
  || fail "BLOCKED: this suite wrote the operator's own switch:$REAL_TOUCHED; why: a test that flips real supervision leaves the machine in whatever state it stopped in; run: rabadon status"

echo
echo "docs truth: $ok ok / $bad fail"
[ "$bad" -eq 0 ] || exit 1
