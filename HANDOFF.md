# rabadon — MÜHÜRLÜ HANDOFF (29.07)

> Sonraki session bunu SIFIRDAN çözmesin. Kanun: ~/.claude/CLAUDE.md §0 + repo CLAUDE.md.

════════════════════════════════════════════════════════════════
0. İŞE YARAMA ŞARTI (HER ŞEYİN ÜSTÜNDE)
════════════════════════════════════════════════════════════════
Çıktı GERÇEKTEN çalışan, işe yarar bir şey olacak. "test yeşil / gösterdim /
kaydettim / özet" = ÇIKTI DEĞİL. Ölçü: Damla'nın parmakla gösterebileceği tek
cümle — "rabadon, agent'ımın DERİN ve ufak bir bozulmasını, ben fark etmeden,
olduğu AN yakaladı, tamir etti, ve bana Langfuse gibi detaylı raporladı;
10. adım rezil olmadı, param+zamanım cepte."

KOLAY YOLA KAÇMAK YASAK: dashboard, observe-only, cost/token raporu TEK BAŞINA,
lens'i genişletme, iç refactor, JS→native port. Hiçbiri ürün değil. Bugün biri
"göster"e kaçtı, Damla Claude Code'u bırakma eşiğine geldi. Ürün TEK şey:
YAKALA + TAMİR ET + TAMİRİ KANITLA + Langfuse-grade RAPORLA.

════════════════════════════════════════════════════════════════
1. VİZYON (Damla'nın kendi sözü — sapma)
════════════════════════════════════════════════════════════════
10 adımlık iş, aralarda kapılar. Bela büyük kapıda değil: 3. adımın 3.24'ünde —
KAPI OLMAYAN ufacık, derin bir yerde. O hata katlana katlana 10. adımı rezil
eder; Damla saat+para yakıp şaşırır. rabadon o hatayı DOĞDUĞU AN yakalamalı,
katlanmadan tamir etmeli.
KİLİT: "her yere kapı koy" ÇÖZÜM DEĞİL (sonsuz gerileme; hata hep gate'siz
aralıkta). Çözüm = HEP-AÇIK AĞ + DRIFT:
  • her tool çağrısından SONRA projenin VAR OLAN doğrularını koş (test/tip/build)
    — el ile kapı yok, ağ her yerde hep açık; hata bir doğruya değdiği AN yakalanır.
  • drift: hiçbir testi kırmayan sinsi sapmayı yön ölçerek flag'le.
Dürüst sınır: hiçbir doğruyu kırmayan tamamen sessiz hata deterministik
yakalanamaz — ABARTMA. Kazanç: İLK doğru-ihlalinde yakalamak (10. adımdan çok önce).

KONUMLANMA: rabadon = Langfuse'un ÜSTKÜMESİ, "yerel Langfuse" DEĞİL.
  gör (Langfuse-grade detaylı trace, SIFIR enstrümantasyon — transcript zaten diskte)
  + DURDUR + DÜZELT + "düzelttim de". Langfuse sadece OKUR/puanlar (LLM-judge,
  olasılıksal, SDK gömdürür). rabadon yolun İÇİNDE durur+tamir eder, hakemi
  senin GERÇEK testin (deterministik yer-doğrusu). Kategori: kendini-iyileştiren
  agent runtime. O Instagram "AI Bug Raporlama" = weekend wrapper (LLM'i çıkar,
  hiçbir şey kalmaz); rabadon = LLM'i çıkar, hakem+gate+repair+ledger kalır.

════════════════════════════════════════════════════════════════
2. NE KANITLANDI (buradan başla, tekrar keşfetme)
════════════════════════════════════════════════════════════════
İLK İŞ: `./native/repair_proof.sh` koş, iki senaryoyu gözünle gör (commit c5cfaec).
  • honest: kırık testli repo → gate YAKALAR → loop tamir → hakem GERÇEK test
    yeşil olduğu için kabul → REPAIR_OK → repairs accepted: 1 (tarihte ilk gerçek).
  • cheat: proposer testi neuter'layıp sahte pass basar → forbidden-sha yakalar →
    REPAIR_FAIL → fail-closed, reddedilir → repairs accepted: 0.
MOAT: hakem (native/verify.cpp) proposer'dan AYRI binary, kandırılamaz.
LENS bitti (usage.h paylaşımlı byte-exact metre + lens.cpp + lens_test.sh, make
test yeşil, gate refactor byte-identical) — AMA tek başına cost tablosu = yanlış
KAPSAM. Doğrusu: bu metre, aşağıdaki fused raporun içinde yaşar.
Motor: loop.cpp (runner+repair) + verify.cpp (hakem: testsuite/differential/
forbidden/cmd/fileExists/fileContains) + gate.cpp (HER tool çağrısı, post-tool
suite) + drift.cpp (sapma) + usage.h (token/$ metre). OKU.

════════════════════════════════════════════════════════════════
3. BUGÜNKÜ TEK HEDEF: OYUNCAK'tan GERÇEK'e + Langfuse-grade rapor
════════════════════════════════════════════════════════════════
Gerçek repo + gerçek LLM proposer (claude -p) + KAPI KONMAMIŞ derin bir hata →
hep-açık ağ (post-tool gerçek test) o AN yakalasın → loop katlanmadan tamir
etsin → hakem doğrulasın → sahte/yarım fix reddedilsin.
ÇIKTI = DÜZ METİN DEĞİL. Damla'nın açık talebi: Langfuse kadar DETAYLI rapor.
Hedef rapor (veri %100 deterministik olarak transcript+ledger'da VAR; kalan =
sunum, wrapper değil):

  rabadon trace — session <id> · <proje> · <model> · <süre> · <token> · $<maliyet> · <tool>
  görev: "<agent'a verilen iş>"
  ▸ 1  <adım>                 ✓ pass      <tool> <token> $<..> <süre>
  ▾ 3  <adım>                 ⚠ YAKALANDI <tool> <token> $<..> <süre>
     ├ 3.1 ...                ✓
     ├ 3.2 <alt-adım>         ✗ <hata>   ◀── gate BURADA yakaladı (o AN)
     │      testsuite RED (<test adı>) → REPAIR → düzeltildi → GERÇEK test GREEN → REPAIR_OK ✓
     └ 3.3 ...                ✓ tamirden sonra yeşil
  ──────────────────────────────────────────
  YAKALANAN N (adım 3.2, 10'a varmadan)  TAMİR N  REDDEDİLEN sahte N
  kurtarılan: adım 4–10 boşa gitmedi (~$X, ~Y saat cepte)   ◀── Langfuse'da YOK

Hiyerarşi: rabadon koşuyu sürerken (plan adımları) NET; serbest agent
session'ında tool-call zaman çizgisi + catch/fix işaretleri (kırılım türetilir).
Çıktı GitHub'da görünür, Damla GÖRÜR.

════════════════════════════════════════════════════════════════
4. TUZAKLAR / KURALLAR
════════════════════════════════════════════════════════════════
• claude -p subprocess: BOUNDED (timeout), child'da RABADON_OFF=1 (recursion),
  RABADON_MAX_REPAIRS küçük. Askıda/gece-boyu koşma YOK.
• Spool'u İZOLE et (RABADON_DIR=temp) — gerçek ledger'ı kirletme (repair_proof.sh örnek).
• bin/rabadon.mjs anti-path — DOKUNMA (gate edit'i bloklar). index.html DAMLA
  ONAYLI — DOKUNMA. Metre işine (lens/usage.h) GERİ DÖNME, genişletme.
• max 90dk / max 3 repair → DUR, çalışan çıktıyı göster, ONAY bekle. KANITLA,
  iddia etme. Bitince commit+push (lowercase İng, co-author ASLA).

════════════════════════════════════════════════════════════════
5. AÇIK STRATEJİ SORUSU (Damla 29.07 — GTM, henüz cevaplanmadı)
════════════════════════════════════════════════════════════════
"Müşteriler bunu KULLANACAK mı? Üyelik/dağıtım nasıl? we don't know."
Yön hipotezi (araştırma sürüyor): bottoms-up open-core, SIFIR-enstrümantasyon
(tek satır, SDK yok = Langfuse'a karşı asıl avantaj). Adoption merdiveni:
observe (güvenli, düşük korku) → catch/alert → opt-in auto-repair. Paylaşılabilir
trace raporu ("X yakalandı, sana $40/6saat kazandırdı") = dağıtım döngüsü.
Analog: Sentry (hata yakala, bottoms-up, dev) + Snyk (CI guardrail). Langfuse
DEĞİL (sadece observe, zayıf para). Üyelik: free local tek-dev; paid team/cloud
= fleet trace + org policy + alerting; per-seat ya da per-korunan-agent-run.
Risk: "control", "observe"den korkutucu → o yüzden observe modundan gir.
Ve tek-agent değil, çoklu-agent (Cursor/Claude Code/fleet) = şirket olmanın şartı.
