#!/usr/bin/env bash
# route_demo.sh — the SECOND FACE proof: provably-safe cost reduction.
#
# One plan, one arbiter, TWO real runs:
#   routed   RABADON_TIERS=haiku,opus — every step is attempted on the cheap
#            model first. rabadon-verify runs the project's OWN frozen spec
#            suite; a step is accepted only when that suite is green, so a cheap
#            answer that is kept has been PROVEN, not hoped for. Rejected -> the
#            same step is re-run on opus and the climb is recorded.
#   control  RABADON_TIERS=opus — the identical plan, identical contracts,
#            identical repair budget, every step on the expensive model.
#
# The saving is the measured difference between the two, and the cheap attempts
# that were REJECTED are inside the routed number — routing pays for its own
# waste. Nothing here is priced by rabadon: every dollar comes from the model's
# own result event (total_cost_usd), fused into the spool per attempt.
#
# FAIRNESS (deliberate, and the reason the number is a floor):
#   * the routed arm runs FIRST, so the 5-minute prompt cache warms up for the
#     CONTROL arm — the cache discount goes to the side we are trying to beat.
#   * both arms start from an identical clean repo and share the spec file's
#     forbidden-sha lock, so neither can win by editing the judge.
#   * if routing ends up costing MORE, the trace prints exactly that.
#
# BOUNDED: isolated spool, RABADON_MAX_REPAIRS=1, per-call wall-clock cap.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

LOOP="$ROOT/native/rabadon-loop"
VERIFY="$ROOT/native/rabadon-verify"
LLM="$ROOT/native/llm-proposer.sh"
TRACE="$ROOT/native/rabadon-trace"
for b in "$LOOP" "$VERIFY" "$LLM" "$TRACE"; do
  [ -x "$b" ] || { echo "build first: $b   (run: make)"; exit 1; }
done
command -v claude >/dev/null || { echo "claude CLI not on PATH"; exit 1; }

CHEAP="${RABADON_CHEAP:-haiku}"
PRICEY="${RABADON_PRICEY:-opus}"
# smoke path: point this at a scripted proposer to exercise the whole demo —
# repo, contracts, escalation, both arms, trace — without spending a cent. The
# money numbers come out as "—" then, which is the honest thing for a fake run.
PROPOSER_BIN="${RABADON_PROPOSER_OVERRIDE:-}"

TMP=$(mktemp -d /tmp/rabadon-route-demo.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export RABADON_DIR="$TMP/ledger"
export RABADON_MAX_REPAIRS=1
export RABADON_LLM_TIMEOUT="${RABADON_LLM_TIMEOUT:-240}"
mkdir -p "$RABADON_DIR/spool"

fnv1a() { python3 -c "
h=1469598103934665603
for b in open('$1','rb').read(): h=((h^b)*1099511628211)&0xffffffffffffffff
print(h)"; }

setup_repo() {   # the customer's repo: a frozen spec suite, an empty toolkit
  local d="$1"; mkdir -p "$d"
  cat > "$d/spec_test.py" <<'EOF'
# The project's OWN spec suite. rabadon never writes this file and never shows
# it to a proposer as something to satisfy: it is the arbiter's ground truth,
# locked by sha. Usage: python3 spec_test.py <group|all>
import sys
try:
    import toolkit as t
except Exception as e:
    print("IMPORT FAIL:", e); raise SystemExit(1)

fails = []
def check(name, fn, want):
    try:
        got = fn()
    except Exception as e:
        fails.append(name); print(f"  FAIL {name}: raised {e!r}"); return
    if got == want: print("  PASS " + name)
    else: fails.append(name); print(f"  FAIL {name}: got {got!r}, want {want!r}")

def raises(name, fn):
    try:
        fn()
    except ValueError:
        print("  PASS " + name); return
    except Exception as e:
        fails.append(name); print(f"  FAIL {name}: raised {e!r}, want ValueError"); return
    fails.append(name); print(f"  FAIL {name}: no ValueError")

def g_slug():
    check("slug_basic",   lambda: t.slugify("Hello,  World!"), "hello-world")
    check("slug_edges",   lambda: t.slugify("--A_b  9--"),     "a-b-9")
    check("slug_empty",   lambda: t.slugify("!!!"),            "")

def g_duration():
    check("dur_hm",       lambda: t.parse_duration("1h30m"), 5400)
    check("dur_s",        lambda: t.parse_duration("45s"),   45)
    check("dur_hms",      lambda: t.parse_duration("2h3m4s"),7384)
    raises("dur_bad",     lambda: t.parse_duration("90"))
    raises("dur_empty",   lambda: t.parse_duration(""))

def g_intervals():
    check("iv_merge",     lambda: t.merge_intervals([(1,3),(2,6),(8,10)]), [(1,6),(8,10)])
    check("iv_touch",     lambda: t.merge_intervals([(1,2),(2,3)]),        [(1,3)])
    check("iv_unsorted",  lambda: t.merge_intervals([(5,6),(1,4),(2,3)]),  [(1,4),(5,6)])
    check("iv_empty",     lambda: t.merge_intervals([]),                   [])

def g_rle():
    # letters only, so the separator-free format stays decodable. The subtlety
    # is the multi-digit run: a decoder that reads ONE digit turns x12 into
    # one x and a literal "2".
    check("rle_basic",    lambda: t.rle_encode("aaabbc"),      "a3b2c1")
    check("rle_multi",    lambda: t.rle_encode("x"*12),        "x12")
    check("rle_round",    lambda: t.rle_decode(t.rle_encode("aaabbbbbbbbbbbc")), "aaabbbbbbbbbbbc")
    check("rle_empty",    lambda: t.rle_encode(""),            "")

def g_wrap():
    check("wrap_basic",   lambda: t.wrap_text("the quick brown fox", 10), ["the quick","brown fox"])
    check("wrap_long",    lambda: t.wrap_text("supercalifragilistic", 8), ["supercal","ifragili","stic"])
    check("wrap_spaces",  lambda: t.wrap_text("  a   b  ", 3),            ["a b"])
    check("wrap_empty",   lambda: t.wrap_text("", 5),                     [])

GROUPS = {"slug":g_slug, "duration":g_duration, "intervals":g_intervals, "rle":g_rle, "wrap":g_wrap}
want = sys.argv[1] if len(sys.argv) > 1 else "all"
for name, fn in GROUPS.items():
    if want in (name, "all"): fn()
if fails:
    print("SUITE RED — failing: " + ", ".join(fails)); raise SystemExit(1)
print("ok")
EOF
  printf '# rabadon fills this in, one step at a time.\n' > "$d/toolkit.py"
}

write_plan() {   # 5 work steps: the model writes real code, the spec judges it
  local d="$1" sha="$2"
  cat > "$d/plan.json" <<EOF
{
  "goal": "build the text toolkit — slugify, durations, intervals, RLE, wrapping",
  "steps": [
    { "id": "slugify", "kind": "work",
      "do": "In toolkit.py implement slugify(s). Read spec_test.py first — the group g_slug defines the exact behavior. Add only this function.",
      "contract": [ { "type": "testsuite", "run": "python3 spec_test.py slug" },
                    { "type": "forbidden", "path": "spec_test.py", "sha": "$sha" } ] },

    { "id": "parse-duration", "kind": "work",
      "do": "In toolkit.py implement parse_duration(s) returning seconds. Read spec_test.py — the group g_duration defines the exact behavior, including which inputs must raise ValueError. Keep the existing functions untouched.",
      "contract": [ { "type": "testsuite", "run": "python3 spec_test.py duration" },
                    { "type": "forbidden", "path": "spec_test.py", "sha": "$sha" } ] },

    { "id": "merge-intervals", "kind": "work",
      "do": "In toolkit.py implement merge_intervals(pairs). Read spec_test.py — the group g_intervals defines the exact behavior. Keep the existing functions untouched.",
      "contract": [ { "type": "testsuite", "run": "python3 spec_test.py intervals" },
                    { "type": "forbidden", "path": "spec_test.py", "sha": "$sha" } ] },

    { "id": "rle-roundtrip", "kind": "work",
      "do": "In toolkit.py implement rle_encode(s) and rle_decode(s) for letter-only strings. Read spec_test.py — the group g_rle defines the exact behavior; note that a run longer than nine characters encodes to a multi-digit count and must still decode back. Keep the existing functions untouched.",
      "contract": [ { "type": "testsuite", "run": "python3 spec_test.py rle" },
                    { "type": "forbidden", "path": "spec_test.py", "sha": "$sha" } ] },

    { "id": "wrap-text", "kind": "work",
      "do": "In toolkit.py implement wrap_text(s, width) returning a list of lines. Read spec_test.py — the group g_wrap defines the exact behavior, including words longer than width. Keep the existing functions untouched.",
      "contract": [ { "type": "testsuite", "run": "python3 spec_test.py wrap" },
                    { "type": "forbidden", "path": "spec_test.py", "sha": "$sha" } ] }
  ],
  "accept": [ { "type": "testsuite", "run": "python3 spec_test.py all" },
              { "type": "forbidden", "path": "spec_test.py", "sha": "$sha" } ]
}
EOF
}

run_arm() {   # <arm> <tiers> <label>
  local arm="$1" tiers="$2" label="$3"
  local d="$TMP/toolkit-$arm"   # the project name shows up in the trace header
  setup_repo "$d"
  local sha; sha=$(fnv1a "$d/spec_test.py")
  write_plan "$d" "$sha"
  echo "────────────────────────────────────────────────────────────────"
  echo "  ARM: $arm   ($label)"
  echo "────────────────────────────────────────────────────────────────"
  local t0 t1; t0=$(date +%s)
  RABADON_ARM="$arm" RABADON_TIERS="$tiers" RABADON_PROPOSER="${PROPOSER_BIN:-$LLM}" \
    "$LOOP" "$d" "$d/plan.json" 2>&1 | sed 's/^/  /'
  local rc=${PIPESTATUS[0]}
  t1=$(date +%s)
  echo "  arm exit: $rc   ($(( t1 - t0 ))s wall)"
  echo
}

echo "=================================================================="
echo " rabadon — VERIFIED ROUTING: cheap where it is PROVEN, expensive"
echo " where the arbiter says it must be. Two real runs, one plan."
echo "=================================================================="
echo
# routed first ON PURPOSE: the prompt cache it warms benefits the control arm,
# so the measured gap is a floor, not a best case.
run_arm "routed"  "$CHEAP,$PRICEY" "cheap-first, arbiter decides when to climb"
run_arm "control" "$PRICEY"        "every step on the expensive model"

echo "=================================================================="
echo " THE OUTPUT — rabadon trace (rendered from the isolated ledger):"
echo "=================================================================="
echo
"$TRACE" "$RABADON_DIR/spool"
