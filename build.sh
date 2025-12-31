#!/bin/bash
set -e

echo "Building CopyCopy..."

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/version.env"

# Build universal (arm64 + x86_64) using SwiftPM cross-compilation.
MIN_VER="${MIN_SYSTEM_VERSION:-14.0}"
ARM_TRIPLE="arm64-apple-macosx${MIN_VER}"
X64_TRIPLE="x86_64-apple-macosx${MIN_VER}"

SCRATCH="$ROOT_DIR/.build"

# Keep build caches inside the repo (helps in sandboxed environments).
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
SWIFTPM_COMMON_ARGS=(--disable-sandbox)

swift build "${SWIFTPM_COMMON_ARGS[@]}" -c release --triple "$ARM_TRIPLE" --scratch-path "$SCRATCH"
swift build "${SWIFTPM_COMMON_ARGS[@]}" -c release --triple "$X64_TRIPLE" --scratch-path "$SCRATCH"

ARM_BUILD_DIR="$(swift build "${SWIFTPM_COMMON_ARGS[@]}" -c release --triple "$ARM_TRIPLE" --scratch-path "$SCRATCH" --show-bin-path)"
X64_BUILD_DIR="$(swift build "${SWIFTPM_COMMON_ARGS[@]}" -c release --triple "$X64_TRIPLE" --scratch-path "$SCRATCH" --show-bin-path)"

ARM_BIN_PATH="$ARM_BUILD_DIR/CopyCopy"
X64_BIN_PATH="$X64_BUILD_DIR/CopyCopy"

UNIVERSAL_DIR="$ROOT_DIR/.build/universal"
mkdir -p "$UNIVERSAL_DIR"
UNIVERSAL_BIN="$UNIVERSAL_DIR/CopyCopy"

lipo -create "$ARM_BIN_PATH" "$X64_BIN_PATH" -output "$UNIVERSAL_BIN"

# Create app bundle
APP_DIR="$ROOT_DIR/dist/CopyCopy.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

cp "$UNIVERSAL_BIN" "$APP_DIR/Contents/MacOS/CopyCopy"

# Copy SwiftPM resource bundles (e.g. KeyboardShortcuts) into the app.
shopt -s nullglob
for bundle in "$ARM_BUILD_DIR"/*.bundle; do
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
shopt -u nullglob

# Copy Sparkle.framework (if present) into Frameworks.
SPARKLE_SRC="$ARM_BUILD_DIR/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
    cp -R "$SPARKLE_SRC" "$APP_DIR/Contents/Frameworks/"

    # Update rpath to find framework in app bundle
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/CopyCopy" 2>/dev/null || true
fi

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
BUILD_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

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

 # Sign (optional): set APP_IDENTITY to a Developer ID identity string.
if [[ -n "${APP_IDENTITY:-}" ]]; then
  codesign --force --deep --timestamp --options runtime --sign "$APP_IDENTITY" "$APP_DIR"
  echo "✅ Signed with: $APP_IDENTITY"

  # Notarize (requires APP_IDENTITY and APP_PASSWORD set)
  if [[ -n "${APP_PASSWORD:-}" && -n "${APPLE_ID:-}" ]]; then
    echo "📤 Uploading for notarization..."
    OUTPUT=$(xcrun notarytool submit "$APP_DIR" \
      --apple-id "$APPLE_ID" \
      --password "$APP_PASSWORD" \
      --team-id "$TEAM_ID" \
      --wait 2>&1 | tee /dev/tty)

    REQUEST_ID=$(echo "$OUTPUT" | grep -oE 'id: [0-9a-f-]+' | cut -d' ' -f2)

    if [[ -n "$REQUEST_ID" ]]; then
      echo "📎 Notarization complete (ID: $REQUEST_ID)"
      xcrun stapler staple "$APP_DIR"
      echo "✅ Stapled notarization ticket"
    fi
  fi
else
  # Ad-hoc signing helps diagnostics but won't satisfy Gatekeeper for downloaded apps.
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
  echo "⚠️  Ad-hoc signed (won't pass Gatekeeper - right-click Open to bypass)"
fi

echo ""
echo "Build complete: dist/CopyCopy.app"
