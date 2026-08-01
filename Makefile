# rabadon native core. one binary, zero deps.
CXX ?= clang++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra

all: native/rabadon-net native/rabadon-truth native/rabadon-serve native/rabadon-gate native/rabadon-drift native/rabadon-verify native/rabadon-loop native/rabadon-do native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit native/rabadon-repair native/rabadon-sandbox native/rabadon-export native/gate_bench

# the OTHER benchmark, and the one the site was quoting without owning: how long
# rbrules::judge_command takes, in process, over the 34 real cases in the
# precision fixture. native/bench.py answers the end-to-end question (the whole
# hook, fork to exit, against the node gate it replaced); this answers the one
# the words "to judge one command" actually name. It is in `all` because the
# site names it as a source, and a source that is not built is a source nobody
# can run.
native/gate_bench: native/gate_bench.cpp native/rules.h native/baseline.h native/cmdtext.h native/pathres.h
	$(CXX) $(CXXFLAGS) -o $@ $<


# native/version.h is a prerequisite of every rule whose source includes it,
# and make does not read #include lines. it was listed nowhere, so a version
# bump answered `make` with "up to date" and shipped a binary announcing the
# previous release. native/version_test.sh holds this rule from both ends:
# textually, and by asking `make -q` after touching version.h.
native/rabadon-gate: native/gate.cpp native/usage.h native/sha256.h native/chain.h native/jsonl.h native/baseline.h native/rules.h native/cmdtext.h native/pathres.h native/cli_help.h native/version.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-audit: native/audit.cpp native/sha256.h native/jsonl.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-repair: native/repair.cpp native/sha256.h native/chain.h native/jsonl.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

# exec is the OTHER caller of the shared rule engine (rules.h -> baseline.h) and
# the ledger writer (chain.h -> sha256.h). None of those were listed, so an edit
# to the rule engine answered `make` with "up to date" and left exec enforcing
# the previous version of the law while the gate enforced the new one — the
# divergence rules.h exists to prevent, reintroduced by the build.
native/rabadon-sandbox: native/sandbox.cpp native/rules.h native/baseline.h native/cmdtext.h native/pathres.h native/chain.h native/jsonl.h native/sha256.h native/cli_help.h
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

native/rabadon-truth: native/truth.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-net: native/net.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-lens: native/lens.cpp native/usage.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-budget: native/budget.cpp native/cli_help.h native/version.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-stats: native/stats.cpp native/cli_help.h native/drill.h
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
	./native/cli_test.sh
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
	./native/baseline_test.sh
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
	./native/cmdtext_test.sh
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
	./native/sandbox_test.sh
	./native/export_test.sh
	./native/gate_promise_test.sh
	./native/lamp_test.sh
	./native/watch_test.sh
	./native/serve_test.sh
	./native/sigpipe_test.sh
	./native/session_test.sh
	./native/budget_test.sh
	./native/postuse_test.sh
	./native/pushgate_test.sh
	./native/drift_test.sh
	./native/verify_test.sh
	./native/loop_test.sh
	./native/route_test.sh
	./native/llm_proposer_test.sh
	./native/truth_test.sh
	./native/net_test.sh
	./native/stats_test.sh
	./native/trace_test.sh
	./native/lens_test.sh
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

# the same suite without the rest of the build, for working on the number
precision: native/rabadon-gate
	./native/precision_test.sh

clean:
	rm -f native/rabadon-net native/rabadon-truth native/rabadon-serve native/rabadon-gate native/rabadon-drift native/rabadon-verify native/rabadon-loop native/rabadon-do native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit native/rabadon-repair native/rabadon-sandbox native/rabadon-export native/gate_bench

.PHONY: all bench clean precision

native/rabadon-verify: native/verify.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-loop: native/loop.cpp native/sha256.h native/chain.h native/jsonl.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-do: native/do.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<
