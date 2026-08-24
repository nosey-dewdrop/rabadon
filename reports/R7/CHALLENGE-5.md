# CHALLENGE-5 — `olc_2b.sh`'ın HÜKMÜ ters: en düşük gözlem ALT sınır değil, ÜST sınırdır

durum: **AÇIK**, insan onayı bekliyor
açan: tur 21 yapan oturumu, 2026-08-24
dokunulan mühür: **hiçbiri** — bu bir öneri, `olc_2b.sh` DEĞİŞTİRİLMEDİ

## Neden şimdi çıktı

Örnekleyici tur 21'de ilk kez tam koştu (5/5 geçerli gözlem) ve kendi HÜKMÜNÜ
bastı: `2b KESIN KIRMIZI — en dusuk gozlem 1218.3 us >= 1000 us`. Hüküm
basıldığı an gerekçesi okundu, ve gerekçe kendi fizik argümanıyla çelişiyor.

## Kusur

`reports/R7/olc_2b.sh:15-26`. Betiğin dayandığı fizik önermesi DOĞRU:

    olculen(yuk L)  >=  gercek_temiz        (yuk yalniz EKLER, cikarmaz)

Betiğin bundan çıkardığı sonuç ise ters:

    "tekrarli olcumlerin EN DUSUGU, temiz-ortam degerinin en iyi ALT SINIR
     tahminidir"                                        (olc_2b.sh:18-19)

Önerme her gözlem için `gözlem ≥ temiz` diyorsa, gözlemlerin en küçüğü için de
`min(gözlem) ≥ temiz` der. Yani **min, temiz değerin ÜST sınırıdır**, alt sınırı
değil. Elimizdeki tek çıkarım şu:

    gercek_temiz  <=  1218.3 us

Bu, `< 1000 us`'yi **dışlamaz** — tam tersine onunla uyumludur.

### İki dal da ters

- `min >= 1000 -> KESIN KIRMIZI` (olc_2b.sh:22-23, 149-156). Yanlış.
  `min ≥ 1000`, temiz değer hakkında **hiçbir şey** söylemez; temiz değer
  700 µs de olabilir. Betiğin kendi cümlesi — "daha temiz bir olcum
  MATEMATIKSEL OLARAK daha dusuk olamaz" — önermenin tersidir: daha temiz bir
  ölçüm matematiksel olarak daha düşük olabilecek **tek** şeydir.
- `min < 1000 -> ACIK, yesil sayilmaz` (olc_2b.sh:24-26, 158-165). Bu dal
  gereğinden **fazla** temkinli. `temiz ≤ min < 1000` geçerli bir çıkarımdır;
  yani asıl kanıt gücü olan dal budur ve betik onu atıyor.

Kısacası betik, kanıt üreten dalı "yetersiz" sayıp, hiçbir şey kanıtlamayan
dalı "KESİN" ilan ediyor.

### Gözlemsel destek (bu turun 5 örneği)

| örnek | 1 dk yük | 15 dk yük | medyan (µs) |
|-------|----------|-----------|-------------|
| 1     | 8.90     | 10.83     | 3302.3      |
| 2     | 2.41     | 7.09      | 1846.2      |
| 3     | 5.12     | 5.52      | 3002.8      |
| 4     | 6.48     | 5.61      | 2112.6      |
| 5     | 3.67     | 4.36      | **1218.3**  |

Yük ile latans arasında pozitif ve güçlü bir ilişki var (Pearson r = +0,737
1 dk yük ile; +0,684 15 dk yük ile), eğim ≈ 250 µs / yük birimi. Doğrusal uyum
yük = 0'da **970 µs** (1 dk) ve **744 µs** (15 dk) kesişimi veriyor — ikisi de
1000 µs'nin ALTINDA.

**BU BİR KANIT DEĞİLDİR ve yeşil sayılamaz.** 5 noktalı bir doğrusal uyumun,
gözlenen en düşük yükün (2,41) çok dışına, sıfıra ekstrapolasyonudur; latansın
yükle doğrusal olduğu VARSAYIMINA dayanır ve o varsayım ölçülmedi. Tek işlevi,
yukarıdaki mantık hatasının pratikte de fark yarattığını göstermek: temiz
makine değeri gerçekten de tavanın altında olabilir.

## 2b'nin kabul durumu bundan ETKİLENMİYOR

Bu challenge 2b'yi yeşile çekmez ve çekmemelidir. `accept.sh`'ın ölçütü bu
makinede alınan MEDYAN'dır ve bu turda 1228,1 µs ölçüldü, tavan 1000 µs.
**2b KIRMIZI.** Beş örneğin beşi de tavanın üstünde. Değişen tek şey KIRMIZININ
ETİKETİ: "kesin, makine bahanesi bitti" değil, "bu makinede kırmızı, temiz
makinede ölçülmedi".

## Önerilen diff (insan onayı olmadan uygulanmaz)

`olc_2b.sh`'ın yorum bloğu ve iki HÜKÜM dalı, önermeyle tutarlı hâle gelir:

- `min` "alt sınır" değil **üst sınır** olarak adlandırılır.
- `min >= TAVAN` dalı: "KESIN KIRMIZI" yerine **"BU MAKİNEDE KIRMIZI, temiz
  ortamda ÖLÇÜLMEDİ"**. Çıkış kodu 1 kalır.
- `min < TAVAN` dalı: "temiz değerin tavanın altında olduğu KANITLANDI, ancak
  `accept.sh`'ın medyan ölçütü ayrıca sağlanmalıdır" — yeşile yine yazmaz,
  çünkü kabul ölçütü medyandır, minimum değil. Çıkış kodu 2 kalır.
- Ayrıca: örnekleyici gözlem başına yükü zaten kaydediyor; yük–latans eğimini
  raporun sonuna yazsın ki ekstrapolasyon tartışması veriyle yapılsın.

## Asıl soru operatöre

Bu makine 8 çekirdekli ve **hiçbir örnekte 1 dk yükü 2,41'in altına inmedi**.
2b'nin gerçek değeri bu worktree'de ölçülemiyor olabilir. Karar operatörün:
2b temiz bir ortamda (boş bir makine / container) mı ölçülecek, yoksa "bu
makinede kırmızı" etiketiyle mi kapanacak?

---

# EK — aynı betikteki İKİNCİ kusur: B1.9 artık-süreç kontrolü KIRMIZIYA DÖNEMİYOR

tur 21'de, ölçümler bittikten sonra bulundu.

## Kusur

`reports/R7/olc_2b.sh:67-69`:

    for p in pytest pip ctest rabadon-gated rabadon-gate; do
      printf '  %-16s %s\n' "$p" "$(pgrep -c -f "$p" 2>/dev/null || echo 0)"
    done

macOS'un BSD `pgrep`'inde **`-c` bayrağı YOKTUR.** Ölçüldü:

    $ pgrep -c -f "rabadon-gated"
    usage: pgrep [-Lfilnoqvx] ...
    rc=2

Komut her zaman kullanım hatası verir, `2>/dev/null` hatayı yutar, `|| echo 0`
devreye girer. Yani **bu kontrol, makinede kaç artık süreç olursa olsun her
zaman `0` basar.** Kırmızıya dönemeyen bir kontrol, kontrol değildir — bu
betiğin B1.9'u uyguladığı iddia edilen tek yeri budur.

## Kaçırdığı gerçek artık süreç (bu turda, beş ölçümün beşinde de)

    $ ps -o pid,lstart,etime,command -p 60547
      PID STARTED                    ELAPSED COMMAND
    60547 24 Agu 15:12:57 2026      06:23:08 /tmp/sprof/dmn/rabadon-gated-sprof

    $ pgrep -f "rabadon-gated"      # -c'siz, DOGRU kullanim
    60547

Önceki bir turun profilleme kalıntısı, **15:12'den beri ayakta**. Tur 21'in
beş ölçümünün TAMAMI bu süreç canlıyken alındı ve rapor beş kez
`rabadon-gated 0` yazdı. Sürecin ölçümü ne kadar kirlettiği **ÖLÇÜLMEDİ** —
büyük ihtimalle boşta bekleyen bir daemon, ama bunu bilmiyoruz, ve B1.9 tam
olarak "bilmiyoruz"u ortadan kaldırmak için var.

## Önerilen diff (insan onayı olmadan uygulanmaz)

`-c`'yi kaldır, sayımı taşınabilir biçimde yap:

    printf '  %-16s %s\n' "$p" "$(pgrep -f "$p" 2>/dev/null | grep -c . || echo 0)"

ve sıfırdan büyük bir sayı görüldüğünde ölçümü GEÇERSİZ say ya da en azından
rapora görünür bir UYARI satırı düşür — bugün sayı rapora yazılıyor ama hiçbir
şeyi tetiklemiyor.

## Süreç ÖLDÜRÜLMEDİ

Bu oturumun başlatmadığı bir süreçtir ve şu anda bu bulgunun KANITIDIR, o
yüzden dokunulmadı. Temizlemek isteyen için tek komut:

    kill 60547
