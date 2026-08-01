# rabadon commands

Every verb of the `rabadon` CLI. The CLI is a thin dispatcher
(`native/rabadon-cli.sh`): recognized verbs go straight to a native binary,
lifecycle verbs (`init`/`remove`/`doctor`) go to `hooks/manage.mjs`.

Maturity tags: **[stable]** = shipping and tested on this machine.
**[building]** = code exists, not yet complete — do not rely on it.

Common exit-code convention: `0` success, `1` an error or a failed check, `2`
a refusal or bad usage, `3` a precondition missing (no backend, no proposer, no
runnable check). Specific codes noted per verb.

Also dispatched, each with its own `--help` screen, reference section still to
be written: `budget` (write the spend ceiling
the gate halts at) · `do` (plan a task into steps and run them under the
arbiter) · `loop` (run an existing plan) · `verify` (decide pass/fail on one
contract) · `net` (run this repo's strongest check and record the verdict) ·
`truth` (what this repo already knows how to check) · `drift` (did the session
wander off its promise) · `serve` (the team ledger) · `fleet` (install the hooks
across every git repo under a root). `native/cli_test.sh` holds every shipped binary to being reachable
through this CLI and listed on the help screen, because `npm i -g rabadon`
installs exactly one file onto your PATH — the dispatcher — so a binary it does
not name is a binary nobody can run.

---

## `rabadon init [dir] [--no-llm] [--global]`   [stable]

Author a guard, lint it, and merge the gate hooks into `.claude/settings.json`.

- Authors `.rabadon/guard.json`. With the `claude` CLI present it writes
  project-specific rules; with `--no-llm` or no `claude` CLI it writes a
  baseline of four rules and tells you so.
- Lints the guard before installing. If the guard has problems, hooks are
  **not** installed and it exits 1.
- Merges hooks, backing up an existing `settings.json` to
  `settings.json.bak-rabadon`. Repairs a stale rabadon install in place.
- An existing guard is kept, never overwritten.

Flags: `--no-llm` (skip authoring, write the baseline), `--global` (target
`~/.claude/settings.json` and the home guard).

Exit: `0` done · `1` guard invalid or settings unreadable · `3` native core not
built.

```
rabadon init
rabadon init ~/code/api --no-llm
rabadon init --global
```

---

## `rabadon on | off | status | toggle`   [stable]

Switch supervision mode. The mode is one native flag (`~/.rabadon/enabled`) the
gate reads, so it is deterministic in any shell.

- `on` — **enforce**: forbidden actions are refused (exit 2).
- `off` — **watch**: every rule still runs and every verdict is recorded as a
  `WOULD_BLOCK` event, but nothing is stopped.
- `status` — print the current mode.
- `toggle` — flip enforce <-> watch (this is also the bare `rabadon` default).

Exit: `0`.

```
rabadon on
rabadon status
```

---

## `rabadon lens [transcript.jsonl | dir] [--days N]`   [stable]

Alias: `rabadon cost`. Sessions, tokens and cost, read straight off the
transcripts Claude Code already writes to disk. Zero instrumentation: nothing
has to be wrapped, no key is needed, and **no model is called to produce any
number here** — the metering is byte-exact arithmetic over files that are
already on your machine.

One row per session: project, model, input / output / cache tokens, total
tokens, cost in USD, tool calls, wall duration.

Argument: a single transcript, or a directory of them. Omitted, it reads
`$RABADON_LENS_DIR`, else `~/.claude/projects`.

Flags: `--days N` (window, default 7).

Exit: `0`.

```
rabadon lens
rabadon lens --days 30
rabadon lens ~/.claude/projects/-Users-me-src-api
```

---

## `rabadon usage [--days N] [--project P] [--full] [--json]`   [stable]

Alias: `rabadon stats`. The ledger. Refusals grouped by rule id with each rule's
reason, plus headline totals. Drills and self-tests are excluded from every
number.

Flags: `--days N` (window, default 7) · `--project P` (one project only) ·
`--full` (list every catch with timestamp and detail) · `--json` (machine
output).

Exit: `0`.

```
rabadon usage --days 30
rabadon usage --project my-project --full
rabadon usage --json
```

---

## `rabadon report [--days N]`   [stable]

The same numbers as `usage`, rendered as Markdown on stdout with a methodology
footer (source spool, drill exclusion, reproduce command). For pasting into a
PR or a README.

Exit: `0`.

```
rabadon report --days 14 > weekly.md
```

---

## `rabadon drill`   [stable]

Fire one tagged synthetic dangerous command (`git push --force origin main`)
through the **real** gate so you see the refusal text in about 30 seconds. The
event is tagged at emit and excluded from the ledger.

Exit: `0` always (the drill reports the gate's verdict in its text, it does not
propagate it).

```
rabadon drill
```

---

## `rabadon trace [run] [--days N] [--last]`   [stable]

One run, step by step: which step was caught, what the check said, whether the
repair was accepted or the fake fix refused, and what the repair cost. Reads the
spool only — nothing here calls a model, and every number printed is already in
the ledger.

`[run]` is a run id, not a file. A bare word is taken as a run whenever it is
not a path that exists; a path (a `.jsonl`, or a directory whose newest day file
wins) is taken as the ledger to read. `--run <id>` is the same thing spelled
long. The id is matched as a substring, so the eight characters the header
prints are enough to address the run.

The id is looked for across the whole `--days` window (default 7), not in the
newest day file alone — a run written yesterday is still addressable today. When
more than one day file carries the run, the header names the first and counts
the rest.

Exit: `0` when a run rendered. `1` when none did — the message names the run and
the window it searched, and stdout stays empty, so a caller can tell "not there"
apart from "there and empty". `2` on an unknown flag or a second positional.

```
rabadon trace ms92w639-mdr-1          # one run, wherever in the window it is
rabadon trace --last --no-color       # the newest run, pipe-safe
rabadon trace --run ms92w639 --days 30
```

---

## `rabadon audit [--days N]`   [stable]

Verify the hash-chained spool. Every event carries `prev` = the SHA-256 of the
previous line in its day file. This re-walks the chain and answers one question:
was the ledger edited after the fact? A broken link is named by file and line.
Unchained lines (legacy writers) are tolerated, counted, reported.

Flags: `--days N` (window, default 7).

Exit: `0` every chained link intact · `1` at least one broken link (tamper).

```
rabadon audit --days 30
```

---

## `rabadon replay [--days N]`   [stable]

Render the verified session timeline event by event, with a chain mark per line
(a check mark before the first break, a cross from there on). The "what
happened" view with the tamper check inline. (Implemented as `audit --replay`.)

Flags: `--days N`.

Exit: `0` intact · `1` a break was found.

```
rabadon replay --days 7
```

---

## `rabadon exec -- <cmd>`   [stable]

Run `<cmd>` under a **kernel** sandbox compiled from `guard.json`: each
`protectedPaths` entry becomes a read-only fence, and `"network":"deny"` cuts
the network. A forbidden write fails with `EPERM` even if the hook was bypassed.

Backends: macOS Seatbelt (`sandbox-exec`), Linux bubblewrap (`bwrap`).

Fail-closed where it matters: if the guard asks for enforcement and no backend
is available, `exec` refuses (exit 3) rather than run unprotected.

Related: `rabadon sandbox --check` (is a backend available?) and
`rabadon sandbox --print` (emit the compiled profile, run nothing).

Exit: `0`/passthrough of `<cmd>` · `2` nothing to run · `3` enforcement asked
but no backend.

```
rabadon exec -- npm run build
rabadon sandbox --check
rabadon sandbox --print
```

---

## `rabadon repair [dir] [--cmd "<check>"]`   [stable]

Close the repair loop. A caught red check -> `claude -p` proposes a fix in an
**isolated copy** -> the same check re-runs there. Green with test files
hash-unchanged -> the verified patch is **held** at `.rabadon/repair-<ts>.patch`
(never auto-applied). Fake or test-weakening fixes are rejected.

Needs the `claude` CLI (or `RABADON_CLAUDE_BIN`) as the proposer.

Flags: `--cmd "<check>"` (the deterministic check to run; otherwise inferred
from the test suite or the net's last red verdict) · `--timeout <sec>`
(proposer wall clock, default 240).

Exit: `0` held a patch, or the check was already green · `2` REPAIR_FAIL (still
red, test-tampered, or a zero-diff flake) · `3` no runnable check, no proposer,
or **the check resolves outside the isolated copy** · `4` FLAKY — the same check
answered differently on two runs of the same tree, so this run graded nothing.

**One run of a check is not a verdict.** Both decisions that can throw work away
are sampled twice. On the way in, a green entry run is confirmed before repair
goes home: green then red exits `4` instead of reporting nothing to repair — a
check that flakes green would otherwise drop a break still sitting in your tree.
On the way out, a red arbiter run is re-sampled before it may reject the
proposal: red twice is REPAIR_FAIL as before, but red then green is **held and
labelled `FLAKY`**, because a suite that flakes red once (expressjs/express
flaked red on 3 of 6 pristine runs) would otherwise destroy a correct,
source-only fix you already paid a proposer call for. A flaky hold is never
called `VERIFIED`, and the ledger carries its own reason (`flaky check: arbiter
samples disagree`) — never `check still red after proposal`, which would be a
false sentence written into a hash-chained record.

Exit `3` is what `pip install -e .` does: the editable install writes an
absolute path into a `.pth` in `site-packages`, the copy inherits it, and the
copy's interpreter imports **your** tree instead. repair refuses before it
copies anything, names the file, and records nothing — grading a proposal
against code it never touched is not a verdict in either direction. Same for an
absolute symlink back into the tree (`npm link`) and for a `bin/` shim your
check invokes by name. Give it a check that stands up inside a fresh copy:
`--cmd "PYTHONPATH=src python3 -m pytest"`.

```
rabadon repair
rabadon repair --cmd "npm test"
```

Apply a held patch yourself: `patch -p1 < .rabadon/repair-<ts>.patch`.

---

## `rabadon export --otlp [--days N]`   [stable]

Emit the ledger as OpenTelemetry OTLP/JSON traces on stdout: one trace per
session, refusals as ERROR spans, GenAI semantic-convention token attributes
where token counts exist. Drop it into Jaeger, Grafana Tempo, Honeycomb, or
Langfuse's OTLP endpoint.

Attributes on a priced event:

| attribute | from | note |
|---|---|---|
| `gen_ai.system` | — | `anthropic` |
| `gen_ai.request.model` | `model` | the tier that actually ran |
| `gen_ai.usage.input_tokens` | `in`, else `tokensIn` | |
| `gen_ai.usage.output_tokens` | `out`, else `tokensOut`, else `tokens` | the gate's Stop ledger writes `tokens` alone and its value *is* the session's cumulative output count — cumulative, so a backend must not sum it across spans |
| `rabadon.usd_e6` | `usd_e6` | micro-dollars, integer, the record |
| `rabadon.cost_usd` | `usd_e6` | USD double, a rendering of the same number |

Cost stays in rabadon's namespace on purpose: OpenTelemetry's GenAI conventions
define token counts and expect a backend to derive money from them, so there is
no `gen_ai.usage.cost` to fill and rabadon does not squat one.

Those key names are the ones `rabadon-gate` and `rabadon-loop` actually append
to the spool. Until 1 Aug 2026 the exporter read `tokensIn`/`tokensOut` — real
names, but they live in `.rabadon/state.json` and never on a spool line — so on
a ledger of 1366 token-bearing events, **zero** spans carried a `gen_ai.*`
attribute while this page advertised them. The suite was green because the
fixture was hand-written in the reader's key names. `native/export_test.sh`
arms 10 and 11 now build their fixtures by *running* the gate and the loop.

Drills are excluded here by the same four rules
`rabadon usage` uses (the emit tag, a `fleet-`/`doctor-`/`drill-` session id,
rabadon's own bench and demo pipes, and events inside a drill's 2-minute
window), one shared predicate, so the refusal count you export is the refusal
count you read locally. Nothing leaves the machine unless you pipe it out.

Flags: `--otlp` (the only format today, required) · `--days N`.

Exit: `0` · `2` `--otlp` not passed.

```
rabadon export --otlp | curl -s localhost:4318/v1/traces \
  -H 'content-type: application/json' --data-binary @-
```

---

## `rabadon lint [dir]`   [stable]

Validate `guard.json` and refuse to certify a rule the gate will ignore. Run
this before trusting a hand-edited guard. (`init` runs it for you.)

Checked:

- unknown **top-level** keys (`protectedPathz` for `protectedPaths`),
- unknown keys **inside a rule** (`denies` for `deny`, `matches` for `match`) —
  a rule the gate silently skips while it reads as law,
- a rule with **no pattern**, or an empty one — it matches nothing,
- every `deny` and `match` regex actually compiles.

Legal beside the pattern: `id`, `why`, and the keys rabadon writes itself
(`authoredBy` + `incidentAt` on incident-authored rules, `source` on rules from
`pack import`). Anything else in a rule object is dead weight the gate never
reads, so lint names it.

Exit: `0` valid · non-zero invalid.

```
rabadon lint
```

```
rabadon lint: rule "no-wrangler-deploy" in bash has unknown key "denies" (typo for "deny"? the gate ignores it)
rabadon lint: rule "no-wrangler-deploy" in bash has no "deny" pattern — it matches nothing, the gate skips it
rabadon lint: 2 problem(s) — fix them or the gate silently ignores those rules.
```

---

## `rabadon remove [dir] [--purge] [--global]`   [stable]

Alias: `rabadon uninstall`. Strip exactly rabadon's hooks (and a rabadon-owned
statusLine) from `settings.json`, leaving everything else in place. Backs up
before it edits.

Flags: `--purge` (also delete the `.rabadon/` directory) · `--global` (target
`~/.claude/settings.json`).

The `~/.rabadon` spool is yours and is left in place.

Exit: `0`.

```
rabadon remove
rabadon remove --purge --global
```

See [uninstall.md](uninstall.md).

---

## `rabadon doctor`   [stable]

Health check: native binaries built, binary/package version lockstep, kernel
sandbox backend, global hook health (every hook command points at a file that
exists), `claude` CLI presence, spool size and retention.

The binary check knows what the core is by reading the `Makefile` — every target
`make all` produces, plus every explicit `native/rabadon-*` rule — so a binary
added to the build is a binary doctor checks for, with nothing to keep in sync.
Any that are absent are listed by name: an absent binary is a command that fails
when you run it, not when you install it, and a partial source build (`make`
stopped on one target) still reports install success. If the `Makefile` cannot
be read, doctor says so and refuses to certify rather than reporting green.

Exit: `0` all green · `1` at least one thing to look at.

```
rabadon doctor
```

---

## `rabadon watch`   [building]

Live terminal view over the local unix socket. Run it in one terminal while your
pipelines run elsewhere.

```
rabadon watch
```

---

## `rabadon ui`   [building — stub]

Local dashboard on `127.0.0.1:8484`. **This is a stub** — it is not a finished
surface. Use `rabadon usage`, `rabadon report`, and `rabadon export --otlp` for
real reporting today.

```
rabadon ui
```
