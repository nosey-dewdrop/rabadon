# DEVİR — rabadon, 2 Ağustos gecesi

Bu dosya yeni oturuma yapıştırılır. Her sayı ölçüldü, hiçbiri tahmin değil.
Ölçülemeyen iki iddia aşağıda ayrıca işaretli.

---

## DURUM, ÖLÇÜLDÜ

Main `cd0f2f3`. `make` sıfır hata, `./native/precision_test.sh` PASS,
`./native/harness_lock_test.sh` 6 pass 0 fail. Koşan iş yok, ağaç temiz,
`hakem-kilit` dalı main'e merge edildi ve içindekiler artık main'de.

```
cases: 34   correct block: 11   wrong block: 0   missed: 0   correct allow: 23
precision 100.0%   recall 100.0%
```

Site dört sayfa ve kaynağı depoda, `site/` altında. `site/build.py` üç sayfayı
her koşumda yeniden üretiyor: catches defterden, patch-notes `git log`'dan,
pull-requests `gh`'dan. Deploy `cd site && vercel deploy --prod --yes`, sonra
`vercel alias set <deployment> rabadon.noseydewdrop.com`. Alias ELLE atılmazsa
özel alan adı eski sürümü servis etmeye devam eder, bu bu gece iki kez oldu.

---

## İKİ İDDİA DÜZELTİLECEK, ÖNCE BU

**1. 42.0µs üretilemiyor.** Bu sayı eski DEVIR'de yazılıydı ama onu ölçen bir
bench bu depoda yok. Koşan tek gerçek ölçüm `native/bench.py` ve o uçtan uca
hook gecikmesini ölçüyor, `judge_command`'ın içini değil:

```
parity: native == node on 2 verdicts (allow=0, deny=2)
native allow  median=   3.35ms  p95=   6.12ms  (n=40)
node   allow  median= 108.35ms  p95= 153.23ms  (n=40)
```

Yapılacak iki şeyden biri. Ya `judge_command` için gerçek bir mikro bench yazılır
ve sayı ölçülür, ya da site ve LinkedIn metninde 42.0µs yerine üretilebilen
karşılaştırma yazılır: aynı kararları veren JS kapısı 108ms, C++ kapısı 3.35ms,
32 kat. İkincisi daha güvenli ve daha güçlü, çünkü tek sayı değil kıyas.

**2. Sitede 207 yazıyor, defterde 219 var.** İkisi de doğruydu, arada yeni kayıt
düştü. `site/build.py` catches sayfasını defterden üretiyor ve orası kendini
günceller, ama `site/index.html` içindeki manşet sayısı ELLE yazılı. Ya elle
güncellenecek ya build.py'den beslenecek. İkincisi doğrusu.

---

## AÇIK İŞLER, SIRAYLA

**1. Bulguları siteye mekanik bağla.** Bugün tamirler defterden otomatik geliyor
ama yabancı repoda bulunan kusurlar `reports/` altında kalıyor ve siteye
düşmüyor. `site/findings.jsonl` aç, her kusur bir satır olsun (repo, dosya, ne
bozuktu, bunu kanıtlayan komut, durumu), `site/build.py` onu catches sayfasında
render etsin. Bundan sonra bulunan her şey elle yazılmadan sitede görünsün.
Damla'nın emri: "bulduğu hataları ve repairleri de loglayacak oraya."

**2. Hakemdeki iki delik.** Korpus denetimi dokuz hile ailesi ölçtü, altısı artık
reddediliyor, ikisi hâlâ geçiyor: girdiye özel dallanma ve karşılaştırma ezme.
İkisi de sadece kaynağı değiştiriyor, hiçbir dosya hash'i göremez. Panzehir
yapısal değil DAVRANIŞSAL: süitin hiç kullanmadığı girdilerle koştur. Testin tam
girdisi için doğru cevap veren hile komşu girdide düşer, ve bunu dallanmayı
başka türlü yazarak atlatamazsın. Karşılaştırma ezmede de aynı yol, `a == b` ile
`!(a != b)` tutarlılığını görülmemiş değerlerle sına. AST okuma ancak bunun
önünde ucuz bir eleme olarak durur, yerine değil. Kanıt `reports/2026-08-01-hakem-korpusu/`.

**3. JUnit ve Go kilidi kanıtlanmadı.** `pom.xml`, `build.gradle`,
`settings.gradle`, `gradle.properties`, `junit-platform.properties` ve `go.work`
hash listesine girdi ve gerekçesi `native/repair.cpp` içinde yazılı, ama uçtan
uca koşulmadı. Bu makinede maven surefire'ı çevrimdışı çözemiyor ve go yok.
Kanıt için maven cache'i dolu ya da go kurulu bir ortam gerekiyor.

**4. npm yayını.** `package.json` v0.2.0 dört platform için önceden derlenmiş
ikili dağıtımına göre kurulu (`@rabadon/darwin-arm64`, `darwin-x64`,
`linux-x64`, `linux-arm64`), `release.yml` var ama gerçek bir tag ile hiç
koşmadı. Yayından ÖNCE kanıtlanacak şey: tag at, release.yml koşsun, tarball'ı
indir, derleyicisi olmayan temiz bir dizinde kur, `rabadon --version` çalışsın.
Bozuk bir ilk kurulum, bir günlük gecikmeden pahalıdır. npm org ve token
Damla'da.

**5. express katkısı, GÖNDERİLMEDİ.** Dal hazır: `~/damla_projects_2026/katki/express`,
dal adı `fix/res-send-arraybuffer-view-bytes`. `res.send()` bir ArrayBuffer
görünümünün baytlarını göndermiyor: `DataView` ile Content-Length 3 yerine 0,
`Uint16Array` ile 4 bayt yerine 2, etag kapalıyken 500 ve
`ERR_INVALID_ARG_TYPE`. Temel 1260 test geçiyordu, dal 1265, yeni kırmızı yok,
lint temiz. Aynı satırlara dokunan açık PR #7363 var, 6 Temmuz'da açılmış, 9
Temmuz'dan beri sıfır yorum, ve `git merge-tree` ile çakıştığı ölçüldü. Aynı
konuda #7381 duplicate diye kapatılmış. Tavsiye: rakip PR değil, #7363 altına
ölçümü koyan bir yorum, çünkü onların yaması ham ArrayBuffer'ı ele alıyor,
bizimki görünümleri. KARAR DAMLA'NIN, hiçbir ajan göndermez.

---

## KURALLAR, İHLAL EDİLMEZ

**Ajanlara dokunma.** Damla "ajan sal" demeden ajan açılmaz. Damla NET olarak
"ajanı öldür" demeden koşan hiçbir iş durdurulmaz, kesilmez, resume edilmez.
Gerekçe ne olursa olsun. 1 Ağustos gecesi 9 ajanın 8'i bitmiş bir koşu kendi
kararımla kesildi ve bu bir daha yapılmayacak.

Regresyon testi ÖNCE yazılır ve kırmızı olduğu çıktıyla gösterilir. Her
"bloklanmalı" testinin yanında "bloklanmamalı" ikizi olur. Yıkıcı komut testi
izole, remote'suz temp repoda, sahte git/rm ikilileriyle, HOME o kök altına
yönlendirilmiş ve içinde kanarya dosya var.

Dışarı hiçbir şey: publish yok, tag yok, PR yok, issue yok, fork yok,
force-push yok. Commit ve main'e normal push serbest.

Bir adım bir commit bir push. Mesaj ne kanıtladığını söyler, lowercase
İngilizce, co-author yok, `-F` ile dosyadan verilir. Mesaja deny kalıbına
benzeyen metin yazılmaz.

Ölçemediğine "ölçemedim" yazılır. Sayı uydurulmaz, yuvarlanmaz. Sitede duran
her sayının altında onu üreten komut olur.

`bin/rabadon.mjs` okunur, asla düzenlenmez. JS'e yeni kod yazılmaz.

İçerik çıkış koşulu: bir sayı, karar, teşhis ya da çürütme çıktığı AN
`~/damla_projects_2026/icerik/dewrites.md` dosyasına düşer. Yazmadan önce
dosyanın başındaki YASA okunur.
