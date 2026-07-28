# rabadon — HISTORY (arşiv)

CLAUDE.md kısa kalsın diye eski session logları buraya taşındı. **Tam metin git geçmişinde** (`git log -p CLAUDE.md`, 28.07 öncesi commit'ler). Aşağısı sadece kaybolmaması gereken kalıcı gerçekler.

## Kalıcı teşhis (Session 7, 22-ajanlık workflow, adversarially doğrulandı)
- Gerçekten çalışan TEK parça = deterministik gate (native + eski hooks/gate.mjs). ~15 gerçek yakalama, çoğu stitchu'da.
- YC'ye satılan gerisi boştu, kanıtla: onarım motoru hiçbir şeyi onarmadı (`repairs accepted: 0` her projede); reliability runtime kütüphanesi (core/rabadon.mjs, wrap.mjs) orphan (kendi 20 projesi bile import etmiyor); `rabadon do` şablon, planlayıcı kör; goal-drift bayrağı 1691 spool olayında bir kez ateşlenmedi.
- 53/53 test yeşildi ama deterministik %20'yi test ediyordu; değer taşıyan %80 (plan/onarım/drift kalitesi) test edilmiyordu.

## Ne kuruldu (native motor, hepsi C++, test yeşil)
- gate (hot+cold+PostToolUse+push-gate), drift (ölçülü yön kontrolü), stats (JS'e byte-identical), verify, loop, do.
- Bench (`make bench`): native gate ~2.1ms vs node ~99ms.
- **Güvenlik:** SIGPIPE fail-open kapandı — ölü watcher socket'i artık bloğu allow'a çeviremez (commit 6e978c9, 10/10).

## Ne SAPMAYDI (28.07 gecesi, 3 saat yakıldı)
Bütün gece mevcut gate/JS motoru C++'a port edildi ("G1: tek binary, JS emekli"). Gerçek mühendislikti AMA Damla'nın istediği "gören yarı" (langfuse ligi gözlemlenebilirlik) DEĞİLDİ; GitHub'da hiçbir şey kımıldamadı. Ders CLAUDE.md'nin başına yazıldı.

## Landing
index.html DAMLA ONAYLI (Temporal referanslı, Space Grotesk 300, antrasit). Dokunma. Canlı: https://nosey-dewdrop.github.io/rabadon/

## 4 acı (lansman postu — gerçek spec)
1. Routing değerli zamanı çalıyor. 2. Pipeline'lar sessizce kırılıyor, checkler yanlış. 3. Loop'lar durmuyor, token yakıyor. 4. Pipeline amacını kaybediyor (drift). Kaynak: `icerik/dewrites_verified.md` → "rabadon lansman postu" (22.07).
