# R0 — CLAIM

**Round:** R0, the handover.
**Date:** 2026-08-22.
**Proof command:** `reports/R0/accept.sh` (exit 0 = accepted).

## What R0 was asked to do, and what it did

| KOSU-RABADON.md R0 item | outcome |
|---|---|
| retire PROTOCOL-T1-T8.md to the archive with a cancellation line | done (was already done before this session; verified, not assumed) |
| KOSU-RABADON.md becomes the root's only plan | done |
| reports/T1 and reports/T2 left untouched | done |
| close the "last 7 day(s)" / 30-day mismatch | README was already closed; quickstart needs no change — see challenge 2 |
| `export CXX` in the Makefile (S0.2) | **not done, deliberately** — see challenge 1. The real remaining hole was fixed instead |
| open docs/POSITIONING.md with the §1b market map, URLs, three competitor sentences | done, with eleven claims marked UNVERIFIED — see §3 |
| `make test` green, count not lowered | 2015 passing, 0 failing, exit 0 |

## Challenges to the plan

The house rule is that a wrong instruction is neither obeyed silently nor fixed
silently. Both of these are the third path: stop, write the evidence, propose.

### Challenge 1 — `export CXX` is the wrong remedy and would undo the right one

KOSU-RABADON.md R0 says "Makefile CXX export eder (S0.2)". PROJECT.md S0.2 offers
two alternative remedies: `${CXX:-c++}` in every test script **or** `export CXX`
in the Makefile. The first remedy is already done and has been for some time —
ten scripts under `native/` carry `CXX="${CXX:-c++}"`, each with the reason
written above the line (`native/cmdtext_test.sh:31`):

> `c++`, not `clang++`. make does NOT export its builtin CXX, so under
> `make test` this variable is unset and the fallback is what actually runs —
> and on a Linux box with only g++ installed, `clang++` is a command that does
> not exist.

Exporting CXX now would push the Makefile's value **into** those ten scripts and
take their fallback away. The two remedies are alternatives, not a checklist:
doing the second after the first is a regression dressed as progress.

The hole that actually remained was the Makefile's own default, `CXX ?= clang++`
— on a g++-only Linux box that names a command which does not exist, and
`make all` dies before a single test runs. R0 changes it to `CXX ?= c++` and
writes the reason in the file.

Evidence:

```
$ grep -rn 'CXX:-clang' --include='*.sh' --include='Makefile' --include='*.yml' --include='*.py' .
(no output)
$ grep -rl 'CXX:-c++' native/ | wc -l
10
$ grep -rn 'clang++' Makefile .github/workflows/*.yml
Makefile:2:CXX ?= clang++          <- the only survivor, and the one R0 changes
```

**Also, PROJECT.md is stale on this point.** PROJECT.md:979 says "S0.2 still
stands: ten scripts under `native/` use `${CXX:-clang++}`". They do not; they use
`${CXX:-c++}`. That line was true when written and is false now. R0 does **not**
edit it: correcting the plan is a human-approved diff in its own commit, not a
side effect of a round. Proposed diff, for approval:

- PROJECT.md:979 — strike the sentence, or replace with: "S0.2's script half is
  done (ten scripts fall back to `c++`); the Makefile default was fixed in R0;
  what remains open is only the proof, which needs a g++-only container."

**S0.2's checkbox stays unticked.** Its stated proof is "`make test` exits 0 in a
container with only g++", and no container was run. What was run is a shim: a
`/tmp/rab_noclang/clang++` that prints to stderr and exits 127, placed first on
`PATH`, followed by `make clean && make test`. Result: exit 0, 2015 passing, and
the shim was never invoked — zero occurrences of "clang++ SHIM" in the log. That
proves nothing in the build or the test scripts reaches for a compiler named
`clang++`. It does not prove a g++-only Linux box, because this machine is
darwin-arm64 and `c++` here resolves to clang. **NOT VERIFIED: Linux, g++ only.**

### Challenge 2 — the quickstart's "7 day" is correct, and the plan says it is wrong

KOSU-RABADON.md §1 says: `README:46 "last 7 day(s)" derken sayılar BENCHMARK:115'in
30 günlük sayıları (docs/quickstart.md:148 tekrarlıyor)`.

Half of that is stale and half is wrong.

- The README half is already fixed. `grep -c '7 day' README.md` returns 0. Its
  sample reads "last 30 day(s)" and names the command and date that produced it.
- The quickstart half was never the same bug. `rabadon usage` genuinely defaults
  to a 7-day window (`native/stats.cpp:472`, `double days = 7;`), and the sample
  at `docs/quickstart.md:148` is explicitly labelled "(EXAMPLE OUTPUT from a
  fresh install)" carrying fresh-install numbers — 3 refused, 41 gated, 0 repairs
  — not BENCHMARK.md's 30-day numbers. Rewriting it to 30 would make the
  quickstart advertise a window the command does not use unless you pass
  `--days 30`.

So R0 changes nothing there, and `reports/R0/accept.sh` claim 2b encodes the real
invariant instead of the plan's instruction: the quickstart may say 7 days **only
while the code still defaults to 7 days**. If that default ever moves, the test
goes red and the doc has to move with it.

## The eleven claims that did not survive primary-source verification

KOSU-RABADON.md §1b was written from research notes. On 2026-08-22 every product,
paper and number in it was checked against a primary source. Most held. These did
not, and they are marked UNVERIFIED in `docs/POSITIONING.md` rather than deleted,
because a claim we know is shaky is safer than one we quietly dropped and someone
re-invents in three weeks.

**Actively contradicted — two:**

1. **Lineman is not $49-149 per seat.** Its own pricing page says "One price
   covers your whole team — we never charge per person": Basic $14.99/mo, Pro
   $49.99/mo, team-wide, plus spend-based tiers.
   *This changes a decision.* The M4 price hypothesis argued $12/month per person
   is "far below their $49 seat". There is no seat. At $12/person, rabadon is
   **more expensive than Lineman for a team of two**. The price has to be
   re-argued on its own merits before M4, and it is not R0's call to make.
2. **There were no hooks-RCE CVEs in February 2026.** NVD was queried directly.
   The February 2026 Claude Code CVEs (CVE-2026-24052/24053/24887, Feb 3;
   CVE-2026-25722/25723/25724/25725, Feb 6) are command- and path-validation
   bypasses — a different class. The closest is CVE-2026-25725, where bubblewrap
   fails to protect `.claude/settings.json`. The PromptArmor writeup is real and
   is enough on its own; the CVE sentence must not be published.

**Could not be confirmed — nine:**

3. **SWE-agent never abandoned semantic stuck-detection over false positives.**
   An exhaustive issue, PR, git-log and source search found no such detector and
   no such decision. **Law 1 currently cites this as its first evidence and must
   stop.** The OpenHands evidence (#5355, plus the documented five-pattern stuck
   detector) is real and carries Law 1 by itself.
4. ccusage is ~18.1k stars, not "13k+"; the repo also moved from
   `ryoppippi/ccusage` to `ccusage/ccusage`.
5. Claude Code has **31** hook events, not 30.
6. SpecBench's 14.5-point figure is one case study inside it (Claude's C
   Compiler, 97.8% vs 83.3%), not its headline. The headline is LOC scaling.
7. EvilGenie establishes that an LLM judge beats held-out tests; it does not rank
   held-out tests above test-file-edited detection.
8. The file-level vs line-level localization result is not SWE-bench Verified
   specific. Drop that framing.
9. Tricorder's under-10% false-positive bar was confirmed in *Software
   Engineering at Google* ch. 20, not in the ICSE 2015 paper.
10. `agent-guardrails` as verified is CLI + MCP, not hooks-based; Morph's
    reflexes are positioned as classifiers, not guardrails. The claim "all
    guardrail products are hooks-based" is wrong. The claim that carries the
    positioning — none of them reads session history — is untouched.
11. claudemarketplaces.com's "380,000+ monthly visitors" is self-published and
    unaudited. Label it or drop it.

## Surfaced without being asked, and it cuts against us

**The cost-tracker market is not fragmented.** It is 18.1k and 9.6k stars, then a
cliff to 58, 26, 9 and 1. Two incumbents own the category. Any positioning line
that leans on "a fragmented tracker market" is not available to us.

**Anthropic's own costs page carries numbers we can quote** (they are the
publisher, so Law 7 permits it): ~$13/developer/active-day, $150-250/month,
under $30/active-day for 90% of users.

**Three Anthropic-adjacent plugin repos carry identical plugin names** —
`anthropics/claude-code/plugins/` is a demo marketplace,
`anthropics/claude-plugins-official` is canonical and auto-registered,
`anthropics/claude-plugins-community` is a third. R8 must ship against the
canonical one.

**Terminal-Bench naming is a trap for R7**: `laude-institute/terminal-bench` is
v1, `harbor-framework/terminal-bench-2` is v2, and the harness is now
`harbor-framework/harbor`. `alibaba/terminal-bench-pro` is third-party. R7 must
name which one it used or its numbers mean nothing.

## Left alone on purpose

`reports/T1/accept.sh` and `reports/T2/accept.sh` still name `PROTOCOL-T1-T8.md`
at its old root path, and both filter the repo root against a file list that
predates `KOSU-RABADON.md`. Re-running either today would likely go red on that
filter. They are **not** edited: an acceptance script is evidence of what was
accepted on the day it ran, and rewriting one so today's tree passes it is the
precise move this product exists to refuse. If T1/T2 ever need to be replayed,
that is a new report with its own reason, not a quiet patch.

## NOT VERIFIED

- `make test` on Linux with only g++ installed. Only the macOS clang-shim proof
  was run. S0.2 stays open.
- `npm view rabadon version` still returns 404. Nothing in R0 addressed that;
  it is R8's work.
- The `roboticforce/agent-guardrails` repo, which may be the hooks-based
  competitor §1b meant. Never fetched.
- Whether reports/T1 and reports/T2 accept.sh actually go red today. Suspected
  from reading their root-file filters; not run.

## NEXT

R1 — the move record. A ring buffer of the last 200 moves inside the session,
tier-0 normalized signatures, no detection and no injection. Its acceptance is
`native/moves_test.sh` with at least six assertions, the last of which is that
gate exit codes are byte-for-byte identical with recording on and off.
