# F1e KART B — belge (işçi tutanağı)

YAPILAN. `native/docs_truth_test.sh` (YENİ, 525 satır) + `docs/claims.tsv` (YENİ, 15 kayıt) + `Makefile` `test:` bağı — commit `1525536`; alt-hücre çakışması düzeltmesi `9c3358d`; üç belgenin düzeltmesi `63e01f3`. Kabul ölçütü ile onu sağlayan içerik AYRI commit'te, bu sırada.
ÖLÇÜLEN (boş yeşil). `bash native/docs_truth_test.sh`, belgeler ESKİYKEN: **14 ok / 27 fail, exit 1** — verbatim `f1e-b-bosyesil.out`. İçinde kart (i)/(ii)/(iii)/(iv)'ün hepsi adıyla: tablo 3 satır, ikili 6 bildiriyor (küme eşitliği iki yönden de FAIL); `rm ~/.rabadon/silent` VERBATIM koşuldu ve aynı olay aynı ikilide **hâlâ exit 0 / 0 bayt**; üç belgede de işaretli blok yok, 15 sicil kaydının 15'i bağsız.
ÖLÇÜLEN (sonra). Aynı komut, belgeler düzeltilmişken: **40 ok / 0 fail, exit 0** — verbatim `f1e-b-sonra.out`.
ÖLÇÜLEN (kapı). `make all` exit 0. `bash native/install_docs_test.sh` → **38 ok / 0 fail** exit 0. `bash native/version_test.sh` → **13 passed / 0 failed** exit 0. `npm test` → **ℹ pass 64 / ℹ fail 0** exit 0. `make test` → SAYILAR AŞAĞIDA (ek A).
YÖNTEM. Belge ekrandan TÜRETİLDİ: altı susturucunun ADI, YERİ ve KAÇIŞ KOMUTU testin içine hiç yazılmadı — her biri gerçek `native/rabadon-gate` kurulup ekranın kendi `silenced by:` / `next:` satırından okunuyor, sonra tablo o kümeye karşı EŞİTLİK için tutuluyor. Tablonun satır sayısı BELGEDEN geliyor (satır eklemek test eklemektir). `machine-silent` hâli ürünün kendi kapısından (`rabadon-gate --silent`) kuruluyor; dosyaya `touch` ile kurulsaydı `rm <dosya>` çalışıyor görünürdü — kusur (i) tam olarak orada saklıydı.
KENDİ TESTİM KENDİMİ YAKALADI. İlk yeşil denemede `off-is-watch-not-silence` "silent" dedi. Elle yeniden ürettim: temiz projede `rabadon off` sonrası gate **exit 0 / 297 bayt** veriyor, yani iddia yanlış değil, ÖLÇÜM aleti bozuktu — sicil kontrolleri komut ikamesi içinde koşuyor, `CELLN` alt kabukta artıyor, bir sonraki prob aynı `$TMP/c<N>` dizinini devralıp önceki probun `.rabadon/off`'unu ölçüyordu. Hücre yolu `mktemp -d`'ye çevrildi (`9c3358d`), ve `f1e-b-bosyesil.out` DÜZELTİLMİŞ süitle yeniden üretildi (eski belgeleri `git stash` ile geri koyup) — yani rapordaki kırmızı, yeşili basan süitin ta kendisiyle ölçüldü.
SESSİZ SİLME YOK. `docs/commands.md`'nin üç yanlış cümlesi silinmedi: her biri OLDUĞU GİBİ alıntılandı, "2026-08-26'da `bash native/docs_truth_test.sh` ile ölçüldü, yanlış çıktı" gerekçesiyle işaretlendi ve ölçümün söylediğiyle değiştirildi. Aynısı `docs/faq.md` (adım 2) ve `docs/uninstall.md` (silence-without-uninstalling) için yapıldı; üçünün de eski `#the-three-silencers...` çapası güncellendi.
YAPILAMAYAN. Yok — kartın beş değişmezi de kodda ve koşuyor.
KART DIŞI FARK EDİLEN (DOKUNMADIM). `docs/commands.md:57` hâlâ "The mode is one native flag (`~/.rabadon/enabled`) the gate reads" diyor. `native/gate.cpp:281,293,2733` bunu **legacy** olarak okuyor; asıl anahtar `$RABADON_DIR/mode` (ve proje/env katmanları). Yani sevk edilen belge modun nerede durduğu konusunda hâlâ bir nesil geride. Bu kartın işaretli bloklarının dışında ve ölçüm gerektirir; kaydı buraya düşüyorum.

## ÖLÇMEDİĞİM
- **Temiz konteyner koşulmadı.** Süit yalnız POSIX shell + git kullanıyor (node/python3/jq/ağ yok, bilerek), ama bu bu makinede kanıtlandı, temiz konteynerde DEĞİL. `install_docs_test.sh`'in `git archive`'lı ağaçta BLOCKED bastığı biliniyor (F1d notu); `docs_truth_test.sh` de her hücrede `git init` yapıyor, ama `.git`siz ağaçta koşturmadım.
- `git worktree`/paralel koşumda `mktemp -d` çakışması olmadığını varsaydım, ölçmedim.
- Sicil grameri (`does NOT|will report|reports the|never|always|is not`) SABİT ve DAR: işaretli blokların DIŞINDAKİ hiçbir cümle taranmıyor, ve gramere uymayan bir davranış iddiası (ör. "shows the mode") işaretli blokta bile yakalanmıyor. Bilinçli kapsam, ama boşluk.
- Sicilin `expect` sütunu ölçümün 2026-08-26'daki cevabıdır; makine cümlenin DOĞRU olduğunu değil, ölçümün hâlâ aynı çıktığını ve hiçbir iddia satırının sicilden kaçmadığını kanıtlar. Cümleyi hâlâ bir insan okuyor.
- `docs/quickstart.md`, `README.md`, `site/` ve `SPEC.md` bu kartta hiç açılmadı; aynı yanlış komutun oralarda olup olmadığını **ölçmedim** (şef `grep`'i üç belgede yaptı, ben o üçünü düzelttim).
- `rabadon on`'un SILENT bastığını `project-off` hâlinde ölçtüm; diğer beş susturucu için `on` ekranını ölçmedim (`status_truth_test.sh` orayı ayrıca tutuyor).
- Kırmızı ad kümesi `{2b,6e,7b}` için `reports/R7/accept.sh` KOŞULMADI (kartın kapı listesinde yok); büyümediğini iddia etmiyorum, ölçmedim.

## EK A — kapı sayıları (hepsini kendim koşturdum)

| komut | sonuç |
|---|---|
| `make all` | exit **0** |
| `make test` | exit **0** |
| `grep -cE '^[[:space:]]*ok\b' <make test çıktısı>` | **3738** |
| `grep -oE 'PASS \([0-9]+ checks?\)' <dosya> \| grep -oE '[0-9]+' \| paste -sd+ - \| bc` | **626** |
| `npm test` | **64 pass / 0 fail**, exit 0 |
| TOPLAM | **4428 yeşil / 0 kırmızı** |
| `bash native/docs_truth_test.sh` | **40 ok / 0 fail**, exit 0 |
| `bash native/install_docs_test.sh` | **38 ok / 0 fail**, exit 0 |
| `bash native/version_test.sh` | **13 passed / 0 failed**, exit 0 |

TABAN. İlan edilen taban 3698 + 626 + 64 = **4388**. Ölçtüğüm 3738 + 626 + 64 = **4428**, fark **+40**. Bu +40 aritmetik olarak tam tamına `docs_truth_test.sh`'in 40 iddiasıdır — yani başka hiçbir süit iddia kaybetmedi, `PASS (N checks)` **626**'da ve npm **64**'te sabit kaldı, ikisi de oynamadı.
KIRMIZI AD KÜMESİ. `reports/R7/accept.sh` bu kartın kapı listesinde yok, KOŞMADIM — `{2b,6e,7b}`'nin büyümediğini iddia ETMİYORUM. `make test` çıktısındaki tek `FAIL` satırı (4257) ve tek `1 fail` dizgisi (3911) fikstür metnidir, gerçek başarısızlık değil; süit exit 0.
DOKUNULAN DOSYALAR (tamamı, `git diff --name-only HEAD~3`): `Makefile`, `docs/claims.tsv`, `docs/commands.md`, `docs/faq.md`, `docs/uninstall.md`, `native/docs_truth_test.sh`, `reports/kosu/RAPOR/f1e-b-{bosyesil,sonra}.out`. Yasak listesinin hiçbiri (`gate.cpp`, `rabadon-cli.sh`, `rabadon.mjs`, `status_truth_test.sh`, `heredoc_prose_test.sh`, `sandbox_test.sh`, `refenv/`) açılmadı; hiçbir mevcut test silinmedi/zayıflatılmadı; yeni CLI verb'ü yok; kod değiştirilmedi. Push EDİLMEDİ.
