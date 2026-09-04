# Faz 2 — dürüst kol madenciliği

Durum: kabul testi koşuyor. Kanıt komutu `bash reports/phase-2/accept.sh`.

## Ne yapıldı

`native/mine_honest.sh` express'in kendi tarihinde 1000 commit tarayıp **4 dürüst
tamir vakası** çıkardı. Her vakada, o commit'in SADECE kaynak değişikliği geri
alındığında süit kırmızıya döndü, geri konduğunda yeşile döndü — ikisi de
koşturuldu, ikisi de loglandı.

```
scanned 1000 commits -> 4 cases  (cap: 0, hit: no)
  discarded 996:
    936 wrong shape
      0 revert would not apply
      0 checkout failed
      0 did not go red
     60 nondeterministic
```

Vakalar:

| Vaka | Commit | Konu |
|---|---|---|
| 1 | `fd95b8cb` | `res.send`: ArrayBuffer view'in gerçek byte'ları |
| 2 | `ae6dd376` | QUERY istekleri için koşullu revalidation |
| 3 | `18e5985b` | `res.send`: Content-Length yalnız Transfer-Encoding yoksa |
| 4 | `59e205a5` | `content-disposition` yükseltmesi |

Her vaka klasöründe: `case.env`, `known-good-fix.patch` (bilinen-iyi düzeltme),
`witness-test.patch` (tanık testin kendisi), `red.log` (üretilen kırmızının
birebir çıktısı).

## Neden 400 değil 1000 commit tarandı

400'de tarama **3 vaka** verdi, kapının tabanı 4. Sebep filtre değil, express'in
kendi süiti: `res "etag" setting … should send no ETag` testi ara sıra
`socket hang up` veriyor. Tek bir flake koşusu geçerli bir vakayı
"nondeterministic" kovasına atıyor — 400'de 29, 1000'de 60 elenen bunun içinde.

Yapılmayan şey: `mine_honest.sh`'a "flake olursa tekrar dene" eklemek. O dosya
Faz 2 kapısı tarafından sha256 ile mühürlü; sayıları okunabilir kılan şey tam
olarak o filtrenin değişmemiş olması. Filtre yerine **tarama derinliği**
artırıldı — daha çok gerçek tarih, aynı süzgeç.

Bu, eleme oranını da düşürmedi: 400'de %99.25, 1000'de %99.6. Kapı 2'nin
"eleme oranı düştüyse filtre gevşemiş" kuralı bu yüzden ateşlemiyor.

## Kapsam dışı olana dokunulmadı

`heldout_test.sh`, `corpus_cheats.sh` ve `mine_honest.sh` — üçü de kabul testi
tarafından sha256 ile kontrol ediliyor, üçü de değişmedi. Yeni vakalar kendi
dizinlerinde (`reports/phase-2/honest-cases/`), mevcut hiçbir fikstürün üstüne
yazılmadı.

## DOĞRULANMADI

- **Bu 4 vaka bir kol için az.** Cheat kolunda 10 aile var, dürüst kolda 4.
  Express tek repo ve süzgeç sıkı; sayıyı gerçekten büyütmek başka repolar
  (commander, ajv, click) taramak demek — Faz 2'nin kapsamı bu değildi.
- **60 "nondeterministic"in kaçının gerçekten flake, kaçının gerçek
  belirsizlik olduğunu ölçmedim.** Süitin flake oranını karakterize etmedim.
- Vakalardan biri (`fd95b8cb`) express'in yerel, push edilmemiş bir dalının
  HEAD'i. O dal rebase edilirse vaka kaybolur. Express'in HEAD'i Faz 2 için
  dondurulmalı.
- `express` çalışma ağacında iki takipsiz giriş var (`.DS_Store`, `.rabadon/`);
  madenci onlara dokunmuyor ama aynı yolu ekleyen bir commit üzerine yazabilir.
