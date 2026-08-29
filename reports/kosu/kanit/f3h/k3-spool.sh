set -u
ROOT="/Users/damummyphus/damla_projects_2026/rabadon"; cd "$ROOT"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
PROBE_DIR="$W/probe"; PGATE="$PROBE_DIR/g"; mkdir -p "$PROBE_DIR"; cp native/*.h "$PROBE_DIR"/
python3 - native/gate.cpp "$PROBE_DIR/g.cpp" <<'PY'
import sys
src=open(sys.argv[1]).read()
P=r'''
#include <chrono>
static std::chrono::steady_clock::time_point g_rbp_t0;
static void rbprobe_dump(){const char*p=getenv("RABADON_PROBE_OUT");if(!p||!*p)return;
const double us=std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now()-g_rbp_t0).count();
char b[64];const int n=snprintf(b,sizeof b,"%.1f\n",us);const int fd=open(p,O_WRONLY|O_APPEND|O_CREAT,0644);
if(fd<0)return;ssize_t w=write(fd,b,(size_t)n);(void)w;close(fd);}
static void rbprobe_begin(){g_rbp_t0=std::chrono::steady_clock::now();atexit(rbprobe_dump);}
'''
a="int main(int argc, char** argv) {"
open(sys.argv[2],"w").write(src.replace(a,P+a+"\n  rbprobe_begin();"))
PY
c++ -std=c++17 -O2 -I "$PROBE_DIR" -o "$PGATE" "$PROBE_DIR/g.cpp" || exit 1
PJ="$W/p"; mkdir -p "$PJ/.git"; printf 'ref: refs/heads/main\n' >"$PJ/.git/HEAD"
EVX="$(python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"speed","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":"echo hello world"}}))' "$PJ")"
med(){ python3 -c "import statistics,sys;print(f'{statistics.median([float(x) for x in open(sys.argv[1])]):.1f}')" "$1"; }
for k in 1 2 3; do
  H="$(mktemp -d "$W/h.XXXXXX")"; mkdir -p "$H/.rabadon/spool"; : >"$H/.rabadon/enabled"
  for _ in $(seq 40); do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$PGATE" >/dev/null 2>&1; done
  O1="$W/fresh.$k"; for _ in $(seq 120); do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_PROBE_OUT="$O1" "$PGATE" >/dev/null 2>&1; done
  for _ in $(seq 1500); do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$PGATE" >/dev/null 2>&1; done
  O2="$W/aged.$k"; for _ in $(seq 120); do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_PROBE_OUT="$O2" "$PGATE" >/dev/null 2>&1; done
  printf 'round %s  after ~160 calls %s us   after ~1660 calls %s us   spool %s\n' "$k" "$(med "$O1")" "$(med "$O2")" "$(du -sk "$H/.rabadon" | cut -f1)K"
done
