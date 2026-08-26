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
- A C++ compiler (`clang++` or `g++`). The install below builds the native core
  from source, so the compiler is required today, not optional. (Prebuilt
  `@rabadon/<platform>` binaries are built for `darwin-arm64`, `darwin-x64`,
  `linux-x64` and `linux-arm64`, and they are what removes this requirement —
  once published; see below.)
- Claude Code CLI (`claude`) is **optional** — needed only for guard authoring
  (`rabadon init` without `--no-llm`) and for `rabadon repair`. Deny rules work
  without it.

## 1. Install

Not on npm yet — install from source. This is the same path README.md
documents, and it is the only one that works today.

```sh
git clone https://github.com/nosey-dewdrop/rabadon && cd rabadon
npm install && npm link   # builds the native core with clang++/g++, puts `rabadon` on your PATH
```

**About the npm path.** The package is built and the release workflow is wired,
but nothing has been published: there is no release tag for the version in
`package.json`, so the global install command is not on npm yet and the registry
answers E404 (measured 2026-08-26). This page will not print a command that
cannot run, so it is described here instead of given as a block to copy.
Once published, a global npm install will be the one-liner, it will pull a
prebuilt `@rabadon/<platform>` binary through optionalDependencies, and no
compiler will be needed; where no prebuilt matches your platform a
`postinstall` step compiles from source, and modern npm refusing that script by
default is what the `--allow-scripts=rabadon` flag is for. `native/install_docs_test.sh`
holds this page to that rule and lifts it by itself the day the tag exists.

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
    ~/.rabadon/config.json   — repair.mode = "ask"  (ask | auto-propose | off)
    ~/code/my-project/.cursor/hooks.json   — the same gate, for Cursor

  see it work in 30 seconds:
    rabadon drill        one tagged test event through the real gate
    rabadon usage        the ledger — drills excluded by design

  from here:
    claude               work normally in ~/code/my-project — the session is supervised
    rabadon on|off       enforce, or pause to watch-only
    rabadon remove       take it all back out (add --global here if you used it)

  disable exactly one rule with  "disabled": ["<rule-id>"]  in .rabadon/guard.json.

  right now: WATCH — every action is recorded and nothing is refused.
             watch is the default: the rules prove themselves on your own
             work first, and enforcing is your call, not ours.
  next:      rabadon on       start refusing (rabadon off returns to watch)
```

That closing block is the screen paying its three debts — what just happened,
why it is that way, and the one command you run next. The paste above is
trimmed of the `repair.mode` explainer the real screen also prints; the uncut
capture is in
[`reports/kosu/RAPOR/f1c-2-init-ekrani.out`](../reports/kosu/RAPOR/f1c-2-init-ekrani.out),
and `native/exit_path_test.sh` holds the block itself, so it cannot go stale
quietly.

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
