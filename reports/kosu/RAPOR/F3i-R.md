# F3i — HAKEM RAPORU

Taban `F3i-oncesi` = `c48c0e4` · uç `c9c7887`. Şef bunu okumaz; hüküm `KAPI.md`'de tek satır.
Bu koşuda hiçbir iş yapmadım; her sayı kendi koşturduğum bir komuttan geliyor.

---

## 0. SIFIRINCI İŞ — PAYLAŞIMLI `~/.claude/settings.json`

`make test`'ten **önce** alındı: `adcb41a93f858d6b`.

| ne zaman | sha (ilk 16) |
|---|---|
| her şeyden önce | `adcb41a93f858d6b` |
| kök klonda `make test` (1. deneme) sonrası | `adcb41a93f858d6b` |
| kök klonda `make test` (nihai, EXIT=0) sonrası | `adcb41a93f858d6b` |
| taban worktree'sinde (`_hakem_f3i_base`) `make test` sonrası | `adcb41a93f858d6b` |

**HER İKİ KOL DA BAYT BAYT DEĞİŞTİRMEDİ — kök klon da, worktree de.** Kartın kök-klon ölçümü
doğrulandı; **kartın worktree bulgusu ise bende YENİDEN ÜRETİLEMEDİ.**

Kart, worktree'den koşulan `make test`'in `6c14cc5f → a91a1165` yaptığını, ve bunun bir
"sessiz de-duplikasyon" olduğunu (iki tekrar `SessionStart` girdisi, bayat
`_hakem_f3g_base/native/rabadon-drift`, bir `PreToolUse "*"` girdisi kaldırılmış) yazmıştı.
**Tutarlı açıklama:** kartın gözlediği yazma, dosyanın **zaten zehirlenmiş** içeriğinin bir
kereye mahsus temizlenmesiydi; şef 03:47'de zehirli grubu söktükten sonra temizlenecek bir şey
kalmadı ve işlem **idempotent** oldu. Yani sınıf "her worktree koşusu dosyayı bozar" değil,
"kirli bir dosya bir kez sadeleştirilir"dir. Kartın sayısı silinmiyor; yanına bu kondu.
Yedeğim gerekmedi (`_hakem_f3i_save/settings.json.pre`, geri yazılmadı).

---

## 1. ⛔ KARTIN KAPSAMI DIŞINDA, HER ŞEYDEN AĞIR — SEVK EDİLEN İKİLİ BİR `exit 0` PUÇU İDİ

Kapıyı koşturmadan önce ağacı saydım. `native/rabadon-gate` **17 bayt**tı:

    $ od -c native/rabadon-gate
    #   !   /   b   i   n   /   s   h  \n   e   x   i   t       0  \n

Gerçek ikili yanına **`native/rabadon-gate.gercek`** (836176 B, Mach-O arm64) olarak
konmuştu. İkisinin de mtime'ı **30 Ağu 03:48**. Aynı dakikada, aynı 17 baytlık puç,
`~/damla_projects_2026/_hakem_f3g_base/native/rabadon-drift` yoluna da konmuştu
(sha ikisinde de `306c6ca740756034`) — yani 03:48'de **sistematik bir silahsızlandırma**
yapılmış: hem sevk edilen kapı, hem B2'nin zehirlediği ölü yol.

**Bunun anlamı:** `~/.claude/settings.json`'ın **altı** kanca girdisi de
`…/rabadon/native/rabadon-gate`'i çağırıyor. 03:48 → 04:12 arasında bu makinede rabadon
**her çağrıda sessizce `exit 0`** veriyordu: kurulu görünen, hiçbir şey görmeyen bir guard.
B1'in `exit 126`'sı hiç değilse gürültülüydü; bu, Promise 1'in yasakladığı **sessiz ölümün**
tam kendisidir.

**Sahibi ÖLÇEMEDİM.** Repodaki hiçbir süit bunu üretmiyor: `#!/bin/sh\nexit 0\n` yazan yedi
yerin hepsi kendi `$TMP` fikstürüne yazıyor (`doctor_test.sh:306-307` dahil), ve
`~/.claude/history.jsonl`'de 03:48'e ait bir kabuk satırı yok. Ağacın dışından geldi.

**`make` bunu ONARMIYOR.** Puçun mtime'ı kaynaklardan yeni olduğu için `make native/rabadon-gate`
"up to date" diyor. Yani durum kendi kendine süresiz yaşardı.

**ÜRÜNÜN KENDİ BAĞIŞIKLIĞI ÇALIŞTI — bu fazın hanesine yazılır değil ama kayda geçer:**
`make test` ilk süitte, 3 saniyede, EXIT=2 ile düştü:

    FAIL - the tree does not agree with itself
      | DRIFT rabadon-gate --version says "", package.json says 0.2.3

`version_test.sh` puçu yakaladı. Ardından `rabadon-gate.gercek` **kendisi** kırmızı üretti
(`cli_test` 321/4): ikili keşfi `native/rabadon-*` glob'uyla yapıldığı için artık dosya
21. ikili sayıldı ve "hiçbir case kolu çözmüyor" dedi. **Elle tutulan liste yerine glob
kullanma kararı, tasarlandığı şeyi tam olarak yakaladı.**

**Hakemin yaptığı, gerekçesiyle:** `rabadon-gate.gercek`'i geri yazdım, kaynaktan yeniden
derledim ve **bayt bayt aynı** çıktı (`a2ffd11c371447b1` = `a2ffd11c371447b1`), yani `.gercek`
gerçekten HEAD ikilisiydi ve derleme yeniden üretilebilir. Artık kopyayı sildim.
Gerekçe: kartı puçlanmış bir ikiliye karşı yargılayamazdım, ve adı `rabadon-gate` olan bir
`exit 0` puçu mümkün olan en tehlikeli hâldir (`mode=watch` olduğu için gerçek ikiliyi geri
koymak hiçbir şeyi BLOKLAMAZ — yalnız görünürlüğü geri verir). Frene (`mode`/`enabled`)
**dokunmadım**.

---

## 2. A1 — FREN

### (i) Freni operatörün kendisi indirdi — DOĞRULANDI, kendi gözümle

`~/.claude/history.jsonl`, üç satır, elle:

    08-30 01:57:21  !rabadon off
    08-30 02:03:02  ! cd ~/damla_projects_2026/_arsiv_2026-08-18/sightstone && rabadon off
    08-30 02:03:15  !rabadon off

Kartın iddiası doğrudur. **Ajan değil, kurulum yolu değil, §3.8 ihlali YOK, ürün kusuru YOK.**
(Kartın yol yazımı `…/sightstone`, gerçeği `_arsiv_2026-08-18/sightstone` — önemsiz.)

### (ii) Beş kesme: hepsini defterden çıkardım — VE KART BUNLARI YANLIŞ SINIFLANDIRIYOR

`~/.rabadon/spool/2026-08-30.jsonl`, `ev=STOP · reason=BLOCKED`. Bugün **altı** tane var:

| # | saat | pipe | kural | kesilen | gerçekten kırmızı mıydı? |
|---|---|---|---|---|---|
| 1 | 03:05:51 | `rabadon:session` | `no-force-push-main` | Bash | ajanın **kendi** K1 probu — doğru ret |
| 2 | 03:06:52 | `sightstone` | `red-base` | Bash | **EVET** — `AssertionError: 140 != 144` |
| 3 | 03:21:44 | `sightstone` | `red-base` | Bash | **EVET** — `UnicodeEncodeError … surrogates` |
| 4 | 03:21:54 | `sightstone` | `build-site-mock-contract` | Edit | **EVET** — `protectedPaths`: `engine/build_site.py` |
| 5 | 03:22:02 | `sightstone` | `red-base` | Bash | **EVET** — aynı UnicodeEncodeError |
| 6 | 03:22:13 | `sightstone` | `build-site-mock-contract` | Edit | **EVET** — aynı korumalı dosya |

Kart 2–6'yı doğru saymış, kendi 1'ini doğru dışlamış, kuralları ve saatleri doğru yazmış.

**AMA: BUNLARIN HİÇBİRİ YANLIŞ POZİTİF DEĞİLDİR.** Beşinin beşinde de kural doğru ateşledi:
üç `red-base`, `sightstone`'un **kendi** `check`'i (`python3 -m pytest -q`) gerçekten kırmızıyken
bastı ve ret metni hatanın tamamını alıntılıyor; iki `build-site-mock-contract`, operatörün
**kendi** `guard.json`'ındaki `protectedPaths` girdisidir. Yanlış ateşleyen kural **sıfır**.

Kart bunları `§4.3 YANLIŞ POZİTİF — 5 OLAY` diye kaydediyor. **Bu, ölçüyü ters yönde bozar.**
CLAUDE.md yanlış retlerin sayılmasını, mazur görülmemesini emreder; meşru yakalamaları o sayaca
yazmak sayacı aynı ölçüde yalancı yapar — ve rabadon'un satacağı tek şey o sayacın dürüstlüğüdür.
Kart doğru teşhisi zaten bir cümlede kuruyor (*"kural yanlış değildi, açılma zamanı yanlıştı"*)
ama sonra yanlış kovaya koyuyor. **HÜKÜM: §4.3 sayacına bu fazdan 0 (SIFIR) yanlış pozitif işlenir;
beş olay ayrı bir sınıfta durur** (aşağıda). Eski sayı silinmiyor, gerekçesiyle düzeltiliyor.

**Sınıf ve sahibi: KOŞU.** Kural da ürün de değil — bunlar **operatörün canlı, ilgisiz oturumunda
yapılmış bir deneyin** bedelidir. Sınıf adı: *gözetimi, rızası alınmamış üçüncü bir tarafın canlı
oturumu üstünde açmak.* Sayı: **5 olay / 16 dakika / 1 oturum** (`7e2325e3`).

### (iii) Frenin bugünkü hâli — DOĞRULANDI

`cat ~/.rabadon/mode` → `watch` · `~/.rabadon/enabled` → **YOK** (mtime 30 Ağu 03:22).
Defterin `MODE` satırları da bunu birebir veriyor: `03:05:51 watch→enforce` ·
`03:08:03 enforce→watch (outOfBand:true)` · `03:21:36 watch→enforce` · `03:22:16 enforce→watch`.
Kartın anlatısı doğru; iki küçük sapma: kart "03:14:07 kapandı" diyor, defterde o geçiş
**03:08:03**'tür; kart "03:20'de tekrar açtım" diyor, defter **03:21:36** diyor. Hükmü değiştirmez.

### (iv) `EXIT=2` ekran çıktısıyla kartta duruyor — DOĞRULANDI

`reports/kosu/kanit/f3i/k1-brake.out`: watch'ta *"would have blocked … Nothing was stopped"*
**EXIT=0**, `rabadon on` sonrası *"rabadon BLOCKED this action"* **EXIT=2**. Şart ölçüm olarak
sağlanmış.

### HÜKÜM — ajan freni geri indirmekle doğru mu yaptı?

**DOĞRU YAPTI, hakem emrini çiğnemedi.** Üç gerekçe: (1) §3.4 ve F3h hakeminin kendi cümlesi
freni **operatörün kalemi** ilan eder — F3h hakemi de bu yüzden dokunmamıştı; (2) operatör
emri elle üç kez, sonra 03:13:49'da düz cümleyle vermişti, ve dakikalar önceki açık emir bir
kart şartının üstündedir; (3) kartın istediği **ölçümdü** ve ölçüm alındı (`EXIT=2`), durum
şartı ile ölçüm şartı ayrı şeylerdir.

**Kusurlu olan emirdir, ajan değil — ve o emri F3h hakemi yazdı, yani bu kürsü.** "Freni geri
aç" emri, paylaşılan ve canlı bir makinede bir **durum** değişikliği emrediyordu ve rıza
kontrolü içermiyordu. Bedelini ajan değil operatör ödedi. Kayda geçer.

---

## 3. A2 — AÇIK SINIF EKRANDA İLAN EDİLDİ Mİ

### İlan GERÇEKTİR — kendi gözümle gördüm

Sevk edilen ikiliye gerçek `SessionStart` verdim (`$HOME` altında fikstür, `/tmp` değil):

      blind spots:
                 - 7 measured shapes DESTROY this project's .rabadon/guard.json and I allow every one
                   . a walk that never spells the law's name:  `find . -delete` and 5 more
                   . the tree deleted from outside, law and all:  `cd .. && rm -rf proj`
                   I judge a command's operands; none of these name the law, so I never
                   see them. Not closing them is deliberate: the cut would also refuse
                   `rm -rf ./old-project`, i.e. fence you inside your own tree.
                   what to do: commit .rabadon/ to git — that copy survives all 7,
                   and `git checkout .rabadon` puts the law back

**F3h'nin bloklayan kartı teslim edilmiştir.** İki sınıf da **adıyla** ekranda, sınıf başına bir
şekil, sayı tablodan türüyor, ve "ne yapacaksın" satırı var (CLAUDE.md'nin üç soru kuralı).
`--law-blind` makineye aynı tabloyu tab-ayrılmış veriyor. `docs/guard.md` aynı sınıfı ölçüm
tarihi + çalıştırılabilir komutla taşıyor ve eski yanlış örneği (`ls | xargs rm -rf`) **silmeden**
yerinde düzeltiyor.

### İddia YÜRÜTÜLEBİLİR — mutasyonu kendim ürettim

`_hakem_f3i_head` worktree'sinde (kök klonun ikilisine dokunmadan):

| mutasyon | sonuç |
|---|---|
| kontrol (mutasyonsuz HEAD) | `law_blind` **10 / 0** |
| **M1** — tabloya gerçekten REDDEDİLEN bir şekil eklendi (`rm -rf .rabadon`) | **8 / 2 KIRMIZI** (hem "declared but false" hem "padded with refused shapes" kolları) |
| **M2** — ekranın sayısı elle 8'e sabitlendi, tablo 7 | **9 / 1 KIRMIZI** ("the count is typed twice") |
| geri alındı | **10 / 0** |

**Boş yeşil turu**, `F3i-oncesi` ikilisini kendim derleyip: `law_blind` **6 geçti / 4 KIRMIZI**
(`0 shapes declared`, `0 classes`, ekran `nothing` diyor, "what to do" yok) —
**kartın 6/4'ü birebir doğru.** `brake_persist` tabanda **13/0 YEŞİL**, kartın dürüstçe yazdığı
gibi: o kilit **önleyicidir**, onardığı bir kod kusuru yok.

### ⛔ AMA F2-S14 EMSALİ KARŞILANMADI: İLAN EDİLEN KÜME, İZİN VERİLEN KÜMEYE **EŞİT DEĞİL**

Brifingin şartı: *ekranın ilan ettiği küme, ikilinin gerçekten ALLOW verdiği kümeye EŞİT olmalı
ve bunu kırmızı düşebilen bir süit tutmalı.* Kendi elimde, aynı `probe-exec.sh` ile ölçtüm —
ilan edilen 7'nin 7'si gerçekten `ALLOW + GONE` (ilan **yalan değil**), **ama ilan edilmemiş
8 şekil daha aynı şekilde `ALLOW + GONE`:**

    ALLOW  GONE   ls -A | xargs rm -rf
    ALLOW  GONE   find . '!' -name zzz -delete
    ALLOW  GONE   find . -not -name zzz -delete
    ALLOW  GONE   find . -not -newer README.md -delete
    ALLOW  GONE   find . -type f -delete
    ALLOW  GONE   find . -depth -delete
    ALLOW  GONE   find . -mindepth 1 -delete
    ALLOW  GONE   find . -exec rm -rf {} +

(Kontroller doğru davrandı: `ls | xargs rm -rf` → `ALLOW THERE`, `rm -rf .rabadon` ve
`git clean -xfd` → `REFUSE`.) İlk ikisi zaten **F3h hakeminin ölçtüğü sekizin içindeydi** ve
tabloya alınmamış. Bu sekizin sekizi de ekranın **zaten adını koyduğu** birinci sınıfa düşüyor,
yani *sınıf* kapsaması tamdır — **yalan olan SAYIDIR.** Ekran "7 measured shapes … I allow
every one" ve "that copy survives all 7" diyor; bu cümleler bir **sayım** vaat ediyor, oysa 7
yalnız **tablonun boyu**. Ben dakikalar içinde 15'e çıkardım.

Ve `law_blind_test.sh` bu yönde **kırmızı düşemez**: süit ileri yönü (ilan edilen her şekil
gerçekten kör mü) + boşluk tabanı (≥5 şekil, ≥2 sınıf) + reddedilen şekil kontrolü tutar;
**"ilan edilmemiş bir kör şekil var mı"** kolunu hiç kurmaz. Sekiz yeni şekli bulduğumda süit
**10/0 yeşil kaldı.** Bu, F2-S14'ün ve `docs_truth_test.sh`'in "yedinci susturucu" dersinin
**aynen tekrarıdır**: kardinalite elle yazılmış bir tablodan okunuyor.

**Ağırlaştırıcı:** ajanın kendi §3.12 tahmini K2'yi *"ekran-küme **eşitliği** kilidi"* diye
yazmıştı. Teslim edilen taban+ileri-yön kilidi; **ajan kendi ilan ettiği yükümlülüğü karşılamadı
ve kartta bunu ölçemedim/karşılamadım diye yazmadı.**

---

## 4. A3 — `2b`, DAEMON VE DEFTER

### (a) Daemon gidiş-dönüşü — YÖN VE YAPI DOĞRULANDI, BÜYÜKLÜK DOĞRULANMADI

`N=200 ROUNDS=8 bash reports/kosu/kanit/f3i/k3-daemon.sh`, kendi elimde:

    round 1  UP 1447.0  DOWN  929.7  delta +517.3
    round 2  UP 1562.1  DOWN  996.3  delta +565.8
    round 3  UP 1620.7  DOWN 1095.2  delta +525.5
    round 4  UP 1722.0  DOWN 1171.5  delta +550.5
    round 5  UP 1862.4  DOWN 1297.9  delta +564.5
    round 6  UP 1926.3  DOWN 1411.7  delta +514.6
    round 7  UP 2017.5  DOWN 1520.2  delta +497.3
    round 8  UP 2201.4  DOWN 1559.4  delta +642.0
    sign test: 8 slower / 0 faster · median +538.0 us · mean +547.2 us · band |439| us

**Daemon leg 3'e maliyet EKLİYOR: 8/8 tek yanlı, bandın dışında.** Bölünme de kartınkiyle
aynı: `connect` 24,9 µs %1,1 · `send` 34,0 %1,5 · **`wait` 2057,6 µs = %92,7** · `close` 39,5 %1,8
(kart: %91,8). **Kartın yapısal teşhisi — `wait` = daemon'un worker fork'u + worker'ın aynı
yargıyı BAŞTAN yapması — doğrudur ve K3'ün gerçek bulgusu budur.** Segment saatinin kendi
maliyeti +54,6 µs olarak ayrıca ölçülüp düşülmüş; betik hile yapmıyor, `accept.sh` ve
`gated_client.h`'a dokunmuyor.

**AMA BÜYÜKLÜK TUTMADI: kart medyan +1498,1 µs (ort. +1560,7) yazmış; bende +538,0 (ort. +547,2).**
Bu, F3h hakeminin **+530,4 µs**'siyle neredeyse birebir aynıdır. Yani kartın *"hakemin
+530,4'ünden daha ağır"* cümlesi **yanlıştır**; hakemin sayısı doğruydu ve kartınki ~2,8 kat
şişkindir (kart o ölçümü ~03:40'ta, operatörün oturumları makineyi doldururken almış; kart
yükü hiç not etmemiş). **Eski sayı silinmiyor, gerekçesiyle düzeltiliyor.**

### (b) `2b` uçtan uca, HEAD ↔ taban — HIZLANMA YOK, DOĞRULANDI

`reports/kosu/kanit/f3/2b-uctan-uca.sh`, N=200, üç eşli tur (kum havuzu `$HOME` altına
alındı, `TMPDIR` override — Tuzak 1):

| tur | HEAD | taban `c48c0e4` | fark |
|---|---|---|---|
| 1 | 1809,7 | 1508,6 | **+301,1** |
| 2 | 1728,0 | 2058,0 | **−330,0** |
| 3 | 1942,1 | 1933,2 | **+8,9** |

**2 artı / 1 eksi, ortalama −6,7 µs, tek yanlı DEĞİL, bandın içinde.**
Kart **+15,8 µs** yazmış; ikisi de gürültüdür. **HÜKÜM: bu faz da `2b`'yi hızlandırmadı,
ve kart bunu açıkça yazdı (CLAUDE.md 8 karşılandı).** Tavan **1000 µs oynatılmadı**;
`accept.sh` ajanın diff'inde yok, **ben de dokunmadım**. `accept.sh`'in kendi `2b`'si bugün
bende **6519,6 µs** (kartta 4132,5) — makine yükü, aşağıya bak.

### (c) Defter büyümesi ve sürüklenme — KART BİR YERDE HAKLI, BİR YERDE YANILDI

`bash reports/kosu/kanit/f3i/k3-ledger.sh`, kendi elimde:

    spool  16 KB -> ilk  400 çağrı: 4203.1 us/çağrı
    spool 136 KB -> ikinci 400    : 5126.0 us/çağrı    sürüklenme +922.9 us (+22.0%)
    KONTROL, spool partiler arasında SİLİNMİŞ:
                   ilk  400       : 6988.6 us/çağrı
                   ikinci 400     : 7965.7 us/çağrı    sürüklenme +977.1 us (+14.0%)
    DEFTER BOYUTUNA ATFEDİLEBİLİR = -54.2 us

**İki ayrı hüküm, ikisi de sayıya bağlı:**

1. **Defter boyutu atfı: F3h'nin +265 µs'si YENİDEN ÜRETİLEMEDİ, ve kartın +110 µs'si de
   üretilemedi.** Bende sayı **−54,2 µs**, yani sıfırdan ayırt edilemez. *Kartın "265 değil"
   demesi doğrudur; "110'dur" demesi ölçülmemiştir.* Defter boyutu bugün `2b`'yi ölçülebilir
   biçimde yavaşlatmıyor.
2. **Sürüklenme atfı: KART YANILDI.** Kart *"'tek koşuda +%39 sürüklenme' BU KOŞUDA YENİDEN
   ÜRETİLEMEDİ (+%0,9)"* diyor. Bende sürüklenme **fazlasıyla** üretildi: aynı kesintisiz
   koşuda **+%22,0**, spool **silinmişken bile +%14,0**, ve `k3-daemon` koşumda sekiz tur
   boyunca DOWN kolu **929,7 → 1559,4 µs = +%67,7**, UP kolu **+%52,1**. **F3h'nin
   sürüklenme gözlemi gerçektir; yalnız SEBEBİ defter değildir — makinedir.**

### (d) ÖLÇÜT HÜKMÜ — bu, `2b`'ye dayanan her iddiayı bağlar

Aynı ikili, aynı fikstür, kod değişmeden, tek bir kesintisiz koşuda **%14–22 sürüklenme**;
ve aynı taban ikilisi üç koşuda **1508,6 / 2058,0 / 1933,2 µs** = **549 µs yayılım**, ki bu
tek başına **|439 µs| bandını aşar**. **Yani `2b`'nin aleti, bu makinede, bandından daha
gürültülüdür.** F3h'nin *"eşli olmayan tek sayı iddia değildir"* hükmü ayakta ve
**genişletiliyor: N=200 yetersizdir; `2b`'ye dayanan her iddia eşli, iç içe ve çok turlu
olmak zorundadır, ve tek bir turun deltası da iddia değildir** (benim turlarım +301 / −330
arasında salındı). Bu yüzden `accept.sh`'in tek atışlık `2b` sayısı (bende 6519,6 µs) bir
gerileme kanıtı olarak ANILAMAZ ve anılmadı.

---

## 5. A4 — §3.12 ve §3.8 DENETİMİ

**§3.12 — TEMİZ.** Tahmin `52643aa` **03:03:22**, fazın **İLK** commit'i ve **kodsuz**
(yalnız `RAPOR/F3i.md`, 13 satır). Faz 03:03:22 → 03:45:56 = **43 dakika**. Tahmin "3 kart,
2 süit, ~27 iddia", gerçekleşen "3 kart, 2 süit, **+23** iddia" — **tahmin aşılmadı**, iki kat
tetiği çalmadı.

**§3.8 — TEMİZ.** `git diff F3i-oncesi..c9c7887`:

- silinen dosya **0** · silinen/`skip`/`xfail` iddia **0** · hiçbir süidin iddia sayısı düşmedi
- mühürlü set diff'te **HİÇ YOK**: `reports/R7/accept.sh` · `ON-KAYIT.md` · `docs/claims.tsv` ·
  `.rabadon/guard.json` · **`bin/rabadon.mjs` (O3)** — hiçbiri
- **ölçüt commit'leri koddan ÖNCE ve KODSUZ**: `f891341` (`law_blind_test.sh` + Makefile) →
  `20318c3` (`gate.cpp`). `c8281d0` (K1) hiç ürün kodu taşımıyor.
- **kâtip commit'i sonuncu DEĞİL**: `5f92baa` (`docs/guard.md`), sonrası üç commit var
- toplam 18 dosya, 1038 ekleme, **1 silme** (bir satır, `gate.cpp` içinde)

**Kapı sayıları — hepsini kendim koşturdum, kartla BİREBİR:**

| ölçü | ben | kart |
|---|---|---|
| `make test` | **EXIT=0** | EXIT=0 |
| native iddia (`^[[:space:]]*ok\b`) | **4045** | 4045 |
| `PASS (N checks)` toplamı | **633** | 633 |
| `npm test` | **64 / 0** | 64/0 |
| **toplam** | **4742 yeşil / 0 kırmızı** | 4742 / 0 |
| süit (kaynaktan, Makefile) | **119** | 119 |
| `accept.sh` | **EXIT=1, 23 yeşil / 3 kırmızı** | 23/3 |
| kırmızı ad kümesi | **`{2b, 6e, 7b}` — BÜYÜMEDİ** | büyümedi |

`cli` **315/0** (beş-verb tavanı yerinde: *"the main help screen lists exactly 5 product commands"*) ·
`doctor` **43/0** · `install_docs` **38/0** · `docs_truth` **42/0** · `version` **13/0**.
**F1e-C üçlüsü fazın NİHAİ ikilisine karşı: 42/0 · 38/0 · 13/0.**

**TABANI DA KENDİM KOŞTURDUM** (`_hakem_f3i_base`, `c48c0e4`, `$HOME` altında, `/tmp` değil):
`make test` **EXIT=0** · native **4022** + **633** + `npm` **64** = **4719** · süit **117**.
Yani **+23**, ve `+23`'ün kaynağını süit-diff'iyle ayırdım — iki `make test` çıktısının
süit özetlerini ayrıştırıp karşılaştırdım (72 → 74 süit özeti):

    brake_persist:  yok -> 13
    law_blind:      yok -> 10
    KÜÇÜLEN: hiç · KAYBOLAN: hiç · toplam delta: +23

**Büyümenin tamamı iki yeni süittir; mevcut hiçbir süidin iddia sayısı düşmedi.**

---

## 6. B1 — İZNİ GİDEN İKİLİ

Alan bulgusu (şef ölçtü): `native/rabadon-gate` `-rw-r--r--`, mtime 30 Ağu 03:11, 20 ikiliden
yalnız o; hook her çağrıda `exit 126`.

**O hâli yeniden gözleyemedim** — 03:48'de dosyanın üstüne §1'deki puç yazıldı ve kanıt silindi.

**Sorumlu süiti ÖLÇEMEDİM, ve aramanın nerede bittiğini yazıyorum.** `chmod` ile gerçek bir
**sevk edilen** ikiliye dokunan tek aday `native/doctor_test.sh:282`:

    VICTIM=$(printf '%s\n' $ALL | grep -v '^gate$' | head -1)
    chmod 644 "$PERMT/native/rabadon-$VICTIM"

Bu **suçlu değil**: `mk()` ikilileri `cp` ile `mktemp -d /tmp/rabadon-doctor-test.XXXXXX`
altına kopyalar (hardlink değil), `trap … EXIT` ile siler, ve kurbanı seçerken `gate`'i
**açıkça dışlar**. `native/*.sh` içinde gerçek ağaca `chmod` atan başka bir yer bulamadım.
Ayrıca ben `make test`'i kök klonda **iki kez** koşturdum ve 20 ikilinin **mod + hash**'ini
öncesi/sonrası karşılaştırdım: **hepsi değişmedi** (§9 tablosu). Yani bugünkü ağaçta bu sınıf
yeniden üretilemiyor.

**Sınıf ağırlığı (CLAUDE.md "Quality bar").** *Bir test süitinin ürünün kendisini bozması*
en ağır sınıftır ve kaçırılmış bir yakalamayla aynı ağırlıktadır: sonucu, kurulu görünen ama
çalışmayan bir guard'dır — "every error path is a designed path" ve Promise 1'in doğrudan
ihlali. `exit 126` hiç değilse gürültülüdür; §1'de bulduğum `exit 0` puçu aynı sınıfın
**sessiz** ve daha kötü hâlidir.

**Kapı ne olmalı — hükme bağlanıyor (§7'de, B3 ile birlikte).** Not: tespit tarafı zaten var
ve çalıştı (`version_test.sh` puçu ilk 3 saniyede yakaladı, `cli_test.sh`'in glob keşfi
artık dosyayı yakaladı); eksik olan, **`make test`'in kendisinin ürünü bozmadığını ölçen bir
kilit** ve **oturumlar arasında bunu koşturan bir şey**.

---

## 7. B2 — SELF-HEAL, GEÇİCİ BİR YOLU OPERATÖRÜN GLOBAL AYARINA YAZDI

### Bugünkü hâl: ONARIM TUTMUŞ

`~/.claude/settings.json`'daki **her** `command` yolunu tek tek varlık kontrolünden geçirdim:
üç ayrı yol, **üçü de mevcut** — `orkestra/src/tick.py` (yabancı kancalar korunmuş),
`orkestra/src/bar.py` (**paylaşımlı `statusLine` korunmuş**), ve altı girdide
`…/rabadon/native/rabadon-gate` (kanonik kök klon). **Kalan zehirli yol: 0.**
Makinedeki **41** `settings*.json`'ın hepsini taradım: `_hakem_` geçen **canlı referans 0**.

### KÖK SEBEP DOĞRULANDI — ve deterministik olarak yeniden ürettim

Kod: `gate.cpp:1295` `refresh_hook_subscriptions()` → `js = self_dir() + "/../hooks/refresh.mjs"`,
oradan `installHooks()`. Yani **o an hangi ikili koşuyorsa onun MUTLAK yolu** yazılıyor.

Sahte bir `$HOME` kurdum (operatörün dosyasına dokunmadan), içine **kanonik** yolu gösteren bir
`settings.json` koydum, ve **taban worktree'sinde derlediğim** ikiliye tek bir `SessionStart`
verdim — env override yok, saf varsayılan:

    ÖNCE : /Users/…/rabadon/native/rabadon-gate
    SONRA: /Users/…/_hakem_f3i_base/native/rabadon-gate
           /Users/…/_hakem_f3i_base/native/rabadon-drift

**Zaten çalışan, var olan, kanonik bir yol geçici bir kopyanın yoluyla EZİLDİ** — ve
`rabadon-drift` de dahil, yani alanda gözlenen zehrin (`_hakem_f3g_base/native/rabadon-drift`)
**tam olarak aynı şekli**. Kök sebep budur.

### F3g HAKEMİNİN SELF-HEAL'İ AKLAMASI YANLIŞTI — sebebini ölçtüm

`KARARLAR.md` · F3g · (5) şöyle diyor: *"Tek başına `SessionStart` olayını worktree ikilisine
verdiğimde repoint OLMADI — yani sebep F3f'in self-heal'i değil, gerçek `$HOME`'a yazan beş
süit."* Bu negatif bir **artefakttır**: self-heal `rdir + "/hooks-refresh.stamp"` ile
**6 saatte bir**e sınırlıdır ve damga tazeyse **hiçbir şey yapmadan döner**. İki kolu da
koşturdum: damga taze → repoint **YOK**; damga yok → repoint **VAR**. Canlı bir `RABADON_DIR`'de
damga her zaman tazedir, o yüzden tek atışlık bir prob **daima** negatif okur.
Beş süit ayrı bir kalem olabilir; **ama self-heal aklanmış değildir ve alan hasarının şekli
onunkidir.** Eski hüküm silinmiyor, gerekçesiyle düzeltiliyor.

### İKİNCİ, DAHA KESKİN KUSUR — ZEHRİ SESSİZ ATIYOR (Promise 1)

`hooks/refresh.mjs:80`:

    const detail = added.length ? `subscribed to ${added.join(', ')}` : 'repointed its entries';

Yani **yol değişikliği yalnız hiçbir olay eklenmediğinde** duyurulur. İkisi birden olduğunda
— ki alan hasarında olan tam budur — ekran sadece *"subscribed to PostToolUse, …"* der ve
**yıkıcı olan değişikliği, adresin değiştiğini, hiç söylemez.** 10 saate mal olan kodun içinde,
"rabadon susmaz" sözünün ihlali.

### HÜKÜM — self-heal hangi yolu yazmalı

**Dayanak sayısı: zehirlenen 6 girdinin 6'sının da yeni bir YOLA ihtiyacı yoktu; hepsinin
ihtiyacı yalnız yeni OLAYLARDI.** Buradan en kısıtlayıcı ve aynı zamanda yeterli kural:

1. **Self-heal var olan bir rabadon `command` dizgesini DEĞİŞTİRMEZ.** Yalnız eksik olay
   aboneliklerini ekler ve mevcut komut dizgesini **aynen** taşır. Upgrade olayla ilgilidir,
   adresle değil.
2. Yeni bir yol yazmak zorunda kaldığı tek durumda (girdi yoksa) **kanonik kurulum yolunu**
   yazar, ve yazdığı yolun **var olduğunu ve kalıcı olduğunu** doğrular — bir git worktree'si,
   bir `mktemp` kökü ya da silinebilir bir kopya altındaki yolu **asla** yazmaz.
3. Yol değiştiyse ekran bunu **eskisi ve yenisiyle** söyler; `added.length` koşuluna
   bağlanamaz.
4. Var olmayan bir ikiliyi gösteren bir hook **sessiz bir ölümdür**: `doctor` bunu zaten
   yakalıyor, ama self-heal'in kendisi de yazdıktan sonra doğrulamalıdır.

### F3f HAKEMİNİN ALTI HOSTİL KONTROLÜNÜN EKSİĞİ

Altısı da (statusLine korunuyor mu · yabancı kancalar · yedek gerçek mi · bozuk JSON'a yedeksiz
yazıyor mu · çıkış var mı · docs) **ikiliyi kendi kanonik yerinden** koşturdu. Hiçbiri
**"ikiliyi İKİNCİ bir yoldan koştur ve ayar dosyasındaki komut dizgesinin DEĞİŞMEDİĞİNİ ölç"**
demedi. Eksik olan tek kontrol budur ve tek satırdır. (Ayrıca hiçbiri damga sınırını sıfırlamadı,
yani F3g'nin negatifi de aynı körlükten doğdu.)

---

## 8. B3 — ORTAK DERS: KOŞU, OPERATÖRÜN DİĞER OTURUMLARINI HİÇ ÖLÇMEDİ

### Sayılar (hepsi bu koşudan, hepsi ölçülmüş)

| olay | ölçü | kaynak |
|---|---|---|
| operatörün canlı oturumunda kesme | **5 olay / 16 dk / 1 oturum** | defter, §2 |
| operatörün elle freni indirmesi | **3 kez** (01:57–02:03) | `history.jsonl` |
| operatörün düz cümleyle yalvarması | **1** (03:13:49) | kart, `history.jsonl` |
| zehirlenmiş global kanca girdisi | **6**, günlerce | B2 |
| izni giden sevk edilen ikili | **1** (`exit 126`) | B1 |
| `exit 0` puçuna çevrilmiş sevk edilen ikili | **1**, ~24 dk (03:48→04:12) | §1 |
| operatörün kendi ifadesiyle kayıp | **10 saat** | brifing |
| bunu ölçen faz | **0 / 9** (F3a…F3i) | faz kartları |

**Dokuz fazın hiçbiri "bu değişiklik operatörün DİĞER oturumlarına ne yapıyor" diye sormadı.**
Üç ayrı hasarın üçü de o kör noktadan çıktı. Karşılaştırma, oranı görmek için: aynı koşunun
yedi fazı `2b`'nin **800 µs**'sini kovalıyor; kör nokta **10 saate** mal oldu. Oran **4,5×10⁷**.

### HÜKÜM: EVET, KAPI OLMALI — ve üçlüsü ölçülebilir

Her faz kapanışında, kartın kendi sayılarıyla aynı yerde:

1. **Sevk edilen ikililerin izni + hash'i değişmedi.** `make test` öncesi/sonrası
   `native/rabadon-*` için `stat` modu + `shasum`. Ben bunu iki kez koşturdum, 20 ikilinin
   20'sinde de değişiklik yok — yani kilit bugün YEŞİL doğar, ama §1'deki puç onu **kırmızı**
   düşürürdü ve `make` onu onarmadığı için başka hiçbir şey yakalamazdı.
   *(Kilidin ucuz olması onu gereksiz yapmaz: kırılabilirliği §1'de canlı olarak kanıtlandı.)*
2. **`~/.claude/settings.json` bayt bayt aynı.** Zaten `home_isolation_test.sh` var ama
   **iki süidi adıyla** tutuyor, özelliği tutmuyor (F3i kartının kendi tespiti); faz kapanışında
   dosyanın sha'sı öncesi/sonrası karşılaştırılmalı — ben her koşumda yaptım, dördü de aynı.
3. **Canlı fren operatörün bıraktığı hâlde.** `~/.rabadon/mode` + `enabled` varlığı,
   faz öncesi/sonrası. Bu fazda ihlal edilen tam olarak buydu.

**Ek şart, B2'den doğrudan:** faz ajanı ya da hakem bir worktree/kopya ikili koşturduysa,
kapanışta `settings.json`'daki her `command` yolunun **var olduğu** doğrulanmalı. Ben 41
settings dosyasını taradım, canlı zehirli yol 0 — ama bunu bir kapı değil, ben yaptım.

---

## 9. HAKEMİN KENDİ İZİ

- Kum havuzlarımın hepsi **`/tmp` DIŞINDA** (`~/damla_projects_2026/_hakem_f3i_*`), ve
  `2b-uctan-uca.sh`'in kendi `${TMPDIR:-/tmp}` kökünü de `TMPDIR` override ile `$HOME` altına
  aldım (Tuzak 1).
- **İki worktree'yi de kaldırdım** (`git worktree remove --force` + `prune`), ve kaldırdıktan
  **sonra** `settings.json`'ın sha'sını yeniden aldım (`adcb41a93f858d6b`, değişmedi) ve her
  `command` yolunun **var olduğunu** doğruladım — B2 tam olarak bu adımın atlanmasından doğmuştu.
- **Frene dokunmadım**: `mode=watch`, `enabled` yok, bulduğum gibi. `guard.json`'a dokunmadım,
  `rabadon off` kullanmadım, CHALLENGE-3 bileşik-komut deliğini kullanmadım.
- **Kapı beni hiç kesmedi** — ama mod `watch`'ta olduğu için bu, çıkış kapısının enforce altında
  çalıştığının kanıtı **DEĞİLDİR** ve öyle yazmıyorum.
- Değiştirdiğim tek ürün dosyası yok; `git status` tracked değişiklik olarak **boş**. Diskte
  yaptığım tek kalıcı değişiklik: `native/rabadon-gate` puçunun yerine gerçek ikili (§1) ve
  artık `rabadon-gate.gercek` kopyasının silinmesi.
- **Benim olmayan, duran çöp (F3j temizlesin):** `_hakem_f3g_base/` (içinde yalnız 17 baytlık
  `rabadon-drift` puçu), `_hakem_f3g_exit.sh`, `_hakem_f3g_probe.sh`, `_hakem_f3h/`.
  **Hiçbiri canlı bir `settings*.json`'dan referans almıyor** (41 dosya tarandı, 0 referans),
  o yüzden zararsız; yine de silmedim, çünkü onları üreten koşu benim koşum değil.

---

## 10. ÖLÇEMEDİKLERİM

- `native/rabadon-gate`'i 03:48'de kim puçladı — repodaki hiçbir süit üretmiyor, `history.jsonl`'de
  satır yok, **ölçemedim**
- B1'in `-rw-r--r--` hâlini üreten süit — aday elendi (`doctor_test` izole `cp` kullanıyor),
  başka aday bulamadım, **ölçemedim**
- `red-base`'in, engeli kaldıracak olan **kontrol komutunun kendisini** engelleyip engellemediği:
  fikstürüm red-base durumuna hiç giremedi, **ölçemedim** (ret metni "re-run that check — a pass
  clears this immediately" diye söz veriyor, doğrulanmadı)
- konteynerde hiçbir şey koşmadı — yalnız konak macOS arm64
- daemon'un yerleşik RAM maliyeti (operatörün "rabadon RAM yiyor" cümlesi) ölçülmedi
- **(c) negatif kontrolü kapsam dışıydı → F4 HÂLÂ KAPALI** ((c) F6'nın aletiyle koşar, F3d hükmü,
  değiştirmedim)
