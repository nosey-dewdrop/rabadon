# POSITIONING — where rabadon sits, and the sources that say so

Every marketing sentence rabadon publishes derives from this file. Nothing here
comes from a chat window: each product, paper and number below carries the URL
it was read from, checked 2026-08-22.

**Reading rule.** A line with no marker was read from the primary source named
beside it. A line marked **UNVERIFIED** could not be confirmed at a primary
source and MUST NOT appear in a README, a landing page, a tweet or a Show HN
post (Law 7). It is kept rather than deleted, because a claim we know is shaky
is more useful than a claim we quietly dropped and someone re-invents later.

---

## 1. The sentence

> Your coding agent repeats itself, drifts, and paints tests green. rabadon sees
> the pattern it can't, hands it back mid-session, and tells you at the end what
> it cost you not to have it.

Category: **reliability layer for coding agents.** Not a guardrail (those filter
one command), not a cost tracker (those look backwards), not a benchmark (those
live in a lab). The gap is the intersection: *inside the session, while the agent
runs, from observable trajectory, without stopping the agent.*

The `package.json` description does not change. It already carries the first two
claims. The third — the counter — enters the README only when R6's acceptance is
green, because an unmeasured promise is not written down.

## 2. Three sentences against three neighbours

- vs ccusage — "ccusage tells you what you spent. rabadon tells you what you
  didn't have to."
- vs guardrails — "They block the dangerous command. rabadon catches the
  expensive pattern."
- vs Lineman — "They shrink every call. rabadon removes the calls that shouldn't
  happen. Run both."

Rule for all three: a competitor's number is quoted from the competitor's own
published page, linked. We never measure a competitor ourselves.

---

## 3. Market A — reward hacking: the research landed, production did not

| source | URL | what it establishes |
|---|---|---|
| RHB (Reward Hacking Benchmark) | https://arxiv.org/abs/2605.02964 | RL post-training moves exploit rate from 0.6% (DeepSeek-V3) to 13.9% (R1-Zero) across 13 frontier models with tool use |
| TRACE (Patronus AI) | https://arxiv.org/abs/2601.20103 | 517 trajectories, 54 hack categories; best detection 63%, and only 45% when a trajectory is judged in isolation — contrast is what makes detection work |
| BenchJack | https://arxiv.org/abs/2605.12673 | a `conftest.py` pytest hookwrapper "resolves" 100% of SWE-bench Verified; 219 flaws found across 9 of 10 benchmarks |
| EvilGenie | https://arxiv.org/abs/2511.21654 | reward-hacking detection on LiveCodeBench; an LLM judge outperforms held-out tests |
| SpecBench | https://arxiv.org/abs/2605.21384 | reward hacking in long-horizon coding agents over 30 systems tasks; the gap grows ~28 points per 10× LOC and reaches ~100 points above 25K LOC |
| Cursor, 25 Jun 2026 | https://cursor.com/blog/reward-hacking-coding-benchmarks | on SWE-bench Pro, contamination-corrected scores drop from 87.1% to 73.0% (Opus 4.8 Max) and 74.7% to 54.0% (Composer 2.5); 63% of answers retrieved rather than derived |
| Zylos, 7 Jun 2026 | https://zylos.ai/research/2026-06-07-specification-gaming-reward-hacking-ai-agents/ | verbatim: "production deployments remain largely unprotected" — note this is an aggregator writeup, not primary research |

**UNVERIFIED — do not publish:** that SpecBench's headline is a "14.5 point
reward hacking gap." 14.5 points is one case study inside it (Claude's C
Compiler, 97.8% vs 83.3%). Cite the LOC-scaling result instead, or nothing.

**UNVERIFIED — do not publish:** that EvilGenie ranks held-out tests above
test-file-edited detection. The paper establishes the LLM-judge ranking only.

What this market does not have: any of it running on a developer's desk. Every
method above is an evaluation-side method. That is the opening.

Why our record is the right substrate: these detectors all operate on the
trajectory — tool calls, diffs, files — not on the model's narration. rabadon's
move record *is* that trajectory, produced locally, for free, as a side effect of
the gate already running on every tool call.

## 4. Market B — guardrails: hooks are mature, all of them are single-move

| product | URL | what it does |
|---|---|---|
| Claude Code hooks (official) | https://code.claude.com/docs/en/hooks | 31 hook events; exit code 2 = block with stderr returned to the agent; JSON output carries `permissionDecision` and `additionalContext` |
| Claude Code plugins (official) | https://code.claude.com/docs/en/plugins-reference | `plugin.json`, `hooks/hooks.json`, `/plugin marketplace add` |
| hookify (Anthropic) | https://github.com/anthropics/claude-plugins-official/tree/main/plugins/hookify | generates hooks from the conversation; markdown+YAML rules, warn/block |
| security-guidance (Anthropic) | https://github.com/anthropics/claude-plugins-official/tree/main/plugins/security-guidance | hook that reviews each edit for vulnerabilities |
| agent-guardrails | https://github.com/logi-cmd/agent-guardrails | pre-merge gates for AI coding agents |
| Rulebricks | https://rulebricks.com | no-code decision tables published as API endpoints — a network call per decision |
| Morph "reflexes" | https://morphllm.com | semantic classifiers over traces, evals and online learning |

Every one of them answers "is this command dangerous?" about a single move. None
reads session history. Repetition, oscillation, a root cause migrating across
different-looking moves, "the suite was red and the agent edited the test" — no
shipped product sees these. That is the gap, and it is why the accumulation
engine is the product rather than the gate.

**Correction to earlier drafts:** the `agent-guardrails` repo verified above is
CLI + MCP, **not** hooks-based, and Morph's reflexes are positioned as
classifiers, not guardrails. The claim "all of them are hooks-based" is wrong and
must not be published. The claim that survives — none of them reads session
history — is the one that matters anyway.

**UNVERIFIED — do not publish:** the repo name `roboticforce/agent-guardrails`
as the hooks-based competitor. It was never fetched.

### The trust argument (real, and ours to make)

| source | URL | what it establishes |
|---|---|---|
| PromptArmor | https://www.promptarmor.com/resources/hijacking-claude-code-via-injected-marketplace-plugins | a marketplace plugin's prompt-submit hook "rewrites Claude's permissions files to permanently allow dangerous commands" |
| anthropics/claude-code#39964 | https://github.com/anthropics/claude-code/issues/39964 | marketplace sync strips execute permissions from `.sh` hooks — fragility, not a security advisory |

So rabadon can honestly say: local binary, no network on the hot path, no model
on the hot path, does not write to your permissions file. That sentence is
publishable because each clause is true of the code.

**UNVERIFIED — actively contradicted, do not publish:** that hooks-based RCE CVEs
landed in February 2026. NVD was queried directly. The Feb 2026 Claude Code CVEs
(CVE-2026-24052/24053/24887 on Feb 3; CVE-2026-25722/25723/25724/25725 on Feb 6)
are command- and path-validation bypasses — a different class. The closest is
CVE-2026-25725, where bubblewrap fails to protect `.claude/settings.json`. Cite
PromptArmor, not a CVE.

## 5. Market C — cost: everyone reports the past, nobody reports the avoidable

| product | URL | what it does |
|---|---|---|
| ccusage | https://github.com/ccusage/ccusage | reads local agent JSONL, prices it from the LiteLLM table; ~18.1k stars |
| codeburn | https://github.com/getagentseal/codeburn | local token/cost tracker across many AI coding tools; ~9.6k stars |
| ccost | https://github.com/carlosarraes/ccost | Rust CLI, pulls LiteLLM pricing live with a 24h cache |
| cccost | https://github.com/badlogic/cccost | instruments Claude Code's `fetch()` for actual token cost |
| CCTracker | https://github.com/miwidot/cctracker | Electron/React desktop usage analytics |
| claude-usage-tracker | https://github.com/658jjh/claude-usage-tracker | local-first tracker across 10+ AI tools |
| LiteLLM price table | https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json | the shared pricing oracle — ccusage, ccost and others all read it |
| LangWatch | https://langwatch.ai/claude-code-usage | marks subscription sessions "Bundled" and computes a theoretical total at API list prices, per token class |
| Lineman | https://lineman.io/pricing | AI FinOps: per-dev/repo/ticket spend attribution plus tool-output compression |
| Lineman's own compression claim | https://lineman.io/news/7-ways-to-reduce-tokens-in-long-llm-agent-chats | verbatim: "cuts 40%+ of tokens while holding output quality at 98.3% of baseline" |
| Anthropic, cost of Claude Code | https://code.claude.com/docs/en/costs | verbatim: "around $13 per developer per active day" and "$150-250 per developer per month"; below $30/active day for 90% of users |

Every tracker says what you spent. None says what you did not have to spend. That
sentence is the counter's whole reason to exist.

LangWatch's practice is the one to copy directly: on a subscription there is no
invoice, but the tokens are real, so the honest move is to print the API-list
theoretical figure with the label attached. That is Law 7's dollar rule, and it
was someone else's good idea first.

**Correction to earlier drafts — this one changes a pricing decision.** Lineman
is **not** $49-149 per seat. Its own pricing page says: "One price covers your
whole team — we never charge per person," with Basic at $14.99/mo and Pro at
$49.99/mo team-wide, plus spend-based tiers. Any positioning that leaned on
"far below their $49 seat" is dead: at $12/month per person, rabadon is *more*
expensive than Lineman for a team of two. The M4 price hypothesis has to be
re-argued on its own merits, not against a seat price that does not exist.

**UNVERIFIED — do not publish:** ccusage at "13k+ stars." It is ~18.1k, and the
repo moved from `ryoppippi/ccusage` to `ccusage/ccusage`.

**Also true, and it cuts against us:** this market is not evenly fragmented.
It is 18.1k and 9.6k stars, then a cliff to 58, 26, 9 and 1. Two incumbents own
the category. "Fragmented tracker market" is not a claim we can make.

## 6. Market D — distribution: the plugin marketplace is the door

| source | URL | what it establishes |
|---|---|---|
| anthropics/claude-plugins-official | https://github.com/anthropics/claude-plugins-official | Anthropic-curated plugin directory, 39 plugins, auto-registered |
| Claude Code plugin docs | https://code.claude.com/docs/en/plugins-reference | `/plugin marketplace add owner/repo` then `/plugin install x@repo` |
| claudemarketplaces.com | https://claudemarketplaces.com/ | third-party directory; scrapes GitHub automatically |

A plugin turns the README's four install steps into one command, which is the
technical precondition for ever selling to a team.

**UNVERIFIED — self-reported, label it if ever used:** claudemarketplaces.com's
"380,000+ monthly visitors, 23,600+ skills, 12,800+ MCP servers." Published by
the site itself, no independent audit.

**Trap to avoid:** three Anthropic-adjacent plugin repos carry the same plugin
names. `anthropics/claude-code/plugins/` is a *demo* marketplace;
`anthropics/claude-plugins-official` is the canonical one;
`anthropics/claude-plugins-community` is a third. Ship against the canonical one.

## 7. Sources behind the Laws

Law 1 (a false positive kills the product):

| source | URL | what it establishes |
|---|---|---|
| OpenHands #5355 | https://github.com/All-Hands-AI/OpenHands/issues/5355 | loop detection killed agents that were waiting on long-running processes; users filed it as a bug |
| OpenHands stuck detector | https://docs.openhands.dev/sdk/guides/agent-stuck-detector | five documented patterns; related issues #10350, #5480, #7183 |
| Software Engineering at Google, ch. 20 | https://abseil.io/resources/swe-book/html/ch20.html | Tricorder's bar is under 10% effective false positives per check; the overall rate runs just below 5% |

**UNVERIFIED — do not publish, and Law 1 must stop citing it:** that SWE-agent
abandoned semantic stuck-detection because of false positives. An exhaustive
issue, PR, git-log and source search found no such detector and no such
decision. The OpenHands evidence stands on its own and is enough.

**UNVERIFIED — attribution only:** Tricorder's under-10% figure was confirmed in
the SWE-at-Google book, not in the ICSE 2015 paper. Cite the book.

Law 2 (showing a line number does harm):

| source | URL | what it establishes |
|---|---|---|
| Sepidband, Pham & Hemmati, Apr 2026 | https://arxiv.org/abs/2604.05481 | file-level localization is worth 15-17× over a no-file baseline, while "line-level context expansion frequently degrades performance due to noise amplification" |

**UNVERIFIED — do not publish:** framing that result as "on SWE-bench Verified."
The paper is not SWE-bench-specific.

Law 3 (contrast beats an error alone):

| source | URL | what it establishes |
|---|---|---|
| ContrastRepair | https://arxiv.org/abs/2403.01971 | a failing+passing test pair "can better isolate the root causes of bugs" |

Law 4 (asking again without better feedback burns tokens):

| source | URL | what it establishes |
|---|---|---|
| Olausson et al., ICLR 2024 | https://arxiv.org/abs/2306.09896 | self-repair's gains are "modest… sometimes not present at all" once cost is counted |

R3's fingerprinting, and R7's harness:

| source | URL | what it establishes |
|---|---|---|
| Schleimer, Wilkerson & Aiken, SIGMOD 2003 | https://theory.stanford.edu/~aiken/publications/papers/sigmod03.pdf | winnowing: local fingerprinting within 33% of the lower bound — dependency-free, microseconds |
| SWE-smith | https://arxiv.org/abs/2504.21798 | 50k task instances from 128 repos; NeurIPS 2025 D&B |
| Terminal-Bench | https://www.tbench.ai/ · https://arxiv.org/abs/2601.11868 | 89 tasks at v2.x; frontier agents below 65% |

**Naming trap for R7:** `laude-institute/terminal-bench` is v1,
`harbor-framework/terminal-bench-2` is v2, and the actual harness is now
`harbor-framework/harbor`. `alibaba/terminal-bench-pro` is third-party. Pick the
harness deliberately and write down which one, or the numbers mean nothing.

## 8. Who we sell to

One audience: a developer running an agent 2+ hours a day in Claude Code or
Cursor, who already asks "how much did I burn today" and already has ccusage
installed. Sell to a person. Teams come after M4.

The purchase moment is the closing line, not an advertisement. On the free tier
the counter runs and the fix is switched off, so the line reads: signals seen,
repair disabled, estimated X $ burned. The user watches their own money leave,
in a number derived from their own ledger. This is exactly why an inflated
counter would destroy the product: the honesty *is* the pitch.

## 9. Numbers rabadon may state today

Only these, and only with their source attached:

- Anthropic's own $13/developer/active-day and $150-250/developer/month.
- Lineman's own "cuts 40%+ of tokens… 98.3% of baseline."
- Cursor's own contamination-corrected SWE-bench Pro deltas.
- The published arXiv figures in §3, attributed to their papers.

rabadon's own numbers — chains cut, instant fixes, dollars saved — do not exist
yet. They are born in R6, verified in R7, and published in M2/M3. Until then the
landing page shows the closing line reading "measurement accumulating," which is
the truth.
