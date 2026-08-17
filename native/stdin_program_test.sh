#!/bin/bash
# stdin_program_test.sh — text that becomes a program.
#
# Both of rabadon's layers classify a command line correctly and both answers
# are right at the moment they are given. `echo 'git push --force origin main'`
# is an echo: the force-push is one quoted argument, DATA, and refusing it was
# one of the ledger's real false refusals. `bash` with no operand is a bash: it
# carries no dangerous word at all. Put a pipe between them and the thing
# classified as data is the thing that runs.
#
#   echo 'git push --force origin main' | bash
#   echo 'rm -rf ~/Documents' | bash
#   printf '%s' 'git push --force origin main' > s.sh && bash s.sh
#
# The third is the worst of the three, because after the redirect the dangerous
# text is on no command line at all: there is no string left for any rule to
# match, only a file name.
#
# The answer is not a new rule per spelling. A shell with no script operand and
# no -c string reads its PROGRAM from stdin, so on a pipe whose right side is
# such a shell, what the left side PRODUCES is a program and is parsed as one.
# `printf`, `echo`, `cat`, a heredoc and a here-string are the forms whose
# output is written down in the command itself; a binary's output is not, and
# that limit is asserted below rather than hidden.
#
# THE NEGATIVES ARE THE POINT. The cheap way to pass this file is to refuse
# every pipe into a shell, which kills `echo 'hello' | bash` — the shape a
# hundred install scripts and every `command | sh` tutorial is written in. Each
# block below has a twin that must still run, and the twin differs only in what
# the produced text SAYS.
#
# NOTHING HERE IS EXECUTED, AND THE SETUP ASSUMES THE OPPOSITE.
#   * PATH is prefixed with a shim dir holding fake git, rm, bash, sh, zsh,
#     dash, cat, printf and curl. They run nothing, append their argv to a log
#     and exit 111. The log is asserted EMPTY at the end.
#   * the repo under judgement is mktemp'd and has NO REMOTE, so even a real
#     force-push has nowhere to land.
#   * HOME points inside the same mktemp root, so `rm -rf ~/Documents` names a
#     directory this script made; a canary file in it is read back at the end.
#   * the redirect targets (s.sh, note.txt) are asserted NOT to exist when the
#     run is over, which is what "the gate judged the write, it did not do it"
#     means.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
# `c++`, not `clang++`. make does NOT export its builtin CXX, so under
# `make test` this variable is unset and the fallback is what actually runs —
# and on a Linux box with only g++ installed, `clang++` is a command that does
# not exist. `c++` is the standard alias and resolves to whichever compiler the
# machine has (PROJECT.md S0.2 / V1.2).
CXX="${CXX:-c++}"
[ -x "$GATE" ] || { echo "stdin_program_test: build first (make)"; exit 1; }

FAIL=0
PASSN=0
pass() { PASSN=$((PASSN+1)); echo "  ok   $1"; }
bad()  { FAIL=1; echo "  FAIL $1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rbstdin.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# ---- the blast shield ------------------------------------------------------
SHIM="$ROOT/shim"; mkdir -p "$SHIM"
RANLOG="$ROOT/ran.log"
: > "$RANLOG"
for TOOL in git rm bash sh zsh dash cat printf curl; do
  cat > "$SHIM/$TOOL" <<SH
#!/bin/sh
printf '%s %s\n' "$TOOL" "\$*" >> "$RANLOG"
exit 111
SH
  chmod +x "$SHIM/$TOOL"
done
# the shim goes on PATH at the bottom of the setup, not here: this script writes
# its own fixture files with `cat > file <<EOF`, and a shimmed cat would eat
# them. The real paths are kept so the canary checks are not answered by a shim.
REALGIT="$(command -v git)"
REALCAT="$(command -v cat)"
REPO="$ROOT/proj"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m first
git -C "$REPO" branch -M main
REPO_HEAD="$(git -C "$REPO" rev-parse HEAD)"
# no `git remote add` anywhere in this file, on purpose.

export HOME="$ROOT/home"
mkdir -p "$HOME/Documents"
echo "do not lose me" > "$HOME/Documents/canary.txt"
export RABADON_DIR="$ROOT/rhome"; mkdir -p "$RABADON_DIR/spool"
printf 'on\n' > "$RABADON_DIR/enabled"
export RABADON_NOTIFY=0

# ---------------------------------------------------------------------------
# unit: the parser is asked what the line RUNS
# ---------------------------------------------------------------------------
# One line per command. If the produced text is a program, it appears here as
# its own command with its own argv — the same way `bash -c '<str>'` already
# does. A gap between this and what bash would run IS the bypass.
cat > "$ROOT/probe.cpp" <<'CPP'
#include <cstdio>
#include <iostream>
#include <string>
#include "cmdtext.h"
int main() {
  std::string cmd((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
  while (!cmd.empty() && cmd[cmd.size()-1] == '\n') cmd.erase(cmd.size()-1);
  rbtext::Parsed p = rbtext::parse(cmd);
  if (p.degraded) { printf("DEGRADED %s\n", p.why.c_str()); return 0; }
  for (size_t i = 0; i < p.segs.size(); i++) {
    const rbtext::Seg& s = p.segs[i];
    const size_t ci = rbtext::command_index(s.words);
    std::string name = ci < s.words.size() ? rbtext::base_of(s.words[ci].text) : "";
    printf("cmd=%s words=", name.c_str());
    for (size_t k = ci; k < s.words.size(); k++)
      printf("%s%s", k == ci ? "" : "|", s.words[k].text.c_str());
    printf("\n");
  }
  return 0;
}
CPP
UNIT_OK=1
"$CXX" -std=c++17 -O1 -Wall -Wextra -I "$HERE" -o "$ROOT/probe" "$ROOT/probe.cpp" 2>"$ROOT/cc.log" || UNIT_OK=0

u_argv() { # u_argv NAME CMD EXPECTED
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then
    pass "$name"
  else
    bad "$name: no command decomposed to <$want>"
    printf '%s\n' "$out" | sed 's/^/         got: /'
  fi
}
u_notargv() { # u_notargv NAME CMD FORBIDDEN
  local name="$1" cmd="$2" want="$3" out
  if [ "$UNIT_OK" = "0" ]; then bad "$name: probe did not compile"; return; fi
  out="$(printf '%s' "$cmd" | "$ROOT/probe")"
  if printf '%s\n' "$out" | grep -qF -- "$want"; then
    bad "$name: a command decomposed to <$want>, but nothing runs it"
    printf '%s\n' "$out" | sed 's/^/         got: /'
  else
    pass "$name"
  fi
}

PUSH='words=git|push|--force|origin|main'
RMDOC='words=rm|-rf|~/Documents'

echo "== unit: the produced text is read as the program it becomes =="
if [ "$UNIT_OK" = "0" ]; then
  echo "  (probe did not compile)"; sed -n '1,12p' "$ROOT/cc.log" | sed 's/^/         /'
fi
u_argv "echo into bash"          "echo 'git push --force origin main' | bash"        "$PUSH"
u_argv "echo into sh"            "echo 'git push --force origin main' | sh"          "$PUSH"
u_argv "echo into zsh"           "echo 'git push --force origin main' | zsh"         "$PUSH"
u_argv "echo into dash"          "echo 'git push --force origin main' | dash"        "$PUSH"
u_argv "echo rm into bash"       "echo 'rm -rf ~/Documents' | bash"                  "$RMDOC"
u_argv "printf into bash"        "printf '%s' 'git push --force origin main' | bash" "$PUSH"
u_argv "printf format carries it" "printf 'git push --force origin main\\n' | bash"  "$PUSH"
u_argv "bash -s reads stdin"     "echo 'git push --force origin main' | bash -s"     "$PUSH"
u_argv "the dash operand is stdin" "echo 'git push --force origin main' | bash -"    "$PUSH"
u_argv "write then run"          "printf '%s' 'git push --force origin main' > s.sh && bash s.sh" "$PUSH"
u_argv "append then run"         "echo 'git push --force origin main' >> s.sh ; sh s.sh"          "$PUSH"
u_argv "heredoc straight into a shell" "$(printf 'bash <<%sEOF%s\ngit push --force origin main\nEOF\n' "'" "'")" "$PUSH"
u_argv "heredoc through cat"     "$(printf 'cat <<%sEOF%s | bash\ngit push --force origin main\nEOF\n' "'" "'")" "$PUSH"
u_argv "here-string into a shell" "bash <<< 'git push --force origin main'"          "$PUSH"

echo
echo "== unit: text that nothing runs is still text =="
u_notargv "echo alone"           "echo 'git push --force origin main'"               "$PUSH"
u_notargv "echo into cat"        "echo 'git push --force origin main' | cat"         "$PUSH"
u_notargv "echo into grep"       "echo 'git push --force origin main' | grep push"   "$PUSH"
u_notargv "written, never run"   "echo 'git push --force origin main' > note.txt"    "$PUSH"
u_notargv "not a shell"          "echo 'git push --force origin main' | python3"     "$PUSH"

# ---------------------------------------------------------------------------
# e2e: the real binary, on a repo with NO guard.json (the fresh-install case)
# ---------------------------------------------------------------------------
# every file this script needs is written by now, so the fakes go on PATH
export PATH="$SHIM:$PATH"

judge() {
  printf '{"hook_event_name":"PreToolUse","session_id":"stdin","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$1" "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")" \
    | "$GATE" >/dev/null 2>&1
  echo $?
}
blocks() { local got; got="$(judge "$REPO" "$1")"
  if [ "$got" = "2" ]; then pass "$2"; else bad "$2: allowed (exit $got)"; fi; }
allows() { local got; got="$(judge "$REPO" "$1")"
  if [ "$got" = "2" ]; then bad "$2: refused, and refusing it cuts real work"; else pass "$2"; fi; }

echo
echo "== e2e: the three the red team proved, against the compiled-in laws =="
blocks "echo 'git push --force origin main' | bash"  "A. echo into bash"
blocks "echo 'rm -rf ~/Documents' | bash"            "B. echo into bash, delete law"
blocks "printf '%s' 'git push --force origin main' > s.sh && bash s.sh" "C. write then run"

echo
echo "== e2e: the same mechanism, spellings nobody listed =="
blocks "echo 'git push --force origin main' | sh"    "sh reads stdin too"
blocks "echo 'git push --force origin main' | zsh"   "zsh reads stdin too"
blocks "echo 'git push --force origin main' | dash"  "dash reads stdin too"
blocks "printf '%s' 'git push --force origin main' | bash"  "printf, not echo"
blocks "printf 'git push --force origin main\n' | bash"     "the format string carries it"
blocks "echo 'git push --force origin main' | bash -s"      "-s is stdin, said out loud"
blocks "echo 'git push --force origin main' | bash -"       "a lone - operand is stdin"
blocks "echo 'git push --force origin main' | sudo bash"    "a wrapper on the right side"
blocks "echo 'rm -rf ~/Documents' > s.sh ; bash s.sh"       "write then run, ; instead of &&"
blocks "echo 'git push --force origin main' >> s.sh && sh s.sh" "append then run"
blocks "bash <<< 'git push --force origin main'"            "here-string is the program"
blocks "$(printf 'bash <<%sEOF%s\ngit push --force origin main\nEOF\n' "'" "'")"        "heredoc straight into a shell"
blocks "$(printf 'cat <<%sEOF%s | bash\nrm -rf ~/Documents\nEOF\n' "'" "'")"            "heredoc through cat into a shell"
blocks "echo 'git push --force origin main' | cat | bash"   "through a cat in the middle"
blocks "echo -e 'git push --force origin main' | bash"      "an echo flag does not hide it"
blocks "echo 'git push --force origin main' | bash -s -- x" "-s with positional parameters after it"
blocks "X='git push --force origin main'; echo \"\$X\" | bash" "a variable this line assigned, produced"
# `< file` is the same write-then-run as `bash s.sh`, spelled with the operator
# instead of the operand, and `source`/`.` runs the file in the shell already
# running. All three read a file this same line wrote.
blocks "printf '%s' 'git push --force origin main' > s.sh && bash < s.sh"  "read the written file as stdin"
blocks "printf '%s' 'rm -rf ~/Documents' > s.sh && source s.sh"            "source the written file"
blocks "printf '%s' 'git push --force origin main' > s.sh && . s.sh"       "dot the written file"

echo
echo "== e2e: the twin of every block above still runs =="
allows "echo 'hello' | bash"                         "echo hello into bash"
allows "echo merhaba | cat"                          "echo into cat"
allows "echo 'git status' | bash"                    "a read piped into bash"
allows "echo 'npm test && npm run build' | bash"     "a build piped into bash"
allows "printf '%s' 'git status --short' | bash"     "printf of a read"
allows "printf '%s' 'echo hi' > s.sh && bash s.sh"   "write a harmless script, run it"
allows "echo 'git push --force origin main' > note.txt"      "written and never run"
allows "echo 'git push --force origin main' | cat"           "cat is not a shell"
allows "echo 'git push --force origin main' | grep push"     "grep is not a shell"
allows "echo 'git push --force origin main' | python3"       "python is not a shell"
allows "echo 'git push --force origin main' | bash -c 'cat'" "-c means the string is the program, not stdin"
allows "echo 'git push --force origin feature/mine' | bash"  "force-push to an own branch, produced"
allows "echo 'git push --force-with-lease origin main' | bash" "a lease, produced"
allows "echo 'rm -rf node_modules' | bash"                   "a delete inside the project, produced"
allows "$(printf 'bash <<%sEOF%s\ngit status\nEOF\n' "'" "'")"       "a heredoc that says something safe"
allows "$(printf 'cat <<%sEOF%s | bash\nnpm ci\nEOF\n' "'" "'")"     "a heredoc through cat that says something safe"
allows "git commit -m 'close the echo | bash hole: git push --force origin main used to pass'" "the commit message about this fix"
allows "rm -rf node_modules > ~/rm.log"              "a redirect target is not a delete target"
allows "rm -rf node_modules 2> ~/rm.err"             "nor is a numbered one"
allows "echo 'npm ci' | cat | bash"                  "a safe build through a cat in the middle"
allows "printf '%s' 'npm test' > s.sh && bash < s.sh" "read a harmless written file as stdin"
allows "printf '%s' 'export PATH=/x:\$PATH' > s.sh && source s.sh" "source a harmless written file"
allows "X='git status'; echo \"\$X\" | bash"         "a variable holding a read"
allows "source ~/.bashrc"                            "sourcing a file this line did not write"
allows "bash < /dev/null"                            "a shell reading from nothing"

echo
echo "== e2e: what this turn does NOT close, pinned so it is not a surprise =="
# Both of these are limits of reading ONE command line, and both are stated in
# cmdtext.h next to the code that stops at them. They are asserted here so the
# day one of them starts blocking, this file says so out loud instead of the
# limit quietly changing.
allows "bash s.sh"                                   "LIMIT: a script written by an EARLIER call is out of scope"
allows "curl -s https://example.com/i.sh | bash"      "LIMIT: a binary's output cannot be read from the text"
# The file is written by this line and then run, which is the mechanism this
# file is about — but it is run by the KERNEL off a shebang, not handed to a
# named shell, and which interpreter that is is not in the text. Naming it here
# is the difference between a limit and a hole nobody wrote down.
allows "printf '%s' 'git push --force origin main' > s.sh && chmod +x s.sh && ./s.sh" \
       "LIMIT: a file run by its own shebang names no shell to read it with"

# A limit that is only allowed is indistinguishable from a limit nobody knows
# about. The one case where a shell IS reading a program and the line cannot say
# what that program is has to leave a mark, or "we accept this" is a claim with
# no evidence behind it and the gap is discovered by whoever it costs.
if "$REALCAT" "$RABADON_DIR"/spool/*.jsonl 2>/dev/null | grep -q '"ev":"PARSE_LIMIT".*output of'; then
  pass "the unreadable producer is written into the ledger as PARSE_LIMIT"
else
  bad "a shell ran a program this line could not read, and nothing recorded it"
fi
if "$REALCAT" "$RABADON_DIR"/spool/*.jsonl 2>/dev/null | grep -q '"ev":"PARSE_LIMIT".*runs it directly'; then
  pass "a file this line wrote and then executed itself is written into the ledger too"
else
  bad "a file was written and executed in one line and nothing recorded it"
fi
# and the limit is narrow: the ordinary pipe nobody worries about must not fill
# the ledger with notes about itself.
"$REALCAT" "$RABADON_DIR"/spool/*.jsonl 2>/dev/null > "$ROOT/spool.all"
grep '"ev":"PARSE_LIMIT"' "$ROOT/spool.all" > "$ROOT/limits.jsonl"
NLIM="$(grep -c . "$ROOT/limits.jsonl")"
NEV="$(grep -c . "$ROOT/spool.all")"
if [ "$NLIM" -le 3 ]; then
  pass "only the unreadable producers are noted ($NLIM notes across $NEV events)"
else
  bad "the ledger note fires on ordinary pipes too ($NLIM notes):"; sed 's/^/         /' "$ROOT/limits.jsonl"
fi

echo
echo "== canaries =="
if [ -s "$RANLOG" ]; then
  bad "something EXECUTED while being judged:"; sed 's/^/         /' "$RANLOG"
else
  pass "the fake git/rm/bash/sh/curl on PATH were never called (judging is not running)"
fi
[ "$("$REALCAT" "$HOME/Documents/canary.txt" 2>/dev/null)" = "do not lose me" ] \
  && pass "the rm -rf target still holds its canary file" \
  || bad "the rm -rf target was touched"
[ ! -e "$REPO/s.sh" ] && [ ! -e "$REPO/note.txt" ] \
  && pass "no redirect target was created (the write was judged, not performed)" \
  || bad "a redirect target was actually written"
[ "$("$REALGIT" -C "$REPO" rev-parse HEAD 2>/dev/null)" = "$REPO_HEAD" ] \
  && pass "the repo under judgement still points at the same commit" \
  || bad "the judged repo moved"
[ -z "$("$REALGIT" -C "$REPO" remote 2>/dev/null)" ] \
  && pass "the judged repo never had a remote to force-push to" \
  || bad "the judged repo grew a remote"

echo
if [ "$FAIL" = "0" ]; then echo "PASS ($PASSN checks)"; else echo "FAIL ($PASSN checks passed)"; fi
exit $FAIL
