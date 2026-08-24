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

## deneme 4 — 2026-08-24 (tur 7, yapan) — operatör CEVAP (a) uygulandı; MÜHÜRLÜ betik İLK KEZ 2b sayısı üretti

**BAĞLAM.** Operatör, deneme 3'ün CHALLENGE'ına (a) ile cevap verdi
(`reports/kosu/6.operator.md`): accept.sh DAR KAPSAMLI düzeltilir, (b) ve (c)
REDDEDİLDİ, **1000 µs tavanı DEĞİŞMEZ**. İzin verilen tam olarak iki kalem:
hazırlık döngüsüne gerçek+tavanlı bekleme, ve YALNIZ kimlik alanlarının
(run, pipe, kum havuzu yolu) normalize edilmesi. Zincir hash'ini toptan
körleştirmek YASAK; satır sayısı/sırası karşılaştırılmaya devam eder.

**DENENEN.** İki kalem uygulandı, koddan ayrı KENDİ COMMIT'İNDE (ba231d6):
`sock_bekle()` (100 × 0.1 sn, tavan 10 sn, soket hâlâ ZORUNLU) accept.sh:113
ve :169'daki uykusuz `seq 50` döngülerinin yerine; `kimliksiz()` ise run3'ün
TÜM çıktısını (yalnız ledger'ı değil — ret metni de gerçek proje yolunu
basıyordu) `$H`/`$PJ`, `"run"`, `"pipe"` üzerinden temizliyor. Sonra mühürlü
betik koşuldu: `bash reports/R7/accept.sh > reports/R7/accept.out 2>&1`.

**SONUÇ 1 — 2a İLK KEZ YEŞİL.** Teşhis doğrulandı: sorun daemon değil,
uykusuz döngüydü. Gerçek bekleme konunca soket her koşuda belirdi.

**SONUÇ 2 — GOAL 2b, MÜHÜRLÜ ALETLE İLK SAYI. Negatif, olduğu gibi.**
Deneme 3'ün 1597.3 µs'i yapanın kendi /tmp yeniden kurgusundandı; operatör
haklı olarak "aletin hiç okumadığı bir şartı emekli edemezsin" dedi. Alet
artık okudu:

| ölçüm | sayı | kaynak |
|---|---|---|
| süreç içi medyan, daemon açık, 300 örnek | **1704.4 µs** | accept.out, GOAL 2b |
| tavan (KOSU-RABADON R7, DEĞİŞMEDİ) | 1000 µs | accept.sh:121 |
| 50-olay / 400-olay medyan | 1665.8 / 1748.8 µs | accept.out, GOAL 2c |
| uzunluk sapması | **4.98%** | accept.out, GOAL 2c |

Mühürlü sayı yapanın kendi sayısından **daha kötü** (1704.4 > 1597.3). Yani
hız iddiası mühürlü aletle de kırmızı, ve /tmp kurgusu iyimserdi.
`reports/R7/LENGTH.md` yazıldı → 2c artık kimlik alanları değil, GERÇEK
eksik yüzünden değil, kayıt yapıldığı için YEŞİL olmaya uygun.

**SONUÇ 3 — GOAL 3: fail-SAME'in KENDİSİ ARTIK KANITLANDI; kalan fark tek
bir alanda.** Normalizasyondan sonra üç komutun da çıkış kodu, `ev`, `mode`,
`rule`, ret metni, `seq`, satır SAYISI ve SIRASI **bayt bayt aynı**. Örnek
(`rm -rf /`, iki kol yan yana) tüm satır aynı, tek fark `"prev"`:

    ...,"rule":"baseline-rm-rf-outside",...,"prev":"47bbbbad29fe23..."
    ...,"rule":"baseline-rm-rf-outside",...,"prev":"359ef055d3fa34..."

Bu, deneme 3'ün iki fail-open düzeltmesinin **mühürlü betikle teyididir**
(operatörün sıraya aldığı kalem): ölü daemon artık sessiz izin vermiyor,
davranış birebir aynı.

**SONUÇ 4 — GOAL 4–7'nin 13 kırmızısının kök sebebi TEK ve teşhis edildi.**
İki kollu koşu HİÇ KOŞULMADI, dolayısıyla `reports/R7/` altında JSONL yok;
5a/5b/5c, 6a–6e, 7a/7b bunun türevleri. 4d ayrı ve küçük: HARNESS.md
.git-temizliği / egress-kapatma hazırlığını "best-effort" etiketiyle
kaydetmiyor. **Bu oturum 4d'yi YAZMADI**: koşu yokken hazırlık belgesi
yazmak, kontrolü yeşile çekip değeri var etmemek olurdu (ödül hacklemesi).

**ELENEN HİPOTEZ.**
- "2a hiçbir uygulamayla geçemez" (CHALLENGE iddia 1) — **ELENDİ**, tavanlı
  bekleme ile geçti. Teşhis doğru, ama "geçilemez" yanlıştı.
- "GOAL 3 temp-dir hash'i yüzünden geçemez" (CHALLENGE iddia 2'nin yapan
  tarafından verilen sebebi) — **ELENDİ**: sebep temp-dir değil, runId'nin
  pid'i + `prev` zincir alanıydı. Operatörün teşhisi (gate.cpp:2738) doğruydu.
- "1597 µs yapanın kurgusunun eseri, mühürlü alette düşer" — **ELENDİ**,
  mühürlü alette 1704.4 µs, daha yüksek.

**KALAN HİPOTEZLER.**
- **`"prev"` ve `.head` sidecar'ı kimlik türevidir ve GOAL 3'ü hâlâ
  geçilemez kılıyor.** `prev`, bir ÖNCEKİ satırın NORMALİZE EDİLMEMİŞ
  içeriğinin SHA-256'sıdır (native/chain.h:191) — o içerikte gerçek `ts` ve
  gerçek `run` vardır, ki ikisi de zaten normalize ediliyor. Dolayısıyla
  `prev` iki koşu arasında ASLA eşleşemez. Aynısı `spool/*.head` için:
  biçimi `<64hex> <satır sayısı>`. Bu operatörün izin verdiği üç alanın
  DIŞINDA, yani bu oturum DOKUNMADI — ayrı operatör kararı gerekiyor
  (`reports/R7/CHALLENGE-2.md`).
- 1704.4 µs hâlâ bileşenlerine ayrılmadı. En güçlü aday gated.cpp:19-24'te
  BELGELENMİŞ "istek başına İKİ fork" — daemon'ın sildiği süreç maliyetini
  ölçümün içine geri koyuyor. ÖLÇÜLMEDİ.
- `native/gate.cpp:720` `open_sock()` sessiz `strncpy` kesmesi hâlâ açık
  (Promise 1). Bu turda incelenmedi.

**SONUÇ 5 (ikinci koşu) — 2c YEŞİL ama SAYISI GÜVENİLMEZ.** LENGTH.md
yazıldıktan sonra betik ikinci kez koşuldu: **11 yeşil / 15 kırmızı**. 2c
yeşile döndü (kayıt şartı sağlandı). ANCAK sayılar oynadı: sapma
4.98% → **1.92%** (2.6 kat), 2b medyanı 1704.4 → **1583.2 µs** (%7.1). Aynı
makine, aynı binary, aynı commit, dakikalar arayla. Yani 2c'nin SAYISI
ölçülmüş sayılmaz — gürültü içinde. LENGTH.md ikisini de kaydediyor; iyimser
olanı seçmek yok. 2b'nin VERDICT'i etkilenmiyor: iki koşu da tavanın ~1.6
katı, gürültünün çok dışında. KIRMIZI.

**KALAN HİPOTEZ (yeni).** 2c/2b ölçümünün koşudan koşuya saçılımının sebebi
ayrıştırılmadı (arka plan yükü / örnek sayısı / interleave'in drift'i gerçekte
iptal etmemesi). ÖLÇÜLMEDİ.

## deneme 5 — 2026-08-24 (tur 8, yapan) — operatör CEVAP (d) uygulandı; GOAL 3 YEŞİL, ve mühürlenen şey bir zayıflatma DEĞİL

**DENENEN.** `reports/kosu/7.operator.md` CEVAP'ı: (d) = (a) KABUL ama tek
başına değil, ZORUNLU 3. madde ile. Yalnız `reports/R7/accept.sh`, kendi
commit'inde, koda dokunmadan (`6481549`).

**SONUÇ 1 — taban KIRMIZI olarak doğrulandı (değişiklikten ÖNCE).** 11 yeşil /
15 kırmızı. GOAL 3 diff'i operatörün analizini bire bir doğruladı:
`echo hello world` YALNIZCA 4. satırda, yani `.head`'de ayrışıyor — `prev`
suçlu değil, çünkü tek satırlık komutta `prev:"genesis"`. `rm -rf /` ise hem
`prev` hem `.head`'de ayrışıyor. Operatörün "YAPANIN ATLADIĞI 1" notu doğru.

**SONUÇ 2 — değişiklikten SONRA 14 yeşil / 12 kırmızı.** GOAL 3'ün üç kolu da
yeşil. `kimliksiz()` iki satır genişledi (yalnız 64-hex `prev`; `.head`'in
yalnız baştaki hash'i, SAYAÇ KORUNDU), ve her iki kolda karşılaştırmadan ÖNCE
`native/rabadon-audit --days 2` koşup `INTACT` + exit 0 şart koşuluyor.

**SONUÇ 3 — 3. maddenin DİŞİ VAR, mutasyonla kanıtlandı (iddia değil).**
Betiğin kopyası bozuldu, gerçek betik değil:
- mutasyon A (spool'da `"sess"` alanı kurcalandı, B kolunda): audit
  `chain BROKEN` + rc=1 → GOAL 3 KIRMIZI. Yakalandı.
- mutasyon B (ASIL TEST — yalnız artık körleştirilen `prev`, başka geçerli
  bir 64-hex ile değiştirildi): bayt karşılaştırması bunu GÖREMEZ, çünkü iki
  kolda da `PREV`'e körleşiyor. Audit yakaladı:
  `chain BROKEN at line 2 (prev=deadbeef0000… expected=ee727fc831e6…)`.
  Yani körleştirmenin kaybettiği TEK sinyal (zincirin bağlantı aritmetiği)
  gerçekten geri alınmış durumda. Bu bir test GÜÇLENDİRME hamlesi.
- körleştirmenin darlığı ayrıca birim olarak sınandı: `prev:"genesis"` ve
  EKSİK `prev` körleşmiyor; `.head` sayacı (`HASH 2` vs `HASH 7`) korunuyor;
  `^[0-9a-f]{64} ` deseni gerçek ledger JSON satırına DEĞMİYOR (`{` ile
  başlıyorlar).

**ELENEN HİPOTEZ.** "GOAL 3 kırmızılığı daemon'da bir fail-open'dan
kaynaklanıyor olabilir" — ELENDİ. Üç komutun tamamında fark yalnız zincir
kimlik alanlarındaydı; davranış (çıkış kodu, `ev`, `mode`, `rule`, ret metni,
satır sayısı ve sırası) zaten bayt bayt aynıydı.

**YASAKLANAN YOL (kalıcı, operatör kararı).** Zinciri NORMALİZE edilmiş
satırdan hesaplamak. Deterministik olduğu ölçüldü ve YASAK: zincir o zaman
ts/run/yol alanlarına taahhüt etmez, saldırgan zaman damgasını değiştirir ve
ledger yine "sağlam" görünür. Bir testi geçirmek için üründeki kurcalama
kanıtını yok etmek olurdu.

**KALAN HİPOTEZLER (sıradaki iş).**
- 2b hâlâ KIRMIZI ve bu turda sayı ÜÇÜNCÜ kez oynadı: 1704.4 → 1583.2 →
  **2063.1 µs**. Üç koşu, aynı makine/binary/commit. Tavan 1000 µs; üçü de
  tavanın üstünde, yani VERDICT sağlam, ama SAÇILIM (%30) ayrıştırılmadı.
  Bileşenlere ayırma (istemci-öncesi / IPC / worker yargılaması) HÂLÂ
  YAPILMADI — operatör bu ayrıştırma gelmeden hız iddiası hakkında yeni karar
  vermeyeceğini yazdı. Sıradaki iş budur.
- Aynı koşuda 2c sapması 3.51% (önceki iki koşu: 4.98%, 1.92%). Üç ölçüm üç
  farklı sayı → 2c'nin SAYISI hâlâ güvenilmez; LENGTH.md bunu kaydetmeli.
- `native/gate.cpp:720` `open_sock()` sessiz `strncpy` kesmesi ÜÇÜNCÜ turdur
  açık (Promise 1 ihlali). Bu turda da incelenmedi.
- GOAL 4d ve 5-7 (kanıt kolu: iki kollu koşu, ham JSONL, beş sayı) hiç
  başlamadı — 12 kırmızının 11'i orada.

### deneme 5 — devam (aynı oturum, tur 8): 2b AYRIŞTIRILDI ve suçlu daemon DEĞİL

**DENENEN.** Operatörün "bu ayrıştırma gelmeden hız iddiası hakkında yeni karar
verilmeyecek" dediği bileşen ayrıştırması. R1.3 süreç-içi probu, 6 tur × 300
örnek = 1800 istek, 11 bitişik kova, artık **0.000 µs**. Yöntem ve komutlar
`reports/R7/PROFIL-DAEMON.md`. native/ kaynağına DOKUNULMADI (prob /tmp'de).

| kova | µs | pay |
|---|---|---|
| istemci, IPC öncesi | 6.5 | 0.4% |
| IPC taşıma | 31.8 | 2.1% |
| fork #1 (handler) | 160.6 | 10.4% |
| fork #2 (worker) | 144.8 | 9.4% |
| exit + reap | 121.3 | 7.9% |
| **rb_gate_main() yargılama** | **1075.1** | **69.7%** |
| TOPLAM | 1542.3 | 100% |

**SONUÇ 1 — belgelenmiş şüpheli GERÇEK ama YETERLİ DEĞİL.** `gated.cpp:19-24`'ün
"istek başına iki fork"u 305.4 µs (%19.8); zorladığı reap ile birlikte tüm
daemon iskelesi 426.7 µs (%27.7). Ama karşı-olgu: **iki fork DA tüm IPC DE
bedava olsa medyan 1144.5 µs** — tavan yine aşılıyor. Yargılama tek başına
1133.9 µs. **1000 µs tavanı yargılama kaçırıyor, daemon değil.** Yani daemon
üzerinde yapılacak hiçbir iş 2b'yi yeşile çeviremez. Bu turun asıl bulgusu bu.

**SONUÇ 2 — ikinci negatif ölçüm.** Sıcak fork'lanmış worker 1075.1 µs,
soğuk süreç 1067.4 µs → **+7.7 µs**. Yani `gated.cpp:11-17`'de yazılı COW/sıcak
sayfa devralma argümanı `main()` içinde HİÇBİR ŞEY kazandırmıyor. Belgedeki o
yorum artık ölçümle çelişiyor.

**ELENEN HİPOTEZ.** "1704 µs'nin sebebi iki fork" — ELENDİ (gerçek ama %20;
kaldırılsa bile kırmızı).

**SONUÇ 3 — SAÇILIMIN SEBEBİ: ARKA PLAN YÜKÜ, talep üzerine üretildi.**
loadavg 2.5 → ~1500 µs, 5.5 → ~1966/2095, 8.0 → 2652, eşzamanlı `c++ -O2` →
3135 µs. Mühürlü üç sayı (1583/1704/2063) bu eğrinin üstünde oturuyor.
ELENDİ: örnek sayısı (n=1000 güven aralığını yarıya indirdi, %6.5 saçılıma
dokunmadı) ve interleave'in drift'i iptal etmemesi (mutlak sayı için zaten
ilgisiz). Fork varyansı bağımsız sebep değil, YÜKSELTİCİ (çekişme altında
×8.9). **ALET KUSURU:** `accept.sh`, 2b'yi ölçmeden hemen önce probu DERLİYOR —
yani ölçtüğü yükün bir kısmını kendisi üretiyor.

**BU TURDA CANLI DOĞRULAMA (dördüncü sayı).** gate.cpp düzeltmesinden sonra
accept.sh yeniden koşuldu: **3150.1 µs** — şimdiye kadarki en yüksek sayı, ve
tam da ağır `make all` + tam test suite koşularının ardından alındı. Yük
teşhisini sahada doğruluyor. Dizi artık: 1704.4 → 1583.2 → 2063.1 → 3150.1.
**VERDICT DEĞİŞMİYOR ve yumuşatılmıyor:** en sessiz tur, neredeyse boş makinede
1477.1 µs, yani tavanın %48 üstünde. 2b KIRMIZI.

**SONUÇ 4 — Promise 1 ihlali KAPANDI (üç turdur açıktı).** `gate.cpp:721`
`open_sock()`. Kanıt, okumayla değil deneyle: kapasiteyi 4 bayt aşan bir
`RABADON_DIR` ile, kesme noktasına bağlanmış bir dinleyiciye **168 bayt gerçek
STEP_START olayı teslim edildi**, exit 0, stderr boş. strncpy hata vermiyor;
hedeflenen yolun ÖNEKİ olan geçerli bir yol üretiyor ve gate oraya bağlanıyor.
Dünyaya yazılabilir bir önekte bu, olay akışını ilk bağlanana veren bir kanal.
Klasik strncpy bellek hatası DEĞİL (addr memset'li, sizeof-1 kullanılmış) —
kusur SESSİZLİK. Kardeş çağrı yerleri (`gated.cpp:157`, `gated_client.h:98`)
bu korumayı zaten taşıyordu; atlanan tek yer gate.cpp'ydi.
Önce KIRMIZI test (`native/sock_path_test.sh`, 1 ok / 2 FAILED), sonra ayrı
commit'te düzeltme (3 ok). Kaybedilen tek şey canlı watcher — o da zaten
kaybediliyordu, sadece sessizce.

**CHALLENGE-3 AÇILDI.** `KOSU-RABADON-2.md:67-68` "yol uzunluğu sınırı R7
testinde assert edilir" diyor. **YALAN:** accept.sh'ta da başka hiçbir testte
de böyle bir assert YOK (grep kanıtı CHALLENGE-3.md'de). Belge, kapsandığını
söylediği bir riski kapsamıyordu. Belge DÜZELTİLMEDİ — önerilen diff
CHALLENGE-3.md'de, insan onayı bekliyor. Bu madde KIRMIZI sayılır.

**KALAN HİPOTEZLER (sıradaki iş).**
- **2b için tek anlamlı soru artık şu: 1075 µs yargılamanın İÇİNDE nereye
  gidiyor?** Tek kova olarak ölçüldü, ayrıştırılmadı. R1.3'ün ayrıştırması
  farklı bir ağaç (süreç doğuşu dahil), doğrudan devredilemiyor.
- Mimari sonuç, operatör kararı gerektiriyor: bu yargılama maliyetiyle <1 ms
  tavanı bu mimaride ULAŞILAMAZ görünüyor. Karar YAPAN'ın değil.
- 2c hâlâ güvenilmez (4.98 / 1.92 / 3.51%), yeterli örnekle yeniden ölçülmedi.
- `cli_test.sh` 4 kırmızı (rabadon-gated npm paketlerinde çözümlenmiyor;
  `--help`/`-h`/tanımsız bayrak 10 sn ASILIYOR) ve `promises_test.sh` 3 kırmızı
  (Promise 3 ve 4). İkisi de bu turdan ÖNCE de kırmızıydı (fix stash'lenip
  yeniden derlenerek doğrulandı) — yani bu turun eseri değil, ama AÇIK.
  `rabadon-gated --help` asılması R8 yayınından önce kapanmalı.
- GOAL 4d ve 5-7 (kanıt kolu) hâlâ hiç başlamadı — 12 kırmızının 11'i orada.

## deneme 6 — 2026-08-24 (tur 9)

**DENENEN.** İki iş, operatörün CEVAP sırasıyla. (1) Tur 8'in "pre-existing"
iddiası ölçüldü: koşu başlangıcı `a59138b` ve `da9e5b2^` ayrı bir `/tmp`
klonunda derlenip koşuldu. (2) 1075 µs yargılama kovası ayrıştırıldı: iki
bağımsız prob (71 kovalı dışlamalı zaman yığını + `main()` içine 531 satır
damgalı kontrol noktası), 300×3 tur + yük altında tur, hepsi `/tmp` kopyalarına
yamalandı, `native/` altına yazılmadı.

**SONUÇ.**
- "Pre-existing" iddiası YARIYA BÖLÜNDÜ. `promises_test.sh` 3 kırmızı gerçekten
  pre-existing (a59138b'de birebir aynı çıktı). `cli_test.sh` 4 kırmızı ise
  **BU KOŞUDA GİRDİ**: `a59138b` ve `d4e7a90` yeşil (297/0), `da9e5b2` kırmızı
  (297/4). Suçlu commit R7'nin kendi GOAL 1 teslimatı. Ayrıntı REGRESYON.md.
- Yargılama ayrıştırıldı, mutabakat tam (kovalar toplamı − ölçülen toplam =
  +0.2 µs, %0.0; prob maliyeti +20.1 µs / %1.7). En büyük kalem **%28.5:
  `gate.cpp:2754`'teki gün dizgisi** — ayrı bir deneyle kanıtlandı ki bu bir
  saat dilimi ilklendirmesidir (soğuk worker'da 269–483 µs, aynı süreçte ikinci
  çağrı **1.0 µs**). Forklanan her worker bunu yeniden ödüyor.
- **Kural motoru yargılamanın %4.4'ü.** %95 defter tutma. Ayrıntı
  reports/R7/PROFIL-YARGILAMA.md.

**ELENEN HİPOTEZ.**
- **"Bu mimaride <1 ms ULAŞILAMAZ" ELENDİ.** Tur 8'in kendi deyimiyle bir
  ekstrapolasyondu; ölçüm çürüttü. Anlamı değişmeyen üç kalem (gün dizgisi,
  `note_mode` spool taraması, tekrarlanan `resolve_real`) %43; oturum durumu
  gidiş-dönüşü eklenince %72. Operatörün %55 eşiği AŞILABİLİR görünüyor.
  Karar kuralı gereği **tavan KALIR, seçenek (b) açılmaz.**
- **"1075 µs regex + dosya I/O'dur" ELENDİ.** Regex (`rx_test`) %1.5, guard
  okuması %4.3. Tur 8'in (b) gerekçesindeki "C'de tipik 200–800 µs regex+I/O"
  literatür tahmini bu ağaçta YANLIŞ.
- **"cli_test kırmızıları bizim eserimiz değil" ELENDİ** (yukarıya bak).

**KALAN HİPOTEZLER (sıradaki iş).**
- Sıradaki turun İLK işi: `da9e5b2` regresyonunu kapatmak (rabadon-gated'a
  case arm + `rb_help`). Bunlar R7'nin kendi teslimatının kusuru ve
  `--help` asılması R8'i de bloklar.
- Projeksiyon ÖLÇÜM DEĞİL: "1075 → 303 µs" aritmetiktir. İlk denenecek kalem
  tartışmasız olan gün dizgisi (%28.5, semantik bedeli yok).
- **SINIR ÇİZGİSİ:** %55 eşiği yalnız oturum durumu gidiş-dönüşü dahil
  edilirse aşılıyor (%43 vs %72) ve o kalem dayanıklılık semantiğini
  değiştirir. Defter yazımı (%15.3) optimizasyon hedefi DEĞİLDİR — sayı için
  delil kısmak bu ürünün varlık sebebine aykırıdır.
- Mutlak sayılar bu koşuda güvenilmez: makine yük ortalaması 3.93–5.21 idi,
  medyanım 1205.7 µs, tur 8'in 1061–1134 aralığının dışında. Paylar dayanıklı
  (3 kat yük değişiminde sabit), mutlaklar değil. Kamuya <1 ms iddiası bu
  ölçümden TÜRETİLEMEZ.
- Boş guard.json ile ölçüldü; kurallı bir projede regex payı yükselir, ölçülmedi.
- 2c hâlâ güvenilmez; GOAL 4d ve 5-7 (kanıt kolu) hâlâ hiç başlamadı.

## deneme 7 — 2026-08-24 (tur 10, yapan) — `da9e5b2` regresyonu KAPANDI; gün dizgisi denendi ve ÖLÇÜLDÜ: −229.8 µs, tavan hâlâ kırmızı

**DENENEN (1/2) — regresyon.** Tur 9 teşhisi (`reports/kosu/REGRESYON.md`)
suçluyu `da9e5b2`'ye bağlamıştı: `rabadon-gated` `make all`'a eklenmiş, başka
hiçbir yere eklenmemişti. Üç delik, tek sebep — ve teşhis ikisini görmüştü,
üçüncüsünü bu tur ölçüm buldu:

1. `native/rabadon-cli.sh`'te `case arm` yok. `npm i -g rabadon` sonrası
   dispatcher **kamusal yüzeyin kendisi**, dolayısıyla daemon repo'yu
   klonlamamış hiç kimse için erişilemezdi. `gated)` armı + `rabadon dev`
   ekranında bir satır (satır olmadan test keşfedilebilirliği kırmızı sayıyor).
2. `gated.cpp` `main()` doğrudan `listen()`'a gidiyordu: `--help`, `-h` ve
   tanımsız bayrak **10 sn ASILIYORDU**. `rb_help` artık `main`'in ilk ifadesi
   (soket işinden önce), bayrak biçimli tanımsız argüman `rb_unknown_flag` ile
   **reddediliyor** (exit 2), yutulmuyor.
3. **BU TUR BULUNDU:** `rabadon-gated` dört platform paketinin hiçbirinin
   `files` listesinde yoktu. Prebuilt kurulumda `rabadon doctor` → *"1 of 19
   binaries absent"*. `make clean` de aynı unutmayı taşıyordu.

**SONUÇ (1/2).** Ölçüm, iddia değil:

| suite | önce | sonra |
|---|---|---|
| `./native/cli_test.sh` | 297 passed, **4 failed** | **310 passed, 0 failed** |
| `./native/npm_install_test.sh` | 11 passed, **1 failed** | **12 passed, 0 failed** |

+13 geliyor çünkü 4 asılma, arkasındaki 9 iddiayı da ölçülemez kılıyordu.
npm kırmızısı için pre-existing kontrolü ayrı klonda yapıldı (B1.8, canlı
worktree'ye dokunulmadı): `git clone . /tmp/rbnpmbase`, `72f5f5f`, `make all`,
suite → **11 passed, 1 failed.** Bu değişiklikten ÖNCE kırmızıydı, `da9e5b2` ile
doğmuştu, sonra yeşil. Commit: `d4fd723`.

**DENENEN (2/2) — gün dizgisi.** `PROFIL-YARGILAMA.md`'nin %28.5'lik kalemi.
Önce KIRMIZI test kendi commit'inde (`12fb21f`, mühür kuralı: kabul kriteri
kodla aynı commit'te olmaz), sonra uygulama (`a821278`).

`native/day_cache_test.sh` iki yönü birbirine karşı geriyor, ve **hiçbiri
diğerini geçirmek için düşürülemez**:
- DOĞRU — önbellek 4808 damgada `gmtime_r`+`strftime` ile birebir aynı: 200 gün
  saatlik adımlarla, gece yarısının iki yanı **ters sırada** sorulmuş, artık
  gün, yıl sınırı.
- UCUZ — 100k tekrar çağrı 3733 µs; **forklanan çocuğun İLK çağrısı 21 µs**
  (cold 269–483 µs idi). Daemon şeklinin tamamı bu satırda.

Anahtar `t/86400` — UTC günü tam 86400 sn olduğu için gece yarısı önbelleği
**tam** geçersiz kılıyor. Takvim aritmetiği yeniden yazılmadı; `gmtime_r` hâlâ
onu yapıyor, sadece çağrı başına değil gün başına soruluyor. `rabadon-gated`
`listen()` öncesi bir kez ısıtıyor, worker'lar COW ile miras alıyor.

**SONUÇ (2/2) — SAYI, ve nasıl alındığı.** Tek bir önce/sonra okuması bunu
çözemez: `PROFIL-YARGILAMA.md` aynı kodun iki koşuda 1108 ve 3058 µs verdiğini
kaydediyor, yani sürüklenme aranan etkiden büyük. Bu yüzden
`reports/R7/ab_day.sh` accept.sh'ın **kendi aletini** iki kaynağa karşı
**dönüşümlü** koşuyor (hangi kolun önce gittiği de her turda değişiyor):

```
round      OLD_us     NEW_us   DELTA_us
1          1531.2     1252.5      278.7
2          1444.0     1180.0      264.0
3          1450.0     1269.0      181.0
4          1564.9     1354.3      210.6
median of medians: OLD 1490.6 -> NEW 1260.8   DELTA 229.8 us (%15.4)
eşleşmiş her tur NEW lehine: True
```
Yeniden koşturma: `bash reports/R7/ab_day.sh 4 300 12fb21f`

**NEGATİF SONUÇ, düz yazılıyor.** 229.8 µs gerçek ve tekrarlanabilir, ama
%28.5 payının tur 8 tabanına (1075 µs) izdüşümü olan **306 µs'den AZ.** Ve
tavana ulaşmıyor: `accept.sh` 2b bugün **1235.3 µs**, tavan 1000 µs, hâlâ
KIRMIZI. Bu tam olarak `PROFIL-YARGILAMA.md`'nin kendi aritmetiğinin söylediği
şey: bu kalem tek başına %28.5'ti, eşik dört kalemle %72 istiyordu. Bir kalem
denendi, bir kalemlik yer kazanıldı, tavan kırmızı kaldı.

**KABUL BETİĞİ (mühürlü, değiştirilmedi).** `bash reports/R7/accept.sh` →
**14 green, 12 red, R7 NOT ACCEPTED** (ham çıktı `reports/R7/accept.out`
bugünkü koşuyla güncellendi; dosyada duran 11/15 tur 8 öncesineydi).
Kısmi yeşil kabul değildir — sayı raporlanıyor, kabul edilmiyor. Bu tur
accept.sh'ın yeşil sayısını **değiştirmedi**: her iki iş de accept.sh'ın
ölçtüğü yerde değil, altındaki suite'te ve 2b'nin içinde duruyordu.

**ELENEN HİPOTEZ.**
- "`make test` ilk kırmızı suite'te duruyor, `promises_test.sh` sıranın
  sonunda kaldığı için hiç görülmüyor" (`REGRESYON.md` PARKED maddesi) —
  **KISMEN YANLIŞ, düzeltiliyor.** `promises_test.sh` `make test`'in içinde
  DEĞİL; `Makefile:932` ayrı bir `promises` hedefi ve ayrı olması bilinçli
  (Makefile:925-931'deki gerekçe). Yani `make test` rc=0'ı 3 promises
  kırmızısını "gizlemiyor" — onları hiç kapsamıyor. Kör nokta gerçek, ama
  sebebi sıralama değil, hedef ayrımı.

**KALAN HİPOTEZLER (sıradaki iş).**
- Tavan için kalan üç kalem: `note_mode` spool taraması (%7.2), `resolve_real`
  8 realpath (%7.3), oturum durumu gidiş-dönüşü (%28.9). İlk ikisi
  `PROFIL-YARGILAMA.md`'de "saf israf" olarak işaretli. Üçüncüsü DEĞİL —
  dayanıklılık semantiğini değiştirir ve o raporun çizdiği sınır çizgisi
  hâlâ geçerli: sayı için delil kısılmaz.
- `promises_test.sh` 3 kırmızı (Promise 3 ve 4) — pre-existing, doğrulandı
  (`REGRESYON.md` Bulgu 1), kendi turunu bekliyor.
- `CHALLENGE-3` hâlâ açık, insan onayı bekliyor.
- GOAL 4d/5/6/7 (iki kollu koşunun ham JSONL'i) bu turda hiç ele alınmadı;
  accept.sh'ın 12 kırmızısının 9'u orada.

**NOT VERIFIED.**
- Hiçbir şey temiz container'da koşulmadı. Tüm ölçümler bu macOS makinesinde.
  Saat dilimi ilklendirme maliyeti platforma bağlı; Linux'ta doğrulanmadı.
- A/B ölçümü sırasında makine SAKİN DEĞİLDİ (load 3.48–5.84). Bu yüzden iddia
  eşleşmiş fark (229.8 µs), mutlak sütun (1260.8 µs) değil.
- Gece yarısını gerçekten geçen canlı bir daemon çalıştırılmadı; sınır davranışı
  `rb_day_str_at`'e damga vererek test edildi, saat ilerletilerek değil.
- Önbellek statikleri kilitsiz. Kapı süreç başına tek iş parçacığı ve daemon
  fork ediyor (thread değil), bu yüzden bugün doğru; bir gün thread girerse
  kilit gerekir, yorumda yazılı.
- `ab_day.sh` OLD kolunu `12fb21f`'ten iki dosya (`gate.cpp`, `gated.cpp`) ile
  kuruyor; başlıklar bugünkü ağaçtan. İki commit arasında başlık değişmediği
  için doğru, ama bu bağımsız olarak assert EDİLMİYOR.
- `npm_install_test.sh` yalnız darwin-arm64 için koştu; diğer üç platform
  paketinin `files` listesi elle düzeltildi, ölçülmedi.

## deneme 11 — 2026-08-24 (tur 11, yapan) — CHALLENGE-3 bloker mı: HAYIR

**DENENEN.** Tur 10'un kapanışında "CHALLENGE-3 açık, bir bloker, GOAL'lerin
önüne geçiyor" yazıyordu. Bu turda kod yazılmadı; tek soru şuydu: CHALLENGE-3
tam olarak neyi talep ediyor ve `reports/R7/accept.sh`'ın GOAL 5/6/7'siyle
gerçekten kesişiyor mu? Dosya okundu, iddiaları bugünkü ağaç üzerinde yeniden
koşuldu, accept.sh'ın 5/6/7 satırları tek tek çıkarıldı. Tam rapor:
`reports/R7/TESHIS-CH3.md`.

**SONUÇ — kesişim SIFIR.** CHALLENGE-3 tek bir şey talep ediyor ve o şey
BELGESEL: `KOSU-RABADON-2.md:63-69`'daki "yol uzunluğu sınırı R7 testinde
assert edilir" cümlesi ya doğru yapılacak ya silinecek, insan onaylı ve kendi
commit'inde. accept.sh'ta soketle ilgili tek satır yok:

```
$ grep -niE 'sun_path|ENAMETOOLONG|104|108|path.*(length|len|too long)' reports/R7/accept.sh
>>> no match
$ grep -n 'sock_path_test' reports/R7/accept.sh
>>> no match
```

GOAL 5 (`accept.sh:387-425`), GOAL 6 (`431-489`) ve GOAL 7 (`492-521`) tek bir
üst-gerçeğe bağlı: `accept.sh:387`'deki `ls "$RD"/*.jsonl` boş dönüyor. On
kırmızının onu da oradan düşüyor. accept.sh'taki tek "uzunluk" işi GOAL 2c
(`145`, `210-241`) ve o **ledger** uzunluğu — CHALLENGE-3 bunu kendi 24-25.
satırında zaten ayırıyor. **GOAL 5/6/7'nin önünde duran şey CHALLENGE-3 değil,
olmayan iki kollu JSONL.**

**CHALLENGE-3 METNİ ARTIK BAYAT — teknik yarısı kapandı.** Dosya "risk hiçbir
testte kapsanmıyor" diyor; bu tur 8'de doğruydu, bugün değil.
`native/sock_path_test.sh` var: `7d344ee`'de KIRMIZI doğdu, bugün 3 ok / 0 FAIL
((a) kesik yola hiçbir bayt gitmiyor, (b) sebep stderr'de, (c) kapı rc=0 ile
spool-only sürüyor). Yetim de değil — `Makefile:856`, `test:` hedefi altında
(`Makefile:104`), olayın anlatısı üstüne yorum olarak yazılmış. Açık kalan tek
şey cümlenin kendisi ve o cümle hâlâ yanlış: assert `make test`'te, "R7
testi"nde değil.

**SAYIM DÜZELTMESİ.** Tur 10 bloğu "12 kırmızının 9'u GOAL 5/6/7'de" diyor;
doğrusu **10**: 5a 5b 5c, 6a 6b 6c 6d 6e, 7a 7b. Kalan ikisi 2b (medyan
1273.3 µs, tavan 1000 µs) ve 4d (.git temizleme / egress kapatma hazırlığı
kayıtsız).

**KABUL BETİĞİ (değiştirilmedi, olduğu gibi koşuldu).**
```
$ ./reports/R7/accept.sh
== R7 acceptance: 14 green, 12 red
R7 NOT ACCEPTED
```
Tur 10'la aynı: 14 yeşil / 12 kırmızı, ham çıktı `reports/R7/accept.out`.

**KALAN HİPOTEZLER (sıradaki iş).**
- Sıradaki iş CHALLENGE-3 DEĞİL. İki kollu koşunun ham JSONL'i: on kırmızı
  tek bir artefakta bakıyor. GOAL 6'nın istediği alan adları accept.sh'ta
  yazılı (`heldout_pass`, token toplamları, müdahale sayıları, FP oranı,
  `estimated_saved`) — üretici tarafı bu şemayı hedeflemeli.
- CHALLENGE-3 için tek eylem: insanın KOSU-RABADON-2.md diff'ini onaylaması.
  Ajan tarafında yapılacak iş kalmadı; §"If PROJECT.md itself is wrong"
  gereği kendi başımıza düzeltmiyoruz.
- 2b (medyan tavanı) ve 4d hâlâ kendi turlarını bekliyor.
- `promises_test.sh` 3 kırmızı (Promise 3 ve 4) — pre-existing, doğrulandı.

**NOT VERIFIED.**
- Hiçbir şey temiz container'da koşulmadı; hepsi bu macOS makinesinde.
  `sock_path_test.sh` Darwin'de CAP=104 seçiyor, Linux dalı (108) hiç
  çalışmadı.
- CHALLENGE-3'ü bir insanın GÖRÜP görmediği bilinmiyor. "İnsan onayı
  bekliyor" dosyanın kendi durum satırı, gözlenmiş bir olgu değil.
- CHALLENGE-3:52-63'teki önerilen diff uygulanmadı ve bugünkü
  KOSU-RABADON-2.md'ye temiz uyup uymadığı denenmedi.
- Bu turda iki kollu koşu denenmedi; on kırmızı accept.sh okunarak teşhis
  edildi, veri üretilip yeşile döndükleri görülerek değil.

## deneme 12 — 2026-08-24 (tur 12, yapan) — iki kollu koşu DENENDİ, dört blokerde durdu; JSONL UYDURULMADI

**DENENEN.** Tur 11'in "sıradaki iş" satırı: on kırmızının tek artefaktı, iki
kollu JSONL. Önce `accept.sh:387-521` okundu ve üretilecek şemanın tamamı
çıkarıldı; sonra SWE-smith v0.0.6 (HARNESS.md'nin sabitlediği sürüm) gerçekten
kurulmaya çalışıldı. Tam teşhis + komut/çıktı: `reports/R7/TESHIS-HARNESS.md`.

**ŞEMA ÇIKARILDI (yapılacak işin hedefi, artık yazılı).** `ls "$RD"/*.jsonl`
(`accept.sh:388`) — yani `reports/R7/` altında **herhangi bir** `*.jsonl`, adı
serbest, boş olmayacak. Satır başına bir kayıt; zorunlu alanlar: `arm` ("A"/"B",
büyük-küçük fark etmez), görev anahtarı `task` | `task_id` | `instance_id`
(üçünden biri), `heldout_pass` (bool), `tokens` (sayı), `interventions` (sayı),
`false_positive` (bool), ve YALNIZ B kolunda `estimated_saved` (sayı). Eşik:
her iki kolda **en az 2 ayrı görev** (`accept.sh:408`). Yani "birer instance"
yetmez — 5b iki kolda da ≥2 görev istiyor.

**SONUÇ — dört bloker, dördü de ölçüldü, hiçbiri ağ dalgalanması değil.**

1. `pip install swesmith==0.0.6` çöküyor: `sglang` → `flashinfer_python` →
   `apache-tvm-ffi==0.1.0b15`, PyPI'de o sürüm YOK (0.1.0…0.1.13.post3 var).
2. Taban imaj yalnız amd64: `jyangballin/swesmith.x86_64:latest` →
   `arches:['amd64']`; `swesmith.arm64` ve `.arm64.v8` → **404**. Makine arm64,
   ve `profiles/base.py:64-65` arm64'te `linux/arm64/v8` seçiyor — yayınlanmamış
   platform.
3. `docker info` → daemon ayakta değil.
4. **En büyüğü, ve kurulumla ilgisi yok:** `harness/eval.py:2` — *"Given
   predictions by SWE-agent, evaluate its performance"*. swesmith AJAN
   KOŞTURMAZ, hazır yamayı puanlar. A/B kolları ayrı bir ajan (SWE-agent) +
   ücretli LLM anahtarı ister; ortamda anahtar yok ve para harcamak operatör
   kararıdır.

**ELENEN HİPOTEZ.**
- **"HARNESS.md'nin sabitlediği swesmith v0.0.6 iki kollu koşuyu tek başına
  üretir" — ELENDİ.** Paket bir *değerlendirici*; üreten taraf (ajan) HARNESS.md'de
  hiç seçilmemiş. Tur 4'ün seçimi eksik: repo+commit sabitlendi, ajan sabitlenmedi.
  HARNESS.md bu turda DÜZELTİLMEDİ (belge kendi başına düzeltilmez, §"If
  PROJECT.md itself is wrong"); eksiklik burada kayıtlı.
- **"Bloker CHALLENGE-3'tü" (tur 10'un iddiası) — tur 11 elemişti, bu tur
  bağımsız doğruladı:** koşu denendiğinde duvara çarpılan yer bağımlılık/ajan/
  mimari, soket yolu değil.

**YAPILMAYAN, BİLEREK.** Sahte JSONL yazılmadı; `bench/reproduce.sh`'e R7 cümlesi
(5c) eklenmedi; 4d hazırlık kaydı yazılmadı. Üçü de var olmayan bir koşuyu
yeşile çevirirdi — accept.sh başlığındaki "NO ASSERTION MAY PASS VACUOUSLY" ve
CLAUDE.md non-negotiable 3. On kırmızı kırmızı kaldı.

**KABUL BETİĞİ (mühürlü, değiştirilmedi).**
```
$ ./reports/R7/accept.sh
== R7 acceptance: 14 green, 12 red
R7 NOT ACCEPTED
```
Tur 10 ve 11 ile aynı sayı: **14 yeşil / 12 kırmızı** (ham çıktı
`reports/R7/accept.out`). `make test` rc=0 (son suite: identity 37/0) — zemin
bozulmadı. 2b bugün 1240.8 µs (dizi: 1704.4 → 1583.2 → 2063.1 → 3150.1 →
1235.3 → 1240.8), tavan 1000 µs, KIRMIZI.

**OPERATÖRE GİDEN KARAR (yapan veremez).** İki kollu koşu üç onay istiyor:
(i) hangi ajan (SWE-agent mı, başkası mı) — HARNESS.md'ye eklenmeli;
(ii) LLM anahtarı + bütçe (A ve B iki tam ajan oturumu, ≥2 görev × 2 kol);
(iii) amd64 zemin — emülasyonlu Docker mı, uzak x86_64 Linux mu. (iii) R7'nin
"temiz container" şartıyla zaten örtüşüyor.

**NOT VERIFIED.**
- swesmith `--no-deps` ile kurulup İÇİ okundu; hiçbir swesmith komutu
  KOŞULMADI. `eval.py`'ın gerçek davranışı okunarak biliniyor, çalıştırılarak
  değil.
- Docker daemon başlatılmadı; amd64 emülasyonun bu makinede çalışıp çalışmadığı
  ÖLÇÜLMEDİ (imaj 404'ü emülasyondan bağımsız, ama emülasyon yolu denenmedi).
- SWE-agent'ın kendi sürümü/bağımlılıkları hiç incelenmedi.
- `sglang`'ı atlayıp elle bağımlılık seçmenin swesmith'i çalışır kılıp
  kılmadığı denenmedi — eksik bağımlılıkla alınan sayı ölçüm sayılmaz.
- Hiçbir şey temiz container'da koşulmadı; hepsi bu macOS arm64 makinesinde.

## deneme 13 — 2026-08-24 (operatörün dördüncü yolu, ilk emir: ÖLÇ)

**DENENEN.** Operatörün tur 12 CEVAP'ı üç seçeneği de reddedip dördüncü yolu
verdi (ajan = `claude -p`) ve bu turun ilk işini emretti: "aday instance
listesinden en az 8'ini deneyip kaçının temiz kurulduğunu ÖLÇ; 4'ten azı
kuruluyorsa DUR." Docker'sız, `swesmith` paketi kurulmadan, yerel venv + pytest
ile 10 saf-Python instance tarandı (`/tmp/rbscan/tara*.sh`, ham TSV+log orada).

**SONUÇ — 10 denendi, 7 TAM TEMİZ.** Temiz = kurulum OK + F2P bozuk kodda düştü
+ P2P bozuk kodda geçti. Eşik 4; **durma şartı doğmadı.** Tablo ve komutlar
`reports/R7/INSTANCE-TARAMA.md`. Temiz-olmayan üçünün sebebi tek tek ölçüldü:
pydantic = `pydantic-core` Rust wheel derlenmedi (gerçek duvar, 10'da 1);
python-docx = `pyparsing` sürüm çakışması (duvar değil); jinja = bozuk dalda
F2P GEÇTİ, yani bug üremiyor (o instance koşuya alınamaz).

**ELENEN HİPOTEZ — tur 12'nin dört blokerinden üçü görev kümesinin blokeri
DEĞİLMİŞ.** `sglang→flashinfer→apache-tvm-ffi` zinciri, amd64-only imaj ve
Docker daemon; üçü de `swesmith` PAKETİNİN ve İMAJLARININ blokeri. Görev kümesi
onlardan bağımsız erişilebilir: her instance ayna repoda bir **git dalı**
(`git ls-remote --heads .../pallets__jinja.ada0a9a6 | wc -l` → 958). Klonla,
venv kur, pytest koş. TESHIS-HARNESS'in "HER MAKİNEDE AYNI" dediği duvar
gerçek, ama yolun üstünde değilmiş.

**YENİ OLGU — held-out testler YAPISAL, biz üretmiyoruz.** instance dalında F2P
test dosyaları SİLİNMİŞ; `main` dalında düzeltilmiş kod + bütün testler var
(oauthlib: dal 235 dosya / main 247; `tests/oauth2/rfc6749/clients/` dalda
yalnız `__init__.py`). 10/10 repoda aynı. İki sonucu: (a) accept.sh 6a'nın
"ajanın kendi testi sayılmaz" şartı mimari olarak karşılanıyor; (b) `origin/main`
hem cevabı hem saklı testleri taşıdığı için ajanın checkout'unda `.git`
SİLİNMEK ZORUNDA — 4d hazırlığı formalite değil, geçerlilik şartı.

**KENDİ ÖLÇÜM HATAM, İKİ KEZ — kayda geçti (Yasa 8).** Geçiş 1 yalnız
`pip install -e .` yaptı; conftest importları çöktü (`trio`/`responses`/
`pyparsing`) ve betiğim çıkış kodu≠0'ı "F2P beklendiği gibi düştü" saydı.
Geçiş 2 ekstraları kurdu, bu sefer F2P dosyalarının dalda hiç olmadığı çıktı.
**Geçiş 1 ve 2'nin F2P sonuçları GEÇERSİZDİR ve yayınlanamaz;** tablodaki tek
geçerli geçiş 3'tür (F2P `origin/main`'den geri konuyor). İlk geçişin
"4 tam temiz"i uydurma bir sayıydı, silinmedi — INSTANCE-TARAMA.md §4'te duruyor.

**ÖLÇÜLEN DİĞERLERİ (tur 12'nin SIRAYA listesi, 4/4 kapandı).**
(1) `claude -p --output-format stream-json` çalıştırıldı; `result` olayının
`usage` bloğu: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`,
`cache_read_input_tokens`, + `total_cost_usd`. `tokens` tanımı ON-KAYIT §4'te
donduruldu. (2) Ayna repolar 10/10 public, `git ls-remote` auth'suz çözdü.
(3) HF datasetinde F2P/P2P MEVCUT, örnek satırla gösterildi (59 136 satır).
(4) `interventions` tanımı koşudan ÖNCE donduruldu, sonradan değil.

**HOOK BAĞLANABİLİR — ölçüldü.** `hooks/gate.mjs`'e sahte PreToolUse olayı
verildi: rc=0 ve `$HOME/.rabadon/spool/2026-08-24.jsonl` + `.head` YAZILDI.
B1.5'in "bağlama kabulü" (ledger'da yeni satır göster) bu koşuda karşılanabilir.
gate.mjs bir Node betiği — B kolu için derleme gerekmiyor.

**ÜRETİLEN.** `reports/R7/INSTANCE-TARAMA.md` (ölçüm kaydı),
`reports/R7/ON-KAYIT.md` (Yasa 7 ön-kaydı: hipotez, çürüten sonuç, N=6 donmuş
görev listesi, alan tanımları, sızıntı önleme). KOSU-RABADON-2.md'ye B1.9
eklendi — operatörün emrettiği yetim-yük-süreci kuralı.

**YAPILMAYAN, BİLEREK.** Hiçbir ajan koşusu yapılmadı, JSONL yazılmadı,
`bench/reproduce.sh`'e R7 cümlesi eklenmedi, HARNESS.md'ye 4d kaydı YAZILMADI.
Dördü de var olmayan bir koşuyu yeşile çevirirdi. GOAL 5/6/7 ve 4d KIRMIZI.

**KALAN HİPOTEZLER (koşu turuna).**
- Altı instance'ın her biri koşu anında da temiz mi (tur başına bir kez ölçüldü,
  koşudan önce tekrar doğrulanacak — ON-KAYIT'ta şart).
- `estimated_saved` alanını rabadon fiilen üretiyor mu; üretmiyorsa 6e/7b
  yapısal olarak kapanamaz. HİÇ BAKILMADI.
- B kolunda hook'un görev checkout'una bağlanması (ayrı proje dizini) ledger'a
  satır düşürüyor mu — burada `$HOME` ile ölçüldü, worktree senaryosunda değil.
- python-docx sabitlenmiş `pyparsing` ile temizlenir mi (denenmedi).

**2b LATANSI BU TURDA ÖLÇÜLMEDİ — ölçülemezdi.** Makine yük altındaydı
(uptime 8.60/6.01/5.24), kaynağı bu tarama değil (AppleSpell, WindowServer,
başka oturumlar). Yük altında alınan latans sayısı geçersiz olurdu; tur 9'un
kirlenmiş ölçümünün tekrarı olurdu. Yetim `while :` süreci ARANDI, YOKTU.
2b KIRMIZI kalıyor, duran emir (PROFIL-YARGILAMA.md) geçerli.

---

## deneme 14 — 2026-08-24 (tur 14, yapan) — `estimated_saved` YOK: 6e/7b bir BİRİM ÇELİŞKİSİ üzerine kurulu

**DENENEN.** Tur 13'ün tek NEXT'i: "`estimated_saved` alanını rabadon fiilen
üretiyor mu?" Kaynak taraması + kapının kendisi çalıştırılarak ölçüldü.

**SONUÇ — üretmiyor, ve mesele eksik alan değil, BİRİM.**

1. `estimated_saved` adlı alan kaynak ağacının HİÇBİR yerinde yok.
   `grep -rn estimated_saved native hooks bin index.mjs repair npm` → 0 satır.
   Ad yalnız `reports/` altında geçiyor (accept.sh, ON-KAYIT, teşhis dosyaları).
2. rabadon'un ürettiği tek tasarruf sayısı `saved_usd` — **USD cinsinden double**
   (`native/counter.h:77`), formülü `median(uncut) * chains_cut * avg_call_usd`
   (`counter.h:19`). Yüzeye `json_object` ile çıkıyor (`counter.h:259`).
3. ÇALIŞTIRILDI, varsayılmadı:
   `RABADON_DIR=$PWD/.rabadon ./native/rabadon-stats --days 30 --json`
   → `"counter":{...,"saved_usd":null,"reason":"no-close","estimated":false,...}`
   Çıktıda token cinsinden HİÇBİR tasarruf alanı yok.
4. accept.sh 6e (satır 456-487) `estimated_saved` toplamını
   `tok_A - tok_B` ile karşılaştırıyor — yani **TOKEN farkıyla**.
   ON-KAYIT.md:113 alanı `int`, :140-141 "rabadon'un ledger'a yazdığı tasarruf
   tahmini... 6e bunu iki kolun GERÇEK token farkıyla karşılaştırır" diyor.

**ELENEN HİPOTEZ.** "6e/7b sadece koşu yapılmadığı için kırmızı" — YANLIŞ.
Koşu kusursuz tamamlansa bile 6e kapanamaz: karşılaştırılan iki büyüklüğün
BİRİMİ farklı. Dolar ile token karşılaştırılıyor. Bu bir ölçüm başarısızlığı
değil, bir kategori hatası.

**NEDEN SESSİZ GEÇİLEMEZ.** 7b'nin tetiklenmesinin ürün sonucu var: sapma >%50
ise "dolar cümlesi README'den ve landing'den aynı gün kalkar". Dolar (ör. 6.80)
ile token farkı (ör. 45 000) karşılaştırılırsa sapma HER ZAMAN ~%100 çıkar ve
7b **birim hatası yüzünden** tetiklenir — gerçek bir ölçüm bulgusu yüzünden
değil. Ürün seviyesinde bir geri çekilmeyi bir birim bug'ı ateşleyemez.

**ZARARSIZ OLAN NE.** Bugünkü halinde 7b "UNCHECKABLE" diye düşüyor (sapma
hesaplanamıyor), TETİKLENMİŞ diye değil. Yani `estimated_saved`'sız koşmak
ürüne zarar VERMEZ; 6e/7b bugünküyle aynı dürüst kırmızıda kalır.

**KALAN HİPOTEZLER (6e/7b için, operatör kararı gerektirir).**
- (a) Harness-içi birim çevrimi: COUNTER olayı `tok_in/tok_cw/tok_cr/tok_out`,
  `session_usd`, `calls`, `avg_call_usd` alanlarını YAZIYOR
  (`counter.h:310-320`) — `saved_usd` token'a çevrilebilir. Dondurulmuş
  ON-KAYIT'ı değiştirmez ama "rabadon'un YAZDIĞI sayı" tanımını gerer.
- (b) 6e'yi dolar-dolar yapmak: `total_cost_usd` iki kolda da result olayında
  var (tur 13 ölçtü). Daha doğru karşılaştırma ama accept.sh (mühür kümesi)
  + dondurulmuş ON-KAYIT değişikliği ister → insan onayı.
- (c) 6e/7b'yi bu turda kırmızı bırakmak ve koşuyu yine de yapmak.

**KOŞUYU BLOKLAMIYOR.** GOAL 5, 6a-6d ve 7a `estimated_saved`'a hiç bakmıyor;
10 JSONL kırmızısının 8'i bu alan olmadan kapanabilir. Bu yüzden tur 13'ün
"üretmiyorsa operatöre git" emri, koşuyu DURDURMAK olarak değil, koşuya
PARALEL bir soru olarak uygulandı.

---

## deneme 15 — 2026-08-24 (tur 14, yapan) — koşu KURULDU ve KOŞTU; 6e/7b'nin üçüncü, ölümcül sebebi ÖLÇÜLDÜ

**DENENEN.** İki kollu koşu fiilen kuruldu (`reports/R7/ab_run.sh`) ve
çalıştırıldı. Ajan `claude -p`, Docker yok, yerel venv + pytest, ajanın
ağacında `.git` YOK.

**SONUÇ 1 — koşu çalışıyor, ilk çift ölçüldü (autograd).**

| kol | heldout_pass | tokens | F2P | P2P | süre | ledger satırı |
|---|---|---|---|---|---|---|
| A | true | 10 660 | 11/11 | 120/120 | 103 s | — (kapı yok) |
| B | true | 15 099 | 11/11 | 120/120 | 147 s | 31 |

B kolunun hook'u GERÇEKTEN bağlandı: ledger'da bu koşuya özgü `pipe`
etiketiyle 31 satır, içinde `SIGNAL`, `INJECT`, `COUNTER`. B1.5'in
"bağlama kabulü" varsayımla değil satır gösterilerek karşılandı.

**SONUÇ 2 — bu görevde hipotez DESTEKLENMEDİ.** İki kol da düzeltti (fix
oranı eşit), B kolu **%42 DAHA FAZLA** token harcadı. 7a'nın literal şartı
"B ya fix oranını ya net token'ı iyileştirmeli" — bu görevde ikisi de yok.
N=1; sonuç değil, ilk veri noktası. Ama yönü olduğu gibi yazılıyor (Yasa 8).

**SONUÇ 3 — DENEME 14'ÜN (a) SEÇENEĞİ ÖLDÜ.** Deneme 14'te "saved_usd
token'a çevrilebilir, çünkü COUNTER olayı tok_in/tok_cw/tok_cr/tok_out ve
session_usd yazıyor" demiştim. B kolunun GERÇEK COUNTER olayı bunu ÇÜRÜTTÜ:

    "chains_cut":1, "fixed":1, "injections":1,
    "saved_usd":null, "reason":"no-price",
    "calls":0, "session_usd":0,
    "tok_in":0, "tok_cw":0, "tok_cr":0, "tok_out":0,
    "median_n":0, "median_uncut":null

Alanlar VAR ama hepsi SIFIR. rabadon bu headless koşuda ajanın
transcript'ini okuyamıyor, dolayısıyla ne fiyat (`no-price`) ne token
tabanı var. Yani `estimated_saved` üç ayrı sebeple üretilemez:
1. birim: rabadon dolar üretir, 6e token farkı bekler (deneme 14);
2. fiyat: `reason:"no-price"` — avg_call_usd çözülemiyor (calls=0);
3. geçmiş: `median_n:0`, MIN_HISTORY=3 karşılanmıyor.
Çevrim yoluyla kurtarma YOK. Kendi önerdiğim (a) seçeneğini kendi ölçümüm
eledi; kayıtta kalsın.

**ELENEN HİPOTEZ.** "6e/7b harness tarafında bir birim çevrimiyle kapatılabilir."
YANLIŞ — çevrilecek sayı da yok.

**KENDİ HATAM — iki kez, kayıtta.**
1. Ön-doğrulamada F2P'yi bozuk ağaçta koştum. F2P test dosyaları o dalda
   SİLİNMİŞ (held-out yapısal), pytest "file or directory not found" deyip
   0 kosuyordu ve autograd/oauthlib/conan "F2P düştü" sanılıp ELENİYORDU.
   Üçü de aslında sağlamdı. Düzeltme: F2P dosyaları `origin/main`'den geri
   konduktan SONRA koşuluyor.
2. Çıplak `pytest` kurdum. Depoların `required_plugins` ilanı yüzünden
   pytest "Missing required plugins: pytest-cov, pytest-xdist" deyip hiç
   koşmadan çıkıyordu — yine sahte bir "0 passed". Düzeltme: eklentiler
   kuruluyor ve `-o addopts=''` ile deponun kendi bayrakları etkisizleniyor.
   Her iki hatada da JSONL'e TEK SATIR yazılmadı; kapı yanlış veriyi
   içeri almadı. `ab_prever.tsv`'deki hatalı satırlar sıfırlandı.

**SONUÇ 4 — B kolunun fazla token'ında bir CONFOUND var, ölçüldü.**
rabadon'un INJECT'i şu yüzden tetiklendi: ajan `.venv/bin/python` yerine
sistem `python3`'ünü çağırdı, pytest eklenti hatası verdi, ajan aynı hatayı
3 kez tekrarladı ve `root_migration` sinyali doğdu. Yani B'nin fazla
token'ının bir kısmı gerçek bir "tekrar freni" yakalaması; ama tetikleyen
şey görevin kendisi değil ortam tuhaflığı. Bu, sayının lehine değil
aleyhine yazılıyor: N büyümeden bu farka anlam yüklenemez.

**KALAN HİPOTEZLER.**
- Kalan görevlerde (oauthlib, conan, pydicom, astroid, feedparser) yön aynı
  mı — koşu devam ediyor, satırlar ham kayda ekleniyor.
- `estimated_saved` için tek yol operatör kararı (deneme 14, (b)/(c)).

---

## deneme 16 — 2026-08-24 (tur 14, yapan) — B kolu SUSTURULMUŞTU; ayrıca B1.5 reçetesi SAĞIR (CHALLENGE)

**DENENEN.** İlk iki B satırı yazıldıktan sonra tek soru soruldu: rabadon'un
enjeksiyonu ajana FİİLEN ULAŞTI MI? Varsayılmadı, transcript'te arandı.

**SONUÇ 1 — ULAŞMAMIŞ. İlk iki B satırı GEÇERSİZ.**
`grep -c "rabadon: attempt" <B stream>` → **0**, ledger'da `INJECT` olayı
VARKEN. Sebep bendeydi: hook sarmalayıcısını
`sh -c 'timeout 2 node <gate> </dev/null >/dev/null 2>&1; exit 0'`
diye yazdım. Claude Code hook'u ajanla **STDOUT** üzerinden konuşur;
`>/dev/null` onu susturdu. Yani B kolu "ledger yazan ama ajana hiç
konuşmayan" bir rabadon'u ölçtü — müdahale değil, BOŞ müdahale.
7a'nın anlamı bu satırlarla test EDİLEMEZ.

O iki satır SİLİNMEDİ, `reports/R7/ab_run_INVALID_muted_hook.jsonl`'e
`_invalid_reason` etiketiyle taşındı. Ham kayıtta yalnız A satırları kaldı,
B kolu yeniden koşuluyor.

Bu arada ölçülen ikinci şey: aynı görevde A 10 660 / B 15 099 token, ama
oauthlib'de A 9 868 / B 8 962 — yani yön DEĞİŞİYOR. Susturulmuş bir kolda
zaten anlam yoktu; iki nokta arasındaki bu salınım N=1-2'de token farkına
anlam yüklemenin neden yanlış olduğunu ayrıca gösteriyor.

**SONUÇ 2 — CHALLENGE: B1.5'in yazılı reçetesi kapıyı SAĞIR yapıyor.**
KOSU-RABADON-2.md:138 sarmalayıcıyı literal olarak şöyle veriyor:

    sh -c 'timeout 2 <gate> ... </dev/null; exit 0'

`</dev/null` kapının **STDIN**'ini keser. Claude Code hook olay JSON'unu
STDIN'e yazar; kesilince kapı hiçbir olay görmez. ÖLÇÜLDÜ (aynı olay, aynı
kapı, tek fark redirect):

    ... node gate </dev/null   -> ledger'a yeni satır: 0
    ... node gate              -> ledger'a yeni satır: 1

Yani **B1.5'in kendi "BAĞLAMA KABULÜ" şartı (ledger'da yeni satır göster)
kendi reçetesiyle karşılanamaz** — belge kendi içinde çelişiyor. Asılma
korkusunu `timeout 2` zaten karşılıyor, stdin'i kesmeye gerek yok.

**ÖNERİLEN DİFF (insan onayı ister, sessizce uygulanmadı).**
KOSU-RABADON-2.md:138'de `</dev/null` KALDIRILSIN:

    sh -c 'timeout 2 <gate> 2>/dev/null; exit 0'

Bu turda koşu bu düzeltilmiş haliyle koşuldu ve gerekçe `ab_run.sh`
`bagla_hook` fonksiyonunun içine yorum olarak yazıldı. Reçetenin kendisi
DEĞİŞTİRİLMEDİ — belge değişikliği insanın.

**ELENEN HİPOTEZ.** "Hook ledger'a satır yazıyorsa B kolu geçerlidir."
YANLIŞ. Ledger satırı kapının DUYDUĞUNU kanıtlar, KONUŞTUĞUNU değil.
Bağlama kabulü bu yüzden yetersiz bir ölçüt: yanına "enjeksiyon ajanın
transcript'inde görünüyor" şartı gerekir.

**KALAN HİPOTEZLER.**
- Kapı artık konuşurken B kolu A'dan farklı mı — koşu sürüyor.
- `estimated_saved` hâlâ üretilemiyor (deneme 14 ve 15); operatör kararı.

---

## deneme 17 — 2026-08-24 (tur 14, yapan) — KONTROL KOLU HİÇ TEMİZ DEĞİLDİ: global settings sızıntısı

**DENENEN.** Deneme 16'da B kolunun sustuğu bulunup düzeltildikten sonra, aynı
soru simetrik olarak A koluna soruldu: **A kolunda rabadon gerçekten YOK MU?**
Varsayılmadı; A transcript'i ve ledger tarandı.

**SONUÇ — YOK DEĞİLDİ. TÜM SATIRLAR (A ve B) GEÇERSİZ.**

Operatörün **global `~/.claude/settings.json`** dosyası
`/Users/damummyphus/damla_projects_2026/rabadon/native/rabadon-gate`'i
`PreToolUse`, `PostToolUse`, `SessionStart`, `Stop`, `UserPromptSubmit`
olaylarının HEPSİNE bağlıyor — bu makinedeki HER claude oturumu için.
Görev checkout'unda koşan `claude -p` de bir claude oturumudur.

İki bağımsız kanıt:
1. A kolu transcript'inde rabadon'un kendi cümlesi:
   `rabadon: here is what I will do in this project. check: python3 -m pytest -q`
   — üstelik görev deposunun test komutuyla, yani kapı O checkout'ta koşuyor.
2. Ledger'da A koluna ait satırlar: autograd `__A` → **36**, oauthlib `__A` → **40**.

ON-KAYIT §3 şunu şart koşuyor: "**A kolu:** `settings.local.json` yok, hook
hiç bağlanmaz. **rabadon yoktur.**" Bu şart HİÇBİR ZAMAN sağlanmadı. Yani
ölçülen şey "rabadon'suz ajan vs rabadon'lu ajan" değil, "rabadon'lu ajan vs
rabadon'lu ajan + ikinci bir rabadon hook'u" idi. İki kollu koşunun kontrastı
YOKTU; fix oranı ve token sayıları gerçek sayılardır ama ön-kayıttaki
hipotezi TEST ETMEZLER.

Satırlar silinmedi: `reports/R7/ab_run_INVALID_global_hook.jsonl`,
`_invalid_reason` alanıyla.

**ELENEN HİPOTEZ.** "Görev checkout'unda `settings.local.json` yazmamak, o
koşuyu rabadon'suz yapar." YANLIŞ — kullanıcı düzeyi (global) ayarlar her
oturuma iner, proje dizini ne olursa olsun.

**ÇÖZÜM ÖLÇÜLDÜ, VARSAYILMADI.** `claude --setting-sources <user,project,local>`
hangi ayar kaynaklarının yükleneceğini seçiyor. Üç ölçüm, hepsi çalıştırıldı:

| kurulum | yeni ledger satırı |
|---|---|
| `--setting-sources project`, boş dizin | **0** |
| `--setting-sources local`, `settings.local.json` YOK | **0** |
| `--setting-sources local`, hook'lu `settings.local.json` VAR | **1** |

Seçilen tasarım: **her iki kol da `--setting-sources local`**. A kolunda
dosya yoktur, B kolunda vardır. Böylece iki kol arasındaki tek fark
ON-KAYIT §3'ün istediği şeydir — hook'un bağlı olup olmaması. Abonelik
auth'u bu bayrakla bozulmadı (üç testte de ajan normal koştu).

**YENİ ŞART — KONTROL KOLU SAFLIĞI (B'nin bağlama kabulünün aynası).**
B kolu için "ledger'da yeni satır GÖSTER" şartı vardı; A kolu için karşılığı
YOKTU ve boşluk tam buradan sızdı. `ab_run.sh`'a eklendi: A koşusundan sonra
o koşuya ait ledger satırı **sıfır değilse** satır JSONL'e YAZILMAZ,
`gecersiz.tsv`'ye düşer. Yasa 7 ruhu: kontrol kolunun temizliği de
varsayılmaz, KANITLANIR.

**KALAN HİPOTEZLER.**
- İzole edilmiş iki kolda fark var mı — koşu 3. kez, düzeltilmiş haliyle koşuyor.
- `estimated_saved` hâlâ üretilemiyor (deneme 14, 15); operatör kararı bekliyor.

---

## deneme 18 — 2026-08-24 (tur 14, yapan) — İZOLE KOŞU TAMAMLANDI: 23 yeşil / 3 kırmızı, ama sayı yayınlanamaz

**DENENEN.** Deneme 17'nin `--setting-sources local` tasarımıyla koşu baştan
koşuldu. Ek olarak kontrol-kolu saflık şartındaki kendi hatam düzeltildi:
şart ham TOPLAM ledger satırına bakıyordu, oysa spool birikimli — autograd ve
oauthlib'in A kolları önceki geçersiz koşulardan kalan 36/40 satır yüzünden
YANLIŞ elendi. Şart DELTA'ya çevrildi (taban her iki kol için de alınıyor).

**SONUÇ — koşu uçtan uca çalıştı.**

    ./reports/R7/accept.sh  ->  23 yesil / 3 kirmizi   (tur 13: 14 yesil / 12 kirmizi)

| metrik | A (rabadon yok) | B (rabadon var) |
|---|---|---|
| held-out fix | 66.7 % | 66.7 % |
| token | 26 780 | 23 697 |
| interventions | 0 | 0 |
| false positive | 0 % | 0 % |

Kontrol kolu saflığı KANITLANDI: üç A koşusunun üçünde de bu koşuya ait yeni
ledger satırı **0**. B koşularında 18 / 6 / 5 satır — hook bağlı.

**ELENEN HİPOTEZ — 7a'nın yeşili kanıt DEĞİL.** accept.sh 7a "B net token'ı
iyileştiriyor" diye geçti. Bu sayı yayınlanamaz:
- düzeltme oranı AYNI; oauthlib'de iki kol da aynı şekilde düştü (15/18);
- üç görevin biri ters yönde (+4.4 %);
- toplam fark tek görevden geliyor (pydicom −24.5 %);
- hücre başına tek ölçüm, varyans tahmini yok. Buna karşılık aynı görev+kol
  koşular arası %16–52 oynadı — koşu-içi salınım, kollar arası %11.5'lik
  farktan BÜYÜK.
KOSU-RABADON-2.md:61-62 gereği gürültü içindeki fark YAYINLANMAZ.

**SONUÇ 2 — üç instance ön-doğrulamada elendi, sebebi ölçüm genişliği.**
conan (P2P 0/3), astroid (73/120), feedparser (0/120). Tur 13 bunları "tam
temiz" saymıştı çünkü P2P örneklemi satır başına İLK 2 testti; burada 120
test koşuldu. Yani tur 13'ün "7/10 temiz"i bir ÜST sınırdı. Ders: instance
taramasında dar P2P örneklemi yanıltıcı.

**KALAN HİPOTEZLER.**
- N=6'ya çıkmak için ya elenen üç instance'ın P2P'si teşhis edilmeli ya da
  INSTANCE-TARAMA yeni adaylarla (geniş P2P örneklemiyle) tekrarlanmalı.
- Anlamlı bir token cümlesi için hücre başına tekrarlı ölçüm gerekiyor
  (aynı görev+kol en az 3 kez), yoksa varyans bilinmiyor.
- 6e/7b: `estimated_saved` hâlâ üretilemiyor — operatör kararı (deneme 14/15).

---

## deneme 19 — 2026-08-24 (tur 14, yapan) — elenen üç instance'ın sebebi HARNESS'TI; N 3'ten 4'e çıktı

**DENENEN.** Deneme 18'de üç instance ön-doğrulamayı geçemedi (conan P2P 0/3,
astroid 73/120, feedparser 0/120). "Instance bozuk" diye geçilmedi; üçünün de
pytest logu okundu.

**SONUÇ — üçünün de sebebi benim harness'imdi, instance değil.**

1. **conan / feedparser: test "extras"ları kurulmuyordu.**
   `ImportError while loading conftest ... No module named 'mock'` (conan),
   `... No module named 'responses'` (feedparser). venv'e yalnız
   `pip install -e .` + pytest eklentileri kuruluyordu; depoların test
   bağımlılıkları setuptools **extras**'ında duruyor. Düzeltme: `kur_venv`
   artık `.[test]`, `.[tests]`, `.[dev]`, `.[testing]` varyantlarını sırayla
   deniyor, ayrıca `mock responses freezegun hypothesis` son çare olarak
   kuruluyor.
2. **astroid: SKIP'ler düşme sayılıyordu.** Özet satırı gerçekte
   `2 failed, 73 passed, 45 skipped` idi. Sayacım `passed == toplam` arıyordu,
   yani 45 skip'i başarısızlık yerine koyuyordu. Düzeltme: ölçüt kümeye göre
   ayrıldı — **P2P için "DÜŞMEDİ"** (skip bozulma değil), **F2P için
   "gerçekten GEÇTİ"** (skip bir düzeltme kanıtı değil). Özet satırı hiç
   yoksa (collection/import çökmesi) sonuç 0 kalır, çünkü o durumda gerçekten
   hiçbir şey koşmamıştır.

**SONUÇ — N 3'ten 4'e çıktı.** feedparser koşuya girdi, iki kol da çözdü
(55/55 F2P, 120/120 P2P). Yeni toplam:

| metrik | A | B |
|---|---|---|
| held-out fix | 75.0 % (4) | 75.0 % (4) |
| token | 35 620 | 33 221 |

**VE SİNYAL DAHA DA ZAYIFLADI — dürüst yön budur.** feedparser B kolunda
**daha pahalı** çıktı (+7.7 %). Artık dört görevin **ikisi B lehine**
(−12.0 %, −24.5 %), **ikisi A lehine** (+4.4 %, +7.7 %). Yani toplamdaki
−6.7 %, işaretçe 2-2 bölünmüş dört ölçümün ortalaması. Düzeltme oranı hâlâ
tıpatıp aynı (75/75). accept.sh 7a yeşil kalıyor ama bu yeşil bir kanıt
değildir ve KOSU.md'de böyle yazıldı.

**ELENEN HİPOTEZ.** "Ön-doğrulamayı geçemeyen instance kötü instance'tır."
YANLIŞ — üç örnekte de kötü olan ölçüm aletiydi. Bir eleme ölçütü, eleme
sebebini LOGDAN okumadan uygulanırsa sessizce örneklemi daraltır ve N'i
düşürür; bu turda tam olarak öyle oldu.

**KALAN.** conan (conftest `test/functional` ağır bağımlılık ister) ve
astroid (2 P2P testi bozuk dalda zaten düşüyor) hâlâ dışarıda, ama sebepleri
artık teşhis edilmiş. N=6 istenirse: astroid için "bozuk dalda zaten düşen
P2P testleri taban kümeden çıkarılır" kuralı gerekir — bu, ON-KAYIT'ın
dondurduğu puanlama semantiğine dokunur, dolayısıyla insan onayı ister.

---

## deneme 20 — 2026-08-24 (tur 15, yapan) — SAYAÇ CANLIDA KÖRDÜ: predikat bir satırdaki İLK "type"ı okuyordu

**DENENEN.** 14.operator.md CEVAP 2'nin bildirdiği P0 bug'ı önce DOĞRULAMAK,
sonra test-önce düzeltmek: `native/usage.h`'in `is_assistant_usage_line`
predikatı satırdaki ilk `"type"` anahtarını alıp `"assistant"` bekliyor.

**SONUÇ.** Doğrulandı, ve iddia edilenden ağır. Gerçek transcript'in üst seviye
anahtar sırası ölçüldü (`~/.claude/projects/.../*.jsonl`):
`parentUuid, isSidechain, message, requestId, type, uuid, ...` — `message`
ÖNCE geldiği için ilk `"type"` her zaman message'ın kendi `"type":"message"`'i.
Predikat hiçbir gerçek satırı eşleştirmiyor. Gerçek 425 satırlık bir
transcript'te **stok json ayrıştırıcı 414 çağrı / 131 098 in / 758 852 out /
1 754 223 cache-write / 136 816 678 cache-read** sayarken rabadon
**1 çağrı / 0 token** okudu.

**ELENEN HİPOTEZ.** "Fixture'lar gerçeği temsil ediyor." Etmiyorlardı: depodaki
BÜTÜN usage fixture'ları (`session_test.sh`, `budget_test.sh`, `export_test.sh`,
`lens_test.sh`) `{"type":"assistant","message":{...}}` diye üst seviye type'ı
ÖNCE yazıyordu. O şekil `--output-format=stream-json`'ın BASTIĞI şekildir,
diske YAZILAN şekil değil. Suite yeşilken ürün canlıda ölüydü; maske
fixture'lardı.

**ELENEN HİPOTEZ 2.** "Düzeltme = satırda `"type":"assistant"` ara." Hayır:
bu deponun kendi oturum logları fixture şekilli satırları ajan METNİNİN İÇİNDE
alıntılıyor (bu dosya dahil). O arama hiç yapılmamış faturalı çağrılar icat
eder. Düzeltme bir DERİNLİK okuması olmak zorundaydı: `value_at_depth()` satırı
bir kez, string-farkında (JSON string'i içindeki süslü parantez iç içelik
değildir, `\"` string'i bitirmez) tarayıp anahtarı yalnız verilen derinlikte
eşleştiriyor. `type`/`toolUseResult` derinlik 1, `usage` derinlik 2.

**KALAN HİPOTEZLER.** Sayaç hâlâ kapanmıyor, ama artık sebep BU DEĞİL. İki
bariyer açık ve ikisi de ölçüldü: (a) B kolunun settings'i yalnız `PreToolUse`
kaydediyor, COUNTER ise yalnız `SessionEnd`/`Stop`'ta üretiliyor — geçerli
koşunun B ledger'ında yalnız STEP_START var, COUNTER/RUN_DONE YOK; (b)
`counter.h:71 MIN_HISTORY=3`, her görev tek oturum, `median_n:0`.

**KANIT KOMUTLARI.**

    ./native/usage_order_test.sh   # düzeltmeden ÖNCE 4 kırmızı, SONRA 9/0 yeşil
    make test                      # rc=0, 3438 ok, 0 fail

Maskenin kalktığının kanıtı: sayaç eski predikata döndürülüp yeniden derlendi →
session 13/2, budget 8/3, export 24/2, lens 12/9 KIRMIZI. Düzeltmeyle dördü de
yeşil (15/0, 11/0, 26/0, 14/0).

---

## deneme 21 — 2026-08-24 (tur 15, yapan) — ELENEN DÖRDÜNCÜ INSTANCE DA HARNESS'TI: `@argfile`

**DENENEN.** ON-KAYIT §7'nin (insan onaylı) P2P dışlama kuralını yedi maddesiyle
uygulamak, ve operatörün "conan = ortam çöküşü" gerekçesini doğrulamak.

**SONUÇ.** Gerekçe çürüdü. conan'ın ön-doğrulama log'unun TAMAMI iki satır:
`ERROR: file or directory not found: @.nodeids` / `no tests ran in 0.39s`.
`kos_pytest` node id'leri pytest'e `@dosya` ile veriyordu; `@` argfile pytest'in
argparse `fromfile_prefix_chars`'ına bağlı ve eski sürümlerde YOK — o sürüm
`@.nodeids`'i bir dosya yolu sanıyor. Argüman olarak geçmeye çevrildi;
conan yeniden ölçüldüğünde **P2P 3/3 GEÇTİ**.

**ELENEN HİPOTEZ.** "conan'ın conftest'i çöküyor / ortamı bozuk." Hayır.
Tur 14'te üç instance harness hatasıyla elenmişti; bu **dördüncüsü**. Deseni
adlandırmak gerekiyor: **N'in düşük kalmasının bugüne kadarki sebebi
instance'ların kalitesi değil, harness'ın kendi kusurlarıydı** — üç ayrı tur
boyunca her seferinde "instance bozuk" diye okundu.

**KALAN HİPOTEZLER.** Altı instance'ın altısı da artık ön-doğrulamayı geçiyor
(N=6 mümkün). astroid'in dışlanan iki testi, iki ayrı ön-doğrulama koşusunun
KESİŞİMİ olarak çıktı — üçüncü aday yok, flake yok, yani deterministikler
(madde 7 ölçüldü, varsayılmadı). conan'ın koşuya alınıp alınmayacağı
OPERATÖR kararı: ON-KAYIT §2'nin ayrı gerekçesi (P2P yalnız 3 test) duruyor.

**KIRILGANLIK KAYDI.** `P2P_CAP=120` ilk 120 id'yi alıyor; astroid'in düşen iki
testi 1584'lük listenin 62. ve 97. sırasında. Yani dilimin içine SIRA ŞANSIYLA
düştüler — cap 50 olsaydı astroid "temiz" görünürdü. Ölçüm cap seçimine duyarlı.

**KANIT KOMUTLARI.**

    PREVER_ONLY=1 bash reports/R7/ab_run.sh   # hiçbir ajan koşmaz, para harcanmaz
    column -t -s$'\t' reports/R7/ab_prever.tsv
    cat reports/R7/p2p_excluded/*.txt

## deneme 22 — 2026-08-24 (tur 16, yapan) — B KOLU YANLIŞ İKİLİYİ BAĞLIYOR: ölçülen rabadon, LEGACY JS kapısı

**DENENEN.** PARKED'in "B kolu ajana hiç konuşmuyor olabilir, ÖLÇÜLMEDİ"
maddesini teşhis etmek. Hiçbir ajan koşulmadı, para harcanmadı.

**SONUÇ — şüphe doğru, ve iki bağımsız sebebi var.** Tam kanıt:
`reports/R7/TESHIS-B-KOLU.md`.

1. **Yanlış ikili.** `ab_run.sh:25` `hooks/gate.mjs`'yi bağlıyor. Birikim motoru
   orada YOK: SIGNAL (gate.cpp:3166,3196), `queue_injection`, INJECT (4724) ve
   ajanla konuşan satır `additionalContext` (4707) — dördü de **yalnız
   `native/gate.cpp`'de**. `gate.mjs`'de `additionalContext` **0 eşleşme**.
   Dahası `hooks/install.mjs:111` `gate.mjs`'yi kendi yorumunda
   *"legacy JS gate path — still recognized (and replaced)"* diye tanımlıyor:
   gerçek kurulum onu bulduğunda SİLİP native ile değiştiriyor.
2. **Yanlış olay kümesi.** `bagla_hook` yalnız `PreToolUse` yazıyor. Native
   bağlansaydı bile zincir kopuktu: PostToolUse → SIGNAL → queue_injection →
   (sonraki) PreToolUse → INJECT. İlk halka kayıtlı değil. COUNTER `SessionEnd`/
   `Stop`'ta (4001,4015), RUN_DONE `Stop`'ta (4093). Gerçek `rabadon init` beş
   olay bağlıyor (install.mjs:169-175); B kolu **birini, yanlış ikiliyle** bağladı.

**ÖLÇÜM.** Spool'daki A/B pipe satırları yazana göre ayrıldı (`run:"ng-…"` +
`sess`/`call` = native; `run:"mt7b…"` = node). **`gate.mjs` 51 satır yazdı,
51'i de STEP_START** — sıfır SIGNAL/INJECT/COUNTER/RUN_DONE/STEP_OK.
Veri kümesindeki tek SIGNAL+INJECT, autograd__B'de 14:08–14:10, `ng-` run'lı,
yani **tur 14'ün GEÇERSİZ ilan edilmiş penceresinde native gate'in** yazdığı
satırlar. Enjeksiyon hiçbir geçerli B koşusunda gerçekleşmedi.

**ELENEN HİPOTEZ — `timeout 2` kapıyı öldürüyor.** Hayır: temiz kum havuzunda
5 koşu, `real 0,14 s` (bir kez 0,34), hepsi rc=0 ve hepsi ledger'a yazdı.
**İKİNCİ ELENEN — "susturma kaldırıldı, sorun bitti" (tur 14, madde 2).**
Hayır: `gate.mjs` PreToolUse/PostToolUse/Stop/SessionEnd'in **hiçbirinde tek
bayt stdout üretmiyor** (ölçüldü). Susturma kalktı, konuşacak şey yoktu.

**NE GEÇERSİZ OLDU.** 7a bu tur YEŞİL geçti (token A 35 620 / B 33 221) ve
**o yeşil delil değildir** — enjeksiyon kolun içinde hiç olmadı. 6b/6c/6e de
okunamaz. 6d yapısal sıfır (`gate.mjs` `wouldRefuse` yazmıyor). `ab_run.sh`'in
bağlama kabulü (`ledyeni > 0`) bunu yakalayamadı: STEP_START o şartı karşılıyor,
ve kabul kapının **konuştuğunu** hiç sormuyor.

**KANIT KOMUTLARI.**

    bash reports/R7/accept.sh                       # 23 yeşil, 3 kırmızı
    cat reports/R7/TESHIS-B-KOLU.md
    grep -c additionalContext hooks/gate.mjs        # 0
    grep -n 'legacy JS gate path' hooks/install.mjs # 111

## deneme 23 — 2026-08-24 (tur 17, yapan) — BAĞLAMA DÜZELTİLDİ; 6e/7b'nin SEBEBİ BAĞLAMA DEĞİLMİŞ

**DENENEN.** Deneme 22'nin teşhisini uygulamak: `ab_run.sh`'in B kolunu
`hooks/gate.mjs`'den `native/rabadon-gate`'e çevirmek, tek olay yerine altı
olayı bağlamak, bağlama kabulünü sertleştirmek. **Hiçbir ajan koşulmadı, para
harcanmadı.** Tam kayıt: `reports/R7/TESHIS-BAGLAMA.md`.

**SONUÇ.** Bağlama düzeldi ve **ölçüldü**: altı olay elle beslenen sentetik bir
oturumda **COUNTER ateşlendi** (eski `PreToolUse`-tek bağlamada yapısal olarak
imkânsızdı; COUNTER yalnız `SessionEnd`/`Stop`'ta, `gate.cpp:4001`). Ama
**`saved_usd` = `null` döndü** — sıfır değil, gerçek değer de değil:
`chains_cut:0, median_n:0, reason:"no-chains"`, ve `counter.h:63 MIN_HISTORY=3`
üç ölçülmüş zincirden azında hiçbir rakam basmıyor.

Kabul betiği **23 yeşil / 3 kırmızı — kapanan kırmızı 0**, ve bu beklenendi:
`accept.sh` 6e/7b'yi önceki (geçersiz) koşunun JSONL'inden okur; düzenleme
sonraki koşuyu değiştirir.

**ELENEN HİPOTEZ — "6e/7b kırmızı çünkü yanlış ikili bağlıydı / COUNTER
ateşlenmiyordu."** Hayır. Kapatan şey bağlama değil; **iki ayrı duvar** var:
1. `ab_run.sh` `estimated_saved` alanını **hiç yazmıyor**
   (`grep -c estimated_saved reports/R7/ab_run.sh` → 0). Kablo yok, yani rakam
   üretilse bile JSONL'e taşınmıyor.
2. Her görev tek oturum → `chains_cut=0`, `median_n=0` < `MIN_HISTORY=3` →
   `saved_usd` her hâlükârda `null`. Kablo çekilse `null` taşınırdı.

**İKİNCİ ELENEN — 2b "geriledi".** `accept.sh` 8148,9 µs okudu ama ölçüm anında
`load average 7,51 / 7,77 / 8,84`, %99,2 Python, %24,2 WindowServer, %18,9
WebKit. Emir gereği ölçüm alınmadı; alınan da delil değil. 2b'nin kırmızısı
"kapı yavaş" değil "**ölçüm yapılmadı**" demektir.

**KALAN HİPOTEZLER / AÇIK KARAR.** Sertleştirilen kabul (SIGNAL veya INJECT
şartı) aynen uygulandı, ama taban oran ölçüldü ve ağır: gerçek dogfooding
ledger'ında **186 oturumun yalnız 8'i (%4,3)** SIGNAL/INJECT üretmiş
(INJECT: 3, %1,6; COUNTER: 52, %28,0). Şart aynen kalırsa B koşularının
çoğunluğu — **ödenmiş para** — atılır ve kalan küme "rabadon'un konuştuğu
oturumlar"a doğru **yanlı** olur, yani turun sorusunun cevabını varsayar.
Bu yüzden bağlamanın kanıtı sinyalden bağımsız iki deterministik satıra da
bağlandı (native `run:"ng-…"` imzası + COUNTER) ve `ledger_signal_inject`
JSONL'e yazılıyor. **Şartın nihai hâli OPERATÖR KARARIDIR** ve paralı koşudan
önce verilmelidir — bkz. `TESHIS-BAGLAMA.md` §4. Yapan kabul gevşetmez.

**KANIT KOMUTLARI.**

    bash -n reports/R7/ab_run.sh
    bash reports/R7/accept.sh                        # 23 yesil, 3 kirmizi (rc=1)
    grep -c estimated_saved reports/R7/ab_run.sh     # 0
    grep -n 'MIN_HISTORY' native/counter.h           # 63: = 3
    sed -n '2733,2734p' native/gate.cpp              # taninan alti olay

## PARKED

- **6e/7b'nin kablosu (ölçüldü, YAPILMADI — bu turun işi değildi).** `ab_run.sh`
  `estimated_saved` yazmıyor. Reçete: B kolu bittikten sonra o pipe etiketinin
  son `COUNTER` satırını spool'dan okuyup `saved_usd`'yi (null ise `null`
  bırakarak) JSONL'e `estimated_saved` olarak yazmak. **Tek başına 6e'yi
  kapatmaz**: sayaç `MIN_HISTORY=3` ölçülmüş zincir görmeden `null` döner ve her
  görev tek oturum. İkinci parça bir koşu-şekli kararıdır, operatöre aittir.
- ÇÖZÜLDÜ → deneme 22 (uygulandı → deneme 23). (Eski madde: "gate.cpp PreToolUse'ta INJECT/SIGNAL
  üretiyor (4697-4707) ama geçerli B örneklerinde yalnız STEP_START var;
  ölçülen B kolu ajana hiç konuşmayan bir rabadon olabilir. ÖLÇÜLMEDİ.")
  Teşhis edildi, sebebi bulundu, düzeltme **UYGULANMADI** — `ab_run.sh`'i
  native gate'e ve beş olaya çevirmek + bağlama kabulünü sertleştirmek
  ayrı bir tur işi, ve o düzeltmeden önce iki kollu koşu TEKRAR KOŞULMAMALI.
- `accept.sh` 2b/2c bu makinede güvenilir ölçülemiyor: ölçüm anında
  `load average 6,24`, Chrome GPU %522, `surface-pattern` %91,7. 2b 1385,2 µs
  → 2443,8 µs "geriledi" ama iki sayı aynı koşulda alınmadı; fark regresyon
  delili DEĞİL. Yük temizlenmeden alınacak her latans sayısı gürültü.
- Makinede `AppleSpell` 3s 39dk boyunca %111 CPU yakıyor (rabadon'un yetim
  süreci DEĞİL, `pgrep pytest|pip` = 0). Latans ölçen her tur bunu önce
  temizlemeli; bu turun ölçümleri geç/kal tipi olduğu için etkilenmedi.
