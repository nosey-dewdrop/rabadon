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
// SECOND FACE — VERIFIED ROUTING (same engine, cost instead of reliability):
//   RABADON_TIERS="haiku,opus" makes each work step run on the CHEAP model
//   first. The arbiter — the same rabadon-verify, the same project contract —
//   decides. Passed: the cheap answer is not hoped-for, it is PROVEN, and the
//   difference is money kept. Failed: the identical step is re-run one tier up
//   and the escalation is recorded with its reason. Routers (Helicone, Portkey,
//   OpenRouter, Martian) route cheap and hope; none of them owns a correctness
//   oracle, so none can say which cheap answer held. Take the LLM out and what
//   remains is the thing that decides: a deterministic arbiter plus a measured
//   two-arm ledger. Unset RABADON_TIERS = the old single-model behavior, byte
//   for byte.
//
// Usage:  rabadon-loop <dir> <plan.json>
//   plan.json = { "steps": [ { "id","kind":"cmd"|"work","do","contract":[...] } ],
//                 "accept": [...] }
//   proposer  = env RABADON_PROPOSER (default: claude -p …), prompt on stdin,
//               run with cwd=<dir>. Swap it, the engine is unchanged.
//   tiers     = env RABADON_TIERS (cheap→expensive, comma separated). The tier
//               for one attempt reaches the proposer as RABADON_MODEL.
//   arm       = env RABADON_ARM ("routed"/"control") — labels the run so the
//               trace can put two MEASURED arms of the same plan side by side.
//   exit 0 = accepted (done is measured)   exit 1 = fail-closed (nothing eclectic)

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <ctime>
#include <unistd.h>
#include <sys/stat.h>
#include "cli_help.h"
#include "chain.h"   // the ledger's one writer: chained line + .head sidecar

using std::string;
using std::vector;

static string read_file(const string& p){ std::ifstream f(p,std::ios::binary); if(!f) return ""; std::stringstream ss; ss<<f.rdbuf(); return ss.str(); }
static void write_file(const string& p,const string& s){ std::ofstream f(p,std::ios::binary|std::ios::trunc); f<<s; }
static long long now_ms(){ struct timespec ts; clock_gettime(CLOCK_REALTIME,&ts); return (long long)ts.tv_sec*1000+ts.tv_nsec/1000000; }

static int shell(const string& cmd,const string& dir){ string f="cd \""+dir+"\" 2>/dev/null && "+cmd; return system(f.c_str()); }

// feed `prompt` to `cmd` on stdin, run with cwd=dir; return child exit code.
// `model` (may be empty) is handed to the proposer as RABADON_MODEL — that is
// the whole routing mechanism on this side: the tier is data, not a code path.
static int proposer_run(const string& cmd,const string& dir,const string& prompt,const string& model=""){
  string env = model.empty() ? "" : ("RABADON_MODEL=\""+model+"\" ");
  string full="cd \""+dir+"\" && "+env+cmd;
  FILE* p=popen(full.c_str(),"w");
  if(!p) return -1;
  fwrite(prompt.data(),1,prompt.size(),p);
  int st=pclose(p);
  return WIFEXITED(st)?WEXITSTATUS(st):-1;
}

// "haiku,opus" -> {"haiku","opus"}; empty/unset -> {""} = one attempt on the
// account default, i.e. exactly what the loop did before routing existed.
static vector<string> split_csv(const string& s){
  vector<string> out; string cur;
  for(char c:s){ if(c==','){ if(!cur.empty()) out.push_back(cur); cur.clear(); } else if(c!=' ') cur+=c; }
  if(!cur.empty()) out.push_back(cur);
  if(out.empty()) out.push_back("");
  return out;
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
  // the loop writes into the same day file as the gate, so it chains through
  // the same writer: an unchained append here would read to `rabadon audit`
  // exactly like a line an attacker stripped, and it took the file's lock with
  // nobody holding it.
  void ev(const string& type,const string& extra){
    string body="{\"v\":1,\"ts\":"+std::to_string(now_ms())+",\"run\":\""+run+"\",\"pipe\":\""+pipe+"\",\"ev\":\""+type+"\""+(extra.empty()?"":","+extra);
    rbchain::append(spool, body);
  }
};

static const char* kHelp =
  "rabadon-loop — run a plan under the arbiter.\n"
  "Every step is checked by rabadon-verify before the next one starts. A failed\n"
  "check triggers a bounded repair, and the repair must pass the SAME check to be\n"
  "kept — so a fix that only neuters the test is refused and the run stops.\n"
  "An empty or unreadable plan fails CLOSED.\n"
  "\n"
  "usage: rabadon-loop <dir> <plan.json>\n"
  "\n"
  "  <dir>        the project the steps execute in.\n"
  "  <plan.json>  {\"steps\":[{\"id\",\"kind\",\"do\",\"contract\":[...]}],\"accept\":[...]}\n"
  "               rabadon-do writes one to <dir>/.rabadon/do-plan.json.\n"
  "  -h, --help   this screen.\n"
  "\n"
  "environment:\n"
  "  RABADON_TIERS       cheap-model-first routing, e.g. \"haiku,opus\".\n"
  "  RABADON_PROPOSER    the coding-agent command called for a repair.\n"
  "  RABADON_MAX_REPAIRS repair attempts per step (default 1).\n"
  "  RABADON_DIR         where the run is spooled (default ~/.rabadon).\n"
  "\n"
  "example:\n"
  "  rabadon-loop ~/src/myrepo ~/src/myrepo/.rabadon/do-plan.json\n";

int main(int argc,char** argv){
  // `rabadon-loop --help` used to hit the arity check and exit 2 with a usage
  // line that named no flag, no environment variable and no example.
  rb_help(argc, argv, kHelp);
  // this binary takes two paths and no options, so any flag is a typo. naming
  // it beats the old bare usage line, which never said WHICH word was wrong.
  for(int i=1;i<argc;i++) if(rb_is_flag(argv[i])) rb_unknown_flag("rabadon-loop", argv[i]);

  if(argc<3){ fprintf(stderr,"usage: rabadon-loop <dir> <plan.json>\n  run `rabadon-loop --help`\n"); return 2; }
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
  // UTC, because the day file has ONE name, and gmtime is the name every other
  // writer uses (gate.cpp, repair.cpp, sandbox.cpp, the JS bus's toISOString).
  // localtime_r here made the Emitter comment above false east of Greenwich
  // after midnight: gate and loop opened two different files, one session in
  // two chains, and every reader that tails "today" saw half of it.
  // native/ledger_day_test.sh holds this at any hour of any day.
  char day[16]; { time_t t=time(nullptr); struct tm tmv; gmtime_r(&t,&tmv); strftime(day,16,"%Y-%m-%d",&tmv); }
  string project=dir; size_t ps=project.rfind('/'); if(ps!=string::npos) project=project.substr(ps+1);
  Emitter em; em.spool=rdir+"/spool/"+string(day)+".jsonl"; em.pipe=project+":do"; em.run="loop-"+std::to_string(now_ms()%100000000)+"-"+std::to_string(getpid());

  // verify a contract array (written to a temp file) via the trusted binary.
  // exit 0 = pass, 1 = a check failed, 2 = malformed/empty = FAIL CLOSED.
  auto verify_contract=[&](const string& contractArr,string& reason)->int{
    if(contractArr.empty()){ reason="step has no contract (fail-closed)"; return 2; }
    string tmp=rdir+"/.loop-contract-"+std::to_string(now_ms())+".json"; write_file(tmp,contractArr);
    string out; { string f="\""+verify+"\" \""+dir+"\" \""+tmp+"\" 2>&1"; FILE* p=popen(f.c_str(),"r"); char buf[2048]; size_t n; while((n=fread(buf,1,sizeof buf,p))>0) out.append(buf,n); int st=pclose(p); reason=out; int rc=WIFEXITED(st)?WEXITSTATUS(st):-1; unlink(tmp.c_str()); return rc; }
  };

  // After EVERY proposer call (a step attempt as well as a repair), the
  // llm-proposer.sh drops the model's own {"type":"result"} stream-json event
  // (byte-exact usage + total_cost_usd + duration_ms) into a sidecar. Fuse those
  // numbers into the event so the spool is a self-contained deterministic
  // ledger — the trace renderer reads token/$/time straight from here, never a
  // transcript. This is also what makes the routing claim measured rather than
  // estimated: no price table, no per-model arithmetic, just the two arms' own
  // accounting. Absent sidecar (text-mode/scripted proposer) -> empty extra ->
  // the trace shows "—", never a fabricated number.
  string metricsPath=rdir+"/.proposer-metrics.json";
  auto attempt_metrics=[&]()->string{
    string m=read_file(metricsPath); unlink(metricsPath.c_str());
    if(m.empty()) return "";
    size_t up=m.find("\"usage\":");
    auto tok_after=[&](const char* key)->long long{ if(up==string::npos) return 0; size_t k=m.find(key,up); if(k==string::npos) return 0; return atoll(m.c_str()+k+strlen(key)); };
    long long in=tok_after("\"input_tokens\":"), out=tok_after("\"output_tokens\":");
    long long cc=tok_after("\"cache_creation_input_tokens\":"), cr=tok_after("\"cache_read_input_tokens\":");
    long long tok=in+out+cc+cr;
    double usd=0; { size_t k=m.find("\"total_cost_usd\":"); if(k!=string::npos) usd=atof(m.c_str()+k+strlen("\"total_cost_usd\":")); }
    long long usd_e6=(long long)(usd*1e6+0.5);
    long long dur=0; { size_t k=m.find("\"duration_ms\":"); if(k!=string::npos) dur=atoll(m.c_str()+k+strlen("\"duration_ms\":")); }
    // model name is the KEY of the modelUsage map: "modelUsage":{"claude-opus-4-8[1m]":{..}
    string model; { size_t k=m.find("\"modelUsage\":{\""); if(k!=string::npos){ size_t s=k+strlen("\"modelUsage\":{\""),e=m.find('"',s); if(e!=string::npos) model=m.substr(s,e-s);} }
    string x=",\"tokens\":"+std::to_string(tok)+",\"in\":"+std::to_string(in)+",\"out\":"+std::to_string(out)
            +",\"usd_e6\":"+std::to_string(usd_e6)+",\"dur_ms\":"+std::to_string(dur);
    if(!model.empty()) x+=",\"model\":\""+json_escape(model)+"\"";
    return x;
  };

  string stepsArr=extract_array(plan,"steps");
  vector<string> steps=split_objects(stepsArr);
  if(steps.empty()){ fprintf(stderr,"rabadon-loop: plan has no steps (fail-closed)\n"); return 2; }

  // the tier ladder, cheap -> expensive. one entry (or unset) = no routing.
  vector<string> tiers; { const char* t=getenv("RABADON_TIERS"); tiers=split_csv(t?t:""); }
  const bool routed = tiers.size()>1;
  const string topTier = tiers.back();
  string tiersCsv; for(size_t i=0;i<tiers.size();i++){ if(i)tiersCsv+=","; tiersCsv+=tiers[i]; }
  const char* armEnv=getenv("RABADON_ARM"); string arm=armEnv?armEnv:"";

  string goal=obj_str(plan,"goal");
  em.ev("RUN_START",(goal.empty()?"":"\"goal\":\""+json_escape(goal)+"\",")+"\"steps\":"+std::to_string(steps.size())
        +(arm.empty()?"":",\"arm\":\""+json_escape(arm)+"\"")
        +(tiersCsv.empty()?"":",\"tiers\":\""+json_escape(tiersCsv)+"\"")
        +",\"bound\":{\"maxRepairsPerStep\":"+std::to_string(maxRepairs)+"}");
  if(routed) fprintf(stderr,"rabadon: %zu-step pipeline, arbiter=rabadon-verify, tiers=%s (cheap first, proven or escalated), %d repair(s)/step at the top tier\n",steps.size(),tiersCsv.c_str(),maxRepairs);
  else       fprintf(stderr,"rabadon: %zu-step pipeline, arbiter=rabadon-verify, proposer bounded to %d repair(s)/step\n",steps.size(),maxRepairs);

  for(const string& step:steps){
    string id=obj_str(step,"id"); string kind=obj_str(step,"kind"); string doWhat=obj_str(step,"do");
    string contract=extract_array(step,"contract");
    em.ev("STEP_START","\"step\":\""+json_escape(id)+"\""+(routed?",\"tiers\":\""+json_escape(tiersCsv)+"\"":""));

    string reason; int rc=0; size_t ti=0;

    // ---- the tier ladder -------------------------------------------------
    // Run the step on the cheapest tier, put the result in front of the SAME
    // arbiter, and only climb when the arbiter says no. A cmd step has no model
    // in it, so it executes once and skips straight to the repair budget.
    if(kind=="cmd"){
      shell(doWhat,dir);
      rc=verify_contract(contract,reason);
      ti=tiers.size()-1;
    } else {
      for(ti=0; ti<tiers.size(); ti++){
        const string& model=tiers[ti];
        if(ti==0){
          proposer_run(proposer,dir,"You are one step in a rabadon pipeline. Do EXACTLY this, nothing more:\n"+doWhat+"\nWork in the current directory, then stop.",model);
        } else {
          // escalation: the identical step, one tier up, told what the arbiter
          // rejected. The contract itself is never shown — the judge stays out
          // of the proposer's reach on every tier.
          proposer_run(proposer,dir,
            "You are one step in a rabadon pipeline, running as the ESCALATION tier. A cheaper model attempted this step and the deterministic arbiter REJECTED its result.\nStep: "+doWhat+
            "\nWhat the arbiter reported:\n"+reason+
            "\nDo the step properly in the current directory so those checks pass for real — the arbiter runs the code and compares behavior, so faking a file or a string will NOT pass. Then stop.",model);
        }
        string m=attempt_metrics();
        em.ev("STEP_TRY","\"step\":\""+json_escape(id)+"\",\"tier\":"+std::to_string(ti+1)
              +(model.empty()?"":",\"tier_name\":\""+json_escape(model)+"\"")+m);
        rc=verify_contract(contract,reason);
        if(rc==0) break;
        em.ev("CHECK_FAIL","\"step\":\""+json_escape(id)+"\",\"tier\":"+std::to_string(ti+1)
              +(model.empty()?"":",\"tier_name\":\""+json_escape(model)+"\"")
              +",\"fails\":[{\"check\":\"contract\",\"why\":\""+json_escape(rbchain::utf8_clip(reason,600))+"\"}]");
        if(ti+1<tiers.size()){
          em.ev("ESCALATE","\"step\":\""+json_escape(id)+"\",\"from\":\""+json_escape(tiers[ti])+"\",\"to\":\""+json_escape(tiers[ti+1])+"\",\"why\":\""+json_escape(rbchain::utf8_clip(reason,300))+"\"");
          fprintf(stderr,"rabadon: %s failed the arbiter on %s — escalating to %s\n",id.c_str(),tiers[ti].c_str(),tiers[ti+1].c_str());
        } else {
          ti=tiers.size()-1; break;   // top tier failed: the repair budget takes over
        }
      }
      if(ti>=tiers.size()) ti=tiers.size()-1;
    }

    // the repair budget picks up where the ladder stopped, always at the top
    // tier — a repair IS an escalation. The ladder already reported the failure
    // it stopped on, so it is never logged twice: one CHECK_FAIL per distinct
    // rejection, which keeps the ledger countable.
    bool failReported = (rc!=0 && kind!="cmd");
    int attempt=0;
    while(rc!=0 && attempt<maxRepairs){
      attempt++;
      if(!failReported) em.ev("CHECK_FAIL","\"step\":\""+json_escape(id)+"\",\"fails\":[{\"check\":\"contract\",\"why\":\""+json_escape(rbchain::utf8_clip(reason,600))+"\"}]");
      failReported=false;
      em.ev("REPAIR_START","\"step\":\""+json_escape(id)+"\",\"attempt\":"+std::to_string(attempt)+(topTier.empty()?"":",\"tier_name\":\""+json_escape(topTier)+"\""));
      fprintf(stderr,"rabadon: gate %s failed — repairing (attempt %d/%d)\n  %s",id.c_str(),attempt,maxRepairs,reason.c_str());
      proposer_run(proposer,dir,
        "You are rabadon's repair inside a pipeline. Step \""+id+"\" ("+doWhat+") failed its contract:\n"+reason+
        "\nFix the PROJECT STATE so the contract passes. Do the real work — the contract runs the code and compares behavior, so faking a file or a string will NOT pass. Smallest correct fix, nothing beyond this step.",topTier);
      string rmetrics=attempt_metrics();
      rc=verify_contract(contract,reason);
      em.ev(rc==0?"REPAIR_OK":"REPAIR_FAIL","\"step\":\""+json_escape(id)+"\",\"attempt\":"+std::to_string(attempt)
            +(topTier.empty()?"":",\"tier_name\":\""+json_escape(topTier)+"\"")+rmetrics);
    }
    if(rc!=0){
      em.ev("STOP","\"reason\":\"BLOCKED\",\"detail\":\""+json_escape(id+" would not pass its contract; repair budget spent")+"\"");
      em.ev("RUN_DONE","\"verdict\":\"CHECK_FAILED\"");
      fprintf(stderr,"rabadon: STOP — %s cannot pass. Fail-closed, nothing eclectic produced.\n%s\n",id.c_str(),reason.c_str());
      return 1;
    }
    // which tier actually carried this step is the routing ledger's core fact:
    // tier 1 = proven cheap (money kept), higher = the arbiter made us climb.
    em.ev("STEP_OK","\"step\":\""+json_escape(id)+"\",\"tier\":"+std::to_string(ti+1)
          +(tiers[ti].empty()?"":",\"tier_name\":\""+json_escape(tiers[ti])+"\""));
    if(routed) fprintf(stderr,"rabadon: %s ok — proven on %s (tier %zu/%zu)\n",id.c_str(),tiers[ti].c_str(),ti+1,tiers.size());
    else       fprintf(stderr,"rabadon: %s ok\n",id.c_str());
  }

  // acceptance — the task-level definition of done, fail-closed if absent
  string accept=extract_array(plan,"accept"); string reason;
  int arc=verify_contract(accept,reason);
  if(arc!=0){
    em.ev("STOP","\"reason\":\"CHECK_FAILED\",\"detail\":\""+json_escape("acceptance: "+rbchain::utf8_clip(reason,150))+"\"");
    em.ev("RUN_DONE","\"verdict\":\"CHECK_FAILED\"");
    fprintf(stderr,"rabadon: steps passed but ACCEPTANCE failed (fail-closed):\n%s\n",reason.c_str());
    return 1;
  }
  em.ev("RUN_DONE","\"verdict\":\"PASS\"");
  fprintf(stderr,"rabadon: accept PASS — the output is the one that was asked for.\n");
  return 0;
}
