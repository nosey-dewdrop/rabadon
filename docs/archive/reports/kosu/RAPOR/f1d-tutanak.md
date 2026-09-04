# F1d TUTANAK — "durum ekranı yalan söylemez"

Faz aralığı: `1ea32c4..HEAD`. Dal `main`, tek kök, yeni dal/worktree açılmadı
(§8.2 için `--detach` geçici worktree kullanıldı ve kaldırıldı).
Kaynak: `reports/kosu/SAPMA-KARARLARI.md` · B1 ve B2.
Şef kod yazmadı; üç işçi salındı (tavan 3), kâtip işi şefin son işi olarak koştu (§9).

---

## 0. FAZIN SEBEBİ — ölçüm, iddia değil

`.rabadon/off` dururken, **sevk edilen** yüzey (`package.json` bin =
`native/rabadon-cli.sh`) şunu diyordu — şefin kendi kum havuzunda, faz
başlamadan yeniden koşturuldu:

    $ native/rabadon-cli.sh on
    rabadon: ON — the arbiter acts: refuses, repairs, proves
    $ native/rabadon-cli.sh status
    rabadon: ON — the arbiter acts: refuses, repairs, proves
      read from: .../.rabadon/mode (present)
    $ printf '<PreToolUse: git push --force origin main>' | native/rabadon-gate
    EXIT=0    stdout: 0 BAYT   stderr: 0 BAYT
    $ printf '{"workspace":...}' | native/rabadon-gate --statusline
    tmp.J6x6A7mci0  * rabadon off

Aynı ikili, aynı an, aynı proje: ekran **ON**, gate **hiç konuşmadı**,
lamba **off**. Bir fren ürününde bu, ürünün tanımının tersidir (§1, §4.8,
§4.12, CLAUDE.md Promise 1). Ve bunu kırmızıya düşürebilen tek bir test
yoktu — kırmızı ad kümesinde görünmemesinin sebebi düzelmiş olması değil,
**hiç ölçülmemiş olmasıydı** (§8.2).

---

## 1. KABUL MADDELERİ — tek tek, kanıtla

### Madde 1 — durum ekranı gate'in HESAPLADIĞI durumu basar · KAPANDI

`native/gate.cpp` içinde tek bir `compute_state(dir)` doğdu. Gate'in kapıda
okuduğu HER girdiyi aynı öncelikle okur: üç susturucu (`RABADON_OFF=1`,
`<proje>/.rabadon/off`, `<RABADON_DIR>/silent`) ve katmanlı mod
(`RABADON_MODE` → `<proje>/.rabadon/mode` → `<proje>/.rabadon/on` →
`<RABADON_DIR>/mode` → `<RABADON_DIR>/enabled`), `blind` kuralı dahil.
**Sıcak yol ikinci bir kopya tutmuyor** — eski ~50 satırlık ayrı okuma silindi
ve sıcak yol aynı fonksiyonu çağırıyor. İki kopya, yarın yeniden ayrışacak
iki kopyadır; F1d tam olarak o ayrışmanın faturasıdır.

Ekran §4.8'in üçünü de basıyor — şefin kendi kum havuzu,
verbatim `reports/kosu/RAPOR/f1d-0-ekran.out`:

    $ native/rabadon-cli.sh on            # .rabadon/off dururken
    rabadon: SILENT — silenced; the gate returns 0 before any rule runs
      silenced by: .rabadon/off (/…/tmp.fsoPYWtHIS/.rabadon/off)
        next: rm /…/tmp.fsoPYWtHIS/.rabadon/off
      the mode underneath is now `enforce`, but nothing will be refused
      while the silencer above is in place.

**NE** bloklandı: hiçbir şey, gate susturulmuş. **NEDEN**: adıyla ve tam
yoluyla `.rabadon/off`. **SIRADAKİ TEK KOMUT**: `rm <tam yol>`.
Yürürlükteki her susturucu ayrı satır alır; hiçbiri gizlenmez.

Ve ekranın verdiği o tek komut koşulduğunda:

    $ rm <proje>/.rabadon/off
    $ native/rabadon-cli.sh status
    rabadon: ON — the arbiter acts: refuses, repairs, proves
    $ aynı olay | native/rabadon-gate      → EXIT=2
    $ --statusline                          → * rabadon   (lamba yanıyor)

Susturucu yokken üç satır (ON / WATCH / SILENT) **bayt bayt eski haliyle**
kaldı — mevcut testler onları pinliyor, hiçbiri değiştirilmedi.

### Madde 2 — kırmızı düşebilen KİLİT, vekil değil · KAPANDI

`native/status_truth_test.sh` (yeni). **16 hücre** —
`mode {watch,enforce}` × `.rabadon/off {var,yok}` × `RABADON_OFF {1,unset}` ×
`silent {var,yok}` — her hücrede **3 iddia** (`status`, `on`, `off`).
Her iddia, CLI'ın metnini değil **gerçek `native/rabadon-gate` ikilisinin
çıkış kodunu ve çıktı bayt sayısını** karşısına alır:

| gerçek hal | çıkış kodu | çıktı |
|---|---|---|
| ENFORCE | 2 | dolu |
| WATCH | 0 | **dolu** ("would have blocked") |
| SUSTURULMUŞ | 0 | **0 bayt** |

"ON" iddiası + `EXIT=0` **kırmızıdır**. WATCH iddiası + 0 bayt da kırmızıdır —
susturulmuşluğu watch diye satmak aynı yalanın ikinci tonu.
Hermetik: her hücre kendi `mktemp -d` proje + `mktemp -d` `RABADON_DIR` +
`mktemp -d` `HOME`'unda; gerçek `~/.rabadon`'a hiç yazılmaz; yalnız git ve
shell ister (`python3`/`jq`/`node` YOK — CLAUDE.md temiz-konteyner barı).
**Pozitif kontrol** var: hiçbir hücrede `exit 2` görülmediyse ölçüm aleti
bozuktur ve test BLOCKED basar — boş yeşil bu betikte de yasak.

### Madde 3 — `status` ile `--statusline` bir daha AYRIŞAMAZ · KAPANDI

Aynı test, her hücrede ikisini de çağırır ve aynı ana dair aynı hükmü şart
koşar. `--statusline` artık aynı `compute_state`'ten türüyor.

**Ölçüm hakemin bulduğundan DAHA KÖTÜ çıktı** (işçi B'nin bulgusu):
`--statusline` `<RABADON_DIR>/mode` dosyasını **hiç okumuyordu**, yani
susturucu OLMAYAN düz `mode=enforce` hücresinde bile "watch" diyordu.
Ayrışma tek bir hücrede değil, üçüncü bir okumadaydı. İkisi de kapandı.

### Madde 4 — `bin/rabadon.mjs` EDİTLENMEDİ, delik yine de kapandı · KAPANDI

Dosya donmuş anti-path (`.rabadon/guard.json` `protectedPaths`), dondurmayı
çözmek operatörün kararıdır (O3, **varsayılan: donuk kalır**).
`git diff --name-only 1ea32c4..HEAD` çıktısında `bin/` **yok**.

Yerine kilit yazıldı — `status_truth_test.sh` C bölümü, bugün **4/4 yeşil**:
`package.json` `bin` → `native/rabadon-cli.sh`; dispatcher'ın `on|off|status)`
ve `toggle)` kollarının gövdesinde `rabadon.mjs` geçmiyor; `scripts` içinde
anti-path'e giden bir denetim verb'ü yok. **Yarın biri o dosyayı geri
bağlarsa bu kilit kırmızı düşer.**

### Madde 5 — `.rabadon/off` belgelendi · KAPANDI (kâtip işi, yalnız `docs/`)

`docs/commands.md` (üç susturucu tablosu), `docs/faq.md` ("gate ateşlemiyor"
teşhisinin 2. adımı), `docs/uninstall.md` ("silmeden sustur").
Her biri için: dosya adı ve tam yolu, ne yaptığı (gate hiçbir kural koşmadan
0 döner, hiçbir şey kaydedilmez), ve onu kaldıran tek komut.
Ve dürüst uyarı, ölçülerek: **`rabadon off` bu dosyayı KALDIRMAZ.**
İşçi C izole `RABADON_DIR` ile ölçtü: `rabadon off` WATCH yazıyor, `mode`
dosyasını yazıyor, `<proje>/.rabadon/off` **yerinde duruyor**.
`README.md` ve `site/` bu iş için açılmadı — gerekmediği ölçüldü.

### Madde 6 — B2, ölü kurulum yolu · KAPANDI

`npm view rabadon version` → E404. `git tag --list` → `v0.2.0 v0.2.1 v0.2.2`;
`package.json` sürümünün etiketi **YOK**. `docs/quickstart.md` §1 bu ölü
komutu kopyalanabilir blok olarak satıyordu ve F1c'nin kilidi onu görmüyordu.

`native/install_docs_test.sh` genişledi (**20 ok → 38 ok**, hiçbir eski ok
düşmedi). Tuttuğu değişmez: *`package.json`'daki sürümün `v<sürüm>` etiketi
`git tag --list`'te YOKKEN, sevk edilen hiçbir belgede `npm i -g rabadon`
yazılabilir bir komut olarak duramaz.* "Yazılabilir" mekanik olarak tanımlı:
fence/`<div class="term">` içindeyse her zaman ihlal; düz metinde ise
yakınında "yayımlanmadı" işareti yoksa ihlal.
**Çevrimdışı** — yalnız `git tag --list` + dosya okuma, ağ isteği YOK, temiz
konteynerde koşar. **F1n gününde kendiliğinden serbest bırakır**: işçi C bunu
`v0.2.3` etiketli geçici bir repoda gerçek koşuyla kanıtladı — etiket varsa
tarama hiç yapılmıyor.
Kapsam dışı ve gerekçesi kodda yazılı: `CHANGELOG.md`, `site/patch-notes.html`,
arşivler — tarihsel kayıttır, geçmişte yazılmış cümleyi bugünkü etiket
durumuna göre değiştirmek sessiz tarih tahrifidir.
Eski npm cümlesi **silinmedi**: gerekçesiyle prose olarak duruyor
("henüz npm'de değil, E404, ölçüm 2026-08-26").

### Madde 7 — kırmızı ad kümesi + test sayacı · KAPANDI

Aşağıda §3.

---

## 2. §8 KAPISI — dokuz madde, şef hepsini kendi koşturdu

**1. Fazın kabul betiği yeşil.**

    $ bash native/status_truth_test.sh      → 94 ok / 0 fail, EXIT=0   (öncesi 17/77)
    $ bash native/install_docs_test.sh      → 38 ok / 0 fail, EXIT=0   (öncesi 20/0)
    $ bash native/version_test.sh           → 13 ok / 0 fail, EXIT=0
    $ npm test                              → 64 pass / 0 fail, EXIT=0
    $ bash reports/R7/accept.sh             → EXIT=1, 23 yeşil / 3 kırmızı

**2. BOŞ YEŞİL KONTROLÜ (§8.2) — AYRI WORKTREE, faz öncesi artefakt.**
Verbatim: `reports/kosu/RAPOR/f1d-bosyesil-worktree.out`.

    $ git worktree add --detach /tmp/f1d-pre 1ea32c4
    $ cp native/{status_truth,install_docs}_test.sh /tmp/f1d-pre/native/
    $ cd /tmp/f1d-pre && make all                    → exit 0
    $ bash native/status_truth_test.sh   → 17 ok / 77 fail, EXIT=1   KIRMIZI
    $ bash native/install_docs_test.sh   → 35 ok /  3 fail, EXIT=1   KIRMIZI

İki yeni kilidin ikisi de faz öncesi kodda kırmızı düşüyor, HEAD'de yeşil.
Boş yeşil değil. Worktree iş bitince kaldırıldı.

**3. Kırmızı AD kümesi büyümedi.** `{2b, 6e, 7b}` — aynı üç ad, aynı üç
gerekçe. `2b` bu koşuda **1293,2 µs** (tavan 1000 µs, hiç oynatılmadı).
Tarihsel seri: 1299,4 → 1244,2 → 1261,0 → 1310,8 → 1248,8 → 1229,9 → 1184,7
→ 1270,3 → **1293,2**. Sürüklenme yok, bant içinde. `2b` DEVRALINAN bir
kırmızıdır, F1d'nin açtığı değil; sahibi atanmış (ölçüm+yasak F2-S9,
onarım F3-S1). Test süitlerinde kırmızı ad YOK.

**4. Eşik / tolerans / ön-kayıt / fixture değişimi:** HİÇBİRİ.

    $ git diff --name-only 1ea32c4..HEAD | grep -iE "fixture|threshold|accept|prereg|R7/"
    (boş)
    $ git log --diff-filter=D --name-only 1ea32c4..HEAD
    (boş — silinen dosya yok)

Mevcut hiçbir test değiştirilmedi, zayıflatılmadı, atlanmadı, silinmedi.

**5. Ölçüm sevk edilen yoldan alındı.** Her hücrede gerçek
`native/rabadon-gate` ikilisi, gerçek `native/rabadon-cli.sh` dispatcher'ı,
`package.json` `bin`'inin gösterdiği yol. Vekil yok, mock yok.

**6. UX KAPISI — üç satır (§8.6).**
- **Kaç adım:** susturucudan çalışır frene **1 adım**. Ekran o tek komutu
  yazıyor (`rm <tam yol>` / `unset RABADON_OFF` / `rabadon off`); kullanıcı
  onu koşuyor, `status` ON diyor ve gate `exit 2` veriyor. Kurulum adım
  sayısı **3 birleşik satır / 0 soru** (F1c'de ölçüldü, F1d değiştirmedi).
- **Ekranda ne yazıyor:** `f1d-0-ekran.out` verbatim — durum satırı +
  yürürlükteki her susturucu için `silenced by: <ad> (<yol>)` + `next: <tek komut>`
  + `read from:` katmanı. Yalan söyleyen ekran yok; ON iddiası ancak gate
  gerçekten `exit 2` veriyorsa basılabilir ve bu bir testle kilitli.
- **Kullanıcı nasıl kaçıyor:** üç susturucu artık BELGELİ ve her birinin
  kaldırma komutu ekranda + `docs/`'ta yazılı. §4.9 "her kuralın çıkış yolu
  vardır" ancak çıkış yolu BİLİNİYORSA gerçektir — bugün biliniyor.

**7. Hakem hükmü:** orkestratörün işi, bu tutanağın dışında (§9, §14).

**8. Kâtip commit'i:** `01a0951` (docs, işçi C) ve `cf34caf` (docs, şefin son
işi §9). İkisi de yalnız `docs/`.

**9. SAPMA satırı:** aşağıda §4.

---

## 3. DEVİR SAYILARI — B5'in TEK GEÇERLİ SAYACIYLA

Yeni lehçe uydurulmadı; `DURUM.md`'nin ilan ettiği üçlü komut koşuldu.

| ölçü | faz öncesi (1ea32c4) | F1d sonrası |
|---|---|---|
| `make test` exit | 0 | **0** |
| native iddia (`^[[:space:]]*ok\b`) | 3504 | **3616** (+112) |
| native `PASS (N checks)` toplamı | 612 | **612** (değişmedi) |
| native toplam | 4116 | **4228** |
| `npm test` | 64 / 0 | **64 / 0** |
| **TOPLAM** | **4180 yeşil / 0 kırmızı** | **4292 yeşil / 0 kırmızı** (+112) |

Sayaç **DÜŞMEDİ**. Yeni testler eklendi, hiçbiri silinmedi.
`make test` çıktısındaki tek `FAIL` dizesi `regression_demo.sh`'in FİKSTÜRÜDÜR
(satır 4112, "what rabadon reports" başlığının altında rabadon'un kendi
raporunu gösteren demo metni); o süit `regression: 4 passed, 0 failed` diyor
ve `make test` exit 0. F1c hakemi de aynı dizeyi görüp aynı sonuca varmıştı.

---

## 4. SAPMA SATIRI (§8.9)

**F1d, §5'in hiçbir YENİ adımını gerçek yapmadı — var olan iki adımın
(2 "kurar", 4 "çalışırken") altındaki YALANI kaldırdı.**
Gösteren sayı: `status_truth_test.sh` **17 ok / 77 fail → 94 ok / 0 fail**,
aynı betik, aynı matris, biri faz öncesi ayrı worktree'de. 77 çelişkinin
77'si, CLI'ın iddiası ile gerçek gate'in çıkış kodu arasındaydı.
**Saptık mı: HAYIR.** Ölçü gevşetilmedi, sertleşti: SAPMA-KARARLARI B1'in
istediği matris (16 hücre) aynen koşuldu, üstüne `status`↔`--statusline`
uyumu ve §4.8 açıklama üçlüsü hücre başına ayrı denetim olarak eklendi.
Yeni verb yok (`rabadon-cli.sh` `1ea32c4` ile **bayt bayt aynı**), yüzey
hâlâ beş, varsayılan hâlâ WATCH, `bin/rabadon.mjs` hâlâ donuk.

---

## 5. İŞÇİLERİN KART METNİNDEN SAPMASI — açıkça yazılı

İşçi A, şefin yazdığı ekran sözleşmesinden **üç noktada** saptı ve üçünü de
raporladı. Sapmanın sebebi her seferinde aynı: **kırmızı kilit testi zaten
yazılmıştı ve testi değiştirmek yasaktı**, o yüzden sözleşme testin
okuduğu biçime uyduruldu, test sözleşmeye değil.
1. İlk satır `OFF —` değil `SILENT — silenced; …` (testin `claim_of()`
   ayrıştırıcısı yalnız ON/WATCH/SILENT tanıyor).
2. Tek `next:` yerine her susturucuya bir `next:` (test her susturucunun
   kaldırma komutunu ayrı arıyor).
3. "ne yaptım" satırında mod adı küçük harf (büyük `WATCH`, susturulmuş
   ekranı yanlış iddiaya düşürüyordu).
Bu doğru yöndür: **ölçüt kodu şekillendirdi, kod ölçütü değil.**

Ayrıca işçi A bir gerçek hata buldu ve düzeltti: macOS'ta `getcwd()`
`/tmp`'yi `/private/tmp`'ye çeviriyordu, yani `next: rm <yol>` satırı
kullanıcıya **var olmayan bir yol** gösterecekti. `$PWD` tercih ediliyor.

**Şefin kâtip olarak düzelttiği kırmızı:** işçi C'nin docs commit'i
(`01a0951`) `docs/quickstart.md`'ye `0.2.3` ve `v0.2.3` sürümlerini düz
metne yazmıştı; devralınan `native/version_test.sh` bunu DRIFT olarak
yakaladı ve `make test`'i kırmızıya düşürdü ("prose'a yazılan sürümü
hiçbir şey bump etmez, yalnız bayatlar"). Test değiştirilmedi; cümle
`package.json`'ı alıntılamak yerine ona işaret edecek şekilde yeniden
yazıldı (`cf34caf`). **Gerçek bir yakalama, kendi ürünümüzün kendi
üstünde.** `version_test.sh` 12/1 → 13/0.

---

## 6. NOT VERIFIED / ÖLÇMEDİĞİM (§5.5, CLAUDE.md kural 8)

- **Temiz konteynerde / temiz klonda hiçbir şey koşulmadı.** İki yeni kilit
  de yalnız `git` + POSIX shell kullanıyor, ama bu bir argümandır, koşum
  değil. CI'da koşacaklar (Makefile `test:`'e bağlı) — **o koşum bu
  tutanakta YOK.**
- **Gerçek Cursor uygulaması başlatılmadı.** `.rabadon/off` yolu Cursor
  tarafında sınanmadı.
- **`2b` yalnız bu makinede ölçüldü** (1293,2 µs). CI referans ortamı
  ölçümü F2-S9c'nin işi, F1d'nin değil.
- **`rabadon on` susturucu varken hâlâ exit 0 döner.** Ekran doğruyu
  söylüyor ama çıkış kodu "başaramadım" demiyor. Davranış kırmamak için
  öyle bırakıldı — PARKED, aşağıda.
- Faz öncesi `make test` sayacı (3504/612) bu oturumda **yeniden ölçüldü**
  ve B5'in ilan ettiği tabanla birebir tuttu; rapordan kopyalanmadı.

---

## 7. PARKED — kart açılmadı, dokunulmadı, yazıldı

1. **`rabadon on` susturucu varken 0 döndürüyor.** Ekran dürüst, çıkış kodu
   değil. Betik yazan biri `rabadon on && ...` diyorsa hâlâ yanılır.
2. **İki ayrı "kapalı" kavramı tek komut adıyla yönetiliyor** (mod=watch ve
   proje susturucusu). F1d bunu GÖRÜNÜR yaptı, BİRLEŞTİRMEDİ — birleştirme
   kararı verilmedi (SAPMA-KARARLARI'nda da açık).
3. **`docs/uninstall.md:56` `npm rm -g rabadon` diyor** — kaynaktan `npm link`
   kurulumunda doğrusu `npm unlink -g rabadon`. B2 ile aynı aile (ölü komut),
   farklı fiil, kilit yakalamıyor.
4. **`PROJECT.md:61,163` ve `SPEC.md:34` npm kurulumunu sevk edilen yol
   olarak anlatıyor.** B2 kilidi planlama belgelerini kapsamıyor.
5. **İşçi C, tarih-tahrifi istisnasını `docs/archive/`'dan `*/arsiv/*` ve
   `docs/kanit/*`'a uzattı.** Kart bunu vermemişti; ikinci bir göz görsün.
6. **`--status`'ın `read from:` satırı** susturucu varken "not consulted"
   diyor; doğru ama katman adını (env/project/machine) basmıyor.
7. **`installCursorHooks` okunamayan `hooks.json`'ı yedeksiz üstüne yazıyor**
   (F1c'den devralındı, hâlâ açık).
8. **Şefin kendi komutu rabadon tarafından reddedildi** (`no-exit-code-after-pipe`)
   ve işçi C'ninki de (`no-blind-inplace-source-rewrite`). İkisi de gerçek
   yakalama, ikisi de bu oturumda. F1b'nin dogfooding sayısına aday, kart
   açılmadı.
