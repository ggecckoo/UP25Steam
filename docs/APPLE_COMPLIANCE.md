# Apple App Store — 25-40 ret önleme kontrol listesi

> Amaç: App Store'a göndermeden önce bilinen ret sebeplerini kapatmak.
> Bu liste UP25'in **gerçek** durumuna göre yazıldı (kod okunarak), genel bir
> şablon değil. Kod değiştikçe güncellenmeli.
>
> Son gözden geçirme: 14 Ağustos 2026

## Uygulama profili

| | |
|---|---|
| Tür | Tek kişilik iskambil oyunu, rakipler bot |
| Bundle ID | `com.atikolabs.up2540` (Ömer'in takımı `Z927F9H783`) |
| Backend | Supabase (auth + veritabanı + edge functions) |
| Giriş | Game Center — **opsiyonel**, çevrimdışı oynanabiliyor |
| Satın alma | Yok |
| Reklam | Yok |
| Analitik / takip | Yok |
| Kullanıcı içeriği / sohbet | Yok |
| Cihaz izinleri | Hiçbiri (kamera, mikrofon, konum, rehber — hiçbirine dokunmuyor) |
| Cihaz ailesi | iPhone + iPad |
| Minimum iOS | 18.0 |

---

## Bize UYGULANMAYANLAR

Genel şablonlarda yer alan ama bu uygulamada **karşılığı olmayan** maddeler.
Bunlarla vakit kaybetme:

| Madde | Neden gerekmiyor |
|---|---|
| Restore Purchases butonu | Satın alma yok |
| Abonelik iptal yönlendirmesi | Abonelik yok |
| ATT izin ekranı / IDFA | Takip yok, reklam ağı yok |
| Üçüncü taraf AI ifşası | AI kullanılmıyor |
| İçerik moderasyonu / raporlama | Kullanıcı içeriği ve sohbet yok |
| UGC için engelleme (blocking) akışı | Oyuncular birbiriyle etkileşmiyor |
| Yaş doğrulama ekranı | 4+ derecelendirme hedefleniyor |
| Veri dışa aktarma (GDPR export) | Zorunlu değil; tutulan veri oyuncu kimliği + skor ile sınırlı, silme yeterli |
| Sağlık/finans veri açıklamaları | Toplanmıyor |
| Kumar lisansı / coğrafi kısıt | Bahis, sanal para, ödül yok — Guideline 5.3 kapsamı dışında |

---

## FAZ 1 — Göndermeden önce ZORUNLU

### 1.1 Gizlilik politikası için herkese açık URL — **ENGELLEYİCİ**

App Store Connect gizlilik politikası **URL'si** istiyor; uygulama içi metin bunun
yerine geçmiyor. Şu an yalnızca uygulama içinde var.

- [ ] `docs/PRIVACY_POLICY.md` bir yere yayımlansın (atikolabs.com altında bir sayfa,
      GitHub Pages, Notion public link — hepsi kabul edilir)
- [ ] URL App Store Connect → App Information → Privacy Policy URL alanına girilsin
- [ ] Yayımlanan metin uygulama içi metinle aynı kalsın

### 1.2 `PrivacyInfo.xcprivacy` eksik — **ENGELLEYİCİ değil ama uyarı üretir**

Uygulama `@AppStorage` üzerinden UserDefaults kullanıyor; bu bir "Required Reason
API". Manifest olmadan Apple yükleme sonrası ITMS-91053 uyarı maili gönderiyor ve
zamanla ret sebebine dönüşüyor.

- [x] `UP 25/PrivacyInfo.xcprivacy` oluştur — hazır XML `ASC_PRIVACY_LABELS.md` içinde
- [x] Dosyanın target'a dahil olduğunu doğrula (klasör senkron olduğu için otomatik girmeli)
- [ ] Arşivden sonra `.app` içinde `PrivacyInfo.xcprivacy` var mı diye bak

### 1.3 Zorunlu giriş riski — Guideline 5.1.1(v)

**Bu, kart oyunu olmasından çok daha muhtemel bir ret sebebi.**

Apple: hesap gerektiren anlamlı bir özellik yoksa kullanıcıyı giriş yapmaya
zorlayamazsın. Şu anki kodda çevrimdışı yol yalnızca Supabase yapılandırılmamışken
görünüyor ([AuthView.swift](../UP%2025/AuthView.swift), `showsGuestPath`):

```swift
#if DEBUG
return true
#else
return !session.isConfigured
#endif
```

Yani `SupabaseConfig.plist` ile yayına çıkıldığı anda buton kaybolur ve Game Center
girişi tek yol haline gelir. Oyun botlara karşı oynanan tek kişilik bir oyun
olduğu için Apple "neden hesap zorunlu?" diyebilir.

- [x] Çevrimdışı/misafir oynama yolu **yayın derlemesinde de açık kalsın**
      (koşulu `!session.isConfigured` yerine her zaman açık yap)
- [x] Skor kaydı ve sıralamanın hesap gerektirdiği ekranda açıkça yazsın —
      hesabın *ne işe yaradığı* görünürse Apple'ın itirazı zaten kalmaz

### 1.4 Yaş derecelendirme anketi

- [ ] "Simulated Gambling" / kumar sorularına **HAYIR** de. İskambil kağıdı
      kullanmak kumar değildir; Apple bu soruyu slot, poker, rulet gibi sanal
      parayla bahis yapılan oyunlar için soruyor. Yanlışlıkla evet demek oyunu
      gereksiz yere en üst yaş grubuna atar.
- [ ] Şiddet, korku, cinsellik, madde kullanımı: hepsi yok
- [ ] Hedef: 4+

### 1.5 Ekran görüntüleri

Cihaz ailesi iPhone **ve** iPad olduğu için ikisi de zorunlu. Sadece iPhone
görselleriyle gönderim kabul edilmiyor.

- [ ] iPhone — en büyük ekran boyutu için set
- [ ] iPad — 13" set
- [ ] Görsellerde gerçek oyun ekranı olsun; sahte arayüz veya mockup çerçeve kullanma

---

## FAZ 2 — Gönderim formu

- [ ] **Kategori:** Games → Card (ikincil: Games → Family veya Board)
- [ ] **Support URL** — zorunlu alan, çalışan bir sayfa olmalı
- [ ] **Copyright** — `2026 Atiko Labs`
- [ ] **App Privacy** — `ASC_PRIVACY_LABELS.md` tablosunu birebir gir
- [ ] **App Review Information** — demo hesap gerekmiyor; not alanına
      *"The game is fully playable without an account — tap the offline/guest option
      on the sign-in screen. Game Center sign-in only stores statistics."* yaz.
      Bu tek cümle 5.1.1(v) itirazını baştan kesiyor.
- [ ] **Açıklama metni** — "kumar", "bahis", "casino", "para kazan" gibi kelimeler
      geçmesin; ASO için bile olsa bu kelimeler incelemeyi zorlaştırır
- [ ] **Export compliance** — `ITSAppUsesNonExemptEncryption` cevaplandı (No)

---

## KIRMIZI BAYRAKLAR

Bu uygulamaya özel, gerçekten ret yiyebileceğimiz noktalar:

1. **Beyan uyuşmazlığı.** ASC App Privacy ↔ `PrivacyInfo.xcprivacy` ↔ gizlilik
   politikası üçlüsünden biri diğerini tutmazsa "Inconsistent Privacy Declaration"
   gelir. Üçü birlikte güncellenmeli.
2. **E-postayı yanlış beyan etmek.** Backend'de `profiles.email` dolu görünüyor ama
   bu `gc_<playerID>@gamecenter.yirmibes.local` biçiminde sentetik bir değer.
   ASC'de "Email Address" işaretlemek yanlış beyan olur.
3. **Zorunlu giriş** — yukarıda 1.3.
4. **Gizlilik politikası URL'sinin ölü olması.** Apple linki gerçekten açar.
5. **iPad görselinin eksikliği** — iPad desteği açıkken en sık atlanan madde.
6. **Game Center capability'sini kaldırmak.** Entitlement ile provisioning profile
   uyuşmazsa build reddedilir.

---

## Durum

| Madde | Durum |
|---|---|
| Uygulama ikonu (1024 + dark + tinted) | ✅ |
| Export compliance | ✅ |
| Hesap silme (uygulama içi, sunucu tarafı cascade) | ✅ |
| Çevrimdışı oynanabilirlik | ✅ yayın derlemesinde de açık (1.3) |
| Uygulama içi gizlilik + şartlar metni | ✅ `UP 25/Legal/*.md` (docs ile senkron) |
| Gizlilik politikası URL'si | ❌ (ASC'ye yayımlanmış URL girilmeli) |
| `PrivacyInfo.xcprivacy` | ✅ |
| Ekran görüntüleri (iPhone + iPad) | ❌ |
| Yaş derecelendirme anketi | ❌ |
| Support URL | ❌ |
