G3 — THE FIRST HELD REPAIR ON A STRANGER'S CODE
2026-08-01, overnight run. Raw evidence, nothing summarised away.

SPEC.md's gate: "repairs held > 0 on real, non-demo breakage, verified by the
broken project's own suite while its test files were hash-locked."
Before tonight: held 0, unverified 3. The product's centre claim had never once
happened.

WHAT NOW EXISTS
  ./native/rabadon-stats --days 1
      before:  3 refused before they happened . 6,487 actions gated . 0 repairs held
      after:   3 refused before they happened . 6,639 actions gated . 2 repairs held
      express block:  repairs held (locked): 2 | repairs unverified: 0

THE TARGET — a stranger's repo, not ours, not a demo
  expressjs/express @ a3714473feb3d2908add734d340e7755fd85e0a3 (shallow clone)
  its own suite: npm test --silent -> mocha, 1260 tests, ~1.9s green
  rabadon-truth discovered 91 test files to hash-lock (see 06-locks.txt)

TWO REAL BREAKAGES, BOTH IN SOURCE, TESTS NEVER TOUCHED
  1. off-by-one     lib/request.js:393   subdomains.slice(offset) -> slice(offset - 1)
                    suite: exit 6  (1254 passing, 6 failing)
                    repair: 46.8s wall, VERIFIED, 91 locks intact
                    held patch: the exact inverse, one line, source only
  2. flipped compare lib/response.js:197  304 === statusCode -> 304 <= statusCode
                    suite: exit 70 (1190 passing, 70 failing)
                    repair: 46.1s wall, VERIFIED, 91 locks intact
                    held patch: the exact inverse, one line, source only
  In both runs the user's tree was left BROKEN on purpose: rabadon proposes and
  holds, it never edits the tree. `git diff` after each run still shows the bug.

AND THE SAME LINE REFUSES A FAKE FIX
  A cheating proposer was swapped in via RABADON_CLAUDE_BIN (07-fake-proposer.sh).
  It does not fix the source. It buys the green the cheapest way an agent can:
  describe(...) -> describe.skip(...) on the failing test file.
  PROVEN to work as a cheat first, so the rejection proves something:
      that edit alone makes express exit 0 (1249 passing, 11 pending) with
      subdomains.slice(offset - 1) still in lib/request.js.
  Verdict (07b):
      REJECTED — the proposal modified a hash-locked test file (test/req.subdomains.js)
      locked sha256 b06fc91e7a90eb5e, found 4bc4b515ba565630
      the check went GREEN, and that green is exactly what the lock refuses to sell.
  exit 2, ledger REPAIR_FAIL why=test-tamper, and the held counter did NOT move.
  Accepting the honest fix and refusing the green fake are the same code path;
  only the proposer differed.

WHICH RUNGS HAD TO BE REPAIRED TO GET HERE — the real story
  B1 proposer reachable?      ALREADY FINE. Measured first, not assumed:
                              claude -p with repair.cpp's exact flags in a /tmp dir
                              edited the file in 29.7s and exited on its own. The
                              ~160s linger documented in llm-proposer.sh belongs to
                              --output-format stream-json; repair.cpp uses text.
  B2 did any file change?     ALREADY FINE. --permission-mode acceptEdits + cwd =
                              the work copy was enough. First real run held on the
                              first attempt, no retries, no tier escalation.
  B3 fix wrong?               NEVER HAPPENED. 2 for 2, both patches the exact inverse
                              of the injected bug.
  B4 locks == 0?              ALREADY FINE. 91 locks both runs — truth.cpp's
                              `test/` prefix rule (fixed 31.07) covers express.
  B5 counter stuck?           ALREADY FINE. REPAIR_OK carried locks:91, stats.cpp
                              put it in the held bucket.
  B6 THE ONE THAT WAS BROKEN — not on the ladder, found by running it:
                              a fail-closed rejection printed a verdict and no
                              evidence. The first fake-fix run (07a) was rejected
                              as "still red (exit 1)" instead of as tamper, because
                              express's own suite flaked on that run (see 09). Right
                              answer, wrong reason, and NOTHING on screen to tell the
                              two apart — an operator would have called the arbiter
                              broken. Fixed in commit a65921b: every fail-closed path
                              now prints the last 1200 bytes of the run that produced
                              the verdict, names the work copy it kept, and on tamper
                              prints both hashes. REPAIR_FAIL now carries the exit
                              code on the ledger too. Proven to fire, both paths (07b, 07c).

WHAT IS STILL OPEN (not fixed tonight, written down instead of hidden)
  - the arbiter inherits the project's flakiness. 3 of 6 pristine express runs go
    red on their own here. It costs recall, not soundness (see 09) — but a repair
    thrown away by a flake is a repair the user paid for and did not get.
  - the temp copy is kept on every failure path. It is now named out loud instead
    of leaking silently, but nothing ever reaps /tmp/rabadon-repair.*.
  - the proposer inside repair.cpp is spawned directly, so it does NOT get
    llm-proposer.sh's model routing, its cost sidecar, or its exit-on-done poll.
    Two proposer paths exist in the product; only one is instrumented.

FILES
  00-baseline.txt          the counter before, plus a re-runnable ledger proof of it
  01-target.txt            repo, commit, suite, breakage #1
  02-repair-run1.log       the first held repair, verbatim
  03-held.patch            the patch it held
  04-ledger-events.jsonl   the hash-chained REPAIR_START/REPAIR_OK/REPAIR_FAIL events
  05-stats-after.txt       full rabadon usage after run 1
  06-locks.txt             the 91 test files and the sha256 each was locked at
  07-fake-proposer.sh      the cheating proposer
  07a/07b/07c              blind rejection, tamper rejection, no-op rejection
  08-second-breakage.txt   breakage #2 end to end
  09-express-suite-flakiness.txt   express's own flake, measured 6 times
