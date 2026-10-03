# Sunum planı

Gameplay `match.gd` içinde kalır. Sunum olayları yeni bir çerçeve sınıfı açmadan mevcut masaya bağlanır.

## Uygulanan dilim

- Koltuğa sabit kamera. Sağ tık basılıyken serbest bakış, kritik sönümlü yay (`look_omega`), yaw/pitch sınırları. `R` ortaya alır. Kamera kafa kemiğini izlemez.
- `C` basılıyken kart fanı öne gelir ve kamera biraz aşağı bakar. Bırakınca eski tutuşa döner.
- Bakışta baş önce, gövde sonra gelir (`head_lag`, `torso_lag`). Oyuncunun gövdesi bakışın küçük bir kısmını gecikmeli takip eder.
- Aktif koltuğu gösteren özgün pirinç çentik, yaklaşık 1,5 saniyelik nabız.
- Seçili kart 1,8 cm kalkar ve sıcak bir ışıma alır.
- `F3` durum, koltuk, meşguliyet ve pati boşluğunu yazar.
- Tüm sayılar `godot/data/feel.tres` içindedir. `sway_enabled` ve `look_enabled` nefes ile bakışı kapatır.

## Sonraki yüksek değerli adımlar

1. Parmak kemikli rig gelince kavrama pozları. O zamana kadar soket + sabit el.
2. Ceza kartı çekilişini ayrı bir sunum vuruşu yapmak. Silah eklenmez.
3. Forward+ seçilirse hafif sis. Şu anki uyumluluk yolu hacimsel sisi desteklemez.
4. Ağ gelirse yalnızca semantik olay çoğaltılır; kemik dönüşü her kare gönderilmez.

## Performans

Dört karakter yaklaşık 26 bin üçgen. Yeni nesneler bir çentik ve seçili kartın malzeme kopyası. 1080p 60 kare ölçülmedi; M4 üzerinde pencere içi el akışı takılmadan döndü. Darboğaz raporu için ayrı bir profil turu gerekir.
