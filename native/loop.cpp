// rabadon-loop — the autonomous engine. C++17, zero deps.
//
// This is the product in one binary: a pipeline runs, a step breaks its
// contract, rabadon repairs it, re-checks against the SAME un-gameable contract,
// and continues — without stopping to ask. The three legs together:
//   reliability  every step is gated by rabadon-verify BEFORE anything flows on.
//   repair       a broken gate triggers a bounded proposer; the fix is accepted
//                ONLY if it passes the same contract. The proposer never sees or
//                edits the contract — the arbiter is a separate trusted binary.
//   reporting    every step/break/repair is emitted to the spool with its reason.
//
// Fixes the two fail-OPEN holes the diagnosis found in the old JS motor:
//   - a step with no contract now FAILS CLOSED (verify exit 2 = fatal), never
//     passes vacuously.
//   - a missing/empty acceptance contract FAILS CLOSED, never auto-passes.
//
// Remove the LLM proposer and what remains: the runner, the gate semantics via
// rabadon-verify, the bounds, the event stream. The moat test passes — the
// proposer is a replaceable part, the deterministic arbiter is the engine.
//
// Usage:  rabadon-loop <dir> <plan.json>
//   plan.json = { "steps": [ { "id","kind":"cmd"|"work","do","contract":[...] } ],
//                 "accept": [...] }
//   proposer  = env RABADON_PROPOSER (default: claude -p …), prompt on stdin,
//               run with cwd=<dir>. Swap it, the engine is unchanged.
//   exit 0 = accepted (done is measured)   exit 1 = fail-closed (nothing eclectic)

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <ctime>
#include <unistd.h>
#include <sys/stat.h>

using std::string;
using std::vector;

static string read_file(const string& p){ std::ifstream f(p,std::ios::binary); if(!f) return ""; std::stringstream ss; ss<<f.rdbuf(); return ss.str(); }
static void write_file(const string& p,const string& s){ std::ofstream f(p,std::ios::binary|std::ios::trunc); f<<s; }
static long long now_ms(){ struct timespec ts; clock_gettime(CLOCK_REALTIME,&ts); return (long long)ts.tv_sec*1000+ts.tv_nsec/1000000; }

static int shell(const string& cmd,const string& dir){ string f="cd \""+dir+"\" 2>/dev/null && "+cmd; return system(f.c_str()); }

// feed `prompt` to `cmd` on stdin, run with cwd=dir; return child exit code
static int proposer_run(const string& cmd,const string& dir,const string& prompt){
  string full="cd \""+dir+"\" && "+cmd;
  FILE* p=popen(full.c_str(),"w");
  if(!p) return -1;
  fwrite(prompt.data(),1,prompt.size(),p);
  int st=pclose(p);
  return WIFEXITED(st)?WEXITSTATUS(st):-1;
}

static string json_escape(const string& s){ string o; for(char c:s){ switch(c){ case '"':o+="\\\"";break; case '\\':o+="\\\\";break; case '\n':o+="\\n";break; case '\r':o+="\\r";break; case '\t':o+="\\t";break; default:o+=c; } } return o; }

static string obj_str(const string& j,const string& key){
  const string pat="\""+key+"\""; size_t k=j.find(pat); if(k==string::npos) return "";
  size_t c=j.find(':',k+pat.size()); if(c==string::npos) return "";
  size_t q=j.find('"',c); if(q==string::npos) return "";
  string out; for(size_t i=q+1;i<j.size();i++){ char ch=j[i]; if(ch=='\\'&&i+1<j.size()){ char n=j[++i]; out+=(n=='n')?'\n':(n=='t')?'\t':n; } else if(ch=='"') break; else out+=ch; } return out;
}

// extract the array literal ([ ... ]) that follows "key", bracket-balanced
static string extract_array(const string& j,const string& key,size_t from=0){
  const string pat="\""+key+"\""; size_t k=j.find(pat,from); if(k==string::npos) return "";
  size_t a=j.find('[',k); if(a==string::npos) return "";
  int depth=0; bool inStr=false;
  for(size_t i=a;i<j.size();i++){ char c=j[i];
    if(inStr){ if(c=='\\')i++; else if(c=='"')inStr=false; continue; }
    if(c=='"'){ inStr=true; continue; }
    if(c=='[')depth++; else if(c==']'){ depth--; if(depth==0) return j.substr(a,i-a+1); }
  }
  return "";
}

// split a JSON array of flat objects into object slices
static vector<string> split_objects(const string& arr){
  vector<string> out; int depth=0; size_t start=string::npos; bool inStr=false;
  for(size_t i=0;i<arr.size();i++){ char c=arr[i];
    if(inStr){ if(c=='\\')i++; else if(c=='"')inStr=false; continue; }
    if(c=='"'){ inStr=true; continue; }
    if(c=='{'){ if(depth==0)start=i; depth++; }
    else if(c=='}'){ depth--; if(depth==0&&start!=string::npos){ out.push_back(arr.substr(start,i-start+1)); start=string::npos; } }
  }
  return out;
}

struct Emitter {
  string spool, pipe; string run;
  void ev(const string& type,const string& extra){
    string line="{\"v\":1,\"ts\":"+std::to_string(now_ms())+",\"run\":\""+run+"\",\"pipe\":\""+pipe+"\",\"ev\":\""+type+"\""+(extra.empty()?"":","+extra)+"}\n";
    std::ofstream f(spool,std::ios::app); f<<line;
  }
};

int main(int argc,char** argv){
  if(argc<3){ fprintf(stderr,"usage: rabadon-loop <dir> <plan.json>\n"); return 2; }
  string dir=argv[1]; string plan=read_file(argv[2]);
  if(plan.empty()){ fprintf(stderr,"rabadon-loop: empty plan (fail-closed)\n"); return 2; }

  // locate the verify binary next to this one
  string self=argv[0]; size_t sl=self.rfind('/'); string bindir=sl==string::npos?".":self.substr(0,sl);
  string verify=bindir+"/rabadon-verify";

  const char* prop=getenv("RABADON_PROPOSER");
  string proposer=prop?prop:"claude -p --output-format text --permission-mode acceptEdits --allowedTools Read,Edit,Write,Bash,Grep,Glob";
  int maxRepairs=1; { const char* mr=getenv("RABADON_MAX_REPAIRS"); if(mr) maxRepairs=atoi(mr); }

  // spool
  const char* home=getenv("HOME"); const char* rd=getenv("RABADON_DIR");
  string rdir=rd?rd:(string(home?home:".")+"/.rabadon"); mkdir(rdir.c_str(),0755); mkdir((rdir+"/spool").c_str(),0755);
  char day[16]; { time_t t=time(nullptr); struct tm tmv; localtime_r(&t,&tmv); strftime(day,16,"%Y-%m-%d",&tmv); }
  string project=dir; size_t ps=project.rfind('/'); if(ps!=string::npos) project=project.substr(ps+1);
  Emitter em; em.spool=rdir+"/spool/"+string(day)+".jsonl"; em.pipe=project+":do"; em.run="loop-"+std::to_string(now_ms()%100000000)+"-"+std::to_string(getpid());

  // verify a contract array (written to a temp file) via the trusted binary.
  // exit 0 = pass, 1 = a check failed, 2 = malformed/empty = FAIL CLOSED.
  auto verify_contract=[&](const string& contractArr,string& reason)->int{
    if(contractArr.empty()){ reason="step has no contract (fail-closed)"; return 2; }
    string tmp=rdir+"/.loop-contract-"+std::to_string(now_ms())+".json"; write_file(tmp,contractArr);
    string out; { string f="\""+verify+"\" \""+dir+"\" \""+tmp+"\" 2>&1"; FILE* p=popen(f.c_str(),"r"); char buf[2048]; size_t n; while((n=fread(buf,1,sizeof buf,p))>0) out.append(buf,n); int st=pclose(p); reason=out; int rc=WIFEXITED(st)?WEXITSTATUS(st):-1; unlink(tmp.c_str()); return rc; }
  };

  string stepsArr=extract_array(plan,"steps");
  vector<string> steps=split_objects(stepsArr);
  if(steps.empty()){ fprintf(stderr,"rabadon-loop: plan has no steps (fail-closed)\n"); return 2; }

  em.ev("RUN_START","\"steps\":"+std::to_string(steps.size())+",\"bound\":{\"maxRepairsPerStep\":"+std::to_string(maxRepairs)+"}");
  fprintf(stderr,"rabadon: %zu-step pipeline, arbiter=rabadon-verify, proposer bounded to %d repair(s)/step\n",steps.size(),maxRepairs);

  for(const string& step:steps){
    string id=obj_str(step,"id"); string kind=obj_str(step,"kind"); string doWhat=obj_str(step,"do");
    string contract=extract_array(step,"contract");
    em.ev("STEP_START","\"step\":\""+json_escape(id)+"\"");

    // execute the step
    if(kind=="cmd") shell(doWhat,dir);
    else proposer_run(proposer,dir,"You are one step in a rabadon pipeline. Do EXACTLY this, nothing more:\n"+doWhat+"\nWork in the current directory, then stop.");

    // gate it
    string reason; int rc=verify_contract(contract,reason);
    int attempt=0;
    while(rc!=0 && attempt<maxRepairs){
      attempt++;
      em.ev("CHECK_FAIL","\"step\":\""+json_escape(id)+"\",\"fails\":[{\"check\":\"contract\",\"why\":\""+json_escape(reason.substr(0,200))+"\"}]");
      em.ev("REPAIR_START","\"step\":\""+json_escape(id)+"\",\"attempt\":"+std::to_string(attempt));
      fprintf(stderr,"rabadon: gate %s failed — repairing (attempt %d/%d)\n  %s",id.c_str(),attempt,maxRepairs,reason.c_str());
      proposer_run(proposer,dir,
        "You are rabadon's repair inside a pipeline. Step \""+id+"\" ("+doWhat+") failed its contract:\n"+reason+
        "\nFix the PROJECT STATE so the contract passes. Do the real work — the contract runs the code and compares behavior, so faking a file or a string will NOT pass. Smallest correct fix, nothing beyond this step.");
      rc=verify_contract(contract,reason);
      em.ev(rc==0?"REPAIR_OK":"REPAIR_FAIL","\"step\":\""+json_escape(id)+"\",\"attempt\":"+std::to_string(attempt));
    }
    if(rc!=0){
      em.ev("STOP","\"reason\":\"BLOCKED\",\"detail\":\""+json_escape(id+" would not pass its contract; repair budget spent")+"\"");
      em.ev("RUN_DONE","\"verdict\":\"CHECK_FAILED\"");
      fprintf(stderr,"rabadon: STOP — %s cannot pass. Fail-closed, nothing eclectic produced.\n%s\n",id.c_str(),reason.c_str());
      return 1;
    }
    em.ev("STEP_OK","\"step\":\""+json_escape(id)+"\"");
    fprintf(stderr,"rabadon: %s ok\n",id.c_str());
  }

  // acceptance — the task-level definition of done, fail-closed if absent
  string accept=extract_array(plan,"accept"); string reason;
  int arc=verify_contract(accept,reason);
  if(arc!=0){
    em.ev("STOP","\"reason\":\"CHECK_FAILED\",\"detail\":\""+json_escape("acceptance: "+reason.substr(0,150))+"\"");
    em.ev("RUN_DONE","\"verdict\":\"CHECK_FAILED\"");
    fprintf(stderr,"rabadon: steps passed but ACCEPTANCE failed (fail-closed):\n%s\n",reason.c_str());
    return 1;
  }
  em.ev("RUN_DONE","\"verdict\":\"PASS\"");
  fprintf(stderr,"rabadon: accept PASS — the output is the one that was asked for.\n");
  return 0;
}
