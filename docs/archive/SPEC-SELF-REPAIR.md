# rabadon kendi kurallarını tamir eder

Damla, 1 Ağustos: *"kendini geliştirmesi lazım. hatalarına göre hep aynı şeyle devam edemeyiz."*

Bugünkü döngü ürün değil, insan. Kapı haksız reddi deftere yazıyor, biri okuyor, biri etiketliyor, biri kuralı düzeltiyor. O biri olmazsa alet hiçbir şey öğrenmiyor.

Oysa döngü zaten motorda var. `rabadon repair` başkasının kodu için şunu yapıyor: kırığı yakala, izole kopyada bir öneri üret, hash-kilitli testle doğrula, ancak kanıtlanırsa tut. Aynı hattı kendi kurallarına çevirmek yeni bir mimari değil, var olanı kendine döndürmek.

Eşleme birebir oturuyor.

| tamir hattı | kural hattı |
|---|---|
| kırık kaynak dosyası | haksız reddeden kural |
| projenin kendi süiti | `native/precision_fixture.jsonl` |
| süit yeşile döndü mü | hassasiyet yükseldi mi |
| test dosyaları hash kilitli | fixture hash kilitli |
| yeşili satın alan öneri reddedilir | recall düşüren öneri reddedilir |

## Kabul şartı, tartışmasız

Bir kural önerisi ancak üçü birden olursa tutulur.

Hassasiyet **yükselecek**. `missed` **0 kalacak**, yani hiçbir gerçek tehlike geçmeyecek. Ve `native/precision_fixture.jsonl` **bayt bayt aynı kalacak**, çünkü fixture Damla'nın gerçek oturumlarından geldi ve kuralı geçirmek için testi düzenlemek, ürünün reddettiği şeyin ta kendisi. Fixture'ın hash'i öneriden önce ve sonra alınır, oynadıysa öneri `REPAIR_FAIL why=fixture-tamper` ile reddedilir ve sayaç kıpırdamaz.

## Nereden başlar

Defterdeki `WOULD_BLOCK` olayları kurala göre gruplanır. Bugün ölçülen tablo şu: 20 reddin 9'u haksız, ve dokuzunun dokuzu da tek bir kuraldan geliyor. Bir kural haksız redlerin çoğunu tek başına üretiyorsa aday odur, çünkü tek bir düzeltme dokuz olayı birden kapatır.

Sonra öneri üretilir, ve önerinin biçimi dar tutulur. Kuralı silmek serbest değil; kural bir yol hakkındaysa metin eşleşmesi yerine çözümlenmiş yol kullanması önerilebilir, muafiyet daraltılabilir, ya da yanlış tarafta eşleşen desen düzeltilebilir. Kuralı kaldırmak recall'ü düşürür ve kabul şartında zaten ölür.

## Neden bu bir özellik, cila değil

Ölçülmüş gerçek: bugün fixture'daki 34 vakanın hepsi tek bir kişinin repolarından ve hassasiyet %55. Bir yabancı kendi repolarında bu aleti açtığında kendi haksız redlerini yaşayacak, ve o redler bizim fixture'ımızda yok. Kural tamiri olmadan o yabancının tek seçeneği aleti kapatmak. Kural tamiri varsa alet onun defterinden öğrenip kendi kuralını düzeltmeyi önerir, ve düzeltmenin işe yaradığını kendi kilidiyle ispatlar.

Satılan cümle de burada değişiyor. "Ajanı denetler" değil, **"kendi haksız kararlarını bulur, düzeltmesini önerir, ve ispatlamadan kabul etmez."**

## Sıra

Bu iş `precision_test.sh` 90 tabanını geçtikten sonra başlar, önce değil. Sebebi ölçü: bugünkü 9 yanlış pozitif tek bir kuraldan geliyor ve elle düzeltilecek kadar dar. Kendi kendini tamir eden bir hat, düzeltilecek şey çeşitlendiğinde değerli olur, ve o çeşitlilik yabancı repolarda çalışıldıkça gelecek.
