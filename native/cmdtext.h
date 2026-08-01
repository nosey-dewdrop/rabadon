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

struct Word { string text; bool quoted = false; };

struct Seg {
  string surface;          // what a regex may match: data neutralized
  vector<Word> words;      // argv, quotes off
  vector<string> nested;   // subshell / substitution bodies lifted out of it
  int group = 0;           // the shell context this command runs in
  int parent = 0;          // the context it inherited its directory from
};

struct Parsed {
  vector<Seg> segs;
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

// FOO=bar, the shell's own prefix form
inline bool is_assignment(const string& s) {
  const size_t eq = s.find('=');
  return eq != string::npos && eq > 0 && s.find('/') == string::npos &&
         (isalpha((unsigned char)s[0]) || s[0] == '_');
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
  return false;
}

// index of the real command word: skip FOO=bar assignments, then each wrapper
// with everything that wrapper consumes.
inline size_t command_index(const vector<Word>& w) {
  size_t i = 0;
  while (i < w.size()) {
    if (is_assignment(w[i].text)) { i++; continue; }
    WrapSpec spec;
    if (!wrapper_of(base_of(w[i].text), spec)) break;
    i++;
    while (i < w.size()) {
      const string& o = w[i].text;
      if (o == "--") { i++; break; }
      if (o.size() < 2 || o[0] != '-') break;
      if (o[1] == '-') {                                   // --long or --long=value
        const bool separate = o.find('=') == string::npos &&
                              spec.longVal.find("|" + o + "|") != string::npos;
        i += separate ? 2 : 1;
        continue;
      }
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

// ---------- pass 1: drop comments and heredoc BODIES ----------
// A heredoc body is the one place in a shell command where arbitrary prose sits
// with no quoting at all, which is why it produced two of the ledger's false
// refusals. `<<EOF`, `<<'EOF'`, `<<"EOF"` and the tab-stripping `<<-EOF` are all
// recognized; `<<<` is a here-STRING, a normal word, and is left alone.
inline string preprocess(const string& cmd, bool* ok, string* why) {
  *ok = true; why->clear();
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
        while (i <= n) {
          const size_t eol = cmd.find('\n', i);
          const size_t end = (eol == string::npos) ? n : eol;
          string line = cmd.substr(i, end - i);
          i = (eol == string::npos) ? n : eol + 1;
          if (pending[p].second) {
            const size_t a = line.find_first_not_of('\t');
            line = (a == string::npos) ? "" : line.substr(a);
          }
          while (!line.empty() && (line[line.size() - 1] == '\r' || line[line.size() - 1] == ' '))
            line.erase(line.size() - 1);
          if (line == pending[p].first) { closed = true; break; }
          if (eol == string::npos) break;
        }
        if (!closed) { *ok = false; *why = "heredoc <<" + pending[p].first + " never terminated"; return cmd; }
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
      if ((c == '&' || c == '|') && i + 1 < n && s[i + 1] == c) i++;
      if (hasWord) { cur.words.push_back(Word{word, wq}); word.clear(); wq = false; hasWord = false; }
      size_t a = cur.surface.find_first_not_of(" \t\r\n");
      if (a == string::npos) cur.surface.clear();
      else cur.surface = cur.surface.substr(a, cur.surface.find_last_not_of(" \t\r\n") - a + 1);
      if (!cur.surface.empty() || !cur.words.empty() || !cur.nested.empty()) out.push_back(cur);
      cur = Seg();
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
inline const string* env_lookup(const vector<std::pair<string, string> >& env, const string& n) {
  for (size_t i = env.size(); i > 0; i--) if (env[i - 1].first == n) return &env[i - 1].second;
  return NULL;
}

inline bool var_char(char c) { return isalnum((unsigned char)c) || c == '_'; }

// the expansion of one unquoted word, or false when any name is unknown
inline bool expand_word(const string& w, const vector<std::pair<string, string> >& env, string& out) {
  out.clear();
  bool any = false;
  for (size_t i = 0; i < w.size(); i++) {
    if (w[i] != '$') { out += w[i]; continue; }
    size_t a = i + 1;
    bool braced = false;
    if (a < w.size() && w[a] == '{') { braced = true; a++; }
    size_t b = a;
    while (b < w.size() && var_char(w[b])) b++;
    if (b == a) return false;                       // $(, $?, bare $ — not ours
    if (braced) { if (b >= w.size() || w[b] != '}') return false; }
    const string* v = env_lookup(env, w.substr(a, b - a));
    if (!v) return false;
    out += *v;
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

inline void apply_env(Seg& sg, vector<std::pair<string, string> >& env) {
  if (!env.empty()) {
    vector<Word> next;
    next.reserve(sg.words.size());
    for (size_t i = 0; i < sg.words.size(); i++) {
      string expanded;
      if (!sg.words[i].quoted && sg.words[i].text.find('$') != string::npos &&
          expand_word(sg.words[i].text, env, expanded)) {
        split_ws(expanded, next);
      } else {
        next.push_back(sg.words[i]);
      }
    }
    sg.words.swap(next);
  }
  // then this segment's own leading assignments join the environment
  for (size_t i = 0; i < sg.words.size(); i++) {
    const string& s = sg.words[i].text;
    if (!is_assignment(s)) break;
    const size_t eq = s.find('=');
    const string val = s.substr(eq + 1);
    if (val.find('$') != string::npos || val.find('`') != string::npos) continue;  // not literal
    env.push_back(std::make_pair(s.substr(0, eq), val));
  }
}

// ---------- the whole answer ----------
inline void emit(const string& text, int group, int parent, Parsed& out, int depth,
                 vector<std::pair<string, string> > env) {
  if (depth > 4) return;
  vector<Seg> local;
  scan(text, local);
  for (size_t i = 0; i < local.size(); i++) {
    Seg sg = local[i];
    sg.group = group;
    sg.parent = parent;
    apply_env(sg, env);
    const vector<string> nested = sg.nested;
    const vector<string> scripts = shell_scripts(sg.words);
    out.segs.push_back(sg);
    // a child is emitted right after its parent so the caller can walk the list
    // in order and still know that a `cd` in a subshell did not move the caller
    for (size_t k = 0; k < nested.size(); k++)
      emit(nested[k], out.groups++, group, out, depth + 1, env);
    for (size_t k = 0; k < scripts.size(); k++)
      emit(scripts[k], out.groups++, group, out, depth + 1, env);
  }
}

inline Parsed parse(const string& cmd) {
  Parsed p;
  bool ok = true;
  string why;
  // when preprocessing fails, `pre` comes back as the raw line: the regex
  // caller is told (degraded) and falls back, and the structural caller still
  // gets segments — the same raw text it read before this header existed.
  const string pre = preprocess(cmd, &ok, &why);
  p.degraded = !ok;
  p.why = why;
  emit(pre, 0, 0, p, 0, vector<std::pair<string, string> >());
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
