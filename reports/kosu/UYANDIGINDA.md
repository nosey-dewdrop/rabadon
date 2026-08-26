# UYANDIĞINDA — koşu 5

On satırı geçmez (§13). Bekleyen her karar VARSAYILANIYLA yazılıdır;
cevap gelmezse varsayılan yürür ve tutanağa yazılır (§10 "kuyruk bekletmez").

## KAPANAN FAZLAR
- **F0** — GEÇTİ (`reports/kosu/KAPI.md`). ADIM satırı yok, belgedeki tek istisna.
- **F1a** — GEÇTİ (`KAPI.md`). ADIM 2 "kurar" **yarım** gerçek oldu:
  CI 4 hücrede yeşil (`gh run view 32924786346`), disclosure kapısı gevşetilmeden
  kapandı (41 karar bekleyen ad → 0, allowlist'e tek isim eklenmeden), doctor dört
  sessiz kurulum ölümünü adıyla yakalıyor, yüzey tavanı ilk kez kırmızı düşebiliyor,
  test 3502 → 3526 (düşmedi). **Ama "iki komut" iddiası ölçümde yanlış çıktı: 5 satır /
  7 komut. Ve `rabadon on` hiçbir kurulum belgesinde yok — README'yi izleyen kullanıcı
  hiçbir şeyi reddetmeyen bir guard kuruyor.** Ayrıntı: `RAPOR/f1a-tutanak.md`.
- **F1c** — GEÇTİ, **İKİ bağımsız hakem** ayrı ayrı ve sayıları tutarak. ADIM 2 "kurar"
  artık TAM: 3 birleşik satır / 0 soru / 34,1 s ve yolun sonunda gerçek gate `exit 2`
  veriyor; `rabadon on` üç belgede kırmızı düşebilen bir testle kilitli; Cursor'ın
  çıkış yolu açıldı. Ayrıntı: `RAPOR/f1c-tutanak.md`, `KAPI.md`.

## BEKLEYEN KARARLAR
- **O1 · npm yayını (F1n).** `npm publish` + `v0.2.3` etiketi + `@rabadon` org'u +
  `NPM_TOKEN`. Geri alınamaz + sahiplik → uykuda koşmaz (§13). F1 ikiye bölündü;
  yayın dışı her şey F1a'da bu gece koşuyor, `npm view rabadon version` maddesi
  gevşetilmeden F1n'e taşındı. **VARSAYILAN: sen ONAY verene kadar yayın yok.**
  Yeni: "kurulum 2 satır" iddiası artık F1n'in kabul maddesi (F1n-S1) — kaynaktan
  dürüst asgari 3 satır, 2'ye ancak yayın indiriyor. Yani yayın gecikirse README
  kalıcı olarak 3 satır satar. **VARSAYILAN değişmedi: onaysız yayın yok.**
- **O2 · 41 proje adı kamuya çıkacak mı? — VARSAYILAN YÜRÜDÜ, iş bitti, karar hâlâ senin.**
  Hepsi SAKLANDI: artefaktlarda `(withheld)` olarak yeniden üretildiler, `make disclosure`
  artık **exit 0** ve CI iki platformda yeşil. `site/published-projects.txt`'e **tek isim
  eklenmedi**, dosya byte byte aynı. Bir ismi açmak istersen tek satırlık iştir; geri
  almak değildir, bu yüzden varsayılan saklamaktı. Tam liste hâlâ:
  `python3 site/allowlist.py --list`.

- **O3 · `bin/rabadon.mjs`'in dondurulması kalksın mı?** O dosya `rabadon on` derken
  gerçekte açmıyor, ama SENİN dondurduğun bir anti-path (`.rabadon/guard.json`
  `protectedPaths` → `anti-path-frozen`, gerekçe "CLAUDE.md / HANDOFF §9"), yani
  düzeltmek için dondurmayı çözmek gerekir ve o senin kararın (§10 sahiplik).
  **VARSAYILAN: DONMUŞ KALIR.** Delik onu editlemeden kapanıyor: F1d yetkili yüzeyi
  (`rabadon status|on|off`) doğru yapıyor ve sevk edilen hiçbir yolun `on`'u o dosyaya
  götürmediğini kırmızı düşebilen bir testle sabitliyor. Gerekmiyor, sorulmuş olsun diye burada.

## SAPMA SATIRLARI (gece)
- F1 → **F1a** (uykuda koşar) + **F1n** (seni bekler). Ölçü gevşemedi, sertleşti:
  yayımlanmamış paket temiz makinede kurulup çalıştığını CI'ın dört hücresinde
  kanıtlayacak. Ayrıntı: `reports/kosu/SAPMA-KARARLARI.md`.
- **Sıra değişti: F1a → F2 → F1b → F1n → F3.** Sebep ölçüm: F1b'nin dayandığı koşu 2
  logları ledger değil düzyazı transkript; gerçek ledger `~/.rabadon/spool/` (246.775
  satır, 104 oturum) ve içinde koşu 2'ye ait yalnız 20 sinyal var.
- **F1a · ölçülmüş ve rahatsız edici:** kurulum "iki komut" değil, **5 satır / 7 komut**.
  Ve `rabadon on` kurulum belgelerinde yok ama zorunlu — onsuz guard WATCH'ta, aynı hook
  olayı exit 0 "Nothing was stopped", `on` sonrası exit 2 "rabadon BLOCKED this action".
  Ayrıca `rabadon remove` Cursor'u sökmüyor (`removeCursorHooks` yok): Cursor
  kullanıcısının çıkış yolu yok, §4.9 ihlali. Üçü de kart açılmadan yazıldı, bütçe doldu.
- **Ölçülmüş ve rahatsız edici:** tüm korpusta `repeat` **0**, `oscillation` **0** kez
  ateşlemiş. Ürünün manşet dedektörlerinin gerçek veride hiç materyali yok. F2 bunu
  gizlemeyecek: `n=0` sinyal "ÖLÇÜLMEDİ" basar ve canlıya çıkmaz.
- **F1c kapandı (iki bağımsız hakem, GEÇTİ). Cevapçı araya YENİ bir faz koydu: F1d.**
  Sıra: F1c → **F1d** → F2 → F1b → F1n → F3. Sebep tek bir ölçüm:
  `.rabadon/off` dosyası dururken **sevk edilen** `rabadon on` ve `rabadon status`
  "ON — the arbiter acts" basıyor, aynı olay gerçek gate'te **EXIT=0 ve 0 BAYT**,
  ve aynı ikilinin `--statusline` ağzı aynı anda **"rabadon off"** diyor.
  Fren "bastım" diyor, disk boş — ve bunu kırmızıya düşürebilen tek bir test yok.
  Yerel, geri alınabilir, para yakmaz. F1d ayrıca `docs/quickstart.md` §1'in ölü
  `npm i -g rabadon` yolunu kapatıyor (kilit genişliyor, gevşemiyor).
- **Hot-path `2b` artık sahipsiz değil:** yedi ölçümün yedisi de tavanın üstünde
  (bugün **1184,7 µs**, tavan 1000, §1 "bir milisaniyenin altı"). Ölçüm + "sub-ms
  deme" yasağı **F2-S9**, onarım **F3-S1**. Kimse tavanı oynatmadı.
- **Korpus kaybı raporlanandan üç kat büyük:** canlı korpusta 933 yazılmış / 527
  duruyor = **406 hamle (%43,5) yok**. F2 kabul sayısını canlı ring'den değil
  dondurulmuş yedekten alacak (**F2-S8**) ve kaybı ekranda ilan edecek (**F2-S4**).
- **Test sayacı uzlaştırıldı (§10).** İki değil ÜÇ lehçe vardı ve yayımlanmış her
  sayı eksikti. TEK GEÇERLİ TABAN bugün: **4180 yeşil / 0 kırmızı**
  (native 3504 iddia + 612 kontrol, node 64). Eski sayılar silinmedi, emekli edildi.
