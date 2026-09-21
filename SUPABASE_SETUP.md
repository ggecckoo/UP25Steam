# Yirmibeş — Supabase + Game Center

Proje: **YirmiBes** (`xlaopbzphkhmepjojbkx`)
Dashboard: https://supabase.com/dashboard/project/xlaopbzphkhmepjojbkx

## Auth akışı

1. Oyuncu **Game Center ile devam** der.
2. GameKit yerel oyuncuyu doğrular ve kimlik imzası üretir.
3. `gamecenter-auth` Edge Function imzayı Apple public key ile doğrular.
4. Supabase Auth kullanıcısı + `profiles` satırı oluşturulur/güncellenir.
5. Uygulama access/refresh token ile oturum açar.

Misafir yolu skor kaydetmez (simülatör / hızlı deneme).

## Xcode + Apple Developer + App Store Connect (zorunlu)

Telefonda Game Center’ın çalışması için **dört** katman birlikte olmalı.
Log’da `GKError 15` / `5019` / `no game matching descriptor` görüyorsan sorun kodda değil, portalda.

1. **Xcode** — Capability: Game Center (`UP 25/UP_25.entitlements`), Bundle ID: `com.atikolabs.UP-25` ✅ (projede var)
2. **Apple Developer → Identifiers → App ID** — aynı bundle için **Game Center** açık
   https://developer.apple.com/account/resources/identifiers/list
3. **App Store Connect → app → iOS sürümü** — sayfada **Game Center** kutusu işaretli
   https://appstoreconnect.apple.com/
   (Apple’ın kendi mesajı: *“enable Game Center on App Store Connect”*)
   Rehber: https://developer.apple.com/help/app-store-connect/configure-game-center/enable-an-app-version-for-game-center
4. **Cihaz** — Ayarlar → Game Center’da Apple ID; ardından Clean + Run / yeni TestFlight build

Edge Function kabul ettiği bundle’lar: `com.atikolabs.UP-25`, `com.atikolabs.up2540` (+ `ALLOWED_BUNDLES` secret).

## Durum

- [x] Proje bağlı, şema yüklü (`profiles`, `game_results`, `game_center_id`)
- [x] `SupabaseConfig.plist` (git’e girmez) — `./scripts/sync-supabase-plist.sh`
- [x] Edge Function: `gamecenter-auth` (`verify_jwt = false`, her iki bundle)
- [x] Edge Function: `delete-account`
- [x] Secret: `ALLOWED_BUNDLES`
- [x] Xcode entitlement: `com.apple.developer.game-center`
- [x] Açılışta `GameCenterAuth.prepare()` + sessiz GC denemesi
- [ ] Anon key’i Ömer’e özel kanaldan gönder
- [ ] Developer → App ID `com.atikolabs.UP-25` → Game Center
- [ ] App Store Connect → iOS sürümü → Game Center checkbox

## Komutlar

```bash
./scripts/sync-supabase-plist.sh
./.bin/supabase db push --yes
./.bin/supabase functions deploy gamecenter-auth --no-verify-jwt
./.bin/supabase functions deploy delete-account
```

## Tablolar

| Tablo / alan | Amaç |
|--------------|------|
| `profiles.game_center_id` | Game Center `teamPlayerID` (unique) |
| `profiles.display_name` | GC görünen ad |
| `game_results` | Skor / sıra / galibiyet |
