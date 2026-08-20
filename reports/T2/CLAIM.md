# T2 — CLAIM

Durum: **AÇIK** — tur başladı, kapanmadı.
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

## Kapanış kontrolü (§6.3)

Tur kapanmadı — bu bölüm tur bitince doldurulur.
