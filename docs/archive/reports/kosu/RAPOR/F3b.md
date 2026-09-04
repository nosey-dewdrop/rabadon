# F3b — kart
**TAHMİN (§3.12, iş başlamadan, `09ff870`): 4 kart, iki katı 8. Kesilen: 3 — AŞILMADI.** Tahminde 3 "canlı ajanda şüpheli", 4 "ŞÜPHELİ" yazılıydı.

## D7 — **KAPANDI** (BLOKLAYAN, her şeyden önce)
İlan edilen 1 değil **7** kural kaynağının include kapanışını eksik sayıyordu: `rabadon-net`←`testout/pathres/cmdtext`, `rabadon-run`←`baseline/gitcfg` (**transitif**, `rules.h` üzerinden), `rabadon-gate`+`rabadon-gated`←`testout.h`.
Kilit `native/make_deps_test.sh` (YENİ, `make test`'te), iki kol: metinsel kapanış + **ampirik** (her başlık ileri mtime'a itilir, `make -q` ona bağlı her ikiliyi out-of-date demek zorunda — **111 (ikili,başlık) çifti / 24 başlık**).
Ölçüt ÖNCE ayrı commit (`6ee07cf` **5 ok/2 FAIL**), onarım SONRA (`eff4541` **7 ok/0 FAIL**). **Mutasyon kanıtı süidin İÇİNDE** (arm F: önkoşulu sökülmüş ağaçta `make` gerçekten "up to date" diyor). **BOŞ YEŞİL** `F3b-oncesi`'nde, `/tmp` DIŞINDA worktree: **5/2 KIRMIZI**.
Semptom: `touch pathres.h && make all` → `rabadon-net` mtime artık DEĞİŞİYOR. **Kendi kapımda kusur buldum ve düzelttim** (`409e58f`): `touch`=ŞİMDİ derlemeyle aynı tick'e düşüp `gate_bench`'i YANLIŞ kırmızı yapıyordu — sebep saatti, build değil.

## F3-S1 — ONARILDI, TAVANIN ALTINA İNMEDİ
Kök sebep (kaynak-içi profil): `rb_day_str_at`'in önbelleği **iki kez sorulan bir sürece** yarar; sevk edilen gate **olay başına bir süreçtir**, yani soğuk `gmtime_r` timezone yüklemesini HER olayda ödüyordu — **582 µs**. Onarım: UTC gününü tamsayı takvimiyle (Hinnant days-to-civil).
Ölçüt ÖNCE (`85a1fc9`: `COLD_FIRST_US` **582 µs KIRMIZI**, agreement damgası 4808→**64808**), onarım SONRA (`3fda255`): **16 µs**; `gmtime_r+strftime`'a karşı 64808 damgada **0 uyuşmazlık**.
**SAYILAR** (`2b-uctan-uca.sh`, N=200, atfedilebilir): arka arkaya **1641,2 → 1287,1 µs**. Gürültü büyük olduğu için **eşli A/B, 10 tekrar**: **ortalama −321,1 µs, medyan −316,0, 9/10 negatif**, HEAD medyanı **1330,5 µs**.
**TAVAN 1000,0 µs OYNATILMADI, `accept.sh`'e DOKUNULMADI. KALAN AÇIK ~330 µs — "yaklaştı" değil, sayı budur.** Süreç-içi `2b`: **1218,7 µs** (F3 hakemi 1237,5), yükselmedi. **NEGATİF SONUÇ:** `strip -x` eşli 8 tekrarda ölçüldü, **etkisi YOK**, sevk EDİLMEDİ.

## (b) "ajan okudu" — **ÖLÇÜLEMEZ, ve sebebi bir ürün kusuru**
`b-katmani.py` (salt-okunur, ikiliden bağımsız) defterin **7 INJECT**'ini yargıladı: **4'ünde `mseq`/`err` YOK**, 1'inin hamle halkası makinede yok, kalan **2'sinde `CAP=200` halkası enjeksiyonun ÜSTÜNDEN GEÇMİŞ**. **Yargılanabilir n = 0 — bu bir geçiş DEĞİLDİR.** (b)'yi yargılayan kanıt, kimse bakmadan önce halka tarafından yok ediliyor.
**SIRADAKİ KART:** INJECT satırı **önceki imzayı** taşısın + ilk sonuç veren hamlede `INJECT_ANSWER` yazılsın → (b) yalnız defterden, halkadan bağımsız cevaplanır. **Kodu YAZMADIM:** enjeksiyonu uçtan uca süren tek süit yok (`grep -ln INJECT native/*_test.sh` → 0), yani kapısız kod olurdu (§3.8/3).

## (c) negatif kontrol — **ÖLÇEMEDİM**
`ab_run.sh` iki kollu koşu ağ + `claude -p` + saatler ister, görev kümesi §3.8/2 ile mühürlü. **(c) olmadan F4 AÇILMAZ — hâlâ doğru. KOSU §F3'ün ürün kapsamı bu fazda da teslim EDİLMEDİ.**

## KAPI
`make test` **EXIT=0** · **3816 iddia + 633 kontrol + npm 64/0 = 4513 yeşil / 0 kırmızı** (taban 4505, **+8**, hepsi yeni iki kolun) · `accept.sh` **EXIT=1, 23/3**, kırmızı ad kümesi **`{2b,6e,7b}` BÜYÜMEDİ** · F1e-C üçlüsü nihai ikiliye karşı **42/0 · 38/0 · 13/0**, kâtip commit'i yok (`docs/` değişmedi).
Silinen/zayıflatılan/atlanan test YOK; eşik/tolerans/fikstür/ön-kayıt/`guard.json`/`ON-KAYIT`/`claims.tsv` HİÇ değişmedi; `rabadon off` kullanılmadı, CHALLENGE-3 deliği kullanılmadı. **Kapı beni 2 kez kesti, ikisi de DOĞRU red** (`no-rm-rf-outside`, `baseline-truncating-redirect`) — §3.8/4 gereği yaklaşımı değiştirdim, hiçbir blokajı aşmadım.
**NOT VERIFIED:** konteyner/x86 koşumu YOK; `make_deps_test.sh` yalnız macOS'ta koştu; eşli A/B makine gürültüsü altında ölçüldü (tek koşu 900–1700 µs saçıyor); (b)/(c) ürün kapsamı teslim EDİLMEDİ; `INJECT_ANSWER` önerisi ölçülmedi, yalnız gerekçelendirildi.
