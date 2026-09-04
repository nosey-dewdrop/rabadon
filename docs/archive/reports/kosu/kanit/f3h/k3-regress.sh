set -u
ROOT="/Users/damummyphus/damla_projects_2026/rabadon"
BASE="$HOME/.rb-f3h-wt"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
build(){ d="$W/$2"; mkdir -p "$d"; cp "$1"/native/*.h "$d"/
python3 - "$1/native/gate.cpp" "$d/g.cpp" <<'PY'
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
c++ -std=c++17 -O2 -I "$d" -o "$d/g" "$d/g.cpp" || exit 1; }
build "$BASE" base; build "$ROOT" head
PJ="$W/p"; mkdir -p "$PJ/.git"; printf 'ref: refs/heads/main\n' >"$PJ/.git/HEAD"
EVX="$(python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"PreToolUse","session_id":"speed","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":"echo hello world"}}))' "$PJ")"
med(){ python3 -c "import statistics,sys;print(f'{statistics.median([float(x) for x in open(sys.argv[1])]):.1f}')" "$1"; }
D=""
for r in 1 2 3 4 5 6; do
  H="$(mktemp -d "$W/h.XXXXXX")"; mkdir -p "$H/.rabadon/spool"; : >"$H/.rabadon/enabled"
  for g in base head; do
    for _ in $(seq 40); do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 "$W/$g/g" >/dev/null 2>&1; done
    for _ in $(seq 120); do printf '%s' "$EVX" | env HOME="$H" RABADON_DIR="$H/.rabadon" RABADON_NOTIFY=0 RABADON_PROBE_OUT="$W/$g.$r" "$W/$g/g" >/dev/null 2>&1; done
  done
  a="$(med "$W/base.$r")"; b="$(med "$W/head.$r")"
  d="$(python3 -c "print(f'{float('$b')-float('$a'):.1f}')")"
  printf 'round %s  F3h-oncesi %8s us   HEAD %8s us   head-base %+8s us\n' "$r" "$a" "$b" "$d"; D="$D $d"
done
python3 -c "
import statistics,sys
d=[float(x) for x in sys.argv[1].split()]
print(f'median head-base : {statistics.median(d):+.1f} us   one-sided: {\"YES\" if all(x>0 for x in d) or all(x<0 for x in d) else \"NO\"}   |439| band: {\"BEATEN\" if abs(statistics.median(d))>439 else \"inside\"}')" "$D"
