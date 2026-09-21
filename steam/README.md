# SteamPipe configuration

These files package the native macOS build. Replace the placeholders only after
Steamworks has created the product's App ID and macOS Depot ID.

## Prepare the VDF files

1. Copy `app_build_APPID.vdf.example` to `app_build_<APP_ID>.vdf`.
2. Copy `depot_build_MACOS_DEPOT_ID.vdf.example` to
   `depot_build_<MACOS_DEPOT_ID>.vdf`.
3. Replace `<APP_ID>` and `<MACOS_DEPOT_ID>` in both copies.
4. Keep the generated files local if they contain account-specific details.

## Build and notarize

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
`dist/steam-content/25-40.app`.

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
depot and do not advertise achievements, leaderboards, Full Controller Support,
or Steam Cloud until each feature is configured and tested.
