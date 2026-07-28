#!/bin/bash
# stats_test.sh — DIFFERENTIAL proof that native/rabadon-stats == the JS oracle.
#
# The JS `rabadon stats` (bin/rabadon.mjs -> core/store.mjs) is the ORACLE.
# For every case below we run BOTH against the SAME spool and compare the
# outputs BYTE-FOR-BYTE (cmp). Byte-identity subsumes "counters match per
# project and in total" — if a single number, rule line, ordering or space
# diverged, the diff would show it.
#
# Cases: a synthetic spool with real projects + drills/demos + force-push
# denies + repairs across projects and days (unicode rules, em-dash splits,
# loop-stops, ties, unparseable lines, old files, marker neighbors), several
# --days variants incl. JS-quirk values, empty/missing spool dirs, the
# empty-string RABADON_DIR fall-through, and the REAL ~/.rabadon spool.
set -u
cd "$(dirname "$0")/.."
export RABADON_NOTIFY=0

NODE_BIN="node bin/rabadon.mjs"
NATIVE=./native/rabadon-stats
[ -x "$NATIVE" ] || { echo "stats_test: build first (make native/rabadon-stats)"; exit 1; }

ok=0; bad=0
TMP=$(mktemp -d /tmp/rabadon-stats-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# run_case <label> <RABADON_DIR value or __HOME__:<home>> [stats args...]
run_case() {
  local label="$1"; shift
  local dirspec="$1"; shift
  local a="$TMP/a.out" b="$TMP/b.out"
  if [[ "$dirspec" == __HOME__:* ]]; then
    local home="${dirspec#__HOME__:}"
    HOME="$home" RABADON_DIR= $NODE_BIN stats "$@" >"$a" 2>"$TMP/a.err"
    local rc_a=$?
    HOME="$home" RABADON_DIR= $NATIVE "$@" >"$b" 2>"$TMP/b.err"
    local rc_b=$?
  else
    RABADON_DIR="$dirspec" $NODE_BIN stats "$@" >"$a" 2>"$TMP/a.err"
    local rc_a=$?
    RABADON_DIR="$dirspec" $NATIVE "$@" >"$b" 2>"$TMP/b.err"
    local rc_b=$?
  fi
  if [ "$rc_a" -ne 0 ] || [ "$rc_b" -ne 0 ]; then
    echo "FAIL  $label — exit codes node=$rc_a native=$rc_b (both must be 0)"
    bad=$((bad+1)); return
  fi
  if [ -s "$TMP/b.err" ]; then
    echo "FAIL  $label — native wrote to stderr:"; sed 's/^/        /' "$TMP/b.err"
    bad=$((bad+1)); return
  fi
  if cmp -s "$a" "$b"; then
    echo "ok    $label"
    ok=$((ok+1))
  else
    echo "FAIL  $label — outputs differ (node vs native):"
    diff "$a" "$b" | head -30 | sed 's/^/        /'
    bad=$((bad+1))
  fi
}

# ---------- synthetic spool ----------
# A known mix: real projects (alpha/beta/gamma/delta/epsilon/zeta/eta), drill
# events (emit-tagged, self-pipe, tmp.*, fleet marker + 2min neighbor),
# force-push denies (STOP BLOCKED) with em-dash rules incl. unicode >80 units,
# CHECK_FAILs (arrays, empty, missing, loop-stop), repairs, old files, an
# old-named file with a recent event (name fast-path), an unparseable-name
# file with a real event, blank/broken lines, a missing-ts event, ties.
SPOOL="$TMP/fix/spool"
mkdir -p "$SPOOL"
node - "$SPOOL" <<'EOF'
const fs = require('fs'), path = require('path');
const spool = process.argv[2];
const NOW = Date.now();
const H = (h) => NOW - Math.round(h * 3600000);
const day = (ts) => new Date(ts).toISOString().slice(0, 10);
const buckets = new Map();
const put = (name, obj) => {
  const f = name || day(obj.ts) + '.jsonl';
  if (!buckets.has(f)) buckets.set(f, []);
  buckets.get(f).push(typeof obj === 'string' ? obj : JSON.stringify(obj));
};
const ev = (ts, pipe, ev_, extra = {}) => ({ v: 1, seq: extra.seq ?? 1, ts, run: extra.run ?? 'r1', pipe, ev: ev_, ...extra });

// --- alpha: gated + blocked (repeat rule + unicode long rule) + checkfails + repairs
put(null, ev(H(5), 'alpha:session', 'STEP_START', { step: 'a', seq: 1 }));
put(null, ev(H(4.9), 'alpha:session', 'STEP_START', { step: 'b', seq: 2 }));
put(null, ev(H(4.8), 'alpha:session', 'STEP_START', { step: 'c', seq: 3 }));
put(null, ev(H(4.7), 'alpha:session', 'STOP', { reason: 'BLOCKED', detail: 'no-force-push-main — force-pushing a shared branch destroys history', seq: 4 }));
put(null, ev(H(4.6), 'alpha:session', 'STOP', { reason: 'BLOCKED', detail: 'no-force-push-main — force-pushing a shared branch destroys history', seq: 5 }));
// unicode rule: >80 UTF-16 units before the em dash (Turkish chars = 1 unit / 2 bytes,
// emoji = 2 units) — exercises the 80-key and 60-print truncations
const uni = 'kanun: "çok önemli" bir kural — değil, bu tire boşluksuz'.replace(' — ', '—') // inner dash WITHOUT spaces: not a split point
  + ' şöyle ki güvenlik 🚀 önce gelir ve açıklama upuzun sürer gider';
put(null, ev(H(4.5), 'alpha:session', 'STOP', { reason: 'BLOCKED', detail: uni + ' — the why part', seq: 6 }));
put(null, ev(H(4.4), 'alpha:session', 'STOP', { reason: 'RUNAWAY', detail: 'not counted anywhere', seq: 7 }));
put(null, ev(H(4.3), 'alpha:session', 'CHECK_FAIL', { step: 's', fails: [{ check: 'loop-stop', why: 'x' }, { check: 'style', why: 'y' }], seq: 8 }));
put(null, ev(H(4.2), 'alpha:session', 'CHECK_FAIL', { step: 's', fails: [], seq: 9 }));           // empty fails -> +1
put(null, ev(H(4.1), 'alpha:session', 'CHECK_FAIL', { step: 's', seq: 10 }));                      // missing fails -> +1
put(null, ev(H(4.0), 'alpha:session', 'REPAIR_OK', { step: 's', attempt: 1, seq: 11 }));
put(null, ev(H(3.9), 'alpha:session', 'REPAIR_OK', { step: 's', attempt: 2, seq: 12 }));
put(null, ev(H(3.8), 'alpha:session', 'STEP_START', { step: 'fleet-x no digits', seq: 13 }));      // "fleet-" w/o digit: NOT a marker

// --- beta: most recent project, lone STEP_START (all-zero counters otherwise)
put(null, ev(H(1), 'beta:do', 'STEP_START', { step: 'only', run: 'r2' }));

// --- gamma: loop-stop suffix + detail-less BLOCKED ('?') + equal-n rule tie order
put(null, ev(H(2.2), 'gamma', 'CHECK_FAIL', { fails: [{ check: 'loop-stop', why: 'z' }], run: 'r3', seq: 1 }));
put(null, ev(H(2.1), 'gamma', 'STOP', { reason: 'BLOCKED', run: 'r3', seq: 2 }));                  // missing detail -> '?'
put(null, ev(H(2.05), 'gamma', 'STOP', { reason: 'BLOCKED', detail: 'rule-b — later', run: 'r3', seq: 3 })); // n=1 tie: '?' first-seen wins

// --- delta: fleet marker (drill) + neighbor inside 2min (drill) + 130s later (REAL)
const T0 = H(10);
put(null, ev(T0, 'delta:session', 'STEP_START', { step: 'x', run: 'fleet-123-delta', seq: 1 }));
put(null, ev(T0 + 60000, 'delta:session', 'STOP', { reason: 'BLOCKED', detail: 'drill-rule — synthetic', run: 'r4', seq: 2 }));
put(null, ev(T0 + 130000, 'delta:session', 'STEP_START', { step: 'real', run: 'r4', seq: 3 }));

// --- pipe-less events: doctor marker (undefined === undefined pipe match)
const T1 = H(8);
put(null, { v: 1, seq: 1, ts: T1, run: 'doctor-77', ev: 'STEP_START', step: 'probe' });            // no pipe, marker
put(null, { v: 1, seq: 2, ts: T1 + 90000, run: 'r5', ev: 'STEP_START', step: 'near' });            // no pipe, within 2min -> drill
put(null, { v: 1, seq: 3, ts: H(6), run: 'r5', ev: 'STEP_START', step: 'far' });                    // no pipe, far -> project "?"

// --- drills: emit-tagged / self pipes / tmp.*
put(null, ev(H(3), 'alpha:session', 'STEP_START', { step: 'drill', drill: true, seq: 20 }));
put(null, ev(H(3), 'do-test:do', 'STEP_START', { step: 'self' }));
put(null, ev(H(3), 'tmp.scratch', 'CHECK_FAIL', { fails: [{ check: 'c', why: 'w' }] }));
put(null, ev(H(3), 'bus-test', 'RUN_START', {}));

// --- epsilon: window-boundary project (30h inside 1.5d, 40h outside 1.5d but inside 7d)
put(null, ev(H(30), 'epsilon:session', 'STEP_START', { step: 'in36', run: 'r6', seq: 1 }));
put(null, ev(H(40), 'epsilon:session', 'STEP_START', { step: 'in7d', run: 'r6', seq: 2 }));

// --- zeta/eta: identical lastTs -> stable first-encounter order (by seq at same ts)
const TIE = H(2.5);
put(null, ev(TIE, 'zeta', 'STEP_START', { step: 't', run: 'r7', seq: 1 }));
put(null, ev(TIE, 'eta', 'STEP_START', { step: 't', run: 'r8', seq: 2 }));

// --- noise: blank lines, whitespace line, truncated JSON, garbage, missing ts
put(day(H(5)) + '.jsonl', '');
put(day(H(5)) + '.jsonl', '   ');
put(day(H(5)) + '.jsonl', '{"v":1,"seq":');
put(day(H(5)) + '.jsonl', 'not json at all');
put(day(H(5)) + '.jsonl', 'null');
put(day(H(5)) + '.jsonl', JSON.stringify({ v: 1, pipe: 'alpha:session', ev: 'STEP_START', step: 'no-ts' }));

// --- old file fully outside the window (name fast-path AND ts filter)
const OLD = NOW - 40 * 86400000;
put(day(OLD) + '.jsonl', ev(OLD, 'ancient:session', 'STEP_START', { step: 'old' }));
// old-NAMED file with a RECENT ts: the JS skips the whole file by NAME — parity on the fast path
put(day(NOW - 39 * 86400000) + '.jsonl', ev(H(1), 'ghost:session', 'STEP_START', { step: 'recent-in-old-file' }));
// unparseable NAME with a real recent event: must still be read
put('zz-notadate.jsonl', ev(H(1.5), 'theta', 'REPAIR_OK', { step: 'r', run: 'r9' }));

for (const [f, lines] of buckets) fs.writeFileSync(path.join(spool, f), lines.join('\n') + '\n');
console.log(`fixture: ${buckets.size} spool file(s) written`);
EOF

FIX="$TMP/fix"
echo "== synthetic spool: $SPOOL"
run_case "synthetic --days default(7)"      "$FIX"
run_case "synthetic --days 2"               "$FIX" --days 2
run_case "synthetic --days 1.5 (fractional)" "$FIX" --days 1.5
run_case "synthetic --days 30"              "$FIX" --days 30
run_case "synthetic --days 0 (falsy -> 7)"  "$FIX" --days 0
run_case "synthetic --days abc (NaN -> 7)"  "$FIX" --days abc
run_case "synthetic --days -3 (future cutoff, empty)" "$FIX" --days -3
run_case "synthetic --days '' (Number('')=0 -> 7)"    "$FIX" --days ""
run_case "synthetic --days trailing (no value -> 7)"  "$FIX" --days
run_case "synthetic --days 0x2 (JS hex quirk -> 2)"   "$FIX" --days 0x2
run_case "synthetic --days -0x2 (signed hex = NaN -> 7)" "$FIX" --days -0x2
run_case "synthetic --days 1e1 (exponent -> 10)"      "$FIX" --days 1e1

# ---------- empty / missing spool dirs ----------
mkdir -p "$TMP/empty/spool"
run_case "empty spool dir"    "$TMP/empty"
run_case "missing spool dir"  "$TMP/does-not-exist"

# ---------- RABADON_DIR="" falls through to HOME/.rabadon (JS ||) ----------
FAKEHOME="$TMP/home"
mkdir -p "$FAKEHOME/.rabadon/spool"
cp "$SPOOL"/*.jsonl "$FAKEHOME/.rabadon/spool/"
run_case "empty RABADON_DIR -> HOME/.rabadon" "__HOME__:$FAKEHOME" --days 7

# ---------- spec author's fixture, if still present ----------
if [ -d /tmp/rbdspec/spool ]; then
  run_case "spec fixture /tmp/rbdspec" /tmp/rbdspec --days 7
fi

# ---------- the REAL spool ----------
# Race guard: a live session appending to ~/.rabadon/spool between the two
# runs would make an honest byte-diff flake, so on mismatch we retry once.
REAL="$HOME/.rabadon"
if [ -d "$REAL/spool" ]; then
  for d in 7 30; do
    a="$TMP/ra.out"; b="$TMP/rb.out"
    RABADON_DIR="$REAL" $NODE_BIN stats --days "$d" >"$a"
    RABADON_DIR="$REAL" $NATIVE --days "$d" >"$b"
    if ! cmp -s "$a" "$b"; then
      RABADON_DIR="$REAL" $NODE_BIN stats --days "$d" >"$a"
      RABADON_DIR="$REAL" $NATIVE --days "$d" >"$b"
    fi
    if cmp -s "$a" "$b"; then
      echo "ok    real spool --days $d ($(grep -c '^  [^ (]' "$a" 2>/dev/null || echo '?') project lines agree byte-for-byte)"
      ok=$((ok+1))
    else
      echo "FAIL  real spool --days $d — outputs differ:"
      diff "$a" "$b" | head -30 | sed 's/^/        /'
      bad=$((bad+1))
    fi
  done
else
  echo "skip  real spool ($REAL/spool not present)"
fi

echo
echo "stats_test: $ok ok, $bad bad"
[ "$bad" -eq 0 ] || exit 1
exit 0
