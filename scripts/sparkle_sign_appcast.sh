#!/bin/zsh

# Signs the notarized ZIP with Sparkle EdDSA and updates appcast.xml.
# Run this after release_notarize.sh completes successfully.
#
# Usage:
#   scripts/sparkle_sign_appcast.sh
#
# Environment variables (optional):
#   DOWNLOAD_URL_PREFIX  - Base URL for update downloads
#                          (default: https://github.com/yusuke/tiley/releases/download)
#   APPCAST_DIR          - Directory where appcast.xml and ZIPs are managed
#                          (default: build/sparkle)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Sparkle CLI tools
SPARKLE_BIN="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"

# Paths from release_notarize.sh output
ZIP_PATH="${ZIP_PATH:-build/Tiley.zip}"
EXPORT_PATH="${EXPORT_PATH:-build/export}"
APP_NAME="${APP_NAME:-Tiley.app}"
EXPORTED_APP_PATH="$EXPORT_PATH/$APP_NAME"

# Sparkle appcast settings
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/yusuke/tiley/releases/download}"
APPCAST_DIR="${APPCAST_DIR:-build/sparkle}"

# Verify prerequisites
if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "Error: sign_update not found at $SPARKLE_BIN"
  echo "Run 'swift build' first to fetch Sparkle artifacts."
  exit 1
fi

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "Error: generate_appcast not found at $SPARKLE_BIN"
  exit 1
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Error: Notarized ZIP not found at $ZIP_PATH"
  echo "Run scripts/release_notarize.sh first."
  exit 1
fi

if [[ ! -d "$EXPORTED_APP_PATH" ]]; then
  echo "Error: Exported app not found at $EXPORTED_APP_PATH"
  exit 1
fi

# Extract version from the app bundle
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$EXPORTED_APP_PATH/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$EXPORTED_APP_PATH/Contents/Info.plist")
echo "App version: $APP_VERSION (build $BUILD_NUMBER)"

# Sign the ZIP with Sparkle EdDSA (key is read from Keychain automatically)
echo "Signing ZIP with Sparkle EdDSA"
SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" -p)
echo "EdDSA signature: $SIGNATURE"

# Prepare appcast directory
mkdir -p "$APPCAST_DIR"

# Copy existing appcast.xml if present in docs/
if [[ -f "$PROJECT_ROOT/docs/appcast.xml" && ! -f "$APPCAST_DIR/appcast.xml" ]]; then
  echo "Copying existing appcast.xml from docs/"
  cp "$PROJECT_ROOT/docs/appcast.xml" "$APPCAST_DIR/"
fi

# Copy the notarized ZIP with version-tagged filename
VERSIONED_ZIP="Tiley-${APP_VERSION}.zip"
cp "$ZIP_PATH" "$APPCAST_DIR/$VERSIONED_ZIP"
echo "Copied ZIP to $APPCAST_DIR/$VERSIONED_ZIP"

# Generate/update appcast.xml
DOWNLOAD_URL="$DOWNLOAD_URL_PREFIX/v$APP_VERSION/$VERSIONED_ZIP"
echo "Download URL: $DOWNLOAD_URL"

echo "Generating appcast.xml"
"$GENERATE_APPCAST" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX/v$APP_VERSION/" \
  -o "$APPCAST_DIR/appcast.xml" \
  "$APPCAST_DIR"

# Copy updated appcast.xml to docs/ for GitHub Pages
mkdir -p "$PROJECT_ROOT/docs"
cp "$APPCAST_DIR/appcast.xml" "$PROJECT_ROOT/docs/appcast.xml"
echo "Updated docs/appcast.xml"

echo ""
echo "=== Sparkle signing complete ==="
echo "  Version:     $APP_VERSION (build $BUILD_NUMBER)"
echo "  Signature:   $SIGNATURE"
echo "  Appcast:     docs/appcast.xml"
echo "  ZIP:         $APPCAST_DIR/$VERSIONED_ZIP"
echo ""
echo "Next steps:"
echo "  1. Commit docs/appcast.xml"
echo "  2. Create GitHub Release tagged v$APP_VERSION"
echo "  3. Upload $APPCAST_DIR/$VERSIONED_ZIP to the release"
