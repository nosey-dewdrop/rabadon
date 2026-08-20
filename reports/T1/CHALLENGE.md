# T1 — CHALLENGE

Bir CHALLENGE, kabul testine ya da protokole dokunma yetkisi **değildir**.
Kanıtı ve önerilen diff'i insanın önüne koyar, orada durur.
Çözümü yalnızca insan onaylı, kendi commit'inde bir diff'tir.

## Neye itiraz ediliyor

`reports/T1/accept.sh` üç iddiada doğru metni kırmızı gösteriyor: **1a, 1c, 1e**.
Testte kötü niyet yok; protokolün kendi iki cümlesi birbirini kesiyor ve test
bunlardan birini kelimesi kelimesine uygulamış.

## Kanıt (yorum değil, koşu çıktısı)

```
FAIL  1a a bare "repairs held = 0" reading still remains
      README.md:67:    repairs held (locked):       0
FAIL  1c a numeric "repairs held" reading shows something other than 2
      README.md:67:    repairs held (locked):       0
FAIL  1e prose still argues the repair number is 0
      README.md:84:  ... On **unplanned** breakage, a bug nobody staged, repairs held is **0**.
      BENCHMARK.md:155: on this page as 0 until it isn't. That second number is the one to watch
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

Toplam 2. Ama stitchu'nun satırı 0, ve o 0 doğru. README gerçek çıktı bastığı
sürece (2) sağlanır, (1) katı okunuşuyla sağlanamaz. stitchu'nun 0'ını 2 yapmak
ledger'ı tahrif etmektir; bu ürün tam olarak onu engellemek için var.

1e'de ayrı bir sorun var: desen hangi sayıdan söz edildiğini ayırt etmiyor.
"planlanmış kırılmada 2" ile "planlanmamış kırılmada 0" iki farklı sayı ve
ikisinin birlikte yazılması protokolün **istediği** şey (§T1.4: "niteliği her
yerde aynı yazılır ... Planlanmamış kırılmada 0"). Test bu doğru cümleyi
yakalıyor.

## Önerilen düzeltme (uygulanmadı — onay bekliyor)

`accept.sh` üzerinde, **ayrı bir oturum tarafından, kendi commit'inde**:

- **1a / 1c** — kontrol, `rabadon usage` çıktısını gösteren fenced code block'un
  içindeki satırları hariç tutsun. Kapsam düzyazı + tablo iddiaları olsun; bir
  ledger dökümünün per-project satırı iddia değil, veridir. Ek olarak: blok
  içindeki **toplam** satırının (`N repairs held`) 2 okuduğu ayrıca kontrol
  edilsin — böylece kontrol zayıflamaz, doğru yere nişan alır.
- **1e** — desen "0" geçen her cümleyi değil, **planlanmış** onarım sayısının 0
  olduğunu iddia eden cümleyi yakalasın. Pratikte: aynı cümlede `unplanned`
  geçiyorsa muaf.

Bu düzeltme testi **daraltmıyor, nişanını düzeltiyor**: yasak olan bayat sıfır
hâlâ kırmızı kalır, doğru olan iki-sayı ayrımı yeşile döner.

## Alternatif — ve neden seçilmedi

Metni testin desenini atlatacak şekilde yeniden yazmak (0 rakamını hiç yazmadan
"henüz tutulmuş bir onarım yok" demek, stitchu bloğunu README'den çıkarmak).
Test yeşile dönerdi ve hiçbir şey doğrulanmış olmazdı. §6.2'nin listesinde bu
"kapsamı sessizce daraltma" satırıdır. Bilerek yapılmadı.

## Bu arada tur ne durumda

**Kısmi.** 16 yeşil / 3 kırmızı. Protokol §6.4'ün ikinci kırmızı bayrağı
gereği, bu çözülmeden **T2 başlamaz**.
