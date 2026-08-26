# UYANDIĞINDA — koşu 5

On satırı geçmez (§13). Bekleyen her karar VARSAYILANIYLA yazılıdır;
cevap gelmezse varsayılan yürür ve tutanağa yazılır (§10 "kuyruk bekletmez").

## KAPANAN FAZLAR
- **F0** — GEÇTİ (`reports/kosu/KAPI.md`). ADIM satırı yok, belgedeki tek istisna.
- **F1a** — şef bitirdi, hakem hükmü bekliyor. ADIM 2 "kurar" **yarım** gerçek oldu:
  CI 4 hücrede yeşil (`gh run view 32924786346`), disclosure kapısı gevşetilmeden
  kapandı (41 karar bekleyen ad → 0, allowlist'e tek isim eklenmeden), doctor dört
  sessiz kurulum ölümünü adıyla yakalıyor, yüzey tavanı ilk kez kırmızı düşebiliyor,
  test 3502 → 3526 (düşmedi). **Ama "iki komut" iddiası ölçümde yanlış çıktı: 5 satır /
  7 komut. Ve `rabadon on` hiçbir kurulum belgesinde yok — README'yi izleyen kullanıcı
  hiçbir şeyi reddetmeyen bir guard kuruyor.** Ayrıntı: `RAPOR/f1a-tutanak.md`.

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
