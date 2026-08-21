#!/bin/bash
# cli_test.sh — the first sixty seconds, for someone who has never seen this.
#
# Every case here is something a stranger does before they have read anything,
# and each one used to end badly:
#   - `rabadon --help`, `-h` and `help` all printed `unknown command` and
#     exited 1. That is the FIRST thing a new user types.
#   - a bare `rabadon` silently TOGGLED machine-wide enforcement, so the second
#     thing they type changed the tool's state without saying so — and typing
#     it twice put it back, which reads as "nothing happened".
#   - `rabadon trace`, the command that shows what the tool actually did,
#     rendered its whole interface in Turkish.
#
# None of these are bugs in the engine. All of them decide whether the engine
# ever gets run a second time.
set -u
cd "$(dirname "$0")/.."
CLI=./native/rabadon-cli.sh
[ -x "$CLI" ] || { echo "cli_test: $CLI is not executable"; exit 1; }

ok=0; bad=0
pass() { ok=$((ok+1)); echo "  ok   - $1"; }
fail() { bad=$((bad+1)); echo "  FAIL - $1"; }

echo "cli: the stranger's first sixty seconds"

HOME_DIR=$(mktemp -d /tmp/rabadon-cli-test.XXXXXX)
trap 'rm -rf "$HOME_DIR"' EXIT
run() { RABADON_DIR="$HOME_DIR" RABADON_NOTIFY=0 "$CLI" "$@"; }

# ---- 1. help exists, under all three spellings a person actually types ----
for FLAG in --help -h help; do
  OUT=$(run $FLAG 2>&1); RC=$?
  [ $RC -eq 0 ] && pass "\`rabadon $FLAG\` exits 0" || fail "\`rabadon $FLAG\` exited $RC"
  printf '%s' "$OUT" | grep -qi "unknown command" && fail "\`rabadon $FLAG\` still says 'unknown command'" \
    || pass "\`rabadon $FLAG\` does not say 'unknown command'"
  # a help screen that lists no verbs is not a help screen. The list is
  # DERIVED, never written down here — see section 1b for why.
  printf '%s' "$OUT" > "$HOME_DIR/help.txt"
  printf '%s' "$OUT" | grep -q "rabadon init" \
    && pass "\`rabadon $FLAG\` shows a runnable example" || fail "\`rabadon $FLAG\` has no example"
done

# ---- 1b. every binary we SHIP is a binary a stranger can run ----
# This used to be `for VERB in init usage exec audit doctor drill trace repair`,
# eight verbs typed in by hand, and that hand-kept list is what let the cost half
# of the product ship invisible: native/rabadon-lens was built by `make all`,
# listed in the `files` of all four @rabadon/<platform> packages, counted by
# `rabadon doctor` as 16/16 — and `rabadon lens` answered `unknown command
# "lens"`, exit 1. Nine of the sixteen were in that state. The suite was green
# the whole time, because lens was never one of the eight words.
#
# package.json `bin` is a single entry, native/rabadon-cli.sh, and the platform
# packages declare no bin at all. So after `npm i -g rabadon` the dispatcher IS
# the public surface: a binary it never names cannot be run by anybody who did
# not clone the repo.
#
# So nothing here is written down. The binaries come from the same glob section
# 5 uses, and the VERBS come from parsing the case arms of rabadon-cli.sh — the
# dispatch code itself, not a table beside it that could quietly disagree with
# it. Four assertions per binary, and the ones with teeth are positive:
#   - some case arm resolves `nbin <name>`            (it is dispatched at all)
#   - the help screen names one of that arm's labels  (it can be discovered)
#   - `rabadon <verb> --help` prints "rabadon-<name>" (the verb lands on THAT
#     binary — without this, "no unknown command" passes for a verb wired to the
#     wrong binary, or for one whose error string was merely renamed)
#   - and only then: no "unknown command", exit != 1
VERB_REPORT=$(mktemp /tmp/rabadon-verb-report.XXXXXX)
python3 - "$CLI" "$HOME_DIR/help.txt" "$VERB_REPORT" <<'PY'
import glob, os, re, subprocess, sys, tempfile

cli, helpfile, report = os.path.abspath(sys.argv[1]), sys.argv[2], sys.argv[3]
out = []
def rec(good, msg): out.append(("PASS" if good else "FAIL") + "\t" + msg)

root = os.getcwd()
names = sorted(os.path.basename(b)[len("rabadon-"):]
               for b in glob.glob(os.path.join(root, "native", "rabadon-*"))
               if not b.endswith(".sh") and os.access(b, os.X_OK))
# a glob that matched nothing would make every assertion below vacuous
rec(len(names) >= 16, "the verb probe found %d shipped binaries to account for" % len(names)
    if len(names) >= 16 else
    "the verb probe found only %d binaries (%s) — build first, this run proves nothing"
    % (len(names), " ".join(names)))

# ---- the verb map, read out of the dispatch code ----
src = open(cli, encoding="utf-8").read()
head = 'case "$VERB" in'
block = src[src.index(head) + len(head):src.rindex("esac")]
verbs = {}          # binary -> [labels], in the order the arms appear
for arm in block.split(";;"):
    labels = None
    for line in arm.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        m = re.match(r"^([^()]*?)\)", s)      # the arm's labels, `a|b|c)`
        if m:
            labels = [x.strip() for x in m.group(1).split("|") if x.strip()]
        break
    if not labels:
        continue
    body = "\n".join(l for l in arm.splitlines() if not l.strip().startswith("#"))
    for b in re.findall(r"nbin ([a-z][a-z0-9-]*)", body):
        verbs.setdefault(b, []).extend(labels)
# the parser checking ITSELF, with no number typed in: every `nbin <name>` call
# in the file must have been attributed to at least one verb. If a future arm is
# written in a shape this parser cannot read, that shows up here as a parser
# fault instead of silently shrinking the map and passing.
live = "\n".join(l for l in src.splitlines() if not l.strip().startswith("#"))
called = set(re.findall(r"nbin ([a-z][a-z0-9-]*)", live))
unattributed = sorted(called - set(verbs))
rec(bool(called) and not unattributed,
    "every `nbin` call in %s was traced back to a verb (%d binaries)"
    % (os.path.basename(cli), len(verbs)) if called and not unattributed else
    "the parser could not tell which verb reaches: %s — fix the parser, the map "
    "below is short by that many" % (" ".join(unattributed) or "(no nbin call found at all)"))

helptext = open(helpfile, encoding="utf-8").read()
rec(len(helptext) > 200, "the help screen was captured (%d bytes) to check verbs against"
    % len(helptext) if len(helptext) > 200 else
    "the captured help screen is %d bytes — the discoverability check would be vacuous"
    % len(helptext))

# The verbs the help screen actually LISTS, which is not the same as the words
# it contains. Deleting the `lens [--days N]` line still left the word "lens" in
# the examples block and in a sentence, so a plain word search called the verb
# documented when it was not listed anywhere — the check passed on prose.
# A listed verb owns the left column: on an indented line, take everything up to
# the first double space (the signature), split it on `|`, and the verb must be
# the FIRST word of one of those alternatives. "on | off | toggle" lists three;
# "rabadon lens --days 30" in the examples lists none, its first word is rabadon.
#
# T2 narrowed the product surface to five lines. The verbs that came off it were
# NOT deleted — they moved under `rabadon dev <verb>`, which has its own help
# screen. So discoverability is still the law and this check still enforces it;
# what changed is that there are now TWO places a stranger can find a verb, and
# a verb must be listed in one of them. Reading only the main screen would make
# this test forbid the very move T2 exists to make, and reading neither would
# let a verb become unreachable in silence. Both screens, same parser.
def listed_from(text):
    out = set()
    for line in text.splitlines():
        if not line.startswith("  ") or not line.strip():
            continue
        sig = re.split(r"\s{2,}", line.strip())[0]
        for alt in sig.split("|"):
            words = alt.split()
            if words:
                out.add(words[0])
    return out

listed_verbs = listed_from(helptext)

devhelp = ""
try:
    _p = subprocess.run([cli, "dev", "--help"], stdin=subprocess.DEVNULL,
                        capture_output=True, text=True, timeout=30)
    devhelp = (_p.stdout or "") + (_p.stderr or "")
except Exception:
    devhelp = ""
rec(len(devhelp) > 200,
    "`rabadon dev --help` was captured (%d bytes) — the second half of the "
    "discoverability check has something to read" % len(devhelp) if len(devhelp) > 200
    else "`rabadon dev --help` printed %d bytes: the verbs T2 moved off the main "
         "screen have nowhere left to be found" % len(devhelp))
listed_verbs |= listed_from(devhelp)

for name in names:
    got = verbs.get(name, [])
    rec(bool(got), "`rabadon %s` reaches rabadon-%s" % (got[0], name) if got else
        "rabadon-%s ships in every platform package and NO case arm resolves it — "
        "nobody who installed from npm can run it" % name)
    if not got:
        continue
    listed = [v for v in got if v in listed_verbs]
    rec(bool(listed), "the help screen lists `%s` for rabadon-%s" % (listed[0], name)
        if listed else
        "rabadon-%s is dispatched (%s) but no help line starts with any of its "
        "verbs — a stranger cannot find it" % (name, "/".join(got)))

    # the live half: does that verb actually land on THAT binary?
    verb = name if name in got else got[0]
    box = tempfile.mkdtemp(prefix="rabadon-verb.")
    env = dict(os.environ, RABADON_DIR=box, RABADON_NOTIFY="0", HOME=box)
    label = "`rabadon %s --help`" % verb
    try:
        p = subprocess.run([cli, verb, "--help"], stdin=subprocess.DEVNULL,
                           capture_output=True, timeout=15, env=env, cwd=root)
    except subprocess.TimeoutExpired:
        rec(False, label + " HUNG for 15s instead of reaching rabadon-" + name)
        continue
    blob = (p.stdout + p.stderr).decode("utf-8", "replace")
    named = ("rabadon-" + name) in blob
    rec(named, label + " lands on rabadon-%s" % name if named else
        label + " never names rabadon-%s — the verb is wired to something else "
        "(%d bytes back)" % (name, len(blob)))
    clean = "unknown command" not in blob.lower() and p.returncode != 1
    rec(clean, label + " exits %d, no 'unknown command'" % p.returncode if clean else
        label + " exited %d saying: %s" % (p.returncode, blob.strip().splitlines()[0][:100]
                                           if blob.strip() else "(nothing)"))

open(report, "w").write("\n".join(out) + "\n")
PY
while IFS=$'\t' read -r VERDICT MSG; do
  [ -z "${VERDICT:-}" ] && continue
  [ "$VERDICT" = "PASS" ] && pass "$MSG" || fail "$MSG"
done < "$VERB_REPORT"
rm -f "$VERB_REPORT"

# ---- 2. a bare `rabadon` REPORTS, it never changes state ----
# The flag file IS the state, so the test looks at the file rather than
# trusting the message printed about it.
BEFORE=$(ls "$HOME_DIR" 2>/dev/null | sort | tr '\n' ' ')
OUT=$(run 2>&1); RC=$?
AFTER=$(ls "$HOME_DIR" 2>/dev/null | sort | tr '\n' ' ')
[ $RC -eq 0 ] && pass "a bare \`rabadon\` exits 0" || fail "a bare \`rabadon\` exited $RC"
[ "$BEFORE" = "$AFTER" ] && pass "a bare \`rabadon\` did NOT change the enforce flag (watch -> watch)" \
  || fail "a bare \`rabadon\` changed state: [$BEFORE] -> [$AFTER]"
printf '%s' "$OUT" | grep -qE "WATCH|ON|SILENT" && pass "a bare \`rabadon\` prints the current mode" || fail "no mode printed"
printf '%s' "$OUT" | grep -q "read from:" && pass "it names the file the mode was read from" || fail "the source file is not named"

# the same, from the ON side — a report must not flip an armed machine off
run on >/dev/null 2>&1
BEFORE=$(ls "$HOME_DIR" 2>/dev/null | sort | tr '\n' ' ')
OUT=$(run 2>&1)
AFTER=$(ls "$HOME_DIR" 2>/dev/null | sort | tr '\n' ' ')
[ "$BEFORE" = "$AFTER" ] && pass "a bare \`rabadon\` did NOT change the enforce flag (on -> on)" \
  || fail "a bare \`rabadon\` disarmed an armed machine: [$BEFORE] -> [$AFTER]"
printf '%s' "$OUT" | grep -q "ON" && pass "it reports ON while ON" || fail "wrong mode reported"

# ---- 3. changing state still works, explicitly ----
run off >/dev/null 2>&1
[ ! -f "$HOME_DIR/enabled" ] && pass "\`rabadon off\` still turns it off" || fail "\`rabadon off\` did not"
run toggle >/dev/null 2>&1
[ -f "$HOME_DIR/enabled" ] && pass "\`rabadon toggle\` still flips it (the verb was kept, only the DEFAULT changed)" \
  || fail "\`rabadon toggle\` did not turn it on"
run toggle >/dev/null 2>&1
[ ! -f "$HOME_DIR/enabled" ] && pass "\`rabadon toggle\` flips it back" || fail "second toggle did not turn it off"

# ---- 4. the product speaks one language ----
# The trace renderer's interface strings were Turkish end to end. Assert on the
# SOURCE, because these strings only appear once a run exists, and a stranger
# hits them on their first real trace.
# python3, NOT `grep -P`: BSD grep has no -P, so on macOS every `grep -P`
# check exits 2 and the shell reads that as "no match found". A scan that
# silently reports clean on the maintainer's own machine is worse than no scan
# — this exact trap passed a Turkish-character check that had never run.
SCAN=$(python3 - <<'PY'
import re, sys
src = open('native/trace.cpp', encoding='utf-8').read()
lines = src.splitlines()
chars = [(i+1, l.strip()[:90]) for i, l in enumerate(lines) if re.search('[çğıöşüÇĞİÖŞÜ]', l)]
# whole words only: "accepted" contains "cepte", and a substring test would
# fail the suite forever on correct English
words = ['görev','YAKALANAN','YAKALANDI','TAMİR','REDDEDİLEN','adım','yakaladı',
         'kurtarılan','cepte','hakem','ucuzda','tamirden','koşmadı','yükseltilen']
found = sorted({w for w in words if re.search(r'(?<!\w)' + re.escape(w) + r'(?!\w)', src)})
print("CHARS", len(chars))
for n, l in chars[:5]: print("  |", n, l)
print("WORDS", " ".join(found))
PY
)
echo "$SCAN" | grep -q "^CHARS 0$" && pass "trace.cpp contains no Turkish characters" \
  || { fail "trace.cpp still contains Turkish characters"; echo "$SCAN" | sed 's/^/    /' | head -6; }
echo "$SCAN" | grep -q "^WORDS $" && pass "no Turkish interface words remain in trace.cpp" \
  || fail "trace.cpp still carries: $(echo "$SCAN" | sed -n 's/^WORDS //p')"

# The source being clean is not the same as the RENDER being clean, so the
# binary is driven over a synthetic run that exercises the translated lines:
# a caught step, a real repair, a rejected fake fix, a stop, a goal header.
if [ -x ./native/rabadon-trace ]; then
  TDIR=$(mktemp -d /tmp/rabadon-cli-trace.XXXXXX)
  mkdir -p "$TDIR/spool"
  DAY=$(date -u +%Y-%m-%d)
  NOW=$(python3 -c 'import time; print(int(time.time()*1000))')
  {
    echo "{\"v\":1,\"seq\":1,\"ts\":$NOW,\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"RUN_START\",\"goal\":\"ship the stats library\",\"steps\":3}"
    echo "{\"v\":1,\"seq\":2,\"ts\":$((NOW+10)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"validate-input\"}"
    echo "{\"v\":1,\"seq\":3,\"ts\":$((NOW+20)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STEP_OK\",\"step\":\"validate-input\",\"tier\":1}"
    echo "{\"v\":1,\"seq\":4,\"ts\":$((NOW+30)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"ship-statslib\"}"
    echo "{\"v\":1,\"seq\":5,\"ts\":$((NOW+40)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"CHECK_FAIL\",\"step\":\"ship-statslib\",\"why\":\"FAIL testsuite [python3 test_statslib.py]: the suite is RED\"}"
    echo "{\"v\":1,\"seq\":6,\"ts\":$((NOW+50)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"REPAIR_START\",\"step\":\"ship-statslib\",\"attempt\":1}"
    echo "{\"v\":1,\"seq\":7,\"ts\":$((NOW+60)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"REPAIR_OK\",\"step\":\"ship-statslib\",\"attempt\":1,\"tokens\":1200,\"usd_e6\":4000,\"dur_ms\":900}"
    echo "{\"v\":1,\"seq\":8,\"ts\":$((NOW+70)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STEP_OK\",\"step\":\"ship-statslib\",\"tier\":1}"
    echo "{\"v\":1,\"seq\":9,\"ts\":$((NOW+80)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STEP_START\",\"step\":\"publish\"}"
    echo "{\"v\":1,\"seq\":10,\"ts\":$((NOW+90)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"CHECK_FAIL\",\"step\":\"publish\",\"why\":\"FAIL testsuite [python3 test_statslib.py]: the suite is RED\"}"
    echo "{\"v\":1,\"seq\":11,\"ts\":$((NOW+100)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"REPAIR_FAIL\",\"step\":\"publish\",\"attempt\":1}"
    echo "{\"v\":1,\"seq\":12,\"ts\":$((NOW+110)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"STOP\",\"reason\":\"BLOCKED\",\"detail\":\"publish would not pass its contract\"}"
    echo "{\"v\":1,\"seq\":13,\"ts\":$((NOW+120)),\"run\":\"t1\",\"pipe\":\"demo:do\",\"ev\":\"RUN_DONE\",\"verdict\":\"CHECK_FAILED\"}"
  } > "$TDIR/spool/$DAY.jsonl"

  RABADON_DIR="$TDIR" ./native/rabadon-trace > "$TDIR/render.txt" 2>&1 || true
  RENDER_BYTES=$(wc -c < "$TDIR/render.txt" | tr -d ' ')
  if [ "$RENDER_BYTES" -lt 50 ]; then
    fail "trace rendered nothing for the synthetic run (${RENDER_BYTES} bytes) — the language check would be vacuous"
  else
    pass "trace renders the synthetic run (${RENDER_BYTES} bytes of output to scan)"
    python3 -c "
import re, sys
t = open('$TDIR/render.txt', encoding='utf-8', errors='replace').read()
bad = [l for l in t.splitlines() if re.search('[çğıöşüÇĞİÖŞÜ]', l)]
if bad:
    print('    | ' + '\n    | '.join(bad[:5]))
    sys.exit(1)
sys.exit(0)" && pass "the RENDERED trace contains no Turkish characters" \
      || fail "the rendered trace still prints Turkish"
    grep -qi "caught" "$TDIR/render.txt" && pass "the rendered trace speaks English (says 'caught')" \
      || { fail "the render does not contain the English verdict wording"; head -12 "$TDIR/render.txt" | sed 's/^/    | /'; }
  fi
  rm -rf "$TDIR"
fi

# ---- 4c. `trace <run>` — the form the docs teach, on a positional ----
# Section 5 below states the law for FLAGS: a word this binary does not know is
# refused, never swallowed, because a swallow prints REAL output and the filter
# then looks honoured. The law stopped at the leading dash, and the form both
# README and `rabadon help` teach has no dash in it:
#
#     trace [run]         one run step by step: caught, repaired, refused
#
# `rabadon-trace ms92w639-mdr-1` took the id as a candidate path, stat() failed,
# and the resolver fell back to the newest day file: 18837 lines of the entire
# ledger, 3401 runs, exit 0 — and the run that was asked for was in yesterday's
# file, not among them. The exact swallow, one word wider.
#
# Every negative below is paired with a positive, because a "must not dump the
# ledger" assertion on its own is passed by a binary that prints nothing at all,
# and by a binary whose spool the probe forgot to fill. So the first assertion
# is that the un-filtered render DOES carry both runs: that is what makes the
# absence of the second run downstream mean something.
TRACE_REPORT=$(mktemp /tmp/rabadon-trace-arg.XXXXXX)
python3 - "$TRACE_REPORT" <<'PY'
import os, subprocess, sys, tempfile, time

report = sys.argv[1]
BIN = os.path.join(os.getcwd(), "native", "rabadon-trace")
out = []
def rec(good, msg): out.append(("PASS" if good else "FAIL") + "\t" + msg)

if not os.access(BIN, os.X_OK):
    rec(False, "native/rabadon-trace is not built — the positional probe cannot run")
    open(report, "w").write("\n".join(out) + "\n"); sys.exit(0)

def run_rows(run, pipe, ms):
    return [
        '{"v":1,"seq":1,"ts":%d,"run":"%s","pipe":"%s","ev":"RUN_START","goal":"g","steps":1}' % (ms, run, pipe),
        '{"v":1,"seq":2,"ts":%d,"run":"%s","pipe":"%s","ev":"STEP_START","step":"s"}' % (ms + 5, run, pipe),
        '{"v":1,"seq":3,"ts":%d,"run":"%s","pipe":"%s","ev":"STEP_OK","step":"s","tier":1}' % (ms + 10, run, pipe),
        '{"v":1,"seq":4,"ts":%d,"run":"%s","pipe":"%s","ev":"RUN_DONE","verdict":"PASS"}' % (ms + 15, run, pipe),
    ]

def make_box():
    """TWO day files: today's with two runs, and a two-day-old one with a third.

    The old file is what the --run defect was made of. trace read the newest
    day file and nothing else, so a run id sitting one file back answered
    "(no matching run)" — for a run that is demonstrably in the ledger."""
    box = tempfile.mkdtemp(prefix="rabadon-trace-arg.")
    os.makedirs(box + "/spool", exist_ok=True)
    ms = int(time.time() * 1000)
    rows = run_rows("alpha-r1", "probe:alpha", ms) + run_rows("beta-r1", "probe:beta", ms + 100)
    open("%s/spool/%s.jsonl" % (box, time.strftime("%Y-%m-%d")), "w").write("\n".join(rows) + "\n")

    two_days = time.time() - 2 * 86400
    old = "%s/spool/%s.jsonl" % (box, time.strftime("%Y-%m-%d", time.localtime(two_days)))
    open(old, "w").write("\n".join(run_rows("old-r1", "probe:old", int(two_days * 1000))) + "\n")
    os.utime(old, (two_days, two_days))   # the file's own age is the window key
    return box

def trace(box, *args):
    env = dict(os.environ, RABADON_DIR=box, RABADON_NOTIFY="0", HOME=box)
    p = subprocess.run([BIN] + list(args) + ["--no-color"], stdin=subprocess.DEVNULL,
                       capture_output=True, timeout=20, env=env, cwd=box)
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")

# POSITIVE 1 — the surface the swallow fell back to is live and carries BOTH
# runs. Without this the assertions below are satisfied by an empty spool.
box = make_box()
rc, so, se = trace(box)
both = "alpha-r1" in so and "beta-r1" in so
rec(rc == 0 and both,
    "`rabadon-trace` with no argument renders the whole day file (both runs present)"
    if rc == 0 and both else
    "the un-filtered render is not the two-run baseline (rc=%d, alpha=%s beta=%s) — every check below would be vacuous"
    % (rc, "alpha-r1" in so, "beta-r1" in so))

# POSITIVE 2 — the documented form. A bare positional that is not a path is the
# run id, and it renders THAT run.
rc, so, se = trace(box, "alpha-r1")
rec(rc == 0 and "alpha-r1" in so,
    "`rabadon-trace alpha-r1` renders the run named on the command line"
    if rc == 0 and "alpha-r1" in so else
    "`rabadon-trace alpha-r1` did not render that run (rc=%d, %d bytes)" % (rc, len(so)))

# NEGATIVE, paired to POSITIVE 2 — and this is the whole defect: the OTHER run
# must be gone. It was not; the whole ledger came back instead.
rec("beta-r1" not in so,
    "`rabadon-trace alpha-r1` does NOT also print the other runs in the file"
    if "beta-r1" not in so else
    "`rabadon-trace alpha-r1` swallowed the id and dumped the whole ledger (%d bytes)" % len(so))

# NEGATIVE — a word that is neither a path nor a run must not answer with the
# default spool. Paired with POSITIVE 1: that spool demonstrably has content.
rc, so, se = trace(box, "no-such-run-anywhere")
rec("alpha-r1" not in so and "beta-r1" not in so,
    "`rabadon-trace no-such-run-anywhere` does not fall back to the default spool"
    if "alpha-r1" not in so and "beta-r1" not in so else
    "an unknown word still printed the default spool (%d bytes) as if it had been honoured" % len(so))

# ---- the window: a run id addresses the SPOOL, not the newest day file ----
# NEGATIVE baseline first, and it is the load-bearing one: the older run must
# NOT be reachable from the newest day file. That is what makes "found it"
# below mean the window was walked, rather than the fallback having quietly
# printed everything again.
rc, so, se = trace(box)
rec("old-r1" not in so,
    "the newest day file does not contain the older run — the window claim is not free"
    if "old-r1" not in so else
    "the probe's two day files collapsed into one; the window assertions would be vacuous")

for form, args in (("`rabadon-trace old-r1`", ("old-r1",)),
                   ("`rabadon-trace --run old-r1`", ("--run", "old-r1"))):
    rc, so, se = trace(box, *args)
    good = rc == 0 and "old-r1" in so
    rec(good, form + " finds a run written to an earlier day file"
        if good else
        form + " could not reach yesterday's file (rc=%d, %d bytes) — it read one day only" % (rc, len(so)))

# ...and the window is a real bound, not "read everything". One day back cannot
# see a two-day-old file. Without this, "found it" would also be passed by a
# binary that ignores --days and reads the entire spool every time.
rc, so, se = trace(box, "--run", "old-r1", "--days", "1")
rec("old-r1" not in so,
    "`--days 1` does not reach a two-day-old file — the window is a bound, not decoration"
    if "old-r1" not in so else
    "--days was ignored: a two-day-old run answered inside a one-day window")

# ---- asking for a run that is not there is a FAILED question ----
# "(no matching run)" printed on stdout at exit 0. A caller that pipes trace
# into anything read success plus an empty report, which is the same bytes as a
# run that genuinely had nothing in it. Three assertions, and the exit code is
# the only one with teeth: the naming assertion alone is passed by a binary that
# echoes the word into a header, which is precisely how the swallowed flag
# survived its own check (see section 5).
for form, args in (("`rabadon-trace no-such-run-anywhere`", ("no-such-run-anywhere",)),
                   ("`rabadon-trace --run no-such-run-anywhere`", ("--run", "no-such-run-anywhere"))):
    rc, so, se = trace(box, *args)
    rec(rc != 0, form + " exits %d" % rc if rc != 0
        else form + " exited 0 as if an absent run were an answer")
    rec("no-such-run-anywhere" in se,
        form + " names the run it could not find" if "no-such-run-anywhere" in se
        else form + " never says which run it could not find")
    rec(not so.strip(),
        form + " writes nothing to stdout" if not so.strip()
        else form + " still put %d bytes on stdout for a run that does not exist" % len(so))

# and the positive that keeps all six honest: a run that IS there still exits 0
# with a report on stdout. Without it, a binary that failed on everything would
# score a clean sweep above.
rc, so, se = trace(box, "old-r1")
rec(rc == 0 and so.strip(),
    "a run that IS in the window still exits 0 with a report on stdout"
    if rc == 0 and so.strip() else
    "the failure path swallowed the success path too (rc=%d, %d bytes)" % (rc, len(so)))

# ---- a path that does not exist ----
# The same swallow wearing a file extension. `rabadon-trace /no/such/file.jsonl`
# answered rc=0 with 21568 lines of the live spool: stat() failed, the source
# stayed empty, and the fallback printed the default ledger as if the file the
# operator named had been read. Measured against the pre-fix binary just now.
rc, so, se = trace(box, "/no/such/file.jsonl")
rec(rc != 0 and not so.strip(),
    "`rabadon-trace /no/such/file.jsonl` exits %d with an empty stdout" % rc
    if rc != 0 and not so.strip() else
    "a ledger path that does not exist still answered with the default spool (rc=%d, %d bytes)"
    % (rc, len(so)))

# ---- a path AND a run, the two positionals the docs allow ----
# POSITIVE: the pair works, and it is the only reading that makes both words
# mean something.
day = os.path.join(box, "spool")
rc, so, se = trace(box, day, "alpha-r1")
good = rc == 0 and "alpha-r1" in so and "beta-r1" not in so
rec(good, "`rabadon-trace <dir> alpha-r1` reads that ledger and renders that run"
    if good else
    "a directory plus a run id did not resolve to one run in that ledger (rc=%d, %d bytes)"
    % (rc, len(so)))

# NEGATIVE: a THIRD word has no meaning left, and guessing one is how this whole
# section started. It ends the run and says which word.
rc, so, se = trace(box, day, "alpha-r1", "beta-r1")
good = rc != 0 and "beta-r1" in se and not so.strip()
rec(good, "a third positional is refused (exit %d) and named back" % rc
    if good else
    "a third positional was swallowed (rc=%d, %d bytes on stdout)" % (rc, len(so)))

open(report, "w").write("\n".join(out) + "\n")
PY
while IFS=$'\t' read -r VERDICT MSG; do
  [ -z "${VERDICT:-}" ] && continue
  [ "$VERDICT" = "PASS" ] && pass "$MSG" || fail "$MSG"
done < "$TRACE_REPORT"
rm -f "$TRACE_REPORT"

# ---- 5. every native binary answers --help ----
# Same sixty seconds, one layer down. A stranger who gets past `rabadon --help`
# reaches the binaries, and there the first word they type used to do one of
# three things, none of which is a help screen:
#   - HANG. `rabadon-do --help` took the flag as the task and opened a model
#     call; `rabadon-serve -h` started the HTTP server.
#   - PRINT THE REAL LEDGER. `rabadon-trace --help` swallowed the flag and
#     dumped 31798 bytes of the live spool, not even valid UTF-8.
#   - REFUSE. budget/loop/verify/export/sandbox/repair/truth exited 1, 2 or 3.
#
# Three assertions per binary, and the third is the one that has teeth: the
# output must NAME the binary. Without it "exit 0 and under 10KB" is passed by
# a binary that prints nothing at all — which is what `rabadon-gate --help` and
# `rabadon-drift --help` already did, 0 bytes, exit 0, looking healthy.
#
# The probe is python3, NOT a bash loop: `do` and `serve` used to hang and bash
# has no portable timeout on macOS (no `timeout`, no `gtimeout` — checked).
#
# The list is DISCOVERED, never written down. A hand-kept list is a gate the
# seventeenth binary walks around: whoever adds it has no reason to think of
# this file, and the suite stays green while the new command answers --help with
# the ledger. So the probe globs native/rabadon-* and refuses to run on zero.

HELP_REPORT=$(mktemp /tmp/rabadon-help-report.XXXXXX)
python3 - "$HELP_REPORT" <<'PY'
import glob, os, subprocess, sys, tempfile, time

report = sys.argv[1]
root = os.getcwd()
names = sorted(os.path.basename(b)[len("rabadon-"):]
               for b in glob.glob(os.path.join(root, "native", "rabadon-*"))
               if not b.endswith(".sh") and os.access(b, os.X_OK))
MAX = 10 * 1024
BOGUS = "--rabadon-no-such-flag"
# the two hook binaries: exit 0 is the only safe refusal (see below)
HOOKS = {"gate", "drift"}
out = []
def rec(good, msg): out.append(("PASS" if good else "FAIL") + "\t" + msg)

# a glob that matched nothing would make every assertion below vacuous, so the
# count itself is asserted. The floor is deliberately a floor and not today's
# exact count: this line said "sixteen" for the two releases after the Makefile
# started building seventeen, and a number typed into a comment is the thing
# this whole file exists to stop trusting. The build is the source; the assertion
# only refuses a glob that came back empty or half-built.
rec(len(names) >= 16, "the help probe found %d native binaries to interrogate" % len(names)
    if len(names) >= 16 else
    "the help probe found only %d binaries (%s) — build first, this run proves nothing"
    % (len(names), " ".join(names)))

# A box with a REAL (tiny) ledger in it. Without data the probe would be
# toothless: a binary that swallows --help and prints its report would find an
# empty spool, print "nothing recorded", and look indistinguishable from one
# that printed help. With a ledger present, swallowing the flag produces a
# ledger dump — which is exactly the bug, at 1/1000 the size.
def make_box():
    box = tempfile.mkdtemp(prefix="rabadon-help.")
    os.makedirs(box + "/spool", exist_ok=True)
    ms = int(time.time() * 1000)
    day = time.strftime("%Y-%m-%d")
    rows = [
        '{"v":1,"seq":1,"ts":%d,"run":"h1","pipe":"probe:do","ev":"RUN_START","goal":"probe ledger","steps":1}' % ms,
        '{"v":1,"seq":2,"ts":%d,"run":"h1","pipe":"probe:do","ev":"STEP_START","step":"probe-step"}' % (ms + 5),
        '{"v":1,"seq":3,"ts":%d,"run":"h1","pipe":"probe:do","ev":"STEP_OK","step":"probe-step","tier":1,"tokens":10,"usd_e6":20,"dur_ms":30}' % (ms + 10),
        '{"v":1,"seq":4,"ts":%d,"run":"h1","pipe":"probe:do","ev":"RUN_DONE","verdict":"OK"}' % (ms + 15),
    ]
    open("%s/spool/%s.jsonl" % (box, day), "w").write("\n".join(rows) + "\n")
    return box

for name in names:
    path = os.path.join(root, "native", "rabadon-" + name)
    if not os.path.exists(path):
        rec(False, "rabadon-%s is not built — the help probe cannot run" % name)
        continue
    for flag in ("--help", "-h"):
        box = make_box()
        env = dict(os.environ, RABADON_DIR=box, RABADON_NOTIFY="0", HOME=box)
        label = "`rabadon-%s %s`" % (name, flag)
        try:
            p = subprocess.run([path, flag], stdin=subprocess.DEVNULL,
                               capture_output=True, timeout=10, env=env, cwd=box)
        except subprocess.TimeoutExpired:
            rec(False, label + " HUNG for 10s instead of printing help")
            continue
        blob = p.stdout + p.stderr
        rec(p.returncode == 0, label + (" exits 0" if p.returncode == 0
                                        else " exited %d" % p.returncode))
        # positive: the screen must name the thing it describes. this is what
        # keeps the size assertion below from being satisfied by silence.
        named = ("rabadon-" + name).encode() in blob
        rec(named, label + (" names itself" if named
                            else " never says 'rabadon-%s' (%d bytes)" % (name, len(blob))))
        rec(len(blob) <= MAX,
            label + (" stays under 10KB (%d bytes)" % len(blob) if len(blob) <= MAX
                     else " printed %d bytes — that is the ledger, not a help screen" % len(blob)))

    # ---- and a flag nobody has ever defined ----
    # The dangerous half is not the refusal, it is the SWALLOW: an unknown flag
    # taken as a path or ignored, after which the binary prints real output that
    # looks like the flag was honoured. `rabadon-lens --help` printed a live
    # report headed "source: --help"; `rabadon-net -h` went looking for a repo
    # named "-h"; `rabadon-stats --projekt foo` would have printed the whole
    # machine under a heading read as one project's.
    #
    # Two assertions, and NEITHER is sufficient alone — measured, not assumed.
    # Rebuilding lens from the pre-fix source and running this: it PASSED "names
    # the offending word back", because it echoed the flag as its own header,
    # `source: --rabadon-no-such-flag`. The naming assertion is what stops
    # silence from passing; the stdout assertion is what catches the swallow.
    # Together they caught it (4 FAILs); either one alone would have let it by.
    box = make_box()
    env = dict(os.environ, RABADON_DIR=box, RABADON_NOTIFY="0", HOME=box)
    label = "`rabadon-%s %s`" % (name, BOGUS)
    try:
        p = subprocess.run([path, BOGUS], stdin=subprocess.DEVNULL,
                           capture_output=True, timeout=10, env=env, cwd=box)
    except subprocess.TimeoutExpired:
        rec(False, label + " HUNG for 10s on an undefined flag")
        continue
    named = BOGUS.encode() in (p.stdout + p.stderr)
    rec(named, label + (" names the offending word back" if named
                        else " never says which word it did not understand"))
    rec(not p.stdout,
        label + (" printed no report on stdout" if not p.stdout
                 else " swallowed the flag and printed %d bytes of real output" % len(p.stdout)))
    if name in HOOKS:
        # gate is a PreToolUse hook and drift a Stop hook: Claude Code reads a
        # non-zero exit as BLOCK. If these refused a typo, one bad character in
        # a settings.json hook line would wedge every tool call on the machine.
        rec(p.returncode == 0,
            label + (" fails OPEN, exit 0 — correct, a hook's non-zero exit means BLOCK"
                     if p.returncode == 0 else " exited %d; a hook must fail OPEN" % p.returncode))
    else:
        rec(p.returncode != 0,
            label + (" exits %d" % p.returncode if p.returncode != 0
                     else " exited 0 as if an undefined flag were fine"))

open(report, "w").write("\n".join(out) + "\n")
PY
while IFS=$'\t' read -r VERDICT MSG; do
  [ -z "${VERDICT:-}" ] && continue
  [ "$VERDICT" = "PASS" ] && pass "$MSG" || fail "$MSG"
done < "$HELP_REPORT"
rm -f "$HELP_REPORT"

# ---- 6. a MISTYPED verb, which is how a stranger meets the command list ----
# `rabadon usag` used to fall through to bin/rabadon.mjs and answer with a verb
# list that had been typed in by hand beside the dispatcher instead of read out
# of it. It named 14 verbs. Five of them — guard, fleet, spin, pack, statusline —
# are in neither README.md nor docs/, and one of those five, `spin`, starts
# headless claude sessions in the reader's repo. It omitted 13 of the 17 commands
# docs/commands.md documents, among them usage, lens, report, trace, audit,
# replay, drill and export: the entire "seeing what happened" half of the
# product, missing from the one screen a newcomer reaches by accident. The same
# binary's `rabadon help` printed the correct set the whole time.
#
# This is the defect README already claims is closed for flags ("refuses a flag
# it does not know rather than swallowing it") and that section 1b closes for the
# shipped binaries. The rule is the same one: a list that is typed twice goes
# stale on one side and no test can see it. So the expectation below is PARSED
# out of the case arms, never written here — if this file named the verbs, it
# would be the third copy and the next rename would leave it behind too.
VERB_MSG_REPORT=$(mktemp /tmp/rabadon-unknown-verb.XXXXXX)
python3 native/unknown_verb_probe.py "$CLI" "$VERB_MSG_REPORT"
while IFS=$'\t' read -r VERDICT MSG; do
  [ -z "${VERDICT:-}" ] && continue
  [ "$VERDICT" = "PASS" ] && pass "$MSG" || fail "$MSG"
done < "$VERB_MSG_REPORT"
rm -f "$VERB_MSG_REPORT"

echo "cli: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
