# faz 0 — üç dosyanın incelemesi

Tarih: 2026-08-20. Faz 0 KOŞTURULMADI, korpus taşınmadı. Bu dosya sadece
inceleme + kabul testinin gerekçesi.

**Bulunan hata: 16.** Kritik 4, orta 7, düşük 5. Her biri komutla kanıtlandı.
Kanıt komutları aşağıda birebir, çıktılarıyla.

---

## KRİTİK

### K1 — `mine_honest.sh` kirli çalışma ağacında kaydedilmemiş işi siler

`git checkout -q --force "$BASE"` üç yerde çağrılıyor (satır 89, 92, 98, 114, 117)
ve script hiçbir yerde `git status --porcelain` sormuyor. Kaydedilmemiş her şey gider.

```
$ cd /tmp/mh-lab/repo && echo "// my uncommitted work" >> calc.js
$ git status --short
 M calc.js
$ OUT=/tmp/mh-lab/out bash mine_honest.sh /tmp/mh-lab/repo 'sh check.sh' 5 50
== baseline: HEAD must be green before anything is mined ==
   green.
scanned 2 commits -> 0 cases
  discarded: 2 wrong shape, 0 did not go red, 0 nondeterministic
$ grep -c "my uncommitted work" calc.js
0
```

Satır 54'teki "HEAD yeşil mi" kontrolü var ama "ağaç temiz mi" kontrolü yok.
Bu repoda şu an 44 silinmiş dosya bekliyor (`git status --short | grep -c '^ D'`),
yani burada koşarsa o silmeler geri gelir ve kimse fark etmez.

### K2 — **GERİ ÇEKİLDİ (20 Ağu).** İddia yanlıştı, kanıtım kanıtlamıyordu.

Aşağıdaki tuzakta commit, `test/old.test.js`'i de değiştirmişti (`sub`
assertion'ını o commit ekledi). Yani kırmızıyı üreten assertion commit'in kendi
eklediği assertion'dı — geçerli bir tanık. "Boş yeni test" dikkat dağıtıcıydı,
vakanın kendisi sağlamdı.

Doğru tuzağı sonradan kurdum: mevcut hiçbir teste dokunmayan, sadece kaynak +
bomboş yeni test içeren bir commit. Script onu **doğru şekilde reddetti**:

```
$ OUT=/tmp/mh3/out bash native/mine_honest.sh /tmp/mh3/repo 'sh check.sh' 0 50
scanned 2 commits -> 0 cases
  discarded: 1 wrong shape, 1 did not go red, 0 nondeterministic
```

Kuruluş aslında sağlam ve sebebi şu: ebeveyn ağaç ESKİ kaynak + ESKİ testlerle
yeşildi. Kaynak-only revert = ESKİ kaynak + YENİ testler. O yüzden düşen her
test, ebeveynden test tarafında farklı olan bir testtir — yani commit'in
eklediği/değiştirdiği bir test. Tek istisna: yeni bir testin bıraktığı durumun
eski bir testi düşürmesi (test kirliliği).

Yapılan düzeltme bu yüzden "kritik hata tamiri" değil, **denetlenebilirlik**:
kırmızı çıktı artık atılmıyor, vaka klasörüne `red.log` olarak yazılıyor, test
tarafı `witness-test.patch` olarak duruyor, ve `case.env`'deki not artık
kanıtlanmamış bir şeyi ("commit'in kendi testi tanıktır") iddia etmiyor.

Toplam sayı bu yüzden **16 değil, 15 hata + 1 geri çekilmiş iddia.**

<details><summary>Geri çekilen orijinal iddia (kayıt için)</summary>

`case.env` şunu yazıyor: *"the commit's own test is the witness"*. Script bunu
hiç kontrol etmiyor — sadece **süitin tamamı** kırmızı mı diye bakıyor. Commit'in
kendi testi hiçbir şey iddia etmese bile vaka kabul ediliyor.

Kurulan tuzak (`/tmp/mh-lab2/repo`): tek commit, iki alakasız kaynak dosyası
(`core.js`, `extra.js`) + yeni bir test dosyası (`test/new.test.js`) ki içinde
sadece `assert(true)` var. Kırmızıyı üreten, commit'ten ÖNCE var olan
`test/old.test.js`.

```
$ OUT=/tmp/mh-lab2/out bash mine_honest.sh /tmp/mh-lab2/repo 'sh check.sh' 5 50
  CASE 1  c101d017  feat: sub + bye, with a vacuous new test
scanned 2 commits -> 1 cases
$ cat /tmp/mh-lab2/out/*/case.env
sha=c101d0176b0ea14832e595e8a02460e362692bed
subject=feat: sub + bye, with a vacuous new test
source_files=core.js extra.js
expect=held
note=source-only revert reproduces the bug; the commit's own test is the witness
```

Yani: dürüst kol korpusuna, tanığı boş bir vaka girdi ve dosya "tanık var" diye
yazdı. Bu tam olarak rabadon'un reddetmek için var olduğu şeyin, rabadon'un kendi
fikstür üreticisinde tekrarlanması. Kapatılması gereken: kaynak-only revert'ten
sonra kırmızıya dönen test dosyası, commit'in EKLEDİĞİ test dosyası olmalı.

</details>

### K3 — Kapı 3'ün mührü 10 gerçek test dosyasını kaçırıyor

Protokoldeki `find` deseni `*_test.sh`, `test/*`, `accept.sh`, `corpus_*.sh`,
`heldout_test.sh` topluyor. Repodaki JS süiti (`*.test.mjs`) desende yok.

```
$ find . -path ./node_modules -prune -o \( -name '*_test.sh' -o -path './test/*' \
    -o -name 'accept.sh' -o -name 'corpus_*.sh' -o -name 'heldout_test.sh' \) -print | sort | wc -l
      98
$ comm -13 /tmp/seal.txt /tmp/alltests.txt
./core/bus.test.mjs
./core/rabadon.test.mjs
./core/store.test.mjs
./core/wrap.test.mjs
./demo/live-repair-evidence.test.mjs
./hooks/gate.test.mjs
./hooks/guard-gen.test.mjs
./hooks/install.test.mjs
./ui/server.test.mjs
./native/testout.h
```

Bir ajan `core/rabadon.test.mjs`'i zayıflatabilir, faz sonu hash diff'i sessiz kalır.
Ayrıca mühür listesinde olmayan üç dosya daha var ve üçü de karar taşıyor:
`.rabadon/guard.json` (gate'in kendi yasası), `site/measured.json` (yayınlanan
sayılar), `reports/scoreboard.tsv` (kayma detektörünün hafızası).

### K4 — `scoreboard.sh` projenin manşet sayısını "?" diye raporluyor

İki anahtarda `value` bir sayı, script onu sözlük gibi indeksliyor. Python
istisna atıyor, `except` bloğu boş string basıyor, `q()` onu "?" yapıyor.

```
$ python3 -c "import json;d=json.load(open('site/measured.json'));
  print(d['corpus.cheats_refused']['value'], d['field.stop']['value'])"
10 431
```

`corpus.cheats_refused["value"]` = **10** (int), script `["value"]["families"]` diyor.
`field.stop["value"]` = **431** (int), script `["value"]["total"]` diyor.

Taban satırının kendisi kanıt:

```
$ PHASE=0 bash scripts/scoreboard.sh .
ts                 phase  cheat  honest  wild_held  stops  wrong  verbs  why_len  classed  repro
2026-08-20T00:26Z  0      ?      ?       ?          ?      6      17     144      ?        ?
```

`cheat` ve `stops` ölçülebilir durumdayken "?" yazıldı. Dosyanın kendi kuralı
("ölçemediği şeye ? yazar") doğru uygulanıyor — ama ölçebildiği şeyi ölçemiyor.
Tehlike: bu iki sütun `up` listesinde, yani asla geri gitmemeli. "?" olduğu sürece
`num()` None döner ve **kayma kontrolü o iki sütun için hiç çalışmaz.**

---

## ORTA

### O1 — `git apply -R` başarısızlığı "wrong shape" diye sayılıyor

Satır 88-90: revert uygulanamazsa `skipped_shape++`. Şekil hatası değil, uygulama
hatası. Kapı 2 eleme sayılarını zorunlu alan yapıyor; o sayı yanlış sebebi gösteriyor.
K1'deki kirli koşuda tam bu oldu — geçerli bir vaka "wrong shape" olarak elendi:

```
$ bash -x mine_honest.sh ... | grep -E "git checkout|git apply|skipped_shape="
108:+ git checkout -q c04aa049...
110:+ git apply -R --index
111:+ git checkout -q --force c04aa049...
112:+ skipped_shape=1
```

Temiz ağaçta aynı commit vaka olarak kabul ediliyor (bkz. O2 trace'i).

### O2 — kural 3 ve 4 ATLANMIYOR (soruya cevap: koşuyor)

Temiz ağaçta trace, ikisinin de koştuğunu gösteriyor:

```
+ git apply -R --index          <- kaynak-only revert
+ run_check ; + eval 'sh check.sh'   <- kural 3: kırmızı bekleniyor
+ git checkout -q --force <sha>
+ run_check ; + eval 'sh check.sh'   <- kural 4: yeşil bekleniyor
+ kept=1
```

Tek atlanma yolu K1/O1: revert uygulanamazsa ikisi de koşmadan vaka elenir ve
eleme yanlış kovaya yazılır. Yani "sessizce atlanıyor" değil, "yanlış etiketle
eleniyor".

### O3 — script repo'yu DETACHED HEAD'de bırakıyor

`BASE=$(git rev-parse HEAD)` bir SHA; son satır `git checkout --force "$BASE"`.
Dal adı kayboluyor.

```
$ git status -sb | head -1
## HEAD (no branch)
```

Kullanıcının hangi dalda olduğu hiç kaydedilmiyor (`git symbolic-ref` yok).

### O4 — vaka minimal değil: aynı commit'teki alakasız kaynak dosyaları da geri alınıyor

K2 tuzağında `extra.js` düzeltmeyle ilgisiz ama `source_files=core.js extra.js`
oldu ve patch ikisini birden taşıyor. Fikstür "bilinen-iyi düzeltme" olarak
sunuluyor; içinde ne olduğu belirsiz.

### O5 — Kapı 1'in kontrol komutu çalışmıyor

Protokol satır 31: `git log --oneline accept.sh`. Repo kökünden:

```
$ git log --oneline accept.sh
fatal: ambiguous argument 'accept.sh': unknown revision or path not in the working tree.
exit=128
```

`--` ve tam yol gerekiyor: `git log --oneline -- reports/phase-N/accept.sh`.
Düzeltilmiş haliyle bu commit'te geçiyor:

```
$ git log --oneline -- reports/phase-0/accept.sh
9d15c1b phase 0 gate: the corpus must rebuild from fetch.sh and still refuse 10 of 10
```

### O6 — Kapı 1'in yapısal boşluğu: kabul testi, faz tarafından yazılan bir dosyaya bağımlı

Faz 0'ın kabul testi `fetch.sh`'ı çağırmak zorunda, ama `fetch.sh`'ı faz 0
yazıyor. Yani gate'in yarısı uygulayan ajanın kontrolünde. `corpus_cheats.sh`
mühürlü (Kapı 3, `corpus_*.sh`), `fetch.sh` değil.

`accept.sh` bunu şu kadar kapatabildi: iddiaları `corpus_cheats.sh`'ın çıktısından
okuyor, `fetch.sh`'ın söylediğinden değil; ve korpus taze bir dizine çekiliyor,
`RABADON_CHEAT_CORPUS` temizleniyor, `/tmp/cheat` kalıntısı testi geçiremiyor.
**Kapatamadığı:** `fetch.sh` bozulmuş bir korpus çekerse bunu anlayamaz. Pinlenmiş
SHA'ları faz 0 yazacağı için şimdiden doğrulanamıyor. AÇIK DELİK — Kapı 2'nin
raporunda faz 0'ın çektiği her SHA'nın public upstream'de olduğu ayrıca gösterilmeli.

### O7 — Kapı 2 sadece azalan elemeyi yakalıyor

Şüphe kuralları: "sıfır eleme → ret" ve "eleme oranı %50'den fazla DÜŞTÜYSE → şüpheli".
Ters yön yok. Filtreyi gevşetip daha çok vaka tutan bir ajan, eleme sayısını da
artırarak iki kuralın ikisinden de temiz geçer. Ayrıca sayıları üreten ajan ile
raporlayan ajan aynı; hiçbir artefaktan bağımsız yeniden sayım yapılmıyor.
`kept` yeniden sayılabilir (`find honest-cases -name case.env | wc -l`), eleme
sayıları hiçbir dosyaya yazılmıyor — sadece stdout'a.

---

## DÜŞÜK

### D1 — `mine_honest.sh` `discards.txt` üretmiyor
Kapı 2 eleme sayılarını zorunlu alan yapıyor, script onları sadece ekrana basıyor
(satır 120). Protokolle script arasında boşluk.

### D2 — MAX varsayılanı 40, Kapı 2 "tam 40" gördüğünde şüpheleniyor
Script satır 65: `[ "$kept" -ge "$MAX" ] && break`. Malzeme yeterliyse çıktı her
zaman tam 40 olur. Protokol satır 43 bunu otomatik şüpheli sayıyor. İki dosya
birbiriyle çelişiyor; ya varsayılan kalkmalı ya kural "MAX'a değdi mi" diye sormalı.

### D3 — `scoreboard.sh` `why_len`'i eksik ölçüyor
`why + fix` toplanıyor ama `guard.json` kurallarında `fix` anahtarı yok:
```
$ python3 -c "import json;d=json.load(open('.rabadon/guard.json'));print(list(d['bash'][0]))"
['id', 'deny', 'why', 'allow', 'catches']
```
144 sayısı sadece `why`. Hedef "why+fix ≤ 200" bu ölçümle test edilmiyor.

### D4 — `verbs` fiil değil başlık sayıyor
```
$ grep -cE '^## `rabadon ' docs/commands.md
17
$ grep -oE '^## `rabadon [a-z |]+' docs/commands.md | sed 's/^## `rabadon //' | tr '|' '\n' | tr -d ' ' | grep -c .
20
```
`## \`rabadon on | off | status | toggle\`` tek satırda 4 fiil. "Artmamalı" denen
sayı, iki başlığı birleştirerek yüzey küçülmeden düşürülebilir.

### D5 — `assert_delta` diff başlığını sayabiliyor (dar kapsam)
Yeni eklenen bir test dosyasının yolu "assert/expect/should" içeriyorsa
`+++ b/...` satırı kural 2'ye bedava +1 veriyor:
```
$ printf -- '--- /dev/null\n+++ b/test/expect.test.js\n' | grep -cE '^\+.*(assert|expect|should|\.to\.|EXPECT_|ASSERT_)'
1
```
Değiştirilen dosyada `--- a/...` de eşleştiği için iki taraf birbirini götürüyor
(1 ve 1), yani sadece YENİ dosyada delik açık. `spec/` altındaki dosyalar
etkilenmiyor — "spec" regex listesinde yok.

Ayrıca küçük notlar: `OUT` varsayılanı `$PWD/honest-cases` (çağıranın durduğu yere
yazar, repoya değil); `scoreboard.sh`'daki `wild_repairs_held` anahtarı
`measured.json`'da hiç yok, o yüzden hep "?"; kayma kontrolünün yorumu "üçten
itibaren" diyor ama kod `len(rows)<2` ile ikinci satırdan itibaren kıyaslıyor;
protokolün sabah kontrolü `locks.txt.before`/`.after` diff'liyor ama Kapı 3
sadece `locks.txt` üretiyor — o diff bugünkü haliyle her zaman hata verir.

---

## NEYE BAKTIM

- Üç dosyanın tamamı satır satır.
- `scoreboard.sh`'ın okuduğu her yol ve anahtar, gerçek dosyalara karşı:
  `site/measured.json` (40 anahtar), `docs/commands.md`, `.rabadon/guard.json`,
  `reports/phase-1/discards.txt` (yok → "?" doğru), `corpus/fetch.sh` (yok → "?" doğru).
- `mine_honest.sh` iki sentetik repoda uçtan uca koşturuldu (`/tmp/mh-lab`,
  `/tmp/mh-lab2`), biri temiz biri kirli ağaçla, `bash -x` trace'iyle.
- Protokolün Kapı 1 ve Kapı 3 komutları bu repoda birebir koşturuldu.
- `native/corpus_cheats.sh` okundu (çıktı formatı, `RABADON_CHEAT_CORPUS`,
  exit kodları) — değiştirilmedi.

## NE DOĞRULAMADIM

- `mine_honest.sh` gerçek bir hedefte (express) hiç koşturulmadı. Faz 2'nin işi,
  kapsam dışı. Sentetik repolardaki davranış oraya birebir taşınmayabilir.
- `accept.sh` yeşil yolunda hiç koşturulmadı — korpus makinede yok
  (`ls -d /tmp/cheat` → No such file or directory). Kırmızı ve "koşamıyorum"
  yolları üçer negatif testle doğrulandı; yeşil yol faz 0 bitene kadar **DOĞRULANMADI**.
- `fetch.sh`'ın çekeceği SHA'ların upstream'de olduğu doğrulanamaz (O6).
- `*.test.mjs` süitlerinin `make test`'e bağlı olup olmadığına bakmadım; son
  commit mesajı "two suites turn out to be wired into nothing" diyor, ilgili olabilir.
- Bu repoda `node_modules` yok, o yüzden Kapı 3'ün `-path ./node_modules -prune`
  deseninin iç içe `node_modules`'ü budamadığı sorunu şu an latent.
