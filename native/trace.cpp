// rabadon-trace — the REPORTING leg. C++17, zero deps.
//
// A pipeline run leaves a deterministic event stream in the spool (RUN_START,
// STEP_START, CHECK_FAIL, REPAIR_START, REPAIR_OK/FAIL, STOP, STEP_OK, RUN_DONE).
// The repair events also carry the model's own byte-exact accounting (tokens,
// usd, duration_ms), fused in by rabadon-loop from the proposer's stream-json
// result event. Nothing here calls an LLM or estimates anything: every number
// printed already exists in the ledger. Remove the LLM from the whole system and
// this renderer still turns the same spool into the same trace — the moat test.
//
// It renders the one thing Langfuse cannot: not just "here is what your run
// cost", but "a door-less deep bug was CAUGHT the moment it was born, REPAIRED,
// the fix PROVEN against the real suite (and a fake fix REJECTED), so steps
// downstream never ran on a broken base." Catch + fix + proof + cost, one view.
//
// Usage:  rabadon-trace [spool.jsonl | dir]  [--run <id>] [--last] [--no-color]
//   source: a path arg (a .jsonl file, or a dir -> its newest *.jsonl), else
//   $RABADON_DIR/spool, else ~/.rabadon/spool (newest day file).

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

using std::string;
using std::vector;

// ---------- io ----------
static string read_file(const string& p){
  FILE* f=fopen(p.c_str(),"rb"); if(!f) return "";
  string out; char buf[65536]; size_t n;
  while((n=fread(buf,1,sizeof buf,f))>0) out.append(buf,n);
  fclose(f); return out;
}
static bool ends_with(const string& s,const char* suf){ size_t n=strlen(suf); return s.size()>=n && s.compare(s.size()-n,n,suf)==0; }

// newest .jsonl inside a directory (by mtime), "" if none
static string newest_jsonl(const string& dir){
  DIR* d=opendir(dir.c_str()); if(!d) return "";
  string best; long long bestT=-1;
  while(struct dirent* e=readdir(d)){
    string n=e->d_name; if(!ends_with(n,".jsonl")) continue;
    string full=dir+"/"+n; struct stat st;
    if(stat(full.c_str(),&st)==0 && (long long)st.st_mtime>bestT){ bestT=st.st_mtime; best=full; }
  }
  closedir(d); return best;
}

// ---------- minimal json field readers over one line ----------
static long long ll_field(const string& line,const char* key){
  size_t p=line.find(key); if(p==string::npos) return 0;
  return atoll(line.c_str()+p+strlen(key));
}
static string str_field(const string& line,const char* key){  // key ends at the opening quote, e.g. "ev":"
  size_t p=line.find(key); if(p==string::npos) return ""; p+=strlen(key);
  string out;
  for(size_t i=p;i<line.size();i++){ char c=line[i];
    if(c=='\\'&&i+1<line.size()){ char n=line[++i]; out+=(n=='n')?'\n':(n=='t')?'\t':n; }
    else if(c=='"') break; else out+=c; }
  return out;
}

// ---------- model ----------
struct Ev {
  string ev, step, why, reason, detail, verdict, model;
  long long ts=0, tokens=0, usd_e6=0, dur_ms=0;
};
struct Run {
  string id, pipe, goal;
  long long firstTs=0, lastTs=0; int declaredSteps=0;
  vector<Ev> evs;
};

// ---------- formatting ----------
static string commafy(long long v){
  string s=std::to_string(v<0?-v:v), out; int c=0;
  for(int i=(int)s.size()-1;i>=0;i--){ out+=s[i]; if(++c%3==0&&i>0) out+=','; }
  if(v<0) out+='-';
  string r(out.rbegin(),out.rend()); return r;
}
static string fmt_usd(long long e6){ char b[32]; snprintf(b,sizeof b,"$%.4f",(double)e6/1e6); return b; }
static string fmt_ms(long long ms){
  if(ms<=0) return "0s";
  long long s=(ms+500)/1000; long long h=s/3600; s%=3600; long long m=s/60; s%=60;
  char b[32];
  if(h>0) snprintf(b,sizeof b,"%lldh%02lldm",h,m);
  else if(m>0) snprintf(b,sizeof b,"%lldm%02llds",m,s);
  else snprintf(b,sizeof b,"%llds",s);
  return b;
}
static string short_model(const string& m){
  if(m.empty()) return "?";
  string s=m; const string pre="claude-";
  if(s.compare(0,pre.size(),pre)==0) s=s.substr(pre.size());
  size_t br=s.find('['); if(br!=string::npos) s=s.substr(0,br);
  return s;
}
// project name from a "proj:do" / "proj:session" pipe label
static string project_of(const string& pipe){
  size_t c=pipe.rfind(':');
  return c==string::npos?pipe:pipe.substr(0,c);
}
// from a verify failure blob: a short, clean descriptor of what broke.
// testsuite -> the named failing test(s); otherwise the message after the
// "FAIL <kind> [..]: " prefix (e.g. "protected content was modified").
static string failing_test(const string& why){
  size_t p=why.find("failing: ");
  if(p!=string::npos){ size_t s=p+9,e=why.find('\n',s); if(e==string::npos)e=why.size(); string t=why.substr(s,e-s);
    if(t.size()>58) t=t.substr(0,58)+"…"; return t; }
  string w=why; size_t nl=w.find('\n'); if(nl!=string::npos) w=w.substr(0,nl);
  size_t colon=w.find("]: ");
  if(colon!=string::npos) w=w.substr(colon+3);
  else { size_t sp=w.find(": "); if(w.rfind("FAIL ",0)==0 && sp!=string::npos) w=w.substr(sp+2); }
  if(w.size()>58) w=w.substr(0,58)+"…";
  return w;
}
static string check_kind(const string& why){
  if(why.find("testsuite")!=string::npos)   return "testsuite";
  if(why.find("forbidden")!=string::npos)   return "forbidden";
  if(why.find("differential")!=string::npos)return "differential";
  if(why.find("no contract")!=string::npos) return "no-contract";
  return "contract";
}

// ---------- palette ----------
struct Pal { const char *dim,*grn,*amb,*red,*bold,*rst; };
static Pal COLOR{ "\x1b[2m","\x1b[32m","\x1b[33m","\x1b[31m","\x1b[1m","\x1b[0m" };
static Pal PLAIN{ "","","","","","" };

// ---------- per-step reduction ----------
struct Node {
  int no=0; string id; bool ok=false, caught=false, repaired=false, rejected=false;
  string why; long long tokens=0, usd_e6=0, dur_ms=0; string model;
  long long startTs=0, endTs=0;
};

static void render_run(const Run& r, const Pal& C, string& out){
  vector<Node> nodes; Node* cur=nullptr;
  string stopReason, verdict, runModel; long long tok=0, usd=0;
  for(const Ev& e: r.evs){
    if(e.ev=="STEP_START"){ nodes.push_back({}); cur=&nodes.back(); cur->no=(int)nodes.size(); cur->id=e.step; cur->startTs=e.ts; }
    else if(e.ev=="CHECK_FAIL" && cur){ cur->caught=true; if(cur->why.empty()) cur->why=e.why; }
    else if((e.ev=="REPAIR_OK"||e.ev=="REPAIR_FAIL") && cur){
      if(e.ev=="REPAIR_OK") cur->repaired=true; else cur->rejected=true;
      cur->tokens+=e.tokens; cur->usd_e6+=e.usd_e6; if(e.dur_ms>cur->dur_ms) cur->dur_ms=e.dur_ms;
      if(!e.model.empty()){ cur->model=e.model; if(runModel.empty()) runModel=e.model; }
      tok+=e.tokens; usd+=e.usd_e6;
    }
    else if(e.ev=="STEP_OK" && cur){ cur->ok=true; cur->endTs=e.ts; }
    else if(e.ev=="STOP"){ if(stopReason.empty()) stopReason=e.reason; if(cur&&cur->endTs==0) cur->endTs=e.ts; }
    else if(e.ev=="RUN_DONE"){ verdict=e.verdict; }
  }

  int N = r.declaredSteps>0 ? r.declaredSteps : (int)nodes.size();
  int firstCaught=0; for(const Node& n: nodes) if(n.caught){ firstCaught=n.no; break; }

  // widest id for column alignment (cap so the metrics stay on screen)
  size_t idw=6; for(const Node& n: nodes) idw=std::max(idw,n.id.size()); if(idw>26) idw=26;
  auto pad=[&](const string& s)->string{ string t=s; if(t.size()>idw) t=t.substr(0,idw-1)+"…"; while(t.size()<idw) t+=' '; return t; };

  // ---- header ----
  char h[512];
  string dur=fmt_ms(r.lastTs-r.firstTs);
  string proj=project_of(r.pipe);
  string mdl=short_model(runModel);
  string cost = usd>0 ? fmt_usd(usd) : "$0";
  string toks = tok>0 ? commafy(tok)+" tok" : "0 tok";
  snprintf(h,sizeof h,"%srabadon trace%s  %s%.8s%s · %s · %s · %s · %s · %s · claude -p\n",
           C.bold,C.rst, C.bold, r.id.c_str(), C.rst,
           proj.c_str(), mdl.c_str(), dur.c_str(), toks.c_str(), cost.c_str());
  out+=h;
  if(!r.goal.empty()){ out+="  "; out+=C.dim; out+="görev: \""+r.goal+"\""; out+=C.rst; out+="\n"; }
  out+="\n";

  // ---- steps ----
  for(const Node& n: nodes){
    char line[600];
    string metrics;
    if(n.tokens>0){ char m[128]; snprintf(m,sizeof m,"claude -p  %s  %s  %s",(commafy(n.tokens)+" tok").c_str(),fmt_usd(n.usd_e6).c_str(),fmt_ms(n.dur_ms).c_str()); metrics=m; }
    else metrics="—";
    long long sdur = (n.endTs>n.startTs)? n.endTs-n.startTs : 0;

    if(!n.caught){
      snprintf(line,sizeof line,"  %s▸%s %2d  %s   %s✓ pass%s      %s   %s%s%s\n",
        C.dim,C.rst, n.no, pad(n.id).c_str(), C.grn,C.rst, metrics.c_str(), C.dim, fmt_ms(sdur).c_str(), C.rst);
      out+=line;
      continue;
    }
    // caught (the repair's own byte-exact token/$/time is the metrics; the step
    // wall-time equals it here, so we don't print it twice)
    (void)sdur;
    snprintf(line,sizeof line,"  %s▾%s %2d  %s   %s⚠ YAKALANDI%s  %s\n",
      C.amb,C.rst, n.no, pad(n.id).c_str(), C.amb,C.rst, metrics.c_str());
    out+=line;

    string kind=check_kind(n.why), test=failing_test(n.why);
    snprintf(line,sizeof line,"     %s├%s %s%s ✗%s %s%s%s     %s◀── ağ BURADA yakaladı (o AN)%s\n",
      C.dim,C.rst, C.red,kind.c_str(),C.rst, C.red,test.c_str(),C.rst, C.amb,C.rst);
    out+=line;

    if(n.repaired){
      snprintf(line,sizeof line,"     %s│%s    %ssuite RED (%s)%s → REPAIR → %sgerçek suite GREEN%s → %sREPAIR_OK ✓%s\n",
        C.dim,C.rst, C.red,test.c_str(),C.rst, C.grn,C.rst, C.grn,C.rst);
      out+=line;
      snprintf(line,sizeof line,"     %s└%s %s   %s✓ tamirden sonra yeşil%s\n",
        C.dim,C.rst, pad(n.id).c_str(), C.grn,C.rst);
      out+=line;
    } else { // rejected -> fail-closed
      snprintf(line,sizeof line,"     %s│%s    %ssahte fix (testi neuter'lar)%s → %sforbidden-sha%s → %sREPAIR_FAIL ✗%s\n",
        C.dim,C.rst, C.red,C.rst, C.bold,C.rst, C.red,C.rst);
      out+=line;
      snprintf(line,sizeof line,"     %s└%s %sSTOP: %s%s — fail-closed, sonraki adımlar HİÇ koşmadı%s\n",
        C.dim,C.rst, C.red, stopReason.empty()?"BLOCKED":stopReason.c_str(), C.rst, "");
      out+=line;
    }
  }

  // ---- footer ----
  int caught=0,repaired=0,rejected=0; string caughtNos;
  for(const Node& n: nodes){ if(n.caught){ caught++; if(!caughtNos.empty())caughtNos+=","; caughtNos+=std::to_string(n.no);} if(n.repaired)repaired++; if(n.rejected)rejected++; }

  out+="  ";
  out+=C.dim; out+="──────────────────────────────────────────────────────────────"; out+=C.rst; out+="\n";
  char f[512];
  snprintf(f,sizeof f,"  YAKALANAN %s%d%s%s · TAMİR %s%d%s · REDDEDİLEN sahte %s%d%s · verdict: %s%s%s\n",
    C.amb,caught,C.rst, caught?(" (adım "+caughtNos+")").c_str():"",
    C.grn,repaired,C.rst, C.red,rejected,C.rst,
    (verdict=="PASS")?C.grn:C.red, verdict.empty()?"?":verdict.c_str(), C.rst);
  out+=f;

  if(caught){
    string saved;
    if(rejected){
      snprintf(f,sizeof f,"  %skurtarılan:%s adım %d'de yakalandı → STOP, adım %d–%d KÖR tabanda HİÇ koşmadı · param cepte   %s◀── Langfuse'da bu satır YOK%s\n",
        C.bold,C.rst, firstCaught, firstCaught+1, N, C.dim,C.rst);
    } else {
      snprintf(f,sizeof f,"  %skurtarılan:%s adım %d'de yakalandı+tamir → adım %d–%d TEMİZ tabanda ilerledi (bug 10. adıma sıçramadı) · tamir maliyeti %s, %s tok   %s◀── Langfuse'da bu satır YOK%s\n",
        C.bold,C.rst, firstCaught, firstCaught+1, N, fmt_usd(usd).c_str(), commafy(tok).c_str(), C.dim,C.rst);
    }
    out+=f;
  }
}

int main(int argc,char** argv){
  string source, wantRun; bool onlyLast=false, color=isatty(fileno(stdout));
  for(int i=1;i<argc;i++){
    string a=argv[i];
    if(a=="--run"&&i+1<argc){ wantRun=argv[++i]; }
    else if(a=="--last"){ onlyLast=true; }
    else if(a=="--no-color"){ color=false; }
    else if(a=="--color"){ color=true; }
    else if(source.empty()){ source=a; }
  }
  // resolve source file
  string file; struct stat st;
  if(!source.empty() && stat(source.c_str(),&st)==0){
    if(S_ISREG(st.st_mode)) file=source; else file=newest_jsonl(source);
  }
  if(file.empty()){
    const char* rd=getenv("RABADON_DIR");
    if(rd&&rd[0]) file=newest_jsonl(string(rd)+"/spool");
  }
  if(file.empty()){
    const char* home=getenv("HOME");
    if(home&&home[0]) file=newest_jsonl(string(home)+"/.rabadon/spool");
  }
  if(file.empty()){ fprintf(stderr,"rabadon-trace: no spool found (pass a .jsonl or a dir)\n"); return 1; }

  const string body=read_file(file);
  // group events by run, first-seen order
  vector<Run> runs; vector<string> order;
  auto find_run=[&](const string& id)->Run&{
    for(Run& r: runs) if(r.id==id) return r;
    runs.push_back({}); runs.back().id=id; return runs.back();
  };
  size_t ls=0;
  while(ls<body.size()){
    size_t le=body.find('\n',ls); if(le==string::npos) le=body.size();
    string line=body.substr(ls,le-ls); ls=le+1;
    if(line.empty()) continue;
    string ev=str_field(line,"\"ev\":\""); if(ev.empty()) continue;
    string run=str_field(line,"\"run\":\""); if(run.empty()) continue;
    Run& R=find_run(run);
    Ev e; e.ev=ev; e.ts=ll_field(line,"\"ts\":");
    e.step=str_field(line,"\"step\":\"");
    if(ev=="CHECK_FAIL") e.why=str_field(line,"\"why\":\"");
    if(ev=="STOP"){ e.reason=str_field(line,"\"reason\":\""); e.detail=str_field(line,"\"detail\":\""); }
    if(ev=="RUN_DONE") e.verdict=str_field(line,"\"verdict\":\"");
    if(ev=="REPAIR_OK"||ev=="REPAIR_FAIL"){
      e.tokens=ll_field(line,"\"tokens\":"); e.usd_e6=ll_field(line,"\"usd_e6\":");
      e.dur_ms=ll_field(line,"\"dur_ms\":"); e.model=str_field(line,"\"model\":\"");
    }
    if(ev=="RUN_START"){
      // "steps": either an int (loop) or an array (session). goal is optional.
      size_t sp=line.find("\"steps\":");
      if(sp!=string::npos){ char nx=line[sp+8]; if(nx>='0'&&nx<='9') R.declaredSteps=(int)ll_field(line,"\"steps\":"); }
      R.goal=str_field(line,"\"goal\":\"");
      if(R.goal.empty()){ string g=str_field(line,"\"steps\":[\""); if(g.rfind("goal:",0)==0) R.goal=g.substr(5); }
      if(!R.goal.empty()){ size_t z=R.goal.find_first_not_of(" "); if(z!=string::npos) R.goal=R.goal.substr(z); }
    }
    if(R.pipe.empty()) R.pipe=str_field(line,"\"pipe\":\"");
    if(R.firstTs==0||e.ts<R.firstTs) R.firstTs=e.ts;
    if(e.ts>R.lastTs) R.lastTs=e.ts;
    R.evs.push_back(std::move(e));
  }

  const Pal& C = color?COLOR:PLAIN;
  string out;
  char hdr[256];
  snprintf(hdr,sizeof hdr,"%s%s  (%zu run%s)%s\n\n",C.dim,file.c_str(),runs.size(),runs.size()==1?"":"s",C.rst);
  out+=hdr;

  size_t shown=0;
  for(size_t i=0;i<runs.size();i++){
    const Run& r=runs[i];
    if(!wantRun.empty() && r.id.find(wantRun)==string::npos) continue;
    if(onlyLast && i!=runs.size()-1) continue;
    render_run(r,C,out);
    out+="\n";
    shown++;
  }
  if(shown==0) out+="  (no matching run)\n";
  fwrite(out.data(),1,out.size(),stdout);
  return 0;
}
