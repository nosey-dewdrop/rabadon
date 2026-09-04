# F1e-C — the reference container, measured suite by suite

Worker card C. This session **measured only**. It did not touch a test, the
Makefile, `docs/`, an acceptance script, or any source file under `native/`
except to ADD one new file, `native/refenv/run.sh`, which runs the
measurement. `native/sandbox_test.sh` was NOT edited — see the CHALLENGE.

## 0. The headline, stated the way it came back

The previous session reported `make test` → exit 2 in a clean container and
**54 suites never ran**. Two corrections, both measured:

- `make test` has **103** suites, not 104 and not 97. `promises_test.sh` is in
  the separate `promises:` target and is not part of `make test`.
  `sandbox_test.sh` is suite **#57**, so the number that never ran behind it
  was **46**, not 54. The "54" was an estimate; this is a count.
- Now that all 103 have actually been run one at a time in the container, the
  census is:

| status | count | at the 300 s ceiling I first used |
|---|---|---|
| GREEN | **100** | 99 |
| RED | 3 | 3 |
| TIMEOUT | 0 | 1 (`npm_install_test.sh`) |
| NEVER RAN | **0** | 0 |
| **total** | **103** | 103 |

The one TIMEOUT was **my harness's fault, not the product's**: re-run offline at
a 900 s ceiling, `npm_install_test.sh` is GREEN, 12/12, in 562 s (§6).

`make all` → **exit 0** (warnings only, no errors). Confirmed again here.

**Scope warning, up front: every number in this report is measured at commit
`6f1bc3c`.** A parallel worker landed four commits on `main` during the run,
one of which adds a 104th suite to `make test` that has never run in a
container. See §5 — do not quote "103" or "100 GREEN" as a fact about main
today.

Of the 3 reds, **two are environment-shaped** (a missing `gh` binary; the
container running as `root`) and **exactly one is a real product defect**:
`sandbox_test.sh`. It is left RED on purpose — see the CHALLENGE in §4.

## 1. The exact command that was run

Committed as `native/refenv/run.sh`. It was invoked as:

    ./native/refenv/run.sh --out reports/kosu/RAPOR --prefix f1e-c- --suite-timeout 300

which produced and printed this `docker run` line verbatim:

    docker run --rm --network none \
      -v /var/folders/5b/s4fb775925l775xmnt2zt_mr0000gn/T//rabadon-refenv.hFdwfr/tree:/w \
      -v /var/folders/5b/s4fb775925l775xmnt2zt_mr0000gn/T//rabadon-refenv.hFdwfr/results:/out \
      -w /w \
      -e SUITE_TIMEOUT=300 \
      -v /var/folders/5b/s4fb775925l775xmnt2zt_mr0000gn/T//rabadon-refenv.hFdwfr/inside.sh:/inside.sh:ro \
      node:22-bookworm bash /inside.sh

(the `/var/folders/...` paths are a per-run `mktemp -d`; the script regenerates
them, so the line is reproducible by re-running the script, not by pasting it.)

- **image**: `node:22-bookworm`
- **image id**: `sha256:8a34c4ab3ea2c5cd194f07e317b2a8f09461d3c8b05c4e34c8ccd56d56024c4d`
- **RepoDigest as reported**: `node@sha256:8a34c4ab3ea2...24c4d` — **note: this
  equals the image ID byte for byte.** Docker Desktop's containerd image store
  reported the same sha in both the `DIGEST` and `IMAGE ID` columns of
  `docker images --digests`. I could not confirm offline that this is the Docker
  Hub *manifest* digest. **DOĞRULANMADI** — treat the image id as the reliable
  identifier here, not the digest.
- **architecture**: `arm64` / `aarch64` (Apple Silicon host, linux/arm64 image)
- **HEAD measured**: `6f1bc3c317aa2a78cb3d5543c0dc92497e678a8e`
- **kernel in container**: `6.12.67-linuxkit`, Debian GNU/Linux 12 (bookworm)
- **toolchain found**: `c++` → g++ (Debian 12.2.0-14+deb12u1), git 2.39.5,
  node v22.23.2, python3 3.11.2
- **`bwrap`: ABSENT**. `unshare` present.
- **network**: `getent hosts registry.npmjs.org` did not resolve — `--network
  none` was in force and is proven in the artifact, not asserted.

### Two deliberate deviations from the card, both named

1. The card said `git worktree add --detach`. The script uses
   **`git clone --no-hardlinks`** instead. Reason, not preference: a worktree's
   `.git` is a *file* pointing at the host's gitdir, and that host path does not
   exist inside the container, so every git-touching suite would have failed for
   a reason about the harness rather than about rabadon. A clone is
   self-contained and, because it clones `HEAD`, it measures the **committed**
   tree rather than a dirty working copy. The main working tree was never built
   in and never had `make` run in it.
2. `make -k` was **not** used. `make -k` still reports one aggregate verdict and
   still interleaves output. The script reads the suite list out of the
   Makefile's own `test:` target and runs each script directly, so every suite
   gets its own exit code, its own ok/fail tally, and its own timeout. The list
   is parsed from the Makefile at run time — it is not a second hand-kept copy
   that can drift from what `make test` runs.

### Artifacts (committed)

| file | what |
|---|---|
| `reports/kosu/RAPOR/f1e-c-env.out` | image/digest/arch/HEAD + container toolchain probe |
| `reports/kosu/RAPOR/f1e-c-build.out` | full `make all` output, exit code on the last line |
| `reports/kosu/RAPOR/f1e-c-suites.tsv` | the table below, machine-readable |
| `reports/kosu/RAPOR/f1e-c-suites.out` | 4588 lines: full stdout+stderr of all 103 suites |

## 2. Per-suite census

Full table: `reports/kosu/RAPOR/f1e-c-suites.tsv` (`suite / exit / ok / fail /
status`). **NEVER RAN: none — all 103 were executed.**

A `-` in the ok/fail columns means the suite does not print the
`N passed, M failed` line the others do; its exit code is still authoritative.
The suites that report this way and were all GREEN (exit 0):
`push_config_file_test.sh`, `path_answer_test.sh`, `guard_reach_test.sh`,
`cmdtext_test.sh`, `shell_function_test.sh`, `git_verbs_test.sh`,
`promise_law_test.sh`, `delete_verbs_test.sh`, `shell_cwd_test.sh`,
`harness_lock_test.sh`, `heldout_test.sh`, `lock_coverage_test.sh`,
`false_reject_test.sh`, `discovery_test.sh`, `lens_test.sh`,
`precision_test.sh`.

The four that are not green:

| suite | exit | ok | fail | status |
|---|---|---|---|---|
| `npm_install_test.sh` | 124 | 8 | 0 | TIMEOUT (300 s) — **GREEN 12/12 at 900 s, §6** |
| `sandbox_test.sh` | 1 | 8 | 1 | RED |
| `site_claims_test.sh` | 1 | 7 | 3 | RED |
| `publish_redaction_test.sh` | 1 | 27 | 1 | RED |

Largest green suites, for scale: `cli_test.sh` 315 ok, `lease_force_test.sh`
146 ok, `head_ref_test.sh` 106 ok, `status_truth_test.sh` 94 ok,
`other_repo_test.sh` 90 ok, `postuse_test.sh` 88 ok, `trace_test.sh` 85 ok.

## 3. Every red, by name and root cause

### 3.1 `sandbox_test.sh` — exit 1, 8 ok / 1 FAIL — REAL DEFECT

Observed, verbatim from `f1e-c-suites.out`:

      skip - no kernel sandbox backend on this platform — enforcement tests skipped (--check is honest about it)
      FAIL - --check message
    sandbox: 8 passed, 1 failed

Root cause: a string that moved on one side of a contract and not the other.

- `native/sandbox.cpp:365` prints
  `rabadon sandbox: NO usable kernel backend — %s`
- `native/sandbox_test.sh:121` greps for `"no kernel backend"`

The grep is `-i`, so case is not the problem. The word **`usable`** sits between
`NO` and `kernel`, so `"no usable kernel backend"` does not contain the
substring `"no kernel backend"` and the match fails. The product's message is
*correct and honest* — it also names the fix (`bwrap is not installed — apt
install bubblewrap`). The **test's expectation is the stale side.**

Archaeology (measured, `git log -S`):

- `native/sandbox_test.sh` line 121 was written in `fe848e7`, with the original
  wording.
- `a74e7d8` (2026-07-31, *"sandbox: presence is not capability — --check now
  asks the backend to do the smallest version of its job"*) changed the string
  from `NO kernel backend on this platform ...` to `NO usable kernel backend —
  %s`. `git show --stat a74e7d8` touched **`.github/workflows/ci.yml` and
  `native/sandbox.cpp` only**. The test was not updated with it.

Why nobody saw it for four weeks: that branch of the suite runs **only when
`--check` fails**, i.e. only on a machine with no sandbox backend. On macOS
`sandbox-exec` is present, so the branch is dead code on the maintainer's box.
A clean Debian container with no `bubblewrap` is the first place it has ever
executed. This is precisely the failure class the "clean container is the
reference environment" bar exists to catch, and it caught one on the first run.

**Left RED. Not fixed. See §4.**

### 3.2 `site_claims_test.sh` — exit 1, 7 ok / 3 FAIL — ENVIRONMENT

Root cause is a single missing binary that cascades into three failures:

    FAIL  site/build.py failed
          FileNotFoundError: [Errno 2] No such file or directory: 'gh'
            File "/w/site/build.py", line 277, in pull_requests
              out = sh(["gh", "search", "prs", "--author", "@me", ...])
    FAIL  site/build.py produced no .../index.html — the checks below would pass on an empty tree
    FAIL  the overview disagrees with the page built from the same source

`site/build.py:277` shells out to the GitHub CLI (`gh`), which is not installed
in `node:22-bookworm` and, even if it were, needs the network and an
authenticated account. `--network none` makes this unpassable by construction.
The third FAIL is a consequence of the second: no `index.html` was produced, so
the comparison had nothing to read. The suite's own guard behaved correctly here
— it *refused to pass on an empty tree*, which is the right behaviour and worth
noting as a positive.

This is not a rabadon logic failure. It is a suite in `make test` that has an
**undeclared external dependency on `gh` + network**. That is still a real
finding against the stated bar ("works on a machine that has only git and a
shell"): `make test` as written cannot pass on such a machine. Whether the fix
is to skip this suite offline or to move it out of `make test` is a decision for
the planning run, not for a measuring worker.

### 3.3 `publish_redaction_test.sh` — exit 1, 27 ok / 1 FAIL — ENVIRONMENT (false positive)

Observed, in section `6. the real site/ carries neither, and the page's claim is
backed by a count`:

    FAIL  published artifacts under /w/site carry what may not be published:
            rule_census.json: 1 project key(s) carrying the home path

Root cause: **the container runs as `root`, so `HOME=/root`.** The scanner
computes an encoded home key at `native/publish_redaction_test.sh:125`:

    enc_home = re.sub(r"[^A-Za-z0-9]+", "-", home)

For `HOME=/root` that is the four-character string `-root`. I searched the file
on the host:

    grep -c -- '-root' site/rule_census.json   ->  1
    grep -oE '.{30}-root.{30}' site/rule_census.json
      ow; a force clean from a $HOME-rooted tree deletes them and every

The single hit is the English phrase **"a `$HOME`-rooted tree"** inside a prose
explanation. It is not a project key and it is not a leak. I also walked every
dict key in `site/rule_census.json` with python and found no key containing
`Users/` or `/home/`; `by_project` holds only `(withheld)`, `rabadon`,
`airflow`, `goose`, `redis`, `terraform`, `crush`, `discourse`, `rails`,
`(no project)`.

This is the **same false-positive class the suite already documents and
exempts for one specific account name**: its own comment at lines 136–140 says a
CI runner's account is a dictionary word and that counting `runner` "would
report the word, not a leak". `root` is a shorter, even more common English
word, and it is the default account of every container on earth — but the
generic-account exemption was written for `runner` and does not cover it. So the
suite goes red under `docker run` as root, on prose, forever.

No secret is exposed. **DOĞRULANMADI**: I did not test whether running the
container as a non-root UID makes this suite green — that is the obvious next
measurement and it was not taken.

### 3.4 `npm_install_test.sh` — exit 124 at 300 s — NOT A RED. My ceiling was too low.

Eight assertions passed, then the suite was killed at the 300 s wall:

      ok   - npm i -g installs the package and its prebuilt platform binaries
      ok   - the rabadon command is on the path
      ok   - doctor finds the prebuilt binaries
      ok   - rabadon init exits 0 on a prebuilt install
      ok   - init wrote the project's settings.json
      ok   - the hook command points at a binary that EXISTS and is executable
      ok   - a force-push is REFUSED through the installed hook — the README's first promise holds
    Terminated

Note what this already proves offline: **the published npm install path works
with no network at all**, from local tarballs, including the README's first
promise firing through the installed hook.

The stall is in the block that begins at `native/npm_install_test.sh:105`
("THE PREBUILT CLAIM, tested where it is actually made: a machine with no
compiler") — a second `npm i -g --prefix` with `cc/gcc/g++/clang/clang++/c++/
make/cmake/ld` all replaced by shims that exit 127. A re-run of this single
suite offline at a 900 s ceiling was taken to separate "slow" from "stuck".

**It is slow. 562 s, offline, 12 passed / 0 failed, exit 0.** Full output in §6.
I initially suspected npm retrying against an unreachable registry; that guess
was wrong and is recorded here rather than quietly deleted.

## 4. CHALLENGE — `native/sandbox_test.sh:121`

Filed under CLAUDE.md "If PROJECT.md itself is wrong" / non-negotiable 1. It is
**not** fixed in this session and must not be fixed by whoever reads this
without the human's word, because the tempting fix is exactly the move rabadon
exists to refuse.

**What is wrong.** `native/sandbox_test.sh:121` asserts a message string that
the product stopped printing on 2026-07-31.

**Evidence — commands and their output, not opinion.**

    $ grep -n "no kernel backend" native/sandbox_test.sh
    121:  "$SB" --check 2>&1 | grep -qi "no kernel backend" && pass "--check reports the absence honestly" || fail "--check message"

    $ grep -n "NO usable kernel backend" native/sandbox.cpp
    365:      printf("rabadon sandbox: NO usable kernel backend — %s\n", why_not());

    $ git log --oneline -S'NO usable kernel backend' -- native/sandbox.cpp
    a74e7d8 sandbox: presence is not capability — --check now asks the backend to do the smallest version of its job

    $ git show --stat --format= a74e7d8
     .github/workflows/ci.yml | 11 +++++++++-
     native/sandbox.cpp       | 56 +++++++++++++++++++++++++++++++++++-------------
     2 files changed, 51 insertions(+), 16 deletions(-)

    container, node:22-bookworm, --network none:
      skip - no kernel sandbox backend on this platform — enforcement tests skipped
      FAIL - --check message
    sandbox: 8 passed, 1 failed        (exit 1)

**Why the obvious fix is the wrong one.** Loosening the grep to
`"kernel backend"`, or rewriting the needle to match today's output, is editing
an acceptance expectation so that a check goes green. Under non-negotiable 1
and 2 that is not permitted here, and it is doubly wrong because the assertion
is doing real work: it is the only thing standing between a user and a silent
`--check` (Promise 1 — rabadon never goes quiet). The assertion's *intent* is
right; only its *literal* is stale.

**Proposed resolution — NOT applied, needs a human.** In its own commit, with
its own justification, and BEFORE any code commit that depends on it:

- Preferred: make the contract explicit instead of re-typing a sentence.
  Have `--check`'s failure path emit a stable machine token (e.g.
  `rabadon-sandbox: backend=none reason=<...>`) alongside the human prose, and
  have `sandbox_test.sh` assert **the token** plus "the prose names a fix". A
  test that greps English will break again the next time the wording improves,
  and the wording *should* keep improving.
- Minimal alternative: update the needle in `native/sandbox_test.sh` to the
  current string in **a commit that contains nothing else**, with the reason
  written out. This is allowed by rule 2 only because the criterion change is
  isolated from any code change — but it buys nothing against the next
  rewording.
- The CI angle is part of the diff either way: `a74e7d8` touched
  `.github/workflows/ci.yml`. **DOĞRULANMADI** — I did not read the CI file to
  see whether a backend-less job exists there; if CI always installs
  `bubblewrap`, CI structurally cannot catch this class, and that is a second
  finding for the planning run.

**Status: left RED, awaiting human judgement.** No file under `native/` was
modified by this session except the addition of `native/refenv/run.sh`.

## 5. `status_truth_test.sh` / `docs_truth_test.sh` (card item e) — AND THE
## CENSUS IS ALREADY STALE

Measured at HEAD `6f1bc3c`:

- **`native/status_truth_test.sh` — present, ran in the container offline:
  exit 0, 94 passed, 0 failed. GREEN.**
- **`native/docs_truth_test.sh` — did not exist in the tree when the clone was
  taken.** `ls native/docs_truth_test.sh` → `No such file or directory`. It is
  still absent at the end of this session.

Neither file was modified by this session.

**But a parallel worker committed to `main` while this measurement was running,
and the census above no longer describes HEAD.** Measured, not guessed:

    $ git log --oneline --reverse 6f1bc3c..HEAD
    52c283d status truth: cross silent at all three mode layers, and run the escape command the screen prints
    e51e77a gate: a mode layer of silent is a silencer — name the layer in force and print the one command that lifts it
    16e0311 f1e-c: raw container evidence   <- mine, artifacts only
    e64c1eb fixture: the measured wrong refusal — a heredoc body is not a command, on the whole-line surface too

    $ git diff --stat 6f1bc3c..HEAD -- Makefile native/
     Makefile                     |   9 +++
     native/gate.cpp              |  80 ++++++++++++++++----
     native/heredoc_prose_test.sh | 143 +++++++++++++++++++++++++++++++++++
     native/status_truth_test.sh  | 169 ++++++++++++++++++++++++++++++-----

    $ git diff 6f1bc3c..HEAD -- Makefile | grep -E '^[+-]\s*\./native'
    +	./native/heredoc_prose_test.sh

Three consequences, stated plainly:

1. **`make test` now has 104 suites, not 103.** `native/heredoc_prose_test.sh`
   was added to the `test:` target in `e64c1eb`. **It has never been run in the
   container. Its container status is UNKNOWN — not green.**
2. **The `status_truth_test.sh` GREEN (94/0) above is for the PRE-`52c283d`
   version.** That commit rewrote 169 lines of it. The number in this report is
   true of the commit it names and is **stale for HEAD**.
3. **`native/gate.cpp` changed by 80 lines** in `e51e77a`. The gate is the
   binary a large share of these suites exercise, so in principle every GREEN
   above is a statement about `6f1bc3c`, not about HEAD.

This report is honest only if read as: **"at commit `6f1bc3c`, in
`node:22-bookworm` arm64, offline."** It is not a statement about main today.

Re-running is one command and takes roughly 25 minutes:

    ./native/refenv/run.sh --out reports/kosu/RAPOR --prefix <p> --suite-timeout 1200

The parallel worker's commits were **not** measured, **not** reviewed and
**not** touched by me.

## 6. The npm diagnostic (offline, 900 s)

A single-suite re-run of `npm_install_test.sh` was taken in the same image with
the same `--network none`, at a 900 s ceiling instead of 300 s, to decide
whether the suite is slow or genuinely stuck. Result is appended below by the
same session; the raw output is at `/tmp/npmdiag/out.txt` (outside the repo, not
committed — it is a diagnostic, not evidence for a claim).

**Result: the suite is GREEN offline. It is slow, not stuck, and it does not
need the network.** 12 passed, 0 failed, exit 0.

    $ docker run --rm --network none -v /tmp/npmdiag/tree:/w -v /tmp/npmdiag/in.sh:/in.sh:ro \
        -w /w node:22-bookworm bash /in.sh
    build rc=0
    06:37:25                                  <- suite start (UTC)
    npm install: the published path (linux-arm64)
      ok   - the platform manifest names only binaries the build produces
      ok   - npm i -g installs the package and its prebuilt platform binaries
      ok   - the rabadon command is on the path
      ok   - doctor finds the prebuilt binaries (was: 'native binaries missing')
      ok   - rabadon init exits 0 on a prebuilt install (was: exit 3)
      ok   - init wrote the project's settings.json
      ok   - the hook command points at a binary that EXISTS and is executable
      ok   - a force-push is REFUSED through the installed hook — the README's first promise holds
      ok   - npm i -g succeeds with every compiler on PATH replaced by a shim that refuses
      ok   - nothing tried to compile: the shim log is empty
      ok   - rabadon --version on a compiler-free install prints 0.2.3: rabadon 0.2.3
      ok   - the gate it found is a real executable shipped in the tarball: rabadon-gate
    npm install: 12 passed, 0 failed
    SUITE RC=0
    06:46:47                                  <- suite end (UTC)

**Wall time: 562 s ≈ 9 min 22 s for one suite**, with `--network none` the whole
way. My 300 s ceiling was the wrong number; the TIMEOUT in §2 is an artefact of
my harness, not a property of the product. Corrected census:

| status | count |
|---|---|
| GREEN | **100** |
| RED | 3 |
| TIMEOUT | 0 (at an adequate ceiling) |
| NEVER RAN | 0 |
| **total** | **103** |

Two findings fall out of this that nobody asked for:

- The prebuilt claim **holds on a machine with no compiler at all** — every one
  of `cc/gcc/g++/clang/clang++/c++/make/cmake/ld` replaced by a shim that exits
  127, the shim log came back empty, and `rabadon --version` printed `0.2.3`.
  That is the README's install promise measured where it is actually made, and
  it passed offline.
- **One suite in `make test` costs 9.4 minutes.** Against the stated bar
  ("performance is a feature", "the reference environment is a clean
  container"), a test target with a single 9-minute member is a real cost on
  every contributor and every CI run. Not a defect, but a number the planning
  run should see. Where the time goes inside those 562 s was **not** measured.

## 7. ÖLÇEMEDİĞİM / NOT VERIFIED (§5.5 — mandatory every turn)

Things this session saw, or could not see, that nobody asked about:

1. **The RepoDigest is not confirmed to be a registry manifest digest.** It is
   byte-identical to the local image ID under Docker Desktop's containerd store.
   Offline I cannot check it against Docker Hub. Anyone reproducing this should
   pin by image ID.
2. **`x86_64 was not measured at all.`** Everything here is `linux/arm64`. A
   compiler warning, an alignment assumption or an endianness bug on amd64 would
   be invisible to this entire report. `docker run --platform linux/amd64` under
   emulation is available and was not run (it is slow, and the card capped time).
3. **Only `node:22-bookworm` was measured.** The stated bar is "a machine that
   has only git and a shell". `node:22-bookworm` is a fat image: it ships g++,
   python3, node and git. A `debian:bookworm-slim` run — the image that would
   actually test the stated bar — was **not** taken. There is a
   `rabadon-refenv:git-and-shell` image (274 MB) already built locally from a
   previous session; it was not used here. **This is the biggest gap in this
   report.** 100 GREEN says "green on a fat image", not "green on git and a
   shell".
4. **`make test` itself was never run end to end in the container this session.**
   The census runs the suites individually. If the `test:` target has ordering
   or shared-state semantics between suites, this measurement would not see it.
   The suites each `mktemp` their own HOME/RABADON_DIR, so cross-talk is
   unlikely, but "unlikely" is not "measured".
5. **The container ran as `root`.** That directly caused §3.3 and may be
   masking or creating other results: as root, a permission-denied assertion
   cannot fail the way it would for a real user. Any suite asserting that a
   write is refused by filesystem permissions would be a false GREEN here.
   Not audited. This is a real risk to the "100 GREEN" number.
6. **A 300 s per-suite timeout is a policy I chose**, not one the repo states,
   and it was WRONG — it manufactured a TIMEOUT for a suite that is green in
   562 s. **Per-suite wall times were not recorded**: `native/refenv/run.sh`
   does not time the suites, so I cannot tell you which of the other 102 are
   close to the wall. That is a defect in the script I wrote and it should be
   fixed before the next census. Anyone re-running should pass
   `--suite-timeout 1200`.
7. **`promises_test.sh` and the `disclosure:` target were not run.** They are
   deliberately outside `make test` (the Makefile explains why: a suite that is
   red on purpose cannot also be the base that decides whether the next action
   may run). Their container status is unknown.
8. **`make bench`, `make precision`, `native/bench.py`, `native/moat_bench.py`
   were not run.** No performance number in this report; the hot-path cost in a
   container is unmeasured.
9. **The compiler warnings in `make all` were not triaged.** The build is exit 0
   but not clean: `native/gate.cpp:454` `-Wmisleading-indentation` ("`if (w <= 0)
   break; off += (size_t)w;`" — two statements on one line, the second not
   guarded) and `native/drift.cpp:240` `-Wunused-function`
   (`generated_patterns` defined but not used). The gate.cpp one is in
   `run_claude`'s write loop and is at least worth a human's eye; I did **not**
   determine whether it is a real bug or only ugly formatting. This is off the
   card's topic and is recorded here rather than dropped.
10. **rabadon's own hook fired on this session and refused two of my commands** —
    once for `no-blind-inplace-source-rewrite` (I tried `sed -i` on
    `native/refenv/run.sh`; the refusal was correct in spirit and I used a
    normal editor instead), and once with "rabadon: tests are RED. Fix the
    failure before moving on." The second is the red-base law firing on the
    known-red base described in this report. Both refusals named the rule and
    the next command; **zero false rejects that cost real work**, but note the
    first refusal fired on a file that is not engine source and not a test —
    a new measurement script — so the rule's reach is slightly wider than its
    stated subject. Worth a look; not a bug I can prove.
11. **The first invocation of `native/refenv/run.sh` failed on a false
    precondition** — `docker image inspect node:22-bookworm` returns "No such
    image" under the containerd store even though `docker images` lists it;
    only `docker.io/library/node:22-bookworm` resolves. Fixed in commit
    `6f1bc3c` before the real run. Recorded because anyone writing a similar
    preflight will hit it.
12. **I did not verify the 100 GREEN against a second run.** Flaky suites would
    be indistinguishable from stable ones in a single sample.
