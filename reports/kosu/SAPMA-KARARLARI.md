# SAPMA KARARLARI — koşu 5

Cevapçının §10 yetkisiyle aldığı faz değişiklikleri. Her kalem: hangi faz,
ne değişti, hangi ÖLÇÜM bunu gerektirdi. Ölçü sertleşir, gevşemez (§10a).
§1, §3, §4 dokunulmaz.

---

## 2026-08-26 · F0 kapanışı sonrası · F1'in bölünmesi ve sertleştirilmesi

Soru: F1 gece modunda (§13) nasıl koşulur, ya da koşulmaz mı?

### 1. Hangi değişmez risk altında?

İki tanesi, aynı anda:

- **§13 / gece modu.** F1'in yazılı KABUL'ünün ilk maddesi
  `npm view rabadon version` sayı döndürüyor. Bu madde ancak `npm publish`
  ile yeşile döner: para değil ama **geri alınamaz** (npm'de bir sürüm
  yayımlandıktan sonra unpublish penceresi dar, isim kalıcı olarak
  sahiplenilir) ve **sahiplik** kalemidir. §13 bunu açıkça uykuda
  koşmaz listesine yazar. Yani F1 yazıldığı haliyle **bu gece kapanamaz**.
- **§4.10 "Yüzey beştir, geri şişirilmez."** ÖLÇÜM: yüzey zaten beş
  (`./native/rabadon-cli.sh --help` → `init`, `on|off`, `usage`, `repair`,
  `doctor` + `version` + `dev`; `dev --help` → 30 verb; exit 0). Ama
  `native/cli_test.sh` (310 ok / 0 fail) yalnız **keşfedilebilirliği**
  denetliyor — "her verb iki ekrandan birinde listeli" — **tavanı
  denetlemiyor.** Ana ekrana altıncı satır eklense hiçbir test kırmızı
  düşmez. Yani §4.10 bugün kırmızı düşebilen bir denetime bağlı DEĞİL.
  Bu bir boş yeşildir (§8.2).

Üçüncü, daha sessiz olan: **disclosure kapısı bugün CI'ı kırmızı tutuyor
ve kimse bunu ölçmemişti.** `gh run view 32922500561` (F0 kapanış
commit'i, 26.08 02:22): `ubuntu-latest` YEŞİL 5m56s, `macos-15` YEŞİL
6m18s, `disclosure ubuntu-latest` ve `disclosure macos-15` **KIRMIZI**.
`make disclosure` yerelde de kırmızı: **53 isim bulundu, 12 izinli,
41 liste dışı.** Liste dışı 41 ismin tamamı operatörün kendi
projelerinin adı (`youkiddingme`, `icerik`, `seviyorsevmiyor`,
`ir-globe`, `parmakestra`, `damla_portfolio`, `psikoloji-kitabi`, …).
**Hangi ismin kamuya çıkacağı cevapçının kararı değildir** (§10,
operatöre giden beş kalem: sahiplik + dış yayın).

### 2. Onu koruyan tasarım — SEÇENEK D

F1 ikiye bölünür. Kabul maddesi **gevşetilmez, taşınır** (§10b, sıra
değişikliği). Ve bölünmeden doğan boşluk daha SERT bir ölçüyle kapatılır.

**F1a — kurulabilir ürün, yayımlanmamış.** Uykuda koşar. Yerel, geri
alınabilir, para yakmaz.

**F1n — yayın.** `npm publish` + `v0.2.3` etiketi + `@rabadon` scope +
`NPM_TOKEN`. Uykuda KOŞMAZ. F1'in yazılı KABUL maddesi
`npm view rabadon version` sayı döndürüyor **aynen buraya taşınır**,
tek kelimesi değişmeden. F1n'in önkoşulu F1a'nın kapanmasıdır.

**SERTLEŞTİRME (§10a).** `npm view rabadon version` sayı döndürmesi zayıf
bir ölçüdür: bozuk bir paket de sayı döndürür. F1a bunun yerine, ondan
daha zor olanı kanıtlar — **yayımlanacak yol, yayımlanmadan önce temiz
makinede kurulup çalışır.** `native/npm_install_test.sh` tarball'ları
paketleyip temiz bir prefix'e kuruyor ve `make test` içinde koşuyor;
F1a bunu CI matrisinin **her hücresinde** koşturur. F1n yayımladıktan
sonra `npm view` maddesi ayrıca aranır. İki ölçü birbirinin yerine
geçmez, üst üste biner.

### 3. KARAR

**SIRADAKİ FAZ: F1a.** Bu gece koşar.

**F1a KABUL (hepsi zorunlu, hepsi yerel/geri alınabilir):**

1. **Yüzey tavanı kırmızı düşebilir hale gelir.** `--help` ana ekranında
   listelenen ürün verb'ü sayısı **beş** (+`version`, +`dev`); altıncısı
   eklenince test KIRMIZI düşer. Boş yeşil kontrolü (§8.2): denetim
   yazıldıktan sonra ana ekrana kasten altıncı satır eklenir, testin
   kırmızı düştüğü loglanır, satır geri alınır. Bugünkü 30 `dev` verb'ü
   ve `cli_test.sh`'in 310 ok'u düşmez.
2. **Disclosure kapısı KAPATILARAK geçilir, gevşetilerek değil.**
   `make disclosure` exit 0. Yol: **varsayılan saklamaktır** — liste
   dışı 41 isim artefaktlarda `(withheld)` olarak yeniden üretilir
   (mekanizma zaten var: `site/redact.py`, `site/field_stats.py`,
   `(withheld)` allowlist'te izinli). **`site/published-projects.txt`'e
   operatör kararı olmadan tek isim eklenmez.** Boş yeşil kontrolü:
   saklama geri alınınca kapı yeniden kırmızı düşer.
3. **`rabadon doctor` dört hata sınıfını adıyla yakalar.** Node sürüm
   uyumsuzluğu, ikili izin sorunu, PATH çakışması, eski kurulum
   kalıntısı. Dördü de fixture'da **kasten üretilir**; doctor her birinde
   (a) ne olduğunu, (b) neden, (c) insanın koşacağı **tek komutu** basar
   (§4.8). Sınıf ele alınmamışsa test kırmızıdır. Bugünkü doctor bu
   dördünü kontrol etmiyor (ölçüm: `rabadon doctor` → 6 satır: ikili
   sayısı, sürüm, sandbox, claude CLI, hook, ledger).
4. **Kurulum matrisi CI'da, dört hücre.** `ci.yml` bugün 2 işletim
   sistemi × **1 Node sürümü** (`node-version: '22'`). İkinci sürüm
   eklenir ve **`20` seçilir**, çünkü `release.yml` yayını Node 20 ile
   yapıyor (`release.yml:102,142`) — yani yayımlanan yol test edilen
   yol olur. Dört hücrenin dördünde `make all && make test && npm test`
   yeşil, `npm_install_test.sh` dördünde de koşmuş.
5. **CI main'de tamamen yeşil.** Kanıt rapordan kopyalanmaz:
   `gh run view <id>` çıktısı tutanağa yapıştırılır. Bugünkü hali
   kırmızıdır ve kırmızı zeminin üstüne adım atılmaz (§11).
6. **Kurulumdan çalışır guard'a kaç adım.** Sayı ölçülür ve yazılır.
   İki komut iddiası ölçülmeden yazılmaz.
7. **Ajan yüzeyi tablosu ölçüme dayanır.** Cursor için "destekleniyor"
   yazılmaz; ENVANTER (b) ölçümü **0 ledger satırı** diyor, tabloya
   satır satır ne yapıp ne yapamadığı ve bu sıfır yazılır (§4.11).

**F1a'nın KAPSAM DIŞI bıraktığı (F1n'e taşındı):** `npm publish`,
`v0.2.3` etiketi, `@rabadon` org'u, `NPM_TOKEN`, `npm view rabadon
version`, plugin paketinin yayını, sitedeki kurulum satırının
`npm i -g`'ye çevrilmesi (kâtip bunu F1n kapandıktan sonra yazar; bugün
yazarsa site çalışmayan bir kurulum satırı satar).

**BÜTÇE (§11):** F1a en fazla **5 işçi**, işçi başına 60 dakika tavanı,
paralel salınan işçiler aynı dosyaya dokunmaz — kart 2 (`site/`) ile
kart 4 (`.github/workflows/`) paralel, kart 1 (`native/cli_test.sh`) ile
kart 3 (`native/doctor*`) paralel, kart 5/6/7 tutanak işidir ve şefe
aittir. Para: sıfır. GitHub Actions dört hücre × ~6 dk, public repo,
ücretsiz.

**DURMA:** kart 2 ya da 4 iki kez üst üste aynı kırmızıyı verirse §13/2
uyarınca üçüncü denenmez, `UYANDIGINDA.md`'ye yazılır.

---

## 2026-08-26 · F1b ve F2'nin sırası değişti

**F2 öne alınır, F1b arkaya. Yeni sıra: F1a → F2 → F1b → F1n → F3.**

**Bunu gerektiren ölçüm.** §7/F1b "koşu 2'nin yirmi iki turluk logları
duruyor, beş dedektör bu logların üstünde çevrimdışı koşturulur" diyor
ve kabulü "rakam **ledger'dan** türetilmiş, elle yazılmamış" diyor.
Bu ikisi bugün birbirini tutmuyor:

- `reports/kosu/*.out` **22 dosya vardır** ama ledger değildir. İçerikleri
  ajanın düzyazı transkripti ve `[tool: Bash]` işaretleridir: yol yok,
  hata imzası yok, çıkış kodu yok, süit durumu yok. Dedektörlerin
  okuduğu alanlar (`native/signals.h`: `err_sig`, `sig`, `suite`, `seq`)
  bu dosyalarda **hiç yok**. Yani F1b yazıldığı gibi koşturulamaz;
  koşturulursa üretilen sayı elle uydurulmuş olur — kabulünün yasakladığı
  şeyin ta kendisi.
- Gerçek ledger `~/.rabadon/spool/` altındadır ve zengindir:
  **246.775 satır, 32 gün dosyası, 104 oturum, 2244 SIGNAL, 368 COUNTER,
  6 INJECT, 1 INJECT_HELD, 751 WOULD_BLOCK.** Ama içinde koşu 2'ye ait
  olan (`rabadon-kosu2:session`) **yalnız 20 SIGNAL satırı** var
  (18 `green_redefined`, 2 `scope_drift`) ve **0 INJECT**.
  Korpusun ağırlığı komşu projede: `stitchu:session` 2080 SIGNAL.

Yani F1b'nin varsaydığı "kendi koşumuz en güçlü kanıtımız" cümlesi
ölçümle çürüktür: kendi koşumuz 20 satır, komşu proje 2080. F2 (`rabadon
scan`) tam olarak bu korpusu okuyan alettir. **F1b'nin sayısı F2'nin
aletinden çıkmalıdır**, ayrı bir tek kullanımlık betikten değil — o
zaman "ledger'dan türetilmiş" iddiası aletin kendisiyle kanıtlanır.

### F2'ye SERTLEŞTİRME (§10a)

Korpusun sinyal dağılımı ölçüldü (`~/.rabadon/spool/*.jsonl`, tüm 32 gün):

| sinyal | korpustaki satır |
|---|---|
| `scope_drift` | 1905 |
| `green_redefined` | 333 |
| `root_migration` | 4 |
| `semantic_repeat` | 2 |
| `repeat` | **0** |
| `oscillation` | **0** |

F2 metni kullanıcıya "kaç tekrar, kaç salınım, kaç kök taşıma" göstermeyi
vaat ediyor. Ölçüm diyor ki 246 bin satırlık gerçek veride **tekrar ve
salınım bir kez bile ateşlememiş**, ve ateşleyenlerin %92'si
`scope_drift` — ki o enjekte etmiyor, yalnız ledger'a yazıyor
(ENVANTER (a)). Buradan iki sert madde doğar:

**F2-S1.** Sıfır ateşleyen sinyal ekranda **boş bir satır olarak
geçiştirilemez**. `n=0` olan her sinyal için çıktı "ÖLÇÜLMEDİ, bu
korpusta hiç ateşlemedi" der ve o sinyal **canlıya çıkmaz**. §4.3'ün
yüzde beş tavanı `n=0`'da hesaplanamaz; hesaplanamayan oran yeşil
sayılmaz. Sessizce sıfır basıp geçmek boş yeşildir (§8.2).

**F2-S2.** F2'nin kabul betiği, ekranda duran **her sayının yanında onu
üreten oturum yolunu** zaten istiyor; buna ek olarak **sinyal başına
`n` ve etiketlenen örnek sayısı** da yazılır. `n < 10` olan sinyal için
oran yazılmaz, ham sayı yazılır — 4 örnekten yüzde çıkarmak
"ölçülmemiş şey satılmaz"ın (§4.5) ihlalidir.

**F2-S3 (önkoşul).** F2'nin okuyacağı korpus, disclosure kapısının
saydığı 41 özel proje adını taşıyan korpusun aynısıdır. Bu yüzden
**F2, F1a'nın disclosure kartı kapanmadan açılmaz**: aksi halde ilk
ekran operatörün özel repo adlarını basar.

### F1b'ye SERTLEŞTİRME

**F1b-S1.** F1b'nin sayısı `rabadon scan` çıktısından türetilir, ayrı
betikten değil; tutanakta komut satırı ve çıktı yolu durur.
**F1b-S2.** F1b "kendi koşumuz" iddiasını yalnız `rabadon-kosu*:session`
kapsamı için kurar ve **n=20**'yi gizlemez. Korpusun geri kalanı
kullanılacaksa hangi projeden geldiği ve kaç satır olduğu yazılır;
"kendi verimiz" diye komşu projenin verisini göstermek §4.5 ihlalidir.

---

## Kart dışı, ölçülmüş, dokunulmadı (sonraki fazların işine yarar)

- **CI temiz makine kanıtı zaten var ve kimse kullanmamış.** `ubuntu-latest`
  ve `macos-15` iş kolları F0 kapanış commit'inde yeşil. ENVANTER (e)
  "temiz makinede koşum ÖLÇÜLEMEDİ" diyor — aslında ölçülmüş, GitHub'da
  duruyor. R7 kabulünün `2b` kırmızısı (bu makinede 1299,4 µs, tavan
  1000 µs) temiz bir referans ortam istiyordu; o ortam bugün CI'da var.
  Bu bir karar değil, sonraki şefin bakması gereken bir imkândır.
- `pages build and deployment` iş akışı da kırmızı (32922500146). Yayın
  yolu `vercel`, `pages` değil; ölü bir yayın yolu her push'ta kırmızı
  basıyor. Kart açılmadı.
- `rabadon doctor` bugün yerelde `all green` basıyor (6 kontrol, exit 0).
  Yeşil olması dört hata sınıfının ele alındığı anlamına GELMİYOR;
  kontroller farklı şeylere bakıyor.
- Korpusun tamamı UTF-8 olarak sorunsuz ayrıştı (`unparsable 0`), ama
  ENVANTER'in `grep -a` uyarısı geçerli: `grep -c` bazı gün dosyalarında
  sessizce boş dönüyor.
- `~/.rabadon/spool/` 71,2 MB ve **30 günlük saklama** ile budanıyor
  (`rabadon doctor`). Yani F2'nin korpusu her gün eriyor. Kart açılmadı,
  ama F2 geciktikçe kanıt küçülüyor.
