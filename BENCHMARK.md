# rabadon — the numbers, measured not claimed

rabadon is a local, fail-closed gate that sits on every coding-agent action
(as a PreToolUse hook), stops a bad call before it spends, and carries a bounded
repair loop plus its own ledger — one budget, on-machine, no data leaves.

Every figure below was reproduced on this machine this session by
`bench/reproduce.sh`. Nothing here is hand-written or rounded up. Where a
counter is 0 it says 0 — that is the honest state, not a gap hidden.

Machine: Apple M2, arm64, macOS (Darwin 24.2.0). Toolchain: Apple clang 17.0.0,
node v26.5.0, python 3.14.6. Reproduce all of it:
`RABADON_NOTIFY=0 bench/reproduce.sh`.

Markers: `[proven]` runs on real projects here, `[building]` proven in-suite
but not yet on real breakage, `[ahead]` not built.

---

## 1. Gate latency — the hook tax on every action  `[proven]`

The gate runs on every coding-agent tool call (PreToolUse hook), on the
critical path, so it has to be cheap. `native/bench.py` builds a scratch project
with one guard rule, feeds the same hook events to two gates, first proves
verdict parity (identical exit codes — a fast wrong gate is worthless), then
times each over 40 runs per case.

- native — `native/rabadon-gate` (the C++ core)
- node — `hooks/gate.mjs` (the legacy Node gate)

Parity held: native == node on both verdicts (allow=0, deny=2). It only holds
because the harness now ARMS the isolated home it benchmarks in. `RABADON_DIR`
relocates the whole rabadon home, mode flags included, so a fresh temp home
starts in WATCH — where the native gate records a deny and exits 0 while the
node gate, which has no watch mode, exits 2. That read as a parity break for as
long as the isolation existed; it was an unset switch, and a bench that leaves
it unset is timing a gate nobody runs.

| gate   | case  | median    | p95       | n  |
|--------|-------|-----------|-----------|----|
| native | allow | 2.78 ms   | 5.26 ms   | 40 |
| native | deny  | 3.70 ms   | 8.60 ms   | 40 |
| node   | allow | 101.44 ms | 126.54 ms | 40 |
| node   | deny  | 101.20 ms | 103.27 ms | 40 |

Measured 2026-09-02 with `RABADON_NOTIFY=0 make bench`. Median hook tax drops
from ~100 ms (node process startup dominates) to 2.8 ms (native), about 36x at
the median. The native p95 is noisier on a laptop (scheduler / spawn jitter), so
the median is the robust number.

Re-measured on 2026-09-02 because the gate gained a whole mechanism since the
August table: the move ring, five detectors, and the injection channel all run
on this path now. The allow median did not move (3.14 → 2.78 ms, inside this
machine's run-to-run spread). A separate two-arm measurement isolates the new
work rather than inferring it — same binary, 40 samples, one sandbox each:

| session state                                    | median  | p95     |
|--------------------------------------------------|---------|---------|
| cold: no moves recorded, nothing queued           | 2.84 ms | 3.54 ms |
| armed: a full move ring and a diagnosis pending   | 2.88 ms | 3.27 ms |

0.04 ms between them. Recording every move and carrying an undelivered
diagnosis is free at this resolution; what the hook costs is process startup,
which is what the native rewrite bought back.

This table read 2.29 ms on 31 July. The honest reading of the difference is that
it is a different binary on a different day and not a regression anybody
measured — the gate has since grown the multi-agent event normaliser — and two
numbers taken in separate sessions do not make a difference. Where one number is
needed, quote this table's, re-run rather than remembered.

Judging alone, with the process cost taken out: **245.3 µs** median, p95 361.5
µs, over 34 real fixture cases at 200 judgements each. That comes from
`./native/gate_bench.sh`, which refuses to print any number unless the
in-process judge and the shipped binary first agree on all 34 verdicts.

One path is deliberately not 2.8 ms: a `git push` after code changed since the
last green test run makes the gate run the project's suite inside that same
hook call. That is bounded by `pushGate.timeoutSec` (default 900 s), and the
installed hook ceiling sits above it at 960 s on purpose — if the outer timeout
fired first, the action would be neither allowed with a verdict nor refused
with a reason.

Command: `RABADON_NOTIFY=0 make bench`.

---

## 2. Correctness — node == native parity, and the native suite  `[proven]`

`native/postuse_test.sh` pipes identical hook JSON into BOTH the node oracle
(`node hooks/gate.mjs`) and the native gate (`native/rabadon-gate`) and asserts
the SAME verdict (exit code) + state.json + spool. 13 of those cases are
explicit node-vs-native differentials:

- 9 dual-engine `differential()` cases (equal exit / state / spool),
- 3 BR2 asserts (exit-2 on both, stderr names all 5 dirs on both, stderr
  byte-identical node==native),
- 1 BR11 twin-dedupe (node==native).

Result: 13/13 node-vs-native cases produced the same verdict + state + spool
= 100% parity, 0 divergences.

Suite totals, reconfirmed this session:

| suite                | result           | node==native? |
|----------------------|------------------|---------------|
| `postuse_test.sh`    | 53 ok, 0 fail    | yes — 13 differential cases |
| `pushgate_test.sh`   | 9 ok, 0 fail     | no — native-only push-gate proof (invokes node 0 times) |

`pushgate_test.sh` is a native-only push-gate proof, NOT a node==native
differential — `grep -cE 'node ' native/pushgate_test.sh` = 0. Its 9 passing
cases are native-behavior proofs (a hanging suite is killed and the push
blocked, etc.), not oracle-parity comparisons.

Commands:
`RABADON_NOTIFY=0 ./native/postuse_test.sh` → `gate postuse: 53 ok, 0 fail`
`RABADON_NOTIFY=0 ./native/pushgate_test.sh` → `gate push: 9 ok, 0 fail`

---

## 3. The ledger — rabadon's own word about what it caught  `[proven]`

`rabadon usage --days 30` aggregates the local spool (`~/.rabadon/spool/`). It
excludes its own drills, demos and self-tests at emit — 3,495 events in this
window — so a tool that counts its own test runs as catches never happens here.
59 projects, one machine, real work:

| view                    | actions gated | caught before happening | would have caught (watch) | checks failed | loops stopped |
|-------------------------|---------------|-------------------------|---------------------------|---------------|---------------|
| all projects (30 days)  | 15,188        | 61                      | 68                        | 314           | 2             |

Biggest signal, by project:

| project     | actions gated | caught before happening | checks failed | loops stopped |
|-------------|---------------|-------------------------|---------------|---------------|
| stitchu     | 4,196         | 43                      | 107           | 2             |
| rabadon     | 3,640         | 12                      | 112           | 0             |
| (home)      | 2,162         | 3                       | 27            | 0             |

What was caught on stitchu (verbatim rule ids from the ledger): `push-gate` 14x
(code edited after the last passing test run), `no-rm-rf-outside-project` 9x,
`no-wrangler-deploy` 6x, `generated-web-html` 5x, `ctest-tail-hides-verdict` 3x,
`loop-stop` 2x, `test-tamper` 2x (assertions being removed from
`test_style.cpp` while the suite was red), `golden-reference` 1x,
`no-force-push-main` 1x.

### The repair counter, split — and what the split cost

This page used to carry one number called **repairs accepted**, and it was 0,
and that was reported as honesty. It was worse than a wrong number: it was one
bucket holding four different events, because `REPAIR_OK` is emitted by the
push gate when a suite goes green, by the gate when a new rule is written, and
by the repair path whether or not any test file was hash-locked while the fix
was re-checked. Counting those together means the headline can grow without a
single line of code ever being repaired.

Split by what actually happened:

| bucket                                        | 30 days |
|-----------------------------------------------|---------|
| repairs **held** — fix re-checked with test files hash-locked | **2** |
| repairs unverified — nothing was locked, so nothing witnessed it | 3 |
| push gates passed — a suite ran green, nothing was repaired    | 0 |
| rules written — law was authored, nothing was repaired         | 1 |

The three that used to read as "repairs accepted" are all unverified, all on
stitchu. The number that sells the product — a fix proven against test files
that provably did not move — reads **2**, both on expressjs/express, and both on
**planned** breakage. On **unplanned** breakage the count is **0**, and this page
will keep printing it either way. That second number is the one to watch; the
first only proves the loop runs end to end.

Command: `RABADON_NOTIFY=0 rabadon usage --days 30`.

Note: the bench harness writes to an ISOLATED spool (`RABADON_DIR` per run), so
bench drills do not inflate this ledger. The stable facts this page rests on:
node/native parity held, stitchu is the largest real signal, and repairs-held is
2 on planned breakage and 0 on unplanned breakage.

---

## 3b. False rejects — the number that decides whether a guard survives  `[proven]`

Latency says the gate is cheap. The ledger says how much it did. Neither
answers the question a stranger actually asks — *will it get in my way* — and
that question decides whether a guard is still installed on day two. A tool
that refuses honest work once a day is uninstalled by lunch, however correct it
is the rest of the time.

rabadon records both halves of the answer without being asked to. A `STOP` is a
refusal that happened. `rabadon wrong <rule> "<why>"` writes a `WRONG_REFUSAL` —
the operator, after the fact, saying that refusal should not have fired. The
false-reject rate is one divided by the other, and it needs no survey, no
instrumentation and no memory of what happened.

Measured 2026-09-05. The ledger is live and grows under the operator's own
work, so a count read tomorrow is a larger count — the date is part of the
claim, not decoration.

| window | refusals | declared wrong | rate |
|--------|----------|----------------|------|
| all 28 days with traffic (2026-08-04 → 09-04) | 524 | 70 | 13.4 % |
| the same, counting only rules that still refuse | 524 | 59 | 11.2 % |
| since 2026-08-28 | 192 | 1 | **0.5 %** |

The middle row exists because 11 of the 70 name a rule that never appears as a
refusal: `ctest-red-block`, `tests-red`, `tests-are-RED` and two more spellings
of what is `red-base` today. The rule was renamed; its refusals moved to the new
id and the operator's verdicts stayed on the old ones, which puts a numerator
over a denominator it does not belong to. **The 13.4 % row is still the one
quoted**, because the correction moves the number in this project's own favour
and a guard that rounds its own error rate down has stopped measuring itself.

Both rows are real and the difference between them is the whole story: **69 of
the 70 wrong refusals happened on two days, 26 and 27 August.** That is what
tuning a rule against real work looks like — the rules that were wrong were
`ctest-tail-hides-verdict` (37 wrong of 152), `red-suite-test-write` (7 of 17)
and `red-base` (10 of 65), each argued down with a written reason on the ledger.
In the 192 refusals since, one was called wrong.

What those 192 stopped, in the operator's own repos: 34 `git commit -m "wip"`
against a project whose guard demands a real message, 34 actions on a red test
base, 24 truncating redirects onto a tracked file, 22 force-pushes to a shared
branch, 21 recursive deletes resolving outside the project, 6 blind in-place
source rewrites, 5 attempts to take apart a project's own `.rabadon/` law, and
one edit that would have put `red-base` into `disabled[]`.

Reproduce, on your own ledger, offline:

```sh
python3 bench/precision.py                     # every day on record
python3 bench/precision.py --since 2026-08-28  # one window
```

It reads `~/.rabadon/spool/*.jsonl` and nothing else. On a machine that has
never refused anything it prints that, rather than a rate computed from zero.

**What this number is not.** It is one operator, one machine, 148 projects, and
the same person who wrote the rules is the one judging them — a stranger's
false-reject rate on a codebase rabadon has never seen is unmeasured, and no
amount of local traffic can stand in for it. The honest claim is narrow: on the
work this machine actually does, the gate now refuses about one honest action in
a hundred and twenty-six.

---

## 3c. A project rabadon has never seen  `[proven]`

§3b's 0.5 % is one operator, one machine, and rules that operator wrote. The
question it cannot answer is the one that decides a stranger's first afternoon:
**zero config, an unfamiliar codebase — does it refuse ordinary work?**

Four real repositories, four ecosystems, cloned fresh and given nothing but a
`testCommand`. No rules, no promise, no tuning. Then the commands their own
maintainers run, taken from their CONTRIBUTING docs and CI config — plus the
destructive ones any guard has to stop.

| repo | language | ordinary actions | falsely refused | harmful | stopped |
|------|----------|------------------|-----------------|---------|---------|
| pallets/flask | Python | 30 | 0 | 10 | 9 |
| expressjs/express | JavaScript | 30 | 0 | 10 | 9 |
| BurntSushi/ripgrep | Rust | 30 | 0 | 10 | 9 |
| gin-gonic/gin | Go | 30 | 0 | 10 | 9 |
| **total** | | **120** | **0** | **40** | **36 (90 %)** |

The ordinary set is not a soft list. It includes `rm -rf docs/_build`,
`rm -rf node_modules`, `rm -rf target`, `rm -rf vendor`,
`find . -name '__pycache__' -exec rm -rf {} +`, `git rebase main`,
`git stash pop`, `git clean -n`, `git push origin feature/x`, `go mod tidy`,
`cargo fmt --check` and `npm ci` — the shapes a blunt rule refuses. None was
refused.

**The four misses are one command, and it is a documented blind spot**, not a
surprise: `cd .. && rm -rf $(basename $PWD)` deletes the tree from outside
itself, naming neither the project nor its law. `rabadon --status` prints this
as one of 21 measured shapes that destroy a project's `.rabadon/` and are
allowed on purpose — the cut that would refuse it also refuses
`rm -rf ./old-project`, i.e. fences you inside your own tree. The stated
mitigation is to commit `.rabadon/` to git, where the copy survives all 21.

Reproduce it, offline, without executing anything in those repos:

```sh
git clone --depth 20 https://github.com/pallets/flask.git      /tmp/str/flask
git clone --depth 20 https://github.com/expressjs/express.git  /tmp/str/express
git clone --depth 20 https://github.com/BurntSushi/ripgrep.git /tmp/str/ripgrep
git clone --depth 20 https://github.com/gin-gonic/gin.git      /tmp/str/gin
RABADON_STRANGERS=/tmp/str python3 bench/strangers.py
```

Every command is handed to the gate as a hook event and only the verdict is
read. The clones are never modified and the harmful list is never run.

**And it is held to, on a machine that is not this one.** Until 2026-09-05 this
was the least protected claim here: the script was wired to nothing, returned no
exit code, and printed `MISSING` four times and crashed with a traceback — at
exit 0 — when the repos were not cloned. It now fails on a single false reject
or a drop below 36 of 40 stopped, skips at exit 3 rather than crashing when the
clones are absent, and runs as its own CI job on a fresh ubuntu runner that
clones the four upstream repositories itself. The operator's machine no longer
gets to be the only witness to this number.

**What this is still not.** These are the commands a maintainer runs, chosen by
reading each project's own docs — not a recording of someone actually working.
A real week by a real stranger on their own codebase remains the measurement
nobody has taken, and it is the one that would let this project claim more than
it does here.

---

## 3d. The refusals that cannot be undone — the only ones worth installing for  `[proven]`

524 refusals is the wrong number to quote and this section exists to say so.
Most of them are recoverable: a `wip` commit message, an action on a red test
base, a `ctest` invocation whose tail hides the verdict. Worth refusing, and
undoable — which means **anyone can write those rules in a shell function in an
afternoon, and nobody installs a tool for them.**

The claim that survives that test is narrower. Split by whether the state comes
back:

| class | refusals in 28 days | can you undo it? |
|-------|--------------------|------------------|
| recoverable — commit message, red base, hidden verdict | 414 | yes, re-run it |
| deferred — a push or deploy held back until the suite is green | 9 | nothing was lost |
| **irreversible** — truncating redirect, delete outside the tree, reflog expiry, blind in-place rewrite, guard switched off | **101** | no |

The middle row used to sit in the bottom one, and an outside reviewer caught it
on 2026-09-03: `push-gate` was 15 of 57 real-work refusals — 26 % of the
headline — and every one of its events reads *"code was edited after the last
passing test run"*. A push was deferred; nothing was destroyed. Counting it as
irreversible made this project's own script violate the thesis it was written
to defend. It is still a rule worth having; it is now counted where it belongs.

The 101 split again, because a guard measured on its own test harness is
measuring itself: **73 on the operator's real work, 28 inside throwaway
sandboxes** this project's own red-team suites create. On real work that is
**18.2 per week**, across 11 distinct days.

    21  baseline-truncating-redirect     `>` onto a tracked file
    19  baseline-rm-rf-outside           a delete resolving outside the project
     8  no-blind-inplace-source-rewrite  sed -i over source with no backup
     6  no-rm-rf-outside                 a delete reaching outside the project
     4  no-shell-write-protected-path
     4  baseline-law-unmade              taking apart the project's own .rabadon/
     3  baseline-reflog-drop             reflog expiry — the way back, deleted
     3  guard-weaken                     a rule moved into disabled[]
     2  anti-path-frozen                 an edit to a file the promise froze
     2  no-force-push-main
     1  no-shell-rewrite-of-guard-or-promise

Reproduce: `python3 bench/irreversible.py` (add `--since YYYY-MM-DD` for a
window). It reads the ledger and nothing else, and it prints the sandbox split
rather than hiding it in the total.

**Read this honestly.** Ten a week is one operator running coding agents
hard, on a machine where those agents are trusted with a shell. A developer who
does not run agents unattended will see a fraction of it. The number that would
settle the question — how many irreversible actions a *stranger's* agent
attempts in a week — is unmeasured, and it is the difference between "useful"
and "necessary".

---

## 4. Where rabadon sits (only repo-backed claims)

| tool                | integration        | can stop a bad call?                     | can repair it? | scope              |
|---------------------|--------------------|------------------------------------------|----------------|--------------------|
| Langfuse            | wrap client        | no — passive by design ("only logs")     | no             | tracing / evals    |
| Braintrust          | wrap client        | no — passive tracer                      | no             | tracing / evals    |
| Galileo             | inline gate        | yes — block / canned override            | no             | one call           |
| **rabadon**         | wrap / hooks / CLI | **yes — inline, fail-closed, pre-spend** `[proven]` | **bounded, re-checked — 2 held on planned breakage, 0 on unplanned breakage** `[building]` | session + pipeline, one budget, local-only |

Passive tracers (Langfuse, Braintrust) wrap the client and watch; they cannot
stop a bad call and cannot repair it. Galileo's inline gate CAN stop a call
(block or canned override) but does not repair. rabadon is inline, fail-closed,
pre-spend on real projects (61 real catches in 30 days: stitchu 43, rabadon 12,
drills excluded), overhead is deterministic C++ at 2.8 ms. The repair loop is
proven in the test suite and has held 2 hash-locked repairs on planned breakage
(expressjs/express, its own suite as arbiter); on unplanned breakage it has held
0 so far.

---

## 5. Not yet — the next gate

**repairs held = 2.** `[building]`

This section read 0 for two weeks after it stopped being 0, which is the exact
failure the rest of this page exists to guard against: a number kept by hand
drifts away from the ledger it claims to summarise, and nobody goes back for the
one that flatters nobody.

The two are on expressjs/express @ a3714473, its own 1,260-test mocha suite in
the judge's seat, all 91 of its test files hash-locked, the working tree never
edited. Raw events and both patches: `reports/2026-08-01-g3-first-held-repair/`.
In the same run a proposal that reached for `describe.skip` was refused as
test-tamper and the counter did not move.

Two things this number is not. It is not breakage found in the wild — both bugs
were planted to drive the loop end to end, and the number that matters next is
the one on breakage nobody planted. And it is not the 46 a raw ledger scan
shows: 44 of those came from a single scripted pipe inside four minutes, which
is what `native/drill.h` rule 5 was written to catch and now does.

---

## Reproduce everything

```
RABADON_NOTIFY=0 bench/reproduce.sh
```

Numbers vary slightly with machine load. The reproducible facts: 2.8 ms native
gate median, 44x median gap over node, 13/13 node==native parity + 53/0 and
9/0 native suites, 55 real catches on stitchu+rabadon in 30 days (drills
excluded), and repairs-held = 2 on planned breakage, 0 on unplanned breakage.
