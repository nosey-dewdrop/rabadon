# f1d-C — `.rabadon/off` documented, B2 install lock

YAPILAN
- `3172895` — `native/install_docs_test.sh`: new B2 section. RED on purpose (35 ok / 3 fail); the criterion lands before the fix.
- `01a0951` — docs only: `docs/commands.md` (three-silencer table under `on|off|status|toggle`, `RABADON_OFF` row cross-linked, line 22 npm reference de-typed), `docs/faq.md` (silencer check is now step 2 of "the gate is not firing"; the npm/`--allow-scripts` answer rewritten around the from-source path), `docs/uninstall.md` ("silence it without uninstalling"), `docs/quickstart.md` §1 (from-source install, npm path kept as prose marked not-published). Nothing deleted.
- README.md and `site/index*.html` NOT touched: measured clean, B2 did not require it.

ÖLÇÜLEN
- `bash native/install_docs_test.sh` → **38 ok / 0 fail, exit 0**. The 20 pre-existing install-block oks are all still there.
- Empty-green round (`f1d-3-bosyesil.out`): dead command restored by hand → **37 ok / 1 fail, exit 1** (`docs/quickstart.md line 30:copy-paste block`) → reverted → green. Self-release proven by a real run in a temp repo tagged `v0.2.3`: the scan is skipped.
- Three silencers vs the shipped `native/rabadon-gate`, force-push event: control **exit 2** `baseline-force-push`; with `RABADON_OFF=1` / `<proj>/.rabadon/off` / `$RABADON_DIR/silent` → **exit 0**, no output, `$RABADON_DIR` left empty (nothing recorded).
- `rabadon off` in an isolated `RABADON_DIR`: prints WATCH, writes `mode`+`mode.last`, and `<proj>/.rabadon/off` **still there** — it removes no silencer. This is now in the docs.
- `git tag --list | grep -c '^v0.2.3$'` → **0**. No tag created. No network command run.

YAPILAMAYAN
- Clean-container run NOT VERIFIED — measured only on this macOS box. The new code is `git tag --list`, `grep`, `sed`, `find`, `awk` only, so it should hold, but that is an argument, not a run.
- The `rabadon doctor` sample in quickstart still prints `/usr/local/lib/node_modules/rabadon`; not re-captured for the `npm link` path (out of card, no code change allowed).

KART DIŞI (DOKUNMADIM, YAZIYORUM)
- `docs/uninstall.md:56` tells you to remove the CLI with `npm rm -g rabadon`. For the from-source `npm link` install the honest command is `npm unlink -g rabadon` (or `npm rm -g rabadon` from the clone). Same class of bug as B2, different verb, so my pattern does not catch it.
- Out of scope by design, all still carrying `npm i -g rabadon`: `CHANGELOG.md:18`, `site/patch-notes.html` (2 lines), `docs/archive/KOSU-RABADON.md:343`, `docs/internal/arsiv/PROTOCOL-T1-T8.md:423`. I extended the card's own history-forgery rationale from `docs/archive/` to `*/arsiv/*` and `docs/kanit/*` — a decision worth a second opinion.
- `PROJECT.md:61,163` and `SPEC.md:34` also state the npm install as the shipped path; the B2 lock does not cover planning docs.
- My scripted attempt to re-insert the dead line for the empty-green round was refused by rabadon itself (`no-blind-inplace-source-rewrite`, exit 2). Real catch, on this card, logged in the `.out`.
