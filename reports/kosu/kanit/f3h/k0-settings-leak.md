# K0 — `make test` rewrites the operator's live `~/.claude/settings.json`

Measured 2026-08-30, macOS 24.2.0, this machine.

## Reproduction (deterministic)

    git worktree add --detach "$HOME/.rb-f3h-wt" F3h-oncesi
    cd "$HOME/.rb-f3h-wt" && make all
    shasum -a 256 ~/.claude/settings.json   -> 6c14cc5fdd4a3407a1448a14f9a6639c39c71327fe3d4e2ab6ae5cd3bb5680aa
    make test ; echo "EXIT=$?"              -> EXIT=0
    shasum -a 256 ~/.claude/settings.json   -> 427ffae042d1bffc1733e2dc878c49663a2f44bdaf6cd6be91b7fdc2f535abbe

The file CHANGED on a run whose exit code was 0. Seven `command` pointers were
repointed from the canonical clone to the throwaway worktree:

    hooks.UserPromptSubmit[1]   rabadon-gate  -> /Users/damummyphus/.rb-f3h-wt/native/rabadon-gate
    hooks.Stop[1]               rabadon-gate  -> same
    hooks.Stop[2]               rabadon-drift -> same dir (was _hakem_f3g_base, itself a stale arbiter leak)
    hooks.PreToolUse[1]         rabadon-gate  -> same
    hooks.PostToolUse[1]        rabadon-gate  -> same
    hooks.PostToolUseFailure[1] rabadon-gate  -> same
    hooks.SessionStart[0]       rabadon-gate  -> same

## Why this is not cosmetic on THIS machine

The same file carries entries that are not rabadon's: `orkestra/src/tick.py` on
nine events and `statusLine.command = orkestra/src/bar.py`. Those were not
modified, but the file is shared, and once the worktree is removed the user's
brake points at a binary that no longer exists and dies without a word. The run
protocol asks for a `--detach` worktree in every phase, so this fires every
phase.

## Which suites — measured, not suspected

Hashing the live file around each of `native/*_test.sh` in turn, restoring
between runs, inside the worktree:

    LEAK: native/contract_test.sh
    LEAK: native/promises_test.sh
    (every other suite: unchanged)

The five suites named on suspicion in the F3g verdict — `doctor_test`,
`exit_path_test`, `failed_call_test`, `hook_upgrade_test`, `npm_install_test` —
were each measured CLEAN, in the root clone AND in the worktree. They already
declare their own `HOME`. **That half of the F3g reading is corrected here.**

## Mechanism, read out of the source

`native/gate.cpp:refresh_hook_subscriptions()` rate-limits itself with
`<RABADON_DIR>/hooks-refresh.stamp`. Both leaking suites hand every arm a FRESH
`mktemp -d` `RABADON_DIR`, so the stamp is never there, so every `SessionStart`
spawns `hooks/refresh.mjs`, whose `refresh()` writes to `os.homedir()` — the
operator's. The product path is behaving as designed; the suites never said
which home they meant, so they borrowed the operator's.

## Isolation

`contract_test.sh` and `promises_test.sh` now allocate their own `HOME` and
export it. `RABADON_SELFHEAL` is untouched — the product path is not switched
off, only its address is declared. Held from the other side by
`native/home_isolation_test.sh` (6 assertions): it runs both suites against a
decoy home stocked to be maximally rewritable, and carries a control arm that
asserts an UN-isolated `SessionStart` still DOES rewrite, so the lock cannot go
vacuous the day the mechanism moves.

## Mutation proof

Removing `export HOME="$SBHOME"` from `contract_test.sh`:

    home_isolation: 4 passed, 2 failed   EXIT=1
      FAIL - contract_test.sh rewrote $HOME/.claude/settings.json
      FAIL - contract_test.sh left a .bak-rabadon beside the operator's settings

Restored: 6 passed, 0 failed, EXIT=0.
