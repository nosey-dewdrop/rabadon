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
#include "cli_help.h"
#include "jsonl.h"
#include "drill.h"

using std::string;
using std::vector;

// drill.h's header says "both readers of the spool call the same code" and names
// rabadon-stats and rabadon-export. There are THREE readers. This file carried
// no copy of the four rules at all, so the exact 18 events of a self-run on pipe
// do-test:do rendered "CAUGHT 2 · REPAIRED 2 · verdict: PASS" plus the money
// line, while `rabadon usage` answered "no events in this window" and `rabadon
// export --otlp` emitted 0 spans over the same bytes. README calls the exclusion
// load-bearing — a tool that counts its own self-tests as catches is worthless —
// and trace is the surface that gets screenshotted into a pitch, so this is
// where the false number does the most damage. One predicate, three readers.
static const char* kDrillLabel = "rabadon's own drill — excluded from every number";

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

// ---------- json field readers over one line (jsonl.h) ----------
// These matched the literal bytes `"ev":"`. SPEC §2 fixes the ledger as
// single-line JSON and fixes no byte layout, so a spool from a stock serializer
// (`"ev": "RUN_START"`) yielded an empty ev on line 428, every line was skipped
// by `if(ev.empty()) continue;`, and this renderer printed `(0 runs)` over a
// perfectly good stream. Same defect as audit's false TAMPER verdict, quieter.
static long long ll_field(const string& line,const char* key){
  return (long long)rbjson::get_num(line,key);
}
static string str_field(const string& line,const char* key){  // top-level only
  return rbjson::get_str(line,key);
}
// The two reads that are genuinely NOT top level: `why` lives inside
// fails[{check,why}] and the session goal inside steps[0]. Scanned at any depth,
// whitespace-tolerant, so a stock serializer reads the same as rabadon's own.
static string nested_str(const string& line,const char* key,bool inArray=false){
  const string pat=string("\"")+key+"\"";
  size_t p=line.find(pat); if(p==string::npos) return "";
  p=rbjson::skip_ws(line,p+pat.size());
  if(p>=line.size()||line[p]!=':') return "";
  p=rbjson::skip_ws(line,p+1);
  if(inArray){ if(p>=line.size()||line[p]!='[') return ""; p=rbjson::skip_ws(line,p+1); }
  string out;
  if(rbjson::scan_string(line,p,&out)==string::npos) return "";
  return out;
}

// ---------- model ----------
struct Ev {
  string ev, step, why, reason, detail, verdict, model, tierName, from, to, repairKind;
  long long ts=0, tokens=0, usd_e6=0, dur_ms=0; int tier=0;
};
struct Run {
  string id, pipe, goal, arm, tiers;
  long long firstTs=0, lastTs=0; int declaredSteps=0;
  // set once, from drill.h, after the whole file has been read: this run is
  // rabadon exercising itself, so none of its catches are catches.
  bool drill=false;
  vector<Ev> evs;
};
// what one arm of a routed A/B costs, filled while its run renders
struct ArmTotal { string arm, tiers, verdict; long long usd_e6=0, tokens=0; int cheapProven=0, escalated=0, steps=0; bool seen=false; };

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
  // drop a trailing release date (…-4-5-20251001 -> …-4-5) so the tier column
  // stays narrow enough for the numbers to line up
  size_t d=s.rfind('-');
  if(d!=string::npos && s.size()-d==9 && s.find_first_not_of("0123456789",d+1)==string::npos) s=s.substr(0,d);
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

// A drill run is still rendered — you asked for this run by id, and printing
// nothing looks like a broken tool — but it is labelled before the first number
// so no screenshot of it can be read as a production catch.
static void drill_banner(const Run& r, const Pal& C, string& out){
  if(!r.drill) return;
  out+="  "; out+=C.amb; out+="⚑ "; out+=kDrillLabel;
  if(!r.pipe.empty()){ out+="  ("; out+=r.pipe; out+=")"; }
  out+=C.rst; out+="\n";
}

// ---------- per-step reduction ----------
struct Node {
  int no=0; string id; bool ok=false, caught=false, repaired=false, rejected=false;
  string why; long long tokens=0, usd_e6=0, dur_ms=0; string model;
  long long startTs=0, endTs=0;
  // routing side: what the cheap attempt cost, whether we had to climb, and
  // which tier finally carried the step.
  bool escalated=false; int wonTier=0;
  string firstTier, wonTierName, escFrom, escTo;
  long long cheapUsd_e6=0, cheapTok=0;
  long long topUsd_e6=0, topTok=0, topDur=0;   // what the escalation tier itself cost
};

// ---------- routed view ----------
// Rendered only for runs that declared a tier ladder. Every number here comes
// from the STEP_TRY/REPAIR events the loop fused from the model's own result
// event — this renderer never prices a token itself.
static void render_routed(const Run& r, const Pal& C, string& out, ArmTotal& tot){
  vector<Node> nodes; Node* cur=nullptr;
  string verdict, stopReason; long long usd=0, tok=0;
  for(const Ev& e: r.evs){
    if(e.ev=="STEP_START"){ nodes.push_back({}); cur=&nodes.back(); cur->no=(int)nodes.size(); cur->id=e.step; cur->startTs=e.ts; }
    else if(e.ev=="STEP_TRY" && cur){
      usd+=e.usd_e6; tok+=e.tokens;
      cur->usd_e6+=e.usd_e6; cur->tokens+=e.tokens; if(e.dur_ms>cur->dur_ms) cur->dur_ms=e.dur_ms;
      string label = !e.model.empty()? short_model(e.model) : e.tierName;
      if(e.tier==1){ cur->firstTier=label; cur->cheapUsd_e6=e.usd_e6; cur->cheapTok=e.tokens; }
      else { cur->topUsd_e6+=e.usd_e6; cur->topTok+=e.tokens; if(e.dur_ms>cur->topDur) cur->topDur=e.dur_ms; }
      cur->wonTierName=label;   // last attempt seen; corrected by STEP_OK below
    }
    else if(e.ev=="CHECK_FAIL" && cur){ cur->caught=true; if(cur->why.empty()) cur->why=e.why; }
    else if(e.ev=="ESCALATE" && cur){ cur->escalated=true; cur->escFrom=e.from; cur->escTo=e.to; }
    else if((e.ev=="REPAIR_OK"||e.ev=="REPAIR_FAIL") && cur){
      if(e.repairKind.empty()){ if(e.ev=="REPAIR_OK") cur->repaired=true; else cur->rejected=true; }
      usd+=e.usd_e6; tok+=e.tokens; cur->usd_e6+=e.usd_e6; cur->tokens+=e.tokens;
      if(!e.model.empty()) cur->wonTierName=short_model(e.model);
    }
    else if(e.ev=="STEP_OK" && cur){ cur->ok=true; cur->endTs=e.ts; cur->wonTier=e.tier;
      if(!e.tierName.empty() && cur->wonTierName.empty()) cur->wonTierName=e.tierName; }
    else if(e.ev=="STOP"){ if(stopReason.empty()) stopReason=e.reason; }
    else if(e.ev=="RUN_DONE"){ verdict=e.verdict; }
  }

  size_t idw=6; for(const Node& n: nodes) idw=std::max(idw,n.id.size()); if(idw>26) idw=26;
  auto pad=[&](const string& s)->string{ string t=s; if(t.size()>idw) t=t.substr(0,idw-1)+"…"; while(t.size()<idw) t+=' '; return t; };

  char h[600];
  string armLabel = r.arm.empty()? "" : r.arm;
  snprintf(h,sizeof h,"%srabadon trace%s  %s%.8s%s · %s · %stier: %s%s · %s · %s · %s\n",
    C.bold,C.rst, C.bold, r.id.c_str(), C.rst, project_of(r.pipe).c_str(),
    C.bold, r.tiers.c_str(), C.rst,
    armLabel.empty()?"—":armLabel.c_str(),
    fmt_ms(r.lastTs-r.firstTs).c_str(), (usd>0?fmt_usd(usd):"$0").c_str());
  out+=h;
  if(!r.goal.empty()){ out+="  "; out+=C.dim; out+="goal: \""+r.goal+"\""; out+=C.rst; out+="\n"; }
  drill_banner(r,C,out);
  out+="\n";

  // a control arm has ONE tier: nothing there is "cheap", and calling it that
  // would flatter the comparison. One ladder = one wording, and it is plain.
  const bool ladder = r.tiers.find(',')!=string::npos;

  int cheapProven=0, escalated=0;
  for(const Node& n: nodes){
    char line[700];
    string metrics = n.tokens>0 ? (commafy(n.tokens)+" tok  "+fmt_usd(n.usd_e6)+"  "+fmt_ms(n.dur_ms)) : string("—");
    // the verdict column is padded by hand: these strings are UTF-8, so printf
    // field widths count bytes and would ragged the whole table.
    if(!n.escalated){
      if(n.ok && n.wonTier<=1) cheapProven++;
      snprintf(line,sizeof line,"  %s▸%s %2d  %s   %s%s%s  %-12s %s\n",
        C.dim,C.rst, n.no, pad(n.id).c_str(), C.grn,
        ladder?"✓ proven cheap":"✓ passed       ",C.rst,
        (n.wonTierName.empty()?"—":n.wonTierName).c_str(), metrics.c_str());
      out+=line;
      continue;
    }
    escalated++;
    string cheapMetrics = n.cheapTok>0 ? (commafy(n.cheapTok)+" tok  "+fmt_usd(n.cheapUsd_e6)) : string("—");
    snprintf(line,sizeof line,"  %s▾%s %2d  %s   %s%s%s  %-12s %s\n",
      C.dim,C.rst, n.no, pad(n.id).c_str(), C.amb,"⚠ judge REJECT",C.rst,
      (n.firstTier.empty()?n.escFrom:n.firstTier).c_str(), cheapMetrics.c_str());
    out+=line;
    snprintf(line,sizeof line,"     %s├%s %s%s ✗%s %s%s%s   %s◀── the cheap answer was NOT PROVEN (measured, not hoped)%s\n",
      C.dim,C.rst, C.red,check_kind(n.why).c_str(),C.rst, C.red,failing_test(n.why).c_str(),C.rst, C.amb,C.rst);
    out+=line;
    if(n.ok){
      // the climb's OWN cost, not the step total — the wasted cheap attempt is
      // counted once, in the arm total, and must not be smuggled in twice here.
      string topMetrics = n.topTok>0 ? (commafy(n.topTok)+" tok  "+fmt_usd(n.topUsd_e6)+"  "+fmt_ms(n.topDur)) : string("—");
      snprintf(line,sizeof line,"     %s└%s %s↑ retried with %s%s → %sjudge GREEN → PROVEN%s   %s\n",
        C.dim,C.rst, C.bold, (n.wonTierName.empty()?n.escTo:n.wonTierName).c_str(), C.rst, C.grn,C.rst, topMetrics.c_str());
    } else {
      snprintf(line,sizeof line,"     %s└%s %sSTOP: %s — the higher tier could not pass either, fail-closed%s\n",
        C.dim,C.rst, C.red, stopReason.empty()?"BLOCKED":stopReason.c_str(), C.rst);
    }
    out+=line;
  }

  out+="  "; out+=C.dim; out+="──────────────────────────────────────────────────────────────"; out+=C.rst; out+="\n";
  char f[600];
  if(ladder)
    snprintf(f,sizeof f,"  PROVEN CHEAP %s%d/%zu%s · ESCALATED %s%d%s · this arm: %s%s%s · verdict: %s%s%s\n",
      C.grn,cheapProven,nodes.size(),C.rst, C.amb,escalated,C.rst,
      C.bold,(usd>0?fmt_usd(usd):"$0").c_str(),C.rst,
      (verdict=="PASS")?C.grn:C.red, verdict.empty()?"?":verdict.c_str(), C.rst);
  else
    snprintf(f,sizeof f,"  SINGLE TIER (%s) · %zu steps · this arm: %s%s%s · verdict: %s%s%s\n",
      r.tiers.c_str(), nodes.size(), C.bold,(usd>0?fmt_usd(usd):"$0").c_str(),C.rst,
      (verdict=="PASS")?C.grn:C.red, verdict.empty()?"?":verdict.c_str(), C.rst);
  out+=f;

  // A drill arm never feeds the A/B block. That delta is the single number a
  // buyer will check by hand, and a self-test on either side would fabricate it
  // outright — the same reason export refuses to ship a drill as a span.
  if(r.drill){
    out+="  "; out+=C.dim;
    out+="this arm is rabadon's own drill: it is NOT entered into the A/B, priced, or exported";
    out+=C.rst; out+="\n";
    return;
  }
  tot.seen=true; tot.arm=r.arm; tot.tiers=r.tiers; tot.verdict=verdict;
  tot.usd_e6=usd; tot.tokens=tok; tot.cheapProven=cheapProven; tot.escalated=escalated; tot.steps=(int)nodes.size();
}

static void render_run(const Run& r, const Pal& C, string& out){
  vector<Node> nodes; Node* cur=nullptr;
  string stopReason, verdict, runModel; long long tok=0, usd=0;
  for(const Ev& e: r.evs){
    if(e.ev=="STEP_START"){ nodes.push_back({}); cur=&nodes.back(); cur->no=(int)nodes.size(); cur->id=e.step; cur->startTs=e.ts; }
    else if(e.ev=="CHECK_FAIL" && cur){ cur->caught=true; if(cur->why.empty()) cur->why=e.why; }
    else if((e.ev=="REPAIR_OK"||e.ev=="REPAIR_FAIL") && cur){
      // only an unmarked repair is a repair: see the note where repair_kind is read
      if(e.repairKind.empty()){ if(e.ev=="REPAIR_OK") cur->repaired=true; else cur->rejected=true; }
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
  if(!r.goal.empty()){ out+="  "; out+=C.dim; out+="goal: \""+r.goal+"\""; out+=C.rst; out+="\n"; }
  drill_banner(r,C,out);
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
    if(r.drill){
      // The step really did fail its check and hiding that would be a second
      // lie, but it failed inside rabadon's own drill: it is not a catch, so it
      // is not drawn as one and no "the net caught it HERE" line follows.
      snprintf(line,sizeof line,"  %s▾ %2d  %s   ∅ drill (not counted)  %s%s\n",
        C.dim, n.no, pad(n.id).c_str(), metrics.c_str(), C.rst);
      out+=line;
      continue;
    }
    snprintf(line,sizeof line,"  %s▾%s %2d  %s   %s⚠ CAUGHT%s  %s\n",
      C.amb,C.rst, n.no, pad(n.id).c_str(), C.amb,C.rst, metrics.c_str());
    out+=line;

    string kind=check_kind(n.why), test=failing_test(n.why);
    snprintf(line,sizeof line,"     %s├%s %s%s ✗%s %s%s%s     %s◀── the net caught it HERE, at that moment%s\n",
      C.dim,C.rst, C.red,kind.c_str(),C.rst, C.red,test.c_str(),C.rst, C.amb,C.rst);
    out+=line;

    if(n.repaired){
      snprintf(line,sizeof line,"     %s│%s    %ssuite RED (%s)%s → REPAIR → %sthe REAL suite went GREEN%s → %sREPAIR_OK ✓%s\n",
        C.dim,C.rst, C.red,test.c_str(),C.rst, C.grn,C.rst, C.grn,C.rst);
      out+=line;
      snprintf(line,sizeof line,"     %s└%s %s   %s✓ green after the repair%s\n",
        C.dim,C.rst, pad(n.id).c_str(), C.grn,C.rst);
      out+=line;
    } else { // rejected -> fail-closed
      snprintf(line,sizeof line,"     %s│%s    %sfake fix (it neuters the test)%s → %sforbidden-sha%s → %sREPAIR_FAIL ✗%s\n",
        C.dim,C.rst, C.red,C.rst, C.bold,C.rst, C.red,C.rst);
      out+=line;
      snprintf(line,sizeof line,"     %s└%s %sSTOP: %s%s — fail-closed, the remaining steps NEVER ran%s\n",
        C.dim,C.rst, C.red, stopReason.empty()?"BLOCKED":stopReason.c_str(), C.rst, "");
      out+=line;
    }
  }

  // ---- footer ----
  int caught=0,repaired=0,rejected=0; string caughtNos;
  for(const Node& n: nodes){ if(n.caught){ caught++; if(!caughtNos.empty())caughtNos+=","; caughtNos+=std::to_string(n.no);} if(n.repaired)repaired++; if(n.rejected)rejected++; }

  // The headline. For a drill it reads zero — the same zero `rabadon usage` and
  // `rabadon export --otlp` already print over these bytes. The shapes are kept
  // for the operator debugging their own drill, but they are named as shapes,
  // and zeroing `caught` here is also what suppresses the "saved:" money line
  // below, because a self-test saved nobody anything.
  int drillCaught=caught, drillRepaired=repaired, drillRejected=rejected;
  if(r.drill){ caught=0; repaired=0; rejected=0; caughtNos.clear(); }

  out+="  ";
  out+=C.dim; out+="──────────────────────────────────────────────────────────────"; out+=C.rst; out+="\n";
  char f[512];
  snprintf(f,sizeof f,"  CAUGHT %s%d%s%s · REPAIRED %s%d%s · FAKE FIX REJECTED %s%d%s · verdict: %s%s%s\n",
    C.amb,caught,C.rst, caught?(" (step "+caughtNos+")").c_str():"",
    C.grn,repaired,C.rst, C.red,rejected,C.rst,
    (verdict=="PASS")?C.grn:C.red, verdict.empty()?"?":verdict.c_str(), C.rst);
  out+=f;

  if(r.drill){
    snprintf(f,sizeof f,"  %s%d catch-shaped · %d repair-shaped · %d refusal-shaped event(s) here are rabadon exercising itself — not counted, not exported, not priced%s\n",
      C.dim, drillCaught, drillRepaired, drillRejected, C.rst);
    out+=f;
    return;
  }

  if(caught){
    string saved;
    if(rejected){
      snprintf(f,sizeof f,"  %ssaved:%s caught at step %d → STOP, steps %d–%d NEVER ran on a blind base · the spend stayed in your pocket   %s◀── a passive tracer has no such line%s\n",
        C.bold,C.rst, firstCaught, firstCaught+1, N, C.dim,C.rst);
    } else {
      snprintf(f,sizeof f,"  %ssaved:%s caught and repaired at step %d → steps %d–%d ran on a CLEAN base (the bug never reached step 10) · repair cost %s, %s tok   %s◀── a passive tracer has no such line%s\n",
        C.bold,C.rst, firstCaught, firstCaught+1, N, fmt_usd(usd).c_str(), commafy(tok).c_str(), C.dim,C.rst);
    }
    out+=f;
  }
}

static const char* kHelp =
  "rabadon-trace — render one pipeline run from the ledger: what was caught,\n"
  "what was repaired, what the repair cost, and which fake fixes were refused.\n"
  "Nothing here calls a model; every number printed already exists in the spool.\n"
  "\n"
  "usage: rabadon-trace [spool.jsonl | dir] [--run <id>] [--last] [--no-color]\n"
  "\n"
  "  [spool.jsonl | dir]  a ledger file, or a directory whose newest *.jsonl wins.\n"
  "                       omitted: $RABADON_DIR/spool, else ~/.rabadon/spool.\n"
  "  --run <id>           render only the run with this id.\n"
  "  --last               render only the most recent run.\n"
  "  --no-color / --color force ANSI off/on (default: on when stdout is a tty).\n"
  "  -h, --help           this screen.\n"
  "\n"
  "example:\n"
  "  rabadon-trace --last --no-color\n";

int main(int argc,char** argv){
  // FIRST statement: `rabadon-trace --help` used to fall through to the source
  // resolver, which ignored the unknown word and printed the whole live ledger
  // — 31798 bytes of it, and not valid UTF-8.
  rb_help(argc, argv, kHelp);

  string source, wantRun; bool onlyLast=false, color=isatty(fileno(stdout));
  for(int i=1;i<argc;i++){
    string a=argv[i];
    if(a=="--run"&&i+1<argc){ wantRun=argv[++i]; }
    else if(a=="--last"){ onlyLast=true; }
    else if(a=="--no-color"){ color=false; }
    else if(a=="--color"){ color=true; }
    // an unrecognised flag is refused, never taken as the source path: taking
    // it silently is how --help became "a file named --help" and the renderer
    // fell back to the real spool as if the flag had been honoured.
    else if(rb_is_flag(a.c_str())){ rb_unknown_flag("rabadon-trace", a.c_str()); }
    // ...and the same law, one word wider. That comment was written for FLAGS
    // and left positionals open, which is the form the docs teach: README and
    // `rabadon help` both print `trace [run]`. There was no positional run
    // support at all — the word became a candidate source path, stat() failed,
    // `file` stayed empty, and the resolver fell back to the newest day file:
    // `rabadon-trace ms92w639-mdr-1` answered with 18837 lines of the WHOLE
    // ledger at exit 0, and the requested run was not among them. Silent in
    // exactly the way the swallowed flag was silent — real output, so the
    // filter looks honoured.
    else {
      struct stat pst;
      if(source.empty() && stat(a.c_str(),&pst)==0) source=a;  // it names a real path
      else if(wantRun.empty()) wantRun=a;                      // else it names a run
      else {
        fprintf(stderr,"rabadon-trace: unexpected argument \"%s\" — the run is already \"%s\"; run `rabadon-trace --help`\n",
                a.c_str(), wantRun.c_str());
        return 2;
      }
    }
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
  // EVERY non-empty line is classified for drill.h, including the ones this
  // renderer then drops: rule 4 reads its marker off events trace never renders,
  // and without them a drill's fallout is indistinguishable from real traffic.
  // drill.h's own header demands exactly this of its callers.
  vector<RbDrillEv> classify;   // one entry per non-empty line, in file order
  vector<string>    lineRun;    // that line's run id, "" when trace skipped it

  size_t ls=0;
  while(ls<body.size()){
    size_t le=body.find('\n',ls); if(le==string::npos) le=body.size();
    string line=body.substr(ls,le-ls); ls=le+1;
    if(line.empty()) continue;

    RbDrillEv c;
    c.pipe=str_field(line,"pipe"); c.has_pipe=!c.pipe.empty();
    c.ts=(double)ll_field(line,"ts");
    c.tag=rb_drill_tag(line);       // rule 1, off the raw bytes
    c.marker=rb_drill_marker(line); // rule 2, off the raw bytes
    classify.push_back(c);
    lineRun.push_back(string());

    string ev=str_field(line,"ev"); if(ev.empty()) continue;
    string run=str_field(line,"run"); if(run.empty()) continue;
    lineRun.back()=run;
    Run& R=find_run(run);
    Ev e; e.ev=ev; e.ts=ll_field(line,"ts");
    e.step=str_field(line,"step");
    if(ev=="CHECK_FAIL") e.why=nested_str(line,"why");   // inside fails[{check,why}]
    if(ev=="STOP"){ e.reason=str_field(line,"reason"); e.detail=str_field(line,"detail"); }
    if(ev=="RUN_DONE") e.verdict=str_field(line,"verdict");
    if(ev=="REPAIR_OK"||ev=="REPAIR_FAIL"||ev=="STEP_TRY"){
      e.tokens=ll_field(line,"tokens"); e.usd_e6=ll_field(line,"usd_e6");
      e.dur_ms=ll_field(line,"dur_ms"); e.model=str_field(line,"model");
      // A gate-side REPAIR_OK can mean "a rule was installed" or "a test run was
      // observed" — neither of which repaired anything. The loop's real repairs
      // carry no marker. Counting them together would let the report claim
      // repairs that never happened, which is the one number a buyer will
      // check by hand.
      e.repairKind=str_field(line,"repair_kind");
    }
    if(ev=="STEP_TRY"||ev=="STEP_OK"){ e.tier=(int)ll_field(line,"tier"); e.tierName=str_field(line,"tier_name"); }
    if(ev=="ESCALATE"){ e.from=str_field(line,"from"); e.to=str_field(line,"to"); }
    if(ev=="RUN_START"){
      R.arm=str_field(line,"arm");
      R.tiers=str_field(line,"tiers");
      // "steps": either an int (loop) or an array (session). goal is optional.
      size_t sp=rbjson::find_field(line,"steps");
      if(sp!=string::npos){ char nx=line[sp]; if(nx>='0'&&nx<='9') R.declaredSteps=(int)ll_field(line,"steps"); }
      R.goal=str_field(line,"goal");
      if(R.goal.empty()){ string g=nested_str(line,"steps",true); if(g.rfind("goal:",0)==0) R.goal=g.substr(5); }
      if(!R.goal.empty()){ size_t z=R.goal.find_first_not_of(" "); if(z!=string::npos) R.goal=R.goal.substr(z); }
    }
    if(R.pipe.empty()) R.pipe=str_field(line,"pipe");
    if(R.firstTs==0||e.ts<R.firstTs) R.firstTs=e.ts;
    if(e.ts>R.lastTs) R.lastTs=e.ts;
    R.evs.push_back(std::move(e));
  }

  // rules 1-4 in one pass over the whole file, then OR'd up to the run: trace's
  // unit is a run, and a run holding ANY drill event is rabadon exercising
  // itself — its catches are not catches and its dollars are not dollars. Same
  // predicate object as `rabadon usage` and `rabadon export --otlp`, which is
  // the entire point: three readers, one definition, no second copy to drift.
  {
    vector<char> isDrill=rb_mark_drills(classify);
    for(size_t i=0;i<isDrill.size();i++){
      if(!isDrill[i] || lineRun[i].empty()) continue;
      for(Run& r: runs) if(r.id==lineRun[i]){ r.drill=true; break; }
    }
  }

  const Pal& C = color?COLOR:PLAIN;
  string out;
  char hdr[256];
  snprintf(hdr,sizeof hdr,"%s%s  (%zu run%s)%s\n\n",C.dim,file.c_str(),runs.size(),runs.size()==1?"":"s",C.rst);
  out+=hdr;

  size_t shown=0; ArmTotal control, routedArm;
  for(size_t i=0;i<runs.size();i++){
    const Run& r=runs[i];
    if(!wantRun.empty() && r.id.find(wantRun)==string::npos) continue;
    if(onlyLast && i!=runs.size()-1) continue;
    if(!r.tiers.empty()){
      ArmTotal t; render_routed(r,C,out,t);
      if(r.arm=="control") control=t; else if(r.arm=="routed") routedArm=t;
    } else render_run(r,C,out);
    out+="\n";
    shown++;
  }

  // ---- the A/B, only when BOTH arms of the same plan actually ran ----------
  // Not a projection, not a price table: two real runs of the identical plan
  // under the identical arbiter, each priced by the model's own accounting. The
  // cheap attempts that were rejected are inside the routed number, so the
  // saving is net of its own waste. If routing lost, this prints that it lost.
  if(control.seen && routedArm.seen){
    long long d = control.usd_e6 - routedArm.usd_e6;
    int pct = control.usd_e6>0 ? (int)((double)d*100.0/(double)control.usd_e6 + (d<0?-0.5:0.5)) : 0;
    char b[700];
    out+="  "; out+=C.bold; out+="MEASURED A/B"; out+=C.rst; out+=C.dim;
    out+="  — same plan, same judge, same contracts; two real runs"; out+=C.rst; out+="\n";
    snprintf(b,sizeof b,"    control · %-16s %10s   %12s tok   %s\n",control.tiers.c_str(),
      fmt_usd(control.usd_e6).c_str(), commafy(control.tokens).c_str(), control.verdict.c_str());
    out+=b;
    snprintf(b,sizeof b,"    routed  · %-16s %10s   %12s tok   %s\n",
      routedArm.tiers.c_str(), fmt_usd(routedArm.usd_e6).c_str(), commafy(routedArm.tokens).c_str(),
      routedArm.verdict.c_str());
    out+=b;
    snprintf(b,sizeof b,"    %s          %d/%d steps PROVEN cheap, %d escalated — the wasted cheap attempts are INSIDE this number%s\n",
      C.dim, routedArm.cheapProven, routedArm.steps, routedArm.escalated, C.rst);
    out+=b;
    if(control.verdict!="PASS"||routedArm.verdict!="PASS"){
      snprintf(b,sizeof b,"    %sWARNING: not both arms PASS — the comparison is only honest when both were accepted%s\n",C.amb,C.rst);
      out+=b;
    }
    // no measured money on either side (a scripted proposer, no result event)
    // means there is no saving to report. Printing "$0.0000 kept" there would
    // be a claim about a run that never priced anything.
    if(control.usd_e6==0 && routedArm.usd_e6==0){
      snprintf(b,sizeof b,"    %sNOT MEASURED: no model bill on this run (scripted proposer) — NO money claim is made%s\n\n",C.dim,C.rst);
      out+=b;
      if(shown==0) out+="  (no matching run)\n";
      fwrite(out.data(),1,out.size(),stdout);
      return 0;
    }
    if(d>=0) snprintf(b,sizeof b,"    %sdelta%s   · %-16s %s%10s kept (%d%%)%s   %s◀── proven saving: a judge decided it, not a router%s\n",
                      C.bold,C.rst, "olculen net", C.grn, fmt_usd(d).c_str(), pct, C.rst, C.dim,C.rst);
    else     snprintf(b,sizeof b,"    %sdelta%s   · %-16s %s%10s%s   %s◀── routing came out MORE expensive: the escalation ate the saving%s\n",
                      C.bold,C.rst, "olculen net", C.red, ("-"+string(fmt_usd(-d))).c_str(), C.rst, C.red,C.rst);
    out+=b; out+="\n";
  }
  if(shown==0) out+="  (no matching run)\n";
  fwrite(out.data(),1,out.size(),stdout);
  return 0;
}
