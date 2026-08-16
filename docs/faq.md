# rabadon FAQ and troubleshooting

**Run `rabadon doctor` first.** It checks the native binaries, version lockstep,
the sandbox backend, global hook health, the `claude` CLI, and the spool. Most
of the answers below start there.

## The gate is not firing — why?

Work through these in order:

1. **Check the mode.** `rabadon status`. In **watch** mode nothing is stopped —
   rules only record `WOULD_BLOCK`. Turn it on with `rabadon on`.
2. **Prove the gate works at all.** `rabadon drill` fires a synthetic dangerous
   command through the real gate. If the drill refuses but your real command does
   not, the gate is healthy and your **guard rule** does not match the command —
   check the regex in `.rabadon/guard.json` (it is matched against the full
   command; run `rabadon lint`).
3. **Check the hooks are installed and point at real binaries.**
   `rabadon doctor` reports global hook health and names any hook command
   pointing at a missing path. If hooks are missing, re-run `rabadon init` in
   the project (or `rabadon init --global`).
4. **Confirm you initialized this project.** The gate only runs where
   `rabadon init` merged the hooks and a `.rabadon/guard.json` exists.

## How do I disable one rule?

Add its id to `disabled[]` in `.rabadon/guard.json`:

```json
"disabled": ["no-force-push-main"]
```

Prefer this over turning the whole gate off. Every refusal message names its
rule id so you always know which one to add.

## Will it slow my session?

No meaningfully. The gate is deterministic native C++ and decides in **3.1 ms**
at the median (3.14 ms allow, 3.20 ms deny, n=40); the hook timeout it runs
inside is measured in seconds. The hot path never calls a model. Reproduce the
number with `make bench` — it prints the table BENCHMARK.md is built from.

One action is deliberately not free: a `git push` when code changed after the
last green test run. There the gate runs your suite before it opens, so that
one hook call costs whatever your tests cost.

## Does anything leave my machine?

No. Events go over a local unix socket and to local files under `~/.rabadon`.
Nothing is uploaded. You can verify: `rabadon export --otlp` prints
OpenTelemetry traces to **stdout** and sends nowhere on its own — it leaves the
machine only if you pipe it to a collector yourself.

## npm install didn't build the binary — what now?

You are on the source-build path (no prebuilt binary matched your platform), and
npm blocked the `postinstall` build script. Either:

- reinstall allowing the script: `npm i -g rabadon --allow-scripts=rabadon`, or
- install a C++ compiler first (`clang++` or `g++`), then run `rabadon doctor` —
  it will point you at the `make` command to build the native core:
  - macOS: `xcode-select --install`
  - Debian/Ubuntu: `sudo apt install g++ make`

Then `rabadon doctor` should show `native core built`.

## What if rabadon itself crashes?

It fails open. A bug in rabadon is treated by Claude Code as allow — a broken
gate never blocks your session. (The opposite direction, a rule match, always
fails closed and refuses.) If you suspect a crash, run `rabadon doctor` and check
for version drift between the binary and `package.json` (rebuild with `make` if
they disagree).

## I need to restore my settings — where is the backup?

Every time rabadon first writes to an existing `.claude/settings.json`, it copies
it to `.claude/settings.json.bak-rabadon`. To restore by hand:

```
cp .claude/settings.json.bak-rabadon .claude/settings.json
```

Or let rabadon strip only its own hooks cleanly with `rabadon remove` (see
[uninstall.md](uninstall.md)).

## Is the ledger really unedited?

Run `rabadon audit`. It re-walks the hash chain and exits 1 if any link is
broken, naming the file and line. `rabadon replay` renders the verified timeline
with a chain mark per line. Note this is tamper-**evident**, not tamper-proof —
see [threat-model.md](threat-model.md).

## The sandbox says no backend — what do I install?

- macOS: `sandbox-exec` ships with the OS; if `rabadon doctor` reports it
  missing, your environment is unusual.
- Linux: install bubblewrap — `sudo apt install bubblewrap`.

Without a backend, `rabadon exec` refuses to run rather than run unprotected.
The hook still works.
