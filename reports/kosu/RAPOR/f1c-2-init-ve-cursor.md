# f1c-2 — init ekranı ve Cursor çıkışı

Kart: `f1c-2-init-ekrani-ve-cursor-cikisi`. Dal: `main`. Yeni verb eklenmedi,
mevcut `remove` düzeltildi, `init` ekranı §4.8'in üç cevabını verecek şekilde
kapatıldı.

## YAPILAN

| ne | yol | commit |
|---|---|---|
| test önce, tek başına (kabul ölçütü) | `native/exit_path_test.sh` (yeni, 22 kontrol) + `Makefile` `test:` içine tek satır | `0073521` |
| kod | `hooks/install.mjs` (`removeCursorHooks`), `hooks/manage.mjs` (remove yolu + init ekranının son bloğu) | `0ba61db` |
| verbatim ekran + rapor | `reports/kosu/RAPOR/f1c-2-init-ekrani.out`, bu dosya | (bu commit) |

Yapılan işin özü iki cümle:

1. `rabadon init` ekranı `rabadon on|off` satırını taşıyordu ama hangi modda
   olunduğunu söylemiyordu. Varsayılan WATCH, WATCH hiçbir şeyi reddetmiyor —
   yani belgeyi harfiyen izleyen kullanıcı hiçbir şeyi durdurmayan bir guard
   kuruyor ve ekran "done" yazıyordu. Ekranın SONUNA üç cevaplı blok kondu:
   `right now: WATCH — every action is recorded and nothing is refused.` /
   `watch is the default … enforcing is your call, not ours.` /
   `next: rabadon on`. Tek `next:` satırı var; `rabadon on` KOŞTURULMUYOR,
   varsayılan WATCH kaldı.
2. `rabadon remove` `.cursor/hooks.json`'a hiç dokunmuyordu. `removeCursorHooks`
   eklendi: yalnız `rabadon-gate` taşıyan girdiler sökülür, kullanıcının kendi
   girdileri aynen kalır, dosya geçerli JSON kalır, geriye yalnız rabadon'un
   yazdığı iskelet kalıyorsa dosya (ve boşsa `.cursor` dizini) silinir,
   okunamayan/yazılamayan `.cursor` bir kaldırmayı patlatmaz.

## ÖLÇÜLEN (her sayının yanında onu basan komut)

| ölçüm | komut | sonuç |
|---|---|---|
| test, KOD ÖNCESİ (empty-green kontrolü) | `./native/exit_path_test.sh` @ `0073521` | **exit 1**, `exit path: 14 ok / 8 fail` |
| test, KOD SONRASI | `./native/exit_path_test.sh` @ `0ba61db` | **exit 0**, `exit path: 22 ok / 0 fail` |
| Makefile bağlaması | `grep -n "exit_path_test" Makefile` | 1 satır (satır 115), `test:` reçetesi içinde, `./native/install_docs_test.sh` hemen ardında |
| yeni fonksiyon gerçekten var | `grep -rn "removeCursorHooks" hooks/` | önce BOŞ → şimdi 4 satır (install.mjs tanım+export, manage.mjs import+çağrı) |
| CLI yüzeyi | `./native/cli_test.sh` | exit 0, `cli: 315 passed, 0 failed`; dispatcher hâlâ 37 advertisable verb / `bin/rabadon.mjs` hâlâ 15 verb — diff `hooks/` dışına çıkmadığı için yüzey sayısı değişmedi |
| doctor | `./native/doctor_test.sh` | exit 0, `doctor: 43 passed, 0 failed` |
| npm install yolu | `./native/npm_install_test.sh` | exit 0, `npm install: 12 passed, 0 failed` |
| node suite | `npm test` | exit 0, `tests 64 / pass 64 / fail 0` |

KIRMIZIYA DÜŞEN 8 KONTROL (kod öncesi, kanıt olarak): "the screen never says that
nothing is refused", "does not say that enforcing is the operator's decision",
"0 next: lines — expected exactly 1", "the next: line does not name `rabadon
on`", "after remove, 5 rabadon hook(s) are STILL in .cursor/hooks.json", "remove
says nothing about .cursor/hooks.json", "hooks.json still exists after remove",
"after remove, rabadon count is 5 in the user's own hooks.json". Yani denetim,
düzeltmeden ÖNCE, faz öncesi artefakt üstünde kırmızı düştü.

`native/exit_path_test.sh` neyi tutuyor (22 kontrol):
- A0 vacuity: init exit 0 mı, ekran gerçekten basıldı mı (33 satır). Ekran
  yakalanamazsa dosya sessizce geçmez, FAIL der.
- A1-A3: mod ADIYLA (`watch`), "hiçbir şey reddedilmiyor" anlamındaki cümle,
  NEDEN (`default` + "your call"), ve TEK `next:` satırı + içinde `rabadon on`.
  Tam metin karşılaştırması yok, hepsi anahtar-kelime/regex.
- Ters yön: ekran "enforcement is on" DEMEMELİ — init varsayılanı değiştirmiyor.
- B: pozitif kontrol (init 5 Cursor hook'u yazdı) → remove sonrası 0 →
  kullanıcının 2 kendi hook'u aynen duruyor ve dosya geçerli JSON → hiç Cursor
  olmayan projede remove exit 0 ve `.cursor` YARATMIYOR → ve PIN: yalnız
  rabadon'un yazdığı dosya SİLİNİYOR (boş iskelet bırakılmıyor).

## GERÇEK EV DOKUNULMADI

- Testin tamamı `mktemp -d /tmp/rabadon-exitpath-test.XXXXXX` altında, her vaka
  kendi `HOME` ve `RABADON_DIR`'ı ile koşuyor (`native/exit_path_test.sh:50-53`).
  Verbatim ekran yakalaması da aynı kalıpta (`.out` dosyasının başlığında sahte
  HOME yolu yazılı).
- `ls -ld ~/.claude/settings.json ~/.cursor` → `24 Ağu 14:56` ve `19 Tem 10:54`:
  bu koşuda değişmedi.
- `git status --porcelain` → commit'ler dışında temiz; diff yalnız
  `native/exit_path_test.sh`, `Makefile` (1 satır + yorum), `hooks/install.mjs`,
  `hooks/manage.mjs`, `reports/kosu/RAPOR/`.
- DÜRÜST İSTİSNA: `~/.rabadon/spool/2026-08-26.jsonl` ve `~/.rabadon/state.json`
  bu koşu sırasında BÜYÜDÜ (`ls -lt ~/.rabadon`, 07:01-07:02). Bunu testler
  yazmadı — bu oturumun kendisi rabadon tarafından denetleniyor ve gate her
  tool çağrısında kendi ledger'ına yazıyor. Testlerin `RABADON_DIR`'ı sahte.

## YAPILAMAYAN

- `.cursor/hooks.json.bak-rabadon`: kullanıcının kendi dosyası varken init bir
  yedek bırakıyor, `remove` o yedeği SİLMİYOR (bilerek — operatör dosyayı o
  günden beri düzenlemiş olabilir, geri yükleme bir kaldırmanın işi değil).
  Yani kullanıcının kendi hook'ları olan bir projede `.cursor/` içinde bir
  `.bak-rabadon` kalıyor. Kartta bir hüküm yoktu, karar yorumda yazılı.
- `rabadon remove --global` Cursor tarafı: `init --global` zaten Cursor
  yazmıyor (`manage.mjs`, `if (!global)`), ama `remove` global yolda da
  `removeCursorHooks(os.homedir())` çağırıyor. `~/.cursor/hooks.json`'da rabadon
  girdisi yoksa hiçbir şey yapmıyor (ölçüldü: hiç kurulmamış projede exit 0,
  dosya yaratılmıyor). Gerçek `~/.cursor` üstünde ÖLÇÜLMEDİ — orada koşmadım.
- `make test` bütünüyle koşturulmadı (tavan). Kartın istediği dört süit +
  `npm test` koşturuldu, hepsi yeşil. `make test` içinde bilerek kırmızı olan
  bir şey yok ama f1c-2'nin dokunmadığı 100+ süit bu raporda ÖLÇÜLMEDİ.
- Gerçek Cursor uygulamasıyla uçtan uca doğrulama yapılmadı: dosya biçimi
  `installCursorHooks`'un yazdığının tersi olarak doğrulandı, Cursor'ın kendisi
  çalıştırılmadı.

## KART DIŞI FARK EDİLEN (dokunulmadı)

1. `installCursorHooks` okunamayan bir `hooks.json`'ı MERGE ETMİYOR, ÜSTÜNE
   YAZIYOR (`catch { /* … an unreadable file is replaced, not merged */ }`).
   `.claude/settings.json` tarafında aynı durum `process.exit(1)` ile
   reddediliyor ("rabadon will not overwrite a file it cannot read"). İki
   yüzey, iki farklı yasa; Cursor tarafında operatörün bozuk ama düzeltilebilir
   dosyası sessizce kayboluyor (yedeği de alınmıyor, çünkü `existed=false`).
2. `init` ekranı `rabadon drill` / `rabadon usage` satırlarını "see it work in 30
   seconds" başlığı altında hâlâ sunuyor. Tek `next:` artık net, ama ekranda üç
   ayrı çağrı bloğu var (see it work / from here / next). Sadeleştirme kartın
   dışındaydı, dokunulmadı.
3. `rabadon remove` çıktısı "fully uninstall the CLI with: npm rm -g rabadon"
   diyor; kaynaktan kurulmuş bir ağaçta bu komut hiçbir şey yapmaz. Kart dışı.
4. `cli_test.sh` "ürün yüzeyi beştir" iddiasını sayı olarak ÖLÇMÜYOR; ölçtüğü
   şey dispatcher'ın 37 advertisable verb'ü ile yardım metninin uyuşması. Yani
   §4.10'un beş-yüzey yasasını bugün hiçbir test doğrudan tutmuyor.
