# 25-40 Steam release handover

The repository now produces a native macOS Steam build. It does not produce a
Windows or Linux binary; consequently this release will not run on Steam Deck.
A Windows/Deck release requires a separate client port because SwiftUI is an
Apple framework.

## What is implemented

- native macOS 13+ target from the shared SwiftUI code
- universal `arm64` and `x86_64` release archive
- offline-first Steam launch with no Game Center or Supabase dependency
- mouse/trackpad controls, Escape handling, and number keys 1–9 for cards
- durable progress at
  `~/Library/Application Support/Atiko Labs/25-40/save.json`
- hardened-runtime Steam overlay entitlements without App Sandbox
- Developer ID signing, notarization, stapling, and verification script
- SteamPipe app/depot templates
- macOS app icon assets and Steam-aware legal copy

Runtime Steamworks APIs are intentionally not linked. They are not required to
sell a game on Steam. Achievements, leaderboards, Steam identity, and controller
support must not be selected on the store page until separately implemented.

## Portal work that requires the publisher account

1. Complete Steamworks onboarding, tax, banking, and the Steam Direct fee.
2. Obtain the App ID, macOS Depot ID, package IDs, and an upload account.
3. Add the macOS depot to the Developer Comp and customer packages.
4. Configure a macOS launch option whose executable is `25-40.app`.
5. Mark `64 Bit Binaries Included` and `App Bundles Are Notarized`.
6. Set the minimum requirement to macOS 13 and disclose that both Apple Silicon
   and Intel are supported.
7. Upload to a private beta branch and install it through Steam on clean Apple
   Silicon and Intel Macs.
8. Keep the Coming Soon page public for Steam's required period and submit the
   near-final store page and build for review.

App IDs, depot IDs, certificates, credentials, prices, release date, and store
publishing cannot be completed from source code and must be supplied by the
Steamworks and Apple account owners.

## Build and upload

Follow `steam/README.md`. The release script requires:

- an active Apple Developer Program membership
- a `Developer ID Application` certificate
- a notarytool keychain profile
- the current Steamworks SDK/SteamPipe tools for upload

Do not upload a DMG. Upload the loose, notarized `25-40.app` bundle produced in
`dist/steam-content`.

## Steam Cloud (optional)

The game does not require cloud saves. To enable Auto-Cloud later, configure:

- root: `MacAppSupport`
- subdirectory: `Atiko Labs/25-40`
- file pattern: `save.json`
- platform: macOS

Test first launch, upload, second-Mac download, conflict handling, reinstall,
and offline-to-online transitions before advertising Steam Cloud.

## Store page checklist

- gameplay trailer
- at least five real 1920×1080 gameplay screenshots
- header capsule 920×430
- small capsule 462×174
- main capsule 1232×706
- vertical capsule 748×896
- shortcut icon 256×256
- client icon 184×184 JPG
- library capsule 600×900
- library hero 3840×1240
- library logo and 920×430 library header
- completed content survey and truthful generative-AI disclosure
- public privacy-policy URL containing the current `docs/PRIVACY_POLICY.md`

Only languages fully reviewed in the desktop build should be selected as
supported. Do not claim Windows, Linux, Steam Deck compatibility, achievements,
leaderboards, or Full Controller Support for this build.

## Final validation

Run the following before each release:

```sh
xcodebuild -project "UP 25.xcodeproj" -scheme "UP 25" \
  -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build

xcodebuild -project "UP 25.xcodeproj" -scheme "UP 25" \
  -sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO build
```

After notarization, verify the output with `codesign`, `stapler`, and `spctl`;
the release script runs all three. Then test launch only from a Steam install,
not from Xcode or the archive folder.
