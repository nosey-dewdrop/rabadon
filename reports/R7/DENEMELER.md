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
