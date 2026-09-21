# Supabase — Çağatay'ın yapması gerekenler

> Hazırlayan: Ömer tarafı · 14 Ağustos 2026
> Uygulayan: Çağatay · 15 Ağustos 2026 (`de6dcf8` handover uygulandı)

## Durum özeti

| | Durum |
|---|---|
| TestFlight build (misafir modu) | ✅ Çalışıyor |
| İmzalama, bundle ID, Game Center entitlement | ✅ Xcode’da var |
| Supabase projesi `xlaopbzphkhmepjojbkx` | ✅ **ACTIVE_HEALTHY**, DNS OK |
| Edge `gamecenter-auth` / `delete-account` | ✅ Deploy edildi (15 Ağu) |
| Bundle allowlist (UP-25 + up2540) | ✅ curl ile doğrulandı |
| Game Center App Store Connect sürümü | ⚠️ Hâlâ ASC’de açılmalı (`GK 15` / `5019`) |
| Anon key → Ömer | ⚠️ Özel kanaldan gönder (repoya koyma) |

---

## Yapılacaklar — uygulama kaydı

### 1. Projeyi uyandır — ✅

DNS (`8.8.8.8` / `1.1.1.1`) IP dönüyor; dashboard status `ACTIVE_HEALTHY`.

### 2. Anon key’i Ömer’e ver — ⏳ manuel

Çağatay makinesinde `UP 25/Config/SupabaseConfig.plist` dolu (`./scripts/sync-supabase-plist.sh` çalıştırıldı).

Ömer’in placeholder plist’i için: Dashboard → Settings → API → **anon public** anahtarını
**özel kanaldan** gönder (Slack/DM). Repoya / commit’e koyma.

### 3. Şema — ⚠️ yeni gizlilik migrasyonu bekliyor

`003_restrict_profile_reads.sql`, giriş yapan kullanıcıların başka profilleri
okuyabildiği eski politikayı yalnızca kendi profiliyle sınırlar. Üretime uygula:

```bash
./.bin/supabase db push --yes --linked
```

Komut tamamlanmadan gizlilik politikasındaki “yalnızca kendi satırları” garantisi
üretim veritabanı için geçerli sayılmamalı.

### 4. Edge secret’lar — ✅

`ALLOWED_BUNDLES=com.atikolabs.UP-25,com.atikolabs.up2540` set edildi.
`SUPABASE_URL` / `ANON_KEY` / `SERVICE_ROLE_KEY` projede mevcut.

### 5. `gamecenter-auth` deploy — ✅

```bash
./.bin/supabase functions deploy gamecenter-auth --no-verify-jwt
```

Curl doğrulama (15 Ağu):

- `com.atikolabs.UP-25` → `401 Game Center imzası geçersiz` ✅ (bundle kabul)
- `com.atikolabs.up2540` → `401 …` ✅
- `com.atikolabs.WRONG` → `403 Geçersiz bundle` ✅

### 6. `delete-account` deploy — ✅

```bash
./.bin/supabase functions deploy delete-account
```

---

## Bundle ID notu

- Çağatay: `com.atikolabs.UP-25` (takım `7AVYNXTB6V`) — `main`
- Ömer TestFlight: `com.atikolabs.up2540` (takım `Z927F9H783`) — `testflight-hazirlik`

Fonksiyon ikisini de kabul ediyor.

---

## Ayrıca: sessiz Game Center — ✅ kodda

`GameCenterAuth.prepare()` `AuthSession.init` + `restore()` içinde çağrılıyor; handler açılışta bağlanıyor.

- Sessiz auth olursa → Supabase oturumu açılıp menüye düşülür (buton yok)
- Olmazsa → auth ekranı + misafir yolu (GC uygulamayı bloklamaz)
- Login VC yalnızca kullanıcı **Devam** deyince gösterilir

> Xcode = GC sandbox · TestFlight/App Store = production. Ayrıca App Store Connect
> sürümünde **Game Center** checkbox açık olmalı; aksi halde `GKError 15` / `5019`.
