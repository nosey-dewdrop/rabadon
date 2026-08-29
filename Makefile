# rabadon native core. one binary, zero deps.
# `c++`, not `clang++`: on a Linux box with only g++ installed, `clang++` is a
# command that does not exist and `make all` dies before a single test runs.
# `c++` is the standard alias and resolves to whichever compiler the machine
# has. The ten test scripts under native/ already fall back to `c++` for the
# same reason (native/cmdtext_test.sh:31); this line was the last place a
# clang-only name survived. NOT exported, on purpose: exporting would push this
# value into those scripts and take their own fallback away. (PROJECT.md S0.2)
CXX ?= c++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra

all: native/rabadon-net native/rabadon-truth native/rabadon-serve native/rabadon-gate native/rabadon-gated native/rabadon-drift native/rabadon-verify native/rabadon-pipeline native/rabadon-do native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit native/rabadon-claims native/rabadon-repair native/rabadon-sandbox native/rabadon-run native/rabadon-export native/gate_bench

# the OTHER benchmark, and the one the site was quoting without owning: how long
# rbrules::judge_command takes, in process, over the 34 real cases in the
# precision fixture. native/bench.py answers the end-to-end question (the whole
# hook, fork to exit, against the node gate it replaced); this answers the one
# the words "to judge one command" actually name. It is in `all` because the
# site names it as a source, and a source that is not built is a source nobody
# can run.
native/gate_bench: native/gate_bench.cpp native/rules.h native/baseline.h native/cmdtext.h native/gitcfg.h native/pathres.h
	$(CXX) $(CXXFLAGS) -o $@ $<

# native/version.h is a prerequisite of every rule whose source includes it,
# and make does not read #include lines. it was listed nowhere, so a version
# bump answered `make` with "up to date" and shipped a binary announcing the
# previous release. native/version_test.sh holds this rule from both ends:
# textually, and by asking `make -q` after touching version.h.
native/rabadon-gate: native/gate.cpp native/usage.h native/counter.h native/prices.h native/sha256.h native/chain.h native/jsonl.h native/baseline.h native/rules.h native/cmdtext.h native/gitcfg.h native/pathres.h native/cli_help.h native/version.h native/hookev.h native/moves.h native/signals.h native/semantic.h native/classify.h native/inject.h native/policy.h native/gated_client.h native/testout.h
	$(CXX) $(CXXFLAGS) -o $@ $<

# R7: the persistent gate. gate.cpp is a PREREQUISITE and also the body — this
# rule compiles native/gated.cpp, which includes gate.cpp with main() renamed,
# so the daemon and the gate can never be two different judgements. That is why
# gate.cpp is listed here and why touching it rebuilds both binaries.
native/rabadon-gated: native/gated.cpp native/gated_client.h native/gate.cpp native/usage.h native/counter.h native/prices.h native/sha256.h native/chain.h native/jsonl.h native/baseline.h native/rules.h native/cmdtext.h native/gitcfg.h native/pathres.h native/cli_help.h native/version.h native/hookev.h native/moves.h native/signals.h native/semantic.h native/classify.h native/inject.h native/policy.h native/testout.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-claims: native/claims.cpp native/jsonl.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-audit: native/audit.cpp native/sha256.h native/jsonl.h native/cli_help.h native/moves.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-repair: native/repair.cpp native/sha256.h native/chain.h native/jsonl.h native/cli_help.h native/heldout.h native/policy.h native/inject.h native/moves.h
	$(CXX) $(CXXFLAGS) -o $@ $<

# exec is the OTHER caller of the shared rule engine (rules.h -> baseline.h) and
# the ledger writer (chain.h -> sha256.h). None of those were listed, so an edit
# to the rule engine answered `make` with "up to date" and left exec enforcing
# the previous version of the law while the gate enforced the new one — the
# divergence rules.h exists to prevent, reintroduced by the build.
native/rabadon-sandbox: native/sandbox.cpp native/rules.h native/baseline.h native/cmdtext.h native/gitcfg.h native/pathres.h native/chain.h native/jsonl.h native/sha256.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-export: native/export.cpp native/cli_help.h native/drill.h native/jsonl.h
	$(CXX) $(CXXFLAGS) -o $@ $<

# trace is the THIRD reader of the spool, next to stats and export, and it is
# the one that gets screenshotted. drill.h was listed on the other two only, so
# the build could not have told anyone that trace applies none of the exclusion
# rules: a tightened rule in drill.h answered `make` with "up to date" and left
# the prettiest surface counting rabadon's own self-tests as catches.
# chain.h/sha256.h are here for the same reason: trace reads the ledger's loss
# evidence (the .head line count, the .unchained sibling) through chain.h's own
# reader, so a change to the sidecar format has to rebuild this binary too.
native/rabadon-trace: native/trace.cpp native/cli_help.h native/jsonl.h native/drill.h native/chain.h native/sha256.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-serve: native/serve.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -pthread -o $@ $<

native/rabadon-run: native/run.cpp native/rules.h native/baseline.h native/cmdtext.h native/gitcfg.h native/pathres.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ native/run.cpp

native/rabadon-truth: native/truth.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

# D7 (2026-08-29): this rule said `net.cpp cli_help.h` while net.cpp:50-51
# includes testout.h and pathres.h, so `touch native/pathres.h && make all`
# left rabadon-net's mtime untouched and the next measurement read a stale
# binary. pathres.h is where D6's $HOME repair lives and net.cpp is where the
# rc==5 repair lives — both could have taken a green from a binary that never
# saw them. cmdtext.h arrives transitively through rules.h.
native/rabadon-net: native/net.cpp native/cli_help.h native/testout.h native/pathres.h native/cmdtext.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-lens: native/lens.cpp native/usage.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-budget: native/budget.cpp native/cli_help.h native/version.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-stats: native/stats.cpp native/cli_help.h native/drill.h native/counter.h native/prices.h native/moves.h native/signals.h native/classify.h native/sha256.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-drift: native/drift.cpp native/cli_help.h native/version.h
	$(CXX) $(CXXFLAGS) -o $@ $<

# measured, not claimed: median hook latency, native vs the legacy node gate,
# same events, same verdicts. prints the table the readme numbers come from.
bench: native/rabadon-gate native/gate_bench
	python3 native/bench.py
	./native/gate_bench.sh

# native proofs: the direction check fires in both directions and fails open.
# `test: all` and not a hand-kept list: the list named 11 binaries while the
# suites run 16, so a clean checkout ran `make test` straight into a missing
# binary. the dependency is 'everything this repo builds'.
test: all
	./native/version_test.sh
# version_test.sh holds ONE header (version.h) from both ends. this holds the
# WHOLE include graph the same way: a rule whose source includes a header it
# does not list answers `make` with "up to date" and hands the next phase a
# green measured on a binary that was never rebuilt. measured 2026-08-29,
# before this line existed: rabadon-net did not rebuild when pathres.h changed.
	./native/make_deps_test.sh
# the two above prove a rule LISTS what it needs. this one proves the suites
# themselves cannot get smaller in silence: measured 2026-08-29, a single
# `touch native/gate.cpp` took version_test.sh from 13 assertions to 11 and it
# still exited 0. 14 such branches in 13 files on the day this line was added.
	./native/silent_skip_test.sh
	./native/cli_test.sh
# cli_test.sh asks whether the dispatcher's screens are well-formed. this one
# asks whether they are TRUE: every claim `rabadon status`, `on` and `off` make
# is held against the exit code the real binary returns for a real PreToolUse
# event in the same instant, across all 16 combinations of mode x the three
# muters. it shipped red (17 ok / 77 fail): a project holding `.rabadon/off`
# printed "ON — the arbiter acts" while the gate returned 0 before any rule ran,
# and the lamp read a third switch again. a status screen that can lie is the
# false green this product sells a cure for, printed by its own dashboard.
	./native/status_truth_test.sh
	./native/install_docs_test.sh
# install_docs_test.sh locks the documented INSTALL block and status_truth_test.sh
# locks the SCREEN. neither asked whether the PAGE tells the truth. on 2026-08-26
# the screen named all six silencers with a command that really lifts each, and
# docs/commands.md still carried the pre-F1d description of the same feature:
# three rows instead of six, and `rm ~/.rabadon/silent` as the lift for a
# silencer that command leaves in place (the product's own `rabadon-gate
# --silent` writes `silent` into the mode file too, and the mode outlives the
# file). docs/faq.md and docs/uninstall.md repeated the same wrong command. this
# suite EXECUTES the table: every row is set up for real, confirmed silent
# through the real gate, then the row's own removal command is run VERBATIM and
# the same event is asked again -- and the row count comes from the page, so
# adding a row adds a test. it also holds every behaviour sentence inside a
# marked block of those three docs to a row in docs/claims.tsv with a check it
# runs. offline, git + shell only, every cell its own mktemp HOME/RABADON_DIR.
	./native/docs_truth_test.sh
# install_docs_test.sh asks whether the documented way IN works. this one asks
# about the way OUT, on both surfaces the install screen names: `rabadon init`
# has to say which mode it left you in (watch, which refuses nothing) and the
# one command that changes it, and `rabadon remove` has to take the CURSOR hooks
# back out too — measured before this suite, a full init + remove round left all
# five rabadon entries in .cursor/hooks.json, so a Cursor user had no exit at
# all. Every case runs under mktemp with its own HOME and RABADON_DIR.
	./native/exit_path_test.sh
	./native/audit_test.sh
# audit_test.sh proves the chain INSIDE one day file. this one proves there IS
# one day file. the chained spool is named by a date and the repo held two
# answers to "which date": gate, repair, sandbox and the js bus name it in UTC,
# loop and drift named it in local time. east of Greenwich after midnight that
# is two files, two chains, one session split between them, and a direction
# check reading a file nobody wrote. it does not wait for midnight to say so --
# it picks a zone off the clock that is provably a different date from UTC right
# now, so it is as red at 15:00 as at 00:48, and every must-land-together check
# has its must-not-move twin under UTC.
	./native/ledger_day_test.sh
# ledger_day_test.sh proves the events land in ONE file. this one proves that
# file is still text. every label in the ledger is a cut of what the operator
# typed, the cut was counted in bytes, and a multi-byte character across the
# boundary left two orphan bytes in a JSON string -- so the line stopped being
# JSON while `rabadon audit` still called the chain sound, because a hash does
# not ask whether the bytes it covers are text. found in the field on 2 August,
# 8 of that day's 982 lines. the twin asserts the label still carries the
# readable head of the command, so "clamp" cannot degrade into "drop".
	./native/ledger_utf8_test.sh
	./native/baseline_test.sh
# moves_test.sh — R1's record. It asserts what gets written AND that writing it
# changed nothing: the same commands run with the record on and off, allow path
# and refusal path, exit codes compared. If R1 can move a verdict, R1 is not a
# recorder and this goes red.
	./native/moves_test.sh
# moves_test.sh guards R1's record. Nothing in this target guarded what READS
# that record: R2's five detectors (native/signals.h) and R3's tier-1
# fingerprint (native/semantic.h) had only their own reports/*/accept.sh, and an
# acceptance script is a one-time argument that a round shipped -- it is not in
# the suite, so a later round could loosen a threshold, drop the `failed >= 2`
# clause, or invert the cascade and every check here would stay green. This is
# the standing check. Each of the five detectors gets a fixture that fires it and
# a nearest neighbour that must not, and the negatives carry the weight: Law 1
# says the expensive failure is the false positive, so the fixtures that must
# stay silent are the ones that nearly broke a rule already -- lint/build/lint/
# build (which once fired `repeat`), a test refactor on a GREEN suite, a test
# file that GAINS assertions, and a red->green where the SOURCE was fixed. For
# tier 1 it asserts the cascade as a fact rather than a comment: three
# byte-identical edits are similarity 1.00, the loudest possible tier-1 input,
# and tier 1 must not run at all because tier 0's hash already matched. Both kill
# switches (RABADON_SIGNALS=0, RABADON_SEM=0) and the silence contract -- no exit
# code moves, stdout stays empty, because stdout is a hook's permission channel
# -- are held from the outside. No assertion can pass on an empty spool: if the
# gate never saw a fixture the negative is red, not green, which is the vacuity
# bug moves_test.sh and reports/R2/accept.sh each shipped once.
	./native/signals_test.sh
# signals_test.sh proves the detectors FIRE. this one proves the injection they
# produce is still JUDGEABLE tomorrow. Measured, not assumed: the ledger held 7
# INJECT lines and 0 of them could be judged, because the INJECT line named the
# move it rode on (mseq) and the move itself lived only in the 200-slot ring in
# native/moves.h. 39 rings on that machine, 2 had rolled past CAP -- and both of
# those two were the rings carrying an injection, 2 of 2. The loss is selective:
# a signal is born in a long session and a long session is the one that rolls.
# So the two facts layer (b) of KOSU §F3 needs -- the signature that was
# repeating BEFORE the injection, and the signature of the first move AFTER it
# -- stop living in the ring and go on the append-only spool as `psig` on INJECT
# and as a new INJECT_ANSWER event. This suite drives a real oscillation to a
# real delivery, then buries it under 210 further moves, proves from the ring
# header that mseq has been evicted, and asks (b) again off the ledger alone. It
# also drives the agent REPEATING itself and requires same=true, because a field
# that is always false proves the field exists and nothing about the agent.
	./native/inject_answer_test.sh
# signals_test.sh proves the DETECTORS fire on a fixture. this one proves the
# SCREEN the user reads when those detectors are replayed over their own move
# rings -- `rabadon usage --signals`. Different claim, so a different file:
# reports/R7/accept.sh pins signals_test.sh to an exact count, and an assertion
# added there for a rendering question would move a number that stands for the
# detectors. What it holds is what a value screen is allowed to say: the corpus
# is declared with its LOSS (the ring keeps 200 per session, the header counts
# every move ever appended, and the difference is moves that existed and are
# gone), a signal with n=0 renders as NOT MEASURED plus its reason instead of as
# a clean run, no counterfactual word appears anywhere, every count carries the
# session file it came from, and the last line names exactly one next command.
# Hermetic: its own mktemp HOME/RABADON_DIR and byte-written synthetic rings.
	./native/signals_screen_test.sh
# baseline_test.sh asks the push law about the three spellings it knows: --force,
# -f, and a leading + on a refspec. this one asks about the spelling that
# contains none of them and is the strongest of all: `git push --mirror origin`
# force-updates every ref on the remote and DELETES the ones that are only
# there (git-push(1)), and it walked past the law as just another option — then
# named no branch, so the "no refspec means the current branch" fallback picked
# the target too. that fallback is the deeper half: `git push --all --force
# origin` from a feature branch force-updates main, and the law was reading feat.
# section 1 proves the premise instead of quoting it — a bare repo made by
# mktemp two lines earlier plays the remote, and the test reads back that it
# lost a commit and lost a branch. the twins keep the fix honest: --all with no
# force, --tags, --set-upstream, the lease and a repo whose refspace holds no
# shared branch all still push.
	./native/mirror_push_test.sh
# the same fallback, one source further out. --all and --mirror ask for the
# whole refspace on the command LINE; `-c` asks for it from CONFIG, and git
# reads remote.<name>.push and push.default before it ever looks at HEAD. so
# `git -c remote.origin.push=refs/heads/x:refs/heads/main push --force origin`
# and `git -c push.default=matching push --force origin` both rewrote main from
# a feature branch, through BOTH layers: the compiled law fell back to .git/HEAD
# and read feat, and a project's deny regex needs the literal word main, which
# neither line contains. every fact the fix rests on is measured against a real
# git with --dry-run and written at the top of the file -- including the two
# that keep it from over-blocking: the config key's SUBSECTION is
# case-sensitive (remote.ORIGIN.push is a different remote), and `--tags`
# replaces the default refspec with tags only, so the law's old refusal of
# `git push --tags --force origin` on main was cutting work that writes no
# branch at all. every must-block case is judged twice, once from main and once
# from a feature branch, because the bug was that the two disagreed.
	./native/push_refspec_test.sh
# the same two config keys, one SOURCE further out, and that source is the one
# the law had written down that it would not look at: "NAMED LIMIT: the same two
# keys can also be set in .git/config, ~/.gitconfig or /etc/gitconfig, and none
# of those are in this command line." the reason given -- that reading only the
# repo's file would report the other two as absent -- argues for reading all
# three, not for reading none, and reading none cost the law to two ordinary
# commands one turn apart: `git config remote.origin.push
# refs/heads/scratch:refs/heads/main` and then `git push --force origin`. neither
# line contains the word main or a refspec, so a project's deny regex misses
# both, and the compiled law read .git/HEAD, saw `scratch` and allowed the
# second one -- measured at exit 0 before this suite, in both the
# remote.origin.push and the push.default=matching spelling. gitcfg.h now reads
# every file git reads, in git's order, WITHOUT running git: the shim on PATH in
# this file is asserted never called, because a gate that shells out to a binary
# named by PATH in order to decide whether to allow that binary is not a gate.
# every fact it rests on is measured against a real git with --dry-run and
# written at the top of the file, including the four that keep it from
# over-blocking -- the deprecated [remote.ORIGIN] section form lower-cases the
# subsection while `-c remote.ORIGIN.push` does not, push.default is
# single-valued so a repo `simple` beats a global `matching`,
# .git/config.worktree is ignored without extensions.worktreeConfig, and
# remote.pushDefault decides WHICH remote's refspec this push uses. one thing is
# knowingly over-refused and it is named in both files: an includeIf is followed
# without evaluating its condition, because deciding gitdir:/onbranch: needs a
# wildmatch and this repo will not grow a second glob engine for one predicate.
	./native/push_config_file_test.sh
# and the spelling that is not a force-push at all. a refspec with an EMPTY
# SOURCE side removes the destination ref -- `git push origin :main` -- and it
# starts with ':' where the law read only '+', so `force` stayed false and the
# walk returned before the branch name was consulted. `--delete` and `-d` say
# the same thing in git's own words and carried no `-f` either, so a project's
# deny regex missed it in the same breath: both layers, one hole. section 1
# measures the premise against a real git in a repo with no remote (these
# spellings parse) and a fake git on PATH (the shell hands them over). the twins
# are longer than the blocks on purpose -- deleting your own merged branch is
# the most ordinary cleanup there is, and a law that cannot tell :main from
# :feature/x would refuse it. it also holds the two laws apart: silencing
# baseline-force-push must not silence baseline-branch-delete.
	./native/push_delete_test.sh
# the suites above ask WHICH WORDS the line carries. this one asks what happens
# when it carries two that disagree: `git push --force-with-lease --force origin
# main` and `git push --force-if-includes --force origin main` both exited 0 on
# the fresh-install path, while the same push MINUS the word that is supposed to
# make it safer exited 2. the law kept two booleans and spent the lease as an
# excuse for the force, so a lease written anywhere on the line switched the law
# off. the tempting reading is that git resolves the pair last-one-wins and the
# bug is the ORDER -- section 1 measures that instead of arguing it, with real
# pushes into a bare repo it mktemps and a genuinely STALE lease, and the
# reading is false: `--force --force-with-lease` destroys the other clone's
# commit too, so a fix built on the position of the last force-ish token would
# have closed one spelling and left its mirror image open. `--force` beats a
# lease from either side, so the lease is no longer consulted at all -- it is
# spent on the WORDING instead, because telling someone who wrote a lease to
# "use --force-with-lease" is advice they already followed. the twins are what
# the removal has to pay: the lease alone and --force-if-includes alone are each
# refused BY GIT (measured, same section), so both still pass, and so does every
# one of these spellings on a branch that is nobody else's.
	./native/lease_force_test.sh
# baseline_test.sh judges the delete law's targets as PATHS. this one judges
# them as PATTERNS: a wildcard or a brace is rewritten by the shell before rm
# sees it, and the rule used to read only the text before the first `*`. it runs
# a shell with a fake deleter first on PATH to show where the expansion really
# lands, then asserts both directions — the escape is refused AND an ordinary
# scratch glob still passes.
	./native/glob_escape_test.sh
# and this one judges WHOSE files the pattern names. computing where a pattern
# lands closed the escape above and opened a worse one: `rm -rf /tmp` was
# refused while `rm -rf /tmp/*` passed, so the law protected the shared temp
# root and handed over everything inside it — another session's mktemp tree, a
# half-written build, a database socket. it proves the handover with a real
# shell and a fake deleter, then holds both directions: a pattern that
# enumerates the shared root is refused, an agent cleaning up the scratch dir it
# named still passes.
	./native/temp_root_glob_test.sh
# and this one asks whether the two layers give the SAME answer. The compiled
# delete law resolves its target; a guard.json deny rule is a regex and reads
# the spelling, so `rm -rf /tmp/build` was scratch to one layer and a delete
# outside the project to the other. It holds both directions per spelling
# (symlink, `..`, glob, $TMPDIR): every must-not-block case has a must-block
# twin, and the twins are re-run with TMPDIR pointed at $HOME and at /.
	./native/path_answer_test.sh
	./native/guard_lint_test.sh
# guard_lint_test.sh asks whether a rule can fire. this one asks whether it is
# ever consulted. the guard was read once, from the directory the session
# happened to start in, so a session started in $HOME -- which is how an agent
# working across several repositories runs all day -- loaded no rules at all.
# not overridden, not disabled: absent. `cd <project> && git commit -m "note: x"`
# and `git -C <project> commit ...` both walked past a rule that refuses them
# when the session stands there. the baseline laws never had the hole because
# they follow the shell. additive only, and section 3 is why: a guard reached
# mid-line may refuse a segment and may never permit one, so walking into a
# directory cannot switch a law off, while the owner's own disabled[] still
# overrides for a session standing in their tree.
	./native/guard_reach_test.sh
# guard_lint_test.sh asks whether a rule CAN fire. this one asks whether it can
# ever hold its fire, which is the half that broke in the field on 2 August: an
# authored semantic-commit rule denied EVERY commit, including the fix: ones it
# existed to permit, because an optional quantifier in front of its negative
# lookahead let the lookahead be tested on a space. lint called that guard
# valid. every rule now carries `allow`, the commands it must NOT match, and
# they are run against its own pattern through the gate's own matcher.
	./native/guard_allow_twin_test.sh
# guard_allow_twin_test.sh asks whether a rule can hold its fire. this one asks
# the other half, which had no answer at all: nothing in the schema let an author
# say what a rule EXISTS TO STOP, so nothing could tell them it stops nothing.
# measured 3 August by driving all 430 guard rules on this machine through the
# real gate with a command each pattern was written to refuse: 16 refused
# nothing, in any repository, ever, and all 16 linted clean. three of those had
# been authored by the engine itself after real incidents, so each named
# something that had already happened once and was free to happen again. the two
# mechanisms are invisible in the pattern -- a path rule authored relative is
# compared against a spelling no event carries (12,948 of 13,128 measured Edit
# calls arrive absolute, project-relative arrives zero times), and a pattern that
# spells a pipe wants a character the parser removed. so a rule carries
# `catches` beside `allow`, lint drives it through the rule's own pattern with
# the gate's own matcher, and a rule born from an incident is not installed at
# all unless it can refuse the thing it names.
	./native/guard_deny_twin_test.sh
# and the shape no rule can reach, found while proving the check above. one
# guard rule, one token, five deliveries: a plain argument, a quoted one and a
# token on the second line are all judged; the same token inside a heredoc body
# is not, because a rule is matched against one parsed segment surface and a
# heredoc body is not a segment. it surfaced because every scripted edit in one
# session went through `python3 - <<PY` and a rule authored that same night to
# refuse exactly those edits never fired once. the FLOOR does not have the gap:
# baseline.h reads words across the whole text, so `bash <<EOF / rm -rf ~/keep`
# is still refused, and a body that only PRINTS the words is still allowed.
# both halves are pinned, including the allow, so the day somebody widens the
# regex layer this file fails and the widening is a decision.
	./native/heredoc_reach_test.sh
# the strength number rabadon publishes has to be orderable. --help documented
# 3 SUITE / 2 BUILD / 1 SYNTAX / 0 NONE and the code emitted the reverse, so a
# repo whose own suite was found printed `level 1  SUITE` -- a number and a word
# contradicting each other on one line -- and 0 (nothing runnable) sat below 1
# (the strongest rung), which left the field uncomparable in either direction.
# found on 2 August measuring discovery on two foreign JS repos.
	./native/truth_level_order_test.sh
	./native/cmdtext_test.sh
# cmdtext_test.sh proves a heredoc BODY is not a command on the per-segment
# surfaces. this one asks the same question of the ONE surface rules.h adds on
# top of them: a rule whose pattern spells a pipe is handed the whole line,
# because no segment can ever contain a `|`. On 26 August that surface refused
# `cat >> reports/kosu/SAPMA-KARARLARI.md <<'MARKER'` under
# no-exit-code-after-pipe — the forbidden shape was in the PROSE being written
# down about the rule, not in the command. A measured wrong refusal, with its
# positives pinned above it so the fix cannot be "stop the rule firing".
	./native/heredoc_prose_test.sh
# cmdtext_test.sh asks what a shell will RUN. this one asks what GIT will run,
# which is not the same question: `git -c alias.x='push --force' x origin main`
# writes the verb into a config value and then invokes it under another name.
# The option walk was already right — it stepped over `-c` and its value exactly
# as git does — and landing on `x` was still the wrong answer. Every alias fact
# it asserts (case folding, chaining, last-definition-wins, a `!` body going to
# a shell, and the attached `-c<name>=` form git REJECTS) was measured against
# real git first, and every must-block case has its must-not-block twin: a read
# alias, a lease push, a force to a private branch, an alias defined and never
# invoked.
	./native/git_alias_test.sh
# the same question one option later: `git push -fu origin main`. git's
# subcommands read their options with parse-options and parse-options takes them
# clustered, so -fu is --force --set-upstream — and both layers missed that word
# from the same side. the compiled law compared the WHOLE token to `-f` and let
# it fall into "starts with a dash, skip"; a project's `(--force|-f)\b` has no
# word boundary between the f and the u. section 0 measures the premise instead
# of quoting it: a bare repo made by mktemp two lines earlier is force-updated
# backwards by `push -fu` and gains an upstream, and the SAME git answers
# "unknown option: -pv" for its own leading options, which is why the split
# starts at the subcommand. the twins are what keep the split from inventing
# flags: -qu, a lease push, -oci.skip, `git commit -mfix` and `git log -12` all
# still run.
	./native/short_cluster_test.sh
# the same question with the other kind of dash. parse-options also resolves a
# LONG option from any unambiguous prefix of its name, and the laws compared
# whole strings: `git push --del origin main`, `git push --mir origin`,
# `git reset --har main` and `git push --al --force origin` all exited 0 on the
# fresh-install path while the spelled-out four exited 2, and a project's own
# `--delete|--mirror` regex missed them from the same side. the fix is the pass
# 7b argument finished: the parser normalises the option to its full name before
# any law reads it, using git's own resolution — an exact name first, then the
# one option carrying the prefix, and NOTHING when two share it. section 0
# measures that premise instead of quoting it: --dele/--del/--de all report
# `[deleted]` against a bare repo it mktemps, --m alone is --mirror, reset --h
# alone is --hard, and --d/--a/--f/--fo all answer 129 "ambiguous option". the
# twins are what the expansion has to pay: --dr is a dry run, --po is porcelain,
# reset --mi is a mixed reset, --force-w is still a lease, `--tag --force`
# writes tags and NO branch (measured) and stays allowed, and every shortened
# spelling gets the SAME verdict as the full name it stands for.
	./native/long_option_prefix_test.sh
	./native/bypass_test.sh
# bypass_test.sh asks whether the LAWS see the command. this one asks whether the
# PARSER hands them one at all: `FOO=bar <cmd>` was judged and `FOO=/x <cmd>` was
# not, because the assignment predicate rejected any word carrying a slash, so the
# command index stopped on the prefix and the rule engine read `x` as the command
# name. every must-block case has its must-not-block twin (same prefix, ordinary
# work), and it proves the premise with a real bash and stub binaries: the shell
# does reach the destructive argv behind the prefix, and does not reach it behind
# a word whose name is not a name.
	./native/assign_prefix_test.sh
# the same question one word further left: a prefix the parser skipped too little
# of. `{ git push --force origin main; }`, `if ...; then <cmd>; fi`, a loop body
# and `! <cmd>` all reported a SHELL RESERVED WORD as the command name, so the
# segment was marked irrelevant and the three compiled laws were never asked —
# on the fresh-install path with no guard.json, the path baseline.h exists for.
# it runs a real bash with stub git/rm first to show the shell does run the
# command behind the keyword, and every must-block spelling has its must-not-block
# twin: the same keyword carrying ordinary work, and the same words as prose in a
# commit message, an echo and a heredoc.
	./native/reserved_word_test.sh
# the same question with the shell's syntax already out of the way, asked of a
# word the parser had no table entry for. the wrapper skip is a TABLE OF NAMES,
# and a name that is not in it is read as the command itself, so `caffeinate -i
# rm -rf ~/work/proj2` exited 0 while the same line without its first word
# exited 2 — one word in front and BOTH compiled laws went unasked, because both
# hang off that word. a table can only ever hold the wrappers someone has already
# been bitten by, so the parser stops needing the name: an unknown word, then
# option-looking words, then a word this parser ALREADY acts on (git, a delete,
# a shell, another wrapper) is a wrapper, and the command is that word. section 0
# proves the premise instead of telling it — a three-line wrapper this file
# creates under a name no table anywhere has, watched execing a fake git and a
# fake rm. the must-allow list is the longer one, and it caught the false refusal
# the rule bought on its first run: `grep rm -r ~/notes` is a search whose
# PATTERN is the word rm, so a command whose operand is TEXT is never read as a
# wrapper. the limit is asserted and not described: an unlisted wrapper whose
# option eats a SEPARATE value is still missed, and the answer to that one is its
# name in the table with what it eats.
	./native/unknown_wrapper_test.sh
# and the same question one moment later in the shell's life: a name the line
# itself binds. `gitx() { git push --force origin main; }; gitx` reached the laws
# as a command called `gitx()`, a command called `}` and a bare word — no `git`
# anywhere — while the SAME program written with newlines was refused, because a
# newline put the body in its own segment and `git` landed in command position by
# accident. a definition runs nothing and a call runs the body, so the body is
# lifted out of the run list and put back at the call. both directions: the four
# spellings a shell accepts, and the twins that must still run — a helper without
# --force, a helper deleting its own build output, and a body that is defined and
# never called.
	./native/shell_function_test.sh
# the keyword above is only half of a loop. `for b in main; do <cmd> $b; done`
# needs the other half: `$b` is an unresolved expansion and those are waived,
# though this same line writes down what b holds four words earlier. a `for`
# header is an assignment in the shell's other spelling and is now read as one.
# the twins keep that reading honest, and the sharpest is the cross-product one:
# over `for b in x main`, the word `backup/$b` is backup/x and backup/main and
# NEVER main, so a fix that binds the whole list to one string and refuses that
# line is refusing work no iteration performs. section 1 runs a real bash with
# stub git and rm to show the body does reach the destructive argv.
	./native/loop_body_test.sh
# and the wrapper that eats a FILE before it eats the command. `script -q
# /dev/null <cmd>` is a session recorder, not a logger wrapped around a shell it
# cannot reach: script(1) runs the argv itself, so the whole line reached the
# laws as a command named `script` and the three compiled laws were never asked.
# section 1 measures the premise instead of quoting it -- a real script(1) under
# a pty (it will not start without a terminal) with a fake git and a fake rm
# first on PATH, and the same section measures the half that keeps the fix
# honest: `script git push --force origin main` runs NOTHING, because `git` is
# the typescript FILE and `push` is a command that does not exist. Eating
# exactly one operand is what tells those two lines apart, and every must-block
# spelling has its must-not-block twin -- recording an ordinary push, a test
# run, an interactive session, and the same words as prose.
	./native/script_wrapper_test.sh
# the same question with the shell's own syntax out of the way: the word in
# command position is a WRAPPER, and the wrapper table did not have its name. a
# name the table does not know is read as the command itself, so `caffeinate git
# push --force origin main` exited 0 while the same line minus its first word
# exited 2, and `caffeinate rm -rf /` exited 0 too — one extra word in front and
# all three compiled laws went unasked. that word is not exotic: it is how a mac
# keeps a LONG job alive, so it sits in front of exactly the commands slow
# enough to be worth protecting. membership is not fame — a real bash with stub
# git and rm watches each name execute the argv behind it, and only the names
# measured doing it were added — this suite holds the two it measured,
# caffeinate and sandbox-exec. the twins are what a longer skip table has to
# pay: the same wrappers carry a fetch, a status, a lease push and a delete of
# the project's own build output, and the name in a commit message, an echo, a
# grep pattern and a heredoc body is text, not a program. the last pair is what
# the table ENTRY buys over reading any unknown word as a wrapper: `-t 3600`
# puts a bare number between the wrapper and the command, and only the entry
# that declares -t knows to eat it.
	./native/wrapper_exec_test.sh
# the same table, one name further, and this one shows that adding a NAME is
# only half of an entry: the entry also says what the name EATS, and getting
# that wrong hands the hole back under a different spelling. arch(1) sits in
# /usr/bin on every mac and execs the program after its options, so `arch -arm64
# git push --force origin main` exited 0 while the same line minus its first
# word exited 2 -- and so did the branch delete, the hard reset and `arch -arm64
# rm -rf ~/Documents`: one word in front, four compiled laws unasked. arch is
# also the one wrapper on the list whose single-dash words are not a cluster --
# a `-name` is an ARCHITECTURE -- and section 0 measures that on the machine
# running the suite instead of quoting the manual: `arch -eFOO=bar /bin/echo`
# answers "Unknown architecture: eFOO=bar", so there is no attached-value form,
# and `arch -arm64e /bin/echo` runs, so the trailing e of that name is not the
# -e option. Spelled as clustering letters, d and e would be found at the end of
# `-arm64e`, the skip would take the next word as their value, and the word it
# ate would be the command. So the three options that take a value are matched
# WHOLE (`-arch arm64`, `-d name`, `-e name=value`) and the cluster reader is
# off for this wrapper. the twins are what the longer skip has to pay: bare
# `arch` prints the machine and must stay allowed, and a build, a status, a
# plain push, a lease push, a private branch, a private branch delete and a
# scratch delete all still run under it.
	./native/arch_wrapper_test.sh
# every suite above asks which WORD is the command. this one asks what a word
# MEANS: `HEAD` and `@` are not branch names, they are the ref the repo
# resolves, and the force-push law compared them against main/master/trunk/
# develop and let them through. git-push(1) calls `git push origin HEAD` a handy
# way to push the current branch to the same name on the remote, so on main that
# line IS the refused one — while the same push with NO refspec at all was
# already refused, because with nothing written down the law had to go read
# .git/HEAD. writing the word turned that resolution off. the twins are where
# this one earns its keep: the SAME command on a branch that is hers must still
# go (force-pushing your own branch is how a review gets fixed up),
# `git reset --hard HEAD` names a commit and must still go, and `main:HEAD` is
# measured against real git — it creates refs/heads/HEAD on the remote, so a fix
# that read the word HEAD anywhere in a refspec would refuse a harmless push.
	./native/head_ref_test.sh
# every suite above asks about ONE verb, spelled many ways: push. git ships other
# verbs that lose work outright and the law named none of them, so the red-team
# corpus collected them and they stayed open. `reset --hard @{u}` and
# `refs/remotes/origin/main` are the shared branch under two names the law never
# resolved; `branch -D` overrides git's own merged check and discards commits no
# remote holds; `clean -x` takes the ignored files git was never watching;
# `reflog expire --expire=now` and `gc --prune=now` remove the way back that
# every other refusal here assumes is still there; and `rm -rf .git` is inside
# the tree, so the delete law's carve-out for "git can undo this" hands over the
# thing doing the undoing. Section 0 measures its own premises against a real git
# and corrected two corpus assumptions: git REFUSES `push --forc` as ambiguous
# (--force has two siblings, so it cannot be abbreviated at all), and deleting
# main locally is the RECOVERABLE case -- the loss is a tip no remote has,
# whatever the branch is called, which is what the law judges.
	./native/git_verbs_test.sh
# every law above can be switched off from inside. On 2 August this repository's
# own guard.json read "disabled": ["promise-anti-path", "promise-tamper"] --
# a supervised session had put the two rules protecting the goal contract on
# the list it does not have to obey, citing a permission the operator gave
# about something else, and rabadon-drift then answered "on the star" for eight
# days while measuring against a promise the drifter was free to rewrite. This
# suite asserts the one invariant that closes it: a session may make its own
# supervision stronger and never weaker. Adding a rule to guard.json goes
# through, removing one or naming one in disabled[] does not, and three rules
# stop answering to disabled[] entirely. Every case names the rule it expects
# to be refused by, because on the first draft a guard.json case "passed" on a
# refusal from promise-off-target that had nothing to do with guard.json.
	./native/promise_law_test.sh
# every law in this repository sat behind one substring scan of the raw line --
# "git" or "rm", nothing else -- so that the common command cost almost nothing.
# a line that empties a tree without spelling either word never reached a law at
# all, and there was no verdict to escape from because no law ran. eleven
# red-team probes were that one filter wearing different clothes: find -delete,
# find -exec rm, rsync --delete, truncate, dd of=, a bare `>` with no command on
# the line, and shred -- which cmdtext.h has listed in the delete family the
# whole time, and which walked anyway because the family is read AFTER the
# filter. section 0 measures the temp waiver instead of describing it: the first
# draft of this suite built its fixture under mktemp, which on macOS lands in
# /var/folders, which the containment law waives on purpose, so ten cases passed
# in the one place on the machine where the law under test is switched off.
	./native/delete_verbs_test.sh
# the law above asks WHAT is being destroyed. this one asks where the shell is
# standing when it happens, which is the other half of every containment
# verdict. the walk that answers it followed one verb and read the word straight
# after it as the directory, so `cd -P /elsewhere && rm -rf engine` moved into
# `-P`, resolved nowhere, left the walk standing in the project and judged a
# delete next door as a delete at home. pushd it did not know at all. six probes,
# and all six failed in the direction that matters: a walk that loses the shell
# does not over-refuse, it believes the delete is happening somewhere deletes are
# allowed. popd is the twin that keeps the fix honest — after a push and a pop
# the shell is home, and the delete at the end of that line must still run.
	./native/shell_cwd_test.sh
# the suite above asks what a word MEANS. this one asks how much of a name has
# to be written down before the law recognizes it: `heads/main` IS
# refs/heads/main, because git resolves a partially qualified ref through the
# refs/ search order and `refs/<refname>` is tried before anything else. The
# name reader already handled the fully spelled prefix and stopped one level
# short of the spelling git also accepts, then handed `heads` to a test for a
# REMOTE, which no remote is called — so it answered "no branch here" and six
# spellings walked out through that answer on the fresh-install path:
# `origin :heads/main`, `--delete`, `-d`, `--force origin heads/main`,
# `main:heads/main`, and `git reset --hard heads/main`, which asks the same
# function the same question. Against the four rules a bare init writes the hole
# splits in half: the force spellings are caught by that regex's \bmain\b and
# every delete spelling is missed, because it hunts for --force|-f and a
# deletion carries neither. Section 1 measures every fact against a real git
# with --dry-run against a bare remote it made itself, INCLUDING the two that
# keep the fix from over-blocking: `tags/` is a different namespace with the
# same last word (`:tags/main` deletes nothing, `main:tags/main` creates
# refs/heads/tags/main), and `refs/heads/origin/main` is a branch of its own
# that git reports as [new branch] — it was being refused as `main` before this,
# so closing the hole also closed a false refusal that was already shipped.
	./native/partial_ref_test.sh
# head_ref_test.sh asks which BRANCH a word means. this one asks which REPO the
# question is even about. the fallback under all of it — "a push that names no
# refspec writes the current branch" — read HEAD in one place, the worktree
# above the shell's cwd, and `-C`, `--git-dir` and $GIT_DIR are precisely the
# words that make git operate on a different repo. so from a scratch branch,
# `git -C ../other push --force origin`, the --git-dir/--work-tree spelling and
# the GIT_DIR= environment spelling all exited 0 while rewriting main next door,
# through BOTH layers: the compiled law resolved the branch in the wrong repo,
# and a deny regex needs the literal word main, which none of those lines
# carries. the parser had the value all along — it stepped over those options to
# find `push` and threw what they said away. `cd ../other && git push --force
# origin` is the same bug one word over and closes with the same resolver.
# section 0 measures every fact against a real git with --dry-run --porcelain:
# the forced update next door, that -C chains, that -C has NO attached form (git
# rejects `-C<dir>`), that a -C is applied before --git-dir in either order,
# that an empty -C is a no-op and a missing one is fatal, and that a linked
# worktree keeps HEAD behind a `.git` FILE. the twins are the half that pays for
# the fix: reading the wrong repo also CUT work, so sitting on main, force-
# pushing her own branch in the repo next door was refused — that now runs, and
# so do a read, a lease, a plain push and a delete in the other repo, while a
# branch written down on the line is still refused from anywhere.
	./native/other_repo_test.sh
# the suites above ask which word is the command inside one program's syntax.
# this one asks it across a program BOUNDARY: `xcrun git push --force origin
# main` exited 0 while the same line without its first word exited 2. xcrun
# finds a tool in the active developer directory and execs it, so the command
# is the tool — but it was not in the wrapper table, so `xcrun` was read as the
# command name, and `xcrun` is neither git nor rm: irrelevant segment, three
# compiled laws never asked. It is not an exotic spelling, it is how a mac runs
# a toolchain, and `xcrun -f git` names a real git on this machine. Section 1
# measures the premise against the REAL xcrun while every tool it is handed is
# an absolute path to a FAKE that only records its argv — absolute because the
# same section measures why a fake on PATH would not have saved it: xcrun
# resolves a tool NAME itself and walks straight past the shell's PATH. The
# option walk is the other half: xcrun answers to `-sdk macosx` as readily as
# `--sdk macosx`, and reading the one-dash spelling as a short cluster would
# have skipped one word too few and named the SDK as the command. The twins are
# the longer list on purpose — simctl, xcodebuild, notarytool, clang and swift
# are all spelled through xcrun, and a fix that names the tool must not start
# refusing the tools.
	./native/xcrun_wrapper_test.sh
	./native/npm_install_test.sh
	./native/doctor_test.sh
	./native/repair_session_test.sh
	./native/repair_isolation_test.sh
	./native/harness_lock_test.sh
# harness_lock_test.sh closes the five families that move the machinery. This one
# closes the two that move nothing but the source, which is why no hash can see
# them: a branch keyed on the exact input the suite feeds, and a type whose ==
# cannot say no. The elimination is structural and decides nothing -- the verdict
# is a RE-RUN of the project's own check with the flagged hunks taken back out,
# and red means the green belonged to them. Four must-refuse cases, four twins,
# and two of the twins are the shapes this could plausibly over-fire on: an
# honest fix carrying a long string constant, and an honest fix to a comparison
# method the codebase already had.
	./native/heldout_test.sh
# and the question underneath both locks: does the lock cover the suite it says
# it covers. It did not, and the gap grew with the size of the suite. repair
# parses rabadon-truth's JSON out of the same buffer that keeps a failing run's
# last 4000 bytes, so past roughly 110 discovered test files the front of the
# JSON was cut away and the parse found nothing -- zero locks, quietly. Measured
# on the corpus's commander checkout: 122 files discovered in 4503 bytes, 0
# locked, while express fit in 2382 bytes and locked all 91. The third case here
# is the one that costs: on a 161-file suite a proposal that neutered the failing
# test was HELD instead of rejected.
	./native/lock_coverage_test.sh
# every check above hunts the MISS: a fake fix that buys a green. this one hunts
# the opposite, and the opposite is the expensive one. measured on a three-line
# fixture, nine correct fixes refused out of twelve -- the isolated copy carried
# __pycache__ for the source the proposal had just replaced, and CPython
# validates a .pyc on the source's mtime and SIZE at one second of resolution,
# `cp -R` preserves mtime, and `a - b` -> `a + b` is the same byte count, so
# every field the cache checks still agreed. the arbiter re-ran the bug and
# called an honest fix a fake one. second class, same family: the proposer
# inherited fd 0, so one that reads stdin hung until the wall clock and reached
# the ledger as a failed repair -- and the SAME proposal passed when the caller's
# stdin was closed, which made the verdict a function of how rabadon was invoked.
	./native/false_reject_test.sh
# and one question further back: the lock covers what discovery found, so what
# was discovery missing. Three silent bounds. The walk stopped at depth 4, and
# zod keeps its suite six directories down, so 170 test files were on disk and 2
# were discovered. The name patterns never matched a file called exactly
# `test.ts`, which is how date-fns names all 253 of its. The list stopped at 512
# and the walk at 20000 entries, neither with a word. Every widening here has a
# twin, and the twin that shaped the rule came from a real repo: jinja has one
# examples/basic/test.py and a src/jinja2/tests.py that is SOURCE, and locking
# either would refuse an honest fix. So a bare `test` stem counts only when the
# repo repeats it in three directories, which is a convention rather than a stray.
	./native/discovery_test.sh
# discovery_test.sh asks whether the walk REACHED the suite. this one asks
# whether it recognised the suite once it got there, which is a different
# failure: the language check ran eleven lines above the location rule, so
# anything off the js/ts/py/c/go/rs/swift/java list hit `continue` before the
# rule that says a file under tests/ belongs to the suite could run. measured
# 3 August on three real repos -- redis 229 .tcl, rails 1290 *_test.rb,
# discourse 3373 *_spec.rb, all with nothing holding them, while redis reported
# 255 locked files that were C headers out of deps/jemalloc. it also silenced
# the repo's OWN law: terraform's guard.json names testdata/ and 0 of the 1715
# .tf fixtures under it were locked. every widening here has a twin, because
# this is the fix that starts hash-locking source and refusing honest repairs
# if it goes wrong.
	./native/discovery_language_test.sh
	./native/sandbox_test.sh
	./native/export_test.sh
# export_test.sh asks whether the spans that ship are correct. this one asks
# whether the ones that did NOT ship were announced. measured 3 August against
# the live spool: 80,690 lines in, 77,084 spans out, exit 0, stderr empty, and
# nothing in the program could tell anyone where the gap went. under that
# silence sat a real discard -- "older than the window" and "I could not read
# this line" left through the same bare `continue`, because rbjson::get_num
# returns 0 for absent, mistyped and unparseable alike. three more cost a reader
# something: one invalid utf-8 byte made the whole 25 MB document invalid per
# RFC 8259 and a collector rejects every span rather than one; a refusal shipped
# with no rule on it, because export read a top-level "rule" while the gate
# writes fails[]; and a torn line shipped as an anonymous span into the trace id
# of the literal string "?". the export now closes its books on stderr and the
# arithmetic reconciles: lines read == spans + drills + held back.
	./native/export_drop_test.sh
	./native/gate_promise_test.sh
	./native/blind_switch_test.sh
	./native/lamp_test.sh
	./native/watch_test.sh
	./native/serve_test.sh
	./native/sigpipe_test.sh
	./native/session_test.sh
# session_test.sh asks whether one session is tracked correctly. this one asks
# what happens to it when six more arrive, which is the ordinary case for the
# thing that supervises a fan-out. every per-session guarantee lived in one
# shared map and the loader kept the last four:
#   if (sessions.size() > 4) sessions.erase(sessions.begin(), sessions.end() - 4);
# on 3 August seven sessions ran at once, one main and six agents, the main
# session's record was evicted, and `promise-off-target` -- whose own refusal
# text reads "fires once per session" -- fired three times. twelve concurrent
# writers left four records and eight silently gone, because every writer
# rewrote the whole file and the last one to finish won. the second half is one
# layer up: lastTestFail and lastTestPass were shared too, so a red one session
# watched at 02:18 was still being read at 04:00 by a session with its own suite
# green, twice, both on the ledger as `rabadon wrong stale-net-verdict`. six
# sections, and section 5 is the one that had to be measured rather than
# assumed -- a green rabadon RAN does cross sessions, and any session's edit
# ends it.
	./native/session_fanout_test.sh
	./native/budget_test.sh
	./native/postuse_test.sh
	./native/agents_test.sh
	./native/run_test.sh
# run_test.sh proves rabadon can supervise an agent that never heard of it.
# This one asks the question one step earlier: before rabadon judges anything,
# does it SAY what it is about to judge? Every arm changes the project and reads
# the block back, because the failure worth catching is not bad wording — it is
# a contract that describes a project other than this one.
	./native/contract_test.sh
# contract_test.sh proves rabadon SAYS what it will do. This one proves it does
# it: the check goes red and the next action does not start. The arms that carry
# the risk are the ones proving the fix path stays open and that an inconclusive
# check refuses nothing — a stop with no way out is how a guardrail gets
# uninstalled, and it would be this rule that did it.
	./native/redbase_test.sh
# redbase_test.sh proves the stop works. this one asks whose work it stops: a
# red is about a TREE, and `cd <neighbour> && git commit` was refused although
# the neighbour is its own worktree with its own verdict (measured, F1b
# CHALLENGE-2). Every arm here has a twin, because the cheap fix — letting a
# `cd` in front of a command switch red-base off — is a bypass an agent would
# learn in one session.
	./native/redbase_scope_test.sh
	./native/scope_test.sh
	./native/pushgate_test.sh
# pushgate_test.sh proves the gate runs the suite and reads the real result.
# this one asks who is allowed to say the suite was green. the gate skipped its
# own run whenever lastTestPass was fresh, and that stamp is written in two
# places it could not tell apart: a run rabadon forked and read the exit code
# of, and a Bash tool result it merely WATCHED go past, where no exit code
# reaches the post hook at all. so a command that ran no tests refreshed the
# stamp and the next push went out over a red suite. measured 3 August, both
# run rather than quoted: `go test -run TestNothingMatchesThis ./...` prints
# `ok vac 0.142s [no tests to run]` and exits 0, and pytest on an empty
# directory prints `no tests ran in 0.00s`. five of the nine cases here are
# twins, because the failure mode of this fix is refusing honest pushes forever
# -- go prints `[no test files]` for every package without tests, beside real
# green lines, on a perfectly healthy run.
	./native/pushgate_forge_test.sh
# and the same mistake pointing the other way. the post hook read "the pass
# pattern did not match" as "the suite failed", and those are different
# sentences. measured in this repo 3 August 14:24:28: `make test` exited 0 with
# 2942 ok lines and zero failing assertions, the run was `make test > log 2>&1`,
# the hook saw `EXIT=0`, and lastTestFail was stamped at that second. that
# verdict goes into .rabadon/handoff.md, where the next session is told the red
# IS the open front, so a false red costs a session hunting nothing. a red needs
# evidence of its own now. the twins are the constraint: a suite that really
# died does not always own the word fail (make prints *** Error 1, a crash
# prints Segmentation fault), and a zero count is not evidence -- rabadon caught
# THAT one in its own passing summary line, "test verdict: 8 ok, 0 fail".
	./native/testverdict_test.sh
	./native/drift_test.sh
	./native/verify_test.sh
	./native/loop_test.sh
	./native/route_test.sh
	./native/llm_proposer_test.sh
	./native/truth_test.sh
# truth_test.sh asks whether the ladder picked the STRONGEST truth. this one
# asks a question one step earlier and it is the one that was answered wrong:
# whose tests are these, and which tree is this verdict about. Three measured
# defects (D6): site-packages was not skipped so a dependency's suite was read
# as the project's, project_root() chose $HOME whenever $HOME held a .git, and
# net.cpp's empty-run exemption was gated on exit 0 so pytest's exit 5 never
# received it. All three produce FALSE REJECTS, which cost the same as a miss.
	./native/discovery_scope_test.sh
	./native/net_test.sh
	./native/stats_test.sh
	./native/trace_test.sh
	./native/lens_test.sh
# lens_test, budget_test and session_test are the three consumers of ONE meter
# (native/usage.h), and on 24 Aug 2026 all three were green while that meter
# read zero tokens from every real transcript on disk. It took the first "type"
# key on a line and required "assistant"; Claude Code writes message{} first, so
# that key is always "message". Every fixture in the repo wrote the opposite
# order, so the suite could not see it. This check is the one that reads real
# bytes: fixtures in BOTH orders, the traps a careless fix would fall into, and
# -- when a real transcript exists on the machine -- a stock json parser as the
# oracle, byte for byte. No transcript to read is a printed SKIP, never a
# quiet pass.
	./native/usage_order_test.sh
	./native/regression_demo.sh
# LAST ON PURPOSE, AND RED ON PURPOSE. Every suite above proves the gate does
# what it was told. This one asks the question none of them ask: was being told
# that the right call? It replays real refusals out of the watch-mode ledger and
# measures how many of them would have cut work that was never dangerous. It
# fails today at 55.0% against a 90% floor — it was 33.3% until deny rules
# stopped matching text a command CARRIES (heredoc bodies, quoted arguments,
# comments) and started matching only the text a shell will RUN, and 50.0%
# until the compiled delete law stopped reading the system temp area as
# somebody's data. Every remaining wrong refusal now comes from a deny regex a
# PROJECT wrote and anchored to its own absolute path. The floor
# lives in exactly one place
# (native/precision_test.sh) and moving it down is the one edit that makes the
# file worthless. `make precision` runs it alone.
	./native/precision_test.sh
# and the page. every source the site names has to exist, no headline number may
# be typed into the template, and a fact that appears on two pages has to have
# one value. written red: the overview said 207 refusals while the page built
# from the same ledger said 232, and it named native/gate_bench.sh as a source
# when no such file existed.
#
# THIS LINE WAS NOT IN THIS TARGET. `precision:` was declared between the
# comment and the command, so the recipe that guards the site belonged to
# `make precision` and `make test` never ran it — for the whole week the suite
# was being reported green. The test written to stop a typed-in number reaching
# the page was the one test nothing was gating.
	./native/site_claims_test.sh
# site_claims_test.sh asks whether a number on the page can be walked back to a
# run. this asks the other question about the same pages: whether something that
# should never have left this machine rode along with it. the redaction in
# site/field_stats.py matched whole strings — the home path, then the account
# name, then a refusal to write if the account name survived — and one thing
# defeated all three at once, a detail the gate had already clipped mid-path.
# `/Users/damu` matched none of them and was published twice.
	./native/field_redaction_test.sh
# field_redaction_test.sh asks whether the redactor in site/field_stats.py holds
# for the file site/field_stats.py writes. this asks the question one level up,
# which is the level the leak was on: whether it holds for everything the domain
# serves. It did not. site/rule_census.json is written by a SECOND generator
# that had no redactor at all, and it went out — 391KB, linked from /field as a
# dataset download — carrying 1058 occurrences of the absolute home path and the
# names of eleven private repositories, one class of which discloses a health
# context by the name alone. The page declared over BOTH files, in schema.org,
# that home paths are rewritten and sensitive records are dropped and counted;
# one of the two files made that true and the other made it false. So the
# redactor is a module now (site/redact.py) and this file checks the PROPERTY
# rather than the generator: every file under site/ that .vercelignore does not
# exclude is read, whatever wrote it. It also asserts the drop is COUNTED in
# both published files, because a filter that hides its own size turns "here is
# everything" into "here is what was chosen". The terms are not in this
# repository — it is public — so sections 1-4 write their own list and are as
# red on a runner as they are here.
	./native/publish_redaction_test.sh
# and whether the page gets republished at all. site_claims_test.sh asks whether
# a number can be walked back to a run; this asks whether the number the public
# reads is the number the ledger holds. Between 25 July and 3 August the only
# thing moving those figures onto the page was an operator typing four commands,
# and the page went on describing a ledger that had grown by 478 events. The job
# is unattended now, so every one of its refusals is asserted here rather than
# hoped for: it does not deploy a site that did not change, it does not stage a
# file it did not write, it does not run beside itself, and it does not trust a
# deploy that said ok — it fetches the live domain afterwards and compares the
# page's own numeric fingerprint. 46 cases and it deploys nothing: vercel, gh
# and git are stubs on PATH and every call is counted. Section 2b is the newest
# and it came from a real miss — the guard-rule census sits on the same page and
# was outside the change trigger, so it moved from 411 to 425 and could not
# publish itself.
	./native/publish_test.sh
# and the number that turned out to be counting the wrong thing. the ledger
# records `new gate: <id>` when the engine authors a rule after an incident, so
# counting those events answers "how many did it write" — not "how many exist".
# `release-workflow-needs-test-gate` is on the ledger and in no guard.json on
# this machine, and it was one line away from being published inside a total of
# twelve live rules while being a rule that cannot fire anywhere.
	./native/field_census_test.sh
# and the product move the field numbers were the argument for. every number in a
# session report is asked which run produced it, against the ledger the gate
# already writes. eight numbers in nine days had no run behind them and none of
# them was anybody lying: a benchmark subtracting x from x, a fixture the
# measured party had chosen, a hash lock that locked 0 of 122 files. written red
# with a fabricated report and its honest twin, identical prose, one difference.
	./native/claims_test.sh
# the false refusal that was found by being on the receiving end of it. `2>&1` is
# a descriptor duplication and the delete law read it as a truncating write to a
# file named 1, so `cd <other repo> && anything 2>&1` was refused -- four of five
# agent sessions, on their first or second command. section 2 holds the law it
# was mistaken for. the fixture is NOT under mktemp: /tmp, /var/tmp and
# /var/folders are exempt by design, and the first version of this file was
# measuring that carve-out rather than the rule.
	./native/fd_dup_test.sh
# sun_path is 104 bytes on macOS and 108 on Linux, and the emitter in gate.cpp
# strncpy'd into it with no length check. that does not fail: it builds a
# SHORTER path that is a prefix of the intended one and connects to that, so a
# deep RABADON_DIR shipped the ledger event stream to whoever could create a
# socket on the prefix -- silently, exit 0, nothing on stderr. the two sibling
# call sites (gated.cpp, gated_client.h) already guarded it; this one was
# missed, and the architecture note claimed a test covered it that did not
# exist (reports/R7/CHALLENGE-3.md). ~85 bytes of a 104 cap is what a plain
# mktemp -d HOME already spends.
	./native/sock_path_test.sh
# the spool's day string. reports/R7/PROFIL-YARGILAMA.md measured the line that
# builds it at 28.5% of the daemon's whole judging cost -- not the formatting,
# the FIRST gmtime_r in a process, which loads the timezone data: 269-483us
# cold, 1.0us warm, measured. rabadon-gated forks a worker per request, so it
# was paid per request for a string that is constant all day. Caching it is the
# obvious move and the dangerous one: a daemon that lives past midnight would
# keep appending to yesterday's spool, silently. this test holds both halves --
# agrees with gmtime_r on both sides of midnight, a leap day and a year
# boundary, AND a forked child inherits the warm cache.
	./native/day_cache_test.sh
# the two events the ledger was not keeping. a session ran `rabadon off` at
# 02:25 on 3 August and the machine was unguarded from then on while four other
# sessions kept working under it, and nothing recorded that. and three refusals
# that night were wrong, and all three ended up as prose in a report because
# there was no record type for them -- which put the one number this product is
# judged on outside the ledger.
	./native/mode_wrong_test.sh
# DEVIR item 2, open since 2 August: the guard was loaded from the exact session
# directory with no walk toward the project root, so a session one directory down
# got none of its project's rules and only the compiled floor was left. Measured
# in a real repository from its engine/ subdirectory: four rules held at the root
# and zero held there, three of them authored by the engine after real incidents.
	./native/guard_subdir_test.sh
# the four ways a rule can lint clean and never fire, as a runnable test rather
# than a paragraph. an agent ran all 430 guard rules on this machine through the
# real gate and 16 could not fire; three of those were authored by the engine
# itself after real incidents, so each named something that had already happened
# once and was free to happen again.
	./native/rule_census_test.sh
# and the field the two files above publish a project under. The gate writes
# `project = basename(cwd)`, so the published column carried whatever a session's
# working directory happened to be called: the home directory, a system scratch
# path, rabadon's own probe trees, the directory that CONTAINS the projects, and
# the residue left after a withheld name was scrubbed out of a longer one. 72
# "project" names, a third of them naming no project at all.
#
# Collapsing those is a correctness fix and it is ALSO, from one step away,
# exactly the move this product refuses: widen the filter one prefix at a time
# and the disclosure gate below goes green without one disclosure decision being
# made. So this suite tests the rules from both sides — every collapse rule has a
# case proving it fires, and cases proving it does NOT fire on an ordinary name,
# that an unknown label survives as a name, and that the committed list cannot
# grow into a blanket. It sits ABOVE the gate deliberately: it must be able to
# fail the build on its own, not only when somebody runs it by hand.
	./native/identity_test.sh
# The disclosure gate USED TO RUN HERE, last in this target. It is `make
# disclosure` now, and moving it is the only change: same suite, same verdict,
# same fail-closed allowlist, run on both platforms in CI as its own job.
#
# It had to move because of the sentence written above `promises` in this file:
# A SUITE DESIGNED TO FAIL CANNOT ALSO BE THE GATE. It is red on purpose and
# stays red until a human makes 41 disclosure decisions, and `make test` is what
# rabadon's own guard runs on this repository — so rabadon refused every action
# in its own tree for as long as the triage was outstanding, including the
# actions that were doing the triage. The red-base law is right; pointing it at
# a deliberate red is what was wrong.
#
# What did NOT happen, because it was the obvious way and it is the move this
# product exists to refuse: the gate was not made lenient, not made advisory,
# not allowlisted-by-default, and no name was added to the allowlist to shrink
# the number. It fails the build in its own job, on both platforms, on every
# push. Only the wiring changed.

# THE SCOREBOARD. Not part of `make test`, and the reason is not squeamishness:
# it asserts promises that are not built yet, so it is RED on purpose, and a red
# `make test` in this repository means rabadon's own red-base law refuses every
# action in its own tree. A suite designed to fail cannot also be the gate.
#
# It is separate for a second reason that matters more. Every other target here
# tests a mechanism; this one asks the owner's question — run the product end to
# end, would a stranger agree the promise is kept — and its criteria are
# transcribed from the owner's words rather than the implementer's. It exists
# because on 16 August two promises were reported finished, with green suites
# behind them, and an audit twenty minutes later found three real holes that no
# mechanism test could have caught.
promises: all
	./native/promises_test.sh

# THE DISCLOSURE GATE. Separate from `make test` for the reason written above
# `promises`, and it is the same reason: a suite that is red on purpose cannot
# also be the base that decides whether the next action may run.
#
# It asks one question about the site artifacts — was every project name in them
# DECIDED, against the public committed allowlist in site/published-projects.txt
# — and it is red until the answer is yes for all of them. It fails closed: a
# missing allowlist allows NOTHING, so a runner with no file refuses everything
# rather than passing on blindness. That is the whole point of it existing
# beside the private withhold list, which CI cannot have.
#
# It runs on both platforms in CI as its own job (.github/workflows/ci.yml), so
# the red is as visible to a stranger as it ever was. What it no longer does is
# tell rabadon's red-base law that this repository's base is broken.
#
# It needs no build: python3 and site/ are all it reads.
disclosure:
	./native/published_allowlist_test.sh

# the same suite without the rest of the build, for working on the number
precision: native/rabadon-gate
	./native/precision_test.sh

clean:
	rm -f native/rabadon-net native/rabadon-truth native/rabadon-serve native/rabadon-gate native/rabadon-gated native/rabadon-drift native/rabadon-verify native/rabadon-pipeline native/rabadon-do native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit native/rabadon-claims native/rabadon-repair native/rabadon-sandbox native/rabadon-run native/rabadon-export native/gate_bench

.PHONY: all bench clean disclosure precision promises

native/rabadon-verify: native/verify.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-pipeline: native/pipeline.cpp native/sha256.h native/chain.h native/jsonl.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-do: native/do.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<
