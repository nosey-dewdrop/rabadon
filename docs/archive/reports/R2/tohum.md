# R2 — tohum (pazarlama hasadı)

Olay + sayı + referans. Yorum yok.

- **Beş dedektör canlı ve hiçbiri konuşmuyor.** 19 kabul iddiası yeşil; sinyaller
  ledger'a düşüyor, çıkış kodu oynamıyor, stdout'a tek bayt gitmiyor.
  (`reports/R2/accept.sh`)

- **Bir fixture bir kuralı sıkıştırdı.** `lint, build, lint, build, lint, build`
  `repeat` ateşledi — sağlıklı bir oturumda üç lint koşusu. Kural sayı saymayı
  bıraktı, "ilerlemiyor olma kanıtı" istemeye başladı. Eşik yükseltilmedi,
  şart eklendi. (`native/signals.h`, repeat)

- **`green_redefined` üç alt desende de ateşliyor, dördüncüde ateşlemiyor:**
  kırmızıyken test dosyasına yazma, sadece test tarafı oynayarak kırmızıdan yeşile
  geçiş, ve assertion sayısının düşmesi — ama **yeşil süitte test refactor'ü
  ateşlemiyor.** Piyasadaki hiçbir guardrail bu dördünün hiçbirini görmüyor.

- **Ölçülen ve kötü:** kayıt + sinyal gate'e **+1571 µs** ekliyor (4.636 → 6.207 ms).
  Kapının eşiği 300 µs. Ara tur denendi, düşürmedi. Tur DUR'da.
  (`reports/R2/kapi.md`)

M1 için aday cümle: reward hacking dedektörü yazan turun kendi kuralını, kendi
fixture'ı yanlış pozitif verdiği için sıkması — ve bunu sayı oynatarak değil şart
ekleyerek yapması.
