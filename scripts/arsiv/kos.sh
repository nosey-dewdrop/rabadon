#!/usr/bin/env bash
# IPTAL 2026-08-25 (KOSU-RABADON-4 §3.1): bu surucu emekli edildi, KOSMAZ. Delil olarak durur.
# yapan -> degerlendiren -> yapan. Sessiz olum yok: her tikanma OPERATOR-duragi.
set -u
set -m   # arka plan isler KENDI process grubunu alir -> agac halinde oldurulebilir
cd "$(git rev-parse --show-toplevel)"
mkdir -p reports/kosu
export GIT_TERMINAL_PROMPT=0 CI=1 npm_config_yes=true DEBIAN_FRONTEND=noninteractive GIT_PAGER=cat
export PYTHONIOENCODING=utf-8 PYTHONUTF8=1   # C/POSIX locale ASCII cokusune karsi parser zirhi
# SURUM SABITLEME (C.0 sarti): kosu ortasinda CLI guncellenirse flag/format
# degisir ve dongu sessizce YANLIS kosar. Global settings.json'a YAZILMAZ —
# operatorun diger oturumlarini etkilememesi icin yalniz bu ortama export.
export DISABLE_AUTOUPDATER=1
# TASINABILIRLIK: macOS'ta `timeout` YOKTUR (BSD userland). Shim olmadan her
# `timeout ...` cagrisi "command not found" ile 127 doner — degerlendiren HIC
# kosmaz, pusla her turda "basarisiz" saniir. gtimeout = GNU timeout (coreutils).
# Shim yoksa dongu sessizce degil, YANLIS kosar; o yuzden burasi sert baslar.
if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then
    timeout() { gtimeout "$@"; }
  else
    echo "HATA: ne timeout ne gtimeout var (macOS'ta: brew install coreutils). Dongu baslamaz." >&2
    exit 2
  fi
fi
MAX_ITER=${MAX_ITER:-40}
# v3/B5 freni: degerlendiren girdisi bu tavani asarsa DURAK. Girdi buyuyorsa
# DEVIR disiplini bozulmustur; karar degil TEMIZLIK gerekir.
GIRDI_MAX=${GIRDI_MAX:-30720}
SESSION_TIMEOUT=${SESSION_TIMEOUT:-7200}   # mutlak tavan (mesru uzun derleme/bench icin genis)
STALL_TIMEOUT=${STALL_TIMEOUT:-1200}       # cikti buyumezse 20 dk'da kes
MAX_WAIT_S=${MAX_WAIT_S:-21600}
RAW_MAX=${RAW_MAX:-15000000}   # tek oturum stream tavani (~token yanigi vekili)
BUTCE_DAR=0                     # context asiminda 1'e cekilir, basarili kararla sifirlanir
GUNLUK=reports/kosu/GUNLUK.tsv
bekle_toplam=0
AKTIF_PID=""
# ZIRH: surucu olurse (Ctrl+C, tmux kill, HUP) aktif yapanin TUM AGACI da gomulur —
# yetim claude gece boyu para yakamaz. -$$ ISE YARAMAZ: set -m ile yapan AYRI gruptadir,
# o yuzden hedef script'in grubu degil AKTIF_PID'in grubudur.
# iki supurge: grup_oldur AYRI gruptaki yapani, kill 0 AYNI gruptaki subshell'i
# (degerlendiren command-substitution'i) gomer. trap ONCE sokulur — kill 0
# script'in kendine de TERM yollar, reset'siz trap ozyinelemeye girer.
trap 'trap - INT TERM HUP; grup_oldur "$AKTIF_PID"; kill -TERM 0 2>/dev/null; exit 130' INT TERM HUP

grup_oldur() {  # tum surec AGACINI oldur: gruba TERM, 5 sn sonra KILL
  [ -n "${1:-}" ] || return 0
  kill -TERM -- "-$1" 2>/dev/null || kill -TERM "$1" 2>/dev/null
  sleep 5
  kill -KILL -- "-$1" 2>/dev/null || true
}

pusla() {  # push; kalirsa rebase+tekrar; yine kalirsa LOGLA — sessiz yutma yok
  timeout 120 git push -q 2>/dev/null && return 0
  timeout 120 git pull --rebase -q 2>/dev/null || git rebase --abort >/dev/null 2>&1
  timeout 120 git push -q 2>/dev/null && return 0
  printf '%s\t%s\tpush BASARISIZ — remote guncel degil, OPERATOR.md YERELDEN izlenmeli\n' \
    "$(date +%Y-%m-%dT%H:%M:%S%z)" "$1" >> reports/kosu/PUSH-HATA.log   # BSD date'te -Is YOK
  return 1
}

operator_duragi() {  # $1: soru
  printf '\nOPERATÖR: %s\n' "$1" >> reports/kosu/OPERATOR.md
  git add -A; git commit -qm "kosu3: OPERATOR duragi" || true; pusla durak
  # muhur: CEVAP: satirlari yetmez, en sonda TEK BASINA 'ONAY' satiri gerekir
  # (yarim kaydedilmis Cmd+S cumlesini talimat sanmamak icin)
  while ! grep -q '^ONAY[[:space:]]*$' reports/kosu/OPERATOR.md 2>/dev/null; do sleep 300; done
  bekle_toplam=0
}

# oturumu watchdog ile kosar: $1 talimat, $2 cikti dosyasi. Donus: 0 normal, 9 stall-kill, 8 hard-timeout
yapan_kos() {
  # nabiz markeri WORKTREE icinde: worktree ile ayni dosya sistemi/saat;
  # git add'den once silindigi icin commit'e girmez
  local raw="$2.raw" mark="./.kosu-nabiz.$$"; touch "$mark"
  claude -p --dangerously-skip-permissions --output-format stream-json --verbose "$1" \
    < /dev/null > "$raw" 2> "$raw.err" &
  local pid=$! start=$(date +%s) last=0 stall=0 now size chg rc=0 durum=0 parse_ok=0
  AKTIF_PID=$pid
  while kill -0 "$pid" 2>/dev/null; do
    sleep 60
    now=$(date +%s); size=$(wc -c < "$raw" 2>/dev/null || echo 0)
    # thrash freni: cikti tasmasi = anlamli ilerleme olmadan hizli token yakma vekili
    if [ "$size" -gt "$RAW_MAX" ]; then durum=7; grup_oldur "$pid"; break; fi
    # iki nabiz: cikti buyumesi VEYA worktree dosya aktivitesi (sessiz derleme .o uretir)
    # -cnewer (ctime): tar/npm mtime'i GECMISE koruyabilir ama ctime kernel'indir, forge edilemez
    # node_modules prune'lu (150k dosyalik stat israfina karsi); build/ BILEREK iceride —
    # sessiz derlemenin tek yasam belirtisi orasi, prune etmek 5. turun false-kill'ini geri getirir.
    # -print -quit ilk eslesmede cikar: tam tarama yalniz aktivite yokken olur. timeout 10:
    # find asilirsa "aktivite VAR" sayilir — watchdog'un kendisi sistemi asamaz, oldurme yonunde degil
    # yasatma yonunde yanilir.
    # NABIZ MARKERI PRUNE EDILIR — yoksa watchdog OLU. BSD/macOS find'da
    # `-cnewer REF` REFERANSIN KENDISINI de eslestirir (GNU find etmez), yani
    # chg her turda marker'i bulur, aktivite hep "var" sanilir ve STALL KILL
    # HIC atesle mez. Olculdu 24.08: `touch .mark; find . -cnewer ./.mark` -> ./.mark
    chg="$(timeout 10 find . -path ./.git -prune -o -name node_modules -prune -o -name '.kosu-nabiz.*' -prune -o -type f -cnewer "$mark" -print -quit 2>/dev/null)"
    [ $? -eq 124 ] && chg="find-zamanasimi-aktivite-sayilir"
    if [ "$size" -gt "$last" ] || [ -n "$chg" ]; then last=$size; stall=0; touch "$mark"
    else stall=$((stall+60)); fi
    if [ "$stall" -ge "$STALL_TIMEOUT" ]; then durum=9; grup_oldur "$pid"; break; fi
    if [ $((now-start)) -ge "$SESSION_TIMEOUT" ]; then durum=8; grup_oldur "$pid"; break; fi
  done
  wait "$pid" 2>/dev/null; rc=$?
  AKTIF_PID=""
  rm -f "$mark"
  # stream-json'dan okunur metni cikar (asistan metinleri + sonuc); olmazsa ham kuyruk
  if timeout 60 python3 - "$raw" > "$2" 2>/dev/null <<'PY'
import json,sys,re
ANSI=re.compile(r'\x1b\[[0-9;]*[A-Za-z]|\r')
out=[]; saw_result=False
for line in open(sys.argv[1],encoding='utf-8',errors='replace'):
    line=line.strip()
    if not line: continue
    if len(line)>2_000_000:          # newline'siz dev binary cop: RAM'e/regex'e sokma
        out.append(f'[PARSER NOTU: {len(line)} baytlik tek dev satir atlandi]'); continue
    try: o=json.loads(line)          # once HAM dene: gecerli JSON'a asla dokunma
    except Exception:
        line=ANSI.sub('',line).strip()   # patladiysa ANSI/\r temizle, tekrar dene
        if not line: continue
        try: o=json.loads(line)
        except Exception: out.append(line); continue
    t=o.get('type')
    if t=='assistant':
        for b in (o.get('message') or {}).get('content',[]):
            if b.get('type')=='text': out.append(b['text'])
            elif b.get('type')=='tool_use': out.append(f"[tool: {b.get('name')}]")
    elif t=='result':
        saw_result=True; out.append(o.get('result') or '')
if not saw_result:
    out.append('[PARSER NOTU: result eventi gorulmedi — akis kesik olabilir, cikti EKSIK sayilmali]')
print('\n'.join(out))
PY
  then parse_ok=1
  else tail -c 200000 "$raw" > "$2"; fi   # fallback: raw adli delil olarak kalir
  if [ -s "$raw.err" ]; then              # CLI stderr'i etiketli+ANSI-temiz ekle
    ESC=$(printf '\033')
    { printf '\n[CLI STDERR kuyrugu:]\n'; tail -15 "$raw.err" | sed "s/${ESC}\[[0-9;]*[A-Za-z]//g"; } >> "$2"
  fi
  [ "$parse_ok" -eq 1 ] && rm -f "$raw" "$raw.err"   # basarili parse: geveze dosyalara gerek yok
  if [ "$durum" -eq 0 ] && [ "$rc" -ne 0 ]; then
    printf '\n[SÜRÜCÜ NOTU: oturum rc=%s ile KENDİLİĞİNDEN öldü (ağ/CLI hatası olabilir) — çıktı eksik sayılmalı.]\n' "$rc" >> "$2"
  fi
  return $durum
}

# v3/B2(1): degerlendirenin girdisi TRANSKRIPTSIZDIR. Girdi once DOSYAYA yazilir
# (olculebilsin diye: B5 freni + B6.2 kaniti), sonra stdin'den beslenir.
# Buraya `cat KOSU-RABADON-3.md` ve `tail -c ... $i.out` GIRMEZ — kasitli.
girdi_yaz() {  # $1: tur no, $2: hedef dosya
  { echo '----- DURUM (kisa) -----';             cat reports/kosu/DURUM.md 2>/dev/null || echo '(DURUM.md yok)'
    echo '----- DEVIR (bu turun ciktisi) -----'; head -40 reports/kosu/DEVIR.md 2>/dev/null || echo '(DEVIR yok)'
    echo '----- GUNLUK (tekrar sayaci) -----';   tail -20 "$GUNLUK" 2>/dev/null || echo '(ilk tur)'
    echo '----- DENEMELER (son degisen 2 tur) -----'
    ls -t reports/*/DENEMELER.md 2>/dev/null | head -2 \
      | while read -r d; do echo "--- $d:"; tail -"$DEN_T" "$d"; done
    echo '----- ONCEKI 2 KARAR -----'
    for k in $(ls reports/kosu/*.karar 2>/dev/null | sort -V | tail -2); do
      echo "--- $k:"; head -60 "$k"; done
    echo '----- GIT -----'; git log --oneline -10; git status --short
    echo '----- BEKLEYEN OPERATOR -----'
    cat reports/kosu/OPERATOR.md 2>/dev/null || echo '(yok)'
    echo '----- HAM CIKTI YOLU (OKUNMAYACAK, delil) -----'
    echo "reports/kosu/$1.out"
  } > "$2"
}

i=$(find reports/kosu -maxdepth 1 -name '*.out' 2>/dev/null | grep -c '')
# v3/B2(3): varsayilan talimat DEVIR yazmayi EMREDER ve ilk is B6'nin uc maddesidir.
talimat="KOSU-RABADON-3.md'yi oku. B1 kurallariyla calis (ALT-AJAN YASAK; agir is scripts/isci.sh ile ayri surecte). Bu tur B6'nin uc maddesini kanitla: (1) isci.sh bir isci kosar, RAPOR/*.md 12 satirda kirpilir, iscinin ciktisindan yapanin stdout'una tek bayt girmez; (2) bu turun degerlendiren girdisi reports/kosu/<tur>.girdi dosyasindan wc -c ile olculur ve 30720 baytin altinda cikar; (3) kasitli olarak DEVIR yazmayan bir turun surucude 'KOSMADI' bloguna dustugu gosterilir (kanit: kos-smoke tarzi tekil test, dongunun kendisi degil). Bulgulari reports/kosu/SMOKE-V3.md'ye yaz, DENEMELER.md'yi guncelle, raporu yaz, reports/kosu/DEVIR.md'yi B7 sablonuyla YENIDEN yaz, DURUM.md'yi tazele, commit+push et."
[ -f reports/kosu/son.talimat ] && talimat="$(cat reports/kosu/son.talimat)"

while true; do
  i=$((i+1))
  if [ "$i" -gt "$MAX_ITER" ]; then
    operator_duragi "iterasyon tavani ($MAX_ITER) doldu. CEVAP: satirlarini yaz, en sona tek basina ONAY yaz; tavan +40 kaydirilir."
    talimat="reports/kosu/OPERATOR.md'deki CEVAP satirlarini uygula, KOSU-RABADON-3.md'nin A6 sirasinda kaldigin yerden devam et. B1 kurallari gecerli (ALT-AJAN YASAK, agir is scripts/isci.sh). DEVIR.md'yi B7 sablonuyla YENIDEN yaz, DURUM.md'yi tazele, commit+push et."
    # i SIFIRLANMAZ (eski dosyalarin uzerine yazardi); tavan kaydirilir, dosyalar monoton
    mv reports/kosu/OPERATOR.md "reports/kosu/tavan-$i.operator.md"; MAX_ITER=$((i+40)); continue
  fi
  if [ "${#talimat}" -gt 50000 ]; then         # E2BIG sigortasi: dev talimat argv'ye degil dosyadan
    talimat="Talimatın tamamı reports/kosu/son.talimat dosyasında (argv sınırı için kısaltıldı). Önce onu oku, sonra uygula. B1 kurallarıyla çalış, DENEMELER.md'yi güncelle, kabul betiğini koş, raporu yaz, commit+push et."
  fi
  # SIRA ONEMLI: once kilit kirilir, sonra abort — index.lock dururken abort da
  # kilide takilir; ters sira bir turu ziyan eder. Worktree'de .git bir DOSYADIR,
  # kilit gercek git-dir'dedir. Guvenli: akis sirali, canli git sureci olamaz.
  GD="$(git rev-parse --git-dir 2>/dev/null)"
  [ -n "$GD" ] && rm -f "$GD/index.lock" "$GD/HEAD.lock" 2>/dev/null || true
  git rebase --abort >/dev/null 2>&1 || true   # stall-kill'in birakabilecegi yarim state
  git merge  --abort >/dev/null 2>&1 || true
  # worktree sagligi: ajan .git'e dokunduysa kilitlenme degil DURAK
  git status --porcelain >/dev/null 2>&1 || {
    operator_duragi "git worktree BOZUK gorunuyor (git status calismiyor) — ajan .git dosyasina/worktree yapisina dokunmus olabilir. Elle onar; CEVAP: yaz, en sona ONAY."
    mv reports/kosu/OPERATOR.md "reports/kosu/bozuk-$i.operator.md"
  }
  bos_kb=$(df -Pk . 2>/dev/null | awk 'NR==2{print $4}'); bos_kb=${bos_kb:-9999999}; case "$bos_kb" in *[!0-9]*|'') bos_kb=9999999;; esac
  # inode kitligi: npm 50MB'a 150k dosya yazar; blok bos, inode dolu olabilir.
  # macOS/BSD df -Pi sutunlari farklidir: orada yanlis (buyuk) sutun okunur,
  # yani mac'te koruma pasif kalir ama YANLIS ALARM uretmez — guvenli yone yanilir.
  bos_inode=$(df -Pi . 2>/dev/null | awk 'NR==2{print $4}'); bos_inode=${bos_inode:-9999999}; case "$bos_inode" in *[!0-9]*|'') bos_inode=9999999;; esac
  # cok-partisyon korlugune karsi: npm/gcc kucuk tmpfs'i doldurur, data diski genis gorunur
  tmp_kb=$(df -Pk /tmp 2>/dev/null | awk 'NR==2{print $4}'); tmp_kb=${tmp_kb:-9999999}; case "$tmp_kb" in *[!0-9]*|'') tmp_kb=9999999;; esac
  if [ "$bos_kb" -lt 1048576 ] || [ "$bos_inode" -lt 10000 ] || [ "$tmp_kb" -lt 524288 ]; then
    operator_duragi "disk 1GB altinda ($((bos_kb/1024)) MB) VEYA inode tukeniyor ($bos_inode) VEYA /tmp doluyor ($((tmp_kb/1024)) MB). Temizlik/karar gerekli. CEVAP: yaz, en sona ONAY."
    mv reports/kosu/OPERATOR.md "reports/kosu/disk-$i.operator.md"
  fi
  # v3/B2(2) on adimi: onceki turun DEVIR'i ARSIVLENIR. Yerinde birakilirsa bu
  # turun yapani DEVIR yazmasa bile eski dosya "bu turun ciktisi" sanilir —
  # KOSMADI blogu HIC atesle mez ve degerlendiren bayat kanitla karar verir.
  [ -f reports/kosu/DEVIR.md ] && mv reports/kosu/DEVIR.md "reports/kosu/$((i-1)).devir"
  yapan_kos "$talimat" "reports/kosu/$i.out"; durum=$?
  if [ "$durum" -eq 9 ]; then
    printf '\n[SÜRÜCÜ NOTU: cikti %s sn buyumedi — STALL KILL. Interaktif prompt / TTY bekleyen arac olasiligini degerlendir; DENEMELER.md guncellenmemis olabilir. Bu bir KESINTIDIR: yurutulen hipotez ELENMIS SAYILMAZ.]\n' "$STALL_TIMEOUT" >> "reports/kosu/$i.out"
  elif [ "$durum" -eq 7 ]; then
    printf '\n[SÜRÜCÜ NOTU: ÇIKTI TAŞMASI — stream %s baytı aştı, muhtemel thrash (hızlı hata döngüsü). Hipotez ELENMEZ ama iş KÜÇÜK ADIMLARA bölünmeli.]\n' "$RAW_MAX" >> "reports/kosu/$i.out"
  elif [ "$durum" -eq 8 ]; then
    printf '\n[SÜRÜCÜ NOTU: oturum %s sn mutlak tavaninda kesildi — kismi cikti yukarida.]\n' "$SESSION_TIMEOUT" >> "reports/kosu/$i.out"
  # LIMIT SEZGISI — DAR KAPSAM. Eskiden TUM govde grep'lenirdi; tur 13'te yapan oturum
  # `rate_limit_info: five_hour` OLCUMUNU rapor edince 16 KB'lik saglam bir tur "limit
  # hatasi" sanildi, cope atildi, 15 dk beklendi ve tur BASTAN kosuldu. Yani arac, kendi
  # olctugu seyi yazan oturumu cezalandiriyordu. Gercek bir limit kesintisi KISA cikti
  # uretir (ya da hic uretmez) ve mesaj CLI stderr kuyruguna duser; dolu bir rapor uretmez.
  # Bu yuzden desen yalniz (a) bos cikti, (b) <3000 bayt kisa cikti, (c) stderr kuyrugu
  # icinde aranir. Yanlis pozitif = bir tur token + 15 dk; yanlis negatif = bir tur bos
  # doner ve degerlendiren zaten gorur. Asimetri kisitlamayi hakli kilar.
  elif [ ! -s "reports/kosu/$i.out" ] \
       || { [ "$(wc -c < "reports/kosu/$i.out")" -lt 3000 ] \
            && grep -qiE 'rate.?limit|usage limit|overloaded|too many requests' "reports/kosu/$i.out"; } \
       || sed -n '/\[CLI STDERR kuyrugu:\]/,$p' "reports/kosu/$i.out" \
            | grep -qiE 'rate.?limit|usage limit|overloaded|too many requests'; then
    bekle_toplam=$((bekle_toplam+900))
    if [ "$bekle_toplam" -ge "$MAX_WAIT_S" ]; then
      operator_duragi "toplam $((MAX_WAIT_S/3600)) saattir limit/bos-cikti beklemesindeyim. Plan/hesap kontrolu gerekebilir. CEVAP: yaz, en sona ONAY."
      mv reports/kosu/OPERATOR.md "reports/kosu/bekleme-$i.operator.md"
    fi
    echo "kosu3 $i: limit/bos — 15 dk" >> reports/kosu/bekleme.log
    i=$((i-1)); sleep 900; continue
  fi
  bekle_toplam=0
  # v3/B2(2): DEVIR tavanini SURUCU uygular. "40 satiri asma" niyet beyanidir,
  # head -40 hukumdur. DEVIR yoksa tur KOSMAMIS sayilir — kirmizi DEGIL.
  if [ -f reports/kosu/DEVIR.md ]; then
    if [ "$(wc -l < reports/kosu/DEVIR.md)" -gt 40 ]; then
      head -40 reports/kosu/DEVIR.md > reports/kosu/DEVIR.t
      echo '[SURUCU: 40 satirda kirpildi — yapan tavani asti]' >> reports/kosu/DEVIR.t
      mv reports/kosu/DEVIR.t reports/kosu/DEVIR.md
    fi
  else
    printf 'TUR: %s · DURUM: KOSMADI\nNOT: yapan DEVIR yazmadan bitti. Ham: reports/kosu/%s.out\n' \
      "$i" "$i" > reports/kosu/DEVIR.md
  fi
  git add -A; git commit -qm "kosu3 $i" || true; pusla "$i"
  if [ "$BUTCE_DAR" -eq 1 ]; then DEN_T=25; else DEN_T=60; fi
  girdi="reports/kosu/$i.girdi"
  girdi_yaz "$i" "$girdi"
  gb=$(wc -c < "$girdi"); gb=${gb:-0}
  if [ "$gb" -gt "$GIRDI_MAX" ]; then
    operator_duragi "degerlendiren girdisi $gb bayt (tavan $GIRDI_MAX) — DEVIR/DENEMELER disiplini bozulmus, karar degil TEMIZLIK gerek. Dosyalari kirp; CEVAP: yaz, en sona ONAY."
    mv reports/kosu/OPERATOR.md "reports/kosu/girdi-$i.operator.md"
    girdi_yaz "$i" "$girdi"; gb=$(wc -c < "$girdi"); gb=${gb:-0}   # operator kirptiysa yeniden olc
  fi
  karar_ham="$(timeout 900 claude -p --model sonnet "$(cat docs/DEGERLENDIREN.md)" < "$girdi")"
  rc_eval=$?
  # yarim-kusma kalkani: timeout(124) ya da ag olumuyle kesilen degerlendirenin
  # KISMI metni karar SAYILMAZ — aksi halde yarim cumle *) dalindan talimat olur
  if [ "$rc_eval" -ne 0 ]; then
    bekle_toplam=$((bekle_toplam+900))
    if [ "$bekle_toplam" -ge "$MAX_WAIT_S" ]; then
      operator_duragi "degerlendiren ust uste basarisiz bitiyor (son rc=$rc_eval; 124=timeout). CEVAP: yaz, en sona ONAY."
      mv reports/kosu/OPERATOR.md "reports/kosu/eval-$i.operator.md"
    fi
    echo "kosu3 $i: degerlendiren rc=$rc_eval — kismi cikti atildi, 15 dk" >> reports/kosu/bekleme.log
    sleep 900; i=$((i-1)); continue
  fi
  if [ -z "$karar_ham" ]; then
    echo "kosu3 $i: degerlendiren bos — 15 dk" >> reports/kosu/bekleme.log
    sleep 900; i=$((i-1)); continue
  fi
  if printf '%s\n' "$karar_ham" | grep -qiE 'prompt is too long|request too large|context (length|window)'; then
    if [ "$BUTCE_DAR" -eq 1 ]; then
      operator_duragi "degerlendiren girdisi DAR butcede bile context sinirini asiyor — DENEMELER/cikti temizligi karari gerek. CEVAP: yaz, en sona ONAY."
      mv reports/kosu/OPERATOR.md "reports/kosu/context-$i.operator.md"; BUTCE_DAR=0
    else
      BUTCE_DAR=1   # bekleme YOK: ayni girdi kuculmeden tekrar gondermek olu taklididir
    fi
    echo "kosu3 $i: context asimi — butce daraltilip tekrar" >> reports/kosu/bekleme.log
    i=$((i-1)); continue
  fi
  if printf '%s\n' "$karar_ham" | head -3 | grep -qiE '^(api )?error|rate.?limit|overloaded|bad gateway|too many requests'; then
    echo "kosu3 $i: degerlendiren HATA sizdirdi, karar degil — 15 dk" >> reports/kosu/bekleme.log
    sleep 900; i=$((i-1)); continue
  fi
  BUTCE_DAR=0
  printf '%s\n' "$karar_ham" > "reports/kosu/$i.karar"
  ilk="$(printf '%s\n' "$karar_ham" | sed -e 's/^[[:space:]>*#`-]*//' -e '/^$/d' | head -1)"
  # KURTARMA AGI: bicim ihlali. Degerlendiren protokolu "ilk satir bicimi belirler"
  # der ama ayni prompt "TEKRAR KONTROLU her kararda ilk is" de diyordu; model 4 turun
  # 3'unde ikinciye uydu ve OPERATÖR: blogunu metnin ORTASINA gomdu -> soru operatore
  # HIC ulasmadi, talimat sanilip yapana gitti (tur 2-3). Belge celiskisi giderildi ama
  # davranis olasiliksal; sessiz olum yasagi tek basina model itaatine dayanamaz.
  # Kosul BILEREK ilk-satir-etiketsizligine bagli: duz talimatlar bu repoda surekli
  # "OPERATÖR:" metnini ALINTILIYOR, kosulsuz arama suresiz yanlis durak uretirdi.
  # BİTTİ: icin ag YOK — yanlis pozitifi exit 0, cok daha pahali (bilincli asimetri).
  case "$ilk" in
    OPERATÖR*|OPERATOR*|BİTTİ*|BITTI*) ;;
    *) if printf '%s\n' "$karar_ham" | grep -qE '^OPERAT(Ö|O)R:'; then
         ilk="OPERATÖR: [SÜRÜCÜ KURTARMASI — biçim ihlali, etiket ilk satırda değildi]"
       fi ;;
  esac
  # v3/B6.2: girdi boyutu tur satirinin UCUNCU sutununda tasinir. Ayri satir
  # olarak yazilmaz — GUNLUK'un tail -20 penceresi tekrar sayacidir, yariya inmez.
  printf '%s\t%s\t[girdi %s bayt]\n' "$i" "$ilk" "$gb" >> "$GUNLUK"
  case "$ilk" in
    OPERATÖR*|OPERATOR*)
      printf '\n%s\n' "$karar_ham" >> reports/kosu/OPERATOR.md
      git add -A; git commit -qm "kosu3 $i: OPERATOR sorusu" || true; pusla "$i"
      while ! grep -q '^ONAY[[:space:]]*$' reports/kosu/OPERATOR.md 2>/dev/null; do sleep 300; done
      talimat="reports/kosu/OPERATOR.md'deki CEVAP satirlarini uygula, sonra KOSU-RABADON-3.md'nin A6 sirasinda kaldigin yerden devam et. B1 kurallari gecerli (ALT-AJAN YASAK, agir is scripts/isci.sh). DEVIR.md'yi B7 sablonuyla YENIDEN yaz, DURUM.md'yi tazele, commit+push et."
      mv reports/kosu/OPERATOR.md "reports/kosu/$i.operator.md" ;;
    BİTTİ*|BITTI*)
      printf '%s\n' "$karar_ham" >> reports/kosu/BITTI.md
      git add -A; git commit -qm "kosu3 bitti" || true; pusla son
      exit 0 ;;
    *) talimat="$karar_ham" ;;
  esac
  printf '%s\n' "$talimat" > reports/kosu/son.talimat
  sleep 20
done
