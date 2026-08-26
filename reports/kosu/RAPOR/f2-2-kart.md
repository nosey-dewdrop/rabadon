# f2-2-ekran — `rabadon usage --signals`

## YAPILAN (yol + hash)

- `943f73c` — `native/signals_screen_test.sh` (YENİ, 35 iddia) + `Makefile` `test:`
  hedefine eklendi. Kabul ölçütü ÖNCE, tek başına, ekran kodu olmadan.
- `28340e2` — `native/stats.cpp` içinde `--signals` bayrağı (`rbscreen::render`),
  `native/rabadon-cli.sh` `usage` satırına bayrak ipucu (YENİ VERB YOK),
  `Makefile` `native/rabadon-stats:` bağımlılıklarına `moves.h signals.h
  classify.h sha256.h`.

Yüzey: `rabadon usage --signals`. Dispatcher `rabadon-cli.sh:211` değişmedi,
argüman aynen `native/rabadon-stats`'a gidiyor. `cli_test.sh` `PRODUCT` listesine
DOKUNULMADI; ipucu satırı 3 boşlukla başlıyor, tavan sayacı onu komut satırı
saymıyor (315 passed, 0 failed, exit 0 — `reports/kosu/RAPOR/f2-2-cli.out`).

## BOŞ YEŞİL TURU (§8.2)

Süit, faz öncesi ikiliye koşuldu — `git show f03320f:native/stats.cpp` ayrı
derlendi (`/tmp/f22-old-stats`), `RABADON_STATS=/tmp/f22-old-stats
./native/signals_screen_test.sh`:

    16 passed, 19 failed
    EMPTYGREEN_EXIT=1

VERBATIM: `reports/kosu/RAPOR/f2-2-bosyesil.out`. Kırmızı düşen iddialar arasında
LOSS satırının yokluğu, `NOT MEASURED`+sebep yokluğu, sayının yanında oturum
yolu yokluğu, kapanış satırında tek komut yokluğu var. (DÜRÜSTLÜK NOTU: eski
ikili `--signals`'ı bilmediği için tek satırlık hata basıyor; 16 "ok"un bir kısmı
— ör. "ekranda 'saved' geçmiyor" — o tek satırda boş yere yeşil. Kırmızıya düşen
19 iddia asıl kilittir, bu 16 değil.)

## ÖLÇÜLEN (sayı + onu basan komut)

DONDURULMUŞ YEDEK (S8, salt okunur):
`COLUMNS=100 RABADON_DIR=$HOME/.rabadon-korpus-snapshot-20260826
./native/rabadon-cli.sh usage --signals`
→ `reports/kosu/RAPOR/f2-2-ekran-snapshot.out`

    34 oturum dosyası · 527 hamle diskte · 2026-08-22 21:22 → 2026-08-26 06:48
    LOSS 127 (başlık 654 saydı; tek taşan ring: 286fd71d… 327 sayıldı, 200 kaldı)
    repeat          NOT MEASURED (n=0)  en uzun aynı-hamle serisi 3, hiçbiri hatalı değil
    oscillation     NOT MEASURED (n=0)  tek dosyaya en çok 5 edit; 6 alternan gerekiyor
    root_migration  NOT MEASURED (n=0)  bir hata en fazla 1 farklı hamleye yayıldı
    scope_drift     n=17, 0'ı etiketli
    green_redefined NOT MEASURED (n=0)  yeşili belirleyen dosyaya toplam 1 edit

Kartın verdiği negatifi BAĞIMSIZ OLARAK YENİDEN ÖLÇTÜM ve doğrulandı: `repeat` 0,
`oscillation` 0. Kartta yazmayan iki negatif daha çıktı ve saklanmadı:
**`root_migration` da 0, `green_redefined` da 0.** Bu korpusta beş dedektörden
YALNIZCA BİRİ (`scope_drift`) ateşledi — ve `signals.h`'nin kendi yorumunda
"buradaki en zayıf kural" diye tarif edilen kural o. Ekranın özet cümlesi 4
NOT MEASURED'ı da, korpusun kısalığını da, 127 kaybı da açıkça yazıyor.

CANLI KORPUS (kabul sayısı DEĞİL, bilgi olarak):
`COLUMNS=100 ./native/rabadon-cli.sh usage --signals` →
`reports/kosu/RAPOR/f2-2-ekran.out`: 34 dosya / 527 diskte / **LOSS 1.417**
(başlık 1.944). Canlı ring bu oturum sırasında büyüdü; karttaki 406 rakamı
artık geçerli değil, kayıp %72,9'a çıktı. Tek sebep tek dosya: `286fd71d…`
1.617 saydı, 200 tuttu.

## KULLANICI EKRANA KAÇ ADIMDA VARIYOR (ölçülmüş)

`reports/kosu/RAPOR/f2-2-adim.out`:

    rabadon --help  ->  --signals geçen satır sayısı: 1   (derinlik 1, doküman kazısı yok)
    rabadon usage --signals                              (tek komut, 0 ayar, 0 dosya)
    TOPLAM YAZILAN KOMUT = 2   (bilen kullanıcı için 1)
    real 0,02 sn

Tek ekran: 37 satır (`wc -l < reports/kosu/RAPOR/f2-2-ekran.out`), ekran
görüntüsü alınabilir; süit 44 satır tavanını kırmızı düşürebiliyor.

## NASIL KAÇIYOR

`reports/kosu/RAPOR/f2-2-readonly.out`: ekran kendiliğinden `exit 0` ile biter —
pager yok, prompt yok, "devam?" yok. RABADON_DIR'ın dosya+mtime kümesi ekrandan
önce ve sonra AYNI hash: hiçbir şey yazmıyor, hiçbir şey silmiyor. Dedektörlerin
kendisi zaten sessiz ve `RABADON_SIGNALS=0` ile kapatılabiliyor (signals.h:63).

## SICAK YOL (S9)

`--signals`, spool açılmadan ÖNCE dönen erken-çıkışlı ayrı bir kol
(`stats.cpp`, `string spool = base + "/spool";` satırının hemen ardında).
Hook yolu bu ikiliye hiç uğramıyor: `grep -c 'rabadon-stats' native/gate.cpp` → 0.
Varsayılan `usage` ekranı değişmedi (süit iddiası: düz `usage` çıktısında
"NOT MEASURED" geçemez). Ekranın hiçbir yerinde "sub-ms" yok, prob sayısı tek
başına anılmıyor (her zaman NOT MEASURED sayısıyla birlikte).

## KAPI

    make all                                   BUILD=0
    ./native/rabadon-cli.sh usage --signals    EXIT=0   (f2-2-ekran.out, verbatim)
    ./native/signals_screen_test.sh            EXIT=0   35 passed, 0 failed
    ./native/cli_test.sh                       EXIT=0   315 passed, 0 failed  (tavan yeşil)
    make test                                  EXIT=0   (f2-2-maketest.out)
    grep -cE '^[[:space:]]*ok\b'               3783     (taban 3748 + bu kartın 35'i)
    PASS (N checks) toplamı                    633      (taban 633, değişmedi)
    npm test                                   pass 64 / fail 0
    bash reports/R7/accept.sh                  23 yeşil / 3 kırmızı, exit 1
      kırmızı AD kümesi: {2b, 6e, 7b} — f0 tabanıyla BİREBİR AYNI, yeni ad YOK.
      8a artık kırmızı değil (paralel işçi onardı, ben dokunmadım).
      8b `native/signals_test.sh 39/0` hâlâ PASS — o dosyaya dokunulmadı.

## YAPILAMAYAN / DOĞRULANMAYAN

- Temiz konteynerde koşulmadı. Süit hermetik (kendi mktemp HOME/RABADON_DIR,
  bayt bayt yazılan sentetik ring, ağ yok, python3/jq/node yok) ama Linux'ta
  DOĞRULANMADI. Fikstür yazıcısı `head -c /dev/zero`, `seq` ve bash dizisi
  kullanıyor; POSIX-sh değil, bash.
- Etiketleme yüzeyi YOK. "0 etiketli" ekranda dürüstçe yazıyor ama etiketi
  girecek bir komut yok; hiçbir sinyalin isabet oranı bilinmiyor.
- `scope_drift`'in 17 ateşlemesinin doğru mu yanlış mı olduğunu ÖLÇMEDİM. Ekran
  da iddia etmiyor — sadece "rabadon bunu yazdı" diyor (S7/(a)).
- `--signals` için `--json` yok; renderer bayrağıyla birleşince reddediyor
  (exit 2), sessizce yok saymıyor.

## KART DIŞI FARK EDİLEN (dokunmadım)

1. **`~/.rabadon/sessions` altında bir dosya tüm kaybı tek başına üretiyor.**
   `286fd71d-2e67-43-57b7234bb75e.moves.bin` canlıda 1.617 hamle saydı, 200
   tuttu. Kalan 33 ring toplam 0 kayıpta. CAP=200, uzun bir oturumun hamle
   kaydını %88 siliyor — R1'in "sekansı yazmak" vaadi tek uzun oturumda
   fiilen çalışmıyor. Kart dışı, yazıldı, dokunulmadı.
2. `native/rabadon-cli.sh:211` `stats|usage)` aynı ikiliye gidiyor; `rabadon dev
   stats --signals` de aynı ekranı basar. Bu ikinci bir yüzey DEĞİL (aynı verb),
   ama belgelenmedi.
3. `reports/R7/accept.sh` `2b` kırmızısı bir performans tavanı (medyan 1213,6 us
   > 1000 us ceiling) ve f0'dan beri kırmızı; bu kartla ilgisi yok.
