# C.2 ÖN KONTROL — kosu3, 2026-08-25

Makine: darwin 24.2.0 (arm64). Worktree:
`/Users/damummyphus/damla_projects_2026/rabadon-kosu3`, dal `kosu3`
(`git worktree add -b kosu3 ../rabadon-kosu3 kosu2`, kosu2 6f5d301'den).

## Sonuç: YEŞİL — döngü başlatılabilir (ama önce §"Operatöre" oku)

| # | Kontrol | Sonuç | Kanıt |
|---|---|---|---|
| 1 | `git push --dry-run` credential sormadan geçiyor mu? | YEŞİL | `GIT_TERMINAL_PROMPT=0 timeout 120 git push -u --dry-run origin kosu3` → rc=0, `* [new branch] kosu3 -> kosu3`. |
| 2 | `GIT_TERMINAL_PROMPT=0` altında test komutu asılmadan dönüyor mu? | YEŞİL | `scripts/isci.sh onkontrol-make-test make test` → **rc=0**, 424 s, 4328 satır, son blok `identity: 37 passed, 0 failed`. Rapor: `reports/kosu/RAPOR/onkontrol-make-test.md`, ham: `reports/kosu/log/onkontrol-make-test.log` (229 993 bayt). |
| 3 | `python3` var mı? | YEŞİL | `Python 3.14.6`. |
| 4 | `claude --version` kaydedildi mi? | YEŞİL | **2.1.172 (Claude Code)** — koşu 2'nin başındaki sürümle AYNI, yani `DISABLE_AUTOUPDATER=1` bir gün boyunca sürümü sabit tuttu (koşu 2'de DOĞRULANMAMIŞ olan madde artık gözlemle destekli). |
| 5 | (v3) `pgrep -f rabadon \| wc -l` doğru sayı basıyor mu? | YEŞİL | **5** basıyor ve süreçleri isim isim listeliyor (`pgrep -fl`). Karşılaştırma: `pgrep -c rabadon` → BSD usage hatası. A2'nin ölü kontrolü artık canlı. |
| 6 | (v3) `reports/kosu/log/` ve `reports/kosu/RAPOR/` var mı? | YEŞİL | İkisi de kuruldu, `isci.sh` ikisine de yazdı. |
| 7 | `timeout` shim | YEŞİL | `/opt/homebrew/bin/timeout` + `gtimeout` mevcut (koşu 2'de kurulmuştu). |

## v3'ün üç farkı — kurulum kanıtı (B6'nın YERİNE GEÇMEZ)

- **isci.sh çalışıyor.** 4328 satır / 230 KB ham çıktı üreten bir iş koştu;
  yapanın stdout'una giren tek şey `reports/kosu/RAPOR/onkontrol-make-test.md (rc=0)`
  satırı oldu. Rapor 12 satır tavanında (ölçüm: 10 satır); kırpmayı SÜREÇ yapıyor.
- **Değerlendiren girdisi ölçüldü: 22 470 bayt** (< 30 720 tavanı). Aynı anda
  koşu 2 usulü girdi (yalnız `KOSU-RABADON-2.md` + son turun çıktısı) 50 451 bayt.
  Fark bu turda ~2,2×; koşu 2'nin tipik turlarında ~200 KB'ydi.
- **KOSMADI bloğu** kod olarak kondu (`scripts/kos.sh`, DEVİR arşivleme + tavan),
  ama **KOŞULARAK KANITLANMADI** — döngünün ilk turunun işi (B6.3).

## Sorulmadı ama önemli — döküm

- **KOŞU 2'NİN SÜRÜCÜSÜ HÂLÂ CANLI.** `tmux ls` → oturum `rabadon`, 24 Ağu
  16:48'de açılmış, PID 2372, **9 sa 19 dk**tır ayakta. `scripts/kos.sh` (kosu2)
  ONAY mührünü bekleyen `while ... sleep 300` döngüsünde. Yani
  `rabadon-kosu2/reports/kosu/OPERATOR.md`'ye bugün `ONAY` yazılırsa **koşu 2
  kaldığı yerden koşmaya başlar**. Kosu3 aynı tmux adını kullanamaz. Karar
  operatörün: koşu 2 sonlandırılacak mı, yoksa cevaplanıp bitirilecek mi?
- **İki artık süreç, 2 gün 10 saattir ayakta:** PID 85131 `rabadon.mjs ui --help`,
  PID 85359 `rabadon.mjs watch --help` (kök `/rabadon` kopyasından). B1.10'un
  yasakladığı türden yetimler; 2b ölçümlerinin alındığı makinede duruyorlardı.
  Öldürmek geri dönüşsüz sayılmadı ama **operatörün kararı** — bu oturum
  DOKUNMADI. Ayrıca `native/rabadon-gate` (PID 32908, 58 sn) canlı.
- **§A ile gerçek arasında sapma vardı ve DURUM.md gerçeğe göre yazıldı.**
  KOSU-RABADON-3.md §A2 "iki kusur DÜZELTİLMEDİ" diyor; oysa ikisi de kosu2
  tur 22'de düzeltilmiş (`10ec3f5` pgrep, `6097bb9` olc_2b hükmü) ve 2b'nin
  gözlem sayısı 5 → 8 olmuş. Belgeye NOT düşüldü, DURUM.md kanıta göre yazıldı
  (kanıt belgeyi yener — CLAUDE.md).
- **§A1'in 5b ön-kayıt sapması AÇIK ve bu oturumda yeniden doğrulandı:**
  `ab_run.jsonl` 8 kayıt = kol başına 4 görev; `ON-KAYIT.md` N = 6 × 2 diyor;
  `accept.sh` 5b kol başına `>=2` arıyor. Düzeltme yapılmadı (turlara başlama
  emri yoktu) — ilk R işi bu.
- **İşçi logları git'e GİRMİYOR:** `.gitignore:1` `*.log` onları eliyor
  (`git check-ignore -v reports/kosu/log/onkontrol-make-test.log`). Yani ham
  kanıt YEREL kalır; `RAPOR/*.md` commit'lenir. Uzaktan izleyen biri işçinin ham
  çıktısını göremez — bilinçli kabul, ama DEVİR'de "HAM: <yol>" yazan satırın
  bu dosyalar için yalnız yerelde çözüleceği unutulmamalı.
- **Rabadon kapısı BAĞLANMADI** (talimat gereği). Hiçbir hook ayarına dokunulmadı.
- **`reports/kosu/son.talimat` SİLİNDİ** — kosu2'den miras kalan "OPERATOR.md'deki
  CEVAP satırlarını uygula" cümlesiydi; durmuş olsaydı kosu3 ilk turda B6 yerine
  onu koşardı.
- Tur numarası kosu2'den devam eder: `reports/kosu/` içinde 22 `.out` var,
  ilk kosu3 turu **23** olacak. Dosyalar monoton, üzerine yazılmaz.
- **DOĞRULANMADI:** B6'nın üç maddesinin hiçbiri DÖNGÜ içinde koşulmadı; kurulum
  kanıtı ile kabul kanıtı ayrı şeylerdir. "Kurulu ama dönmemiş döngü yok
  hükmündedir."
- **DOĞRULANMADI:** 30 KB freninin OPERATÖR durağı ve DEVİR arşivleme yolu
  çalıştırılmadı; yalnız `bash -n` sözdizimi geçti.

## Kurulan şeyler

- `KOSU-RABADON-3.md` (repo kökü, §A'ya 25.08 notu düşülmüş hâliyle)
- `scripts/kos.sh` — B2'nin üç farkı: transkriptsiz `girdi_yaz()` + ölçüm,
  DEVİR arşivleme/tavan/KOSMADI, v3 varsayılan talimatı; etiketler kosu3
- `scripts/isci.sh` — yeni (B1.2/B1.3)
- `docs/DEGERLENDIREN.md` — B3 ekleri (transkript yok, DEVİR sayısı, isci.sh)
- `reports/kosu/DURUM.md` — 49 satır, §A'nın kanıtla güncellenmiş türevi

## Başlatma (operatör)

```
cd /Users/damummyphus/damla_projects_2026/rabadon-kosu3
tmux new -d -s rabadon3 scripts/kos.sh      # 'rabadon' adı koşu 2'de MEŞGUL
```
İlk çevrimler B6'nın üç maddesidir. Sonrası: `reports/kosu/OPERATOR.md`'ye
`CEVAP: ...` satırları + en sona tek başına `ONAY`.
