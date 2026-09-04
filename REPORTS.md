# REPORTS — rabadon

Ne oldu, tarih sırasıyla. **En yeni üstte. Sadece eklenir, hiçbir şey silinmez.**

- Buraya *olan biten* yazılır. *Şu an ne doğru* → `CLAUDE.md`. *Ne inşa ediyoruz* → `PROJECT.md`.
- Her oturum sonunda `/wrap` buraya tek blok ekler.
- Eski uzun raporlar `docs/raporlar/` altında (13 adet).

---

## 2026-09-05 — reports/ arşivlendi, kayıt üçlüsüne dönüldü

**Neden:** `reports/` 573 dosya / 130 md / 14 MB'a çıkmıştı ve bu, projenin kendi
kayıt kuralını (merkezi `reports/` yasak, tarihli dosya adı yasak) ihlal ediyordu.
Klasör `docs/archive/reports/` altına **taşındı, silinmedi** — 573 dosyanın hepsi
git'te olduğu için `git mv` tam geçmişi koruyor, geri alma tek `git mv` ile.

**Taşımadan önce ölçüldü (taban):** `make test` EXIT=0, 4284 `ok`, 0 gerçek
kırmızı. ("failed" içeren 3 satırın ikisi süit BAŞLIĞI, biri fixture'ın
beklenen RED çıktısı — kırmızı değil.)

**Taşınırken düzeltilen üç canlı yol** (körlemesine taşınsaydı suite kırılırdı):
- `native/failed_call_test.sh` — `RAPOR/f3e-1-posttooluse-failure-payload.json`'u
  açıp okuyor, `make test` içinde.
- `site/build.py:44` — `2026-08-01-real-defect-mine/cases.json` okuyor;
  `native/site_claims_test.sh` her cited path'in var olmasını şart koşuyor.
- `site/build.py:1865` — canlı siteye public GitHub linki basıyor.

**Arşivden REPORTS.md'ye taşınan canlı bilgi:**
- **F3k sonrası taban (2026-08-30, hakem ölçümü):** `make test` exit 0 ·
  native geniş `ok` 4096 · `PASS (N checks)` 633 · `npm test` 64/0 ·
  **toplam 4793 yeşil / 0 kırmızı** · 53 adlı süit, 0 küçülen, 0 kaybolan.
  Dar regex 4044; emekli 4034 sayacıyla fark tam 52 ve `ok`'u sütun 0'dan
  basan iki süide ait — **kayıp iddia yok**.
- **`2b` hükmü (F3k, şık B):** ölçüt DEĞİŞMEZ, `2b` kalıcı §1 hedef ihlali
  olarak yayımlanır. Tavan 1000 µs gevşetilmedi. `rabadon-gated` **sevk
  EDİLMEZ** — istek başına iki-fork modeli ölçülmüş açık kusur
  (+2645,3 / +3365,9 µs, 7/7 çift). Sevk edilen kurulumda `settings.json`
  5 olayda `native/rabadon-gate` kayıtlı, `rabadon-gated` 0 olayda.
- **`reports/R7/accept.sh` 23 yeşil / 3 kırmızı**, kırmızı ad kümesi
  `{2b, 6e, 7b}` — büyümedi.
- **Kapanmamış kalem:** §4.3 yanlış pozitif adayı 1 adet, kapıda değil
  **self-heal kolunda** — `hooks/refresh.mjs:127` "world-writable + sticky
  (1777)" gördüğü her atayı kalıcı değil sayıyor; bu makinede `/Users/Shared`
  ve `/Library/Caches` sistemin süpürmediği 1777 kök. Onarılmadı.
- **Kapanmamış kalem:** `truth.cpp:336-337` keşif seçicisi — bulan, erteleyen
  ve kaydeden üç yer var, **sahiplenen kart yok**.

**Ayrıca bu turda ölçüldü (iki devirde "DOĞRULANMADI" duruyordu):**
`rabadon-audit` bu makinede **exit 1**. Kırık: `2026-09-03.jsonl` satır 10736
(`prev=12ba53c9… expected=d790fc7e…`) — 3 Eylül yarası, bilinen ve kasten
onarılmamış. **Yeni bulgu:** 5 dosya daha UNVERIFIABLE —
`2026-08-17.unchained.jsonl` (40 satır) ve `2026-08-21.unchained.jsonl`
(78 satır) tamamen zincir dışı; 08-08 / 08-09 / 08-29 içinde zincirlemeyen
bir yazıcıdan 8 / 3 / 1 satır. README'nin çıkış kodu sözleşmesi bu iki sebebi
de anlatmalı.

**Ölçülen kırık referanslar (bu turda açılmadı, zaten kırıktı):**
`site/build.py:87` ve `native/repair.cpp:422` `reports/2026-08-01-hakem-korpusu`
diyor — o klasör YOK. `scripts/kos-smoke.sh:81` `scripts/kos.sh` kopyalıyor,
dosya 26 Ağu'da `scripts/arsiv/`'e taşınmış. Üçü de yorum/ölü yolda olduğu
için hiçbir test görmüyor.

---

## 2026-08-23 (2) — R6 sayaç
**Yapıldı:** R6 tamamlandı. Kapanış satırı gerçek fixture'da:

    rabadon: 2 hata zinciri kesildi, 1'i anında düzeltildi, tahmini 0.36 $ kurtarıldı.

Sayının tamamı ledger'dan: median(kesilmemiş zincir) 6 (5 örnek: 4,6,6,8,10) ×
2 kesilen zincir × oturumun kendi ortalama çağrı maliyeti 0.03 $ = 0.36 $ brüt,
eksi 0.0006 $ enjeksiyon gideri (üst sınır: 400 karakter × 2 enjeksiyon / 4
karakter-token, input fiyatıyla) = **0.3594 $**. Elle aynı sayı: sonnet-4-5
(3 / 15 / 3.75 / 0.30 $/Mtok, dört ayrı sınıf) ile bir tur =
(1000×3 + 2000×3.75 + 40000×0.30 + 500×15)/1e6 = 0.03 $. cache-read input'a
katılsaydı sayı ~4 katı çıkardı; 2d bunu ayrıca ölçüyor. `fixed_instantly` = 1:
ikinci zincirde ajan "fixed it — all good" yazdı, aynı TypeError iki hamle sonra
döndü, sayaç ona inanmadı.
Önceki ajanın (60090c1) `counter.h` / `prices.h` / `gate.cpp` / `stats.cpp`
işi doğruydu ve olduğu gibi tutuldu. Benim değiştirdiğim üç şey:
(1) `Makefile`'da `rabadon-gate` ve `rabadon-stats` `counter.h`/`prices.h`'e
bağlı değildi — başlığı düzenleyip `make` demek hiçbir şeyi yeniden derlemiyordu,
sessiz bir eski-binary tuzağı; (2) Yasa 7'nin "API liste fiyatıyla teorik"
etiketi hiçbir yerde basılmıyordu ama `docs/COUNTER.md` basıldığını söylüyordu —
etiket `usage --explain`'e (`basis: API list price (api_list)`) ve `--json`'a
(`.counter.prices.basis`) eklendi, doküman gerçeğe çekildi; (3) aşağıdaki kusurun
koşulabilir kanıtı.
**Ölçüm (in-process, /tmp altındaki enstrümante kopya, `native/` temiz):**
`rb_counter_compute` oturum kapanışında p50 **978 µs**, p90 1116 µs, max 1750 µs
(10 kapanış, 184 satırlık ledger + 5 geçmiş oturum). Hot-path'e **sıfır**: kod
yalnız `SessionEnd`/`Stop` dalında; R6 6c ledger büyüdükçe PreToolUse'un
büyümediğini ayrıca ölçüyor (3.97 ms taze → 3.68 ms yüklü).
`make test` 2075 geçti, 0 kaldı (taban korundu). moves 21/0, signals 39/0,
R2 19 yeşil, R4 20 yeşil, R5 18 yeşil, R3 14 yeşil.
**Çıkan gerçek — `reports/R6/accept.sh`'te bir kusur, kanıtlanmış, dosya
DEĞİŞTİRİLMEDİ (26 yeşil / 12 kırmızı):**
*`jq_counter` boruyla gelen JSON'u hiç görmüyor.* Yardımcı `python3 - "$2" <<PY`
yazıyor: heredoc sürecin **stdin**'i, ve `python3 -` programını stdin'den okuyor,
sonuna kadar. Program çalıştığında `sys.stdin.read()` boş string dönüyor, boruyla
gönderilen JSON o fd'ye hiç girmiyor; `json.loads("")` patlıyor, yardımcı çıktısız
exit 1 veriyor — **her girdi için**, `{"a":{"b":7}}` dahil. Bu yüzden 2a-2h, 3a,
3b, 4c ürün ne yaparsa yapsın yeşile dönemiyor; 5b de onlarla düşüyor, çünkü
`EXP_NET` 2a'nın okuduğu fiyatlardan hesaplanıyor.
Kanıt: `reports/R6/defect-jq_counter.sh`. Önce yardımcıyı birebir kopyalayıp
doğru girdiye karşı koşuyor (çıktı boş, exit 1), sonra accept.sh'in **tek**
farkı `python3 -` yerine `python3 -c` olan bir kopyasını koşuyor: **38 yeşil,
0 kırmızı, R6 ACCEPTED**. `diff` çıktısı betiğin içinde basılıyor, başka hiçbir
iddia metnine dokunulmuyor.
**NOT VERIFIED:** temiz konteynerde/temiz clone'da koşulmadı (sadece bu makine,
macOS 24.2, bash 3.2 + python3). `prices.h` anlık görüntüsü (2026-08-22) LiteLLM
tablosuna karşı otomatik doğrulanmıyor; Anthropic'in yayınlanmış liste fiyatlarıyla
elle karşılaştırıldı, tutuyor. Abonelik/API ayrımı tespit edilmiyor (edilemez),
bu yüzden etiket koşulsuz basılıyor.
**Sonraki:** İnsan kararı — (a) accept.sh'te `jq_counter`'ın kendi commit'inde
düzeltilmesi (kriter önce değişir), (b) Yasa 7 etiketinin kapanış satırının
kendisine de girip girmeyeceği; o satır ürünün reklamı, tek başıma değiştirmedim.
README'ye sayaç cümlesi, accept.sh yeşile dönmeden girmiyor (KOSU §0).

## 2026-08-23
**Yapıldı:** R5 — onarım kolunun tur içi tetiği ve politika kapısı.
`native/policy.h` (yeni): `repair.mode` = ask | auto-propose | off, `$RABADON_DIR/
config.json`'dan okunur, `rabadon init` bir kez yazar (varsayılan `ask`, hiç soru
sormadan). Üç değerden biri olmayan bir mod sessizce izin sayılmaz, `off` okunur
ve stderr'e söylenir. Gate'te tetik: `root_migration` **ve** R4'ün o sinyale
diyecek bir şeyi kalmaması + en az bir enjeksiyonun ajana ulaşmış olması + aynı
hatanın o andan sonra **üç farklı hamleden** daha çıkması. Oturumda bir kez.
auto-propose'da `rabadon-repair` fork edilir (net gibi detached), ask'ta
`.rabadon/repair-request.json` + `REPAIR_ASK` yazılır, off'ta hiçbir şey.
`rabadon-repair --approve` ve `--apply` eklendi; `--apply` rabadon'da kullanıcı
ağacına dokunan **tek** yol ve onu insan yazar. Önerici metni `rbinject::scrub`
ile satır satır temizleniyor (Yasa 2) ve ağaçta gerçekten var olan dosyalar
listeleniyor; proposer çağrısı ledger'a `COST` olarak yazılıyor (chars_in/
chars_out ölçülmüş, `tokens` `"estimated":1` etiketli).
**Ölçüm (in-process, /tmp altında enstrümante kopya, `native/` temiz):** eklenen
iş, sinyal yolundaki her PostToolUse olayında p50 **125 ns**, p90 **1.2 µs**
(120 örnek, 10 oturum). Tetiğin ateşlendiği tek olay 0.39–1.22 ms — politika
dosyası okuma + fork/exec; kol detached, hook beklemez.
`make test` 2075 geçti, 0 kaldı (öncesiyle aynı). moves 21/0, signals 39/0,
R2 19 yeşil, R3 14 yeşil, R4 20 yeşil.
**Çıkan gerçek — `reports/R5/accept.sh`'te iki kusur, kanıtlanmış, dosya
DEĞİŞTİRİLMEDİ (12 yeşil / 6 kırmızı):**
1. *Claim 5 ve 6 sırayla ölçülemez.* İkisi de `$PROMPT` ve `$NEW_HOME`'u canlı
   okuyor, ama araya giren `CLAIM 4`'ün `sandbox off` çağrısı `reset_proposer`
   ile `$PROMPT`'u boşaltıyor ve `$NEW_HOME`'u yeni bir sandbox'a bağlıyor —
   `repair_cost_tokens` artık off sandbox'ının spool'unu okuyor. Claim 4a
   "proposer hiç çağrılmadı" diye ısrar ettiği için o pencerede bir çağrı
   olması da imkânsız: iki iddia birbirini dışlıyor. Kanıt: accept.sh'in
   **tek bir iddia metnine dokunulmadan** sadece CLAIM 5+6 bloğu CLAIM 4'ün
   önüne alınmış kopyası **17 yeşil / 1 kırmızı** veriyor; 5a/5b/5c ve 6a/6b
   yeşile dönüyor, 4a/4b yeni yerinde yine yeşil kalıyor.
2. *Claim 1b'nin tanığı oturuma göre kapsanmamış.* `proposer_calls_fs` makine
   genelinde tek bir dosyayı sayıyor. 1a'nın auto-propose kolu (doğru şekilde)
   detached koşuyor ve proposer'ı tetikten ~0.6 s sonra çağırıyor; 1b'nin
   sandbox'ı ~0.4 s sonra kuruluyor, yani 1a'nın çağrısı 1b'nin penceresine
   düşebiliyor. Kanıt: kaçak çağrının `cwd`'si `/private/tmp/rabadon-repair.*/
   work` (bir onarım kolunun çalışma kopyası) ve 1b'nin kendi spool'unda tek bir
   `REPAIR_*` satırı yok — gate, fork'tan ÖNCE senkron `REPAIR_TRIGGER` yazdığı
   için o kol 1b'ye ait olamaz. Aynı iddianın oturuma kapsanmış yarısı
   (`n_repair_ev`) doğru şekilde 0 okuyor. 10 koşuda ~4 kez kırmızı.
   Senkron bir kol yarışı kapatırdı ama hook'u onarım boyunca dondururdu
   (CLAUDE.md performans yasası), o yüzden kol detached bırakıldı.
**Sonraki:** İnsan kararı — accept.sh'te CLAIM 5+6 bloğunun CLAIM 4'ten önce
alınması ve 1b'nin makine-genel tanığının oturuma kapsanması (ikisi de kendi
commit'inde, kriter önce değişir).

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
