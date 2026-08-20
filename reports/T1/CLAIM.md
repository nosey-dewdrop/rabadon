# T1 — CLAIM

Durum: **KISMİ** (17 yeşil / 2 kırmızı). "Tamamlandı" yazılmıyor (§6.3).
Tarih: 2026-08-20.

## Açılış kontrolü (§6.3)

- Ürünün cümlesi hâlâ §0'daki mı? **Evet**, değişmedi.
- Bu tur o cümleye hangi somut adımı ekliyor? Ürünün kendini tarif ettiği üç
  yüzeyi (README ilk paragraf, package.json, BENCHMARK sayıları) §0'daki tek
  cümleye hizalıyor. Bundan önce repo üç ayrı şey iddia ediyordu.
- Bir önceki turun accept.sh'ı geçiyor mu? T1 ilk tur, önceki yok.

## Kapı 1'in kağıt izi

`reports/T1/accept.sh` uygulamadan **önce**, uygulayan oturumun **yazamadığı**
ayrı bir oturum tarafından yazıldı ve kendi commit'inde durdu:

```
$ git log --oneline -- reports/T1/accept.sh
3b2cd9c T1 acceptance test, written before the round by a session that cannot implement it
```

Uygulama commit'leri bu commit'ten sonradır ve accept.sh'a tek karakter
dokunmadı. Ayrı oturumdaki hakem bunu bağımsız olarak doğruladı.

## Sayılar

```
$ ./reports/T1/accept.sh          # uygulamadan ÖNCE
== T1 acceptance: 2 green, 17 red

$ ./reports/T1/accept.sh          # ilk uygulamadan sonra
== T1 acceptance: 16 green, 3 red

$ ./reports/T1/accept.sh          # hakem bulgularından sonra
== T1 acceptance: 17 green, 2 red
```

`make test`: exit 0, 230 s. Hiçbir test dosyasına dokunulmadı — test sayısının
düşmesi yapısal olarak mümkün değil, ve hiçbir test silinmedi, skip'lenmedi,
zayıflatılmadı.

## Sayı nereden okundu

Elle yazılmadı, ledger'dan çekildi:

```
$ RABADON_NOTIFY=0 rabadon usage --days 30
  520 refused before they happened · 90,274 actions gated · 2 repairs held · 3 unverified · 684 would-have-refused (watch)
  stitchu   repairs held (locked): 0   repairs unverified: 3
  express   repairs held (locked): 2   repairs unverified: 0
```

README'deki örnek blok bu koşudan alındı. Eskisi 2026-07-31 tarihli bayat bir
snapshot'tı ve "repairs held has since gone 0 -> 2" diye kendi bayatlığını
dipnotta taşıyordu; bir sayının kendi düzeltmesini dipnotta taşıması, T1'in
kaldırmak için var olduğu şeyin ta kendisi.

Hakem ledger'ı kendi koşturup her sayıyı tek tek karşılaştırdı: stitchu'nun ve
express'in bütün sayıları, kural kırılımları ve event damgaları **birebir**
tuttu. İki toplam (gated 90,274, watch 684) hakemin koşusunda 90,315 ve 685
okudu — canlı ledger monoton artıyor ve artışın kaynağı hakemin kendi
komutlarıydı; donmuş projelerin sayıları kıpırdamadı. Uydurma sayı bulunmadı.

## Hakemin yakaladığı ve düzeltilen üç şey

İlk CLAIM üç kırmızının üçünü de "test haksız" diye savunuyordu. Hakem bunun
yanlış olduğunu gösterdi; 1.5'i dürüstçe kapatılabilirdi ve kapatıldı.

1. **1e** — kırmızıyı yakan "unplanned = 0" bilgisi değil, eski BENCHMARK'tan
   devralınan tek bir retorik kuyruktu: *"and it stays on this page as 0 until
   it isn't."* Protokol o kuyruğu istemiyor. İki dosyadan da silindi, bilgi
   kaybı sıfır. **Yeşil.**
2. **`README.md:84`** — düzyazıda "repairs held is 0" yazıyordu; BENCHMARK
   aynı olguyu "the count is 0" diye yazıp deseni hiç tetiklemiyordu. Güvenli
   ifade zaten bir dosyada vardı, diğerine taşınmamıştı. Hizalandı.
3. **En ağırı — README'nin ledger bloğu aritmetik tutmuyordu.** Blok
   `caught before happening: 171` basıp altında 152'lik bir kural listesi
   gösteriyordu; eksik 19 event sekiz kurala yayılıydı ve kırpıldığı **hiçbir
   yerde yazmıyordu**. Blok kendini "Every count is verbatim" diye sunarken
   okuyucu toplayınca tutmuyordu. Bu, dürüstlüğü satan sayfanın üstünde açılmış
   bir delik. Düzeltildi: kırpmanın üç biçimi de (projeler, kural listeleri,
   watch kırılımları) bloğun başında tek tek yazılı, 152/171 farkı rakamla
   veriliyor, ve stitchu'nun düşürülmüş `push gates passed` / `rules written`
   satırları geri kondu.

## Kırmızı kalan iki iddia (1a ve 1c) — tek satır

İkisi de aynı satırı gösteriyor: `README.md`'nin ledger bloğunda stitchu'nun
`repairs held (locked): 0` satırı. stitchu'da tutulmuş onarım gerçekten 0;
2 olan express.

Protokolün kendi iki maddesi çakışıyor — §T1.4 hem "her satır aynı değeri
gösterir" hem "sayı ledger'dan okunur" diyor, ve gerçek ledger çıktısı projeye
göre 0 ve 2 basıyor. Dürüst bir üçüncü yol yok: stitchu'nun 0'ını 2 yapmak
ledger tahrifi, stitchu'yu bloktan çıkarmak cherry-picking. Hakem bu iki maddede
itirazı bağımsız olarak **meşru** buldu.

`reports/T1/CHALLENGE.md` itirazı ve önerilen accept.sh diff'ini taşıyor —
diff testi daraltmıyor, per-project satırı muaf tutup blok içindeki **toplam**
satırının 2 okuduğunu ayrıca assert ederek güçlendiriyor. Karar insanın;
kabul testine bu oturum dokunmadı ve dokunmayacak.

## Kapanış kontrolü (§6.3)

- Kaç yeşil / kaç kırmızı? **17 / 2.** Kırmızı var → **kısmi**.
- Kapsam dışına çıkıldı mı? **Hayır.** Hiçbir kaynak kod dosyasına dokunulmadı,
  hiçbir CLI verb'ü değişmedi. Ama kapsamın **beşte biri yapılmadı** (aşağıda).
- Sonraki tur için değişen varsayım var mı? **Evet:** protokol "repair sayısı
  geçen her satır aynı değeri gösterir" derken README'nin gerçek per-project
  ledger çıktısı basacağını hesaba katmamış.

## Açık madde — T1 kapanmadan yapılmalı

**T1'in beş işinden biri hiç yapılmadı:** madde 3, GitHub repo description ve
topics. `discards.txt` #1'de "YAPILMADI" diye duruyor. accept.sh bunu kontrol
etmiyor, yani iki kırmızı çözülse ve test 19/19 yeşil olsa bile protokol
kapsamı 4/5 kalır. Kabul testinin yeşili, kapsamın tamamlandığı anlamına
gelmiyor — bu, testin denetlemediği bir boşluk ve gizlenmiyor.

## NOT VERIFIED

- **Temiz makinede kurulum.** README artık `git clone && npm install && npm link`
  diyor. `node scripts/build.mjs` bu makinede exit 0 verdi ("native binaries
  already built (18/18)") ve postinstall tam olarak onu çağırıyor, `bin`
  haritası `rabadon`'u PATH'e koyuyor. Ama **sıfırdan bir klonda, derleyicisi
  olan temiz bir kutuda uçtan uca koşturulmadı.** Bu makinede binary'ler zaten
  derliydi.
- **`bench/reproduce.sh` koşturulmadı.** Protokol sayının ondan üretilmesini
  istiyor; sayı `rabadon usage`'dan alındı (aynı ledger'ın aynı okuyucusu).
  O yol doğrulanmadı.
- **README örnek bloğu birebir çıktı değil, kırpılmış bir yeniden dizim.**
  Sayılar ledger'dan birebir; ama satır hizalamaları yeniden dizildi, kural
  açıklamaları bu sayfa için yazılmış gloss, ve üç biçimde kırpıldı. Üçü de
  artık bloğun başında yazılı — ama "gerçek çıktı" ifadesi bu kayıtla birlikte
  okunmalı.
- **Hakem `make test`'i koşturmadı** (4 dk); 18 iddiayı gerçek dosyalar
  üzerinde koşturup uygulayanla birebir aynı sonucu aldı. `make test` exit 0
  iddiası uygulayan tarafından üç kez ölçüldü, hakem tarafından doğrulanmadı.
- **Baseline koşusu (2 yeşil / 17 kırmızı) hakem tarafından doğrulanmadı** —
  o ağaç artık yok, yeniden üretmek `3b2cd9c`'ye checkout gerektirirdi.
