#!/usr/bin/env bash
# 2-abc-olcum.sh — KOSU-RABADON-5.md §F3's three acceptance layers, measured
# against the SHIPPED binary, not against a probe.
#
#   (a) did rabadon write it   -> SIGNAL, INJECT and COUNTER, all three, in one
#                                 session's ledger. STEP_START does not count:
#                                 it is written on both hooks regardless.
#   (b) did the agent read it  -> the signature of the first move after the
#                                 injection against the one that was repeating
#                                 before it. Answerable off the ledger alone
#                                 since psig/INJECT_ANSWER (this phase).
#   (c) did it do harm         -> a negative control on a sealed task set.
#                                 NOT RUN HERE, and this script says so rather
#                                 than leaving the layer looking measured.
#
# It also counts the LIVE ledger, because a fixture proves the mechanism and
# the live ledger is the only thing that proves the mechanism is reaching real
# sessions.
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
GATE="${RABADON_GATE:-$ROOT/native/rabadon-gate}"
[ -x "$GATE" ] || { echo "no gate binary at $GATE"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/rbabc.XXXXXX")"
trap 'rm -rf "$T"' EXIT
H="$T/h"; P="$T/p"
mkdir -p "$H/.rabadon/spool" "$P/.git" "$P/src"
printf 'ref: refs/heads/main\n' > "$P/.git/HEAD"
: > "$H/.rabadon/enabled"

ev() { # ev <hook> <tool> <tool_input-json>
  printf '{"hook_event_name":"%s","session_id":"abc","cwd":"%s","tool_name":"%s","tool_input":%s}' \
    "$1" "$P" "$2" "$3" \
  | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$GATE" 2>/dev/null
}
edit() { ev PreToolUse Edit "{\"file_path\":\"$P/$1\",\"old_string\":\"\",\"new_string\":\"$2\"}"; }

echo "=== fixture: an A-B-A-B-A-B oscillation on one file, the real binary ==="
for i in 1 2 3; do
  edit src/app.js 'const timeout = 500;'  >/dev/null
  edit src/app.js 'const timeout = 5000;' >/dev/null
done
OUT="$(edit src/carrier.js 'const carrier = 1;')"   # the carrier: delivery rides here
edit src/other.js 'const other = 2;' >/dev/null      # the answer
printf '{"hook_event_name":"SessionEnd","session_id":"abc","cwd":"%s"}' "$P" \
  | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$GATE" >/dev/null 2>&1

case "$OUT" in
  *additionalContext*) echo "delivery      : YES — additionalContext on stdout, the documented envelope";;
  *)                   echo "delivery      : NO  — nothing below is worth reading"; exit 1;;
esac

python3 - "$H/.rabadon/spool" <<'PY'
import json, os, sys, glob
evs = []
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.jsonl"))):
    for line in open(f):
        line = line.strip()
        if not line: continue
        try: evs.append(json.loads(line))
        except Exception: pass
kinds = {}
for e in evs: kinds[e.get("ev")] = kinds.get(e.get("ev"), 0) + 1

print()
print("=== (a) did rabadon write it ===")
for k in ("SIGNAL", "INJECT", "COUNTER"):
    print("  %-8s x%-3d %s" % (k, kinds.get(k, 0), "PRESENT" if kinds.get(k) else "ABSENT"))
a_ok = all(kinds.get(k) for k in ("SIGNAL", "INJECT", "COUNTER"))
print("  (a) =", "MET" if a_ok else "NOT MET")
print("  (STEP_START x%d is NOT counted: written on both hooks regardless.)" % kinds.get("STEP_START", 0))

print()
print("=== (b) did the agent read it ===")
inj = [e for e in evs if e.get("ev") == "INJECT"]
ans = [e for e in evs if e.get("ev") == "INJECT_ANSWER"]
judgeable = 0
for e in ans:
    if e.get("psig") and e.get("sig"):
        judgeable += 1
        print("  signal=%s psig=%s -> sig=%s same=%s" %
              (e.get("signal"), e.get("psig"), e.get("sig"), e.get("same")))
print("  INJECT n=%d, INJECT_ANSWER n=%d, JUDGEABLE n=%d" % (len(inj), len(ans), judgeable))
print("  (b) =", "ANSWERABLE" if judgeable else "NOT ANSWERABLE")

print()
print("=== (c) did it do harm ===")
print("  NOT RUN. The negative control is a two-armed run over the sealed task")
print("  set (orkestrasyon v6 §3.8/2) and needs network plus `claude -p`.")
print("  §F3: \"Bu olcum yapilmadan F4 acilmaz.\" -> F4 STAYS CLOSED.")
PY

echo
echo "=== the LIVE ledger, for contrast (this is the number that matters) ==="
python3 - "${RABADON_LIVE_SPOOL:-$HOME/.rabadon/spool}" <<'PY'
import json, os, sys, glob
d = sys.argv[1]
inj = injp = ans = 0
if os.path.isdir(d):
    for f in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
        for line in open(f, errors="replace"):
            line = line.strip()
            if not line: continue
            try: e = json.loads(line)
            except Exception: continue
            if e.get("ev") == "INJECT":
                inj += 1
                if e.get("psig"): injp += 1
            elif e.get("ev") == "INJECT_ANSWER":
                ans += 1
else:
    print("  no live spool at", d); raise SystemExit(0)
print("  live spool           :", d)
print("  INJECT               :", inj)
print("  of those carrying psig:", injp)
print("  INJECT_ANSWER        :", ans)
print("  live judgeable n     :", min(injp, ans))
print("  Every INJECT line older than this phase predates psig, so a live n of 0")
print("  is expected and is NOT evidence that the mechanism fails; it is the")
print("  count starting from zero. The fixture above is what proves the wiring.")
PY
