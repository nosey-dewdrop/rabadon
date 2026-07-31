# rabadon native core. one binary, zero deps.
CXX ?= clang++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra

all: native/rabadon-net native/rabadon-truth native/rabadon-serve native/rabadon-gate native/rabadon-drift native/rabadon-verify native/rabadon-loop native/rabadon-do native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit

native/rabadon-gate: native/gate.cpp native/usage.h native/sha256.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-audit: native/audit.cpp native/sha256.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-trace: native/trace.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-serve: native/serve.cpp
	$(CXX) $(CXXFLAGS) -pthread -o $@ $<

native/rabadon-truth: native/truth.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-net: native/net.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-lens: native/lens.cpp native/usage.h
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-budget: native/budget.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-stats: native/stats.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-drift: native/drift.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

# measured, not claimed: median hook latency, native vs the legacy node gate,
# same events, same verdicts. prints the table the readme numbers come from.
bench: native/rabadon-gate
	python3 native/bench.py

# native proofs: the direction check fires in both directions and fails open.
test: native/rabadon-gate native/rabadon-drift native/rabadon-verify native/rabadon-loop native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit
	./native/audit_test.sh
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
	./native/truth_test.sh
	./native/net_test.sh
	./native/stats_test.sh
	./native/lens_test.sh
	./native/regression_demo.sh

clean:
	rm -f native/rabadon-net native/rabadon-truth native/rabadon-serve native/rabadon-gate native/rabadon-drift native/rabadon-verify native/rabadon-loop native/rabadon-do native/rabadon-stats native/rabadon-budget native/rabadon-lens native/rabadon-trace native/rabadon-audit

.PHONY: all bench clean

native/rabadon-verify: native/verify.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-loop: native/loop.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

native/rabadon-do: native/do.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<
