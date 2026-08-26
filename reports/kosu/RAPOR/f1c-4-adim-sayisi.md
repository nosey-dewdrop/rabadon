# F1c · KART 4 — kurulum adım sayısı, YENİDEN ölçüldü

Şef ölçtü (kod yazılmadı, yalnız komut koşturuldu). Tarih: 2026-08-26.
Yöntem F1a ile birebir aynı: `mktemp -d`, sahte `HOME`, sahte `RABADON_DIR`,
sahte `npm_config_prefix`, yerel klon, `RABADON_NOTIFY=0`.
Kum havuzu: `/tmp/f1c-adim.Vnkd5E` (doğrulama) ve `/tmp/f1c-timed.CL9A28` (süre).

## ESKİ SAYI SİLİNMEDİ

| ne zaman | sayı | ne sayıldı |
|---|---|---|
| **F1a, 26.08 (önce)** | **5 birleşik satır / 7 ayrık komut**, ~35,8 s | README kurulum bloğunun izlediği yol. `rabadon on` o blokta YOKTU, yani ölçülen yol **hiçbir şeyi reddetmeyen** bir guard'a varıyordu. |
| **F1c, 26.08 (sonra)** | **3 birleşik satır / 7 ayrık komut**, **34,1 s**, **0 soru** | Kurulumdan **fiilen reddeden** guard'a (`exit 2`) dürüst asgari yol. |

İki sayı aynı şeyi saymıyor ve bu kasıtlıdır: F1a'nın 5'i belgedeki satırları
saydı, F1c'nin 3'ü **çalışır bir frene varan asgari yolu** sayıyor. Fark bir
gevşetme değil: F1a'nın vardığı nokta WATCH'tı, F1c'ninki `exit 2`.

## ÖLÇÜLEN ÜÇ SATIR, BİREBİR

    1  git clone https://github.com/nosey-dewdrop/rabadon && cd rabadon \
         && npm install && npm link
    2  cd your-project && rabadon init
    3  rabadon on

Ayrık kabuk komutu olarak sayarsan 7: `git clone`, `cd`, `npm install`,
`npm link`, `cd`, `rabadon init`, `rabadon on`.

Süreler (`/tmp/f1c-timed.CL9A28`, `python3 time.time()` ile satır satır):

    line1 clone+install+link : 33.7 s   ← 19 C++ ikilisinin derlenmesi
    line2 cd proj + init     :  0.4 s
    line3 rabadon on         :  0.0 s
    TOTAL                    : 34.1 s

**Soru sayısı: 0.** Üç satırın hiçbiri girdi beklemedi; hepsi etkileşimsiz
koştu (aksi halde ölçüm zaman aşımına uğrardı, uğramadı).

## KANIT: yolun sonunda gerçekten çalışan bir fren var

Aynı hook olayı, `init` sonrası ve `on` sonrası, gerçek `rabadon-gate`
ikilisine verildi (`init`'in `.claude/settings.json`'a yazdığı komutun
tam yolu). VERBATIM:

    ########## A) after init only (WATCH) ##########
    rabadon (watch) would have blocked this.
    Rule: no-force-push-main — force-pushing a shared branch destroys history
    command matched deny rule: git push --force origin main
    Nothing was stopped. `rabadon on` makes this a real refusal.
    EXIT=0

    ########## B) after rabadon on ##########
    rabadon BLOCKED this action.
    Rule: no-force-push-main — force-pushing a shared branch destroys history
    command matched deny rule: git push --force origin main
    Adjust the approach instead of retrying the same action.
    (user override: add "no-force-push-main" to disabled[] in .rabadon/guard.json, or `rabadon off` to pause supervision)
    EXIT=2

Bunu basan komut:

    G="$T/rabadon/native/rabadon-gate"
    EV='{"session_id":"f1c","cwd":"<proj>","hook_event_name":"PreToolUse",
         "tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
    rabadon off; printf "$EV" | "$G"; echo "EXIT=$?"
    rabadon on ; printf "$EV" | "$G"; echo "EXIT=$?"

Yani F1a'nın **KIRMIZI-A'sı kapandı**: belgeyi harfiyen izleyen kullanıcı
artık `exit 2` veren bir guard kuruyor, ve `on` satırı belgede kurulum
bloğunun içinde (kart 1, `native/install_docs_test.sh` ile kilitli).

## 3 → 2 FARKI: kovalanmadı, sebebi ölçülü

Kalan tek satır fazlalığının sebebi **paketin yayımlanmamış olması**:
kaynaktan kurulum `git clone` + `npm install` + `npm link` gerektiriyor.
Yayımlandığında yol `npm i -g rabadon` · `cd proj && rabadon init && rabadon on`
= 2 satır olur. **Bu F1c'nin işi değildir** — SAPMA-KARARLARI §A.4'te
**F1n-S1** kabul maddesi olarak yazılıdır ve orada ölçülecektir.
Üçüncü satırı `init`'e katlamak YASAKTIR (§7/F7: watch varsayılan kalır).

## KART DIŞI FARK EDİLEN (dokunulmadı)

1. `npm install` süresinin **tamamı derleme** (33,7 s'nin neredeyse hepsi
   19 ikilinin `clang++` ile derlenmesi). Yayımlanan pakette önceden
   derlenmiş ikili varsa bu süre düşer; DOĞRULANMADI, ölçülmedi.
2. `docs/quickstart.md`'nin `## 1. Install` bloğu bugün `npm i -g rabadon`
   diyor — README ise "npm'de değil, kaynaktan kur" diyor. **İki belge
   çelişiyor** ve quickstart'ın ilk adımı bugün çalışmayan bir komut.
   Kart dışı (işçi 1 de bunu yazdı), dokunulmadı.
3. Kum havuzunda `rabadon init` `.cursor/hooks.json` yazmadı — proje
   `.cursor` dizini olmayan bir ağaçtı; Cursor yolu kart 5'in testinde
   ayrıca kanıtlandı.
4. `rabadon drill` (kanıt adımı) bu ölçüme DAHİL DEĞİL, F1a'da da değildi.
