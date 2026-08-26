# f1e-a — kod (KART A)

1. **C5 test önce (kırmızı).** `native/status_truth_test.sh` → +18 hücre (bölüm D:
   `RABADON_MODE{unset,silent}` × `<proj>/.rabadon/mode{none,watch,silent}` ×
   `<RABADON_DIR>/mode{watch,enforce,silent}`), +68 iddia. `next:` komutu EKRANDAN
   `sed` ile çekilir, yorumlanır (`unset RABADON_MODE` / `unset RABADON_OFF` /
   `rm <mutlak yol>` / `rabadon off`; tanımadığı komut = FAIL), verbatim koşulur,
   sonra gerçek gate aynı olayda yeniden ölçülür. Commit `52c283d`.
2. **C5 kod (yeşil).** `native/gate.cpp` `compute_state`: konuşan mode katmanları
   toplanır, `silent` diyenlerin BAŞTAN GELEN KESİNTİSİZ DİZİSİ `Muter` olarak
   kaydedilir (gölgede kalan `silent` listelenmez), `modeSilencer` bayrağı
   `read from:` satırının yalan söylemesini engeller. İkinci kopya yok: ekran,
   `--statusline` ve sıcak yol aynı struct'ı okur. Commit `e51e77a`.
   Ölçüm: `bash native/status_truth_test.sh` → `status truth: 162 ok / 0 fail`, exit 0.
   Boş-yeşil (§8.2): `reports/kosu/RAPOR/f1e-a-bosyesil.out` — faz öncesi ikilide
   (05ab1ac, ayrı worktree) **130 ok / 32 fail**; üç katmanın `silent` hücrelerinin
   hepsi kırmızı düştü. Worktree kaldırıldı.
3. **C6 fikstür önce (kırmızı).** `native/heredoc_prose_test.sh` (Makefile'a bağlı,
   yalnız git+shell, python3/jq yok) — ölçülen ret 5 hücrede yeniden üretildi:
   `reports/kosu/RAPOR/f1e-a-c6-once.out` (`FAILED`, exit 1). Commit `e64c1eb`.
4. **C6 kod (yeşil).** Kök sebep ÖLÇÜLDÜ: `rules.h:rule_refuses`/`rx_test_cmd`,
   `pattern_names_a_pipe` doğru olan kurallara EK yüzey olarak **ham satırı**
   veriyordu; `cmdtext.h` heredoc gövdesini zaten segment yüzeylerinden çıkarıyor,
   çıkarmadığı tek yüzey buydu. `rbtext::Parsed.line` (ön-işlenmiş satır: yorumlar
   ve heredoc gövdeleri yok, borular/ayraçlar yerinde) eklendi; rules.h artık onu
   veriyor. Kural silinmedi, eşik gevşetilmedi, `disabled[]`e dokunulmadı.
   Commit `6699efb`. Ölçüm: `bash native/heredoc_prose_test.sh` → `PASS (14 checks)`.
   (c) maddesi: gerçek `make test | tail -5` + `echo exit=$?` HÂLÂ BLOCK; heredoc
   VE gerçek ihlal aynı satırdaysa yine BLOCK. (d) maddesi: `no-gnu-timeout-on-macos`
   de `[;&|]` yazdığı için ham satırı alıyordu — `; timeout 5 ...` içeren düz yazı
   önce reddediliyordu, artık geçiyor (fikstürde ayrı hücre).
5. **Yan etki (kart dışı değil, benim yol açtığım).** `native/site_claims_test.sh`
   kırmızı düştü: README "~20k" diyordu, `native/` 23366 satır ölçtü (izin 21k–25k).
   README 37. satır `~23k` yapıldı, aynı commit'te (docs move with behavior).
6. **KAPI.** `make all` exit 0; `make test` exit 0. Sayaç
   (`/tmp/f1e-maketest3.out`, `/tmp/f1e-npm2.out`):
   native iddia **3698** + PASS **626** + npm **64** = **4388 yeşil / 0 kırmızı**
   (taban 4292; düşüş yok, kırmızı ad kümesi büyümedi).

## YAPILAMAYAN
- Yok. (Başlık yorumu `red-suite-test-write` tarafından iki kez reddedildi;
  suite yeşile döndükten sonra ayrı commit `5eaec6d` ile yazıldı.
  `rabadon wrong` HİÇ KOŞULMADI, `disabled[]`e dokunulmadı.)

## KART DIŞI FARK EDİLEN (DOKUNULMADI)
- **`red-suite-test-write` bayat kırmızı okuyor.** Kural `sess.lastTestFail >
  sess.lastTestPass` bakıyor, ve `lastTestPass` yalnız çıktısı GÖRÜNEN bir test
  komutundan güncelleniyor. `make test > dosya 2>&1` (gate.cpp:3736'nın kendi
  anlattığı vaka) yeşil kapatıyor ama işareti temizlemiyor, dolayısıyla suite
  gerçekte yeşilken test dosyası yazımı reddedilmeye devam ediyor. Ölçüldü:
  162 ok / 0 fail'den sonra iki Write reddedildi; `npm test`'i görünür koşunca
  serbest kaldı. Bu bir WRONG_REFUSAL ailesidir, F1e C6'nın kardeşi.
- `native/cmdtext_test.sh:178` olay JSON'unu `python3` ile kuruyor — "temiz
  konteyner" barı (yalnız git+shell) o dosyada tutulmuyor.
- `native/regression_demo.sh` çıktısında `FAIL testsuite [node --test]` satırı
  kasıtlı demo metnidir; `grep -cE '^[[:space:]]*FAIL'` sayacını kirletiyor
  (bu koşuda 2 eşleşmenin biri o, diğeri site_claims'in şimdi düzeltilen reddi).
- `~/.rabadon/wrong-red-base` dosyası duruyor — daha önceki bir override izi.
