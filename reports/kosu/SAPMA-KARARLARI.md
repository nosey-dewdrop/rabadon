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
