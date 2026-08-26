# F1c TUTANAK — kurulumun kırmızısı kapandı

Şef: F1c. Tarih: 2026-08-26. Kök: `/Users/damummyphus/damla_projects_2026/rabadon`, dal `main`.
F1c bir mini-fazdır; tanımı ve gerekçesi `reports/kosu/SAPMA-KARARLARI.md`
"2026-08-26 · F1'in bölünmesi ve sertleştirilmesi" §A.3'tedir. Kaynak odur.

Kesilen kart: 4 (kart 0 korpus yedeği + kart 1 belge kilidi + kart 2 = SAPMA'nın
3+5'i birleşik + kart 4 adım sayısı). Salınan işçi: **2** (tavan 2).
Alt ajan salınmadı. **Şef kod yazmadı** — şefin yazdığı tek şey rapor, tutanak ve
kâtip görevindeki `docs/`. Commit: 9. Durma koşulu tetiklenmedi.

Faz aralığı: `3df7af3..HEAD`.

---

## KART 0 — KANIT YEDEĞİ (acil, kart öncesi)

Replay korpusu eriyordu ve kaybı geri alınamazdı. Repo DIŞINA salt-okunur
anlık görüntü alındı: `~/.rabadon-korpus-snapshot-20260826/`.
Kaynak ve kopya EŞİT: **34 oturum = 34**, **527 kayıt = 527**.
Ayrıntı ve komutlar: `f1c-korpus-yedek.md`.

**Yedek geç kaldığı kadarıyla ölçüldü ve yazıldı:** başlıkların `count` toplamı
666, diskte duran kayıt 527 — yani **139 hamle yedekten ÖNCE zaten kaybolmuştu**
(dolu ring `286fd71d…`, `CAP=200`). Ve o dolu ring bu koşuyu koşan oturumun
kendisi: yedek anından sonra 3 dakikada 12 hamle daha yazdı, yani **her koşu
korpusun en eski ucunu yiyor.** F2 bunu bilerek planlanmalı.

---

## KABUL MADDELERİ — SAPMA §A.3'ün altısı, madde madde

### 1. `rabadon on` belgelenmiş her kurulum yolunda, bloğun İÇİNDE · GEÇTİ
- `README.md` kurulum bloğuna satır girdi (`README.md:32`), `rabadon init` SONRASI
  ve ajan başlatılmadan (`claude`) ÖNCE.
- `docs/quickstart.md` kurulum bloğuna girdi.
- `site/index.html`: satır **zaten kurulum bloğunun içinde çalıştırılabilir bir
  komut satırıydı** — işçi siteye satır EKLEMEDİ ve bunu rapor etti. Test onu ilk
  koşuda yeşil geçti, ama §8.2 turu satırı kaldırınca kırmızı düştüğünü kanıtlıyor,
  yani kilit sitede de gerçek.
- `site/index.html` ÜRETİLMİŞ dosyadır (`site/build.py`, kaynak `site/index.tmpl.html`);
  yalnız render'ı kilitlemek sahte yeşil olurdu, test **şablonu da** denetliyor.
- **site/index.html'in ÜRÜN anlatısına dokunulmadı** (F7'nin işi). `git diff` kanıtı:
  faz aralığında `site/` altında **hiçbir dosya değişmedi**.

### 2. Kırmızı düşebilen kilit + BOŞ YEŞİL KONTROLÜ (§8.2) · GEÇTİ
`native/install_docs_test.sh` (yeni, 141 satır). Ne yapıyor:
blok başlığını/çitini ARAYARAK kurulum bloğunu çıkarıyor (**sabit satır numarası
yok**), bloğun bulunduğunu ve boş olmadığını ayrı ayrı denetliyor (vacuity guard:
en az 3 komut satırı; blok bulunamazsa test FAIL der, sessizce geçmez), ve
`rabadon on`'un blok İÇİNDE bir komut satırı olmasını arıyor. Sıra da denetleniyor:
`rabadon init`'ten önce ya da ajan başlatıldıktan sonra olamaz.
README:133'teki kurulumla ilgisiz `rabadon on` geçişi **sayılmıyor** ve ona
dokunulmadı — kilidin ölçtüğü şey vekil değil hedefin kendisi.

Boş yeşil turu, üç belge için AYRI AYRI, komut çıktısıyla `f1c-1-bosyesil.out`'ta:

| tur | test | exit |
|---|---|---|
| taban | `20 ok / 0 fail` | 0 |
| README.md satırı silinince | `17 ok / 1 fail` | **1** |
| README.md geri konunca | `20 ok / 0 fail` | 0 |
| site/index.html satırı silinince | KIRMIZI | **1** |
| site/index.html geri konunca | YEŞİL | 0 |
| docs/quickstart.md satırı silinince | KIRMIZI | **1** |
| docs/quickstart.md geri konunca | YEŞİL | 0 |

FAIL metni §4.8'in üç sorusunu cevaplıyor (VERBATIM, `f1c-1-bosyesil.out`):
`BLOCKED — no rabadon on command inside the install block.` / `why: rabadon init
leaves the project in WATCH mode…` / `next: add a rabadon on line to the install
block in README.md, after rabadon init and before the agent is started, then
re-run ./native/install_docs_test.sh`

**§11 uyuldu:** kabul ölçütü (`1844a55`, test, KIRMIZI) onu sağlayan koddan
(`c1cd220`, belgeler) AYRI COMMIT'te.

### 3. `init` ekranı MODU ve TEK SIRADAKİ KOMUTU söylüyor · GEÇTİ
Ekranın sonuna §4.8'in üç cevabı kondu. VERBATIM (tam ekran: `f1c-2-init-ekrani.out`,
sahte HOME altında gerçek koşumdan, exit 0):

    right now: WATCH — every action is recorded and nothing is refused.
               watch is the default: the rules prove themselves on your own
               work first, and enforcing is your call, not ours.
    next:      rabadon on       start refusing (rabadon off returns to watch)

- ne oldu: WATCH, hiçbir şey reddedilmiyor.
- neden: watch varsayılandır, açmak kullanıcının kararıdır.
- sıradaki tek komut: `rabadon on`. Ekranda **tam bir tane** `next:` satırı var.
- **Varsayılan WATCH kaldı.** `init` `on`'a katlanmadı (§7/F7 korundu).
- `native/exit_path_test.sh` bunu kilitliyor ve ters yönü de: ekran "enforcement is
  on" DEMEMELİ.

### 4. Adım sayısı YENİDEN ölçüldü, eski sayı SİLİNMEDİ · GEÇTİ
Şef ölçtü. Tam rapor: `f1c-4-adim-sayisi.md`.

| | sayı | ne sayıldı |
|---|---|---|
| **F1a (önce)** | **5 birleşik satır / 7 komut**, ~35,8 s | belgedeki satırlar; varılan yer **WATCH** |
| **F1c (sonra)** | **3 birleşik satır / 7 komut**, **34,1 s**, **0 soru** | çalışır bir frene (`exit 2`) varan asgari yol |

Eski 5 silinmedi, yan yana duruyor. İkisi aynı şeyi saymıyor ve bu yazılı.
Ölçüm sevk edilen yoldan: gerçek `native/rabadon-gate` ikilisi, `init`'in
`.claude/settings.json`'a yazdığı tam yol. VERBATIM karşıtlık:

    A) after init only (WATCH):  "Nothing was stopped. `rabadon on` makes this a real refusal."   EXIT=0
    B) after rabadon on:         "rabadon BLOCKED this action."                                   EXIT=2

**2 KOVALANMADI.** 3→2 farkının tek sebebi paketin yayımlanmamış olması; o
**F1n-S1** kabul maddesidir (SAPMA §A.4), F1c'nin işi değil.

### 5. `removeCursorHooks` — Cursor'un çıkış yolu · GEÇTİ
`grep -rn "removeCursorHooks" hooks/` → önce **BOŞ**, şimdi **4 satır**.
`hooks/install.mjs`'e eklendi, `hooks/manage.mjs`'in `remove` yolundan çağrılıyor.
Davranış, `native/exit_path_test.sh` ile PİNLİ:
- `init` `.cursor/hooks.json`'a 5 girdi yazar (pozitif kontrol) → `remove` sonrası **0**.
- **Kullanıcının kendi Cursor hook'ları aynen durur**, dosya geçerli JSON kalır.
  (Kullanıcının dosyasını silmek çıkış yolu değil, yeni bir hasar olurdu.)
- Yalnız rabadon'un yazdığı dosya SİLİNİR — boş iskelet bırakılmaz.
- Hiç Cursor'ı olmayan projede `remove` exit 0 ve `.cursor` YARATMAZ.

§4.9 ihlali kapandı: kesin seviyenin Cursor'daki kuralının artık çıkış yolu var.
**Yeni verb eklenmedi** — mevcut `remove` düzeltildi (§4.10 korundu).

Kod öncesi kırmızı (§8.2, işçinin ölçümü, `0073521`): `exit path: 14 ok / 8 fail`,
exit 1. Kod sonrası (`0ba61db`): `22 ok / 0 fail`, exit 0. Ölçüt ve kod AYRI commit.

### 6. Kırmızı ad kümesi büyümedi, test sayısı düşmedi · GEÇTİ
- `bash reports/R7/accept.sh` → exit 1, **23 yeşil / 3 kırmızı**, adlar
  **`2b`, `6e`, `7b`** — F0 ve F1a ile AYNI KÜME, büyümedi.
  (`2b` bu koşuda 1261,0 µs, tavan 1000 µs — F1a'da 1244,2 µs'ti; aynı ad, aynı
  kusur, makine gürültüsü. Tavan OYNATILMADI.)
- `make test` → **exit 0**, `grep -c '^  ok'` **3448 → 3490 (+42)**, 54 → 56 süit.
  Yeni iki süit gerçekten koştu: `install docs: …` ve `exit path: 22 ok / 0 fail`.
- `npm test` → **64/64**, 0 fail.
- `make disclosure` → **exit 0**, `9 ok, 0 fail` (F1a'nın kapattığı kapı açılmadı).
- `git log --diff-filter=D --name-only 3df7af3..HEAD` → **BOŞ**. Sessiz silme yok.
- `git diff --stat 3df7af3..HEAD -- native/` → yalnız İKİ YENİ DOSYA. **Mevcut
  hiçbir test, fixture, eşik ya da tolerans değişmedi.**

---

## §8 KAPI — dokuz madde, şef koşturdu

| # | kapı | hüküm | kanıt |
|---|---|---|---|
| 1 | kabul betiği yeşil | GEÇTİ | `make test` exit 0 / 3490 ok · `npm test` 64/64 · `make disclosure` exit 0 · `install_docs_test` 20/0 · `exit_path_test` 22/0 |
| 2 | **boş yeşil kontrolü** | GEÇTİ | üç belge için kırmızı→yeşil turu `f1c-1-bosyesil.out`'ta; `exit_path_test` kod öncesi 14/8 kırmızı |
| 3 | **kırmızı AD kümesi büyümedi** | GEÇTİ | `reports/R7/accept.sh` → 23/3, `{2b, 6e, 7b}` |
| 4 | eşik/tolerans/ön-kayıt/fixture değişti mi | DEĞİŞMEDİ | `git diff --stat 3df7af3..HEAD -- native/` yalnız iki yeni dosya |
| 5 | ölçüm sevk edilen yoldan mı | GEÇTİ | gerçek `native/rabadon-gate` ikilisi, sahte HOME'lu kum havuzunda `exit 2` |
| 6 | **UX kapısı (ADIM 2), ÜÇÜ DE** | GEÇTİ | aşağıda |
| 7 | hakem hükmü | *(ayrı oturumda, `reports/kosu/KAPI.md`)* | §9: hakem her fazda ayrıdır, esnemez |
| 8 | kâtibin commit'i | GEÇTİ | `c1cd220` (README+quickstart) ve `0170975` (quickstart/uninstall/commands/agent-contract) |
| 9 | SAPMA satırı | GEÇTİ | aşağıda |

### §8.6 UX KAPISI — üçü de yazılı ve ÖLÇÜLÜ
1. **Kaç adımda varılıyor:** 3 birleşik satır / 7 ayrık komut / 34,1 s / **0 soru**,
   varılan yer `exit 2` veren bir guard. Kum havuzunda ölçüldü (`f1c-4-adim-sayisi.md`).
2. **Ekranda ne yazıyor:** `f1c-2-init-ekrani.out`, kırpılmamış, exit 0 ile.
   Kapanış bloğu §4.8'in üçünü veriyor (yukarıda verbatim).
3. **Kullanıcı nasıl kaçıyor:** `rabadon off` (watch'a döner) · tek kural için
   `.rabadon/guard.json` içinde `disabled[]` · `rabadon remove` (`--purge`,
   `--global`) — ve **artık Cursor da dahil**, test ile pinli. Kaçış yolu belgede:
   `docs/uninstall.md`, `docs/commands.md`, `docs/agent-contract.md`.

---

## SAPMA SATIRI (§8.9)

F1c, §5'in **ADIM 2 "kurar"** adımını gerçek yaptı — F1a'da YARIM kalmıştı.
Gösteren sayı: kurulum **3 birleşik satırda, 0 soruda, 34,1 saniyede**, ve
sonunda gerçek `rabadon-gate` ikilisi bir PreToolUse olayına **`exit 2`**
veriyor; F1a'da aynı yolun sonu `exit 0` + "Nothing was stopped." idi.
Belgedeki `rabadon on` artık kırmızı düşebilen bir testle kilitli
(`native/install_docs_test.sh`), yani cümle bir daha sessizce bayatlayamaz.
**Sapmadık.** Kapsam SAPMA §A.3'ün altı maddesiydi; altısı da kapandı, kapsam
dışı bırakılan beş kalem (npm yayını, `no manifes`, `allow-scripts`, `.gitignore`,
`pages`) AÇILMADI. "2 satır" iddiası kovalanmadı — F1n-S1'de duruyor.

---

## DÜRÜSTÇE: NE DOĞRULANMADI

1. **Temiz makinede / temiz konteynerde koşulmadı.** Ölçümler bu makinede,
   `mktemp -d` + sahte `HOME`/`RABADON_DIR`/`npm_config_prefix` ile izole edildi;
   bu izolasyon değil, sahte bir izolasyondur. CI matrisi (2 OS × 2 Node) yeni iki
   süiti henüz koşmadı — bu tutanak yazılırken push edilmemişti.
2. **Gerçek Cursor uygulaması çalıştırılmadı.** `.cursor/hooks.json`'ın sökülmesi
   dosya düzeyinde kanıtlı; Cursor'ın o dosyayı gerçekten öyle okuduğu
   DOĞRULANMADI. Cursor'a atfedilebilir ledger satırı hâlâ **0** ve ledger'da
   ajanı ayırt eden alan HÂLÂ YOK — yani Cursor ateşlese bile atfedilemezdi.
3. **`npm i -g` yolu ölçülmedi** — paket yayımlanmadı. 3 sayısı kaynaktan
   derleme yolunundur.
4. `.cursor/hooks.json.bak-rabadon` `remove` sonrası SİLİNMİYOR (bilerek; işçinin
   kararı, raporda gerekçeli). Yani kullanıcının kendi hook'ları olan bir projede
   `.cursor/` içinde bir yedek kalıyor.
5. `rabadon remove --global` yolunun gerçek `~/.cursor` üstündeki davranışı
   ölçülmedi — orada koşulmadı.

## İŞÇİNİN BİR BULGUSU YANLIŞ ÇIKTI — düzeltmesi burada

İşçi 2, kart dışı notunda "`cli_test.sh` §4.10'un beş-yüzey yasasını bugün
hiçbir test doğrudan tutmuyor" yazdı. **Bu YANLIŞTIR ve düzeltilmeden
bırakılırsa sonraki ajan yüzeyin kilitsiz olduğunu sanır.**
`grep -n "surface" native/cli_test.sh` → satır 271: *"WHY: five commands IS the
product surface (T2); a sixth line on this screen…"*, satır 282: *"this set is
the whole advertised surface and is fixed"*, satır 299: *"an entry that is
neither one of the five nor version/dev is an unaccounted surface"*.
Ayrıca F1a hakemi altıncı verb'ü KENDİ enjekte edip 315/0 → 312/3 kırmızısını
görmüştü. Yüzey tavanı **kilitlidir**.

## KART DIŞI, DOKUNULMADI, YAZILI

1. **README ile quickstart çelişiyor:** README "npm'de değil, kaynaktan kur"
   derken `docs/quickstart.md`'nin `## 1. Install` bloğu `npm i -g rabadon`
   diyor — bugün çalışmayan bir komut. Belgelenmiş iki kurulum yolundan biri
   ölü. F1n'in işi.
2. **`installCursorHooks` okunamayan bir `hooks.json`'ı yedeksiz ÜSTÜNE YAZIYOR**,
   oysa `.claude` tarafında aynı durum `process.exit(1)` ile reddediliyor
   ("rabadon will not overwrite a file it cannot read"). İki yüzey, iki farklı
   yasa; Cursor tarafında kullanıcının bozuk ama düzeltilebilir dosyası sessizce
   kayboluyor. **Bunun kartı açılmadı ve açılmalı.**
3. `rabadon remove` çıktısı "fully uninstall the CLI with: npm rm -g rabadon"
   diyor; kaynaktan kurulmuş bir ağaçta bu komut hiçbir şey yapmaz.
4. `init` ekranında hâlâ üç ayrı çağrı bloğu var (see it work / from here / next).
   Tek `next:` net, ama ekran sadeleştirilebilir. F7'nin işi.
5. Site kurulum yolu ile README/quickstart yolu farklı ürün gibi okunuyor
   (sitede `rabadon init` hiç geçmiyor).
6. `~/.rabadon/spool/` bu koşuda büyüdü — testler değil, bu oturumu denetleyen
   canlı gate yazdı. Testlerin `RABADON_DIR`'ı sahte.

---

## ŞEFİN KENDİ KAPI KOŞUMU (devam oturumu, 2026-08-26)

Önceki şef oturumu tutanağı ve `DURUM.md`'yi YAZDI ama **commit'lemedi ve hüküm
satırı vermedi** — yani §11'e göre iş SAHİPSİZDİ. Devam eden şef, yukarıdaki
tabloların hiçbirine güvenmeden §8 kapılarını KENDİ koşturdu. Sonuçlar:

| kapı | komut | sonuç |
|---|---|---|
| kabul betiği | `bash reports/R7/accept.sh` | exit **1**, **23 yeşil / 3 kırmızı** |
| kırmızı AD kümesi | aynı çıktı | **`{2b, 6e, 7b}` — BÜYÜMEDİ** (`2b` bu koşuda **1310,8 µs**, tavan 1000 µs; tavan OYNATILMADI) |
| süit tabanı | `make test` | exit **0**, `grep -c '^  ok'` → **3490** |
| node süiti | `npm test` | exit **0**, **64 pass / 0 fail** |
| disclosure | `make disclosure` | exit **0**, **9 ok / 0 fail** |
| yeni kilit 1 | `bash native/install_docs_test.sh` | exit **0**, **20 ok / 0 fail** |
| yeni kilit 2 | `bash native/exit_path_test.sh` | exit **0**, **22 ok / 0 fail** |
| sessiz silme | `git log --diff-filter=D --name-only 3df7af3..HEAD` | **BOŞ** |
| native değişimi | `git diff --stat 3df7af3..HEAD -- native/` | yalnız **2 yeni dosya**, +385 satır; mevcut hiçbir test/eşik/fixture değişmedi |

### BOŞ YEŞİL — şefin kendi turu (vekil değil, hedefin kendisi)

    sed -i '' '32d' README.md          # kurulum bloğundaki `rabadon on` satırı
    bash native/install_docs_test.sh   # → EXIT=1, 17 ok / 1 fail
    cp /tmp/README.bak README.md
    bash native/install_docs_test.sh   # → EXIT=0, 20 ok / 0 fail
    git diff --stat README.md          # → BOŞ (dosya bayt-bayt geri geldi)

Kırmızı metni (VERBATIM, şefin turundan):

    FAIL - README.md: BLOCKED — no `rabadon on` command inside the install block.
           why: `rabadon init` leaves the project in WATCH mode. A reader who
           next: add a `rabadon on` line to the install block in README.md, after

§4.8'in üç sorusu da cevaplı: ne engellendi, neden, sıradaki tek komut.

### Kart 0 — şefin doğruladığı

`~/.rabadon-korpus-snapshot-20260826/` DURUYOR, izinler `dr-xr-xr-x` (salt-okunur),
`sessions/` altında **46 dosya**. Kaynak-kopya fiziksel kayıt EŞİT (527=527, 34=34);
başlık `count`'u eşit DEĞİL (666 vs 654) ve bu farkın sebebi raporda yazılı
(kopyalama anından sonra canlı ring yazmaya devam etti). Eşitsizlik gizlenmedi.

### Ölçüm sevk edilen yoldan mı

`file native/rabadon-gate` → **Mach-O 64-bit executable arm64**. Adım sayısı ve
`exit 2` ölçümü bu gerçek native ikiliden, `init`'in `.claude/settings.json`'a
yazdığı tam yoldan alındı. Kabuk taklidi değil.

### ŞEFİN HÜKMÜ

**F1c BİTTİ.** Altı kabul maddesinin altısı da kapalı, §8'in şefe düşen sekiz
kapısı da yeşil. Dokuzuncu kapı (hakem hükmü) §9 gereği AYRI ve TEMİZ bir
oturumdur; şef onu doğurmaz ve onu BEKLEMEZ — orkestratör salar, hükmü
`reports/kosu/KAPI.md`'ye yazılır.

### BU DEVAM OTURUMUNDA DA DOĞRULANMAYANLAR

- Temiz konteyner/temiz klon KOŞULMADI. Yukarıdaki her sayı bu makinede.
- CI matrisi iki yeni süiti HENÜZ koşmadı — bu commit push edilene kadar
  `install_docs_test.sh` ve `exit_path_test.sh` yalnız yerelde yeşil.
- Gerçek Cursor uygulaması ÇALIŞTIRILMADI (dosya düzeyi kanıt var, davranış yok).
- `npm i -g` yolu ölçülmedi (paket yayımlanmadı; F1n-S1).
- `2b`'nin kırmızısı F1c'nin işi değildi ve KAPATILMADI; ad kümesinde duruyor.
