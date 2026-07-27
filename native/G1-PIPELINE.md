# G1 pipeline — the engine JS dies

This is a hand-written instance of the contract rabadon itself will one day
generate (`rabadon do` plans work exactly like this). It exists because the
work it describes is precisely the kind that drifts: a multi-step migration
where "it compiles" quietly replaces "it behaves the same". So the pipeline is
declared before the work starts, every step has a checkpoint that must run
green before the next step opens, every repair loop is bounded, and the
promise pins what this work is NOT allowed to touch.

## the promise (drift rule)

- **Target:** zero `node` in any rabadon hook path; the engine lives in native
  binaries; the suite stays green at every step; the bench is re-measured, not
  re-claimed.
- **Allowed ground:** `native/`, `Makefile`, `~/.claude/settings.json` (hook
  rewiring), deletions of retired `.mjs`, `README.md` numbers.
- **Forbidden ground:** new features of any kind (this is a migration — parity
  plus root-fixes for the two known state bugs, nothing else), the landing
  (`index.html`, approval-locked), any new `.mjs`.
- **Loop bound:** each checkpoint gets at most 3 repair attempts; a 4th red is
  a STOP — the step is reported broken, never papered over.

## steps

S1. **State gets one owner.** `.rabadon/state.json` schema is fixed
    (lastCodeEdit/lastTestPass/lastTestFail/lastTestRun + sessions map);
    the native gate reads AND writes it via a minimal fixed-schema JSON
    writer; the parallel `state-native-*.txt` store is retired. Root-fixes
    ride along: the stray top-level `s` key dies; goal capture refuses the
    gate's own recursive prompts.
    ✓ checkpoint: new `native/session_test.sh` green + existing suites green.

S2. **Cold paths go native.** UserPromptSubmit (goal capture), SessionStart
    (reset + handoff injection), Stop (token ledger from the transcript,
    devridaim handoff write), non-tool 2s-bucket dedupe — all in `gate.cpp`.
    ✓ checkpoint: session_test proves goal→handoff round-trip natively.

S3. **PostToolUse goes native.** Code-edit tracking, scope fan-out, measured
    red/green test detection, incident diagnosis + re-anchor via bounded
    `claude -p` subprocess (LLM stays off the hot path; `RABADON_OFF=1` is
    passed to the child so the supervisor can never supervise itself —
    the root fix for goal poisoning), incident-authored guard rules.
    ✓ checkpoint: red-suite → diagnosis → new-rule path proven on a scratch
    repo; test-tamper chain E2E native.

S4. **The hooks are binaries.** `~/.claude/settings.json` rewired: every
    rabadon hook entry calls `native/rabadon-gate`; `delegate_to_node` and
    `hooks/gate.mjs` are deleted; `hooks/install.mjs` logic moves to init.
    ✓ checkpoint: a scripted 5-event session (prompt→edit→test→stop) runs
    end-to-end with `node` absent from every rabadon hook line.

S5. **The CLI is a binary.** `rabadon` (stats, guard, init, on/off, doctor,
    statusline, watch) in C++; `bin/rabadon.mjs` retired.
    ✓ checkpoint: command-output parity on the real spool.

S6. **The ui serves from the binary.** Local HTTP in C++; `ui/page.mjs` stays
    (browser page, exempt by law). `core/store.mjs` aggregation ported.
    ✓ checkpoint: dashboard renders the same ledger numbers.

S7. **The orphans are buried.** `core/rabadon.mjs`, `core/wrap.mjs`,
    `core/bus.mjs`, `repair/*.mjs`, demos that only exercised them — deleted
    (git history keeps them; the diagnosis already ruled them orphan).
    Bench re-run, README numbers replaced with the new measurements.
    ✓ checkpoint: `make test` + full suite green; language bar tells the truth.

## status

- [x] S1 — state.json single-owner native writer; stray `s` alias dead on
      first save; loop/dedupe/trail counters unified; session_test 7/7,
      full native 39/39, js 47/47
- [x] S2 — cold paths native: goal capture refuses the gate's own recursive
      prompts (poisoning root-fixed), SessionStart resets + injects handoff,
      Stop measures tokens from the transcript incrementally and writes the
      devridaim handoff; goal→handoff round-trip proven with zero node;
      session_test 15/15, native 47/47, js 47/47
- [x] S3 — PostToolUse native: code-edit tracking, scope fan-out, red/green
      detection (incl. the "fail 0" trap), incident diagnose + incident-rule
      authoring, all C++; run_claude spawns the model with RABADON_OFF=1
      (recursion root-fix); 53/53 differential node==native parity across every
      branch; native 100/100, js 47/47
- [ ] S4
- [ ] S5
- [ ] S6
- [ ] S7

Each finished step flips its box in the same commit that passes its
checkpoint.
