# rabadon native core. one binary, zero deps.
CXX ?= clang++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra

all: native/rabadon-net native/rabadon-truth native/rabadon-serve native/rabadon-gate native/rabadon-drift native/rabadon-verify native/rabadon-loop native/rabadon-do native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit native/rabadon-repair native/rabadon-sandbox native/rabadon-export

# native/version.h is a prerequisite of every rule whose source includes it,
# and make does not read #include lines. it was listed nowhere, so a version
# bump answered `make` with "up to date" and shipped a binary announcing the
# previous release. native/version_test.sh holds this rule from both ends:
# textually, and by asking `make -q` after touching version.h.
native/rabadon-gate: native/gate.cpp native/usage.h native/sha256.h native/chain.h native/jsonl.h native/baseline.h native/rules.h native/cli_help.h native/version.h
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
native/rabadon-sandbox: native/sandbox.cpp native/rules.h native/baseline.h native/chain.h native/jsonl.h native/sha256.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-export: native/export.cpp native/cli_help.h native/drill.h native/jsonl.h
	$(CXX) $(CXXFLAGS) -o $@ $<

# trace is the THIRD reader of the spool, next to stats and export, and it is
# the one that gets screenshotted. drill.h was listed on the other two only, so
# the build could not have told anyone that trace applies none of the exclusion
# rules: a tightened rule in drill.h answered `make` with "up to date" and left
# the prettiest surface counting rabadon's own self-tests as catches.
native/rabadon-trace: native/trace.cpp native/cli_help.h native/jsonl.h native/drill.h
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
	./native/guard_lint_test.sh
	./native/bypass_test.sh
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
	./native/lens_test.sh
	./native/regression_demo.sh

clean:
	rm -f native/rabadon-net native/rabadon-truth native/rabadon-serve native/rabadon-gate native/rabadon-drift native/rabadon-verify native/rabadon-loop native/rabadon-do native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit native/rabadon-repair native/rabadon-sandbox native/rabadon-export

.PHONY: all bench clean

native/rabadon-verify: native/verify.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-loop: native/loop.cpp native/sha256.h native/chain.h native/jsonl.h native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-do: native/do.cpp native/cli_help.h
	$(CXX) $(CXXFLAGS) -o $@ $<
