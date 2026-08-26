# UYANDIĞINDA — koşu 5

On satırı geçmez (§13). Bekleyen her karar VARSAYILANIYLA yazılıdır;
cevap gelmezse varsayılan yürür ve tutanağa yazılır (§10 "kuyruk bekletmez").

## KAPANAN FAZLAR
- **F0** — GEÇTİ (`reports/kosu/KAPI.md`). ADIM satırı yok, belgedeki tek istisna.

## BEKLEYEN KARARLAR
- **O1 · npm yayını (F1n).** `npm publish` + `v0.2.3` etiketi + `@rabadon` org'u +
  `NPM_TOKEN`. Geri alınamaz + sahiplik → uykuda koşmaz (§13). F1 ikiye bölündü;
  yayın dışı her şey F1a'da bu gece koşuyor, `npm view rabadon version` maddesi
  gevşetilmeden F1n'e taşındı. **VARSAYILAN: sen ONAY verene kadar yayın yok.**
- **O2 · 41 proje adı kamuya çıkacak mı?** `make disclosure` kırmızı ve CI'ı main'de
  kırmızı tutuyor (53 isim, 12 izinli, **41 karar bekliyor**: `youkiddingme`, `icerik`,
  `seviyorsevmiyor`, `ir-globe`, `parmakestra`, `damla_portfolio`, `psikoloji-kitabi`,
  … tam liste: `python3 site/allowlist.py --list`). Hangi ismin kamuya çıkacağı senin
  kararın (sahiplik + dış yayın). **VARSAYILAN: hepsi SAKLANIR** — artefaktlarda
  `(withheld)` olarak yeniden üretilir, kapı kapatılarak geçilir, `site/published-projects.txt`'e
  senin onayın olmadan tek isim eklenmez. Sonradan isim açmak tek satırlık iştir, geri
  almak değildir.

## SAPMA SATIRLARI (gece)
- F1 → **F1a** (uykuda koşar) + **F1n** (seni bekler). Ölçü gevşemedi, sertleşti:
  yayımlanmamış paket temiz makinede kurulup çalıştığını CI'ın dört hücresinde
  kanıtlayacak. Ayrıntı: `reports/kosu/SAPMA-KARARLARI.md`.
- **Sıra değişti: F1a → F2 → F1b → F1n → F3.** Sebep ölçüm: F1b'nin dayandığı koşu 2
  logları ledger değil düzyazı transkript; gerçek ledger `~/.rabadon/spool/` (246.775
  satır, 104 oturum) ve içinde koşu 2'ye ait yalnız 20 sinyal var.
- **Ölçülmüş ve rahatsız edici:** tüm korpusta `repeat` **0**, `oscillation` **0** kez
  ateşlemiş. Ürünün manşet dedektörlerinin gerçek veride hiç materyali yok. F2 bunu
  gizlemeyecek: `n=0` sinyal "ÖLÇÜLMEDİ" basar ve canlıya çıkmaz.
