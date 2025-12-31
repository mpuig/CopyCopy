#!/bin/bash
set -e

echo "Building CopyCopy..."

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/version.env"

# Build release binary using Swift Package Manager
swift build -c release

# Get the binary path
BUILD_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BUILD_DIR/CopyCopy"

# Create app bundle
APP_DIR="$ROOT_DIR/dist/CopyCopy.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/CopyCopy"

# Copy Sparkle framework
SPARKLE_SRC="$BUILD_DIR/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
    cp -R "$SPARKLE_SRC" "$APP_DIR/Contents/Frameworks/"

    # Update rpath to find framework in app bundle
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/CopyCopy" 2>/dev/null || true
fi

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
BUILD_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
MIN_VER="${MIN_SYSTEM_VERSION:-14.0}"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_VER}</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CopyCopyBuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
  <key>CopyCopyGitCommit</key><string>${GIT_COMMIT}</string>
  <key>CopyCopyHomepageURL</key><string>${HOMEPAGE_URL}</string>
</dict>
</plist>
PLIST

chmod +x "$APP_DIR/Contents/MacOS/CopyCopy"
chmod -R u+w "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -name '._*' -delete 2>/dev/null || true

echo ""
echo "Build complete: dist/CopyCopy.app"
