#!/bin/bash
# rabadon — the single command the user types (bare `rabadon`, or `!rabadon` in the
# Claude prompt). DEFAULT = toggle the one native flag the gate reads
# (~/.rabadon/enabled), so on/off is deterministic in ANY shell — no dependency on a
# shell function that the `!` path doesn't load. Recognized verbs go native; anything
# else (watch/ui/do/fleet/doctor…) delegates to the original rabadon.mjs, untouched
# (that file is anti-path — never edited, only called through here).
GATE="$HOME/damla_projects_2026/rabadon/native/rabadon-gate"
STATS="$HOME/damla_projects_2026/rabadon/native/rabadon-stats"
JS="$HOME/damla_projects_2026/rabadon/bin/rabadon.mjs"
case "${1:-toggle}" in
  toggle)        exec "$GATE" --toggle ;;
  on|off|status) exec "$GATE" "--$1" ;;
  statusline)    exec "$GATE" --statusline ;;
  stats)         shift; exec "$STATS" "$@" ;;
  *)             exec node "$JS" "$@" ;;
esac
