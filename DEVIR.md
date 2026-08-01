# DEVİR — rabadon, 1 Ağustos akşamı

Bu dosya yeni oturuma yapıştırılır. Her sayı ölçüldü, hiçbiri tahmin değil.

---

## İLK İŞ, SIRAYLA

**1. Koşan iki işi devam ettir.** İkisi de oturum limiti ya da context sınırıyla düşmüş olabilir; aynı komutla devam ederler, biten ajanlar cache'ten döner.

```
Workflow({scriptPath: "/Users/damummyphus/.claude/projects/-Users-damummyphus-damla-projects-2026-rabadon/8650e14b-2405-4db5-8602-0b7680fe654f/workflows/scripts/rabadon-hassasiyet-90-wf_31fc4113-cd4.js", resumeFromRunId: "wf_31fc4113-cd4"})

Workflow({scriptPath: "/Users/damummyphus/.claude/projects/-Users-damummyphus-damla-projects-2026-rabadon/8650e14b-2405-4db5-8602-0b7680fe654f/workflows/scripts/rabadon-yabanci-toprak-wf_9f3713b6-133.js", resumeFromRunId: "wf_9f3713b6-133"})
```

Birincisi rabadon deposuna YAZIYOR, ikincisi yazmıyor. Aynı anda rabadon deposuna yazan ikinci bir koşu başlatma.

**2. `/rabadon rapor`** ile durumu tek ekranda gör. Kapı hangi modda, defterin sayıları, hangi koşular canlı, repo nerede, ve Damla'nın kararını bekleyenler.

---

## TEK BLOKÖR

`./native/precision_test.sh`:

```
cases: 34   correct block: 11   wrong block: 9   missed: 0   correct allow: 14
precision 55.0%   recall 100.0%   floor 90%
```

Dokuz yanlış pozitifin dokuzu da aynı kuraldan (`no-rm-rf-outside-project`) ve dokuzu da `/tmp` altındaki kendi geçici dosyasını silmek (fixture'da F06 ile F14).

Sebep bir katman aşağıda. Komut ayrıştırma bugün tek yere alındı (`cmdtext.h`, 17 kaçak kapandı, `judge_command` 54.0us'ten 42.0us'e indi çünkü satır iki kez yerine bir kez ayrıştırılıyor). Ama "bu yol proje ağacının dışında mı" sorusunu hâlâ iki yer cevaplıyor: `baseline.h` sistem geçici alanını biliyor, guard.json'daki elle yazılmış regex bilmiyor.

**Kabul koşulu:** precision 90 tabanını geçecek, `missed` 0 kalacak. Kuralı kaldırarak, testi zayıflatarak ya da fixture'a dokunarak geçmek ihlal. `native/precision_fixture.jsonl` Damla'nın gerçek oturumlarından geldi, dokunulmaz.

---

## AÇIK İŞLER

**Veri sonradan programa dönüşüyor.** `echo 'git push --force origin main' | bash` geçiyor. Tırnaklı dize `echo`'nun argümanı olduğu için veri sayılıp etkisizleştiriliyor, ikinci parça tek başına yargılanınca sadece `bash` kelimesi ve zararsız, ama operandsız `bash` programını stdin'den okuyor. Kalıcı hâli daha kötü: `printf '%s' '...' > s.sh` sonra `bash s.sh`, çünkü tehlikeli metin artık hiçbir komut satırında yok. `native/stdin_program_test.sh` yarım duruyor, çöpe atma, tamamla.

**Temp muafiyetinin açtığı delik.** `rm -rf /tmp/*/../../Users/u/proj1` geçiyor: `check_segment` glob içeren hedefi ilk glob karakterinden kesip yalnızca önündeki dizini yargılıyor (`t2 = t2.substr(0, s)`, `s = rfind('/', g)`), incelenen dize `/tmp`, globdan sonrası hiç okunmuyor. Ayrıca `rm -rf /tmp/*`, `TMPDIR=/usr/local` düşmanca ayarlıyken `rm -rf /usr/local/lib`, ve `rm -rf $HOME/Documents` (içinde `$` geçen hedef atlanıyor).

**Kırmızı takım, üst üste iki tur boş dönene kadar.** Tur başına en az 25 yeni deneme, kapananları tekrar deneme.

**Hakem, yeşili satın almanın altı yolundan ikisini yakalıyor.** Kanıt `reports/2026-08-01-hakem-korpusu/`. Yakalananlar testi atlamak ve assert'i boşaltmak, ikisi de sha256 ile. Kaçanlar: kökteki `conftest.py`, jest konfigi ve setup dosyası, `package.json` test script'i (keşif desenine uymuyorlar, kilit listesine hiç girmiyorlar), koleksiyonu daraltmak (53 test 23'e iniyor, tek hash oynamıyor), girdiye özel dallanma, ve karşılaştırmayı ezme. Son ikisi bugün hiçbir sinyalle görünmüyor çünkü sadece kaynağı değiştiriyorlar ve hakem kaynak diff'ine hiç bakmıyor.

**Kendi kurallarını tamir etmesi.** Spec yazıldı ve pushlandı: `SPEC-SELF-REPAIR.md`. Damla'nın sözü: *"kendini geliştirmesi lazım, hatalarına göre hep aynı şeyle devam edemeyiz."* Sıra şu: bu iş precision 90 tabanını geçtikten SONRA başlar.

---

## BUGÜN ÖLÇÜLENLER

**Oynaklık teşhisi çürütüldü.** "O %50 oynaklık bizim koşturucumuz" dedim, yanlıştı. 130 pristine koşu: kanıtlanmış boş makinede 10'da 6 kırmızı, 8 çekirdek spin döngüsüyle doyurulup load1 63'ü geçtiğinde 10'da 3, yani yüklü makine daha sakin. Gerçek oran %26.9. Mekanizma yükte değil: 29 kırmızı koşu 29 **farklı** test düşürdü, hiçbiri iki kez düşmedi. Test yardımcısı her vaka için `listen(0)` çağırıyor, süit makine genelindeki 49152-65535 aralığından ~1260 geçici dinleyici açıyor, çekirdek portu önceki istemci bırakmadan geri dönüştürüyor, ve bir test başka bir testin sunucusundan cevap alıyor (413 bekleyen test 401 aldı). Hakem zaten kırmızı koşuyu yeniden örneklediği için dürüst tamiri boşuna reddetme oranı **%4**, 25'te 1.

**31 gerçek hata vakası**, 8 açık kaynak repodan, 545 commit taranarak, `reports/2026-08-01-gercek-hata-madeni/`. Sentetik değil: her vaka projenin kendi tarihinden, hatayı yakalayan testi o hatayı düzelten mühendis yazmış, sadece düzeltmenin kaynak yarısı geri alındı. Medyan 6 kaynak satırı, medyan 1 düşen test, 31/31 deterministik.

**Korpus:** 12 reponun 12'si kullanılabilir, `reports/2026-08-01-hakem-korpusu/`, commit `1778fc7`.

---

## YÖN, Damla'nın kararı

Rabadon yabancı repolarda **watch modunda** kullanılacak, enforce'ta değil. Sebep ölçülü: hassasiyet %55, yani başkasının reposunda her 20 reddin 9'u meşru işi keserdi.

Asıl kazanç veri. Bugün fixture'daki 34 vakanın hepsi Damla'nın kendi repolarından, ve hassasiyeti 90'a çıkaracak çeşitlilik orada yok. Yabancı repoda çalışılan her saat başkasının Makefile'ını, CI script'ini, tanımadığı test runner'ını deftere düşürüyor. Koşan `yabanci-toprak` işi bu hattı kuruyor.

Aynı koşu express oynaklık bulgusunu yayın seviyesine çıkarıyor. Gönderme kararı Damla'nın, hiçbir ajan issue ya da PR açmayacak.

---

## KURALLAR

Regresyon testi ÖNCE yazılır ve kırmızı olduğu çıktıyla gösterilir. Her "bloklanmalı" testinin yanında "bloklanmamalı" ikizi olur. Yıkıcı komut testi izole, remote'suz temp repoda, sahte git/rm ikilileriyle, HOME o kök altına yönlendirilmiş ve içinde kanarya dosya var.

Dışarı hiçbir şey: publish yok, tag yok, gönderim yok, force-push yok. Commit ve main'e normal push serbest.

Bir adım bir commit bir push. Mesaj ne kanıtladığını söyler, lowercase İngilizce, co-author yok, `-F` ile dosyadan verilir. Mesaja deny kalıbına benzeyen metin yazılmaz, yoksa kendi kapın seni bloklar.

`bin/rabadon.mjs` ve `index.html` okunur, asla düzenlenmez. JS'e yeni kod yazılmaz.

İçerik çıkış koşulu: bir sayı, karar, teşhis ya da çürütme çıktığı AN `~/damla_projects_2026/icerik/dewrites.md` dosyasına düşer. Yazmadan önce dosyanın başındaki YASA okunur, özellikle SES KAPISI (üç ses dosyası okunmadan tek satır yazılmaz) ve YOĞUNLUK ÖLÇÜSÜ (sayı ve hatanın şekli girer, mekanizması silinmiş soyut anlatım basılmaz) maddeleri.
