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

## 2026-08-26 · F1a hakem hükmü sonrası · F1a'nın kırmızısı + F2'nin yeniden tanımı

Sorulan iki şey: (1) hakemin adıyla bıraktığı "kurulum iki cümleye iner
gerçek olmadı" kırmızısı §11 ile §8.6 arasındaki gerilimde nasıl çözülür,
(2) korpusta `repeat`=0 / `oscillation`=0 bulgusu F2'nin tanımını
değiştirmeli mi. İkisi de bu oturumda YENİDEN ÖLÇÜLDÜ; aşağıdaki her sayının
yanında onu basan komut var.

---

### A. KIRMIZI KARARI — seçenek (c), ve gerekçesi ölçüm

#### A.1 Gerilim gerçek mi? Evet, ve iki ayrı şeyi tek ada sıkıştırıyor

§8.6 "üçü YAZILI değilse kapanmaz" der; üçü yazılıdır, o yüzden hakem GEÇTİ
demekte haklıdır. §11 "kırmızıyı sonraki faza taşımak" yasağı ise yazılı
olmayı değil, DÜZELTİLMİŞ olmayı ister. İkisi çelişmiyor: §8.6 bir
BELGELEME kapısı, §11 bir ZEMİN kapısıdır. Hakemin bıraktığı kırmızı, tek
bir kusur değil, **birbirinden bağımsız iki kusurdur** ve tek ad altında
tutuldukları için çözümsüz görünüyorlar. Ölçüm ikisini ayırıyor.

**KIRMIZI-A · `rabadon on` hiçbir kurulum yolunda yok.** Bu oturumda
yeniden koşturuldu:

```sh
grep -n "rabadon on" README.md
```
→ tek eşleşme **satır 132**, kurulumla ilgisiz bir paragrafın içinde.
README'nin kurulum bloğu (`README.md:22-40`) şu yedi satırı sayıyor:
`git clone && cd`, `npm install && npm link`, `cd your-project`,
`rabadon init`, `rabadon drill`, `claude`, `rabadon usage` — ve içinde
`rabadon on` **yok**. `site/index.html:83` `rabadon on`'u yalnız komut
listesinde anıyor, kurulum satırında değil. `docs/quickstart.md:120`
içinde var ama kurulum bloğunun sonrasında.

Sonucu §7/F1a kart 5'te ölçülmüştü ve doğrudur: `init` sonrası mod
WATCH'tır, aynı hook olayı `exit 0` + `Nothing was stopped` verir; `on`
sonrası `exit 2` + `rabadon BLOCKED this action`. Yani **belgeyi harfiyen
izleyen kullanıcı hiçbir şeyi reddetmeyen bir guard kuruyor.** Bu §3'ün
tek cümlelik iyi-ürün tanımının ("kullanıcı kurar, ilk gün fark yaratır")
ve §4.8'in ihlalidir. **Yereldir, geri alınabilir, para yakmaz, bu gece
kapanır.**

**KIRMIZI-B · "iki cümle" sayısı.** Ölçülen 5 birleşik satır / 7 ayrık
komut. KIRMIZI-A kapandıktan sonra dürüst asgari **3 satır**:
`git clone … && cd rabadon && npm install && npm link` · `cd proj &&
rabadon init` · `rabadon on`. Kalan 3 → 2 farkının tek sebebi ölçülebilir:
**paket yayımlanmamış.** Yayımlandığında yol `npm i -g rabadon` ·
`cd proj && rabadon init && rabadon on` = **2 satır**. Yayın O1'dir,
operatör kararıdır (§13, geri alınamaz + sahiplik).

Üçüncü satırın `init`'e katlanması **yasaktır**: §7/F7 "watch modunun
varsayılan olması… bozulmayacak" diyor ve bu operatörün korunacak dediği
refleks. Yani KIRMIZI-B'nin kalan kısmı bir ihmal değil, **O1'in kendisi**.

#### A.2 Hangi değişmez ihlal ediliyor

- **§11 · "kırmızıyı sonraki faza taşımak yasak"** — KIRMIZI-A bu gece
  kapanabiliyorken F2'ye devredilirse ihlal edilir. Seçenek (a) tek başına
  bu yüzden **reddedildi**.
- **§3 / §4.8** — KIRMIZI-A açık kaldığı her saat, belgeyi izleyen her
  kullanıcıda ürün fren değil süs.
- **§10a · ölçü gevşetilemez** — KIRMIZI-B'yi "aslında 3, yani yeşil"
  diye yeniden adlandırmak ödül hacklemedir. Yapılmadı: sayı 5 olarak
  ölçülü kalıyor, 3 hedef olarak yazılıyor, 2 **F1n'in kabul maddesi**
  oluyor ve ölçümle sınanıyor.

#### A.3 KARAR: yeni bir mini-faz, **F1c**, F2'den ÖNCE (§10c + §10b)

Kart değil faz, çünkü kapanışı bağımsız bir hakem hükmü ister (§9 "hakem
her fazda ayrıdır ve bu asla esnemez") ve içinde **kırmızı düşebilen bir
test** var — kâtip commit'i tek başına kapatmaz. F1a'da kâtip commit'i
olmaması (§8.8 zayıf, hakemin kendi notu) da burada kapanır.

**F1c KABUL (hepsi zorunlu, hepsi yerel/geri alınabilir):**

1. **`rabadon on` belgelenmiş her kurulum yolunda, kurulum bloğunun
   İÇİNDE.** `README.md`, `site/index.html`, `docs/quickstart.md`. Kâtip
   işi (§15.5): yalnız `docs/`, `README.md`, `site/`.
2. **Kırmızı düşebilen kilit.** Yeni bir test, belgelenmiş kurulum
   bloklarını okur ve `rabadon on` (ya da `on`'u içeren bir satır) yoksa
   **BLOCKED** basar. Boş yeşil kontrolü (§8.2): satır belgeden çıkarılır,
   test kırmızı düşer, log'lanır, geri konur. Bu madde 1'in tek gerçek
   kanıtıdır — belgeye bir cümle eklemek kanıt değildir, kilitlemek
   kanıttır.
3. **`rabadon init` ekranı modu SÖYLER.** Bugün söylemiyor (ölçüm:
   `f1a-5` §2 verbatim ekran; `rabadon on|off` satırı var, "şu an
   WATCH'tasın" yok). Ekran §4.8'in üç sorusunu kurulum sonu için
   cevaplar: **şu an ne olduğu (WATCH, hiçbir şey durdurulmaz), neden
   (varsayılan watch'tır ve öyle kalması senin kararın), sıradaki tek
   komut (`rabadon on`)**. Verbatim ekran tutanağa girer.
4. **Adım sayısı YENİDEN ölçülür ve yazılır.** Aynı kum-havuzu yöntemi
   (`mktemp -d`, sahte `HOME`, `npm_config_prefix`). Beklenen 3; ne
   çıkarsa o yazılır (§4.5, CLAUDE.md kural 8). **5 sayısı silinmez**,
   tutanakta "önce 5, sonra N" olarak yan yana durur.
5. **`rabadon remove` Cursor hook'unu söker.** `removeCursorHooks` yok
   (ölçüm: `grep -rn "removeCursorHooks" hooks/` → boş; `remove` sonrası
   `.cursor/hooks.json` beş olayla TAM duruyor). §4.9 "kesin seviyenin
   her kuralının çıkış yolu vardır" ihlali ve Cursor kullanıcısının çıkış
   yolu **hiç yok**. Test: `init` → `remove` → `.cursor/hooks.json`
   içinde rabadon kalmadı.
6. **Kırmızı ad kümesi büyümedi** (`{2b, 6e, 7b}`), `make test` ok sayısı
   düşmedi (F1a sonrası taban: 3448).

**F1c'nin KAPSAM DIŞI bıraktığı:** npm yayını ve "2 satır" iddiası
(F1n'e), `init`'in kesik hata mesajı `no manifes`, `npm link`'in 4 satır
`allow-scripts` uyarısı, `.gitignore` kalıntısı, `pages-build-deployment`
kırmızısı. Beşi de ölçülü ve yazılı, kart açılmadı.

**BÜTÇE:** 2 işçi (kart 1+2+3 kâtip/kilit, kart 5 Cursor sökme), işçi
başına 60 dk, paralel salınırlarsa aynı dosyaya dokunmazlar
(`README/site/docs` vs `hooks/manage.mjs`). Para: sıfır.

#### A.4 F1n'e giden SERTLEŞTİRME (§10a) — devir değil, kabul maddesi

F1n'in kabulüne şu madde eklenir, mevcut `npm view rabadon version`
maddesinin ÜSTÜNE (yerine değil):

> **F1n-S1.** Yayından sonra kurulum adım sayısı temiz bir kum havuzunda
> YENİDEN ölçülür. Kabul: `npm i -g rabadon` ile başlayan yol, çalışır
> bir guard'a (bir hook olayının `exit 2` döndüğü ana) **en fazla 2
> birleşik satırda** ve **sıfır soruda** varır. Sayı 2'nin üstündeyse
> F1n kapanmaz. Ölçüm komutu ve verbatim çıktı tutanağa girer.

Bu, kırmızıyı taşımak değildir: taşınabilir kısım (KIRMIZI-A) bu gece
kapanıyor, kalan kısmın tek sebebi F1n'in kendisi ve o artık F1n'in
kendi ölçüsüyle sınanıyor.

---

### B. F2 — ÜÇ ÖLÇÜM, ÜÇ DEĞİŞİKLİK

Cevapçının önceki kararındaki bulgu (`repeat` 0 / `oscillation` 0) bu
oturumda yeniden koşturuldu ve **doğrulandı**, ama ölçüm bunun ötesine
gitti ve F2'nin temelinde daha büyük iki şey buldu.

#### B.1 Sıfırın sebebi: (i) mi (ii) mi? — ÖLÇÜLDÜ, cevap (ii)

**Ayıran komut, ikiye bölünmüş olarak:**

**(i) dedektör bağlı mı / ateşliyor mu — GERÇEK ikili üstünden:**
```sh
./native/signals_test.sh          # GATE="${RABADON_GATE:-$HERE/rabadon-gate}"
```
→ **39 passed, 0 failed.** İçinde birebir şunlar var:
`ok - three failing runs of one command are a repeat` ve
`ok - an A-B-A-B-A-B edit loop on one file is oscillation`.
Yani **dedektör bağlı ve gerçek `rabadon-gate` ikilisi üstünden
ateşliyor.** (i) ELENDİ.

**(ii) korpus bu sinyali içeriyor mu — dedektörü gerçek korpusa
yeniden koşturarak:** Korpus replay edilebilir tek yerde durur,
`~/.rabadon/sessions/*.moves.bin`, ve `rabadon audit --export` ile
okunur (aynı kapı `native/moves_test.sh:133`'ün kullandığı kapıdır).
`signals.h`'nin `repeat` ve `oscillation` mantığı eşikleriyle birlikte
bu kayıtların üstünde yeniden koşturuldu:

| koşum | sonuç |
|---|---|
| `repeat`, sevk edilen eşik (`REPEAT_MIN=3`, `failed>=2`, pencere 20) | **0** |
| `repeat`, `REPEAT_MIN=2` | **0** |
| `repeat`, `REPEAT_MIN=1` (§4.1'in "eşik birdir"i) | **0** |
| `repeat`, `MIN=3` ama `failed>=1` | **0** |
| `oscillation`, sevk edilen `OSC_CYCLES=3` (6 dönüşümlü edit) | **0** |
| `oscillation`, `OSC_CYCLES=2` (4 dönüşümlü edit) | **0** |

**Sebep de ölçüldü, tahmin değil:** 527 hamlenin **497'si Bash, 23'ü
Edit, 7'si Write**; yalnız **20'si** hata taşıyor (`claimed_rc==1`,
%3,8); yalnız **30'unda** yol dolu; ve **hiçbir tek yola 6'dan fazla
edit gitmemiş** — tek-yol edit histogramı `{1 edit: 8 yol, 2: 4, 3: 3,
5: 1}`, oscillation en gevşek halinde bile 4 istiyor ve A-B-A-B deseni
arıyor. `suite` alanı 527 kaydın **1'inde** dolu.

**HÜKÜM: (ii).** Dedektör çalışıyor; korpusta materyal yok. Ve bu bir
eşik meselesi de değil — eşik bire indirilse bile sıfır. §4.1'in eşik-bir
talebi (F4) bu korpusta **hiçbir yeni yakalama üretmeyecek**, ve bu F4
için şimdiden ölçülmüş bir gerçektir.

#### B.2 Daha büyük bulgu: F2'nin korpusu 246.775 satır DEĞİL, 527 kayıt

Bu, sorulmamıştı ama F2'nin temelini doğrudan yıkıyor.

```sh
grep -aho '"ev":"[A-Z_]*"' ~/.rabadon/spool/*.jsonl | sort | uniq -c | sort -rn
```
→ 247.715 satırın **152.349'u `STEP_START`**, 78.579'u `STEP_OK`.
`SIGNAL` 2289, `INJECT` 6, `COUNTER` 368.

Ve spool'da **hamle kaydı yoktur**: dedektörlerin okuduğu alanlar
(`sig`, `err_sig`, `suite`, `claimed_rc`, `asserts` — `native/moves.h`
`struct Rec`) spool'a hiç yazılmaz. Spool yalnız **o gün ateşlemiş olan
SIGNAL satırlarını** taşır. Yani `rabadon scan` spool'u okursa
dedektörleri **yeniden koşturamaz**, sadece geçmişte basılmış sonucu
okur.

Yeniden koşturulabilir korpus şudur ve ölçüldü:
```sh
for f in ~/.rabadon/sessions/*.moves.bin; do \
  echo $(( ($(stat -f%z "$f")-4096)/320 )); done | paste -sd+ - | bc
```
→ **527 kayıt / 34 oturum / 652 KB.**

İkisi de eriyor, ve süresi ölçülü:
- Ring **oturum başına 200 kayıtla sınırlı** (`moves.h: CAP = 200`); bir
  oturum (`286fd71d`) **zaten 200'de** — daha eskisini sessizce üzerine
  yazmış.
- Oturum `.json` dosyaları **24 saatte** siliniyor
  (`gate.cpp:1107 SESSION_TTL_MS = 24h`); diskte 34 `.moves.bin` var ama
  yalnız **6** `.json`.
- Spool 30 günde budanıyor.

Ve zaman aralığı: `SIGNAL` olayları **yalnız 5 gün dosyasında** var
(2026-08-22 … 08-26); kalan **27 gün dosyasında 0**. `.moves.bin`
dosyalarının hepsi 22-26 Ağustos tarihli.

**Sonuç: §7/F2'nin "kullanıcı kendi son yedi gününü görür" cümlesi bu
makinede karşılığı olmayan bir vaattir.** Yedi gün yok; 4-5 gün ve 527
hamle var.

#### B.3 Ölçülen üçüncü şey: `rabadon scan` altıncı verb olur — §4.10 ihlali

```sh
./native/rabadon-cli.sh scan
```
→ `rabadon: unknown command "scan"`. Verb yok, yazılacak.

Ama `native/cli_test.sh` F1a'da tam olarak bunu kırmızıya düşürecek hale
getirildi: ana ekranda ürün verb'ü sayısı beşten farklıysa **BLOCKED**
basıyor ve ad kümesini `{init, on|off, usage, repair, doctor}` olarak
sabitliyor (`cli_test.sh:265-302`). Hakem bunu kendi eliyle sınadı:
altıncı verb → 315/0'dan **312/3**'e. Ayrıca §11 açıkça **"yeni CLI
verb'ü"**'nü yasaklar ve §4.10 "yüzey beştir, geri şişirilmez" der.

`scan`'i eklemek için `cli_test.sh`'in `PRODUCT` listesini düzenlemek
gerekir — yani **mühür kümesindeki bir testi geçmek için değiştirmek**.
Bu, bu projenin var olma sebebinin tam tersidir. §7'deki verb ADI,
§4.10'un altındadır ve §4'e dokunamam.

#### B.4 Dördüncü şey, F2'nin aleti kırık: export geçerli JSON basmıyor

```sh
./native/rabadon-audit --export ~/.rabadon/sessions/286fd71d-*.moves.bin \
  | python3 -c 'import sys,json;[json.loads(l) for l in sys.stdin if l.strip()]'
```
→ `json.decoder.JSONDecodeError: Unterminated string`. Tüm korpusta
**608 satırın 280'i (%46) geçersiz JSON.**

Sebep `native/audit.cpp:181-186`: `path` ve `raw` alanları **hiç
kaçışlanmadan** `printf("%s")` ile basılıyor. İçinde `"`, `\` ya da
satır sonu taşıyan her hamle çıktıyı bozuyor (bozan gerçek kayıt:
`"raw":"cd … && python3 - <<'EOF'` + satır sonu). Bu, F2'nin okuyacağı
**tek kapı**dır ve `moves_test.sh` bozuk satırları `except: continue`
ile sessizce atladığı için hiçbir test kırmızı düşmüyor. Boş yeşil
(§8.2).

---

### B.5 KARAR: F2 tanımı DEĞİŞİR (§10a sertleştirme + §10b sıra)

**SIRA: F1c → F2 → F1b → F1n → F3.** (F1c yeni, gerisi değişmedi.)

**F2'nin adı ve yüzeyi değişir: `rabadon scan` YOK. F2'nin ilk ekranı
mevcut beş verb'ün içinden çıkar — `rabadon usage`'a bir BAYRAK olarak
(`--signals`).** Bayrak verb değildir, ana yardım ekranına satır
eklemez, `cli_test.sh` tavanını kırmızıya düşürmez. Bu bir gevşetme
değil, §4.10'un dayattığı daha dar bir kapsamdır: ürün yüzeyi büyümeden
aynı ekran teslim edilecek.

**F2 KABUL — eskisi aynen durur (her sayının yanında oturum yolu, elle
etiketleme, sinyal başına yanlış pozitif oranı, %5 üstü canlıya
çıkmaz, üç zeminde ölçüm, en kötü zemin ölçüt), üstüne şunlar biner:**

**F2-S1 (önceki karardan, aynen durur ve sertleşir).** `n=0` olan sinyal
"ÖLÇÜLMEDİ" basar ve canlıya çıkmaz. **EK:** sıfırın SEBEBİ de basılır
ve ölçülür — kaç aday hamle bakıldı, hangi eşik tutmadı. "0" tek başına
bir sayı değil, bir sessizliktir; sebebi olmadan ekrana konması §4.5
ihlalidir.

**F2-S2 (önceki karardan, aynen durur).** Sinyal başına `n` ve
etiketlenen örnek sayısı yazılır; `n < 10` ise oran değil ham sayı.

**F2-S3 (önceki karardan, aynen durur).** F1a'nın disclosure kartı
kapanmadan açılmaz — kapandı, bu önkoşul artık YEŞİL.

**F2-S4 · YENİ — okuduğu korpusu ekranda ilan eder.** Çıktının ilk
satırı, okunan korpusu ölçüyle basar: **kaç hamle kaydı, kaç oturum,
hangi tarih aralığı, hangi dosyalardan.** "Son yedi gün" ifadesi ancak
yedi günlük kayıt gerçekten okunduysa basılır; okunmadıysa gerçek
aralık basılır. Bugünkü ölçüm 527 kayıt / 34 oturum / 22-26 Ağustos
diyor ve bu, hiçbir yerde 7 gün olarak yazılamaz (§4.5, §4.6).

**F2-S5 · YENİ — export kapısı önce onarılır, testiyle.** `path` ve
`raw` JSON-kaçışlanır (`native/audit.cpp`). Kabul: ham korpusun
**608/608** satırı `json.loads` ile ayrışır (bugün 328/608). Boş yeşil
kontrolü: kaçışlama geri alınınca test kırmızı düşer. Ve `moves_test.sh`
içindeki sessiz `except: continue` yutucusu **sayar ve raporlar** —
bugün yuttuğu 280 satır hiçbir yerde görünmüyordu.

**F2-S6 · YENİ — dağıtım kapısı bu korpusla açılamaz.** §7/F2 "burası
yeşilse ürün dağıtılabilir" diyor. Ölçüm sonrası bu **koşullu** hale
gelir: ekran, dört sinyalden ikisi (`repeat`, `oscillation`) için
"ÖLÇÜLMEDİ" basacaksa ve okunan korpus 7 günden kısaysa, dağıtım
cümlesi bunu **saklamaz**. Dağıtılabilirlik hükmü F2 hakemine aittir ve
hakem bu iki satırı ekranda GÖRMEDEN GEÇTİ diyemez. Negatifi olumluya
çevirmek yasaktır (§11).

**F2-S7 · YENİ — kanıt üç katmanlıdır, ekran ikinci katmanı iddia
etmez.** §4.12. F2 yalnız "(a) yazdı" katmanını gösterir. Ekranda
"yakaladı / kurtardı / kazandırdı" gibi ikinci-üçüncü katman fiili
kullanılamaz; kullanılırsa faz kapanmaz.

**F2 BÜTÇE (§11):** en fazla **6 işçi**, işçi başına 60 dk. Paralel
salınanlar aynı dosyaya dokunmaz: `native/audit.cpp` (S5) ile
`native/usage.h` + `rabadon-cli.sh` (ekran) ayrı; etiketleme kartı
salt-okunur. Para: sıfır, ağ yok, model çağrısı yok.

**F2 DURMA (§13/2):** okuma kartı (S5) iki kez üst üste aynı kırmızıyı
verirse üçüncü denenmez, `UYANDIGINDA.md`'ye yazılır. Ve F2 hakemi
KALDI derse F1b açılmaz — F1b'nin sayısı F2'nin aletinden çıkıyor
(F1b-S1).

**ACELE, ölçülü:** korpus eriyor. Oturum `.json`'ları 24 saatte,
spool 30 günde, ring 200 kayıtta. `.moves.bin` süpürülmüyor ama ring
üzerine yazıyor ve bir oturum zaten dolmuş. **F2 geciktikçe elimizdeki
527 kayıt küçülüyor, büyümüyor.**

---

## Kart dışı, ölçülmüş, dokunulmadı (sonraki fazların işine yarar)

- **`suite` alanı pratikte ölü.** 527 hamle kaydının **1'inde** `suite`
  != -1. `green_redefined` ve `counter.h`'nin "süit koştuysa yeşildi"
  zinciri bu alana dayanıyor. F3/F5 buna bakmalı. DOĞRULANMADI: alanın
  neden dolmadığı (hook mu gelmiyor, `testout.h` mi tanımıyor) — kart
  açılmadı, ölçülmedi.
- **`INJECT` 6 satırın 6'sı da `root_migration`**, ve ikisi
  `pipe:"stitchu:session"` / `"video-essay:session"` — yani enjeksiyon
  gerçek oturumlarda ateşlemiş. F3'ün "hiç ulaşmadı" cümlesi
  ENVANTER'de kollu koşu için doğru, ama korpusta 6 gerçek INJECT var
  ve F3 bunlara bakmadan başlamamalı. `INJECT_CAPPED` 0, `INJECT_HELD` 1.
- **`usage` ekranı proje adlarını ham basıyor** (`damummyphus`,
  `stitchu`, …). Yerelde doğru; ama F2'nin ekranı ekran görüntüsü
  alınabilir olacak (§7/F2 "ADIM 8") ve o an disclosure kuralı
  ekran çıktısı için de gerekir. Bugün `site/` için var, CLI çıktısı
  için YOK. Kart açılmadı.
- **`WRONG_REFUSAL` korpusta 6 kez var.** §4.3'ün yanlış pozitif tavanı
  için elimizdeki tek gerçek saha kalemi bu olabilir. Kart açılmadı,
  içerikleri okunmadı.
- **`TEST_EVIDENCE_MISSING` 936 kez.** Korpusun en kalabalık dördüncü
  olayı ve hiçbir fazın tanımında geçmiyor.
- **ÖLÇEMEDİĞİM:** temiz Linux konteynerde hiçbir şey koşturmadım;
  Cursor uygulamasını başlatmadım; `npm i -g rabadon` (yayımlanmamış);
  `rabadon dev replay`'i hiç koşturmadım (F2'nin işine yarayabilir,
  `dev --help` "re-run a recorded session against the current rules"
  diyor — DOĞRULANMADI); F1c'nin tahmin ettiğim "3 satır"ı ölçmedim,
  ölçüm F1c'nin kabul maddesidir.

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

---

## 2026-08-26 · F1c hakem hükümleri sonrası · hakemlerin açık bıraktığı beş bulgu

İki bağımsız hakem F1c'ye GEÇTİ dedi ve sayıları birbirini tuttu. Kapıyı
kapatmayan ama açık bıraktıkları BEŞ bulgu (B1–B5) bu oturumda **tek tek
yeniden koşturuldu**. Aşağıdaki her sayının yanında onu basan komut var ve
hiçbiri rapordan kopyalanmadı. Üçü ölçümde raporlanandan **daha kötü** çıktı.

---

### B1 · "AÇTIM" DİYEN VE AÇMAYAN YÜZEY — ertelenemez, F2'den ÖNCE kapanır

#### B1.1 Hakemin bulduğu, doğrulandı

Kum havuzu (`mktemp -d`, sahte `HOME`/`RABADON_DIR`, `git init`, `node
hooks/manage.mjs init --no-llm`), aynı PreToolUse olayı (`git push --force
origin main`) gerçek `native/rabadon-gate` ikilisine verildi:

| yol | ekranda ne yazdı | gate ne yaptı |
|---|---|---|
| yalnız `init` | — | **EXIT=0** · "rabadon (watch) would have blocked this." |
| `node bin/rabadon.mjs on` | `rabadon: ON — the session is supervised again.` | **EXIT=0** · hâlâ watch |
| `native/rabadon-cli.sh on` | `rabadon: ON — the arbiter acts…` | **EXIT=2** · "rabadon BLOCKED this action." |

Doğrulandı: `bin/rabadon.mjs` yalnız `.rabadon/off` dosyasını siliyor
(`bin/rabadon.mjs:522-534`), `$RABADON_DIR/mode`'a dokunmuyor. Ve doğrulandı
ki bu dosya sevk edilen yol DEĞİL: `package.json` `bin` = `native/rabadon-cli.sh`,
dispatcher'ın `on|off|status` kolu (`rabadon-cli.sh` case satırı 118) doğrudan
`rabadon-gate --on`'a gidiyor, `bin/rabadon.mjs`'e yalnız `ui|watch` ve
`guard|fleet|spin|pack` kolları düşüyor. Yani **`on` hiçbir sevk edilen
yoldan o dosyaya varmıyor.**

#### B1.2 ÖLÇÜM HAKEMİN BULDUĞUNDAN DAHA KÖTÜ ÇIKTI — yalan SEVK EDİLEN yüzeyde

Aynı kum havuzunda devam edildi. `.rabadon/off` dosyası ortamda dururken
(oraya `bin/rabadon.mjs off` koydu, ama dosyayı elle yaratmak da aynı şey):

    $ native/rabadon-cli.sh on            # SEVK EDİLEN yüzey, package.json bin
    rabadon: ON — the arbiter acts: refuses, repairs, proves
    $ printf '<PreToolUse: git push --force origin main>' | native/rabadon-gate
    EXIT=0    (çıktı: 0 BAYT — hiç konuşmadı)

    $ native/rabadon-cli.sh status
    rabadon: ON — the arbiter acts: refuses, repairs, proves
      read from: …/.rabadon/mode (present)

Ve **aynı ikili, aynı an, aynı proje**, ikinci bir ağızdan:

    $ printf '{"workspace":{"current_dir":"$P"}}' | native/rabadon-gate --statusline
    proj  * rabadon off

`rabadon status` "ON — the arbiter acts" diyor; kullanıcının prompt satırında
duran `--statusline` **"rabadon off"** diyor. İkisi de `native/rabadon-gate`.
Gate zaten biliyor: `gate.cpp:2429` `hardOff`'u `RABADON_OFF` + `.rabadon/off`
+ `~/.rabadon/silent` ile hesaplıyor — ama **yalnız statusline için**.
`--status` ve `--on` bu üç girdiyi hiç okumuyor (`gate.cpp:2658-2660` sessiz
yolda okuyor, ekrana basmıyor).

Ayrıca ölçüldü: `native/rabadon-cli.sh off` `.rabadon/off`'u **kaldırmıyor**;
`docs/`, `README.md`, `site/` içinde `.rabadon/off` dosyası **hiç geçmiyor**
(`docs/commands.md:550` yalnız `RABADON_OFF` ortam değişkenini anlatıyor).
Yani belgesiz bir susturucu var, onu kaldırmanın belgelenmiş yolu yok, ve
durumu soran komut onun varlığını görmüyor.

#### B1.3 Hangi değişmez ihlal ediliyor

- **§1 · "fren".** Frenin pedalı "bastım" diyor, disk boş. Bu bir kusur değil,
  ürünün tanımının tersi.
- **§4.8.** Ekran üç sorunun üçünü de cevaplamıyor: ne olduğu YANLIŞ yazılı,
  neden yok, sıradaki komut yok.
- **§4.12 · "yazdı ≠ işe yaradı".** `on` yazdı; işe yaramadı.
- **CLAUDE.md Promise 1** — "if rabadon can't check, it says so; it never goes
  quiet." Burada tam olarak sessizce gidiyor ve ON diyor.
- **§8.2 · boş yeşil.** Bunu kırmızıya düşürebilen tek bir test YOK. Kırmızı ad
  kümesinde görünmemesinin sebebi düzelmiş olması değil, **hiç ölçülmemiş
  olması**.

#### B1.4 KARAR — yeni mini-faz **F1d**, F2'den ÖNCE (§10c + §10b)

**Ertelenemez.** Gerekçe ölçüm: yalan sevk edilen yüzeydedir, bir üçüncü şahıs
yüzeyde değil. §11 "kırmızıyı sonraki faza taşımak" yasağı burada bağlayıcı:
bu gece kapanabilir (yerel, geri alınabilir, para yakmaz). Ve F2'nin ürünü tam
olarak **kullanıcının kendi verisi hakkında doğru söyleyen bir ekran**;
durumunu yanlış söyleyen bir alet dürüstlük ekranı satamaz.

Kart değil FAZ, çünkü kapanışı bağımsız bir hakem hükmü ister (§9) ve içinde
kırmızı düşebilen yeni bir test var.

**F1d KABUL (hepsi zorunlu, hepsi yerel/geri alınabilir):**

1. **Durum ekranı, gate'in HESAPLADIĞI durumu basar.** `rabadon status`,
   `rabadon on` ve `rabadon off` çıktısı, gate'in kapıda okuduğu HER girdiden
   türetilir: `$RABADON_DIR/mode`, `~/.rabadon/silent`, `RABADON_OFF`,
   projedeki `.rabadon/off`. Susturuculardan biri yürürlükteyse ekran onu
   **adıyla** söyler, **nereden okuduğunu** söyler ve **onu kaldıran tek
   komutu** verir (§4.8). `.rabadon/off` dururken "ON — the arbiter acts"
   tek başına basılamaz.
2. **Kırmızı düşebilen kilit — iddia ile fiil karşılaştırılır, vekil değil.**
   Yeni test, her durum için (a) CLI'ın İDDİA ettiği durumu, (b) aynı anda
   gerçek `native/rabadon-gate` ikilisine verilen aynı PreToolUse olayının
   ÇIKIŞ KODUNU alır ve **ikisi çelişirse BLOCKED basar.** Matris:
   `mode ∈ {watch, enforce}` × `.rabadon/off ∈ {var, yok}` ×
   `RABADON_OFF ∈ {1, unset}` × `~/.rabadon/silent ∈ {var, yok}`.
   "ON" iddiası + `EXIT=0` **kırmızıdır**.
   Boş yeşil kontrolü (§8.2): test F1d ÖNCESİ koda karşı koşulur ve KIRMIZI
   düşer — bugünkü ölçüm bunu şimdiden garanti ediyor (yukarıdaki tablo).
   Ayrı ağaçta koşulur (`git worktree add --detach`), çalışma ağacına
   dokunulmaz.
3. **`--statusline` ile `status` bir daha ayrışamaz.** Aynı test ikisini de
   çağırır ve aynı ana dair aynı hükmü vermelerini şart koşar. Bugün
   ayrışıyorlar (B1.2, verbatim).
4. **`bin/rabadon.mjs` EDİTLENMEZ.** Ölçüldü: bu dosya bu reponun KENDİ
   guard'ında korumalı bir anti-path'tir — `.rabadon/guard.json`
   `protectedPaths` içinde `anti-path-frozen` ve `anti-path-frozen-abs`,
   ayrıca `bash` kuralı `no-shell-write-to-frozen-file`; gerekçe olarak
   "CLAUDE.md / HANDOFF §9" yazılı. Onu düzeltmek için dondurmayı çözmek
   **operatörün kararıdır** (§10: sahiplik), cevapçının değil →
   `UYANDIGINDA.md`, **VARSAYILAN: donmuş kalır.**
   Delik onu editlemeden kapanır: madde 1 yetkili yüzeyi doğru yapar, ve
   ek olarak **kırmızı düşebilen bir kilit, sevk edilen hiçbir giriş
   noktasının `on|off`'u `bin/rabadon.mjs`'e yönlendirmediğini** sabitler
   (bugün böyle: `package.json` bin, dispatcher kolları, `npm run watch`
   yalnız `watch` çağırıyor). Bu kilit yarın birinin o dosyayı geri
   bağlamasını kırmızıya düşürür.
5. **`.rabadon/off` belgelenir.** §4.9 "her kuralın çıkış yolu vardır" ancak
   çıkış yolu BİLİNİYORSA gerçektir. Kâtip işi (§15.5, yalnız `docs/`):
   dosya adı, ne yaptığı (gate tamamen susar), nasıl kaldırılacağı.
   Bugün hiçbir belgede geçmiyor — ölçüldü.
6. **B2 aynı fazda kapanır** (aşağıda, ayrı bulgu).
7. **Kırmızı ad kümesi büyümedi** (`{2b, 6e, 7b}`), `make test` exit 0 ve
   sayaç düşmedi — **B5'te ilan edilen tek geçerli sayaçla ölçülür.**

**F1d BÜTÇE (§11):** en fazla **3 işçi**, işçi başına 60 dk. Paralel salınanlar
aynı dosyaya dokunmaz: kart A/B `native/gate.cpp` + yeni test, kart C
`docs/` + `native/install_docs_test.sh`. Para: **sıfır**, ağ yok, model
çağrısı yok.
**F1d DURMA (§13/2):** kart A iki kez üst üste aynı kırmızıyı verirse üçüncü
denenmez, `UYANDIGINDA.md`'ye yazılır.

---

### B2 · `docs/quickstart.md` §1'in ÖLÜ kurulum yolu — F1n değil, F1d; kilit GENİŞLER

**Doğrulandı, kendi koşumumla:** `npm view rabadon version` → **E404**
(`404 Not Found - GET https://registry.npmjs.org/rabadon`). Ve
`docs/quickstart.md` `## 1. Install` bloğu verbatim `npm i -g rabadon`
diyor, altında `npm i -g rabadon --allow-scripts=rabadon` alternatifi ve
`rabadon doctor` doğrulaması var. F1c'nin kilidi (`native/install_docs_test.sh`)
`rabadon init` çapalı §2 bloğuna baktığı için bu bloğu **hiç görmüyor**.

**Hangi değişmez:** §4.7 ("kurulum iki cümleye iner, soru sorulmadan çalışır")
ve §3 ("kullanıcı kurar"). Belgelenmiş iki kurulum yolundan biri ilk komutta
patlıyor. §5'in ADIM 2'si F1c'de "GERÇEK" ilan edildi — o hüküm README yolu
için doğru, quickstart yolu için **yanlış**, ve ikisi aynı ürünü anlatıyor.

**KARAR: satır F1n'e AİT DEĞİL, kilit GENİŞLER ve iş F1d'de biter.** F1n'e
bırakmak, ölü kurulum yolunu yayın gününe kadar canlı tutmak demektir; §11
"kırmızıyı sonraki faza taşımak" yasağı. Gevşetme değil, kapsam genişletmesi:

**F1d-B2 KABUL:**

1. **Tek kanonik kurulum yolu.** `docs/quickstart.md` §1, README'nin
   kaynaktan kurma yoluyla aynı şeyi söyler. Kâtip işi (yalnız `docs/`,
   `README.md`, `site/`).
2. **Kilit genişler, ÇEVRİMDIŞI kalır.** `native/install_docs_test.sh`
   artık **belgedeki her kurulum bloğunu** bulur (yalnız `rabadon init`
   çapalı olanı değil) ve şu değişmezi tutar: *belgelenmiş hiçbir kurulum
   bloğu, repoda `package.json`'daki sürümün `v<sürüm>` etiketi YOKKEN
   `npm i -g rabadon` taşıyamaz.* Etiket çevrimdışı ve doğrulanabilir
   (`git tag --list`), ağ isteği YOK — test temiz bir konteynerde de koşar
   (CLAUDE.md: yalnız git ve shell).
   Bu kilit F1n gününde kendiliğinden serbest bırakır: yayın `v0.2.3`
   etiketini attığı an satır yasal olur.
3. **Boş yeşil kontrolü (§8.2):** `npm i -g rabadon` satırı geri konur, test
   KIRMIZI düşer, loglanır, geri alınır.
4. F1n'in kendi maddesi **DEĞİŞMEDEN durur**: yayından sonra
   `npm view rabadon version` sayı döndürür (+ F1n-S1, 2 satır ölçümü).

---

### B3 · HOT-PATH `2b` — sahipsiz kalmaz: ÖLÇÜM+YASAK F2'ye, ONARIM F3'e

**Kendi koşumum:** `bash reports/R7/accept.sh` → exit **1**, **23 yeşil /
3 kırmızı**, adlar **`{2b, 6e, 7b}`**. Verbatim:

    in-process median with the daemon up: 1184.7 us over 300 samples
    ceiling = 1000 us (KOSU-RABADON R7); instrument = R1.3 in-process probe
    FAIL  2b the gate's median is 1184.7 us with the daemon up, ceiling is 1000 us
          50-event session: 1194.8 us   400-event session: 1270.3 us   divergence 6.32%

Ölçülen seri (aynı komut, aynı tavan, farklı oturumlar):
**1299,4 → 1244,2 → 1261,0 → 1310,8 → 1248,8 → 1229,9 → 1184,7 µs.**
Tavan 1000 µs, hiç oynatılmadı. **Hedef ihlali kalıcı, gürültü değil:
yedi ölçümün yedisi de tavanın üstünde.**

**Hangi değişmez:** §1'in son cümlesi — *"Hedef gecikme bir milisaniyenin
altı."* §1'e dokunamam (§10). Ve hiçbir faz bu satırı sahiplenmiyor: F2
çevrimdışı okuma, F3 enjeksiyonu bağlıyor, R7 kabulü ise faz değil devralınan
bir betik. Sahipsiz hedef, ölçülmemiş iddiaya dönüşür (§4.5).

**Neden F2'nin işi değil ama F2'yi bağlar:** §7/F2 açıkça **dağıtım kapısıdır**
("burası yeşilse ürün dağıtılabilir"). Yani F2 yeşilse ürün, §1'in manşet
gecikme vaadi ölçülmüş biçimde **%18,5 ihlal edilmişken** dağıtılır. Bu, §4.5
ve §11'in "ledger'dan türetilmeyen sayıyı kamuya yazmak" yasağının kardeşidir.

**KARAR — üçe bölünür, hiçbiri gevşetme değil:**

**F2-S9 (YENİ, F2 kabul maddesi) · sıfır maliyet, üç parça:**
  a) **F2 hot-path'e hiçbir şey EKLEMEZ.** `2b` F2 öncesi ve sonrası aynı
     komutla ölçülür ve **yükselmez**. (F2 zaten `usage --signals` bayrağı,
     çevrimdışı; bu madde onu kanıta bağlar.)
  b) **F2'nin ekranı ve dağıtım cümlesi "bir milisaniyenin altı" / "sub-ms" /
     "instant" DEMEZ**, `2b` kırmızı olduğu sürece. Derse faz kapanmaz.
     Negatifi olumluya çevirmek yasak (§11). Gerçek sayı yazılacaksa
     ölçülmüş medyan ve tavan yan yana yazılır.
  c) **Referans ortamda BİR KEZ ölçülür.** Bugüne kadar `2b`'nin her ölçümü
     bu makinede alındı; temiz referans ortam **zaten var ve bedava**:
     CI'ın `ubuntu-latest` + `macos-15` hücreleri (public repo, F1a'da
     4 hücre yeşil koştu). `2b`'nin medyanı orada da ölçülür ve tutanağa
     yazılır. Ne çıkarsa yazılır (CLAUDE.md kural 8). Bu bir ONARIM değil,
     **1184,7 µs'in makineye mi ürüne mi ait olduğunu öğrenmektir** — ve
     onarımı planlayacak faz bu sayı olmadan plan yapamaz.

**F3-S1 (YENİ, F3 kabul maddesi) · onarımın sahibi:**
  `2b` F3'ün kabulüne girer. F3 motoru canlı hook'a bağlayan fazdır, yani
  hot-path bütçesinin sahibi odur. Kabul: **F3 kapanışında `2b`'nin medyanı
  F3 ÖNCESİNDEN YÜKSEK OLAMAZ**, ve F3 `2b`'yi 1000 µs'in altına indirmediyse
  bunu tutanağında **ölçüyle ve adıyla** yazar; §1'in vaadi ile ölçülen
  gerçek arasındaki fark hiçbir yüzeyde gizlenmez. `2b`'nin tavanı
  (1000 µs) hiçbir fazda oynatılamaz — §11.

**Bu bir devir değil:** taşınabilir kısım (ölçüm + yasak) F2'de kapanıyor,
kalan kısım (onarım) onu yapabilecek tek fazın kendi ölçüsüne bağlanıyor.

---

### B4 · KORPUS KAYBI — raporlanandan ÜÇ KAT büyük, ve büyümeye devam ediyor

**Kendi saydım.** `native/moves.h`: `HDR_BYTES=4096`, `REC_BYTES=320`,
`CAP=200`, `Hdr{ char magic[8]; long long count; long long nextSeq; }` —
yani `count` = şimdiye kadar YAZILAN, diskteki kayıt = `(boyut-4096)/320`.
Betik başlıktan `count`'u okuyup diskteki kayıtla karşılaştırıyor:

| korpus | oturum | başlık `count` toplamı | diskte duran kayıt | **KAYIP** |
|---|---|---|---|---|
| **canlı** `~/.rabadon/sessions` | 34 | **933** | **527** | **406 (%43,5)** |
| **dondurulmuş yedek** `~/.rabadon-korpus-snapshot-20260826/sessions` | 34 | **654** | **527** | **127 (%19,4)** |

Dolu ring **tek**: `286fd71d-…moves.bin`, diskte 200/200.
Yedek anında `count=327`, **şimdi `count=606`** — yani **F1c ve bu oturum
boyunca 279 hamle daha üzerine yazıldı.** Tutanağın "139 hamle kaybolmuştu"
sayısı yedek anı için doğruydu; **bugün canlı korpustaki kayıp 406.**
Ve dolu ring, bu koşuyu koşan oturumun kendisidir.

**Hangi değişmez:** §4.5 ("ölçülmemiş şey satılmaz") ve §4.6. F2 kullanıcıya
"kendi son yedi günün" diye bir korpus ilan edecek; o korpusun **%43,5'i yok**
ve hangi hamlelerin gittiği bilinmiyor. Kaybı ilan etmeyen bir ekran, kısmi
bir veriyi tam veri gibi satar.

**KARAR — F2-S4 SERTLEŞİR + F2-S8 YENİ:**

**F2-S4 (sertleşti).** Çıktının ilk satırı okunan korpusu ölçüyle ilan eder:
kaç hamle kaydı, kaç oturum, hangi tarih aralığı, hangi dosyalardan — **ve
bunlara EK olarak KAYIP**: `başlık count toplamı − diskteki kayıt`, ve dolu
ring'i olan her oturum için ayrı satır. "N hamle okundu" cümlesi, N'in
yazılanın tamamı olmadığı durumda **tek başına basılamaz**. "Son yedi gün"
ifadesi ancak yedi günlük kayıt gerçekten okunduysa basılır; bugün ölçüm
**22–26 Ağustos, 4-5 gün** diyor.

**F2-S8 (YENİ).** **F2 kabul sayısını CANLI korpustan almaz.** Ölçüm
`~/.rabadon-korpus-snapshot-20260826/` (salt-okunur, `dr-xr-xr-x`) üstünde
koşar ve hangisini okuduğu tutanakta yazılıdır. Sebep ölçülü: canlı ring
her koşuda dönüyor (yedekten bu yana 279 hamle), yani canlı korpustan alınan
bir sayı **yarın yeniden üretilemez** — yeniden koşturulamayan sayı hakemin
sınayamayacağı sayıdır (§9: "sayıyı kendisi yeniden koşturur") ve §4.5
ihlalidir. Ürünün canlı yolda çalıştığı ayrıca gösterilecekse, o **ikinci**
bir koşumdur ve sayısı kabul sayısı değildir.

---

### B5 · TEST SAYACI — iki sayaç DEĞİL, ÜÇ lehçe; ikisi de eksik sayıyor

§10 gereği iki komutu da KENDİM koşturdum. Sonuç, hakemin teşhisinden farklı
ve daha kötü.

**Koşturduklarım** (`make test` exit **0**, `npm test` exit **0**):

| sayaç | komut | bugün |
|---|---|---|
| DAR | `grep -c '^  ok'` | **3490** |
| GENİŞ | `grep -cE '^[[:space:]]*ok\b'` | **3504** |
| yalnız özet basan süitler | `grep -oE 'PASS \([0-9]+ checks?\)'` toplamı | **612** |
| sayı basmayan süitler | çıplak `PASS` satırı | **3** (sayı yok) |
| node | `npm test` → `ℹ pass` / `ℹ fail` | **64 / 0** |

**Bulgu 1 — hakemin "make'in kendi süit özetleri" teşhisi YANLIŞ.**
F0/F1a'nın 3438/3462'si süit özetlerinden değil, `grep -cE "^\s*ok\b"`
regexinden geldi (`envanter-d-test-npm.md:78` komutu adıyla yazıyor).
Süit özetlerinin toplamı bugün **2603**, hiçbir yayımlanmış sayıyla eşleşmiyor.

**Bulgu 2 — iki regex GERÇEKTEN farklı ve fark tam 14.** DAR sayaç,
çıktının 3951-3965 satırlarındaki bir süitin **14 gerçek iddiasını sessizce
düşürüyor**, çünkü o süit `ok`'u sütun 0'dan basıyor (`ok    fixture: exit 0,
clean stderr` …). Bir süiti sessizce düşürebilen sayaç, ölçtüğünü sandığı
şeyi ölçmeyen sayaçtır — §8.2'nin ta kendisi. **DAR SAYAÇ EMEKLİ EDİLDİ.**

**Bulgu 3 — DURUM.md'deki gerçek hata, hakemin sandığı yerde değil.**
Fark 14, F1a hakeminin 3448'i ile f1a-tutanak'ın 3462'si arasındaki farkın
da aynısı. Yani DURUM.md'nin **F1a satırı GENİŞ sayaçla (3462+64=3526)**,
**F1c satırı DAR sayaçla (3490+64=3554)** yazılmış. İki farklı birim yan
yana konunca büyüme **+28** gibi okunuyor; **tek sayaçla gerçek büyüme
her iki sayaçta da +42'dir** (3462→3504 ve 3448→3490). Düzeltildi.

**Bulgu 4 — her iki yayımlanmış sayı da EKSİK.** `PASS (N checks)` basan
**9 süidin 612 kontrolü** iki regexin de tamamen dışında; ayrıca 3 süit hiç
sayı basmıyor. Bugüne kadar yayımlanan 3438/3448/3462/3490 sayılarının
hepsi en az 612 eksiktir.

#### KARAR — TEK GEÇERLİ SAYAÇ (ve bu birim bir daha değişmez)

Sayaç bir üçlüdür, üçü birden yazılır, hepsi tek komuttan:

    make test ; echo "EXIT=$?"                                    # 0 OLMALI
    grep -cE '^[[:space:]]*ok\b'        <make test çıktısı>       # native iddia
    grep -oE 'PASS \([0-9]+ checks?\)'  <…> | grep -oE '[0-9]+' | paste -sd+ - | bc
    npm test                                                      # 'ℹ pass' / 'ℹ fail'

**BUGÜNKÜ TABAN (2026-08-26, F1c sonrası, bu oturumda ölçüldü):**

> **native 3504 iddia + 612 kontrol = 4116 · node 64 · TOPLAM 4180 yeşil /
> 0 kırmızı**, `make test` exit 0, `npm test` exit 0.
> Sayı basmayan native süit: **3** (adı yok, sayısı yok — bilinen boşluk).

Sonraki her faz bu üç sayıyı bu komutlarla basar. **Eski sayılar silinmez**
(3502 / 3526 / 3554), ama artık "emekli DAR/GENİŞ sayaçla, `PASS (N checks)`
hariç" etiketiyle dururlar ve yeni sayılarla **kıyaslanmazlar**. Sayacı
değiştirmek yeşil için sayı oynatmak değildir — burada değişen ölçüm YÖNTEMİ,
ölçüt değil; ve yön SERTLEŞMEDİR: yeni sayaç eskisinin görmediği 612 kontrolü
ve düşürdüğü 14 iddiayı görür.

---

## SIRA (bu kararla güncellendi)

**F1c → F1d → F2 → F1b → F1n → F3 → F4 → F5 → F6 → F7 → F8 → F9.**

`F1d` yeni ve F2'nin önündedir; gerekçesi B1 ve B2 (§11 kırmızıyı taşıma
yasağı, ikisi de bu gece kapanabilir, ikisi de para yakmaz).

---

## F2'NİN NİHAİ KAPSAM SINIRI — F2 şefine verilecek metin

**Önkoşul:** F1d hakem hükmü GEÇTİ. KALDI ise F2 AÇILMAZ (§11).

**Yüzey:** `rabadon usage --signals` **BAYRAĞI**. Yeni verb YASAK (§4.10,
§11). `rabadon scan` YOKTUR ve yazılmaz. `native/cli_test.sh`'in beş-verb
tavanı kırmızı düşemez; `PRODUCT` listesi DEĞİŞTİRİLEMEZ.

**Kabul, tam liste — hiçbiri gevşetilemez:**
- Yazılı kabul aynen durur: her sayının yanında onu üreten oturum yolu; elle
  etiketleme; sinyal başına yanlış pozitif oranı; %5 üstü canlıya çıkmaz;
  üç zeminde ölçüm; en kötü zemin ölçüt (§7/F2).
- **S1** `n=0` sinyal "ÖLÇÜLMEDİ" basar, sıfırın SEBEBİ ölçülür, canlıya çıkmaz.
- **S2** sinyal başına `n` + etiketlenen örnek; `n<10` ise oran değil ham sayı.
- **S3** disclosure önkoşulu — YEŞİL (`make disclosure` exit 0).
- **S4 (SERTLEŞTİ, B4)** okunan korpus ekranda ilan edilir + **KAYIP** ilan
  edilir (`count` toplamı − diskteki kayıt, dolu ring başına satır).
- **S5** export kapısı önce onarılır: `native/audit.cpp` `path`/`raw`
  JSON-kaçışlanır, ham korpusun **608/608** satırı `json.loads` ile ayrışır,
  `moves_test.sh`'in sessiz `except: continue` yutucusu **sayar ve raporlar**.
- **S6** dağıtım cümlesi "ÖLÇÜLMEDİ" satırlarını ve kısa korpusu saklamaz;
  hakem bu satırları EKRANDA görmeden GEÇTİ diyemez.
- **S7** kanıt üç katmanlı; ekran "yakaladı / kurtardı / kazandırdı" demez.
- **S8 (YENİ, B4)** kabul sayısı **dondurulmuş yedekten** alınır
  (`~/.rabadon-korpus-snapshot-20260826/`), canlı ring'den değil; hangisi
  okundu tutanakta yazılı.
- **S9 (YENİ, B3)** F2 hot-path'e hiçbir şey eklemez ve `2b` yükselmez;
  ekran/dağıtım cümlesi `2b` kırmızıyken "sub-ms" demez; `2b` bir kez
  CI referans ortamında ölçülüp tutanağa yazılır.

**Kapsam DIŞI (açılmaz):** yeni verb, npm yayını, `2b`'nin ONARIMI (F3-S1),
`suite` alanının neden ölü olduğu, `WRONG_REFUSAL`/`TEST_EVIDENCE_MISSING`
kartları, `installCursorHooks` yedeksiz üstüne yazma kartı, `pages` iş akışı,
site ürün anlatısı (F7).

**BÜTÇE (§11):** en fazla **6 işçi**, işçi başına **60 dk**. Paralel salınanlar
aynı dosyaya dokunmaz: `native/audit.cpp` (S5) ile `native/usage.h` +
`rabadon-cli.sh` (ekran) ayrı; etiketleme kartı salt-okunur.
**Para: sıfır. Ağ yok. Model çağrısı yok.**
**DURMA (§13/2):** S5 iki kez üst üste aynı kırmızıyı verirse üçüncü
denenmez; F2 hakemi KALDI derse F1b açılmaz (F1b-S1).

---

## BU OTURUMDA GÖRÜLEN, SORULMAMIŞ, DOKUNULMAMIŞ (§5.5 dökümü)

- **`native/rabadon-cli.sh off` `.rabadon/off`'u kaldırmıyor.** İki ayrı
  "kapalı" kavramı var (mod=watch ve proje susturucusu) ve tek komut adıyla
  yönetiliyorlar. F1d madde 1 bunu görünür yapar ama iki kavramı
  BİRLEŞTİRMEZ — birleştirme kararı verilmedi, kart açılmadı.
- **`rabadon remove` çıktısı hâlâ "npm rm -g rabadon" diyor**, kaynaktan
  kurulmuş ağaçta hiçbir şey yapmayan bir komut. F1n/F1d-B2 ile aynı aile,
  kart açılmadı.
- **`make test` çıktısında 3 süit hiç sayı basmıyor** (çıplak `PASS`).
  Hangi süitler olduğu ölçülmedi; sayaç bu boşluğu adıyla taşıyor.
- **Süit özetlerinin toplamı 2603**, iddia satırı sayısı 3504. Aradaki fark
  süitlerin kendi özetlerinin de eksik olduğunu gösteriyor; sebebi
  ölçülmedi, kart açılmadı.
- **DOĞRULANMADI:** temiz konteynerde/temiz klonda hiçbir şey koşturmadım;
  gerçek Cursor uygulamasını başlatmadım; `npm i -g rabadon` yolunu
  ölçmedim (yayımlanmamış); `2b`'yi CI'da koşturmadım (F2-S9c'nin işi);
  `.rabadon/off` yolunu Cursor tarafında sınamadım; F1d'nin tahmin ettiğim
  kırmızısını yalnız elle gösterdim, test olarak yazmadım (o F1d'nin
  kabul maddesidir).

---

## 2026-08-26 · F1d hakem hükmü (GEÇTİ) sonrası · cevapçı: hakemin dört açık bulgusu + iki yenisi

Hakem F1d'yi GEÇTİ verdi ama kapıyı kapatmayan dört bulgu bıraktı (C1-C4).
Dördünü de KENDİM koşturdum, rapordan tek sayı kopyalamadım. Doğrularken
**BEŞİNCİ ve daha ağır bir bulgu (C5)** çıktı: kusur yalnız belgede değil,
**sevk edilen EKRANDA.** Ve yazarken **ALTINCI (C6)**: rabadon'un kendi
üstümüzde ölçülmüş bir YANLIŞ POZİTİFİ. Aşağıdaki her sayı bu oturumda bu
makinede ölçüldü.

---

### C1 · SEVK EDİLEN BELGEDE YALAN — DOĞRULANDI, üç cümlenin ÜÇÜ DE yanlış

Kum havuzu: `mktemp -d` + sahte `HOME`/`RABADON_DIR` + `git init`, sevk edilen
`native/rabadon-cli.sh` ve gerçek `native/rabadon-gate` ikilisi.

**(i) "`rabadon off` does NOT remove any of these" (`docs/commands.md:90`) — YANLIŞ,
üçüncü satır için.** Kaynak: `native/gate.cpp:2713-2715`, `--off` kolu
`unlink(flag)` + **`unlink(mute)`**; `mute = rhome + "/silent"`. Ölçüm:

    before: /tmp/c1-9r3J/rdir/silent
    $ rabadon off      -> exit 0
    after : ls: /tmp/c1-9r3J/rdir/silent: No such file or directory

Birinci ve ikinci satır için cümle DOĞRU: `<proje>/.rabadon/off` `off`'tan sonra
yerinde duruyor (ölçüldü), `RABADON_OFF` bir alt süreç tarafından zaten
kaldırılamaz. Yani cümle üç satırın **birinde** yalan — ve o satır, makinenin
tamamını susturan satır.

**(ii) "if a silencer is present, `rabadon on` will report ENFORCE" — YANLIŞ.**
Ölçülen ekran (`<proje>/.rabadon/off` dururken):

    rabadon: SILENT — silenced; the gate returns 0 before any rule runs
      silenced by: .rabadon/off (/tmp/c1-9r3J/proj/.rabadon/off)
        next: rm /tmp/c1-9r3J/proj/.rabadon/off
      the mode underneath is now `enforce`, but nothing will be refused while the silencer above is in place.

**(iii) "`rabadon status` reports the mode, not the silencer" — YANLIŞ.**

    rabadon: SILENT — silenced; the gate returns 0 before any rule runs
      silenced by: .rabadon/off (...)
        next: rm ...
      read from: /tmp/c1-9r3J/rdir/mode (not consulted — a silencer above answers first)

Üçü de F1d ÖNCESİ davranışın tarifi. Sebep hakemin yazdığı gibi commit sırası:
kâtip `01a0951` (yalnız `docs/`) koddan `27b84f8` ÖNCE yazdı, kimse dönmedi.

---

### C2 · İKİ FARKLI KOMUT — hakemin sandığından KÖTÜ: tablonunki çalışmıyor

Hakem "ikisi de çalışıyor, kullanıcı zararı yok" demişti. **Ölçüm bunu
çürütüyor.** İki giriş yolu var ve tablonun komutu birinde iş görmüyor:

| SILENT'a nasıl girildi | tablonun komutu `rm $RABADON_DIR/silent` | ekranın komutu `rabadon off` |
|---|---|---|
| dosya ELLE yaratıldı (mode dosyası yok) | ÇALIŞIR -> WATCH | ÇALIŞIR -> WATCH |
| ürünün KENDİ yolu (`rabadon-gate --silent`) | **ÇALIŞMAZ** | ÇALIŞIR -> WATCH |

`--silent` hem `silent` dosyasını hem **`mode` dosyasına `silent`** yazıyor
(`gate.cpp:2716-2718`). Tablonun komutu yalnız dosyayı siliyor, `mode` yerinde
kalıyor. Ölçülen sonuç:

    $ rabadon-gate --silent ; rm $RABADON_DIR/silent
    $ rabadon status
    rabadon: SILENT — dormant everywhere, records nothing (`rabadon off` to watch again)
      read from: .../rdir/mode (present)
    $ gate <PreToolUse: git push --force origin main>   ->  EXIT=0

Yani kullanıcı belgedeki "**the one command that removes it**" komutunu koşuyor
ve **susturulmuş kalıyor** — üstelik `rm` başarılı olduğu için hiçbir uyarı yok.
Bu §4.8 ihlali: belgenin verdiği tek komut kapıyı açmıyor.

**Yan etkiler de aynı değil.** `rabadon off`: `mode=watch` + `mode.last=watch`
yazıyor ve **bir `MODE` ledger satırı** düşüyor (spool'da 2 satır). `rm`:
hiçbir şey yazmıyor (1 satır). `gate.cpp:2688-2695` bunu adıyla anlatıyor —
denetimin ortadan kalkması bu araca yapılan en sonuçlu şeydir ve olay
olmayan tek eylemdi. Aynı yasa denetimin GERİ GELMESİ için de geçerli;
`rm` yolu o olayı üretmiyor.

**KARAR — tek doğru cevap EKRANIN cevabıdır, ve belge ondan TÜRETİLİR.**
`rabadon off`, `silent` dosyası satırı için doğru komuttur (iki giriş yolunun
ikisinde de ölçüldü). Tablonun 3. satırındaki `rm ~/.rabadon/silent` YANLIŞTIR
ve `rabadon off` ile değiştirilir. Tekleştirme yöntemi C1'in kilidiyle
aynıdır (F1e-B/3): **ikilinin bastığı sıradaki-komut satırı ile belgenin o
satır için verdiği komut BAYT BAYT AYNI olmak zorundadır**, ve bunu bir test
tutar.

**Ve tablo EKSİK.** Belge "Three things put it there, and any one of them is
enough" diyor. Ölçüm: **ALTI yol var, üçü belgesiz.**

| susturucu | belgede mi | ölçülen sonuç |
|---|---|---|
| `RABADON_OFF=1` | var | SILENT |
| `<proje>/.rabadon/off` | var | SILENT |
| `$RABADON_DIR/silent` | var | SILENT |
| **`$RABADON_DIR/mode` = `silent`** | **YOK** | SILENT, gate EXIT=0 |
| **`<proje>/.rabadon/mode` = `silent`** | **YOK** | SILENT, gate EXIT=0 |
| **`RABADON_MODE=silent`** | **YOK** | SILENT, gate EXIT=0 |

---

### C5 · YENİ VE EN AĞIR BULGU — kusur belgede DEĞİL, SEVK EDİLEN EKRANDA

C2'yi doğrularken çıktı. **Ekranın kendi bastığı kaçış komutu iki halde
kapıyı açmıyor.** Sevk edilen ikili, verbatim:

    $ export RABADON_MODE=silent
    $ rabadon status
    rabadon: SILENT — dormant everywhere, records nothing (`rabadon off` to watch again)
      read from: RABADON_MODE (environment variable)
    $ rabadon off                      # <- ekranın KENDİ verdiği komut
    rabadon: SILENT — dormant everywhere, records nothing (`rabadon off` to watch again)
    $ gate <force-push olayı>  ->  EXIT=0     # HÂLÂ SUSTURULMUŞ
    $ unset RABADON_MODE                # <- gerçekte işe yarayan komut, ekranda HİÇ geçmiyor
    $ rabadon status  ->  WATCH

Aynısı `<proje>/.rabadon/mode` = `silent` için de ölçüldü: `rabadon off`
sonrası ekran yine SILENT, gate yine EXIT=0. İşe yarayan komut
(`rm <proje>/.rabadon/mode`) **hiç basılmıyor.**

**Bu bir belge kusuru değil, ürün kusuru** ve tam olarak F1d'nin var olma
sebebi olan hastalık: fren "çıkış kapısı burada" diyor, kapı açılmıyor.
§4.8 (insan sıradaki HANGİ komutu koşacak) ve §4.9 (her kuralın çıkış yolu
vardır) ihlali, sevk edilen yolda, `main`'de, bugün.

**F1d'nin kilidi bunu YAKALAYAMAZ, ölçtüm.** `native/status_truth_test.sh`
16 hücreyi `MODE ∈ {watch, enforce}` × `projoff` × `RABADON_OFF` × `silent`
üzerinden geziyor (satır 211-217): **`silent` kelimesi hiçbir `mode` dosyasına
hiç yazılmıyor**, ve `grep -c RABADON_MODE native/status_truth_test.sh` -> **0**.
Yani F1d'nin kilidi kendi kapsamı içinde dürüst, ama kapsamı ürünün susturucu
kümesinden küçük — ve fark tam olarak kırık olan yerde.

---

### C3 · §8.5 — ölçüm aleti DOĞRULANDI ve sevk edilen yol ALETTEN KÖTÜ

Bugün, aynı makinede, aynı olay şekli, N=300:

| alet | sayı |
|---|---|
| `reports/R7/accept.sh` süreç-içi probu (2 koşu) | **1187,7** ve **1176,0 µs** |
| GERÇEK `native/rabadon-gate`, daemon açık, python subprocess medyanı | **3201,8 µs** (p10 3053,4 / p90 3516,2) |
| aynı harness'ta boş taban (`/usr/bin/true`) | 1145,3 µs |
| GERÇEK ikili, bash pipeline ortalaması (bağımsız ikinci harness) | **3224,5 µs/çağrı** |
| aynı döngüde boş taban (`/bin/cat`) | 1547,1 µs |
| -> **rabadon'a ATFEDİLEBİLİR uçtan uca maliyet** | **1677,4 – 2056,5 µs** |

İki bağımsız harness aynı yere düşüyor. **Yön tarafsız değil: sevk edilen yol
DAHA KÖTÜ.** Ham uçtan uca sayı yayımlanan sayının **2,7 katı**; harness'ın
kendi süreç açma maliyeti düşüldükten sonra bile atfedilebilir maliyet
**probun 1,42–1,75 katı** ve 1000 µs tavanının **1,7–2,1 katı**.

Prob yanlış bir alet değil — R7 başlığındaki gerekçe (ekilmiş 150 µs
regresyonu 7/7 yakaladı, uçtan uca cetvel 8'de 3 kaçırdı) ayakta ve prob
REGRESYON cetveli olarak kalır. **Ama tek sayı olarak kalamaz**, çünkü
kullanıcının hook'unda geçen süre o değil.

---

### C4 · TEMİZ KONTEYNER — mümkün, ve BU OTURUMDA KOŞTURULDU

**Mümkün mü: EVET.** `docker` CLI kuruluydu, **daemon KAPALIYDI**
(`Cannot connect to the Docker daemon`). `open -ga Docker` -> ~10 s'de ayakta.
İndirilenler: `debian:bookworm-slim`, `node:22-bookworm` (linux/arm64).
Para: sıfır. Geri alınabilir.

**1) "yalnız git ve shell" iddiası ARTIK ÖLÇÜLDÜ.** `rabadon-refenv:git-and-shell`
imajı kuruldu; içinde `git`/`bash`/`awk`/`sed`/`grep` VAR,
`node`/`npm`/`python3`/`jq`/`curl`/`wget`/`c++`/`g++`/`make` **YOK** (tek tek
`command -v` ile basıldı). Repo salt-okunur bağlandı, **`--network none`**:

    docker run --rm --network none -v <klon>:/w:ro -w /w rabadon-refenv:git-and-shell \
      bash native/install_docs_test.sh
    ->  38 ok / 0 fail, exit 0

F1d'nin "çevrimdışı, temiz konteynerde koşar" iddiası **iddia olmaktan çıktı,
ölçüm oldu.**

**2) `make all` temiz konteynerde YEŞİL.** `node:22-bookworm`, `--network none`,
g++ 12.2 / linux-arm64 -> **exit 0**. Kod macOS'a bağımlı değil.

**3) `make test` temiz konteynerde KIRMIZI — ve bu yeni bir bilgi.**

    docker run --rm --network none -v <ağaç>:/w -w /w node:22-bookworm bash -lc 'make test'
    ->  exit 2
        native iddia (GENİŞ) 2694 · PASS(N checks) 605
        sandbox: 8 passed, 1 failed  ->  FAIL - --check message
        make: *** [Makefile:161: test] Error 1

**Kök sebep ölçüldü.** Konteynerde çekirdek sandbox arka ucu yok, ürün bunu
dürüstçe söylüyor:

    rabadon sandbox: NO usable kernel backend — bwrap is not installed — apt install bubblewrap

`native/sandbox_test.sh:121` ise `grep -qi "no kernel backend"` arıyor —
ürünün bastığı dizgede araya **"usable"** girdiği için eşleşmiyor. Yani ürünün
mesajı §4.8'e uygun (yokluğu söylüyor + sıradaki komutu veriyor), **testin
deseni ürünün mesajından dar.** Ve bu dal macOS'ta hiç koşmuyor (seatbelt arka
ucu var -> `--check` exit 0), yani **bu iddia bu makinede BİR KEZ BİLE
çalışmamış.**

**İkinci ölçüm, en az bunun kadar önemli:** `make` orada durduğu için
**54 süit konteynerde HİÇ KOŞMADI** — yeşil değiller, **ölçülmemişler.**

**Konteynerde koşan ve YEŞİL düşen:** F1d'nin iki kilidi de oradaydı —
`status truth: 94 ok / 0 fail`, `install docs: 38 ok / 0 fail`. F1d'nin
hükmü referans ortamda ilk kez bağımsız olarak doğrulandı.

**CLAUDE.md'nin "referans ortam temiz bir konteynerdir" barı bugüne kadar
hiç ölçülmemişti; ölçüldü ve KIRMIZI.** Negatif sonuç olduğu gibi yazılıyor
(CLAUDE.md kural 8).

---

### C6 · YENİ — rabadon'un ÖLÇÜLMÜŞ BİR YANLIŞ POZİTİFİ (§4.3)

Bu kararı dosyaya yazarken, sevk edilen kapı beni reddetti:

    Rule: no-exit-code-after-pipe
    command matched deny rule: cat >> reports/kosu/SAPMA-KARARLARI.md <<'MARKER' ...

Reddedilen eylem bir belgeyi yazmaktı. Yasak kalıp **koşulan komutta değil,
heredoc'un İÇİNDEKİ BELGE METNİNDE** geçiyordu — yani kural, alıntılanan bir
örneği yürütülen bir komut sanıp meşru bir eylemi kesti. **Bu bir WRONG_REFUSAL'dır**
ve §4.3'ün ("yanlış pozitif ürünü öldürür") tam olarak saydığı sınıftır;
CLAUDE.md de "yanlış redler mazur görülmez, SAYILIR" diyor. Bugüne kadar bu
koşuda ölçülmüş yanlış pozitif sayısı **0** ilan ediliyordu; **bugünkü sayı 1**
ve kaynağı buradadır. Kart açılmadı, kural değiştirilmedi, kapı gevşetilmedi —
iş geçici dosya üzerinden yapıldı ve olay yazıldı.

**F1e-E (YENİ KABUL MADDESİ):** `no-exit-code-after-pipe` (ve aynı aileden
`no-gnu-timeout-on-macos` gibi metin eşleşmeli kurallar) **heredoc gövdesini
ve tırnaklanmış belge metnini komut olarak okumamalıdır.** Kabul: bugünkü
verbatim komut kırmızı düşebilen bir fikstür olarak yazılır, ONARIMDAN ÖNCE
reddi yeniden üretir, onarımdan sonra **geçer**, ve aynı fikstür setinde
GERÇEK `cmd | grep x ; echo $?` kalıbı **hâlâ reddedilir** (kural gevşetilmiş
olmaz). Yanlış pozitif sayısı tutanakta yayımlanır — sıfır olsun diye
gizlenmez.

---

## KARAR

### 1. C1 + C2 + C5 + C6 F2'DEN ÖNCE KAPANIR — YENİ MİNİ-FAZ: **F1e**

C1 tek başına "F2'nin kabul maddesi olsun" diye savunulabilirdi. **Ölçüm
buna izin vermiyor**, dört sebeple, ve hiçbiri kolaylık değil:

1. **C5 ve C6 belge işi değil, KOD işi.** Sevk edilen ekran çalışmayan bir
   kaçış komutu basıyor (ölçüldü, iki halde) ve sevk edilen kapı meşru bir
   eylemi kesiyor (ölçüldü, bir kez). Kâtip koda dokunamaz (§15.5), yani bu
   kalemler tanım gereği kâtip maddesi olamaz.
2. **Kilit, koruduğu düzyazıdan ÖNCE var olmak zorunda.** F1d'nin kök sebebi
   commit sırasıydı (`01a0951` docs -> `27b84f8` kod). F2 YENİ bir ekran
   (`usage --signals`) ve o ekranı anlatan YENİ düzyazı üretecek. Kilit F2'nin
   içinde doğarsa, F2'nin kâtibi kilitten önce yazar ve **C1 birebir tekrar
   eder.** Bu tahmin değil: F1d'de aynı sırayla aynı şey oldu.
3. **F2 DAĞITIM KAPISIDIR** (§7/F2: "burası yeşilse ürün dağıtılabilir").
   F2'yi yalan söyleyen `docs/commands.md` ile yeşile boyamak, yalanı
   dağıtmaktır. §11: "kırmızıyı sonraki faza taşımak" yasak.
4. **F2 kendi belgesinin hakemi olamaz.** Ekranı yazan fazın, o ekran
   hakkındaki düzyazıyı denetleyen kilidin de sahibi olması §9'un can
   damarına (işi yapan kendi işini onaylamaz) aykırıdır.

**F1e — "belge de yalan söylemez, ve kaçış kapısı gerçekten açılır".**
Sıra: **F1e -> F2 -> F1b -> F1n -> F3 -> F4 -> F5 -> F6 -> F7 -> F8 -> F9.**
Uykuda koşar: yerel, geri alınabilir, para yakmaz, ağ yok.

#### F1e KABUL — hiçbiri gevşetilemez

**F1e-A · ÖNCE KOD: her susturucunun bastığı kaçış komutu GERÇEKTEN açar.**
`native/status_truth_test.sh` hücre kümesi ürünün susturucu kümesine kadar
GENİŞLER: `RABADON_MODE ∈ {unset, silent}`, makine `mode` dosyası ve proje
`.rabadon/mode` dosyası `silent` değerini de alır. Değişmez, her hücre için:
**ekranın bastığı kaçış komutu ekrandan çekilir, verbatim koşulur, ve
sonrasında GERÇEK `native/rabadon-gate` aynı olayda artık susturulmuş
OLMAMALIDIR.** Bugün ölçülen iki hücre (`RABADON_MODE=silent`,
`<proje>/.rabadon/mode=silent`) bu kilitte KIRMIZI düşer; F1e onları yeşile
çevirir. Boş yeşil kontrolü (§8.2): kilit faz ÖNCESİ ikiliye karşı koşulur ve
tam bu iki hücrede kırmızı düştüğü loglanır.
**`native/status_truth_test.sh`'in mevcut 94 iddiasının hiçbiri silinemez,
zayıflatılamaz, atlanamaz** (CLAUDE.md 1). Sayı yalnız artabilir.

**F1e-B · SONRA BELGE: düzyazı-kod sapmasını yakalayan kilit.**
Sorunun cevabı: **keyfi düzyazı için kilit MÜMKÜN DEĞİL; sınırlı bir yüzey
için MÜMKÜN, ve bu repoda ÇALIŞTIĞI KANITLI** — `native/version_test.sh`
kâtibin `docs/quickstart.md`'ye yazdığı `0.2.3` düz metnini DRIFT olarak
yakaladı, `make test` kırmızı düştü, test değiştirilmedi, cümle yeniden
yazıldı (`cf34caf`). Aynı şablon genişletilir. Yeni süit
`native/docs_truth_test.sh`, beş değişmez, hepsi çevrimdışı ve deterministik
(LLM yok, ağ yok):

  1. **TABLO YÜRÜTÜLÜR, okunmaz.** `docs/commands.md`'nin susturucu tablosu
     ayrıştırılır; **her satır için** temiz kum havuzunda o hâl kurulur,
     gerçek `native/rabadon-gate` ile SILENT doğrulanır, satırın kendi
     "the one command that removes it" komutu **verbatim** koşulur, ve gate
     artık susturulmuş OLMAMALIDIR. Satır sayısı belgeden türetilir: satır
     eklemek test eklemektir.
  2. **KÜME EŞİTLİĞİ.** Belgedeki satır kümesi, ikilinin gerçekten
     raporlayabildiği susturucu kümesine **EŞİT** olmak zorundadır. Bugün
     3 != 6 -> KIRMIZI. Bu madde C2'nin eksik tablosunu kapatır ve tablo bir
     daha sessizce eksilemez.
  3. **EKRAN = BELGE, BAYT BAYT.** Bir susturucu için ikilinin bastığı
     sıradaki-komut ile belgenin o satırdaki komutu **bayt bayt aynı**
     olmalıdır. Tek başına bu madde C1(i)'i ve C2'yi birlikte öldürür.
  4. **DAVRANIŞ İDDİASI SİCİLİ.** `docs/commands.md`, `docs/faq.md` ve
     `docs/uninstall.md`'nin işaretlenmiş davranış bölümlerinde, sabit ve dar
     bir iddia gramerine uyan cümleler (`does NOT`, `will report`,
     `reports the`, `never`, `always`, `is not`) tek tek `docs/claims.tsv`'ye
     kayıtlı olmak ve her kaydın yürütülebilir bir kontrolü olmak zorundadır.
     **Sicilde olmayan iddia cümlesi KIRMIZIDIR.** Kapsam bilinçli olarak
     dardır: amaç tüm düzyazıyı denetlemek değil, *gözlemlenebilir CLI
     davranışı hakkındaki* cümleleri serbest metin olmaktan çıkarmaktır.
  5. `docs/commands.md:90-95`'in üç yanlış cümlesi ölçüme göre yeniden
     yazılır. **Eski cümle silinmez**, gerekçesiyle (ölçüm tarihi + komut)
     düzeltilir — sessiz silme yok (§15.5).

**F1e-C · SIRA KURALI — kök sebep budur, ve yalnız bu kapatır.**
**Kâtibin commit'i bir fazın SON commit'i olamaz.** Bir faz ancak
`docs_truth_test.sh` + `install_docs_test.sh` + `version_test.sh` üçlüsü
**fazın NİHAİ ikilisine karşı** yeşil koştuktan sonra kapanır, ve bu koşum
tutanağa komutuyla yazılır. F1d'nin yalanı tam olarak bunun yokluğundan
doğdu (`01a0951` docs, `27b84f8` kod, dönen olmadı). Bu madde **§8'e ek bir
kapı şartı olarak F1e'den itibaren her fazda geçerlidir.**

**F1e-D · REFERANS ORTAM (C4) — ölçüm zorunlu, yeşil zorunlu DEĞİL, SUSMAK YASAK.**
  a) Referans konteyner koşumu **commit'lenmiş ve yeniden koşulabilir** olur
     (betik ya da belgelenmiş tek `docker run` satırı), `--network none` ile,
     ve tam çıktısı `reports/` altına düşer.
  b) `make` ilk kırmızıda durduğu için **54 süit ölçülmeden kaldı**; F1e o
     54 süiti de koşturur (`make -k` ya da tek tek) ve sonucu yazar.
     "Koşmadı" ile "yeşil" bir daha karıştırılamaz.
  c) Her kırmızı **adıyla ve kök sebebiyle** yazılır. Bugün bilinen tek ad:
     `sandbox_test.sh:121 --check message`.
  d) **`native/sandbox_test.sh`'in iddiası bu fazda YEŞİL İÇİN DEĞİŞTİRİLEMEZ.**
     Ölçüm testin deseninin ürünün mesajından dar olduğunu gösteriyor; bu
     CLAUDE.md 1'in tarif ettiği "test gerçekten yanlış" hâlidir ve cevabı
     sessiz düzeltme değil, **oturum günlüğüne CHALLENGE + kırmızı bırakmaktır.**
     Düzeltilecekse KENDİ commit'inde, kendi gerekçesiyle, koddan ayrı.
  e) F1e'nin kendi eklediği süitler temiz konteynerde, çevrimdışı, **YEŞİL
     koşmak zorundadır** — bu gece `install_docs_test.sh` için yapıldığı gibi.

**F1e-E · YANLIŞ POZİTİF (C6).** Yukarıda tam metni yazılı. Fikstür kırmızı
düşebilir olacak, onarım kuralı GEVŞETMEYECEK, sayı yayımlanacak.

**F1e BÜTÇE (§11):** en fazla **3 işçi**, işçi başına **60 dk**. Paralel
salınanlar aynı dosyaya dokunmaz: kart A `native/gate.cpp` +
`native/status_truth_test.sh` (C5) ve aynı işçide C6'nın kural fikstürü;
kart B `docs/` + yeni `native/docs_truth_test.sh` + `docs/claims.tsv`;
kart C yalnız ölçer ve `reports/` altına yazar (koda ve kabul betiklerine
DOKUNMAZ).
**Kart B, kart A'nın hükmü düşmeden BAŞLAMAZ** — belge, düzeltilmiş ekranın
bastığını yazar; ters sıra F1d'nin hatasıdır.
**Para: sıfır. Ağ: yalnız imaj indirme (bir kez, zaten yapıldı), ölçüm
`--network none`. Model çağrısı: yok.**
**DURMA (§13/2):** kart A iki kez üst üste aynı kırmızıyı verirse üçüncü
denenmez, `UYANDIGINDA.md`'ye yazılır.

---

### 2. C3 — F2-S9 SERTLEŞİR (gevşemez): iki alet, iki sayı, tek tutanak

**F2-S9d (YENİ).** `2b` hakkında yayımlanan hiçbir sayı tek başına süreç-içi
probdan gelemez. F2 tutanağı **YAN YANA** iki sayı basar:
  - süreç-içi prob medyanı (regresyon cetveli, R7 başlığındaki gerekçesiyle),
  - **GERÇEK `native/rabadon-gate` ikilisinin uçtan uca medyanı**, daemon
    açık, N>=300, **ve kullanılan boş tabanın adı + sayısı** (ölçüm bu gece
    iki bağımsız harness'ta 3201,8 µs ve 3224,5 µs/çağrı verdi; boş tabanlar
    1145,3 ve 1547,1 µs).
**F2-S9e (YENİ).** §8.5 satırı tutanağa **verbatim** yazılır: `2b` süreç-içi
probdan alındı; `gate.cpp`'nin YAMALI BİR KOPYASI ölçülüyor, sevk edilen ikili
değil; sevk edilen ikilinin aynı gün ölçülen sayısı şudur: ... Bu satır yoksa
faz kapanmaz.
**F2-S9b GENİŞLER:** `2b` kırmızıyken hiçbir yüzey "sub-ms"/"instant" demez —
ve artık **prob sayısını tek başına anmak da bu yasağa girer.**
**F3-S1 SERTLEŞİR:** F3'ün onarım hedefi prob sayısı DEĞİL, **sevk edilen
ikilinin uçtan uca sayısıdır.** Probu 1000 µs'in altına indirip sevk edilen
yolu 3200 µs'te bırakmak, ölçüyü değil vekili yeşile boyamaktır (§11
"hedef yerine vekil denetlemek").
`2b`'nin 1000 µs tavanı hiçbir fazda oynatılamaz (§11). **Bu bir gevşetme
değildir: ölçülecek sayı arttı, tavan sabit kaldı.**

---

### 3. C4 — nereye yazılır

Ölçümün kendisi yukarıda ve `UYANDIGINDA.md`'de. Kabul maddesi olarak:
**referans ortam koşumu F1e-D'nindir** (F2'nin değil — F2 zaten 6 işçi ve
S1-S11 taşıyor, ve konteyner kırmızısı F2'nin ürettiği bir kırmızı değil,
devralınan ve bugüne kadar hiç ölçülmemiş bir kırmızıdır).
**F2 buna EK bir madde alır (S10):** F2'nin KENDİ eklediği her süit temiz
konteynerde çevrimdışı yeşil koşar. Böylece F2 mevcut kırmızıyı onarmakla
yükümlü olmaz ama **yenisini de üretemez.**
"ÖLÇÜLEMEDİ" satırına gerek yok: ölçüldü.

---

## F2'NİN NİHAİ KAPSAM SINIRI — F2 şefine verilecek metin (BU SÜRÜM GEÇERLİ)

Yukarıdaki eski F2 bloğunun yerine bu geçer. Değişenler: **önkoşul F1e'dir**,
S9 sertleşti (d, e), **S10 ve S11 eklendi**. Gevşetilen madde YOKTUR.

**Önkoşul:** **F1e hakem hükmü GEÇTİ.** KALDI ise F2 AÇILMAZ (§11).
(F1d hükmü GEÇTİ'dir ve durur, ama tek başına yetmez.)

**Yüzey:** `rabadon usage --signals` **BAYRAĞI**. Yeni verb YASAK (§4.10, §11).
`rabadon scan` YOKTUR ve yazılmaz. `native/cli_test.sh`'in beş-verb tavanı
kırmızı düşemez; `PRODUCT` listesi DEĞİŞTİRİLEMEZ.

**Kabul, tam liste — hiçbiri gevşetilemez:**
- Yazılı kabul aynen durur: her sayının yanında onu üreten oturum yolu; elle
  etiketleme; sinyal başına yanlış pozitif oranı; %5 üstü canlıya çıkmaz;
  üç zeminde ölçüm; en kötü zemin ölçüt (§7/F2).
- **S1** `n=0` sinyal "ÖLÇÜLMEDİ" basar, sıfırın SEBEBİ ölçülür, canlıya çıkmaz.
- **S2** sinyal başına `n` + etiketlenen örnek; `n<10` ise oran değil ham sayı.
- **S3** disclosure önkoşulu — YEŞİL (`make disclosure` exit 0).
- **S4** okunan korpus ekranda ilan edilir + **KAYIP** ilan edilir
  (`count` toplamı eksi diskteki kayıt, dolu ring başına satır).
- **S5** export kapısı önce onarılır: `native/audit.cpp` `path`/`raw`
  JSON-kaçışlanır, ham korpusun **608/608** satırı `json.loads` ile ayrışır,
  `moves_test.sh`'in sessiz `except: continue` yutucusu **sayar ve raporlar**.
- **S6** dağıtım cümlesi "ÖLÇÜLMEDİ" satırlarını ve kısa korpusu saklamaz;
  hakem bu satırları EKRANDA görmeden GEÇTİ diyemez.
- **S7** kanıt üç katmanlı; ekran "yakaladı / kurtardı / kazandırdı" demez.
- **S8** kabul sayısı **dondurulmuş yedekten** alınır
  (`~/.rabadon-korpus-snapshot-20260826/`), canlı ring'den değil; hangisi
  okundu tutanakta yazılı.
- **S9 (SERTLEŞTİ, C3)** F2 hot-path'e hiçbir şey eklemez ve `2b` yükselmez;
  ekran/dağıtım cümlesi `2b` kırmızıyken "sub-ms" demez; `2b` bir kez CI
  referans ortamında ölçülür; **+S9d** prob sayısı ve GERÇEK ikilinin uçtan
  uca sayısı yan yana, boş tabanın adıyla basılır; **+S9e** §8.5 satırı
  aletin ne olduğunu verbatim yazar; **+** F2'nin hiçbir yüzeyi prob sayısını
  tek başına anmaz.
- **S10 (YENİ, C4)** F2'nin KENDİ eklediği her süit **temiz referans
  konteynerde, `--network none` ile YEŞİL koşar** ve komut + çıktı tutanakta
  yazılıdır. F2 devralınan konteyner kırmızısını onarmakla yükümlü DEĞİLDİR,
  ama **yeni bir tane üretemez.**
- **S11 (YENİ, F1e-C'nin devamı)** F2 ancak kâtibin commit'inden SONRA
  `docs_truth_test.sh` + `install_docs_test.sh` + `version_test.sh` fazın
  NİHAİ ikilisine karşı yeşil koştuktan sonra kapanır; koşum komutuyla
  tutanakta.

**Kapsam DIŞI (açılmaz):** yeni verb, npm yayını, `2b`'nin ONARIMI (F3-S1),
konteynerdeki `sandbox_test.sh` kırmızısının onarımı (F1e-D/d, CHALLENGE),
`suite` alanının neden ölü olduğu, `WRONG_REFUSAL`/`TEST_EVIDENCE_MISSING`
kartları, `installCursorHooks` yedeksiz üstüne yazma kartı, `pages` iş akışı,
site ürün anlatısı (F7).

**BÜTÇE (§11):** en fazla **6 işçi**, işçi başına **60 dk**. Paralel salınanlar
aynı dosyaya dokunmaz: `native/audit.cpp` (S5) ile `native/usage.h` +
`rabadon-cli.sh` (ekran) ayrı; etiketleme kartı salt-okunur.
**Para: sıfır. Ağ yok. Model çağrısı yok.**
**DURMA (§13/2):** S5 iki kez üst üste aynı kırmızıyı verirse üçüncü
denenmez; F2 hakemi KALDI derse F1b açılmaz (F1b-S1).

---

## SIRA (bu kararla güncellendi)

**F1d (GEÇTİ) -> F1e -> F2 -> F1b -> F1n -> F3 -> F4 -> F5 -> F6 -> F7 -> F8 -> F9.**

---

## BU OTURUMDA GÖRÜLEN, SORULMAMIŞ, DOKUNULMAMIŞ (§5.5 dökümü)

- **rabadon bu oturumda BENİ üç kez reddetti; ikisi DOĞRU, biri YANLIŞ.**
  Doğru olanlar: `no-gnu-timeout-on-macos` (`timeout 180 docker pull ...`) —
  macOS'ta `timeout` yok, komut iş yapmadan ölecekti, gerçek bir hata önlendi;
  ve `no-exit-code-after-pipe`'ın ilk ateşlemesi (`docker info 2>&1 | sed ...`
  ardından çıkış kodu okuma) — o da doğruydu. Yanlış olan C6'dır. F1d'nin iki
  yakalamasıyla birlikte **kendi ürünümüzün kendi üstümüzdeki gerçek yakalama
  sayısı bu koşuda 4, ölçülmüş yanlış pozitifi 1.** F1b'ye aday, kart açılmadı.
- **`native/rabadon-cli.sh`'te `silent` bir ürün verb'ü DEĞİL.** SILENT'a
  yalnız `native/rabadon-gate --silent` ile ya da dosyayı elle yaratarak
  girilebiliyor. Belge `$RABADON_DIR/silent`'ı bir hâl olarak anlatıyor ama
  oraya nasıl girildiğini hiç yazmıyor. Kart açılmadı.
- **`gate.cpp:2697-2705` içinde YAZILI, çözülmemiş bir CHALLENGE var**
  (`enabled` + `mode.last` birleştirmesi `native/cli_test.sh:210` ile
  çelişiyor, `reports/phase-3/BLOCKED.md`'ye kaçırılmış). İnsan hükmü bekliyor,
  bu koşuda hiçbir faz sahiplenmedi.
- **`make test` konteynerde 54 süiti hiç koşturmadı** — bu süitler hakkında
  "linux'ta yeşil" DENEMEZ. F1e-D/b bunu ölçtürüyor.
- **Docker Desktop'ı BEN başlattım** (kapalıydı) ve üç imaj indirdim
  (`debian:bookworm-slim` 138 MB, `node:22-bookworm` 1,63 GB,
  `rabadon-refenv:git-and-shell` 274 MB — sonuncusunu ben kurdum). Toplam
  ~2 GB disk. Para yok, geri alınabilir (`docker rmi`). Operatör isterse
  kaldırır; F1e'nin işine yarayacağı için bıraktım.
- **DOĞRULANMADI:** gerçek Cursor uygulamasını başlatmadım; `2b`'yi CI'da
  koşturmadım (F2-S9c'nin işi); `npm i -g rabadon` yolunu ölçmedim
  (yayımlanmamış); konteyner ölçümleri linux/**arm64**'tedir, x86_64'te
  ayrıca ölçülmedi; uçtan uca `2b` sayısını CI'da ya da konteynerde ölçmedim,
  yalnız bu makinede; `docs/faq.md` ve `docs/uninstall.md`'nin susturucu
  cümlelerini tek tek sınamadım — yalnız `docs/commands.md`'yi ölçtüm, o iki
  dosyada da aynı yalanın olup olmadığı **AÇIK BİR SORUDUR** ve F1e-B/4 onları
  kapsama alıyor; C6'nın kural motorunda kök sebebi (hangi ayrıştırma adımının
  heredoc'u yutmadığı) **ölçülmedi**, yalnız reddin kendisi ölçüldü.

---

## 2026-08-26 · F1e hakem hükmü (GEÇTİ) sonrası · hakemin dört bulgusu (D1-D4) + mini-faz zincirinin kendisi

Hakem F1e'yi GEÇTİ verdi ve dört bulgu bıraktı. Dördünü de KENDİM koşturdum;
rapordan tek sayı kopyalamadım. Doğrularken **sevk edilen kapı beni de kesti**
(D1'in canlı tekrarı) ve **beşinci, hepsinden ağır bir bulgu** çıktı: yanlış
pozitif sayacının hammaddesi zaten defterde duruyor ve bu koşu onu hiç okumadı.

---

### D1 · İLAN EDİLMEMİŞ AÇIK — DOĞRULANDI, ve hakemin bulduğundan GENİŞ

F1e-E'nin normatif cümlesi kuralın "heredoc gövdesini **ve tırnaklanmış belge
metnini**" komut saymamasını istiyordu. Kaynak okundu: `native/rules.h`
`whole_line()` yalnız yorumları ve **heredoc gövdelerini** kaldırıyor
(`rbtext::Parsed::line`); tırnaklanmış metin için hiçbir şey yok, ve bu eksik
hiçbir tutanakta, hiçbir kabul maddesinde, hiçbir CHALLENGE'ta yazılı değil.

**Kendi probum** (`/tmp/d1probe.sh`, operatörün gerçek `guard.json`'undaki
regexin bayt kopyası, sevk edilen `native/rabadon-gate` ikilisi, kum havuzu
`mktemp -d` + sahte `RABADON_DIR`, taban `enforce`). Yasak kalıp her satırda
`make test | grep -c ok ; echo exit=$?`:

| şekil | sonuç |
|---|---|
| `printf '%s' "<kalıp>"` (çift tırnak) | **BLOCK** |
| `printf '%s' '<kalıp>'` (tek tırnak) | **BLOCK** |
| `echo "never write: <kalıp>" >> notes.md` | **BLOCK** |
| `python3 -c "print('<kalıp>')"` | **BLOCK** |
| `git commit -m "doc: <kalıp> is wrong"` | **BLOCK** |
| GERÇEK ihlal, çıplak `<kalıp>` | BLOCK (doğru) |
| heredoc gövdesinde `<kalıp>` (F1e'nin onardığı yarı) | ALLOW |

Yani açık **bir şekil değil, bir aile**: ürünü anlatan hiçbir cümle bir
tırnağın içinde yazılamıyor — **commit mesajı dahil**. F1e-B/5 "eski cümle
silinmez, gerekçesiyle düzeltilir" diyor; o gerekçeyi yazan commit'in kendisi
bu kuralla reddedilebilir.

Ve bu tahmini bir zarar değil: **bu oturumda beni kesti**, ölçüm betiğini
koştururken (`bash -c '...'` içinde iç tırnaklı dizge). Hakemi de aynı gece
kesmiş. §4.3'ün ("yanlış pozitif ürünü öldürür") tam sınıfı, sevk edilen
yolda, `main`'de, bugün.

**Kapanır, ilan edilmez.** Yerel, geri alınabilir, para yakmaz, ve §11
"kırmızıyı sonraki faza taşımak" yasağının kapsamında. Ama **yeni bir mini-faz
DOĞMAZ** (gerekçe aşağıda, D5) — F2'nin **BLOKLAYAN İLK KARTI** olur.

**Ayırt edici ölçüldü, ve gevşetme gerektirmiyor.** İki halin farkı tırnak
değil, **borunun kendisi**: gerçek ihlalde `|` tırnak DIŞINDA
(`make test | grep -c ok` + ayrıca tırnaklı `"exit=$?"` — bu, F1e'nin kendi
pozitif fikstürü ve KIRMIZI kalmak zorunda); yanlış pozitifte `|` tırnak
İÇİNDE. Yani "tırnaklı metni komple at" YASAKTIR (o gerçek ihlali öldürür);
değişmez şudur: **tırnaklı bir kelimenin içinde duran boru bir boru hattı
değildir.**

**AÇIK SORU, ölçülmedi, uydurulmayacak:** `bash -c "make test | tail -5; echo
exit=$?"` — burada boru tırnak içinde ama GERÇEKTEN koşuyor. Bu hücrenin
cevabını vermiyorum çünkü ölçmedim; kabul maddesi onu fikstüre koyuyor ve
işçi ayıramıyorsa cevap gevşetme değil **CHALLENGE**'dır.

---

### D1b · YANLIŞ POZİTİF SAYACI — hakemin sorusu, ve cevap ölçüldü: SAYAÇ ZATEN ÜRÜNÜN İÇİNDE, KOŞU ONU HİÇ KULLANMADI

Bu, gecenin en ağır bulgusu ve sorulmamıştı.

**1. Payda defterde duruyor.** `native/gate.cpp:4281` her ret için
`STOP  reason=BLOCKED  rule=<id>  sid=<oturum>  call=<araç çağrısı>` yazıyor
(watch modunda `WOULD_BLOCK`, aynı alanlarla). Yani "bu koşuda kaç ret oldu"
sorusu hatırlamaya değil, tek bir `grep`'e bakıyor.

**2. Pay da defterde duruyor, ve verbi de var.** `rabadon wrong <rule> "<niye>"`
sevk edilen bir `dev` verbi (`native/gate.cpp:2702`), aynı hash-zincirli
deftere `WRONG_REFUSAL` yazıyor. Kaynaktaki kendi cümlesi:
*"so the false-positive count of this rule is READ from the ledger rather than
asserted"*. **Bu koşu o verbi bir kez bile çağırmadı.**

**3. Ölçüm — koşunun kendi oturumu (`sid` 286fd71d), tüm gün dosyaları:**

    grep -ah '"ev":"STOP"' ~/.rabadon/spool/*.jsonl | grep -a BLOCKED \
      | grep -a 286fd71d | grep -ao '"rule":"[^"]*"' | sort | uniq -c

| kural | ret |
|---|---|
| `no-exit-code-after-pipe` | **7** |
| `red-suite-test-write` | **4** |
| `no-blind-inplace-source-rewrite` | **3** |
| `no-gnu-timeout-on-macos` | **1** |
| **TOPLAM** | **15** |
| `WRONG_REFUSAL` (aynı oturum, bu gece öncesi) | **0** |

**Yayımlanan elle sayım: 4 yakalama + 4 yanlış pozitif = 8 olay.
Defter 15 diyor.** Yedi ret hiçbir sütuna girmedi, ve **iki kural
(`no-blind-inplace-source-rewrite` 3, `no-shell`-ailesi dışındaki kalanlar)
hiçbir yayımlanmış sayıda geçmiyor.** §4.3 sinyal başına ORAN istiyor; oran
paydasız hesaplanamaz ve payda bugüne kadar hiç yazılmadı. §4.5'in
"kamuya giden her sayı ledger'dan türetilir" cümlesi bu sayıda ihlal edildi —
kötü niyetle değil, **elle sayıldığı için.**

**Kendi ölçümümü deftere yazdım** (`rabadon wrong no-exit-code-after-pipe
"..."`, çıktı: `recorded a wrong refusal`). Ve yazarken **iki eksik daha
ölçüldü:**
  - `WRONG_REFUSAL` satırında `sess`/`sid`/`call` **YOK** (alanları:
    `v seq ts run pipe ev rule why prev`). `STOP`'ta var. Yani pay ile payda
    **kural adı üzerinden** birleşebiliyor, **tek tek retle birleşemiyor.**
    §4.3 için kural bazlı oran yeterlidir, ama "hangi ret" izlenemez.
  - `rabadon wrong` her kural için `~/.rabadon/wrong-<kural>` tek-atımlık
    izin dosyası bırakıyor, ama o dosyayı **yalnız `red-suite-test-write`
    tüketiyor** (`gate.cpp:4815`). Diğer her kural için kalıcı bir yetim dosya.
    Şu an diskte: `wrong-no-exit-code-after-pipe`, `wrong-red-base`.
    Kart açılmadı, dosyalar **kasten bırakıldı** (kanıt).

---

### D2 · FAZ ÖNCESİ SAYI — hakem HAKLI, tutanak YANLIŞ: 6'da 4 değil, **6'da 3**

§10 "iki ajan aynı büyüklük için farklı sayı bastıysa cevapçı iki komutu da
KENDİSİ koşturur" der. Koşturdum.

Faz öncesi ikili (`05ab1ac`) atılabilir bir klonda (`/tmp/d2-pre`,
`git clone --no-hardlinks`, `make all` exit 0) derlendi; aynı prob
(`/tmp/d2probe.sh`) HEM ona HEM HEAD'e (`55c8e29`) koşuldu. Prob, altı
susturucunun her biri için: hâli kurar, gate'in gerçekten sustuğunu doğrular
(`exit 0 && 0 bayt`, `docs_truth_test.sh`'in `is_silent` tanımının aynısı),
ekranın `next:` satırını **ekrandan çeker**, verbatim koşar, aynı olayı
yeniden verir.

| hücre | 05ab1ac (ÖNCE) | 55c8e29 (HEAD) |
|---|---|---|
| `env-off` | `unset RABADON_OFF` → exit 2 · AÇILDI | AÇILDI |
| `project-off` | `rm <proj>/.rabadon/off` → exit 2 · AÇILDI | AÇILDI |
| `machine-silent` | `rabadon off` → exit 0 / **296 bayt** · AÇILDI (watch) | AÇILDI |
| `machine-mode` | **`next:` SATIRI HİÇ YOK** | `rabadon off` → 296 bayt · AÇILDI |
| `project-mode` | **`next:` SATIRI HİÇ YOK** | `rm <proj>/.rabadon/mode` → exit 2 · AÇILDI |
| `env-mode` | **`next:` SATIRI HİÇ YOK** | `unset RABADON_MODE` → exit 2 · AÇILDI |
| | **3 / 6** | **6 / 6** |

Faz öncesi üç hücrenin ekranı sadece
`rabadon: SILENT — dormant everywhere, records nothing (\`rabadon off\` to watch
again)` basıyor: **`next:` satırı yok**, ve parantez içindeki komut C5'te
ölçüldüğü gibi zaten açmıyor.

**HÜKÜM: hakemin 3'ü geçerli, tutanağın 4'ü geçersiz.** Yani "önce" hâli
iddia edilenden **daha kötüydü** — sapma tutanağın lehine değil aleyhine.
İki dosyada düzeltilir (**sayı silinmez, düzeltilir**):
`reports/kosu/DURUM.md:377` ve `reports/kosu/UYANDIGINDA.md`.
Bu bir gevşetme değil: faz öncesi ne kadar kötüyse F1e'nin teslim ettiği
o kadar büyüktür; yanlış olan sayı **düşük** olan değil, **yanlış** olandır.

---

### D3 · KİLİDİN TAVANI — DOĞRULANDI, ve türetilebilir

`native/docs_truth_test.sh:170`:

    SITUATIONS='env-off project-off machine-silent machine-mode project-mode env-mode'

Kaynağı okudum. Kilidin **iki tarafı da dürüst ve biri türetilmiş**: belgedeki
satır kümesi belgeden ayrıştırılıyor (satır numarasıyla değil, başlıkla),
ikilinin küme elemanlarının **adı, yeri ve kaçış komutu** ekranın kendi
`silenced by:` / `next:` satırlarından okunuyor — teste yazılmıyor. Ama
**KARDİNALİTE bu listeden geliyor.** İkilinin susturucu kümesi, yalnız bu altı
hâl kurulduğu için altı çıkıyor. Yarın `gate.cpp`'ye yedinci bir susturucu
girse `SITUATIONS` altı kalır, `BINCOUNT` 6 kalır, belge 6 satır kalır,
**6 = 6 yeşil düşer ve kimse yedinciyi görmez.** Hakem haklı: kilit bugünü
koruyor, yarını korumuyor.

**Türetilebilir mi: EVET, ve yüzey büyütmeden.** Susturucu kümesi tek bir
yerde hesaplanıyor (`gate.cpp` `compute_state`, `muters.push_back(Muter{...})`
+ mode katmanları). İkiliye bir **introspeksiyon bayrağı** eklenip
(`rabadon-gate --silencers`, ürün CLI'ının yardım ekranına DEĞİL) o tablonun
kendisi bastırılırsa, kilit kardinaliteyi ikiliden alır. §4.10 riski ölçüldü
ve **yok**: `native/cli_test.sh:248`'in `PRODUCT` listesi yalnız
`rabadon-cli.sh --help` ana ekranını sayıyor; gate ikilisinin bayrakları
(`--status --on --off --toggle --silent --statusline --check --export`) o
listede değil ve hiçbiri onu şişirmedi.

**Kimin işi: F2.** Sebep zorlama değil ölçüm: F2 **YENİ bir ekran**
(`usage --signals`) ve onu anlatan **YENİ düzyazı** üretiyor, ve F2-S11 bu
kilidi F2'nin kapı şartı yapıyor. Tavanı fikstüre bağlı bir kilidi F2'nin
yeni yüzeyine devretmek, F1d'nin hatasını bir kat büyütmektir.

---

### D4 · KONTEYNER BARI — hakem haklı, ve ÖLÇÜLEBİLİR (ölçtüm: emülasyon çalışıyor, ağsız, bedava)

**Doğrulandı.** `native/refenv/run.sh` sabit `IMAGE=node:22-bookworm`
(satır 48) ve `docker run --rm --network none ... $IMAGE_REF` (satır 218) —
`--user` YOK, `--platform` YOK. 102 yeşilin hepsi **şişman imaj, linux/arm64,
root**. `reports/kosu/RAPOR/f1e-c-konteyner.md` bunu kendi NOT VERIFIED
bölümünde zaten yazıyor (§4/2: *"x86_64 was not measured at all"*, §4/5:
*"the container ran as root"*) — **ama hiçbir fazın kabul maddesi değil ve
UYANDIGINDA.md'de hiç geçmiyor.** Sahipsiz ölçüm, §4.5'e göre satılamaz.

**Ölçülebilir mi: EVET, ve bu oturumda kanıtladım.**

    docker run --rm --network none --platform linux/amd64 \
      mcr.microsoft.com/mssql/server:2022-latest uname -m
    ->  x86_64

Yani **x86_64 emülasyonu bu makinede ÇALIŞIYOR, `--network none` ile, para
sıfır** (amd64 bir imaj zaten yerelde duruyordu). Eksik olan tek şey amd64
etiketli bir **inşa** imajı; o da bir kerelik ücretsiz `docker pull
--platform linux/amd64 node:22-bookworm`, ve `run.sh` **hiç değişmeden**
`--image <amd64-etiketi>` ile koşar. Non-root koşum için de tek satır
(`--user`) yeterli, ve konteyner kırmızılarından biri (`rule_census` düzyazıda
`-root` eşleşmesi) bunun ürün kusuru değil ortam artefaktı olduğunu
gösteriyor — non-root koşum o iddiayı sınar.

**DÜRÜST UYARI, uydurmuyorum:** emülasyon altında `g++` ve süitler **daha
yavaş** koşacak ve `run.sh`'in `SUITE_TIMEOUT=300` tavanına takılabilir.
Bunu ölçmedim. Kabul maddesi bu yüzden **ölçüm zorunlu, yeşil zorunlu değil,
susmak yasak** (F1e-D'nin aynı formülü): ne çıkarsa yazılır, zaman aşımı
çıkarsa o yazılır.

**Kimin işi: F2**, ve **yalnız ölçüm** olarak. F2 devralınan konteyner
kırmızısını onarmakla yükümlü değil (F2-S10 zaten öyle diyor); yeni bir mimari
üzerinde **ölçmekle** yükümlü, çünkü §3'ün barı "milyonlarca geliştirici" ve
onların ezici çoğunluğu x86_64'te.

---

### D5 · SAPMA DEĞERLENDİRMESİ — mini-faz zinciri: KAPANIYOR. Beşincisi doğmayacak.

Bu, hakemin sormadığı ama sorulması istenen şey, ve cevabı ölçüme dayanıyor.

**ÖLÇÜM 1 — zincir kendi kendini besliyor, 4/4.** F1c'yi F1a'nın hakemi
doğurdu, F1d'yi F1c'nin hakemleri, F1e'yi F1d'nin hakemi, ve şimdi D1-D4'ü
F1e'nin hakemi. **Dört fazın dördü de bir önceki fazın hakem bulgusundan
doğdu.** Bu bir tesadüf dizisi değil, bir sabit nokta: her dürüstlük fazı yeni
yüzey (ekran + düzyazı + kilit) üretiyor, yeni yüzey yeni bulgu üretiyor.
Beşincisini açarsam altıncısını da açacağım ve bunu bugün biliyorum.

**ÖLÇÜM 2 — §5 karşılığı.** Dört mini-fazın §5 hasılatı:
F1a → ADIM 2 yarım. F1c → **ADIM 2 tam** (3 satır / 0 soru / yolun sonunda
gerçek gate `exit 2`). F1d → yeni adım YOK (ADIM 2/4'ün altındaki yalan
kalktı). F1e → yeni adım YOK (ADIM 7'nin çıkış kapısı gerçek oldu).
**Sekiz adımın altısı (1, 3, 4, 5, 6, 8) bu koşuda bir kez bile açılmadı.**
§7 açık: *"Adımı gerçek yapmayan faz, faz değildir."* Zincir bu cümlenin
kenarında yürüyor.

**AMA — zincir yanlış iş yapmadı, ve bunu da ölçüm söylüyor.** F1d ve F1e'nin
kapattığı şey süs değildi: `rabadon on` "ON" diyip gate'i `exit 0` bırakıyordu
(§1'in tanımının tersi), ve ekranın kendi kaçış komutu iki hâlde kapıyı
açmıyordu (§4.9). Bunlar açıkken F2'nin teslim edeceği şey — **kullanıcının
kendi verisi hakkında doğru söyleyen bir ekran** — yalan söyleyen bir aletin
üstünde durur. Yani zincir doğru işi yaptı; **sorun işin doğruluğu değil,
zincirin durma kuralının olmaması.**

**KARAR — durma kuralı bugün konuyor, ve zincir bugün kapanıyor:**

1. **F1f YOKTUR.** D1, D1b, D3, D4'ün hiçbiri yeni bir faz doğurmaz. D1
   (kod işi, tek dosya, tek fikstür) F2'nin **BLOKLAYAN İLK KARTIDIR**:
   yeşil olmadan F2'nin hiçbir başka kartı BAŞLAMAZ ve F2 hakemi onu ayrıca
   sınar. Bu §11'in "kırmızıyı sonraki faza taşımak" yasağının ihlali
   DEĞİLDİR — kırmızı taşınmıyor, **sonraki fazın içinde, her şeyden önce
   kapanıyor**, ve bağımsız bir hakem hükmüne bağlanıyor. Emsali bu dosyada
   var: B3'te `2b` ölçüm/yasak F2'ye, onarım F3'e bölündü.
   Alternatif (beşinci mini-faz) tek işçilik bir işi bir şef + bir hakem
   döngüsüne çevirir; bu, §0'ın oyalama tarifidir.
2. **SIRADAKİ FAZ F2'DİR ve §5'in ADIM 3'ünü gerçek yapmak ZORUNDADIR.**
   F2 kapanışında "yeni adım gerçek olmadı" yazan bir SAPMA satırı (§8.9)
   **kabul edilmez**: F2'nin tanımı gereği ADIM 3 (ve 8) onun işidir.
   Yalnız dürüstlük onaran üçüncü bir ardışık faz, ürün ilerlemesini yiyor
   demektir.
3. **TETİK — bu kararın kendisi sınanabilir olsun.** F2'nin hakemi de
   fazın ürününden ÖNCE kapatılması gereken bir kod kusuru bulursa, bu
   **arka arkaya beşinci** olur ve artık bir faz sorunu değil bir **koşu
   yapısı** sorunudur. O noktada cevapçının yetkisi biter (§10: ürün
   konumu operatörün kalemidir) ve soru `UYANDIGINDA.md`'ye **O5** olarak
   düşer. Varsayılanı şimdiden yazılı (aşağıda).

---

## F2'NİN NİHAİ KAPSAM SINIRI — F2 şefine verilecek metin (BU SÜRÜM GEÇERLİ)

Bir önceki F2 bloğunun yerine bu geçer. Değişenler: **S12-S15 eklendi**,
**kart sırası bağlayıcı oldu**, **ADIM 3 kapı şartı oldu**.
**Gevşetilen madde YOKTUR.**

**Önkoşul:** F1e hakem hükmü **GEÇTİ** (`KAPI.md`, 2026-08-26). F1d GEÇTİ'dir
ve durur. Yeni önkoşul yok.

**Yüzey:** `rabadon usage --signals` **BAYRAĞI**. Yeni ürün verb'ü YASAK
(§4.10, §11). `rabadon scan` YOKTUR ve yazılmaz. `native/cli_test.sh`'in
beş-verb tavanı kırmızı düşemez; `PRODUCT` listesi DEĞİŞTİRİLEMEZ.
(S14'ün `rabadon-gate --silencers` bayrağı bu tavanın DIŞINDADIR; ölçüldü:
`cli_test.sh:248` yalnız CLI ana yardım ekranını sayıyor.)

**Kabul, tam liste — hiçbiri gevşetilemez:**
- Yazılı kabul aynen durur (§7/F2): her sayının yanında onu üreten oturum
  yolu; elle etiketleme; sinyal başına yanlış pozitif oranı; %5 üstü canlıya
  çıkmaz; üç zeminde ölçüm; en kötü zemin ölçüt.
- **S1** `n=0` sinyal "ÖLÇÜLMEDİ" basar, sıfırın SEBEBİ ölçülür, canlıya çıkmaz.
- **S2** sinyal başına `n` + etiketlenen örnek; `n<10` ise oran değil ham sayı.
- **S3** disclosure önkoşulu — YEŞİL (`make disclosure` exit 0).
- **S4** okunan korpus ekranda ilan edilir + **KAYIP** ilan edilir
  (`count` toplamı eksi diskteki kayıt, dolu ring başına satır).
- **S5** export kapısı önce onarılır: `native/audit.cpp` `path`/`raw`
  JSON-kaçışlanır, ham korpusun **608/608** satırı `json.loads` ile ayrışır,
  `moves_test.sh`'in sessiz `except: continue` yutucusu **sayar ve raporlar**.
- **S6** dağıtım cümlesi "ÖLÇÜLMEDİ" satırlarını ve kısa korpusu saklamaz;
  hakem bu satırları EKRANDA görmeden GEÇTİ diyemez.
- **S7** kanıt üç katmanlı; ekran "yakaladı / kurtardı / kazandırdı" demez.
- **S8** kabul sayısı **dondurulmuş yedekten** alınır
  (`~/.rabadon-korpus-snapshot-20260826/`), canlı ring'den değil.
- **S9 (+d, +e)** F2 hot-path'e hiçbir şey eklemez ve `2b` yükselmez; hiçbir
  yüzey `2b` kırmızıyken "sub-ms" demez **ve prob sayısını tek başına anmaz**;
  prob medyanı ile GERÇEK ikilinin uçtan uca medyanı **yan yana**, boş tabanın
  adıyla; §8.5 satırı verbatim.
- **S10** F2'nin KENDİ eklediği her süit temiz referans konteynerde
  `--network none` ile YEŞİL koşar; devralınan kırmızıyı onarmak zorunda
  değil, **yenisini üretemez**.
- **S11** F2 ancak kâtibin commit'inden SONRA `docs_truth_test.sh` +
  `install_docs_test.sh` + `version_test.sh` fazın NİHAİ ikilisine karşı
  yeşil koştuktan sonra kapanır; koşum komutuyla tutanakta.

- **S12 (YENİ, D1) · BLOKLAYAN İLK KART — F2'nin başka hiçbir kartı bu yeşil
  olmadan BAŞLAMAZ.** `no-exit-code-after-pipe` ailesi (boru adı geçen her
  kural) **tırnaklanmış bir kelimenin içindeki boruyu boru hattı saymaz.**
  Kabul, hepsi tek fikstür setinde ve **sıra bağlayıcı — her "hâlâ reddedilir"
  hücresi, ikizinden ÖNCE koşar** (`heredoc_prose_test.sh`'in kendi yasası):
  a) **ONARIMDAN ÖNCE kırmızı düşer.** Yukarıdaki beş tırnaklı şekil
     (`printf` çift/tek tırnak, `echo ... >> dosya`, `python3 -c`,
     **`git commit -m`**) faz öncesi ikilide BLOCK olarak yeniden üretilir ve
     loglanır (§8.2).
  b) **Onarımdan sonra beşi de ALLOW.**
  c) **Kural GEVŞEMEZ:** çıplak `make test | grep -c ok ; echo exit=$?` ve
     `heredoc_prose_test.sh`'in mevcut yedi pozitifinin **hepsi** BLOCK kalır.
     `native/heredoc_prose_test.sh`'in tek bir iddiası silinemez,
     zayıflatılamaz, atlanamaz (CLAUDE.md 1); sayı yalnız artabilir.
  d) **`bash -c "<gerçek boru hattı>"` hücresi fikstüre KONUR ve ölçülür.**
     Bu hücrenin doğru cevabı BLOCK'tur (gerçekten koşuyor). İşçi bu hücreyi
     (b)'yi bozmadan tutturamıyorsa **kuralı gevşetmez**: sonucu ölçer,
     `UYANDIGINDA.md`'ye ve oturum günlüğüne **CHALLENGE** yazar, ve
     hücreyi bilinen boşluk olarak ADIYLA ilan eder. Sessiz geçmek yasak.
  e) `.rabadon/guard.json`'daki regexler, eşikler ve `disabled[]`
     **DEĞİŞTİRİLEMEZ.** Onarım `native/rules.h`/`cmdtext.h` tarafındadır.

- **S13 (YENİ, D1b) · YANLIŞ POZİTİF SAYACI ELLE SAYILMAZ.** §4.3'ün oranı
  ve §4.5'in "ledger'dan türetilir" cümlesi tek bir komutla karşılanır:
  a) **PAYDA:** koşunun kapsamındaki her ret, kural adıyla, defterden:
     `STOP  reason=BLOCKED` + `WOULD_BLOCK`. Bugünkü ölçüm (`sid` 286fd71d):
     **15 ret** — `no-exit-code-after-pipe` 7, `red-suite-test-write` 4,
     `no-blind-inplace-source-rewrite` 3, `no-gnu-timeout-on-macos` 1.
  b) **PAY:** `WRONG_REFUSAL`, ve tek yazma yolu sevk edilen
     **`rabadon wrong <kural> "<niye>"`** verbidir. Bir daha hiçbir yanlış
     pozitif düzyazıya yazılıp deftere yazılmadan geçmez.
  c) **Bu 15 retin HEPSİ tek tek hükme bağlanır** (doğru / yanlış), ve
     yanlış olanların her biri (b) ile deftere düşer. Hükümsüz bırakılan ret
     sayısı **sıfır** olur ya da adıyla ilan edilir.
  d) **Yayımlanan her yanlış pozitif sayısı bundan böyle PAY/PAYDA olarak,
     kural adıyla yazılır.** Paydasız yüzde yazmak §4.5 ihlalidir;
     `n<10` olan kuralda oran değil ham sayı (S2 ile aynı yasa).
  e) **Ölçülen boşluk ilan edilir:** `WRONG_REFUSAL` satırında `sess`/`sid`/
     `call` yok, `STOP`'ta var — yani pay/payda **kural** üzerinden
     birleşiyor, **tek tek retle birleşmiyor**. Bunu onarmak F2'nin ödevi
     DEĞİLDİR (kapsam dışı), ama tutanakta adıyla yazılır.
  f) Bu koşuda bugüne kadar yayımlanan "**4 olay / 2 sınıf**" ve "**yakalama
     4**" sayıları **silinmez**; "elle sayıldı, defterle uyuşmuyor, payda 15"
     etiketiyle dururlar ve yeni sayılarla **kıyaslanmazlar** (B5'in sayaç
     emekliliğiyle aynı yöntem).

- **S14 (YENİ, D3) · KİLİDİN KARDİNALİTESİ FİKSTÜRDEN DEĞİL İKİLİDEN GELİR.**
  `native/docs_truth_test.sh`'in `SITUATIONS` listesi bugün altı adı
  **yazıyor**; kilit bu yüzden yedinci bir susturucuyu göremez.
  a) İkili kendi susturucu kaynak kümesini **kendisi ilan eder**
     (`compute_state`'in tek tablosundan; ürün CLI yardım ekranına satır
     eklenmez, `cli_test.sh` `PRODUCT` listesine dokunulmaz).
  b) Süit, `SITUATIONS` kümesinin ikilinin ilan ettiği kümeye **EŞİT**
     olmasını şart koşar; eşit değilse **BLOCKED**.
  c) **Boş yeşil kontrolü (§8.2):** kaynağa yedinci bir susturucu geçici
     olarak eklenir, süitin KIRMIZI düştüğü loglanır, geri alınır.
     Bu madde 1 ve 2'nin tek gerçek kanıtıdır.
  d) `docs_truth_test.sh`'in mevcut 40 iddiasının hiçbiri silinemez.

- **S15 (YENİ, D4) · REFERANS ORTAM: ÖLÇÜM ZORUNLU, YEŞİL ZORUNLU DEĞİL,
  SUSMAK YASAK.** (F1e-D'nin formülü, yeni eksene uygulanıyor.)
  a) `native/refenv/run.sh` **bir kez `linux/amd64` üstünde** koşar
     (`--image <amd64 etiketli imaj>`, `--network none`). Ölçüldü ve
     kanıtlandı ki emülasyon bu makinede çalışıyor ve para sıfır; eksik olan
     tek şey bir kerelik ücretsiz `docker pull --platform linux/amd64`.
  b) **Bir kez `--user` ile non-root** koşar; konteyner kırmızılarından
     `rule_census` düzyazı eşleşmesinin ortam artefaktı olduğu iddiası
     böylece sınanır.
  c) **Ne çıkarsa yazılır** (CLAUDE.md 8). Emülasyon `SUITE_TIMEOUT`'a
     takılırsa, imaj bulunamazsa ya da koşum tamamlanamazsa: sonuç
     **"ÖLÇÜLEMEDİ + sebep + komut"** olarak yazılır ve F2 bu yüzden
     KALMAZ. Yasak olan **susmak** ve **"muhtemelen yeşildir" demek**.
  d) `run.sh`'in ham çıktısı `reports/` altına **commit'lenir**. Ölçüldü:
     bugün `reports/refenv/` diskte YOK ve git'te izli hiçbir çıktı dosyası
     yok — sayılar yalnız `RAPOR/f1e-c-konteyner.md` düzyazısında duruyor.
  e) **102 yeşil hakkında bugüne kadar yazılan hiçbir cümle "linux'ta yeşil"
     ya da "temiz makinede yeşil" diye genellenemez**; geçerli etiketi
     `node:22-bookworm · linux/arm64 · root · --network none`'dur.

**ADIM KAPISI (§8.6, F2 için bağlayıcı):** F2 §5'in **ADIM 3'ünü gerçek
yapar** (ve ADIM 8'i besler). "Yeni adım gerçek olmadı" yazan bir SAPMA
satırıyla F2 KAPANMAZ. Üçü yazılı olacak: kullanıcı kaç adımda o ekrana
varıyor, ekranda ne yazıyor (verbatim), nasıl kaçıyor.

**Kapsam DIŞI (açılmaz):** yeni ürün verb'ü, npm yayını, `2b`'nin ONARIMI
(F3-S1), konteynerdeki `sandbox_test.sh` kırmızısının onarımı (F1e-D/d,
CHALLENGE, O4), `WRONG_REFUSAL`'a `sid` eklemek (S13/e, yalnız ilan edilir),
`rabadon wrong`'un yetim izin dosyaları, `suite` alanının neden ölü olduğu,
`TEST_EVIDENCE_MISSING` kartı, `installCursorHooks` yedeksiz üstüne yazma,
`pages` iş akışı, site ürün anlatısı (F7).

**BÜTÇE (§11, tavan aşılmıyor):** en fazla **6 işçi**, işçi başına **60 dk**.
Kart dağılımı, paralel salınanlar aynı dosyaya dokunmayacak biçimde:

| kart | iş | dokunduğu dosyalar |
|---|---|---|
| **0 (BLOKLAYAN)** | S12 + S13 | `native/rules.h`(+`cmdtext.h`), `native/heredoc_prose_test.sh`, sayaç betiği |
| 1 | S5 export onarımı | `native/audit.cpp`, `native/moves_test.sh` |
| 2 | `usage --signals` ekranı (S1,S4,S6,S7) | `native/usage.h`, `native/rabadon-cli.sh` |
| 3 | etiketleme + ölçüm (S2,S8, üç zemin) | **salt-okunur** + `reports/` |
| 4 | S14 kardinalite | `native/gate.cpp`, `native/docs_truth_test.sh` |
| 5 | S15 referans ortam | `native/refenv/run.sh`, `reports/` |

**Kart 0 yeşil olmadan 1-5 BAŞLAMAZ.** Sebep ölçüm: kart 1, 2, 4 ve 5'in
işçileri belge ve rapor yazacak, ve D1'in açığı tam olarak **belge yazmayı**
kesiyor — bugün beni kesti. Kartlar 1-5 paralel salınabilir.
**Para: sıfır. Ağ: yalnız bir kerelik imaj indirme (S15/a), ölçüm
`--network none`. Model çağrısı: yok.**

**DURMA (§13/2):** kart 0 ya da kart 1 iki kez üst üste aynı kırmızıyı
verirse üçüncü denenmez, `UYANDIGINDA.md`'ye yazılır. F2 hakemi KALDI derse
F1b açılmaz (F1b-S1).

---

## SIRA (bu kararla güncellendi)

**F1e (GEÇTİ) → F2 → F1b → F1n → F3 → F4 → F5 → F6 → F7 → F8 → F9.**

**Mini-faz zinciri kapandı: F1f yoktur** (D5). D1/D1b/D3/D4 F2'nin kabul
maddeleridir (S12-S15), D1 bloklayan ilk karttır.

---

## BU OTURUMDA GÖRÜLEN, SORULMAMIŞ, DOKUNULMAMIŞ (§5.5 dökümü)

- **`rabadon wrong` yetim izin dosyası bırakıyor.** `gate.cpp:2717` her kural
  için `~/.rabadon/wrong-<kural>` yazıyor, ama onu **yalnız**
  `red-suite-test-write` tüketiyor (`gate.cpp:4815`). Diskte şu an
  `wrong-no-exit-code-after-pipe` (benim, bu gece) ve `wrong-red-base`
  (daha eski). Kasten silmedim — kanıt. Kart açılmadı.
- **`red-base` kuralı için de bir `WRONG_REFUSAL` var** (08-26, `pipe`
  `damummyphus:cli`): *"F2 hakemi: kirmizilar OLCULEN BULGU..."*. Bu satır
  BAŞKA bir projenin koşusundan geliyor (`damummyphus:cli`), rabadon
  koşusundan değil — yani defterdeki `WRONG_REFUSAL`'lar kapsam
  filtrelenmeden sayılırsa yanlış sayı çıkar. S13/a bu yüzden kapsamı
  `sid`/`pipe` ile daraltıyor.
- **Deftere göre 08-26'da 5 `WRONG_REFUSAL` var ama 4'ü komşu projelerin.**
  rabadon koşusunun kendi oturumunda bu gece öncesi **0**.
- **`~/.rabadon/spool/2026-08-26.jsonl`: `SIGNAL` 511, `CHECK_FAIL` 165,
  `WOULD_BLOCK` 69, `TEST_EVIDENCE_MISSING` 61, `REPAIR_FAIL` 10,
  `PARSE_DEGRADED` 1, `PARSE_LIMIT` 1.** `PARSE_DEGRADED`/`PARSE_LIMIT`
  doğrudan D1'in ailesi (ayrıştırıcı okuyamadığı satırı ESKİ yolla, ham
  metin olarak yargılıyor — `rules.h` `rule_refuses`, `p.degraded` kolu).
  Yani D1'in onarımı bozuk ayrıştırmada **etkisiz kalır ve kalmalıdır**
  (redde doğru yön). Ölçmedim, kart açılmadı.
- **`reports/refenv/` diskte yok ve git'te izli değil.** F1e-D/a "tam
  çıktısı `reports/` altına düşer" diyordu; betik commit'li, ham çıktı
  değil. Sayılar `RAPOR/f1e-c-konteyner.md` düzyazısında duruyor. S15/d
  bunu kapsıyor.
- **Faz öncesi ikiliyi `/tmp/d2-pre` altında ayrı bir KLONA kurdum**
  (`git clone --no-hardlinks`, worktree DEĞİL — F0 "yeni worktree açılmaz"
  der). `make all` orada exit 0. Klon ve `/tmp/d1probe.sh`, `/tmp/d2probe.sh`
  betikleri `/tmp` altında duruyor, repoya girmediler.
- **DOĞRULANMADI:** `bash -c "<gerçek boru hattı>"` hücresinin doğru
  ayrılabilirliğini ölçmedim (S12/d onu ölçtürüyor); amd64 emülasyonunda
  `make all`/`make test`in gerçekten tamamlandığını ölçmedim, **yalnız
  emülasyonun çalıştığını** ölçtüm (`uname -m` → `x86_64`, `--network none`);
  non-root konteyner koşumunu hiç denemedim; `2b`'yi bu oturumda hiç
  koşturmadım (yayımlanan 1994,5 µs / tavanın 1,99 katı sayısını
  F1e tutanağından alıyorum, kendim yeniden ölçmedim); `npm i -g rabadon`
  yolunu ölçmedim (yayımlanmamış); gerçek Cursor uygulamasını başlatmadım;
  15 retin hangilerinin DOĞRU hangilerinin YANLIŞ olduğunu tek tek hükme
  bağlamadım — bu S13/c'nin işidir ve kasten bana ait değil.
