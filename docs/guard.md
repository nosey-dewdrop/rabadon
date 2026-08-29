# guard.json — the project's law

`guard.json` is the machine-checkable law for one project. It lives at
`<project>/.rabadon/guard.json`. `rabadon init` authors a starting guard for
you — **you must review it before you trust it.**

## The floor you get without this file

These laws are compiled into the gate and hold in any repo, with no
`guard.json` at all. `guard.json` extends this floor; it does not create it.

| id | refuses |
| --- | --- |
| `baseline-force-push` | a force-push to a shared branch (`main`, `master`, `trunk`, `develop`) — `--force`, `-f`, a bundled short cluster carrying `f` (`-fq`) and the `+refspec` form alike. `--force-with-lease` is the safe form and passes. Pushing `--force` to your own branch passes. |
| `baseline-rm-rf-outside` | a recursive `rm` whose target lands outside the project tree **and** outside the system temp area. The target is **resolved**, not pattern-matched: `..`, `~` and a symlinked parent land where they really land, and a wildcard or a brace is expanded the way a shell expands it *before* it is judged — `rm -rf /tmp/*/../../Users/you/work` is refused because every word it expands to leaves the temp area, while `rm -rf /tmp/build-*/out` passes. The temp carve-out is **your** scratch, not the shared root's contents: under `/tmp`, `/var/tmp` or `$TMPDIR` the first component of the target must be a name you wrote, so `rm -rf /tmp/scratch-*` and `rm -rf /tmp/proj-out/*` pass while `rm -rf /tmp/*`, `rm -rf /tmp/*.log` and `rm -rf /tmp/*/x` are refused — they name another session's mktemp tree as surely as your own. `$TMPDIR` is read from the environment, which is the one input an agent writes for itself, so a root named there is honoured only when it lands inside the machine's real temp area (`/tmp`, `/var/tmp`, `/var/folders`) and not under `$HOME`: `TMPDIR=/usr/local rm -rf /usr/local/lib` and `TMPDIR=/srv rm -rf /srv/www` are refused, because an assignment does not make a directory disposable. The cost, stated: an unusual `$TMPDIR` such as `/run/user/1000` is no longer read as scratch, and a recursive delete there is refused when it is also outside the project tree — silence `baseline-rm-rf-outside` by id if that is your setup. `rm -rf ./build` and `rm -rf node_modules` pass. |
| `baseline-branch-delete` | a push that **removes** a shared branch from the remote: the empty-source refspec (`git push origin :main`, `git push origin :refs/heads/main`), `--delete` and `-d`. A deletion is not a force-push and does not carry `-f`, which is how it walked past both the compiled law and the `--force|-f` deny regex most projects write. It has its own id on purpose: a repo that silenced `baseline-force-push` because one person rewrites their own trunk has not agreed to that trunk being deleted, and a force-push replaces history other people already have while a deletion removes the branch and every commit reachable only from it, with no remote reflog to walk back through. Deleting a branch you own is ordinary work and passes: `git push origin :feature/x`, `git push --delete origin my-branch`. So does deleting a tag (`git push origin :refs/tags/nightly`) and a branch merely named after one (`:main-backup`). |
| `baseline-hard-reset` | `git reset --hard` onto a shared branch. `git reset --hard HEAD~1` passes. |
| `baseline-law-unmade` | anything that takes apart **this project's own copy of the law** — `.rabadon/guard.json`, `.rabadon/promise.json`, or the `.rabadon` directory holding them. It is judged by **effect, not by verb name**, because the verbs are the part that goes stale: measured against the shipped binary on 2026-08-30, `rm -rf .rabadon`, `truncate -s 0`, `cp /dev/null`, `chmod 000`, `ln -sf /dev/null`, `install /dev/null`, `dd of=`, and `find .rabadon -delete` all returned 0 while only `rm <file>` was refused. So the question asked is: after this command, is the law still there, still whole, still readable? Removed, emptied, overwritten, renamed away, symlinked over, appended to, or chmod'ed out of reach are one answer, and a verb this law has never heard of pointed at those paths is refused rather than waved through. This is the one place in the gate where an unknown name fails **closed**, because the subject is exactly three filenames. A path is reached however the shell would reach it: a glob (`rm -rf .r*`, `rm -rf .*`) and a brace (`mv .rabadon{,.bak}`) are expanded before they are judged — but `rm -rf *` passes, because bash does not expand a bare star onto a dotted name. An **inline** program handed to an interpreter (`python3 -c`, `perl -e`, `node -e`, `ruby -e`, and awk's first operand) is opaque text, so a body that spells one of the three names is refused; a program handed over as a **file** is not guessed at. **Reading passes**, and that is held by test from the other side: `cat`, `grep` (including `grep -c rm .rabadon/guard.json`, which spells a verb but writes nothing), `head`, `tail`, `wc`, `ls`, `stat`, `diff`, `git diff`, `git log`, `sed -n`, an interpreter reading it with no in-place flag and no inline body, `cd` into the directory, and `cp .rabadon/guard.json ./backup.json` — copying it **out** — all pass. **So does creating it and backing it up:** `mkdir -p .rabadon` is the first step of installing the law by hand and `tar -cf backup.tar .rabadon` is the promise above being kept, and both were REFUSED until 2026-08-30 — see the correction below. So does ordinary destructive work anywhere else in the tree, and so does deleting a whole project of yours that happens to contain a `.rabadon`: the subject is the law, not the tree around it. Change the law with an edit the guard can see, or silence `baseline-law-unmade` by id if a shell rewrite is really what you meant. |

### Correction, 2026-08-30 — what the sentence above did NOT do until today

The row says "this project's own copy of the law", and until 2026-08-30 the
compiled rule did not do that: it fired on **every** path on the disk whose last
component was `.rabadon`, and it read five ordinary shapes as attacks. Measured
with an empty `bash[]` fixture in a project sandbox under `$HOME` — deliberately
not under a machine temp root, whose carve-out inflates the reading — one line
per shape, `REFUSE` when the gate exits 2:

    bash reports/kosu/kanit/f3h/probe.sh <<'EOF'
    mkdir -p .rabadon
    mkdir -p /elsewhere/unrelated/.rabadon
    mkdir -p "$VAR/.rabadon"
    tar -cf backup.tar .rabadon
    find . -not -path '*/.rabadon/*' -delete
    EOF

    REFUSE  mkdir -p .rabadon                          <- installing the law by hand
    REFUSE  mkdir -p /elsewhere/unrelated/.rabadon     <- an absolute path in no project of ours
    REFUSE  mkdir -p "$VAR/.rabadon"
    REFUSE  tar -cf backup.tar .rabadon                <- BACKING THE LAW UP
    REFUSE  find . -not -path '*/.rabadon/*' -delete   <- the walk that EXCLUDES the law

All five now pass, and each is an assertion in `native/law_family_test.sh`
alongside the shape it must not have opened (`mkdir -m 000 .rabadon`,
`tar -xf a.tar -C .rabadon`, `find . -path '*/.rabadon/*' -delete`, this
project's own copy spelled absolute). **The rule was not weakened; its subject
was narrowed to what this row always said it was.** Another tree's `.rabadon` is
`baseline-rm-rf-outside`'s business, under that rule's own id.

### The way out?

A guard with no way out is a trap, so here is the way out, measured on
2026-08-30 rather than asserted. **Deleting a project of your own that carries
its own `.rabadon` is ordinary work and passes** — `rm -rf ./old-project`,
`mv ./old-project /tmp/bin`, both held by assertion in
`native/law_family_test.sh`. The subject of this rule is the law, not the tree
around it.

For a leftover somewhere else on the disk, the refusal now names the rule that
is actually speaking, which before today it did not:

    rm -rf ~/scratch/old-sandbox
    -> Rule: baseline-rm-rf-outside — a recursive delete outside the project tree
       (user override: add "baseline-rm-rf-outside" to disabled[] in .rabadon/guard.json,
        or `rabadon off` to pause supervision)

Both of those work, and so does `disabled: ["baseline-law-unmade"]` for the law
itself — that path is asserted in the suite too, because an override named in
every refusal message that does not actually open the door is worse than no
override at all. **`RABADON_OFF=1 <command>` is NOT one of them**: an env prefix
is part of the command text and the gate reads it as a silencer being spelled at
it. That spelling was published by an earlier phase and is wrong; use
`rabadon off`.

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
  is refused. It also arms **`red-suite-test-write`**: while the suite is red,
  *any* write to a file matched here is refused, weakening or not. That is a
  wider net than test-tamper on purpose — "make the judge say yes" does not have
  to look like weakening — and it has a known false-positive class: sometimes the
  test is the thing that is wrong. That case has one command, named in the
  refusal itself: `rabadon wrong red-suite-test-write "why the test is wrong"`.
  It writes `WRONG_REFUSAL` on the same hash-chained ledger as the refusal, so
  this rule's false-positive count is read rather than asserted, and it leaves a
  **one-shot** pass: the next write goes through (`OVERRIDE_USED` on the ledger)
  and the one after that is refused again. On a green suite the rule is silent.
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
