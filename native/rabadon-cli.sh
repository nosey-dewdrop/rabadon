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
# A BARE `rabadon` REPORTS, it does not act. It used to default to `toggle`, so
# the first thing a new user typed silently flipped machine-wide enforcement —
# and typing it again to see what happened put it back, which reads as "nothing
# happened". A supervision tool whose state you change by accident is not one
# you can trust about anything else. Changing it is still one word away.
VERB="${1:-status}"   # resolved once: the branches below read VERB, never a bare $1
case "$VERB" in
  toggle)          G="$(nbin gate)" || exit 1; shift; exec "$G" --toggle "$@" ;;
  help|--help|-h)
    cat <<'HELP'
rabadon — a deterministic gate for coding agents. It refuses a bad action
before it happens, records what it refused, and can prove a repair.

usage: rabadon <command> [args]
       rabadon                     show whether supervision is on, change nothing

supervision
  on | off | toggle   turn enforcement on or off (machine-wide)
  status              print the current mode and the file it was read from
  budget [cap] [dir]  write the spend ceiling the gate halts a run at
  drill               feed one synthetic dangerous command through the REAL gate
  doctor              check the install: binaries, hooks, sandbox backend

setting up
  init [dir]          write the hooks into a project and author its guard.json
  lint [dir]          find rules in a project's guard.json that cannot fire
  truth [dir]         the strongest check this repo already knows how to run
  fleet [root]        install the hooks across every git repo under root
  remove              uninstall the hooks from a project

seeing what happened
  lens [--days N]     sessions, tokens and cost, read off the transcripts on disk
  usage [--days N]    what was refused, in which project, by which rule
  report [--days N]   the same, as markdown
  trace [run]         one run step by step: caught, repaired, refused
  drift [dir]         did this session wander off what it promised to work on
  audit [--days N]    verify the ledger has not been tampered with
  replay              re-run a recorded session against the current rules
  export [--otlp]     the ledger in an open format, for your own tooling

acting
  exec -- <cmd>       run a command under the project's law AND a kernel sandbox
  do "<task>" [dir]   plan a task into steps and run them under the arbiter
  loop <dir> <plan>   run an existing plan, every step checked before the next
  repair              attempt a bounded, re-checked fix for a failing check
  verify <dir> <c>    decide pass/fail on one contract, the arbiter alone
  net [dir]           run this repo's strongest check, record the verdict
  watch | ui          live view of the current session
  serve [--port N]    the team ledger: an append-only HTTP store for runs

examples
  rabadon init                    set up the project you are standing in
  rabadon drill                   see the refusal an agent would get
  rabadon usage --days 7          what it caught this week
  rabadon lens --days 30          sessions, tokens and cost for the month
  rabadon exec -- npm run deploy  run it under the guard, refused if forbidden

docs: https://github.com/nosey-dewdrop/rabadon
HELP
    exit 0 ;;
  # the rest of the line goes to the binary too: `rabadon status --help` used to
  # drop the flag on the floor and print the mode instead, the same swallow the
  # binaries themselves were fixed for.
  on|off|status)   G="$(nbin gate)" || exit 1; shift; exec "$G" "--$VERB" "$@" ;;
  statusline)      G="$(nbin gate)" || exit 1; shift; exec "$G" --statusline "$@" ;;
  # the cost half of the product. rabadon-lens shipped in every platform
  # package for weeks with no verb in front of it: `npm i -g rabadon` puts ONE
  # file on your PATH (this script), so a binary the dispatcher never names is
  # a binary nobody outside this repo can run. `cost` is kept as a spelling
  # because that is the word people reach for.
  lens|cost)       L="$(nbin lens)" || exit 1; shift; exec "$L" "$@" ;;
  stats|usage)     S="$(nbin stats)" || exit 1; shift; exec "$S" "$@" ;;
  report)          S="$(nbin stats)" || exit 1; shift; exec "$S" --md "$@" ;;
  trace)           T="$(nbin trace)" || exit 1; shift; exec "$T" "$@" ;;
  audit)           A="$(nbin audit)" || exit 1; shift; exec "$A" "$@" ;;
  repair)          R="$(nbin repair)" || exit 1; shift; exec "$R" "$@" ;;
  exec)            B="$(nbin sandbox)" || exit 1; shift; exec "$B" --dir "$(pwd)" "$@" ;;
  sandbox)         B="$(nbin sandbox)" || exit 1; shift; exec "$B" "$@" ;;
  replay)          A="$(nbin audit)" || exit 1; shift; exec "$A" --replay "$@" ;;
  lint)            G="$(nbin gate)" || exit 1; shift; exec "$G" --lint "${1:-.}" ;;
  export)          E="$(nbin export)" || exit 1; shift; exec "$E" "$@" ;;
  # the same defect as lens, seven more times: budget/do/drift/loop/net/truth/
  # verify/serve all ship in the platform packages and none of them had a verb.
  # `do` reached its binary only through bin/rabadon.mjs, which resolves
  # ../native directly and therefore misses the prebuilt platform package
  # entirely — nbin is the resolver that does not.
  budget)          B="$(nbin budget)" || exit 1; shift; exec "$B" "$@" ;;
  do)              D="$(nbin do)" || exit 1; shift; exec "$D" "$@" ;;
  drift)           D="$(nbin drift)" || exit 1; shift; exec "$D" "$@" ;;
  loop)            L="$(nbin loop)" || exit 1; shift; exec "$L" "$@" ;;
  net)             N="$(nbin net)" || exit 1; shift; exec "$N" "$@" ;;
  truth)           T="$(nbin truth)" || exit 1; shift; exec "$T" "$@" ;;
  verify)          V="$(nbin verify)" || exit 1; shift; exec "$V" "$@" ;;
  serve)           S="$(nbin serve)" || exit 1; shift; exec "$S" "$@" ;;
  init|remove|uninstall|doctor)
                   exec node "$ROOT/hooks/manage.mjs" "$@" ;;
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
