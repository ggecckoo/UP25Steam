# Meshy karakter hazırlığı

Birim yaklaşık 1 metre. Oyun ölçeği `ROOM_FIT` 1.16. İleri yön model +Z, yukarı +Y. Hepsi tek gövde mesh'i, blendshape yok, LOD yok, fizik gövdesi yok.

| Karakter | Rig | Üçgen | Klip | Parmak / göz / çene |
| --- | --- | --- | --- | --- |
| kaya, sis, kok, karaca, sirtlan, dere | 24 kemik | 25.5–26.1 bin | `Armature\|clip0\|baselayer` | yok |
| nida, kul | rig yok, statik mesh | ~25.5–25.8 bin | yok | yok |

Rigli iskelet: `Hips`, bacaklar, `Spine` / `Spine01` / `Spine02`, omuzlar, `LeftArm` / `LeftForeArm` / `LeftHand`, sağ kolun aynıları, `neck`, `Head`, `head_end`, `headfront`.

Masada kullanılanlar kaya, sis, kok, karaca. nida ve kul üretim kalitesinde riglenmeden oturtulamaz. Kod onları rigli saymaz.

Doku: albedo var. Ayrı metalik/pürüz haritası yok; kumaş `seat_actor` içinde metalik 0, pürüz 0.86 ile matlaştırılıyor.

## Üretim için gereken rig

Final el pozu için her elde başparmak ve en az üç parmak kemiği, skin weight ile. Yüz için ya blendshape (göz kırpma, çene) ya da göz ve çene kemiği. İkisi de yoksa kırpma ve ağız hareketi yapılmaz. Kulak ve kuyruk ayrı kemiğe bağlanırsa ikincil hareket eklenebilir; şu an yok.

Bu adım Godot içinde tamamlanamaz. Mixamo veya Meshy rig dışarıda üretilip aynı kemik adlarıyla yeniden içeri alınmalıdır.

## Krupiye (kul)

Meshy'nin otomatik rigi kuş anatomisinde başarısız olduğu için karga `tools/rig_dealer.py` ile riglenir: A-pozdaki `kul.glb` 1,55 m'ye ölçeklenir, yukarıdaki 24 kemik aynı adlarla elle yerleştirilir (her kemiğin +Y'si çocuğuna bakar), ağırlıklar bölge bölge zarf yöntemiyle boyanır. Çıktı `godot/assets/characters/krupiye.glb`; yeniden üretince `Godot --headless --path godot --import` ile içe aktar. Sahnede `godot/scripts/dealer.gd` sürer.

Masadaki oyuncuların elleri artık Meshy pençesi değil, `fp_hands.gd`'deki parmaklı ellerdir; kürk rengi her karakterin kendi pençe dokusundan örneklenir.
