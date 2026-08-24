# tur 19 — operatör CEVAP'larının uygulanması

Girdi: `reports/kosu/18.operator.md` (iki CEVAP + ONAY).
Kural: B1. Mühür: `reports/R7/accept.sh` ve `KOSU-RABADON-2.md` **değiştirilmedi**.

## 1. Önce olgu doğrulaması (uygulamadan ÖNCE)

CEVAP 2 bir olgu düzeltmesine dayanıyordu ("şart accept.sh'ta değil,
ab_run.sh'ta"). Birinci elden doğrulandı, **DOĞRU**:

| komut | sonuç |
|---|---|
| `grep -n 'SIGNAL\|INJECT' reports/R7/accept.sh` | hiçbir eşleşme |
| `grep -n 'SIGNAL\|INJECT' reports/R7/ab_run.sh` | 26,27,29,253,270,342,347,557… |
| `grep -c estimated_saved reports/R7/accept.sh` | 2 |
| `grep -c estimated_saved reports/R7/ab_run.sh` | **0** |
| `sed -n '63p' native/counter.h` | `MIN_HISTORY = 3` |

Şart mühürlü betikte değil koşucuda; §A1 ihlal edilmeden düzeltilebilir.

## 2. CEVAP 2 — SIGNAL/INJECT artık kapı değil, ÖLÇÜLEN DEĞİŞKEN

`reports/R7/ab_run.sh`:
- Eleme şartı (`sigyeni <= 0` → `continue`) **KALDIRILDI**. Bağlama kabulü
  artık yalnız **native `ng-` satırı + COUNTER**.
- `ledger_sinyal_sayisi` ikiye ayrıldı: `ledger_signal_sayisi`,
  `ledger_inject_sayisi`. JSONL'e ayrı alan: `signals`, `injects`.
  (`ledger_signal_inject` geriye dönük uyum için toplam olarak duruyor.)
- `estimated_saved` kablosu çekildi: o pipe etiketinin **son COUNTER**
  satırından `saved_usd`; yoksa **`null`** — uydurma sıfır DEĞİL.
- SIGNAL/INJECT üretmeyen koşu artık **geçerli**, yalnız not düşülüyor.

Neden: gerçek dogfooding ledger'ında 186 oturumun 8'i (%4,3) SIGNAL/INJECT
üretmiş. Şart kalsaydı ödenmiş B koşularının **%95,7'si atılır** ve kalan küme
"rabadon'un konuştuğu" oturumlara yanlı olurdu — böyle bir örneklemden çıkan
fark ürün lehine ÜRETİLMİŞ sayıdır (Yasa 7).

**Birim testi (sentetik ledger, gerçek fonksiyonlarla):**

| durum | `saved_usd` | signals | injects | JSONL |
|---|---|---|---|---|
| MIN_HISTORY karşılanmamış | `null` | 1 | 2 | `"estimated_saved": null` |
| gerçek değer | `0.0417` | 0 | 0 | `"estimated_saved": 0.0417` |
| rabadon ateşlendi, konuşmadı | `null` | 0 | 0 | satır **YAZILIYOR** (eskiden atılırdı) |

`null` ile `0` ayrımı korunuyor: `0` "tasarruf olmadı", `null` "sayı
hesaplanamadı" demek ve `accept.sh` ikisini farklı okuyor.

## 3. CEVAP 1 — 2b yük kapısı (mühür dışı sarmalayıcı)

`reports/R7/olc_2b.sh` (YENİ). `accept.sh`'ı **çağırır, değiştirmez**.
1 dk yük **3 ardışık örnekte < 2,0** olana kadar bekler (60 sn ara, tavan 90 dk).
- Tavan dolarsa: 2b **KOŞULMAZ**, `YUK-2B.md`'ye "ölçülemedi + yük bağlamı"
  yazılır, **kırmızı kalır**, sayı uydurulmaz.
- Kapı açılırsa: ölçümün yanına 1/5/15 yük, en çok CPU yiyen 3 süreç ve
  B1.9 artık-süreç kontrolü yazılır.

### Sarmalayıcıda bulunan ve düzeltilen iki gerçek hata

1. **Locale tuzağı (sessizce YANLIŞ yönde).** Makine tr_TR: `sysctl` yükü
   virgüllü basıyor. Sinsi olanı **awk da locale'e uyuyor** —
   `echo 7.81 | awk '{print $1+0}'` → **7**. Yalnız `sysctl`'i C'ye almak
   yetmiyordu; kapı ondalığı düşürüp **gevşek** yanılırdı. `LC_ALL=C` betiğin
   tamamına export edildi; doğrulandı, awk artık `11.2` okuyor.
2. **Yarım kabul çıktısı.** `accept.sh | tee accept.out` doğrudan yazıyordu:
   dış `timeout` accept.sh ortasında dolarsa `accept.out` yarım kalır ve
   "23 yeşil / 3 kırmızı" gibi okunur. Artık geçici dosyaya yazılıp yalnız
   `R7 acceptance:` kapanış satırı görülünce taşınıyor.

## 4. ÖNEMLİ — CEVAP 1'in premisi ARTIK GEÇERLİ DEĞİL

Tur 18 CEVAP 1'in gerekçesi: *"ctest hâlâ canlı (pid 65243), yük 2.89→3.14 ve
DÜŞÜYOR; makine kendiliğinden sakinleşiyor, bir şeyi öldürmeye gerek yok."*

Bu turda ölçüldü:

    pgrep -fl ctest               -> BOŞ            (ctest kendiliğinden ÖLDÜ)
    LC_ALL=C sysctl -n vm.loadavg -> 3.44 … 11.20   (yük DÜŞMEDİ, YÜKSELDİ)
    ps -Ao pid,pcpu,comm -r       -> Google Chrome Helper (GPU) %453,5

Yani: **engel artık stitchu'nun ctest'i değil.** O bitti. Yeni ve baskın kaynak
**operatörün kendi Chrome'unun GPU helper'ı, tek başına ~4,5 çekirdek.**

Fark önemli: ctest **biten** bir toplu işti, beklemek işe yarardı. Chrome
**etkileşimli ve sürekli** — "bekle, sakinleşir" stratejisi bu kaynak için
çalışmaz. 8 çekirdekli makinede yükün < 2,0'a inmesi, Chrome GPU helper
sakinleşmeden **yapısal olarak mümkün değil.**

Bu, operatörün tek hamlede çözebileceği bir şey (ctest'in aksine kendi
uygulaması) — ama kararı ona ait, bu tur hiçbir şeyi öldürmedi.

### Kapı koşuldu, AÇILMADI — 2b ölçülmedi

Kayıt: `reports/R7/YUK-2B.md` (tur 19 bölümü) + `YUK-2B-BEKLEME.log`.

    19:34  11.20   19:36   7.03   19:38  31.86   19:40  18.33
    19:35   7.13   19:37  18.15   19:39  19.26

Tek temiz örnek yok; yük 7,03'ten 31,86'ya **çıktı**. Kaynaklar: Chrome GPU
helper %463,5 (~4,6 çekirdek) ve stitchu `surface-pattern` %96,5.

**Dürüstlük notu:** 90 dk tavan DOLMADI; kapı 6 dk sonra bu oturum tarafından
durduruldu. Gerekçe: koşu boyunca kaydedilmiş **bütün** yük değerlerinin en
düşüğü **2,4** — `< 2,0` eşiği bu makinede bir kez bile gözlenmedi. Kapı 90 dk
değil, kayıtlı geçmişin tamamında açılmazdı; 84 dk daha beklemek ölçüm değil
yalnız tur yakardı. Sapma gizlenmiyor, karar operatörün.

**2b KIRMIZI KALIR. Sayı alınmadı, sayı uydurulmadı.**

## 5. Kabul durumu

`accept.sh` bu turda **KOŞULMADI** (yük kapısı açılmadı; kirli ölçüm delil
değil, B1.9). Devralınan sayı **23 yeşil / 3 kırmızı** (2b, 6e, 7b) —
kod değişmediği için değişmesi beklenmez, ama bu bir **çıkarım, ölçüm değil**.

6e/7b'nin kırmızı kalması **BEKLENEN** sonuçtur ve operatör CEVAP 2 bunu
açıkça böyle sabitledi: `MIN_HISTORY=3`, her görev tek oturum → `median_n:0`
→ `saved_usd` her hâlükârda `null`. Bu bir **ürün gerçeği**, harness hatası
değil: **rabadon tek oturumluk kullanımda tasarruf sayısı üretemiyor.**
Satılabilir bir kusur tespitidir, gizlenecek bir şey değil.

## 6. DOĞRULANMADI / yapılmadı

- `ab_run.sh` değişiklikleri **canlı koşuda denenmedi** — yalnız `bash -n` ve
  sentetik ledger birim testi. **Paralı koşu bu turda başlatılmadı.**
- `accept.sh`'ın 25 kaleminin hiçbiri bu turda yeniden ölçülmedi.
- Proje temiz bir kutuda (CLAUDE.md referans ortamı) **hiç** çalıştırılmadı.
## 7. YENİ CHALLENGE — `reports/R7/CHALLENGE-4.md` (AÇIK, insan onayı bekliyor)

Kablo çekilince 6e'nin erişilebilir hâli ilk kez görüldü ve bir kabul-kapısı
kusuru çıktı: **6e bir DOLAR değerini bir TOKEN farkıyla karşılaştırıyor.**
`est` = sayacın `saved_usd`'si (`counter.h:299`, dolar); `real` =
`tok_A - tok_B` (token). Ölçüldü — sapma dolar değeri ne olursa olsun ~%100:

    saved_usd=0.0001 -> %100.0     saved_usd=1.0 -> %101.1
    saved_usd=0.05   -> %100.1     saved_usd=5.0 -> %105.6

**6e'de eşik YOK** (`accept.sh:481`): `NODIFF` dışında her sapmada **yeşil**
basar. Yani "sayaç doğrulandı" satırı %100 sapmayla yeşil olurdu — kapının
ölçtüğünü iddia ettiği şeyi ölçmemesi, bu projenin engellemek için var olduğu
şeyin ta kendisi. 7b'de eşik var (%50), o kırmızı olurdu — güvenli yön, ama
gerekçe yanlış atfedilirdi ("sayaç sapıyor" ≠ "birim yanlış").

**Bugün tetiklenmiyor:** `MIN_HISTORY=3` yüzünden `estimated_saved` zaten
`null`, 6e "field yok" diye kırmızı. Kusur `MIN_HISTORY` düşerse ya da
çok-oturumlu koşuya geçilirse canlanır. Önerilen düzeltme (b): `real`'i
token farkı yerine **maliyet farkı** yap — `total_cost_usd` her iki kol için
JSONL'de **zaten var** (doğrulandı, 8 satırın 8'inde). Artı 6e'ye 7b'nin
eşiği. `accept.sh` mühürlü → **DEĞİŞTİRİLMEDİ**, challenge açıldı, adım
kırmızı sayılıyor.

---

## Oturum ritüeli

**DONE**
- Tur 18 CEVAP 2 uygulandı: SIGNAL/INJECT eleme şartı `ab_run.sh`'tan kaldırıldı
  (bağlama kabulü = native `ng-` + COUNTER); `signals`/`injects` ayrı JSONL
  alanı; `estimated_saved` kablosu çekildi (`null` korunur, uydurma sıfır yok).
  Kanıt: `bash -n reports/R7/ab_run.sh`; `sed -n '603,638p' ab_run.sh > w.py` ile
  gerçek yazıcı çıkarılıp üç senaryoda koşuldu (A / B-sessiz / B-konuşkan) →
  `null`, `null`, `0.0417`; B-sessiz satırı artık **yazılıyor** (eskiden atılırdı).
  `sed -n '435,459p' accept.sh` ile gerçek 6e okuyucusu aynı JSONL'de koşuldu.
- Tur 18 CEVAP 1 uygulandı: `reports/R7/olc_2b.sh` yazıldı (mühür dışı, accept.sh'ı
  çağırır/değiştirmez). Kanıt: `bash -n reports/R7/olc_2b.sh`; kapı mantığı C
  locale'de 6 değerle test edildi.
- Sarmalayıcıda iki gerçek hata bulunup düzeltildi: (1) awk'ın tr_TR locale'inde
  `7.81`'i `7` okuması — `LC_ALL=C` betiğin tamamına; (2) `tee accept.out`'un
  timeout'ta yarım kabul çıktısı bırakması — atomik `mv`, kapanış satırı şartlı.
- 2b ölçülmedi ve bu kayda geçti (`YUK-2B.md`): kapı açılmadı, sayı uydurulmadı.
- `CHALLENGE-4.md` açıldı: 6e dolar↔token karşılaştırıyor, üstelik eşiksiz.
- Commit'ler: `760c63e`, `5db1804`, `3f1e087`, `CHALLENGE-4`, `YUK-2B`. Hepsi push'landı.

**NOT VERIFIED**
- `ab_run.sh` değişiklikleri **canlı koşuda denenmedi**; yalnız `bash -n` +
  sentetik ledger + çıkarılmış yazıcı. **Paralı koşu bu turda başlatılmadı.**
- `accept.sh`'ın 25 kaleminin **hiçbiri** bu turda koşulmadı. "23 yeşil / 3 kırmızı"
  tur 17'den **devralınmış** bir sayıdır — çıkarım, ölçüm değil.
- 2b'nin gerçek değeri bilinmiyor (dört sayı da yük altında alınmış).
- Proje temiz konteynerde (CLAUDE.md referans ortamı) **hiç** çalıştırılmadı.
- `ledger_saved_usd` gerçek bir rabadon spool'una karşı denenmedi; `sed`
  ayıklaması sentetik COUNTER satırlarında doğrulandı.
- CHALLENGE-4'ün (b) önerisi (maliyet farkı) **uygulanmadı**, yalnız
  `total_cost_usd`'nin her iki kolda var olduğu doğrulandı.

**NEXT**
Operatör kararı: 2b nasıl ölçülecek — (a) makineyi sustur, (b) eşiği gevşet,
(c) temiz konteyner (bu oturumun önerisi: c) — ve CHALLENGE-4'ün kabulü.
İkisi de mühre/geri dönüşsüz işe dokunduğu için B4 kategorisinde.
