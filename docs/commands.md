# rabadon commands

Every verb of the `rabadon` CLI. The CLI is a thin dispatcher
(`native/rabadon-cli.sh`): recognized verbs go straight to a native binary,
lifecycle verbs (`init`/`remove`/`doctor`) go to `hooks/manage.mjs`.

Maturity tags: **[stable]** = shipping and tested on this machine.
**[building]** = code exists, not yet complete — do not rely on it.

Common exit-code convention: `0` success, `1` an error or a failed check, `2`
a refusal or bad usage, `3` a precondition missing (no backend, no proposer, no
runnable check). Specific codes noted per verb.

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

Exit: `0` held a verified patch, or the check was already green · `2`
REPAIR_FAIL (still red, test-tampered, or a zero-diff flake) · `3` no runnable
check or no proposer.

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
Langfuse's OTLP endpoint. Drills are excluded here too — nothing leaves the
machine unless you pipe it out.

Flags: `--otlp` (the only format today, required) · `--days N`.

Exit: `0` · `2` `--otlp` not passed.

```
rabadon export --otlp | curl -s localhost:4318/v1/traces \
  -H 'content-type: application/json' --data-binary @-
```

---

## `rabadon lint [dir]`   [stable]

Validate `guard.json`: unknown keys, uncompilable regex. Run this before
trusting a hand-edited guard. (`init` runs it for you.)

Exit: `0` valid · non-zero invalid.

```
rabadon lint
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
