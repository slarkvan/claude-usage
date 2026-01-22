#!/bin/bash
set -e

APP_NAME="ClaudeUsageWidget"
VERSION="${1:-1.0.0}"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"

echo "Building $APP_NAME v$VERSION..."

# 1. Build release binary
swift build -c release

# 2. Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# 4. Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.syncwise.claudewidget</string>
    <key>CFBundleName</key>
    <string>Claude Usage Widget</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage Widget</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>Claude Usage Widget needs calendar access to add reset time reminders.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Claude Usage Widget needs calendar access to add reset time reminders.</string>
</dict>
</plist>
EOF

echo "Created $APP_BUNDLE"

# 5. Create DMG
echo "Creating DMG..."
rm -f "$BUILD_DIR/$DMG_NAME"

# Create a temporary directory for DMG contents
DMG_TEMP="$BUILD_DIR/dmg-temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -r "$APP_BUNDLE" "$DMG_TEMP/"

# Add Applications symlink for drag-to-install
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

rm -rf "$DMG_TEMP"

echo ""
echo "✅ Build complete!"
echo "   App: $APP_BUNDLE"
echo "   DMG: $BUILD_DIR/$DMG_NAME"
echo ""
echo "Note: The app is not code-signed. Users may need to:"
echo "  Right-click -> Open -> Open (to bypass Gatekeeper)"
echo "  Or: xattr -cr /Applications/$APP_NAME.app"
