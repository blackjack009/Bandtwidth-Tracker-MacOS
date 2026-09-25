#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BandwidthTracker"
BUNDLE_NAME="Bandwidth Tracker.app"
BUILD_DIR=".build/release"
STAGE_DIR="./$BUNDLE_NAME"
INSTALL_DIR="/Applications/$BUNDLE_NAME"

echo "→ Building release..."
swift build -c release

echo "→ Assembling $BUNDLE_NAME..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Contents/MacOS"
mkdir -p "$STAGE_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$STAGE_DIR/Contents/MacOS/$APP_NAME"
cp Info.plist "$STAGE_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$STAGE_DIR" >/dev/null 2>&1 || true

echo "→ Deploying to /Applications..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5
rm -rf "$INSTALL_DIR"
cp -R "$STAGE_DIR" "$INSTALL_DIR"

# Refresh LaunchServices registration
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$INSTALL_DIR" >/dev/null 2>&1 || true

# Clean staging copy so folder stays tidy
rm -rf "$STAGE_DIR"

echo "→ Launching..."
open "$INSTALL_DIR"

sleep 1
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "✓ Running from $INSTALL_DIR"
else
    echo "✗ Failed to launch — check ~/Library/Logs/DiagnosticReports/"
    exit 1
fi
