# T2 — CLAIM

Durum: **TAMAMLANDI** — kabul 21 yeşil / 0 kırmızı, temiz zeminde doğrulandı.
Tarih: 2026-08-21.

## Açılış kontrolü (§6.3)

**Ürünün cümlesi hâlâ §0'daki mı?** Evet, değişmedi.

**Bu tur o cümleye hangi somut adımı ekliyor?** Yüzeyi 25 verb'den 5'e indiriyor.
Gerekçe §0'a bağlı: birikme motoru (T3–T6) bu yüzeyin üstüne eklenecek ve
25 verb'lük bir bakım borcunun üstüne motor koymak borcu katlar. Ayrıca
`loop.cpp` adı, T3'ten sonra gelecek gerçek döngü motoruyla çakışacak.

**Bir önceki turun `accept.sh`'ı temiz checkout'ta geçiyor mu? — EVET.**

Kendi çalışma ağacında değil, `HEAD`'den açılmış ayrı bir worktree'de koşturuldu:

```
$ git worktree add ~/damla_projects_2026/_t1_clean_check HEAD
$ git -C ~/damla_projects_2026/_t1_clean_check status --short
(boş — kirli dosya yok)

$ cd ~/damla_projects_2026/_t1_clean_check && ./reports/T1/accept.sh
...
PASS  5 `make test` exited 0 (330s)
== T1 acceptance: 20 green, 0 red
T1 ACCEPTED        (exit 0)
```

Bağımsız hakem oturumu değil — bağımsız **zemin**. T1'in yeşili, uygulayanın
ağacındaki artıklara değil, commit'lenmiş içeriğe dayanıyor. Worktree sonra
kaldırıldı.

### İlk deneme `/tmp` altında yapıldı ve kırmızı verdi — kayda geçiyor

İlk temiz koşu `/tmp/t1-clean`'de yapıldı ve **19 yeşil / 1 kırmızı** verdi:
`make test` exit 2, `native/fd_dup_test.sh` içinde refüze edilmesi gereken dört
komut ALLOWED çıktı.

Sebep bulundu ve T1 ile ilgisi yok — koda hiç dokunulmamıştı. Gate `/tmp`'yi
bilerek özel muamele ediyor (`baseline.h`: "A directory every process on the
machine writes into is not a project"). `fd_dup_test.sh` ise fixture'ını
`$HERE/../.fdtest-$$` ile **repo dizininin içine** kuruyor. Repo `/tmp` altında
olduğunda fixture da `/tmp` altında kalıyor, temp muafiyeti devreye giriyor ve
"proje ağacı dışına yazma" kuralı ateşlenmiyor.

Yani zemin olarak `/tmp` seçmek confound üretti; ölçülen şey T1 değil,
fixture'ın konum bağımlılığıydı. Ev dizininde tekrarlandı, 20/0 geldi.

**Bu bir bulgu ve park ediliyor, T2 kapsamı değil:** `native/fd_dup_test.sh`
repo'nun `/tmp` altında bulunmadığını **sessizce varsayıyor**. Bu, repo
`CLAUDE.md`'sinin kalite çıtasının ihlali ("Works on a machine that has only
git and a shell... The reference environment is a clean container" — container
yolu `/tmp` altında olabilir). Test kırılırsa sebep ürün değil fixture, ama
kırılma sessiz ve yanıltıcı: "dört refüz kaçtı" diye okunuyor, oysa muafiyet
kasıtlı. `reports/T2/discards.txt`'ye park edildi.

## Ne yapıldı

**Yüzey beş satıra indi.** `rabadon --help` artık yalnız `init`, `on | off`,
`usage`, `repair`, `doctor` listeliyor (+ `version` ve `dev`). Taşınan 29
verb'ün hiçbiri ana ekranda görünmüyor.

**Hiçbir kod silinmedi, hiçbir verb kırılmadı.** `dev` arm'ı kendini yeniden
dispatch ediyor (`exec "$SELF" "$@"`), yani aşağıdaki case kollarının **tek
biri bile değişmedi**. Bare yazılan `rabadon audit` hâlâ çalışıyor, `rabadon
dev audit` da. Bu, "geri almak tek satır" cümlesinin kod karşılığı: `dev`
arm'ını ve budanmış HELP'i geri alırsan eski yüzey aynen döner.

**`loop.cpp` → `pipeline.cpp`, `rabadon-loop` → `rabadon-pipeline`.** 25 dosyada
72 referans. Verb `loop` olarak kaldı — kullanıcının yazdığı kelime o; değişen
dosya ve binary adı. Sebep protokolde: `loop` adı loop-stop kuralıyla ve T3'ten
sonra gelecek gerçek döngü motoruyla çakışıyordu.

Yeniden adlandırma körlemesine yapılmadı. `export.cpp`, `stats.cpp`, `gate.cpp`,
`trace.cpp` içindeki referansların **yorum** olduğu, tek yük taşıyanın
`do.cpp:109`'daki çalışma-anı binary yolu olduğu önce okundu — eğer bunlar
ledger'daki pipe adı olsaydı yeniden adlandırma eski kayıtları okunamaz hale
getirirdi.

## Kabul

```
$ ./reports/T2/accept.sh
== T2 acceptance: 21 green, 0 red     (exit 0)
PASS  3a make test exited 0 (262s)
PASS  3b make test passing count did not drop: 2015 >= baseline 2014
```

Baseline `reports/T2/baseline.txt`'te, **uygulamadan önce** ölçüldü: 2014.
Sayı düşmedi, bir arttı — eklenen iddia aşağıda.

### Temiz zemin

Kendi ağacımda değil, `HEAD`'den açılmış worktree'de, **sıfırdan derlenerek**:

```
$ git worktree add ~/damla_projects_2026/_t2_clean_check HEAD
$ cd ~/damla_projects_2026/_t2_clean_check && make -j4      # BUILD EXIT=0
$ ls native/rabadon-loop                                    # No such file
$ ./reports/T2/accept.sh
== T2 acceptance: 21 green, 0 red     (exit 0)
```

Bu turda eski binary elle silinmişti (`rm -f native/rabadon-loop`); temiz ağaç
o silmenin bir artık değil, gerçekten Makefile'dan düşmüş olduğunu doğruluyor.
Worktree sonra kaldırıldı.

## İki test değiştirildi — ikisi de koddan önce, kendi commit'lerinde

T2'nin gerçek zorluğu buydu: iki süit, **ana yardım ekranının** her verb'ü
listelemesini şart koşuyordu. Yani turun yapmak için var olduğu hamleyi
yasaklıyorlardı.

- `native/cli_test.sh` — "a stranger cannot find it"
- `native/unknown_verb_probe.py` — "explained SOMEWHERE a reader can reach"

İkisinin de koruduğu şey **keşfedilebilirlik**, ana ekranın kendisi değil. T2
keşif yerini değiştirdi, şartını değil. İkisi de artık `rabadon dev --help`
ekranını da okuyor ve verb'ün ikisinden birinde listelenmesini şart koşuyor.

Zayıflatma yapılmadığının kanıtı iki tane:
- `unknown_verb_probe.py`'nin `>= 15` eşiği **düşürülmedi**; iki ekran birlikte
  38 verb listeliyor.
- `cli_test.sh`'a **yeni bir iddia eklendi**: `rabadon dev --help` gerçekten
  dolu mu (>200 bayt). Boş bir `dev` yardımı = 29 verb'ün hiçbir yerde
  bulunamaması, ve artık kırmızı verir. Test sayısının 2014 → 2015 çıkmasının
  sebebi bu.

Gerekçeler `discards.txt` madde 3 ve 3b'de.

## Kapanış kontrolü (§6.3)

- Kaç yeşil / kaç kırmızı? **21 / 0.** → tamamlandı.
- Kapsam dışına çıkıldı mı? **Hayır.** Ama kapsam, tur başlamadan **insan
  onayıyla genişledi**: protokol 25 verb sayıyordu, dispatcher'da 43 var,
  taşınan sayı 19 değil 29. Düzeltme kendi commit'inde ve uygulamadan önce
  (`discards.txt` madde 1).
- Sonraki tur için değişen varsayım var mı? **Evet:** T3'ün "gerçek döngü
  motoru" artık `loop` adıyla çakışmıyor — `pipeline` o adı boşalttı.

## NOT VERIFIED

- **Bağımsız hakem oturumu T2'ye bakmadı.** T1'de hakem üç gerçek hata
  bulmuştu; T2'de bu adım atlanmadı, henüz yapılmadı.
- **`rabadon dev <verb>` çağrılarında yalnız YÖNLENDİRME doğrulandı, davranış
  değil.** Kabul testi her verb'ü `--help` ile çağırıyor. `remove`, `repair`
  gerçek iş yapar, `serve` port bağlar; onları koşturan bir kabul testi yıkıcı
  test olurdu. Davranışı `make test` kapsıyor.
- **npm paket tarafı derlenmedi.** `npm/*/package.json`'ların `files` dizisinde
  ad düzeltildi ama dört platform paketi bu turda **paketlenip denenmedi**.
  Yanlışsa T8'de (yayın) patlar, burada değil.
- **`.github/workflows/release.yml` koşturulmadı** — CI'da doğrulanmadı.
- `docs/commands.md` ve `site/patch-notes.html` hâlâ `rabadon-loop` diyor.
  Kasıtlı: kabul testi 4c bunları geçmiş/doküman olarak dışlıyor. Ama
  `docs/commands.md` **canlı doküman**, geçmiş değil — bayat kaldı ve T2'de
  düzeltilmedi.
