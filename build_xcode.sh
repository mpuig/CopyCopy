#!/bin/bash
set -e

echo "Building CopyCopy..."

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# Build using xcodebuild (handles XCFramework linking)
echo "Building with xcodebuild..."
xcodebuild -scheme CopyCopy \
    -destination 'platform=macOS,arch=arm64' \
    -configuration Release \
    -derivedDataPath "$ROOT_DIR/.build/derived" \
    clean build

# Find the built binary
BUILT_BINARY="$ROOT_DIR/.build/derived/Build/Products/Release/CopyCopy"

if [ ! -f "$BUILT_BINARY" ]; then
    echo "Error: Could not find built binary at $BUILT_BINARY"
    exit 1
fi

# Create app bundle structure
APP_DIR="$ROOT_DIR/dist/CopyCopy.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

# Copy binary
cp "$BUILT_BINARY" "$APP_DIR/Contents/MacOS/CopyCopy"

# Copy all required frameworks
for framework in "$ROOT_DIR/.build/derived/Build/Products/Release/"*.framework; do
    if [ -d "$framework" ]; then
        cp -R "$framework" "$APP_DIR/Contents/Frameworks/"
        echo "  Copied $(basename "$framework")"
    fi
done

# Fix rpath for Sparkle
install_name_tool -change "@rpath/Sparkle.framework/Versions/B/Sparkle" "@executable_path/../Frameworks/Sparkle.framework/Versions/B/Sparkle" "$APP_DIR/Contents/MacOS/CopyCopy" 2>/dev/null || true

# Add proper rpath for frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/CopyCopy" 2>/dev/null || true

# Copy SwiftPM resource bundles
for bundle in "$ROOT_DIR/.build/derived/Build/Products/Release/"*.bundle; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" "$APP_DIR/Contents/Resources/"
    fi
done

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>CopyCopy</string>
  <key>CFBundleExecutable</key><string>CopyCopy</string>
  <key>CFBundleIdentifier</key><string>com.copycopy.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>CopyCopy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>https://copycopy.app/appcast.xml</string>
  <key>SUPublicEDKey</key><string>kv+bKebrBiVvqksoUmDzJmBrD6LoUJ01Zu+Xh95zooM=</string>
</dict>
</plist>
PLIST

# Sign
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo ""
echo "✅ Build complete: dist/CopyCopy.app"
echo "   Models download on first use to ~/.copycopy/models/"
