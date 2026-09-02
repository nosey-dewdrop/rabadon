# PROJECT.md — rabadon roadmap & session protocol

This file is the single source of truth for what rabadon has promised,
what is done, and what the current session is allowed to work on.
Every agent session MUST start by reading this file and MUST end by
updating the STATUS block of the promise it touched. A session that
does not update this file did not happen.

**The current run is KOSU-RABADON-5.md**, in the repo root: phases F0-F9.
On 2026-08-26 (F0) it replaced KOSU-RABADON.md, -2, -3 and -4, all four of
which are now cancelled and archived under `docs/archive/` with a cancellation
line at the top. KOSU-RABADON.md itself had replaced PROTOCOL-T1-T8.md on
2026-08-22, archived at `docs/internal/arsiv/PROTOCOL-T1-T8.md`.
The T1 and T2 work stands; `reports/T1/` and `reports/T2/` are unchanged. If
KOSU-RABADON-5.md and this file ever disagree, this file wins and the conflict is
written into the round's CLAIM.md — see `reports/R0/CLAIM.md` for two that
already happened.

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
machine, five consecutive runs and again inside `make test`. The redbase fix
itself is INDEPENDENTLY CONFIRMED: CI run 32021838705 is green on both
platforms, and a fresh clone at `e74c790` ran 26/0 in a third environment.
It stays RED because rule 2 and rule 7 are not met: `make test` still exits 2 on a
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

### 2026-09-02 (3) — three live runs, no red; the ledger's (b) is answered by a metric that cannot say no

Two more throwaway repos, driven by real `claude -p` (Claude Code 2.1.257,
bypassPermissions, max-turns 40), with the binary from `38a600e` bound through
the operator's global hooks:

- **live1** — `collect(item, bucket=[])`, task: add `collect_many` on top of
  it. The agent read the file before running anything, named the mutable
  default, fixed it in the same heredoc that added the feature. 4 turns,
  green → green. Ledger: 2× `tests: GREEN`, 0 SIGNAL.
- **live2** — 10 modules, task: sort `render()` keys; a golden test two
  directories away depends on key order. The agent grepped every caller, read
  the golden, checked the order in Python before editing. 12 turns,
  green → green. (The trap was also miscut — `id;name;region;score` is already
  alphabetical — my error; the agent caught that too.)

With last session's two, that is **four live runs on small repos and zero
green→red transitions.** A competent agent reads before it writes, and on a
repo it can read entirely it does not break what it cannot see. The contrast
trigger's precondition is a change whose blast radius exceeds what the agent
read — a long session in a large tree. The venue for measuring this product is
not a synthetic repo; it is the operator's own sessions, which is where every
INJECT today actually happened.

**Today's ledger (real traffic, this machine, watch mode):** 323 SIGNAL
(236 scope_drift, 42 green_redefined, 40 regression_contrast, 5
root_migration), **10 INJECT, 8 INJECT_ANSWER — all `same=false`**,
35 INJECT_CAPPED, 2 RULE_YIELDED, 139 CHECK_FAIL.

CHALLENGE — **(b) as written cannot come back false.** `INJECT_ANSWER.same`
compares the next move's signature with the one that was repeating before the
injection. For a contrast injection there was no repeating move — the "before"
is whatever command last ran — and a competent agent's next command is always
a different one. 8 of 8 `same=false` is what the metric produces regardless of
whether the paragraph was read. The devir's acceptance ("INJECT_ANSWER +
causal:true") names a field that does not exist in the code. What would
answer (b): the next move touches a file the injection NAMED and the agent had
not touched before it, or the agent's next text quotes it. Not implemented;
not in PROJECT.md; proposal only.

CHALLENGE — **the trigger still runs on vocabulary through `claimed_rc`.**
signals.h says the contrast condition is "the suite going red, or the move
claiming a non-zero status", not the error signature. But on PostToolUse
`claimed_rc = (E.failed || !err_sig.empty())`, and err_sig is the vocabulary.
Measured live at 1788355899210 and again while writing this entry: a `python3`
that PRINTED ledger lines containing "attempt 4 on the same failure" and "not
found" fired regression_contrast and the injection quoted that printout as
"the previous attempt ended with". Two false positives in one afternoon, both
this shape. INJECT_CAPPED=35 is the other face of it: two of these spend the
session's budget for that signal and the trigger is mute for the rest of a
long session — the exact session it is for.

Fixed on the way, small: a redirect target still holding a shell variable
(`> app/stage$i.py`, named live at 1788355899210) is no longer recorded as a
file. `inject_payload_test.sh` section 3b; suite 13 passed, 0 failed.

DONE: `./native/inject_payload_test.sh` 13/0, `./native/signals_test.sh` 39/0;
full `make test` exit 0, 122 suite scripts, no failing line. Transcripts and
ledgers for live1/live2 are under the session scratchpad, not the repo.

NOT VERIFIED: layer (b) — still. Not because the channel is dark (10 INJECT
today on real traffic) but because the yardstick cannot fail. False positive
RATE: two found, still not a rate. Doubled lines: RUN_START appears twice per
live run; STEP lines once — narrower than "every event twice", cause unknown.

NEXT: (1) define (b) so it can be false — the next move names a file the
injection named — and record it beside `same`; (2) stop `claimed_rc` from
inheriting the vocabulary on PostToolUse when the command is not a test and
the harness reported no failure, or cut the contrast trigger to `suite == 0`
only and measure what that loses; (3) then read a week of the operator's own
ledger, not a synthetic repo.

### 2026-09-02 (2) — the payload told the truth only when the runner spoke its vocabulary

The previous entry left the trigger firing live and the text it delivered
wrong: `The previous attempt ended with: {"stdout":"def collect(item,
bucket=[]):`. Three causes, each found by driving the binary, each with a
fixture now:

1. **The envelope was read as the output.** Claude Code delivers a Bash result
   as `{"stdout":..,"stderr":..}`; the suite verdict un-escaped it once before
   judging, the move record did not. `err_sig` and `readable_error` saw ONE
   line — the whole object — and quoted its first 120 characters, which were a
   file the agent had cat'ed. `response_text()` (gate.cpp) now hands both
   readers stdout+stderr. `readable_error` also prefers the line that IS the
   error (`E AssertionError`, `FAILED x::y`, `NameError:`) over a line that
   mentions one, and skips the `Traceback` header.
2. **A heredoc was not a change.** `cat > tests/test_b.py <<EOF` left "Changed
   since that green" empty. `shell_write_target()` asks the existing redirect
   parser for `>`/`>>` targets and reads `tee` and `sed -i`; `/dev/null` and
   `&1` name nothing. `rbsig::is_write` = Edit tool OR a Bash move with a path;
   only the contrast trigger and the payload use it — oscillation and the
   assertion-count rule stay on `is_edit` (a shell write has no text to read).
3. **The detectors ran before the verdict existed.** The move is recorded and
   tier 0 runs near the top of the event; the suite verdict is stamped 800
   lines later. So `suite` read -1 at detection time and the trigger really
   asked "did the output contain an error word". `Tests: 1 failed, 2 passed`
   after a green: CHECK_FAIL on the ledger, suite stamped 0, NO SIGNAL. The
   verdict block now calls back after stamping a red; the pass re-emits
   nothing it already said (set keyed name+why+seqs) and recomposes the queued
   text so the contrast sentence reads "it was red" instead of "it failed with
   that error". Two crashes on the way there, both measured (CHECK_FAIL vanished
   from the ledger): the callback captured block-local lambdas and strings by
   reference from a frame that had closed. `ms` is hoisted to event scope, the
   queued args live behind a shared_ptr, the lambda chain is captured by value.

Live, unplanned: while this session ran its own suite, rabadon in watch mode
injected into THIS session's PreToolUse —
`rabadon: this suite was green earlier in this session. The file last edited
is native/inject_payload_test.sh. The previous attempt ended with:
inject-payload: 10 passed, SOME FAILED. Contrast: after \`…python3 - <<'PY'…\`
the suite was green; after …` — the trigger fires on real traffic, the file
named was the right one, the quoted line was the run's own summary. The green
command it names is a python heredoc clipped mid-line: the `raw` field is
96 bytes and a long compound command reads as noise there. NOT fixed.

DONE: `native/inject_payload_test.sh` 11 passed, 0 failed (wired into `make
test` after inject_answer_test.sh); moves 22/0, signals 39/0, signals_screen
38/0, inject_answer 16/0, postuse 88/0 — unchanged by this work. Proof:
`./native/inject_payload_test.sh && ./native/signals_test.sh`.

Full `make test`: exit 0, 122 suite scripts ran, no failing line in the log
(the previous entry's "119/4" was a different runner's count; not reconciled).

NOT VERIFIED: Layer (b) — did the agent's next move change
because of the injection — still has no INJECT_ANSWER with `causal:true` in
any live run; the self-injection above is delivery, not causation. False
positive RATE still unmeasured. The doubled ledger lines from live runs
(previous entry, D) not investigated. `raw` at 96 bytes makes the contrast
sentence unreadable for compound commands (above).

NEXT: run `claude -p` on the synthetic green→heredoc→red repo again with this
binary and read the delivered text end to end; then chase INJECT_ANSWER
causal:true, which is the product's thesis and is still unmeasured.

### 2026-09-02 — the second cause: the refusal arm was eating the repair arm

Line 338 of this file left it open: *"whether a correctly bound native gate
actually produces INJECT in this harness is **not** established."* It is
established now, and the answer has a second cause the tur-16 diagnosis did
not reach. Tur 16 was right that arm B bound `gate.mjs`, which cannot speak.
It is not the whole story: the native gate, correctly bound, also did not
speak — for a different reason, in the exact scenario the product exists for.

DONE — **measured, on this machine, against `native/rabadon-gate` built from
`7d7f805`.** Driving the gate directly with a repeating-failure scenario
(same `pytest -q`, no edit between, PreToolUse + PostToolUseFailure pairs):
`repeat` fires 8 times and **0 INJECT** are delivered. Two links were broken,
independently, and each one alone is sufficient:

1. `inject.h speaks()` did not speak for `repeat` — the comment at
   `inject.h:70` parks it in the "weak → ledger only" arm. The most frequent
   signal in the product was wired to the block arm and never to the
   injection arm.
2. `gate.cpp` `loop-stop` calls `block()`, which `exit()`s. The delivery site
   ("R4: deliver the diagnosis") sits **below** every refusal by deliberate
   design — its own comment says *"HERE, AND NOWHERE EARLIER … an injection
   cannot move a verdict."* So the moment a loop is detected, the process
   leaves before the diagnosis it just assembled is handed over.

Proof that the mechanism itself was never the problem: with `loop-stop`
unable to fire (command varied so `cmdRepeat` never reaches 3) and `speaks()`
patched, the same scenario delivers **2 INJECT + 2 INJECT_ANSWER**, with real
text on stdout — `rabadon: attempt 3 on the same failure … Contrast: no green
move is on record this session`. The channel works. The ordering was the wall.

DONE — **fixed, per the operator's ruling (2026-09-02), in `8c99e69`.** Rule:
*non-sealed behavioural rules produce no refusal while an injection is
pending; the diagnosis is delivered and the call is allowed. For sealed rules
the ordering does not change: an injection may not move a security decision.*
Implemented at the top of `block()` so both the enforce and watch arms are
covered from one place, with a new `RULE_YIELDED` ledger event so a stand-down
is never silent. Same loop scenario, before → after: INJECT 0 → 2,
INJECT_ANSWER 0 → 2, WOULD_BLOCK 3 → 1. The surviving WOULD_BLOCK is correct —
nothing was pending at the first detection, so the rule spoke.

DONE — **suite: 119 pass, 4 fail** (`for t in native/*_test.sh`). The four
(`machine_intact`, `make_deps`, `promises`, `stdin_program`) were re-run on
the stashed, unmodified tree and fail there too: pre-existing, not caused by
this change. `loop_test`, `loop_body_test`, `inject_answer_test` and
`signals_test` all pass with the change in.

NOT VERIFIED — **the agent's half.** Everything above drives the gate with
synthesised hook JSON; no Claude Code session was run, so whether a real agent
reads the paragraph and changes its next move is still unmeasured, and that is
the product thesis. Also unmeasured: the latency cost of the extra
`injPending` check on the hot path; whether standing a rule down can let
through an action a user wanted refused (the false-negative direction this
trade opens, by design); the four pre-existing reds were not diagnosed; and
`RULE_YIELDED` has no test yet. The KOŞU v9 document's Appendix B figures
("24/24 red, then 15/24 after the trigger patch") were checked against a real
run and do **not** reproduce — the trigger patch alone leaves 0/24, because
the scenario in that test puts an edit between each command, and with an edit
as the newest move `repeat` never fires at all. That document also freezes
`0/24` as its acceptance bar while its own `e4` assertion is hardcoded
`false`, so the bar is unreachable by construction.

DONE — **live, twice, and the result is negative in a way that matters.** The
fixed binary was bound as PreToolUse/PostToolUse/PostToolUseFailure hooks in
two throwaway projects and driven by a real `claude -p` session (Claude Code
2.1.257, `--permission-mode bypassPermissions`, `--max-turns 40`). Scenario 1:
`calc.py` correct but shadowed by a `calc/` package whose `add` was wrong.
Scenario 2: order-dependent mutable-default bug — `test_b` passes alone, fails
in the suite. Both are genuine compounding-error shapes, neither is staged for
a detector. The agent solved **each one in a single pass**, named the real
cause, and re-ran the suite to verify.

Ledger for both sessions: **0 SIGNAL, 0 INJECT, 0 INJECT_ANSWER.** (The
`WOULD_BLOCK` lines in the spool for that window are the operator's own shell,
not the measured agent.) So the delivery fix above is real but it was never
exercised live: `repeat` needs the same command three times with no edit in
between, and a competent agent on a small, well-scoped task does not do that.

**The bottleneck is the trigger, not the channel.** The channel is fixed and
proven in simulation; the condition that opens it is too rare to be worth
anything. This is the same shape as the ledger's own history — one
`INJECT_ANSWER` in 29 days is what a count-based trigger produces, not what a
broken channel produces. The KOŞU v9 document already reached the right
conclusion here and its wording stands: *"tetik — bilgiye bağlı, sayıya
değil"*, with T0 (the move touches ground the goal never named), T1 (contrast
against the last green), and T2 (this error signature was closed before, in an
earlier session). The code implements none of those; it implements counting.

NOT VERIFIED — whether the agent acts on the paragraph, still. Two live runs
produced no injection to act on, so layer (b) remains unmeasured on real
traffic and the product thesis is untested. Also unmeasured: whether a long
run (hours, not 40 turns) produces loops that a short one does not — the whole
premise is about long runs, and both measurements here were short.

DONE — **the trigger is information-based now, and the reason it was silent was
one layer below it** (`31420dd`). Chasing "why does no signal fire" by running
the gate instead of reading it landed on `gate.cpp`'s default test vocabulary:
`ctest|--test|npm test`. `python3 -m pytest -q` is not a test run to that
line. With no `testCommand` in guard.json — the default install — no move on a
Python repo was ever stamped green or red, `lastTestVerified` stayed 0, and
every contrast the injection can draw is anchored on "the suite was green
earlier". The product was structurally silent for the default install of the
most common language it meets, and nothing in the ledger said so, because an
unrecognised test run looks exactly like any other command.

Four changes, each measured before and after:
- the vocabulary now covers pytest/unittest, go, cargo, jest, vitest, mocha,
  `make test`, rspec, phpunit, dotnet, maven, gradle, bun — anchored on runner
  names, never on the bare word `test`.
- a pass count with no failure vocabulary beside it now reads as green, so
  `2 passed in 0.02s` finally is one. This produced **two false greens during
  the work and both were caught by running it**: `1 failed, 2 passed` (the
  failure count is number-first, which the `fail: N` form never sees) and the
  same line with an unexpanded `\n` gluing the count to a letter so `\b` found
  no boundary — the trap this file already documents for the red half. Fixed
  by deciding on words after stripping zero-counts, not on a bounded digit.
- `regression_contrast` (signals.h): fires on the FIRST failure after a green
  when edits landed in between, and carries the changed files. No counting.
- it triggers on a red suite or a non-zero claimed rc, never on an error
  signature alone; and an Edit's response no longer yields a signature at all.
  Both were live false positives: editing a file containing the word `failed`
  recorded an error that never happened, and the injection quoted the diff back
  to the agent as "the previous attempt ended with".

What the agent receives on a first red, verbatim from the run:
> rabadon: this suite was green earlier in this session. Changed since that
> green: test_b.py, store.py. The file last edited is test_b.py. The previous
> attempt ended with: FAILED test_b.py::test_x - AssertionError: assert 2 == 1.

Suite: **119 pass, 4 fail** — the same four that are red on the unmodified
tree. `postuse_test` broke twice during this work (BR13) and is green again,
88 ok / 0 fail.

NOT VERIFIED — the live loop was **not** closed. Every measurement above drives
the gate with synthesised hook JSON or observes it inside the operator's own
session; no `claude -p` run has yet been observed producing `INJECT` followed
by a changed move, because each fixed layer revealed the next one underneath.
False-positive rate is unquantified: two were found by inspection, in one
afternoon, in one session — that is not a rate. The four pre-existing reds are
still undiagnosed, `RULE_YIELDED` and `regression_contrast` have no tests, and
the latency cost of the new work on the hot path was never measured.

DONE — **the trigger fires on live traffic, for the first time** (`72e036e`).
Four `claude -p` sessions were run against the current binary, each one
exposing the next layer:

- Run 3 caught a **false red the previous commit introduced**: the agent ran
  `python3 -m pytest -q 2>&1 | tail -5; ls; cat *.py`, the `cat` printed test
  sources containing `assert`, and a suite that had just reported `2 passed`
  was stamped RED. Before that commit the same run was merely unrecognised, so
  the change turned silence into a wrong verdict — the direction this file
  already calls the expensive one. Fixed the way the repo fixed it once
  before, in the other direction: **only a count may answer a count.** A pass
  count is disqualified by a failure COUNT, never by loose vocabulary, and
  `declaredPassCount` now suppresses a bare failure word exactly as
  `declaredZeroFailures` does. Both failure-count reads drop the leading `\b`
  — with an unexpanded `\n` the digit is preceded by the letter `n` and no
  boundary exists. That single detail broke `postuse_test` BR13 twice.
- Run 4 caught the trigger's own blind spot: `regression_contrast` required a
  counted Edit move between green and red, and the agent created the failing
  file with `cat > test_b.py <<EOF` inside a Bash command. Nothing the ring
  calls an edit ever landed. Writing files through the shell is normal agent
  behaviour, so **the transition is now the evidence** and the file list is a
  payload — named when the ring knows it, omitted when it does not.

With both fixed, the live ledger shows `SIGNAL regression_contrast` →
`INJECT` delivered on the next PreToolUse, landing immediately before the
agent's root-cause fix. Suite: 119 pass, 4 fail (the same four).

NOT VERIFIED — **layer (b) is still open, and the payload is wrong.** No
`INJECT_ANSWER` was recorded in that run, so "the agent read it and moved
differently" remains unmeasured; the injection arriving before the fix is
sequence, not causation. And the text it delivered was poor:

> rabadon: this suite was green earlier in this session. The previous attempt
> ended with: {"stdout":"def collect(item, bucket=[]):\n bucket.append(item)…

`readable_error` took the compound command's stdout — a file dump from `cat` —
instead of the assertion. A paragraph whose "previous attempt" quotes a source
listing is worth little to the agent, and it names no changed files because
the shell writes are invisible to the ring. Also still unmeasured: the
false-positive rate, the hot-path cost of this work, and tests for
`RULE_YIELDED` and `regression_contrast`. Every event in these runs appears
**twice** in the spool, which is unexplained and was not investigated.

NEXT — make the payload true before anything else: `readable_error` must
prefer the failing assertion over arbitrary stdout, and the changed-file list
must see shell writes (`>`, `>>`, `tee`, `sed -i`, heredoc) as edits. Then
re-run this protocol and require `INJECT_ANSWER` with `causal:true` in the
ledger, which is layer (b) and the actual verdict on the thesis.

### 2026-08-24 (koşu tur 16) — arm B was never rabadon: it binds the LEGACY JS gate, on one event

START: the PARKED item from `reports/R7/DENEMELER.md` — "arm B may be a rabadon
that never speaks to the agent; NOT MEASURED". One step: diagnose it. Proof
command: `bash reports/R7/accept.sh` plus the spool census in
`reports/R7/TESHIS-B-KOLU.md`. No agent was run; no money spent.

DONE — **measured, and the suspicion is confirmed and worse than written.**
Full evidence in `reports/R7/TESHIS-B-KOLU.md`. Two independent causes, either
one sufficient. (1) `ab_run.sh:25` binds `hooks/gate.mjs`. The accumulation
engine is not in it: SIGNAL (gate.cpp:3166,3196), `queue_injection`, INJECT
(4724) and the line that actually speaks to the agent, `additionalContext`
(4707), exist **only** in `native/gate.cpp`; `gate.mjs` has **zero** matches for
`additionalContext`. `hooks/install.mjs:111` calls `gate.mjs` the *"legacy JS
gate path — still recognized (and replaced)"*: the real install deletes it and
substitutes the native binary. (2) `bagla_hook` registers only `PreToolUse`,
so even the native gate would emit nothing — the chain is PostToolUse → SIGNAL
→ queue_injection → next PreToolUse → INJECT, and the first link is not
registered; COUNTER is on SessionEnd/Stop (4001,4015), RUN_DONE on Stop (4093).
A real `rabadon init` binds five events (install.mjs:169-175).
Census of the spool, split by writer (`run:"ng-…"`+`sess`/`call` = native,
`run:"mt7b…"` = node): **gate.mjs wrote 51 lines and all 51 are STEP_START** —
zero SIGNAL/INJECT/COUNTER/RUN_DONE/STEP_OK. The dataset's only SIGNAL+INJECT
is on autograd__B at 14:08–14:10 with an `ng-` run id: the native gate, inside
turn 14's **already-invalidated** window. Injection never happened in a valid
arm-B run. Two hypotheses were eliminated by measurement: `timeout 2` does not
kill the hook (5 clean-sandbox runs, 0.14 s, rc=0, all wrote), and turn 14's
"arm B was muted, fixed" is too generous — `gate.mjs` emits **zero bytes of
stdout on PreToolUse, PostToolUse, Stop and SessionEnd alike**. Unmuting
restored the ledger, not the voice.

DONE — **acceptance re-run: 23 green, 3 red** (`bash reports/R7/accept.sh`,
`reports/R7/accept.out`). The diagnosis explains **two of the three reds**:
6e (`estimated_saved`) twice over — COUNTER never fires in arm B, and even if
it did, `saved_usd` multiplies by `chains_cut`, counted only from INJECT/STOP
(gate.cpp:2027, counter.h:23), which is 0 — and 7b, which hangs off 6e. It does
**not** explain 2b (daemon latency), a separate open front.

DONE — **a green that must not be reported as one.** 7a passed this run
("arm B improves on net tokens", A 35 620 / B 33 221). Per the above, the
injection was never in the arm, so 7a is not a verdict on the thesis. 6b/6c/6e
are unreadable for the same reason and 6d is a structural zero (`gate.mjs`
never writes `wouldRefuse`). `ab_run.sh`'s own binding acceptance
(`ledger_new_lines > 0`) passed an empty gate: STEP_START satisfies it, and it
never asks whether the gate SPOKE.

NOT VERIFIED — whether a correctly bound native gate actually produces INJECT
in this harness is **not** established: the only instance of it is 1 SIGNAL +
1 INJECT in one invalidated run out of 4 instances, so the injection rate may
be low even after the fix. Whether the injected text reached the agent's
transcript was not checked in `*.stream.jsonl`. `orkestra/src/tick.py` is bound
to the same five global events and its effect on turn 14 was not examined.
2b/2c were measured on a **loaded** box (load avg 6.24, Chrome GPU 522 % CPU,
another project's `surface-pattern` at 91.7 %): 2b read 2443.8 µs against
1385.2 µs previously, and those two numbers are **not comparable** — the gap is
not evidence of a regression, though red is correct in both readings. Nothing
was measured in a clean container. **No fix was applied** this session.

NEXT: fix `ab_run.sh` before any further paid run — point `GATE` at
`native/rabadon-gate`, bind the five events from `hooks/install.mjs:169-175`
(preferably by calling install.mjs rather than hand-copying it, since the
hand-copy is exactly what drifted), and harden arm B's binding acceptance to
require a SIGNAL/INJECT/COUNTER rather than any ledger line.

### 2026-08-24 (koşu tur 14) — R7's two-armed run runs; the control arm was never clean, and now it is

START: operator's turn-12 CEVAP (fourth path: the agent IS `claude -p`), then
A4 from where turn 13 stopped. Turn 13's single NEXT was: does rabadon actually
emit `estimated_saved`? Proof commands: `./reports/R7/accept.sh`, `make test`.

DONE — **the run exists and ran end to end.** `reports/R7/ab_run.sh`: no Docker,
mirror repo cloned per instance, `.git` deleted from the agent's tree, local
venv + pytest, held-out F2P files restored from `origin/main` only at scoring.
Acceptance moved **14 green / 12 red → 23 green / 3 red**
(`./reports/R7/accept.sh`). `make test` rc=0, identity 37/0. Raw record:
`reports/R7/ab_run.jsonl`; write-up `reports/R7/KOSU.md`.

Three separate invalidations were caught **before** any number was believed,
each by asking "did the thing I assumed actually happen?" and measuring:

1. **`estimated_saved` does not exist and cannot be derived.** rabadon emits
   `saved_usd` (USD); accept.sh 6e compares it to a **token** difference. The
   real arm-B COUNTER event settled the workaround too: `saved_usd:null`,
   `reason:"no-price"`, `calls:0`, all token subtotals **0**. 6e/7b are
   structurally unclosable — an operator decision, not a run failure.
2. **Arm B was muted.** I wrapped the hook with `>/dev/null 2>&1`; Claude Code
   hooks speak to the agent through stdout, so rabadon wrote its ledger and
   never said a word. Separately, B1.5's literal recipe carries `</dev/null`,
   which makes the gate **deaf** (measured: 0 ledger lines vs 1 without it) —
   B1.5's own binding-acceptance cannot be met by its own recipe. **CHALLENGE**
   filed in `reports/R7/DENEMELER.md` deneme 16; the document was not edited.
3. **The control arm was never rabadon-free.** The operator's global
   `~/.claude/settings.json` attaches `rabadon-gate` to every hook event of
   every session on this machine. Arm A wrote 36 and 40 ledger lines of its
   own. Fixed with `--setting-sources local` (measured: 0 lines without the
   settings file, 1 with it) and a new **control-arm purity** condition — the
   mirror of B's binding acceptance, whose absence is exactly where this leaked.

All invalidated rows were quarantined, not deleted:
`ab_run_INVALID_muted_hook.jsonl`, `ab_run_INVALID_global_hook.jsonl`.

DONE — **the exclusions were my bugs too, and fixing them raised N.** Three
instances failed pre-verification; reading their pytest logs showed all three
were harness faults, not bad instances: conan and feedparser died in conftest
on missing test **extras** (`mock`, `responses`), and astroid's "73/120" was
really `2 failed, 73 passed, 45 skipped` — my counter treated skips as
failures. Fixed (extras installed; P2P now scores "did not fail", F2P scores
"actually passed"). feedparser then ran and both arms solved it. N: 3 → 4.

DONE — **the result, stated plainly.** A and B both fix **75.0 %** (4 tasks);
tokens A 35 620 / B 33 221. accept.sh 7a goes green on the token line, **and
that green is not evidence**: the fix rate is identical, and the per-task
direction is split **2–2** — B is cheaper on autograd (−12.0 %) and pydicom
(−24.5 %), dearer on oauthlib (+4.4 %) and feedparser (+7.7 %). The aggregate
−6.7 % is the mean of four measurements half of which point the other way.
There is one measurement per cell and no variance estimate, while the same
task+arm swung 16–52 % across runs. Run-to-run noise exceeds the between-arm
gap, so per KOSU-RABADON-2.md:61-62 **the number is not published.** What this
turn proved is that the measurement chain works, not that the thesis holds.

NOT VERIFIED — no agent run was repeated under identical conditions, so there
is **no variance estimate**; two of the six pre-registered instances still did
not run (conan's conftest wants heavy `test/functional` deps; astroid has 2
P2P tests already failing on the broken branch), so N=4 not 6; turn 13's
"7/10 clean" was an upper bound produced by a 2-test P2P sample; P2P is
capped at 120 of 574–4174 (`p2p_cap` is in every row); `joke2k__faker` was
swapped for conan because its `problem_statement` is **empty** — and the
substitute did not run either, so that swap bought nothing; 18 033 of SWE-smith's
59 136 rows (**30.49 %**) are likewise empty, a selection criterion nobody was
applying; egress is best-effort only (`claude -p` must reach the API); measured
on this macOS arm64 box, not a clean container; 2b (daemon latency, 1341 µs vs
1000 µs ceiling) is untouched and out of this run's scope.

NEXT: decide `estimated_saved` (6e/7b) — the only paths left are (b) make 6e a
dollar-to-dollar comparison using `total_cost_usd`, which needs an edit to
accept.sh and the frozen ON-KAYIT and therefore human approval, or (c) leave
both red. Option (a), deriving tokens from the counter, is dead and measured.

### 2026-08-17 (5) — the project column becomes an identity, and `make test` is green

START: two steps, in the operator's order. (1) the NEXT of the last session — make
the published `project` field carry a project identity rather than a cwd basename.
(2) the approved structural decision — move the deliberate-red disclosure gate out
of `make test` into its own target and its own CI job. Proof commands: `make test`,
`make disclosure`, `python3 site/allowlist.py --list`, and CI on both platforms.

DONE (1) — THE IDENTITY FIX. `native/gate.cpp:1829` writes `project =
basename(cwd)`, and every published project name descends from that string. A
basename is not an identity, so the column was publishing directories as
repositories. Four commits, and the criterion moved in its own commit ahead of
the code per non-negotiable 2.

  72 distinct names -> 53.  off-list 60 -> 41.  Every collapse has a reason that
  can be checked by someone who is not on this machine:
    the home directory   116 records, in TWO spellings — `home`, and the `~` a
                         guard path leaves after unhome(); 7 rules were published
                         under `~` as though home were a repository
    rabadon's own trees  `fixed` is created by native/guard_allow_twin_test.sh:64
                         with `"project": "fixed"` in its guard; the rbprobe/rbd-
                         probes; the 12 bench repos
    not project roots    `spool`, `damla_projects_2026`, `p` — the last two are
                         glossed as "the projects root" and "a scratch repository"
                         in site/build.py's own table, which is where this defect
                         was papered over instead of fixed
    one project, two     idea garden/idea-garden, just ballet/just-ballet,
    names                message-in-a-bottle/messageinabottle,
                         urun-psikolojisi-kitap/psikoloji-kitabi,
                         apache-airflow/airflow. The census published the name a
                         guard DECLARES about itself; 10 of 63 guards declare a
                         name their directory does not have. Identity is where a
                         project lives, and the guard path is beside every rule in
                         the published file, so this is checkable off-machine.
    a scrub residue      `(withheld)-showcase` is what is left after a name is cut
                         out of a longer one. Not a second project.

AND IT FOUND TWO LIVE LEAKS, which is the part that mattered more than the count.
  a. Two guards declare a nickname; both their directories are on the operator's
     private withhold list and neither nickname is, because that list is written
     in directory names. Every rule record for those two projects was dropped —
     and their by_project AGGREGATE ROWS survived, published under the nicknames,
     stating how many rules each withheld project has. No record carried a path,
     so nothing in the record could be judged. The census now decides AGAIN after
     the identity pass (pass 4 of 5) and drops them, counted in the published file
     as `identity.by_project: 2`.
  b. Regenerating measured.json put `no-blanket-add-<withheld>` back verbatim — a
     rule id ending in a withheld project's name. It was found on 2026-08-17 and
     fixed IN THE ARTIFACT (commit c3f6e21 edited two published files; the
     generator was left alone), so the next `--write` reinstated it. Fixed at the
     cause: a rule id is free text and goes through the redactor like free text.

NOT A COUNT-DRIVEN COLLAPSE, and it is tested from both sides.
native/identity_test.sh (37 cases) proves each rule fires AND proves an underscore
is not rewritten, a dot inside a name is part of the name, an unknown label stays
a project name in front of a human, and that site/non-projects.txt cannot grow
into a blanket (<=20 entries, every one with its evidence above it, format
checked). Mutation-tested both directions before it was committed: stop
collapsing the residue -> 2 fail; collapse everything unknown -> 8 fail.

THE NUMBER THAT FELL IS RABADON'S OWN, published as it fell. The lab filter was
under-inclusive and lived inside one of the three generators that publish a name.
Widening it correctly costs the field headline 37 WOULD_BLOCK and 77 STOP that
were rabadon's own probe trees counted as field evidence.

AND A COUNT THAT FELL FOR A REASON THAT IS NOT THIS WORK: the census publishes 39
fewer rule records than the file on disk did. The operator's private list grew
from 11 terms to 12 since the last publish. Verified by running the PREVIOUS
generator against the CURRENT list — 328 published, 102 withheld, identical but
for this change's 2. Attribution checked rather than assumed.

DONE (2) — THE GATE MOVED OUT. `make disclosure` is its own target with its own
CI job on ubuntu-latest and macos-15, fail-fast off. Same suite, same fail-closed
allowlist (a missing file allows NOTHING), same exit code 2. Not one name was
added to the allowlist to shrink the number, and the check was not made lenient,
advisory or default-allow. Only the wiring moved. The reason is the sentence
already written above `promises` in the Makefile: a suite designed to fail cannot
also be the gate — `make test` is what rabadon's red-base law runs here, so a
deliberate red was refusing every action in rabadon's own tree, including the
actions doing the triage. It refused this session's commands twice.

Proof:
  make test                        EXIT=0, 0 FAIL lines across 94 suites
  make disclosure                  exit 2, "53 name(s) found, 12 allowed, 41 off-list"
  CI run 32050931727 (e42251a)     ubuntu-latest  success
                                   macos-15       success
                                   disclosure ubuntu-latest  failure, same verdict
                                   disclosure macos-15       failure, same verdict
  ./native/identity_test.sh        37 ok, 0 failed
  ./native/publish_redaction_test.sh  28 ok, 0 failed (27/1 at the criterion
                                   commit, red on purpose, before the code landed)
  The run before the move (old Makefile, all 94 suites incl. the gate) had
  exactly 1 FAIL and it was the gate — so the identity work broke nothing.

CORRECTION, FOUND WHILE STARTING V1.2 AND WRITTEN AGAINST THIS SESSION'S OWN
CLAIM: `make test` green does NOT mean every suite in native/ is green. There are
97 `*_test.sh` files and the Makefile names 96 of them plus one non-test script;
two suites are wired into nothing:
  native/parser_unify_test.sh    PASS (69 checks) — green, just not run
  native/stdin_program_test.sh   FAIL (76 passed) — RED, and not run
The two failures in it are FALSE REFUSALS, which CLAUDE.md counts at the same
severity as a missed catch: "a redirect target is not a delete target: refused,
and refusing it cuts real work", and the numbered-descriptor twin of it. They
predate this session — the same two fail at the previous commit with the CXX
change stashed, so this session did not cause them and did not fix them.

This is the masking problem the last session fixed at the END of the target,
reappearing at the other end: a suite that is not in the list cannot mask
anything, and nothing can catch it either. It is NOT wired in here on purpose.
Wiring a genuinely red suite into `make test` turns rabadon's own base red again
one commit after the deliberate red was moved out — and unlike the disclosure
gate this red is a real defect, so the red-base law would be right to stop
everything. That is a decision with a real cost either way and it belongs to the
operator, not to the session that happened to find it.

READY FOR INDEPENDENT VERIFICATION — Promise 2 was NOT flipped, deliberately.
`make test` is green on the builder's machine and green on CI on both platforms.
Rule 7 is still unmet: no fresh clone, and the builder's own green is a claim,
not a verdict. The auditor runs the fresh-clone clause. Promise 2's STATUS line
is untouched.

NOT VERIFIED: no fresh clone on a machine that is not the dev box; no g++-only
container (S0.2 still open). The 41 surviving names are NOT decided — none of them
was decided here, and deciding them is not a session's to make. Rule ids other than
the one in field.rules_list still do not pass through the content redactor
(`stop_by_rule`, `would_block_by_rule`, `wrong_by_rule`, and field.jsonl's `rule`);
field.jsonl is protected by the record-level drop instead, and the counters
currently carry no withheld term — but that is luck, not a mechanism. The gate
itself still writes `basename(cwd)`: this session fixed the PUBLISH path, so
history is unchanged and future records will keep arriving as basenames until
gate.cpp is fixed. A ledger record carries no path, so `reports` and the other
subdirectory labels cannot be resolved from history at all.

THREE THINGS FOR THE OPERATOR, none of them fixable by a session:
  1. `msducky-stays-private` is a live rule id in the published census, and its
     own `why` reads "portfolio law: msducky-abone stays PRIVATE (KVKK), never
     enters the public wall/repo". The name is NOT on the private withhold list,
     so nothing withholds it, and allowlist.py cannot see it (it reads `project`
     fields; a name inside an identifier is its documented known limit). This is
     the same class as the leak fixed on 2026-08-17. It predates this session.
  2. `pattern-bridge` (2 records, off-list) resolves on this machine to
     `~/damla_projects_2026/<withheld>/engine/pattern-bridge` — a component
     directory of a withheld project. Publishing the name discloses a part of it.
  3. rabadon's own drift rule `promise-off-target` blocked this session's first
     edit under site/: `.rabadon/promise.json` declares areas `^native/`,
     `^Makefile$`, `^scripts/` and six more, and `^site/` is not among them —
     while the last five sessions' work (the redactor, the census, the disclosure
     gate) has been almost entirely under site/. Either the promise is stale or
     that work is drift. promise.json was NOT edited: changing gate config to
     unblock myself is the move this product refuses. The rule is right that
     something disagrees; only the operator can say which side.

V1.2 STARTED, NOT DONE. The half that could be proven here is done: all ten test
scripts that hardcoded `CXX="${CXX:-clang++}"` now say `${CXX:-c++}`. make does
not export its builtin CXX, so under `make test` that fallback is what actually
runs, and on a Linux box with only g++ installed `clang++` is a command that does
not exist. Proof: `make test` EXIT=0, 0 FAIL lines, and `CXX=g++
./native/cmdtext_test.sh` -> PASS (61 checks).
  NOT DONE, and the step stays unchecked: the Makefile still defaults
  `CXX ?= clang++`, so `make all` itself would still fail on a g++-only machine;
  and the CI matrix does not yet run g++ AND clang. Flipping the build's default
  compiler switches ubuntu CI from clang to g++ under -Wall -Wextra, which is a
  change that deserves its own session and its own red to watch. The step's own
  proof — "`make test` exits 0 in a container with only g++" — was not produced:
  there is no container here. UNVERIFIED, and the box stays unticked.

NEXT: the two unwired suites above — decide whether `native/stdin_program_test.sh`
goes into `make test` red (the honest reading of the red-base law) or gets its two
false refusals fixed first. Then the operator triages the 41 names below; then fix
`native/gate.cpp:1829` so new records carry the project ROOT rather than the cwd
basename (the source half of this session's fix), with a test that runs the gate
from a subdirectory of a git repo and asserts the repo's name on the pipe.

THE 41, one line per name, for triage. `repo` = a git repository of that name
exists here; `dir` = the directory exists and is not a repository; the last three
are not projects at all and history cannot say what they were.
  [ ] youkiddingme                 33  repo
  [ ] icerik                       26  dir   ~/damla_projects_2026/icerik
  [ ] seviyorsevmiyor              19  repo
  [ ] ir-globe                     17  repo
  [ ] parmakestra                  14  repo
  [ ] inf-baseline-kernel          12  dir
  [ ] kisalafinuzunu               11  repo
  [ ] missingsemicolon             10  repo
  [ ] moonlight                    10  repo
  [ ] nosey-dewdrop.github.io      10  repo
  [ ] sunflower                    10  repo
  [ ] noseydewrites                 9  repo
  [ ] shortstorylong                9  repo
  [ ] sightstone                    9  repo
  [ ] vibecodedflopware             9  repo
  [ ] damla_portfolio               8  repo
  [ ] idea-garden                   8  repo
  [ ] peek-a-book                   8  repo
  [ ] psikoloji-kitabi              8  repo
  [ ] just-ballet                   7  repo
  [ ] ladybug                       7  repo
  [ ] messageinabottle              7  repo
  [ ] mumucakes                     7  repo
  [ ] musical-improvisation-tool    7  repo
  [ ] snailmail-web                 7  repo
  [ ] wildflower.dev                7  repo
  [ ] blog                          6  repo  (three of them exist; ambiguous)
  [ ] creator-books                 6  repo
  [ ] houndhub                      6  repo
  [ ] idea-parking                  6  repo
  [ ] ir-globe-showcase             6  repo
  [ ] lingolingo                    6  repo
  [ ] sahaf                         6  repo
  [ ] seviyorsevmiyor-showcase      6  repo
  [ ] synthjury                     6  repo
  [ ] visionboard                   6  repo
  [ ] benimstilim                   5  repo
  [ ] reports                      47  NOT A PROJECT — five `reports` directories
                                       exist here, one of them inside the withheld
                                       tree. A subdirectory published as a repo.
  [ ] pattern-bridge                2  NOT A PROJECT — a component directory of a
                                       withheld project (see finding 2 above)
  [ ] 2026-08-01-real-defect-mine   1  NOT A PROJECT — it is
                                       rabadon/reports/2026-08-01-real-defect-mine
                                       (site/finding.py:36), a directory in THIS repo
  [ ] falmarx                       1  repo

### 2026-08-17 (4) — the gate moves last, and the 60 are not 60 decisions

START: one step — the approved Makefile ordering decision (move the allowlist
gate to the END of the test target so a red gate cannot mask the suites behind
it). Proof command: `make test`, reading the order suites are invoked in and the
count of FAIL lines in the whole run.

DONE — the ordering, and it is the only thing this session changed. The gate was
at Makefile:777, position 87 of 94, immediately after its sibling
`publish_redaction_test.sh`. `make` stops at the first failing recipe line, so
while the gate stood red the last 7 suites never ran under `make test` at all —
last session had to run them by hand to know they were green. Moved to the end,
after `rule_census_test.sh`, with its comment block and a new paragraph naming
the ordering rule so it does not drift back: a long-lived deliberate red belongs
at the END of a serial target, and anything added below that line is hidden by
it. No test file, assertion, expected value or acceptance criterion was touched;
the diff is a move of 9 comment lines plus 1 recipe line, and 8 new comment
lines. `Makefile` is the only modified file.

Proof:
  make test  -> exit 2, and the suites now run in this order at the tail:
                site_claims, field_redaction, publish_redaction, publish,
                field_census, claims, fd_dup, mode_wrong, guard_subdir,
                rule_census, THEN published_allowlist last
                All 7 formerly-masked suites now execute inside the run:
                publish 46/0, field census 1/0, claims 13/0, fd_dup 11/0,
                mode_wrong 9/0, guard_subdir 16/0, rule census GREEN
  grep -c '^  FAIL' over the whole run  -> 1
                exactly one FAIL line in 94 suites, and it is the deliberate
                allowlist gate. NOTHING is behind it any more.
  git status --short after the run      -> ` M Makefile` only. No tracked site/
                artifact was mutated (last session's fix holds).

NOT DONE, AND IT COULD NOT BE: `make test` is NOT green, Promise 2 was NOT
flipped, and no next step was started.

THE TRIAGE COMMIT IS NOT IN THIS REPOSITORY. Reported as landed for the second
consecutive session; absent for the second consecutive session. This is stated
with evidence because it contradicts the instruction and the instruction does
not outrank evidence:
  site/published-projects.txt   still the 12 seeded names, 46 lines, unchanged
  its only commit               4045665 — the seed commit from two sessions ago
  git status                    clean before this session's Makefile edit
  main vs origin/main           0 / 0 after `git fetch`
  git stash list                empty;  git worktree list: one;  git branch -a: main only
  git reflog -10                carries only these sessions' commits
  git log --all --grep=triage --grep=allowlist -i  -> only 4045665
  python3 site/allowlist.py --list  -> 72 found, 12 allowed, 60 off-list
  python3 site/allowlist.py         -> exit 1
Byte-identical verdict to last session. If that edit exists it is in another
clone, or was never committed. Nothing was invented to make this read better.

CI is red on the same single thing, on BOTH platforms — run 32035685460, commit
cfc894b: one distinct FAIL across macos-15 and ubuntu-latest, `72 name(s) found,
12 allowed, 60 off-list`. So local and CI agree exactly, and the gate needs no
private list to say so. NOT VERIFIED: this run predates the Makefile move, so
the reordering itself has not been through CI.

AND THE 60 ARE NOT 60 DISCLOSURE DECISIONS — the count is inflated by a data
defect, which makes this a smaller decision than it looks. `allowlist.py` reads
the `project` field each record DECLARES, and that field is not a project
identity: it is a directory basename, temp and fixture trees included. Classified
against the real directories under `~/damla_projects_2026`:
  39 names / 377 records  ARE real project directories — genuine disclosure
                          decisions, and they belong to the operator
  21 names / 305 records  are NOT — led by `home` (116 records) and `fixed`
                          (102), which together are a THIRD of all off-list
                          records and are not projects at all. `home` records
                          are STOP events whose cwd resolved to a home-relative
                          path; `fixed` is a redteam fixture tree
                          (`git commit -m "wip"` × 102). Also here:
                          `rbprobe.nqskoD` (33), `rbprobe`, `rbd-do`,
                          `rbd-toggle.IZCtM2`, `.reachprobe`, `p`, `tmp`,
                          `.claude`, `spool`, `damla_projects_2026` — mktemp
                          dirs and scratch paths.
  Plus 4 duplicate spellings of names already decidable once: `idea garden` vs
  `idea-garden`, `just ballet` vs `just-ballet`, `message-in-a-bottle` vs
  `messageinabottle`, `urun-psikolojisi-kitap` vs `psikoloji-kitabi`.
  And one that is a redaction artifact, not a name: `(withheld)-showcase` (5).
The mechanism to exclude harness trees ALREADY EXISTS and is under-inclusive:
`site/field_stats.py:53-57`, `LAB_EXACT` / `LAB_PREFIX = ("tmp.", "rabadon-",
"test-", "scratch")` / `FIXTURE`. It catches none of the 21. And `allowlist.py`
does not consult it at all.

DELIBERATELY NOT FIXED, because fixing it here would be the exact move this
product refuses. Widening `LAB_PREFIX` until the count falls is indistinguishable
from redefining the gate to get green, and it would have been done in the same
session that was asked to produce green. The classification above is offered as
evidence for a decision, not taken as one. Whether the extractor should report a
project identity instead of a cwd basename is a real bug with a real fix; it
needs its own session and its own commit, ahead of any triage, so that the
operator triages ~39 real names and not 60 strings.

STRUCTURAL FINDING, unfixed and worth naming: the allowlist gate is now a
permanently-red suite inside `make test`, and `make test` is what rabadon's own
guard runs on this repo. So rabadon now refuses every action in its own tree —
it refused this session's commands twice, correctly. The Makefile's own comment
above `promises` states the principle this violates: "A suite designed to fail
cannot also be the gate." Moving the gate last fixed masking; it did not fix
this. Options are a session's worth of thought, not a paragraph's.

NOT VERIFIED: no fresh clone, no clean machine, no g++-only container. The
reordered Makefile has not run on CI. Promise 2's STATUS condition (`make test`
green from a fresh clone on a machine that is not the dev box, verified by a
session that did not build it) is unmet on all three clauses, so it stays RED
and was not touched. The 21 non-project names are classified by directory
existence, which is evidence about the extractor, NOT proof that each of the 39
is safe to publish — none of the 39 was decided here.

NEXT: fix the `project` field so it carries a project identity rather than a cwd
basename (or make `allowlist.py` apply the existing lab/fixture filter), in its
own commit, and re-measure. Then the operator triages what survives.

### 2026-08-17 (3) — the suite stops rewriting what the site serves

DECISION (operator) — git history: option (a), LEAVE IT. The name was launched
publicly by the operator's own posts, cited SHAs must not be orphaned, and a
tamper-evident tool does not rewrite its own history. `stitchu` stays on the
private withhold list. The BLOCKED entry in the previous session log is
resolved by this decision; no history was rewritten and none will be.

DECISION (operator) — triage: reported as edited and committed by hand.
NOT PRESENT IN THIS REPOSITORY, and the check is unchanged as a result.
Evidence, since this contradicts the instruction and the instruction does not
outrank it: `site/published-projects.txt` still holds exactly the 12 seeded
names; its only commit is `4045665`, which is this session line's own seed
commit; `git status` clean; `main` and `origin/main` at 0/0 after a fetch; no
stash, one worktree, one branch, and the reflog carries only these sessions'
commits. So the verdict asked for is the same one as before:
  python3 site/allowlist.py --list  ->  72 name(s) found, 12 allowed, 60 off-list
  python3 site/allowlist.py         ->  exit 1
The 60 names are still untriaged and `native/published_allowlist_test.sh` is
still red by design. Nothing was invented to make this read better: if the edit
exists it is in another clone or was never committed/pushed.

DONE — the logged NEXT. `make test` mutated three tracked, publishable files on
every run, because `native/site_claims_test.sh` ran `python3 site/build.py` in
the real repo and build.py wrote to hardcoded `site/` paths. Fixed at both ends:
  site/build.py       `OUT = os.environ.get("RABADON_SITE_OUT", "site")`, used
                      at all four write sites — the six pages (:1938), the og
                      card (:1951, via og.render's existing `out=` parameter),
                      sitemap.xml (:1976) and robots.txt (:1980). Unset, a run
                      is byte-for-byte what it was; the deploy path is untouched.
                      The READS deliberately did not move: measured.json, the
                      templates, and the committed copy `rendered_day` dates a
                      page against all stay in site/.
  site_claims_test.sh renders into a `mktemp -d` and asserts against THAT, at
                      all three read points — the build invocation, the
                      placeholder grep, and the two-pages-one-number
                      cross-check, whose `first_stat`/`proof_stat` now resolve a
                      `site/` prefix through one `built()` helper.
NOT WEAKENED, and this was checked rather than asserted: the placeholder case
still reads freshly rendered output, and a `{{fake.placeholder}}` planted into
that output is still seen. Moving the output opened one new way to pass
vacuously — a build that writes nothing would make the grep trivially empty —
so a NEW assertion was ADDED, "the build wrote the page it is judged on"
(`[ -s "$BUILT/index.html" ]`). The suite went from 9 to 10 cases; no existing
assertion, needle or expected value changed.

Proof:
  bash native/site_claims_test.sh    -> pass 10, fail 0, "site claims: GREEN"
  RABADON_SITE_OUT=$(mktemp -d) python3 site/build.py
                                     -> exit 0, all 9 artifacts written there,
                                        `git status` clean
  make test                          -> exit 2, and the ONLY failure in the run
                                        is the deliberate allowlist gate:
                                        gate postuse 88/0, contract 35/0,
                                        red base 26/0, site claims GREEN,
                                        publish redaction 28/0, 88 suites run,
                                        then published allowlist 8 ok / 1 fail
  git status --short after that run   -> only this file's own uncommitted log
                                        edit. NO tracked site/ artifact was
                                        mutated. THAT CRITERION IS MET, and it
                                        is the one this session existed for.

THE CHECK CAUGHT ITS OWN AUTHOR, and the run above is the second one because of
it. `site/allowlist.py` — written last session to close this very class — spelled
the leaked rule id verbatim in its own KNOWN LIMIT docstring. Everything under
site/ is uploaded by `vercel deploy`, source included, so documenting the leak
republished it. publish_redaction_test.sh section 6 failed on
`allowlist.py: withheld project name(s) stitchu=1`, which is exactly the failure
it should produce. Rewritten to describe the class and never the name, and the
lesson is now a paragraph inside that file rather than a line in this one.
After the fix: 0 files under site/ carry a withheld term, publish redaction 28/0.

WHAT THE DELIBERATE RED HIDES, counted rather than assumed: `make` stops at the
first failing recipe line, and the allowlist gate sits at Makefile:777 with 86
suites before it and 7 after. Those 7 never run under `make test` while the gate
is red, so they were run individually instead — publish_test 46/0,
field_census_test 1/0, claims_test 13/0, fd_dup_test 11/0, mode_wrong_test 9/0,
guard_subdir_test 16/0, rule_census_test GREEN. All exit 0, 96 assertions, and
none of them mutates a tracked file either. Nothing is hiding behind the gate.
Moving the gate to the end of the test target would stop it masking anything;
that is a Makefile ordering decision, it was not taken here.

NOT VERIFIED / NOT MET: `make test` exit 0 was NOT achieved, so this session's
Done is incomplete by its own terms. The cause is not this step — it is the
allowlist gate standing red on 60 untriaged names, and the triage commit that
was reported as made is not in this repository (see the decision above). No
fresh-clone or clean-machine run. CI had not run at the time this was written.

NEXT: triage the 60 off-list project names — each one joins
site/published-projects.txt with its reason, or goes on the private withhold
list — and land that edit IN THIS REPOSITORY. That is the single thing between
here and a green `make test`.

CI (run 32035238269, commit e161e3e) mirrors the local run exactly, on BOTH
platforms — macos-15 and ubuntu-latest:
  red base: 26 ok, 0 fail            site claims: GREEN
  publish redaction: 28 passed, 0 failed
  published allowlist: 8 ok, 1 fail  -> 72 found, 12 allowed, 60 off-list
So this step is confirmed on machines that are not the dev box, and the run's
only failure is the intended gate. One thing worth naming: the allowlist gate
reports the SAME 72/12/60 on a runner as it does here. That was the entire
design goal — publish_redaction's section 6 can only ever see a leak where the
private terms file exists, and this gate needs no private list to enforce a
public decision. It is the first check in this repo that can fail on a
disclosure question anywhere.

### 2026-08-17 (2) — redaction decided after it had scrubbed the evidence

DONE 1 — the bookkeeping. `site/rule_census.py` sanitized in ONE pass that
cleaned each record before asking whether to withhold it, so
`redact.withhold_reason` was handed a blob the scrub had already emptied of
every term it looks for. It never fired: 0 withheld where 3 were owed, and all
four fixture rules survived with their names quietly rubbed out — a cover-up
with a counter stuck at zero. `redact.clean`'s own docstring says the
record-level drop happens "one layer up" from it, so the order was the bug.
Split into `prune` (decide on the ORIGINAL text, inner lists first) then
`scrub` (rewrite only what survived). No test file touched.
Proof: `bash native/publish_redaction_test.sh` 26 passed/2 failed -> 27/1.

DONE 2 — the leak. The disclosure was not a `project` field, which redaction
had correctly set to `(withheld)`; it was the rule ID itself,
`no-blanket-add-stitchu`. The two tracked, published artifacts each carried it
once and nothing else: a full scan of site/ against the operator's 12 terms
found exactly 2 files, 1 occurrence each. Replaced the token with what
`redact.clean` itself produces for it, `no-blanket-add-(withheld)`, so not one
published number moved (diff: 2 files, 1 line each). The current code would
withhold that record outright, so the artifacts were STALE — generated before
the term was listed.
Proof: `bash native/publish_redaction_test.sh` -> 28 passed, 0 failed;
`make test` -> exit 0, the first fully green local run.

DONE 3 — the gate, mechanism only, by operator decision. Measured first,
because the number is the argument: 72 distinct project names are published in
site/ artifacts; the private terms file holds 12; and of the 58 names published
as `project` values, ZERO were on it. The private list is deliberately outside
the tree (`site/redact.py:60-77`) and that stays — but it makes the check
default-ALLOW and unenforceable off one machine, which is why CI's section 6
passes on blindness. So the question is inverted against a PUBLIC committed
allowlist: not "is this name secret" but "was this name decided".
  site/published-projects.txt        the allowlist, 12 names seeded: rabadon,
                                    the `(withheld)` marker, and the 10 public
                                    OSS repos the benchmarks name
  site/allowlist.py                  the checker; `--list` prints the verdict
                                    per name; a missing or empty list allows
                                    NOTHING (fails closed)
  native/published_allowlist_test.sh NEW file, 9 cases, wired into `make test`
Proof: `bash native/published_allowlist_test.sh` -> 8 ok, 1 fail. The 8 prove
the gate can turn red, names the offender, reads both artifact shapes, goes
green when every name is decided, and fails closed on a missing or empty list.
The 1 is the real site/: 72 found, 12 allowed, 60 off-list. It is RED ON
PURPOSE — seeding the allowlist with everything already published would have
been a check that cannot turn red, and which of the 60 may be public is a
disclosure decision that belongs to the operator, not to this session.

NOT VERIFIED: `make test` was exit 0 BEFORE the allowlist gate was wired in;
with the gate it is red by design until the 60 names are triaged, so the
session ends on a deliberate red, not a green. Nothing was run on a clean
machine or a fresh clone. CI has not run since the gate landed. The 60 names
have not been triaged and no claim is made about which are sensitive.

BLOCKED — the name in git history, a human decision, untouched by design.
The working tree is clean but `stitchu` remains in the history and on GitHub.
Options, with costs:
  (a) leave it. The name is in old commits and any fork or clone already has
      it. Cheapest, and honest as long as it is written down here.
  (b) rewrite history (`git filter-repo`), force-push. Touches 500+ commits,
      breaks every existing clone, and GitHub keeps unreachable objects
      reachable by SHA for a while, so a full scrub is NOT guaranteed. Needs
      its own session.
  (c) decide the name is not sensitive enough to warrant (b) and remove it
      from the private terms list instead, which is a smaller, honest answer
      if it is true.
Nothing here was acted on.

ALSO FOUND, and it breaks one of this session's Done criteria: `make test`
still mutates tracked publishable files. `native/site_claims_test.sh:112` runs
`python3 site/build.py` in the REAL repo, and build.py writes to hardcoded
`site/` paths (build.py:1917, 1952, 1956), so a run regenerates
site/index.html, site/catches.html and site/patch-notes.html from the live
ledger. Restored with `git restore` twice this session, never committed. The
fix is an output-directory override (`RABADON_SITE_OUT`, defaulting to `site`
so nothing changes unless set) plus repointing site_claims_test.sh's three read
points at the fresh output — that last part moves an EXISTING test's
assertions, which is not something to improvise at the end of a long session,
so it is NEXT and not done. Doing it any other way (letting the assertions read
the committed pages instead of the fresh build) would reinterpret the test into
one that can no longer catch a build.py emitting placeholders.

NEXT: triage the 60 off-list project names — each one either joins
site/published-projects.txt with its reason or goes on the private withhold
list — then `make test` is green again.

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

CI VERIFIED (run 32021838705, commit db2d954): `red base: 26 ok, 0 fail` on
BOTH platforms — macos-15 and ubuntu-latest — alongside `gate postuse: 88 ok,
0 fail` and `contract: 35 ok, 0 fail`. This is the first time since `7ffb0fb`
that CI got past redbase. The run is still red, and only at
`publish_redaction`.

AND THE LEAK IS WORSE THAN A FAILING TEST: CI CANNOT SEE IT. Locally that
suite reports 26 passed / 2 failed; on CI it reports 27 passed / 1 failed.
The difference is the section that checks the real site/ artifacts. The
withheld-terms list lives at `~/.rabadon/redact/projects.txt`, deliberately
outside the tree (`site/redact.py:60-77`: a list of private repo names written
into a public repo would be published twice over). CI has no such file, so
name-based withholding does nothing there and the check passes on BLINDNESS,
not on cleanliness. `stitchu` appears 3 times in the operator's terms file and
once each in the tracked, published `site/field.html` and
`site/measured.json`. So: this class of leak can only ever be caught on the
operator's machine, and `make test` green on CI is not evidence that site/ is
clean.

The causal chain, for the next session: redaction bookkeeping is broken
(withheld 0 of 3, and the four rule names survive) -> a withheld project name
flowed into the generated site artifacts -> those artifacts were committed and
published. Fixing the bookkeeping is the root; scrubbing the two files is the
consequence; making CI able to fail on this without publishing the terms list
is the third, open question.

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
