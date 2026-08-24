# C.0 ÖN KONTROL — 2026-08-24

Makine: darwin 24.2.0 (arm64), uid 501.
Worktree: `/Users/damummyphus/damla_projects_2026/rabadon-kosu2`, branch `kosu2`,
kök kopya `/Users/damummyphus/damla_projects_2026/rabadon` (main).

## Sonuç: YEŞİL — döngü başlatılabilir

| # | Kontrol | Sonuç | Kanıt |
|---|---|---|---|
| 1 | `git push --dry-run` credential sormadan geçiyor mu? | YEŞİL | `git push -u --dry-run origin kosu2` → rc=0, `* [new branch] kosu2 -> kosu2`. Sonra gerçek `git push -u origin kosu2` yapıldı; upstream `origin/kosu2` kuruldu. |
| 2 | `GIT_TERMINAL_PROMPT=0` altında test komutu asılmadan dönüyor mu? | YEŞİL | `timeout 900 make test </dev/null` → **rc=0**, 4286 satır, son blok `identity: 37 passed, 0 failed`. Ham log koşu dışı: `/tmp/maketest.log`. |
| 3 | python3 var mı? | YEŞİL | `Python 3.14.6 (Clang 17.0.0)`. kos.sh'in stream-json ayrıştırıcısı bu yorumlayıcıyla koşacak. |
| 4 | `claude --version` kaydedildi mi, auto-update kapalı mı? | YEŞİL | **2.1.172 (Claude Code)** — koşu boyunca sabit. kos.sh `export DISABLE_AUTOUPDATER=1` ile başlıyor. |

## Ön kontrolde ÇIKAN İKİ KIRMIZI (düzeltildi, commit'li)

**1. `timeout` macOS'ta YOK.** BSD userland'de GNU `timeout` bulunmaz.
Shim olmadan kos.sh'teki her `timeout ...` çağrısı `command not found` (rc=127)
ile dönerdi. Sonuç sessiz değil, YANLIŞ bir koşu olurdu:
- `timeout 900 claude -p "$(cat docs/DEGERLENDIREN.md)"` hiç koşmaz → her turda
  `karar_ham` boş → döngü sonsuz "değerlendiren boş — 15 dk" beklemesine girer,
  `i` her seferinde geri alındığı için ilerleme sıfır;
- `pusla()` her turda push'u başarısız sayar → PUSH-HATA.log şişer;
- watchdog'un `timeout 10 find` nabzı ölür.

Düzeltme: `brew install coreutils` (GNU coreutils 9.11 → `gtimeout`), ve kos.sh'in
başına shim: `timeout` yoksa `gtimeout`a delege eder, ikisi de yoksa **rc=2 ile
durur** (sessizce yanlış koşmaz). Shim üç davranışta doğrulandı:
`timeout 2 sleep 10` → rc=**124** (GNU semantiği), boru içinde rc=0, heredoc'lu
`python3 -` çağrısında rc=0.

**2. `date -Is` BSD date'te YOK.** `pusla()`'nın PUSH-HATA damgası hata verirdi.
`date +%Y-%m-%dT%H:%M:%S%z` ile değiştirildi (GNU'da da aynı çıktıyı verir).

Her iki düzeltme hem `scripts/kos.sh`'e hem **KOSU-RABADON-2.md §B2 kod bloğuna**
işlendi; doc ile dosya `diff` ile birebir aynı doğrulandı. (Doc "tek kaynak"tır —
sadece scripti düzeltseydim, sonraki oturum B2'yi birebir yeniden yazınca hata
geri gelirdi.)

## Sorulmadı ama önemli — döküm

- **`df -Pi` macOS'ta yanlış sütun okuyor, ama güvenli yöne.** B2'nin öngördüğü
  gibi: mac'te `$4` inode değil boş blok sayısı (ölçüm: `3068648` iused /
  `1710590080` ifree). Yani inode koruması mac'te **pasif**, yanlış alarm üretmiyor.
  Blok ve /tmp kontrolleri çalışıyor. Şu an boş: kök disk 342 GB.
- **R7 soket yolu tavanı sorun değil.** `/tmp/rabadon-501.sock` = 21 bayt,
  macOS `sun_path` tavanı 104. Worktree yolu derin olsa da soket repo dışında.
- **Rabadon kapısı BAĞLANMADI** (B1.5 gereği: smoke + 5 temiz tur sonrası,
  observe modda, sarmalayıcıyla). Bu oturum hiçbir hook ayarına dokunmadı.
- **`DISABLE_AUTOUPDATER` global `settings.json`'a YAZILMADI** — bilerek. Damla'nın
  diğer oturumlarını etkilememesi için yalnız kos.sh'in kendi ortamına export edildi;
  koşu bitince iz kalmaz. Kaynak: code.claude.com/docs/en/setup.md, "Disable auto-updates";
  aynı belge auto-update'in `-p` koşularında da işlediğini söylüyor.
- **DOĞRULANMADI:** `DISABLE_AUTOUPDATER=1`'in 2.1.172'de gerçekten güncellemeyi
  durdurduğu belgeye dayanıyor, çalıştırılarak kanıtlanmadı (kanıtlamak için
  günler süren bir gözlem gerekirdi). Koşu sonunda `claude --version` yeniden
  bakılırsa sürüm sabitliği fiilen doğrulanmış olur.
- **DOĞRULANMADI:** B6 smoke testinin hiçbir maddesi bu oturumda koşulmadı —
  tam çevrim, OPERATÖR yolu, tekrar freni, watchdog tatbikatı döngünün kendi
  ilk işidir. "Kurulu ama dönmemiş döngü yok hükmündedir" (belge girişi).
- `make test` bu oturumda **bir kez** koştu ve yeşildi; bu R turlarının kabul
  betiklerinin yerine geçmez (`reports/R7/accept.sh` hâlâ kırmızı, A1).

## Kurulan şeyler (commit'ler)

- `d1a2c57` — KOSU-RABADON-2.md + scripts/kos.sh + docs/DEGERLENDIREN.md (§B2/§B3'ten birebir)
- `30d5cbb` — timeout shim + BSD date düzeltmesi (script ve doc birlikte)
- `kosu2` worktree: `git worktree add -b kosu2 ../rabadon-kosu2 main`

## Başlatma (operatör)

```
cd /Users/damummyphus/damla_projects_2026/rabadon-kosu2
tmux new -d -s rabadon scripts/kos.sh
```
İlk çevrimler B6 smoke testidir. Sonrası: `reports/kosu/OPERATOR.md`'ye
`CEVAP: ...` satırları + en sona tek başına `ONAY`.
