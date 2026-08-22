# REPORTS — rabadon

Ne oldu, tarih sırasıyla. **En yeni üstte. Sadece eklenir, hiçbir şey silinmez.**

- Buraya *olan biten* yazılır. *Şu an ne doğru* → `CLAUDE.md`. *Ne inşa ediyoruz* → `PROJECT.md`.
- Her oturum sonunda `/wrap` buraya tek blok ekler.
- Eski uzun raporlar `docs/raporlar/` altında (13 adet).

---

## 2026-08-22
**Yapıldı:** R0 kapandı — `reports/R0/accept.sh` 17 yeşil, 0 kırmızı, exit 0.
KOSU-RABADON.md tek plan oldu (PROTOCOL-T1-T8 arşivde, iptal işaretli, PROJECT.md
oraya işaret ediyor). `docs/POSITIONING.md` açıldı: §1b'deki her ürün URL'siyle.
Makefile `CXX ?= clang++` → `c++` (clang++ shim'iyle ölçüldü, shim hiç çağrılmadı).
`make test` 2015 geçti, 0 kaldı.
**Çıkan gerçek:** §1b'nin 11 iddiası birincil kaynakta doğrulanamadı, 2'si
çürütüldü — Lineman koltuk başı fiyatlamıyor (M4 fiyat hipotezi bu dayanağı
kaybetti) ve Şubat 2026 hooks RCE CVE'leri yok. Yasa 1'in ilk kaynağı
(SWE-agent'ın semantik takılma tespitini bırakması) hiç var olmamış; OpenHands
kaynağı gerçek ve yasayı tek başına taşıyor. Hepsi CLAIM.md'de, silinmedi.
**Sonraki:** R1 — hamle kaydı (200'lük halka tampon, tespit/enjeksiyon yok),
kabul `native/moves_test.sh`.

<!-- aşağıdaki iki kayıt eskiden yeniye sıralı; başlıktaki "en yeni üstte"
     kuralı bu girdiyle başlıyor, eskiler olduğu gibi bırakıldı. -->

## 2026-08-01
**Yapıldı:** G3 first-held-repair ve real-defect-mine koşuları. Ham çıktılar
(baseline, patch, ledger-events, locks, blind-fix logları) `docs/kanit/` altında.
**Sonraki:** —

## 2026-08-18
**Yapıldı:** Kayıt sistemi kuruldu — bu dosya doğdu. Eski merkezi `reports/`
klasörü kapatıldı, bu projeye ait 13 rapor `docs/raporlar/` altına taşındı.
**Sonraki:** —
