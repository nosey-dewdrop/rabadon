# DEVİR — rabadon, 3 Ağustos

Bu dosya yeni oturuma yapıştırılır. Bir önceki devir `DEVIR-2026-08-02.md`'de duruyor, silinmedi.
Gecenin tam raporu: `~/damla_projects_2026/reports/2026-08-03-saha-kosusu.txt`.

---

## OTURUM TİPİ: YAPIM. Saha değil.

Dün gece beş yabancı depoda saha koşuldu ve kusurlar bilerek düzeltilmedi.
Bu oturum onların en ağırını kapatır. Yeni depoya girilmez, yeni ajan salınmaz
(Damla "ajan sal" demedikçe).

---

## TEK İŞ

**"Hakem kandırılamaz, sahte fix reddedilir" cümlesinin yabancı depoda dayanağı yok.
Bu oturum o dayanağı kurar.**

Neden bu, neden başka bir şey değil. Motor sağlam ve sayı bunu söylüyor: beş depoda
88 belgelenmiş sıradan komutun 88'i doğru geçti, yanlış blok 0. Kırılan yer motor
değil, motora *neyi koruyacağını* söyleyen katman. Ve o katman kırık olduğu için
ürünün sattığı cümle şu anda kendi repolarının dışında yanlış.

---

## ADIM 1 — Keşif dosyanın dilinden değil, yerinden karar verecek

`native/truth.cpp:156-167` bir uzantı beyaz listesi tutuyor (js/ts/py/c/cpp/h/go/rs/
swift/java). Liste dışı her dosya `continue` ile düşüyor. `tests/` yol kuralı 11 satır
aşağıda, guard'ın kendi `testPaths` kuralı 20 satır aşağıda. **İkisine de hiç ulaşılmıyor.**

ÖLÇÜLEN BUGÜNKÜ HÂL (kırmızı testin beklediği sayılar bunlar):
```
redis   rabadon 255 dosya kilitledi, .tcl sayısı 0.  Diskte 229 .tcl (211'i unit/
        integration/cluster/sentinel altında).  discoveryCapped: []  ← uyarı yok
rails   rabadon 20 dosya kilitledi.  Diskte 1290 *_test.rb.  Oran %1.55.
        O 20'nin içinde gzip fixture'ı, dummy app manifest'i, rollup config var;
        ancak 7'si gerçek test.
```
REGRESYON KORUMASI — bu ikisi BOZULMAYACAK, ikisi de bugün doğru:
```
terraform  668 / 668 kilitli, discoveryCapped boş, hiçbir sınır ısırmadı
airflow    4096 / 4103 kilitli, discoveryCapped ['depth','limit'] diye DÜRÜST bastı
```

## ADIM 2 — Push kapısı zaman damgası değil ağaç soracak

`native/gate.cpp:1777` koşulu: `lastCodeEdit > lastTestPass`. Bu bir zaman damgası
sorusu, doğruluk sorusu değil. Sıfır test koşan tek komut damgayı tazeliyor ve kapı
kendini kapatıyor.

UÇTAN UCA ÖLÇÜLDÜ, kırmızı test bunları kullanacak:
```
terraform  go test -run TestNothingMatchesThis ./...   gerçek çıktı "ok ... [no tests
           to run]", exit 0  →  lastTestPass tazelendi  →  git push rc=0 İZİN VERİLDİ
           (suit hâlâ kırmızı, suit hiç koşturulmadı)
discourse  bin/rspec spec/models --tag nonexistent_tag  →  aynı sonuç
her ikisi   tek satır "ok pkga (cached)" beslemek de aynı etkiyi yapıyor, çünkü uzun
           tool çıktıları kırpılıyor — burada hile bile yok
```
İKİNCİ DELİK, aynı ailede: `gate.cpp:1351` PostToolUse yolu `lastTestPass`'i **yalnız
desene bakarak** set ediyor, çıkış koduna BAKMIYOR. Kapının kendi koştuğu yol
(`gate.cpp:1790`) `(code == 0) && rx_test(...)` diyor, yani orası sağlam. Delik karar
yolunda.

## ADIM 3 — `discoveryCapped` yalan söylemeyi bırakacak

Bugün "kırpılmadım" ile "her şeyi gördüm" aynı boş dizi. redis'te 229 dosya sessizce
düşerken `discoveryCapped: []` bastı. Sayaç dolu göründüğü için koruma varmış gibi
duruyor, ve bu sıfır basmaktan daha kötü.

---

## KAPANIŞ KANITI — beş depo diskte, klonlama maliyeti sıfır

ÖNEMLİ, ölçüldü: ağaçların hepsi gerçek değil. Dün gece ağ 2-5 KB/s'e düştüğü için
iki depo yeniden inşa edildi (isimler gerçek, içerik sıfır bayt).
```
depo         dosya    sıfır bayt   kullanılabilirlik
redis         2244        3        GERÇEK, derlenmiş, suit koştu — asıl kanıt burada
rails         4977       62        GERÇEK (tarball) — isim tabanlı keşif geçerli
airflow        288        0        gerçek ama SPARSE (13661 yolun 288'i)
terraform     5438     5167        İSKELET — yalnız isim tabanlı ölçüm
discourse    24023    23987        İSKELET — yalnız isim tabanlı ölçüm
```
Yani: içerik gerektiren her kanıt **redis** üstünde koşar (gerçek yeşil ve gerçek
kırmızı koşu dün üretildi). İsim tabanlı keşif kanıtı beşinde de koşar.

Oturumun çıktısı: aynı probe matrisleri yeniden koşulup **beş gerçek açık kaynak
deposu üstünde önce/sonra tablosu**. Önce sayıları yukarıda ve raporda hazır.

---

## KURALLAR — İHLAL EDİLMEZ

Regresyon testi ÖNCE yazılır ve kırmızı olduğu çıktıyla gösterilir. Her "bloklanmalı"
testinin yanında "bloklanmamalı" ikizi olur.

`git add -A` YASAK. Commit öncesi `ps ax | grep claude`; başka oturum varsa sadece
kendi yollarını tek tek stage'le. Dün gece 6 oturum paralel koştu ve state dosyası
çakıştı.

**SIK COMMIT AT, BİRİKTİRME.** Bir adım bir commit değil, bir *hamle* bir commit.
Kırmızı test yazıldı → commit. Test yeşile döndü → commit. Alt adım kapandı → commit.
Ölçüm çıktı → commit. Üç saat çalışıp tek commit atmak yasak; Damla ilerlemeyi
git geçmişinden okuyor ve boş geçmiş "hiçbir şey olmadı" demek. Mesaj lowercase
İngilizce, ne kanıtladığını söyler, co-author yok, `-F` ile dosyadan verilir.
Her commit'ten sonra `git push` — **rabadon deposunun uzak sunucusu var**, oraya
push edilir. Ev deposunun (`~`) uzak sunucusu YOK (`git remote -v` boş), oradaki
kayıt commit'te durur ve bu normaldir.

Dışarı hiçbir şey: publish yok, tag yok, PR yok, fork yok, force-push yok.

`bin/rabadon.mjs` okunur, asla düzenlenmez. JS'e yeni kod yazılmaz.

Ölçemediğine "ölçemedim" yazılır. Sayı uydurulmaz.

İçerik çıkış koşulu: bir sayı, karar, teşhis ya da çürütme çıktığı AN
`~/damla_projects_2026/icerik/dewrites.md` dosyasına düşer. Yazmadan önce dosyanın
başındaki YASA okunur.

---

## BU OTURUMDA YAPILMAYACAKLAR (kuyruk, sırayla — hiçbiri kayıp değil)

Hepsi ölçüldü, hepsi rapordadır, hiçbiri bu oturumun işi değil:

1. `codePaths`'in "kod" tanımı. rails'te üretim kodunun %6'sı (93/1558) ve 14 yayınlanmış
   migration dışarıda, çünkü kural `lib/` diyor ve üç bileşen `app/` kullanıyor.
   discourse'ta 1728 dosyalık `db/` hiç tanınmıyor, yani migration düzenlemek "kod
   düzenlemesi" bile sayılmıyor.
2. `protectedPaths` yalnız Edit/Write araçlarını görüyor. Aynı dosya `sed -i`,
   `truncate -s 0`, `echo >`, `rm` ile serbest. Beş deponun beşinde de.
3. `^` çapalı yol kuralları mutlak yolla eşleşmiyor. airflow'da 5 kuralın 2'si üretimde
   ölü, `lint` "valid" dedi.
4. Yeni kaçak ailesi: `make -C`, `make --directory=`, `env -C`,
   `git --git-dir=/--work-tree=`. `git -C` çözülüyor, bunlar çözülmüyor.
5. `baseline.h:199` `shared_branch()` dört ada gömülü (main/master/trunk/develop).
   redis'in ana dalı `unstable`, ve üç taban yasası birden kör.
6. ir-globe'un her commit'i bloklayan `no-emoji-in-commit` kuralı, ve `\uXXXX`
   kaçışlarının `std::regex` char altında sessizce "her şey"e derlenmesi.
7. Yabancı depoya yazma: `.rabadon/` davetsiz yazılıyor, ve `install.mjs:227` yabancı
   deponun **takipli** `.gitignore`'unu değiştiriyor.
8. `evidence[]` gerçeği anlatmıyor; guard yazan alt süreç `--allowedTools` kısıtı
   olmadan koşuyor, yani üretim tekrarlanabilir değil.
9. `lint` ikiz uyarısını basıp yine de exit 0 veriyor. 241 canlı kuralın 241'inde ikiz yok.
10. `promise-off-target`'ın "oturumda bir kez ateşler" sözü, durumu tek dosyada kilitsiz
    ve son 4 oturukla sınırlı tuttuğu için yedi oturum altında bozuluyor.
    `no-blind-inplace-source-rewrite`'ın `\.h` deseni `.html`'i de yakalıyor.
11. Siteye eş zamanlı loglama. **Bilerek en sonda.** Defter kesintisiz yazıyor
    (83657 satır, 10 gün, JSON olmayan 0 satır) ama site elle üç komutla yayınlanıyor
    ve hiçbir workflow'da yayın adımı yok. Boru döşenmeden önce sayının anlamı düzelmeli,
    yoksa yanlış sayıyı hızlandırmış oluruz.

---

## DAMLA'NIN MASASINDA (Claude yapamaz)

`charmbracelet/crush#3482` — teknik itiraz yok, tek engel CLA botu. PR'a şu yorum:
`I have read the Contributor License Agreement (CLA) and hereby sign the CLA.`

`aaif-goose/goose#10890` — kapandı, CI 13 yeşil 0 hata, inceleme cevaplandı. Beklemede.

rails'te bir katkı adayı var: `rake smoke` çıkış kodunu yutuyor (Rakefile L144-158
`system()` dönüş değerini atıyor, L13-21'deki `rake test` atmıyor). Kasıtlı olabilir,
rails özellik için önce forumda geri bildirim istiyor. PR değil, önce soru.

`~/.rabadon/enabled` dün gece kendiliğinden doğdu ve makineyi ENFORCE'a aldı; WATCH'a
geri alındı. Yazan kod bulunamadı, **sebep DOĞRULANMADI**.
