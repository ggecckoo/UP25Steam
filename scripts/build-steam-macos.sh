#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/UP 25.xcodeproj"
SCHEME="UP 25"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build/steam-macos}"
ARCHIVE="$BUILD_ROOT/25-40.xcarchive"
CONTENT_ROOT="$ROOT/dist/steam-content"
APP="$CONTENT_ROOT/25-40.app"

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to the Apple Developer team ID.}"
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the full Developer ID Application certificate name.}"
: "${NOTARY_PROFILE:?Create a notarytool keychain profile and set NOTARY_PROFILE.}"

rm -rf "$BUILD_ROOT" "$CONTENT_ROOT"
mkdir -p "$BUILD_ROOT" "$CONTENT_ROOT"

xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  SKIP_INSTALL=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

ARCHIVED_APP="$ARCHIVE/Products/Applications/UP 25.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
  echo "Archived app not found: $ARCHIVED_APP" >&2
  exit 1
fi

ditto "$ARCHIVED_APP" "$APP"

NOTARY_ZIP="$BUILD_ROOT/25-40-notarization.zip"
ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo
echo "Steam content is ready:"
echo "  $APP"
echo
echo "Upload the contents of $CONTENT_ROOT with the SteamPipe templates in steam/."
