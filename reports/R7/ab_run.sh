#!/usr/bin/env bash
# R7 iki kollu kosu — ON-KAYIT.md'nin (dondurulmus) uygulamasi.
#
# A kolu: claude -p, rabadon YOK.
# B kolu: claude -p, rabadon hook'u gorev checkout'una bagli (observe).
# Fark YALNIZ hook'un bagli olup olmamasidir (ON-KAYIT §3).
#
# DOCKER YOK, swesmith pip paketi KURULMAZ. Her instance ayna repoda bir
# branch'tir; klonlanir, .git SILINIR (sizinti onleme, ON-KAYIT §5), yerel
# venv + pytest ile arm64'te kosulur.
#
# YENIDEN BASLATILABILIR: tamamlanan (instance,arm) ciftleri JSONL'de durur ve
# atlanir. Oturum zaman sinirina takilirsa sonraki tur kaldigi yerden devam eder.
#
# Her adim KENDI timeout'uyla sinirli (B1.9: kabuk olse bile yetim surec kalmaz).
set -u
export GIT_TERMINAL_PROMPT=0 CI=1 PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8

ROOT="$(git rev-parse --show-toplevel)"
RUN=/tmp/rbrun
JSONL="$ROOT/reports/R7/ab_run.jsonl"
PREVER="$ROOT/reports/R7/ab_prever.tsv"
LOGS="$RUN/logs"
GATE="$ROOT/hooks/gate.mjs"
GOREVLER="$RUN/gorevler.json"

# P2P TAVANI — sessiz degil, ILAN EDILMIS kisitlama. Tam listeler 574-4174 test;
# hepsini iki kolda x 7 instance kosmak turu tek basina doldururdu. Ilk N node id
# kosulur ve bu sayi JSONL'e p2p_cap olarak YAZILIR.
P2P_CAP=${P2P_CAP:-120}
AGENT_TIMEOUT=${AGENT_TIMEOUT:-1500}    # tek ajan oturumu tavani (sn)
PYTEST_TIMEOUT=${PYTEST_TIMEOUT:-900}

mkdir -p "$LOGS" "$RUN/tasks" "$RUN/scorer"
[ -f "$JSONL" ] || : > "$JSONL"
[ -f "$PREVER" ] || printf 'instance_id\tkurulum\tf2p_bozukta\tp2p_bozukta\tkarar\n' > "$PREVER"

say(){ printf '%s | %s\n' "$(date +%H:%M:%S)" "$*"; }

# (instance,arm) zaten JSONL'de mi?
bitti_mi(){
  python3 - "$JSONL" "$1" "$2" <<'PY'
import json,sys
try: lines=open(sys.argv[1]).read().splitlines()
except Exception: lines=[]
for l in lines:
    l=l.strip()
    if not l: continue
    try: r=json.loads(l)
    except Exception: continue
    if r.get("instance_id")==sys.argv[2] and str(r.get("arm","")).upper()==sys.argv[3]:
        sys.exit(0)
sys.exit(1)
PY
}

# ---------------------------------------------------------------- hazirlik
# Bir instance icin: ayna klonu (puanlayici, .git DURUR) + temiz gorev agaci.
hazirla_scorer(){   # $1 iid, $2 repo(sw esmith/xxx)
  local iid="$1" repo="$2" d="$RUN/scorer/$1"
  [ -d "$d/.git" ] && return 0
  rm -rf "$d"
  # ayna daima github.com/swesmith/<repo>; 'repo' alani zaten 'swesmith/...' geliyor
  timeout 900 git clone -q --branch "$iid" \
      "https://github.com/swesmith/${repo#swesmith/}" "$d" >>"$LOGS/$iid.prep" 2>&1 \
  || return 1
  ( cd "$d" && timeout 300 git fetch -q origin main >>"$LOGS/$iid.prep" 2>&1 ) || true
  return 0
}

# Ajanin gorecegi agac: scorer'dan kopyalanir, .git SILINIR.
# Dizin adi BENZERSIZ olmali: ledger satirindaki "pipe" alani cwd'nin BASENAME'inden
# turuyor ("<dizin>:session"). Ortak spool'da 220k+ satir var ve baska oturumlar da
# yaziyor; oncesi/sonrasi farki almak BASKA oturumlarin satirlarini sayardi.
# Benzersiz basename ile bu kosuya ait satir kesin ayirt edilir.
hazirla_gorev(){    # $1 iid, $2 arm -> agac yolu stdout
  local iid="$1" arm="$2" s="$RUN/scorer/$1" d="$RUN/tasks/${1}__${2}"
  rm -rf "$d"; mkdir -p "$(dirname "$d")"
  cp -R "$s" "$d" || return 1
  rm -rf "$d/.git"          # ON-KAYIT §5.1: gecmis/origin/main/cevap KALMAZ
  rm -rf "$d/.venv"
  printf '%s' "$d"
}

kur_venv(){         # $1 agac
  local d="$1"
  timeout 300 python3 -m venv "$d/.venv" >>"$LOGS/venv.log" 2>&1 || return 1
  timeout 300 "$d/.venv/bin/python" -m pip install -q -U pip setuptools wheel >>"$LOGS/venv.log" 2>&1
  timeout 1200 "$d/.venv/bin/python" -m pip install -q -e "$d" >>"$LOGS/venv.log" 2>&1 || return 1
  # OLCULDU (tur 14): cıplak pytest YETMIYOR. Depoların setup.cfg/tox.ini'si
  # `required_plugins` ilan ediyor ve pytest "Missing required plugins:
  # pytest-cov, pytest-xdist" diyip HIC KOSMADAN cikiyor. O zaman "0 passed"
  # okunur ve saglam bir instance "F2P dustu" sanilip elenirdi — sessiz bir
  # yanlis eleme. Eklentiler kuruluyor VE addopts bosaltiliyor (asagida).
  timeout 600 "$d/.venv/bin/python" -m pip install -q \
      pytest pytest-cov pytest-xdist pytest-timeout pytest-mock \
      >>"$LOGS/venv.log" 2>&1 || return 1
  # deponun kendi test bagimliliklari (varsa) — best effort, kirilirsa devam
  for rq in requirements-test.txt requirements_test.txt test-requirements.txt; do
    [ -f "$d/$rq" ] && timeout 600 "$d/.venv/bin/python" -m pip install -q -r "$d/$rq" \
        >>"$LOGS/venv.log" 2>&1
  done
  return 0
}

# F2P test DOSYALARINI origin/main'den agaca geri koy (puanlama ani).
geri_koy_f2p(){     # $1 agac, $2 iid
  local d="$1" iid="$2" s="$RUN/scorer/$iid" n=0
  local yollar; yollar="$(python3 - "$GOREVLER" "$iid" <<'PY'
import json,sys
g=json.load(open(sys.argv[1]))[sys.argv[2]]
print("\n".join(sorted({t.split("::")[0] for t in g["F2P"]})))
PY
)"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    ( cd "$s" && timeout 60 git checkout -q origin/main -- "$p" 2>/dev/null ) || continue
    mkdir -p "$d/$(dirname "$p")"
    cp "$s/$p" "$d/$p" 2>/dev/null && n=$((n+1))
    ( cd "$s" && timeout 60 git checkout -q "$iid" -- "$p" 2>/dev/null ) || true
  done <<< "$yollar"
  printf '%s' "$n"
}

kos_pytest(){       # $1 agac, $2 iid, $3 F2P|P2P, $4 logdosyasi -> "gecti toplam"
  local d="$1" iid="$2" kume="$3" log="$4"
  python3 - "$GOREVLER" "$iid" "$kume" "$P2P_CAP" > "$d/.nodeids" <<'PY'
import json,sys
g=json.load(open(sys.argv[1]))[sys.argv[2]]
ids=g["F2P"] if sys.argv[3]=="F2P" else g["P2P"][:int(sys.argv[4])]
print("\n".join(ids))
PY
  local tot; tot=$(grep -c . "$d/.nodeids")
  [ "$tot" -eq 0 ] && { printf '0 0'; return; }
  # `-o addopts=''` ZORUNLU: depoların kendi addopts'u coverage/xdist/özel bayrak
  # istiyor; biz node id listesiyle hedefli kosuyoruz, o bayraklar yalniz kirar.
  # `-x` YOK: ilk hatada durmak "kac test gecti" sayisini bozar.
  ( cd "$d" && timeout "$PYTEST_TIMEOUT" ./.venv/bin/python -m pytest \
      -p no:cacheprovider -o addopts='' -q --no-header \
      --continue-on-collection-errors @.nodeids ) >"$log" 2>&1
  # "N passed" satirindan gecen sayisi
  local gec; gec=$(grep -oE '[0-9]+ passed' "$log" | tail -1 | grep -oE '^[0-9]+')
  printf '%s %s' "${gec:-0}" "$tot"
}

# ------------------------------------------------------------------ B kolu
bagla_hook(){       # $1 agac  — B1.5 recetesi: goreli komut + sarmalayici
  local d="$1"
  mkdir -p "$d/.claude"
  # STDOUT ASLA SUSTURULMAZ. Claude Code hook'u ajanla STDOUT uzerinden
  # konusur; rabadon'un enjeksiyonu oradan gider. Tur 14'te bir kez
  # `>/dev/null 2>&1` yazildi ve B kolu "ledger yazan ama AJANA HIC KONUSMAYAN"
  # bir rabadon'u olctu — yani bos bir mudahale. Olculdu: B transcript'inde
  # "rabadon: attempt" 0 kez geciyordu, ledger'da INJECT olayi VARKEN.
  #
  # STDIN de YONLENDIRILEMEZ. B1.5 receteside literal olarak `</dev/null`
  # yaziyor ama OLCULDU (tur 14): o redirect kapiyi SAGIR yapiyor — Claude Code
  # olay JSON'unu hook'un STDIN'ine yazar, /dev/null'a cevirince gate hicbir
  # olay gormez. Olcum:
  #   `... node gate </dev/null` -> ledger'a YENI SATIR: 0
  #   `... node gate`            -> ledger'a YENI SATIR: 1
  # Yani B1.5'in kendi "baglama kabulu" (ledger'da yeni satir goster) kendi
  # recetesiyle KARSILANAMAZ. Bu bir CHALLENGE kalemidir, DENEMELER'e yazildi.
  # Asilma korkusunu `timeout 2` zaten karsiliyor; stdin'i kesmeye gerek yok.
  # stderr susturulur (gureltu), stdout ve stdin DOKUNULMAZ, exit daima 0.
  cat > "$d/.claude/settings.local.json" <<JSON
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command",
        "command": "sh -c 'timeout 2 node $GATE 2>/dev/null; exit 0'" } ] }
    ]
  }
}
JSON
}

# $1 = benzersiz pipe etiketi (gorev dizininin basename'i). Ortak spool'da BASKA
# oturumlar da yazdigi icin sayim bu etikete gore SUZULUR, ham fark alinmaz.
ledger_satir_sayisi(){
  cat "$HOME"/.rabadon/spool/*.jsonl 2>/dev/null | grep -cF "\"pipe\":\"$1:"
}
# false_positive (ON-KAYIT §4): observe modda "engellerdim" = wouldRefuse.
# A kolunda kapi YOK -> yapisal sifir. Ayrim gucu yalniz B'dedir.
ledger_wouldrefuse_sayisi(){
  cat "$HOME"/.rabadon/spool/*.jsonl 2>/dev/null | grep -F "\"pipe\":\"$1:" \
    | grep -ciE '"(wouldRefuse|would_refuse)"[[:space:]]*:[[:space:]]*true|"ev"[[:space:]]*:[[:space:]]*"WOULD_REFUSE"'
}

# --------------------------------------------------------------------- ana
GOREV_SIRASI="$(python3 -c "import json;print(' '.join(json.load(open('$GOREVLER')).keys()))")"

for iid in $GOREV_SIRASI; do
  repo="$(python3 -c "import json;print(json.load(open('$GOREVLER'))['$iid']['repo'])")"
  say "=== $iid"

  if ! hazirla_scorer "$iid" "$repo"; then
    say "  KLON BASARISIZ — atlaniyor"; continue
  fi

  # ---- KOSU ONCESI ZORUNLU DOGRULAMA (ON-KAYIT §2), her instance icin bir kez
  if ! grep -q "^$iid	" "$PREVER"; then
    say "  on-dogrulama..."
    pv="$(hazirla_gorev "$iid" prever)" || { say "  agac hazirlanamadi"; continue; }
    if ! kur_venv "$pv"; then
      printf '%s\tFAIL\t\t\tKOSUYA_ALINMADI\n' "$iid" >> "$PREVER"
      say "  KURULUM BASARISIZ — koşuya alinmadi"; rm -rf "$pv"; continue
    fi
    # F2P test DOSYALARI bozuk dalda YOKTUR (ON-KAYIT §5: held-out yapisal).
    # Once origin/main'den geri konmali, yoksa pytest "file or directory not
    # found" deyip 0 kosar ve saglam instance yanlislikla elenirdi.
    nr="$(geri_koy_f2p "$pv" "$iid")"
    read -r fg ft <<<"$(kos_pytest "$pv" "$iid" F2P "$LOGS/$iid.prever.f2p")"
    read -r pg pt <<<"$(kos_pytest "$pv" "$iid" P2P "$LOGS/$iid.prever.p2p")"
    say "  (geri konan F2P dosyasi: $nr)"
    # bozuk dalda: F2P DUSMELI (gecen < toplam), P2P GECMELI
    if [ "$fg" -lt "$ft" ] && [ "$pg" -eq "$pt" ]; then
      printf '%s\tOK\t%s/%s_DUSTU\t%s/%s_GECTI\tKOSUYA_ALINDI\n' "$iid" "$fg" "$ft" "$pg" "$pt" >> "$PREVER"
      say "  on-dogrulama OK (F2P $fg/$ft dustu, P2P $pg/$pt gecti)"
    else
      printf '%s\tOK\t%s/%s\t%s/%s\tKOSUYA_ALINMADI\n' "$iid" "$fg" "$ft" "$pg" "$pt" >> "$PREVER"
      say "  ON-DOGRULAMA DUSTU (F2P $fg/$ft, P2P $pg/$pt) — koşuya alinmadi"
      rm -rf "$pv"; continue
    fi
    rm -rf "$pv"
  fi
  grep -q "^$iid	.*KOSUYA_ALINDI" "$PREVER" || { say "  on-dogrulamayi gecmemis, atlaniyor"; continue; }

  for arm in A B; do
    if bitti_mi "$iid" "$arm"; then say "  [$arm] zaten JSONL'de, atlandi"; continue; fi
    say "  [$arm] hazirlik"
    d="$(hazirla_gorev "$iid" "$arm")" || { say "  [$arm] agac YOK"; continue; }
    if ! kur_venv "$d"; then say "  [$arm] venv BASARISIZ"; continue; fi

    etiket="${iid}__${arm}"          # ledger 'pipe' etiketi = gorev dizini basename
    led0=0; wr0=0
    if [ "$arm" = B ]; then
      bagla_hook "$d"; led0="$(ledger_satir_sayisi "$etiket")"; wr0="$(ledger_wouldrefuse_sayisi "$etiket")"
    fi

    ps="$RUN/ps.$iid.txt"
    python3 -c "
import json;print(json.load(open('$GOREVLER'))['$iid']['problem_statement'])" > "$ps"

    say "  [$arm] ajan kosuyor (tavan ${AGENT_TIMEOUT}s)..."
    raw="$LOGS/$iid.$arm.stream.jsonl"; t0=$(date +%s)
    ( cd "$d" && timeout "$AGENT_TIMEOUT" claude -p --dangerously-skip-permissions \
        --output-format stream-json --verbose \
        "$(cat "$ps")

Bu depodaki hatayi bul ve duzelt. Testleri sen yazma; mevcut kaynak kodu duzelt." \
        < /dev/null ) > "$raw" 2>"$raw.err"
    rc=$?; t1=$(date +%s)
    say "  [$arm] ajan bitti rc=$rc sure=$((t1-t0))s"

    # tokens: son result olayindan (ON-KAYIT §4: input+output, cache HARIC)
    read -r tin tout tcw tcr cost <<<"$(python3 - "$raw" <<'PY'
import json,sys
tin=tout=tcw=tcr=0; cost=0.0
for l in open(sys.argv[1],encoding='utf-8',errors='replace'):
    l=l.strip()
    if not l: continue
    try: o=json.loads(l)
    except Exception: continue
    if o.get("type")=="result":
        u=o.get("usage") or {}
        tin=u.get("input_tokens",0) or 0; tout=u.get("output_tokens",0) or 0
        tcw=u.get("cache_creation_input_tokens",0) or 0
        tcr=u.get("cache_read_input_tokens",0) or 0
        cost=o.get("total_cost_usd",0) or 0
print(tin,tout,tcw,tcr,cost)
PY
)"

    # interventions (ON-KAYIT §4): zaman sinirina takildi/hata ile bitti = 1
    iv=0; [ "$rc" -ne 0 ] && iv=1

    # ---- PUANLAMA: F2P dosyalarini origin/main'den geri koy, F2P+P2P kos
    say "  [$arm] puanlama"
    nrest="$(geri_koy_f2p "$d" "$iid")"
    read -r fg ft <<<"$(kos_pytest "$d" "$iid" F2P "$LOGS/$iid.$arm.f2p")"
    read -r pg pt <<<"$(kos_pytest "$d" "$iid" P2P "$LOGS/$iid.$arm.p2p")"
    hp=false; { [ "$fg" -eq "$ft" ] && [ "$ft" -gt 0 ] && [ "$pg" -eq "$pt" ]; } && hp=true

    # ---- B kolu BAGLAMA KABULU: ledger'da YENI SATIR yoksa satir YAZILMAZ
    fp=false; ledyeni=0; wryeni=0
    if [ "$arm" = B ]; then
      led1="$(ledger_satir_sayisi "$etiket")"; ledyeni=$((led1-led0))
      wr1="$(ledger_wouldrefuse_sayisi "$etiket")"; wryeni=$((wr1-wr0))
      [ "$wryeni" -gt 0 ] && fp=true
      if [ "$ledyeni" -le 0 ]; then
        say "  [$arm] LEDGER'DA YENI SATIR YOK — bu kosu GECERSIZ, JSONL'e YAZILMIYOR"
        printf '%s\t%s\tLEDGER_SATIRI_YOK\n' "$iid" "$arm" >> "$RUN/gecersiz.tsv"
        continue
      fi
    fi

    python3 - "$JSONL" "$iid" "$arm" "$hp" "$tin" "$tout" "$tcw" "$tcr" "$cost" \
             "$iv" "$fp" "$fg" "$ft" "$pg" "$pt" "$rc" "$((t1-t0))" "$ledyeni" "$nrest" "$P2P_CAP" "$wryeni" <<'PY'
import json,sys
(jl,iid,arm,hp,tin,tout,tcw,tcr,cost,iv,fp,fg,ft,pg,pt,rc,dur,ledyeni,nrest,cap,wryeni)=sys.argv[1:]
row={"arm":arm,"instance_id":iid,"task":iid,
     "heldout_pass":hp=="true",
     "tokens":int(tin)+int(tout),
     "tokens_input":int(tin),"tokens_output":int(tout),
     "cache_creation_input_tokens":int(tcw),"cache_read_input_tokens":int(tcr),
     "total_cost_usd":float(cost),
     "interventions":int(iv),
     "false_positive":(fp=="true"),
     "f2p_passed":int(fg),"f2p_total":int(ft),
     "p2p_passed":int(pg),"p2p_total":int(pt),"p2p_cap":int(cap),
     "agent_rc":int(rc),"duration_s":int(dur),
     "ledger_new_lines":int(ledyeni),"ledger_would_refuse":int(wryeni),
     "f2p_files_restored":int(nrest)}
with open(jl,"a") as f: f.write(json.dumps(row)+"\n")
print("YAZILDI", arm, iid, "heldout_pass="+str(row["heldout_pass"]), "tokens="+str(row["tokens"]))
PY
    rm -rf "$d/.venv"   # disk: agac kalir (delil), venv gider
  done
done
say "=== ab_run.sh bitti"
