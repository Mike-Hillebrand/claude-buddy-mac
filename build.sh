#!/bin/sh
# Builds Buddy.app with plain swiftc (no Xcode needed, Command Line Tools are enough).
#   ./build.sh            → build/Buddy.app
#   ./build.sh install    → build + copy to /Applications + (re)launch
#   ./build.sh release    → build + zip → build/Buddy-<version>.zip (for GitHub Releases)
set -e
cd "$(dirname "$0")"

APP_NAME="Buddy"
BUNDLE_ID="com.mikehillebrand.buddy"
VERSION="1.6.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
MIN_OS="14.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ compiling ($ARCH, macOS $MIN_OS+)"
swiftc \
  -O -swift-version 5 \
  -target "$ARCH-apple-macos$MIN_OS" \
  -sdk "$SDK" \
  -framework AppKit -framework SwiftUI -framework ServiceManagement \
  -lsqlite3 \
  -module-name "$APP_NAME" \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  Sources/Core/*.swift Sources/App/*.swift

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Mike Hillebrand Media</string>
</dict>
</plist>
EOF

cp hooks/buddy-hook.sh hooks/buddy-statusline.sh hooks/install-hooks.py "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/buddy-hook.sh"

# App icon: rendered from Resources/AppIcon-1024.png at build time (iconutil ships with macOS).
if [ -f Resources/AppIcon-1024.png ] && command -v iconutil >/dev/null; then
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s*2))
    sips -z $d $d Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" && rm -rf "$ICONSET"
fi

echo "→ signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
xattr -cr "$APP" 2>/dev/null || true

echo "✓ built $APP"

case "$1" in
  install)
    echo "→ installing to /Applications"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    echo "✓ launched /Applications/$APP_NAME.app"
    ;;
  release)
    ZIP="$BUILD_DIR/$APP_NAME-$VERSION-$ARCH.zip"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    echo "✓ release archive $ZIP"
    ;;
esac
