# TUR 21 — örnekleyici tam koştu; 2b bu makinede kırmızı, hükmün mantığı kusurlu

tarih: 2026-08-24 · yapan oturum · branch `kosu2`

## Tek cümle

5 örneğin 5'i de 1000 µs tavanının üstünde çıktı (**en düşük 1218,3 µs**),
`accept.sh`'ın `ls | head -1` kusuru kapatıldı, kabul **23 yeşil / 3 kırmızı**
ile DEĞİŞMEDİ, ve örnekleyicinin kendi HÜKÜM mantığının ters olduğu bulunup
`CHALLENGE-5.md`'ye yazıldı.

## Yapılanlar, sırayla

1. **`accept.sh` tek satır düzeltmesi, kendi commit'inde.**
   `JL="$(ls "$RD"/*.jsonl | head -1)"` → `JL="$RD/ab_run.jsonl"`.
   Kusur önce ÜRETİLDİ: üç jsonl'li bir dizine `AAA_yeni.jsonl` konunca eski
   satır onu seçiyor. GOAL 5 ve 6'nın tamamı yanlış dosyaya bakabilirdi.
   Düzeltme örnekleyiciden ÖNCE koşuldu ki 5 ölçümün hepsi aynı betikle alınsın.
   commit: `r7: accept.sh names ab_run.jsonl instead of guessing with ls | head -1`
2. **Örnekleyici: `ORNEK=5 ARA=1200 timeout 7000 bash reports/R7/olc_2b.sh`**
   arka planda, B1.9 uyarınca `timeout` sarmalı. 20:06–21:32, 85 dakika.
   Her örneğin yanına yük + en çok CPU yiyen 3 süreç + artık-süreç kontrolü
   kaydedildi (`YUK-2B.md`). Çıkış kodu 1.
3. **`bash reports/R7/accept.sh` → `reports/R7/accept.turn21.out`.**
4. `DENEMELER.md`'ye deneme 27, `CHALLENGE-5.md` açıldı.

## Sayılar

| örnek | saat  | 1 dk yük | 15 dk yük | medyan (µs) |
|-------|-------|----------|-----------|-------------|
| 1     | 20:08 | 8.90     | 10.83     | 3302.3      |
| 2     | 20:28 | 2.41     | 7.09      | 1846.2      |
| 3     | 20:50 | 5.12     | 5.52      | 3002.8      |
| 4     | 21:11 | 6.48     | 5.61      | 2112.6      |
| 5     | 21:31 | 3.67     | 4.36      | **1218.3**  |

- geçerli gözlem **5/5**, en düşük **1218,3 µs**, tavan **1000 µs**
- kabul turundaki 2b medyanı: **1228,1 µs** (300 örnek, daemon açık)
- 2c: **%6,50** (50 olaylı 1226,2 µs / 400 olaylı 1305,8 µs) — %10 tavanı altı,
  ama R1.3'ün %3,5-4,9 bandının üstünde ve trend yanlış yönde
- yük–latans Pearson r: **+0,737** (1 dk), **+0,684** (15 dk)

## Kabul

    == R7 acceptance: 23 green, 3 red
    R7 NOT ACCEPTED

Kırmızılar, tur 20'yle **aynı üçü**: `2b` (medyan tavanın üstünde),
`6e` (`estimated_saved` üretilmiyor — `MIN_HISTORY=3`), `7b` (6e'siz
hesaplanamıyor). `5a` artık dosyayı adıyla yazıyor: `(ab_run.jsonl)`.

## CHALLENGE-5 — kısaca

`olc_2b.sh` "en düşük gözlem, temiz değerin ALT sınırıdır" diyor. Kendi fizik
önermesi (`ölçülen ≥ temiz`) bunun tersini verir: min, temiz değerin **ÜST**
sınırıdır. Dolayısıyla `min ≥ 1000 → KESIN KIRMIZI` çıkarımı geçersiz —
temiz değer 1218,3'ün altında herhangi bir şey olabilir. Betik
DEĞİŞTİRİLMEDİ. Ayrıntı ve önerilen diff: `reports/R7/CHALLENGE-5.md`.

**2b'nin kırmızılığı bundan etkilenmiyor.** `accept.sh`'ın ölçütü bu makinede
alınan medyandır ve o medyan 1228,1 µs. Değişen tek şey kırmızının etiketi.

## NOT VERIFIED

- 2b'nin **temiz ortam** değeri ölçülmedi. Bu worktree'de 1 dk yükü hiç 2,41'in
  altına inmedi; boş bir container'da ölçüm ALINMADI.
- Yük–latans doğrusallığı VARSAYIM; ölçülmedi. Yük=0 ekstrapolasyonu
  (970 / 744 µs) bir kanıt değildir ve hiçbir yerde yeşil sayılmadı.
- Latans varyansının yükle açıklanmayan ~%55'i ayrıştırılmadı (termal kısma,
  disk, kaydedilmeyen süreçler).
- `ab_run.sh` değişiklikleri hâlâ canlı koşuda denenmedi.
- Hiçbir şey temiz klonda / temiz makinede doğrulanmadı; tüm sayılar bu
  worktree'den.

## NEXT

Operatör kararı: 2b temiz bir ortamda mı ölçülecek, yoksa "bu makinede
kırmızı" etiketiyle mi kapanacak? CHALLENGE-5 insan onayı bekliyor ve
onaylanana kadar `olc_2b.sh`'ın HÜKÜM metni olduğu gibi duruyor.
