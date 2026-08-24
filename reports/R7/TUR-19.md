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
- **YENİ ŞÜPHE, çözülmedi:** `accept.sh:456` `estimated_saved`'i `tok_A-tok_B`
  (TOKEN farkı) ile karşılaştırıyor, ama sayacın `saved_usd`'si **DOLAR**
  (`counter.h:299`). Token farkıyla dolar karşılaştırmak sapma yüzdesini
  anlamsız kılar; **6e yeşile dönse bile sayısı şüpheli olurdu.** Düzeltmek
  mühürlü `accept.sh`'a dokunmayı gerektirir → operatör kararı, bu turun işi
  değil. Şu an 6e zaten `null` yüzünden kırmızı, dolayısıyla yanlış bir sayı
  yayınlanma riski YOK.
