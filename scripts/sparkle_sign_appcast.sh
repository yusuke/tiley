#!/bin/zsh

# Signs the notarized archive (ZIP or DMG) with Sparkle EdDSA and updates appcast.xml.
# Run this after release_notarize.sh completes successfully.
#
# Usage:
#   scripts/sparkle_sign_appcast.sh          # uses ZIP (default)
#   scripts/sparkle_sign_appcast.sh --dmg    # uses DMG
#
# Environment variables (optional):
#   DOWNLOAD_URL_PREFIX  - Base URL for update downloads
#                          (default: https://github.com/yusuke/tiley/releases/download)
#   APPCAST_DIR          - Directory where appcast.xml and archives are managed
#                          (default: build/sparkle)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

FORMAT=zip
for arg in "$@"; do
  case "$arg" in
    --dmg) FORMAT=dmg ;;
  esac
done

# Sparkle CLI tools
SPARKLE_BIN="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"

# Paths from release_notarize.sh output
DMG_PATH="${DMG_PATH:-build/Tiley.dmg}"
ZIP_PATH="${ZIP_PATH:-build/Tiley.zip}"
EXPORT_PATH="${EXPORT_PATH:-build/export}"
APP_NAME="${APP_NAME:-Tiley.app}"
EXPORTED_APP_PATH="$EXPORT_PATH/$APP_NAME"

# Determine which archive to use
if [[ "$FORMAT" == "dmg" ]]; then
  ARCHIVE_PATH="$DMG_PATH"
  ARCHIVE_EXT="dmg"
else
  ARCHIVE_PATH="$ZIP_PATH"
  ARCHIVE_EXT="zip"
fi

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

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "Error: Notarized archive not found at $ARCHIVE_PATH"
  echo "Run scripts/release_notarize.sh first$([ "$FORMAT" = "dmg" ] && echo " with --dmg")."
  exit 1
fi

if [[ ! -d "$EXPORTED_APP_PATH" ]]; then
  echo "Error: Exported app not found at $EXPORTED_APP_PATH"
  exit 1
fi

echo "Distribution format: $FORMAT"

# Extract version from the app bundle
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$EXPORTED_APP_PATH/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$EXPORTED_APP_PATH/Contents/Info.plist")
echo "App version: $APP_VERSION (build $BUILD_NUMBER)"

# Check if this version+build already exists in appcast.xml
EXISTING_APPCAST="$PROJECT_ROOT/docs/appcast.xml"
if [[ -f "$EXISTING_APPCAST" ]]; then
  # Check for matching shortVersionString AND version (build number)
  if grep -q "<sparkle:shortVersionString>${APP_VERSION}</sparkle:shortVersionString>" "$EXISTING_APPCAST" \
    && grep -q "<sparkle:version>${BUILD_NUMBER}</sparkle:version>" "$EXISTING_APPCAST"; then
    echo "Error: Version $APP_VERSION (build $BUILD_NUMBER) already exists in appcast.xml."
    echo "Bump the version or build number before releasing."
    exit 1
  fi
fi

# Promote [Unreleased] to [X.Y.Z] in all CHANGELOG files if no section exists yet
RELEASE_DATE=$(date +%Y-%m-%d)
CHANGELOG_FILES=("$PROJECT_ROOT/CHANGELOG.md")
for f in "$PROJECT_ROOT"/changelogs/CHANGELOG.*.md; do
  [[ -f "$f" ]] && CHANGELOG_FILES+=("$f")
done

for CHANGELOG in "${CHANGELOG_FILES[@]}"; do
  CHANGELOG_BASENAME=$(basename "$CHANGELOG")
  if ! grep -q "^## \\[${APP_VERSION}\\]" "$CHANGELOG"; then
    echo "Promoting [Unreleased] to [${APP_VERSION}] - ${RELEASE_DATE} in ${CHANGELOG_BASENAME}"
    # Replace "## [Unreleased]" with "## [Unreleased]\n\n## [X.Y.Z] - YYYY-MM-DD"
    sed -i '' "s/^## \\[Unreleased\\]/## [Unreleased]\\
\\
## [${APP_VERSION}] - ${RELEASE_DATE}/" "$CHANGELOG"
    # Update link references at the bottom (only in main CHANGELOG.md)
    if [[ "$CHANGELOG_BASENAME" == "CHANGELOG.md" ]]; then
      if grep -q '^\[Unreleased\]:' "$CHANGELOG"; then
        # Update existing Unreleased link to compare from new version
        sed -i '' "s|^\[Unreleased\]:.*|[Unreleased]: https://github.com/yusuke/tiley/compare/v${APP_VERSION}...HEAD|" "$CHANGELOG"
        # Add version link if not present
        if ! grep -q "^\\[${APP_VERSION}\\]:" "$CHANGELOG"; then
          sed -i '' "/^\[Unreleased\]:/a\\
[${APP_VERSION}]: https://github.com/yusuke/tiley/releases/tag/v${APP_VERSION}
" "$CHANGELOG"
        fi
      else
        # No link references yet, append them
        printf '\n[Unreleased]: https://github.com/yusuke/tiley/compare/v%s...HEAD\n[%s]: https://github.com/yusuke/tiley/releases/tag/v%s\n' \
          "$APP_VERSION" "$APP_VERSION" "$APP_VERSION" >> "$CHANGELOG"
      fi
    fi
  else
    echo "${CHANGELOG_BASENAME} already has section for ${APP_VERSION}"
  fi
done

# Sign the archive with Sparkle EdDSA (key is read from Keychain automatically)
echo "Signing $ARCHIVE_EXT with Sparkle EdDSA"
SIGNATURE=$("$SIGN_UPDATE" "$ARCHIVE_PATH" -p)
echo "EdDSA signature: $SIGNATURE"

# Prepare appcast directory
mkdir -p "$APPCAST_DIR"

# Copy existing appcast.xml if present in docs/
if [[ -f "$PROJECT_ROOT/docs/appcast.xml" && ! -f "$APPCAST_DIR/appcast.xml" ]]; then
  echo "Copying existing appcast.xml from docs/"
  cp "$PROJECT_ROOT/docs/appcast.xml" "$APPCAST_DIR/"
fi

# Copy the notarized archive with version-tagged filename
VERSIONED_ARCHIVE="Tiley-${APP_VERSION}.${ARCHIVE_EXT}"
cp "$ARCHIVE_PATH" "$APPCAST_DIR/$VERSIONED_ARCHIVE"
echo "Copied $ARCHIVE_EXT to $APPCAST_DIR/$VERSIONED_ARCHIVE"

# Generate/update appcast.xml
DOWNLOAD_URL="$DOWNLOAD_URL_PREFIX/v$APP_VERSION/$VERSIONED_ARCHIVE"
echo "Download URL: $DOWNLOAD_URL"

echo "Generating appcast.xml"
"$GENERATE_APPCAST" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX/v$APP_VERSION/" \
  -o "$APPCAST_DIR/appcast.xml" \
  "$APPCAST_DIR"

# Embed localized release notes from CHANGELOG files into appcast.xml
#
# English comes from CHANGELOG.md (root); other languages from
# changelogs/CHANGELOG.{lang}.md.  Each <description> gets an xml:lang
# attribute so Sparkle can pick the right one for the user's locale.
APPCAST_XML="$APPCAST_DIR/appcast.xml"
CHANGELOG_LANGS=("en" "ja" "ko" "zh-Hans" "zh-Hant" "de" "es" "fr" "it" "pt-BR" "ru")
EMBEDDED_COUNT=0

# Helper: extract version section from a changelog and convert to HTML
extract_and_convert() {
  local changelog_file="$1"
  local version="$2"

  [[ -f "$changelog_file" ]] || return 1

  local notes
  notes=$(awk "/^## \\[${version}\\]/{found=1;next} /^## \\[/{if(found)exit} found" "$changelog_file" \
    | grep -v '^\[.*\]: ' \
    | awk '{lines[NR]=$0} END{for(i=1;i<=NR;i++)if(length(lines[i])>0){s=i;break} for(i=NR;i>=1;i--)if(length(lines[i])>0){e=i;break} for(i=s;i<=e;i++)print lines[i]}')

  [[ -z "$notes" ]] && return 1

  echo "$notes" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/^### \(.*\)/<h3>\1<\/h3>/' \
    -e 's/^- \(.*\)/<li>\1<\/li>/' \
  | awk 'BEGIN{il=0} /<li>/{if(il==0){printf "<ul>\n";il=1}} /<h3>/{if(il==1){printf "</ul>\n";il=0}} /^$/{next} {print} END{if(il==1)printf "</ul>\n"}'
}

# Collect all versions present in the appcast
APPCAST_VERSIONS=($(grep -oE '<sparkle:shortVersionString>[^<]+</sparkle:shortVersionString>' "$APPCAST_XML" \
  | sed 's/<[^>]*>//g'))

for version in "${APPCAST_VERSIONS[@]}"; do
  for lang in "${CHANGELOG_LANGS[@]}"; do
    if [[ "$lang" == "en" ]]; then
      changelog_file="$PROJECT_ROOT/CHANGELOG.md"
    else
      changelog_file="$PROJECT_ROOT/changelogs/CHANGELOG.${lang}.md"
    fi

    HTML_NOTES=$(extract_and_convert "$changelog_file" "$version")
    if [[ -z "$HTML_NOTES" ]]; then
      echo "Warning: No $lang entry for $version in $(basename "$changelog_file"), skipping"
      continue
    fi

    ESCAPED_HTML=$(echo "$HTML_NOTES" | sed -e 's/[\/&]/\\&/g' | tr '\n' '\a')
    sed -i '' "/<title>${version}<\/title>/a\\
            <description xml:lang=\"${lang}\"><![CDATA[${ESCAPED_HTML}]]></description>
" "$APPCAST_XML"
    # Restore newlines from \a placeholders
    sed -i '' "s/$(printf '\a')/\\
/g" "$APPCAST_XML"
    EMBEDDED_COUNT=$((EMBEDDED_COUNT + 1))
  done
done

if [[ $EMBEDDED_COUNT -gt 0 ]]; then
  echo "Embedded release notes in appcast.xml ($EMBEDDED_COUNT languages)"
else
  echo "Warning: No release notes embedded in appcast.xml"
fi

# Copy updated appcast.xml to docs/ for GitHub Pages
mkdir -p "$PROJECT_ROOT/docs"
cp "$APPCAST_DIR/appcast.xml" "$PROJECT_ROOT/docs/appcast.xml"
echo "Updated docs/appcast.xml"

echo ""
echo "=== Sparkle signing complete ==="
echo "  Version:     $APP_VERSION (build $BUILD_NUMBER)"
echo "  Signature:   $SIGNATURE"
echo "  Appcast:     docs/appcast.xml"
echo "  Archive:     $APPCAST_DIR/$VERSIONED_ARCHIVE"
echo ""
echo "Next steps:"
echo "  1. Commit docs/appcast.xml"
echo "  2. Create GitHub Release tagged v$APP_VERSION"
echo "  3. Upload $APPCAST_DIR/$VERSIONED_ARCHIVE to the release"
