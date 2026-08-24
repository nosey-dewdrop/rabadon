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

## Ne kadarı koşuldu

Ham kayıttaki satır sayısı bu bölümün tek doğrulayıcısıdır:

    python3 -c "import json;rows=[json.loads(l) for l in open('reports/R7/ab_run.jsonl') if l.strip()];\
    print(len(rows),'satır');\
    print({a:sum(1 for r in rows if r['arm']==a) for a in ('A','B')})"

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

## `estimated_saved` — 6e ve 7b yapısal olarak kapanamaz

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
