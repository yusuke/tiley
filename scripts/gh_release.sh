#!/bin/zsh

# Creates a GitHub Release, uploads the notarized archive (ZIP or DMG), and pushes the updated appcast.xml.
# Run this after sparkle_sign_appcast.sh completes successfully.
#
# Prerequisites:
#   - gh CLI installed and authenticated (https://cli.github.com/)
#   - sparkle_sign_appcast.sh has been run (builds build/sparkle/Tiley-X.Y.Z.{zip,dmg} and docs/appcast.xml)
#
# Usage:
#   scripts/gh_release.sh            # uploads ZIP (default)
#   scripts/gh_release.sh --dmg      # uploads DMG
#
# Environment variables (optional):
#   REPO            - GitHub repository (default: yusuke/tiley)
#   DRAFT           - Create as draft release: true/false (default: false)
#   PRERELEASE      - Mark as prerelease: true/false (default: false)
#   RELEASE_NOTES   - Path to release notes file (default: auto-generated from git log)

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

# Settings
REPO="${REPO:-yusuke/tiley}"
EXPORT_PATH="${EXPORT_PATH:-build/export}"
APP_NAME="${APP_NAME:-Tiley.app}"
APPCAST_DIR="${APPCAST_DIR:-build/sparkle}"
DRAFT="${DRAFT:-false}"
PRERELEASE="${PRERELEASE:-false}"
RELEASE_NOTES="${RELEASE_NOTES:-}"

EXPORTED_APP_PATH="$EXPORT_PATH/$APP_NAME"

# Determine archive extension
if [[ "$FORMAT" == "dmg" ]]; then
  ARCHIVE_EXT="dmg"
else
  ARCHIVE_EXT="zip"
fi

# Verify prerequisites
if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI not found. Install from https://cli.github.com/"
  exit 1
fi

if [[ ! -d "$EXPORTED_APP_PATH" ]]; then
  echo "Error: Exported app not found at $EXPORTED_APP_PATH"
  echo "Run scripts/release_notarize.sh first."
  exit 1
fi

# Extract version from the app bundle
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$EXPORTED_APP_PATH/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$EXPORTED_APP_PATH/Contents/Info.plist")
TAG="v$APP_VERSION"
echo "Releasing $TAG (build $BUILD_NUMBER) — format: $FORMAT"

# Verify the versioned archive exists
VERSIONED_ARCHIVE="$APPCAST_DIR/Tiley-${APP_VERSION}.${ARCHIVE_EXT}"
if [[ ! -f "$VERSIONED_ARCHIVE" ]]; then
  echo "Error: Versioned archive not found at $VERSIONED_ARCHIVE"
  echo "Run scripts/sparkle_sign_appcast.sh first$([ "$FORMAT" = "dmg" ] && echo " with --dmg")."
  exit 1
fi

# Verify appcast.xml has been updated
if [[ ! -f "$PROJECT_ROOT/docs/appcast.xml" ]]; then
  echo "Error: docs/appcast.xml not found"
  echo "Run scripts/sparkle_sign_appcast.sh first."
  exit 1
fi

# Check if tag already exists
if git -C "$PROJECT_ROOT" rev-parse "$TAG" &>/dev/null; then
  echo "Error: Tag $TAG already exists."
  echo "If you want to re-release, delete the tag first:"
  echo "  git tag -d $TAG && git push origin :refs/tags/$TAG"
  exit 1
fi

# Check if release already exists
if gh release view "$TAG" --repo "$REPO" &>/dev/null 2>&1; then
  echo "Error: GitHub Release $TAG already exists."
  echo "Delete it first with: gh release delete $TAG --repo $REPO"
  exit 1
fi

# Commit and push appcast.xml
echo "Committing docs/appcast.xml"
git -C "$PROJECT_ROOT" add docs/appcast.xml
if git -C "$PROJECT_ROOT" diff --cached --quiet; then
  echo "docs/appcast.xml already committed, skipping."
else
  git -C "$PROJECT_ROOT" commit -m "Update appcast.xml for $TAG"
fi
git -C "$PROJECT_ROOT" push

# Create tag
echo "Creating tag $TAG"
git -C "$PROJECT_ROOT" tag "$TAG"
git -C "$PROJECT_ROOT" push origin "$TAG"

# Build gh release flags
GH_FLAGS=("--repo" "$REPO" "--title" "Tiley $APP_VERSION")

if [[ "$DRAFT" == "true" ]]; then
  GH_FLAGS+=("--draft")
fi

if [[ "$PRERELEASE" == "true" ]]; then
  GH_FLAGS+=("--prerelease")
fi

if [[ -n "$RELEASE_NOTES" && -f "$RELEASE_NOTES" ]]; then
  GH_FLAGS+=("--notes-file" "$RELEASE_NOTES")
else
  # Extract release notes from CHANGELOG.md for this version
  CHANGELOG="$PROJECT_ROOT/CHANGELOG.md"
  NOTES=""
  if [[ -f "$CHANGELOG" ]]; then
    # Extract the section between ## [X.Y.Z] and the next ## heading
    NOTES=$(awk "/^## \\[${APP_VERSION}\\]/{found=1;next} /^## \\[/{if(found)exit} found" "$CHANGELOG" \
      | grep -v '^\[.*\]: ' \
      | awk '{lines[NR]=$0} END{for(i=1;i<=NR;i++)if(length(lines[i])>0){s=i;break} for(i=NR;i>=1;i--)if(length(lines[i])>0){e=i;break} for(i=s;i<=e;i++)print lines[i]}')
  fi

  if [[ -z "$NOTES" ]]; then
    echo "Warning: No entry for $APP_VERSION found in CHANGELOG.md, falling back to git log"
    PREV_TAG=$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 "$TAG^" 2>/dev/null || echo "")
    if [[ -n "$PREV_TAG" ]]; then
      NOTES=$(git -C "$PROJECT_ROOT" log --pretty=format:"- %s" "$PREV_TAG..$TAG" -- ':!docs/' ':!scripts/')
    else
      NOTES=$(git -C "$PROJECT_ROOT" log --pretty=format:"- %s" "$TAG" -- ':!docs/' ':!scripts/' | head -20)
    fi
  fi

  if [[ -z "$NOTES" ]]; then
    NOTES="Tiley $APP_VERSION"
  fi
  GH_FLAGS+=("--notes" "$NOTES")
fi

# Create GitHub Release and upload archive
ASSET_NAME="Tiley-${APP_VERSION}.${ARCHIVE_EXT}"
echo "Creating GitHub Release $TAG"
gh release create "$TAG" "${GH_FLAGS[@]}" "$VERSIONED_ARCHIVE#$ASSET_NAME"

RELEASE_URL="https://github.com/$REPO/releases/tag/$TAG"
echo ""
echo "=== GitHub Release published ==="
echo "  Tag:       $TAG"
echo "  Release:   $RELEASE_URL"
echo "  Asset:     $ASSET_NAME"
echo "  Appcast:   docs/appcast.xml (committed & pushed)"
