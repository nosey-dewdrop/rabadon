# F1c · KART 0 — replay korpusunun salt-okunur anlık görüntüsü

Tarih: 2026-08-26. Sebep: cevapçının ölçümü (`reports/kosu/SAPMA-KARARLARI.md` §B.2)
korpusun eridiğini ve kaybın geri alınamaz olduğunu söylüyor: ring oturum başına
200 kayıtla sınırlı (`native/moves.h:63 CAP = 200`), bir oturum zaten dolu, ve
oturum `.json` dosyaları 24 saatte siliniyor (`gate.cpp SESSION_TTL_MS`).

## YEDEĞİN YOLU

    ~/.rabadon-korpus-snapshot-20260826/
      sessions/        ← 46 dosya (34 *.moves.bin, 6 *.json, *.fp.bin, 1 *.moves.jsonl)
      state.json  guard.json  mode.last

Repo DIŞINDA. Repoya commit'lenmedi (§7 local-first, kişisel veri).
Ağaç salt-okunur: `chmod -R a-w`, dizinler `dr-xr-xr-x`, dosyalar `-r--r--r--`.

Kopyalama komutu:

    D=~/.rabadon-korpus-snapshot-20260826
    mkdir -p "$D"
    cp -Rp ~/.rabadon/sessions "$D/sessions"
    cp -p ~/.rabadon/state.json ~/.rabadon/guard.json ~/.rabadon/mode.last "$D/"
    chmod -R a-w "$D"

## SAYILAR — kaynak ve kopya

Sayan komut (her iki dizinde birebir aynı betik, `/tmp/korpus_say.py`; başlık
4096 bayt, kayıt 320 bayt — `native/moves.h` `HDR_BYTES` / `REC_BYTES`):

    python3 /tmp/korpus_say.py ~/.rabadon/sessions
    python3 /tmp/korpus_say.py ~/.rabadon-korpus-snapshot-20260826/sessions

| ölçü | KAYNAK | KOPYA | eşit mi |
|---|---|---|---|
| oturum (`*.moves.bin`) | **34** | **34** | EVET |
| kayıt, diskte duran (fiziksel) | **527** | **527** | EVET |
| kayıt, başlığın `count`'u (şimdiye kadar yazılan) | 666 | 654 | hayır — aşağı bak |
| dolu ring (200/200) | 1 (`286fd71d…`) | 1 (`286fd71d…`) | EVET |
| kayıt zaman aralığı (kayıt `ts` alanı) | 2026-08-22 18:22:14Z → 2026-08-26 03:48:58Z | 2026-08-22 18:22:14Z → 2026-08-26 03:48:01Z | başlangıç aynı |
| dosya mtime aralığı | 2026-08-22 → 2026-08-26 | 2026-08-22 → 2026-08-26 | EVET |

**Durma koşulu tetiklenmedi:** kart 0'ın şartı "kaynakla kopyanın SAYISI eşit"
idi — 34 = 34 oturum, 527 = 527 kayıt. EŞİT.

Tek satır sayı komutu (SAPMA-KARARLARI'nın kullandığı biçim, kopyanın üstünde):

    for f in ~/.rabadon-korpus-snapshot-20260826/sessions/*.moves.bin; do \
      echo $(( ($(stat -f%z "$f")-4096)/320 )); done | paste -sd+ - | bc
    → 527

    ls ~/.rabadon-korpus-snapshot-20260826/sessions/*.moves.bin | wc -l
    → 34

Bayt eşitliği (kopyalama anında):

    cat ~/.rabadon/sessions/*.moves.bin | wc -c              → 307904
    cat $D/sessions/*.moves.bin | wc -c                      → 307904

## KART DIŞI, AMA ÖNEMLİ — dökülüyor (CLAUDE.md §5.5)

1. **139 hamle ZATEN KAYBOLMUŞ, yedekten önce.** Başlıkların `count` toplamı
   kaynakta **666**, diskte duran kayıt **527**. Fark, dolu ring'in
   (`286fd71d…`, `count=339`, saklanan 200) sessizce üzerine yazdığı
   **139 hamledir**. Yedek bunu geri getirmiyor; yedek yalnız kalanı donduruyor.
   Yani cevapçının "eriyor" teşhisi doğru ve erime çoktan başlamış.
2. **Dolu ring, bu koşuyu koşan oturumun kendisi.** `286fd71d…` yedek anından
   sonra da yazmaya devam etti (kopya `count=327` → kaynak `count=339`,
   12 hamle 3 dakikada). Yani **bu koşu her dakika korpusun en eski ucunu
   yiyor.** F2 replay'i bu oturumdan sonra koşarsa daha az veri bulur.
3. Aynı sebeple kaynak ile kopya arasında **tek bir dosya** hash'i farklı
   (`286fd71d…`, canlı oturum); diğer 33 dosya bit-bit aynı. Kanıt:
   `for f in *.moves.bin; do shasum karşılaştır; done` → tek DIFF satırı.
4. Diskte **34 `.moves.bin` ama yalnız 6 `.json`** var — 24 saatlik TTL'in
   çalıştığının doğrudan gözlemi. Yedek 6 `.json`'u da aldı.
5. `~/.rabadon/spool/` (60 dosya, 30 günlük SIGNAL/STEP kayıtları) **yedeğe
   ALINMADI** — kart korpusu `*.moves.bin` diye tanımladı ve spool ayrı bir
   budama takviminde (30 gün). Toplam `~/.rabadon` 73 MB. İstenirse ayrıca
   alınmalı; DOĞRULANMADI: spool'un bugünkü en eski tarihi ölçülmedi.
6. `.moves.jsonl` uzantılı **tek** dosya var (`82b5b921…`) — eski/başka bir
   format; sayıma girmedi, yedeğe girdi.

## GÖREMEDİĞİM

- Yedeğin başka bir makinede okunabilirliği (tek makine var).
- Ring'in ileride ne kadar hızlı döneceği (hamle/saat oranı ölçülmedi).
- Spool budama takviminin bugün nereye geldiği.
