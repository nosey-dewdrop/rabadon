# TESHIS-HARNESS — iki kollu koşu neden kurulamadı (tur 12)

Durum: **BLOKE.** Koşu YAPILMADI, JSONL ÜRETİLMEDİ.
Tarih: 2026-08-24. Makine: macOS 24.2.0, arm64, Python 3.14.6.

## Tıkanan adım — 5 satır

1. `pip install swesmith==0.0.6` **çöküyor**: `sglang` (36 zorunlu bağımlılıktan
   biri, sürüm sabitlenmemiş) → `flashinfer_python` → `apache-tvm-ffi==0.1.0b15`,
   ki bu sürüm PyPI'de **yok** (mevcut: 0.1.0…0.1.13.post3). Ağ değil, çözümsüz
   bağımlılık; her makinede aynı.
2. Konteyner tabanı yalnız **amd64**: `jyangballin/swesmith.x86_64` tag `latest`
   → `arches: ['amd64']`; `swesmith.arm64` ve `swesmith.arm64.v8` → **404**.
   Bu makine arm64.
3. `docker info` → **daemon ayakta değil** (`Cannot connect to … docker.sock`).
4. `swesmith/harness/eval.py:2` kendi cümlesiyle: *"Given predictions by
   SWE-agent, evaluate its performance"* — swesmith **ajan koşturmaz**, hazır
   yamayı puanlar. A ve B kolu ayrı bir ajan (SWE-agent) ister.
5. O ajan **ücretli bir LLM anahtarı** ister; ortamda ne `ANTHROPIC_API_KEY` ne
   `OPENAI_API_KEY` var. Anahtar koymak ve para harcamak **operatör kararıdır**,
   yapan oturumun değil.

## Kanıt (komut ve çıktı, iddia değil)

    $ .venv/bin/pip install 'swesmith==0.0.6'
    ERROR: Could not find a version that satisfies the requirement
           apache-tvm-ffi==0.1.0b15 (from versions: 0.1.0, … 0.1.13.post3)
    ERROR: Failed to build 'flashinfer_python' … installing build dependencies

    $ python3 -c "…pypi.org/pypi/swesmith/0.0.6/json…"
    requires_python: >=3.10   n_deps: 36   (listede: sglang, swebench, docker, litellm)

    $ hub.docker.com/v2/repositories/jyangballin/swesmith.x86_64/tags
    tag: latest | arches: ['amd64']
    jyangballin/swesmith.arm64      -> HTTP Error 404
    jyangballin/swesmith.arm64.v8   -> HTTP Error 404

    $ docker info
    Cannot connect to the Docker daemon at unix:///…/docker.sock.

    $ uname -m
    arm64

`swesmith/profiles/base.py:64-65` arm64 makinede `pltf="linux/arm64/v8"` seçiyor,
ama o platformda yayınlanmış imaj yok (yukarıdaki 404) — yani ajan/Docker
sorunu çözülse bile taban imaj bu makinede emülasyonsuz gelmiyor.

## Ne YAPILMADI ve neden

**Sahte JSONL yazılmadı.** GOAL 5/6/7'nin on kırmızısı tek bir dosyaya bakıyor;
o dosyayı elle uydurulmuş `heldout_pass`/token/`estimated_saved` alanlarıyla
üretmek betiği yeşile çevirir ve ölçülmüş hiçbir şey var etmez. CLAUDE.md
non-negotiable 3 ve accept.sh başlığındaki "NO ASSERTION MAY PASS VACUOUSLY"
tam olarak bunu yasaklıyor. On kırmızı KIRMIZI kaldı.

**5c de yazılmadı.** `bench/reproduce.sh`'e "R7 iki kollu koşu" cümlesi eklemek
teknik olarak mümkündü ve 5c'yi yeşile çevirirdi — ama var olmayan bir koşuyu
yeniden koşan betik olmaz. Aynı vakum kuralı.

**4d de yazılmadı.** Hazırlık (`.git` temizliği, egress kapatma) yapılmadı;
yapılmadan kaydını yazmak yine vakum.

## Operatöre giden karar (yapan veremez)

İki kollu koşu, bugünkü halde **üç ayrı onay** istiyor ve üçü de para/politika:

- (i) hangi ajan? swesmith ajan sağlamıyor; SWE-agent ayrı kurulum.
- (ii) LLM anahtarı ve bütçe — A ve B kolu iki tam ajan oturumu demek.
- (iii) amd64 zemin: emülasyonlu Docker mı, uzak bir x86_64 Linux makine mi?
  (ii) ve (iii) birlikte, R7'nin "temiz container" şartıyla da örtüşüyor.

`sglang` blokeri için ayrıca teknik bir kaçış var ama o da karar:
`--no-deps` ile swesmith'i kurup gerçek bağımlılıkları elle seçmek. Bu turda
paketin İÇİNİ okumak için yapıldı (`pip install --no-deps` ile wheel açıldı),
KOŞU için yapılmadı — eksik bağımlılıkla alınan bir sayı ölçüm sayılmaz.
