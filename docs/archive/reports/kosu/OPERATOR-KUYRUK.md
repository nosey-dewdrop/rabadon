# OPERATÖR KUYRUĞU — koşu 4

Bu dosya koşuyu BLOKE ETMEZ (KOSU-RABADON-4 §3.11). Cevap gelmezse
VARSAYILAN yürür. Cevap vermek istersen: ilgili satırın altına
`CEVAP: <a|b|c>` yaz, dosyanın en soruna tek başına `ONAY` satırı koy.
Cevap SON KULLANMA'dan sonra gelirse ölçüm geri alınmaz; fark bir sonraki
fazın kartı olur (§3.11/3).

Teknik soru buraya DÜŞMEZ (§7.5). Buradaki her satır bir ürün/yayın kararıdır.

---

## K1 · 2b latans kırmızısı nasıl kapanacak?

- KARAR GEREKEN: bu makinede prensip olarak kanıtlanamayan bir ölçüm R7'yi
  bloke etmeye devam etsin mi?
- SEÇENEKLER:
  - (a) CI/konteyner temiz referans ortam kurulur, ölçüm orada alınır.
  - (b) 1000 µs tavanı bu makinenin gerçeğine çekilir.
  - (c) 2b R7'den koparılır, CI artefaktına bağlanır ("CI'da yeşil değilse
    geçmez"); R7'nin geri kalanı bloke edilmez.
- YAN BİLGİ (ölçülmüş, koşu 2 tur 22): tavan 1000 µs · 8 gözlem · min
  1218,3 µs · her gözlem üst sınır olduğu için tek geçerli çıkarım
  "temiz ≤ 1218,3 µs" ve bu 1000'i DIŞLAMAZ.
- **VARSAYILAN: (c)**
- ETKİLER: F2, F4
- SON KULLANMA: F2 açılışı

## K2 · 6e/7b sayaç doğrulaması nasıl yeşile döner?

- KARAR GEREKEN: `MIN_HISTORY=3` yüzünden tek oturumluk koşuda üretilmeyen
  `estimated_saved` nasıl doğrulanacak?
- SEÇENEKLER:
  - (a) fixture zinciri `MIN_HISTORY=1` ile kurar; ürün kodu DEĞİŞMEZ.
  - (b) "veri yok" uyarısını yeşil saymak — bu bir zayıflatmadır, teklif
    edilmiyor (§7.1).
  - (c) paralı çok-oturumlu koşu.
- **VARSAYILAN: (a)**
- ETKİLER: F3, F4
- SON KULLANMA: F3 açılışı

## K3 · "yeşil main" ne demek?

- KARAR GEREKEN: disclosure kapısı yayın kapısı olarak kalsın mı?
- SEÇENEKLER:
  - (a) `DISCLOSURE.md`'deki 41 ismin sınıflaması uygulanır (girecek girer,
    girmeyecek `site/` artefaktlarından çıkar); kapı yayın kapısı olarak KALIR.
  - (b) disclosure kapısı yayın kapısı olmaktan çıkarılır.
- YAN BİLGİ (ölçüm `ca1ea4e`): 53 isim, 12'si listede, 41'i liste dışı;
  kural tam eşleşme + fail-closed.
- **VARSAYILAN: (a)** — (b) kapıyı gevşeterek geçmektir (§7.1).
- ETKİLER: F6, F7
- SON KULLANMA: F6 açılışı

## K4 · `npm publish` ve tag

- KARAR GEREKEN: paket ilk kez npm'e çıksın mı, ne zaman?
- **VARSAYILAN YOK — PARK** (§3.11/4, geri dönüşsüz dış adım).
- Hazırlık F5/F6'da biter; `DURUM.md`'ye "R8 HAZIR" satırı düşer; koşu F8'e
  geçer, beklemez.
- ETKİLER: F7
- SON KULLANMA: yok (PARK'ta bekler)

## K5 · marketplace PR + Show HN

- KARAR GEREKEN: dışarıya gönderim yapılsın mı?
- **VARSAYILAN YOK — PARK.** F10 malzemeyi hazırlar; gönderim operatörün.
- ETKİLER: F10
- SON KULLANMA: yok (PARK'ta bekler)

## K6 · fiyat

- KARAR GEREKEN: M4'te fiyat yazılsın mı?
- **VARSAYILAN YOK.** KOSU-RABADON.md M4'ün kendi hükmü geçerli: M4 fiyat
  yazılmadan da koşar; üç orandan ikisi fiyattan bağımsız ölçülür, üçüncüsü
  raporda "bilinen boşluk" olarak durur.
- ETKİLER: M4 / F10
- SON KULLANMA: yok

---
