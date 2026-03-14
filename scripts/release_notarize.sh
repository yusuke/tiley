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
ZIP_PATH="${ZIP_PATH:-build/Tiley.zip}"
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

echo "Cleaning previous build artifacts"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$ZIP_PATH"
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

echo "Creating zip for notarization"
ditto -c -k --keepParent "$EXPORTED_APP_PATH" "$ZIP_PATH"

echo "Submitting for notarization"
if [[ -n "${KEYCHAIN_PROFILE}" ]]; then
  xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait
else
  xcrun notarytool submit "$ZIP_PATH" \
    --key "$API_KEY_PATH" \
    --key-id "$API_KEY_ID" \
    --issuer "$API_ISSUER_ID" \
    --wait
fi

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

echo "Release artifact ready at $EXPORTED_APP_PATH"
