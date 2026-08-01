// cmdtext.h — the difference between a command and a string that mentions one.
//
// A deny rule is a regex, and until now it was run against the whole command
// line as typed. That reads DATA as if it were CODE. Three ways it went wrong,
// all of them out of the live ledger, none of them theoretical:
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
// This header answers one question: given a command line, what text is actually
// going to be EXECUTED? Everything else — heredoc bodies, quoted arguments
// carried as data, comments — is out of the matching area. And the things that
// do execute stay in it, because the cheapest way to make a false positive go
// away is to stop the rule from ever firing, and that deletes the product:
//
//   ; && || |          every chained command is its own surface
//   ( ... ) and $( )   a subshell is a command, not a word
//   bash -c "<str>"    the string IS a command; it is parsed and added
//   sh -c, eval        same
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
// WHEN IT CANNOT PARSE (unterminated quote, heredoc with no terminator) it says
// so instead of guessing: `degraded` comes back true, the caller falls back to
// the old whole-line behaviour, and the gate writes a PARSE_DEGRADED line into
// the ledger. Failing toward MORE refusals is the safe direction; failing there
// quietly is not.
#pragma once

#include <cctype>
#include <string>
#include <vector>

namespace rbtext {

using std::string;
using std::vector;

// whitespace that a regex must not read as a word boundary
static const char DATA_WS = '\x01';

struct Word { string text; bool quoted = false; };
struct Seg  { string surface; vector<Word> words; };

struct Surfaces {
  vector<string> texts;      // every executable surface, one per command
  bool degraded = false;     // could not be parsed; caller must fall back
  string why;
};

// ---------- small helpers (kept local so this header stands alone) ----------

inline bool ws(char c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }

inline string base_of(const string& s) {
  const size_t p = s.rfind('/');
  return p == string::npos ? s : s.substr(p + 1);
}

// index of the real command word: skip FOO=bar assignments and wrappers
inline size_t command_index(const vector<Word>& w) {
  size_t i = 0;
  while (i < w.size()) {
    const string& s = w[i].text;
    const size_t eq = s.find('=');
    const bool assign = eq != string::npos && eq > 0 && s.find('/') == string::npos &&
                        (isalpha((unsigned char)s[0]) || s[0] == '_');
    const string b = base_of(s);
    if (assign || b == "sudo" || b == "doas" || b == "env" || b == "command" ||
        b == "nohup" || b == "time" || b == "exec" || b == "timeout" || b == "stdbuf") { i++; continue; }
    break;
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

// ---------- pass 2: segments, and the surface of each ----------
inline void scan(const string& s, vector<Seg>& out, int depth);

// a `$( )` or backtick body sitting inside double quotes still RUNS. Its
// whitespace must not be neutralized with the quoted text around it, so it is
// lifted out and parsed as the command it is.
inline void lift(const string& body, vector<Seg>& out, int depth) {
  if (depth > 4) return;
  scan(body, out, depth + 1);
}

inline void scan(const string& s, vector<Seg>& out, int depth) {
  if (depth > 4) return;
  Seg cur;
  string word;
  bool wq = false, hasWord = false;
  vector<Seg> lifted;

  const size_t n = s.size();
  for (size_t i = 0; i < n; i++) {
    const char c = s[i];

    if (c == '\\' && i + 1 < n) {
      const char d = s[++i];
      if (d == ' ' || d == '\t' || d == '\n') { cur.surface += DATA_WS; word += ' '; }
      else { cur.surface += '\\'; cur.surface += d; word += d; }
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
          if (e == '$' || e == '`' || e == '"' || e == '\\' || e == '\n') {
            cur.surface += ws(e) ? DATA_WS : e; word += e;
          } else { cur.surface += '\\'; cur.surface += e; word += '\\'; word += e; }
          k += 2; continue;
        }
        if (s[k] == '$' && k + 1 < n && s[k + 1] == '(') {
          const size_t e = match_paren(s, k + 1);
          if (e == string::npos) { cur.surface += s[k]; word += s[k]; k++; continue; }
          lift(s.substr(k + 2, e - k - 2), lifted, depth);
          k = e + 1; continue;
        }
        if (s[k] == '`') {
          const size_t e = s.find('`', k + 1);
          if (e == string::npos) { cur.surface += s[k]; word += s[k]; k++; continue; }
          lift(s.substr(k + 1, e - k - 1), lifted, depth);
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
      if (!cur.surface.empty() || !cur.words.empty()) out.push_back(cur);
      cur = Seg();
      continue;
    }

    if (c == ' ' || c == '\t' || c == '\r') {
      if (hasWord) { cur.words.push_back(Word{word, wq}); word.clear(); wq = false; hasWord = false; }
      cur.surface += ' ';
      continue;
    }

    // outside quotes a `$( )` body is already whitespace-correct: it stays
    // inline, exactly as the old whole-line matcher saw it
    cur.surface += c; word += c; hasWord = true;
  }
  if (hasWord) cur.words.push_back(Word{word, wq});
  {
    size_t a = cur.surface.find_first_not_of(" \t\r\n");
    if (a == string::npos) cur.surface.clear();
    else cur.surface = cur.surface.substr(a, cur.surface.find_last_not_of(" \t\r\n") - a + 1);
    if (!cur.surface.empty() || !cur.words.empty()) out.push_back(cur);
  }
  for (size_t i = 0; i < lifted.size(); i++) out.push_back(lifted[i]);
}

// ---------- pass 3: a string a SHELL is about to run is a command ----------
// `bash -c "git push --force origin main"` is the whole force-push, spelled as
// one quoted word. Neutralizing it as data and stopping there would be the
// bypass. It is parsed and appended instead. `python3 -c` is not on this list on
// purpose: python is not a shell, and its argument really is data.
inline bool is_shell(const string& name) {
  return name == "bash" || name == "sh" || name == "zsh" || name == "dash" ||
         name == "ksh" || name == "ash";
}

inline void expand_shell_strings(vector<Seg>& segs, int depth) {
  if (depth > 4) return;
  const size_t n = segs.size();
  for (size_t k = 0; k < n; k++) {
    const vector<Word>& w = segs[k].words;
    const size_t ci = command_index(w);
    if (ci >= w.size()) continue;
    const string name = base_of(w[ci].text);
    vector<string> scripts;
    if (is_shell(name)) {
      for (size_t j = ci + 1; j < w.size(); j++) {
        const string& a = w[j].text;
        if (a.size() >= 2 && a[0] == '-' && a[1] != '-' && a.find('c') != string::npos) {
          if (j + 1 < w.size()) scripts.push_back(w[j + 1].text);
          break;
        }
        if (a.empty() || a[0] != '-') break;  // an operand: a script FILE, not a string
      }
    } else if (name == "eval") {
      string joined;
      for (size_t j = ci + 1; j < w.size(); j++) {
        if (!joined.empty()) joined += " ";
        joined += w[j].text;
      }
      if (!joined.empty()) scripts.push_back(joined);
    }
    for (size_t x = 0; x < scripts.size(); x++) {
      vector<Seg> sub;
      scan(scripts[x], sub, depth + 1);
      expand_shell_strings(sub, depth + 1);
      for (size_t y = 0; y < sub.size(); y++) segs.push_back(sub[y]);
    }
  }
}

// ---------- the whole answer ----------
inline Surfaces exec_surfaces(const string& cmd) {
  Surfaces r;
  bool ok = true;
  string why;
  const string pre = preprocess(cmd, &ok, &why);
  if (!ok) { r.degraded = true; r.why = why; return r; }
  vector<Seg> segs;
  scan(pre, segs, 0);
  expand_shell_strings(segs, 0);
  for (size_t i = 0; i < segs.size(); i++)
    if (!segs[i].surface.empty()) r.texts.push_back(segs[i].surface);
  return r;
}

}  // namespace rbtext
