# R7 — instance taraması: Docker'sız yerel venv koşusu ölçüldü

Tarih: 2026-08-24 (tur 13 yapan oturumu)
Emir: operatörün tur 12 CEVAP'ı — "aday instance listesinden en az 8'ini deneyip
kaçının temiz kurulduğunu ÖLÇMEK. 4'ten azı kuruluyorsa DUR ve operatöre dön."

Bu dosya bir ölçüm kaydıdır. Her satırın arkasında çalıştırılmış bir komut var;
hiçbir satır swesmith belgesinden alınmadı.

---

## 1. Aday havuzu — nasıl seçildi

HF `SWE-bench/SWE-smith` datasetinden (**59 136 satır**, `/size` uç noktasıyla
okundu) on ayrı ofsetten 100'er satır çekildi. Örneklemde **12 ayrı repo** çıktı.
İkisi Go (`denisenkom__go-mssqldb`, `spf13__cobra`) — derlenen zincir istedikleri
için kapsam dışı bırakıldı. Kalan **10 saf-Python repo** tarandı; her repodan
BİR instance, hepsi ayrı repodan.

**Klonlanabilirlik (SIRAYA madde 2) — 10/10 GEÇTİ.** Onunun da ayna reposu
public; `git ls-remote` auth'suz çözüldü, hash döndü. Örnek:

    $ git ls-remote https://github.com/swesmith/pallets__jinja.ada0a9a6 HEAD
    83b73140ca308ee1c65870c78d11ebdff5a13d68

---

## 2. EN ÖNEMLİ BULGU — instance bir Docker imajı değil, bir GIT DALI

`swesmith` pip paketi kurulmadı, Docker çalıştırılmadı. Ölçülen yapı:

    $ git ls-remote --heads https://github.com/swesmith/pallets__jinja.ada0a9a6 | wc -l
    958
    $ git ls-remote --heads .../pallets__jinja.ada0a9a6 "*047pa4yh*"
    2103f96d3f24fd4e321e32293480fc4ecf789bd6  refs/heads/pallets__jinja.ada0a9a6.func_pm_ctrl_shuffle__047pa4yh

Her instance ayna repoda bir **dal**. Dolayısıyla görev, dalı klonlayıp yerel
venv + pytest ile arm64'te koşulabilir. Bu, TESHIS-HARNESS'in dört blokerinden
üçünü (sglang bağımlılık zinciri, amd64-only imaj, Docker daemon) devre dışı
bırakır — o blokerler `swesmith` paketinin ve imajlarının blokerleriydi,
görev kümesinin değil.

## 3. İKİNCİ BULGU — held-out testler dalda YOK, `main`'de var

Tarama sırasında F2P testleri "bulunamadı" diye düştü. Sebep ölçüldü:

    $ ls tests/oauth2/rfc6749/clients/          # instance dalinda
    __init__.py                                  # ALTI test dosyasi YOK
    $ git ls-tree -r --name-only origin/main -- tests/oauth2/rfc6749/clients/
    tests/oauth2/rfc6749/clients/__init__.py
    tests/oauth2/rfc6749/clients/test_backend_application.py
    ... (alti dosya)
    dal: 235 dosya   main: 247 dosya

**instance dalı** = bozuk kod + F2P test dosyaları silinmiş.
**`main` dalı** = düzeltilmiş kod + bütün testler.

İki sonucu var:

1. **Held-out'luk yapısaldır, biz üretmiyoruz.** accept.sh 6a'nın "ajanın kendi
   testi sayılmaz" şartı mimari olarak karşılanıyor. Puanlama = F2P dosyalarını
   `origin/main`'den geri koyup koşmak.
2. **Sızıntı riski ölçülmüş bir gerçek.** `origin/main` hem cevabı hem saklı
   testleri taşıyor; `git diff origin/main` görevi tek komutta çözer. Ajanın
   checkout'unda `.git` SİLİNMEK ZORUNDA. Bu, 4d hazırlığının boş bir formalite
   değil, bu koşunun geçerlilik şartı olduğu anlamına gelir.

---

## 4. Kendi taramamın iki hatası — düzeltildi, kayda geçti

Yasa 8 gereği kendi ölçüm hatalarım burada duruyor; ilk iki geçişin F2P
sonuçları YAYINLANAMAZ.

- **Geçiş 1 (`pip install -e .` yalnız).** conftest importları çöktü
  (`trio`, `responses`, `pyparsing` yok). Betiğim çıkış kodu ≠ 0'ı "test
  beklendiği gibi düştü" saydı. Yanlış: test düşmedi, **toplama** çöktü.
  Geçiş 1'in dört "tam temiz"i GEÇERSİZDİR.
- **Geçiş 2 (test ekstraları eklendi).** Toplama düzeldi ama bu sefer F2P
  dosyalarının dalda hiç olmadığı görüldü — §3'teki mekanizma. Geçiş 2 de
  F2P hakkında bir şey söyleyemez.
- **Geçiş 3 (doğru yöntem).** F2P dosyaları `origin/main`'den geri konur,
  eksik test modülleri adıyla kurulur, sonra ölçülür. Aşağıdaki tablo
  yalnız geçiş 3'ündür.

---

## 5. SONUÇ TABLOSU (geçiş 3 — geçerli olan tek geçiş)

Yöntem: dal klonlandı → venv → `pip install -e .` + test ekstraları → eksik test
modülü adıyla kuruldu → F2P dosyaları `origin/main`'den geri kondu → F2P ve P2P
koşuldu. "Temiz" = kurulum oldu **VE** F2P bozuk kodda düştü (bug gerçek)
**VE** P2P bozuk kodda geçti (zemin sağlam).

| # | instance | kurulum | F2P (düşmeli) | P2P (geçmeli) | temiz? |
|---|---|---|---|---|---|
| 1 | `oauthlib__oauthlib.1fd52536.combine_file__09vlzwgc` | OK | düştü ✓ | geçti ✓ | **EVET** |
| 2 | `joke2k__faker.8b401a7d.combine_module__5edhgqcy` | OK | düştü ✓ | geçti ✓ | **EVET** |
| 3 | `kurtmckee__feedparser.cad965a3.combine_module__bd6dsmkp` | OK | düştü ✓ | geçti ✓ | **EVET** |
| 4 | `pylint-dev__astroid.b114f6b5.func_pm_ctrl_shuffle__b40xxf3u` | OK | düştü ✓ | geçti ✓ | **EVET** |
| 5 | `conan-io__conan.86f29e13.pr_12165` | OK | düştü ✓ | geçti ✓ | **EVET** |
| 6 | `pydicom__pydicom.7d361b3d.func_pm_remove_cond__c4ctdv6a` | OK | düştü ✓ | geçti ✓ | **EVET** |
| 7 | `HIPS__autograd.ac044f0d.pr_579` | OK | düştü ✓ | geçti ✓ | **EVET** |
| 8 | `pallets__jinja.ada0a9a6.func_pm_ctrl_shuffle__047pa4yh` | OK | **GEÇTİ ✗** | geçti | hayır |
| 9 | `python-openxml__python-docx.0cf6d71f.func_basic__1uvp2npv` | OK | toplanamadı | — | hayır |
| 10 | `pydantic__pydantic.acb0f10f.pr_10412` | **ÇÖKTÜ** | — | — | hayır |

### SAYI: 10 denendi, **7 tam temiz**.

Operatörün eşiği 4'tü ("4'ten azı kuruluyorsa DUR ve operatöre dön").
**7 ≥ 4 — durma şartı doğmadı, koşu yolu açık.** Duvar sanılan şey duvar değil;
operatörün dördüncü yolu bu noktada ölçümle doğrulandı.

### Üç temiz-olmayanın sebebi ayrı ayrı ölçüldü

- **jinja — bug ÜREMİYOR.** Bozuk dalda F2P testlerinin ikisi de GEÇTİ. Bu
  instance'ın enjekte edilmiş hatası, kendi F2P testleriyle yakalanmıyor.
  Böyle bir görev koşuya alınırsa iki kol da "çözdü" görünür ve sayı şişer.
  **Koşuya alınamaz.** Aynı repodaki diğer ~950 dal ayrı ayrı denenebilir;
  bu bir repo reddi değil, bir instance reddidir.
- **python-docx — sürüm çakışması, duvar değil.** Otomatik kurduğum `pyparsing`
  çok yeni: `PyparsingDeprecationWarning: 'delimitedList' deprecated` hataya
  dönüşüyor ve `tests/unitutil/cxml.py` import edilemiyor. Reponun kendi
  sabitlemesiyle (`pyparsing<3.1`) düzelmesi beklenir — bu turda DENENMEDİ.
- **pydantic — GERÇEK derlenen-bağımlılık duvarı.** `Failed building wheel for
  pydantic-core` (Rust). Docker'sız yerel venv yolunun tek gerçek sınırı bu
  sınıf: Rust/C uzantısı kaynaktan derlenen repolar. 10'da 1.

### Tarama ortamının bir kusuru — sonucu iyimser DEĞİL, kötümser yapar

venv'ler **Python 3.14.6** ile kuruldu; bu repoların çoğu o kadar yeni bir
Python'ı hedeflemiyor. python-docx'in düşmesi buna bağlı. Yani 7/10 bir
ALT sınırdır; sabitlenmiş bir Python ile daha yükseği beklenir. Bu yine de
ölçülmedi ve iddia edilmiyor.

---

## 6. Ölçülen diğer kalemler (SIRAYA listesi, tur 12 CEVAP)

**(1) `claude -p` token alan adları — çalıştırılıp GÖRÜLDÜ, varsayılmadı.**
`--output-format stream-json --verbose` çıktısının son `{"type":"result"}`
olayında `usage` bloğu: `input_tokens`, `output_tokens`,
`cache_creation_input_tokens`, `cache_read_input_tokens`; ayrıca kardeş alan
`total_cost_usd`. ON-KAYIT §4'te `tokens = input_tokens + output_tokens`
olarak donduruldu.

**(2) Ayna repoların klonlanabilirliği** — 10/10, §1'de.

**(3) HF datasetinde F2P/P2P** — MEVCUT. Örnek satır
`oauthlib__oauthlib.1fd52536.combine_file__09vlzwgc`: alanlar
`['instance_id','patch','FAIL_TO_PASS','PASS_TO_PASS','image_name','repo','problem_statement']`,
F2P 18 test, P2P 655 test.

**(4) `interventions` tanımı** — ON-KAYIT §4'te koşudan ÖNCE donduruldu
(headless oturumun anormal sonlanması = 1, normal bitiş = 0), sonradan değil.

---

## 7. NOT VERIFIED — bu turda ölçülmeyenler

- Hiçbir **ajan koşusu** yapılmadı. Bu tur yalnız zemini ölçtü; A/B kolları
  koşulmadı, JSONL yazılmadı, GOAL 5/6/7 KIRMIZI kalıyor.
- `.git` silme + egress kapatma adımları **uygulanmadı**, yalnız gerekliliği
  ölçüldü. 4d KIRMIZI kalıyor.
- Ölçüm bu macOS arm64 makinesinde yapıldı, **temiz container'da değil**.
  Repoların Linux/amd64'te de aynı davranıp davranmadığı bilinmiyor.
- Repo başına **tek** instance denendi. Aynı repodaki diğer ~950 dalın da
  temiz kurulduğu ÖLÇÜLMEDİ, varsayılıyor — koşuya girecek her instance
  koşudan önce ayrıca doğrulanmalı.
- P2P örneklemi satır başına **ilk 2 test**tir, tam liste (655–5437 test)
  koşulmadı. Zemin "bu iki test için" sağlam; tamamı için değil.
- **2b latansı bu turda ÖLÇÜLMEDİ ve ölçülemezdi**: makine yük altındaydı
  (uptime 8.60 / 6.01 / 5.24, kaynağı bu tarama değil — AppleSpell,
  WindowServer, başka oturumlar). Yük altında alınan latans sayısı geçersiz
  olurdu. Yetim `while :` yük süreci ARANDI ve YOKTU (yeni B1.9 kuralı).
