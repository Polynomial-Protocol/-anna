#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Anna — Production DMG Builder
#
# Creates a polished DMG with:
#   - Anna.app icon on the left
#   - Applications alias on the right
#   - Custom window sizing and icon placement
#   - Proper Finder presentation
#
# Usage:
#   ./Scripts/build_dmg.sh              # Standard build
#   ./Scripts/build_dmg.sh --sign       # Build + codesign (requires Developer ID)
# ─────────────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Anna.xcarchive"
DMG_STAGING_DIR="$BUILD_DIR/dmg_staging"
DMG_TEMP="$BUILD_DIR/Anna_temp.dmg"
DMG_PATH="$BUILD_DIR/Anna.dmg"
SCHEME="Anna"
PROJECT_PATH="$ROOT_DIR/Anna.xcodeproj"
SIGN_BUILD=false

if [[ "${1:-}" == "--sign" ]]; then
    SIGN_BUILD=true
fi

# ─── Preflight ───────────────────────────────────────────────

for cmd in xcodegen xcodebuild hdiutil; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: $cmd is required but not found." >&2
        exit 1
    fi
done

# ─── Clean ───────────────────────────────────────────────────

echo "==> Cleaning build directory"
rm -rf "$ARCHIVE_PATH" "$DMG_STAGING_DIR" "$DMG_TEMP" "$DMG_PATH"
mkdir -p "$BUILD_DIR" "$DMG_STAGING_DIR"

# ─── Generate Xcode Project ─────────────────────────────────

echo "==> Generating Xcode project"
cd "$ROOT_DIR"
xcodegen generate

# ─── Archive ─────────────────────────────────────────────────

echo "==> Archiving release build"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_ENTITLEMENTS="$ROOT_DIR/Anna.entitlements" \
    archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/Anna.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "error: App bundle not found at $APP_PATH" >&2
    exit 1
fi

# ─── Optional: Code Signing ─────────────────────────────────

if $SIGN_BUILD; then
    echo "==> Signing with Developer ID"
    # Find the Developer ID Application identity
    IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
    if [[ -z "$IDENTITY" ]]; then
        echo "error: No Developer ID Application certificate found in keychain." >&2
        echo "Install one from developer.apple.com or run without --sign." >&2
        exit 1
    fi
    echo "    Using identity: $IDENTITY"

    # Sign all embedded frameworks and dylibs first
    find "$APP_PATH/Contents/Frameworks" "$APP_PATH/Contents/Resources" \
        \( -name "*.dylib" -o -name "*.framework" \) -print0 2>/dev/null | \
    while IFS= read -r -d '' item; do
        codesign --force --options runtime --sign "$IDENTITY" --timestamp "$item" || true
    done

    # Sign the piper binary
    if [[ -f "$APP_PATH/Contents/Resources/piper/piper" ]]; then
        codesign --force --options runtime --sign "$IDENTITY" --timestamp \
            "$APP_PATH/Contents/Resources/piper/piper"
    fi

    # Sign the main app bundle
    codesign --force --deep --options runtime --sign "$IDENTITY" --timestamp \
        --entitlements "$ROOT_DIR/Anna.entitlements" \
        "$APP_PATH"

    echo "==> Verifying signature"
    codesign --verify --deep --strict "$APP_PATH"
    echo "    Signature valid."
fi

# ─── Prepare DMG Contents ───────────────────────────────────

echo "==> Preparing DMG contents"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

# ─── Create Temporary Read-Write DMG ────────────────────────

echo "==> Creating DMG"
# Calculate size needed (app size + 20MB headroom)
APP_SIZE_KB=$(du -sk "$DMG_STAGING_DIR" | awk '{print $1}')
DMG_SIZE_KB=$((APP_SIZE_KB + 20480))

hdiutil create \
    -volname "Anna" \
    -size "${DMG_SIZE_KB}k" \
    -fs HFS+ \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDRW \
    "$DMG_TEMP"

# ─── Style the DMG Window ───────────────────────────────────

echo "==> Styling DMG window"
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP" 2>&1)
MOUNT_DIR=$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/.*' | head -1)

if [[ -z "$MOUNT_DIR" ]]; then
    echo "error: Failed to mount DMG. Output:" >&2
    echo "$MOUNT_OUTPUT" >&2
    exit 1
fi
echo "    Mounted at: $MOUNT_DIR"

# Set custom volume icon before Finder styles it
if [[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]]; then
    cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

# Use AppleScript to configure Finder window appearance
osascript <<EOF
tell application "Finder"
    tell disk "Anna"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 760, 440}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set background color of viewOptions to {3084, 3084, 4112}
        set position of item "Anna.app" of container window to {140, 160}
        set position of item "Applications" of container window to {420, 160}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Ensure .DS_Store is written
sync

hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force 2>/dev/null

# ─── Convert to Compressed Read-Only DMG ────────────────────

echo "==> Compressing final DMG"
hdiutil convert "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

rm -f "$DMG_TEMP"

# ─── Done ────────────────────────────────────────────────────

DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
echo ""
echo "==> Build complete!"
echo "    Output:  $DMG_PATH"
echo "    Size:    $DMG_SIZE"
echo ""

if $SIGN_BUILD; then
    echo "==> Next steps:"
    echo "    1. Notarize:  xcrun notarytool submit '$DMG_PATH' --keychain-profile 'AC_PASSWORD' --wait"
    echo "    2. Staple:    xcrun stapler staple '$DMG_PATH'"
    echo "    3. Verify:    spctl --assess --type open --context context:primary-signature '$DMG_PATH'"
else
    echo "==> This build is NOT signed or notarized."
    echo "    To distribute, re-run with: ./Scripts/build_dmg.sh --sign"
    echo ""
    echo "    For local testing: Right-click Anna.app > Open, or go to"
    echo "    System Settings > Privacy & Security > 'Open Anyway'"
fi
