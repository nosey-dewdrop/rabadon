# R1.2 — operatör kararı (BLOKLAR)

## SORU 3 — her olayda tüm tarihçe okunmalı mı?

İki ara tur, iki farklı yeri ucuzlattı, ikisi de eşiği tutturamadı:

| tur | ne yaptı | ölçüm |
|---|---|---|
| R1 (taban) | moves oturum JSON'unda, tam dosya yeniden yazımı | +1571 µs |
| R1.1 | `save()` dirty-tracked | +1571 µs (değişmedi) |
| R1.2 | append-only günlük, ~170 bayt yazım | **+1949 µs (kötüleşti)** |

Sebep artık net: **maliyet yazımda değil, okumada.** Gate her olayda günlüğün tamamını
ayrıştırıp satır başına SHA-256 zincirini doğruluyor. Oturum uzadıkça bu doğrusal büyüyor.

Üç yol:

**A. Zincir doğrulamasını her olaydan çıkar.** `prev` yazılmaya devam eder ama yalnızca
`RABADON_MOVES_STRICT=1` ile ya da `audit` sırasında doğrulanır. Hot-path'te hash yok.
*Bedel:* eksik satır anında değil, denetimde yakalanır. Şart (3)'ün "zincir eksik satırı
yakalar" cümlesi hâlâ doğru — ne zaman yakaladığı değişir.

**B. Kuyruğu oku, tamamını değil.** Detektörlerin penceresi zaten dar (repeat 20, oscillation 6).
Dosyanın son ~40 KB'ını oku, yalnız onu ayrıştır. *Bedel:* `scope_drift` ve `root_migration`
oturumun tamamına bakıyor; pencereleri daralır ve bu R2'nin ölçtüğü şeyi değiştirir.

**C. Kabul et ve R7'ye bırak.** Daemon süreç içinde kaydı bellekte tutar, dosya sadece
dayanıklılık için yazılır. *Bedel:* R3-R6 boyunca her oturum ~2 ms taşır.

**Önerim: A, sonra ölç.** En küçük değişiklik, tek bir şeyi hot-path'ten çıkarıyor
(hash döngüsü), ve hiçbir detektörün gördüğü veriyi daraltmıyor. Tutmazsa B ölçülür.
Ama bu üçüncü ara tur olur ve kural onu bana yasaklıyor — bu yüzden soruyorum.

---

## Açık soru sayacı — **3, yani BLOK**

Kapının kuralı: *"Açık soru sayısı ikiyi geçemez... üçüncüsü tek başına BLOK'tur."*

1. **SORU 1** (R2/SORU.md) — depolama biçimi. **Cevaplandı: A.** Kapandı.
2. **SORU 2** (R2/SORU.md) — `docs/kanit/` canlı mı? **Hâlâ açık.**
3. **SORU 3** (bu dosya) — her olayda tüm tarihçe okunmalı mı? **Açık ve bloklar.**

İki açık soru var ve ikisi de cevap bekliyor. Yeni soru açmıyorum.
