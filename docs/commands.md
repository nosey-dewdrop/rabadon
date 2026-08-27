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
through this CLI and listed on the help screen, because installing rabadon puts
exactly one file onto your PATH — the dispatcher — so a binary it does not name
is a binary nobody can run.

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

### The six silencers — and why `off` is not one of them

`off` is **watch**, not silence: the rules still run and the ledger still fills.
There is a fourth state below all three modes, **SILENT**, where the gate
returns exit `0` immediately — no rule is evaluated, no event is recorded,
nothing is printed. Six things put it there, and any one of them is enough:

| what | where | what it does | the one command that removes it |
|---|---|---|---|
| `RABADON_OFF=1` | environment variable | silences this process and every child it spawns (rabadon sets it on its own model subprocesses, so the supervisor never supervises itself) | `unset RABADON_OFF` |
| `.rabadon/off` | `<project>/.rabadon/off` | silences the gate for that project tree, for every shell and every user, until the file is deleted | `rm <project>/.rabadon/off` |
| `silent` | `$RABADON_DIR/silent` | silences the gate on this machine, in every project. `rabadon-gate --silent` writes this file AND `silent` into the mode file, so deleting the file alone leaves the mode behind | `rabadon off` |
| `mode = silent` | `$RABADON_DIR/mode` | the machine mode layer reading `silent` — it silences every project on this machine | `rabadon off` |
| `.rabadon/mode = silent` | `<project>/.rabadon/mode` | the project mode layer reading `silent` — it silences that project tree | `rm <project>/.rabadon/mode` |
| `RABADON_MODE=silent` | environment variable | the environment mode layer reading `silent` — it silences this shell and every child it spawns | `unset RABADON_MODE` |

Read that table as the exit door it is: an agent guard that cannot be switched
off is a guard people rip out instead. But the door has to be labelled, because
a silencer you do not know about is indistinguishable from a broken guard. That
is why `rabadon status` prints the silencer in force by name, by location, and
with the row's own command — the names in the first column are the names the
screen prints.

<!-- rabadon:claims-begin -->
Corrected on 2026-08-26. Three sentences that stood in this section until that
day were measured false against the shipped gate and are quoted below beside
what replaced them. Nothing here is prose alone: every claim line in this block
is bound to a check in `docs/claims.tsv` that `native/docs_truth_test.sh` runs
against the real binary on every `make test`.

Was: "`rabadon off` does NOT remove any of these." Measured false, one row at a
time:

- `rabadon off` deletes `$RABADON_DIR/silent` and writes `watch` over a
  `silent` mode file, so it does lift rows three and four by itself.
- `rabadon off` is not a way out of `RABADON_OFF=1` — row one survives it.
- `rabadon off` is not a way out of `<project>/.rabadon/off` — row two survives.
- `rabadon off` is not a way out of `<project>/.rabadon/mode` — row five too.
- `rabadon off` is not a way out of `RABADON_MODE=silent` — nor row six.

Was: "with a silencer present, `rabadon on` will report ENFORCE."
Measured false: under a silencer `rabadon on` will report SILENT.

Was: "`rabadon status` reports the mode, not the silencer."
Measured false: `rabadon status` reports the silencer as well — by name, by
location, and with the one command that lifts it.

The sentence that was right and stays: `rabadon off` is not silence. After it
the gate still runs every rule and still records what it would have stopped.

The table above always lists every silencer the binary can report; today that
is six rows, and the suite goes red the day the two sets differ.
<!-- rabadon:claims-end -->

Measured on 2026-08-26 against the shipped gate: with any one of the six in
place, a `git push --force origin main` event that exits `2` with
`baseline-force-push` on a clean tree exits `0` with no output and writes
nothing to the ledger. Running the row's own command restores the refusal on
the very next event; there is no cache and no restart. Reproduce every row of
the table with `bash native/docs_truth_test.sh`, which sets each one up in a
throwaway project and runs the command printed beside it.

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

## `rabadon usage [--days N] [--project P] [--full] [--json] [--signals]`   [stable]

Alias: `rabadon stats`. The ledger. Refusals grouped by rule id with each rule's
reason, plus headline totals. Drills and self-tests are excluded from every
number.

Flags: `--days N` (window, default 7) · `--project P` (one project only) ·
`--full` (list every catch with timestamp and detail) · `--json` (machine
output).

Exit: `0` when the ledger rendered — including a genuinely empty ledger, which
is a real answer and comes with the onboarding block. `1` when `--project P`
matched nothing: the message names `P`, the spool and the window it searched,
lists the projects that ARE in the window, and stdout stays empty on all three
renderers, so a script asking "how many catches for P this week" can tell a
wrong name apart from a clean week. `2` on an unknown flag, or on a `--days`
that is negative — a window cannot end before it starts.

```
rabadon usage --days 30
rabadon usage --project my-project --full
rabadon usage --json
```

### `--signals` — a different source, not a different rendering

`--signals` reads the per-session move rings under `$RABADON_DIR/sessions`
instead of the refusal ledger, and replays the five R2 detectors (`repeat`,
`oscillation`, `root_migration`, `scope_drift`, `green_redefined`) over every
surviving move. Those detectors are silent: on 2026-08-26 none of them refused
anything and none of them reached a decision, and the screen says so in its
second line. It is read-only — measured the same day, the file and mtime set of
`$RABADON_DIR` hashes the same before and after the run
(`reports/kosu/RAPOR/f2-2-readonly.out`).

Three things the screen prints that a reader has to be able to place:

- **LOSS.** Each ring keeps the newest 200 moves of its session while the ring
  header counts every move ever appended. The difference is moves that were
  recorded and are gone, and the screen prints it as a `LOSS:` block with the
  count and the ring file behind it. Every number under it is over the moves
  that survived, not over the moves that happened. On the frozen corpus of
  2026-08-26 that was 527 moves on disk against a header count of 654 — 127
  gone, all of them from one long session's overflowed ring.
- **`NOT MEASURED (n=0)`.** A detector with no samples renders as this plus the
  corpus fact behind its zero (how long the longest identical run was, how many
  times the most-edited file was edited, and so on). Zero samples is not a
  result and is not rendered as one; four of the five detectors read that way on
  the frozen corpus.
- **`n` with the session file behind it.** A detector that did fire prints a raw
  count and the count of those samples a human has labelled. With no labels
  there is no rate, and the screen prints no rate: raw counts only.

Nothing on this screen is a counterfactual. It reports what rabadon wrote, not
what would have happened without it.

Exit: `0` when the screen rendered, including an empty corpus, which prints that
it could not measure rather than printing zeros. `2` when `--signals` is combined
with a renderer flag such as `--json`, which is refused rather than silently
ignored — there is no JSON form of this screen.

```
rabadon usage --signals
```

Locked by `native/signals_screen_test.sh` (38 assertions), which drives the
binary against a synthetic ring that overflows on purpose, so a screen that
hides a loss falls red.

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

A refusal is a run too. `rabadon-gate` and `rabadon exec` write one run per
refusal, and it holds exactly two events — the failed check and the STOP — with
no step ever announced, because the refusal returns before the step starts. That
run renders as its caught step: the tool that was stopped, the rule id that
fired, what the rule said, `CAUGHT 1`, and `verdict: BLOCKED`. Nothing was
proposed and nothing was priced, so no repair, no cost and no model is printed —
the header names the surface the refusal came through instead.

A WATCH verdict is not a catch and is never counted as one. `rabadon off` records
what the arbiter WOULD have stopped and lets the command run; that renders as
`WOULD BLOCK`, on its own line, against `CAUGHT 0` — the same split `rabadon
usage` keeps between `refused` and `wouldRefuse`.

The `saved:` line is the only sentence here that talks about steps which did NOT
run, so every number in it is measured off the run rather than assumed from the
catch. The steps it says NEVER ran are the plan's declared count minus the steps
the run actually started — never "everything after the catch", because the run
may have gone on for several steps before it stopped. The steps it says ran on a
clean base are the ones that started after the catch. A catch on the run's last
step has no range at all and prints none. A rejected repair followed by an
accepted one is not a STOP; it is reported as both. And a run whose ledger holds
no `REPAIR_FAIL` for a step never prints a refused fake fix for it, exactly as a
run with `REPAIRED 0` never says repaired.

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

Beside each day file sits a `.head` sidecar committing two facts under the same
lock: the last hash **and how many chained lines the file must have**. A file
carrying lines but no sidecar — a legacy writer, or a day older than chaining —
is UNVERIFIABLE and reported as such, never folded into the clean count. "I do
not know" must not read as "clean", which is why there are three exits and not
two. (This page said "tolerated" and listed two exits for a fortnight after the
code stopped doing that.)

Flags: `--days N` (window, default 7).

Exit: `0` every file verified against its sidecar · `1` at least one broken link
(tamper) · `2` nothing broken, but at least one file cannot be verified.

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
(proposer wall clock, default 240) · `--approve` (run the repair the arm asked
about in `ask` mode) · `--apply` (apply the newest held patch — **the only thing
in rabadon that edits your tree**, and a human types it).

**The arm also starts itself, under a policy you set once.** `rabadon init`
writes `repair.mode` into `$RABADON_DIR/config.json` and never asks again:

| mode | what happens when the trigger fires |
| --- | --- |
| `ask` (default) | one line on stderr and a `REPAIR_ASK` ledger event. Nothing runs until `rabadon repair --approve`. |
| `auto-propose` | runs without asking, and **never touches your tree** — the patch waits at `.rabadon/repair-<ts>.patch` for `rabadon repair --apply`. |
| `off` | the arm is disabled. The signals still reach the ledger. |

A value that is none of those three is read as `off`, and said out loud: a
policy nobody can parse is not permission to spend.

The trigger is both halves of one sentence, and one half is not enough: the
`root_migration` signal — **the same error out of a third different move** —
*and* the injections did not help, meaning R4 has already answered that signal
with everything it had, at least one of those answers reached the agent, and the
error has since come out of three more different moves. Firing on the first
sighting would bill for what an injection fixes for free. It fires at most once
per session, and the proposer call it makes is booked on the ledger as a `COST`
carrying characters in, characters out, and a token figure marked
`"estimated":1`.

The text handed to the proposer names **files, never lines** (Law 2): every
`file.py:44`, `line 3` and `L44` is stripped out of the whole assembled prompt,
and the files the failing output names — the ones that actually exist in the
tree — are listed instead. The arbiter's raw output is framed by rabadon's own
words, never forwarded on its own.

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
session, one row per tool call, refusals as ERROR spans, GenAI
semantic-convention token attributes where token counts exist. Drop it into
Jaeger, Grafana Tempo, Honeycomb, or Langfuse's OTLP endpoint.

**What a trace is.** The session id the hook was handed, which the gate writes
as `sess`. It used to be `pipe` — spelled `<project>:session` and not one: it is
the *directory*. 227 of them cover nine days of the author's machine and
`stitchu:session` alone spans 214.1 hours, because every session and every
subagent that ever ran in that folder wrote into it. That shipped as a single
24,056-span "trace", which no viewer renders as anything. A line with no session
id still falls back to its pipe, and one with neither to the file it was read
from; every span says which of the three it got in
`rabadon.export.trace_basis`, so a trace that is a folder's history cannot pass
for a session.

**What a span is.** One event — every event. A tool call, though, is *two*
events: `STEP_START` when the gate admits it and `STEP_OK` when it returns. Both
hooks are handed the same `tool_use_id`, which the gate writes as `call`, so the
`STEP_OK` becomes the interval `[START.ts, OK.ts]` and the `STEP_START` becomes
its child (`parentSpanId`) — one top-level row per call, with nothing deleted to
get it. The interval is *gate-admitted to returned*, so a call that waited on a
human approval carries that wait: it is how long the call held the session, not
how long the tool computed. A pair is refused, and both ends stay honest points,
when either end is undated, when the OK predates the START, when the two ends
are in different sessions, or when one end never arrived. `rabadon.span.basis`
says `pair` or `dur_ms` on anything that got a width, and
`rabadon.span.start_source` names the ledger line the start was read off, so
the join is checkable against the bytes.

This only works forward: the ids arrived on 4 August 2026 and no earlier line
has them. On the 86,881 lines already on disk, zero carry `call`, so those spans
are exactly what they were.

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

Also strips rabadon's entries from `.cursor/hooks.json` (since 2026-08-26 —
before that, Cursor wiring was written by `init` and never removed). Your own
Cursor hooks are left alone; a file that held only rabadon's entries is deleted.

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

---

## Environment

rabadon is deterministic by default: no variable below needs to be set for any
law to hold, and with none of them set nothing calls a model.

| variable | default | effect |
|---|---|---|
| `RABADON_JUDGE` | unset = off | `1` enables the drift judge and the red-suite diagnosis. `0` disables both and wins over the guard key. Also settable per project as `"judge": true` in `.rabadon/guard.json`. |
| `RABADON_JUDGE_MODEL` | `claude-haiku-4-5` | model for the drift verdict |
| `RABADON_DIAGNOSE_MODEL` | account default | model for the red-suite diagnosis |
| `RABADON_MODEL` | unset | proposer model for `do` / `loop` / `repair`. **Not** read by the gate — one name for two jobs sends the judge somewhere nobody asked for. |
| `RABADON_TIERS` | unset | cheap-first tier ladder for `loop`, e.g. `haiku,opus` |
| `RABADON_CLAUDE_BIN` | `claude` | proposer binary for `repair` |
| `RABADON_DIR` | `~/.rabadon` | spool + state root. Keep it shallow: the live watcher socket is `$RABADON_DIR/rabadon.sock`, and `sun_path` caps a unix socket path at 104 bytes on macOS / 108 on Linux. Over the cap, rabadon says so on stderr and writes to the spool only — judging is unaffected. |
| `RABADON_LENS_DIR` | `~/.claude/projects` | transcript source for `lens` |
| `RABADON_NOTIFY` | on | `0` silences desktop notifications |
| `RABADON_OFF` | unset | `1` makes the gate a no-op for this process and its children (set on every model subprocess rabadon spawns, so the supervisor never supervises itself). One of six silencers; see [the six silencers](#the-six-silencers--and-why-off-is-not-one-of-them) for the other five and the one command that lifts each |
| `RABADON_DRILL` | unset | `1` tags emitted events as self-test, excluded from every count |

When the judge or the diagnosis does run, each call writes one `LLM_CALL` event
carrying `purpose`, `model`, `ms` and `ok` — failures included. There is no USD
on that event on purpose: `claude -p --output-format text` reports no usage, so
the cost is not knowable at that line. It comes from the transcripts instead,
via `rabadon lens`.
