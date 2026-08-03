#!/bin/bash
# publish-field.sh — keep the published numbers as fresh as the ledger they come from.
#
# The field page says what the engine did in real repositories, and it says it in
# past tense off a file that is still being appended to. Between 25 July and
# tonight the only thing moving those numbers onto the page was an operator
# typing four commands in a row, and the last hand-run happened at 03:03. There
# is no cron entry, no launchd job and no workflow that deploys, so from 03:03
# onward the page described a ledger that had grown by 478 events and said
# nothing about them. A page that measures itself and freezes the moment nobody
# is watching is a page that ages into a claim.
#
#   python3 site/field_stats.py --write   read the ledger, write the numbers
#   python3 site/build.py                 render the pages from the numbers
#   vercel deploy --prod --yes            upload, and PRINT a deployment url
#   vercel alias set <that url> <domain>  point the domain at that deployment
#
# THE FOURTH STEP IS THE WHOLE FAILURE MODE. A deploy that is not aliased is a
# deploy that exists at a url nobody visits; the domain keeps serving whatever
# it was serving yesterday, and every signal says success. So the url is
# captured from the deploy's own output rather than reconstructed, the alias is
# set to exactly that url, and afterwards the live domain is fetched over the
# network and asked whether it is carrying the numbers that were just written.
#
# Three things it refuses to do.
#
# It does not deploy a site that did not change. The trigger is a hash of the
# field.* section of site/measured.json plus site/field.jsonl — the two files
# that carry every number on the page. Identical hash, no upload.
#
# It does not stage a file it did not write. Another session is usually editing
# site/build.py and site/field_stats.py, which live under site/, so `git add
# site/` would sweep somebody's half-finished work into an unattended commit.
# The staged set is the explicit list of generated artefacts below and nothing
# else, which is narrower than site/ and can only get narrower.
#
# It does not run beside itself. Two copies racing means two deploys racing the
# alias, and the domain ends up on whichever one finished second, which is not
# necessarily the newer one.
#
#   scripts/publish-field.sh          run it
#   ~/.rabadon/publish.log            one line per run: when, what, which url
#
# exit 0 published / 0 nothing to publish / 0 another copy holds the lock
# exit non-zero on a real failure, with the step that failed named on stdout
# and in the log.
set -u

# --------------------------------------------------------------------------
# where things are. the repository is resolved from THIS FILE, never from $PWD:
# a scheduler starts the job in / and a shell starts it wherever the operator
# happened to be standing, and both have to reach the same tree.
# --------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

# launchd hands a job a PATH of /usr/bin:/bin:/usr/sbin:/sbin and nothing else,
# and vercel, gh, node and python3 all live in the homebrew prefix. Named here
# rather than in the plist so the script behaves the same however it is started.
# An existing PATH is kept in front so a test can put a stub ahead of the real
# thing.
PATH="${PATH}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

STATE_DIR="${RABADON_DIR:-$HOME/.rabadon}"
LOG="$STATE_DIR/publish.log"
STATE="$STATE_DIR/publish.state"
LOCK="$STATE_DIR/publish.lock"
DOMAIN="${RABADON_PUBLISH_DOMAIN:-rabadon.noseydewdrop.com}"

# the files this script generates, and therefore the only files it may stage.
# site/build.py and site/field_stats.py are deliberately absent: they are inputs
# somebody else edits, not outputs this job produces.
ARTIFACTS="site/index.html site/field.html site/catches.html site/benchmarks.html \
site/patch-notes.html site/pull-requests.html site/measured.json site/field.jsonl \
site/sitemap.xml site/robots.txt"

mkdir -p "$STATE_DIR"
TMP="$(mktemp -d)"
STARTED="$(date -u +%s)"
HELD_LOCK=""
EXIT_CODE=0

now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }
say()  { printf '%s\n' "$*"; }
log()  { printf '%s  %s\n' "$(now)" "$*" >> "$LOG"; }

# the lock is released by a trap rather than by each exit path, because the exit
# path that gets forgotten is the one that leaves a lock behind and stops every
# future run of an unattended job.
cleanup() { rm -rf "$TMP"; [ -n "$HELD_LOCK" ] && rm -rf "$LOCK"; return 0; }
trap cleanup EXIT

# every exit goes through one of these two, so no run can end without a line in
# the log saying what it did.
finish() {   # finish <word> <rest of the line>
  local word="$1"; shift
  log "$(printf '%-10s %s' "$word" "$*")"
  say "$word: $*"
  # a run can publish the site correctly and still have failed at something.
  # The line above records what it did; the exit code has to record that
  # something went wrong, or a scheduler watching exit codes never learns.
  exit "${EXIT_CODE:-0}"
}
die() {      # die <step> <what went wrong>
  local step="$1"; shift
  log "$(printf '%-10s %s' FAILED "step '$step': $*")"
  say "FAILED at step '$step': $*"
  exit 1
}

# --------------------------------------------------------------------------
# 0. the lock. mkdir is the atomic primitive that exists on every unix; macOS
#    has no flock(1). The pid inside is what makes a crashed run recoverable
#    without a human: a lock whose owner is gone is not a lock, it is litter.
# --------------------------------------------------------------------------
take_lock() {
  if mkdir "$LOCK" 2>/dev/null; then HELD_LOCK=1; echo $$ > "$LOCK/pid"; return 0; fi
  local owner; owner="$(cat "$LOCK/pid" 2>/dev/null || echo '?')"
  if [ "$owner" != "?" ] && ! kill -0 "$owner" 2>/dev/null; then
    # the owner is not running. clear it once and try again exactly once, so a
    # genuine race still ends with one winner rather than two.
    rm -rf "$LOCK"
    if mkdir "$LOCK" 2>/dev/null; then
      HELD_LOCK=1; echo $$ > "$LOCK/pid"
      log "$(printf '%-10s %s' cleared "a lock left behind by pid $owner, which is not running")"
      return 0
    fi
    owner="$(cat "$LOCK/pid" 2>/dev/null || echo '?')"
  fi
  finish locked "another publish is running (pid $owner) — this run did nothing"
}
take_lock

# --------------------------------------------------------------------------
# the change trigger: the VALUES under the field.* block of measured.json, plus
# every published record. Everything the page says about the field is derived
# from these, so if they are unchanged the page has nothing new to say.
#
# THE VALUES, AND NOT THE WHOLE BLOCK. Measured, not assumed: two runs twenty
# seconds apart both published 430 recorded and 456 refused, and both deployed,
# because every field.* entry carries a `note` that ends "83786 lines over 10
# day files" — the raw line count of the ledger. The gate appends to that ledger
# continuously, including for the commands this script itself runs, so the note
# is different on every single read. Hashing the block as written would have
# deployed the identical site 48 times a day forever, each deploy caused by the
# previous one. The counter is real and it belongs on the page; it is not a
# reason to re-upload the page.
# --------------------------------------------------------------------------
field_hash() {
  {
    python3 - "$REPO/site/measured.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    sys.stderr.write("measured.json unreadable: %s\n" % e); sys.exit(1)
print(json.dumps({k: (v.get("value") if isinstance(v, dict) else v)
                  for k, v in d.items() if k.startswith("field.")},
                 sort_keys=True, ensure_ascii=False))
PY
    cat "$REPO/site/field.jsonl" 2>/dev/null
  } | shasum -a 256 | cut -d' ' -f1
}

field_value() {   # field_value <key> -> the integer the page will print
  python3 - "$REPO/site/measured.json" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
v = d.get(sys.argv[2], {}).get("value")
print(v if isinstance(v, int) else "")
PY
}

# the numbers as they appear in the rendered html, in order. build.py writes
# every headline figure as data-to="<n>", so this is the page's own numeric
# fingerprint — and unlike a sentence, it does not change when somebody rewrites
# the prose around it.
page_numbers() {  # page_numbers <file>
  grep -Eo 'data-to="[0-9]+"' "$1" 2>/dev/null | sed 's/[^0-9]//g' | tr '\n' ' '
}

# --------------------------------------------------------------------------
# 1. read the ledger
# --------------------------------------------------------------------------
cd "$REPO" || die setup "cannot enter the repository at $REPO"
[ -f site/field_stats.py ] || die setup "no site/field_stats.py under $REPO"
[ -f site/build.py ]       || die setup "no site/build.py under $REPO"

if ! python3 site/field_stats.py --write > "$TMP/stats.out" 2>&1; then
  die field_stats "$(tail -3 "$TMP/stats.out" | tr '\n' ' ')"
fi

WOULD_BLOCK="$(field_value field.would_block)"
STOP="$(field_value field.stop)"
[ -n "$WOULD_BLOCK" ] || die field_stats "measured.json has no field.would_block after the write"

NEW_HASH="$(field_hash)"
OLD_HASH="$(cat "$STATE" 2>/dev/null || echo none)"

# --------------------------------------------------------------------------
# 2. render the pages
# --------------------------------------------------------------------------
# build.py reads the open pull requests off GitHub and returns an empty list if
# gh cannot answer, which renders a truthful-looking page saying there are none.
# Under a scheduler nobody is watching that happen, so the page is put back the
# way it was rather than published hollow.
GH_OK=1
gh api user --jq .login > /dev/null 2>&1 || GH_OK=0

if ! python3 site/build.py > "$TMP/build.out" 2>&1; then
  die build "$(tail -3 "$TMP/build.out" | tr '\n' ' ')"
fi

if [ "$GH_OK" -eq 0 ]; then
  if git show HEAD:site/pull-requests.html > "$TMP/pr.html" 2>/dev/null; then
    cp "$TMP/pr.html" site/pull-requests.html
    log "$(printf '%-10s %s' kept "gh could not answer; site/pull-requests.html restored from HEAD rather than published empty")"
  fi
fi

# --------------------------------------------------------------------------
# 3. is there anything to publish?
# --------------------------------------------------------------------------
if [ "$NEW_HASH" = "$OLD_HASH" ]; then
  DIRTY="$(git status --porcelain -- $ARTIFACTS 2>/dev/null | awk '{print $2}' | tr '\n' ' ')"
  if [ -n "$DIRTY" ]; then
    # the rendered pages moved without the field numbers moving, which is what a
    # new commit landing in patch-notes looks like. Not published on its own,
    # and not hidden either: it rides along with the next real change.
    finish "no change" "field hash ${NEW_HASH:0:12}, would_block=$WOULD_BLOCK — nothing deployed; rebuilt but unpublished: $DIRTY"
  fi
  finish "no change" "field hash ${NEW_HASH:0:12}, would_block=$WOULD_BLOCK — nothing deployed"
fi

# --------------------------------------------------------------------------
# 4. commit the artefacts. ONLY the artefacts.
# --------------------------------------------------------------------------
STAGE=""
for f in $ARTIFACTS; do [ -f "$f" ] && STAGE="$STAGE $f"; done
# shellcheck disable=SC2086
git add -- $STAGE || die commit "git add refused the artefact list"

# and prove it before writing history: anything staged that is not on the list
# is somebody else's work, and the commit does not happen.
OUTSIDE="$(git diff --cached --name-only | grep -v '^site/' || true)"
[ -z "$OUTSIDE" ] || die commit "refusing to commit: staged paths outside site/ — $(echo "$OUTSIDE" | tr '\n' ' ')"
NOTOURS="$(git diff --cached --name-only | grep -vE '^(site/(index|field|catches|benchmarks|patch-notes|pull-requests)\.html|site/measured\.json|site/field\.jsonl|site/sitemap\.xml|site/robots\.txt)$' || true)"
[ -z "$NOTOURS" ] || die commit "refusing to commit: staged a file this job does not generate — $(echo "$NOTOURS" | tr '\n' ' ')"

COMMITTED=none
if ! git diff --cached --quiet; then
  MSG="the field numbers, regenerated from the ledger at $WOULD_BLOCK recorded and $STOP refused"
  git commit -q -m "$MSG" || die commit "git commit failed"
  COMMITTED="$(git rev-parse --short HEAD)"
fi

# A push that loses a race with another session must not stop the numbers from
# reaching the page: the site is the thing the public reads, the commit is local
# and the next successful run carries it. So the deploy goes ahead — and the run
# still ends non-zero, because a failure that exits 0 is a failure nobody hears
# about until somebody goes looking.
PUSHED=ok
if [ "$COMMITTED" != none ]; then
  if ! git push origin main > "$TMP/push.out" 2>&1; then
    PUSHED="FAILED($(tail -1 "$TMP/push.out" | tr -d '\n' | cut -c1-90))"
    EXIT_CODE=1
  fi
fi

# --------------------------------------------------------------------------
# 5. deploy, and CATCH THE URL IT PRINTS
# --------------------------------------------------------------------------
# snapshotted here rather than after the render: vercel uploads site/ as it
# stands at THIS moment, so the copy the verification compares against has to be
# taken as late as possible, next to the upload it is meant to describe.
cp site/field.html "$TMP/field.built.html" 2>/dev/null

( cd "$REPO/site" && vercel deploy --prod --yes ) > "$TMP/dep.out" 2> "$TMP/dep.err"
DEP_RC=$?
[ $DEP_RC -eq 0 ] || die deploy "vercel deploy exited $DEP_RC — $(tail -2 "$TMP/dep.err" | tr '\n' ' ')"

URL_RE='https://[A-Za-z0-9._-]+\.vercel\.app'
DEPLOY_URL="$(grep -Eo "$URL_RE" "$TMP/dep.out" | tail -1)"
[ -n "$DEPLOY_URL" ] || DEPLOY_URL="$(grep -Eo "$URL_RE" "$TMP/dep.err" | tail -1)"
[ -n "$DEPLOY_URL" ] || die deploy "the deploy succeeded and printed no deployment url — refusing to guess one; the alias would have been pointed at nothing"

# --------------------------------------------------------------------------
# 6. move the alias TO THAT DEPLOYMENT, not to some other one
# --------------------------------------------------------------------------
vercel alias set "$DEPLOY_URL" "$DOMAIN" > "$TMP/alias.out" 2>&1 \
  || die alias "vercel alias set $DEPLOY_URL $DOMAIN failed — $(tail -2 "$TMP/alias.out" | tr '\n' ' ')"

# --------------------------------------------------------------------------
# 7. ask the live domain what it is serving
# --------------------------------------------------------------------------
# The assertion is not "the deploy command said ok". It is that the page the
# public gets back carries the numbers that were just written. The comparison is
# the ordered list of figures the page renders, so it survives somebody
# rewriting the prose around them.
WANT="$(page_numbers "$TMP/field.built.html")"
SERVED=""; GOT=""; TRY=0
while [ $TRY -lt 5 ]; do
  TRY=$((TRY+1))
  if curl -fsSL -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
        "https://$DOMAIN/field?publish=$STARTED.$TRY" -o "$TMP/served.html" 2>/dev/null; then
    GOT="$(page_numbers "$TMP/served.html")"
    SERVED="$(grep -Eo "data-to=\"$WOULD_BLOCK\"" "$TMP/served.html" | head -1)"
    [ "$GOT" = "$WANT" ] && break
  fi
  sleep 3
done

if [ "$GOT" != "$WANT" ]; then
  die verify "https://$DOMAIN is not serving the build that was just deployed. deployment $DEPLOY_URL, alias set, page still reports [$GOT] where the build says [$WANT]"
fi
[ -n "$SERVED" ] || die verify "the served page does not carry field.would_block=$WOULD_BLOCK"

ELAPSED=$(( $(date -u +%s) - STARTED ))
printf '%s' "$NEW_HASH" > "$STATE"

finish published "would_block=$WOULD_BLOCK stop=$STOP  $DEPLOY_URL  alias=$DOMAIN  served=$WOULD_BLOCK  commit=$COMMITTED push=$PUSHED  ${ELAPSED}s"
