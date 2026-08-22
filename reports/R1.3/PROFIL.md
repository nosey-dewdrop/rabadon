# R1.3 — kalan maliyet nerede? (ölçüldü, tahmin edilmedi)

Bu dosyanın önceki hali JSONL günlük dönemini anlatıyordu ("400 satır / 67.090 bayt",
"maliyetin neredeyse tamamı parse"). R1.3 formatı değiştirdi: kayıt artık sabit genişlikli
ikili bir ring. O yüzden buradaki her sayı yeniden ölçüldü ve dosya baştan yazıldı.

Aşağıdaki her satır bir ölçümün çıktısı. İzole edilemeyen her şey **DOĞRULANMADI** diye
işaretli ve üstüne cümle kurulmadı.

## Makine, ve yöntemin neden değişmek zorunda kaldığı

    $ uptime
    23:33  up 1 day, 25 mins, 4 users, load averages: 12,51 8,17 5,70

Her şey yüklü bir makinede ölçüldü. Bu, dosyadaki her şeyden önce gelir, o yüzden başa
yazıldı.

Bariz yöntem — gate'i N kez çalıştır, duvar saatini ölç, çıkar — denendi ve **bu turun
ölçmesi gereken şeyi çözemiyor.** Kendi kopyasına karşı koşturulan bir kontrol kolu (aynı
binary, aynı ortam, aynı sandbox tarifi; iki kez etiketlenip araya sokuldu) şunu verdi:

| kollar üzerindeki istatistik | kontrol vs kendi kopyası |
|---|---|
| 7 tur x 150 çağrının medyanı | **191 µs** fark |
| 13 tur x 250 çağrının medyanı | **176 µs** fark |
| 17 tur x 250 çağrının min'i | **9 µs** fark |

Aynı programın iki kolunun 176–191 µs ayrışması, bu makinede medyan-yönteminin tabanıdır.
68 KB'lık okuma, iki pwrite ve tek SHA-256 — üçü de **bu tabandan küçük**, yani hiçbir
toggle deneyi onları bulamazdı. Çok turlu `min` (en az müdahaleye uğrayan tur, gerçek
maliyete en yakın tahmindir) tabanı 9 µs'ye indiriyor ve aşağıdaki uçtan uca sayıların
hepsi onunla alındı.

Bileşen başına sayılarda yöntem yine farklı, ve daha iyi:

- **süreç içi mikro-benchmark** (`-O2`, shipped gate'in yazdığı gerçek 68096 baytlık ring
  dosyasına karşı) — dört ilkel için;
- **gate'in enstrümante edilmiş bir kopyası** — `native/gate.cpp`'nin değiştirilmemiş bir
  kopyasına ilgilenilen fonksiyonların başına RAII zamanlayıcı eklenip `/tmp` altında
  derlendi. `native/` altında **hiçbir dosyaya dokunulmadı.** Bu, `main()` içini ölçer;
  fork/exec/dyld gürültüsü tamamen dışarıda kalır.

## Manşet: maliyet süreç açılışında, gate'te değil

    TOTAL_main (main() içindeki her şey)          1.61 – 1.93 ms
    uçtan uca duvar saati / gate çağrısı          3.9 – 4.3 ms

Her gate çağrısının kabaca **2.3 ms'si fork + exec + dinamik yükleme** — rabadon'un tek
satırı çalışmadan önce. Bu turun elleyebileceği bir şey değil, ama 4 ms'lik uçtan uca sayı
üzerinden alınan her yüzde bununla sulanıyor, ve GOAL 4'teki "%5" tavanı sulanmış sayının
tavanı.

## İzole etmem istenen dört şey

Süreç içi mikro-benchmark; 20.000 iterasyonluk 9 bloğun medyanı; 400 olay sonrası gerçek
ring'e karşı (68096 B):

| ilkel | ölçüm |
|---|---|
| `open` + sadece başlık `pread`'i (4096 B) — taban | **0.38 µs** |
| `open` + başlık + tam ring `pread`'i (68096 B) | **2.05 µs** |
| → **64000 baytlık ring pread'inin kendisi** | **1.68 µs** |
| append: iki `pwrite` (320 B kayıt + 4096 B başlık) | **2.18 µs** |
| bir 320 baytlık kayıt üzerinde tek SHA-256 | **1.95 µs** |
| canlı pencereyi çöz: 200 x `from_rec` → `Move` | **5.52 µs** |
| `sig_bash` (relativise + mask_scratch + squeeze + sha) | **1.10 µs** |
| tek başına `relativise` | **0.068 µs** |
| tek başına `clip` | **0.001 µs** |
| dolu 200'lük move vektörüne `push` | **1.15 µs** |

**Adı geçen dört şüpheli toplam ~6 µs.** Move formatının tamamı — oku, çöz, hash'le,
append'le, kur — toplam ~14 µs. Maliyet orada değil.

Aynı bileşenler uçtan uca da ölçüldü (tam olarak bir şeyi çıkarılmış variant binary'ler,
alt akış sabit kalsın diye `RABADON_SIGNALS=0` ile, 13 tur x 250 çağrının min'i): ring
pread'i çıkınca 27 µs, tüm yükleme çıkınca 20 µs, iki pwrite çıkınca 58 µs, iki SHA-256
çıkınca −38 µs. Hepsi o yöntemin 176 µs'lik tabanının içinde. **Hiçbir şey doğrulamıyorlar
ve buraya yalnızca kimse aynı deneyi cevap bekleyerek tekrar koşmasın diye yazıldılar.
Bileşen ölçümü olarak DOĞRULANMADI; geçerli olan yukarıdaki süreç içi sayılar.**

## Kayıt maliyeti gerçekte nerede

Enstrümante gate, 200 olayla ısınmış oturum, 120 olayın medyanı:

| prob | MOVES açık | MOVES=0 | delta |
|---|---|---|---|
| `TOTAL_main` | 1802.4 µs | 1410.9 µs | **+391.5 µs** |
| `state_load` | 109.4 µs | 82.3 µs | +27.1 µs |
| `load_moves` | 31.4 µs | 3.2 µs | +28.2 µs (kapalıyken dosya yok, okunacak şey yok) |
| `record_block` (gate.cpp:2216) | 397.9 µs | — | +397.9 µs |
| ├ `build+append` | 56.7 µs | — | |
| ├ `signals_detect` | 2.5 µs | — | |
| └ blok içinden çağrılan `save()` | ~320 µs | — | |
| olay başına toplam `save()` | 640.6 µs (**2 çağrı**) | 319.4 µs (**1 çağrı**) | **+321.2 µs** |

**Kaydın maliyeti fazladan bir `save()`.** Kaydı açmak move ring'ine ölçülmeye değer bir
I/O eklemiyor (28 µs); aynı süreçte `State::save()`'e **ikinci** bir çağrı ekliyor, çünkü
kayıt bloğu `stt.save()` ile bitiyor ve olay sonra yine save ediyor. `save()` çağrı başına
~320 µs ve moves açıkken iki kez, kapalıyken bir kez çağrılıyor. 391 µs'lik deltanın
321'ini tek başına bu satır açıklıyor. Ring'in kendisi 28 µs, move kurulumu 57 µs.

`save()` pahalı çünkü paylaşılan `state.json` üzerinde **her seferinde** `write_atomic`
yapıyor — fonksiyonun o yarısında dirty kontrolü yok, yani oturum dosyasının kendi dirty
takibi ne derse desin her çağrı bir temp dosya artı bir rename.

Uçtan uca aynı delta (17 tur x 250 çağrının min'i, çözünürlük tabanı 9 µs): kayıt toplamı
**590 µs**; bunun **62 µs**'si ring I/O + çözme + sinyaller, **528 µs**'si geri kalan.
Aynı hikâye, aynı oranlar, ikinci bir yöntemle.

## Değişmez (GOAL 6): uçtan uca %7 ile yeşil, süreç içinde %18 — ve suçlu ring değil

Enstrümante gate, 50 olaylık oturum vs 400 olaylık oturum, kollar dönüşümlü, her biri 140
olayın medyanı:

| prob | 50 olay | 400 olay | delta |
|---|---|---|---|
| `TOTAL_main` | 1636.8 µs | 1933.8 µs | **+297.0 µs (+%18.1)** |
| `last_ledger_mode` | 142.9 µs | 464.0 µs | **+321.1 µs** |
| `state_load` | 111.2 µs | 117.3 µs | +6.2 µs |
| `load_moves` | 28.6 µs | 35.5 µs | **+7.0 µs** |
| `record_block` | 408.6 µs | 400.4 µs | −8.2 µs |
| `build+append` | 51.5 µs | 50.5 µs | −1.0 µs |
| `save` | 661.5 µs | 653.2 µs | −8.3 µs |
| `emit` | 167.6 µs | 158.8 µs | −8.8 µs |

    50 olaylık oturum:  ring=20096 B   spool=10693 B
    400 olaylık oturum: ring=68096 B   spool=85943 B

**R1.3 yapmak için kurulduğu şeyi yaptı.** Move kaydının uzunluk bağımlılığına katkısı 8
kat uzun bir oturumda **+7.0 µs**, ve CAP=200'de tamamen büyümeyi kesiyor — 400 olaylık
ring ile 200 olaylık ring aynı 68096 bayt.

**Buna rağmen gate hâlâ uzunluğa bağımlı, +297 µs,** çünkü `last_ledger_mode()`
(gate.cpp:516) en yeni `MODE` satırını bulmak için **her olayda** spool'un o günkü
dosyasının tamamını bir string'e okuyor. Spool oturumla birlikte büyüyor — 50 olayda
10.7 KB, 400 olayda 85.9 KB — o okuma da onunla büyüyor: +321 µs. Kımıldayan tek prob o.

**GOAL 6 kabul koşuşunda YEŞİL geldi: 5.180 ms (50 olay) vs 4.841 ms (400 olay), %7.0
ayrı, tavan %10.** Bu, yukarıdaki +297 µs ile çelişmiyor — onu açıklıyor. Uçtan uca çağrı
~4.2 ms ve bunun ~2.3 ms'si fork/exec/dyld, yani süreç içindeki %18.1'lik büyüme uçtan uca
297/4200 ≈ **%7'ye seyreliyor.** Ölçülen iki sayı aynı olgunun iki ölçeği.

Yani şart, gerçek bir uzunluk bağımlılığı **varken** geçiyor. Kaydın payı +7 µs olduğu için
R1.3'ün kendi iddiası ayakta; ama tavanın altında kalmayı sağlayan şey ring değil, süreç
açılışının sayıyı sulaması. `last_ledger_mode` bir olay daha uzun bir spool görürse bu
%7'nin %10'u geçmesi için çok yer yok — ve şart o gün ring'e bakarak kırmızıya döner, ki
suçlu ring değil. Bu bir ölçüm notu, kabul kararı değil: GOAL 6 yeşil.

## İzole EDEMEDİKLERİM — DOĞRULANMADI

- **Dört adlı bileşen, uçtan uca.** 176 µs'lik tabana karşı 27 / 20 / 58 / −38 µs.
  Kullanılabilir olan yalnızca süreç içi sayılar. Bu dört şey için uçtan uca toggle deneyi
  bu makinede ölü bir yöntem, öyle kaydedildi.
- **Dedektörün (sinyaller) maliyeti.** `base − signals_off` **−4 µs**, `moves_off −
  both_off` **+63 µs** döndü; ikisi de kendilerini üreten yöntemin tabanının içinde.
  Enstrümante build `signals_detect`'i **2.5 µs** koyuyor — bu gerçek bir sayı, ama yalnız
  kayıt bloğunun içindeki `rbsig::detect` çağrısını ölçüyor; sinyal işi `main()` içinde
  başka bir yerde de oluyorsa bu prob onu görmedi. **Uçtan uca izole edilmedi.**
- **`TOTAL_main`'in hiçbir probun kapsamadığı ~1.4 ms'si.** Problar 1.93 ms'lik
  `TOTAL_main`'in kabaca `state_load` 110 + `record_block` 400 + `last_ledger_mode` 464 +
  `emit` 160 ≈ 1.13 ms'sini açıklıyor, üstelik `save` `record_block` ile çakıştığı için
  gerçek kapsama daha da düşük. **Geri kalan profillenmedi. Ölçmedim, adını da koymuyorum.**
- **Bu makine dışında herhangi bir makine hakkında hiçbir şey.** Load average 12.5, 8 GB
  RAM, her şey başka işler koşarken ölçüldü. Mutlak mikrosaniye değerleri bu kutunun.
  Taşınması beklenmesi gereken şey **oranlar** ve bileşenlerin **sıralaması** — o bile
  DOĞRULANMADI.
- **GOAL 6'nın ne kadar kararlı yeşil olduğu.** Kabul koşuşunda %7.0 ile geçti, tavan %10.
  Ama gürültü kontrolleri (iki sandbox'ı da zamanlamadan önce tohumlamak, kolların sırasını
  turlar arası değiştirmek) eklenmeden ÖNCE aynı protokol, değişmemiş bir binary üzerinde
  beş tekrarda **%0.3 ile %68.6** arası ayrışma döndürüyordu; kontroller eklendikten sonra
  beş tekrarda **%1.1 – %20.9**. Yani tek bir yeşil koşu bu makinede şartın kararlı geçtiği
  anlamına GELMEZ. Boş bir makinede hiç test edilmedi. **DOĞRULANMADI.**

## Tekrar üretmek için

Variant binary'ler ve harness'lar `/tmp/prof/` altında, `native/gate.cpp`'nin
değiştirilmemiş kopyalarından (yama yalnız kopyada) `c++ -std=c++17 -O2 -I native` ile
derlendi. Bu profil koşusu `native/` altında hiçbir dosyayı değiştirmedi. Variant'lar:
`nopread` (ring `pread`'i çıkarıldı), `noload` (canlı pencere yüklemesi çıkarıldı),
`noappend` (iki `pwrite` de çıkarıldı), `nosha` (iki SHA-256 da çıkarıldı), `noio`
(`load_moves` ve `append_move` no-op yapıldı), `timed` (yalnız RAII prob; davranış aynı).

---

# SONRASI — 22 Ağustos, iki neden de kaldırıldı

Yukarıdaki her şey "maliyet nerede" sorusunun cevabıydı. Bu bölüm o iki yeri
düzelttikten sonraki sayılar, aynı satırda öncesiyle yan yana.

## Yöntem: bu turun sayıları da süreç İÇİ

`native/gate.cpp`'nin **değiştirilmemiş iki kopyası** — biri düzeltme öncesi
commit'ten (`c127981`), biri sonrasından — `/tmp/prof2/` altında aynı RAII prob
yamasıyla derlendi (`c++ -std=c++17 -O2 -I native`). `native/` altında hiçbir
dosyaya dokunulmadı. Yukarıdaki turdan bir fark var ve önemli: prob çıktısı
artık **tamponlanıyor**, süreç sonunda tek seferde basılıyor. Önceki tur her
prob için stderr'e bir `fprintf` yapıyordu, yani kolu daha çok problu olan taraf
ölçüme fazladan syscall ödüyordu. Aşağıdaki "önce" sütunu bu yüzden yeniden
ölçüldü; ilk turun sayılarıyla aynı hikâyeyi veriyor, mutlak değerleri biraz
daha düşük.

Makine bu sefer boştu, ve bu da bir fark:

    $ uptime
    23:52  up 1 day, 44 mins, 4 users, load averages: 2,46 3,47 4,13

## NEDEN 1 — olay başına ikinci `save()`

`State::save()`, oturum dosyası için R1.1'de dirty-takibe alınmıştı; paylaşılan
`state.json` yarısı alınmamıştı, yani her çağrı bir temp dosya artı bir rename
ödüyordu. Şimdi **birleştirilmiş** sonuç, o anda diskte duran baytlarla
karşılaştırılıyor ve eşitse syscall atlanıyor. Karşılaştırılan şeyin
birleştirme SONRASI olması şart: `cur` her çağrıda taze okunuyor, bu yüzden
başka bir yazıcının güncellemesi karşılaştırmayı düşürür ve yazma yine yapılır.
Birleştirme mantığının tek satırı değişmedi — yalnız yazma koşullu.

200 olayla ısınmış oturum, 120 olayın medyanı, kayıt açık vs `RABADON_MOVES=0`:

| prob | önce | sonra |
|---|---|---|
| `TOTAL_main` deltası (kaydın maliyeti) | +386.2 µs | **+245.2 µs** |
| olay başına toplam `save()` (2 çağrı) | 611.0 µs | **339.4 µs** |
| └ `save#1` | 354.2 µs | **191.4 µs** |
| └ `save#2` | 308.7 µs | **164.6 µs** |
| kayıt kapalıyken tek `save()` | 282.7 µs | **158.8 µs** |
| `record_block` | 364.1 µs | **226.6 µs** |

## NEDEN 2 — `last_ledger_mode()` her olayda tüm spool'u okuyordu

Artık dosyanın **kuyruğunu** okuyor: sondan 32 KB'lık bir pencere, penceredeki
yarım ilk satır atılıyor, en yeni `MODE` satırı orada aranıyor. Pencerede yoksa
tüm dosya okunuyor — yani hiçbir girdi için cevap değişmiyor.

Bu geri düşüş nadir DEĞİL, ve bunu açıkça yazmak gerekiyor: hiç mod
değiştirmemiş bir makinede spool'da hiç `MODE` satırı yoktur, yani her olay
pencereyi ışkalar. Yokluk, her bayta bakmadan kanıtlanamaz. Düzeltilebilecek
olan şey o baytların NASIL okunduğuydu: eski `read_file` string'i bir
`ostringstream` üzerinden büyütüyordu; yeni okuyucu dosyayı `fstat`'lıyor,
string'i bir kez boyutlandırıyor ve tek `pread` döngüsüyle dolduruyor.

Aynı davranışın kanıtı ölçüm değil, karşılaştırma: eski tam-okuma taraması ile
yeni kuyruk taraması **154 girdide** karşılaştırıldı (boş dosya, hiç MODE,
pencereden eski MODE, iki MODE, boş `to`, `to` alanı olmayan satır, satır sonu
olmayan dosya, ve MODE satırını 32768. baytın iki yanında 140 bayt boyunca
gezdiren bir sınır taraması). **0 uyuşmazlık.**

50 olaylık oturum vs 400 olaylık oturum (spool 42.5 KB vs 120.9 KB), her biri
140 olayın medyanı:

| prob | önce 50 | önce 400 | önce delta | sonra 50 | sonra 400 | **sonra delta** |
|---|---|---|---|---|---|---|
| `TOTAL_main` | 1513.6 | 1857.9 | +344.3 (+%22.7) | 1235.7 | 1269.3 | **+33.6 (+%2.7)** |
| `last_ledger_mode` | 148.2 | 471.6 | +323.4 | 47.5 | 126.2 | **+78.7** |

Kalan +78.7 µs, yukarıda yazılan sebebin ta kendisi: MODE satırı olmayan bir
spool'da geri düşüş her olayda koşuyor ve tüm dosyayı okur. Okuma ~9 kat
ucuzladı, ama hâlâ O(dosya). **Uzunluk bağımlılığı bitmedi, küçüldü.**

## Kabul koşusu (`reports/R1.3/accept.sh`, boş makine)

    GOAL 4: kayıt kapalı medyan 4.248 ms   açık 4.544 ms   delta 296 µs
            tavan = off-medyanın %5'i = 212 µs            -> KIRMIZI
    GOAL 6: 4.555 ms (50 olay) vs 4.299 ms (400 olay), %5.9 ayrı, tavan %10
                                                          -> YEŞİL
    12 yeşil, 1 kırmızı

**GOAL 6 yeşil ve bu sefer sebebi gürültü değil.** 400 olaylık kol 50 olaylık
koldan *hızlı* çıktı; ayrışmanın işareti bile sabit değil, yani ölçülen şey artık
uzunluk değil makinenin kendisi. Süreç içi +%2.7 bunu doğruluyor.

**GOAL 4 hâlâ kırmızı, ve nerede olduğu ölçüldü.** Kaydın süreç içi maliyeti
386 → 245 µs; kalan 245'in dağılımı: `save#2` 165, `append_move` 46,
`load_moves` 28, `state_load` 28. Yani kalan kalemin tamamına yakını **ikinci
`save()`'in oturum dosyasına yaptığı gerçek yazma.** O yazma dirty-takiple
atlanamaz: kayıt bloğu ile olayın sonraki dalları arasında oturum nesnesi
GERÇEKTEN değişiyor (`actionCount`, `recent`, `lastCmd`), yani iki çağrının
baytları farklı. Bunu düşürmenin tek yolu save#2'yi ertelemek ya da birleştirmek
— ikisi de davranış değişikliği (kayıt bloğu erkenden save ediyor çünkü aşağıdaki
her ret dalı erken return'lüyor), ve bu turun yetkisi dışında. Uydurmuyorum:
**ölçtüm, yerini söylüyorum, dokunmadım.**

Bir not daha, ve kabul kararı değil: accept.sh'in GOAL 4 tavanı uçtan uca
medyanın %5'i, yani 212 µs. KOSU-RABADON.md §4 bu paydayı zaten reddediyor
("Bu tablodaki her sayı süreç-İÇİ ölçülür"). Süreç içi maliyet 245 µs ve o da
212'nin üstünde, yani bu not GOAL 4'ü kurtarmıyor — sadece iki sayının farklı
şeyleri ölçtüğünü kayda geçiriyor. Betiğe dokunulmadı.

## Bu turda DOĞRULANMADI

- **GOAL 4'ün kırmızılığının ne kadar kararlı olduğu.** Aynı ikili, yüklü bir
  makinede (load ~12) 269 µs / tavan 210 µs, boş makinede 296 µs / tavan 212 µs
  döndürdü. İki koşu da kırmızı, ama uçtan uca tek koşunun kendi gürültüsü bu
  farkın büyüklüğünde.
- **GOAL 6'nın kararlılığı, hâlâ.** Yükseldeki koşu (load ~12) %10.3 ile
  KIRMIZI, boş makinedeki %5.9 ile YEŞİL geldi — düzeltme aradaydı, yani ikisi
  doğrudan karşılaştırılamaz. Süreç içi +%2.7 sayısı tek koşuluk; beş tekrarlı
  kararlılık taraması yapılmadı.
- **Kuyruk penceresinin 32 KB olmasının doğru sayı olduğu.** Seçilmiş bir sayı,
  ölçülmüş değil. Daha küçük bir pencerenin daha çok geri düşüşe, daha büyüğünün
  daha pahalı hızlı yola yol açtığı ölçülmedi.
- **`save#2`'yi kaldırmanın GOAL 4'ü yeşile çevireceği.** Kalan bütçeye
  bakıldığında öyle görünüyor (245 − 165 = 80 µs), ama denenmedi ve
  denenmeden yazılan sayı sayı değildir.
- **Bu makine dışında hiçbir makine.** Yukarıdaki her mikrosaniye bu kutunun.

---

# SONRASI-2 — 23 Ağustos, `save#2` denendi

Bir üst bölümün son maddesi "`save#2`'yi kaldırmanın GOAL 4'ü yeşile
çevireceği — denenmedi" diyordu. Denendi. Bu bölüm o denemenin sayıları,
öncekiyle aynı satırda.

## Ne değişti: kayıt bloğu artık YAZMIYOR, işaretliyor

Kayıt bloğu `stt.save()` çağırıyordu, aşağıdaki dallar kendi değişiklikleriyle
tekrar save ediyordu, ve o ikinci yazma gerçekti — `actionCount`, `recent`,
`lastCmd` arada değişiyor, yani baytlar farklı, yani dirty-takip onu atlayamaz.
Tek olay, iki gerçek yazma.

Kayıt bloğu artık `stt.pendingRecord = true` diyor. İşaret ya olayın zaten
yapacağı bir sonraki `save()` tarafından kapatılıyor — o save kaydı ve dalın
kendi değişikliklerini AYNI yazmada taşıyor — ya da hiç save yapmayan bir
yolda `main()`'in başındaki `StateFlushGuard`'ın yıkıcısı tarafından.

**Ertelenen şey kayıt DEĞİL.** İşaret konmadan önce `append_move()` ring
kaydını ve başlığını diske yazmış oluyor. Kayıt bloğunun oturum dosyasında
dokunduğu tek alan `nextSeq`, ve `load_moves()` her yüklemede `nextSeq`'i ring
başlığından okuyor — yani oturum dosyasındaki kopyası zaten dayanıklı bir
gerçeğin tekrarı. Erteleme burada bu yüzden güvenli, ring'in taşımadığı bir
alan için olmazdı.

`exit()` yerel yıkıcıları çalıştırmaz, ve bu dosya üç yerde return değil exit
ediyor: mühürlü kural (exit 2), watch modu (exit 0), bütçe tavanı
(exit refuse_code()) — üçü de ret yolu, yani kaydı kaybetmemesi gereken
yolların ta kendisi. Guard bu yüzden hem yıkıcı hem `atexit` kaydı tutuyor;
`exit()` atexit'i main'in çerçevesi hâlâ ayaktayken çalıştırır, hangisi önce
tetiklenirse yazar, ikincisi işareti temizlenmiş bulur. Üç `_exit(127)`
çağrısının üçü de exec'i başarısız olmuş fork çocuğunda — çocuk ebeveynin
oturum dosyasını yazmamalı, yani orada ne yıkıcının ne atexit'in çalışmaması
doğru davranış, boşluk değil.

## Davranış aynı mı: ölçüm değil, karşılaştırma

Tek satırlık A/B (yalnız `stt.save()` ↔ `stt.pendingRecord = true`) iki ayrı
binary olarak derlendi ve **10 senaryoda** bıraktıkları `.rabadon` ağacı bayt
bayt karşılaştırıldı: oturum json'ı, move ring'i, spool günlüğü ve `.head`'i,
`state.json`. Maskelenen tek şey saat türevi: ring'de `ts` ve `prev`, spool'da
`ts`/`run`/`pipe`/`prev` ve sandbox yolları. `seq`, `tool`, `sig`, `err`,
`asserts`, `path`, `raw`, `ev`, `step`, `rule`, olay sayısı ve **her çağrının
çıkış kodu** bayt bayt karşılaştırıldı.

    izin yolu (5 olay)                                  PASS
    ret yolu (rm -rf /, force-push, chmod 777)          PASS
    watch modu (exit 0 dalı)                            PASS
    bütçe tavanı (exit refuse_code dalı)                PASS
    RABADON_MOVES=0 / SIGNALS=0 / MOVES_STRICT=1        PASS
    60 olaylık oturum                                   PASS
    tests-RED reddi (dalında save OLMAYAN return)       PASS
    karışık izin + ret + post                           PASS
    -> 10 senaryo, 0 uyuşmazlık

**Ret yolu hâlâ kaydediyor, ve bunun kanıtı argüman değil koşu:** ret
senaryolarında iki binary'nin ring'i bayt bayt aynı ve çıkış kodları aynı
([0,2,2,0]).

Guard'ın kendisi hakkında dürüst olan: **807 olaylık bir taramada (5 env x 20
komut x 4 araç x 2 hook, artı Stop/SessionStart/UserPromptSubmit/SubagentStop/
PreCompact/Notification, artı bütçe tavanı) guard bir kez bile yazmadı** —
ulaşabildiğim her yolda olay zaten bir `save()` yapıyor. Guard'ı devre dışı
bırakan bir negatif kontrol de 10 senaryonun hepsinde eşdeğer çıktı. Yani
guard bugün yük taşımıyor; ileride save yapmayan bir erken return eklenirse
işaretin sessizce düşmemesi için duruyor.

## Süreç içi sayılar (aynı `/tmp` enstrümante-kopya yöntemi)

Bu turun A/B'si TEK SATIR: aynı kaynak ağacın iki kopyası, biri
`stt.pendingRecord = true`, öteki `stt.save()`. Arada R3 tier-1 gate'e girdi,
o yüzden "önce" sütunu bir üst bölümün sayıları değil, **bugünkü ağacın**
yeniden ölçülmüş öncesi. 200 olayla ısınmış oturum, 120 olayın medyanı, iki
dönüşümlü tur:

| prob | önce | sonra |
|---|---|---|
| olay başına `save()` çağrısı | **2** | **1** |
| `save#1` | 178.2 / 165.9 µs | 167.1 / 162.3 µs |
| `save#2` | **160.6 / 157.8 µs** | **yok** |
| `TOTAL_main` deltası (kaydın maliyeti) | +257.2 / +234.8 µs | **+62.2 / +59.9 µs** |
| `record_block` | 246.3 / 222.6 µs | **57.5 / 57.2 µs** |
| `save` deltası (açık − kapalı) | +178.9 / +160.7 µs | **−3.0 / −4.1 µs** |

Kaydın süreç içi maliyeti **~246 → ~61 µs**. KOSU-RABADON.md §4'ün istediği
süreç içi ölçüde 212 µs tavanının **151 µs altında**. Kalan 61'in dağılımı
değişmedi: `append_move` ~49, `load_moves` ~29, `state_load` ~29, `build`
~3 — yani kalan kalem artık ring'in kendisi, ve o R1.3'ün ödemeye razı olduğu
kalem.

## Kabul koşusu — ve uçtan uca gürültünün büyüklüğü

`reports/R1.3/accept.sh`, aynı binary, beş koşu (ilki yüklü makinede, load ~5;
kalan dördü load ~3.5):

| koşu | GOAL 4 delta | GOAL 4 tavan | GOAL 6 ayrışma |
|---|---|---|---|
| 1 (yüklü) | 602 µs | 476 µs — KIRMIZI | %5.0 — yeşil |
| 2 | **118 µs** | 209 µs — YEŞİL | %11.7 — kırmızı |
| 3 | 213 µs | 209 µs — KIRMIZI | %0.9 — yeşil |
| 4 | **−59 µs** | 286 µs — YEŞİL | %0.4 — yeşil |
| 5 | 228 µs | 323 µs — YEŞİL | %11.6 — kırmızı |

Öncesi tek koşuda 296 µs / tavan 212 idi. Sonrası dört sakin koşunun üçü
tavanın altında, biri 4 µs üstünde. **Bunu "GOAL 4 yeşil oldu" diye yazmıyorum:
uçtan uca yöntem bu makinede ±150 µs oynuyor ve marj o oynamayla aynı boyda.**
Kararı taşıyan sayı süreç içi olan: 246 → 61 µs, ve o tek yönlü.

GOAL 6 beş koşuda %0.4 – %11.7 arası gezdi ve tavanı iki kez geçti. Bu
değişikliğin GOAL 6 ile ilgisi yok — kaldırılan şey uzunluktan bağımsız sabit
bir yazma — ve bir üst bölümün "GOAL 6'nın kararlılığı DOĞRULANMADI" maddesi
aynen ayakta: aynı ikili beş koşuda hem yeşil hem kırmızı veriyor.

## Bu turda DOĞRULANMADI

- **Guard'ın gerçekten yük taşıdığı bir yol.** 807 olayda hiç tetiklenmedi;
  statik olarak dalında `save()` bulunmayan iki `return refuse_code()` var
  (PostToolUse net-kırmızı ve tests-RED), ama fikstürle o iki dala
  pendingRecord açıkken ulaşamadım. Guard oraya ulaşılırsa yazar; **ulaşıldığı
  ölçülmedi.**
- **Çökme/sinyal penceresi.** Kayıt bloğu ile çıkış arasında SIGKILL/segfault
  olursa bekleyen oturum yazması kaybolur. Kaybolmayan şey kayıt: ring
  append'i zaten olmuş, ve riskteki tek alan `nextSeq`, onu da `load_moves()`
  ring başlığından okuyor. **Bu akıl yürütme kodu okuyarak yapıldı, bir çökme
  enjekte edilerek denenmedi.**
- **GOAL 4'ün uçtan uca kararlı yeşil olduğu.** Dört sakin koşunun biri 213 µs
  ile 209 µs tavanını 4 µs geçti. Tek koşu bu makinede karar değil.
- **Bu makine dışında hiçbir makine.** Yukarıdaki her mikrosaniye bu kutunun.
