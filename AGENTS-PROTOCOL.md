# rabadon — faz protokolü

Fazlar ayrı ajanlara verilir. Devir konuşmayla değil **dosyayla** yapılır.
Hiçbir ajan bir öncekinin context'ini görmez, iddiasına da güvenmez.

---

## Devir kuralı

Her faz `reports/phase-N/` altına şunları yazar:

- `CLAIM.md` — ne yapıldı, tek sayfa
- `accept.sh` — kabul testi, exit 0 = geçti
- `discards.txt` — elenen/başarısız olan her şey, sebebiyle
- `git log` — commit'ler

Sonraki faz **ilk iş olarak** `accept.sh`'ı temiz bir checkout'ta koşturur.
Geçmezse kendi işine başlamaz, `BLOCKED.md` yazıp durur.

`CLAIM.md` okunur ama kanıt sayılmaz. Kanıt sadece `accept.sh`'ın exit kodu.

---

## Üç kapı

### Kapı 1 — kabul testini uygulayan yazmaz

Faz N'in `accept.sh`'ı, faz N başlamadan **ayrı bir ajan** tarafından yazılır
ve commit'lenir. Uygulayan ajan o dosyaya dokunamaz.

Kontrol: faz sonunda

```sh
git log --oneline -- reports/phase-N/accept.sh
```

tek commit göstermeli, ve o commit uygulama commit'lerinden önce olmalı.
Değilse faz geçersiz. (`--` ve tam yol şart: `git log --oneline accept.sh`
"ambiguous argument" deyip 128 döner — kapı hiç çalışmaz.)

**Kapının bilinen sınırı:** kabul testi fazın kendi ürettiği bir dosyayı
çağırmak zorundaysa, gate'in yarısı uygulayan ajanın elindedir. Faz 0'da somut:
`accept.sh` mühürlü `corpus_cheats.sh`'ı çağırır ama fazın yazdığı `fetch.sh`'ı
da çağırır. O yüzden kabul testleri iddiayı **fazın ürettiği dosyanın
söylediğinden değil, mühürlü aracın çıktısından** okur; fazın getirdiği her dış
girdi (pinlenmiş SHA gibi) Kapı 2 raporunda ayrıca gösterilir.

### Kapı 2 — hedeflenen sayı raporlanan sayı değildir

Ajana "N tane üret" hedefi verilmez. Verilen hedef: **filtreyi uygula, sonucu
raporla.** Eleme sayıları zorunlu alan, **makinenin yazdığı dosyadan** gelir
(`discards.txt`), ajanın anlatısından değil. Toplam yetmez: eleme **sebep sebep**
ayrılır — "uygulanamayan revert"i "yanlış şekil"e yazmak sayıyı doğru, sebebi
yanlış gösterir.

Şüphe kuralları:
- sıfır eleme → otomatik ret, filtre çalışmıyor demektir
- eleme oranı bir önceki koşudan %50'den fazla **düştüyse** → filtre gevşemiş,
  `git diff` ile ispatlanmalı
- eleme oranı %50'den fazla **arttığı halde tutulan vaka da arttıysa** → filtre
  değişmiş, aynı ispat. (Tek yönlü kural, filtreyi gevşetip elemeyi de şişiren
  ajanı kaçırıyordu.)
- koşu bir üst sınıra değdiyse (`max_hit=yes`) → sayı verinin şekli değil,
  sınırın şekli; sınır kaldırılıp yeniden koşulur. Araçlarda vaka üst sınırı
  varsayılan olarak KAPALI. ("Tam 40 şüphelidir" kuralı, aracın kendi
  varsayılanı 40 olduğu için her dolu koşuda ateşliyordu — sınırı aracın
  raporladığı `max_hit` alanı söylüyor artık, yuvarlaklık sezgisi değil.)
- tutulan vaka sayısı bağımsız yeniden sayılabilmeli
  (`find <out> -name case.env | wc -l`), yoksa rapor kanıt değil iddiadır.

### Kapı 3 — test ve fikstür dosyaları mühürlü

Faz başlamadan ve faz bitince:

```sh
bash scripts/seal.sh N before     # faz başlamadan
bash scripts/seal.sh N after      # faz bitince
diff reports/phase-N/locks.txt.before reports/phase-N/locks.txt.after
```

Hash değiştiyse faz **reddedilir**, sebebi `discards.txt`'e yazılır. Test
değiştirmek gerekiyorsa ayrı commit, ayrı gerekçe, insan onayı.

Mühür listesi `scripts/seal.sh` içinde, tek yerde. Elle yazılan `find` deseni
JS süitini (`*.test.mjs`) kaçırıyordu: `core/`, `hooks/`, `ui/`, `demo/`
altındaki 9 test dosyası mühürsüzdü, yani bir ajan onları zayıflatabilir ve faz
sonu diff'i sessiz kalırdı. Mühür artık üç şeyi daha kapsıyor:

- `.rabadon/guard.json` — gate'in kendi yasası
- `site/measured.json` — yayınlanan sayılar
- `reports/scoreboard.tsv` — kayma detektörünün hafızası

Harness dosyaları da mühürlü: `package.json`, `Makefile`, `pytest.ini`,
`CMakeLists.txt`, `conftest.py`.

---

## Her faz promptunun taşıması gereken beş başlık

1. **Kapsam** — ne yapılacak
2. **Kapsam dışı** — hangi dizin/dosyalara dokunulmayacak (ajanı asıl dar
   tutan kısım burası)
3. **Kabul** — hangi komut, hangi exit kodu
4. **Rapor** — hangi sayılar `discards.txt`'e yazılacak
5. **Durma şartı** — hangi durumda `BLOCKED.md` yazıp duracak

---

## Fazlar

### Faz 0 — korpusu git'e al — **BLOKE, 20 Ağu 2026**
**Kapsam:** `/tmp/cheat` → `rabadon-corpus` reposu. Pinlenmiş commit SHA'ları +
`fetch.sh`. `corpus_cheats.sh` oradan okusun.
**Kapsam dışı:** `native/*.cpp`, `native/*.h`. Tek satır C++ değişmeyecek.
**Kabul:** temiz makinede `fetch.sh && corpus_cheats.sh` → 10 aile, 10 refused.
**Rapor:** her checkout'un SHA'sı ve boyutu.
**Durma:** bir checkout çekilemiyorsa dur, atlama.

> Taşınacak şey yok: `/tmp/cheat` makinede yok ve hiç commit'lenmemiş.
> Ayrıntı ve kanıt: `reports/phase-0/BLOCKED.md`. Kabul testi yerinde duruyor ve
> exit 2 ("koşamıyorum") veriyor — yeşile boyanmadı, zorlanmadı.

### Faz 1 — REPAIR sonuç ölçümü
**Kapsam:** her `REPAIR_START` için kapanış + sonuç + tutmadıysa **sınıf**
deftere yazılsın (`REPAIR_FAIL` / `FLAKY` / `test-tamper` / `harness-tamper` /
`proposer-empty` / `timeout`). 22 günlük spool'u geriye dönük tara, dağılımı çıkar.
**Kapsam dışı:** gate kuralları, `guard.json`, ui/.
**Kabul:** `rabadon audit` yeşil + dağılım tablosu `reports/phase-1/` altında.
**Rapor:** sınıflandırılamayan olay sayısı.
**Durma:** eski olaylar sınıflandırılamıyorsa dur — geriye dönük uydurma yok.

> Bu faz gecenin en önemli işi. Tamirin neden tutmadığını bilmeden
> sonraki fazlar kör gider.

### Faz 2 — dürüst kol madenciliği
**Kapsam:** `mine_honest.sh`'ı `native/` altına al, express'te koştur.
**Kapsam dışı:** `heldout_test.sh` ve `corpus_cheats.sh` mühürlü — dokunma.
Yeni vakalar ayrı dosyaya.
**Kabul:** her vaka için kaynak-only revert kırmızı, geri koyunca yeşil —
ikisi de loglanmış.
**Rapor:** `discards.txt`'i araç yazar: taranan, tutulan, ve eleme sebep sebep
(şekil / revert uygulanamadı / checkout başarısız / kırmızıya dönmedi / flaky),
`max_hit` alanıyla birlikte.
**Durma:** eleme sayısı sıfırsa dur — filtre çalışmıyor.

### Faz 3 — kapsam düzeltmesi
**Kapsam:** `netRed` kökle birlikte yazılsın, kök eşleşmezse red-base
ateşlemesin. `project_root()` cwd'ye düştüyse red-base devre dışı.
Check'in üçüncü hali `could-not-run`. Mod katmanlı: env → proje → makine.
`~/.rabadon/enabled` + `mode.last` tek dosyaya insin.
**Kapsam dışı:** repair.cpp, korpus, ui/.
**Kabul:** bir dizin kırmızıyken komşu dizinde ateşlemediğini gösteren yeni test.
**Rapor:** mevcut testlerden kaçı kırıldı ve neden.
**Durma:** mevcut bir test kırılıyorsa dur — silme, zayıflatma.

### Faz 4 — `rabadon check`
**Kapsam:** salt-okunur rapor. Hook kurmaz, `.claude/settings.json`'a dokunmaz,
seansa sıfır byte. Üç bölüm: doğrulandı / yakalandı / maliyet.
**Kapsam dışı:** gate.cpp, repair.cpp. Sadece okuma.
**Kabul:** `rabadon check` boş repoda exit 0 + anlamlı çıktı; `strace`/log ile
hiçbir yazma olmadığı gösterilmiş.
**Rapor:** okunan dosya sayısı, yazılan dosya sayısı (sıfır olmalı).
**Durma:** yazma tespit edilirse dur.

---

## Gece sonu tek kontrol

Sabah şu üçünü koştur, üçü de yeşil değilse gece geçersiz sayılır:

```sh
for d in reports/phase-*/; do
  [ -f "$d/locks.txt.before" ] && diff "$d/locks.txt.before" "$d/locks.txt.after"
done
for p in reports/phase-*/accept.sh; do bash "$p" || echo "FAIL $p"; done
rabadon audit
```

Üçüncüsü önemli: defter kendi kendini doğrulamıyorsa gecede yazılan
hiçbir sayıya güvenilmez.

Not: mühür dosyalarının adı `locks.txt.before` / `locks.txt.after`. Kapı 3
eskiden tek bir `locks.txt` üretiyordu, yani buradaki `diff` her sabah "böyle
bir dosya yok" diyordu — kontrol koşuyor görünüp hiçbir şey kontrol etmiyordu.
`scripts/seal.sh` ikisini de doğru adla yazar.
