// rabadon-do — task in, gate-verified output out. C++17, zero deps.
//
// Two moves, both honest about where the LLM sits:
//   PLAN   one claude -p call decomposes the task into a pipeline whose every
//          step carries an un-gameable contract (differential / forbidden where
//          behavior must hold; cmd/fileExists/fileContains otherwise). The plan
//          is a PROPOSAL — it is enforced, not trusted.
//   RUN    exec rabadon-loop, which gates every step with rabadon-verify and
//          repairs-then-continues, bounded, fail-closed.
//
// Remove the LLM and what remains: the loop, the verify arbiter, the bounds,
// the spool. The planner is the one replaceable LLM part; everything that
// decides pass/fail is deterministic C++.
//
// Usage:  rabadon-do "<task>" [dir]

#include <cstdio>
#include <cstdlib>
#include <string>
#include <fstream>
#include <unistd.h>
#include <sys/stat.h>
#include "cli_help.h"

using std::string;

static void write_file(const string& p,const string& s){ std::ofstream f(p,std::ios::binary|std::ios::trunc); f<<s; }

static string run_capture(const string& cmd){
  string out; char buf[8192]; FILE* p=popen(cmd.c_str(),"r"); if(!p) return "";
  size_t n; while((n=fread(buf,1,sizeof buf,p))>0) out.append(buf,n); pclose(p); return out;
}

// feed prompt to `claude -p` on stdin, return its stdout
static string claude(const string& prompt,const string& dir){
  string tmp=dir+"/.rabadon/.plan-prompt.txt"; write_file(tmp,prompt);
  string cmd="cd \""+dir+"\" && claude -p --output-format text < \""+tmp+"\" 2>/dev/null";
  string out=run_capture(cmd); unlink(tmp.c_str()); return out;
}

// strip ``` fences if the model wrapped the JSON
static string unfence(string s){
  size_t a=s.find('{'); size_t b=s.rfind('}');
  if(a!=string::npos && b!=string::npos && b>=a) return s.substr(a,b-a+1);
  return s;
}

static const char* kHelp =
  "rabadon-do — one task in, a gate-verified pipeline out.\n"
  "One model call decomposes the task into steps whose every contract is checked\n"
  "by machine; rabadon-loop then runs it, repairs what fails, and refuses a fix\n"
  "that only pretends to pass.\n"
  "\n"
  "usage: rabadon-do \"<task>\" [dir]\n"
  "\n"
  "  \"<task>\"   what you want done, in one sentence.\n"
  "  [dir]      the project it runs in (default: the current directory).\n"
  "  -h, --help this screen. costs nothing — no model call is made.\n"
  "\n"
  "environment:\n"
  "  RABADON_PROPOSER    the coding-agent command the loop calls for repairs.\n"
  "  RABADON_MAX_REPAIRS repair attempts per step (default 1).\n"
  "\n"
  "example:\n"
  "  rabadon-do \"add a --json flag to the stats command\" ~/src/myrepo\n";

int main(int argc,char** argv){
  // FIRST statement, before the repo walk and before claude() — `rabadon-do
  // --help` used to take the flag as the task and open a paid model call, so
  // the one word a new user types first HUNG and cost money.
  rb_help(argc, argv, kHelp);

  if(argc<2){ fprintf(stderr,"usage: rabadon-do \"<task>\" [dir]\n  run `rabadon-do --help`\n"); return 2; }
  string task=argv[1];
  // a task is a sentence, never a flag. without this, a mistyped option became
  // the prompt and was billed.
  if(rb_is_flag(task.c_str())) rb_unknown_flag("rabadon-do", task.c_str());
  string dir=argc>2?argv[2]:".";
  { char buf[4096]; if(dir=="."){ if(getcwd(buf,sizeof buf)) dir=buf; } }
  mkdir((dir+"/.rabadon").c_str(),0755);

  // real repo structure (depth-limited, not just 40 top names) so the planner
  // can actually see what it must contract over
  string tree=run_capture("cd \""+dir+"\" && (git ls-files 2>/dev/null | head -200 || find . -maxdepth 3 -type f -not -path './.git/*' | head -200)");

  string self=argv[0]; size_t sl=self.rfind('/'); string bindir=sl==string::npos?".":self.substr(0,sl);

  const string prompt=
    "You are rabadon's planner. Decompose the task into a pipeline whose EVERY step is verifiable BY MACHINE. Return ONLY JSON, no prose, no fences:\n"
    "{ \"steps\": [ { \"id\":\"s1\", \"kind\":\"cmd\"|\"work\", \"do\":\"<cmd: literal shell command | work: one narrow instruction for a coding agent>\",\n"
    "  \"contract\":[ <one or more checks> ] } ], \"accept\":[ <task-level definition of done> ] }\n\n"
    "Check types (prefer the un-gameable ones — a repair must not be able to fake them):\n"
    "  {\"type\":\"differential\",\"run\":\"<shell cmd>\",\"expect\":\"<exact stdout that proves correct behavior>\"}  // runs the code, compares behavior; use to PIN behavior\n"
    "  {\"type\":\"forbidden\",\"path\":\"<file>\",\"sha\":\"<leave empty, rabadon fills>\"}  // a file the work must NOT change\n"
    "  {\"type\":\"cmd\",\"run\":\"<shell cmd>\",\"passPattern\":\"<string that appears only on success; omit for exit-0>\"}\n"
    "  {\"type\":\"fileExists\",\"path\":\"<file>\"}   {\"type\":\"fileContains\",\"path\":\"<file>\",\"pattern\":\"<text>\"}\n\n"
    "Laws: 1-6 steps. EVERY step and the accept[] get at least one check. Prefer differential whenever the task has observable behavior (a function's output, a command's result) — that is what makes the gate un-gameable. Use RELATIVE paths in fileExists/fileContains/forbidden and relative commands in run (they execute with the project dir as cwd); do NOT use absolute paths. Steps run in: "+dir+"\n"
    "Repo files:\n"+tree.substr(0,4000)+"\n\nTHE TASK: "+task;

  fprintf(stderr,"rabadon do: planning (one model call)…\n");
  string raw=claude(prompt,dir);
  string plan=unfence(raw);
  if(plan.find("\"steps\"")==string::npos){ fprintf(stderr,"rabadon do: planner returned no usable pipeline.\n%s\n",raw.substr(0,300).c_str()); return 1; }
  string planPath=dir+"/.rabadon/do-plan.json";
  write_file(planPath,plan);
  fprintf(stderr,"rabadon do: plan written to .rabadon/do-plan.json — running under the gate.\n");

  // hand off to the loop: it gates every step with rabadon-verify, repairs, continues
  string loop=bindir+"/rabadon-loop";
  execl(loop.c_str(),loop.c_str(),dir.c_str(),planPath.c_str(),(char*)nullptr);
  // if execl returns, fall back to system()
  string cmd="\""+loop+"\" \""+dir+"\" \""+planPath+"\"";
  return system(cmd.c_str())==0?0:1;
}
