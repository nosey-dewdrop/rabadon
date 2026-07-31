#!/bin/bash
# rabadon — the single command the user types (bare `rabadon`, or `!rabadon` in the
# Claude prompt). DEFAULT = toggle the one native flag the gate reads
# (~/.rabadon/enabled), so on/off is deterministic in ANY shell — no dependency on a
# shell function that the `!` path doesn't load. Recognized verbs go native; anything
# else (watch/ui/do/fleet…) delegates to the original rabadon.mjs, untouched
# (that file is anti-path — never edited, only called through here).
#
# Self-locating: resolves its own real path through npm-bin symlinks, so the same
# file works from npm -g, npm link, or a plain git clone — no paths are baked in.
SELF="$0"
while [ -L "$SELF" ]; do
  DIR="$(cd "$(dirname "$SELF")" && pwd)"
  SELF="$(readlink "$SELF")"
  case "$SELF" in /*) ;; *) SELF="$DIR/$SELF" ;; esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# native binary resolution: local build first (git clone / postinstall compile),
# then the prebuilt platform package (@rabadon/<os>-<cpu>), which npm installs
# either under this package's node_modules or as a sibling in the global tree.
plat() {
  case "$(uname -s)" in Darwin) os=darwin ;; Linux) os=linux ;; *) os=unsupported ;; esac
  case "$(uname -m)" in arm64|aarch64) cpu=arm64 ;; x86_64|amd64) cpu=x64 ;; *) cpu=unsupported ;; esac
  printf '%s-%s' "$os" "$cpu"
}
nbin() {
  n="rabadon-$1"
  for p in "$ROOT/native/$n" \
           "$ROOT/node_modules/@rabadon/$(plat)/$n" \
           "$ROOT/../@rabadon/$(plat)/$n"; do
    if [ -x "$p" ]; then printf '%s' "$p"; return 0; fi
  done
  echo "rabadon: native binary '$n' is not available — no prebuilt package for $(plat) and no local build." >&2
  echo "  build from source: cd '$ROOT' && make   (needs clang++ or g++; then re-run)" >&2
  echo "  diagnose:          rabadon doctor" >&2
  return 1
}

JS="$ROOT/bin/rabadon.mjs"
case "${1:-toggle}" in
  toggle)          G="$(nbin gate)" || exit 1; exec "$G" --toggle ;;
  on|off|status)   G="$(nbin gate)" || exit 1; exec "$G" "--$1" ;;
  statusline)      G="$(nbin gate)" || exit 1; exec "$G" --statusline ;;
  stats|usage)     S="$(nbin stats)" || exit 1; shift; exec "$S" "$@" ;;
  report)          S="$(nbin stats)" || exit 1; shift; exec "$S" --md "$@" ;;
  trace)           T="$(nbin trace)" || exit 1; shift; exec "$T" "$@" ;;
  audit)           A="$(nbin audit)" || exit 1; shift; exec "$A" "$@" ;;
  repair)          R="$(nbin repair)" || exit 1; shift; exec "$R" "$@" ;;
  exec)            B="$(nbin sandbox)" || exit 1; shift; exec "$B" --dir "$(pwd)" "$@" ;;
  sandbox)         B="$(nbin sandbox)" || exit 1; shift; exec "$B" "$@" ;;
  replay)          A="$(nbin audit)" || exit 1; shift; exec "$A" --replay "$@" ;;
  drill)
    # one tagged test event through the REAL gate — see the refusal text an
    # agent would get, without waiting for a real incident and without
    # polluting the ledger (RABADON_DRILL=1 + drill-<pid> tag at emit).
    G="$(nbin gate)" || exit 1
    CWD="$(pwd)"
    CMD="git push --force origin main"
    echo "rabadon drill — feeding a synthetic dangerous command through the REAL gate:"
    echo "    \$ $CMD"
    echo
    OUT="$(printf '{"hook_event_name":"PreToolUse","session_id":"drill-%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' \
      "$$" "$CWD" "$CMD" | RABADON_DRILL=1 "$G" 2>&1)"
    RC=$?
    [ -n "$OUT" ] && printf '%s\n' "$OUT"
    echo
    if [ "$RC" -eq 2 ]; then
      echo "the gate REFUSED it (exit 2) — a live agent session would have been stopped here."
    elif printf '%s' "$OUT" | grep -q "would have blocked"; then
      echo "the rule FIRED in watch mode — \`rabadon on\` makes this a real refusal (exit 2)."
    else
      echo "no guard rule matched in $CWD — run \`rabadon init\` here to author one."
    fi
    echo "this was a drill: tagged at emit, excluded from the ledger. \`rabadon usage\` counts only real catches."
    exit 0 ;;
  *)               exec node "$JS" "$@" ;;
esac
