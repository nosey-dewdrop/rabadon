#!/bin/bash
# record-cast.sh — the twenty seconds of rabadon, recorded off real runs.
#
# WHY THIS FILE EXISTS. The Cyberpark jury watched the repository for forty
# silent seconds and could not tell what the product stops. Nothing in the tree
# was watchable: no .cast, no .gif, no .mp4, no local .svg, and no recorder
# either. Every part of the drama already worked and none of it had ever been
# recorded once. So this is a RECORDING job, not a build job, and the rule that
# follows from that is the only rule here worth stating —
#
#   EVERY LINE ON THE STAGE IS CAPTURED FROM A PROCESS THAT ACTUALLY RAN.
#
# Nothing is typed into a fixture and dressed up as output. The refusals come
# out of native/rabadon-gate reading a real hook event; the two verdicts come
# out of native/rabadon-repair with a real arbiter running a real test file. If a
# binary is missing this script stops rather than narrating what would have
# happened, because a demo that can be produced without the product is a
# drawing of the product.
#
# THREE THINGS IT REFUSES TO DO TO THE MACHINE IT RUNS ON.
#   1. It writes to an isolated ledger ($RABADON_DIR under mktemp). The scoreboard
#      on the site is the operator's real work and a demo may not add to it.
#   2. It sets RABADON_DRILL=1, so if any event does escape it is tagged at emit
#      and excluded from every published count, the same way `rabadon drill` is.
#   3. It never runs the dangerous commands. The gate is a PreToolUse hook: it
#      judges the command text and returns an exit code BEFORE anything runs.
#      That is the product, and it is also why this recording is safe.
#
# THE GUARD IS THIS REPOSITORY'S OWN. The two rules on stage are copied from
# .rabadon/guard.json, where both were authored after real incidents. Writing a
# fresh rule for the camera would have been easier and would have made the demo
# a statement about a regex somebody wrote for the demo.
#
#   ./scripts/record-cast.sh              record, render docs/cast/rabadon.svg
#   ./scripts/record-cast.sh --frames-only  capture, skip the render
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"

GATE="$ROOT/native/rabadon-gate"
REPAIR="$ROOT/native/rabadon-repair"
for b in "$GATE" "$REPAIR"; do
  [ -x "$b" ] || { echo "build first: make ${b##*/}" >&2; exit 1; }
done
[ -f "$ROOT/.rabadon/guard.json" ] || { echo "no .rabadon/guard.json to record against" >&2; exit 1; }

OUT_DIR="$ROOT/docs/cast"
FRAMES="$OUT_DIR/frames.jsonl"
mkdir -p "$OUT_DIR"
: > "$FRAMES"

TMP="$(mktemp -d /tmp/rabadon-cast.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
export RABADON_DIR="$TMP/ledger"
export RABADON_DRILL=1
export RABADON_MAX_REPAIRS=1
mkdir -p "$RABADON_DIR/spool"

# ---------------------------------------------------------------------------
# frame capture. One record per step: what was typed, what came back, how long
# it took in milliseconds, and the exit code. The renderer decides how to show
# it; this half only decides what is true.
# ---------------------------------------------------------------------------
now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

emit() {   # emit <cmd> <exit> <ms> <output-file> [note]
  python3 - "$1" "$2" "$3" "$4" "${5:-}" <<'PY' >> "$FRAMES"
import json, sys
cmd, rc, ms, path, note = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
out = open(path, encoding="utf-8", errors="replace").read().rstrip("\n")
lines = out.split("\n") if out else []
print(json.dumps({"cmd": cmd, "exit": rc, "ms": ms, "out": lines, "note": note},
                 ensure_ascii=False))
PY
}

# run_step <cwd> <display-cmd> <note> -- <argv...>
#
# The working directory is passed and entered in a subshell rather than handed
# to `env -C`, which is a GNU extension. macOS `env` accepts no such flag, does
# not say so, and exits 1 — so the first recording came back with four steps at
# eighteen milliseconds and exit 1 apiece, which reads exactly like a product
# that does not work. A recorder that cannot tell "the tool refused" from "the
# harness could not start the tool" is worse than no recorder.
run_step() {
  local dir="$1" disp="$2" note="$3"; shift 3; [ "$1" = "--" ] && shift
  local f="$TMP/step.out" t0 t1
  t0=$(now_ms)
  ( cd "$dir" && "$@" ) > "$f" 2>&1
  local rc=$?
  t1=$(now_ms)
  emit "$disp" "$rc" "$((t1 - t0))" "$f" "$note"
  printf '  %-46s exit %-3s %sms\n' "$disp" "$rc" "$((t1 - t0))" >&2
}

# a PreToolUse event, the shape Claude Code sends the hook
event() {   # event <cwd> <command>
  printf '{"hook_event_name":"PreToolUse","session_id":"cast-%s","tool_use_id":"cast-%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' \
    "$$-$RANDOM" "$$-$RANDOM" "$1" "$2"
}

gate_step() {   # gate_step <cwd> <command> <note>
  local f="$TMP/step.out" t0 t1
  t0=$(now_ms)
  event "$1" "$2" | "$GATE" > "$f" 2>&1
  local rc=$?
  t1=$(now_ms)
  emit "$2" "$rc" "$((t1 - t0))" "$f" "$3"
  printf '  %-46s exit %-3s %sms\n' "$2" "$rc" "$((t1 - t0))" >&2
}

# ---------------------------------------------------------------------------
# the stage
# ---------------------------------------------------------------------------
echo "recording, off real runs:" >&2

# A project that carries THIS repository's guard, so the rules on stage are the
# ones incidents wrote rather than ones written for a camera.
PROJ="$TMP/proj"
mkdir -p "$PROJ/.rabadon"
cp "$ROOT/.rabadon/guard.json" "$PROJ/.rabadon/guard.json"

HOME_SAVE="$HOME"
export HOME="$TMP/home"; mkdir -p "$HOME"

# 1. the switch, read by the binary itself
run_step "$ROOT" "rabadon on" "supervision goes from watch to enforce" -- "$GATE" --on

# 2 and 3. two refusals, from two rules this repository's own incidents wrote
gate_step "$PROJ" "git push --force origin main" "no-force-push-main"
gate_step "$PROJ" "rm -rf ~/damla_projects_2026" "no-rm-rf-outside"

export HOME="$HOME_SAVE"

# 4-7. a real bug, its own test, and the two proposers
setup_repo() {
  local d="$1"; mkdir -p "$d"
  printf 'def add(a, b):\n    return a - b   # the bug\n' > "$d/calc.py"
  cat > "$d/test_calc.py" <<'EOF'
import calc
assert calc.add(2, 3) == 5, "add(2,3) must be 5"
assert calc.add(10, 4) == 14, "add(10,4) must be 14"
print("ok")
EOF
  rm -f "$d/.sha"
}

mkdir -p "$TMP/bin"
printf '#!/bin/bash\ncat >/dev/null\nprintf "def add(a, b):\\n    return a + b\\n" > calc.py\n' > "$TMP/bin/honest.sh"
printf '#!/bin/bash\ncat >/dev/null\nprintf "print(\\"ok\\")\\n" > test_calc.py\n' > "$TMP/bin/cheat.sh"
chmod +x "$TMP/bin"/*.sh

HON="$TMP/honest"; setup_repo "$HON"
run_step "$HON" "python3 test_calc.py" "the project's own test, before" -- python3 test_calc.py
RABADON_CLAUDE_BIN="$TMP/bin/honest.sh" \
  run_step "$HON" "rabadon repair ." "an agent proposes a fix in an isolated copy" -- \
  env RABADON_CLAUDE_BIN="$TMP/bin/honest.sh" "$REPAIR" "$HON" --cmd "python3 test_calc.py" --timeout 60
# The verdict is VERIFIED and the tree is still red, and that is the product
# working. rabadon HOLDS the patch instead of applying it, so the frame after a
# successful repair has to show the operator applying it — otherwise the reel
# reads as "the repair did not work", which is the opposite of what happened.
run_step "$HON" "python3 test_calc.py" "still red on purpose: the fix is HELD, not applied" -- \
  python3 test_calc.py
run_step "$HON" "patch -p1 < .rabadon/repair-*.patch && python3 test_calc.py" \
  "the operator applies it, and the project's own test answers" -- \
  bash -c 'patch -s -p1 < "$(ls .rabadon/repair-*.patch | tail -1)" && python3 test_calc.py' 

CHT="$TMP/cheat"; setup_repo "$CHT"
run_step "$CHT" "rabadon repair ." "same bug, a proposer that edits the TEST instead" -- \
  env RABADON_CLAUDE_BIN="$TMP/bin/cheat.sh" "$REPAIR" "$CHT" --cmd "python3 test_calc.py" --timeout 60
# The closing frame is the tree itself, because fail-closed is a claim ABOUT the
# tree and a verdict line is not evidence for it. The first cut of this reel
# used native/rabadon-loop and this frame came back showing test_calc.py reduced
# to `print("ok")` under a caption that said the repository was untouched. The
# frame was right and the caption was wrong, which is the whole argument for
# ending on the tree rather than on the verdict.
run_step "$CHT" "cat calc.py test_calc.py" "and the repository the cheat ran against" -- \
  cat calc.py test_calc.py

echo >&2
printf 'frames: %s  ->  %s\n' "$(wc -l < "$FRAMES" | tr -d ' ')" "$FRAMES" >&2

[ "${1:-}" = "--frames-only" ] && exit 0
exec python3 "$ROOT/scripts/cast_svg.py" "$FRAMES" "$OUT_DIR/rabadon.svg"
