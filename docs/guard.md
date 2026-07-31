# guard.json — the project's law

`guard.json` is the machine-checkable law for one project. It lives at
`<project>/.rabadon/guard.json`. Every rule the gate enforces comes from this
file (plus a few built-in structural rules). `rabadon init` authors a starting
guard for you — **you must review it before you trust it.**

## The schema

```json
{
  "project": "name",
  "bash": [
    { "id": "kebab-id", "deny": "<regex over the full command>", "why": "<one line>" }
  ],
  "protectedPaths": [
    { "id": "kebab-id", "match": "<regex over the file path>", "why": "<one line>" }
  ],
  "codePaths":       ["<regex: what counts as code>"],
  "testPaths":       ["<regex: what counts as a test file>"],
  "testCommand":     "<regex matching a test invocation>",
  "testPassPattern": "<regex present in output ONLY when fully green>",
  "pushGate":        { "why": "<the law>", "run": "<literal command rabadon runs itself>", "timeoutSec": 600 },
  "network":         "deny",
  "disabled":        ["rule-id"]
}
```

### Field by field

- **`project`** — the name shown in `rabadon usage`. Cosmetic.
- **`bash`** — deny rules. Each `deny` is a regex matched against the **full
  command** the agent is about to run. A match refuses the action (enforce) or
  records a would-block (watch). `id` names the rule in every refusal and in the
  ledger; `why` is the one-line reason written back to the agent.
- **`protectedPaths`** — path rules. Each `match` is a regex matched against the
  **file path** of a write/edit. A match refuses the write. These also become
  kernel-enforced under `rabadon exec` (see below).
- **`codePaths`** — regexes for what counts as source code. This arms the push
  gate (an edit under a code path is what a push is gating).
- **`testPaths`** — regexes for what counts as a test file. This arms the
  test-tamper detector: while the suite is red, an edit that weakens a test file
  is refused.
- **`testCommand`** — a regex matching a test invocation.
- **`testPassPattern`** — a regex that appears in test output **only** when the
  suite is fully green. rabadon decides on the real output, never on a claim.
- **`pushGate`** — if `run` is declared, rabadon executes that literal command
  itself at push time and decides on the real result. `why` is the law,
  `timeoutSec` bounds it.
- **`network`** — set to `"deny"` to cut the network for commands run under
  `rabadon exec`.
- **`disabled`** — a list of rule ids to switch off (see below).

## Regex gotchas?

- **Matched against the full string.** A `bash` deny is tested against the
  entire command line, not a token. A `protectedPaths` match is tested against
  the whole file path.
- **ECMAScript, case-insensitive.** Rules compile as ECMAScript regex and match
  case-insensitively.
- **JSON needs doubled backslashes.** A regex `\s` must be written `"\\s"` in
  JSON; `\.` must be `"\\."`. A single backslash is a JSON escape and will
  either error or silently change your pattern. When in doubt run `rabadon lint`
  — it flags uncompilable regex.
- **Anchor path rules.** `protectedPaths` matches are usually anchored with `^`
  and `$` so `"^src/core/.*"` fences the subtree without matching
  `vendor/src/core`.

## Worked examples

### A deny rule (bash)

Refuse any force-push to `main` or `master`:

```json
{ "id": "no-force-push-main",
  "deny": "git\\s+push[^|;&]*(--force|-f)\\b[^|;&]*\\b(main|master)\\b",
  "why": "force-pushing a shared branch destroys history" }
```

`\\s+` is one-or-more whitespace; `[^|;&]*` keeps the match inside a single
command (not across a pipe or `;`); `\\b` are word boundaries.

### A protectedPaths rule

Freeze a file that must never be edited by the agent:

```json
{ "id": "anti-path-frozen",
  "match": "^(bin/rabadon\\.mjs|index\\.html)$",
  "why": "these files are frozen — edits go through review, not the agent" }
```

Under `rabadon exec`, the literal prefix of this rule (`bin/rabadon.mjs`,
`index.html`) is also fenced by the kernel — a write fails with `EPERM`.

### A pushGate with testPassPattern

Hold every push until the real suite is green:

```json
{
  "testCommand": "npm\\s+test",
  "testPassPattern": "Tests:\\s+\\d+\\s+passed",
  "pushGate": {
    "why": "no push while the suite is red",
    "run": "npm test",
    "timeoutSec": 600
  }
}
```

At push time rabadon runs `npm test` itself, checks the real output against
`testPassPattern`, and refuses the push if it is not green. It never trusts the
agent's claim that tests pass.

## Disabling one rule

Add its `id` to `disabled[]`. The rule stays documented in the file but stops
firing:

```json
"disabled": ["no-force-push-main"]
```

Every refusal message names its rule id and this override path, so the agent (or
you) always knows exactly which rule fired and how to switch it off. Prefer
disabling one rule over turning the whole gate off.

## How the guard gets authored?

- **`rabadon init`** authors it. With the `claude` CLI present, it writes
  project-specific rules; with `--no-llm` or no `claude` CLI it writes a
  baseline of four rules (force-push to a shared branch, `rm -rf` outside the
  tree, hard-reset of main, hook bypass). It then lints the result and refuses
  to install hooks if the guard is invalid.
- The authored guard is a **draft**. An LLM wrote it or a generic baseline
  seeded it; either way **read it**. You are the one who knows what your project
  must protect. Open `.rabadon/guard.json`, check every deny regex and every
  protected path, tighten what is loose, remove what is wrong, and run
  `rabadon lint`.

## protectedPaths and the kernel

`protectedPaths` are enforced two ways:

- The **hook** checks every write the agent asks about, using the full regex.
- Under **`rabadon exec`**, the same paths become an OS policy: the kernel makes
  them read-only, so a forbidden write fails with `EPERM` even if the write came
  from a subprocess the hook never saw.

One caveat: the kernel can only fence a path with a literal prefix. A pure-regex
match with no literal head (starting with a metacharacter) cannot be turned into
a kernel fence — `rabadon exec` reports which rules it skipped, and the hook
still checks them. See [threat-model.md](threat-model.md).
