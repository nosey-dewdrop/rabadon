redteam — the numbers that are ABOUT this gate rather than for it.

redteam.py         95 named escapes, one representative command each, judged by
                   the CURRENT binary. rc 2 = refused (closed), rc 0 = allowed
                   (still open). Nothing runs: PreToolUse only, fake rm/git/find
                   and every other destructive binary first on PATH, canaries in
                   the lab, and the fake-bin log is asserted empty at the end.
                     python3 redteam/redteam.py

ledger_replay.py   replays every real refusal in ~/.rabadon/spool through the
                   current gate. The command TEXT is recovered from the Claude
                   Code transcripts, because the ledger truncates at 160 chars.
                   Its input is this machine's own history and never leaves it;
                   only this script ships.

ledger_label.py    the labelling criterion, written once and applied
                   mechanically to every replayed refusal. TRUE means running it
                   unsupervised would have lost something irreversible. FALSE
                   means the refusal cut real work.

The fixture in native/precision_fixture.jsonl answers "is a refusal the right
refusal" on 34 cases lifted out of real sessions. These answer the harder
version of the same question on everything that ever happened, and the two
numbers are not the same number. Both are on the site, next to each other.
