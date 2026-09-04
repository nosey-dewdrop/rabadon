# f1a-4-ci-matris

YAPILAN — `.github/workflows/ci.yml` (tek dosya, 12 satır ekleme / 3 silme):
`test` job'ının matrisine `node: ['20', '22']` eklendi; `setup-node`
`node-version: ${{ matrix.node }}` oldu; job adı `${{ matrix.os }} node${{ matrix.node }}`.
`fail-fast: false` duruyor. Neden 20: `release.yml` publish (satır 102) ve smoke
(satır 141) `node-version: "20"` ile koşuyor — yayımlanan yol artık test edilen yol.
Gerekçe dosyaya yorum olarak yazıldı; mevcut yorumların hiçbiri silinmedi.
`disclosure` job'ına dokunulmadı (`git diff | grep -c disclosure` → `0`).

ÖLÇÜLEN:
    $ python3 -c "import yaml,itertools; d=yaml.safe_load(open('.github/workflows/ci.yml')); \
      m=d['jobs']['test']['strategy']['matrix']; print(m, len(list(itertools.product(m['os'],m['node']))))"
    {'os': ['ubuntu-latest', 'macos-15'], 'node': ['20', '22']} 4
YAML geçerli (safe_load hatasız), `test` hücre sayısı = 4, `disclosure` matrisi
hâlâ `{'os': ['ubuntu-latest', 'macos-15']}` = 2 hücre.

npm_install_test.sh KANITI — ayrı bir CI adımı GEREKMEDİ, `make test` içinde koşuyor:
    $ grep -n npm_install_test Makefile   →  602:	./native/npm_install_test.sh
    $ awk 'NR>=95 && NR<=620 && /^[a-zA-Z0-9_.-]+:/ {print NR": "$0}' Makefile
      96: bench: ...        104: test: all
604'e kadar araya başka hedef girmiyor, yani 602 `test:` reçetesinin içinde.
`make test` dört hücrenin dördünde koştuğu için temiz prefix kurulumu da 4 kez koşar.

YAPILAMAYAN: workflow gerçekten çalıştırılmadı (git yazma ve push kartta yasak,
`gh workflow view` uzak durumu okur, yerel dosyayı değil). 4 hücrenin YEŞİL olduğu
DOĞRULANMADI — ölçülen tek şey matrisin 4 hücre ürettiği.

KART DIŞI (dokunulmadı):
- `package.json` `engines.node: ">=18"` diyor ama CI'da 18 yok; 18 desteği hâlâ
  ölçülmemiş bir iddia. 20+22 bunu daraltıyor, kapatmıyor.
- `npm_install_test.sh` npm yoksa/desteklenmeyen OS'ta `exit 0` ile SKIPPED yazıyor
  (satır 24-30). CI runner'larında npm var, ama skip pass gibi okunabilir bir yüzey.
- `release.yml` smoke job'ı `ubuntu-22.04` kullanıyor, CI `ubuntu-latest`; bu fark
  bilinçli (dosyadaki yorum bunu açıklıyor) ve dokunulmadı.
