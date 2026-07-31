# rabadon

Supervise your coding agent. rabadon stands at the gate of a live Claude Code session and enforces your project's own laws deterministically, **before** every action — then keeps a tamper-evident record of everything it did.

A hook is advice. rabadon is the layer that also makes the advice **hold**: the deterministic gate refuses the force-push before it rewrites history, stops the loop on its third identical spin, refuses the assertion-strip while the suite is red, holds the untested push. When you ask for it, the same rules compile into a kernel sandbox, so a forbidden write fails with `EPERM` even if the gate was bypassed. Every event is chained by SHA-256 to the one before it, so the ledger you show people can be verified, not just trusted.

Everything is local, by law: events append to `~/.rabadon/spool/` on your machine over a unix socket. No account, no upload, nothing leaves.

## Install

```sh
npm i -g rabadon          # prebuilt native core for macOS/Linux (source-build fallback)

cd your-project
rabadon init              # authors guard rules from your law files (CLAUDE.md / RULES.md),
                          # or writes a safe baseline; merges hooks into your existing
                          # .claude/settings.json (backed up, never clobbered)
rabadon drill             # see a real refusal in 30 seconds, without waiting for an incident
claude                    # work normally — the session is supervised
rabadon usage             # the ledger: what was caught, backed by timestamped events
```

macOS + Linux, Node ≥ 18. The core is ~5k lines of dependency-free C++; prebuilt binaries ship per platform, and if none matches, the postinstall builds from source with `clang++`/`g++` (`rabadon doctor` diagnoses either way). Full walkthrough: [docs/quickstart.md](docs/quickstart.md).

## A real catch, verbatim

From the author's own week, replayable from the spool — a mid-session `wrangler deploy` refused by a project's own deny rule:

```
{"ts":1785072099372,"pipe":"stitchu:session","ev":"CHECK_FAIL","step":"Bash",
 "fails":[{"check":"no-wrangler-deploy","why":"command matched deny rule: cd backend && npx wrangler deploy —
  ENV.md Deploy: wrangler deploy is the human's step; the agent must never deploy or claim the worker is live."}]}
```

`rabadon usage` turns a week of those into the only sales artifact that matters — what it caught, in your repo, on your work:

```
rabadon usage — last 7 day(s) · local, nothing leaves this machine

  61 refused before they happened · 10,564 actions gated · 3 repairs accepted

  stitchu                                            last event: today 15:56
    actions gated             3,330
    caught before happening      43
      13x  push-gate           code was edited after the last passing test run
       6x  no-wrangler-deploy  deploys go through CI, never from a live session
       5x  no-rm-rf-outside    recursive delete outside the project tree is unrecoverable
       2x  loop-stop           the same command a 3rd time with no code change in between
    checks failed (caught)       98   (loops stopped: 2)
    repairs accepted              3

  (312 event(s) from rabadon's own drills and self-tests — excluded from every number above)
```

The drill exclusion is load-bearing: a tool that counts its own self-tests as catches is worthless, so rabadon tags them at emit and never counts them. That honesty is the brand.

## The built-in laws

On every session, no configuration:

- **loop-stop** — the same command run 3× with no code change in between is a loop, not progress; refused.
- **test-tamper** — while the suite is red, an edit that weakens a test (skip added, assertions removed) is refused. Fix the code, not the thermometer.
- **push gate** — if your laws demand green tests before a push, rabadon runs the suite itself at push time and decides on the real result, never on a claim.
- **scope fan-out** — a task spreading across a 5th top-level directory is challenged once.

Plus your own laws, authored into `.rabadon/guard.json` (deny rules, protected paths, budgets) — see [docs/guard.md](docs/guard.md). Escape hatches are first-class: `rabadon off` pauses everything, and every refusal names its rule id so you can disable exactly that one (`"disabled": ["rule-id"]`).

## What makes it more than a hook

**Kernel enforcement — `rabadon exec`.** Protected paths and network denies from `guard.json` compile into an OS sandbox (macOS Seatbelt, Linux bubblewrap). A forbidden write is refused by the kernel with `EPERM` even when nothing consulted rabadon first — a subprocess, an MCP tool, a shell one-liner that dodged the matcher. If a fence is asked for and no backend exists, `exec` refuses to run rather than run unprotected. This is the hard boundary a hook alone cannot draw. Scope and bypass vectors are stated plainly in [docs/threat-model.md](docs/threat-model.md).

**Tamper-evident ledger — `rabadon audit`.** Every spool event carries `prev` = the SHA-256 of the line before it. `rabadon audit` re-walks the chain and names any broken link by file and line; edit, drop, reorder or truncate a single event and the verdict flips to a break. A trust product's ledger should be "verify it yourself," not "believe me." `rabadon replay` renders the verified timeline.

**Real repair — `rabadon repair`.** When a deterministic check goes red, `claude -p` proposes a fix **in an isolated copy** of the repo; the same check re-runs; a fix that turns it green *and* leaves every hash-locked test file untouched produces a **held patch** (`.rabadon/repair-<ts>.patch`) — reviewed and applied by you, never silently. A fix that games the check (weakens a test) is rejected. The arbiter is the project's own test suite, not an LLM judging itself — the un-gameable kernel.

**Speaks OpenTelemetry — `rabadon export`.** `rabadon export --otlp` emits the ledger as OTLP/JSON traces (one trace per session, refusals as ERROR spans, GenAI-semconv token attributes) so any backend — Jaeger, Grafana Tempo, Langfuse — renders a rabadon session. Observation is a solved, standardized problem; rabadon exports to the standard instead of reinventing a dashboard.

## Where it sits

| Tool | Can observe? | Can **stop** a bad action? | Can **repair** it? | Can **prove** the record? | Kernel enforcement? |
|---|---|---|---|---|---|
| Langfuse / Braintrust | yes | no — passive by design | no | no | no |
| Guardrails AI / Instructor | — | one structured output | re-ask, single output | no | no |
| **rabadon** | **yes (OTLP export)** | **yes — inline, pre-spend, fail-closed** | **yes — re-verified, held, un-gameable** | **yes — hash-chained audit** | **yes — Seatbelt / bwrap** |

Observation is table stakes. What nobody else in this class does: supervise a live coding-agent session, hold the enforcement down to the kernel, close the repair loop with the project's own tests as the arbiter, and hand you a ledger you can verify.

## The engine underneath

The session guard is one binding of a smaller thing: a runtime that runs work in bounded, checked, repairable steps. The JavaScript API (`pipeline()`, `session().wrap()`) is documented in [SPEC.md](SPEC.md); any runtime that can execute a subprocess can implement the same gate contract.

## Commands

`init` · `on`/`off`/`status` · `usage` (`stats`) · `report` · `drill` · `audit` · `replay` · `exec` · `repair` · `export` · `lint` · `doctor` · `remove` · `watch`. Full reference: [docs/commands.md](docs/commands.md). How the hooks, spool and modes fit together: [docs/how-it-works.md](docs/how-it-works.md).

## Prove it yourself

```sh
make && make test    # the native core: 20 suites, incl. kernel-EPERM, chain-tamper,
                     # and the caught→propose→re-verify repair loop, all green
npm test             # the JS surface: install/merge, wrap, store, ui
```

## Status

Building in public. **Proven, by running code committed here:** the session gate (deny rules, loop-stop, test-tamper, push gate) through the real binary; kernel-enforced protected paths (real OS `EPERM`); the hash-chained ledger with tamper detection; the session repair loop (caught → proposed in isolation → re-verified → held patch, fake fixes rejected); OTLP export; portable `npm i -g` install with prebuilt binaries; clean `init`/`remove`/`doctor`. **[building]:** the local dashboard (`rabadon ui`) is a stub — `rabadon watch` is the live surface today. **Honest gap:** the repair loop is proven on scripted and isolated real repos; the first repair on a stranger's live project is the next proof this README will cite. Not yet published to npm — the release workflow and provenance are wired and waiting on the maintainer's `npm publish`.
