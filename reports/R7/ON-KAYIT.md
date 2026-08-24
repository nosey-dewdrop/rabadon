# R7 iki kollu koşu — ÖN-KAYIT

Durum: TAMAM ve DONMUŞ. Koşu YAPILMADI — bu dosya koşudan önce kapanır.
Tarih: 2026-08-24 (tur 13 yapan oturumu)
Yetki: operatörün tur 12 CEVAP'ı (dördüncü yol: ajan = `claude -p`).

Yasa 7 gereği bu dosya **koşudan ÖNCE** yazılır. Burada yazılı olmayan hiçbir
tanım koşudan sonra icat edilemez; koşulan sayı ancak bu dosyaya uyuyorsa
yayınlanabilir.

---

## 1. Hipotez ve onu ÇÜRÜTECEK sonuç

**Hipotez.** Aynı ajan (Claude Code), aynı görevlerde, rabadon kapısı bağlıyken
(B kolu) bağlı olmadığı hale (A kolu) göre ya daha yüksek held-out düzeltme
oranı ya da daha az net token harcar.

**Çürüten sonuç (accept.sh 7a'nın literal hali).** B kolu ne düzeltme oranını
ne net token'ı iyileştirirse hipotez YANLIŞTIR. O zaman birikme motoru susar ve
ürün konumu yeniden düşünülür — sayı yine yayınlanır, çevrilmez (Yasa 8).

**İkinci çürütme (7b).** B kolunun `estimated_saved` toplamı, iki kolun gerçek
token farkından %50'den fazla saparsa tasarruf sayacı yanlıştır; dolar cümlesi
README'den ve landing'den aynı gün kalkar.

---

## 2. Görev kümesi

Harness: **SWE-bench/SWE-smith**, commit `057f0478b6918bfcd89a51ceeec7229c60bb1028`
(v0.0.6). HARNESS.md değişmedi; operatörün tur 7 seçimi geçerli.

**Docker YOK, `swesmith` pip paketi KURULMAZ.** Ölçülerek doğrulandı (tur 13):
her instance, ayna repoda `refs/heads/<instance_id>` adlı bir **branch**'tir
(`git ls-remote --heads https://github.com/swesmith/pallets__jinja.ada0a9a6`
→ 958 branch, hedef instance dalı mevcut). Koşu bu dalı klonlayıp yerel venv +
pytest ile arm64'te yapar. Böylece `sglang → flashinfer_python →
apache-tvm-ffi==0.1.0b15` (PyPI'de yok) blokeri devre dışı kalır.

**N ve seçim.** N = 6 görev × 2 kol = 12 koşu. accept.sh'ın kol başına ≥2 görev
şartı bir TABANDIR, hedef değil. Görevler INSTANCE-TARAMA.md'de "tam temiz"
çıkan (kurulum OK + F2P beklenen şekilde düştü + P2P geçti) adaylardan,
her biri AYRI repodan seçilir. Liste koşudan önce buraya YAZILIR ve donar.

**GÖREV LİSTESİ — DONDURULDU (INSTANCE-TARAMA.md geçiş 3 ölçümünden).**
Yedi temiz adaydan altısı; hepsi ayrı repo. Bu liste koşudan önce yazıldı ve
koşudan sonra değiştirilemez.

| # | instance_id | F2P | P2P |
|---|---|---|---|
| 1 | `oauthlib__oauthlib.1fd52536.combine_file__09vlzwgc` | 18 | 655 |
| 2 | `joke2k__faker.8b401a7d.combine_module__5edhgqcy` | 5 | 2098 |
| 3 | `kurtmckee__feedparser.cad965a3.combine_module__bd6dsmkp` | 55 | 4174 |
| 4 | `pylint-dev__astroid.b114f6b5.func_pm_ctrl_shuffle__b40xxf3u` | 9 | 1584 |
| 5 | `pydicom__pydicom.7d361b3d.func_pm_remove_cond__c4ctdv6a` | 1 | 2328 |
| 6 | `HIPS__autograd.ac044f0d.pr_579` | 11 | 574 |

**Neden conan yedincisi olarak alınmadı:** temiz çıktı ama P2P listesi yalnız
3 test (diğerlerinde 574–4174). "P2P bozulmadı" şartı orada neredeyse hiçbir
şey ölçmez; regresyona karşı kör bir görev, `heldout_pass`'i ucuzlatır. Yedek
olarak durur.

**DIŞLANANLAR ve sebebi (ölçülmüş):** jinja — bozuk dalda F2P GEÇTİ, bug
üremiyor, iki kol da "çözdü" görünürdü. python-docx — `pyparsing` sürüm
çakışması. pydantic — `pydantic-core` Rust wheel derlenmedi.

**KOŞU ÖNCESİ ZORUNLU DOĞRULAMA.** Yukarıdaki altı instance bu turda BİRER kez
ölçüldü. Koşuyu yapan oturum, her instance için koşudan hemen önce aynı üç
kontrolü tekrarlar (kurulum OK, F2P düştü, P2P geçti) ve sonucu JSONL'in
yanına yazar. Kontrolü geçmeyen instance koşuya ALINMAZ ve yerine yedek
(conan) girer.

**Ölçülmüş zemin (tur 13, varsayım değil).** HF `SWE-bench/SWE-smith` datasetinde
59 136 satır, örneklemde 12 ayrı repo. `FAIL_TO_PASS` ve `PASS_TO_PASS` alanları
her satırda MEVCUT — örnek satır `oauthlib__oauthlib.1fd52536.combine_file__09vlzwgc`:
F2P 18 test, P2P 655 test. Ayna repoların 10/10'u public ve `git ls-remote` ile
auth'suz çözüldü.

---

## 3. Kolların TEK farkı

Fark env değişkeni değil, **hook'un bağlı olup olmamasıdır** (B1.5 reçetesi):

- **A kolu:** `settings.local.json` yok, hook hiç bağlanmaz. rabadon yoktur.
- **B kolu:** göreve özgü checkout'ta `settings.local.json`, hook komutu
  `$CLAUDE_PROJECT_DIR` göreli, sarmalayıcı
  `sh -c 'timeout 2 <gate> ... </dev/null; exit 0'`.

**BAĞLAMA KABULÜ (B1.5, aynen geçerli).** B kolu koşusu, ledger'da o koşuya ait
YENİ SATIR gösterilmeden "B kolu" sayılmaz. Satır yoksa o koşu geçersizdir ve
JSONL'e B satırı olarak YAZILMAZ. Bu, hook'un doğru köke bağlandığının kanıtla
doğrulanmasıdır, varsayımla değil.

Diğer her şey iki kolda aynıdır: aynı model, aynı prompt, aynı görev metni
(`problem_statement`), aynı zaman sınırı, aynı makine, sıralı koşu.

---

## 4. Alan tanımları — koşudan ÖNCE donduruldu

JSONL satırı başına alanlar (accept.sh 5b/6a–6e'nin okuduğu adlar):

| alan | tanım |
|---|---|
| `arm` | `"A"` veya `"B"` |
| `instance_id` | SWE-smith instance kimliği (= ayna repo dal adı) |
| `heldout_pass` | bool. **(tüm F2P testleri geçti) VE (P2P'den hiçbiri bozulmadı)** |
| `tokens` | int. `input_tokens + output_tokens`, `result` olayının `usage` bloğundan |
| `interventions` | int. Aşağıdaki tanım |
| `false_positive` | bool. Aşağıdaki tanım |
| `estimated_saved` | int, YALNIZ B kolunda. rabadon'un kendi tasarruf tahmini |

**`tokens` — ölçülerek belirlendi, varsayılmadı.** `claude -p --output-format
stream-json --verbose` çıktısının son `{"type":"result"}` olayında `usage`
bloğu şu adları taşıyor (tur 13'te çalıştırılıp GÖRÜLDÜ):
`input_tokens`, `output_tokens`, `cache_creation_input_tokens`,
`cache_read_input_tokens`, ayrıca `total_cost_usd`.
`tokens` = `input_tokens + output_tokens`. Cache alanları **dışarıda bırakılır**
ve ham JSONL'e ayrı alan olarak yine de yazılır — cache okuması ajanın işinin
büyüklüğü değil, oturum geçmişinin bir yan etkisidir ve iki kolda asimetrik
şişer (B kolunda hook çıktısı bağlama girer). Karar burada donar.

**`interventions` — headless koşuda yapısal olarak 0 olabilir, tanım şudur:**
koşuyu sürdürmek için bir insanın müdahale etmesi gereken olay sayısı. Headless
`claude -p` koşusunda insan yoktur; bu yüzden operasyonel tanım:
**ajan oturumu, görevi bitirmeden zaman sınırına takılarak veya hata ile
sonlandığında 1, normal bittiğinde 0.** İki kolda AYNI tanım uygulanır.
Her iki kolda toplam 0 çıkması geçerli bir sonuçtur ve accept.sh 6c'yi
geçirir (0 sayısal bir değerdir, eksik değil) — ama o durumda bu metrik
"iki kol arasında ayrım üretmedi" diye RAPORLANIR, sessizce yeşile sayılmaz.

**`false_positive` — tanım:** rabadon'un, göreve zarar vermeyen meşru bir
ajan eylemini engellemesi (veya observe modda "engellerdim" demesi). **A kolunda
kapı YOKTUR, dolayısıyla `false_positive` her zaman `false`'tır** — bu bir
ölçüm değil, yapısal bir sıfırdır ve raporda böyle etiketlenir. Ayrım gücü
yalnız B kolundadır.

**`estimated_saved`:** rabadon'un ledger'a yazdığı tasarruf tahmini toplamı.
6e bunu iki kolun GERÇEK token farkıyla karşılaştırır; sapma > %50 ise 7b düşer.

---

## 5. Held-out mekanizması ve sızıntı önleme — 4d hazırlığı

**Mekanizma ÖLÇÜLDÜ (tur 13), swesmith belgesinden değil repodan okundu:**

- instance dalı (`refs/heads/<instance_id>`) = **bozuk kod**, ve F2P test
  dosyaları o daldan **SİLİNMİŞ**. Örnek: oauthlib instance dalında
  `tests/oauth2/rfc6749/clients/` içinde yalnız `__init__.py` var; altı test
  dosyası yok. Dal 235 dosya, `main` 247 dosya.
- `main` dalı = **düzeltilmiş kod + bütün testler**, saklı F2P dosyaları dahil.

Yani **held-out'luk yapısaldır, biz üretmiyoruz** — SWE-smith saklı testleri
zaten ajanın göreceği ağaçtan çıkarmış. Bu, 6a'nın "ajanın kendi testi
sayılmaz" şartını mimari olarak karşılar.

**Puanlama yordamı (bundan sonra donuk):** koşu bittikten sonra puanlayıcı,
F2P node id'lerinin dosya yollarını `origin/main`'den geri koyar
(`git checkout origin/main -- <yol>`), sonra F2P + P2P koşar.
`heldout_pass = (tüm F2P geçti) VE (P2P bozulmadı)`.

**SIZINTI — bu koşuda teorik değil, ÖLÇÜLMÜŞ bir risk.** `origin/main` hem
**cevabı** (düzeltilmiş kod) hem **saklı testleri** taşıyor ve klonlanan
depoda erişilebilir. `git diff origin/main` tek komutta görevi çözer. Bu iki
kolu birden şişirir ve bug olarak değil, "iki güzel sayı" olarak görünür.

Bu yüzden her görev checkout'unda, ajan başlamadan ÖNCE:
1. Hedef dal klonlanır, sonra **`.git` dizini tamamen SİLİNİR**. Geçmiş, uzak
   referans, `main` kalmaz. Puanlayıcı `main`'i AYRI bir klonda tutar; ajanın
   ağacıyla teması yoktur.
2. Ajanın ağacında F2P dosyaları zaten yoktur (yukarıdaki mekanizma). Ekstra
   çıkarma gerekmez; puanlama anında geri konur.
3. Ağ: görev checkout'undan giden git/pip erişimi kapatılır. Bu adım
   **best-effort** olarak etiketlenir — `claude -p` model API'sine çıkmak
   zorundadır, tam egress kapatma MÜMKÜN DEĞİLDİR ve böyle raporlanır.

Bu maddeler HARNESS.md'ye 4d kaydı olarak, koşu FİİLEN kurulduğunda yazılır —
önce değil (boş yeşil yasağı).

---

## 6. Bu ön-kaydın kapsamADIĞI

- **Daemon kolu.** 2b latansı (bugün 1240.8 µs, tavan 1000 µs) KIRMIZI kalır ve
  bu koşuyla yeşile gitmez. Ayrı emir: PROFIL-YARGILAMA.md'deki kalan kalemler.
- **İstatistiksel yayın gücü.** N=6, gürültüyü yenmek için küçüktür. Sonuç
  KOSU-RABADON-2.md:61-62 uyarınca değerlendirilir: fark gürültü içinde kalırsa
  **YAYINLANMAZ**, ama ham JSONL ve bu ön-kayıt yine de repoda durur.
