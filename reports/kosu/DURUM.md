# DURUM — kosu3 (25.08, dal `kosu3`, kosu2 6f5d301'den ayrildi)
Koşunun kısa ve KANITLI durumu. Her satır bir dosyadan okundu. Uzun anlatı yok.
Bu dosya her tur kapanışında yapan tarafından tazelenir (v3/B2-1).

## KAPALI
R0–R6 ACCEPTED · T1/T2 kimlik işi kapalı · döngü smoke 19/19 PASS
(`reports/kosu/SMOKE.md`). v3'ün üç yeni farkı (isci.sh · girdi<30KB · KOSMADI)
HENÜZ KANITLANMADI — ilk turun işi bu (B6).

## R7 — 23 yeşil / 3 kırmızı + 1 gizli kırmızı, NOT ACCEPTED
Kanıt: `reports/R7/ab_run.jsonl` 8 kayıt, A:4 / B:4 görev.
GOAL 5 ve GOAL 8 tam yeşil (moves 21/0, signals 39/0, R2 19/0).
Sayılar: düzeltme A %75 / B %75 · token A 35620 / B 33221 · insan 0/0 · YP 0/0.

- **2b latans — KIRMIZI (etiket: bu makinede).** Tavan 1000 µs. 8 gözlem,
  min **1218,3 µs** (`reports/R7/olc_2b.tur22.out`). Tek geçerli çıkarım
  `temiz ≤ 1218,3 µs`; bu, 1000'i DIŞLAMAZ. Bu worktree'de kırmızı PRENSİP
  OLARAK kanıtlanamaz (her gözlem üst sınır) → temiz referans ortam gerekir.
- **6e / 7b — KIRMIZI, tek kök:** `MIN_HISTORY=3` yüzünden tek oturumluk koşuda
  `estimated_saved` üretilmiyor. `MIN_HISTORY` OYNANMAYACAK (operatör bağlaması,
  deneme 26). Yeşile dönüş: çok oturumlu koşu VEYA fixture VEYA GOAL'in yeniden
  ifadesi — üçü de KARAR.
- **5b — ÖN-KAYIT SAPMASI, AÇIK (accept.sh göremiyor).** `reports/R7/ON-KAYIT.md`
  koşudan önce donmuş: **N = 6 görev × 2 kol**. jsonl'de duran: **4 × 2**.
  Eksik: `joke2k__faker.8b401a7d`, `pylint-dev__astroid.b114f6b5`. `accept.sh`
  5b kol başına **≥2** arıyor (satır ~410) — hedefi değil gevşemiş vekilini
  denetliyor. DÜZELTME: 5b, ON-KAYIT'taki N'i okuyacak. SONUÇ: 7a hükmü n=4'te
  veriliyor; A ve B düzeltme oranı ÖZDEŞ, fark yalnız token'da (%6,7) —
  gürültü içinde kalan fark yayınlanmaz (Yasa 7).

## ÖLÇÜM HİJYENİ — A2'nin iki kusuru tur 22'de KAPANDI
- `olc_2b.sh` hükmü düzeltildi: "min gözlem temiz değerin ÜST sınırıdır",
  eski "KESİN KIRMIZI" etiketi GEÇERSİZ ilan edildi (`6097bb9`).
- `pgrep -c` (BSD'de YOK) kaldırıldı, `pgrep -f <ad> | wc -l` kondu (`10ec3f5`).
  İlk gerçek sayı: 8 gözlemin tamamı **2 canlı `ctest`** varken alınmış.
  Kirliliğin büyüklüğü ÖLÇÜLMEDİ.

## R8 — yayın, BLOKLU
`package.json` 0.2.3 · npm 404 · tag yok. BLOK: `make disclosure` fail-closed,
41 liste dışı isim (`reports/R8/DISCLOSURE.md`). YAYIN kararı OPERATÖR'de.
Karar gerektirmeyen işler açık: 17/18 binary uyuşmazlığı, tag, plugin paketi,
10k additionalContext kesme testi.

## M0–M4 — hiç başlamadı. POSITIONING M3'e, SAVUNMA+landing M4'e bağlı.
## İZLE (kırmızı değil): 2c %3,35 → %6,50 (tavan %10; R1.3 bandı %3,5–4,9 aşıldı).

## SIRA
BEKLEYEN OPERATÖR KARARI (2b nasıl kapanacak · 6e/7b fixture mı) → 5b ön-kayıt
sapması → 2b'nin kalan yolu → 6e/7b → R8'in karar gerektirmeyen işleri → R8 →
M3 → M4. Kısmi kabulle sonraki tur başlamaz.
