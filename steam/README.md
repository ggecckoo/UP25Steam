# SteamPipe configuration

These files package the macOS app and the Windows / Steam Deck desktop client.
Replace the placeholders only after Steamworks has created the App ID and the
three depot IDs.

## Prepare the VDF files

1. Copy `app_build_APPID.vdf.example` to `app_build_<APP_ID>.vdf`.
2. Copy each `depot_build_*_DEPOT_ID.vdf.example` to
   `depot_build_<DEPOT_ID>.vdf`.
3. Replace `<APP_ID>`, `<MACOS_DEPOT_ID>`, `<WINDOWS_DEPOT_ID>`, and
   `<LINUX_DEPOT_ID>` in the copies.
4. Keep the generated files local if they contain account-specific details.

## macOS

Create a notarytool keychain profile once:

```sh
xcrun notarytool store-credentials "25-40-notary"
```

Then run:

```sh
DEVELOPMENT_TEAM="YOUR_TEAM_ID" \
DEVELOPER_ID_APPLICATION="Developer ID Application: Company (TEAMID)" \
NOTARY_PROFILE="25-40-notary" \
./scripts/build-steam-macos.sh
```

The final, universal and stapled app is written to
`dist/steam-content/25-40.app`. The Steam launch option executable is
`25-40.app`.

## Windows and Steam Deck

```sh
./scripts/build-steam-desktop.sh
```

This writes `dist/steam-windows/25-40.exe` and, when the local Linux toolchain
is present, `dist/steam-linux/25-40`. Launch option executables are `25-40.exe`
and `25-40`. On a Mac the script also writes `dist/desktop-macos/25-40` so the
same client can be tried locally. That file is not the macOS Steam depot.

Steam Deck should launch the Linux binary. Set the game to fullscreen; the
client does that itself when Steam sets `SteamDeck=1`. Proton can run the
Windows executable as a fallback.

## Upload

Use the Steamworks SDK's `steamcmd`:

```sh
steamcmd +login YOUR_BUILD_ACCOUNT \
  +run_app_build /absolute/path/to/steam/app_build_<APP_ID>.vdf \
  +quit
```

Set the uploaded build live on a password-protected beta branch first. Do not
put a Steam password, Web API publisher key, or notary credential in this
repository.

The runtime Steamworks API is not linked. Do not add `steam_appid.txt` to the
depot and do not advertise achievements, leaderboards, or Steam Cloud until
each feature is configured and tested. Enable Full Controller Support only
after a full match has been played on a Steam Deck with the controller.
