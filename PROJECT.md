# PROJECT.md — rabadon roadmap & session protocol

This file is the single source of truth for what rabadon has promised,
what is done, and what the current session is allowed to work on.
Every agent session MUST start by reading this file and MUST end by
updating the STATUS block of the promise it touched. A session that
does not update this file did not happen.

## Invariants (sealed — changing any line here requires human
## approval and a ledger event; a planning run may not touch this block)

- North star: rabadon is the trust layer of the agent era — the first
  thing a developer installs before handing an agent a repo.
- Local-first. The ledger lives on the user's machine by law.
- The agent is never made to wait. Checks run detached; the window's
  cost is measured and published, not hidden.
- Negative measurements are published like positive ones.
- Acceptance criteria are never edited in the same commit as the code
  that passes them.
- A check that cannot turn red is not a check.

## Operating rules

1. One promise per session. No session touches two promises.
2. A promise is DONE only when every acceptance check below it can
   turn red and is currently green on a clean machine (`make && make test`
   from a fresh clone, no local state). "It works on the dev box" is
   not a state this file recognizes.
3. Every DONE claim ships with the command that proves it, so anyone
   can re-run the proof.
4. Scope changes to a promise's acceptance criteria are edits to this
   file, made BEFORE the work, in their own commit. Criteria are never
   edited in the same commit as the code that passes them.
5. Known limits are written next to the promise, not hidden. A limit
   with a number beats a limit with an adjective.
6. Session end ritual: update STATUS, list what was verified vs NOT
   verified, name the single next action. Three lines minimum.
7. Builder is never the auditor. A version's GATE is verified by a
   session (or human, or independent model) that did not build it,
   from a fresh clone on a machine that isn't the dev box. The
   builder's own green is a claim, not a verdict.
8. This file is part of the seal. Once Promise 5 ships, PROJECT.md's
   invariants block and the current version's GATE lines join the
   seal set: an agent edit to them is refused like any other gate
   redefinition. Until then, rule 4 is enforced by human review of
   every diff that touches this file.

## Sprint 0 — the door (ops, half a day, blocks everything else)

- [ ] S0.1 `npm publish` — the README's first command must work.
      Proof: `npm i -g rabadon && rabadon --version` on a machine that
      never saw this repo.
- [ ] S0.2 Fix CXX fallback for real. `${CXX:-clang++}` fails under
      `make test` on clang-less Linux because make does not export its
      builtin CXX. Use `${CXX:-c++}` in every test script or
      `export CXX` in the Makefile.
      Proof: `make test` exits 0 in a container with only g++.
- [ ] S0.3 Remove or revive dead surfaces: rabadon.noseydewdrop.com
      and the GitHub Pages homepage both 403. A missing link beats a
      dead one.
- [ ] S0.4 Close the 7-day/30-day number mismatch between README usage
      sample and BENCHMARK.md. One window, one count, everywhere.
- [ ] S0.5 Strip internal notes from public files (native/G1-PIPELINE.md
      work-order tone, personal notes in SPEC-SELF-REPAIR.md).

## Promise 1 — the contract

STATUS: DONE (verified 16.08 on an independent machine)
The block is visible in the first session after init, from one source,
in Claude Code, Cursor and `rabadon run`. On an uncheckable project it
says so instead of going quiet. Proof: `bash native/contract_test.sh`
(35 checks).

## Promise 2 — a red base stops the next action

STATUS: RED — fix landed 2026-08-17, awaiting independent verification.
The recovery half was broken by a silent skip in the twin-delivery dedupe
(`native/gate.cpp:1857`); the cause and the measurement are in the session
log. `bash native/redbase_test.sh` now prints 26 ok, 0 fail on the builder's
machine, five consecutive runs and again inside `make test`. It stays RED
because rule 2 and rule 7 are not met: `make test` still exits 2 on a
separate pre-existing failure (`publish_redaction_test.sh`, 2 fails, a live
disclosure leak), and the builder's own green is a claim, not a verdict.
Goes DONE when `make test` is green from a fresh clone on a machine that is
not the dev box, verified by a session that did not build it.
Break the repo, the next action exits 2 with the real failing output
on screen, recovery is automatic when the base turns green.
Proof: `bash native/redbase_test.sh` (26) + `bash native/postuse_test.sh` (88).
KNOWN LIMIT: checks run detached; actions started inside the check
window pass on stale knowledge. The window's cost must be measured
from the ledger (actions-per-window count) and published next to the
limit. That number is owed before Promise 3 ships.

## Promise 5 — the seal (definition-of-done lock)  ← NEXT

STATUS: NOT STARTED
At task start rabadon locks a seal set: existing test files, gate and
guard config (guard.json, gate-test identity, feature/opt-in flag
files), and the acceptance file if present. Hashes land in the ledger
as a SEAL_SET event. During the task, any action that modifies or
deletes a file in the seal set stops with exit 2 and the reason on
screen. Humans update the seal deliberately via `rabadon seal --update`;
the update is ledgered with who/when/which hashes. Adding NEW test
files is always allowed — the seal protects the existing gate, not
growth.

Acceptance (all must be able to turn red):
- [ ] A1 stitchu replay: the recorded bypass diff (feature moved to
      opt-in + gate test edited to keep the tree green) MUST produce a
      refusal. Test is red if it passes silently.
- [ ] A2 redteam class "gate redefinition": ≥10 variants (flag flip in
      config, gate test removed from the list, test file renamed, suite
      command swapped, resolution changed). Target: missed = 0.
- [ ] A3 legitimate-flow fixtures: refactor outside the seal set, new
      test file added, ordinary feature work. Target: false rejects = 0,
      counted, published.
- [ ] A4 `rabadon seal --update` path works and every update is a
      ledger event; a silent seal change is itself a red test.

## Promise 3 — repair from inside the session

STATUS: NOT STARTED (starts only after Sprint 0 and Promise 5)
When the base is red, trigger repair from the session: bounded
attempts, isolated copy, project's own suite must turn green, every
test and harness file byte-identical (now enforced by the seal),
default OFF.
Acceptance: to be written in this file BEFORE work starts, in its own
commit, per rule 4.

## Promise 4 — drift

STATUS: NOT STARTED
Long-run goal drift detection. Not designed yet. Design doc comes
first, acceptance criteria second, code third.

## Version map (10 × ~100h)

Every version is an installable product release with three fields:
FEATURES — what a user can do after this version that they couldn't
before (the release notes); SHOW — the public, demonstrable moment
this version produces (a clip, a number, a story); GATE — the proof
that can turn red, checked at the boundary with the three drift
questions. Feature-level detail exists for all ten versions below.
Step-level detail exists ONLY for the current version — the planning
run that closes V(n) writes the steps for V(n+1). V1 and V2 are
commitments; V3+ may be reordered, rewritten or dropped by a planning
run. The invariants block may not.

### V1 — The Door & The Seal  ← CURRENT

FEATURES: `npm i -g rabadon` works on mac arm64/x64 + linux x64
(prebuilt binaries, no compiler needed); 2-minute quickstart; `drill`;
the contract block in Claude Code, Cursor and `rabadon run`; red base
stops the next action; the seal — definition-of-done lock with
`rabadon seal --update`.
SHOW: a 30-second clip, install to first refusal; and the stitchu
bypass diff being refused, ledger line on screen.
GATE: a stranger's machine goes install→drill refusal in ≤2 minutes;
the recorded stitchu replay is refused; `make test` green in a
g++-only container.

Steps:
- [ ] V1.1 Release pipeline: prebuilt binaries per platform, CI
      release job, `npm publish`. (S0.1)
- [ ] V1.2 `${CXX:-c++}` in every test script or exported CXX;
      CI matrix runs clean-machine g++ AND clang. (S0.2)
- [ ] V1.3 Surface hygiene: dead landings removed or revived, 7d/30d
      mismatch closed, internal notes stripped. (S0.3–S0.5)
- [ ] V1.4 Seal mechanism: SEAL_SET ledger event, refusal path,
      `seal --update` with ledgered who/when/hashes.
- [ ] V1.5 stitchu replay fixture + "gate redefinition" redteam class,
      ≥10 variants, missed = 0.
- [ ] V1.6 Legitimate-flow fixtures: false rejects = 0, counted.
- [ ] V1.7 README top rewritten user-first: the five-benefit list,
      then quickstart, architecture below the fold; FAQ gains a
      "Why not just a git hook / 100 lines of bash?" entry — answered
      with the paid-for bug classes (spelling-sensitive escapes,
      false-green words, fail-open gaps), not adjectives.

### V2 — Repair

FEATURES: `rabadon repair` — a red base is fixed from inside the
session; bounded attempts, isolated copy, project's own suite decides,
default OFF; the seal guarantees every test/harness byte identical.
SHOW: a timelapse — repo breaks, agent blocked, repair turns it green,
the ledger tells the whole story end to end.
GATE: broken fixture repo turns green with zero human edits, seal set
byte-identical; a "cheating repair" redteam class exists, missed = 0.

### V3 — The Window & Drift v0

FEATURES: window-cost meter (actions started inside the check window,
counted from real ledgers) published next to the known limit; first
drift detection for long runs.
SHOW: the number itself — "across N real sessions the detached window
let X actions through; here is the trade, measured, not adjectives."
GATE: the number in the README regenerates from the ledger; a
long-run goal-drift fixture is caught.

### V4 — Strangers

FEATURES: Windows/WSL support, monorepo support, long-suite strategy
(targeted/incremental checks), per-tool install docs.
SHOW: 10 external users known by name or handle; the first real-catch
story published with permission.
GATE: ≥10 external users, ≥1 real (non-drill) catch on a stranger's
machine, false-reject count published.

### V5 — The Report

FEATURES: `rabadon report` — weekly human-language summary of what
was refused and what it saved (tokens, resets, force-pushes); export
and OTLP polish.
SHOW: a screenshot of a real user's weekly report.
GATE: a user shares their report unprompted.

### V6 — Ecosystem

FEATURES: one-command setup per agent tool (Claude Code, Cursor,
Codex), starter-kit templates, a live docs site.
SHOW: rabadon appearing in setup guides and starter kits the
maintainer didn't write.
GATE: listed in ≥3 independent guides.

### V7 — Policy language

FEATURES: org-level policy files ("no agent force-pushes in this
org"), rules that apply above the repo, readable violation messages.
SHOW: one config line blocking the same violation across five repos,
on video.
GATE: a policy violation refused across a multi-repo set; policy
false rejects = 0.

### V8 — Team ledger

FEATURES: multi-machine chain, central sync, tamper visibility across
the team.
SHOW: two laptops, one chain; a tampering attempt going loudly
visible.
GATE: cross-machine chain verifies; a tamper fixture is caught.

### V9 — Audit layer

FEATURES: compliance/audit report export, team view, pricing.
SHOW: the first paying team.
GATE: first payment cleared.

### V10 — The standard

FEATURES: public agent-contract spec v1 + a benchmark harness anyone
can run against any guard tool.
SHOW: an unaffiliated person runs the benchmark and publishes results.
GATE: independent benchmark results exist in public.

## Planning runs

Every planning run opens with three drift questions, answered in the
session log: (1) does this version's PROOF pass on a machine that is
not ours, (2) would we still install this today if we hadn't built it,
(3) did this version move us toward the north star. This is a gate,
not a review: a NO on any of them blocks V(n+1). The next run is a
repair run against the failed proof, and repair runs repeat until the
answer is YES — the same law the product applies to a red base, a red
version stops the next version. Only after three YES answers does the
run revise the plan for what comes next.

At every version boundary this revision is a diff to PROJECT.md, in its
own commit, before any V(n+1)
work starts. A planning run may reorder, rewrite, add or drop versions
from V3 onward. It may never edit the invariants block; a diff that
touches it stops and asks for human approval, and the approval is a
ledger event. Sessions read only this file plus the current version's
spec — never the full chat history, never future versions' details.

## Session log

(append-only; newest first; three lines per session:
DONE / NOT VERIFIED / NEXT)

### 2026-08-17 — the silent skip behind Promise 2's recovery half

DONE: root-caused and fixed the two `native/redbase_test.sh` failures without
touching any test file. `native/gate.cpp:1857` deduped twin deliveries, and its
own comment reserved the 2-second time bucket for NON-tool events — but the
condition read `hook != "PreToolUse"`, which sent PostToolUse down the bucket
branch whenever the agent sent no `tool_use_id`. Two genuinely different edits
inside the same two seconds therefore produced ONE supervised event: the second
returned 0 above the branch that starts the project's own check, so no check
ran and a red base could never clear. That is why the suite passed here and
failed on CI — the bug is phase-dependent on wall-clock, not deterministic.

Measured, two edits 300ms apart, 3 runs each (`/tmp/rb-probe6.sh`):
  same 2s bucket, before the fix  -> the suite ran 1 time, verdict stayed red
  across a bucket boundary        -> the suite ran 2 times, verdict green
  same 2s bucket, after the fix   -> the suite ran 2 times, verdict green
The bucket never did its own job for tool events either: a genuine twin
delivered 1ms apart across a boundary lands in two buckets and passes through.
Tool events now dedupe only on `tool_use_id`; absent one there is no identity,
so they are not deduped. No test asserts the old behaviour —
`native/postuse_test.sh:136` explicitly ignores `recentEv` as
"dedupe bookkeeping, not verdict state".

Proof, run in this order:
  make all
  bash native/redbase_test.sh   -> 26 ok, 0 fail, five consecutive runs
  bash native/postuse_test.sh   -> 88 ok, 0 fail
  bash native/contract_test.sh  -> 35 ok, 0 fail
  make test                     -> redbase 26 ok 0 fail INSIDE the full suite
Scope of the defect was wider than the test: every second edit inside the same
two seconds went unsupervised, so catches were lost silently, not just this
recovery path.

NOT VERIFIED: `make test` still exits 2 — see the blocker below. Nothing was
run on a clean machine or a fresh clone; CI has not been seen green on either
platform since the fix. Per PROJECT.md rule 7 this green is a claim, not a
verdict, so Promise 2 stays RED until an independent run confirms it.

BLOCKER — a second, pre-existing red, and it is a live data leak.
`native/publish_redaction_test.sh` returns 26 passed, 2 failed, and it failed
identically BEFORE this session touched gate.cpp, with the older binary, so it
is not a regression from this fix:
  FAIL  the withheld bookkeeping does not hold
        withheld count is 0, expected 3; wrong rules survived
        ['no-force-push-main','no-rm-rf-outside','protect-data','no-copy-out']
  FAIL  published artifacts under site/ carry what may not be published:
        field.html: withheld project name(s) stitchu=1
        measured.json: withheld project name(s) stitchu=1
Both files are TRACKED in git and the site is public, so a project name the
redaction law is supposed to withhold is currently published. The redaction
path is withholding 0 of 3 things it should. This is a publish-blocking,
disclosure-grade failure and it owns the next session.

ALSO FOUND: `make test` mutates tracked publishable artifacts. Running it
rewrote site/index.html, site/catches.html and site/patch-notes.html with
regenerated field numbers (461 -> 468 refused, ledger 123,911 -> 124,402).
Those were minted while the base was red and publishing is paused, so they
were restored with `git restore`, not committed. A test suite that rewrites
published files is a hazard on its own.

NEXT: fix the redaction path so the withheld count is 3 of 3 and no
published artifact under site/ carries a withheld project name.

### 2026-08-17 — protocol files land, branches sorted

PUBLISHING PAUSED, AND A TAINTED RANGE. The field-numbers job
(`scripts/publish-field.sh`, launchd every 1800s) is stopped until main is
green: it mints the published figures from ledger verdicts, and while the
Promise 2 recovery bug is open a verdict it reads can be the stale one, which
it would then alias onto the live domain as fact. Two locks, on purpose — the
launchd agent is booted out, AND the script refuses a hand-run while
`scripts/publish-field.PAUSED` exists (proof: `bash scripts/publish-field.sh`
prints "PAUSED — nothing was published", exit 0). **The overnight range that
carried the counter from 490 to 502 refused was minted under the bug and is
TAINTED**: it must be re-derived from the ledger once the base is green, not
trusted. Resume ritual: delete the marker, then reload the agent.

CHALLENGE — Promise 2 is red, not DONE. Approved by the operator on
2026-08-17; the STATUS line above now reads RED. This file claimed:

    Promise 2 — STATUS: DONE (verified 16.08 on an independent machine)
    Proof: bash native/redbase_test.sh (26) + bash native/postuse_test.sh (88)

The evidence contradicts the first half. `native/redbase_test.sh` returns
**24 ok, 2 fail** on CI, deterministically, on ubuntu-latest AND macos-15,
on every run since 2026-08-16 11:28. Last green CI commit: `d2bca90`. First
red: `7ffb0fb` ("close the three holes the audit found"). Still red at
`e926fc2`. Verbatim, from run 31979858461:

    FAIL - still not green after the fix: {"ts":1786922041077,"level":3,
      "kind":"suite","cmd":"npm test --silent","verdict":"red","exit":1,
      "dur_ms":150,"tail":"FAIL: a() must return 1\n"}
    FAIL - still refusing after the check went green: the wedge is real
    red base: 24 ok, 2 fail

Both failures are in section "4. a real pass clears it"
(`native/redbase_test.sh:122-130`): after the CORRECT fix is written,
`settle green` times out and `.rabadon/net.json` still holds the stale red
verdict, so the refusal never clears. The second failure follows from the
first. This is not a cosmetic test failure — it is the recovery half of
Promise 2 ("recovery is automatic when the base turns green") not working.

Proposed diff to PROJECT.md, for human approval, NOT applied here:
Promise 2's STATUS line becomes
`RED — challenged 2026-08-17, see session log` until
`bash native/redbase_test.sh` returns 26 ok, 0 fail. Per CLAUDE.md rule
"a challenged step is treated as red", and non-negotiable #5, no V1 step
starts before this is green. `redbase_test.sh` is not to be touched: the
test looks correct and the code regressed.

DONE: PROJECT.md added to the repo (it did not exist); CLAUDE.md replaced
with the session law and removed from .gitignore so a clone carries it
(the superseded Turkish mission file is kept locally, untracked, as
CLAUDE-eski-misyon.md); dead branches `fix/publish-blockers-2026-08-15`
and `hakem-kilit` deleted local + origin, and the prunable worktree at
/private/tmp/rabadon-hakem pruned — `main` is the only branch left.
Proof: `git branch -a` lists only main/origin-main; `git ls-files | grep
-E '^(PROJECT|CLAUDE)\.md$'` lists both; both branches deleted with
`git branch -d` (not -D), which git only permits when fully merged, and
`git rev-list --count main..<branch>` was 0 for each.

NOT VERIFIED: no test was run this session — `make test` was not invoked
and the base is still red (see CHALLENGE). Nothing was checked on a clean
machine or a fresh clone beyond a local clone check of the two files. The
three PARKED items below are reported from reading, not from running.

NEXT: diagnose the two `redbase_test.sh` failures introduced by `7ffb0fb`
and fix them in the code without touching the test.

PARKED (found while reading; not in PROJECT.md; each needs its own session):
- rabadon has NEVER been published: `npm view rabadon` returns 404. Tags
  v0.2.0/v0.2.1/v0.2.2 exist, but the release workflow died on the
  darwin-arm64 build all three times and `fail-fast: true` took the
  publish job with it — it has never run to completion. Root cause: no
  pytest on the macOS runner, so `heldout_test.sh` scored 0 pass / 8 fail.
  A pytest guard now exists at `native/heldout_test.sh:121` and
  `native/harness_lock_test.sh:118`, but it is NOT VERIFIED on a real
  runner. The NPM_TOKEN secret exists (added 2026-08-04); whether the
  `@rabadon` scope exists is unknown.
- `rabadon-run` would be missing from every published platform package:
  `.github/workflows/release.yml` copies 17 binaries into
  `npm/<target>/`, while each `npm/*/package.json` `files` array lists 18.
  V1's GATE requires the `rabadon run` surface, so this blocks release.
- S0.2 still stands: ten scripts under `native/` use `${CXX:-clang++}` and
  the Makefile does not export CXX.
- S0.4 still stands: `README.md:46` says "last 7 day(s)" above numbers
  that are `BENCHMARK.md:115`'s 30-day figures; `docs/quickstart.md:148`
  repeats it.
