# rabadon — MÜHÜRLÜ HANDOFF (29.07 geç)

> Sonraki session bunu SIFIRDAN çözmesin. Kanun: ~/.claude/CLAUDE.md §0 + repo CLAUDE.md.

════════════════════════════════════════════════════════════════
0. İŞE YARAMA ŞARTI (HER ŞEYİN ÜSTÜNDE)
════════════════════════════════════════════════════════════════
Çıktı GERÇEKTEN çalışan, işe yarar bir şey olacak. "test yeşil / gösterdim /
kaydettim / özet" = ÇIKTI DEĞİL. Ölçü: Damla'nın parmakla gösterebileceği tek
cümle — "rabadon, agent'ımın DERİN ve ufak bir bozulmasını, ben fark etmeden,
olduğu AN yakaladı, tamir etti, ve bana Langfuse gibi detaylı raporladı; 10.
adım rezil olmadı, param+zamanım cepte."
KOLAY YOLA KAÇMAK YASAK: dashboard, observe-only, cost/token raporu TEK BAŞINA,
lens genişletme, iç refactor, JS→native port. Ürün TEK şey:
YAKALA + TAMİR ET + TAMİRİ KANITLA + Langfuse-grade RAPORLA.

════════════════════════════════════════════════════════════════
1. İLK 10 DAKİKA (yap, atlama)
════════════════════════════════════════════════════════════════
Üç proof'u KOŞ, gözünle gör (hepsi izole spool, Damla'nın ledger'ını kirletmez):
  • ./native/repair_proof.sh        — scripted moat (honest REPAIR_OK / cheat REPAIR_FAIL)
  • ./native/repair_proof_llm.sh    — GERÇEK claude -p toy bug'ı kapatır (REPAIR_OK, ~21s)
  • ./native/regression_net_demo.sh — STEP C: gerçek modül + derin off-by-one, ağ
      check 5/6'da yakalar, canlı claude -p tamir eder, sahte fix forbidden-sha ile red
OKU: native/loop.cpp (runner+repair) · native/verify.cpp (hakem: testsuite/
differential/forbidden/cmd/fileExists/fileContains) · native/gate.cpp (hep-açık
yüzey + default-off + --statusline/--on/--off/--toggle) · native/drift.cpp ·
native/usage.h (byte-exact token/$ metre) · native/llm-proposer.sh (bounded claude -p).

════════════════════════════════════════════════════════════════
2. VİZYON (Damla'nın sözü — sapma yok)
════════════════════════════════════════════════════════════════
10 adımlık iş, aralarda kapılar. Bela büyük kapıda değil: 3. adımın 3.24'ünde —
KAPI OLMAYAN ufacık derin bir yer. rabadon o hatayı DOĞDUĞU AN yakalar, katlanmadan
tamir eder. Çözüm = HEP-AÇIK AĞ (her tool sonrası projenin VAR OLAN doğrularını koş)
+ DRIFT. "Her yere kapı koy" ÇÖZÜM DEĞİL. Dürüst sınır: hiçbir doğruyu kırmayan
tamamen sessiz hata deterministik yakalanamaz — ABARTMA.
KONUMLANMA: rabadon = Langfuse'un ÜSTKÜMESİ ("otonom agent koşuları için Sentry").
gör (SIFIR enstrümantasyon, transcript zaten diskte) + DURDUR + DÜZELT + "düzelttim
de". Moat = yolun içindeki DETERMİNİSTİK HAKEM (projenin GERÇEK testini koşar) —
LLM'i çıkar, hakem+gate+repair+ledger kalır.

════════════════════════════════════════════════════════════════
3. NE KANITLANDI (28-29.07 — tekrar keşfetme)
════════════════════════════════════════════════════════════════
• LENS + usage.h byte-exact metre bitti (tek başına cost tablosu = yanlış kapsam;
  metre fused raporun içinde yaşamalı).
• TAMİR DÖNGÜSÜ KAPANDI (repair_proof.sh, commit c5cfaec): honest→REPAIR_OK,
  cheat→forbidden-sha REPAIR_FAIL. Deterministik, LLM'siz.
• ADIM B (822e769): scripted proposer yerine GERÇEK claude -p — toy bug'ı kapattı,
  hakem gerçek testle kabul, REPAIR_OK. llm-proposer.sh = bounded (RABADON_OFF=1
  recursion guard, wall-clock cap).
• ADIM B2 (e22fdd1): proposer model biter bitmez sonlanıyor (stream-json terminal
  "result" event) — 181s→21s. Süre/maliyet profili artık dürüst (Step D için şart).
• ADIM C (64a10da): gerçek çok-fonksiyonlu modül (statslib) + moving_average'da
  KAPI-KONMAMIŞ off-by-one. Ağ = projenin KENDİ suite'i, check 5/6'da yakaladı
  (mean/variance/median yeşil). Canlı claude -p off-by-one'ı düzeltti (REPAIR_OK);
  sahte fix (testi neuter) forbidden-sha ile REDDEDİLDİ, fail-closed (maskelenmedi).
• DEFAULT-OFF + LAMBA (7ca5f10, 811c0dd, 6615797): rabadon artık DEFAULT KAPALI.
  Global hook'lar duruyor ama ~/.rabadon/enabled yoksa gate dormant. Toggle native:
  `rabadon` (veya prompt'ta `!rabadon`) = çevir; `rabadon status/on/off/stats`.
  /opt/homebrew/bin/rabadon symlink native wrapper'a (rabadon-cli.sh) taşındı,
  watch/do/fleet hâlâ mjs'e delege. Status line native --statusline: AÇIK=lila
  `* rabadon`, KAPALI=gri `* rabadon off` — lamba artık gerçek state'i gösterir.

════════════════════════════════════════════════════════════════
4. SIRADAKİ TEK HEDEF: ADIM D — Langfuse-grade RAPOR renderer
════════════════════════════════════════════════════════════════
Koşunun ÇIKTISI düz metin DEĞİL. `rabadon-trace` diye NATIVE renderer yaz (C++,
mission): izole spool event'leri (RUN_START/STEP_START/CHECK_FAIL/REPAIR_START/
REPAIR_OK/STEP_OK/RUN_DONE) + usage.h token/$ → aşağıdaki iç içe trace. Veri %100
deterministik ledger+transcript'te VAR — kalan = SUNUM, wrapper değil. **EKSTRA LLM
KOŞUSU YOK, ucuz.** regression_net_demo.sh'ın izole spool'unu girdi olarak kullan.

Şablon:
  rabadon trace — session <id> · <proje> · <model> · <süre> · <token> · $<maliyet> · <tool>
  görev: "<agent'a verilen iş>"
  ▸ 1  <adım>              ✓ pass      <tool> <token> $<..> <süre>
  ▾ 3  <adım>              ⚠ YAKALANDI <tool> <token> $<..> <süre>
     ├ 3.2 <alt-adım>      ✗ <hata>   ◀── gate BURADA yakaladı (o AN)
     │      testsuite RED (<test>) → REPAIR → GERÇEK test GREEN → REPAIR_OK ✓
     └ 3.3 ...             ✓ tamirden sonra yeşil
  ──────────────────────────────────────────
  YAKALANAN N (3.2, 10'a varmadan)  TAMİR N  REDDEDİLEN sahte N
  kurtarılan: adım 4–10 boşa gitmedi (~$X, ~Y saat cepte)   ◀── Langfuse'da YOK
Hiyerarşi: plan koşusunda net; serbest session'da tool-call zaman çizgisi +
catch/fix işaretleri (kırılım türetilir) — ABARTMA. Her adım max 90dk/3 repair →
DUR, çalışan çıktıyı Damla'ya göster, ONAY bekle. Commit+push.

════════════════════════════════════════════════════════════════
5. KURALLAR / TUZAKLAR
════════════════════════════════════════════════════════════════
• DEFAULT = PROPOSE-and-hold, silent-apply DEĞİL (GTM riski #1). Hakem gerçek testi
  geçirdiyse uygula; şüpheliyse öner+beklet. Hassasiyet = public benchmark.
• claude -p BOUNDED: child'da RABADON_OFF=1 (recursion), wall-clock cap, spool İZOLE
  (RABADON_DIR=temp). Askıda/gece-boyu koşma YOK. NOT: --allowedTools child'ı GERÇEKTEN
  kısıtlamıyor (B2'de Bash kullandı) — sahte fix'i durduran hakem, tool kısıtı değil.
• bin/rabadon.mjs anti-path — DOKUNMA (sadece rabadon-cli.sh üzerinden delege).
  index.html DAMLA ONAYLI — DOKUNMA. lens/usage.h metre işine GERİ DÖNME.
• promise areas = ^native/ ^Makefile$ ^SPEC.md$ ^README.md$. native/'te kal.
• rabadon şu an DEFAULT KAPALI; geliştirirken açmak istersen `rabadon on`.
• Bitince commit+push (lowercase İng, co-author ASLA).

════════════════════════════════════════════════════════════════
6. GTM (Damla haftaya yatırım arıyor)
════════════════════════════════════════════════════════════════
FİYAT = "doğrulanmış tamir" başına (hakem geçişi = kandırılamaz birim). Konumlanma =
"agent koşuları için Sentry", asla observability. Rakip: Sentry Seer (deterministik
hakem yok). HEDEF SORUSU (session başında cevapla): rabadon neden var? → gözetimsiz
otonom agent koşarken KAPI-KONMAMIŞ derin hatayı katlanmadan YAKALAYIP TAMİR eden ve
tamiri deterministik KANITLAYAN + Langfuse-grade RAPORLAYAN sistem.
