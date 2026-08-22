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
