# 25-40 Steam release handover

The repository produces three Steam clients:

- macOS 13+, universal, from the SwiftUI app (`scripts/build-steam-macos.sh`)
- Windows x64, from the desktop client (`scripts/build-steam-desktop.sh`)
- Steam Deck, as a native Linux x64 binary of that same desktop client

The desktop client plays at a fixed 1280×800 layout, letterboxed if the window
is another size. On Steam Deck (`SteamDeck=1`) it opens fullscreen. Keyboard,
mouse, and a standard gamepad (Steam Deck uses the same south/east button
layout as an Xbox pad) can drive the menus and the match.

## What is implemented

- native macOS 13+ target from the shared SwiftUI code
- Windows and Linux/Steam Deck client with the same rules, scoring, and tempo
- offline-first launch with no Game Center, Supabase, or Steam identity
- keyboard, mouse, and gamepad controls, including number keys 1–9 for cards
- durable progress. The Mac app uses
  `~/Library/Application Support/Atiko Labs/25-40/save.json`.
  The desktop client uses the same relative path under the platform config
  directory: Windows `%AppData%`, Linux `$XDG_CONFIG_HOME` or `~/.config`
- hardened-runtime Steam overlay entitlements without App Sandbox on macOS
- Developer ID signing, notarization, stapling, and verification script
- SteamPipe app/depot templates for macOS, Windows, and Linux
- macOS app icon assets and Steam-aware legal copy

Runtime Steamworks APIs are intentionally not linked. They are not required to
sell a game on Steam. Achievements, leaderboards, and Steam identity must not
be selected on the store page until separately implemented. Do not mark Full
Controller Support until the build has been played through on a Steam Deck;
the client is written for a controller, and that store flag is a hands-on claim.

The desktop client does not include the guided two-round demo. "How to play"
is the controller-accessible rules screen. The ten languages from the Mac app
are included. Chinese and Japanese use a font that covers the in-game text.

## Portal work that requires the publisher account

1. Complete Steamworks onboarding, tax, banking, and the Steam Direct fee.
2. Obtain the App ID, macOS, Windows, and Linux depot IDs, package IDs, and an
   upload account.
3. Add all three depots to the Developer Comp and customer packages.
4. Configure launch options:
   - macOS executable `25-40.app`
   - Windows executable `25-40.exe`
   - Linux executable `25-40`
5. On macOS, mark `64 Bit Binaries Included` and `App Bundles Are Notarized`.
   Set the minimum requirement to macOS 13 and disclose Apple Silicon and Intel.
6. On Windows, require 64-bit Windows 10 or later.
7. On Linux, target Steam Deck: 1280×800, fullscreen when Steam launches it.
   The native binary is the Deck build. Proton can run `25-40.exe` as a
   fallback, but it is not the preferred Deck launch option.
8. Upload to a private beta branch and install it through Steam on a Mac, a
   Windows PC, and a Steam Deck.
9. Keep the Coming Soon page public for Steam's required period and submit the
   near-final store page and build for review.

App IDs, depot IDs, certificates, credentials, prices, release date, and store
publishing cannot be completed from source code and must be supplied by the
Steamworks and Apple account owners.

## Build and upload

Follow `steam/README.md`.

The macOS script requires an Apple Developer ID certificate, a notarytool
profile, and the three environment variables named in that README. Do not
upload a DMG. Upload the loose, notarized `25-40.app` in `dist/steam-content`.

The desktop script writes:

- `dist/steam-windows/25-40.exe`
- `dist/steam-linux/25-40`
- `dist/desktop-macos/25-40` when run on a Mac

`dist/desktop-macos/25-40` is only for trying the Windows/Deck client on a Mac.
The macOS Steam depot stays the Swift app.

Linux cross-compilation uses a local Zig toolchain and Debian sysroot under
`.toolchain/`. That directory is not part of the repository. Without it, the
script still produces the Windows executable.

## Steam Cloud (optional)

The game does not require cloud saves. To enable Auto-Cloud later, use one
root per operating system and the same relative path `Atiko Labs/25-40`,
pattern `save.json`:

- macOS: `MacAppSupport`
- Windows: `WinAppDataRoaming`
- Linux and Steam Deck: `LinuxXdgConfigHome`

The Mac app and the desktop client share that file if both run on one Mac.
The Mac app keeps the counts and ignores the extra desktop fields. A later save
from the Mac app drops the desktop resume, language, and sound fields.

Test first launch, upload, second-device download, conflict handling,
reinstall, and offline-to-online transitions before advertising Steam Cloud.

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

Only languages fully reviewed in the shipped build should be selected as
supported. Do not claim achievements, leaderboards, or Full Controller Support
until each one has been tested on the target device.

## Final validation

```sh
xcodebuild -project "UP 25.xcodeproj" -scheme "UP 25" \
  -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build

xcodebuild -project "UP 25.xcodeproj" -scheme "UP 25" \
  -sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO build

./scripts/build-steam-desktop.sh
```

After notarization, verify the Mac app with `codesign`, `stapler`, and
`spctl`; the macOS release script runs all three. Then test launch only from a
Steam install, not from Xcode or the archive folder. On Deck, confirm the
native Linux build from a Steam install in gaming mode: menus, a full match,
pause, and return to the menu with the controller only.
