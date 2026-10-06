# Sunum denetimi

Tarih: 2026-10-03. Motor repository'den okundu. Referans videosu projede yok (`Docs/Reference/` altında mp4 bulunamadı); kare çıkarılmadı.

## Motor ve akış

- Godot 4.7.2, `GL Compatibility`. Ana sahne `godot/scenes/main.tscn`.
- Oynanış `godot/scripts/match.gd` içinde yerel 25-40 simülasyonu. Ağ katmanı yok. Sunucu otoritesi, RPC ve late-join yok.
- Swift macOS istemcisi ve Go masaüstü istemcisi bu dilimin dışında. Kurallar: eşik 30, tavan 80, en çok 8 tur, 7 kart. Deste 1, 3, 5, 7, 9, Vale 15 ve King 20.
- Girdi Godot'un olay sistemidir. Ayrı bir InputMap eylemi yok. Yürüme yok; oyuncu koltuğa sabit.
- Kamera `room_preview.gd` içinde, kafa kemiğine bağlı değil. Kartlar `card_table.gd` ve `seat_actor.gd` ile duruyor.
- Animasyon, Meshy klibi değil. GLB'deki tek klip durduruluyor. Oturma, bakış ve kollar prosedürel.

## Baseline

- `godot/tests/check.gd` değişiklikten önce ve sonra `OK`.
- `godot/tests/characters.gd` önceden de kırık: `HandR` ve `SitIdle` gibi olmayan kemik/klip arıyor. Canlı iskelet `RightHand` kullanıyor ve tek klip `Armature|clip0|baselayer`.

## Bu dilimde bilinçli olarak yapılmayanlar

- Revolver, kuru tetik, ölüm kamerası, ragdoll ve seyirci bakışı yok. 25-40'ta ceza silah değil, kart çekmek. Referansın rulet akışı kopyalanmaz.
- Hacimsel sis ve gerçek alan derinliği bu render yolunda yok.
- Parmak, çene, göz kemiği ve blendshape olmadığı için yüz katmanı ve tetik pozu uydurulmadı.
