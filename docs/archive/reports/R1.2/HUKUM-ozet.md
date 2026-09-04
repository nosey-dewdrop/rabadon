# R1.2 — sonuç: hedef tutmadı, kapı operatöre gidiyor

Kabul: **9 yeşil, 2 kırmızı.** `native/moves_test.sh` 21/0, 44 iddiasının hiçbiri değişmeden.

## Ne yapıldı

Append-only hamle günlüğü kuruldu (`<key>.moves.jsonl`), üç şartla:
1. Okuyan taraf son 200 kaydı görür; `moves_test.sh`'ın halka iddiaları değişmeden yeşil. ✅
2. Sıkıştırma `docs/butce.md`'de sayıyla, SessionEnd'de, hot-path'te değil. ✅
3. fsync yok; satır başına `prev` zinciri eksik satırı yakalıyor (kabul 3a yeşil), yarım
   satır gate'i durdurmuyor (3b), `rabadon audit` yeşil (3c). ✅

## Ne tutmadı — ve neden

**Goal 4: 1949 µs (4.771 → 6.720 ms). Eşik 300 µs. Öncekinden KÖTÜ (1571 µs idi).**

Yazım ucuzladı: 60 KB'lık tam dosya yeniden yazımı yerine ~170 baytlık `write()`.
Ama bedel **okuma tarafına taşındı ve büyüdü**:

- `load_moves()` her olayda günlüğün tamamını ayrıştırıyor,
- ve satır başına bir SHA-256 hesaplayıp zinciri doğruluyor.

Ölçüm 410 olaylık bir oturumda yapıldı ve arada SessionEnd yok, yani günlük 410 satıra
kadar büyüyor: son olay 410 satır ayrıştırıp 410 hash hesaplıyor. Sıkıştırma bunu
oturum sonunda düzeltiyor — ama oturum **içinde** maliyet doğrusal büyüyor.

Yani bu bir ayar hatası değil: **her olayda tüm tarihçeyi okuyup doğrulayan bir tasarım**,
yazımı ne kadar ucuzlatırsan ucuzlat, okuma tarafında aynı duvara çarpıyor.

## Kabul betiğinin kendi hatası (1b)

`1b` kırmızı ve **ürün hatası değil, benim test hatam**: iki ayrı sandbox'ın ilk satırını
karşılaştırıyor, satırlar `ts` taşıyor, iki sandbox iki farklı milisaniyede kuruluyor.
Aynı dosyanın önce/sonrasını karşılaştırmalıydı. Düzeltmedim — kırmızı bir iddiayı
DUR anında düzeltmek, hükmü kendi lehime çevirmek olurdu. Yargıç oturuma bırakıyorum.

## Kural gereği

> Ara tur (R<n>.1) kuralı: ... R<n>.2'ye gidiyorsa DUR; iki ara tur = tasarım hatası,
> operatöre gider.

İki ara tur denendi (R1.1 dirty-tracking, R1.2 append-only). İkisi de eşiğin altına
inmedi. **DUR.** Soru `reports/R1.2/SORU.md`'de.
