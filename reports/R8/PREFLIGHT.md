# R8 preflight — what is TRUE TODAY (2026-08-23)

Read-only verification of the three "known breakages" named in `KOSU-RABADON.md § R8`,
plus the two open questions R8 depends on. Nothing was fixed here. Where the plan is
wrong, it is said plainly: a corrected plan is the point of this file.

Method: every claim below has the command that produced it. Anything I could not run
is marked **DOĞRULANMADI**.

---

## 1. Is rabadon still 404 on npm?

```
$ npm view rabadon version
npm error code E404
npm error 404 Not Found - GET https://registry.npmjs.org/rabadon - Not found
```

```
$ git tag
v0.2.0  v0.2.1  v0.2.2
$ gh run list --workflow=release.yml -L 6
completed  failure  release  v0.2.2  2026-08-05
completed  failure  release  v0.2.1  2026-08-05
completed  failure  release  v0.2.0  2026-08-04
completed  failure  release  main    2026-07-31 (workflow_dispatch)
completed  cancelled release  main    2026-07-31
completed  failure  release  main    2026-07-31
```

**Verdict: plan is RIGHT.** The name has never been published. Six release runs, zero
successes, the last one 18 days ago. Local `package.json` sits at **0.2.3** — a version
that has no tag and has never been built by the release workflow.

**R8 must do:** publish for the first time from a tag that does not exist yet (`v0.2.3`
or later), and treat the registry 404 as the acceptance baseline — `npm view rabadon
version` returning a number is the only proof that R8 closed.

---

## 2. The darwin-arm64 death and the two pytest guards

### The guards exist, at almost exactly the lines the plan names

```
$ grep -n "python3 -m pytest --version" native/heldout_test.sh native/harness_lock_test.sh
native/heldout_test.sh:121:  if ! python3 -m pytest --version >/dev/null 2>&1; then
native/harness_lock_test.sh:118:    py)   python3 -m pytest --version >/dev/null 2>&1 || need_ok=0 ;;
```

`heldout_test.sh:121` — exact hit. `harness_lock_test.sh:118` — exact hit (the `py`
branch of a `case`; the `local need_ok=1` that opens the guard is at :116).

What they actually do: a case whose toolchain is missing increments `skipped`, prints
`SKIP <name> — no pytest on this box, the probe was not judged here`, and **returns 0
instead of voting**. At the end, both files refuse to call an ungraded run green:

```
native/heldout_test.sh:287       elif [ "$pass" -eq 0 ]; then ... "held-out probe: NOT JUDGED"
native/harness_lock_test.sh:215  elif [ "$pass" -eq 0 ]; then ... "harness lock: NOT JUDGED"
```

Both still `exit 0` when `fail == 0`, so a fully-skipped file does not fail `make test`.
It is loud, not fatal — which is the trade the workflow comment argues for.

### The workflow already carries a third fix the plan does not mention

`.github/workflows/release.yml` has a step **"Give the suite the toolchain it grades
with (best effort)"** — `pip install pytest`, with `--break-system-packages` fallback,
`continue-on-error: true`, added in `35541b2` (2026-08-08). The plan writes "runner'a
pytest kurmak da meşru çözümdür, hangisi seçildiyse workflow'a yazılır" as future work.
**It is already written.** Both solutions are in the tree at once.

### "Never verified on a real runner" is STALE — it was verified last night

```
$ gh run view 32601613477            # ci, main, 2026-08-22 22:08
✓ macos-15 in 4m9s (ID 97100630490)   <- `make test`, GREEN
✓ ubuntu-latest in 4m46s
X disclosure ubuntu-latest / X disclosure macos-15   <- a different job, see §6
```

```
$ gh run view --job 97100630490 --log | grep -E "SKIP|NOT JUDGED|GREEN"
SKIP  pytest-ini-added — no py toolchain on this box, the lock was not judged here
... (5 cases)
harness lock: GREEN (5 case(s) not judged here)
SKIP  special-case-sha256 — no pytest on this box, the probe was not judged here
... (8 cases)
held-out probe: NOT JUDGED — every case was skipped for a missing toolchain
lock coverage: NOT JUDGED — both locking cases were skipped for a missing toolchain
```

`ci.yml` installs no pytest, so the macos-15 runner exercised the guards on the bare
box and `make test` finished green. This is the real-runner verification the plan says
is missing. It runs on a `macos-15` label — the same label `release.yml` uses for
darwin-arm64 — with the same `make test` command.

For contrast, the v0.2.2 death, confirmed from the log:

```
$ gh run view 30964392220 --log-failed | tail
/opt/homebrew/opt/python@3.14/bin/python3.14: No module named pytest
FAIL  honest-fix-with-short-guard -> got verdict-none, want verified (exit 2)
pass 0   fail 8
held-out probe: RED
make: *** [test] Error 1
##[error]Process completed with exit code 2.
```

The guard commits (`8d046b7`, `ec3f766`) landed **2026-08-05, after** the v0.2.2 tag
commit `2ddc91e` of the same day. That run built a pre-guard tree. No release run has
happened since.

**Verdict: plan is STALE on this point.** The guards exist, they are at the lines named,
and they have been exercised on a real macOS-15 runner as of 2026-08-22. The specific
failure that killed v0.2.0/1/2 cannot recur in that form.

**R8 must do:**
- Not re-do this fix. Delete "doğrulanır" from the R8 checklist and replace with the
  citation: ci run 32601613477, job 97100630490.
- Note the one thing this does **not** prove: on the release runner the pip step may
  *succeed*, and then the twelve cases actually run on macOS with pytest 9.x. Whether
  all twelve pass there is **DOĞRULANMADI** — the only macOS evidence available is a
  box where they were skipped. R8's first tag push is still the first real test of the
  pytest-present path on darwin-arm64.
- Because the darwin-arm64 death is closed and `fail-fast: true` is still set, the
  next-most-likely stranding is a retired runner label. The workflow comment already
  warns that `macos-14` entered deprecation 2026-07-06 and that a retired label
  **queues forever** rather than failing. Current labels are `macos-15`,
  `macos-15-intel`, `ubuntu-22.04`, `ubuntu-22.04-arm`. Whether all four are live on
  release day is **DOĞRULANMADI** (last release-workflow execution: 2026-08-05).

---

## 3. 17 binaries copied vs 18 declared

Both lists counted by hand, from the files themselves.

```
$ sed -n '/Stage binaries into the platform package/,/upload-artifact/p' \
    .github/workflows/release.yml | grep -o 'native/rabadon-[a-z]*' | sed 's|native/||' | sort
17 names
$ node -e "console.log(require('./npm/darwin-arm64/package.json').files.length)"
18
$ comm -23 <(pkg files, sorted) <(workflow list, sorted)
rabadon-run
$ comm -13 ...    # only-in-workflow
(empty)
```

All four platform manifests are byte-identical on this list — 18 each:

```
$ for d in npm/*/; do node -e "console.log(require('./$d/package.json').files.length)"; done
18 18 18 18   (darwin-arm64, darwin-x64, linux-arm64, linux-x64)
```

**Verdict: plan is RIGHT, exactly.** 18 − 17 = 1, and the missing one is `rabadon-run`.
The workflow's `cp` is a strict subset; it copies nothing the manifests do not list.

Why this matters more than a count: `npm publish` does **not** error on a `files` entry
that is absent from the directory — it silently ships 17. The installed
`@rabadon/<plat>` package would then be missing the binary that `native/rabadon-cli.sh`
dispatches the `run` verb to:

```
native/rabadon-cli.sh:219:  run)  B="$(nbin run)" || exit 1; shift; exec "$B" --dir "$(pwd)" "$@" ;;
```

`nbin` would fall through all three search paths and print *"native binary 'rabadon-run'
is not available — no prebuilt package for <plat>"* to a stranger who installed
correctly. `rabadon run -- <agent>` is the verb the README sells as "supervise ANY
agent, adapted or not" (`rabadon-cli.sh:178`).

The existing suite cannot catch this. `native/npm_install_test.sh:38-52` builds the test
tarball by **reading the manifest and copying from `native/`** — the opposite direction
from the workflow. It asserts "the platform manifest names only binaries the build
produces" (true: `make all` produces `rabadon-run`) and never looks at `release.yml`.
So this mismatch is green locally and only appears in a published tarball.

**R8 must do:**
1. Add `native/rabadon-run` to the `cp` in the "Stage binaries into the platform
   package" step of `.github/workflows/release.yml`. One word, four platforms at once.
2. Write the acceptance test the R8 checklist already promises ("test iki listeyi
   karşılaştırır"): parse the `cp` block out of `release.yml`, parse `files` out of all
   four `npm/*/package.json`, and fail on any set difference in either direction. It has
   to derive both lists, not restate them — a typed-in list of 18 is the same defect one
   layer up. Put it in `make test`, not only in `reports/R8/accept.sh`.
3. Consider deriving the third list too: `make all`'s target list (see §4). Three places
   name these binaries and nothing holds them together.

---

## 4. What does `make all` build today?

```
$ grep '^all:' Makefile | tr ' ' '\n' | grep -o 'rabadon-[a-z]*' | sort | wc -l
18
$ diff <(make all rabadon-* names) <(npm/darwin-arm64 files)
IDENTICAL
```

`Makefile:12` — `all` has **19 targets**: 18 `native/rabadon-*` binaries plus
`native/gate_bench`, which is a benchmark, not a shipped binary (the Makefile comment
says it is in `all` because the site cites it as a source and an unbuilt source is one
nobody can run).

**Answer: 18 shipped binaries, and the set matches the platform `package.json` `files`
list exactly — same 18 names, no difference in either direction.** It does *not* match
the workflow's 17.

So the odd one out is `release.yml`, alone against Makefile and all four manifests. That
is the cheapest possible fix and it also tells you which list is canonical.

Note for whoever writes the comparison test: `gate_bench` must be excluded by name, and
`make all` also builds it, so a naive "everything `all` builds" list gives 19.

---

## 5. Plugin package: does it exist?

```
$ ls .claude-plugin
ls: .claude-plugin: No such file or directory
$ find . -name plugin.json -not -path ./.git/*
(nothing)
$ find . -name hooks.json -not -path ./.git/*
./.cursor/hooks.json
$ find . -maxdepth 3 -name '*marketplace*' -not -path ./.git/*
(nothing)
$ ls hooks/
gate.mjs  gate.test.mjs  guard-gen.mjs  guard-gen.test.mjs
install.mjs  install.test.mjs  manage.mjs
```

**Verdict: plan is RIGHT — neither file exists.** `hooks/` is the npm package's JS hook
surface (`gate.mjs` is what the release smoke job invokes via
`$(npm root -g)/rabadon/hooks/gate.mjs`), not a Claude Code plugin manifest. There is no
`.claude-plugin/`, no `hooks/hooks.json`, and no marketplace manifest anywhere in the
tree.

The one thing that does exist is `.cursor/hooks.json`, and it is the shape of the
answer — five Cursor events (`beforeShellExecution`, `beforeMCPExecution`,
`afterFileEdit`, `beforeSubmitPrompt`, `stop`) all pointing at a single command. But it
points at an **absolute developer path**:

```
"command": "/Users/damummyphus/damla_projects_2026/rabadon/native/rabadon-gate"
```

That works on one machine only. It is not a template for a published plugin, and it is
worth checking whether it should be shipped at all.

**R8 must do:**
- Author `.claude-plugin/plugin.json` and `hooks/hooks.json` from scratch.
- Honour the "no second code path" rule literally: the hook commands must resolve to the
  same binary npm installs. `native/rabadon-cli.sh`'s `nbin()` already implements that
  resolution (local `native/`, then `node_modules/@rabadon/<plat>/`, then the sibling
  `../@rabadon/<plat>/`) — the plugin should call through the installed `rabadon`
  command or reuse that resolver, never hardcode a path the way `.cursor/hooks.json`
  does.
- The R8 acceptance line "`claude --plugin-dir .` loads the plugin, diff sıfır" needs a
  concrete diff subject: propose comparing the resolved absolute path of the hook
  command against `$(npm root -g)/rabadon/...`'s resolution for the same verb.
- Whether `anthropics/claude-plugins-official` is still the canonical, auto-registered
  directory (vs `claude-code/plugins/` demo and `claude-plugins-community`) is
  **DOĞRULANMADI** — that is a claim about a third-party repo, not about this tree, and
  I did no network lookup for it. Verify before spending the PR.

---

## 6. Not asked, but it blocks R8: main is red, and by design

R8 item 3 says *"Yayın yeşil main'den, temiz tag'le yapılır; kırmızı tabandan publish
yasak."* On today's tree that rule cannot be satisfied as written:

```
$ gh run list --workflow=ci.yml -L 5
failure  failure  failure  failure  failure      (every push, 2026-08-22)
$ make disclosure
FAIL - site/ publishes project names nobody decided to publish:
       53 name(s) found, 12 allowed, 41 off-list
published allowlist: 8 ok, 1 fail
make: *** [disclosure] Error 1
```

The `disclosure` job is **deliberately red** and fails `ci.yml` on every push until a
human triages 41 project names in `site/`. `.github/workflows/ci.yml:79-95` documents
this on purpose: it was moved out of `make test` into its own job precisely so a
designed-red suite would stop acting as rabadon's own gate. The two `make test` jobs
(ubuntu-latest, macos-15) are green.

So "green main" is ambiguous today: **green suite, red workflow.** R8 has to pick one
and write it down:
- either triage the 41 names so `ci.yml` is genuinely green before the tag (real work,
  outside R8's stated scope, and it is content/naming work not release work), or
- define the publish precondition as "both `make test` jobs green" and say so
  explicitly, naming the disclosure job as the known-and-accepted red.

Silently publishing off a red `ci.yml` is the third failure mode the plan was trying to
forbid, arriving through a door the plan did not look at.

---

## Ne gördüm, sorulmadı (döküm)

- **`package.json` is at 0.2.3, untagged.** `optionalDependencies` pin all four
  `@rabadon/*` at `0.2.3` too, and `native/version_test.sh` holds the tree in lockstep
  (13 checks, green on the last runner). The version sanity step
  (`scripts/prepare-release.mjs --check`) runs in `publish`, i.e. *after* all four
  builds; a version mismatch burns the whole matrix before it is caught.
- **`fail-fast: true` on the build matrix** means one runner strands the release. The
  workflow's own comment records the 31.07 case: `macos-13` (retired 2025-12) queued
  forever while three targets went green.
- **The main `package.json` `files` list does not ship the platform binaries at all** —
  it ships sources (`native/*.cpp`, `native/*.h`), `Makefile`, `hooks/`, `bin/`, `core/`,
  `repair/`, `ui/` and `native/rabadon-cli.sh`. `bin.rabadon` points at
  `./native/rabadon-cli.sh`. So the main package is source + dispatcher, and the four
  `@rabadon/<plat>` optional deps carry the binaries. That is why a missing
  `rabadon-run` in the platform package is invisible until runtime.
- **README line 19 still says "Not on npm yet — install from source."** R8's acceptance
  already names this; recorded here so nobody has to grep for it.
- **The smoke job is stronger than the plan credits.** It waits up to 300s for the
  registry, installs globally, and then requires the installed gate to refuse a
  force-push (exit 2) *and* allow `git status` (exit 0), plus `rabadon drill`. It does
  not exercise `rabadon run`, so the §3 defect would survive the smoke job too.
- **`native/run.cpp` exists** (11,792 bytes, 2026-08-16) and `Makefile` builds it. This
  is not a stale manifest entry — the binary is real and only the workflow forgot it.
- **`hooks/gate.mjs` is 33 KB of JS** doing hook work next to the C++ gate. Whether the
  plugin should call `gate.mjs` or the native binary is an open design question R8 will
  hit immediately; I did not resolve it.
- **Could not check:** anything requiring a release-workflow execution (pip step
  behaviour on a real macOS release runner, runner-label liveness, provenance/OIDC,
  whether `NPM_TOKEN` and the `@rabadon` npm org exist). All **DOĞRULANMADI**. The
  `@rabadon` scope's existence was not probed on the registry.
