#!/bin/sh
# Builds Buddy.app with plain swiftc (no Xcode needed, Command Line Tools are enough).
#   ./build.sh            → build/Buddy.app
#   ./build.sh install    → build + copy to /Applications + (re)launch
set -e
cd "$(dirname "$0")"

APP_NAME="Buddy"
BUNDLE_ID="com.mikehillebrand.buddy"
VERSION="1.0.0"
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

cp hooks/buddy-hook.sh hooks/install-hooks.py "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/buddy-hook.sh"
[ -f assets/AppIcon.icns ] && cp assets/AppIcon.icns "$APP/Contents/Resources/"

echo "→ signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
xattr -cr "$APP" 2>/dev/null || true

echo "✓ built $APP"

if [ "$1" = "install" ]; then
  echo "→ installing to /Applications"
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
  echo "✓ launched /Applications/$APP_NAME.app"
fi
