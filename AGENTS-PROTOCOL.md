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

Kontrol: faz sonunda `git log --oneline accept.sh` tek commit göstermeli, ve o
commit uygulama commit'lerinden önce olmalı. Değilse faz geçersiz.

### Kapı 2 — hedeflenen sayı raporlanan sayı değildir

Ajana "N tane üret" hedefi verilmez. Verilen hedef: **filtreyi uygula, sonucu
raporla.** Eleme sayıları zorunlu alan.

Şüphe kuralları:
- sıfır eleme → otomatik ret, filtre çalışmıyor demektir
- eleme oranı bir önceki koşudan %50'den fazla düştüyse → filtre değişmiş,
  `git diff` ile ispatlanmalı
- vaka sayısı hedefe tam oturuyorsa (tam 40) → şüpheli, gerçek dağılım yuvarlak
  sayı vermez

### Kapı 3 — test ve fikstür dosyaları mühürlü

Faz başlamadan:

```sh
find . -path ./node_modules -prune -o \
  \( -name '*_test.sh' -o -path './test/*' -o -name 'accept.sh' \
     -o -name 'corpus_*.sh' -o -name 'heldout_test.sh' \) -print \
  | sort | xargs sha256sum > reports/phase-N/locks.txt
```

Faz sonunda aynı komut, `diff` ile karşılaştır. Hash değiştiyse:
faz **reddedilir**, sebebi `discards.txt`'e yazılır. Test değiştirmek
gerekiyorsa ayrı bir commit, ayrı gerekçe, insan onayı.

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

### Faz 0 — korpusu git'e al
**Kapsam:** `/tmp/cheat` → `rabadon-corpus` reposu. Pinlenmiş commit SHA'ları +
`fetch.sh`. `corpus_cheats.sh` oradan okusun.
**Kapsam dışı:** `native/*.cpp`, `native/*.h`. Tek satır C++ değişmeyecek.
**Kabul:** temiz makinede `fetch.sh && corpus_cheats.sh` → 10 aile, 10 refused.
**Rapor:** her checkout'un SHA'sı ve boyutu.
**Durma:** bir checkout çekilemiyorsa dur, atlama.

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
**Rapor:** taranan commit, elenen (şekil / kırmızıya dönmedi / flaky), kalan.
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
diff reports/phase-*/locks.txt.before reports/phase-*/locks.txt.after
for p in reports/phase-*/accept.sh; do bash "$p" || echo "FAIL $p"; done
rabadon audit
```

Üçüncüsü önemli: defter kendi kendini doğrulamıyorsa gecede yazılan
hiçbir sayıya güvenilmez.
