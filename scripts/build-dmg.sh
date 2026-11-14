#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Warren.app"
APP_PATH="$DIST_DIR/$APP_NAME"
README_SOURCE="$ROOT_DIR/README.md"
INFO_PLIST="$ROOT_DIR/Resources/Bundling/Info.plist.template"
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_NAME="Warren-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
VOLUME_NAME="Warren ${VERSION}"

if [[ ! -d "$APP_PATH" ]]; then
    "$ROOT_DIR/scripts/build-app.sh"
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Expected app bundle at $APP_PATH but it was not found." >&2
    exit 1
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/skmole-dmg.XXXXXX")"
STAGING_DIR="$TMP_ROOT/staging"
mkdir -p "$STAGING_DIR"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME"
if [[ -f "$README_SOURCE" ]]; then
    cp "$README_SOURCE" "$STAGING_DIR/README.md"
fi
ln -s /Applications "$STAGING_DIR/Applications"

if [[ -f "$ICON_PATH" ]]; then
    cp "$ICON_PATH" "$STAGING_DIR/.VolumeIcon.icns"
    SetFile -a C "$STAGING_DIR" || true
fi

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Sign the disk image with the same Developer ID identity the app was signed with.
SIGN_IDENTITY="$(codesign -dvv "$APP_PATH" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -1)"
if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
    echo "Signed DMG with: $SIGN_IDENTITY"

    # Notarize and staple when a notarytool keychain profile is named (xcrun notarytool store-credentials).
    if [[ -n "${SKMOLE_NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "$SKMOLE_NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG_PATH"
        xcrun stapler validate "$DMG_PATH"
    else
        echo "Not notarized: set SKMOLE_NOTARY_PROFILE to a notarytool keychain profile to notarize and staple."
    fi
else
    echo "Not signed: the app is not signed with a Developer ID Application identity."
fi

echo "Built DMG at:"
echo "  $DMG_PATH"
