#!/bin/zsh
#
# test_quarantine_dmg.sh
#
# Notarize済みのDMGにquarantine属性を付与し、マウントして
# App Translocation経由での起動をテストするスクリプト。
#
# 使い方:
#   scripts/test_quarantine_dmg.sh [dmg_path]
#
# dmg_path を省略すると build/Tiley.dmg を使用します。
#
# 確認ポイント:
#   - ダイアログが「コピーしますか？」（移動ではない）と表示されること
#   - /Applications/Tiley.app にコピーされること
#   - コピー後にアプリが正常に再起動すること

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

DMG_PATH="${1:-build/Tiley.dmg}"

if [[ ! -f "$DMG_PATH" ]]; then
    echo "Error: DMG not found at $DMG_PATH"
    echo "Usage: $0 [dmg_path]"
    exit 1
fi

# 既にマウントされているTileyボリュームがあればデタッチ
EXISTING_MOUNT=$(hdiutil info | grep -A1 "$DMG_PATH" | grep '/Volumes/' | awk '{print $NF}' 2>/dev/null || true)
if [[ -n "$EXISTING_MOUNT" ]]; then
    echo "Detaching existing mount: $EXISTING_MOUNT"
    hdiutil detach "$EXISTING_MOUNT" -force 2>/dev/null || true
fi

echo "Adding quarantine attribute to $DMG_PATH"
xattr -w com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" "$DMG_PATH"

echo "Verifying quarantine attribute:"
xattr -p com.apple.quarantine "$DMG_PATH"

echo ""
echo "Mounting DMG..."
hdiutil attach "$DMG_PATH" -noautoopen

echo ""
echo "Opening Tiley.app from DMG..."
echo "(App Translocation should activate due to quarantine attribute)"
open "/Volumes/Tiley/Tiley.app"

echo ""
echo "=== Test Checklist ==="
echo "1. Dialog should say 'Copy to Applications' (NOT 'Move')"
echo "2. App should be copied to /Applications/Tiley.app"
echo "3. App should relaunch from /Applications"
echo "4. DMG eject dialog should appear"
