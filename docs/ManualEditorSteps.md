# Elle editör adımları

Bu dilim için Godot editöründe veya bir DCC aracında zorunlu adım yok. Oyun `godot/scenes/main.tscn` ile açılır.

İleride parmaklı veya yüzlü rig alınırsa:

1. Yeni GLB'yi `godot/assets/characters/` altına aynı dosya adıyla koy.
2. Godot'un içe aktarmasını bekle. Kök kemik `Hips`, eller `LeftHand` ve `RightHand` kalsın.
3. `godot/tests/characters.gd` hâlâ eski `HandR` ve `SitIdle` adlarını arar. Bu test canlı iskeletle uyumsuz; yeşil olmasını bekleme.
