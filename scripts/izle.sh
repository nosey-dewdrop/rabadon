#!/usr/bin/env bash
# Kosuyu CANLI izle. Salt-okunur: hicbir sey oldurmez, hicbir dosyaya yazmaz.
# Ctrl+C ile cikmak GUVENLI — surucu ayri tmux oturumunda, etkilenmez.
cd "$(git rev-parse --show-toplevel)" || exit 1
export PYTHONIOENCODING=utf-8 PYTHONUTF8=1

son=""
while true; do
  # en son yazilan .out.raw = su an konusan yapan oturum
  yeni="$(ls -t reports/kosu/*.out.raw 2>/dev/null | head -1)"
  if [ -z "$yeni" ]; then
    printf '\n[izle] aktif akis yok — degerlendiren dusunuyor ya da OPERATOR bekleniyor\n'
    sleep 10; continue
  fi
  if [ "$yeni" != "$son" ]; then
    printf '\n\033[1m══ YENI TUR: %s ══\033[0m\n' "$yeni"; son="$yeni"
  fi
  # tail -f: dosya donerse (yeni tur) --pid degil, dis dongu yakalar
  tail -n +1 -f "$yeni" 2>/dev/null | python3 -u -c '
import json,sys
for line in sys.stdin:
    line=line.strip()
    if not line or len(line)>2_000_000: continue
    try: o=json.loads(line)
    except Exception: continue
    t=o.get("type")
    if t=="assistant":
        for b in (o.get("message") or {}).get("content",[]):
            if b.get("type")=="text":
                s=b["text"].strip()
                if s: print("\n\033[36m│\033[0m "+s.replace("\n","\n\033[36m│\033[0m "))
            elif b.get("type")=="tool_use":
                n=b.get("name","?"); inp=b.get("input") or {}
                d=inp.get("command") or inp.get("file_path") or inp.get("pattern") or inp.get("description") or ""
                print(f"  \033[90m→ {n}\033[0m {str(d)[:110]}")
    elif t=="user":
        for b in (o.get("message") or {}).get("content",[]):
            if isinstance(b,dict) and b.get("type")=="tool_result":
                c=b.get("content")
                if isinstance(c,list): c="".join(x.get("text","") for x in c if isinstance(x,dict))
                c=(str(c) or "").strip().replace("\n"," ")
                if c: print(f"    \033[90m← {c[:130]}\033[0m")
    elif t=="result":
        print("\n\033[1;32m══ TUR BITTI ══\033[0m")
        print((o.get("result") or "")[:2000])
' &
  tpid=$!
  # akis dosyasi silinince (basarili parse sonrasi) yeni tura gec
  while [ -f "$yeni" ]; do sleep 5; done
  kill "$tpid" 2>/dev/null; wait "$tpid" 2>/dev/null
done
