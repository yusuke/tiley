#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
  source "$SCRIPT_DIR/env.sh"
fi

PROJECT="Tiley.xcodeproj"
SCHEME="Tiley"
CONFIGURATION="Release"
ARCHIVE_PATH="${ARCHIVE_PATH:-build/Tiley.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-build/export}"
APP_NAME="${APP_NAME:-Tiley.app}"
DMG_PATH="${DMG_PATH:-build/Tiley.dmg}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"
API_KEY_PATH="${API_KEY_PATH:-}"
API_KEY_ID="${API_KEY_ID:-}"
API_ISSUER_ID="${API_ISSUER_ID:-}"

if [[ -n "${API_KEY_PATH}" && "${API_KEY_PATH}" == "~"* ]]; then
  API_KEY_PATH="${HOME}${API_KEY_PATH#\~}"
fi

if [[ -z "${KEYCHAIN_PROFILE}" && ( -z "${API_KEY_PATH}" || -z "${API_KEY_ID}" || -z "${API_ISSUER_ID}" ) ]]; then
  echo "Either KEYCHAIN_PROFILE or all of API_KEY_PATH, API_KEY_ID, API_ISSUER_ID is required."
  [[ -z "${API_KEY_PATH}" ]] && echo "Missing: API_KEY_PATH"
  [[ -z "${API_KEY_ID}" ]] && echo "Missing: API_KEY_ID"
  [[ -z "${API_ISSUER_ID}" ]] && echo "Missing: API_ISSUER_ID"
  echo "Examples:"
  echo "  KEYCHAIN_PROFILE=AC_NOTARY scripts/release_notarize.sh"
  echo "  API_KEY_PATH=~/keys/AuthKey_ABC123XYZ.p8 API_KEY_ID=ABC123XYZ API_ISSUER_ID=00000000-0000-0000-0000-000000000000 scripts/release_notarize.sh"
  exit 1
fi

if [[ -z "${KEYCHAIN_PROFILE}" && ! -f "${API_KEY_PATH}" ]]; then
  echo "API key file not found: ${API_KEY_PATH}"
  exit 1
fi

# Check if this version+build already exists in appcast.xml (before expensive archive/notarize)
PBXPROJ="$PROJECT_ROOT/Tiley.xcodeproj/project.pbxproj"
EXISTING_APPCAST="$PROJECT_ROOT/docs/appcast.xml"
if [[ -f "$PBXPROJ" && -f "$EXISTING_APPCAST" ]]; then
  PRE_APP_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *\(.*\);/\1/' | tr -d ' ')
  PRE_BUILD_NUMBER=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= *\(.*\);/\1/' | tr -d ' ')
  if [[ -n "$PRE_APP_VERSION" && -n "$PRE_BUILD_NUMBER" ]]; then
    if grep -q "<sparkle:shortVersionString>${PRE_APP_VERSION}</sparkle:shortVersionString>" "$EXISTING_APPCAST" \
      && grep -q "<sparkle:version>${PRE_BUILD_NUMBER}</sparkle:version>" "$EXISTING_APPCAST"; then
      echo "Error: Version $PRE_APP_VERSION (build $PRE_BUILD_NUMBER) already exists in appcast.xml."
      echo "Bump the version or build number before releasing."
      exit 1
    fi
  fi
fi

echo "Cleaning previous build artifacts"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$DMG_PATH"
mkdir -p build

echo "Archiving app"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Archived app not found at $APP_PATH"
  exit 1
fi

echo "Preparing export directory"
mkdir -p "$EXPORT_PATH"
cp -R "$APP_PATH" "$EXPORT_PATH/"

EXPORTED_APP_PATH="$EXPORT_PATH/$APP_NAME"
CODESIGN_ID="${CODESIGN_ID:-Developer ID Application}"

echo "Re-signing embedded frameworks for notarization"
FRAMEWORKS_PATH="$EXPORTED_APP_PATH/Contents/Frameworks"
if [[ -d "$FRAMEWORKS_PATH" ]]; then
  # Sign all nested binaries (XPC services, helper apps, dylibs) inside-out
  find "$FRAMEWORKS_PATH" -type f \( -name '*.dylib' -o -perm +111 \) -print0 | while IFS= read -r -d '' binary; do
    # Skip non-Mach-O files
    file "$binary" | grep -q "Mach-O" || continue
    echo "  Signing: ${binary#$EXPORTED_APP_PATH/}"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_ID" "$binary"
  done
  # Sign .xpc bundles
  find "$FRAMEWORKS_PATH" -name '*.xpc' -type d -print0 | while IFS= read -r -d '' xpc; do
    echo "  Signing: ${xpc#$EXPORTED_APP_PATH/}"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_ID" "$xpc"
  done
  # Sign .app bundles inside frameworks
  find "$FRAMEWORKS_PATH" -name '*.app' -type d -print0 | while IFS= read -r -d '' app; do
    echo "  Signing: ${app#$EXPORTED_APP_PATH/}"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_ID" "$app"
  done
  # Sign the framework itself
  find "$FRAMEWORKS_PATH" -name '*.framework' -type d -maxdepth 1 -print0 | while IFS= read -r -d '' fw; do
    echo "  Signing: ${fw#$EXPORTED_APP_PATH/}"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_ID" "$fw"
  done
fi

echo "Re-signing app bundle"
codesign --force --options runtime --timestamp --sign "$CODESIGN_ID" "$EXPORTED_APP_PATH"

echo "Submitting app for notarization (via temporary zip)"
NOTARIZE_ZIP="build/Tiley-notarize-tmp.zip"
ditto -c -k --norsrc --keepParent "$EXPORTED_APP_PATH" "$NOTARIZE_ZIP"

if [[ -n "${KEYCHAIN_PROFILE}" ]]; then
  xcrun notarytool submit "$NOTARIZE_ZIP" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait
else
  xcrun notarytool submit "$NOTARIZE_ZIP" \
    --key "$API_KEY_PATH" \
    --key-id "$API_KEY_ID" \
    --issuer "$API_ISSUER_ID" \
    --wait
fi
rm -f "$NOTARIZE_ZIP"

echo "Stapling notarization ticket"
STAPLE_MAX_RETRIES=5
STAPLE_RETRY_INTERVAL=30
for ((i=1; i<=STAPLE_MAX_RETRIES; i++)); do
  if xcrun stapler staple "$EXPORTED_APP_PATH"; then
    break
  fi
  if ((i == STAPLE_MAX_RETRIES)); then
    echo "Stapling failed after $STAPLE_MAX_RETRIES attempts."
    exit 1
  fi
  echo "Stapling attempt $i failed. Retrying in ${STAPLE_RETRY_INTERVAL}s... ($i/$STAPLE_MAX_RETRIES)"
  sleep "$STAPLE_RETRY_INTERVAL"
done

echo "Validating stapled app"
xcrun stapler validate "$EXPORTED_APP_PATH"
spctl -a -vvv -t exec "$EXPORTED_APP_PATH"

# Strip extended attributes to prevent AppleDouble ._files
echo "Stripping extended attributes"
xattr -cr "$EXPORTED_APP_PATH"

# Create DMG with the app and an Applications symlink (custom Finder layout)
echo "Creating DMG"
DMG_STAGING="build/dmg-staging"
DMG_RW="build/Tiley-rw.dmg"
rm -rf "$DMG_STAGING" "$DMG_RW"
mkdir -p "$DMG_STAGING"
cp -R "$EXPORTED_APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Create a read-write DMG first so we can customise the Finder view
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Tiley" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDRW \
  "$DMG_RW"
rm -rf "$DMG_STAGING"

# Mount the read-write DMG
MOUNT_DIR=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen | grep '/Volumes/' | tail -1 | awk -F'\t' '{print $NF}')
echo "Mounted DMG at: $MOUNT_DIR"

# Configure Finder window appearance via AppleScript
echo "Configuring DMG Finder layout"
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "Tiley"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, 640, 640}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set background color of viewOptions to {65535, 65535, 65535}
    set position of item "Tiley.app" of container window to {130, 190}
    set position of item "Applications" of container window to {410, 190}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

# Make sure .DS_Store is flushed to disk
sync

# Detach the DMG
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed read-only format
hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_PATH"
rm -f "$DMG_RW"

echo "Release artifact ready at $EXPORTED_APP_PATH"
echo "DMG ready at $DMG_PATH"
