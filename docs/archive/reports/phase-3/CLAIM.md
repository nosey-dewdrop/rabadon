# Faz 3 — kapsam düzeltmesi

Durum: **kısmi.** `bash reports/phase-3/accept.sh` → exit 1 (51 madde yeşil,
5 madde kırmızı, hepsi tek konuda). Ayrıntı ve karar: `BLOCKED.md`.

## Kapatılan delik

Bir net verdict'i taşınabilir bir nesneydi. `<dir>/.rabadon/net.json` yeşil ya
da kırmızı diyordu ve **hangi ağaç hakkında** olduğunu söylemiyordu. Ölçülen iki
sonuç:

```
A'nın net.json'ını komşu B'ye kopyala, B'de çalış  -> exit 2   B, hiç koşmayan bir süit yüzünden reddedildi
verdict'in yazıldığı dizini yeniden adlandır        -> exit 2   artık o adla var olmayan bir ağacın kararı ateşliyor
```

Artık verdict kökünü taşıyor (`"root"`), ve red-base yalnız o kök oturumun
durduğu ağaç olduğunda ateşliyor. Kökü olmayan verdict — bu alan var olmadan
önce yazılmış olan — hâlâ ateşliyor: yükseltmede her kurulu makineyi sessizce
silahsızlandırmak daha kötü bir hata.

Bu bir kapsam düzeltmesi, ampütasyon değil: aynı worktree içinde verdict hâlâ
geçerli (`scope_test.sh` maddesi 6).

## Yeni test (protokolün Kabul'ü)

`native/scope_test.sh` — 9 iddia, hepsi geçiyor: komşu sızıntısı, yeniden
adlandırma, legacy verdict, alt dizin, git-olmayan dizinin alt ağacı, yeşil.

```
$ make test
exit 0 · 3331 ok · 0 fail    (öncesi 3322; fark yeni testin 9 iddiası)
```

## Üçüncü hal

`net.cpp` artık "koşacak bir şey yoktu" durumunu `could-not-run` yazıyor.
`inconclusive` kaldı ve anlamı korundu: "koştuk, kullanılabilir cevap alamadık"
(bütçesini aşan süit hâlâ `inconclusive`; `net_test.sh:89` bunu mühürlüyor).
Amaç birini yeniden adlandırmak değil, ikisini ayırmak.

## Mod katmanlı

`RABADON_MODE` (env) → `<cwd>/.rabadon/mode` (proje) → `<RABADON_DIR>/mode`
(makine). İlk konuşan kazanır, altındakine bakılmaz. Okunamayan bir
`RABADON_MODE` değeri **watch'a düşmez — enforce eder ve söyler**; bir yazım
hatası muhafızı sessizce silahsızlandırmamalı. Üst katman alttakini asla yazmaz.
Legacy `<cwd>/.rabadon/on` proje katmanında kaldı, makine katmanının üstünde —
o da "bu ağaç" hakkında bir karar.

## Yapılmayan

`enabled` + `mode.last` tek dosyaya **inmedi**. Protokolün Kapsam'ı emrediyor,
Durma'sı yasaklıyor (mühürlü `cli_test.sh:210` o dosyanın varlığını doğruluyor).
Testi düzeltmedim: kabul kriterini onu sağlayan kodla aynı diff'te değiştirmek,
bu ürünün reddetmek için var olduğu hamle. `<RABADON_DIR>/mode` yazılıyor ve
okunuyor; eski iki dosya insan kararına kadar yerinde.

## DOĞRULANMADI

- **Performans ölçülmedi.** Her PreToolUse artık bir `project_root()` + bir
  string karşılaştırması daha yapıyor. `native/gate_bench.sh` var, koşturmadım.
  CLAUDE.md sıcak yol yavaşladıysa sayıyı istiyor — o sayı yok.
- **Eşzamanlılık test edilmedi.** İki repoda iki gate aynı anda: bu fazın konusu
  tam olarak bu ve paralel koşturulmadı.
- **`~/.rabadon` kendini denetliyor mu?** Bu makinede `~/.rabadon/net.json`
  gerçek bir verdict tutuyor (`pytest`, `inconclusive`, 120 sn bütçe aşımı).
  Kırmızı gelseydi `cwd=$HOME` olan her oturum, hiçbir projeye ait olmayan bir
  pytest koşusu yüzünden reddedilecekti. `$HOME` burada bir git reposu, yani yeni
  kök kuralı da bunu engellemez. Protokolde böyle bir kural yok; uydurmadım,
  kayda geçiriyorum.
