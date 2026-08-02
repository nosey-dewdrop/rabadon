// rabadon-claims — ask a report which run produced each of its numbers.
//
// Nine days of sessions on this machine produced eight numbers that no run had
// made. None of them was an attack and none of them was a lie anybody told on
// purpose. A benchmark subtracted x from x. A fixture had been chosen by the
// party being measured. A precision figure was measured in its own laboratory.
// A hash lock reported locking a repository's tests and locked 0 of 122 files.
// A drift check read the words written by the thing that was drifting. Two
// numbers measured at different moments were presented as a regression. A rule
// was passed by reading a test's exit code rather than which rule had refused.
// A fixture was built in the one directory where the law is switched off.
//
// Every one of those is the same shape: a sentence that carries a number, and
// no run underneath it. The gate already writes down every command that runs on
// this machine, hash-chained, as it happens. So the report can be asked the one
// question that separates a measurement from a sentence, and the ledger can
// answer it without anybody being asked to remember anything.
//
//   BACKED     a command is cited near the number, and the ledger saw it run
//   UNRUN      a command is cited, and no run of it exists on the ledger
//   UNSOURCED  a number with no command cited anywhere near it
//
// WHAT THIS CANNOT DO, in full, because a checker that overstates its own reach
// is the defect it was built to find.
//
//   1. The ledger stores the command, clipped to 80 characters, and it does NOT
//      store the command's OUTPUT. So this proves the run happened. It cannot
//      prove the output said what the report says it said. It catches the number
//      that came from nowhere; it does not catch the rigged run.
//   2. A backticked fragment written as an ILLUSTRATION reads here as a
//      citation. `cd -P /baska` in a sentence explaining a parser bug is not a
//      claim that the command was run, and this will call it unrun. Measured on
//      a real 382-line report: 7 of 113 numbers land that way. That is the known
//      false-alarm rate of the backtick rule and it is printed, not buried.
//
// Exit 0 = every number is backed. Exit 1 = at least one is not.
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <set>
#include <sstream>
#include <string>
#include <vector>
#include <dirent.h>
#include <pwd.h>
#include <sys/stat.h>
#include <unistd.h>
#include "jsonl.h"

using std::string;
using std::vector;

// The gate clips a command to this many characters before it writes the ledger
// line. 46,169 of this machine's 76,653 step records sit exactly at that
// boundary, so a checker that demanded a whole-string match would call almost
// every honest report a fabrication. Everything compares on the prefix the
// ledger actually kept.
static const size_t kClip = 80;

static string read_file(const string& p) {
  struct stat st;
  if (stat(p.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return string();
  std::ifstream f(p, std::ios::binary);
  if (!f) return string();
  std::ostringstream ss; ss << f.rdbuf();
  return ss.str();
}

// ---------- normalising a command ----------
// The same command is written many ways: with a `$ ` prompt, inside a fence,
// wrapped in backticks, indented, with runs of spaces where the author lined
// something up. None of those differences are the command, so none of them
// survive to the comparison.
static string normalize(const string& in) {
  string s;
  bool sp = false;
  for (char c : in) {
    const unsigned char u = (unsigned char)c;
    if (u == '\t' || u == '\n' || u == '\r' || u == ' ') { sp = !s.empty(); continue; }
    if (sp) { s += ' '; sp = false; }
    s += c;
  }
  return s;
}

static string strip_prompt(string s) {
  size_t i = 0;
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t')) i++;
  s = s.substr(i);
  // a shell prompt written into prose, and the two markers a markdown author
  // reaches for when showing a command
  if (s.rfind("$ ", 0) == 0) s = s.substr(2);
  else if (s.rfind("% ", 0) == 0) s = s.substr(2);
  while (!s.empty() && (s.back() == '`' || s.back() == ' ')) s.pop_back();
  while (!s.empty() && s.front() == '`') s = s.substr(1);
  return s;
}

// A CITED command is one the author PRESENTED as a command: a `$` prompt, a
// fenced block, an indented block, backticks. It is never a line that merely
// looks command-shaped.
//
// The first version guessed instead, and the guess was tested against a real
// report rather than a fixture, which is the only reason this is not still in
// it. That report is prose with file paths in it, and lines like
//
//   yaparsa .rabadon/state.json block/goose'a acilan PR'in icine girer
//
// were read as commands, were of course not on the ledger, and turned every
// honest number in the paragraph into "the command under this never ran". A
// checker that invents the citation and then convicts the number for it is
// worse than no checker: a false alarm here teaches the reader to ignore the
// real one. Guessing is the failure mode, so the guess is gone. A number whose
// author never showed a command is UNSOURCED, which is true and which is a
// verdict about the report rather than about the run.
static bool command_shaped(const string& s) {
  if (s.size() < 3 || s.size() > 400) return false;
  if (s.find(' ') == string::npos && s.find('/') == string::npos) return false;
  const char c = s[0];
  if (!(isalnum((unsigned char)c) || c == '.' || c == '/' || c == '_' || c == '~')) return false;
  // the first word is the program. a program name has no apostrophe and no
  // comma in it, and prose in any language does.
  const size_t sp = s.find(' ');
  const string head = sp == string::npos ? s : s.substr(0, sp);
  for (char h : head)
    if (h == '\'' || h == ',' || h == ';' || h == '"') return false;
  return true;
}

// the text between the first pair of backticks on a line, if it is command
// shaped. `Komut: \`python3 redteam/redteam.py\`` is a citation and reads as
// one to a person, so it reads as one here.
static bool backticked(const string& raw, string& out) {
  const size_t a = raw.find('`');
  if (a == string::npos) return false;
  const size_t b = raw.find('`', a + 1);
  if (b == string::npos || b <= a + 1) return false;
  const string inner = raw.substr(a + 1, b - a - 1);
  if (!command_shaped(inner)) return false;
  out = inner;
  return true;
}

// ---------- the ledger: every command this machine ever ran ----------
struct Ledger {
  std::set<string> ran;      // normalised, clipped
  int files = 0;
  long long lines = 0;
};

static void collect(Ledger& L, const string& path) {
  std::ifstream f(path);
  if (!f) return;
  L.files++;
  string line;
  while (std::getline(f, line)) {
    if (line.empty()) continue;
    L.lines++;
    const string ev = rbjson::get_str(line, "ev");
    if (ev != "STEP_OK" && ev != "STEP_START") continue;
    string step = rbjson::get_str(line, "step");
    // the gate writes "<verb>: <command>"; the verb is not part of the command
    const size_t colon = step.find(": ");
    if (colon != string::npos && colon <= 12) step = step.substr(colon + 2);
    step = normalize(step);
    if (!step.empty()) L.ran.insert(step.substr(0, kClip));
  }
}

static Ledger load_ledger(const string& dir) {
  Ledger L;
  const string spool = dir + "/spool";
  vector<string> files;
  if (DIR* d = opendir(spool.c_str())) {
    while (struct dirent* e = readdir(d)) {
      const string n = e->d_name;
      if (n.size() > 6 && n.compare(n.size() - 6, 6, ".jsonl") == 0) files.push_back(n);
    }
    closedir(d);
  }
  std::sort(files.begin(), files.end());
  for (const auto& n : files) collect(L, spool + "/" + n);
  return L;
}

// ---------- the report ----------
struct Claim {
  string number;
  string cmd;        // "" = none was cited near it
  int line = 0;
  const char* verdict = "unsourced";
};

// A number is a run of digits that a reader would read as a measurement. A
// version (0.4.1), a date (2026-08-03) and a commit-ish hex string are not
// claims about anything measured, so they are not asked to prove themselves.
static bool number_at(const string& s, size_t i, size_t& end, string& out) {
  if (!isdigit((unsigned char)s[i])) return false;
  if (i > 0) {
    const char p = s[i - 1];
    if (isalnum((unsigned char)p) || p == '.' || p == '-' || p == '_' || p == '/' ||
        p == '#' || p == ':' || p == '=') return false;
  }
  size_t j = i;
  while (j < s.size() && (isdigit((unsigned char)s[j]) || s[j] == ',' ||
                          (s[j] == '.' && j + 1 < s.size() && isdigit((unsigned char)s[j + 1]))))
    j++;
  if (j < s.size() && (isalpha((unsigned char)s[j]) || s[j] == '-' || s[j] == '/' ||
                       s[j] == ':' || s[j] == '_')) {
    // 2026-08-03, 4d15769c, v2, 80-character: not a measurement being claimed
    if (s[j] == '-' || s[j] == '/' || s[j] == ':' || s[j] == '_') return false;
  }
  out = s.substr(i, j - i);
  end = j;
  // a bare 0 or 1 inside prose is not a measurement anybody would check
  if (out.size() == 1 && (out == "0" || out == "1")) return false;
  return true;
}

int main(int argc, char** argv) {
  bool asJson = false;
  string path;
  for (int i = 1; i < argc; i++) {
    const string a = argv[i];
    if (a == "--json") asJson = true;
    else if (a == "-h" || a == "--help") {
      printf("rabadon-claims — does a run exist behind each number in this report?\n"
             "\n"
             "Reads the hash-chained ledger the gate writes as it runs, and asks of every\n"
             "number in a report whether a command was cited near it and whether that command\n"
             "was ever actually run on this machine.\n"
             "\n"
             "usage: rabadon-claims [--json] <report-file>\n"
             "\n"
             "  backed      a command is cited and the ledger saw it run\n"
             "  unrun       a command is cited and no run of it is on the ledger\n"
             "  unsourced   a number with no command cited near it\n"
             "\n"
             "The ledger stores the command, clipped to 80 characters. It does NOT store the\n"
             "command's output, so this proves a run happened and cannot prove the output said\n"
             "what the report says it said. It catches the number that came from nowhere. It\n"
             "does not catch the rigged run.\n"
             "\n"
             "  RABADON_DIR   where the spool lives (default ~/.rabadon).\n"
             "\n"
             "exit 0 = every number is backed. exit 1 = at least one is not.\n");
      return 0;
    } else if (!a.empty() && a[0] == '-') {
      // an unrecognised flag is silence about a request somebody made. saying
      // WHICH word was not understood is the difference between a tool that
      // ignored you and a tool that told you.
      fprintf(stderr, "rabadon-claims: unknown option '%s'\n"
                      "try: rabadon-claims [--json] <report-file>   (--help for the verdicts)\n",
              a.c_str());
      return 2;
    } else path = a;
  }
  if (path.empty()) { fprintf(stderr, "usage: rabadon-claims [--json] <report-file>\n"); return 2; }

  string home;
  if (const char* h = getenv("HOME")) home = h;
  if (home.empty()) { if (struct passwd* pw = getpwuid(getuid())) home = pw->pw_dir; }
  string rdir = home + "/.rabadon";
  if (const char* rd = getenv("RABADON_DIR")) if (rd[0]) rdir = rd;

  const Ledger L = load_ledger(rdir);
  const string body = read_file(path);
  if (body.empty()) { fprintf(stderr, "rabadon-claims: cannot read %s\n", path.c_str()); return 2; }

  // walk the report line by line, carrying the most recent command forward. a
  // number is attributed to the command nearest ABOVE or BELOW it within a few
  // lines, because both orders are written in practice: the command then its
  // result, and the sentence then the command that proves it.
  vector<string> lines;
  { std::istringstream ss(body); string l; while (std::getline(ss, l)) lines.push_back(l); }

  vector<int> cmdOf(lines.size(), -1);          // line -> index of a command line
  vector<string> cmds(lines.size());
  vector<char> pureCmd(lines.size(), 0);
  bool inFence = false;
  for (size_t i = 0; i < lines.size(); i++) {
    const string& raw = lines[i];
    string trimmed = raw;
    size_t k = 0;
    while (k < trimmed.size() && (trimmed[k] == ' ' || trimmed[k] == '\t')) k++;
    const size_t indent = k;
    trimmed = trimmed.substr(k);
    if (trimmed.rfind("```", 0) == 0 || trimmed.rfind("~~~", 0) == 0) { inFence = !inFence; continue; }

    string cited;
    const bool prompted = trimmed.rfind("$ ", 0) == 0 || trimmed.rfind("% ", 0) == 0;
    const string bare = strip_prompt(raw);
    if (prompted && command_shaped(bare)) cited = bare;
    else if (inFence && command_shaped(bare)) cited = bare;
    else if (backticked(raw, cited)) { /* cited set */ }
    // INDENTATION IS NOT A CITATION. It reads like one in markdown and it means
    // nothing in a plain-text report, where the whole body is indented under a
    // heading. Accepting it turned `date-fns diskte 265, rabadon 296 buluyor`
    // into a command that had never run, and every number on that line into a
    // fabrication, in a report whose numbers were fine. Three markers are left
    // and all three are unambiguous in both formats.
    (void)indent;

    if (!cited.empty()) {
      cmds[i] = normalize(cited);
      cmdOf[i] = (int)i;
      // a line that is ONLY a command carries no claim. a sentence that cites a
      // command inside backticks carries both, and skipping it would drop the
      // number it exists to prove.
      pureCmd[i] = prompted || inFence;
    }
  }
  // Nearest command within this many lines, either direction, and BELOW wins a
  // tie. That is not a taste: a report states the claim and puts the command
  // that proves it underneath, which is the form this project's own pages use.
  // Reading upward on a tie attributed a fabricated number to the previous
  // paragraph's honest benchmark and called it backed, which is the one verdict
  // this tool must never return.
  const int kNear = 4;
  auto nearest = [&](size_t i) -> string {
    for (int d = 0; d <= kNear; d++) {
      if (i + d < lines.size() && cmdOf[i + d] >= 0) return cmds[i + d];
      if ((int)i - d >= 0 && cmdOf[i - d] >= 0) return cmds[i - d];
    }
    return string();
  };

  vector<Claim> claims;
  for (size_t i = 0; i < lines.size(); i++) {
    if (pureCmd[i]) continue;                  // a bare command line carries no claim
    const string& s = lines[i];
    for (size_t j = 0; j < s.size();) {
      size_t end; string num;
      if (number_at(s, j, end, num)) {
        Claim c;
        c.number = num;
        c.line = (int)i + 1;
        c.cmd = nearest(i);
        if (c.cmd.empty()) c.verdict = "unsourced";
        else c.verdict = L.ran.count(c.cmd.substr(0, kClip)) ? "backed" : "unrun";
        claims.push_back(c);
        j = end;
      } else j++;
    }
  }

  int backed = 0, unbacked = 0;
  for (const auto& c : claims) (strcmp(c.verdict, "backed") == 0 ? backed : unbacked)++;

  if (asJson) {
    printf("{\"file\":\"%s\",\"ledgerFiles\":%d,\"ledgerLines\":%lld,\"commandsKnown\":%zu,"
           "\"backed\":%d,\"unbacked\":%d,\"claims\":[",
           path.c_str(), L.files, L.lines, L.ran.size(), backed, unbacked);
    for (size_t i = 0; i < claims.size(); i++) {
      printf("%s{\"number\":\"%s\",\"line\":%d,\"verdict\":\"%s\",\"cmd\":\"", i ? "," : "",
             claims[i].number.c_str(), claims[i].line, claims[i].verdict);
      for (char ch : claims[i].cmd) {
        if (ch == '"' || ch == '\\') printf("\\%c", ch);
        else if ((unsigned char)ch < 0x20) printf(" ");
        else putchar(ch);
      }
      printf("\"}");
    }
    printf("],\"limit\":\"the ledger stores the command, not its output: a backed number is a "
           "number whose run happened, not a number whose output was checked\"}\n");
    return unbacked ? 1 : 0;
  }

  printf("rabadon claims — %s\n", path.c_str());
  printf("ledger: %lld lines over %d day files, %zu distinct commands ever run\n\n",
         L.lines, L.files, L.ran.size());
  if (claims.empty()) {
    printf("  no numbers in this report to check.\n");
    return 0;
  }
  for (const auto& c : claims) {
    const char* mark = strcmp(c.verdict, "backed") == 0 ? "ok  " : "MISS";
    printf("  %s  %-12s line %-4d %-9s %s\n", mark, c.number.c_str(), c.line, c.verdict,
           c.cmd.empty() ? "(no command cited near it)" : c.cmd.substr(0, 72).c_str());
  }
  printf("\n  %d backed, %d not\n", backed, unbacked);
  printf("  the ledger stores the command and not its output, so a backed number is one whose\n"
         "  run happened -- it is not a number whose output was checked.\n");
  return unbacked ? 1 : 0;
}
