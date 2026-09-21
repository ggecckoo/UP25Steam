# ASC App Privacy — 25-40 için beyan tablosu

> App Store Connect → My Apps → 25-40 → **App Privacy** bölümüne girilecek cevaplar.
>
> Bu üçü **birebir** tutmak zorunda; Apple review sırasında çapraz kontrol ediyor ve
> uyuşmazlıkta "Inconsistent Privacy Declaration" ile ret geliyor:
> 1. ASC App Privacy (aşağıdaki tablolar)
> 2. `UP 25/PrivacyInfo.xcprivacy`
> 3. `docs/PRIVACY_POLICY.md` + uygulama içi `UP 25/Legal/PrivacyPolicy.md`

---

## Tracking

**App Tracking Transparency: KAPALI.** ATT izni istemiyoruz, IDFA okumuyoruz,
reklam ağı yok, üçüncü taraf analitik yok.

```
NSPrivacyTracking = false
NSPrivacyTrackingDomains = []   (boş)
```

## Data Used to Track You

**Yok.** Bu bölümde hiçbir kategori işaretlenmeyecek.

## Data Linked to You

| Kategori | Alt tür | Amaç |
|---|---|---|
| Identifiers | User ID | App Functionality |
| Contact Info | Name | App Functionality |
| Usage Data | Product Interaction | App Functionality |

- **User ID** — Game Center `teamPlayerID` ve ona bağlı Supabase hesap kimliği.
- **Name** — Game Center görünen adı. Kullanıcının seçtiği bir takma addır ama
  gerçek isim içerebildiği için eksik beyan etmektense burada beyan ediyoruz.
- **Product Interaction** — oynanan oyun sayısı, galibiyet, skor ve sıralama.

## Data Not Linked to You

**Yok.** Kaza raporlarını biz toplamıyoruz; Apple'ın kendi topladığı crash verisi
bizim beyanımıza girmiyor.

---

## Beyan ETMEDİKLERİMİZ ve nedeni

| Kategori | Neden hayır |
|---|---|
| **Email Address** | Gerçek e-posta toplamıyoruz. Backend hesap kimliğini e-posta formatında istediği için `gc_<playerID>@gamecenter.yirmibes.local` biçiminde sentetik, posta alamayan bir adres üretiliyor ([gamecenter-auth/index.ts](../supabase/functions/gamecenter-auth/index.ts)). Bunu "Email Address" diye beyan etmek yanlış olurdu. |
| Device ID | IDFA/IDFV okumuyoruz. |
| Purchases | Uygulamada satın alma yok. |
| Location, Contacts, Photos, Audio, Health, Browsing History | Hiçbirine erişmiyoruz, izin de istemiyoruz. |
| Diagnostics | Kendi crash/analytics SDK'mız yok. |
| Sensitive Info, Financial Info | Yok. |

---

## Required Reason APIs

`PrivacyInfo.xcprivacy` içine girecek tek kategori:

| API kategorisi | Reason kodu | Neden |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | `@AppStorage` ile ses tercihi, dil, tutorial durumu ve yerel oyun sayacı saklanıyor |

Diğer kategoriler (File Timestamp, Disk Space, System Boot Time, Active Keyboards)
**gerekmiyor** — kodda kullanılmıyorlar.

### Eklenecek dosya

`UP 25/PrivacyInfo.xcprivacy` olarak oluşturulup hedefe dahil edilmeli:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeUserID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeName</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeProductInteraction</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

`supabase-swift` kendi manifestini paketi içinde taşıyor; onun topladıklarını
burada tekrar beyan etmiyoruz, Apple gönderim sırasında hepsini birleştiriyor.

---

## Ne zaman güncellenir

Yeni bir SDK, analitik, reklam, satın alma veya yeni bir veri alanı eklendiğinde
yukarıdaki **üç yeri birden** aynı anda güncelle. Tek birini güncellemek en sık
görülen ret sebeplerinden biri.
