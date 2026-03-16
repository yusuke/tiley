#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

PROJECT="Tiley.xcodeproj"
SCHEME="Tiley"
CONFIGURATION="Release"
ARCHIVE_PATH="${ARCHIVE_PATH:-build/Tiley.xcarchive}"
APP_NAME="${APP_NAME:-Tiley.app}"
INSTALL_DIR="/Applications"
INSTALLED_APP_PATH="$INSTALL_DIR/$APP_NAME"

mkdir -p build

if pgrep -x "Tiley" >/dev/null 2>&1; then
  echo "Tiley is running. Quitting app..."
  osascript -e 'tell application "Tiley" to quit' >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x "Tiley" >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done

  if pgrep -x "Tiley" >/dev/null 2>&1; then
    echo "Tiley did not quit in time. Sending TERM..."
    pkill -TERM -x "Tiley" || true
  fi
fi

if [[ -d "$INSTALLED_APP_PATH" ]]; then
  echo "Removing existing app: $INSTALLED_APP_PATH"
  rm -rf "$INSTALLED_APP_PATH"
fi

echo "Cleaning previous archive: $ARCHIVE_PATH"
rm -rf "$ARCHIVE_PATH"

echo "Building archive"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive

ARCHIVED_APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
if [[ ! -d "$ARCHIVED_APP_PATH" ]]; then
  echo "Archived app not found at: $ARCHIVED_APP_PATH"
  exit 1
fi

echo "Copying app to $INSTALL_DIR"
cp -R "$ARCHIVED_APP_PATH" "$INSTALL_DIR/"

echo "Launching $APP_NAME"
open "$INSTALLED_APP_PATH"

echo "Done: $INSTALLED_APP_PATH"
