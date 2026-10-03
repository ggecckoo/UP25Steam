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
