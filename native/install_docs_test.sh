#!/bin/bash
# install_docs_test.sh — the brake has to be IN the install path, in every doc
# that documents one.
#
# `rabadon init` leaves a project in WATCH mode by design: it records what it
# would have refused and stops nothing. `rabadon on` is the line that turns the
# recording into a refusal. A reader who follows a documented install to the
# letter and never types `rabadon on` has installed a logger, believes they
# installed a brake, and finds out on the day it mattered. That is the product
# failing in the one place a guard cannot fail.
#
# So this suite treats the install block as an acceptance surface: in every doc
# that ships one, `rabadon on` must be a command line INSIDE the block —
# after `rabadon init`, before the agent is started. A mention of the command
# somewhere else on the page does not count and is not looked at: the block is
# cut out of the file first, and only the block is searched.
#
# The blocks are found by CONTENT, never by line number — a test pinned to
# `README.md:26` goes green the moment someone adds a paragraph above it.
set -u
cd "$(dirname "$0")/.."

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

echo "install docs: the brake is inside the install block"

# ---- extraction ----------------------------------------------------------
# md_block FILE ANCHOR — prints the first ```-fenced block whose body has a
# line matching ANCHOR. Fence-aware, so prose between blocks can never leak in.
md_block() {
  awk -v anchor="$2" '
    /^[ \t]*```/ {
      if (inb) { if (hit) { printf "%s", buf; exit } ; buf=""; hit=0; inb=0 }
      else { inb=1 }
      next
    }
    inb { buf = buf $0 "\n"; if ($0 ~ anchor) hit=1 }
  ' "$1"
}

# html_block FILE ANCHOR — prints the first <div class="term"> ... </div> whose
# body matches ANCHOR, with tags stripped and entities unescaped, so the result
# is the commands a reader would actually type.
html_block() {
  awk -v anchor="$2" '
    /class="term"/ { inb=1; buf=""; hit=0 }
    inb {
      buf = buf $0 "\n"; if ($0 ~ anchor) hit=1
      if (/<\/div>/) { if (hit) { printf "%s", buf; exit } ; inb=0 }
    }
  ' "$1" | sed -e 's/<[^>]*>//g' \
               -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' \
               -e 's/&quot;/"/g' -e "s/&#39;/'/g"
}

# command lines only: no blanks, no comment-only lines, no shell prompt noise.
cmd_lines() { grep -v '^[ \t]*$' | grep -v '^[ \t]*#' ; }

# ---- the checks ----------------------------------------------------------
# check NAME BLOCK  — three questions per doc: is there a block, is it real,
# is the brake in it.
check_block() {
  NAME="$1"; BLOCK="$2"

  if [ -z "$BLOCK" ]; then
    fail "$NAME: BLOCKED — kurulum blogu bulunamadi / install block not found.
         why: this suite locks \`rabadon on\` inside the documented install
         block, and it could not find the block to look in. Either the block
         was removed or its anchor changed, and an install doc without an
         install block is a worse failure than a missing line.
         next: ./native/install_docs_test.sh  (after restoring the block in $NAME)"
    return
  fi
  pass "$NAME: install block found"

  # vacuity guard. An extractor that returns one stray line would let every
  # check below pass on nothing, which is the empty green this whole suite
  # exists to refuse. A real install block runs at least three commands.
  N=$(printf '%s\n' "$BLOCK" | cmd_lines | wc -l | tr -d ' ')
  if [ "$N" -lt 3 ]; then
    fail "$NAME: BLOCKED — install block has $N command line(s), expected >= 3.
         why: the extracted block is too short to be the real install path, so
         every check against it would pass vacuously.
         next: ./native/install_docs_test.sh  (after checking what got extracted from $NAME)"
    return
  fi
  pass "$NAME: install block is non-vacuous ($N command lines)"

  # the load-bearing one.
  if ! printf '%s\n' "$BLOCK" | grep -qE '^[ \t$]*rabadon on([ \t]|$)'; then
    fail "$NAME: BLOCKED — no \`rabadon on\` command inside the install block.
         why: \`rabadon init\` leaves the project in WATCH mode. A reader who
         follows this block exactly ends up recording refusals instead of
         making them, and believes the guard is armed. \`rabadon on\` must be a
         command line in the block itself; a mention elsewhere on the page is
         not part of the install path and is not counted here.
         next: add a \`rabadon on\` line to the install block in $NAME, after
         \`rabadon init\` and before the agent is started, then re-run
         ./native/install_docs_test.sh"
    return
  fi
  pass "$NAME: \`rabadon on\` is a command inside the install block"

  # order: arming after init, and before the agent is handed the keys.
  ON=$(printf '%s\n' "$BLOCK" | grep -nE '^[ \t$]*rabadon on([ \t]|$)' | head -1 | cut -d: -f1)
  INIT=$(printf '%s\n' "$BLOCK" | grep -nE '^[ \t$]*rabadon init([ \t]|$)' | head -1 | cut -d: -f1)
  AGENT=$(printf '%s\n' "$BLOCK" | grep -nE '^[ \t$]*claude([ \t]|$)' | head -1 | cut -d: -f1)

  if [ -n "$INIT" ] && [ "$ON" -lt "$INIT" ]; then
    fail "$NAME: BLOCKED — \`rabadon on\` comes before \`rabadon init\` in the block.
         why: there is no project guard to arm until init has written one, so
         the documented order does not work when typed.
         next: move the \`rabadon on\` line below \`rabadon init\` in $NAME"
  else
    pass "$NAME: \`rabadon on\` is not before \`rabadon init\`"
  fi

  if [ -n "$AGENT" ] && [ "$ON" -gt "$AGENT" ]; then
    fail "$NAME: BLOCKED — the agent is started before \`rabadon on\`.
         why: the first supervised session would run in watch mode, which is
         exactly the session the reader installed the tool for.
         next: move the \`rabadon on\` line above the agent line in $NAME"
  else
    pass "$NAME: \`rabadon on\` is not after the agent is started"
  fi
}

# The docs that ship an install path. The anchor is what makes the block the
# INSTALL block: the markdown docs are anchored on the line that wires a
# project (`rabadon init`), the site on the line that fetches and builds it.
check_block "README.md"          "$(md_block   README.md          '^[ \t]*rabadon init')"
check_block "docs/quickstart.md" "$(md_block   docs/quickstart.md  '^[ \t]*rabadon init')"
check_block "site/index.html"    "$(html_block site/index.html     'git clone')"
# site/index.html is a rendering of site/index.tmpl.html; if the two disagree
# the next build silently deletes the line this suite just proved.
check_block "site/index.tmpl.html" "$(html_block site/index.tmpl.html 'git clone')"

# ==========================================================================
# B2 — a documented install command that cannot work is worse than no doc
# ==========================================================================
# The invariant:
#
#   While the version in package.json has no `v<version>` tag in
#   `git tag --list`, no shipped doc may present `npm i -g rabadon` (or
#   `npm install -g rabadon`) as a command the reader is meant to TYPE.
#
# Why a tag is the test: a version that was never tagged was never released,
# so the registry does not have it and `npm i -g rabadon` answers E404. A
# reader who follows the docs to the letter then dies on the FIRST command of
# the FIRST page — the worst possible place to lose someone, and the tool's
# own promise ("say what you can't do, never go quiet") broken by its docs.
#
# This lock RELEASES ITSELF. It is not a ban on the npm path; it is a ban on
# printing it before it exists. The moment a release tags `v<version>`, the
# check below finds the tag, prints a pass, and every line it was guarding
# becomes legal with no edit to this file.
#
# TYPEABLE, precisely, because a fuzzy rule is a rule that gets argued with:
#   1. inside a ```-fence (md) or a <div class="term"> (html) — that is the
#      copy-paste surface, and NOTHING excuses a dead command there; or
#   2. in prose, unless the same line or the line directly above it carries
#      an availability marker (`not on npm yet`, `E404`, `once published`, ...).
#      Prose that names the future path and says plainly that it is not live
#      is documentation. Prose that names it with no such warning is an
#      instruction, and it is a lie today.
#
# OUT OF SCOPE, on purpose: CHANGELOG.md and site/patch-notes.html. Those are
# HISTORICAL RECORD. A sentence written on the day it was written does not
# become false because the world moved; editing it to match today's tag state
# is quiet history-forgery, which is a worse failure than the one this check
# prevents. Archive trees (`*/archive/*`, `*/arsiv/*`) and captured evidence
# (`docs/kanit/*`) are excluded for exactly the same reason: they are records
# of a past state, not instructions for a present reader.
#
# OFFLINE BY CONSTRUCTION: `git tag --list` and file reads. No `npm view`, no
# network, so this runs identically in a clean container with only git+shell.

echo
echo "install docs: no dead npm install command while the version is untagged"

INSTALL_RE='npm[ \t]+(i|install)[ \t]+(-g|--global)[ \t]+rabadon'
# "this command does not work yet" said in a way a machine can see.
MARKER_RE='not on npm yet|not yet on npm|not published|not yet published|once published|when published|E404|unpublished'

VERSION=$(grep -m1 '"version"' package.json | sed -e 's/.*"version"[ \t]*:[ \t]*"//' -e 's/".*//')
if [ -z "$VERSION" ]; then
  fail "BLOCKED — could not read \"version\" out of package.json.
         why: this check compares the shipped version against the git tags, and
         with no version there is nothing to compare, so it would pass on
         nothing — the empty green this suite exists to refuse.
         next: ./native/install_docs_test.sh  (after checking package.json)"
else
  pass "package.json version read: $VERSION"

  if ! TAGS=$(git tag --list 2>/dev/null); then
    fail "BLOCKED — \`git tag --list\` failed; cannot tell if v$VERSION was released.
         why: the release state is the whole premise of this check. Not being
         able to check is not the same as being fine, and this suite never
         reports a green it did not measure.
         next: run ./native/install_docs_test.sh from inside a git clone of the repo"
  elif printf '%s\n' "$TAGS" | grep -qx "v$VERSION"; then
    # The self-release path. Nothing to guard: the command works.
    pass "tag v$VERSION exists — \`npm i -g rabadon\` is a live command, install docs unrestricted"
  else
    pass "tag v$VERSION absent — \`npm i -g rabadon\` is E404 today, so it must not be typeable in any shipped doc"

    # ---- the scanned set -------------------------------------------------
    SCAN=$(
      printf '%s\n' README.md site/index.html site/index.tmpl.html
      find docs -name '*.md' \
        -not -path '*/archive/*' -not -path '*/arsiv/*' -not -path 'docs/kanit/*' \
        | sort
    )
    NF=$(printf '%s\n' "$SCAN" | grep -c . )

    # vacuity guard: a scan over nothing is not a green.
    if [ "$NF" -lt 5 ]; then
      fail "BLOCKED — only $NF file(s) in the scanned set, expected >= 5.
         why: this check is only worth its green if it actually read the
         shipped docs. A collapsed file list would pass on an empty scan.
         next: ./native/install_docs_test.sh  (run from the repo root; check the find expression)"
    else
      pass "scanned set is non-vacuous ($NF files: README, site pages, docs/*.md minus archives and captured evidence)"

      for F in $SCAN; do
        if [ ! -f "$F" ]; then
          fail "$F: BLOCKED — file in the scanned set does not exist.
         why: a doc this check is supposed to guard has been moved or deleted,
         so the guard is silently covering less than it says it does.
         next: restore $F, or remove it from the scanned set in native/install_docs_test.sh"
          continue
        fi

        # HITS: "<line-no>:<kind>" for every typeable occurrence.
        HITS=$(awk -v re="$INSTALL_RE" -v mk="$MARKER_RE" -v html="$F" '
          BEGIN { isHtml = (html ~ /\.html$/) }
          {
            line = $0
            # ---- fence / term-div state, computed BEFORE testing the line ----
            if (isHtml) {
              if (line ~ /class="term"/) inb = 1
            } else {
              if (line ~ /^[ \t]*```/) { inb = !inb; prev = line; next }
            }

            if (line ~ re) {
              if (inb) print NR ":copy-paste block"
              else if (line ~ mk || prev ~ mk) { }   # prose, honestly labelled
              else print NR ":unlabelled prose"
            }

            if (isHtml && line ~ /<\/div>/) inb = 0
            prev = line
          }
        ' "$F")

        if [ -n "$HITS" ]; then
          fail "$F: BLOCKED — a dead \`npm i -g rabadon\` is presented as a command to type:
$(printf '%s\n' "$HITS" | sed 's/^/           line /')
         why: package.json says $VERSION and there is no v$VERSION tag, so that
         version was never released and the registry answers E404. A reader
         following this page verbatim fails on the install command itself.
         next: replace it with the from-source install README.md documents, and
         keep the npm path as prose marked not-yet-published (or tag and publish
         v$VERSION, after which this check releases the line on its own)"
        else
          pass "$F: no typeable \`npm i -g rabadon\`"
        fi
      done
    fi
  fi
fi

echo "$ok ok / $bad fail"
[ "$bad" -eq 0 ] || exit 1
