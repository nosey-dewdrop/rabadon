# T1 — CLAIM

Durum: **KISMİ** (16 yeşil / 3 kırmızı). "Tamamlandı" yazılmıyor (§6.3).
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

Uygulama commit'i bu commit'ten sonradır ve accept.sh'a tek karakter dokunmadı.

## Baseline (uygulamadan önce, testin ilk koşusu)

```
$ ./reports/T1/accept.sh
== T1 acceptance: 2 green, 17 red
T1 NOT ACCEPTED
```

Yeşil olan iki iddia: `make test` (245 s, exit 0) ve BENCHMARK.md'nin 2'yi
planlanmış kırılma olarak nitelemesi. Kalan her şey kırmızıydı.

## Uygulamadan sonra

```
$ ./reports/T1/accept.sh
== T1 acceptance: 16 green, 3 red
T1 NOT ACCEPTED
```

`make test`: exit 0, 233 s. Test sayısı düşmedi; hiçbir test silinmedi,
skip'lenmedi, zayıflatılmadı.

### Yeşile dönenler

- **2a/2b** — README artık yayınlanmamış paket için kurulum komutu basmıyor.
  `npm i -g rabadon` hem kurulum bloğundan hem satır içi düzyazıdan düştü,
  Status'teki "portable `npm i -g` install with prebuilt binaries" ibaresi
  kalktı. Yerine kaynaktan kurulum geldi.
- **3** — "Supervise your coding agent" repoda kalmadı (git-tracked dosyalarda,
  reports/ ve protokol dosyası hariç).
- **4a/4b/4c** — kanonik cümle README ilk paragrafı ve package.json
  description'ı oldu. keywords'ten `guardrails`, `sandbox`, `pipeline` düştü;
  `compound-error`, `agent-recovery`, `coding-agent` girdi.
- **1b** — "0 on real breakage" ifadesi BENCHMARK.md §4 tablosundan kalktı.
  Doğru kelime "unplanned"; "real" olan 2 onarım da gerçekti, çelişki oradaydı.
- **1d** — hem README hem BENCHMARK artık 2'yi planlanmış kırılma olarak
  niteliyor ve unplanned = 0 cümlesini ayrıca kuruyor.

### Sayı nereden okundu

Elle yazılmadı. Ledger'dan çekildi:

```
$ RABADON_NOTIFY=0 rabadon usage --days 30
  520 refused before they happened · 90,274 actions gated · 2 repairs held · 3 unverified · 684 would-have-refused (watch)
  ...
  stitchu    repairs held (locked): 0   repairs unverified: 3
  express    repairs held (locked): 2   repairs unverified: 0
```

README'deki örnek blok bu koşudan alındı. Eskisi 2026-07-31 tarihli bayat bir
snapshot'tı ve "repairs held has since gone 0 -> 2" diye kendi bayatlığını
dipnotla açıklıyordu; bir sayının kendi düzeltmesini dipnotta taşıması, T1'in
kaldırmak için var olduğu şeyin ta kendisi.

## Kırmızı kalan üç iddia — ve neden metni değiştirerek geçirmedim

Üçü de **doğru cümleleri** yakalıyor. Testin deseni, ürünün gerçeğinden geniş.

**1a ve 1c — `README.md:67` → `repairs held (locked): 0`**
Bu satır stitchu'nun gerçek ledger çıktısının içinde. stitchu'da tutulmuş onarım
gerçekten 0; 2 olan express. Yani bu bir çelişki değil, proje kırılımının
olgusu. Testin "her satır aynı değeri göstersin" iddiası, per-project bir
dökümün içindeki 0'ı da kapsıyor.

Burada protokolün kendi iki maddesi çakışıyor:
- §T1.4: "repair sayısı geçen her satır aynı değeri gösteriyor"
- §T1.4: "Sayı ledger'dan okunur, elle yazılmaz"

Ledger'dan okunan gerçek çıktı, projeye göre 0 ve 2 basıyor. İkisi aynı anda
sağlanamıyor. Sayıyı 2 yapmak için stitchu'nun satırını elle 2'ye çevirmek
ledger'ı tahrif etmek olurdu — Yasa 5'in ve bu ürünün varlık sebebinin ihlali.

**1e — `README.md:84` ve `BENCHMARK.md:155` → "stays on this page as 0 until it isn't"**
Bu cümle artık **unplanned** breakage hakkında ve doğru. Testin deseni
(`(fix|repair)...still 0`, `as 0 until`) hangi sayı hakkında konuşulduğunu
ayırt etmiyor. Cümleyi "0" rakamını yazmadan kurup deseni atlatabilirdim;
yapmadım — bu, testi zayıflatmanın kelime düzeyindeki hali olurdu.

`reports/T1/CHALLENGE.md` bu üçünü ve önerilen düzeltmeyi taşıyor. Karar
insanın; kabul testine bu oturum dokunmadı ve dokunmayacak.

## Kapanış kontrolü (§6.3)

- Kaç yeşil / kaç kırmızı? **16 / 3.** Kırmızı var → **kısmi**.
- Kapsam dışına çıkıldı mı? **Hayır.** Beş işin beşi de T1'in kapsamında;
  hiçbir kaynak kod dosyasına dokunulmadı, hiçbir CLI verb'ü değişmedi.
- Sonraki tur için değişen varsayım var mı? **Evet, bir tane:** protokol
  "repair sayısı geçen her satır aynı değeri gösterir" derken README'nin gerçek
  per-project ledger çıktısı basacağını hesaba katmamış. Bu ikisi aynı anda
  doğru olamaz ve CHALLENGE ile insana taşındı.

## NOT VERIFIED

- **Temiz makinede kurulum.** README artık `git clone && npm install && npm link`
  diyor. `node scripts/build.mjs` bu makinede exit 0 verdi ("native binaries
  already built (18/18)") ve `package.json` postinstall'ı tam olarak onu
  çağırıyor, `bin` haritası `rabadon`'u PATH'e koyuyor. Ama **sıfırdan bir
  klonda, derleyicisi olan temiz bir kutuda uçtan uca koşturulmadı.** Bu
  makinede binary'ler zaten derliydi.
- **GitHub repo description ve topics** (T1 madde 3) **yapılmadı** — ağ/yetki
  işi, ve accept.sh onu kontrol etmiyor. Açık madde olarak duruyor.
- README örnek bloğundaki kural açıklamaları (her kuralın yanındaki tek satır)
  ledger'ın kendi metni değil, bu sayfa için yazılmış gloss. Sayılar birebir
  ledger'dan; bu ayrım bloğun başında açıkça yazılı.
- `bench/reproduce.sh` bu turda **koşturulmadı**; sayı `rabadon usage`'dan
  alındı. Protokol reproduce.sh'ı işaret ediyor, o yol doğrulanmadı.
