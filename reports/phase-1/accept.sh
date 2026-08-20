#!/usr/bin/env bash
# reports/phase-1/accept.sh — the gate for phase 1, written before phase 1 runs,
# by an agent that will not implement phase 1 (AGENTS-PROTOCOL.md, Kapı 1).
#
# ---------------------------------------------------------------------------
# WHAT PHASE 1 OWES
# ---------------------------------------------------------------------------
#   The ledger records that a repair was ATTEMPTED far more often than it
#   records how the attempt ENDED. Measured on this machine, on the real spool,
#   before phase 1 started (~/.rabadon/spool, 26 day files, 2026-07-26 →
#   2026-08-20):
#
#       REPAIR_START ................ 435
#       terminal events for them .... 168   (REPAIR_OK 113 + REPAIR_FAIL 55)
#       REPAIR_START with NOTHING ... 267
#
#   Those 267 are not "probably failures". For 267 of them there is not one
#   further event in the whole run after the REPAIR_START — no terminal, no
#   STEP_OK, no RUN_DONE, nothing. The ledger simply stops. The emitter that
#   opens the repair (native/gate.cpp, the repair_kind="diagnosis" path around
#   line 2353) has code paths that never close it.
#
#   Phase 1 owes two separate things, and they must not be confused:
#     (a) FORWARD: from now on, every REPAIR_START gets a closing event that
#         carries an outcome, and — when the repair did not hold — a CLASS from
#         the protocol's closed list:
#             REPAIR_FAIL / FLAKY / test-tamper / harness-tamper /
#             proposer-empty / timeout
#     (b) BACKWARD: the existing spool is scanned and a distribution table is
#         produced under reports/phase-1/ — and the events that CANNOT be
#         classified are counted and reported as unclassified, not guessed.
#
#   The protocol's stop condition is one sentence long and it is the whole
#   point of this phase: "eski olaylar sınıflandırılamıyorsa dur — geriye
#   dönük uydurma yok." Retroactive invention is forbidden.
#
# ---------------------------------------------------------------------------
# WHAT THIS SCRIPT REFUSES TO ASSUME
# ---------------------------------------------------------------------------
#   1. It refuses to believe a table. A table is a claim. Every number in
#      reports/phase-1/distribution.tsv is recomputed here, from the raw
#      ledger, by this script, in this run. If the two disagree, the table
#      loses.
#
#   2. It refuses to reward a zero. A gate that goes green when "unclassified:
#      0" is a gate that pays for lying, because the cheapest way to reach zero
#      is to stamp REPAIR_FAIL on 267 events nobody can account for. This
#      script computes the unclassifiable count ITSELF and demands the reported
#      number equal it. Reporting fewer unclassified than the ledger supports
#      is the failure this gate exists to catch.
#
#   3. It refuses to accept a classification without a pointer to evidence.
#      Every classified row must name the exact ledger line (file + line
#      number) that proves it. This script re-opens that file, reads that line,
#      parses it, and checks that it really is a terminal event for that
#      repair: same run, same attempt, same day file, later in the file, later
#      in time. No line may be cited twice.
#
#   4. It refuses evidence that phase 1 wrote itself. Every day file's byte
#      length and the SHA-256 of that prefix are PINNED below, captured before
#      phase 1 began. Evidence for a historical REPAIR_START must lie inside
#      the pinned prefix. Appending a fresh REPAIR_FAIL today "for" a July run
#      is exactly the invention the protocol forbids, and it is inadmissible
#      here. The ledger is append-only: the pinned prefix must still hash the
#      same, or this gate fails and says the history was rewritten.
#
#   5. It refuses "the emitter is fixed, trust me". A code diff is not a
#      behaviour. Phase 1 must leave at least one REPAIR_START in the LIVE part
#      of the ledger (past the pin) and every live REPAIR_START older than five
#      minutes must be closed, with an explicit outcome field and, when not
#      held, a class. That is checked against the ledger, not against a report.
#
#   6. It refuses to demand `rabadon audit` exit 0, and says why out loud.
#      Measured before phase 1: `rabadon audit` on the real spool exits 2
#      (PARTIAL) — 13 files predate the hash chain or were written outside it.
#      That is pre-existing and is NOT phase 1's to fix. Demanding exit 0 here
#      would hand the implementing agent one cheap way out: delete the old day
#      files. So "green" is read the only honest way available: no
#      TAMPER-EVIDENT BREAK, no file newly unverifiable, and no loss of chained
#      history. If the ledger becomes MORE verifiable, that passes too.
#
# ---------------------------------------------------------------------------
# THE CONTRACT PHASE 1 MUST SATISFY (this is the spec; build to it)
# ---------------------------------------------------------------------------
#   A. reports/phase-1/classified.tsv — one row per historical REPAIR_START
#      (exactly the 435 inside the pinned prefix), TAB-separated, 8 columns.
#      A leading header line and lines starting with '#' are ignored.
#
#        start_file  start_line  run  attempt  outcome  class  ev_file  ev_line
#
#        outcome  : held | not-held | unclassified
#        class    : '-' when outcome is held or unclassified; otherwise one of
#                   REPAIR_FAIL FLAKY test-tamper harness-tamper
#                   proposer-empty timeout
#        ev_file  : day-file name of the closing event, or '-' if unclassified
#        ev_line  : 1-based line number in that file, or '-'
#
#   B. reports/phase-1/distribution.tsv — the table the protocol asks for.
#      TAB-separated `key<TAB>count`, header/'#' lines ignored. Exactly these
#      eight keys, no more, no fewer:
#
#        held  REPAIR_FAIL  FLAKY  test-tamper  harness-tamper
#        proposer-empty  timeout  unclassified
#
#      Every count must equal this script's own recount of classified.tsv.
#
#   C. The class a row claims must be the class the cited evidence supports.
#      This script derives the class independently, from the evidence line's
#      own `ev` and `why`, with first-match-wins markers:
#
#        ev = REPAIR_OK                      -> held, class '-'
#        ev = REPAIR_FLAKY                   -> not-held, FLAKY
#        why contains "test-tamper"          -> test-tamper
#        why contains "harness-tamper"       -> harness-tamper
#        why contains "timed out"/"timeout"  -> timeout
#        why contains "flaky"                -> FLAKY
#        why contains "proposer"             -> proposer-empty
#        otherwise (ev = REPAIR_FAIL/CLOSE)  -> REPAIR_FAIL
#
#      The order matters: "proposer timed out" is a timeout, not an empty
#      proposer. Bucketing a specific reason into generic REPAIR_FAIL fails
#      this gate — the count would be right and the reason wrong, which is the
#      thing Kapı 2 was written against.
#
#      If phase 1 believes one of these mappings is genuinely wrong, that is
#      not a thing to work around: this file is sealed against the implementing
#      agent. Write the disagreement and the evidence in reports/phase-1/
#      discards.txt, stop, and let a human amend the gate in its own commit.
#
#   D. Forward closure, checked in the live ledger (past the pin):
#      at least one REPAIR_START, and every live REPAIR_START older than 300 s
#      closed by an event whose `ev` starts with REPAIR_ and which carries
#      "outcome":"held" or "outcome":"not-held", plus a "class" from the six
#      when not held.
#
# ---------------------------------------------------------------------------
# EXIT CODES
# ---------------------------------------------------------------------------
#   0  every clause above held
#   1  a clause failed — the reason is printed, nothing is inferred
#   2  cannot run at all (no python3, no spool, audit will not build, the
#      pinned ledger is gone). NOT a pass, NOT a silent skip: "I can't check
#      this" is a designed state, per CLAUDE.md.
#
# USAGE
#   bash reports/phase-1/accept.sh [repo-root]

set -u

REPO="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO" || { echo "accept: cannot cd into $REPO"; exit 2; }

fail()  { echo "FAIL: $*"; exit 1; }
cannot(){ echo "CANNOT RUN: $*"; exit 2; }
ok()    { echo "  ok  $*"; }

echo "phase 1 acceptance — every repair start must close with a traceable outcome"
echo "  repo: $REPO"

command -v python3 >/dev/null 2>&1 || cannot "python3 is absent; this gate parses JSONL"

RDIR="${RABADON_DIR:-$HOME/.rabadon}"
SPOOL="$RDIR/spool"
[ -d "$SPOOL" ] || cannot "no spool at $SPOOL — there is no ledger to measure"
ok "spool: $SPOOL"

# --- clause: rabadon audit must be runnable and must not report a BREAK -------
if [ ! -x "$REPO/native/rabadon-audit" ]; then
  echo "  building native/rabadon-audit (absent)"
  make -C "$REPO" native/rabadon-audit >/dev/null 2>&1 \
    || cannot "native/rabadon-audit is absent and 'make native/rabadon-audit' failed"
fi
AUDIT_OUT=$(mktemp "${TMPDIR:-/tmp}/rabadon-phase1-audit.XXXXXX") || cannot "mktemp failed"
trap 'rm -f "$AUDIT_OUT"' EXIT
"$REPO/native/rabadon-audit" >"$AUDIT_OUT" 2>&1
AUDIT_RC=$?
AUDIT_VERDICT=$(grep -E '^\s*verdict:' "$AUDIT_OUT" | head -1)
echo "  rabadon audit exit=$AUDIT_RC"
echo "  $AUDIT_VERDICT"

if [ "$AUDIT_RC" -eq 1 ] || grep -q 'TAMPER-EVIDENT BREAK' "$AUDIT_OUT" || grep -q 'chain BROKEN' "$AUDIT_OUT"; then
  echo "--- rabadon audit ---"; cat "$AUDIT_OUT"; echo "---------------------"
  fail "rabadon audit reports a tamper-evident break. the ledger was edited, truncated, reordered or deleted after emit — no number computed from it means anything."
fi
if [ "$AUDIT_RC" -ne 0 ] && [ "$AUDIT_RC" -ne 2 ]; then
  echo "--- rabadon audit ---"; cat "$AUDIT_OUT"; echo "---------------------"
  cannot "rabadon audit exited $AUDIT_RC — unexpected; refusing to interpret it"
fi

# baseline measured before phase 1: 13 UNVERIFIABLE files, 89203 chained events.
# audit prints two different words for the same verdict — "UNVERIFIABLE" for a
# file with no chain at all, "UNPROVEN" for a chained file that also carries
# unchained lines — so the count is taken from the verdict line, which totals
# both, not from a grep that would silently see only half of them.
UNVERIF=$(sed -n 's/.*, \([0-9]*\) file(s) UNVERIFIABLE holding.*/\1/p' "$AUDIT_OUT" | head -1)
[ -n "$UNVERIF" ] || UNVERIF=0
CHAINED=$(sed -n 's/.*verdict: PARTIAL — \([0-9]*\) chained.*/\1/p;s/.*verdict: INTACT — \([0-9]*\) chained.*/\1/p' "$AUDIT_OUT" | head -1)
[ -n "$CHAINED" ] || fail "could not read the chained-event count out of rabadon audit's verdict line"
[ "$UNVERIF" -le 13 ] || fail "rabadon audit now calls $UNVERIF file(s) UNVERIFIABLE; before phase 1 it was 13. phase 1 wrote events outside the hash chain."
[ "$CHAINED" -ge 89203 ] || fail "rabadon audit verified $CHAINED chained event(s); before phase 1 it was 89203. chained history was lost."
ok "audit: no break · unverifiable $UNVERIF/13 · chained $CHAINED >= 89203"

# --- everything else is ledger arithmetic; bash is the wrong tool for it ------
PIN_FILE=$(mktemp "${TMPDIR:-/tmp}/rabadon-phase1-pin.XXXXXX") || cannot "mktemp failed"
trap 'rm -f "$AUDIT_OUT" "$PIN_FILE"' EXIT

# PINNED LEDGER PREFIXES — captured 2026-08-20, before phase 1 started.
# name <SP> byte-length-of-prefix <SP> sha256-of-that-prefix
# Each length is newline-aligned, so the prefix is a whole number of records.
cat >"$PIN_FILE" <<'PINS'
2026-07-26.jsonl 63115 741c95c04dbf8412d3c716658b4a21d1482c91d779f0a82a5f8161d387c14bad
2026-07-27.jsonl 1710291 c148907f61b782344ea2df03e53cc79dfa1f29e7cd2d895f3f6e744d14e60ef8
2026-07-28.jsonl 752724 13967420686686ed232c64150face060a0d6eeb4f98d3cea36510f6806a342d7
2026-07-29.jsonl 1576878 d66f6b9b09322240df5888b532c19cbb5f5b8e88415650d6a0c160f25b2cec0d
2026-07-30.jsonl 773292 6dff0b2754f8cf737d5dc105684e8bfaf178c4db4efb7b3cf406749068f52150
2026-07-31.jsonl 3105666 8aca6d9594f3c75bec2bc9c3004f5f00036cdb5dc20e5074fd063d339bcf1143
2026-08-01.jsonl 9128516 3f4aec11b07fc1637385b6f68d00da8c4b7385968306adf031fd09db2fa3f7df
2026-08-01.unchained.jsonl 6303 bd4e45eef4072ae617ddc4985f6d4098425e5db3325a9b86e99a7afa654f53f9
2026-08-02.jsonl 2629743 9a66da6158446962293e9c3bc5d60fd0359ed9dc9bf8b5217f78d0c35aa6f27e
2026-08-03.jsonl 689013 4d611b4d41b53ac78a28831abf5fe029c56416374b88da0c921427d9977d46c2
2026-08-04.jsonl 1631054 f35850f94049dd29336713d60aebf3807525b1b866865c7d1464a516ea43e7ec
2026-08-05.jsonl 610528 a6fefd18a924d5ca64bc0fc5dd549129baf0588f80b6370354ac04625c26ec28
2026-08-08.jsonl 251666 d31009514a1021dfb989fcb8f1501a53f3c48e68f2c25d29ee4e57386873a469
2026-08-09.jsonl 475113 ef210a9813ff2706e3f7dd32d9e570e5ef8ca52fdead71ea9f1c583ef392c50a
2026-08-10.jsonl 365604 c85c9682047ed6e64d0a1e43d096b553cbd376ab2a90e1b9a7740d366d4b648a
2026-08-11.jsonl 167912 91bccf17dcb636893f9abb9e1de74bae1591f7e7386c7086d4ffab6bebc951c2
2026-08-12.jsonl 168003 3fad70fc0ff74a2db394b74678cc578729604e35ccfcd25e870f090c452d68cd
2026-08-13.jsonl 324502 b3381e9bc86423968dc33d0de4e219bc537661ca9c4ea835d3f8943a115bbf10
2026-08-14.jsonl 1196887 357562680eab946acfe66ae93b3864247714374bbe998d9b6eca85850f67eed9
2026-08-15.jsonl 367332 740ebe26b4b6781d31d1b60137689bef7bf96905c413fec469daa3c64627963c
2026-08-16.jsonl 6398949 e21c20d52a1570050bec873417666b31b0a5c8f01d0143109b6bad2c48444072
2026-08-17.jsonl 5760761 9707de08442cb18a9cf07d40ac2e9906a971c52a6aca875992cdfb06c14f9850
2026-08-17.unchained.jsonl 9928 c22bca046338018d9ee42bb4e806485c7c66e492c45d37939efd3bd00daa592e
2026-08-18.jsonl 1808219 a567d903017abe04069580bd1816b59b7995203a002a7c3a69cb811cae769dcb
2026-08-19.jsonl 3456889 c7fb41e364354aae8f8a01698aee2ccccc865372f5f53b3944b29f621503edc6
2026-08-20.jsonl 225348 a14c72f2e36c9bccf5deeed98a7b248951257c6bd0a2f4f68d8f1d9ebc386642
PINS

SPOOL="$SPOOL" REPO="$REPO" PIN_FILE="$PIN_FILE" python3 - <<'PY'
import hashlib, json, os, sys, time

SPOOL   = os.environ["SPOOL"]
REPO    = os.environ["REPO"]
PIN     = os.environ["PIN_FILE"]

# ground truth measured before phase 1, over exactly the pinned prefixes.
EXPECT_STARTS       = 435
EXPECT_TERMINALS    = 168
EXPECT_UNCLASSIFIED = 267

TERMINAL_EVS = {"REPAIR_OK", "REPAIR_FAIL", "REPAIR_FLAKY", "REPAIR_CLOSE"}
CLASSES = ["REPAIR_FAIL", "FLAKY", "test-tamper", "harness-tamper",
           "proposer-empty", "timeout"]
DIST_KEYS = ["held"] + CLASSES + ["unclassified"]

def fail(msg):
    print("FAIL: " + msg)
    sys.exit(1)

def cannot(msg):
    print("CANNOT RUN: " + msg)
    sys.exit(2)

def ok(msg):
    print("  ok  " + msg)

# ---------------------------------------------------------------- clause: pins
pins = []
for ln in open(PIN):
    ln = ln.strip()
    if not ln:
        continue
    name, size, sha = ln.split()
    pins.append((name, int(size), sha))

prefixes = {}
for name, size, sha in pins:
    p = os.path.join(SPOOL, name)
    if not os.path.exists(p):
        cannot("pinned ledger file %s is GONE. the 22-day spool this phase is "
               "measured against no longer exists on this machine; nothing can "
               "be verified." % name)
    actual = os.path.getsize(p)
    if actual < size:
        fail("%s shrank: %d bytes now, %d bytes when this gate was sealed. the "
             "ledger is append-only; something removed history." % (name, actual, size))
    with open(p, "rb") as fh:
        blob = fh.read(size)
    got = hashlib.sha256(blob).hexdigest()
    if got != sha:
        fail("%s no longer hashes to its sealed prefix (%s… expected %s…). the "
             "first %d bytes were REWRITTEN, not appended to. every distribution "
             "computed from this file is void."
             % (name, got[:12], sha[:12], size))
    prefixes[name] = blob
ok("ledger append-only: %d pinned day file(s), every sealed prefix still hashes the same" % len(pins))

# ------------------------------------------------- independent ledger recount
def records(blob, fname):
    """yield (line_no, dict) for complete lines in blob."""
    for i, raw in enumerate(blob.split(b"\n"), 1):
        if not raw.strip():
            continue
        try:
            o = json.loads(raw.decode("utf-8", "replace"))
        except Exception:
            continue
        if isinstance(o, dict):
            yield i, o, raw.decode("utf-8", "replace")

hist_starts = {}      # (file, line) -> record
hist_terms  = []      # (file, line, record, raw)
for name in sorted(prefixes):
    for i, o, raw in records(prefixes[name], name):
        ev = o.get("ev")
        if ev == "REPAIR_START":
            hist_starts[(name, i)] = o
        elif ev in TERMINAL_EVS:
            hist_terms.append((name, i, o, raw))

# one-to-one match: each terminal consumes the nearest preceding unmatched
# REPAIR_START in the same day file with the same run and attempt.
consumed = set()
pairing = {}          # (start_file, start_line) -> (ev_file, ev_line)
for tn, ti, to, _raw in hist_terms:
    key = (to.get("run"), to.get("attempt"))
    cands = [(sn, si) for (sn, si), so in hist_starts.items()
             if sn == tn and si < ti and (so.get("run"), so.get("attempt")) == key
             and (sn, si) not in consumed]
    if cands:
        pick = max(cands)
        consumed.add(pick)
        pairing[pick] = (tn, ti)

n_starts  = len(hist_starts)
n_matched = len(pairing)
n_unclass = n_starts - n_matched

print("  recount over the sealed prefixes (this script, this run):")
print("    REPAIR_START ................ %d" % n_starts)
print("    closed by a terminal event .. %d" % n_matched)
print("    UNCLASSIFIABLE .............. %d" % n_unclass)

if (n_starts, len(hist_terms), n_unclass) != (EXPECT_STARTS, EXPECT_TERMINALS, EXPECT_UNCLASSIFIED):
    fail("the sealed prefixes hash correctly but no longer yield the numbers "
         "measured when this gate was written (%d/%d/%d, got %d/%d/%d). this "
         "gate is out of date or its parser changed — a human must reconcile it "
         "before any phase-1 number is believed."
         % (EXPECT_STARTS, EXPECT_TERMINALS, EXPECT_UNCLASSIFIED,
            n_starts, len(hist_terms), n_unclass))
ok("recount agrees with the sealed measurement: %d starts, %d closed, %d unclassifiable"
   % (n_starts, n_matched, n_unclass))

# --------------------------------------------------------- clause: the reports
P1 = os.path.join(REPO, "reports", "phase-1")
CLS = os.path.join(P1, "classified.tsv")
DST = os.path.join(P1, "distribution.tsv")
for p in (CLS, DST):
    if not os.path.isfile(p):
        fail("%s does not exist. phase 1 has not produced the distribution the "
             "protocol asks for (Kabul: 'dağılım tablosu reports/phase-1/ altında')."
             % os.path.relpath(p, REPO))
ok("reports present: classified.tsv, distribution.tsv")

def tsv(path, ncols):
    rows = []
    for n, ln in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        ln = ln.rstrip("\n")
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        parts = ln.split("\t")
        if n == 1 and parts and parts[0].strip() in ("start_file", "key", "class"):
            continue                       # header
        if len(parts) != ncols:
            fail("%s line %d has %d TAB-separated field(s), the contract says %d: %r"
                 % (os.path.basename(path), n, len(parts), ncols, ln[:160]))
        rows.append((n, [p.strip() for p in parts]))
    return rows

# ------------------------------------------- clause: classified.tsv is a bijection
rows = tsv(CLS, 8)
seen = {}
for n, r in rows:
    try:
        key = (r[0], int(r[1]))
    except ValueError:
        fail("classified.tsv line %d: start_line %r is not a number" % (n, r[1]))
    if key in seen:
        fail("classified.tsv line %d repeats %s:%s (already on line %d). one row "
             "per REPAIR_START, or the counts are inflated by duplication."
             % (n, key[0], key[1], seen[key]))
    seen[key] = n

missing = set(hist_starts) - set(seen)
extra   = set(seen) - set(hist_starts)
if missing:
    s = sorted(missing)[:5]
    fail("classified.tsv omits %d REPAIR_START(s) that are in the sealed ledger, "
         "e.g. %s. an event left out of the table is an event quietly forgiven."
         % (len(missing), ", ".join("%s:%d" % k for k in s)))
if extra:
    s = sorted(extra)[:5]
    fail("classified.tsv invents %d row(s) that point at no REPAIR_START in the "
         "sealed ledger, e.g. %s." % (len(extra), ", ".join("%s:%d" % k for k in s)))
ok("classified.tsv covers exactly the %d sealed REPAIR_START events, no dupes" % n_starts)

# --------------------------------- clause: every classification cites real evidence
def marker_class(ev, why):
    if ev == "REPAIR_OK":
        return "held", "-"
    if ev == "REPAIR_FLAKY":
        return "not-held", "FLAKY"
    w = (why or "").lower()
    for needle, cls in (("test-tamper", "test-tamper"),
                        ("harness-tamper", "harness-tamper"),
                        ("timed out", "timeout"),
                        ("timeout", "timeout"),
                        ("flaky", "FLAKY"),
                        ("proposer", "proposer-empty")):
        if needle in w:
            return "not-held", cls
    return "not-held", "REPAIR_FAIL"

term_index = {(f, l): (o, raw) for f, l, o, raw in hist_terms}
cited = {}
counts = dict((k, 0) for k in DIST_KEYS)

for n, r in rows:
    sf, sl, run, attempt, outcome, cls, ef, el = r
    sl = int(sl)
    start = hist_starts[(sf, sl)]

    if str(start.get("run")) != run:
        fail("classified.tsv line %d: run %r, but %s:%d says run %r"
             % (n, run, sf, sl, start.get("run")))
    if str(start.get("attempt")) != attempt:
        fail("classified.tsv line %d: attempt %r, but %s:%d says attempt %r"
             % (n, attempt, sf, sl, start.get("attempt")))

    if outcome == "unclassified":
        if cls != "-" or ef != "-" or el != "-":
            fail("classified.tsv line %d: outcome 'unclassified' but it still "
                 "carries a class/evidence (%r %r %r). unclassified means the "
                 "ledger does not say — say that, do not decorate it."
                 % (n, cls, ef, el))
        counts["unclassified"] += 1
        continue

    if outcome not in ("held", "not-held"):
        fail("classified.tsv line %d: outcome %r is not one of held / not-held / "
             "unclassified" % (n, outcome))

    # evidence must exist, inside the sealed prefix, and belong to this repair.
    if ef not in prefixes:
        fail("classified.tsv line %d cites %s:%s as evidence. that file is not a "
             "sealed ledger prefix — evidence written after this gate was sealed "
             "is not evidence about a historical repair, it is invention."
             % (n, ef, el))
    try:
        el_i = int(el)
    except ValueError:
        fail("classified.tsv line %d: ev_line %r is not a number" % (n, el))
    if (ef, el_i) not in term_index:
        fail("classified.tsv line %d cites %s:%d, which is not a terminal repair "
             "event in the sealed ledger. the classification rests on nothing."
             % (n, ef, el_i))
    if (ef, el_i) in cited:
        fail("classified.tsv line %d cites %s:%d, already cited by line %d. one "
             "closing event cannot close two repairs — that is how 267 unknowns "
             "get laundered into a full table."
             % (n, ef, el_i, cited[(ef, el_i)]))
    cited[(ef, el_i)] = n

    evrec, evraw = term_index[(ef, el_i)]
    if ef != sf:
        fail("classified.tsv line %d: evidence is in %s but the REPAIR_START is in "
             "%s. no run in this ledger spans two day files." % (n, ef, sf))
    if el_i <= sl:
        fail("classified.tsv line %d: evidence at line %d precedes the "
             "REPAIR_START at line %d. a repair cannot close before it opens."
             % (n, el_i, sl))
    if str(evrec.get("run")) != run or str(evrec.get("attempt")) != attempt:
        fail("classified.tsv line %d: evidence %s:%d belongs to run=%r attempt=%r, "
             "not run=%r attempt=%r."
             % (n, ef, el_i, evrec.get("run"), evrec.get("attempt"), run, attempt))
    try:
        if float(evrec.get("ts", 0)) < float(start.get("ts", 0)):
            fail("classified.tsv line %d: evidence %s:%d is timestamped before its "
                 "REPAIR_START." % (n, ef, el_i))
    except (TypeError, ValueError):
        fail("classified.tsv line %d: %s:%d has no usable ts" % (n, ef, el_i))

    want_outcome, want_class = marker_class(evrec.get("ev"), evrec.get("why"))
    if outcome != want_outcome:
        fail("classified.tsv line %d says outcome %r, but %s:%d is a %s event, "
             "which is %r." % (n, outcome, ef, el_i, evrec.get("ev"), want_outcome))
    if cls != want_class:
        fail("classified.tsv line %d classes this %r, but its own evidence "
             "%s:%d (ev=%s why=%r) supports %r. the count would be right and the "
             "reason wrong — that is the failure Kapı 2 was written against."
             % (n, cls, ef, el_i, evrec.get("ev"),
                (evrec.get("why") or "")[:90], want_class))

    counts["held" if outcome == "held" else cls] += 1

ok("every classified row cites a real, unique, sealed, same-run closing event")
ok("every class matches what its evidence says (markers checked both ways)")

# ---------------------------------------- clause: the mandatory unclassified number
if counts["unclassified"] != n_unclass:
    fail("classified.tsv reports %d unclassified; the sealed ledger has %d "
         "REPAIR_START events with no closing event of any kind. %s"
         % (counts["unclassified"], n_unclass,
            "reporting fewer is retroactive invention — the protocol's stop "
            "condition, not a rounding difference."
            if counts["unclassified"] < n_unclass else
            "reporting more means classifiable events were thrown away."))
if counts["unclassified"] == 0:
    fail("unclassified is 0. on this ledger that is not possible; it means the "
         "unknowns were labelled instead of counted.")
ok("unclassified = %d, and it matches this script's own recount" % counts["unclassified"])

# ------------------------------------------ clause: the table matches the recount
drows = tsv(DST, 2)
table = {}
for n, (k, v) in drows:
    if k in table:
        fail("distribution.tsv repeats key %r on line %d" % (k, n))
    if k not in DIST_KEYS:
        fail("distribution.tsv line %d has key %r, which is not one of the eight "
             "the contract fixes: %s" % (n, k, " ".join(DIST_KEYS)))
    try:
        table[k] = int(v)
    except ValueError:
        fail("distribution.tsv line %d: count %r is not a number" % (n, v))
absent = [k for k in DIST_KEYS if k not in table]
if absent:
    fail("distribution.tsv is missing key(s): %s. a class with zero events is "
         "reported as 0, not omitted — an absent row hides whether the scan "
         "looked for it at all." % ", ".join(absent))

bad = [(k, table[k], counts[k]) for k in DIST_KEYS if table[k] != counts[k]]
if bad:
    lines = ["    %-16s table=%d  recount=%d" % b for b in bad]
    fail("distribution.tsv disagrees with a recount of classified.tsv:\n"
         + "\n".join(lines))
if sum(table.values()) != n_starts:
    fail("distribution.tsv sums to %d; the sealed ledger holds %d REPAIR_START "
         "events." % (sum(table.values()), n_starts))
ok("distribution.tsv == independent recount, and sums to %d" % n_starts)
print("  distribution (recomputed here, not read from the report):")
for k in DIST_KEYS:
    print("    %-16s %d" % (k, counts[k]))

# ------------------------------- clause: forward closure, proven in the live ledger
live_starts = []
live_terms  = []
now_ms = time.time() * 1000.0
for name in sorted(os.listdir(SPOOL)):
    if not name.endswith(".jsonl"):
        continue
    with open(os.path.join(SPOOL, name), "rb") as fh:
        blob = fh.read()
    off = 0
    for pn, size, _sha in pins:
        if pn == name:
            off = size
    tail = blob[off:]
    base_line = prefixes[name].count(b"\n") if name in prefixes else 0
    for i, o, raw in records(tail, name):
        ev = o.get("ev")
        if ev == "REPAIR_START":
            live_starts.append((name, base_line + i, o))
        elif isinstance(ev, str) and ev.startswith("REPAIR_") and ev != "REPAIR_START":
            live_terms.append((name, base_line + i, o))

if not live_starts:
    fail("not one REPAIR_START in the live part of the ledger (past the seal). "
         "phase 1 changed code that nothing then exercised: the claim 'every "
         "REPAIR_START now closes' has not been demonstrated once. run the "
         "product against a scratch project until a repair fires, and leave the "
         "evidence in the ledger.")

open_live = []
for name, line, o in live_starts:
    key = (o.get("run"), o.get("attempt"))
    closer = None
    for tn, tl, to in live_terms:
        if tn == name and tl > line and (to.get("run"), to.get("attempt")) == key:
            closer = (tn, tl, to)
            break
    if closer is None:
        try:
            age = now_ms - float(o.get("ts", 0))
        except (TypeError, ValueError):
            age = 1e12
        if age > 300000:
            open_live.append((name, line, o, age / 1000.0))
        continue
    tn, tl, to = closer
    oc = to.get("outcome")
    if oc not in ("held", "not-held"):
        fail("live closing event %s:%d (ev=%s) carries outcome=%r. the contract "
             "says every closing event states held or not-held explicitly — "
             "inferring it from the event name is what left 267 repairs silent."
             % (tn, tl, to.get("ev"), oc))
    if oc == "not-held" and to.get("class") not in CLASSES:
        fail("live closing event %s:%d says not-held but class=%r, which is not "
             "one of the six the protocol fixes: %s"
             % (tn, tl, to.get("class"), " ".join(CLASSES)))

if open_live:
    s = ", ".join("%s:%d (open %.0fs)" % (a, b, d) for a, b, _c, d in open_live[:5])
    fail("%d live REPAIR_START event(s) older than 5 minutes still have no "
         "closing event: %s. this is the exact hole phase 1 was given."
         % (len(open_live), s))

ok("forward closure: %d live REPAIR_START event(s), all closed with an explicit outcome"
   % len(live_starts))

print("PASS: phase 1 — %d repair starts accounted for; %d closed against sealed "
      "evidence, %d reported UNCLASSIFIABLE and not invented; the live emitter "
      "closes what it opens" % (n_starts, n_matched, n_unclass))
PY
RC=$?
[ "$RC" -eq 0 ] || exit "$RC"
exit 0
