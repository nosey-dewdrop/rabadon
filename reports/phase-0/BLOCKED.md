# Faz 0 — BLOKE

Tarih: 2026-08-20. Durma sebebi: `reports/phase-0/accept.sh` **exit 2** veriyor
("koşamıyorum"), ve bu fazın kapsamı içinde kalarak düzeltilemez.

## Ne olması gerekiyordu

Faz 0'ın kapsamı, protokolde tek cümle: *"`/tmp/cheat` → `rabadon-corpus`
reposu. Pinlenmiş commit SHA'ları + `fetch.sh`."* Yani taşıma işi.

## Neden yapılamıyor

Taşınacak şey yok. Korpus bu makinede yok ve git'e hiç girmemiş.

```
$ ls -d /tmp/cheat
ls: /tmp/cheat: No such file or directory

$ git log --all --diff-filter=A --name-only --format="%h" -- '*proposers*' '*probe_ms*' '*probe_cmd*'
(çıktı yok)

$ find ~ /tmp -maxdepth 6 \( -name 'probe_ms.py' -o -name 'probe_cmd.py' -o -type d -name proposers \) 2>/dev/null
(çıktı yok)
```

`native/corpus_cheats.sh` korpustan şunları istiyor (satır 38-56, 111-116):

| Yol | Ne | Durum |
|---|---|---|
| `$CORPUS/proposers/{h1_skip,h2_weaken,h3_conftest,h4_collect,h5_specialcase,h6_eq}.sh` | 6 Python cheat ailesi | yok |
| `$CORPUS/proposers/{h1js_skip,h3js_jestsetup,h3js_pkgscript,h4js_ignore}.sh` | 4 JS cheat ailesi | yok |
| `$CORPUS/probe_ms.py`, `$CORPUS/probe_cmd.py` | "bug hâlâ duruyor mu" probları | yok |
| `$CORPUS/ms/repo-pristine-red`, `$CORPUS/cmd/repo-pristine-red` | iki kasıtlı kırık checkout | yok |
| `$CORPUS/ms/venv` | Python ortamı | yok |

Hepsi elle yazılmış, hiçbiri versiyonlanmamış, hepsi `/tmp` altındaydı.

## Bunun ne anlama geldiği — sadece bir faz gecikmesi değil

`site/measured.json` şu an şunu iddia ediyor:

```
corpus.cheats_refused = 10   ("10 of 10", ölçüm tarihi 2026-08-02, commit 43e43cf)
corpus.cheats        = 10 aile, 10 refused, 0 accepted, 0 held-with-defect
```

Bu sayı **şu an kimse tarafından yeniden üretilemez** — ben de dahil, Damla da
dahil, siteyi okuyan bir yabancı da dahil. Ölçüm gerçekti; ölçüldüğü zemin yok
oldu. Faz 0 tam olarak bunu kapatmak için vardı, ve zemin ondan önce gitti.

Sayı silinmedi ve düzeltilmedi — o benim kararım değil. Ama "doğrulanabilir"
sütununda durmayı hak etmiyor, ve bunu bilerek yayında tutmak ile bilmeden
tutmak farklı şeyler.

## Ne YAPILMADI, bilerek

- Korpus yeniden üretilmedi. 10 cheat ailesini yeniden yazmak Faz 0'ın kapsamı
  değil (kapsam: taşı), ve yayınlanmış bir sayının kanıtını sonradan imal etmek
  bu projenin reddettiği hamlenin ta kendisi. Yeni yazılan bir korpus 2 Ağustos
  ölçümünü doğrulamaz, sadece ona benzeyen yeni bir ölçüm üretir.
- `accept.sh` gevşetilmedi, atlanmadı, yeşile boyanmadı. Olduğu gibi duruyor ve
  exit 2 veriyor.
- Faz 0 "geçti" diye işaretlenmedi.

## Sonraki fazlar

Faz 1, 2, 3, 4 korpusa bağlı değil; Damla'nın kararıyla onlara geçildi
(20 Ağu). Protokolün "sabah üçü de yeşil olacak" kuralı bu gece **karşılanmıyor**
ve karşılanmış gibi raporlanmayacak: Faz 0 kırmızı kalıyor.

## Açılması için gereken karar

Damla'nın vermesi gereken karar, teknik değil kapsam kararı:

1. Korpusu sıfırdan yaz (yeni ölçüm, yeni tarih, eski sayı geri gelmez), veya
2. `corpus.cheats*` sayılarını siteden "doğrulanamıyor" olarak işaretle/kaldır, veya
3. Faz 0'ı "korpusu taşı" yerine "korpusu kur" olarak yeniden tanımla — o zaman
   bu `accept.sh` de yeniden yazılmalı, çünkü bu hâliyle taşımayı test ediyor.
