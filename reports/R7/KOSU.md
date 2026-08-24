# R7 iki kollu koşu — koşu kaydı

Durum: KOŞULDU (kısmi — bkz. "Ne kadarı koşuldu").
Tarih: 2026-08-24 (tur 14 yapan oturumu)
Ön-kayıt: `reports/R7/ON-KAYIT.md` (koşudan ÖNCE donduruldu, tur 13).
Ham kayıt: `reports/R7/ab_run.jsonl` — **sayıların tek kaynağı budur.**
Harness: `reports/R7/ab_run.sh`. Görev metinleri: `reports/R7/ab_gorevler.json`.

Bu dosya yorum katmanıdır; bir sayı burada varsa ham kayıtta da vardır.

---

## Kurulum — operatörün dördüncü yolu, uygulanmış hali

- **Ajan `claude -p`.** Abonelik auth'u; marjinal dolar maliyeti ~0.
- **Docker YOK, `swesmith` pip paketi KURULMADI.** Her instance ayna repoda bir
  branch; klonlanıp yerel venv + pytest ile arm64'te koşuyor. Tur 12'nin
  `sglang → flashinfer_python → apache-tvm-ffi` blokeri böylece devre dışı.
- **Kolların tek farkı hook.** Her iki kol da
  `claude -p --setting-sources local` ile koşar. A kolunda
  `.claude/settings.local.json` YOKTUR; B kolunda vardır ve içinde
  `sh -c 'timeout 2 node <gate> 2>/dev/null; exit 0'` sarmalayıcısı bulunur.

  **`--setting-sources local` deneyin geçerlilik şartıdır, bir ayrıntı değil.**
  Operatörün global `~/.claude/settings.json`'ı `rabadon-gate`'i bu makinedeki
  HER claude oturumunun HER hook olayına bağlıyor. Bu bayrak olmadan A kolu da
  rabadon'lu koşar ve kontrast YOK OLUR. Tur 14'te tam olarak bu oldu: A kolu
  kendi etiketiyle 36 ve 40 ledger satırı yazdı, transcript'inde rabadon'un
  kendi cümlesi vardı. O satırlar
  `reports/R7/ab_run_INVALID_global_hook.jsonl`'e taşındı.

  Üç ölçüm bayrağın davranışını kanıtlıyor (hepsi çalıştırıldı):
  `--setting-sources local` + dosya YOK → **0** ledger satırı;
  + hook'lu dosya VAR → **1**; `--setting-sources project` boş dizinde → **0**.

  **Sarmalayıcı B1.5'in yazılı halinden BİLEREK farklı — sebebi ölçüldü.**
  B1.5 literal olarak `</dev/null` diyor; o redirect kapıyı SAĞIR yapıyor
  (Claude Code olay JSON'unu hook'un STDIN'ine yazar). Aynı olayla ölçüm:
  `</dev/null` ile ledger'a yeni satır **0**, onsuz **1**. Yani B1.5'in kendi
  "bağlama kabulü" şartı kendi reçetesiyle karşılanamıyor. Reçete
  DEĞİŞTİRİLMEDİ — bu bir CHALLENGE'dır (DENEMELER deneme 16), belge
  değişikliği insanın.

  Ayrıca stdout **asla** susturulmaz: kapı ajanla stdout üzerinden konuşur.
  Bu turda bir kez `>/dev/null` yazıldı ve B kolu "ledger yazan ama ajana
  hiç konuşmayan" bir rabadon'u ölçtü; o satırlar geçersiz sayılıp
  `reports/R7/ab_run_INVALID_muted_hook.jsonl`'e taşındı, silinmedi.
- **Sızıntı önleme.** Ajanın ağacında `.git` YOK (silinir). `origin/main` hem
  çözümü hem saklı testleri taşıdığı için bu formalite değil geçerlilik şartı.
  Puanlayıcı `main`'i ayrı bir klonda tutar.

---

## SONUÇ — beş sayı, ham kayıttan

Kabul betiği: `./reports/R7/accept.sh` → **23 yeşil / 3 kırmızı**
(tur 13'te 14 yeşil / 12 kırmızıydı).

| metrik | A kolu (rabadon YOK) | B kolu (rabadon VAR) |
|---|---|---|
| held-out düzeltme oranı | **75.0 %** (4 görev) | **75.0 %** (4 görev) |
| toplam token | **35 620** | **33 221** |
| insan müdahalesi | 0 | 0 |
| yanlış pozitif | 0 % (yapısal) | 0 % |

Görev bazında token:

| görev | A | B | fark | heldout_pass |
|---|---|---|---|---|
| autograd | 14 775 | 13 007 | **−12.0 %** | ikisi de geçti |
| pydicom | 6 378 | 4 813 | **−24.5 %** | ikisi de geçti |
| oauthlib | 5 627 | 5 877 | **+4.4 %** | ikisi de DÜŞTÜ (15/18 F2P) |
| feedparser | 8 840 | 9 524 | **+7.7 %** | ikisi de geçti |

### Bu sayı YAYINLANAMAZ — ve bunu 7a'nın "geçmesi" değiştirmez

accept.sh 7a yeşil verdi ("B kolu net token'ı iyileştiriyor"). **Bu bir
kanıt değildir ve öyle sunulmayacaktır.** Sebepler, hepsi ham kayıttan:

1. **Düzeltme oranı AYNI** (75.0 % / 75.0 %). Dört görevin üçünde iki kol da
   çözdü, birinde (oauthlib) iki kol da **aynı şekilde** düştü — ikisi de
   18 F2P'nin 15'ini geçti. rabadon hiçbir görevde farklı bir sonuç üretmedi.
2. **Yön 2-2 BÖLÜNMÜŞ.** İki görevde B daha ucuz (−12.0 %, −24.5 %), iki
   görevde daha pahalı (+4.4 %, +7.7 %). Toplamdaki −6.7 %, dört ölçümün
   işaretçe yarısının ters olduğu bir ortalamadır.
3. **N = 4.** Ön-kayıt N=6 diyordu; iki instance ön-doğrulamayı geçemedi.
4. **Hücre başına TEK ölçüm var, varyans tahmini YOK.** Buna karşılık aynı
   görev+kol farklı koşularda şu kadar oynadı: autograd B 15 099 → 13 007
   (%16), oauthlib B 8 962 → 5 877 (%52). Koşu-içi salınım, iki kol
   arasındaki farktan **BÜYÜK**.

KOSU-RABADON-2.md:61-62 gereği: fark gürültü içinde kalırsa YAYINLANMAZ.
Kalıyor. Ham JSONL ve bu ön-kayıt repoda durur; dışarıya bir oran/tasarruf
cümlesi çıkmaz.

**Doğru okuma:** bu tur, iki kollu koşunun **koşulabilir olduğunu** ve
ölçüm zincirinin uçtan uca çalıştığını kanıtladı. Hipotezi ne doğruladı ne
çürüttü — N ve tekrar sayısı bunun için yeterli değil.

## Ne kadarı koşuldu

Ham kayıttaki satır sayısı bu bölümün tek doğrulayıcısıdır:

    python3 -c "import json;rows=[json.loads(l) for l in open('reports/R7/ab_run.jsonl') if l.strip()];\
    print(len(rows),'satır');\
    print({a:sum(1 for r in rows if r['arm']==a) for a in ('A','B')})"

**Altı görevin dördü koşuldu.** İkisi koşu öncesi zorunlu doğrulamayı
geçemedi ve ALINMADI (`ab_prever.tsv`):

| instance | sebep |
|---|---|
| conan | P2P 0/3 — conftest hâlâ çöküyor (`test/functional` ağır bağımlılık ister) |
| astroid | P2P 118/120 — iki P2P testi bozuk dalda ZATEN düşüyor, "bozulmadı" o ikisi için ölçülemez |

**Başlangıçta ÜÇ instance elenmişti ve üçünün elenme sebebi de HARNESS
HATASIYDI, instance hatası değil.** İki ayrı kusur:

1. **Test "extras"ları kurulmuyordu.** conan `No module named 'mock'`,
   feedparser `No module named 'responses'` diye conftest'te çöküyordu.
   `kur_venv` artık `pip install -e '.[test]'` (ve dev/tests/testing)
   varyantlarını deniyor.
2. **Skip'ler düşme sayılıyordu.** astroid "P2P 73/120" diye elenmişti;
   pytest özeti aslında "2 failed, 73 passed, **45 skipped**" diyordu.
   Sayaç `passed == toplam` arıyordu. Artık P2P için ölçüt "DÜŞMEDİ"
   (skip bozulma değildir), F2P için "gerçekten GEÇTİ" (skip bir düzeltme
   kanıtı değildir).

Düzeltmeden sonra **feedparser koşuya girdi** ve iki kol da çözdü (55/55 F2P).
astroid ve conan hâlâ dışarıda, ama artık sebepleri TEŞHİS EDİLMİŞ durumda
(yukarıdaki tablo), "bilinmeyen bir duvar" değil.

Koşu **yeniden başlatılabilir**: tamamlanmış (instance, kol) çiftleri ham
kayıtta durur ve `ab_run.sh` yeniden çalıştırıldığında atlanır. Oturum zaman
sınırına takılırsa sonraki tur kaldığı yerden devam eder — yarım kalan iş
hiçbir zaman uydurulmuş bir satıra dönüşmez.

---

## İki KABUL şartı — her iki kol da kanıtlanır, varsayılmaz

- **B kolu / bağlama kabulü (B1.5).** Ledger'da o koşuya ait YENİ SATIR
  gösterilmezse koşu B sayılmaz ve JSONL'e yazılmaz.
- **A kolu / kontrol kolu saflığı (tur 14'te doğdu, YENİ).** Ledger'da o
  koşuya ait TEK satır bile varsa kontrol kolu kirlenmiştir ve satır JSONL'e
  yazılmaz. B'nin şartı vardı, A'nınki YOKTU — global settings sızıntısı tam
  o boşluktan geçti. Simetri artık kodda (`ab_run.sh`), `gecersiz.tsv`'ye
  düşer.

Satırların `pipe` etiketiyle sayılması gerekiyor, ham fark ile değil: ortak
spool'da 220 000+ satır var ve başka oturumlar da yazıyor. Görev dizini
`<instance_id>__<kol>` diye benzersiz adlandırılır, ledger satırındaki
`"pipe":"<dizin>:..."` alanı bu koşuya ait satırı kesin ayırır.

## Koşu ÖNCESİ zorunlu doğrulama (ON-KAYIT §2 şartı)

`reports/R7/ab_prever.tsv`. Her instance için koşudan hemen önce üç kontrol
TEKRARLANDI: kurulum OK, F2P bozuk ağaçta düştü, P2P bozuk ağaçta geçti.
Bu üçünü geçmeyen instance koşuya ALINMADI.

**Held-out testler bozuk dalda YOKTUR** — bu yüzden F2P kontrolü ancak
dosyalar `origin/main`'den geri konduktan sonra anlamlıdır. (Tur 14'te bu
önce atlandı ve sağlam instance'lar yanlışlıkla elendi; bkz. DENEMELER
deneme 15, "kendi hatam".)

---

## Ön-kayıttan SAPMA — bir görev değişti, sebebi ölçülmüş

**`joke2k__faker...5edhgqcy` koşuya ALINMADI. Yerine yedek `conan-io__conan.86f29e13.pr_12165` girdi.**

Sebep: faker instance'ının `problem_statement` alanı **BOŞ** (0 karakter).
Ajana verilecek bir görev metni yok; koşulsaydı iki kol da boş bir istemle
çalışır, sonuç ölçüm değil gürültü olurdu.

Bu tek bir instance'ın kazası değil: **SWE-smith'in 59 136 satırının
18 033'ünde (%30.49) `problem_statement` boş.** Ölçüldü, parquet üzerinden
sayıldı. Tur 13'ün instance taraması kurulum/F2P/P2P'ye bakıyordu, görev
metninin varlığına HİÇ bakmıyordu — bu, tarama ölçütündeki bir boşluktur ve
gelecek seçimlerde dördüncü kontrol olmalıdır.

Yedeğe geçiş ON-KAYIT'ın kendi mekanizmasıdır (conan orada "yedek olarak
durur" diye adlandırılmıştı). Ama ON-KAYIT'ın zorunlu ön-doğrulaması üç
kontrol sayıyor, "problem_statement boş değil" onlardan biri DEĞİL — yani
bu sapma dondurulmuş belgenin ÖNGÖRMEDİĞİ bir sebeple yapıldı. Sessizce
yapılmadı, buraya ve DENEMELER'e yazıldı; değerlendiren/operatör reddederse
ham kayıt hangi instance'ların koştuğunu satır satır gösteriyor.

conan'ın bilinen zayıflığı da kayıtta kalsın: P2P listesi yalnız 3 test
(diğerlerinde 574–4174), yani "P2P bozulmadı" orada regresyona karşı büyük
ölçüde kör bir kontroldür.

---

## İLAN EDİLMİŞ kısıtlamalar (sessiz değil)

- **P2P tavanı.** Tam P2P listeleri 574–4174 test. Her satırda ilk
  `p2p_cap` (varsayılan 120) node id koşuldu ve bu sayı ham kayıtta
  `p2p_cap` alanı olarak YAZILI. "P2P bozulmadı" bu örneklem için geçerlidir,
  tam liste için değil.
- **Ajan zaman sınırı** her iki kolda AYNI (`AGENT_TIMEOUT`, koşuda 900 s).
- **Ölçüm bu macOS arm64 makinesinde**, temiz container'da değil.
- **Egress kapatma best-effort.** `claude -p` model API'sine çıkmak zorunda;
  tam ağ kapatma mümkün değil. Kapatılan somut kanal `.git`'tir.

---

## `estimated_saved` — 6e ve 7b KIRMIZI KALIR: RABADON TASARRUF SAYISINI ÜRETEMİYOR

**OPERATÖR KARARI (24.08, `reports/kosu/14.operator.md` CEVAP 1).** 6e ve 7b
kırmızı kalır, R7 **23/25** ile kapanır, ön-kayda DOKUNULMAZ. Bu bir betik
kusuru ya da birim hatası **değildir** — bir **ürün boşluğudur**, ve şartı
değiştirmek onu gizlerdi. Aşağıdaki "birim çelişkisi" çerçevelemesi bu kararla
GEÇERSİZDİR; teşhisi doğru, sonucu yanlıştı ve düzeltilmek üzere bırakıldı.

Ön-kaydı `total_cost_usd`'ye çevirme önerisi ölçümle çürüdü: `ab_run.jsonl`'in
8 satırının 8'inde de `estimated_saved` alanı **zaten yok**, yani 6e'nin
düştüğü yer payda değil PAY; birim değişse de kırmızı kalırdı. Üstelik `est`
harness'ın kendi `total_cost_usd` farkına çevrilseydi geriye `|x-x|/x = %0`
kalırdı — her koşuda otomatik yeşil bir totoloji, yani testi zayıflatmanın
birebir tarifi.

**ÜÇ BAĞIMSIZ BARİYER — üçü de ölçüldü:**

1. **Predikat körlüğü — tur 15'te DÜZELTİLDİ.** `native/usage.h`'in sayacı bir
   satırdaki İLK `"type"` anahtarını alıp `"assistant"` bekliyordu. Claude Code
   `message{}`'i üst seviye `type`'tan ÖNCE yazdığı için o anahtar her gerçek
   satırda `"message"` çıkıyor ve predikat hiçbir gerçek satırı eşleştirmiyordu.
   Gerçek 425 satırlık bir transcript'te stok json ayrıştırıcı **414 çağrı /
   136 816 678 cache-read token** sayarken rabadon **1 çağrı / 0 token**
   okuyordu. Sayaç, Stop token ledger'ı (`gate.cpp`) ve lens aynı predikattan
   besleniyor — yani rabadon'un üç iddiasından üçüncüsü, "parayı söyler",
   canlıda ölüydü ve suite yeşildi. Depodaki BÜTÜN fixture'lar üst seviye
   `type`'ı önce yazdığı için hiçbir test bunu göremiyordu; fixture'lar maskeydi.
   `native/usage_order_test.sh` ile kapatıldı (`make test` içinde).
2. **B kolunda sayaç HİÇ KOŞMUYOR — tur 15'te DOĞRULANDI, AÇIK.**
   `ab_run.sh:249-258` B kolunun `settings.local.json`'ına yalnız `PreToolUse`
   yazıyor. COUNTER olayı ise yalnız `gate.cpp:4008` (`SessionEnd`) ve
   `gate.cpp:4092` (`Stop`) üzerinden üretiliyor. Ledger bunu bağımsız
   doğruluyor: geçerli koşunun B örneklerinde **sadece STEP_START** var
   (feedparser__B: 9, pydicom__B: 5 — JSONL'deki `ledger_new_lines` ile birebir),
   COUNTER ve RUN_DONE **yok**.
3. **`median_n:0` — AÇIK, yapısal.** `counter.h:71` `MIN_HISTORY=3` istiyor;
   her görev tek oturum, birikmiş örnek yok. Predikat düzelse ve hook doğru
   bağlansa bile 6e bu turda kapanmazdı. Beklenen sonuç, tekrar denenmeyecek.

**YAYIN YASAĞI (CEVAP 2).** Dolar/tasarruf cümlesi, 1 ve 2 kapanıp bir koşuda
sıfırdan farklı bir sayı ÖLÇÜLENE kadar POSITIONING.md, SAVUNMA.md, landing
page ya da başka HİÇBİR yerde yayınlanmayacak.

### (geçersiz çerçeveleme, kayıt için bırakıldı) birim çelişkisi

Bu, koşunun bir başarısızlığı değil, ön-kayıtla ürünün arasındaki bir
**birim çelişkisidir** ve koşudan bağımsızdır:

- rabadon'un ürettiği tek tasarruf sayısı `saved_usd` — **USD cinsinden**
  (`native/counter.h:77`). Çalıştırılarak görüldü:
  `rabadon-stats --json` → `"saved_usd":null,"reason":"no-close"`.
- `estimated_saved` adlı alan kaynak ağacında **HİÇ YOK**.
- accept.sh 6e bu alanı `tok_A - tok_B` ile, yani bir **token farkıyla**
  karşılaştırıyor. Dolar ile token karşılaştırılamaz.

Bugünkü halinde 7b "UNCHECKABLE" diye düşüyor, "TETİKLENMİŞ" diye değil —
yani dolar cümlesi bir birim hatası yüzünden README'den kaldırılmıyor. Bu
doğru davranıştır ve korunmalıdır. Karar operatöre bırakıldı; seçenekler
DENEMELER deneme 14'te.

---

## NOT VERIFIED

- Ham kayıt kaç göreve ulaştıysa o kadarı ölçüldü; kalanlar için hiçbir sayı
  iddia EDİLMEZ.
- N küçük. KOSU-RABADON-2.md:61-62 gereği fark gürültü içinde kalırsa sayı
  YAYINLANMAZ; ham kayıt ve ön-kayıt yine de repoda durur.
- `interventions` headless koşuda yapısal olarak çoğunlukla 0'dır (tanım:
  ajan zaman sınırına takılır/hata ile biterse 1). İki kolda 0 çıkarsa bu
  metrik "ayrım üretmedi" diye raporlanır, sessizce yeşile sayılmaz.
- 2b latansı (daemon kolu) bu koşunun KAPSAMI DIŞINDA ve KIRMIZI kalıyor.

---

## P2P DIŞLAMASI — İLAN (ON-KAYIT §7 madde 5)

Bozuk dalda zaten düşen P2P testleri taban kümeden çıkarılır. Bu **sessiz bir
kısıtlama değildir**; sayı ve isimle burada, `ab_prever.tsv`'de ve JSONL'in
`p2p_excluded` / `p2p_excluded_ids` alanlarında durur.

Ön-doğrulama tur 15'te altı instance'ın ALTISI için yeniden koşuldu
(`reports/R7/prever.tur15.out`, `PREVER_ONLY=1` — hiçbir ajan oturumu, yani
hiçbir para harcanmadı):

| instance | F2P (bozukta) | P2P | dışlanan | karar |
|---|---|---|---|---|
| autograd | 0/11 düştü | 120/120 | 0 | ALINDI |
| oauthlib | 0/18 düştü | 120/120 | 0 | ALINDI |
| conan | 0/29 düştü | 3/3 | 0 | ALINDI |
| pydicom | 0/1 düştü | 120/120 | 0 | ALINDI |
| astroid | 0/9 düştü | 118/118 | **2** | ALINDI |
| feedparser | 39/55 düştü | 120/120 | 0 | ALINDI |

Dışlanan iki test (`p2p_excluded/pylint-dev__astroid...txt`), iki ayrı
ön-doğrulama koşusunun KESİŞİMİ:
`tests/brain/test_brain.py::TypingBrain::test_has_dunder_args` ve
`::test_typing_types`. Üçüncü aday çıkmadı, flake çıkmadı.

**Neden bu bir kaçış yolu değil:** çıkarılan şey SAYI değil **İSİMDİR**, ve
iki kol birebir aynı küçültülmüş kümeyi koşar. Ajan başka iki P2P testini
bozarsa `pg < pt` çıkar; `heldout_pass` şartı `pg == pt` olarak aynen durur.
Küme ajan koşmadan önce, ayrı bir ağaçta, ayrı bir commit'te üretildi.

## HARNESS HATASI — conan'ın elenmesi ölçümle çürüdü

conan tur 14'te "P2P 0/3 = toplama/ortam çöküşü" diye elendi. Log'un TAMAMI:

    ERROR: file or directory not found: @.nodeids
    no tests ran in 0.39s

Bu bir ortam çöküşü değil, **harness'ımızın hatasıydı**: node id'ler pytest'e
`@dosya` argfile'ıyla veriliyordu, o da pytest'in argparse
`fromfile_prefix_chars` desteğine bağlıdır ve eski sürümlerde YOKTUR — o sürüm
`@.nodeids`'i bir dosya yolu sanar. Argümanla geçmeye çevrildi; conan yeniden
ölçüldüğünde **3/3 geçti**. Tur 14'te elenen üç instance da harness hatasıydı;
bu dördüncüsü. **N'in bugüne kadarki değeri harness kusurlarıyla bastırılmıştı.**

conan'ın koşuya alınması yine de OPERATÖR kararıdır: ON-KAYIT §2'nin ayrı
gerekçesi (P2P listesi yalnız 3 test, `heldout_pass`'i ucuzlatır) bu ölçümden
bağımsız olarak geçerlidir.

## P2P_CAP KIRILGANLIĞI — kayda geçti

`P2P_CAP=120` ilk 120 node id'yi alır (`ab_run.sh:178`). astroid'in P2P listesi
**1584** test; düşen iki test bu listenin **62.** ve **97.** sırasında, yani
dilimin içine tamamen SIRA ŞANSIYLA düşmüşler. Cap 60 olsaydı biri, cap 50
olsaydı ikisi de görünmezdi ve astroid "temiz" sanılırdı. Kapsama %7.6.
Bu, ölçümün cap seçimine duyarlı olduğunun kaydıdır.

## A KOLU LEDGER SATIRI — hangi koşuya ait olduğu doğrulandı

`HIPS__autograd...__A` etiketli COUNTER olayı (`reason:"no-chains"`,
ts=1787580484063 → 24.08 17:08:04) **karantinaya alınmış** koşuya ait:
`/tmp/rbrun/ab_run.out` A kolu 17:06:21–17:08:04 (103 sn) ve
`ab_run_INVALID_global_hook.jsonl` autograd A `duration_s=103`. Geçerli
koşudaki (ab_run.jsonl) autograd A `duration_s=184`. Aynı karantina koşusunda
`autograd__B`, `oauthlib__A`, `oauthlib__B` COUNTER'ları da var — yani "global
hook A koluna da bağlıydı" tespiti ledger'da bağımsız olarak doğrulanıyor.
**Geçerli koşuda hiçbir `__A` ledger satırı yok; kontrol kolu temiz.**
