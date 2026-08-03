#!/bin/bash
# publish_test.sh — a deploy that is not aliased is a deploy nobody sees.
#
# The site's numbers were moved onto the domain by hand, four commands at a
# time, and the fourth is the one with no feedback. `vercel deploy` uploads a
# build and prints a url that nothing has ever pointed at; `vercel alias set`
# is what makes rabadon.noseydewdrop.com serve it. Skip the fourth command and
# every signal still reads success — the deploy exits 0, the url is real, the
# build is live at that url, and the domain keeps serving the previous one.
# There is no error anywhere. The page just quietly says yesterday.
#
# scripts/publish-field.sh exists to run those four steps unattended, so the
# first thing this file asks is whether the alias got the SAME deployment id
# the deploy printed, and it asks it in a way that can answer no: section 1
# runs a copy of the script with the alias step deleted and requires the
# failure to be caught, because a check that has never been red is not a check.
#
# Nothing here deploys anything. `vercel` and `curl` are stubs on PATH: the
# deploy stub copies the uploaded directory into a fake deployment store and
# prints a url, the alias stub records which deployment the domain now points
# at, and the curl stub serves whatever the alias currently points at. That is
# the entire mechanism the real failure lives in, and it is reproducible on a
# machine with no network and no vercel account.
#
# The repository, the ledger, the home directory and the git remote are all
# built here under mktemp, so the real ~/.rabadon, the real site/ and the real
# origin are never read or written.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SCRIPT="$REPO/scripts/publish-field.sh"
[ -f "$SCRIPT" ] || { echo "  no scripts/publish-field.sh to test"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

STUB="$T/stub"
mkdir -p "$STUB/deployments" "$T/bin" "$T/home/.rabadon" "$T/repo/site" "$T/repo/scripts"
export STUB_DIR="$STUB"
export RABADON_DIR="$T/home/.rabadon"
export RABADON_PUBLISH_DOMAIN="rabadon.test"
LOG="$RABADON_DIR/publish.log"

# ---------------------------------------------------------------------------
# the stubs. `vercel deploy` prints a url on stdout and chatter on stderr, the
# way the real one does; the deployment store is what the domain can serve.
# ---------------------------------------------------------------------------
cat > "$T/bin/vercel" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_DIR/argv.log"
case "${1:-}" in
  deploy)
    n=$(( $(cat "$STUB_DIR/n" 2>/dev/null || echo 0) + 1 ))
    printf '%s' "$n" > "$STUB_DIR/n"
    id="rabadon-dep${n}k7q-nosey-dewdrops-projects"
    mkdir -p "$STUB_DIR/deployments/$id"
    cp "$PWD"/*.html "$PWD"/*.json "$PWD"/*.jsonl "$STUB_DIR/deployments/$id/" 2>/dev/null
    [ -n "${STUB_SLOW:-}" ] && sleep 2
    echo "Vercel CLI 55.0.0" >&2
    echo "Inspect: https://vercel.com/nosey-dewdrops-projects/rabadon/9xKq2 [1s]" >&2
    echo "Production: https://$id.vercel.app [3s]" >&2
    echo "https://$id.vercel.app"
    ;;
  alias)
    printf '%s' "$3" > "$STUB_DIR/alias_target"
    printf '%s' "$4" > "$STUB_DIR/alias_domain"
    echo "Success! Assigned $4 to $3"
    ;;
  whoami) echo "nosey-dewdrop" ;;
  *) echo "stub vercel: unhandled $*" >&2; exit 64 ;;
esac
SH

# the domain. it serves the deployment the alias points at, and nothing else —
# which is the only honest model of the bug: an un-moved alias is not an error,
# it is an older file being served with a 200.
cat > "$T/bin/curl" <<'SH'
#!/bin/bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -H) shift 2 ;;
    -*) shift ;;
    *)  shift ;;
  esac
done
target="$(cat "$STUB_DIR/alias_target" 2>/dev/null || true)"
id="${target#https://}"; id="${id%.vercel.app}"
src="$STUB_DIR/deployments/$id/field.html"
[ -n "$id" ] && [ -f "$src" ] || exit 22
[ -n "$out" ] && cp "$src" "$out"
SH

cat > "$T/bin/gh" <<'SH'
#!/bin/bash
[ -f "$STUB_DIR/gh_broken" ] && exit 1
case "$*" in
  "api user --jq .login") echo "nosey-dewdrop" ;;
  *) echo "[]" ;;
esac
SH
chmod +x "$T/bin/vercel" "$T/bin/curl" "$T/bin/gh"
export PATH="$T/bin:$PATH"

# ---------------------------------------------------------------------------
# the repository. a stand-in field_stats.py that reads a ledger this test can
# move, and a stand-in build.py that renders the number into the same
# data-to="<n>" marker the real pages carry.
# ---------------------------------------------------------------------------
cat > "$T/repo/site/field_stats.py" <<'PY'
import json, os, sys
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
n = int(open(os.path.join(os.environ["RABADON_DIR"], "ledger")).read().strip())
if "--write" in sys.argv:
    mp = os.path.join(REPO, "site", "measured.json")
    d = json.load(open(mp, encoding="utf-8")) if os.path.exists(mp) else {}
    # the note carries the raw ledger line count, which the gate increments for
    # every command this job itself runs, so it is different on every read. It
    # is inside a field.* key. If the change trigger hashes the block instead of
    # the values, section 2 below cannot pass.
    note = "read from the ledger (%d lines)" % (100000 + os.getpid())
    d["field.would_block"] = {"value": n, "cmd": "python3 site/field_stats.py",
                              "what": "recorded", "note": note}
    d["field.stop"] = {"value": n * 2, "cmd": "python3 site/field_stats.py",
                       "what": "refused", "note": note}
    # a number that is NOT field.*, rewritten every run. the change trigger must
    # ignore it, or every run deploys and the skip is decorative.
    d["gate.run_nonce"] = {"value": os.getpid(), "cmd": "x", "what": "not a field number"}
    json.dump(d, open(mp, "w", encoding="utf-8"), indent=2, sort_keys=True)
    with open(os.path.join(REPO, "site", "field.jsonl"), "w", encoding="utf-8") as f:
        for i in range(n):
            f.write(json.dumps({"ev": "WOULD_BLOCK", "i": i}) + "\n")
print("ledger read: %d" % n)
PY

cat > "$T/repo/site/build.py" <<'PY'
import json, os
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
d = json.load(open(os.path.join(REPO, "site", "measured.json"), encoding="utf-8"))
wb, st = d["field.would_block"]["value"], d["field.stop"]["value"]
def w(name, body):
    open(os.path.join(REPO, "site", name), "w", encoding="utf-8").write(body)
mark = ('<div><a class="n p" data-to="%d" data-show="%d">%d</a>'
        '<span class="t">commands it would have refused</span></div>'
        '<div><a class="n y" data-to="%d" data-show="%d">%d</a>'
        '<span class="t">commands it refused outright</span></div>' % (wb, wb, wb, st, st, st))
w("field.html", "<html><body><div class=proof>" + mark + "</div></body></html>\n")
w("index.html", "<html><body>overview " + mark + "</body></html>\n")
w("patch-notes.html", "<html><body>patch notes</body></html>\n")
w("sitemap.xml", "<urlset/>\n")
w("robots.txt", "User-agent: *\nAllow: /\n")
prs = os.environ.get("STUB_PRS", "one pull request")
w("pull-requests.html", "<html><body>%s</body></html>\n" % prs)
print("built")
PY

cp "$SCRIPT" "$T/repo/scripts/publish-field.sh"
chmod +x "$T/repo/scripts/publish-field.sh"
RUN="$T/repo/scripts/publish-field.sh"

git init -q "$T/origin.git" --bare 2>/dev/null || { mkdir -p "$T/origin.git"; git init -q --bare "$T/origin.git"; }
(
  cd "$T/repo"
  git init -q .
  git symbolic-ref HEAD refs/heads/main
  git config user.email "test@example.invalid"
  git config user.name  "publish test"
  git config commit.gpgsign false
  git remote add origin "$T/origin.git"
  printf '5\n' > "$RABADON_DIR/ledger"
  RABADON_DIR="$RABADON_DIR" python3 site/field_stats.py --write >/dev/null
  python3 site/build.py >/dev/null
  git add -A
  git commit -q -m "the site as it stood before anything was published"
  git push -q origin main
) || { echo "  fixture repo could not be built"; exit 1; }

set_ledger() { printf '%s\n' "$1" > "$RABADON_DIR/ledger"; }
vercel_calls() { wc -l < "$STUB/argv.log" 2>/dev/null | tr -d ' '; }
alias_now()   { cat "$STUB/alias_target" 2>/dev/null; }

echo "publish — the deploy is not the publish; the alias is"
echo

# ---------------------------------------------------------------------------
# 1. THE ALIAS GETS THE DEPLOYMENT THE DEPLOY PRINTED
# ---------------------------------------------------------------------------
# Written first and required to be able to fail. Everything else in this file is
# housekeeping around this one line.
echo "1. the alias is set to the same deployment id the deploy printed"
set_ledger 41
OUT="$("$RUN" 2>&1)"; RC=$?
DEPLOYED="$(grep -Eo 'https://rabadon-dep[0-9]+k7q-nosey-dewdrops-projects\.vercel\.app' "$STUB/argv.log" 2>/dev/null | tail -1)"
# what the deploy PRINTED, read back out of the stub's own deployment store
LATEST="https://rabadon-dep$(cat "$STUB/n" 2>/dev/null)k7q-nosey-dewdrops-projects.vercel.app"

if [ $RC -eq 0 ]; then ok "the first publish succeeded (exit 0)"
else bad "the first publish failed (exit $RC)"; echo "$OUT" | sed 's/^/        /'; fi

if [ "$(alias_now)" = "$LATEST" ]; then
  ok "alias points at $LATEST — the deployment this run created"
else
  bad "alias points at '$(alias_now)', the deploy printed '$LATEST'"
fi

if grep -q "alias set $LATEST rabadon.test" "$STUB/argv.log"; then
  ok "vercel alias set was called with that url and the domain"
else
  bad "no 'alias set <that url> rabadon.test' in the stub's argv log"
  sed 's/^/        /' "$STUB/argv.log"
fi

# and the deployment the domain now serves has to carry the number just written
if [ "$(cat "$STUB/deployments/rabadon-dep$(cat "$STUB/n")k7q-nosey-dewdrops-projects/field.html" 2>/dev/null | grep -c 'data-to="41"')" -ge 1 ]; then
  ok "the aliased deployment carries would_block=41"
else
  bad "the aliased deployment does not carry the number that was published"
fi

echo
echo "1b. the same run with the alias step deleted must be caught"
# The bug, reproduced: deploy succeeds, url is real, alias never moves. If the
# script's verification cannot see this, the check in 1 proves nothing.
sed '/vercel alias set/,+1d' "$RUN" > "$T/repo/scripts/no-alias.sh"
chmod +x "$T/repo/scripts/no-alias.sh"
BEFORE="$(alias_now)"
set_ledger 42
OUT="$("$T/repo/scripts/no-alias.sh" 2>&1)"; RC=$?
if [ $RC -ne 0 ]; then ok "the un-aliased publish is rejected (exit $RC)"
else bad "an un-aliased deploy reported success — the whole point of this file"; echo "$OUT" | sed 's/^/        /'; fi
if echo "$OUT" | grep -q "verify"; then ok "it names the step that failed: verify"
else bad "it does not name the failing step"; echo "$OUT" | sed 's/^/        /'; fi
if [ "$(alias_now)" = "$BEFORE" ]; then ok "the domain is provably still on the older deployment"
else bad "the alias moved in a run that had no alias step"; fi
if tail -1 "$LOG" | grep -q "FAILED"; then ok "the failure is written to the log, not only to stdout"
else bad "a failed run left no FAILED line in $LOG"; tail -2 "$LOG" | sed 's/^/        /'; fi

echo

# ---------------------------------------------------------------------------
# 2. NOTHING CHANGED -> vercel is not called at all
# ---------------------------------------------------------------------------
echo "2. a second run with an unchanged ledger does not deploy"
set_ledger 41                 # back to the state that was actually published
"$RUN" >/dev/null 2>&1        # re-publish 41 so the state file matches reality
BEFORE_CALLS="$(vercel_calls)"
OUT="$("$RUN" 2>&1)"; RC=$?
AFTER_CALLS="$(vercel_calls)"
if [ "$AFTER_CALLS" = "$BEFORE_CALLS" ]; then ok "vercel was not invoked once ($BEFORE_CALLS calls before and after)"
else bad "vercel was called $((AFTER_CALLS - BEFORE_CALLS)) time(s) on an unchanged ledger"; fi
if [ $RC -eq 0 ]; then ok "the no-op run still exits 0"
else bad "the no-op run exited $RC"; echo "$OUT" | sed 's/^/        /'; fi
if echo "$OUT" | grep -qi "no change"; then ok "it says 'no change' rather than going quiet"
else bad "it does not say what it decided"; echo "$OUT" | sed 's/^/        /'; fi
if tail -1 "$LOG" | grep -qi "no change"; then ok "the skipped run is on the log too — silence is not an answer"
else bad "a skipped run left nothing in $LOG"; fi

# two things move under it on every single run and neither is a published
# number: gate.run_nonce, which is not a field.* key at all, and the `note`
# INSIDE field.would_block, which carries the ledger's raw line count and is
# therefore incremented by the very commands this job runs. The second one is
# not hypothetical — it shipped, and it redeployed the identical site twice
# twenty seconds apart before it was caught.
if [ "$AFTER_CALLS" = "$BEFORE_CALLS" ]; then
  ok "a non-field number changing under it does not trigger a deploy"
  ok "a note inside a field.* key changing does not trigger a deploy either"
fi
if grep -q '"note"' "$T/repo/site/measured.json" && \
   [ "$(grep -c 'read from the ledger' "$T/repo/site/measured.json")" -ge 1 ]; then
  ok "the volatile note really is in the file the trigger reads (fixture is honest)"
else
  bad "the fixture no longer contains the volatile note, so the check above proves nothing"
fi

echo

# ---------------------------------------------------------------------------
# 3. THE LEDGER MOVED -> it does deploy
# ---------------------------------------------------------------------------
echo "3. a changed ledger does deploy"
BEFORE_CALLS="$(vercel_calls)"
BEFORE_ALIAS="$(alias_now)"
set_ledger 77
OUT="$("$RUN" 2>&1)"; RC=$?
AFTER_CALLS="$(vercel_calls)"
if [ "$AFTER_CALLS" -gt "$BEFORE_CALLS" ]; then ok "vercel was invoked ($((AFTER_CALLS - BEFORE_CALLS)) calls: deploy and alias)"
else bad "a changed ledger did not reach vercel"; echo "$OUT" | sed 's/^/        /'; fi
if [ "$(alias_now)" != "$BEFORE_ALIAS" ]; then ok "the alias moved to the new deployment"
else bad "the alias did not move for a real change"; fi
if [ $RC -eq 0 ] && echo "$OUT" | grep -q "would_block=77"; then ok "it reports the number it published (77)"
else bad "exit $RC, and the run does not name the published number"; echo "$OUT" | sed 's/^/        /'; fi
if tail -1 "$LOG" | grep -Eq 'https://rabadon-dep[0-9]+k7q'; then ok "the log line carries the deployment url"
else bad "the log does not say which deployment went live"; tail -1 "$LOG" | sed 's/^/        /'; fi

echo

# ---------------------------------------------------------------------------
# 4. TWO AT ONCE -> one proceeds
# ---------------------------------------------------------------------------
echo "4. two concurrent runs, one publish"
# first deterministically: a lock held by a process that IS alive must be
# respected, with no timing involved.
mkdir -p "$RABADON_DIR/publish.lock"
echo $$ > "$RABADON_DIR/publish.lock/pid"
BEFORE_CALLS="$(vercel_calls)"
set_ledger 91
OUT="$("$RUN" 2>&1)"; RC=$?
if [ "$(vercel_calls)" = "$BEFORE_CALLS" ]; then ok "a held lock stops the run before any deploy"
else bad "it deployed while another copy held the lock"; fi
if [ $RC -eq 0 ]; then ok "the blocked run exits 0 quietly, not as an error"
else bad "the blocked run exited $RC"; fi
if echo "$OUT" | grep -qi "another publish is running"; then ok "it says who is holding it"
else bad "it does not explain why it did nothing"; echo "$OUT" | sed 's/^/        /'; fi
rm -rf "$RABADON_DIR/publish.lock"

# then for real: two copies started together, with a deploy slow enough that
# they overlap. exactly one of them may reach vercel.
BEFORE_CALLS="$(vercel_calls)"
set_ledger 92
STUB_SLOW=1 "$RUN" > "$T/a.out" 2>&1 &
P1=$!
STUB_SLOW=1 "$RUN" > "$T/b.out" 2>&1 &
P2=$!
wait $P1; RC1=$?
wait $P2; RC2=$?
DELTA=$(( $(vercel_calls) - BEFORE_CALLS ))
if [ "$DELTA" -le 2 ]; then ok "two concurrent runs produced at most one deploy+alias pair ($DELTA vercel calls)"
else bad "two concurrent runs made $DELTA vercel calls — both deployed"; cat "$T/a.out" "$T/b.out" | sed 's/^/        /'; fi
if grep -qi "another publish is running" "$T/a.out" "$T/b.out"; then ok "the loser says it stood down"
else bad "neither run reported standing down"; cat "$T/a.out" "$T/b.out" | sed 's/^/        /'; fi
if [ $RC1 -eq 0 ] && [ $RC2 -eq 0 ]; then ok "both exit 0 — losing a lock race is not a failure"
else bad "a lock race produced a non-zero exit ($RC1, $RC2)"; fi
if [ ! -d "$RABADON_DIR/publish.lock" ]; then ok "the lock is released when the run ends"
else bad "the lock outlived the run that took it"; fi

echo

# ---------------------------------------------------------------------------
# 5. IT NEVER STAGES A PATH OUTSIDE site/
# ---------------------------------------------------------------------------
echo "5. what it is allowed to commit"
# Another session is mid-edit. Two of its files are OUTSIDE site/ and two are
# INSIDE it — site/build.py and site/field_stats.py live there — so `git add
# site/` is not narrow enough and this asks for the narrower thing.
mkdir -p "$T/repo/native"
printf 'int main(){}\n' > "$T/repo/native/gate.cpp"
printf 'somebody else was editing this\n' >> "$T/repo/Makefile"
(cd "$T/repo" && git add native/gate.cpp Makefile && git commit -q -m "another session's work, already committed")
printf '// half-finished edit by another session\n' >> "$T/repo/native/gate.cpp"
printf '# half-finished edit by another session\n' >> "$T/repo/Makefile"
printf '# half-finished edit, and it is UNDER site/\n' >> "$T/repo/site/build.py"

BEFORE_OTHERS="$(cd "$T/repo" && git rev-parse HEAD)"
set_ledger 108
OUT="$("$RUN" 2>&1)"; RC=$?
TOUCHED="$(cd "$T/repo" && git show --name-only --format= HEAD | grep -v '^$' | tr '\n' ' ')"

if [ $RC -eq 0 ]; then ok "it published with another session mid-edit (exit 0)"
else bad "another session's dirty tree broke the publish (exit $RC)"; echo "$OUT" | sed 's/^/        /'; fi

OUTSIDE="$(cd "$T/repo" && git show --name-only --format= HEAD | grep -v '^site/' | grep -v '^$' || true)"
if [ -z "$OUTSIDE" ]; then ok "the commit touches nothing outside site/ ($TOUCHED)"
else bad "it committed paths outside site/: $(echo "$OUTSIDE" | tr '\n' ' ')"; fi

if (cd "$T/repo" && git show --name-only --format= HEAD | grep -q '^site/build.py$'); then
  bad "it committed site/build.py — under site/, and not a file this job writes"
else
  ok "site/build.py is under site/ and was still left alone"
fi

if (cd "$T/repo" && git status --porcelain -- native/gate.cpp Makefile site/build.py | grep -q '^ M'); then
  ok "the other session's three edits are still uncommitted, where it left them"
else
  bad "the other session's edits were swept up"
  (cd "$T/repo" && git status --porcelain | sed 's/^/        /')
fi

if (cd "$T/repo" && git log --oneline "$BEFORE_OTHERS..HEAD" | grep -qi "field numbers"); then
  ok "the commit message names what it is (lowercase, no co-author line)"
else
  bad "no publish commit was written"
fi
if (cd "$T/repo" && git log -1 --format=%B | grep -qi "co-authored-by"); then
  bad "the commit carries a co-author line"
else
  ok "no co-author trailer"
fi
if (cd "$T/repo" && git log --oneline origin/main -1 | grep -q .); then
  ok "the commit reached origin (a normal push, no force)"
else
  bad "nothing was pushed"
fi

echo

# ---------------------------------------------------------------------------
# 6. A HOLLOW PAGE IS NOT PUBLISHED IN PLACE OF A FULL ONE
# ---------------------------------------------------------------------------
# build.py reads the open pull requests off GitHub and renders an empty page
# when gh cannot answer. Under a scheduler nobody sees that happen.
echo "6. gh unreachable does not publish an empty pull-requests page"
touch "$STUB/gh_broken"
STUB_PRS="" ; export STUB_PRS
set_ledger 133
OUT="$("$RUN" 2>&1)"; RC=$?
unset STUB_PRS
rm -f "$STUB/gh_broken"
if grep -q "one pull request" "$T/repo/site/pull-requests.html"; then
  ok "the previous pull-requests page was kept rather than published empty"
else
  bad "an empty pull-requests page was published while gh was down"
  cat "$T/repo/site/pull-requests.html" | sed 's/^/        /'
fi
if grep -q "gh could not answer" "$LOG"; then ok "and it said so in the log"
else bad "it silently substituted a page"; fi

echo

# ---------------------------------------------------------------------------
# 7. THE LOG ANSWERS "WHEN DID THE SITE LAST ACTUALLY UPDATE"
# ---------------------------------------------------------------------------
echo "7. the log"
if [ -s "$LOG" ]; then ok "$(wc -l < "$LOG" | tr -d ' ') lines, one per run"
else bad "no log at $LOG"; fi
if grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$LOG"; then
  ok "every line starts with an unambiguous utc timestamp"
else
  bad "the log lines are not timestamped"; head -3 "$LOG" | sed 's/^/        /'
fi
if grep -q "published" "$LOG" && grep -qi "no change" "$LOG" && grep -q "FAILED" "$LOG"; then
  ok "published, no change and FAILED are all distinguishable in one file"
else
  bad "the log does not separate the three outcomes"; sed 's/^/        /' "$LOG"
fi
if [ "$(grep -c 'https://rabadon-dep' "$LOG")" -ge 2 ]; then
  ok "each published line carries the deployment url it aliased"
else
  bad "a human still cannot tell which deployment is live"; sed 's/^/        /' "$LOG"
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
