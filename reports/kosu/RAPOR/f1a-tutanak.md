# F1a TUTANAK — kurulabilir ürün, yayımlanmamış

Şef: F1a. Tarih: 2026-08-26. Kök: `/Users/damummyphus/damla_projects_2026/rabadon`, dal `main`.
Kapsam: `reports/kosu/SAPMA-KARARLARI.md` · "2026-08-26 · F1'in bölünmesi ve sertleştirilmesi".
Kart raporları: `f1a-1-yuzey-tavani.md`, `f1a-2-disclosure.md`, `f1a-3-doctor.md`,
`f1a-4-ci-matris.md`, `f1a-5-adim-sayisi-ve-cursor.md` (hepsi bu dizinde).

Kesilen kart: 5. Salınan işçi: 5 (tavan 5). Alt ajan salınmadı. Şef kod yazmadı.
Commit: 6 (`66d2720`, `01436fc`, `513573c`, `b09d18b`, `43e3cda`, kart 5 raporu, + bu tutanak).
Durma koşulu tetiklenmedi.

---

## KABUL MADDELERİ — madde madde, ölçümle

### 1. Yüzey tavanı kırmızı düşebilir · GEÇTİ
`native/cli_test.sh` bölüm 1c: `--help` çıktısı ayrıştırılıyor, ürün verb sayısı 5 ve ad
kümesi `{init, on|off, usage, repair, doctor}` olmak zorunda; `version` ve `dev` ayrı
sayılıyor; ekran kısaysa vacuity guard patlıyor. Sayı sabit karşılaştırma değil, çıktıdan
sayılıyor.
- `./native/cli_test.sh` → exit 0, **310 ok → 315 ok**, 0 fail.
- Ürün verb'ü eklenmedi/silinmedi/yeniden adlandırılmadı. `dev` ekranındaki 30 verb duruyor.

### 2. Disclosure kapısı KAPATILARAK geçildi · GEÇTİ
`site/redact.py::project_of` sonuna tek kural: `site/identity.py`'nin proje dediği ve
`site/published-projects.txt`'te olmayan her etiket `(withheld)` olarak yayımlanıyor —
tek işaretçi, böylece saklanan proje SAYISI da yayımlanmıyor.
- `python3 site/allowlist.py --list | tail -1`:
  **önce** `53 found, 12 allowed, 41 off-list`, `make disclosure` exit 2
  **sonra** `12 found, 12 allowed, 0 off-list`, `make disclosure` **exit 0**
- `git diff site/published-projects.txt` BOŞ — operatörün onayı olmadan tek isim eklenmedi.
- `git diff native/published_allowlist_test.sh` ve `site/allowlist.py` BOŞ — denetim
  gevşetilmedi, advisory yapılmadı, varsayılan-izinli yapılmadı, eşik oynatılmadı.
- Yol üstünde bulunan gerçek sızıntı düzeltildi: `field.would_block_by_rule` ham kural
  id'lerini `clean()`'den geçirmiyordu, id ilk on ikiye tırmanınca özel bir ad
  `measured.json` ve `field.html`'e düştü. Sayım sonrası temizlendi, yayımlanan hiçbir
  sayı oynamadı.
- **Kapalı değil, yazılı:** serbest metne (kural id'leri, cümleler, alıntılanmış yollar)
  gömülü liste dışı adlara dokunulmadı. Kapı, kaydın BEYAN ettiği `project` alanını okur.

### 3. `doctor` dört hata sınıfını adıyla yakalıyor · GEÇTİ
`native/doctor_test.sh` bölüm 9-12, sınıf başına bir fixture **ve bir POZİTİF KONTROL**
(her şeye ateşleyen kontrol de yakalanıyor). `three()` yardımcısı, WARN bloğunda §4.8'in
üç cevabı (ne / `why:` / `run:`) yoksa case'i kırmızı yapıyor. Her fixture kendi
`mktemp -d` ağacında, `HOME`/`RABADON_DIR`/`PATH` override; gerçek kurulum, gerçek
`~/.claude/settings.json` ve `~/.rabadon` bozulmadı.

| sınıf | doctor ne yapıyor |
|---|---|
| Node sürüm uyumsuzluğu | taban `package.json engines.node`'dan OKUNUYOR, kodda sabit sayı yok |
| ikili izin sorunu | X_OK'suz ikililer adlandırılıyor + tam o yollar için `chmod +x`; OS'in reddettiği spawn (quarantine / yanlış mimari) AYRI dal — "var ama çekirdek reddetti" ≠ "yok" |
| PATH çakışması | PATH yürünüyor, her `rabadon` realpath ile çözülüyor: "koşacağın rabadon kurduğun mu" |
| eski kurulum kalıntısı | ölü hook (yol yok) ile BAYAT hook (yol var, başka ağaç) ayrılıyor; sessizce patlayan ikincisi |

- `./native/doctor_test.sh`: **24 ok / 0 fail (taban) → 28 ok / 15 fail (yalnız ölçüt) →
  43 ok / 0 fail (kodla birlikte)**, exit 0.
- `node hooks/manage.mjs doctor` gerçek makinede `all green.`, exit 0.
- Fixture'ın beklenen cevabı koda gömülmedi (CLAUDE.md 3): kontroller `engines.node`,
  mod bitleri, PATH ve settings dosyasını okuyor, fixture adını tanımıyor.

### 4. CI matrisi: 2 OS × 2 Node = 4 hücre, temiz kurulum · GEÇTİ
`node: ['20','22']` eklendi. 20 keyfi değil: `release.yml` yayını ve smoke'u Node 20 ile
koşuyor, yani **yayımlanan yol test edilen yol** oldu. `fail-fast: false` korundu.
`continue-on-error` / `|| true` eklenmedi. `disclosure` job'ına dokunulmadı.
Temiz prefix kurulumu için ayrı adım gerekmedi: `grep -n npm_install_test Makefile` → 602,
`test` reçetesinin içinde (104'te başlıyor) — dört hücrenin dördü tarball'ları paketleyip
temiz prefix'e kuruyor.

### 5. CI main'de yeşil · GEÇTİ (rapordan kopyalanmadı, `gh run view` çıktısı)
```
$ gh run view 32924786346
✓ main ci · 32924786346
Triggered via push about 10 minutes ago

JOBS
✓ disclosure ubuntu-latest in 4s (ID 98045386604)
✓ macos-15 node22 in 5m21s (ID 98045386698)
✓ ubuntu-latest node22 in 5m49s (ID 98045386722)
✓ ubuntu-latest node20 in 5m39s (ID 98045386753)
✓ disclosure macos-15 in 9s (ID 98045386760)
✓ macos-15 node20 in 6m22s (ID 98045386787)
```
Altı job, altısı yeşil. Bir önceki main koşusunda (`32923315019`) `disclosure` iki
platformda da KIRMIZIYDI. Kırmızı zeminin üstüne adım atılmadı: kırmızı kaldırıldı.
**Kalan tek kırmızı iş akışı `pages build and deployment`** ve F1a ONU YEŞİLE ÇEVİRMEDİ —
F1a öncesinde de kırmızıydı (`32923314370`, `32922500146`), cevapçı kart açmamıştı
(yayın yolu `vercel`, `pages` ölü bir yol). Kırmızı **ad** kümesi büyümedi, küçüldü.

### 6. Kurulumdan çalışır guard'a kaç adım · ÖLÇÜLDÜ ve YAZILDI
Temiz `mktemp -d`, yerel klon, `HOME`/`RABADON_DIR`/`npm_config_prefix` override.
- **N = 5 birleşik satır / 7 ayrık kabuk komutu**, ~35,8 s, kanıt adımı hariç.
- "iki komut" iddiasıyla fark: **+3 satır / +5 komut.** İddia savunulmadı.
- Bu, `npm i -g` yolunun DEĞİL, bugün belgelenmiş kaynaktan derleme yolunun sayısıdır.
  `npm i -g` yayınla gelir ve F1n'in işidir.

### 7. Ajan yüzeyi tablosu ölçüme dayanıyor · GEÇTİ
Cursor için "destekleniyor" YAZILMADI. Üç sütun (`f1a-5`):
- **yapıyor:** `init` `.cursor/hooks.json`'ı beş olayla yazıyor; bir Cursor payload'ı
  gerçek gate'te fiilen reddediliyor (exit 2, `{"permission":"deny",...}`).
- **yapmıyor:** ledger'da Cursor'a atfedilebilir SIGNAL/INJECT/COUNTER **0**; ledger'da
  ajanı ayırt eden alan (`agent`/`dialect`/`editor`/`client`) HİÇ YOK, yani Cursor
  ateşlese bile atfedilemezdi; `remove` Cursor'u sökmüyor; `beforeFileEdit` yok.
- **ÖLÇÜLEMEDİ:** Cursor uygulaması başlatılmadı (GUI, kart dışı).
- Sıfırı basan komut birebir:
  `grep -ah "cursor" ~/.rabadon/spool/*.jsonl | grep -ac '"ev":"\(SIGNAL\|INJECT[A-Z_]*\|COUNTER\)"'` → **0**
  ("cursor" geçen 30 satırın tamamı `STEP_START`/`STEP_OK`/`RUN_START` — kanıt sayılmaz.)

### Kalan yirmi verb silinmedi, test sayısı düşmedi · GEÇTİ
`dev` ekranındaki 30 verb duruyor, hiçbiri silinmedi.
`make test` **3438 ok → 3462 ok**, 0 gerçek fail, exit 0. `npm test` **64/64**, 0 fail.
Toplam **3502 → 3526 yeşil**. Hiçbir test silinmedi, zayıflatılmadı, atlanmadı,
yeniden adlandırılmadı.
(`/tmp/f1a.maketest.out:3941`'deki tek `FAIL` satırı `regression_demo.sh`'ın fikstür
çıktısıdır ve kırmızı DEĞİLDİR — ENVANTER §e bu tuzağı adıyla uyarıyor, `make test` exit 0.)

---

## §8 KAPI — dokuz madde, şef koşturdu

| # | kapı | hüküm | kanıt |
|---|---|---|---|
| 1 | kabul betiği yeşil | GEÇTİ | `make test` exit 0 (3462 ok), `npm test` exit 0 (64/64), `make disclosure` exit 0 |
| 2 | **boş yeşil kontrolü** | GEÇTİ | üçü de aşağıda, her biri kendi `.out` dosyasıyla |
| 3 | kırmızı **AD** kümesi büyümedi | GEÇTİ | `bash reports/R7/accept.sh` → 23 yeşil / 3 kırmızı, adlar `{2b, 6e, 7b}` — ENVANTER'de dondurulan kümenin AYNISI |
| 4 | eşik/tolerans/ön-kayıt/fixture değişimi gerekçeli | GEÇTİ | hiçbir eşik oynatılmadı; değişen fixture'lar YENİ eklendi, mevcut biri değiştirilmedi; her commit mesajı gerekçeli |
| 5 | ölçüm sevk edilen yoldan | GEÇTİ | gerçek native ikili: R7 `2b` 1244,2 µs gate ikilisinden; kart 5'in guard kanıtı gerçek `rabadon-gate`'e stdin'den tek JSON; doctor fixture'ları gerçek ikililer üstünde |
| 6 | **UX kapısı** (üçü de yazılı) | GEÇTİ | kaç adım: **N=5/7**; ekranda ne yazıyor: `init` çıktısı `f1a-5`'te **birebir**; nasıl kaçıyor: `off` ve `remove` temiz kopyada gerçekten koşuldu, çıktıları yazılı |
| 7 | hakem hükmü GEÇTİ | **ŞEFİN İŞİ DEĞİL** — hakem ayrı, temiz oturum (§9). Orkestratör açar. |
| 8 | kâtibin commit'i | **KÂTİBE** başlığı altında aşağıda; F1a'da kâtip ayrı oturum, şef docs/README/site metnine dokunmadı |
| 9 | SAPMA satırı | aşağıda |

### Boş yeşil kontrolü, üç kez (§8.2)
1. **Yüzey tavanı** — help ekranına kasten altıncı ürün satırı eklendi:
   `./native/cli_test.sh` → **EXIT 1, 312 ok / 3 fail**,
   `BLOCKED: the main help screen lists 6 product commands, not 5 — [init on|off usage repair doctor scan]`.
   Satır geri alındı, `git diff --stat native/rabadon-cli.sh` BOŞ. → `f1a-1-bosyesil.out`
2. **Disclosure** — `RABADON_PUBLISH_UNDECIDED=1` ile artefaktlar yeniden üretildi:
   `make disclosure` **exit 2**, `62 found, 12 allowed, 50 off-list`. Anahtar kaldırıldı,
   yeniden üretildi, exit 0. (41 değil 50, çünkü iki koşu arasında ledger büyüdü.)
   → `f1a-2-bosyesil.out`
3. **doctor** — ölçüt kodsuz koşturuldu: **EXIT 1, 28 ok / 15 fail**, dört sınıf da kırmızı.
   `f1a-3-kirmizi-once.out`. **Bunu şef KENDİ de yeniden koşturdu:** `hooks/manage.mjs`
   HEAD'e döndürüldü → `./native/doctor_test.sh` EXIT 1, `doctor: 28 passed, 15 failed`;
   sonra geri alındı. Rapordaki sayı kopyalanmadı, tekrar üretildi.

---

## SAPMA SATIRI (§8.9)

**F1a, §5'in 2. adımını (“kurar”) gerçek yaptı — ama tabloyu “kurulabiliyor” diye
işaretlemek için değil, kurulumun NEREDE PATLADIĞINI ölçülebilir yaptığı için.**
Gösteren sayılar: kurulum matrisi elden CI'a geçti ve dört hücrenin dördü yeşil
(`gh run view 32924786346`); dört sessiz kurulum ölümü artık adıyla yakalanıyor
(doctor 24 → 43 ok, ölçütsüz halinde 15 kırmızı); yüzey tavanı ilk kez kırmızı düşebiliyor
(cli 310 → 315 ok, kasıtlı altıncı verb'de 3 fail); disclosure kapısı gevşetilmeden
kapandı (41 off-list → 0, allowlist'e tek isim eklenmeden).

**SAPTIK MI: HAYIR, ama adım YARIM.** §5'in 2. satırı "iki komut, soru yok" diyor.
Soru sorulmuyor kısmı doğru (`init` 0 soru, 0,546 s). "İki komut" kısmı **yanlış** ve
ölçüldü: **5 satır / 7 komut**. Ve ölçümün açtığı daha kötü gerçek: **`rabadon on`
hiçbir kurulum belgesinde yok ama zorunlu** — README'yi harfiyen izleyen kullanıcı
WATCH modda, hiçbir şeyi reddetmeyen bir guard kuruyor (aynı hook olayı `on`'suz
exit 0 "Nothing was stopped", `on` sonrası exit 2 "rabadon BLOCKED this action").
Bu F1a'nın kapattığı bir delik değil, F1a'nın ORTAYA ÇIKARDIĞI bir delik ve
olumluya çevrilmiyor (CLAUDE.md 8).

---

## KÂTİBE (F1a'da kâtip ayrı oturum — şef bunları YAPMADI, yazdı)

1. **README kurulum bloğu `rabadon on`'u atlıyor ve bu bir sessiz felakettir.**
   `grep -n 'rabadon on' README.md` → kurulum bloğunda sıfır eşleşme. Bloğu izleyen
   kullanıcı hiçbir şeyi reddetmeyen bir kurulum elde ediyor. Ölçüm: `f1a-5` §A.
   Bu, kâtibin F1a kapanışında yazacağı BİRİNCİ satırdır.
2. **README (`npm install && npm link`) ile `site/index.html` (`git clone && make`)
   kurulum satırı çelişiyor.** İkisi de temiz kopyada koşuldu, ikisi de çalıştı —
   yani hata "biri bozuk" değil, "iki farklı doğru" ve kullanıcı hangisini izleyeceğini
   bilmiyor. Tek doğru yol seçilip diğeri gerekçesiyle arşive.
3. **`site/index.html`'deki kurulum satırına DOKUNULMADI ve dokunulmamalı.**
   `npm i -g` yolu F1n kapanana kadar yazılamaz; bugün yazılırsa sayfa çalışmayan bir
   kurulum satırı satar. (Operatör kapsam sınırı; F1a bunu ihlal etmedi, doğrulandı:
   `git diff` içinde kurulum satırı yok.)
4. **`site/` artefaktları yeniden üretildi** (kart 2). Manşet sayılar oynadı ve biri
   AŞAĞI indi: `field.stop` 431 → 391, `field.rules_live` 13 → 11, ledger neredeyse
   iki katına çıkmışken (127.112 satır / 22 gün → 246.342 / 32). Bu saklamadan
   kaynaklanmıyor (`is_lab`, drill filtresi ve STOP sayımı `project_of`'a hiç dokunmuyor).
   **Ayrı bir bakış istiyor ve olumluya çevrilmeden yazılmalı.**
5. **Commit'lenmiş `index.html` 508 red diyor, commit'lenmiş `measured.json` 431 diyordu**
   — sayfa ile veri seti bu değişiklikten ÖNCE de 77 ayrıydı. Sayfada duran her sayının
   yanında onu basan aletin adı ve ölçüm tarihi olmalı (§7/F7 kabulü).
6. **`docs/agent-contract.md`'ye Cursor satırı:** "destekleniyor" yazılmaz. `f1a-5`'in üç
   sütunlu tablosu aynen alınır, 0 ledger satırı ve onu basan `grep -a` komutu dahil.

---

## AÇIK KALAN, GİZLENMEYEN (kart açılmadı, bütçe 5/5 doldu)

- **`removeCursorHooks` YOK.** `installCursorHooks` var, karşılığı yok: `rabadon remove`
  ve `uninstall --purge` `.cursor/hooks.json`'a dokunmuyor, dosya beş olayla tam kalıyor.
  **Cursor kullanıcısının çıkış yolu yok** ve bu §4.9'un ("kesin seviyenin her kuralının
  çıkış yolu vardır") doğrudan ihlalidir. `.gitignore`'a eklenen 2 satır da geri alınmıyor.
- **`rabadon off` KAPALI DEĞİL, WATCH.** Gate her tool çağrısında koşmaya ve ledger'a
  yazmaya devam ediyor. §5'in 7. adımı ("rahatsız olursa tek sinyali kısar") için bu
  yeterli olabilir, ama `off` kelimesi yaptığı şeyi söylemiyor.
- **Ledger'da ajanı ayırt eden alan yok** (`agent`/`dialect`/`editor`/`client` → boş).
  F8'in "OpenHands'te enjeksiyon ledger'da görünüyor" kabulü bu alan olmadan
  KANITLANAMAZ. F8'den önce çözülmeli.
- **`pages build and deployment` iş akışı hâlâ kırmızı** (ölü yayın yolu; yayın `vercel`).
  F1a öncesinde de kırmızıydı, büyümedi.
- `package.json` `engines.node: ">=18"` diyor ama CI'da 18 hücresi yok — 18 desteği
  hâlâ ölçülmemiş bir iddia. Ya hücre eklenir ya taban yükseltilir.
- `npm_install_test.sh:24-30` npm yoksa `exit 0` + SKIPPED basıyor: skip'in pass gibi
  okunduğu bir yüzey (dosyanın kendisi uyarıyor). CI'da npm hep var, ama denetim orada.
- `doctor`'ın `version drift` uyarısı hâlâ tek satır — `why:`/`run:` yok, §4.8'e göre eksik.
  Kartın dört sınıfı dışındaydı.
- `dev` ekranının (30 verb) tavanı yok; `bin/rabadon.mjs`'teki elle yazılmış verb listesi
  dispatcher'la karşılaştırılmıyor. Help metnindeki "Five commands is the whole product"
  cümlesi sayıya bağlı değil.
- Serbest metne gömülü liste dışı adlar (`site/catches.html`, `site/field.html`,
  `site/field.jsonl`, `site/rule_census.json`) duruyor. Kapatmak 41 adı alt-dizge
  değiştirmeyi ister, birkaçı sıradan kelime (`blog`, `reports`, `sunflower`).
- Kum havuzu `/tmp/f1a.sqcNcG` silinmedi (kanıt kalsın diye).

## DOĞRULANMADI (§ CLAUDE.md self-audit — boş liste bakmadığın anlamına gelir)

- doctor'ın **quarantine dalı** fixture'la kanıtlanmadı; karantinalı bir ikili indirmek
  gerekiyor. chmod -x dalı kanıtlı ve ikisi aynı kod dalı — ama bu bir çıkarım, ölçüm değil.
- **Gerçek eski Node** (v16/v18) ile koşulmadı; sürüm tabanı yükseltilerek üretildi.
- Temiz bir KONTEYNERDE fresh clone koşulmadı; temiz makine kanıtı CI'ın dört hücresi.
- Cursor uygulaması hiç başlatılmadı.
- Kart 5'in ölçtüğü N, **bu makinede** ölçüldü; Linux'ta kaç adım olduğu ölçülmedi.
