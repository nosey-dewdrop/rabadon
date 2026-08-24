# rabadon — koşu belgesi 3 (v3.0: ajanlar süreçtir, değerlendiren transkript okumaz)

Bu dosya repo kökünde `KOSU-RABADON-3.md` olarak durur ve **koşunun tek
kaynağıdır**. `KOSU-RABADON.md` ürün/tur tanımları için geçerli kalır.
`KOSU-RABADON-2.md` §B'si (orkestrasyon) BU BELGEYLE DEĞİŞTİRİLİR; §A'sı
(durum) bayattır ve aşağıdaki §A onun yerine geçer. Çelişkide bu dosya kazanır.
`AGENTS-PROTOCOL.md` devir kuralı ve üç kapısı aynen geçerli. Yasa 7 aynen:
kamuya giden her sayı ledger'dan türetilir, elle yazılmaz.

---

## 0. NEDEN 3 — koşu 2 çöktüğü için değil, ŞİŞTİĞİ için kapatıldı

Koşu 2 çalıştı: 21 tur döndü, B6 smoke 19/19 geçti, OPERATÖR durağı sekiz kez
ateşledi, tekrar freni tur 17'de doğru hüküm verdi ("bu tekrar değil, farklı
duvar"), DENEMELER 27. denemeye kadar birikti. Bu mekanizma korunur.

Kapatılma sebebi mekanizma değil, **her turun context faturasıdır.** İki
ölçülmüş kaynak var:

**1) Değerlendireni her turda transkriptle besliyorduk.** `kos.sh`'ın
`karar_ham` bloğu her turda şunu tek prompt'a yığıyordu:

| girdi | boyut |
|---|---|
| `cat KOSU-RABADON-2.md` (tamamı) | ~35 KB |
| `tail -c $OUT_B` yapan oturumun HAM çıktısı | ≤150 KB |
| önceki 3 kararın TAMAMI | ~5 KB |
| DENEMELER (2 dosya × 60 satır) | ~4 KB |
| GUNLUK + git log + OPERATOR | ~4 KB |

Tur başına ~200 KB ≈ 50k token, 21 tur. Bunun içinde **hiç okunmaması gereken
tek şey ham transkriptti**: değerlendiren yapanın gerekçelerini değil
kanıtlarını okur (B3'ün kendi kuralı), ama biz ona gerekçelerin tamamını
veriyorduk ve "bakma" diyorduk.

**2) Ağır işi alt-ajana veriyorduk (B1.2).** Alt-ajan boşluğa ölmez,
**ebeveynine ölür**: son raporu ebeveynin context'ine yazılır. Görünmeden açılan
uzun ömürlü bir alt-ajanın özeti kısa olmaz. Ölçülmüş uç örnek (stitchu
tarafında, aynı desen): tek alt-ajan 21 sa 10 dk yaşadı, 154,4k token yaktı,
iki tanesi ebeveyni %91 context'e çıkardı.

v3'ün tamamı iki cümlenin sonucudur:

> **Ajan ölümü bedavadır, ajan DÖNÜŞÜ pahalıdır.**
> **Bir ajanın dönüşü yoktur; ajanın bıraktığı DOSYA vardır.**

Bir de bu belgenin kendisi context maliyetidir: koşu 2'de 567 satırdı ve her
tura giriyordu. v3'te değerlendiren bu dosyayı GÖRMEZ (bkz. B3) — yalnız
yapan görür, o da tur başına bir kez.

---

## A. Doğrulanmış durum (24.08, `main` 30d5cbb · `kosu2` c1e6e4d)

Aşağıdaki her satır kosu2 dalından okundu. Koşu 2'nin hiçbir "kapandı"
cümlesi kanıt sayılmadan alınmamıştır; sayılar `accept.turn21.out` ve
`DENEMELER.md`'den.

> **NOT (25.08, kosu3 kurulumu).** Bu belge yazıldıktan sonra kosu2'de bir tur
> daha (tur 22, `6f5d301`) koştu. §A2'nin iki kusuru O TURDA DÜZELTİLDİ ve
> `2b`'nin gözlem sayısı 5'ten 8'e çıktı. Güncel ve kanıtlı durum
> `reports/kosu/DURUM.md`'dedir; çelişkide DURUM.md kazanır (kanıt belgeyi
> yener — CLAUDE.md). §A1'in `5b` ön-kayıt sapması bulgusu AÇIK durmaktadır.

### A0. Kapalı
R0–R6 ACCEPTED. T1/T2 kimlik işi kapalı. B6 smoke: 19 assert / 19 PASS
(`reports/kosu/SMOKE.md`, ham `SMOKE.out`) — bu turda watchdog'un macOS'ta ÖLÜ
olduğu ve sürüm sabitlemenin iddia edilip yapılmadığı bulundu, ikisi de kapandı.

### A1. R7 — **23 yeşil / 3 kırmızı + 1 gizli kırmızı, NOT ACCEPTED**
Kanıt kolu indi: `reports/R7/ab_run.jsonl`, 8 kayıt, A:4 / B:4 görev.
GOAL 5 tam yeşil, GOAL 8 tam yeşil (moves 21/0, signals 39/0, R2 19/0).
Beş sayının dördü çıktı: düzeltme oranı A %75 / B %75 · token A 35620 /
B 33221 · insan müdahalesi 0/0 · yanlış pozitif 0/0.

Üç kırmızı, tur 20'den beri aynı:

- **`2b` latans.** Tavan 1000 µs. Beş örnek (85 dk): 3302,3 · 1846,2 · 3002,8 ·
  2112,6 · **1218,3** µs. Yük–latans r=+0,737 (1 dk) / +0,684 (15 dk), ilişki
  gerçek ama **monoton değil** — yük tek açıklayıcı değişken değil, varyansın
  ~%55'i ölçülmemiş.
- **`6e`** — B kolunda `estimated_saved` toplamı yok, sayaç doğrulanamıyor.
- **`7b`** — yanlışlama-2 hesaplanamıyor, sapma üretilemiyor.

- **`5b` — ÖN-KAYIT SAPMASI (bu koşuda bulundu, accept.sh göremiyor).**
  `reports/R7/ON-KAYIT.md` koşudan önce donmuş: **N = 6 görev × 2 kol**, altı
  instance isim isim. `ab_run.jsonl`'de duran: **4 görev × 2 kol**. Eksik ikisi
  `joke2k__faker.8b401a7d` ve `pylint-dev__astroid.b114f6b5`. GOAL 5b yeşil
  basıyor çünkü kol başına ≥2 arıyor — oysa ön-kayıtın kendi cümlesi "bu şart
  bir TABANDIR, hedef değil" diyor. Kabul betiği hedefi değil gevşemiş vekilini
  denetliyor; 2b'nin kirli ölçümüyle aynı sınıf. **Düzeltme:** `5b`, sabit taban
  yerine ON-KAYIT'taki N'i okuyacak. **Sonuç:** 7a şu an "enjeksiyon tezi
  ayakta" hükmünü n=4'te veriyor; düzeltme oranı A %75 / B %75 ÖZDEŞ, fark
  yalnız token'da (%6,7). Ön-kayıtın kendi Yasa 7 cümlesi bunu zaten yasaklıyor:
  gürültü içinde kalan fark "kurtarır" diye yayınlanmaz.

`6e`/`7b`'nin kökü aynı ve **ürün gerçeğidir:** `MIN_HISTORY=3` yüzünden tek
oturumluk koşuda `estimated_saved` üretilmiyor. Bu kırmızıyı yeşile çekmek için
`MIN_HISTORY` OYNANMAYACAK (operatör bağlaması, deneme 26). Yeşile dönüş yolu
ya çok oturumlu koşu ya da GOAL'in yeniden ifadesidir — ikisi de karar.

### A2. R7'nin ölçüm hijyeni BOZUK — 2b'ye hüküm verilmeden önce kapanmalı
İki kusur `reports/R7/CHALLENGE-5.md`'de duruyor, ikisi de DÜZELTİLMEDİ:

- **`olc_2b.sh`'ın hükmü ters.** Betik `min ≥ 1000 → KESİN KIRMIZI` basıyor,
  gerekçesi "daha temiz ölçüm matematiksel olarak daha düşük olamaz". Bu kendi
  fizik önermesinin tersi: `ölçülen ≥ temiz` ise `min(ölçülen)` temiz değerin
  **ÜST** sınırıdır. Tek geçerli çıkarım `temiz ≤ 1218,3 µs` ve bu `< 1000`'i
  **dışlamaz**. 2b yine kırmızı; değişen tek şey etiketi — "kesin, makine
  bahanesi bitti" değil, "bu makinede kırmızı".
- **B1.9 artık-süreç kontrolü hiç ateşlenemiyor.** `pgrep -c` macOS BSD'de yok;
  usage hatası `|| echo 0`'a düşüyor, kontrol her zaman 0 basıyor. Beş ölçümün
  **beşi de** 6 sa 23 dk'dır ayakta olan başıboş bir `rabadon-gated-sprof`
  (PID 60547) canlıyken alındı ve rapor beş kez "rabadon-gated 0" yazdı.

**Hüküm: 2b'nin beş ölçümü de KİRLİ ortamda alınmıştır ve temiz-ortam değeri
BİLİNMİYOR.** Kirli ölçümün üstüne etiket yapıştırmak Yasa 7 ihlalidir.

### A3. R8 — yayın (bloklu)
`package.json` 0.2.3, npm'de 404, tag yok. **BLOK:** `make disclosure` tasarım
gereği kırmızı — `site/allowlist.py` tam eşleşmeyle çalışıyor, fail-closed, ve
41 liste dışı isim var (`reports/R8/DISCLOSURE.md`, ölçüm ca1ea4e). Ya 41 isim
listeye girer/temizlenir, ya disclosure kapısı yayın kapısı olmaktan çıkar.
YAYIN kararı OPERATÖR'dedir. Karar gerektirmeyen işler (17/18 binary
uyuşmazlığı, tag, plugin paketi, 10k additionalContext kesme testi) açıktır.

### A4. M0–M4 — hiç başlamadı
A0'ın POSITIONING görevi (Watcher/Mindlas ile güncelleme, "kimse yok" cümlesini
silme) M3'e bağlı. `docs/SAVUNMA.md` ve landing M4'te. Fiyat ve her kamuya
yayın adımı OPERATÖR.

### A5. İzlenecek (kırmızı değil, trend yanlış yönde)
`2c` %3,35 → **%6,50**. Tavan %10, ama R1.3'ün %3,5–4,9 bandı aşıldı ve latans
düştükçe yüzde büyür. Her turda bakılır, sessizce aşılmaz.

### A6. Sıra
Bekleyen iki karar (§C.1) → ön-kayıt sapması (eksik iki görev koşulur ya da
sebebi ON-KAYIT'a yazılır; 5b düzeltilir) → ölçüm hijyeni (A2'nin iki kusuru) → 2b temiz ölçüm
→ 6e/7b karar → R8 "yeşil main" kararı + karar gerektirmeyen R8 işleri → R8 →
M3 → M4. M0–M2'nin R tarafı kapalı; paralel oturumlara dağıtılabilir, kamuya
YAYINLAMA hariç.

---

## B. Orkestrasyon v3 — süreçler, dosyalar, ince değerlendiren

### B0. İlke (değişmez)
**Yapan süreç → değerlendiren süreç → yapan süreç.** Yapanın **DEVİR DOSYASI**
değerlendirene gider; transkripti gitmez. Değerlendiren sonraki talimatı yazar.
Yapanın metninde desen/keyword aranmaz. "Soru" durum bildirimidir, karar değil.
**Operatör kurye değildir**; ona yalnız B4 listesi düşer.

### B1. Context yasaları (koşu 2'nin B1'i + üç yeni yasa)

1. **Her tur taze süreç.** `claude -p`, sıfır miras. Devir dosyalardan.
2. **ALT-AJAN (Task) YASAK. İşçi de süreçtir.** Ağır iş — repo taraması, uzun
   derleme/bench, log analizi — `scripts/isci.sh` ile AYRI SÜREÇTE koşar;
   stdout `/dev/null`'a, ham çıktı `reports/kosu/log/`'a gider. Yapan sonra
   `reports/kosu/RAPOR/<ad>.md` dosyasını **okumayı seçer** — 12 satır.
   *(Yeni. Koşu 2'nin B1.2'si bunun tersini söylüyordu ve şişmenin yarısıydı.)*
3. **Dönen metnin tavanını SÜREÇ uygular.** "12 satırı aşma" niyet beyanıdır;
   `head -12` hükümdür. Her rapor yazıldıktan sonra kabuk kırpar. *(Yeni.)*
4. **Değerlendiren HAM ÇIKTI GÖRMEZ.** Yapan turu bitirirken
   `reports/kosu/DEVIR.md`'yi B7 şablonuyla YENİDEN yazar (≤40 satır, sürücü
   mekanik kırpar). Değerlendirenin girdisi budur. Transkript diskte delil
   olarak yaşar ve yalnız YOL olarak anılır. *(Yeni.)*
5. **DENEMELER.md — birikimli teşhis hafızası.** Tur kırmızıysa o turda çalışan
   oturum `reports/<tur>/DENEMELER.md`'ye tek blok ekler: DENENEN · SONUÇ ·
   ELENEN HİPOTEZ · KALAN HİPOTEZLER. Strateji kararları buradan verilir.
6. **Koşu izole; dogfooding zırhlı.** Döngü taze worktree'de, `kosu3` dalında.
   Rabadon kapısı yalnız sarmalayıcıyla bağlanır:
   `sh -c 'timeout 2 <gate> ... </dev/null; exit 0'`. Bağlama kabulü ledger'da
   yeni satır GÖSTERMEKTİR; göstermeyen bağlanmamıştır.
7. **Ortam interaktif-imkânsız + iki nabızlı watchdog.** `GIT_TERMINAL_PROMPT=0`,
   `CI=1`, `npm_config_yes=true`, `DEBIAN_FRONTEND=noninteractive`, stdin
   `/dev/null`. Nabız: çıktı büyümesi VEYA worktree dosya aktivitesi (`-cnewer`).
8. **Tek yazar ilkesi.** GUNLUK.tsv → yalnız sürücü. `reports/<tur>/DENEMELER.md`
   → yalnız o turun yapanı. DEVIR.md → yalnız o turun yapanı. OPERATOR.md →
   değerlendiren soru, operatör CEVAP.
9. **Worktree dokunulmazdır.** `git checkout main`, `branch -D`, `reset --hard`,
   `.git` yapısına dokunmak YASAK. main'e taşıma yalnız tur kabulü yeşilken,
   değerlendiren talimatıyla, tek squash-merge.
10. **Artık süreç bırakılmaz — ve kontrolü TAŞINABİLİR olmalı.** Her arka plan
    işi `timeout` sarılı. Kontrol `pgrep -c` KULLANMAZ (BSD'de yok, A2):
    `pgrep -f <ad> | wc -l` kullanılır ve kontrolün kendisi kasıtlı bir
    süreçle bir kez kırmızıya döndürülüp kanıtlanır. *(A2'nin dersi.)*

### B2. Sürücü — `scripts/kos.sh` (koşu 2'den üç fark)

Koşu 2'nin sürücüsü korunur — trap/grup_oldur zırhı, iki nabızlı watchdog,
`pusla()`, disk+inode+/tmp kontrolü, ONAY mührü, rc-kalkanı, dar bütçe,
`i` monotonluğu, git kilidi→abort sırası. Üç şey değişir:

**(1) Değerlendiren girdisi transkriptsizdir.** `karar_ham` bloğu şu olur:

```bash
  karar_ham="$(
    { echo '----- DURUM (kisa) -----';           cat reports/kosu/DURUM.md
      echo '----- DEVIR (bu turun ciktisi) -----'; head -40 reports/kosu/DEVIR.md
      echo '----- GUNLUK (tekrar sayaci) -----';  tail -20 "$GUNLUK"
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
      echo "reports/kosu/$i.out"
    } | timeout 900 claude -p --model sonnet "$(cat docs/DEGERLENDIREN.md)"
  )"
```

`cat KOSU-RABADON-3.md` ve `tail -c 150000 $i.out` **kaldırıldı**. Girdi tur
başına ~200 KB'den ~15 KB'ye iner. `reports/kosu/DURUM.md` bu belgenin §A'sının
≤50 satırlık türevidir ve her tur kapanışında yapan tarafından tazelenir.

**(2) DEVİR tavanını sürücü uygular.** Yapan `DEVIR.md` yazmadıysa tur
KOŞMAMIŞ sayılır (kırmızı değil — B1.5'in ruhu):

```bash
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
```

**(3) İlk talimat DEVİR yazmayı emreder.** Varsayılan talimatın sonu:
`"...raporu yaz, reports/kosu/DEVIR.md'yi B7 sablonuyla YENIDEN yaz, DURUM.md'yi tazele, commit+push et."`

### B3. Değerlendiren — `docs/DEGERLENDIREN.md`

Koşu 2'nin metni korunur (MÜHENDİS DEĞİL YÖNLENDİRİCİ · gerekçe değil kanıt
oku · tekrar kontrolü · DENEMELER'den strateji · 3'te yaklaşım değiştir, 6'da
operatöre · thrash → küçük adımlar · üç biçim, ilk satır belirler · 150 satır
tavanı). Değişen ve eklenen:

- **Sana DURUM + DEVİR verildi, transkript VERİLMEDİ.** Yapanın ne dediğini
  değil ne BIRAKTIĞINI okursun. Ham çıktının yolu girdinin sonunda duruyor;
  **onu sen okumazsın** — gerekiyorsa bir sonraki yapana okutursun.
- **DEVİR'de sayı yoksa ilk talimatın onu ürettirmektir.** "Kabul betiği koştu"
  cümlesi kanıt değildir; kabul betiğinin SAYISI kanıttır.
- **İşçi salınacaksa talimatın `scripts/isci.sh`'yi ADIYLA yazar.** Alt-ajan
  öneren talimat biçim ihlalidir (B1.2).
- Kural: §A6 sırası ve tur kabul betikleri ölçüttür. Kısmi kabulle sonraki tur
  başlamaz.

### B4. Operatöre giden beş kategori (değişmez)
fiyat · ürün konumlandırma · kamuya yayın · sahiplik · geri dönüşsüz işler
(sürücünün tavan/bekleme durakları beşincinin üyesi).

### B5. Bütçe ve fren
Sürücü: `MAX_ITER` (tavanda durak) · `SESSION_TIMEOUT` · `STALL_TIMEOUT` ·
`MAX_WAIT_S` · `RAW_MAX`. Değerlendiren: DENEMELER tabanlı hipotez eleme ·
3-tekrar yaklaşım değişimi · 6-tekrar OPERATÖR. DRIFT.md'nin üç kırmızı bayrağı
aynen. **Yeni fren:** değerlendiren girdisi 30 KB'yi aşarsa DURAK — girdi
büyüyorsa DEVİR disiplini bozulmuş demektir, karar değil temizlik gerekir.

### B6. Döngünün kendi kabulü (SMOKE — ilk turun asıl işi)
Koşu 2'nin B6'sı 19/19 geçti ve **yeniden koşulmaz**; yalnız v3'ün üç
farkı kanıtlanır:

1. `scripts/isci.sh` bir işçi koşar, `RAPOR/*.md` 12 satırda kırpılmış olarak
   yazılır, yapanın stdout'una işçiden **tek bayt** girmez (log dosyası dolu,
   stdout boş — ikisi de gösterilir).
2. Bir tur boyunca değerlendiren girdisi ölçülür ve **< 30 KB** çıkar
   (`wc -c`, GUNLUK'a yazılır).
3. Yapan kasıtlı olarak DEVİR yazmadan bitirilir; sürücünün "KOSMADI" bloğunu
   yazdığı ve döngünün kırmızı saymadan devam ettiği gösterilir.

Bu üçü olmadan hiçbir R turuna başlanmaz.

### B7. DEVİR şablonu — `reports/kosu/DEVIR.md` (≤40 satır)

```
TUR: <n>  ·  DURUM: KAPANDI | YARIM | KOSMADI
KABUL: <betik> → <yesil>/<kirmizi>   (yoksa: kosulmadi + sebep)
KIRMIZI ADLARI: <ad> · <ad>          (yalniz AD, cikti degil)
OLCULEN: <ad>=<deger> (<komut>)      (en fazla 5 satir)
YAPILAMAYAN: <tek cumle sebep>
DENEMELER: deneme <n> eklendi | eklenmedi (sebep)
COMMIT: <hash>  ·  HAM: reports/kosu/<n>.out
SONRAKI TURA UYARI: <tek cumle>      (yoksa satir yazilmaz)
```

Yasak: gerekçe paragrafı, anlatı, log yapıştırma, "şunu yapmaya çalıştım".
Uzun anlatı tur raporuna gider ve değerlendiren onu okumaz.

---

## C. Başlatma

### C.1 Devralınan iki karar — döngü BAŞLAMADAN önce
Koşu 2, `reports/kosu/OPERATOR.md`'de cevaplanmamış iki soruyla kapandı.
Bunlar `kosu3`'ün ilk OPERATÖR durağıdır ve A2'nin ölçüm hijyeni yüzünden
**önerileri değişmiştir**:

- **2b nasıl kapanacak?** Koşu 2'nin değerlendireni "(c) bu makinede kırmızı
  etiketle kapat" önerdi. **Bu öneri artık geçersiz:** beş ölçümün beşi de
  başıboş daemon canlıyken alındı (A2), yani "bu makinede" ifadesi de
  ölçülmemiş. Sıra: (1) `pgrep -f` düzeltmesi + kontrolün kırmızıya
  dönebildiğinin kanıtı, (2) `kill 60547` + Chrome kapalı, (3) TEK örnek.
  ~25 dk, sıfır kurulum. Altına inerse 2b zaten yeşil; inmezse "temiz makinede
  kırmızı" artık kanıtlı bir etikettir ve (c) meşrulaşır.
- **CHALLENGE-5 `olc_2b.sh` mantık hatası?** (a) betiği düzelt — hükmü
  "temiz ≤ min" olarak yaz. Tek satır, ölçülen değer değişmez, yalnız
  kurulamayan cümle kurulmaz olur.

> **NOT (25.08).** Bu iki maddenin İŞ kısmı tur 22'de yapıldı (bkz. DURUM.md):
> `pgrep -f` düzeltildi, `olc_2b.sh`'ın hükmü "temiz ≤ min" olarak yeniden
> yazıldı, daemon öldürüldükten sonra 3 örnek daha alındı (min hâlâ 1218,3 µs).
> `reports/kosu/OPERATOR.md`'de bekleyen soru bu yüzden GÜNCELLENMİŞ hâliyle
> duruyor: 2b nasıl kapanacak (CI mi, kopar-parked mi) ve 6e/7b fixture mı.
> Cevap OPERATÖR'ündür; döngü ONAY mührünü bekler.

### C.2 Ön kontrol (ilk oturum yapar)
`git push --dry-run` credential sormadan geçiyor mu · `GIT_TERMINAL_PROMPT=0`
altında test komutu asılmadan dönüyor mu · `python3` var mı · `claude --version`
`reports/kosu/ONKONTROL.md`'ye KAYDEDİLDİ mi (koşu boyunca auto-update kapalı).
**v3 eki:** `pgrep -f rabadon | wc -l` doğru sayı basıyor mu (A2) ve
`reports/kosu/log/`, `reports/kosu/RAPOR/` dizinleri var mı.
Kırmızıysa döngü BAŞLAMAZ.

### C.3 Claude Code'a tek talimat

    KOSU-RABADON-3.md repo köküne kondu. Oku. İlk işin: B2'deki kos.sh üç
    farkını mevcut scripts/kos.sh'a uygulamak, B3'teki DEGERLENDIREN.md
    eklerini yazmak, scripts/isci.sh'yi kurmak, §A'dan reports/kosu/DURUM.md'yi
    (≤50 satır) türetmek, koşu için kosu3 dalında taze worktree hazırlamak ve
    C.2 ön kontrolünü koşup ONKONTROL.md'ye yazmak. Rabadon kapısını BAĞLAMA.
    Turlara BAŞLAMA.

### C.4 Sonra

    tmux new -d -s rabadon scripts/kos.sh

İlk çevrimler B6'nın üç maddesidir; döngü onları kendisi koşar. Ardından ilk
OPERATÖR durağı C.1'in iki sorusudur.

Sonrası: `reports/kosu/OPERATOR.md`'ye `CEVAP:` satırları, EN SONA tek başına
`ONAY`. Mühürsüz cevap işlenmez. Oturum çıktısı okumak yok — okunacak çıktı
zaten context'e giren çıktıdır ve v3'ün tamamı onu engellemek üzerine kurulu.
Uzaktan izliyorsan önce `PUSH-HATA.log` boş mu bak.
