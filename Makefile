# rabadon native core. one binary, zero deps.
CXX ?= clang++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra

all: native/rabadon-net native/rabadon-truth native/rabadon-serve native/rabadon-gate native/rabadon-drift native/rabadon-verify native/rabadon-loop native/rabadon-do native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit native/rabadon-repair native/rabadon-sandbox native/rabadon-export

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
bench: native/rabadon-gate
	python3 native/bench.py

# native proofs: the direction check fires in both directions and fails open.
# `test: all` and not a hand-kept list: the list named 11 binaries while the
# suites run 16, so a clean checkout ran `make test` straight into a missing
# binary. the dependency is 'everything this repo builds'.
test: all
	./native/version_test.sh
	./native/cli_test.sh
	./native/audit_test.sh
	./native/baseline_test.sh
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
	./native/npm_install_test.sh
	./native/doctor_test.sh
	./native/repair_session_test.sh
	./native/repair_isolation_test.sh
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
	rm -f native/rabadon-net native/rabadon-truth native/rabadon-serve native/rabadon-gate native/rabadon-drift native/rabadon-verify native/rabadon-loop native/rabadon-do native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit native/rabadon-repair native/rabadon-sandbox native/rabadon-export

.PHONY: all bench clean precision

native/rabadon-verify: native/verify.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-loop: native/loop.cpp native/sha256.h native/chain.h native/jsonl.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-do: native/do.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<
