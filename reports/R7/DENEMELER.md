# DENEMELER — R7 (iki kollu kanıt + daemon)

Tek yazar: o turun yapan oturumu (B1.7). Yeni blok EN ALTA eklenir.

## deneme 1 — 2026-08-24 (tur 1, yapan) — teşhis turu, kod yazılmadı

**DENENEN.** R7'ye kod yazmadan önce zeminin ne olduğu ölçüldü: `native/`,
`core/`, `scripts/` altında `rabadon-gated` ya da AF_UNIX **sunucu** soketi
açan bir kaynak var mı, varsa yolu A1'in `${XDG_RUNTIME_DIR:-/tmp}/rabadon-$UID.sock`
kuralına uyuyor mu. Kabul betiği olduğu gibi koşuldu (değiştirilmedi).

**SONUÇ.** `./reports/R7/accept.sh` → **4 green, 22 red, R7 NOT ACCEPTED**
(ham çıktı `reports/R7/accept.out`). Daemon hiçbir biçimde yok: binary yok,
`gated.cpp`/`daemon.cpp`/`gated.h` yok, `Makefile:12` `all:` listesinde hedef
yok. `RABADON_GATED_SOCK` **hiçbir kaynak dosyada geçmiyor** — yalnız accept.sh
ve belgelerde. Repodaki AF_UNIX sunucusu tek: `core/bus.mjs:263-283`, sahibi
`rabadon watch`, kapıyla ilgisi yok. `native/gate.cpp:714-724` yalnız
**istemci** (`connect`, `bind`/`listen` yok). `native/serve.cpp:477-498`
AF_INET/TCP, konu dışı. Tam teşhis: `reports/R7/TESHIS.md`.

**ELENEN HİPOTEZ.**
- "`native/gate.cpp` `RABADON_GATED_SOCK` fallback'ini içeriyor" (tur 1
  ONKONTROL/SMOKE bloğunun iddiası) — **ELENDİ, iddia yanlıştı.** Repo geneli
  grep sıfır kaynak eşleşmesi verdi; accept.sh GOAL 1c bunu bağımsız doğruladı
  (`FAIL 1c … there is no thin client`). `reports/kosu/SMOKE.md`'ye düzeltme
  yazıldı.
- "Daemon kısmen var, yalnız derlenmemiş olabilir" — ELENDİ, `Makefile`'da
  hedefi bile yok; unutulmuş derleme değil, yazılmamış iş.
- "`core/bus.mjs`'in soketi R7 daemon'ı olabilir" — ELENDİ, `core/bus.mjs:19`
  sahibinin `rabadon watch` olduğunu yazıyor ve yargılama bu yoldan geçmiyor;
  kapı ledger'ı diske yazdıktan SONRA fan-out ediyor (`native/gate.cpp:742-743`).

**KALAN HİPOTEZLER / açık uçlar.**
- **YENİ BULGU, doğrulandı:** `native/gate.cpp:720` `strncpy(addr.sun_path, …)`
  uzunluk kontrolü yapmadan **sessizce kesiyor**; `native/` altında tek bir
  `sun_path`/ENAMETOOLONG guard'ı yok. A1'in daemon için öngördüğü hata sınıfı
  bugünkü istemcide zaten mevcut ve belirtisi "daemon kapalı" ile aynı, hiçbir
  yerde sayılmıyor (Promise 1 ihlali). Düzeltme R7 kapsamında, bu turda
  UYGULANMADI.
- A1'in 0600 izin şartı hiçbir soket yaratımında yok (`core/bus.mjs:281` düz
  umask). ÖLÇÜLDÜ, düzeltilmedi.
- `reports/R7/accept.sh:107` daemon soketini `mktemp -d` altına koyuyor; macOS'ta
  bu `/var/folders/…/T/` olur ve `sun_path` tavanına yaklaşır. Kabul betiğinin
  KENDİSİ A1 kuralını çiğniyor olabilir — daemon olmadığı için bu kol hiç
  koşmadı, **ÖLÇÜLMEDİ**.
- Daemon protokolü (çerçeveleme, timeout, eşzamanlılık) hiçbir yerde
  tasarlanmamış. **ÖLÇÜLMEDİ.**
- R7'nin ikinci yarısı (harness seçimi, iki kollu koşu, beş sayı, ham JSONL)
  bu turda hiç incelenmedi — GOAL 4/5/6/7'nin 13 kırmızısı teşhis edilmedi,
  yalnız kaydedildi. **İNCELENMEDİ.**
- **A1 ÖNCELİK SORUSU hâlâ cevapsız** (`KOSU-RABADON-2.md:54-57`): accept.sh
  olduğu gibi mi kalsın, yoksa R7a (kanıt) / R7b (daemon) diye ayrılsın mı?
  Bu bir OPERATÖR kararıdır ve R7'ye kod yazılmadan önce verilmelidir —
  22 kırmızının 9'u daemon kolunda, 13'ü kanıt kolunda.
