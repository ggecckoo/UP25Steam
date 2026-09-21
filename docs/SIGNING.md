# İmzalama — iki Apple takımı

`main` varsayılanı Çağatay’ın kimliğidir. Ömer’in TestFlight derlemesi ayrı
bundle / team kullanır; backend her ikisini de kabul eder.

| | Çağatay (`main`) | Ömer (TestFlight) |
|---|---|---|
| Team ID | `7AVYNXTB6V` | `Z927F9H783` |
| Bundle ID | `com.atikolabs.UP-25` | `com.atikolabs.up2540` |
| Build | `1` (pbxproj) | `1.001` (override) |

## Çağatay

[UP 25.xcodeproj/project.pbxproj](../UP%2025.xcodeproj/project.pbxproj) içindeki
`DEVELOPMENT_TEAM` / `PRODUCT_BUNDLE_IDENTIFIER` değerlerini kullan. Değiştirme.

## Ömer

1. [UP 25/Config/Signing.Omer.xcconfig](../UP%2025/Config/Signing.Omer.xcconfig)
   değerlerini oku.
2. Xcode → target **UP 25** → **Signing & Capabilities**:
   - Team: Ömer Faruk ATICI (`Z927F9H783`)
   - Bundle Identifier: `com.atikolabs.up2540`
3. Build Settings → **Current Project Version** = `1.001` (yeni TF yüklemesi için artır).
4. Product → Archive → TestFlight.

İsteğe bağlı: xcconfig’i target’ın Debug/Release configuration’ına
`#include` ile bağlayabilirsin; bağlı değilse Xcode’da elle uygula — `main`
pbxproj’i kirlenmesin diye bilerek ayrı tutuluyor.

## Supabase

Edge function `ALLOWED_BUNDLES` her iki bundle’ı içerir. Yeni bundle eklemek için:

```bash
./.bin/supabase secrets set ALLOWED_BUNDLES="com.atikolabs.UP-25,com.atikolabs.up2540"
./.bin/supabase functions deploy gamecenter-auth --no-verify-jwt
```
