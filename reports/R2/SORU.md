# R2 — operatör kararı bekleyen sorular

## SORU 1 — hamle kaydı nereye yazılsın? (R3'ü BLOKLAR)

**Durum.** R1'in kaydı çalışıyor, R2'nin beş dedektörü onun üstünde yeşil. Bedeli
gate latency'sinde **+1571 µs** (4.636 → 6.207 ms medyan, tek partide dönüşümlü,
3 koşu/kol). Kapının eşiği 300 µs. R1.1 (`save()` dirty-tracked) denendi ve
**düşürmedi** — yanlış şeyi hedefledi, nedeni `reports/R2/kapi.md` madde 1'de.

**Sebep.** Çift yazım değil, tek yazımın kendisi: 200 hamlelik oturum dosyası
(~60 KB) her tool olayında serialize edilip diske yazılıyor.

**Üç yol, maliyetleriyle:**

| yol | ne değişir | maliyet | ne zaman |
|---|---|---|---|
| **A. Append-only hamle günlüğü** — `moves` JSON dizisi yerine oturum yanında satır-satır eklenen dosya | R1'in depolama sözleşmesi, `moves_test.sh`'ın sabitlediği şey | R1 yeniden açılır; `moves_test.sh` ve `postuse_test.sh` güncellenir; ring/eviction okuma tarafına taşınır | şimdi, R1.2 olarak |
| **B. Bekle, R7 çözsün** — daemon zaten planda, hedefi < 1 ms | hiçbir şey; kayıt bugünkü haliyle kalır | R3-R6 boyunca her oturum +1.5 ms taşır; R7'nin daemon'ı bunu çözmezse geç öğreniriz | R7 |
| **C. Kaydı ayrık çocuğa ver** — hot-path'ten tamamen çıkar | red yolunda kayıt kaybolabilir | R1'in "red yolunun kaydı da tutulmalı" kararını geri alır | — |

**Benim önerim: A.** Gerekçe: (1) B, ölçülmemiş bir varsayıma 4 tur boyunca yaslanmak
demek — R7 daemon'ı süreç başlatmayı çözer ama dosya yazımını çözeceğini kimse ölçmedi;
(2) C, R1'in bilerek verdiği kararı geri alır ve oturumun yanlış yarısını kaydeder;
(3) A'nın bedeli bir turluk iş ve `moves_test.sh`'ın iddiaları aynen korunabilir —
değişen depolama biçimi, sözleşmenin anlamı değil.

**Ama bu senin kararın**, çünkü A "iki ara tur = tasarım hatası" kuralını tetikliyor ve
kapı bu noktada operatöre gitmemi söylüyor. Tahmin ederek A'ya başlamadım.

**Ne sorduğumun net hali:** A mı, B mi, C mi?

---

## SORU 2 — `docs/kanit/` canlı mı? (bloklamaz)

Takipsiz duruyor ve `reports/` altındaki iki dizinle **aynı isimleri** taşıyor:
`2026-08-01-g3-first-held-repair`, `2026-08-01-real-defect-mine`. `REPORTS.md`
2026-08-01 kaydı ham çıktıların `docs/kanit/` altında olduğunu söylüyor, ama dizin
git'e hiç girmemiş. Hangisi canlı? Dokunmadım, R1/R2'yi bloklamadı, R3'ü de bloklamaz.

---

## Açık kalan, karar beklemeyen bilinen boşluklar

- **S0.2** hâlâ işaretsiz: g++-only Linux container koşulmadı, sadece macOS + clang shim.
- **npm** hâlâ 404 (R8'in işi).
- **M4 fiyatı AÇIK** — M3'ün iki kollu koşusu olmadan yazılamaz.
- **`scope_drift` en zayıf kural** ve öyle olduğu biliniyor; sessiz mod tam da onu ölçmek için var.
- **200/50 sınırları** iddia edildi, veriyle gerekçelendirilmedi.
