# Çok oyunculu masa — arka uç

> Durum (17 Ekim 2026): arka uç yazıldı ve yerelde test edildi; **henüz canlıya
> alınmadı** (migration push / function deploy yapılmadı). Godot istemcisi tek
> oyunculu çalışmaya devam ediyor, ağa bağlanmıyor.

## Mimari

Sunucu yetkili (authoritative): istemciler yalnızca hamle gönderir, oyunu
sunucu yürütür.

| Parça | Yer | Görevi |
|---|---|---|
| Kural motoru | `supabase/functions/_shared/game/engine.ts` | `godot/scripts/match.gd` ile aynı kurallar: deste, tur, 30/80 hedefi (3 kişide 23/60, 2 kişide 14/40), kart çekme, el sonu sıralaması, taş-kağıt-makas, masadan ayrılma. Saf ve deterministik: rastgelelik motorun kendi tohumundan, zaman dışarıdan verilen `now`'dan. |
| Masa servisi | `supabase/functions/_shared/game/service.ts` | Lobi (oluştur, kodla katıl, ayrıl), başlat (boş koltuklara bot), hamle, zamanı ilerletme. Depolama `Store` arayüzü arkasında. |
| Edge Function | `supabase/functions/game-table/` | HTTP uç noktası; giriş yapmış kullanıcı (`verify_jwt = true`). Postgres deposu `store.ts`. |
| Şema | `supabase/migrations/004_multiplayer_tables.sql` | Tablolar, RLS, atomik commit fonksiyonu, Realtime yayını. |

Her değişiklik aynı yoldan geçer: motor ve sürümü okunur → `advance(now)` ile
zaman yetişir → hamle uygulanır → `game_table_commit` sürüm hâlâ aynıysa
tek işlemde yazar; değilse (biri araya girdiyse) baştan denenir.

### Zaman

Motor beklemez; bekleyen her durumun bir `deadline`'ı vardır. Süresi dolan
adımları `advance` oynar: botun hamlesi, süresi biten insanın hamlesi (bot
gibi oynanır), açılışın bitişi, taş-kağıt-makasın her aşaması. Arka planda
çalışan bir sunucu yok: masadaki herhangi bir istemci, herkese açık
`deadline` geçince `tick` çağırır. Süreler `engine.ts` → `TIMING`
(dağıtım 6 sn, hamle 30 sn, açılış 9,5 sn, atış seçimi 15 sn …); istemci
animasyonları bu sürelere sığacak şekilde.

## Veri modeli

| Tablo | İçerik | Kim okur |
|---|---|---|
| `game_tables` | Kod, ev sahibi, durum (`lobby/playing/over/closed`), lobi koltukları, **herkese açık durum** (`state`), sürüm, `deadline` | Masanın üyeleri |
| `game_table_members` | Kim hangi koltukta, görünen ad, karakter, ayrıldı mı | Masanın üyeleri |
| `game_table_hands` | Oyuncunun kendi kartları | **Yalnız sahibi** |
| `game_table_engines` | Motorun tamamı (deste, herkesin eli, rastgele durumu) | Hiçbir istemci (yalnız service role) |

İstemciler hiçbir tabloya yazamaz; tüm yazma `game-table` fonksiyonundan,
`game_table_commit` ile (yalnız `service_role` çalıştırabilir). Oturum
bitince sonuçlar aynı işlemde `game_results`'a yazılır ve `profiles`
sayaçları bir kez artar.

`state` (motorun `publicView`'ı) şunları içerir: faz, el/tur, sıra sahibi,
hedef/tavan, sıradaki koltuk, `deadline`, koltuklar (ad, karakter, bot mu,
masada mı, kart sayısı), masadaki kapalı kartlar (yalnız kim attı), biten
turun açık kartları/sonucu/kimin hangi kartı çektiği (`last`),
taş-kağıt-makas (atışlar ancak eller inince görünür), sıralama, şampiyon.
Elde tutulan hiçbir kart burada yoktur.

## API — `POST /functions/v1/game-table`

`Authorization: Bearer <kullanıcı JWT>`, gövde `{ "action": ..., ... }`.

| action | Gövde | Dönüş |
|---|---|---|
| `create` | `name?`, `preset?` | `table_id`, `code` (6 harf), `seat` |
| `join` | `code`, `name?`, `preset?` | `table_id`, `seat` (aynı karakter seçilmişse boştaki ilk karakter verilir) |
| `leave` | `table_id` | Lobide koltuğu boşaltır (ev sahibi çıkarsa masa kapanır); oyunda koltuk bota geçer |
| `start` | `table_id` | Yalnız ev sahibi; boş koltuklara kalan karakterlerden bot oturur |
| `play` | `table_id`, `card_id` | |
| `throw` | `table_id`, `choice` (0 taş, 1 kağıt, 2 makas) | |
| `tick` | `table_id` | Süresi dolan adımları oynatır |
| `state` | `table_id` | `table`, `seat`, `hand` (yeniden eşitleme için) |

Hatalar `409 { error_code }`: `not_your_turn`, `card_not_in_hand`,
`not_playing`, `no_duel`, `not_in_duel`, `not_choosing`, `table_full`,
`table_started`, `table_not_found`, `not_host`, `not_a_member`,
`not_seated`, `busy`.

## İstemci entegrasyonu (sonraki adım)

1. **Giriş:** test için Supabase anonim girişi (Dashboard → Authentication →
   Anonymous sign-ins; `config.toml`'da kapalı). Yayın için Steam oturum
   bileti doğrulayan bir `steam-auth` fonksiyonu (Game Center'daki
   `gamecenter-auth` gibi).
2. **Abonelik:** Realtime ile `game_tables` (id filtresi) ve kendi
   `game_table_hands` satırı. RLS geçerli; başkasının elini alamaz.
3. **Görüntü:** Godot'da `Match` ile aynı arayüzü sunan bir ağ maçı
   (`NetMatch`) `state`'i masa sahnesine aktarır; masa, krupiye, HUD olduğu
   gibi kalır. Tek oyunculu mod yerel `Match` ile devam eder.
4. **Hamle:** kart seçilince `play`, atışta `throw`; `deadline` geçince `tick`.

## Test

```bash
# Kural motoru ve masa servisi (Node 22.18+/24, TypeScript doğrudan çalışır)
node --test supabase/functions/_shared/game/*.test.ts

# SQL: göçleri WebAssembly Postgres'te uygular, commit ve RLS'yi dener
mkdir -p /tmp/pglite && cd /tmp/pglite && npm i @electric-sql/pglite@0.2.17
node <repo>/supabase/tests/multiplayer_sql_check.mjs
```

Kapsananlar: match.gd ile kural eşliği (`tests/check.gd`'deki değerler),
yalnız saatle oynanan 300 tam oturum (kart korunumu, her oturum biter),
taş-kağıt-makas (kazanan asla çıkmaz, kaybeden yalnız kaybedince),
herkese açık durumda el/kapalı kart sızmaması, dört kişinin API üzerinden
tam oturumu ve sonuçların bir kez yazılması, oyun ortasında ayrılan
oyuncunun koltuğunun bota geçmesi, aynı masaya yarışan iki hamle, RLS.

## Canlıya alma (yapılmadı)

```bash
./.bin/supabase db push --linked            # 004_multiplayer_tables.sql
./.bin/supabase functions deploy game-table
```

## Yayından önce

- Gizlilik: çok oyunculu oyunda görünen ad masadakilere görünür ve hamleler
  Supabase'de tutulur. `docs/README.md`'deki dört yer (ve Steam sayfası)
  birlikte güncellenmeli; şu an "Steam sürümü çevrimdışı" yazıyor.
- Steam girişi (`steam-auth`), istek sınırlama, eski/terk edilmiş masaların
  temizliği (ör. pg_cron ile `status = 'lobby'` ve 1 günden eski).
