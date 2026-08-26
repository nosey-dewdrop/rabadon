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

echo "$ok ok / $bad fail"
[ "$bad" -eq 0 ] || exit 1
