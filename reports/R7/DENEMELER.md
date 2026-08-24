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

## deneme 3 — 2026-08-24 (tur 6, yapan) — daemon YAZILDI, iki fail-open bulundu ve kapatıldı, hız iddiası ÇÜRÜDÜ

**BAĞLAM.** Operatör CEVAP 3 ile A1 öncelik sorusunu kapattı: accept.sh
BÖLÜNMEZ, 22 kırmızı birlikte kapanır (`reports/kosu/4.operator.md`). Karar
`KOSU-RABADON-2.md §A1`'e işlendi (commit d4e7a90). Bu oturum daemon kolunu
(GOAL 1–3) hedefledi; kanıt kolu (GOAL 4–7) elle sürülmedi.

**DENENEN.** `native/gated.cpp` + `native/gated_client.h` yazıldı, Makefile'a
`native/rabadon-gated` hedefi eklendi. Mimari karar: daemon, gate.cpp'yi
`#define main rb_gate_main` ile **include eder**. Yargılamanın ikinci bir
kopyası YOKTUR — daemon ile kapının farklı karar verebileceği bir dünya
kurulmadı. İstek başına iki fork (handler + worker); worker cwd/env/stdout/
stderr olarak çağıranın kendisi olur ve olağan `rb_gate_main()`'i koşar.

**SONUÇ 1 — iki gerçek fail-open bulundu, ikisi de ÖLÇÜLEREK.**
İlk sürüm `rm -rf /` için doğru ret metnini bastı ama **çıkış kodu 0** döndü
(doğrudan koşuda 2). Kök sebep zincirleme iki hataydı:

    [DBG] worker=59806 got=-1 errno=10      <- ECHILD
    [DBG] client read got=0 code=0          <- verdict hiç gelmedi

1. Daemon'ın SIGCHLD reaper'ı handler çocuğuna **miras kalıyor**; worker
   ölünce handler'ın kendi `waitpid(-1)`'i statüyü önce topluyor, handler'ın
   `waitpid(worker)`'ı ECHILD alıyor, verdict yazılmıyor.
2. Daha derini: verdict gelmeyince istemci fallback'e düşüyor — ama fd 0'ı
   worker'a devretmiştik, yani **stdin zaten tüketilmişti**. Fallback boş olay
   okuyup `return 0` veriyor. Yani ölü daemon = SESSİZ İZİN.

Düzeltme: (1) handler `signal(SIGCHLD, SIG_DFL)` ile kendi çocuğunun statüsüne
sahip olur; (2) **stdin ARTIK DEVREDİLMEZ** — olay baytları payload'da kopya
gider, istemci kendi kopyasını korur, sadece stdout/stderr SCM_RIGHTS ile
geçer. Fallback ancak çağıran tek başına yargılayabiliyorsa dürüsttür.
Doğrulama (kendi harness'im, sealed betik değil): `rm -rf /` üç kolda da
rc=2 ve aynı ret metni — doğrudan / daemon açık / daemon ölü.

**SONUÇ 2 — accept.sh 9 yeşil / 17 kırmızı (6/20'den).** GOAL 1'in üçü de
yeşil (1a/1b/1c). GOAL 8 bozulmadı: moves 21/0, signals 39/0, R2 19/0.

**SONUÇ 3 — R7'nin HIZ İDDİASI ÖLÇÜLDÜ VE ÇÜRÜDÜ. Negatif sonuç, olduğu gibi.**
accept.sh'ın kendi prob tekniğiyle (yama yalnız /tmp kopyasına), 300 örnek:

| kol | süreç içi medyan |
|---|---|
| daemon AÇIK (istemci devrediyor) | **1597.3 µs** |
| daemon YOK (bugünkü yol) | **1139.6 µs** |
| tavan (KOSU-RABADON R7) | 1000 µs |

Daemon ölçülen sayıyı **iyileştirmiyor, kötüleştiriyor** (+457 µs) ve iki kol da
tavanın üstünde. Sebep yapısal: prob `t0`'ı **istemcinin** `main()`'inin başına
koyuyor, yani daemon'ın sildiği şeyi (fork/exec/dyld, ~2.3 ms) ölçüm ZATEN
dışarıda bırakıyor; buna karşılık daemon'ın eklediği şeyi (iki fork + IPC +
worker'ın tam yargılaması) ölçümün TAM İÇİNE koyuyor. Bu şekildeki hiçbir
daemon bu aletle <1 ms gösteremez. CHALLENGE dosyasında ayrıntılı.

**ELENEN HİPOTEZ.**
- "Daemon süreç açılışını sildiği için süreç içi medyan <1 ms'ye iner" —
  **ELENDİ, ölçümle.** Sildiği maliyet aletin görüş alanının dışında.
- "`reports/R7/accept.sh:107` mktemp soketi `sun_path` tavanını aşabilir"
  (deneme 1'in açık ucu) — **ELENDİ, ölçüldü:** yol 79 bayt, macOS tavanı 104.
  Bu makinede ihlal yok.
- "Daemon yazmak GOAL 2/3'ü yeşile çeker" — **ELENDİ:** 2a ve 3a-c betiğin
  kendi kusurları yüzünden hiçbir uygulamayla geçemez (CHALLENGE).

**KALAN HİPOTEZLER.**
- Worker'ın (sıcak fork) yargılaması soğuk süreçten ucuz mu? Toplam 1597 µs
  bileşenlerine AYRILMADI (istemci-öncesi iş / IPC / worker). **ÖLÇÜLMEDİ.**
- Daemon uçtan uca (Claude Code'un gördüğü duvar saati) kazandırır mı? R7
  uçtan uca cetveli YASAKLIYOR, o yüzden koşulmadı. **ÖLÇÜLMEDİ.**
- 1139 µs'lik gerçek yargılama işinin kendisi nasıl <1000 µs'ye iner
  (PROFIL.md: `save#2` ~165 µs, `last_ledger_mode` O(dosya))? Bu, daemon
  sorusu değil, gate'in kendi maliyeti. **İNCELENMEDİ.**
- `native/gate.cpp:720` `open_sock()` sessiz `strncpy` kesmesi (deneme 1 §5)
  hâlâ duruyor. Yeni istemci kendi yolunu kontrol ediyor ve KONUŞUYOR, ama
  eski watch istemcisine dokunulmadı. **DÜZELTİLMEDİ.**
- GOAL 4d/5/6/7'nin 13 kırmızısı (kanıt kolu) bu turda da elle sürülmedi.
  **İNCELENMEDİ.**
