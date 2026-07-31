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
  trace)           T="$(nbin trace)" || exit 1; shift; exec "$T" "$@" ;;
  *)               exec node "$JS" "$@" ;;
esac
