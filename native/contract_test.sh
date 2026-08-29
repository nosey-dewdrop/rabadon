#!/usr/bin/env bash
# contract_test.sh — rabadon says what it will do BEFORE it does anything.
#
# The complaint that produced this file: "it catches nothing, it repairs
# nothing, on what grounds it would repair is unknown, when it would fire is
# unknown." Four complaints, one cause — the supervisor never stated its terms,
# so the only way to learn them was to trip one.
#
# What this suite holds is not the wording. It is the property that makes the
# wording worth reading: the contract DESCRIBES THIS PROJECT, and it describes
# it truthfully in the cases where the truth is unflattering. A block that says
# "check: npm test" in a directory with no npm is worse than no block at all,
# because it is a promise of cover that is not there.
#
# So every arm below changes the world and reads the block back:
#   - a project with a suite            -> names the real command
#   - a project with nothing runnable   -> says so, and says what would fix it
#   - watch mode                        -> says it will run NOTHING
#   - Cursor                            -> names the pre-edit hole Cursor has
#   - Claude Code                       -> does NOT name it (it is not blind there)
#   - repair off / on                   -> says which, and never lies about spend
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/rabadon-gate"
[ -x "$GATE" ] || { echo "build first: make native/rabadon-gate"; exit 1; }
[ -x "$HERE/rabadon-truth" ] || { echo "build first: make native/rabadon-truth"; exit 1; }
export RABADON_JUDGE=0
# HOME ISOLATION — MEASURED, NOT ASSUMED (2026-08-30).
# This suite drives SessionStart with a FRESH RABADON_DIR every arm, which means
# the self-heal stamp is always absent, which means gate.cpp spawns
# hooks/refresh.mjs, whose refresh() targets `os.homedir()` — the REAL one. On
# this machine `~/.claude/settings.json` is shared with tools that are not
# rabadon's, and running `make test` from a worktree repointed six rabadon hook
# entries plus one drift entry at the worktree binary; when the worktree is
# removed the user's brake points at a binary that no longer exists and dies
# silently. Reproduced by hashing the live file around every suite in
# native/*_test.sh: exactly two suites moved it, this one and promises_test.sh.
# The reference environment is a clean container (CLAUDE.md "Quality bar"); a
# suite that reaches the dev box's $HOME is a bug in the suite, so the suite
# declares its own $HOME instead of borrowing the operator's. Held from the
# other side by native/home_isolation_test.sh, which fails if this line is
# removed. Nothing about the product's behaviour is switched off here —
# RABADON_SELFHEAL is untouched — only the address it writes to is declared.
SBHOME="$(mktemp -d)"; export HOME="$SBHOME"
trap 'rm -rf "$SBHOME"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
has() { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

echo "contract: the terms are stated before the first judgement"

# every arm gets its own RABADON_DIR, because the machine running this suite has
# its own switch and an inherited `enabled` would make the watch arm untestable.
say() { # say <projectdir> <homedir> <json>
  printf '%s' "$3" | RABADON_DIR="$2" "$GATE" 2>&1
}

# ---------- 1. a project that CAN be checked ----------
P="$(mktemp -d)"; RD="$(mktemp -d)"; : > "$RD/enabled"
printf '{"name":"p","scripts":{"test":"node -e \\"process.exit(0)\\""}}' > "$P/package.json"
mkdir -p "$P/.rabadon"
OUT="$(say "$P" "$RD" "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$P\",\"session_id\":\"c1\"}")"

has "npm test" "$OUT" \
  && ok "names the command it will actually run, not a category" \
  || bad "the real check command is missing from the block: $OUT"
has "your own test suite" "$OUT" \
  && ok "says how strong that evidence is (a suite, not a syntax check)" \
  || bad "no strength-of-evidence line"
has "package.json scripts.test" "$OUT" \
  && ok "says WHERE it found the command — the claim is auditable" \
  || bad "no provenance for the discovered command"
has "changed a file" "$OUT" \
  && ok "says when it fires" || bad "no when-line"
# and it says WHY the trigger is trustworthy. The first version of the when-line
# read "after every edit to code", which was true only of edits made with an
# edit tool — a shell `sed -i`, or any agent driven through `rabadon run`, went
# unchecked while the contract said otherwise. The sentence and the mechanism
# were fixed together.
has "not the tool name" "$OUT" \
  && ok "and says the trigger is the filesystem, not the tool name — so it holds for any agent" \
  || bad "the when-line does not say what actually triggers the check"
has "you never wait for it" "$OUT" \
  && ok "says the check is off the agent's critical path" \
  || bad "does not say the agent is not stalled"
has "if it goes red" "$OUT" \
  && ok "says what happens on red BEFORE any red happens" \
  || bad "no consequence stated"

# the ledger carries the same terms, so a session's contract is auditable later
LEDG="$(cat "$RD"/spool/*.jsonl 2>/dev/null)"
has '"ev":"CONTRACT"' "$LEDG" \
  && ok "the contract is on the ledger, not only on the screen" \
  || bad "no CONTRACT event on the spool"
has 'npm test' "$LEDG" \
  && ok "the ledger records WHICH check was promised" \
  || bad "the CONTRACT event does not carry the command"

# ---------- 2. repair is off, and the reason is money ----------
has "repair" "$OUT" && ok "repair has a line of its own" || bad "repair not mentioned"
has "YOUR account" "$OUT" \
  && ok "says whose money a repair spends — the reason it is off by default" \
  || bad "does not say repair spends the user's own money"
has "RABADON_JUDGE=1" "$OUT" \
  && ok "gives the exact way to turn repair on" || bad "no way to turn repair on"

RD2="$(mktemp -d)"; : > "$RD2/enabled"
OUT_ON="$(printf '%s' "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$P\",\"session_id\":\"c1b\"}" \
  | RABADON_DIR="$RD2" RABADON_JUDGE=1 "$GATE" 2>&1)"
has "repair     : on" "$OUT_ON" \
  && ok "with the judge on, the block says repair is ON" \
  || bad "judge on but the contract still reads OFF: $OUT_ON"
has "isolated copy" "$OUT_ON" \
  && ok "and says the repair lands in an isolated copy, not the user's tree" \
  || bad "does not say the tree is untouched"

# ---------- 3. a project with NOTHING runnable ----------
# The arm that matters most. Silence here is the failure mode: a tool that finds
# nothing and says nothing looks exactly like a tool that is working.
Q="$(mktemp -d)"; RD3="$(mktemp -d)"; : > "$RD3/enabled"
echo hello > "$Q/readme.txt"
OUTQ="$(say "$Q" "$RD3" "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$Q\",\"session_id\":\"c2\"}")"
has "NONE FOUND" "$OUTQ" \
  && ok "a project it cannot check is TOLD it cannot be checked" \
  || bad "silent on an uncheckable project: $OUTQ"
has '"check"' "$OUTQ" \
  && ok "and it hands over the exact thing that fixes that" \
  || bad "says it is blind but not how to fix it"
has "npm test" "$OUTQ" \
  && bad "invented a check in a project that has none" \
  || ok "invents nothing: no command is named where none exists"

# THE ARM THAT KEEPS THE CONTRACT HONEST. The block above tells the user to do
# a specific thing. If that thing does not work, the contract is worse than
# silence — it spends the user's trust on a dead end. So: do exactly what the
# block said, verbatim, and check that rabadon now checks the project.
printf '{"project":"q","check":"sh -c \\"exit 0\\"","bash":[]}' > "$Q/.rabadon/guard.json" 2>/dev/null \
  || { mkdir -p "$Q/.rabadon"; printf '{"project":"q","check":"sh -c \\"exit 0\\"","bash":[]}' > "$Q/.rabadon/guard.json"; }
RD7="$(mktemp -d)"; : > "$RD7/enabled"
OUTQ2="$(say "$Q" "$RD7" "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$Q\",\"session_id\":\"c2b\"}")"
has 'sh -c "exit 0"' "$OUTQ2" \
  && ok "doing what the block said makes rabadon name that command back" \
  || bad "the declared check never reached the contract: $OUTQ2"
has "YOU declared" "$OUTQ2" \
  && ok "and it says the command was declared, not guessed — the two are different claims" \
  || bad "a declared command is presented as a discovery"
has "NONE FOUND" "$OUTQ2" \
  && bad "still claims it is blind after being told what to run" \
  || ok "no longer claims to be blind"
# and the net RUNS it — the contract's promise reaches the thing that executes
"$HERE/rabadon-net" "$Q" --cap-ms 20000 >/dev/null 2>&1
NETJ="$(cat "$Q/.rabadon/net.json" 2>/dev/null)"
has '"verdict":"green"' "$NETJ" \
  && ok "the net actually RAN the declared command and read its exit code" \
  || bad "declared check never ran: $NETJ"

# ---------- 4. watch mode runs nothing, and says NEVER ----------
W="$(mktemp -d)"; RD4="$(mktemp -d)"   # no `enabled` flag -> watch
printf '{"name":"w","scripts":{"test":"node -e \\"process.exit(0)\\""}}' > "$W/package.json"
OUTW="$(say "$W" "$RD4" "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$W\",\"session_id\":\"c3\"}")"
has "watch mode" "$OUTW" \
  && ok "watch mode is disclosed, not assumed" || bad "watch mode not disclosed: $OUTW"
has "NEVER" "$OUTW" \
  && ok "and the when-line says NEVER — watch spends nothing on your machine" \
  || bad "watch mode still claims it will run the check"
has "if it goes red" "$OUTW" \
  && bad "promises a stop it cannot perform in watch mode" \
  || ok "promises no stop it cannot perform"

# ---------- 5. the blind spots are named, per agent ----------
has "absolute path" "$OUT" \
  && ok "names the shim hole (an absolute-path call walks past it)" \
  || bad "the absolute-path hole is not disclosed"
has "Cursor has no pre-edit hook" "$OUT" \
  && bad "claims a Cursor hole while running under Claude Code" \
  || ok "does not invent a hole the current agent does not have"

C="$(mktemp -d)"; RD5="$(mktemp -d)"; : > "$RD5/enabled"
printf '{"name":"c","scripts":{"test":"node -e \\"process.exit(0)\\""}}' > "$C/package.json"
OUTC="$(say "$C" "$RD5" "{\"hook_event_name\":\"sessionStart\",\"workspace_roots\":[\"$C\"],\"conversation_id\":\"c4\"}")"
has "Cursor has no pre-edit hook" "$OUTC" \
  && ok "on Cursor it names the hole Cursor actually has" \
  || bad "Cursor's post-hoc file editing is not disclosed: $OUTC"
has "npm test" "$OUTC" \
  && ok "and the rest of the contract still resolves on the Cursor dialect" \
  || bad "the Cursor session got no check line"

# ---------- 5b. an agent with no post-action event is told what it does NOT get ----------
# `rabadon run` supervises agents that were never adapted, by owning their PATH.
# That is enough to refuse a program before it runs and nothing more: no event
# arrives after an action, so the project's check never starts and no red can
# stop anything. Printing the standard block here unchanged would promise a stop
# that cannot happen — the most expensive kind of wrong, because the user stops
# checking for themselves.
RUNP="$(mktemp -d)"; RDR="$(mktemp -d)"; : > "$RDR/enabled"
printf '{"name":"r","scripts":{"test":"node -e \\"process.exit(0)\\""}}' > "$RUNP/package.json"
printf '#!/bin/sh\necho agent-ran\n' > "$RUNP/ag.sh"; chmod +x "$RUNP/ag.sh"
RUNOUT="$(cd "$RUNP" && RABADON_DIR="$RDR" "$HERE/rabadon-run" --dir "$RUNP" -- sh ag.sh 2>&1)"
has "agent-ran" "$RUNOUT" \
  && ok "an unadapted agent still runs under rabadon run" || bad "the agent did not run: $RUNOUT"
has "rabadon: here is what I will do" "$RUNOUT" \
  && ok "and it gets the SAME contract, not a different one written twice" \
  || bad "no contract for a hook-less agent: $RUNOUT"
has "I will NOT stop you on a red one" "$RUNOUT" \
  && ok "which states plainly that on this path there is no stop on red" \
  || bad "the contract promises a stop this path cannot perform: $RUNOUT"
has "your next action does not start" "$RUNOUT" \
  && bad "it promised a refusal that cannot happen without a post-action event" \
  || ok "and the promise it cannot keep is absent, not merely contradicted later"
rm -rf "$RUNP" "$RDR"

# ---------- 6. scope ----------
has "every path in this project is fair game" "$OUT" \
  && ok "with no promise on file it says the scope is unlimited, rather than implying one" \
  || bad "no scope line for a project without a promise"
mkdir -p "$P/.rabadon"
printf '{"north_star":"n","areas":["^src/","^lib/"]}' > "$P/.rabadon/promise.json"
RD6="$(mktemp -d)"; : > "$RD6/enabled"
OUTS="$(say "$P" "$RD6" "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$P\",\"session_id\":\"c5\"}")"
has "^src/" "$OUTS" \
  && ok "with a promise on file, the contract quotes the promised areas" \
  || bad "scope line ignores .rabadon/promise.json: $OUTS"

# ---------- 7. the block does not stall the session ----------
# A contract printed by a supervisor that takes a second to think is a second
# added to every session start. Discovery is a 100ms deterministic pass; hold it.
T0=$(date +%s)
say "$P" "$RD6" "{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$P\",\"session_id\":\"c6\"}" >/dev/null
T1=$(date +%s)
[ $((T1 - T0)) -le 2 ] \
  && ok "the whole SessionStart, discovery included, finishes inside 2s" \
  || bad "session start took $((T1 - T0))s — the contract is now a tax"

rm -rf "$P" "$Q" "$W" "$C" "$RD" "$RD2" "$RD3" "$RD4" "$RD5" "$RD6"
echo ""
echo "contract: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
