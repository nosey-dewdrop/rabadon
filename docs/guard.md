# guard.json — the project's law

`guard.json` is the machine-checkable law for one project. It lives at
`<project>/.rabadon/guard.json`. `rabadon init` authors a starting guard for
you — **you must review it before you trust it.**

## The floor you get without this file

Three laws are compiled into the gate and hold in any repo, with no
`guard.json` at all. `guard.json` extends this floor; it does not create it.

| id | refuses |
| --- | --- |
| `baseline-force-push` | a force-push to a shared branch (`main`, `master`, `trunk`, `develop`) — `--force`, `-f` and the `+refspec` form alike. `--force-with-lease` is the safe form and passes. Pushing `--force` to your own branch passes. |
| `baseline-rm-rf-outside` | a recursive `rm` whose target lands outside the project tree **and** outside the system temp area. The target is **resolved**, not pattern-matched: `..`, `~` and a symlinked parent land where they really land, and a wildcard or a brace is expanded the way a shell expands it *before* it is judged — `rm -rf /tmp/*/../../Users/you/work` is refused because every word it expands to leaves the temp area, while `rm -rf /tmp/build-*/out` passes. `rm -rf ./build` and `rm -rf node_modules` pass. |
| `baseline-hard-reset` | `git reset --hard` onto a shared branch. `git reset --hard HEAD~1` passes. |

Each is judged per command segment (`&&`, `||`, `;`, `|`, newline) after
parsing, so `npm test && git push origin feature/x` is two commands and
`echo "git push --force origin main"` is an echo. Silence any of them by id:

```json
{ "disabled": ["baseline-force-push"] }
```

Your rules run **first**, so a refusal carries your id and your reason; the
baseline is the backstop underneath. What it deliberately does not do: an
operand only a shell can resolve (`$VAR`, `$(cmd)`) is not guessed at — see
[threat-model.md](threat-model.md).

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
- **A rule with no `deny` is not a rule.** The gate reads `deny` in `bash[]` and
  `match` in `protectedPaths[]` and nothing else. Misspell it, or put a `match`
  in `bash[]`, and the object is still valid JSON with an id and a why — it just
  matches nothing and the gate allows the command. `rabadon lint` refuses to
  certify a guard containing one, and names the rule.

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
- **Lint is the trust step, so it is checked to the key.** An LLM writing
  `"denies"` for `"deny"` costs one letter and produces a rule that reads as
  enforced and enforces nothing — and `init` decides whether to install the
  hooks on lint's verdict. Lint therefore reads inside each rule object, not
  just the top level: an unrecognised key, or a missing pattern, is a non-zero
  exit naming the rule. Held by `native/guard_lint_test.sh`, which also pins the
  other half — a guard that is genuinely fine must still pass, or the first
  false alarm teaches you to skip the step.

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
