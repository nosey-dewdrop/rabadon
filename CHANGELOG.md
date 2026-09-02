# Changelog

All notable changes to rabadon. Dates are the day the tag was pushed.

## 0.2.4 — 2026-09-02

The first release anyone can install. 0.2.3-rc.1 published the same day and is
on the registry under `next`; this is the version `npm i -g rabadon` resolves
to. Everything below was measured by running the binary, not by reading it.

### The injection channel, which had never worked end to end

- A diagnosis is delivered even when a rule would have refused the call. `block()` used to reach `exit()` before the delivery site, so in the one scenario an injection exists for — a failure repeating — the paragraph was assembled, queued, and never handed over. Non-sealed rules now stand down and emit `RULE_YIELDED`; the three sealed rules (promise-tamper, promise-anti-path, guard-weaken) refuse exactly as before, so an injection can never move a security decision.
- The paragraph quotes the run, not the envelope. A Bash result arrives as `{"stdout":…}` and the move record read that object as one line, so the agent was told "the previous attempt ended with" the first 120 characters of a file it had `cat`ed. Both readers now get the un-escaped text, and the quoted line is the one that IS the error rather than one that mentions it.
- A file written through the shell counts as a change. Agents write with `cat > x.py <<EOF`, `>>`, `tee` and `sed -i`; none of it was an edit, so "changed since that green" came out empty in exactly the sessions that needed it.
- The trigger sees the verdict. Detectors ran before the suite verdict was stamped, so the contrast trigger really asked "did the output contain an error word" — `Tests: 1 failed, 2 passed` produced a red on the ledger and no signal at all.
- A failure is claimed by a leading error line, not by vocabulary. A `cat` of an error handler or a dumped log used to claim a failed command; 28 of 43 signals measured on one real day were that shape. **And the first cut of this rule was too strict**: measured against eleven real failure lines, it caught four. gcc, clang, tsc, go, eslint, make and npm all write the place before the mark, so the check now reads past one leading location. 11/11 real failures caught, 3/3 noise shapes still silent.

### What the ledger can now answer

- `INJECT_ANSWER` carries `named`: did the agent's next move go to a file the paragraph pointed at. `same` could not come back false for a competent agent, so layer (b) was unmeasurable. First real traffic: two answers, both `named=true`.

### Test suites, and what they cost

- `yield_test.sh` (13 cases) covers the branch that turns refusals off. `signals_test.sh` gains a section for `regression_contrast`, which fired more than any other detector and had no fixture. `inject_payload_test.sh` (35 cases) holds the payload's truthfulness and the eleven-tool failure census.
- The release pipeline hung for 2h23m on ubuntu-22.04 in a test that runs a real `script(1)` under a pty: util-linux 2.37 keeps the pty open after the child exits. Every real `script(1)` call is now fenced with a wall clock.
- Hook latency re-measured on this binary: 2.78 ms median to allow (was 3.14 ms in August, before any of this existed). A session carrying a full move ring and an undelivered diagnosis costs 2.88 ms against 2.84 ms cold — the machinery is free on the hot path.

### Known, and stated rather than smoothed over

- The false positive rate of the contrast trigger after these cuts is NOT measured. Before them it was 28 false of 43 on one machine over one day. It needs days of real traffic under this build.
- The injection budget is two paragraphs per signal per session, and a session on a real machine can run sixteen hours. Measured: one session spent both by 15:42 and stayed mute through 140 later failures. A proposal to charge the budget per failure instead is written up in PROJECT.md and awaits a decision; nothing in the trigger path moved for it.

## 0.2.2 — 2026-08-05

- The lock's python cases assumed pytest was on the machine. On a runner without it the arbiter went red for a missing interpreter, four graded verdicts collapsed into no verdict at all, and the suite reported failures it had never measured. Each case now checks for the toolchain it needs, says which cases it did not judge, and refuses to print GREEN when it judged nothing.
- A repair the arbiter could not grade the same way twice no longer writes REPAIR_OK. The screen already refused to certify it while the ledger recorded it as a success, so the held-repair counter included a coin flip. That run now carries its own event.

## 0.2.1 — 2026-08-05

- The v0.2.0 release build failed on the macOS runner and took the publish job with it. A test that stands up a throwaway git remote let the host name the branch, so a box configured for `master` produced `src refspec main does not match any` while the same test passed here. The lab now names its own branch. Reproduced with the host forced to `master`: 144 passed and 2 failed before, 146 passed and 0 failed after.
- Published site data is written through a redactor rather than beside one. Absolute home paths are rewritten and records matching a private-project list are dropped and counted, so a published file states how many records it withheld instead of quietly shrinking. A test reads what the domain would serve and fails if either ever reappears.

## 0.2.0 — 2026-08-05

Tagged, and **not** published. This line used to read "First published release.
`npm i -g rabadon`", which the registry disagrees with: `npm view rabadon`
returns 404, and the release workflow failed on the darwin-arm64 build for
v0.2.0, v0.2.1 and v0.2.2, taking the publish job with it each time. The
workflow and its provenance attestation are wired and have never once run to
completion. A changelog announcing a release nobody can install is the same
class of error as a benchmark citing a file that does not exist.

### The gate
- Deny decisions are made in native C++ before a command is produced, not after it runs. Force-push to a protected branch, recursive deletes outside a project, and untested pushes are refused at emit time.
- Eleven laws are compiled into the binary and hold with no configuration at all. Any of them can be switched off by id in a project's `disabled[]` — none is sealed, and the README says the same. Everything else lives in a project's `.rabadon/guard.json`, and a rule born from a real incident carries `authoredBy: incident`.
- `rabadon drill` produces a real refusal on a throwaway command so a new user sees the mechanism in one step. Drills are tagged at emit and excluded from the ledger, so they never inflate `rabadon usage`.

### The repair loop
- When a suite goes red, a proposer writes a patch in an isolated copy and the arbiter runs the project's own check command. The verdict is that command's exit code. No model is asked whether the repair is real.
- Test files and the harness are hash-locked before the proposer starts. A patch that edits, deletes, skips, or neuters a locked test is refused, and the accepted-repair counter does not move.
- A red result is re-sampled. If two samples disagree the verdict is FLAKY rather than verified.

### The ledger
- Every gated event is appended to a hash-chained day file. `rabadon audit` detects an edited character, a dropped line, a truncated tail, a stripped `prev`, a re-forged chain, and a deleted day file.
- Events carry the calling tool's id and the session id, so a trace can be rebuilt per session without instrumenting anything.

### Install
- Prebuilt binaries ship as `@rabadon/<platform>` optional dependencies with npm provenance. Where no prebuilt matches, `postinstall` compiles the native core from the source in the package.
- Verified on a clean HOME from the packed tarball: install, `rabadon init`, `rabadon on`, `rabadon drill`, and the gate refuses with exit 2.

### Packaging
- The published tarball carries 53 files at 360.3 kB. Unit tests, demo fixtures, example guard packs, and maintainer release scripts are no longer shipped.
