#!/usr/bin/env bash
set -euo pipefail

# Anna — Clean Uninstall Script
# Removes the app, its preferences, caches, logs, and TCC permission entries
# so that a fresh reinstall behaves as if Anna was never installed.

BUNDLE_ID="com.polynomial.anna"
APP_NAME="Anna"

echo "==> Uninstalling $APP_NAME ($BUNDLE_ID)"

# 1. Quit the app if running
if pgrep -f "$APP_NAME" > /dev/null 2>&1; then
    echo "    Quitting $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
    pkill -f "$APP_NAME" 2>/dev/null || true
fi

# 2. Remove the app bundle
APP_PATH="/Applications/$APP_NAME.app"
if [[ -d "$APP_PATH" ]]; then
    echo "    Removing $APP_PATH"
    rm -rf "$APP_PATH"
fi

# 3. Remove UserDefaults / preferences
PLIST_PATH="$HOME/Library/Preferences/${BUNDLE_ID}.plist"
if [[ -f "$PLIST_PATH" ]]; then
    echo "    Removing preferences: $PLIST_PATH"
    rm -f "$PLIST_PATH"
fi
defaults delete "$BUNDLE_ID" 2>/dev/null || true

# 4. Remove caches and application support
echo "    Removing caches and support data..."
rm -rf "$HOME/Library/Caches/$BUNDLE_ID" 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/$BUNDLE_ID" 2>/dev/null || true
rm -rf "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState" 2>/dev/null || true
rm -rf "$HOME/Library/HTTPStorages/$BUNDLE_ID" 2>/dev/null || true

# 5. Remove Anna logs
echo "    Removing logs..."
rm -rf "$HOME/.anna" 2>/dev/null || true

# 6. Reset TCC permissions (requires Full Disk Access or SIP disabled for user TCC.db)
TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
if [[ -f "$TCC_DB" ]]; then
    echo "    Attempting to remove TCC entries for $BUNDLE_ID..."
    sqlite3 "$TCC_DB" "DELETE FROM access WHERE client = '$BUNDLE_ID';" 2>/dev/null && \
        echo "    TCC entries removed." || \
        echo "    Could not modify TCC.db (this is normal — you may need to manually remove Anna from System Settings > Privacy & Security)."
fi

# 7. Kill cfprefsd to flush preference caches
killall cfprefsd 2>/dev/null || true

echo "==> $APP_NAME has been fully uninstalled."
echo "    If permissions still appear in System Settings, remove them manually:"
echo "    System Settings > Privacy & Security > [Microphone/Accessibility/Automation/Screen Recording]"
