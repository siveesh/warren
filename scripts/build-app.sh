#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Warren.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LIBRARY_DIR="$CONTENTS_DIR/Library"
HELPER_TOOLS_DIR="$LIBRARY_DIR/HelperTools"
LAUNCH_DAEMONS_DIR="$LIBRARY_DIR/LaunchDaemons"
LOGIN_ITEMS_DIR="$LIBRARY_DIR/LoginItems"
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"
LOCALIZATION_DIR="$ROOT_DIR/Resources/Localization"
INFO_TEMPLATE="$ROOT_DIR/Resources/Bundling/Info.plist.template"
MENU_BAR_HELPER_INFO_TEMPLATE="$ROOT_DIR/Resources/Bundling/MenuBarHelper-Info.plist.template"
HELPER_PLIST_TEMPLATE="$ROOT_DIR/Resources/Bundling/com.siveesh.skmole.privilegedhelper.plist.template"
SOURCE_ICON="$ROOT_DIR/Resources/AppIcon-source.png"
HELPER_INFO_PLIST="$ROOT_DIR/Resources/Bundling/PrivilegedHelper-Info.plist"
WIDGETS_INFO_TEMPLATE="$ROOT_DIR/Resources/Bundling/Widgets-Info.plist.template"
WIDGETS_ENTITLEMENTS="$ROOT_DIR/Resources/Bundling/Widgets.entitlements"
COMPANION_ENTITLEMENTS="$ROOT_DIR/Resources/Bundling/Companion.entitlements"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
WIDGETS_APPEX_DIR="$PLUGINS_DIR/Warren Widgets.appex"

# Signing: SKMOLE_CODESIGN_IDENTITY picks the identity ("-" signs ad hoc). With none given, a Developer ID Application
# identity in the keychain is used, which is what the privileged helper and the widgets need to run.
SIGN_IDENTITY="${SKMOLE_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi
TEAM_ID=""
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    TEAM_ID="$(printf '%s' "$SIGN_IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')"
fi

# The helper's embedded Info.plist and the extension must carry the app's own version, since the app asks the helper
# for a build no older than its own.
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_TEMPLATE")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_TEMPLATE")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$HELPER_INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$HELPER_INFO_PLIST"

mkdir -p "$DIST_DIR"

if [[ -f "$SOURCE_ICON" ]]; then
    "$ROOT_DIR/scripts/build-icon.sh" "$SOURCE_ICON"
fi

swift build -c release --package-path "$ROOT_DIR" --product SKMoleApp
swift build -c release --package-path "$ROOT_DIR" --product SKMolePrivilegedHelper
swift build -c release --package-path "$ROOT_DIR" --product SKMoleMenuBarHelper
swift build -c release --package-path "$ROOT_DIR" --product SKMoleWidgets

BUILD_DIR="$(swift build -c release --show-bin-path --package-path "$ROOT_DIR")"
BINARY_PATH="$BUILD_DIR/SKMoleApp"
HELPER_BINARY_PATH="$BUILD_DIR/SKMolePrivilegedHelper"
MENU_BAR_HELPER_BINARY_PATH="$BUILD_DIR/SKMoleMenuBarHelper"
WIDGETS_BINARY_PATH="$BUILD_DIR/SKMoleWidgets"
MENU_BAR_HELPER_APP_DIR="$LOGIN_ITEMS_DIR/Warren Companion.app"
MENU_BAR_HELPER_CONTENTS_DIR="$MENU_BAR_HELPER_APP_DIR/Contents"
MENU_BAR_HELPER_MACOS_DIR="$MENU_BAR_HELPER_CONTENTS_DIR/MacOS"
MENU_BAR_HELPER_RESOURCES_DIR="$MENU_BAR_HELPER_CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$WIDGETS_APPEX_DIR/Contents/MacOS" "$MACOS_DIR" "$RESOURCES_DIR" "$HELPER_TOOLS_DIR" "$LAUNCH_DAEMONS_DIR" "$LOGIN_ITEMS_DIR" "$MENU_BAR_HELPER_MACOS_DIR" "$MENU_BAR_HELPER_RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/Warren"
chmod +x "$MACOS_DIR/Warren"
cp "$INFO_TEMPLATE" "$CONTENTS_DIR/Info.plist"
cp "$HELPER_BINARY_PATH" "$HELPER_TOOLS_DIR/com.siveesh.skmole.privilegedhelper"
chmod +x "$HELPER_TOOLS_DIR/com.siveesh.skmole.privilegedhelper"
cp "$HELPER_PLIST_TEMPLATE" "$LAUNCH_DAEMONS_DIR/com.siveesh.skmole.privilegedhelper.plist"
if [[ -n "$TEAM_ID" ]]; then
    # launchd starts the helper only from code signed by this team, with this identifier.
    DAEMON_PLIST="$LAUNCH_DAEMONS_DIR/com.siveesh.skmole.privilegedhelper.plist"
    /usr/libexec/PlistBuddy -c "Add :SpawnConstraint dict" "$DAEMON_PLIST"
    /usr/libexec/PlistBuddy -c "Add :SpawnConstraint:team-identifier string $TEAM_ID" "$DAEMON_PLIST"
    /usr/libexec/PlistBuddy -c "Add :SpawnConstraint:signing-identifier string com.siveesh.skmole.privilegedhelper" "$DAEMON_PLIST"
fi
cp "$WIDGETS_BINARY_PATH" "$WIDGETS_APPEX_DIR/Contents/MacOS/WarrenWidgets"
chmod +x "$WIDGETS_APPEX_DIR/Contents/MacOS/WarrenWidgets"
cp "$WIDGETS_INFO_TEMPLATE" "$WIDGETS_APPEX_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$WIDGETS_APPEX_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$WIDGETS_APPEX_DIR/Contents/Info.plist"
cp "$MENU_BAR_HELPER_BINARY_PATH" "$MENU_BAR_HELPER_MACOS_DIR/Warren Companion"
chmod +x "$MENU_BAR_HELPER_MACOS_DIR/Warren Companion"
cp "$MENU_BAR_HELPER_INFO_TEMPLATE" "$MENU_BAR_HELPER_CONTENTS_DIR/Info.plist"

mkdir -p "$RESOURCES_DIR/Licenses"
cp "$ROOT_DIR/LICENSE" "$ROOT_DIR/NOTICE.md" "$RESOURCES_DIR/Licenses/"

if [[ -f "$ICON_PATH" ]]; then
    cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
    cp "$ICON_PATH" "$MENU_BAR_HELPER_RESOURCES_DIR/AppIcon.icns"
fi

if [[ -d "$LOCALIZATION_DIR" ]]; then
    cp -R "$LOCALIZATION_DIR"/. "$RESOURCES_DIR"/
fi

if command -v codesign >/dev/null 2>&1; then
    SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
    COMPANION_ARGS=()
    WIDGET_ARGS=()
    if [[ "$SIGN_IDENTITY" != "-" ]]; then
        # Developer ID distribution requires a secure timestamp and hardened runtime.
        SIGN_ARGS+=(--options runtime --timestamp)
        # The companion writes, and the sandboxed widgets read, the readings in the team's app group.
        COMPANION_ARGS=(--entitlements "$COMPANION_ENTITLEMENTS")
        WIDGET_ARGS=(--entitlements "$WIDGETS_ENTITLEMENTS")
    fi

    # Sign nested code from the inside out so the enclosing app seals each signature.
    codesign "${SIGN_ARGS[@]}" --identifier "com.siveesh.skmole.privilegedhelper" "$HELPER_TOOLS_DIR/com.siveesh.skmole.privilegedhelper"
    codesign "${SIGN_ARGS[@]}" ${WIDGET_ARGS[@]+"${WIDGET_ARGS[@]}"} --identifier "com.siveesh.skmole.widgets" "$WIDGETS_APPEX_DIR"
    codesign "${SIGN_ARGS[@]}" ${COMPANION_ARGS[@]+"${COMPANION_ARGS[@]}"} --identifier "com.siveesh.skmole.menubar" "$MENU_BAR_HELPER_APP_DIR"
    codesign "${SIGN_ARGS[@]}" --identifier "com.siveesh.skmole" "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

echo "Built app bundle at:"
echo "  $APP_DIR"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Note: signed ad hoc. The privileged helper and widgets need a Developer ID Application identity (SKMOLE_CODESIGN_IDENTITY)."
else
    echo "Signed with: $SIGN_IDENTITY"
fi
