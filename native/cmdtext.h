// cmdtext.h — THE command parser. There is one, and both layers link it.
//
// rabadon asks a Bash command two questions. A deny rule asks what the line
// LOOKS like (a regex, rules.h). The three compiled-in laws ask what the line
// DOES (a structural read, baseline.h). Both have to answer a third question
// first — where does one command end, which word is the command name, which
// words are arguments, and which text is data — and for a while each answered
// it with its own code. That is not redundancy. Two answers to one question is
// a hole, and the hole opens under the WEAKER answer: a repo with no
// guard.json has only the compiled-in laws, so the stranger who runs
// `npm i -g rabadon` was protected by the smaller of the two parsers.
//
// Twelve spellings of one refused force-push were allowed by the laws while
// the plain form was refused (native/parser_unify_test.sh names each one and
// the exit code it used to get). None of them was a new kind of danger. Every
// one was the same command, spelled in a way only the other parser could read.
// So this file answers the shared question once, and baseline.h and rules.h
// both read the answer instead of deriving it.
//
// ---------------------------------------------------------------------------
// WHAT A CALLER GETS: parse() returns one Seg per command the line runs, and
// each Seg carries BOTH answers, from the same walk:
//
//   .surface   the text a regex is allowed to match. Data is neutralized here
//              (see below); this is what rules.h reads.
//   .words     argv, quotes off, the way execve would receive it. This is what
//              baseline.h reads.
//   .group     which shell context the command runs in, so a `cd` inside
//              `sh -c '...'` moves that context and not its caller's.
//
// ---------------------------------------------------------------------------
// WHY A SURFACE AT ALL. A deny rule used to be run against the whole command
// line as typed, which reads DATA as if it were CODE. Three ways it went
// wrong, all out of the live ledger, none theoretical:
//
//   git commit -m "close the git -C bypass: an agent wrote git push --force"
//       refused as a force-push. The push is nine characters of a commit
//       message. rabadon blocked the commit that was FIXING the bypass.
//   cat >> notes.txt <<'EOF' ... run npx wrangler deploy yourself ... EOF
//       refused as a deploy, twice, on prose being appended to a file.
//   claude -p "run this: git push --force origin master"
//       refused, though the outer command starts an agent and pushes nothing.
//
// The fix is not a softer regex. It is telling the regex where a command ENDS.
// Everything that executes stays in the matching area, because the cheapest way
// to make a false positive go away is to stop the rule from ever firing, and
// that deletes the product:
//
//   ; && || |          every chained command is its own surface
//   ( ... ) $( ) ` `   a subshell and a substitution are commands, not words
//   bash -c "<str>"    the string IS a command; it is parsed and added
//   sh -lc, eval       same. a short-flag CLUSTER carrying c is still -c
//   xargs sh -c        a wrapper is skipped to find the command underneath
//   python3 -c "<str>" NOT a shell; its argument stays data (this is the line
//                      between "re-parse it" and "trust it": only a shell)
//
// HOW A QUOTED WORD IS NEUTRALIZED. Not by dropping it — `git push --force
// origin "main"` must still be refused, and dropping quoted words is exactly
// the bypass an agent would find first. The quote characters come off and the
// word survives; only WHITESPACE THAT CAME FROM INSIDE THE QUOTES is rewritten
// to \x01. A pattern like `git\s+push` asks for two WORDS, and inside a commit
// message they are not two words, they are eleven characters of one. \x01 is
// not \s and not \w, so `\s` and `\b` both read it the way a shell would.
//
// A COMMAND NAME IS COMPARED THE WAY THE FILE SYSTEM COMPARES IT. `GIT push
// --force origin main` ran git, because APFS and HFS+ resolve GIT and git to
// the same binary, and macOS is case-insensitive by default — which is most of
// the audience README.md is written for. On a case-sensitive file system GIT is
// a different name and matching it would be a false positive, so this is a
// platform question and name_is() answers it per platform, not per taste.
//
// WHEN IT CANNOT PARSE (unterminated quote, heredoc with no terminator) it says
// so instead of guessing: `degraded` comes back true, the regex caller falls
// back to whole-line matching, and the gate writes a PARSE_DEGRADED line into
// the ledger. The segments are still produced — from the raw text, which is
// exactly what the structural caller used to see — so failing to preprocess
// never turns a law off. Failing toward MORE refusals is the safe direction;
// failing there quietly is not.
#pragma once

#include <cctype>
#include <string>
#include <utility>
#include <vector>

namespace rbtext {

using std::string;
using std::vector;

// whitespace that a regex must not read as a word boundary
static const char DATA_WS = '\x01';

struct Word { string text; bool quoted = false; bool op = false; };

// A redirection is an operator, not an argument, and reading it as one costs
// both ways. `rm -rf node_modules > ~/rm.log` deletes node_modules and writes a
// log, and the delete law read `~/rm.log` as a second target and refused the
// line. The same operator is also how text becomes a program: `> s.sh` on one
// command and `sh s.sh` on the next runs what the redirect wrote.
struct Redir { string op; string target; };

struct Seg {
  string surface;          // what a regex may match: data neutralized
  vector<Word> words;      // argv, quotes off, redirections taken out
  vector<Redir> redirs;    // < > >> << <<< and their targets
  vector<string> heredocs; // heredoc bodies this command reads on stdin
  vector<string> nested;   // subshell / substitution bodies lifted out of it
  int group = 0;           // the shell context this command runs in
  int parent = 0;          // the context it inherited its directory from
  bool pipes_out = false;  // a single `|` followed this command
};

struct Parsed {
  vector<Seg> segs;
  // where the read of ONE command line stops. Not an error and not a refusal:
  // a place the parser can name but cannot see into, written down so that
  // "we accept this" is a claim with evidence under it instead of a silence.
  vector<string> limits;
  int groups = 1;
  bool degraded = false;
  string why;
};

// kept for callers that only want the regex half
struct Surfaces {
  vector<string> texts;
  bool degraded = false;
  string why;
};

// ---------- small helpers (kept local so this header stands alone) ----------

inline bool ws(char c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }

inline string base_of(const string& s) {
  const size_t p = s.rfind('/');
  return p == string::npos ? s : s.substr(p + 1);
}

inline char lower_c(char c) { return (c >= 'A' && c <= 'Z') ? char(c - 'A' + 'a') : c; }

// Does the platform's file system resolve two spellings of a name to the same
// file? macOS (APFS and HFS+, both case-insensitive by default) and Windows do;
// Linux's ext4/xfs/btrfs do not. Comparing case-insensitively where the kernel
// compares case-sensitively would refuse a command that cannot run, which is a
// false positive, so the answer is compiled per platform.
#if defined(__APPLE__) || defined(_WIN32)
#define RB_FS_CASE_INSENSITIVE 1
#else
#define RB_FS_CASE_INSENSITIVE 0
#endif

inline bool name_is(const string& a, const char* lit) {
#if RB_FS_CASE_INSENSITIVE
  size_t i = 0;
  for (; i < a.size() && lit[i]; i++) if (lower_c(a[i]) != lower_c(lit[i])) return false;
  return i == a.size() && !lit[i];
#else
  return a == lit;
#endif
}

// the same rule for the gate's hot-path pre-filter: a line that cannot contain
// the name cannot break a law, and on a case-insensitive file system "GIT" is
// the name. Two scans of a short string, which is what the 2.3ms budget bought.
inline bool mentions(const string& hay, const char* needle) {
#if RB_FS_CASE_INSENSITIVE
  size_t len = 0;
  while (needle[len]) len++;
  if (len == 0 || hay.size() < len) return len == 0;
  for (size_t i = 0; i + len <= hay.size(); i++) {
    size_t k = 0;
    while (k < len && lower_c(hay[i + k]) == lower_c(needle[k])) k++;
    if (k == len) return true;
  }
  return false;
#else
  return hay.find(needle) != string::npos;
#endif
}

// FOO=bar, the shell's own prefix form.
//
// The NAME is the constrained half: [A-Za-z_][A-Za-z0-9_]*, which is the rule a
// shell applies itself. The VALUE is not constrained, and that is what this
// predicate used to get wrong: it rejected any word carrying a '/' ANYWHERE, so
// `FOO=/x` was not an assignment, command_index() stopped on it, and
// base_of("FOO=/x") handed the rule engine `x` as the command name. Not git,
// not rm, so a line a shell runs as a force-push consulted no law at all. One
// character of VALUE text turned the whole gate off.
//
// Reading the NAME instead of the whole word keeps everything the slash test was
// there for: `bin/tool=v2` is a path and not an assignment, because its slash
// sits before the '=' where a name may not carry one; and `2FOO=/x` is not one
// either, so the words after it are still read as arguments of a command by
// that name -- which is what a shell does with it.
//
// Which spellings count was answered by ASKING a shell, not by reading a manual:
// `FOO+=v` (append) and `arr[i]=v` (one element) are prefixes too, and bash runs
// the command after them exactly as it runs it after `FOO=v` -- so leaving them
// out would have left the same hole open under two more spellings. `arr[]=v` is
// in for the same measured reason: bash complains about the subscript and runs
// the command anyway. `FOO+bar=v` and an unclosed `arr[0=v` are out, because
// bash looks for a COMMAND by that name and never reaches what follows.
inline bool is_assignment(const string& s) {
  if (s.empty() || !(isalpha((unsigned char)s[0]) || s[0] == '_')) return false;
  size_t i = 1;
  while (i < s.size() && (isalnum((unsigned char)s[i]) || s[i] == '_')) i++;
  if (i < s.size() && s[i] == '[') {           // arr[i]= -- an element is a name too
    int depth = 0;
    size_t j = i;
    for (; j < s.size(); j++) {
      if (s[j] == '[') depth++;
      else if (s[j] == ']' && --depth == 0) break;
    }
    if (j >= s.size()) return false;           // never closed: a command word
    i = j + 1;
  }
  if (i < s.size() && s[i] == '+') i++;        // FOO+=v, the append form
  return i < s.size() && s[i] == '=';
}

// ---------- wrappers: the command is not always the first word ----------
// `xargs bash -c "git push --force origin main"` was allowed because the
// wrapper list had sudo/env/nohup/time and not xargs, so the shell underneath
// was never seen as a shell. A list of NAMES is not enough either: `timeout 5
// git push --force origin main` reads `5` as the command unless the wrapper's
// own operand is skipped, and `env -i git ...` reads `-i`. So each wrapper
// declares what it eats: which short flags take a separate value, which long
// flags do, and how many plain operands come before the command.
struct WrapSpec { string shortVal; string longVal; int operands; };

inline bool wrapper_of(const string& base, WrapSpec& w) {
  w.shortVal.clear(); w.longVal.clear(); w.operands = 0;
  if (name_is(base, "sudo"))    { w.shortVal = "ugpCDRhUT";
                                  w.longVal = "|--user|--group|--prompt|--chdir|--chroot|--close-from|"; return true; }
  if (name_is(base, "doas"))    { w.shortVal = "uC"; return true; }
  if (name_is(base, "env"))     { w.shortVal = "uCS"; w.longVal = "|--unset|--chdir|"; return true; }
  if (name_is(base, "command"))  return true;
  if (name_is(base, "builtin"))  return true;
  if (name_is(base, "nohup"))    return true;
  if (name_is(base, "setsid"))   return true;
  if (name_is(base, "exec"))    { w.shortVal = "a"; return true; }
  if (name_is(base, "stdbuf"))  { w.shortVal = "ioe"; w.longVal = "|--input|--output|--error|"; return true; }
  if (name_is(base, "time"))    { w.shortVal = "of"; w.longVal = "|--output|--format|"; return true; }
  if (name_is(base, "nice"))    { w.shortVal = "n"; w.longVal = "|--adjustment|"; return true; }
  if (name_is(base, "ionice"))  { w.shortVal = "cnp"; return true; }
  if (name_is(base, "timeout")) { w.shortVal = "ks"; w.longVal = "|--kill-after|--signal|";
                                  w.operands = 1; return true; }   // the duration
  if (name_is(base, "xargs"))   { w.shortVal = "IiLnPsEadD";
                                  w.longVal = "|--replace|--max-lines|--max-args|--max-procs|"
                                              "--max-chars|--eof|--arg-file|--delimiter|"; return true; }
  // xcrun finds a tool in the active developer directory and EXECS it, which is
  // the wrapper shape exactly, and the name it was handed is the command. It was
  // not in this table, so `xcrun` was read as the command name -- neither git nor
  // rm, segment marked irrelevant, the three compiled laws never asked. Not a
  // hypothetical: `xcrun git` resolves to a real git shipped with the Xcode
  // command line tools this project already needs in order to build, and xcrun
  // does NOT resolve that name through PATH, so nothing the shell can see stands
  // in front of it. Both measured in native/xcrun_wrapper_test.sh.
  //
  // shortVal is EMPTY on purpose: none of xcrun's short options takes a value,
  // and it refuses a cluster outright (`-nk` is an unrecognized option), so no
  // short token can eat the next word. Its two valued options answer to one dash
  // and to two alike and both spellings are listed, because reading `-sdk` as a
  // cluster would skip one word too few and name the SDK as the command. The
  // attached form is not listed because xcrun rejects it and runs nothing.
  if (name_is(base, "xcrun"))   { w.longVal = "|--sdk|-sdk|--toolchain|-toolchain|"; return true; }
  // `script -q /dev/null git push --force origin main`. A session recorder is
  // not a logger wrapped AROUND a shell it cannot reach: script(1) runs the
  // argv itself -- `script [-aeFkqr] [-t time] [file [command ...]]`. Measured
  // under a pty (it refuses to start without a terminal) with a fake git first
  // on PATH, in section 1 of script_wrapper_test.sh: the destructive argv
  // arrives unchanged.
  //
  // The typescript FILE is why a name-only entry would have repeated the
  // `timeout 5 git ...` mistake, and why the operand count earns its keep in
  // the other direction too: `script git push --force origin main` runs NOTHING
  // -- `git` is the file it records INTO, `push` is the command, and there is no
  // command by that name. Same measurement: the fake git is never called and a
  // file named `git` is left behind. Eating exactly one operand is what tells
  // those two lines apart.
  if (name_is(base, "script"))  { w.shortVal = "t";                // -t <flush interval>
                                  w.operands = 1; return true; }   // the typescript file
  return false;
}

// ---------- reserved words: the shell's syntax is not a command name ----------
// `{ git push --force origin main; }` reported its command name as `{`, and `{`
// is neither git nor rm, so the segment was marked irrelevant and the three
// compiled laws were never asked. `then`, `do`, `else`, `elif` and `!` are the
// same shape: the shell CONSUMES the word and runs the command after it. They
// are reserved words, recognized only when they stand alone and unquoted, which
// is why the comparison is exact and case-sensitive — a shell resolves `git` on
// a case-insensitive file system, but it never reads `THEN` as `then`, and it
// never reads a quoted `'{'` as syntax either.
//
// `for`, `in`, `select` and `function` are deliberately NOT here: the word
// after those is a variable or a function NAME, and skipping to it would name a
// command the shell does not run. `case` is handled separately below, because
// what it consumes is not one word.
inline bool reserved_word(const Word& w) {
  if (w.quoted) return false;
  const string& s = w.text;
  return s == "!" || s == "{" || s == "}" ||
         s == "if" || s == "then" || s == "elif" || s == "else" || s == "fi" ||
         s == "while" || s == "until" || s == "do" || s == "done" || s == "esac";
}

// `a)` — a case ARM's pattern. It is a word ending in an unquoted ')' with no
// '(' of its own, which is what separates it from a function head (`f()`), an
// arithmetic command (`((i++))`) and a substitution (`$(x)`): those carry their
// own opening paren, this one is closed by a paren the `case` opened.
inline bool case_pattern(const Word& w) {
  return !w.quoted && !w.text.empty() && w.text[w.text.size() - 1] == ')' &&
         w.text.find('(') == string::npos;
}

// index of the real command word: skip the shell's own syntax, then FOO=bar
// assignments, then each wrapper with everything that wrapper consumes.
inline size_t command_index(const vector<Word>& w) {
  size_t i = 0;
  while (i < w.size()) {
    if (reserved_word(w[i])) { i++; continue; }
    // `case WORD in PATTERN) cmd` — two words and a pattern list stand between
    // the keyword and the first command of the arm, so the pattern is what ends
    // the skip. When the arm sits on its own line the segment STARTS with the
    // pattern, which is the i == 0 case.
    if (!w[i].quoted && w[i].text == "case") {
      size_t j = i + 1;
      while (j < w.size() && !case_pattern(w[j])) j++;
      i = (j < w.size()) ? j + 1 : w.size();
      continue;
    }
    if (i == 0 && case_pattern(w[i])) { i++; continue; }
    if (is_assignment(w[i].text)) { i++; continue; }
    WrapSpec spec;
    if (!wrapper_of(base_of(w[i].text), spec)) break;
    i++;
    while (i < w.size()) {
      const string& o = w[i].text;
      if (o == "--") { i++; break; }
      if (o.size() < 2 || o[0] != '-') break;
      // an option whose value is a SEPARATE word. Membership in the wrapper's
      // own list is asked BEFORE the dash count, because a wrapper decides for
      // itself how many dashes its options wear: xcrun answers to `-sdk macosx`
      // exactly as it answers to `--sdk macosx`. Every entry in every list that
      // existed before this line was `--`-prefixed, so no token that used to
      // reach the short-cluster branch reaches it differently now.
      if (o.find('=') == string::npos &&
          spec.longVal.find("|" + o + "|") != string::npos) { i += 2; continue; }
      if (o[1] == '-') { i++; continue; }                  // --long, or --long=value
      // a short cluster: the first flag that takes a value ends it, and the
      // value is the rest of the token when there is one (-I{}, -n1) or the
      // next word when there is not (-n 1)
      bool nextWord = false;
      for (size_t k = 1; k < o.size(); k++) {
        if (spec.shortVal.find(o[k]) == string::npos) continue;
        nextWord = (k + 1 == o.size());
        break;
      }
      i += nextWord ? 2 : 1;
    }
    while (i < w.size() && is_assignment(w[i].text)) i++;   // env FOO=bar cmd
    for (int k = 0; k < spec.operands && i < w.size(); k++) i++;
  }
  return i;
}

// index of the ')' closing the '(' at `open`, quote-aware. npos if unbalanced.
inline size_t match_paren(const string& s, size_t open) {
  int depth = 0;
  for (size_t i = open; i < s.size(); i++) {
    const char c = s[i];
    if (c == '\\' && i + 1 < s.size()) { i++; continue; }
    if (c == '\'') {
      const size_t j = s.find('\'', i + 1);
      if (j == string::npos) return string::npos;
      i = j; continue;
    }
    if (c == '"') {
      size_t j = i + 1;
      while (j < s.size() && s[j] != '"') j += (s[j] == '\\' && j + 1 < s.size()) ? 2 : 1;
      if (j >= s.size()) return string::npos;
      i = j; continue;
    }
    if (c == '(') depth++;
    else if (c == ')') { if (--depth == 0) return i; }
  }
  return string::npos;
}

// ---------- pass 1: lift comments and heredoc BODIES out of the line ----------
// A heredoc body is the one place in a shell command where arbitrary prose sits
// with no quoting at all, which is why it produced two of the ledger's false
// refusals. `<<EOF`, `<<'EOF'`, `<<"EOF"` and the tab-stripping `<<-EOF` are all
// recognized; `<<<` is a here-STRING and is copied through whole.
//
// The body comes OUT of the matchable text and is handed back in `bodies`,
// in the order the `<<` operators appear, rather than dropped. Prose appended to
// a notes file still must not read as code — that is the false refusal this pass
// exists for — but the same bytes handed to a shell ARE code, and a pass that
// forgets them cannot tell those two apart.
inline string preprocess(const string& cmd, bool* ok, string* why,
                         vector<string>* bodies = NULL) {
  *ok = true; why->clear();
  if (bodies) bodies->clear();
  string out;
  vector<std::pair<string, bool> > pending;  // delimiter, dash form
  const size_t n = cmd.size();
  size_t i = 0;
  bool wordStart = true;
  while (i < n) {
    const char c = cmd[i];
    if (c == '\\' && i + 1 < n) { out += c; out += cmd[i + 1]; i += 2; wordStart = false; continue; }
    if (c == '\'') {
      const size_t j = cmd.find('\'', i + 1);
      if (j == string::npos) { *ok = false; *why = "unterminated single quote"; return cmd; }
      out += cmd.substr(i, j - i + 1); i = j + 1; wordStart = false; continue;
    }
    if (c == '"') {
      size_t j = i + 1;
      while (j < n && cmd[j] != '"') j += (cmd[j] == '\\' && j + 1 < n) ? 2 : 1;
      if (j >= n) { *ok = false; *why = "unterminated double quote"; return cmd; }
      out += cmd.substr(i, j - i + 1); i = j + 1; wordStart = false; continue;
    }
    // a comment starts only at the beginning of a word, which is why `$#`,
    // `${#x}` and `http://h/p#frag` are not comments
    if (c == '#' && wordStart) {
      while (i < n && cmd[i] != '\n') i++;
      continue;
    }
    // a here-STRING. All three bytes are consumed together: reading them one at
    // a time left the parser standing on the SECOND '<', where `<<` with a
    // following word looks exactly like a heredoc whose terminator never
    // arrives — `bash <<< 'text'` came back degraded for that reason alone.
    if (c == '<' && i + 2 < n && cmd[i + 1] == '<' && cmd[i + 2] == '<') {
      out += "<<<"; i += 3; wordStart = false; continue;
    }
    if (c == '<' && i + 1 < n && cmd[i + 1] == '<' && !(i + 2 < n && cmd[i + 2] == '<')) {
      out += "<<"; i += 2;
      bool dash = false;
      if (i < n && cmd[i] == '-') { dash = true; out += '-'; i++; }
      while (i < n && (cmd[i] == ' ' || cmd[i] == '\t')) { out += cmd[i]; i++; }
      string delim;
      while (i < n) {
        const char d = cmd[i];
        if (d == '\'') {
          const size_t j = cmd.find('\'', i + 1);
          if (j == string::npos) { *ok = false; *why = "unterminated heredoc delimiter"; return cmd; }
          delim += cmd.substr(i + 1, j - i - 1); out += cmd.substr(i, j - i + 1); i = j + 1; continue;
        }
        if (d == '"') {
          size_t j = i + 1;
          while (j < n && cmd[j] != '"') j += (cmd[j] == '\\' && j + 1 < n) ? 2 : 1;
          if (j >= n) { *ok = false; *why = "unterminated heredoc delimiter"; return cmd; }
          delim += cmd.substr(i + 1, j - i - 1); out += cmd.substr(i, j - i + 1); i = j + 1; continue;
        }
        if (d == '\\' && i + 1 < n) { delim += cmd[i + 1]; out += cmd.substr(i, 2); i += 2; continue; }
        if (ws(d) || d == '<' || d == '>' || d == '|' || d == ';' || d == '&' || d == ')') break;
        delim += d; out += d; i++;
      }
      if (delim.empty()) { *ok = false; *why = "heredoc with no delimiter"; return cmd; }
      pending.push_back(std::make_pair(delim, dash));
      wordStart = false;
      continue;
    }
    if (c == '\n' && !pending.empty()) {
      out += '\n'; i++;
      for (size_t p = 0; p < pending.size(); p++) {
        bool closed = false;
        string body;
        while (i <= n) {
          const size_t eol = cmd.find('\n', i);
          const size_t end = (eol == string::npos) ? n : eol;
          const string raw = cmd.substr(i, end - i);
          string line = raw;
          i = (eol == string::npos) ? n : eol + 1;
          if (pending[p].second) {
            const size_t a = line.find_first_not_of('\t');
            line = (a == string::npos) ? "" : line.substr(a);
          }
          // the TERMINATOR is compared with its trailing blanks off; the body
          // line is kept exactly as written, because it is about to be read as
          // a program and a program's own spacing is its own business
          string term = line;
          while (!term.empty() && (term[term.size() - 1] == '\r' || term[term.size() - 1] == ' '))
            term.erase(term.size() - 1);
          if (term == pending[p].first) { closed = true; break; }
          body += pending[p].second ? line : raw;
          body += '\n';
          if (eol == string::npos) break;
        }
        if (!closed) { *ok = false; *why = "heredoc <<" + pending[p].first + " never terminated"; return cmd; }
        if (bodies) bodies->push_back(body);
      }
      pending.clear();
      wordStart = true;
      continue;
    }
    out += c; i++;
    wordStart = ws(c) || c == ';' || c == '&' || c == '|' || c == '(';
  }
  if (!pending.empty()) { *ok = false; *why = "heredoc <<" + pending[0].first + " never terminated"; return cmd; }
  return out;
}

// ---------- pass 2: one segment per command, with its surface and its argv ----
// A `( )`, `$( )` or backtick body RUNS. Inside double quotes it is lifted out
// and the quoted text closes over it, because its whitespace must not be
// neutralized with the data around it. OUTSIDE quotes the text is left exactly
// where it was as well as lifted: the surface a regex sees stays byte for byte
// what it saw before this file learned about substitution, so no existing rule
// changes meaning, while the lifted copy is what gives the argv reader a
// command name that is `git` and not `$(git`.
inline void scan(const string& s, vector<Seg>& out) {
  Seg cur;
  string word;
  bool wq = false, hasWord = false, tickOpen = false;

  const size_t n = s.size();
  for (size_t i = 0; i < n; i++) {
    const char c = s[i];

    if (c == '\\' && i + 1 < n) {
      const char d = s[++i];
      // a backslash-newline is a LINE CONTINUATION: bash removes both bytes and
      // does NOT break the word. Copying the newline through was what made
      // `git push \<newline>--force` arrive as the single token "\n--force",
      // which is neither "--force" nor anything starting with '-'.
      if (d == '\n') continue;
      if (d == ' ' || d == '\t') { cur.surface += DATA_WS; word += ' '; hasWord = true; continue; }
      cur.surface += '\\'; cur.surface += d; word += d;
      hasWord = true;
      continue;
    }

    if (c == '\'') {
      size_t j = s.find('\'', i + 1);
      if (j == string::npos) j = n;
      for (size_t k = i + 1; k < j; k++) {
        const char e = s[k];
        cur.surface += ws(e) ? DATA_WS : e;
        word += e;
      }
      wq = true; hasWord = true; i = j;
      continue;
    }

    if (c == '"') {
      size_t k = i + 1;
      while (k < n && s[k] != '"') {
        if (s[k] == '\\' && k + 1 < n) {
          const char e = s[k + 1];
          if (e == '\n') { k += 2; continue; }             // line continuation
          if (e == '$' || e == '`' || e == '"' || e == '\\') {
            cur.surface += e; word += e;
          } else { cur.surface += '\\'; cur.surface += e; word += '\\'; word += e; }
          k += 2; continue;
        }
        if (s[k] == '$' && k + 1 < n && s[k + 1] == '(') {
          const size_t e = match_paren(s, k + 1);
          if (e == string::npos) { cur.surface += s[k]; word += s[k]; k++; continue; }
          cur.nested.push_back(s.substr(k + 2, e - k - 2));
          k = e + 1; continue;
        }
        if (s[k] == '`') {
          const size_t e = s.find('`', k + 1);
          if (e == string::npos) { cur.surface += s[k]; word += s[k]; k++; continue; }
          cur.nested.push_back(s.substr(k + 1, e - k - 1));
          k = e + 1; continue;
        }
        const char e = s[k];
        cur.surface += ws(e) ? DATA_WS : e;
        word += e;
        k++;
      }
      wq = true; hasWord = true; i = (k < n) ? k : n;
      continue;
    }

    if (c == '&' || c == '|' || c == ';' || c == '\n') {
      // `|` hands this command's stdout to the next one; `||` does not, it is a
      // branch. Which of the two it is decides whether the text on the left is
      // the PROGRAM on the right, so the answer is recorded here, where it is
      // still known, instead of being re-derived later from the raw line.
      const bool pipe = (c == '|') && !(i + 1 < n && s[i + 1] == '|');
      if ((c == '&' || c == '|') && i + 1 < n && s[i + 1] == c) i++;
      if (hasWord) { cur.words.push_back(Word{word, wq}); word.clear(); wq = false; hasWord = false; }
      size_t a = cur.surface.find_first_not_of(" \t\r\n");
      if (a == string::npos) cur.surface.clear();
      else cur.surface = cur.surface.substr(a, cur.surface.find_last_not_of(" \t\r\n") - a + 1);
      cur.pipes_out = pipe;
      if (!cur.surface.empty() || !cur.words.empty() || !cur.nested.empty()) out.push_back(cur);
      cur = Seg();
      continue;
    }

    // A redirection is an operator and bash ends the word at it, with or
    // without a space: `>s.sh`, `> s.sh` and `2>&1` are all operator + target.
    // Reading them as ordinary argv is what handed the delete law a second
    // "target" it was never asked to delete. The SURFACE is untouched — the
    // same bytes in the same order — because a regex is entitled to see the
    // line as it was written.
    if (c == '>' || c == '<') {
      string op;
      bool fd = hasWord && !wq && !word.empty();
      for (size_t k = 0; fd && k < word.size(); k++)
        if (!isdigit((unsigned char)word[k])) fd = false;
      if (fd) { op = word; word.clear(); hasWord = false; wq = false; }
      else if (hasWord) { cur.words.push_back(Word{word, wq}); word.clear(); wq = false; hasWord = false; }
      size_t k = i;
      op += s[k++];
      if (k < n && s[k] == c) {                                   // >> or <<
        op += s[k++];
        if (c == '<' && k < n && s[k] == '<') op += s[k++];        // <<< here-string
      } else if (k < n && (s[k] == '&' || s[k] == '|' || (c == '<' && s[k] == '>'))) {
        op += s[k++];                                             // >& <& >| <>
      }
      cur.words.push_back(Word{op, false, true});
      cur.surface.append(s, i, k - i);
      i = k - 1;
      continue;
    }

    if (c == ' ' || c == '\t' || c == '\r') {
      if (hasWord) { cur.words.push_back(Word{word, wq}); word.clear(); wq = false; hasWord = false; }
      cur.surface += ' ';
      continue;
    }

    // outside quotes the body of a substitution or a subshell is already
    // whitespace-correct, so it stays inline exactly as the old whole-line
    // matcher saw it — and is ALSO recorded, so it gets read as a command
    if (c == '$' && i + 1 < n && s[i + 1] == '(') {
      const size_t e = match_paren(s, i + 1);
      if (e != string::npos) cur.nested.push_back(s.substr(i + 2, e - i - 2));
    } else if (c == '`') {
      if (!tickOpen) {
        const size_t e = s.find('`', i + 1);
        if (e != string::npos) { cur.nested.push_back(s.substr(i + 1, e - i - 1)); tickOpen = true; }
      } else tickOpen = false;
    } else if (c == '(' && (!hasWord || word == "<" || word == ">")) {
      const size_t e = match_paren(s, i);
      if (e != string::npos) cur.nested.push_back(s.substr(i + 1, e - i - 1));
    }

    cur.surface += c; word += c; hasWord = true;
  }
  if (hasWord) cur.words.push_back(Word{word, wq});
  {
    size_t a = cur.surface.find_first_not_of(" \t\r\n");
    if (a == string::npos) cur.surface.clear();
    else cur.surface = cur.surface.substr(a, cur.surface.find_last_not_of(" \t\r\n") - a + 1);
    if (!cur.surface.empty() || !cur.words.empty() || !cur.nested.empty()) out.push_back(cur);
  }
}

// ---------- pass 3: a string a SHELL is about to run is a command ----------
// `bash -c "git push --force origin main"` is the whole force-push, spelled as
// one quoted word. Neutralizing it as data and stopping there would be the
// bypass. It is parsed and appended instead. `python3 -c` is not on this list on
// purpose: python is not a shell, and its argument really is data.
inline bool is_shell(const string& name) {
  return name_is(name, "bash") || name_is(name, "sh") || name_is(name, "zsh") ||
         name_is(name, "dash") || name_is(name, "ksh") || name_is(name, "ash");
}

// every string this segment hands to a shell to run. `-c` is not a token to
// compare against: `sh -lc`, `sh -xc` and `sh -ec` are short-flag CLUSTERS and
// each of them runs the next word.
inline vector<string> shell_scripts(const vector<Word>& w) {
  vector<string> scripts;
  const size_t ci = command_index(w);
  if (ci >= w.size()) return scripts;
  const string name = base_of(w[ci].text);
  if (is_shell(name)) {
    for (size_t j = ci + 1; j < w.size(); j++) {
      const string& a = w[j].text;
      if (a.size() >= 2 && a[0] == '-' && a[1] != '-' && a.find('c') != string::npos) {
        if (j + 1 < w.size()) scripts.push_back(w[j + 1].text);
        break;
      }
      if (a == "-c" || a == "--command") { if (j + 1 < w.size()) scripts.push_back(w[j + 1].text); break; }
      if (a.empty() || a[0] != '-') break;  // an operand: a script FILE, not a string
    }
  } else if (name_is(name, "eval")) {
    string joined;
    for (size_t j = ci + 1; j < w.size(); j++) {
      if (!joined.empty()) joined += " ";
      joined += w[j].text;
    }
    if (!joined.empty()) scripts.push_back(joined);
  }
  return scripts;
}

// ---------- pass 4: an operator is not an argument ----------
inline void split_redirs(Seg& sg) {
  vector<Word> kept;
  kept.reserve(sg.words.size());
  for (size_t i = 0; i < sg.words.size(); i++) {
    if (!sg.words[i].op) { kept.push_back(sg.words[i]); continue; }
    Redir r;
    r.op = sg.words[i].text;
    if (i + 1 < sg.words.size() && !sg.words[i + 1].op) { r.target = sg.words[i + 1].text; i++; }
    sg.redirs.push_back(r);
  }
  sg.words.swap(kept);
}

// does this redirection carry the text the command WROTE? `2>` is the error
// stream and carries none of it.
inline bool redir_writes_stdout(const Redir& r) {
  size_t a = 0;
  while (a < r.op.size() && isdigit((unsigned char)r.op[a])) a++;
  const string fd = r.op.substr(0, a), body = r.op.substr(a);
  if (body != ">" && body != ">>" && body != ">|") return false;
  return fd.empty() || fd == "1";
}
inline bool redir_appends(const Redir& r) { return r.op.find(">>") != string::npos; }

// `./s.sh` and `s.sh` are one file, and a redirect and the shell that runs it
// rarely spell it the same way.
inline string norm_target(const string& p) {
  size_t a = 0;
  while (a + 2 <= p.size() && p[a] == '.' && p[a + 1] == '/') a += 2;
  return p.substr(a);
}

// ---------- pass 5: a shell with nothing to run reads its program from stdin --
// THE HOLE THIS CLOSES. Both layers answered correctly and the answers were
// still wrong together:
//
//   echo 'git push --force origin main' | bash
//
// The left side is an echo whose force-push is one QUOTED ARGUMENT — data, and
// refusing it was a real false refusal in the watch-mode ledger, which is why
// the surface neutralizes it. The right side is the bare word `bash`, which
// carries no dangerous word at all. Neither classification is wrong. But a
// shell handed no script operand and no -c string reads its PROGRAM from
// standard input, so on this pipe the thing classified as data is the thing
// that runs, and `> s.sh` then `sh s.sh` is the same move with the text parked
// in a file first — worse, because after the redirect the dangerous string is
// on no command line at all.
//
// The answer is not a rule per spelling; twelve of those were the last bug. It
// is that a pipe into an operand-less shell makes the left side's OUTPUT a
// program, and it is parsed as one.
//
// WHAT THIS MUST NOT DO. Refusing every pipe into a shell passes every case
// above and kills `curl ... | sh`, `echo 'hello' | bash` and every install
// tutorial ever written. Only the produced TEXT is judged, by the same laws as
// any other command, so the twin of each block still runs.
inline bool shell_reads_stdin(const vector<Word>& w) {
  const size_t ci = command_index(w);
  if (ci >= w.size() || !is_shell(base_of(w[ci].text))) return false;
  for (size_t j = ci + 1; j < w.size(); j++) {
    const string& a = w[j].text;
    if (a.empty()) continue;
    if (a == "-") return true;                        // the operand that names stdin
    if (a == "--") return j + 1 >= w.size();          // `sh -- file` still has a file
    if (a[0] != '-') return false;                    // an operand: a script FILE
    if (a.size() >= 2 && a[1] == '-') {
      if (a.compare(0, 9, "--command") == 0) return false;
      continue;
    }
    if (a.find('c') != string::npos) return false;    // -c, and -lc / -xc clusters
    if (a.find('s') != string::npos) return true;     // -s says stdin out loud
  }
  return true;
}

// the file a command was told to RUN: a shell's script operand, or the argument
// of `source` / `.`, which runs the file in the shell already running and so is
// the same write-then-run with no new process to notice.
//
// NOT here, and named in native/stdin_program_test.sh as a limit rather than
// left to be discovered: `chmod +x s.sh && ./s.sh`. That file is written by the
// line and then run by the line, but it is run off its own shebang, and which
// interpreter that names is not in the text.
inline string run_file_operand(const vector<Word>& w);

// the script FILE a shell was told to run — "" when it was told a string, or
// told nothing at all
inline string shell_script_operand(const vector<Word>& w) {
  const size_t ci = command_index(w);
  if (ci >= w.size() || !is_shell(base_of(w[ci].text))) return string();
  for (size_t j = ci + 1; j < w.size(); j++) {
    const string& a = w[j].text;
    if (a.empty()) continue;
    if (a == "--") return (j + 1 < w.size()) ? w[j + 1].text : string();
    if (a == "-") return string();
    if (a[0] != '-') return a;
    if (a.size() >= 2 && a[1] == '-') continue;
    if (a.find('c') != string::npos || a.find('s') != string::npos) return string();
  }
  return string();
}

inline string run_file_operand(const vector<Word>& w) {
  const size_t ci = command_index(w);
  if (ci >= w.size()) return string();
  const string name = base_of(w[ci].text);
  if (name == "." || name_is(name, "source"))
    return (ci + 1 < w.size()) ? w[ci + 1].text : string();
  return shell_script_operand(w);
}

// ---------- pass 6: the text a command WRITES, when the line contains it -----
// `echo`, `printf`, a heredoc and a here-string carry their output in the
// command itself, so it can be read off the line with no execution and no
// guessing. A binary's output is not in the line. That boundary is named in
// Parsed::limits instead of being assumed away in either direction — assuming
// it harmless is the hole; assuming it dangerous refuses `curl | sh`.
struct Produced { bool known = false; string text; string producer; };

inline void echo_output(const vector<Word>& w, size_t ci, string& out) {
  size_t i = ci + 1;
  while (i < w.size()) {
    const string& a = w[i].text;
    if (a.size() >= 2 && a[0] == '-' && a.find_first_not_of("neE", 1) == string::npos) { i++; continue; }
    break;
  }
  out.clear();
  for (bool first = true; i < w.size(); i++, first = false) {
    if (!first) out += ' ';
    out += w[i].text;
  }
}

// printf reuses its format until the arguments run out, and so does this.
inline void printf_output(const vector<Word>& w, size_t ci, string& out) {
  out.clear();
  size_t a = ci + 1;
  if (a < w.size() && w[a].text == "--") a++;
  if (a >= w.size()) return;
  const string fmt = w[a].text;
  size_t argi = a + 1;
  for (int rounds = 0; rounds < 16; rounds++) {
    const size_t started = argi;
    for (size_t i = 0; i < fmt.size(); i++) {
      const char c = fmt[i];
      if (c == '\\' && i + 1 < fmt.size()) {
        const char e = fmt[++i];
        if (e == 'n') out += '\n';
        else if (e == 't') out += '\t';
        else if (e == 'r') out += '\r';
        else if (e == '\\' || e == '"' || e == '\'') out += e;
        else { out += '\\'; out += e; }
        continue;
      }
      if (c != '%') { out += c; continue; }
      if (i + 1 < fmt.size() && fmt[i + 1] == '%') { out += '%'; i++; continue; }
      size_t j = i + 1;
      while (j < fmt.size() && !isalpha((unsigned char)fmt[j])) j++;
      if (j >= fmt.size()) { out += c; continue; }
      if (argi < w.size()) { out += w[argi].text; argi++; }
      i = j;
    }
    if (argi <= started || argi >= w.size()) break;
  }
}

inline const string* file_text(const vector<std::pair<string, string> >& wrote, const string& p) {
  const string k = norm_target(p);
  for (size_t i = wrote.size(); i > 0; i--) if (wrote[i - 1].first == k) return &wrote[i - 1].second;
  return NULL;
}

inline Produced produced_stdout(const Seg& sg, const vector<std::pair<string, string> >& wrote,
                                const Produced* pipedIn) {
  Produced p;
  const size_t ci = command_index(sg.words);
  if (ci >= sg.words.size()) {                 // `<<EOF` with no command of its own
    if (sg.heredocs.empty()) return p;
    for (size_t k = 0; k < sg.heredocs.size(); k++) p.text += sg.heredocs[k];
    p.known = true;
    return p;
  }
  const string name = base_of(sg.words[ci].text);
  p.producer = name;
  if (name_is(name, "echo"))   { echo_output(sg.words, ci, p.text);   p.known = true; return p; }
  if (name_is(name, "printf")) { printf_output(sg.words, ci, p.text); p.known = true; return p; }
  if (name_is(name, "cat")) {
    string acc;
    bool operands = false;
    for (size_t j = ci + 1; j < sg.words.size(); j++) {
      const string& a = sg.words[j].text;
      if (a.empty()) continue;
      if (a[0] == '-' && a != "-") continue;                       // cat's own flags
      if (a == "-") continue;                                      // stdin, handled below
      const string* t = file_text(wrote, a);
      if (!t) return p;                     // a file this line did not write: unknown
      acc += *t;
      operands = true;
    }
    if (!operands) {
      for (size_t k = 0; k < sg.heredocs.size(); k++) acc += sg.heredocs[k];
      if (sg.heredocs.empty()) {
        if (!pipedIn || !pipedIn->known) return p;                 // whatever came down the pipe
        acc = pipedIn->text;
      }
    }
    p.text = acc;
    p.known = true;
  }
  return p;
}

// ---------- a variable the line itself defined is not unresolved ----------
// `C="push --force"; git $C origin main` was allowed because an operand
// carrying `$` is waived. That waiver is real and stays: guessing where an
// unknown path expands to is worse than missing one, which is why the delete
// law still passes over `$TARGET`. But the waiver was argued for rm TARGETS and
// it silently covered the git SUBCOMMAND as well, and a subcommand this same
// line assigns two words earlier is not unknown at all — it is written down.
//
// So only what the line ASSIGNS, from a literal, is substituted, and only into
// argv. An unquoted expansion word-splits, exactly as the shell does it, so
// `git $C` becomes three words and not one. Anything still unknown stays `$X`
// and stays waived.
//
// The SURFACE is deliberately left as written. A regex reads the line as text
// and `echo $MSG` is not a force-push no matter what MSG holds; rewriting the
// text a rule matches would invent commands nobody typed. The structural reader
// does not have that problem: it checks the command NAME, so it can tell
// `git push --force` from `echo push --force`.
// A name this line bound, and every value it can hold where the body runs.
//
//   C="push --force"   ONE value that happens to contain a space. `git $C`
//                      word-splits into three words, because that is what C
//                      really holds and what the shell really does with it.
//   for b in x main    TWO values, and never both at once: the body runs once
//                      with b=x and once with b=main. Joining them into one
//                      string and letting the word split sort it out is the
//                      wrong model, and it invents commands. Over that header,
//                      `git push --force origin backup/$b` would become the
//                      words `backup/x` AND `main` — and the gate would refuse
//                      a push to main that no iteration of that loop performs.
//                      So a word expands to the CROSS PRODUCT of its variables'
//                      values (`backup/x`, `backup/main`, both of them branches
//                      of this caller's own), and a law that refuses on any one
//                      of them has asked the right question of every pass.
struct Binding { string name; vector<string> values; };

inline const Binding* env_lookup(const vector<Binding>& env, const string& n) {
  for (size_t i = env.size(); i > 0; i--) if (env[i - 1].name == n) return &env[i - 1];
  return NULL;
}

inline bool var_char(char c) { return isalnum((unsigned char)c) || c == '_'; }

// The cap is on the cross product, not on the line: two twenty-value loops in
// one word is four hundred spellings of one command and the gate has a 2.3ms
// budget (BENCHMARK.md). Past the cap the word stays as written and stays
// waived — the same answer this file already gives for `$(cmd)`.
const size_t kExpandCap = 64;

// every word this line can make of one unquoted word; false when any name is
// unknown, or when the fan-out is past the cap
inline bool expand_word(const string& w, const vector<Binding>& env, vector<string>& out) {
  out.assign(1, string());
  bool any = false;
  for (size_t i = 0; i < w.size(); i++) {
    if (w[i] != '$') { for (size_t k = 0; k < out.size(); k++) out[k] += w[i]; continue; }
    size_t a = i + 1;
    bool braced = false;
    if (a < w.size() && w[a] == '{') { braced = true; a++; }
    size_t b = a;
    while (b < w.size() && var_char(w[b])) b++;
    if (b == a) return false;                       // $(, $?, bare $ — not ours
    if (braced) { if (b >= w.size() || w[b] != '}') return false; }
    const Binding* v = env_lookup(env, w.substr(a, b - a));
    if (!v || v->values.empty()) return false;
    if (out.size() * v->values.size() > kExpandCap) return false;
    vector<string> next;
    next.reserve(out.size() * v->values.size());
    for (size_t k = 0; k < out.size(); k++)
      for (size_t m = 0; m < v->values.size(); m++) next.push_back(out[k] + v->values[m]);
    out.swap(next);
    any = true;
    i = braced ? b : b - 1;
  }
  return any;
}

inline void split_ws(const string& s, vector<Word>& out) {
  size_t i = 0;
  while (i < s.size()) {
    while (i < s.size() && ws(s[i])) i++;
    size_t j = i;
    while (j < s.size() && !ws(s[j])) j++;
    if (j > i) out.push_back(Word{s.substr(i, j - i), false});
    i = j;
  }
}

// `for NAME in W1 W2 ...` — the shell's OTHER way of writing down what a name
// holds. The header is its own segment (the line splits on `;` and newline), so
// it is read here and handed to the segments after it exactly as a leading
// assignment is. Without it, `for b in main; do git push --force origin $b;
// done` reached the force-push law with `$b` unresolved, and an unresolved
// expansion is waived — the waiver argued for `$TARGET` coming from somewhere
// the line cannot see, spent on a value the line spells out four words earlier.
//
// LITERAL ONLY, on the same terms as an assignment: a value carrying `$` or a
// backtick is fetched, not written down, so `for b in $(git branch)` stays
// waived. A glob, a brace or a leading `~` is not written down either — the
// shell rewrites those before the first pass, and binding the pattern TEXT
// would claim the variable holds a string it never holds.
//
// The binding outlives the loop on purpose: after `done` a shell leaves the
// variable holding its last value, so a `$b` after the loop is not unknown
// either.
inline bool loop_header(const vector<Word>& w, Binding& out) {
  if (w.size() < 4) return false;
  if (w[0].quoted || w[0].text != "for") return false;
  if (w[2].quoted || w[2].text != "in") return false;
  const string& n = w[1].text;
  if (n.empty() || w[1].quoted) return false;
  if (!(isalpha((unsigned char)n[0]) || n[0] == '_')) return false;
  for (size_t i = 1; i < n.size(); i++) if (!var_char(n[i])) return false;
  out.name = n;
  out.values.clear();
  for (size_t i = 3; i < w.size(); i++) {
    const string& v = w[i].text;
    if (v.empty()) return false;
    if (v.find('$') != string::npos || v.find('`') != string::npos) return false;
    if (v.find('*') != string::npos || v.find('?') != string::npos ||
        v.find('[') != string::npos || v.find('{') != string::npos) return false;
    if (v[0] == '~') return false;
    if (out.values.size() >= kExpandCap) return false;
    out.values.push_back(v);
  }
  return !out.values.empty();
}

inline void apply_env(Seg& sg, vector<Binding>& env) {
  if (!env.empty()) {
    vector<Word> next;
    next.reserve(sg.words.size());
    for (size_t i = 0; i < sg.words.size(); i++) {
      vector<string> forms;
      if (!sg.words[i].quoted && sg.words[i].text.find('$') != string::npos &&
          expand_word(sg.words[i].text, env, forms)) {
        for (size_t k = 0; k < forms.size(); k++) split_ws(forms[k], next);
      } else {
        next.push_back(sg.words[i]);
      }
    }
    sg.words.swap(next);
  }
  // then what this segment writes down for the ones after it joins the
  // environment: a loop header, or leading assignments.
  Binding loop;
  if (loop_header(sg.words, loop)) { env.push_back(loop); return; }
  for (size_t i = 0; i < sg.words.size(); i++) {
    const string& s = sg.words[i].text;
    if (!is_assignment(s)) break;
    const size_t eq = s.find('=');
    const string val = s.substr(eq + 1);
    if (val.find('$') != string::npos || val.find('`') != string::npos) continue;  // not literal
    env.push_back(Binding{s.substr(0, eq), vector<string>(1, val)});
  }
}

// ---------- pass 2c: a name this line binds, and then runs ----------
// `gitx() { git push --force origin main; }; gitx` arrived at the laws as three
// commands: one called `gitx()` whose ARGUMENT LIST happened to contain a
// force-push, one called `}`, and a bare word `gitx` naming nothing any law
// could read. A shell reads the same bytes as one force-push.
//
// The same program written with newlines instead of semicolons was already
// refused — a newline puts the body in its own segment, so `git` landed in
// command position by accident. Same bytes, opposite verdict, decided by
// punctuation. That is the tell that the gate was reading the line's shape
// instead of what a shell does with it.
//
// A shell does two different things with those bytes at two different moments.
// A DEFINITION runs nothing at all: it binds a name to a body and moves on. A
// CALL runs the body — in the caller's own shell, not a subshell, so a `cd` in
// it moves the caller. So the body comes OUT of the run list where it is
// written and goes back in where it is CALLED, in the caller's own segment
// group, which is where the walk below already tracks directories. Both halves
// matter: lifting it out is what stops `gitx() { rm -rf ~; }` with no call from
// being refused for something that never ran, and putting it back is what
// stops the call from being a bare word.
//
// The call word itself STAYS in the list. Its arguments are the function's
// positional parameters, and they can carry a `$( )` the scanner already lifted
// or text a user's deny regex is entitled to read; dropping them would trade
// one blind spot for another.
struct FnDef { string name; vector<Seg> body; };

// a word that can be bound as a function name. Deliberately narrow: a shell
// accepts stranger names than this, and every character allowed here is one a
// call site could be mistaken for.
inline bool fn_name_ok(const string& s) {
  if (s.empty()) return false;
  for (size_t i = 0; i < s.size(); i++) {
    const char c = s[i];
    if (isalnum((unsigned char)c) || c == '_' || c == '-' || c == '.' || c == ':') continue;
    return false;
  }
  // a word the shell reads as syntax is not a name it can bind
  return !(s == "if" || s == "then" || s == "elif" || s == "else" || s == "fi" ||
           s == "while" || s == "until" || s == "for" || s == "do" || s == "done" ||
           s == "case" || s == "esac" || s == "in" || s == "select" ||
           s == "function" || s == "time" || s == "coproc");
}

// Does a definition start at segment `i`? The four spellings a shell accepts —
// `f() {`, `f () {`, `function f {`, `function f() {` — differ only in where
// the parens are and whether the keyword is there, and the scanner glues `()`
// onto the name when no space separates them.
inline bool fn_header(const vector<Seg>& segs, size_t i, string& name,
                      size_t& bodySeg, size_t& bodyWord) {
  const vector<Word>& w = segs[i].words;
  size_t k = 0;
  bool kw = false;
  if (k < w.size() && !w[k].quoted && w[k].text == "function") { kw = true; k++; }
  if (k >= w.size() || w[k].quoted) return false;
  name = w[k].text;
  bool parens = false;
  if (name.size() > 2 && name.compare(name.size() - 2, 2, "()") == 0) {
    name.erase(name.size() - 2);
    parens = true;
    k++;
  } else {
    k++;
    if (k < w.size() && !w[k].quoted && w[k].text == "()") { parens = true; k++; }
    else if (k + 1 < w.size() && !w[k].quoted && w[k].text == "(" &&
             !w[k + 1].quoted && w[k + 1].text == ")") { parens = true; k += 2; }
  }
  // without the parens only the keyword form is a definition, so `mkdir { a }`
  // stays the command it is
  if (!parens && !kw) return false;
  if (!fn_name_ok(name)) return false;
  if (k < w.size()) {
    if (w[k].quoted || w[k].text != "{") return false;
    bodySeg = i;
    bodyWord = k + 1;
    return true;
  }
  // `f()` with the brace on the next line: the newline already ended the
  // segment, so the body opens at the start of the next one
  if (i + 1 < segs.size() && !segs[i + 1].words.empty() &&
      !segs[i + 1].words[0].quoted && segs[i + 1].words[0].text == "{") {
    bodySeg = i + 1;
    bodyWord = 1;
    return true;
  }
  return false;
}

// the `}` that closes the brace the header opened, counting the groups nested
// inside it. A quoted brace is data and does not count.
inline bool fn_body_end(const vector<Seg>& segs, size_t bodySeg, size_t bodyWord,
                        size_t& endSeg, size_t& endWord) {
  int depth = 1;
  for (size_t s = bodySeg; s < segs.size(); s++)
    for (size_t j = (s == bodySeg ? bodyWord : 0); j < segs[s].words.size(); j++) {
      const Word& x = segs[s].words[j];
      if (x.quoted) continue;
      if (x.text == "{") depth++;
      else if (x.text == "}" && --depth == 0) { endSeg = s; endWord = j; return true; }
    }
  return false;                      // an unclosed body: left exactly as it was
}

inline void lift_functions(vector<Seg>& segs, vector<string>* limits) {
  vector<FnDef> defs;
  // `gitx() { gitx; }; gitx` does not return in a shell either, and a parser
  // that answers a pre-commit hook is not allowed to be the thing that hangs.
  // The budget is what makes this walk terminate, and running out of it is
  // written down instead of being passed off as "nothing found".
  int budget = 32;
  bool spent = false;
  for (size_t i = 0; i < segs.size();) {
    string name;
    size_t bs = 0, bw = 0, es = 0, ew = 0;
    if (fn_header(segs, i, name, bs, bw) && fn_body_end(segs, bs, bw, es, ew)) {
      FnDef d;
      d.name = name;
      for (size_t s = bs; s <= es; s++) {
        Seg part = segs[s];
        const size_t from = (s == bs) ? bw : 0;
        const size_t to = (s == es) ? ew : part.words.size();
        part.words = (from <= to)
                         ? vector<Word>(part.words.begin() + from, part.words.begin() + to)
                         : vector<Word>();
        if (s == es) part.pipes_out = false;   // the `}` ends the body, not a pipe
        if (!part.words.empty() || !part.nested.empty()) d.body.push_back(part);
      }
      segs.erase(segs.begin() + i, segs.begin() + es + 1);
      size_t at = defs.size();
      for (size_t k = 0; k < defs.size(); k++) if (defs[k].name == name) { at = k; break; }
      if (at == defs.size()) defs.push_back(d); else defs[at] = d;   // a rebinding
      continue;                       // segs[i] is now whatever followed the `}`
    }

    const size_t ci = command_index(segs[i].words);
    const FnDef* hit = NULL;
    if (ci < segs[i].words.size() && !segs[i].words[ci].quoted)
      for (size_t k = 0; k < defs.size(); k++)
        if (defs[k].name == segs[i].words[ci].text) { hit = &defs[k]; break; }
    if (hit && !hit->body.empty()) {
      if (budget > 0) {
        budget--;
        vector<Seg> body = hit->body;
        // what a function PRINTS is what its body printed, so the pipe and the
        // redirections written on the CALL belong to the body's last command:
        // `deploy > out.sh` writes what the body wrote.
        Seg& last = body[body.size() - 1];
        last.pipes_out = segs[i].pipes_out;
        for (size_t r = 0; r < segs[i].redirs.size(); r++) last.redirs.push_back(segs[i].redirs[r]);
        segs[i].redirs.clear();
        segs[i].pipes_out = false;
        segs.insert(segs.begin() + i + 1, body.begin(), body.end());
      } else if (!spent) {
        spent = true;
        if (limits) limits->push_back(
            "this line calls named functions more times than the parser expands "
            "them, so the deepest calls are named here but not read");
      }
    }
    i++;
  }
}

// ---------- pass 7: an alias the SAME line defines IS the subcommand --------
// THE HOLE THIS CLOSES.
//
//   git -c alias.x='push --force' x origin main
//
// The option walk below already knew that `-c` takes a value and stepped over
// it correctly, which is exactly how the verb got through: the walk landed on
// `x`, the compiled law compared that token to `push`, and a user's deny regex
// needs the literal word `push` in the text. Both layers returned 0. The
// dangerous verb was written down once, inside a quoted config value, and never
// said again — the same shape as `C="push --force"; git $C`, one layer further
// in, and the answer is the same one: what the line itself writes down is not
// unknown, it is resolved before any law reads it.
//
// Measured against git 2.39.5 in a repo with no remote, and each fact below is
// a case in native/git_alias_test.sh rather than a reading of the manual:
//   -c alias.X=... invoked as x   runs. config keys fold case on BOTH sides,
//                                 section and variable name.
//   -c alias.a=b -c alias.b=...   runs. aliases chain, so this expands in a
//                                 loop, with a seen-list ending a cycle.
//   -c alias.x=A -c alias.x=B     runs B. the last definition wins.
//   -c alias.x='!...' x aa bb     hands `... aa bb` to a SHELL. that is not
//                                 argv at all, so it is returned as a script
//                                 and pass 3's machinery reads it as a command.
//   -calias.x=... (attached)      REJECTED by git ("unknown option"), so it is
//                                 not a hole and nothing here pretends it is.
//
// THE ONE LIMIT, named and not hidden: git resolves BUILT-IN commands before
// aliases, so `-c alias.status=<anything> status` really runs status and this
// expands it anyway. Telling them apart needs a list of every git builtin —
// the hand-kept set this parser exists to avoid — and the error it buys is a
// refusal of a line nobody writes.
// git's own leading options: EVERY one of them, not a list of known ones.
// `git --exec-path=/x push --force` slipped through a hand-listed set (31.07).
// The rule is structural: after `git`, skip every token that starts with '-',
// consuming a value only for the options that genuinely take a separate one.
// This walk lived in baseline.h and moved here when the alias table above had
// to be read off the same options — "which word is the subcommand" is a
// question about READING the line, and this file is where the line is read.
inline bool git_subcommand(const vector<Word>& t, size_t gi, size_t& subIdx) {
  size_t i = gi + 1;
  while (i < t.size()) {
    const string& s = t[i].text;
    if (s.empty() || s[0] != '-') { subIdx = i; return true; }
    const bool takesValue = (s == "-C" || s == "-c" || s == "--git-dir" || s == "--work-tree");
    i += takesValue ? 2 : 1;
  }
  return false;
}

// `alias.x=push --force` — the config pair `-c` carries, name folded the way
// git folds a config key. Not an alias key: not ours, and `-c user.name=push`
// must stay a name and not become a subcommand.
inline bool git_alias_pair(const string& tok, string& name, string& body) {
  const size_t eq = tok.find('=');
  if (eq == string::npos) return false;
  string key = tok.substr(0, eq);
  for (size_t i = 0; i < key.size(); i++) key[i] = lower_c(key[i]);
  if (key.size() <= 6 || key.compare(0, 6, "alias.") != 0) return false;
  name = key.substr(6);
  body = tok.substr(eq + 1);
  // inside quotes this parser writes its own marker where the whitespace was,
  // so the value read off a SURFACE and the value read off argv are one string
  for (size_t i = 0; i < body.size(); i++) if (body[i] == DATA_WS) body[i] = ' ';
  return true;
}

// ---------- a `-c` pair that is not an alias ---------------------------------
// An alias is not the only thing `-c` can hand git. `remote.<name>.push` is a
// REFSPEC, and a refspec decides which branch a push rewrites — the question
// the force-push law asks. `git -c remote.origin.push=refs/heads/x:refs/heads/
// main push --force origin` names no branch on the line, so the law fell back
// to reading .git/HEAD and refused it only from main.
//
// The key is split and folded the way git folds a config key, and the two
// halves fold DIFFERENTLY. Measured against git 2.39.5 with --dry-run against a
// bare repo in a scratch dir (each line is a case in native/push_refspec_test.sh):
//   -c REMOTE.origin.PUSH=<a>:<main>   used     section and variable fold case
//   -c remote.ORIGIN.push=<a>:<main>   NOT used the subsection between them is
//                                               case-SENSITIVE, so this is a
//                                               config for a different remote
// A key with no dot at all names no section and is not a key.
inline bool git_config_pair(const string& tok, string& key, string& value) {
  const size_t eq = tok.find('=');
  if (eq == string::npos) return false;
  const string raw = tok.substr(0, eq);
  const size_t first = raw.find('.'), last = raw.rfind('.');
  if (first == string::npos) return false;
  string sec = raw.substr(0, first), var = raw.substr(last + 1);
  const string sub = (first == last) ? string() : raw.substr(first + 1, last - first - 1);
  for (size_t i = 0; i < sec.size(); i++) sec[i] = lower_c(sec[i]);
  for (size_t i = 0; i < var.size(); i++) var[i] = lower_c(var[i]);
  key = sub.empty() ? sec + "." + var : sec + "." + sub + "." + var;
  value = tok.substr(eq + 1);
  // inside quotes this parser writes its own marker where the whitespace was,
  // so the value read off a SURFACE and the value read off argv are one string
  for (size_t i = 0; i < value.size(); i++) if (value[i] == DATA_WS) value[i] = ' ';
  return true;
}

// EVERY value this line binds to `wantKey`, in order, and not the last one:
// remote.<name>.push is MULTI-VALUED, and git pushes all of them. Measured —
//   -c remote.origin.push=<a>:<topic> -c remote.origin.push=<a>:<main>
//     -> feat -> main (forced update) AND feat -> topic
// so a reader that kept the last definition would have read the harmless half
// of that line. Only the options BEFORE the subcommand are read: that is where
// git's own are, and `git push origin -c remote.origin.push=...` is an operand.
inline void git_config_values(const vector<Word>& t, size_t gi, size_t sub,
                              const string& wantKey, vector<string>& out) {
  for (size_t i = gi + 1; i + 1 < sub && i + 1 < t.size(); i++) {
    if (t[i].text != "-c") continue;
    string k, v;
    if (!git_config_pair(t[i + 1].text, k, v)) continue;
    if (k == wantKey) out.push_back(v);
  }
}

// the body this command line binds to `want`, last definition winning. Only the
// options BEFORE the subcommand are read: that is where git's own are.
inline bool git_line_alias(const vector<Word>& t, size_t gi, size_t sub,
                           const string& want, string& body) {
  string key = want;
  for (size_t i = 0; i < key.size(); i++) key[i] = lower_c(key[i]);
  bool found = false;
  for (size_t i = gi + 1; i + 1 < sub && i + 1 < t.size(); i++) {
    if (t[i].text != "-c") continue;
    string n, v;
    if (!git_alias_pair(t[i + 1].text, n, v)) continue;
    if (n != key) continue;
    body = v;
    found = true;
  }
  return found;
}

// `--config-env=alias.x=NAME` binds the alias to an ENVIRONMENT variable, and
// the environment of the shell that will run git is not in this text. Named as
// a limit rather than guessed at, which is what Parsed::limits is for.
inline bool git_configenv_alias(const vector<Word>& t, size_t gi, size_t sub, const string& want) {
  static const string pre = "--config-env=";
  string key = want;
  for (size_t i = 0; i < key.size(); i++) key[i] = lower_c(key[i]);
  for (size_t i = gi + 1; i < sub && i < t.size(); i++) {
    const string& s = t[i].text;
    if (s.size() <= pre.size() || s.compare(0, pre.size(), pre) != 0) continue;
    string n, v;
    if (git_alias_pair(s.substr(pre.size()), n, v) && n == key) return true;
  }
  return false;
}

// Rewrites `t` into the argv git will really run. A `!` body is not argv, so it
// comes back through *shellBody and the caller hands it to pass 3.
inline void expand_git_alias(vector<Word>& t, string* shellBody, vector<string>* limits) {
  const size_t ci = command_index(t);
  if (ci >= t.size() || !name_is(base_of(t[ci].text), "git")) return;
  vector<string> seen;
  for (int round = 0; round < 8; round++) {
    size_t sub = 0;
    if (!git_subcommand(t, ci, sub)) return;
    const string tok = t[sub].text;
    string body;
    if (!git_line_alias(t, ci, sub, tok, body)) {
      if (limits && git_configenv_alias(t, ci, sub, tok))
        limits->push_back("an alias named '" + tok + "' is bound by --config-env to an "
                          "environment variable, so what git will run under that name is not "
                          "in this command line");
      return;
    }
    string key = tok;
    for (size_t i = 0; i < key.size(); i++) key[i] = lower_c(key[i]);
    for (size_t i = 0; i < seen.size(); i++) if (seen[i] == key) return;  // an alias cycle
    seen.push_back(key);
    if (!body.empty() && body[0] == '!') {
      if (shellBody) {
        string s = body.substr(1);
        for (size_t i = sub + 1; i < t.size(); i++) { s += " "; s += t[i].text; }
        *shellBody = s;
      }
      return;
    }
    vector<Word> words;
    split_ws(body, words);
    if (words.empty()) return;
    vector<Word> next(t.begin(), t.begin() + sub);
    next.insert(next.end(), words.begin(), words.end());
    next.insert(next.end(), t.begin() + sub + 1, t.end());
    t.swap(next);
  }
}

// ---------- pass 7b: a cluster of short options IS those options ------------
// THE HOLE THIS CLOSES.
//
//   git push -fu origin main
//
// git's subcommands read their options with parse-options, and parse-options
// takes short options written as one word: `-fu` is `--force --set-upstream`.
// Both layers missed that word from the same side. The compiled law compared
// the WHOLE token to `-f`, so `-fu` fell through to "starts with a dash, skip"
// and force stayed false. A project spells the same law `(--force|-f)\b`, and
// there is no word boundary between the f and the u. One word, two layers,
// zero refusals — and the answer is the one this file always gives: what git
// will really run is resolved once, here, before any law reads it.
//
// Measured against git 2.39.5, and every line is a check in
// native/short_cluster_test.sh rather than a reading of the manual:
//   push -fu into a rewound branch  forced the remote back a commit AND set
//                                   upstream. The f in the cluster is --force.
//   push -qf / -fq / -uf / -qfu     parse (they reach the remote lookup), so
//                                   order and company do not matter.
//   push -fZ                        exit 129, "unknown switch `Z'": an unknown
//                                   letter is refused, never ignored.
//   git -pv status, git -pC . status  exit 129, "unknown option". git's OWN
//                                   options — the ones before the subcommand —
//                                   are not parse-options and do NOT cluster.
//
// So the split starts AT THE SUBCOMMAND, the word the option walk above already
// finds, and stops at `--`, after which git reads operands and a path may be
// spelled anything. A single-letter token is already its own option and is left
// alone.
//
// THE ONE LIMIT, named and not hidden: parse-options lets a short option carry
// its value attached, and an attached value made of letters looks like more
// letters. `git commit -mfix` commits the message "fix" and this reads it as
// `-m -f -i -x`. Two things bound what that costs. A cluster is split only when
// every character after the dash is an ASCII LETTER, so an attached path, a
// dotted value, a hyphenated word, a count (`git log -12`, `git log -n5`) and
// anything quoted are untouched; and no law reads a short flag outside
// `git push`, where the only short option taking a value is `-o`. The twin
// checks in the test file hold that: `git commit -mfix`, `git commit -am fix`,
// `git push -oci.skip origin main` and `git log -12` are all still allowed.
inline bool short_option_cluster(const Word& w) {
  const string& s = w.text;
  if (w.quoted || s.size() < 3 || s[0] != '-' || s[1] == '-') return false;
  for (size_t k = 1; k < s.size(); k++)
    if (!isalpha((unsigned char)s[k])) return false;
  return true;
}

inline void split_git_short_clusters(vector<Word>& t) {
  const size_t ci = command_index(t);
  if (ci >= t.size() || !name_is(base_of(t[ci].text), "git")) return;
  size_t sub = 0;
  if (!git_subcommand(t, ci, sub)) return;
  vector<Word> next(t.begin(), t.begin() + (sub + 1));
  bool operandsOnly = false;
  for (size_t i = sub + 1; i < t.size(); i++) {
    const Word& w = t[i];
    if (!operandsOnly && !w.quoted && w.text == "--") operandsOnly = true;
    if (operandsOnly || !short_option_cluster(w)) { next.push_back(w); continue; }
    for (size_t k = 1; k < w.text.size(); k++)
      next.push_back(Word{string("-") + w.text[k], false});
  }
  t.swap(next);
}

// ---------- the whole answer ----------
inline void emit(const string& text, int group, int parent, Parsed& out, int depth,
                 vector<Binding> env,
                 const vector<string>* bodies = NULL, size_t* bcur = NULL) {
  if (depth > 4) return;
  vector<Seg> local;
  scan(text, local);
  for (size_t i = 0; i < local.size(); i++) split_redirs(local[i]);
  // preprocess lifted the heredoc bodies out of THIS text, in the order the
  // `<<` operators appear in it, so the two lists line up by position. A nested
  // text (a -c string, a subshell body) was never preprocessed, so a `<<` in it
  // owns no body here and claims none.
  if (bodies && bcur && depth == 0)
    for (size_t i = 0; i < local.size(); i++)
      for (size_t r = 0; r < local[i].redirs.size(); r++)
        if (local[i].redirs[r].op == "<<" && *bcur < bodies->size())
          local[i].heredocs.push_back((*bodies)[(*bcur)++]);
  // AFTER the heredoc bodies are handed out and not before: that hand-off is
  // positional, it counts `<<` operators in the order the scanner produced
  // them, and this pass moves segments. A definition is taken out of the run
  // list here and its body is put back at every call, so everything below —
  // the directory walk, the pipe chain, the file a line writes and then runs —
  // sees a function call as the commands it actually runs.
  lift_functions(local, &out.limits);

  vector<std::pair<string, string> > wrote;  // path -> what this line put in it
  Produced piped;                            // what the command before handed over
  bool pipedIn = false;

  for (size_t i = 0; i < local.size(); i++) {
    Seg sg = local[i];
    sg.group = group;
    sg.parent = parent;
    apply_env(sg, env);
    // the argv git will really run, before anything reads it: the alias this
    // same line defines is resolved here, so the structural reader sees the
    // subcommand AND the rebuilt text a deny regex is matched against carries
    // it too. A `!` body is a shell program, and joins the scripts below.
    string aliasShell;
    expand_git_alias(sg.words, &aliasShell, &out.limits);
    // and the options that alias body may itself have written as one word: an
    // alias is resolved first because `-c alias.x='push -fu'` puts the cluster
    // on the line only after the body is spliced in.
    split_git_short_clusters(sg.words);
    const vector<string> nested = sg.nested;
    vector<string> scripts = shell_scripts(sg.words);
    if (!aliasShell.empty()) scripts.push_back(aliasShell);

    // the program this command is about to run but was never handed as an
    // argument: read off stdin, or read out of a file this same line wrote
    string prog, blind;
    bool progKnown = false;
    if (shell_reads_stdin(sg.words)) {
      string hs, infile;
      bool hasHs = false;
      for (size_t r = 0; r < sg.redirs.size(); r++) {
        if (sg.redirs[r].op == "<<<") { hs = sg.redirs[r].target; hasHs = true; }
        else if (sg.redirs[r].op == "<") infile = sg.redirs[r].target;
      }
      if (!sg.heredocs.empty()) {
        for (size_t k = 0; k < sg.heredocs.size(); k++) prog += sg.heredocs[k];
        progKnown = true;
      } else if (hasHs) {
        prog = hs; progKnown = true;
      } else if (!infile.empty()) {
        // `sh < s.sh` is `sh s.sh` with the operator standing in for the operand
        if (const string* t = file_text(wrote, infile)) { prog = *t; progKnown = true; }
      } else if (pipedIn) {
        if (piped.known) { prog = piped.text; progKnown = true; }
        else blind = piped.producer.empty() ? string("the command before it") : piped.producer;
      }
    } else {
      const string f = run_file_operand(sg.words);
      if (!f.empty()) {
        if (const string* t = file_text(wrote, f)) { prog = *t; progKnown = true; }
      } else {
        // this line wrote a file and this line runs it straight off its own
        // shebang. The program IS known — it is sitting in `wrote` — but which
        // interpreter reads it is decided by the file's first line, not by this
        // command, so judging it as shell would be inventing a fact. Recorded
        // instead of guessed in either direction.
        const size_t ci2 = command_index(sg.words);
        if (ci2 < sg.words.size() && file_text(wrote, sg.words[ci2].text))
          out.limits.push_back("this line wrote '" + sg.words[ci2].text +
                               "' and then runs it directly, so which interpreter reads it is "
                               "named by the file's own first line and not by this command");
      }
    }

    out.segs.push_back(sg);
    // a child is emitted right after its parent so the caller can walk the list
    // in order and still know that a `cd` in a subshell did not move the caller
    for (size_t k = 0; k < nested.size(); k++)
      emit(nested[k], out.groups++, group, out, depth + 1, env, bodies, bcur);
    for (size_t k = 0; k < scripts.size(); k++)
      emit(scripts[k], out.groups++, group, out, depth + 1, env, bodies, bcur);
    if (progKnown && !prog.empty())
      emit(prog, out.groups++, group, out, depth + 1, env);
    if (!blind.empty())
      out.limits.push_back("a shell reads its program from the output of '" + blind +
                           "', and this command line does not contain that output");

    // what this command produced, and where it went
    Produced pr = produced_stdout(sg, wrote, pipedIn ? &piped : NULL);
    const Redir* w = NULL;
    for (size_t r = 0; r < sg.redirs.size(); r++)
      if (redir_writes_stdout(sg.redirs[r])) w = &sg.redirs[r];
    if (w && !w->target.empty()) {
      const string key = norm_target(w->target);
      string val;
      if (pr.known && redir_appends(*w))
        if (const string* prevText = file_text(wrote, key)) val = *prevText;
      if (pr.known) { val += pr.text; wrote.push_back(std::make_pair(key, val)); }
      else for (size_t k = wrote.size(); k > 0; k--)
        if (wrote[k - 1].first == key) { wrote.erase(wrote.begin() + (k - 1)); break; }
      pr.known = false;                      // it went to a file, not down the pipe
      pr.text.clear();
    }
    piped = pr;
    pipedIn = local[i].pipes_out;
  }
}

inline Parsed parse(const string& cmd) {
  Parsed p;
  bool ok = true;
  string why;
  vector<string> bodies;
  size_t bcur = 0;
  // when preprocessing fails, `pre` comes back as the raw line: the regex
  // caller is told (degraded) and falls back, and the structural caller still
  // gets segments — the same raw text it read before this header existed.
  const string pre = preprocess(cmd, &ok, &why, &bodies);
  p.degraded = !ok;
  p.why = why;
  emit(pre, 0, 0, p, 0, vector<Binding>(), &bodies, &bcur);
  return p;
}

inline Surfaces exec_surfaces(const string& cmd) {
  const Parsed p = parse(cmd);
  Surfaces r;
  r.degraded = p.degraded;
  r.why = p.why;
  if (p.degraded) return r;
  for (size_t i = 0; i < p.segs.size(); i++)
    if (!p.segs[i].surface.empty()) r.texts.push_back(p.segs[i].surface);
  return r;
}

// The command split as raw text slices, quotes left on. A user rule is a regex
// and must be judged against the line as it was WRITTEN; this is what the regex
// caller falls back to when the line cannot be parsed.
inline vector<string> raw_segments(const string& cmd) {
  vector<string> out;
  size_t start = 0;
  for (size_t i = 0; i < cmd.size(); i++) {
    const char c = cmd[i];
    if (c == '\\' && i + 1 < cmd.size()) { i++; continue; }
    if (c == '\'') { const size_t j = cmd.find('\'', i + 1); i = (j == string::npos) ? cmd.size() : j; continue; }
    if (c == '"') {
      size_t j = i + 1;
      while (j < cmd.size() && cmd[j] != '"') j += (cmd[j] == '\\' && j + 1 < cmd.size()) ? 2 : 1;
      i = j;
      continue;
    }
    if (c == '&' || c == '|' || c == ';' || c == '\n') {
      out.push_back(cmd.substr(start, i - start));
      if ((c == '&' || c == '|') && i + 1 < cmd.size() && cmd[i + 1] == c) i++;
      start = i + 1;
    }
  }
  out.push_back(cmd.substr(start));
  vector<string> kept;
  for (size_t i = 0; i < out.size(); i++) {
    const string& s = out[i];
    const size_t a = s.find_first_not_of(" \t\r\n");
    if (a == string::npos) continue;
    const size_t b = s.find_last_not_of(" \t\r\n");
    kept.push_back(s.substr(a, b - a + 1));
  }
  return kept;
}

}  // namespace rbtext
