# R7 — TEŞHİS

Bu dosya birikimlidir. Yeni blok EN ALTA eklenir, üstüne yazılmaz.

## teşhis 1 — 2026-08-24 (tur 1, yapan) — daemon yok, soket kuralı hiçbir kaynakta yok

**KAPSAM.** `native/`, `core/`, `scripts/` altındaki tüm kaynaklar; ayrıca
`rabadon-gated`, `RABADON_GATED_SOCK`, `XDG_RUNTIME_DIR` için repo geneli
(`.git` hariç) tarandı. Aşağıdaki her satır bir dosya:satır referansı taşır.

### 1. `rabadon-gated` diye bir şey YOK — hiçbir biçimde

- Binary yok: `native/rabadon-gated` mevcut değil.
- Kaynak yok: `accept.sh`'in aradığı `native/gated.cpp`, `native/daemon.cpp`,
  `native/gated.h` üçünün hiçbiri dizinde yok.
- Derleme hedefi yok: `Makefile:12` `all:` listesinde 19 binary var,
  `rabadon-gated` bunların arasında değil; `Makefile:932` `clean:` listesinde
  de yok. Yani unutulmuş bir hedef değil, **hiç yazılmamış**.
- İsim yalnız BELGEDE geçiyor: `KOSU-RABADON-2.md:50`, `KOSU-RABADON.md:323`
  ve `reports/R7/accept.sh` (47, 69, 72, 107, 115). Tek bir kaynak dosyada
  bile geçmiyor.

R7'nin hız yarısı %0'dır. Bu bir regresyon değil, hiç başlamamış iştir —
`KOSU-RABADON-2.md:48` ("hiç başlamadı, accept.sh kırmızı") ile birebir uyumlu.

### 2. `RABADON_GATED_SOCK` hiçbir kaynakta geçmiyor → ince istemci yok

Env değişkeni yalnız `reports/R7/accept.sh:91,109,...` içinde ve talimat
metinlerinde var. `native/gate.cpp` bu adı hiç okumuyor. `accept.sh` GOAL 1c
(`gate.cpp` / `gated_client.h` / `client.h` içinde soket adı arar) bu yüzden
kırmızıdır ve öyle olmalıdır: daemon'a uzanan bir istemci yolu yok.

Bunun bir yan sonucu var ve accept.sh bunu kendi yorumunda zaten söylüyor
(GOAL 3): istemci yokken "daemon kapalı" durumu bugünkü davranıştan
**yapısal olarak** ayırt edilemez, yani fail-SAME karşılaştırması
kurgu gereği başarısız olamaz. Kırmızı doğru sonuçtur; yeşil olsaydı
vakum-yeşil olurdu.

### 3. Var olan soketler — üçü de R7 daemon'ı DEĞİL

`bind(2)` / `accept(2)` / `listen(2)` / `AF_UNIX` taraması üç gerçek yer verdi:

| kaynak | rol | aile | yol |
|---|---|---|---|
| `native/gate.cpp:714-724` `open_sock()` | **İSTEMCİ** (`connect` var, `bind`/`listen` YOK) | AF_UNIX | `native/gate.cpp:2718` → `rdir + "/rabadon.sock"` |
| `core/bus.mjs:263-283` `bind()` | **SUNUCU** (`net.createServer` + `server.listen`) | AF_UNIX | `core/bus.mjs:30` → `$RABADON_SOCK` ya da `$RABADON_DIR/rabadon.sock` |
| `native/serve.cpp:477-498` | sunucu | **AF_INET** (loopback TCP) | port; `rabadon serve` HTTP store'u |

- `serve.cpp` bir unix soketi değil, TCP'dir — R7 ile ilgisi yok, listeye
  yalnız taramanın tam olduğunu göstermek için girdi.
- `gate.cpp`'deki AF_UNIX soketi bir **canlı yayın istemcisidir**: ledger satırı
  diske yazıldıktan sonra (`native/gate.cpp:742-743`) varsa `rabadon watch`'a
  fan-out eder. Bağlanamazsa sessizce düşer (`sockFd = -1`) ve kapı işine devam
  eder. Yargılama bu soketten GEÇMİYOR — yani R7'nin sileceği süreç başlatma
  maliyetine dokunmuyor.
- `core/bus.mjs`'in sunucusunun sahibi `rabadon watch`'tır (`core/bus.mjs:19`
  bunu açıkça yazıyor: "`rabadon watch` OWNS the socket").

**Sonuç:** repoda AF_UNIX sunucu soketi açan tek şey watch veri yoludur. Kapıya
hizmet eden kalıcı bir süreç yoktur.

### 4. A1'in soket kuralına UYUM: sıfır

`KOSU-RABADON-2.md:60-66` şunu şart koşuyor: soket yolu KISA ve MUTLAK,
`${XDG_RUNTIME_DIR:-/tmp}/rabadon-$UID.sock`, 0600 izin, uzunluk sınırı
testte assert edilir.

- **`XDG_RUNTIME_DIR` hiçbir kaynak dosyada geçmiyor.** Repo genelinde yalnız
  iki yerde var: `KOSU-RABADON-2.md:64` (kuralın kendisi) ve
  `reports/kosu/1.karar:13` (bu turun talimatı). Kural yazıldı, koda hiç
  girmedi — beklenen durum, çünkü daemon da yok.
- Var olan iki soket de kurala aykırı yerde: ikisi de `$RABADON_DIR` altında,
  varsayılanı `$HOME/.rabadon` (`native/pathres.h:187-192`,
  `core/bus.mjs:29-30`). `RABADON_DIR` env ile ezilebilir, yani **worktree'nin
  içine gösterilebilir** — A1'in tam olarak yasakladığı şey.
- **0600 izni hiçbir yerde verilmiyor.** `core/bus.mjs:281` `server.listen(SOCK_PATH)`
  düz umask ile yaratıyor; `chmod`/`fchmod` çağrısı yok.

### 5. YENİ BULGU — belgenin öngördüğü hata SINIFI zaten kodda, sessiz biçimde

A1, ENAMETOOLONG'u gelecekteki daemon için bir risk olarak yazıyor. Ama aynı
hata sınıfı **bugün, sevk edilmiş istemcide** mevcut:

```
native/gate.cpp:720
  strncpy(addr.sun_path, sockPath.c_str(), sizeof(addr.sun_path) - 1);
```

`strncpy` uzunluk kontrolü yapmaz, **sessizce keser**. `sockPath`
`sun_path` tavanını (macOS 104 / Linux 108) aşarsa:
- `bind()` ENAMETOOLONG ile düşmez — çünkü burada `bind` yok;
- `connect()` kesilmiş bir yola gider, ENOENT alır,
- kod `sockFd = -1` yapıp **sessizce devam eder** (`native/gate.cpp:721-723`).

Yani belirti "daemon kapalı" ile birebir aynıdır. `RABADON_DIR` derin bir
worktree'ye gösterildiğinde canlı yayın sessizce ölür ve hiçbir yerde
sayılmaz. Bu, CLAUDE.md'nin "her hata yolu tasarlanmış yoldur, asla sessizleşmez"
(Promise 1) kuralının ihlalidir.

Doğrulama: `native/` altında `sun_path` uzunluk kontrolü ya da `ENAMETOOLONG`
ele alan **tek bir satır yok** (arama boş döndü).

**ÖNERİ (uygulanmadı — R7 kapsamı, bu tur değil):** A1'in kuralı yalnız yeni
daemon'a değil, `gate.cpp`'nin mevcut `open_sock()`'una da uygulanmalı; kesme
sessiz kalmamalı, sayılmalı.

### KALAN HİPOTEZLER / ölçülmemiş

- Daemon'ın hangi süreci konuşacağı (protokol, çerçeveleme, timeout) hiçbir
  yerde tasarlanmamış. `core/bus.mjs`'in satır-bazlı JSONL çerçevelemesi hazır
  bir örnektir ama kapı için yeniden mi kullanılır, bilinmiyor. **ÖLÇÜLMEDİ.**
- `accept.sh` daemon soketini `$W` (mktemp -d) altına koyuyor
  (`reports/R7/accept.sh:107`). macOS'ta `mktemp -d` `/var/folders/.../T/` verir
  ve buna `rabadon-gated.sock` eklenince `sun_path` tavanına yaklaşır.
  Kabul betiğinin kendisi A1 kuralına uymuyor olabilir — **ÖLÇÜLMEDİ**,
  daemon olmadığı için bu kol hiç koşmadı.
- R7'nin ikinci yarısı (iki kollu kanıt, harness, beş sayı, JSONL) bu turda
  hiç incelenmedi; yalnız daemon yarısı teşhis edildi. **İNCELENMEDİ.**
