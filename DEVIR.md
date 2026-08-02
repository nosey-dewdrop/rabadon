# DEVİR — rabadon, 2 Ağustos sabahı

Bu dosya yeni oturuma yapıştırılır. Her sayı ölçüldü. Ölçülemeyenler en altta,
ayrı başlık altında, "ölçemedim" diye yazılı.

---

## DURUM

`make test` EXIT=0, sıfır hata. Sitede duran her sayının altında onu üreten
komut var ve bunu bir test tutuyor.

```
cases: 34   correct block: 11   wrong block: 0   missed: 0   correct allow: 23
precision 100.0%   recall 100.0%
judge one command   median 130.0µs   p95 ~205µs   (n=200 × 34 vaka)
hook, uçtan uca     native 2.70ms    node 102ms    38 kat
```

Site dört sayfa, dördü de üretiliyor. Deploy `python3 site/build.py`, sonra
`cd site && vercel deploy --prod --yes`, sonra
`vercel alias set <deployment> rabadon.noseydewdrop.com`.

**DEPLOY TUZAĞI, 2 Ağustos'ta düzeltildi.** `site/` klasörü kendi adını taşıyan
ikinci bir Vercel projesine bağlıydı, alan adı ise `rabadon` projesinin. Bir
alan adını başka projenin deployment'ına alias'lamak deployment protection'ı
açık bırakıyor, yani **rabadon.noseydewdrop.com her ziyaretçiye 302 SSO login
duvarı veriyordu** ve 200 dönen tek adres eski sayfayı servis eden
rabadon.vercel.app'ti. `site/.vercel/project.json` artık `rabadon` projesine
bağlı. Deploy'dan sonra `curl -o /dev/null -w '%{http_code}'` ile 200 gör.

---

## BU GECE KAPANANLAR

**1. 42.0µs ölçülemiyordu, artık ölçülüyor.** Sitede haftalardır duran sayı
`native/gate_bench.sh`'ı kaynak gösteriyordu ve o dosya yoktu; depoda hiçbir
mikro benchmark yoktu. `native/gate_bench.cpp` yazıldı, `rbrules::judge_command`
in-process ölçülüyor, 34 gerçek vaka, medyan **130.0µs** (sayfadaki sayının üç
katı). Benchmark timer'ı okumadan önce aynı 34 vakayı gerçek `rabadon-gate`
binary'sinden geçiriyor; tek hüküm uyuşmazsa hiçbir sayı basmıyor.

**2. Gate, judge_command'ın elle yazılmış ikinci kopyasıydı.** Parite kanıtı
bunu buldu. `rules.h` "bu fonksiyonun yarısını yeniden yazan caller exec'i
bypass yaptı" diye yazıyor ve o caller gate'in kendisiydi. Artık paylaşılan
hükmü çağırıyor, parse'ı geri alıyor, ve gate_bench.sh ikisini bir arada tutuyor.

**3. Manşet sayıları elle tutulmuyor.** `site/index.tmpl.html` şablon,
`site/measured.json` ölçümleri komut ve commit ile taşıyor, `native/measure.sh`
onu yazıyor. `native/site_claims_test.sh` dört kuralı tutuyor: sitenin adını
verdiği her kaynak var olacak, manşet yuvasına elle sayı yazılamayacak, iki
sayfada geçen olgunun tek değeri olacak, ve README'nin satır iddiası gerçek
sayıyla karşılaştırılacak.

**4. Bulgu defteri açıldı.** `site/findings.jsonl`, 42 kalem, her biri repo +
dosya + ne bozuktu + kanıtlayan komut + durum. `site/finding.py` ekliyor, elle
yazılmıyor. Catches sayfasında render ediliyor. 31'i sekiz açık kaynak projeden
çıkarılmış gerçek kusur, yamalarıyla birlikte `reports/2026-08-01-real-defect-mine/`.

**5. Hakemdeki iki delik kapandı.** `native/heldout.h` + repair.cpp adım 5c.
Eleme yapısal ve hiçbir şeye karar vermiyor (kilitli test dosyalarındaki her
string, sha256'sı ve uzunluğu toplanıyor); hüküm her zaman yeniden koşu
(işaretli hunk'lar `patch -R` ile geri alınıp projenin kendi kontrolü tekrar
koşuyor, kırmızı ise yeşil o hunk'a aitti). Girdiye kilitlenmenin üç biçimi de
kapalı: değer, sha256, uzunluk. `native/heldout_test.sh` 4 reddedilmeli + 4
ikiz, hepsi gerçek binary.

**6. Hile korpusu ürünün kendisiyle koşuldu.** `native/corpus_cheats.sh`, 10
aile, **10 reddedildi, 0 kabul, defekti hâlâ taşıyan 0 tutulan yama.** Denetim
bunu arena.sh taklidiyle yapmıştı.

**7. Kilit hiçbir şeyi kilitlemiyordu, büyük süitlerde.** İlk korpus koşusu
buldu: `rabadon-truth` commander'da 122 test dosyası buluyor, `repair` 0
kilitliyordu. Sebep tek varsayılan — `run_shell` çocuğun çıktısının son 4000
baytını tutuyor ve repair truth'un JSON'unu aynı tampondan okuyor; JSON 4503
bayt olunca `"testFiles":[` etiketi baştan kesiliyor. express 2382 baytla
sığdığı için 91 kilitlemiş ve kimse görmemişti. **Süit büyüdükçe koruma
azalıyordu.** `native/lock_coverage_test.sh` kırmızı yazıldı; üçüncü vakası
bedeli gösteriyor: 161 dosyalık süitte testi `assert True` yapan öneri
reddedilmiyor, TUTULUYORDU.

**8. Keşifte üç sessiz sınır.** Derinlik 4 (zod'un süiti 6 derinde, 170'in 2'si
bulunuyordu), `test.ts` adlı dosyaya uyan hiçbir desen yok (date-fns'in 253
dosyasının tamamı), liste 512 + yürüyüş 20000 bütçe. Derinlik 12, liste 4096,
bütçe 200000, ve üçü de `discoveryCapped` ile kendini ilan ediyor. İkiz kuralı
gerçek repodan geldi: jinja'da `src/jinja2/tests.py` KAYNAK ve
`examples/basic/test.py` örnek, ilk geçiş ikisini de kilitledi. Artık çıplak
`test` kökü ancak repo üç ayrı dizinde tekrarlıyorsa sayılıyor, `tests` hiç
sayılmıyor.

**9. npm kurulumu derleyicisiz kanıtlandı.** `native/npm_install_test.sh` bölüm
6: temiz prefix, PATH'in başında cc/gcc/g++/clang/clang++/c++/make/cmake/ld
yerine adını loglayıp 127 ile çıkan shim'ler. Kurulum başarılı, shim logu boş,
`rabadon --version` tarball'dan gelen gerçek binary'den 0.2.0 basıyor. 12 kontrol,
sıfır atlama. **Tag atılmadı, yayın yapılmadı.**

**10. `rabadon --version` diye bir komut yoktu.** `unknown command "--version"`
diyordu. Alttaki her binary cevaplıyordu, insanın yazdığı tek komut
cevaplamıyordu. Artık var ve cevabı BINARY'den alıyor.

**11. README 2.7 kat eksik söylüyordu.** "~5k lines of dependency-free C++"
yazıyordu, gerçek 14.140. Düzeltildi ve site_claims_test.sh her koşuda yeniden
sayıyor.

---

## 2 AĞUSTOS 03:55 — SİTEDEKİ MANŞET DÜZELTİLDİ, AKTİF MOD AÇILMIYOR

Bu oturumun /clear'dan ÖNCE başlattığı workflow (39 ajan, ~7 saat) 03:11'de
bitti ve iki sayı getirdi. İkisini de kendim yeniden ürettim.

**Fixture %100, gerçek defter %26.3.** 34 vakalık fixture yanlış değil, DAR.
Aynı binary `~/.rabadon/spool` içindeki 215 gerçek reddedişle koşulunca: 15
gerçek tehlike duruyor, 0 geçiyor, 42 meşru iş kesiliyor. 42'nin 41'i rabadon'un
KENDİ kırmızı-takım laboratuvarı; onlar çıkınca 15/16 = %93.8. Üç sayı da sitede,
her birinin altında komutu.

**95 adı konmuş kaçağın 58'i açık.** `python3 redteam/redteam.py` ile kendim
koştum: 37 kapalı, 58 açık. Dokuzunu izole laboratuvarda elle tekrar doğruladım,
dokuzu da tekrarlandı (`git push --forc`, `git branch -D main`, `git clean -xfd`,
`git reset --hard @{u}`, `rm -rf .git`, `find -delete`, `rsync --delete`,
`pushd && rm -rf`, `bash /tmp/s.sh`). Dört küme: silen fiil rm değil (14), kabuk
konumu takip edilmiyor (5), program satırda yok (11), git'in kendi grameri (28).

**AKTİF MOD AÇILMIYOR.** Tutamayacağı koruma sözü veren kapı, ne durdurduğunu
söyleyen kapıdan kötüdür. Site bunu yazıyor.

**Bir sızıntı kapatıldı:** `NOTES-FOR-DAMLA.md` public repoya üç yayınlanmamış
proje adıyla push'lanmıştı. HEAD'de temizlendi. Adlar tek bir commit'in
geçmişinde duruyor; çıkarmak filter-repo + force-push ister, o KARAR DAMLA'NIN.

---

## ÖLÇEMEDİKLERİM

- **zod ve date-fns bu makinede yok.** Keşif düzeltmesi onların ÖLÇÜLMÜŞ
  şekillerine (derinlik, `test.ts` adı) göre kurulmuş fixture'larla ve jinja
  üstünde kanıtlandı. O iki repoda 2/170 ve 16/253 sayıları YENİDEN ÖLÇÜLMEDİ.
- **JUnit ve Go kilidi hâlâ uçtan uca koşulmadı.** `pom.xml`, `build.gradle`,
  `go.work` hash listesinde ve gerekçesi repair.cpp'de yazılı, ama bu makinede
  maven surefire'ı çevrimdışı çözemiyor ve go yok.
- `h3js_pkgscript` ailesi "still-red" ile reddedildi, harness kilidiyle değil:
  koşuya `--cmd` ile sabit komut verildiğinden package.json'ı yeniden yazmak
  hakemin koştuğu komutu değiştirmedi. Reddediş gerçek, gerekçe farklı.
- Hile ailelerinin sadece 2 repoda (markupsafe, commander) denendiği korpus
  uyarısı hâlâ geçerli.

---

## SIRADAKİ İŞLER

**A. Bağımsız oracle'lı fuzzer (Damla'nın git-ai turundan, kabul edildi).**
Hakemin kandırılamazlığının kanıtı hâlâ elle kurulmuş 10 aile ve elle kurulan
hile kuranın aklına geleni sınar. Fuzz'lanacak şey proposer uzayı; bağımsız
oracle "hata hâlâ kaynakta mı" probu. Her bulgu dörde dönüşür: seed + operasyon
logu, minimize edilmiş deterministik regresyon testi, kök sebep, kalıcı test.
`make test`'e GİRMEZ, ayrı `make fuzz` hedefi olur.

**B. `docs/LEDGER.md` + bağımsız doğrulayıcı.** `rabadon audit` "zincir sağlam"
diyor ve bunu kimse bağımsız doğrulayamıyor, çünkü alan sırası, boşluk ve prev
hash'in tam olarak neyin sha256'sı olduğu sadece kodda yaşıyor. Tek sayfa spec
artı spec'e bakarak yazılmış 20 satırlık python doğrulayıcı artı onu koşturan
test. Doğrulayıcı `rabadon audit` ile aynı cevabı vermiyorsa spec yalandır.

**C. `docs/BANNED-PROOFS.md`.** Denenip elenmiş ispat yolları tek yerde: dosya
hash'i H5/H6'yı göremez, test sayımı kök conftest'i göremez, AST tek başına
yeter değil, trace2 asenkron olduğu için gate olamaz. Malzeme bu gece üretildi.

**D. Redaksiyon.** README "nothing leaves" diyor, aynı repoda `export --otlp`
var ve event'lerin `detail` alanı komut metnini taşıyor. Dar iş: export yolunda
sır deseni taraması, baştan/sondan 4 karakter bırakan redaksiyon, önce kırmızı
test (gerçek şekilli sahte token'lar export'tan geçiyor mu).

**E. express katkısı, GÖNDERİLMEDİ, KARAR DAMLA'NIN.** Dal hazır:
`~/damla_projects_2026/katki/express`, dal adı
`fix/res-send-arraybuffer-view-bytes`. Aynı satırlara dokunan açık PR #7363 var,
6 Temmuz'dan beri yorumsuz, çakıştığı `git merge-tree` ile ölçüldü. Tavsiye:
rakip PR değil, #7363 altına ölçümü koyan bir yorum. Hiçbir ajan göndermez.

**F. npm yayını.** v0.2.0 dört platform için kurulu, kurulum derleyicisiz
kanıtlandı. Eksik olan tek şey npm org + NPM_TOKEN, ikisi de Damla'da.

---

## KURALLAR, İHLAL EDİLMEZ

**AYNI AĞAÇTA İKİNCİ OTURUM VARSA `git add -A` YAPMA.** 2 Ağustos gecesi açık
kalmış başka bir Claude oturumu bu repoda çalışıyordu ve 01:48'de attığı commit
benim stage'lediğim dosyaları kendi mesajının altına aldı. Commit'ten önce
`ps ax | grep claude` ve son 5 dakikada değişen dosyalara bak; başkası varsa
sadece kendi yollarını tek tek stage'le.

**Ajanlara dokunma.** Damla "ajan sal" demeden ajan açılmaz. Damla NET olarak
"ajanı öldür" demeden koşan hiçbir iş durdurulmaz, kesilmez, resume edilmez.

Regresyon testi ÖNCE yazılır ve kırmızı olduğu çıktıyla gösterilir. Her
"bloklanmalı" testinin yanında "bloklanmamalı" ikizi olur. Yıkıcı komut testi
izole, remote'suz temp repoda, sahte git/rm ikilileriyle, HOME o kök altına
yönlendirilmiş ve içinde kanarya dosya var.

Dışarı hiçbir şey: publish yok, tag yok, PR yok, issue yok, fork yok,
force-push yok. Commit ve main'e normal push serbest.

Bir adım bir commit bir push. Mesaj ne kanıtladığını söyler, lowercase
İngilizce, co-author yok, `-F` ile dosyadan verilir.

Ölçemediğine "ölçemedim" yazılır. Sayı uydurulmaz. Sitede duran her sayının
altında onu üreten komut olur ve `native/site_claims_test.sh` bunu tutar.

`bin/rabadon.mjs` okunur, asla düzenlenmez. JS'e yeni kod yazılmaz.

İçerik çıkış koşulu: bir sayı, karar, teşhis ya da çürütme çıktığı AN
`~/damla_projects_2026/icerik/dewrites.md` dosyasına düşer. Yazmadan önce
dosyanın başındaki YASA okunur. Bu gecenin girdisi: `TOHUM 2-8-02-55`.
