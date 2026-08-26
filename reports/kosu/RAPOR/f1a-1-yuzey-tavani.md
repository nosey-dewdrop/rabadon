# f1a-1-yuzey-tavani — ana `--help` ürün verb tavanı

YAPILAN
- `native/cli_test.sh` +100 satır, yeni bölüm "1c. the main screen has a CEILING, and it can go red" (1b'den sonra, 2'den önce). Mevcut hiçbir case silinmedi/zayıflatılmadı/yeniden adlandırılmadı; tek dosya değişti (`git diff --stat native/` → cli_test.sh | 100 +++, 1 file changed).
- Denetim `--help` çıktısını AYRIŞTIRIR (bölüm 1'in yakaladığı `$HOME_DIR/help.txt`): `examples` başlığına kadar TAM iki boşlukla girintili satırlar = giriş; ilk çift boşluğa kadarki sol sütun = imza; `on | off` tek giriş, etiketi `on|off`. 4 assertion: (a) ürün verb sayısı == 5, (b) ad kümesi == {init, on|off, usage, repair, doctor}, (c) `version`+`dev` ayrı ve bu sırada, (d) toplam satır 7. Vacuity guard: ekran >200 bayt olmalı. Kırmızı mesajları §4.8 formatında (BLOCKED / WHY / NEXT) ve fazlalık verb ADINI basıyor.

ÖLÇÜLEN
- `./native/cli_test.sh` → EXIT=0, `cli: 315 passed, 0 failed` (eski 310 ok / 0 fail; +5 ok = 1c'nin 5 assertion'ı: vacuity guard + sayı + ad kümesi + version/dev + toplam).
- Boş yeşil: help ekranına `  scan                a sixth verb on purpose` eklendi → `./native/cli_test.sh` EXIT=1, `cli: 312 passed, 3 failed`, kırmızı satır "lists 6 product commands, not 5 — [init on|off usage repair doctor scan]". Tam çıktı: `reports/kosu/RAPOR/f1a-1-bosyesil.out`.
- Geri alındı: `git diff --stat native/rabadon-cli.sh` BOŞ, `git status --porcelain native/rabadon-cli.sh` BOŞ.

YAPILAMAYAN
- Yok. Commit atılmadı (kart yasağı: git yazma komutu yok, şef commit'ler).

KART DIŞI FARK EDİLEN (dokunulmadı)
- `dev` ekranında (rabadon-cli.sh:152-191) 30 verb var ve orada da tavan yok — bir verb dev ekranından SİLİNSE bölüm 1b onu yakalar (binary'si varsa), ama dev ekranına ürün-dışı yeni satır eklenmesi hâlâ testsiz.
- `bin/rabadon.mjs` içindeki elle yazılmış verb listesi (cli_test.sh:47-48'de anlatılıyor) hâlâ dispatcher'la ayrık; hiçbir test iki listeyi karşılaştırmıyor.
- Ana help metnindeki "Five commands is the whole product" cümlesi ile ayrıştırılan sayı arasında bağ yok: sayı 6 olsa cümle yine "Five" der. 1c sayıyı kırmızıya düşürüyor ama cümleyi denetlemiyor.
