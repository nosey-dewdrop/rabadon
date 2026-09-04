# F3g — mutasyon kanıtı (§3.8/3). Kırmızı olamayan kapı kapı değildir.

Üçü de bu makinede, gerçek `native/rabadon-gate` ikilisi yeniden derlenerek
koşturuldu. Her mutant kasten kondu, ölçüldü, geri alındı.

| # | mutant | suite | yeşil | mutantla | geri alınca |
|---|---|---|---|---|---|
| 1 | `law_unmade` çağrısı `if (false && …)` ile kapatıldı (`baseline.h`, `check_parsed`) | `law_family_test.sh` | 62/0 | **26/36 KIRMIZI** | 62/0 |
| 2 | yasa **DOSYA adıyla** korunmaya devam etti, **dizin** kolu kapatıldı (`is_project_law_path`, `if (false && last == ".rabadon")`) | `law_family_test.sh` | 62/0 | **54/8 KIRMIZI** | 62/0 |
| 3 | kart 2'nin daraltması geri alındı (`rules.h`, `segment_writes_nothing` satırı silindi) | `guard_delete_test.sh` | 22/0 | **18/4 KIRMIZI** | 22/0 |

**2 numaralı mutant kartın kendi dersidir.** F3f tam olarak o hâli sevk etti:
dosya adıyla korunuyor, dizin açık. Süit o hâli **54/8 kırmızı** görüyor — yani
"bir şekli kapatıp aileyi açık bırakmak" bu süitte yeşil basamaz.

**3 numaralı mutant yanlış pozitifin kendisidir:** daraltma olmadan
`grep -c rm .rabadon/guard.json` yine rc=2 döner ve süit kırmızı düşer.

## Boş yeşil turu

`reports/kosu/kanit/f3g/bosyesil.out` — iki süit de `F3g-oncesi` (`906b1e1`)
artefaktının üstünde, `--detach` bir worktree'de, **`/tmp` DIŞINDA**
(`~/damla_projects_2026/_f3g_bosyesil`, sonra kaldırıldı) koştu:

    law_family_test.sh    26 passed, 36 failed   EXIT=1
    guard_delete_test.sh  18 passed,  4 failed   EXIT=1

Fikstürler de `/tmp` dışında: `law_family_test.sh` kum havuzunu `$HOME` altında
açar (`mktemp -d "$LAB/.rb-lawfam.XXXXXX"`), çünkü kapsam yasası makine temp
kökünü muaf tutar ve F3f'in "canlı bypass" okuması tam olarak bu yüzden şişikti.
