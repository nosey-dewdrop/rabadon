# T1 — CHALLENGE

Bir CHALLENGE, kabul testine ya da protokole dokunma yetkisi **değildir**.
Kanıtı ve önerilen diff'i insanın önüne koyar, orada durur.
Çözümü yalnızca insan onaylı, kendi commit'inde bir diff'tir.

## Bu dosyanın geçmişi — itirazın üçte biri geri çekildi

İlk hali üç kırmızının (**1a, 1c, 1e**) üçü için de "test doğru cümleyi
yakalıyor" diyordu. Ayrı oturumdaki hakem bunun yanlış olduğunu gösterdi ve
haklıydı: üçünden **1.5'i** testi de metni de tahrif etmeden dürüstçe
kapatılabilirdi. Kapatıldı. Geriye kalan itiraz aşağıdadır ve kapsamı dardır.

Geri çekilen ve metin düzeltmesiyle kapatılan iki madde:

- **1e** — kırmızıyı yakan şey "unplanned = 0" bilgisi değildi, eski
  BENCHMARK'tan devralınan tek bir retorik kuyruktu: *"and it stays on this page
  as 0 until it isn't."* Protokol o kuyruğu istemiyor; istediği yalnızca
  "planlanmamış kırılmada 0". Kuyruk iki dosyadan da silindi, bilgi kaybı sıfır.
- **1a'nın ikinci hit'i (`README.md:84`)** — düzyazıda "repairs held is 0"
  yazıyordu. BENCHMARK.md aynı olguyu "the count is 0" diye yazıyor ve deseni
  hiç tetiklemiyor; yani güvenli ifade zaten bir dosyada kullanılmıştı, diğerine
  taşınmamıştı. Hizalandı.

## Geriye kalan itiraz: 1a'nın birinci hit'i ve 1c

Tek satır hakkında: `README.md`, `rabadon usage` çıktısını gösteren fenced code
block'un içinde, stitchu'nun satırı.

```
FAIL  1a a bare "repairs held = 0" reading still remains
      README.md:  repairs held (locked):       0
FAIL  1c a numeric "repairs held" reading shows something other than 2
      README.md:  repairs held (locked):       0
```

## Çakışma

Protokol §T1 madde 4 iki şey birden istiyor:

1. "repair sayısı geçen her satır **aynı** değeri gösteriyor"
2. "Sayı **ledger'dan okunur**, elle yazılmaz"

Ledger'ın gerçek çıktısı projeye göre kırılıyor:

```
$ RABADON_NOTIFY=0 rabadon usage --days 30
  520 refused · 90,274 gated · 2 repairs held · 3 unverified
  stitchu   repairs held (locked): 0   repairs unverified: 3
  express   repairs held (locked): 2   repairs unverified: 0
```

Toplam 2. stitchu'nun satırı 0, ve o 0 doğru. README gerçek çıktı bastığı sürece
(2) sağlanır, (1) katı okunuşuyla sağlanamaz.

İki çıkış yolu vardı, ikisi de reddedildi:
- stitchu'nun 0'ını 2 yapmak → ledger tahrifi. Bu ürün tam olarak onu engellemek
  için var.
- stitchu'yu bloktan çıkarıp yalnız express'i göstermek → cherry-picking.
  Ürünün en büyük gerçek sinyalini saklayıp parlayan projeyi vitrine koymak,
  §6.2'nin "kapsamı sessizce daraltma" satırı.

Hakem de bu iki maddede itirazı **meşru** buldu ve dürüst bir üçüncü yol
olmadığını bağımsız olarak doğruladı.

## Önerilen düzeltme (uygulanmadı — onay bekliyor)

`accept.sh` üzerinde, **ayrı bir oturum tarafından, kendi commit'inde**:

- Kontrol, `rabadon usage` çıktısını gösteren fenced code block'un içindeki
  per-project satırları hariç tutsun. Kapsam düzyazı + tablo iddiaları olsun;
  bir ledger dökümünün per-project satırı iddia değil, veridir.
- **Ve kontrol aynı anda güçlensin:** blok içindeki **toplam** satırının
  (`N repairs held`) 2 okuduğu ayrıca assert edilsin. Böylece muafiyet bir
  delik açmaz — bugün kontrol edilmeyen toplam satırı, yarın kontrol edilir.

Net etki: yasak olan bayat sıfır hâlâ kırmızı kalır, per-project olgu yeşile
döner, ve test bugünkünden **daha fazla** şey doğrular.

## accept.sh'ın kendi içindeki gerilim (bilgi olarak, itiraz değil)

Hakemin işaret ettiği ve buraya not düşülmesi gereken bir nokta: `1d` her iki
dosyada "unplanned ... 0" cümlesini **zorunlu** kılıyor, `1a` ise
"repairs held ... 0" ifadesini **yasaklıyor**. İkisi ancak zorunlu cümle
"repairs held" kelimelerinden kaçınırsa aynı anda sağlanabilir. Kaçınmak
mümkün ve iki dosya da artık kaçınıyor — yani bu bir kusur, bir engel değil.
İtiraz konusu yapılmıyor, kayda geçiriliyor.

## Bu arada tur ne durumda

**Kısmi.** Protokol §6.4'ün ikinci kırmızı bayrağı gereği, bu çözülmeden
**T2 başlamaz.**
