
OPERATÖR: `reports/R7/CHALLENGE-2.md` bekliyor — `prev` zincir alanı ve `.head` sidecar'ı normalize edilsin mi? Bu kapanmadan GOAL 3 geçilemez, dolayısıyla R7 kapalı kalamaz.

**Durum:** 11 yeşil / 15 kırmızı. GOAL 3'te tek engel `"prev"` ve `.head`. `prev` = bir önceki satırın **normalize edilmemiş** SHA'sı (`chain.h:191`'de belgelenmiş) — içinde gerçek `ts` var, koşudan koşuya değişiyor, hiçbir uygulama eşleştiremez. `.head` sidecar biçimi `<64hex> <satır sayısı>` — yapan, operatörün yasakladığı `s/^[0-9a-f]{64} /HASH /` deseninin yalnız bunu etkilediğini, ledger JSON satırlarıyla hiç eşleşmediğini kanıtladı.

**Üç seçenek:**

**(a) `prev` ve `.head` normalize edilir:** `kimliksiz()` fonksiyonuna iki satır daha eklenir (JSON `"prev":"..."` alanını siler veya sabitler; `.head` satırını `HASH <N>` yapar). Bu operatörün daha önce izin verdiği üç alana paralel bir genişleme.

**(b) GOAL 3 şartı gevşetilir:** "bayt-bayt aynı" yerine `prev`/`.head` alanları hariç tutularak kıyaslanır — accept.sh'ta yorum satırı + koşul değişikliği.

**(c) Daemon bağımsız belgelenir, GOAL 3'ün "bayt-bayt" şartı kaldırılır:** fail-SAME zaten davranışsal olarak kanıtlandı (çıkış kodu, `ev`, `mode`, `rule`, ret metni, `seq` aynı); `prev` bir iç zincir alanı, dış API'nin parçası değil.

Önerim **(a)**: küçük, izole, veriye dayalı. `prev`'in normalize edilmesi önceki kararla aynı tür bir izin — kimlik alanı, değer alanı değil. Kod değil, sadece `accept.sh`'taki `kimliksiz()` genişler. CEVAP: satırlarını yaz, en sona tek başına ONAY yaz.
