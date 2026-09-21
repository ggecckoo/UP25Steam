# docs

App Store ve Steam çıkış hazırlığı dokümanları.

| Dosya | Ne işe yarar | Dil |
|---|---|---|
| [SUPABASE_HANDOVER.md](SUPABASE_HANDOVER.md) | **Çağatay'a:** backend'i ayağa kaldırmak için yapılacaklar. Game Center girişi bunlar olmadan çalışmıyor. | TR |
| [SIGNING.md](SIGNING.md) | Çağatay vs Ömer team/bundle; `Signing.Omer.xcconfig` | TR |
| [APPLE_COMPLIANCE.md](APPLE_COMPLIANCE.md) | Ret önleme kontrol listesi. Neyin gerektiği, neyin **gerekmediği**. Buradan başla. | TR |
| [ASC_PRIVACY_LABELS.md](ASC_PRIVACY_LABELS.md) | App Store Connect → App Privacy'ye girilecek tablolar + hazır `PrivacyInfo.xcprivacy` | TR |
| [STEAM_RELEASE.md](STEAM_RELEASE.md) | macOS Steam paketi, portal ayarları, mağaza varlıkları ve son doğrulama | EN |
| [PRIVACY_POLICY.md](PRIVACY_POLICY.md) | Yayımlanacak gizlilik politikası | EN |
| [TERMS_OF_SERVICE.md](TERMS_OF_SERVICE.md) | Kullanım şartları | EN |

Legal metinler İngilizce çünkü hem uygulama içi kopya İngilizce, hem de App Store
incelemecisi İngilizce okuyor. Çalışma dokümanları Türkçe.

## Senkron tutulması gerekenler

Bir veri alanı, SDK veya izin eklendiğinde şu dördü **aynı anda** güncellenmeli —
biri unutulursa Apple "Inconsistent Privacy Declaration" ile reddediyor:

1. App Store Connect → App Privacy
2. `UP 25/PrivacyInfo.xcprivacy`
3. `docs/PRIVACY_POLICY.md` **ve** uygulama paketi `UP 25/Legal/PrivacyPolicy.md`
   (şartlar için `docs/TERMS_OF_SERVICE.md` ↔ `UP 25/Legal/TermsOfService.md`)
4. Uygulama içi kısa yedek metin — `settings.privacy.body` / `settings.terms.body`
   (`UP 25/Localizable.xcstrings`); birincil metin Legal/*.md üzerinden yüklenir

Legal dosyaları değiştirildiğinde **docs/** ve **UP 25/Legal/** birlikte güncellenmeli.
Uygulama dili Türkçe ise `PrivacyPolicy-tr.md` / `TermsOfService-tr.md`, aksi halde İngilizce dosyalar gösterilir.
