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
