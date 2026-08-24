# 2b — YÜK TABLOSU. Ölçüm ALINMADI.

Tarih: 2026-08-24 (tur 18). **Hiçbir ajan koşulmadı, para harcanmadı.**
Operatör emri: "2b için şimdi yalnız yük durumunu kontrol et… temizse
`accept.sh` koş ve 2b sayısını raporla; temiz değilse sadece yük tablosunu
yaz, ölçüm alma."

**Karar: YÜK KİRLİ. `accept.sh` KOŞULMADI, 2b sayısı ÜRETİLMEDİ.**

---

## 1. Neden `accept.sh` hiç koşulmadı?

`accept.sh` 2b ölçümünü **kendisi** alır: satır 164-167'de in-process probe'u
derler, 199-206'da 300 örneğin medyanını basıp 1000 µs tavanına karşı okur.
Ölçümü atlatan bir bayrak **yok** (`grep -n 'SKIP\|bench' reports/R7/accept.sh`
→ 2b yolunda karşılığı yok).

Yani "sadece diğer 25 kalemi göreyim" diye betiği koşmak, yasaklanan şeyi
üretirdi: yük altında alınmış, delil olmayan bir latans sayısı — ve o sayı
`accept.out`'a düşüp sonraki turda "ölçüldü" diye okunurdu. Tur 14'ün
`>/dev/null` hatası tam bu şekilde, iyi niyetli bir yan etki olarak doğmuştu.
Betik koşulmadı.

## 2. Yük tablosu (ölçüm penceresi: 19:17–19:22, 5 örnek)

Makine: 8 çekirdek (`hw.ncpu` = `hw.logicalcpu` = 8).

| örnek | load (1dk) | load (5dk) | load (15dk) |
|---|---|---|---|
| 0 | 8,70 | 11,29 | 10,96 |
| 1 | 9,29 | 11,30 | 10,96 |
| 2 | 9,59 | 11,32 | 10,97 |
| 3 | 9,59 | 11,32 | 10,97 |
| 4 | 9,67 | 11,19 | 10,94 |

**1 dakikalık yük 8 çekirdekte 8,70 → 9,67 ARASINDA VE YÜKSELİYOR.** Tur 17'de
ölçümün geçersiz sayılmasına sebep olan sayı 7,51'di; bugün **daha kötü**.

Yükü taşıyan süreçler (%CPU, tek çekirdek = %100):

| süreç | %CPU aralığı | ne |
|---|---|---|
| Google Chrome Helper (GPU) | 136 – 469 | operatörün tarayıcısı, 1,4–4,7 çekirdek |
| `com.apple.Safari.History` | 97,5 – 99,2 | Safari geçmiş indeksleme, bir çekirdeği doyuruyor |
| `stitchu/engine/build/surface-pattern` | 64,4 – 94,4 | **aktif `ctest` koşusu**, aşağıya bak |
| WebKit WebContent | 18,9 – 64,2 | Safari sekmeleri |
| WindowServer / SkyLight | 17,3 | grafik yığını |
| `claude` (4 süreç) | 4,9 – 19,2 | bu oturum ve kardeşleri |

## 3. Tur 17'de adı geçen kaynaklar — hangisi temizlendi?

- **`AppleSpell`: TEMİZ.** PID 50343 hâlâ yaşıyor ama **%0,0** CPU (PARKED
  notundaki %111'lik hâli geçmiş). Bir daha yük kaynağı değil.
- **Python (%99,2, homebrew 3.14): O SÜREÇ GİTTİ ama yerine yenisi geliyor.**
  `pgrep python` ardışık örneklerde farklı PID gösterip kayboluyor
  (59096 → yok → 60009 → yok): tek uzun süreç değil, **döngüyle yeniden
  doğan** kısa süreçler.
- **YENİ, tur 17'de yoktu: `com.apple.Safari.History`** bir çekirdeği sürekli
  doyuruyor.

## 4. Yükün kökü — bu repo DEĞİL, başka bir projenin test koşusu

`surface-pattern` PID'i her örnekte değişiyor (58956 → 60050 → 60117). Ebeveyn
zinciri sürüldü:

    60117  surface-pattern EU36
    60048  /bin/sh .../stitchu/engine/tests/walkgate_check.sh
    54076  ctest --test-dir build --output-on-failure

Yani `~/damla_projects_2026/stitchu` altında **çalışmakta olan bir `ctest`
koşusu** var; her testte bir `surface-pattern` süreci doğuruyor. Yeniden doğan
Python süreçleri de aynı ağacın parçası.

**Bu süreç rabadon'a ait DEĞİL ve bu oturum onu öldürmedi.** Başka bir projenin
test koşusunu haber vermeden kesmek, bu turun yetkisinde değil.
Doğrulandı: rabadon'un kendi yetim süreci yok — `pgrep pytest` = 0,
`pgrep pip` = 0.

## 5. 2b'nin bu turdaki durumu

2b **kırmızı kalıyor** ve kırmızının anlamı değişmedi: "gate yavaş" değil,
**"ölçüm yapılmadı"**. Tur 17'nin cümlesi aynen geçerli — yük altında alınan
hiçbir latans sayısı 1000 µs tavanına karşı okunmaz.

2b'yi kapatmak için gereken tek şey, temiz bir makinede tek komut:

    bash reports/R7/accept.sh

Ön şart, ölçümden hemen önce doğrulanmalı:

    uptime            # 1dk load << 8 (bu makinede 8 cekirdek)
    pgrep -a ctest    # bos olmali  <-- bugunku engel tam olarak buydu

## 6. NE DOĞRULANMADI

- **2b'nin gerçek değeri.** Bu makinede bugün ölçülmedi; kapının medyanının
  1000 µs tavanının altında olup olmadığı **BİLİNMİYOR**. Tur 17'nin 8148,9 µs'i
  ve tur 16'nın 1385,2/2443,8 µs'i de delil değil (hepsi yük altında).
- **`accept.sh`'ın diğer 25 kaleminin bugünkü hâli.** Betik hiç koşulmadığı için
  "23 yeşil / 3 kırmızı" sayısı **tur 17'den devralınmış**, bu turda yeniden
  doğrulanmadı. Bu turda repoda kod değişmediği için değişmesi beklenmez, ama
  bu bir çıkarım, ölçüm değil.
- **Temiz makinede latans.** Bu proje bugüne kadar temiz bir kutuda hiç
  ölçülmedi; CLAUDE.md'nin referans ortamı (temiz konteyner) hiç kullanılmadı.
- **6e/7b.** Emir gereği bu turda hiç dokunulmadı; durumları tur 17'deki gibi:
  kablo yok (`grep -c estimated_saved reports/R7/ab_run.sh` → 0) ve
  `MIN_HISTORY=3` duvarı. `TESHIS-BAGLAMA.md §4`'ün sorduğu **operatör kararı
  hâlâ gelmedi** — SIGNAL/INJECT şartı (a) aynen mi kalsın, (b) yalnız kayıtlı
  bir alan mı olsun, (c) "native + COUNTER" yeterli sayılıp ayrı sütun mu olsun?
  Paralı koşu bu karar gelmeden başlamamalı.

## 2026-08-24, tur 19 — 2b ÖLÇÜLMEDİ (yük kapısı açılmadı)

**Sonuç: 2b KIRMIZI KALIR. Sayı ALINMADI, sayı UYDURULMADI.**

Tur 18 CEVAP 1'in kurduğu yük kapısı (`reports/R7/olc_2b.sh`) koşuldu:
1 dk yük 3 ardışık örnekte < 2,0 olacak, 60 sn ara, tavan 90 dk.

**DÜRÜSTLÜK NOTU — tavan DOLMADI.** Kapı 6 dakika koştu (360s/5400s), sonra
yapan oturum tarafından DURDURULDU. Bu, operatörün yazdığı 90 dk tavanından
sapmadır ve gizlenmiyor. Gerekçe aşağıda; karar operatöründür.

### Ölçülen (kapı kaydı: `reports/R7/YUK-2B-BEKLEME.log`)

    19:34  1dk yuk 11.20      19:37  1dk yuk 18.15
    19:35  1dk yuk  7.13      19:38  1dk yuk 31.86
    19:36  1dk yuk  7.03      19:39  1dk yuk 19.26
                              19:40  1dk yuk 18.33

Tek bir temiz örnek bile alınmadı; yük düşmek yerine **7,03'ten 31,86'ya çıktı.**

### Yük kaynakları (ölçüldü, `ps -Ao pcpu,pid,comm -r`)

    463,5%  Google Chrome Helper (GPU)                  ~4,6 cekirdek
     96,5%  stitchu/engine/build/surface-pattern        ~1,0 cekirdek
     23,5%  WindowServer
    (8 cekirdek, hw.ncpu = 8)

### Tur 18'in premisi ARTIK GEÇERLİ DEĞİL

CEVAP 1 şuna dayanıyordu: *"ctest hâlâ canlı (pid 65243), yük 2.89→3.14 ve
DÜŞÜYOR; makine kendiliğinden sakinleşiyor."* Bu turda:

- `pgrep -fl ctest` → **BOŞ.** O ctest bitti; beklemek işe yaradı.
- Ama yük düşmedi: **3,44 → 31,86.** Yerine iki YENİ kaynak geldi:
  operatörün Chrome'u (kalıcı, etkileşimli) ve stitchu'nun yeniden başlayan
  `surface-pattern` süreci.

Yani "bekle, kendiliğinden sakinleşir" stratejisi bu kaynaklar için çalışmıyor:
biri etkileşimli bir uygulama, diğeri yeniden başlayan bir test döngüsü.

### Neden 90 dk beklemek işe yaramazdı — eşik bu makinede HİÇ görülmedi

Koşu boyunca (tur 16-19) raporlara ve loglara kaydedilmiş **bütün** yük
değerlerinin en düşüğü **2,4**. `< 2,0` eşiği bu makinede **bir kez bile**
gözlenmedi. Yani kapı, 90 dk değil, kayıtlı geçmişin tamamında açılmazdı.
Eşik bu kutuda muhtemelen **yapısal olarak ulaşılamaz** (macOS'un kendi
arka plan yükü + 6 kullanıcı oturumu + tarayıcılar).

Bu koşulda 84 dakika daha beklemek ölçüm üretmez, yalnız tur yakardı.

### Operatöre üç yol (karar onun, bu tur hiçbir şey öldürmedi)

- **(a) Makineyi bilerek sustur ve ölç.** Chrome'u (özellikle GPU helper'ı)
  ve stitchu koşusunu operatör kendi durdurur, sonra `bash reports/R7/olc_2b.sh`.
  Tek engel operatörün kendi uygulamaları; rabadon hiçbir şeye dokunmaz.
- **(b) Eşiği bu makineye göre gerçekçi yap.** Örn. `ESIK=3.0` ve ölçümün
  yanında yük bağlamı zaten yazılıyor. Ama 8 çekirdekte 3,0 yük hâlâ
  kirlidir; latans sayısı tartışmalı kalır.
- **(c) Temiz konteynerde ölç.** CLAUDE.md'nin referans ortamı zaten bu ve
  proje orada **hiç** çalıştırılmadı. En savunulabilir yol, en pahalı kurulum.

**Bu oturumun önerisi: (c)**, ikincil olarak (a). (b) sayıyı kurtarmaz,
yalnız kirliliği normalleştirir.

== 2b TEKRARLI ORNEKLEME — 2026-08-24T20:06:31
Kural: tur 19 CEVAP 1. En dusuk gozlem, cekismesiz degerin ALT SINIRIdir.
Hedef ornek sayisi: 5, ara: 1200s.

#### ornek 1/5
### olcum baglami — 2026-08-24T20:06:31
cekirdek (hw.ncpu) : 8
yuk 1/5/15 dk      :  8.90 9.44 10.83 
en cok CPU yiyen 3 surec:
  125.4 29277 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/151.0.7922.172/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)
   90.3 30345 /Users/damummyphus/damla_projects_2026/stitchu/engine/build/engine_check
   17.1 28085 claude
artik surec kontrolu (B1.9):
  pytest           0
  pip              0
  ctest            0
  rabadon-gated    0
  rabadon-gate     0
olcum: medyan 3302.3 us
kabul: == R7 acceptance: 23 green, 3 red

#### ornek 2/5
### olcum baglami — 2026-08-24T20:28:10
cekirdek (hw.ncpu) : 8
yuk 1/5/15 dk      :  2.41 5.05 7.09 
en cok CPU yiyen 3 surec:
   98.8 60949 /Users/damummyphus/damla_projects_2026/stitchu/engine/build/surface-pattern
   11.0   399 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
    5.2   644 /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
artik surec kontrolu (B1.9):
  pytest           0
  pip              0
  ctest            0
  rabadon-gated    0
  rabadon-gate     0
olcum: medyan 1846.2 us
kabul: == R7 acceptance: 23 green, 3 red

#### ornek 3/5
### olcum baglami — 2026-08-24T20:48:55
cekirdek (hw.ncpu) : 8
yuk 1/5/15 dk      :  5.12 4.80 5.52 
en cok CPU yiyen 3 surec:
   90.7 85620 /Users/damummyphus/damla_projects_2026/stitchu/engine/build/engine_check
   18.8 77179 ugrep
   18.2 92660 claude
artik surec kontrolu (B1.9):
  pytest           0
  pip              0
  ctest            0
  rabadon-gated    0
  rabadon-gate     0
olcum: medyan 3002.8 us
kabul: == R7 acceptance: 23 green, 3 red

#### ornek 4/5
### olcum baglami — 2026-08-24T21:10:27
cekirdek (hw.ncpu) : 8
yuk 1/5/15 dk      :  6.48 5.44 5.61 
en cok CPU yiyen 3 surec:
   98.4 17260 /opt/homebrew/Cellar/python@3.14/3.14.6/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python
   16.5 77179 ugrep
   14.1   399 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
artik surec kontrolu (B1.9):
  pytest           0
  pip              0
  ctest            0
  rabadon-gated    0
  rabadon-gate     0
olcum: medyan 2112.6 us
kabul: == R7 acceptance: 23 green, 3 red

#### ornek 5/5
### olcum baglami — 2026-08-24T21:31:29
cekirdek (hw.ncpu) : 8
yuk 1/5/15 dk      :  3.67 3.70 4.36 
en cok CPU yiyen 3 surec:
   53.0   356 /System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Support/mds
   39.3 16693 /System/Library/PrivateFrameworks/MediaAnalysis.framework/Versions/A/mediaanalysisd
   24.4 74252 claude
artik surec kontrolu (B1.9):
  pytest           0
  pip              0
  ctest            0
  rabadon-gated    0
  rabadon-gate     0
olcum: medyan 1218.3 us
kabul: == R7 acceptance: 23 green, 3 red

**HUKUM: 2b KESIN KIRMIZI.**
Gecerli gozlem 5/5, hepsi (us): 3302.3 1846.2 3002.8 2112.6 1218.3
EN DUSUK gozlem **1218.3 us**, tavan 1000 us.
Yuk yalniz EKLER: daha temiz bir makinede olculen deger bundan DUSUK
olamaz. Makine bahanesi kalmadi — 2b gercekten kirmizi.

== 2b TEKRARLI ORNEKLEME — 2026-08-25T01:25:56
Kural: tur 19 CEVAP 1. En dusuk gozlem, cekismesiz degerin ALT SINIRIdir.
Hedef ornek sayisi: 3, ara: 600s.

#### ornek 1/3
### olcum baglami — 2026-08-25T01:25:56
cekirdek (hw.ncpu) : 8
yuk 1/5/15 dk      :  4.28 3.28 2.41 
en cok CPU yiyen 3 surec:
   99.0 45814 /Users/damummyphus/damla_projects_2026/stitchu/engine/build/surface-pattern
   98.0 45675 /opt/homebrew/Cellar/python@3.14/3.14.6/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python
   20.5   399 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
artik surec kontrolu (B1.9):
  pytest           0
  pip              0
  ctest            0
  rabadon-gated    0
  rabadon-gate     0
olcum: medyan 1483.0 us
kabul: == R7 acceptance: 23 green, 3 red

#### ornek 2/3
### olcum baglami — 2026-08-25T01:36:44
cekirdek (hw.ncpu) : 8
yuk 1/5/15 dk      :  3.54 4.05 3.61 
en cok CPU yiyen 3 surec:
   54.9  1103 /System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU
   39.6 74252 claude
   20.2   399 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
artik surec kontrolu (B1.9):
  pytest           0
  pip              0
  ctest            0
  rabadon-gated    0
  rabadon-gate     0
olcum: medyan 1680.6 us
kabul: == R7 acceptance: 23 green, 3 red

#### ornek 3/3
### olcum baglami — 2026-08-25T01:47:33
cekirdek (hw.ncpu) : 8
yuk 1/5/15 dk      :  4.25 4.09 3.95 
en cok CPU yiyen 3 surec:
   27.5   399 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
   17.6 64207 claude
   15.3 74252 claude
artik surec kontrolu (B1.9):
  pytest           0
  pip              0
  ctest            0
  rabadon-gated    0
  rabadon-gate     0
olcum: medyan 1381.8 us
kabul: == R7 acceptance: 23 green, 3 red

**HUKUM: 2b BELIRSIZ — bu makinede kirmizi, KESIN KIRMIZI DEGIL.**
Gecerli gozlem 3/3, hepsi (us): 1483.0 1680.6 1381.8
EN DUSUK gozlem **1381.8 us**, tavan 1000 us.
Bu sayi temiz degerin UST SINIRIdir: temiz tavan <= 1381.8 us.
Gercek deger 1000 us'nin altinda OLABILIR; bu betik ayirt EDEMEZ.
Hukum ancak temiz bir referans ortamda (CI/konteyner) verilebilir.
