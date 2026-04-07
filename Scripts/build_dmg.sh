#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Anna.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_STAGING_DIR="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/Anna.dmg"
SCHEME="Anna"
PROJECT_PATH="$ROOT_DIR/Anna.xcodeproj"

echo "==> Preparing build directories"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_STAGING_DIR" "$DMG_PATH"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR" "$DMG_STAGING_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required. Install full Xcode and select it with xcode-select." >&2
  exit 1
fi

echo "==> Generating Xcode project"
cd "$ROOT_DIR"
xcodegen generate

echo "==> Archiving app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/Anna.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Preparing DMG contents"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

echo "==> Creating DMG"
hdiutil create \
  -volname "Anna" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Done"
echo "$DMG_PATH"
echo ""
echo "NOTE: Since the app is not notarized, macOS Gatekeeper may block it."
echo "To open: Right-click the app > Open, or go to"
echo "System Settings > Privacy & Security > 'Open Anyway'"
