# rabadon quickstart

rabadon is a reliability runtime for AI coding agents. It sits between a live
agent session and the world: it refuses the destructive command before it
happens, keeps a tamper-evident ledger of everything it caught, can run commands
under a kernel sandbox, and closes a catch -> propose -> re-verify repair loop.

This is a stranger's five minutes: install it, point it at a project, watch it
catch something, turn it on, work normally, read the ledger.

## Requirements?

- macOS or Linux (no Windows).
- Node >= 18.
- A C++ compiler (`clang++` or `g++`) **only if** no prebuilt binary exists for
  your platform. Prebuilt binaries ship for `darwin-arm64`, `darwin-x64`,
  `linux-x64`, `linux-arm64`.
- Claude Code CLI (`claude`) is **optional** — needed only for guard authoring
  (`rabadon init` without `--no-llm`) and for `rabadon repair`. Deny rules work
  without it.

## 1. Install

```
npm i -g rabadon
```

npm pulls a prebuilt `@rabadon/<platform>` binary via optionalDependencies.
If no prebuilt matches your platform, a `postinstall` step compiles from source
(this is the path that needs `clang++`/`g++`). Modern npm may refuse the build
script by default; if so:

```
npm i -g rabadon --allow-scripts=rabadon
```

Confirm the install:

```
rabadon doctor
```

```
rabadon doctor — /usr/local/lib/node_modules/rabadon

  ok   native core built (16/16 binaries)
  ok   version <x.y.z> (binary matches package.json)
  ok   kernel sandbox: available — macOS Seatbelt (sandbox-exec)
  ok   claude CLI present (guard authoring + repair proposer available)
  ok   ledger: 0 day-file(s), 0.0 MB (retention: 30 days, pruned on session start)

  all green.
```

## 2. Point it at a project

```
cd ~/code/my-project
rabadon init
rabadon on          # init leaves the project in watch mode; this arms the brake (step 4)
```

`init` authors a guard (`.rabadon/guard.json`), lints it, and merges the gate
hooks into `.claude/settings.json` (backing up any existing file to
`.claude/settings.json.bak-rabadon`). If the `claude` CLI is absent or you pass
`--no-llm`, it falls back to a baseline of four rules (force-push to a shared
branch, `rm -rf` outside the tree, hard-reset of main, hook bypass).

```
rabadon init — done.

  wired in:
    ~/code/my-project/.rabadon/guard.json   — the law, REVIEW it (deny rules + protected paths)
    ~/code/my-project/.claude/settings.json   — gate hooks merged (original: settings.json.bak-rabadon)

  see it work in 30 seconds:
    rabadon drill        one tagged test event through the real gate
    rabadon usage        the ledger — drills excluded by design

  from here:
    claude               work normally in ~/code/my-project — the session is supervised
    rabadon on|off       enforce, or pause to watch-only

  disable exactly one rule with  "disabled": ["<rule-id>"]  in .rabadon/guard.json.
```

**Review the guard before you trust it.** It is your project's law; open
`.rabadon/guard.json` and read the deny rules and protected paths. See
[guard.md](guard.md).

## 3. See a catch right now

You do not have to wait for a real incident. `rabadon drill` fires one tagged,
synthetic dangerous command through the **real** gate so you see the exact
refusal text an agent would get — in about 30 seconds.

```
rabadon drill
```

```
rabadon drill — feeding a synthetic dangerous command through the REAL gate:
    $ git push --force origin main

rabadon (watch) would have blocked this.
Rule: no-force-push-main — force-pushing a shared branch destroys history

the rule FIRED in watch mode — `rabadon on` makes this a real refusal (exit 2).
this was a drill: tagged at emit, excluded from the ledger. `rabadon usage` counts only real catches.
```

The drill is tagged at emit and excluded from the ledger — it never inflates
your numbers.

## 4. Turn enforcement on

A fresh install is in **watch** mode: it records what it would have blocked but
stops nothing. To make refusals real:

```
rabadon on
```

```
ENFORCE — the arbiter acts. Forbidden actions are refused before they happen.
```

Toggle back with `rabadon off` (watch) and check state with `rabadon status`.

## 5. Work normally

```
claude
```

Nothing changes in how you use Claude Code. The gate runs on every tool action
in single-digit milliseconds — 3.1 ms at the median, measured, see
[BENCHMARK.md](../BENCHMARK.md). If
the agent tries something the guard forbids, the action is refused (exit 2) and
the reason is written back to the agent so it self-corrects.

## 6. Read the ledger

```
rabadon usage
```

```
rabadon usage — last 7 day(s) · local, nothing leaves this machine
source: ~/.rabadon/spool

  3 refused before they happened · 41 actions gated · 0 repairs held
  (EXAMPLE OUTPUT from a fresh install — your numbers start at zero and grow.)

  my-project                                          last event: 2026-07-31 14:22:07
        2x  no-force-push-main
            force-pushing a shared branch destroys history
        1x  no-rm-rf-outside
            recursive delete outside a project is unrecoverable
```

Everything is local. Nothing left your machine.

## Where next?

- [commands.md](commands.md) — every verb, its flags and exit codes.
- [guard.md](guard.md) — how to author and review `guard.json`.
- [how-it-works.md](how-it-works.md) — the hooks, the gate contract, the ledger.
- [threat-model.md](threat-model.md) — what the kernel fences and what it does not.
- [faq.md](faq.md) — troubleshooting.
