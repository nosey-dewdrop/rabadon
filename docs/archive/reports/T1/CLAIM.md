# T1 — CLAIM

Durum: **TAMAMLANDI** — kabul 20 yeşil / 0 kırmızı, kapsamın beş işi de yapıldı.
Tarih: 2026-08-20.

Bu dosya turun içinden geçtiği üç durumu de tutuyor ve hiçbirini silmiyor:
16/3 (ilk uygulama) → 17/2 (hakem düzeltmeleri) → 20/0 (protokol düzeltmesi
sonrası yeniden yazılan kabul testi). Yeşile giden yol, yeşilin kendisi kadar
kayıtta.

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

$ ./reports/T1/accept.sh          # protokol düzeltmesi + yeniden yazılan test
== T1 acceptance: 20 green, 0 red
T1 ACCEPTED
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

## Kırmızı kalan iki iddia nasıl çözüldü (1a ve 1c)

**Testi değil, protokolü düzelterek** — insan kararı, 2026-08-20.

Sıra §6.2'nin gerektirdiği gibi işledi ve üçü de ayrı commit:
1. `PROTOCOL-T1-T8.md` §T1.4 + Kabul maddesi 1 düzeltildi, gerekçesi
   `discards.txt` madde 8'e yazıldı — **kendi commit'inde, testten önce**.
2. `accept.sh` **ayrı bir oturum** tarafından yeni maddeye göre yeniden yazıldı
   — **tek başına commit'lendi**. Uygulayan oturum yine dokunmadı.
3. Koşturuldu: **20 yeşil / 0 kırmızı**.

Kural zayıflamadı, genişledi. Muafiyet dar: yalnız ledger dökümü bloğunun
içindeki `repairs held (locked): <n>` biçimli per-project satırları. Karşılığında
**yeni bir iddia (1f)** eklendi: bloğun **toplam** satırı 2 okumak zorunda — eski
testin hiç kontrol etmediği bir şey.

Testi yeniden yazan oturum 8 mutasyonla kendi işine saldırdı. Eski testin
**tamamen yeşil kaldığı** iki hile artık kırmızı: ledger bloğunu tümden silmek,
ve toplam satırını 0'a çevirmek. Düzyazıdaki bayat sıfır, tablo hücresindeki
bayat sıfır, blok dışına taşınmış per-project satırı, banner'sız fence içine
saklanmış satır — hepsi hâlâ kırmızı.

Açık bırakılan delik, kapatılmadığı için yazılıyor: banner'ı, sahte toplamı ve
sahte per-project satırı **tam kurallı** yazılmış uydurma bir ledger bloğu muaf
olurdu. Kapatmak testin çevrimdışı yapamayacağı bir şeyi gerektirir (bloğu canlı
`rabadon usage` çıktısıyla diff'lemek). Zayıf ama gerçek iki tutamak: her koşuda
muaf tutulan satır sayısı ve blok sayısı ekrana basılıyor (hakem görebilsin diye,
güvenmek zorunda kalmasın), ve sahte ledger dökümü yazmak protokolün "ledger
tahrifi" dediği fiilin ta kendisi.

## Çözülmeden önceki hali (kayıt için)

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

- Kaç yeşil / kaç kırmızı? **20 / 0.** → **tamamlandı**.
- Kapsam dışına çıkıldı mı? **Hayır.** Hiçbir kaynak kod dosyasına dokunulmadı,
  hiçbir CLI verb'ü değişmedi, `native/` ve `core/` hiç açılmadı.
- Kapsamın beş işi de yapıldı mı? **Evet.** Madde 3 (GitHub description +
  topics) en son kapandı ve accept.sh onu kontrol etmiyor — yani bu maddenin
  yeşili testten değil, komut çıktısından geliyor (`discards.txt` #1).
- Sonraki tur için değişen varsayım var mı? **Evet, bir tane ve insan onaylı:**
  §T1.4'ün "her satır aynı sayı" ifadesi iddia/veri ayrımı yapmıyordu; düzeltildi
  (`discards.txt` madde 8, `DRIFT.md`).

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
- **20/0'lık son koşu hakem tarafından denetlenmedi.** Testi yeniden yazan
  oturum kendi işine 8 mutasyonla saldırdı ve sonuçları raporladı, ama bu
  kendi kendini ölçmenin bir biçimi. Bağımsız bir hakem oturumu T1'in son
  haline bakmadı.
- **1c'nin önceden var olan zayıf noktası duruyor:** kuralı "satırda sayı varsa
  ve 2 onların arasındaysa geç". `0 repairs held · 2 unverified` yazan bir satır
  1c'yi tatmin ederdi. Yeni 1f o satırı düzgün kapatıyor ama 1c'nin genel
  zayıflığı yerinde.
- **accept.sh'ta bir bash 3.2 tuzağı var:** macOS bash, `$(...)` içindeki
  tırnaklı heredoc'ta backtick'i ayrıştırıyor. T2–T8'in kabul scriptleri aynı
  kalıpla yazılacaksa bilinmeli.
