# TUR 22 — operatörün tur 21 CEVAP'ları uygulandı; 2b'nin "kesin kırmızı" etiketi geri alındı

tarih: 2026-08-25
yapan: tur 22 oturumu
kabul: `bash reports/R7/accept.sh` → **23 yeşil, 3 kırmızı** (`reports/R7/accept.tur22.out`)

## Ne yapıldı

Dört commit, hepsi ayrı ve gerekçeli:

| commit | iş |
|--------|-----|
| `b37af54` | `olc_2b.sh`'ın ters hükmü düzeltildi (CEVAP 1) |
| `49e70c0` | B1.9 genişletildi: kapsam tipe değil KÖKENE göre (CEVAP 2) |
| `288d1c7` | CHALLENGE-5 kapatıldı; temiz-ortam ölçümü PARKED'e girdi |
| `10ec3f5` | B1.9 artık-süreç kontrolü kırmızıya dönebilir hâle getirildi |

**Hiçbir mühür dosyasına dokunulmadı.** `accept.sh`'ın 2b ölçütü (medyan
< 1000 µs) DEĞİŞMEDİ. Tavan 1000 µs'de duruyor — operatör (d) seçeneğini
("tavanı ölçülen değere çek") açıkça reddetti, ve bu koşuda defalarca reddedildi.

## Ölçüm — 3/3 geçerli gözlem

| örnek | 1 dk yük | medyan (µs) |
|-------|----------|-------------|
| 1     | 4.28     | 1483,0      |
| 2     | 3.54     | 1680,6      |
| 3     | 4.25     | **1381,8**  |

Betiğin hükmü: `2b BELIRSIZ — bu makinede kirmizi; temiz tavan <= 1381.8 us`.
Düzeltilmiş dal ilk kez ateşlendi; eski kod burada **"KESIN KIRMIZI"** basardı.

## Operatörün önkoşulu tutmadı — bunu saklamıyorum

Operatör daemon'ı öldürüp 2.35/1.91/1.77 ölçtü ve "**hemen** koş, bu pencere
kapanabilir" dedi. Pencere mesaj bana ulaştığında **kapanmıştı**: örnekleme
4.28'de başladı, ilk beklemede yük **11.04**'e fırladı, tur boyunca 1 dk yükü
hiç 2,84'ün altına inmedi. Yükün kaynağı daemon değil, operatörün canlı işleri
(stitchu `surface-pattern` %90,7, WebKit %62,2) — ve bunlar ölçüm için
susturulmaz (tur 19 kararı).

Ölçümü yine de aldım, çünkü **düzeltilmiş asimetri altında kirli ölçüm asla
yanıltıcı olamaz**: yalnız YEŞİL kanıtlayabilir, kırmızı kanıtlayamaz. Yani
kaybedecek bir şey yoktu; üç örnek yükün dip yaptığı ana denk gelebilirdi.
Gelmedi.

## En iyi kanıt DEĞİŞMEDİ

Sekiz gözlemin (tur 21: 5, tur 22: 3) en düşüğü hâlâ **1218,3 µs** — tur 21
örnek 5. Bu turun min'i (1381,8) ondan **daha kötü**. Yani:

    temiz_medyan  <=  1218,3 us

Bu 1000 µs'yi **dışlamaz**. Elimizdeki en dar üst sınır budur ve bu turda
daralmadı.

## Daemon hipotezi ELENDİ

"Daemon ölünce makine 2b'yi ölçebilir hâle gelir" yanlış çıktı: daemon canlıyken
alınan bir gözlem (1218,3), daemon ölüyken alınan üç gözlemin **hepsinden**
düşük. 10 saatlik daemon gerçek bir kirletici idi ama tek belirleyici değildi.

## Bu turun ölçümleri de sanılandan kirli

`pgrep -c` düzeltilince kontrol ilk kez gerçek sayı bastı: **2 canlı `ctest`
süreci**. Eski kontrol bunları tur 21'in beş ve tur 22'nin üç örneğinde de `0`
diye raporladı. Süreçler bu oturumun değil (kardeş `/rabadon` deposu), ama
sekiz gözlemin tamamı onlar canlıyken alındı. Kirliliğin büyüklüğü **ÖLÇÜLMEDİ**.

Kanıt:

    pgrep -c -f rabadon-gate   -> usage error, "0" okunur (KIRMIZIYA DÖNEMEZ)
    ps|grep|grep -c .          -> canlı süreçte 8 (döner)

## 2b'nin kapanışı — operatörün (c) şıkkı

Operatör: "Yeni min >= 1000 çıkarsa (c) uygulanır." Çıktı. Dolayısıyla 2b
**"bu makinede kırmızı; temiz tavan ≤ 1218,3 µs; referans ortam CI"** etiketiyle
kapanır. Bu bir yeşil DEĞİL ve yeşile yazılmadı — `accept.sh` hâlâ 2b'yi FAIL
sayıyor ve öyle kalması doğru.

Altı çizilecek nokta: bu worktree'de 2b'nin kırmızılığı **prensip olarak**
kanıtlanamaz. Her gözlem temiz değerin üst sınırı olduğu için burada yalnız
yeşil kanıtlanabilir. "Daha çok örnek al" bir çözüm değil — kanıt yönü yanlış.
Temiz ortam bir konfor değil, **tek kanıt yolu**.

## B1.9 tur sonu kontrolü

Yeni kural gereği soru "yetim yük süreci var mı" değil, "bu turda başlattığım
HER şey öldü mü":

    45834  timeout 3600 env ORNEK=3 ...  -> öldü
    45838  bash reports/R7/olc_2b.sh     -> öldü
    ad ile tarama (ps|grep)              -> artık YOK

## Kabul durumu

    == R7 acceptance: 23 green, 3 red
    FAIL 2b  — bu tur ele alındı, etiketi düzeltildi, temiz ortama devredildi
    FAIL 6e  — estimated_saved kablosu, PARKED
    FAIL 7b  — falsification 2 UNCHECKABLE, 6e ile aynı kök

6e ve 7b tek bir kökten geliyor ve **operatör kararı bekliyor**: kabloyu çekmek
tek başına 6e'yi kapatmıyor, çünkü sayaç `MIN_HISTORY=3` ölçülmüş zincir görmeden
`null` dönüyor ve her görev tek oturum. İkinci parça bir **koşu-şekli kararı** ve
para harcatıyor — bu yüzden yapan oturum tek başına alamaz.

## NOT VERIFIED

- `ctest` süreçlerinin sekiz gözlemi ne kadar kirlettiği ölçülmedi.
- 2b'nin temiz ortamdaki değeri ölçülmedi; ~970 µs yalnız 5 noktalı bir
  ekstrapolasyon, kanıt değil.
- Düzeltilmiş `baglam()` tam bir örnekleme turunda koşmadı; ayrı ayrı
  (`bash -n` + fonksiyonu doğrudan çalıştırma) doğrulandı.
- Temiz makinede fresh clone denenmedi.
