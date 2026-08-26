İPTAL: koşu 3'ün interaktif tur protokolü. KOSU-RABADON-5.md ile değiştirildi, 2026-08-26. kosu3 worktree'si kaldırılmadan önce commit'lenmemiş halde bulundu, silinmesin diye buraya alındı.

# TUR — interaktif koşu, sürücü YOK

Arka planda dönen script yok. `tmux` yok, `kos.sh` yok, gizli döngü yok.
**Sürücü sensin.** Bir tur açarsın, ajan gözünün önünde çalışır, işini
bitirir, ÖLÜR. Sen `DEVIR.md`'yi okursun, sonraki turu açarsın.

Context neden şişmiyor: her tur AYRI üst-düzey oturum. Ölen oturum boşluğa
ölür, kimsenin context'ine bir şey dönmez. Devir diskte yaşar.

---

## Bir turun döngüsü — senin yapacağın üç şey

1. Yeni oturum aç (yeni pencere ya da `/clear`).
2. Aşağıdaki bloğu yapıştır, `<İŞ>` satırını doldur.
3. Bittiğinde `reports/kosu/DEVIR.md`'yi oku. Emin değilsen çıktıyı
   yönlendiriciye at. Sonra 1'e dön.

Ajan bitmeden ikinci tur açma. Ekranı izleyebiliyorsan iş görünürdür;
görünmeyen iş yoktur.

---

## YAPIŞTIRILACAK BLOK

    Bu turun tek işi: <İŞ — tek cümle, dosya yollarıyla>

    Oku, başka hiçbir şey açma:
      KOSU-RABADON-3.md · reports/kosu/DURUM.md · reports/kosu/DEVIR.md

    KURALLAR (ihlali işi geçersiz kılar):

    1. ALT-AJAN (Task) KULLANMA. Ağır iş — repo taraması, derleme, bench,
       log analizi — ayrı süreçte koşar:
           scripts/isci.sh <ad> <komut...>
       Ham çıktı reports/kosu/log/<ad>.log'a, 12 satırlık rapor
       reports/kosu/RAPOR/<ad>.md'ye düşer. Raporu OKUYABİLİRSİN; ham logu
       açma, yolunu yaz.

    2. Uzun sessiz komut kurma. 15 dakikadan uzun sürecek tek komutu
       parçala, ara çıktı bastır. Ne yaptığın ekranda görünsün.

    3. Kanıtsız cümle kurma. "Baktım / çalışıyor / düzelttim / kapandı"
       yasak. Her sayının yanında onu basan komut, her adımın yanında
       dosya yolu. Yol gösteremediğin cümleyi kurma.

    4. Kamuya giden hiçbir sayı elle yazılmaz; ledger'dan türetilir.
       Fixture bir testi yeşile çekebilir, fixture'dan çıkan rakam
       kamuya giden cümleye giremez.

    5. Emin değilsen ya da bir hüküm fazla iyi görünüyorsa:
           scripts/ajan.sh hakem "<hüküm>" <kanıt yolları...>
       Ağır bir yol tasarlanması gerekiyorsa:
           scripts/ajan.sh agir "<problem>" <kanıt yolları...>
       İkisini aynı anda çağırma. Dönen cevabı DEĞİŞTİRMEDEN aktar.

    6. Worktree dokunulmaz: checkout, branch -D, reset --hard, .git'e
       dokunmak YASAK. Geçmiş gerekiyorsa git log/show salt-okunur.

    BİTİRİRKEN, sırayla:
      a) reports/kosu/DEVIR.md'yi ŞU ŞABLONLA YENİDEN YAZ (≤40 satır):

         TUR: <n> · DURUM: KAPANDI | YARIM | KOŞMADI
         KABUL: <betik> → <yeşil>/<kırmızı>   (koşmadıysa: sebep)
         KIRMIZI ADLARI: <ad> · <ad>          (yalnız AD)
         ÖLÇÜLEN: <ad>=<değer> (<komut>)      (en fazla 5 satır)
         YAPILAMAYAN: <tek cümle sebep>
         COMMIT: <hash> · HAM: reports/kosu/log/<...>
         SONRAKİ TURA UYARI: <tek cümle>      (yoksa satır yazma)

      b) reports/kosu/DURUM.md'yi tazele (≤50 satır, kanıta göre).
      c) Kırmızı kaldıysa reports/<tur>/DENEMELER.md'ye bir blok ekle:
         DENENEN · SONUÇ · ELENEN HİPOTEZ · KALAN HİPOTEZLER.
      d) commit + push.
      e) Ekrana SADECE DEVIR.md'yi bas. Özet, anlatı, gerekçe yazma.
         Uzun anlatı tur raporuna gider, ekrana değil.

    Sonra BİT. Sonraki turu sen açmıyorsun.

---

## Turlar arası — senin işin

`DEVIR.md`'de **sayı** var mı? Yoksa sonraki turun tek işi o sayıyı
ürettirmektir. "Kabul betiği koştu" bir cümledir; kabul betiğinin SAYISI
kanıttır.

`DURUM: KOŞMADI` kırmızı değildir — kesintidir. Yürütülen hipotez elenmiş
sayılmaz, aynı iş tekrar açılır (gerekirse adımlara bölünerek).

Aynı kırmızı üçüncü kez geldiyse yaklaşımı değiştir: farklı teşhis yolu,
farklı araç, ya da işi ikiye böl. `DENEMELER.md` hangi hipotezlerin elendiğini
söyler; elenen bir yolu tekrar yazma.

---

## Sıra (DURUM.md ölçüttür, bu liste hatırlatma)

1. 2b — pgrep-f sonrası 3 gözlem temiz ortamda mı alındı, `grep -c
   "rabadon-gated 0" reports/R7/YUK-2B*.log` ile bak. Temizse "temiz
   makinede kırmızı, referans ortam CI" etiketiyle PARKED.
2. 5b ön-kayıt sapması — eksik iki görev (`joke2k__faker.8b401a7d`,
   `pylint-dev__astroid.b114f6b5`) koşulur ya da sebebi ON-KAYIT.md'ye
   yazılır. `7a` hükmü n=6 tamamlanmadan okunmaz.
3. 6e/7b — fixture yalnız aritmetiği doğrular. MIN_HISTORY=3 oynanmaz.
4. R8 — "yeşil main / 41 isim" kararı senin.
5. `rabadon ui --help` 2,5 gündür asılı duruyordu: bu R8 blokeridir,
   kullanıcının ilk teması `--help`'tir. `ps -o pid,stat,wchan -p <pid>`
   çıktısıyla reports/R8/'e satır.
