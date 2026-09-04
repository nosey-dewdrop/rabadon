# tur 20 — CHALLENGE-4 kapatıldı, 2b örnekleyicisi yazıldı

Girdi: `reports/kosu/19.operator.md` (iki CEVAP + ONAY).
Kural: B1. Mühür: `KOSU-RABADON-2.md` **değiştirilmedi**. `accept.sh`
operatör izniyle, DAR KAPSAMLI ve KENDİ COMMIT'İNDE değiştirildi.

**Kabul: 23 yeşil / 3 kırmızı — değişmedi.** Kırmızılar: 2b, 6e, 7b.

---

## 1. Sıra ve disiplin (CEVAP 2'nin şartı)

Operatör "değişiklikten ÖNCE mevcut 23/3 kaydedilir, SONRA yeniden koşulur ve
fark raporlanır" dedi. Aynen bu sırayla yapıldı:

| adım | komut | sonuç |
|---|---|---|
| 1. ÖNCE | `bash reports/R7/accept.sh > reports/R7/accept.ONCE.out` | **23 yeşil / 3 kırmızı**, 2b medyan 2506,9 µs, yük 12,46 |
| 2. commit | `dd2a652` — yalnız `reports/R7/accept.sh`, kod yok, koşu yok | — |
| 3. SONRA | `bash reports/R7/accept.sh > reports/R7/accept.SONRA.out` | **23 yeşil / 3 kırmızı**, 2b medyan 1918,8 µs, yük 9,63 |

## 2. CHALLENGE-4 — önce doğrulama, sonra düzeltme

İddiayı kabul etmeden önce eski blok `git show HEAD:reports/R7/accept.sh`'ten
**aynen çıkarılıp** sentetik veriyle koşuldu. Çıktı:

    PASS  6e counter validation: estimate 5.0000 vs real difference 2399.0,
          deviation 99.8%

5 dolarlık bir tasarruf iddiası 2399 token'lık bir farkla karşılaştırıldı ve
**%99,8 sapmada YEŞİL bastı.** Blokta eşik yoktu; yalnız veri eksikse ya da
fark tam sıfırsa kırmızıya dönebiliyordu. CHALLENGE-4 doğru.

### İzin verilen iki kalem, aynen

1. **Birimler eşitlendi.** Sağ taraf artık `cost_A - cost_B`: kol başına
   `total_cost_usd` toplamı. Veri var — `ab_run.jsonl`'in **8 satırının
   8'inde de**, iki kolda da. Token farkı 6e'den çıktı.
2. **Eşik eklendi.** `|DEV| > 50` → FAIL, 7b ile aynı sınır.

**Totoloji değil.** `est` rabadon'un KENDİ sayacının iddiası (`saved_usd`);
`real` harness'ın CLI stream'inden ÖLÇTÜĞÜ maliyet farkı. İki ayrı kaynak,
dolayısıyla 6e gerçek bir soru soruyor: *rabadon'un tasarruf iddiası gerçekle
uyuşuyor mu?*

### Düzeltilmiş 6e KIRMIZIYA DÖNEBİLİYOR — kanıt

Blok dosyadan aynen çıkarılıp dört durumla koşuldu:

| durum | sonuç |
|---|---|
| iddia $0,30 / ölçülen $0,30 | **PASS**, sapma %0,0 |
| iddia $5,00 / ölçülen $0,30 | **FAIL**, sapma %1566,7 (>%50) |
| `est` yok (bugünkü gerçek veri) | **FAIL** "counter validation impossible" |
| maliyet farkı sıfır | **FAIL** "NODIFF" |

### İzin dışına taşan tek kalem — operatöre BİLDİRİLİYOR

7b'nin hata satırı `"...from the real token difference"` diyordu ve DEV'i 6e
ile PAYLAŞIYOR. Birim değişince bu cümle YANLIŞ bir şey söyler hâle geldi;
`"from the measured cost difference"` olarak düzeltildi. **Yalnız metin;
7b'nin karar mantığına dokunulmadı, sonucu değişmedi.** Operatör bunu fazla
bulursa tek satırlık geri alma.

### Bağlanan beklenti gerçekleşti

Operatör "6e null yüzünden kırmızı kalacak, bu BEKLENEN ve DÜRÜST sonuçtur"
diye bağlamıştı. Aynen öyle oldu: `estimated_saved` `MIN_HISTORY=3` yüzünden
8 satırın hepsinde `null`, 6e "estimated_saved yok" dalından kırmızı kaldı.
**Düzeltme 6e'yi yeşile çekmedi; ANLAMLI hale getirdi.** `MIN_HISTORY`'ye
dokunulmadı, çok oturumlu sahte birikim kurulmadı.

### Önce/sonra farkının tamamı

    < FAIL  6e ... or no token totals
    > FAIL  6e ... or no per-arm total_cost_usd
    < FAIL  2b the gate's median is 2506.9 us      (yuk 12,46)
    > FAIL  2b the gate's median is 1918.8 us      (yuk  9,63)
    < PASS  2c the residual length dependence ... (4.56%)
    > PASS  2c the residual length dependence ... (3.35%)

6e dışında hiçbir GOAL'ün YARGISI değişmedi. 2b/2c'nin sayıları değişti çünkü
yük değişti — bu değişikliğin değil, makinenin eseri.

## 3. CEVAP 1 — `olc_2b.sh` artık kapı değil, ÖRNEKLEYİCİ

Eski kapı 1 dk yükün 3 ardışık örnekte `< 2,0` inmesini bekliyordu; tur 19 bu
makinede kayıtlı en düşük yükü **2,4** olarak ölçtü — kapı hiçbir zaman
açılamazdı. Operatör eşiği gevşetmeyi de reddetti: gözlemden değil rahatlıktan
seçilmiş ikinci bir keyfi sayı, ilk hatanın tekrarı olurdu.

**Yeni dayanak fizik:** çekişme altında ölçülen latans, çekişmesiz gerçek
latanstan HER ZAMAN büyük ya da eşittir — yük yalnız EKLER. Öyleyse tekrarlı
ölçümlerin EN DÜŞÜĞÜ, temiz değerin en iyi ALT SINIR tahminidir.

Betik `ORNEK=5` kez, `ARA=1200` sn arayla `accept.sh` koşar; her sayının
yanına 1/5/15 yük, en çok CPU yiyen 3 süreç ve B1.9 artık-süreç kontrolü
yazar. `accept.sh`'ın 2b ÖLÇÜTÜ (medyan < 1000 µs) DEĞİŞMEDİ.

**Sahte yeşil üretemez** — iki durumu ayırır:
- en düşük gözlem ≥ 1000 µs → **2b KESİN KIRMIZI** (exit 1). Makine bahanesi
  biter: daha temiz bir ölçüm matematiksel olarak daha düşük olamaz.
- en düşük gözlem < 1000 µs → **2b AÇIK, YEŞİL SAYILMAZ** (exit 2). Ölçüt
  medyan üzerindedir ve bu medyan kirlidir; sayı "en iyi gözlenen koşul"
  etiketiyle raporlanır, temiz ortamda yeniden ölçülmesi gerekir.
- hiç geçerli ölçüm yok → **ÖLÇÜLEMEDİ** (exit 3), sayı uydurulmaz.

### Sarmalayıcıda bulunan ve düzeltilen tuzak

20 dk'lık tek bir `sleep`, sürücünün stall watchdog'unun eşiğine
(`kos.sh STALL_TIMEOUT=1200`) TAM oturuyor — örnekleyici kendi bekleme
süresinde öldürülebilirdi. Bekleme 60 sn'lik parçalara bölündü ve her parçada
log'a satır düşüyor: watchdog'un iki nabzı (çıktı büyümesi + dosya aktivitesi)
da besleniyor.

### Doğrulama (stub `accept.sh` ile, `/tmp/rb2bsmoke`)

| girdi | hüküm | exit |
|---|---|---|
| medyanlar 2506,9 ve 1918,8 | KESİN KIRMIZI, en düşük **1918,8** | 1 |
| medyan 950,0 | AÇIK — yeşil sayılmaz | 2 |
| medyan satırı hiç yok | ÖLÇÜLEMEDİ, sayı uydurulmadı | 3 |
| biri geçersiz biri geçerli | geçerli olana hükmeder (1/2) | 2 |

En düşük seçimi SAYISAL, sözlüksel değil: 2506,9 varken 1918,8 seçildi.

## 4. 2b için bu turun kendi verisi

İki bağımsız ölçüm, aynı gün, aynı makine, farklı yük:

| yük (1 dk) | 2b medyan | 2c sapma |
|---|---|---|
| 12,46 | 2506,9 µs | %4,56 |
| 9,63 | **1918,8 µs** | %3,35 |

Yük düştü, latans düştü. Bu, CEVAP 1'in dayandığı fizik argümanının doğrudan
gözlemsel desteği. İkisi de 1000 µs tavanının çok üstünde. Bugünkü en iyi alt
sınır tahmini **1918,8 µs** — tavanın ~1,9 katı.

---

## DONE

- `dd2a652` — `accept.sh` 6e birim düzeltmesi + eşik, kendi commit'inde,
  içinde kod/koşu yok. Kanıt: yukarıdaki dört durumluk tablo.
- `1f80788` — `olc_2b.sh` örnekleyiciye dönüştürüldü. Kanıt: stub tablosu.
- Kabul, değişiklikten önce ve sonra koşuldu:
  `bash reports/R7/accept.sh` → **23 yeşil / 3 kırmızı**, iki kez.

## NOT VERIFIED

- **Örnekleyici GERÇEK `accept.sh` ile hiç koşmadı.** Yalnız stub'la
  doğrulandı. 5 örnek × 20 dk ≈ 100 dk, turun 7200 sn tavanına kabul işiyle
  birlikte sığmıyor.
- 6e'nin düzeltilmiş YEŞİL dalı gerçek veriyle hiç görülmedi — `est` her
  satırda `null` olduğu için "impossible" dalından çıkılamıyor. Yeşil dal
  yalnız sentetik veriyle görüldü.
- `ab_run.sh`'ın tur 19 değişiklikleri hâlâ CANLI/paralı koşuda denenmedi.
- Temiz makinede / konteynerde hiçbir şey denenmedi. Bu turun tüm sayıları
  yükü 9–13 arasında gezen bir makinede alındı.
- **Yeni görülen, düzeltilmeyen kusur:** `accept.sh`'ta
  `JL="$(ls "$RD"/*.jsonl | head -1)"` dizindeki üç jsonl'den alfabetik ilkini
  alıyor. Bugün doğrusunu seçiyor (`ab_run.jsonl`), ama bu şans; adı önce gelen
  yeni bir dosya kabul betiğini sessizce geçersiz veriye çevirir. Bu turun
  izni dışındaydı, DOKUNULMADI.

## NEXT

Tek iş: `ORNEK=5 ARA=1200 bash reports/R7/olc_2b.sh` — gerçek `accept.sh` ile,
turun tamamını kaplayacak şekilde. Hüküm `reports/R7/YUK-2B.md`'ye yazılır ve
2b ya KESİN KIRMIZI'ya ya AÇIK'a ayrılır.
