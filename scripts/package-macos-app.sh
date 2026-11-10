#!/usr/bin/env bash
# Build a double-clickable macOS .app from the SwiftPM FSMonitor product.
# Intended to run on macOS with Xcode/Swift. Does not notarize or Developer ID sign.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT_NAME="FSMonitor"
APP_NAME="FSMonitor"
BUNDLE_ID="me.atschx.fs-monitor"
MIN_SYSTEM="13.0"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-"$ROOT/dist"}"
BUILD_DIR="${BUILD_DIR:-"$ROOT/.build"}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "package-macos-app.sh must run on macOS." >&2
  exit 1
fi

echo "==> Environment"
sw_vers
xcodebuild -version
swift --version
uname -m

echo "==> Test"
swift test --parallel

echo "==> Build $CONFIGURATION product $PRODUCT_NAME"
swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME"

BIN="$BUILD_DIR/$CONFIGURATION/$PRODUCT_NAME"
if [[ ! -x "$BIN" ]]; then
  # SwiftPM may place binaries under a triple subdirectory.
  BIN="$(find "$BUILD_DIR" -type f -path "*/$CONFIGURATION/$PRODUCT_NAME" -perm -111 | head -n 1 || true)"
fi
if [[ -z "${BIN}" || ! -x "$BIN" ]]; then
  echo "Built executable not found under $BUILD_DIR" >&2
  exit 1
fi

echo "Binary: $BIN"
file "$BIN"
lipo -archs "$BIN" || true

VERSION="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo "untagged")"
SHORT_VERSION="${SHORT_VERSION:-0.1.0-test}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo 0)}"

APP_ROOT="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_ROOT" "$OUTPUT_DIR/${APP_NAME}.app.zip" "$OUTPUT_DIR/${APP_NAME}.app.sha256"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"

cat > "$APP_ROOT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleExecutable</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>FSMonitor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${SHORT_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_SYSTEM}</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
</dict>
</plist>
PLIST

cp "$BIN" "$APP_ROOT/Contents/MacOS/$PRODUCT_NAME"
chmod +x "$APP_ROOT/Contents/MacOS/$PRODUCT_NAME"

echo "==> Ad-hoc codesign (not Developer ID, not notarized)"
codesign --force --deep --sign - --timestamp=none "$APP_ROOT"
codesign --verify --verbose=2 "$APP_ROOT"
codesign -dv --verbose=4 "$APP_ROOT" 2>&1 | tee "$OUTPUT_DIR/codesign.txt" || true
spctl --assess --type execute -v "$APP_ROOT" 2>&1 | tee "$OUTPUT_DIR/spctl.txt" || true

ARCHS="$(lipo -archs "$APP_ROOT/Contents/MacOS/$PRODUCT_NAME" 2>/dev/null || echo unknown)"
cat > "$OUTPUT_DIR/BUILD_INFO.txt" <<INFO
product=$APP_NAME.app
bundle_id=$BUNDLE_ID
short_version=$SHORT_VERSION
build_number=$BUILD_NUMBER
git_describe=$VERSION
architectures=$ARCHS
min_system=$MIN_SYSTEM
signing=ad-hoc
notarized=no
developer_id=no
runner_machine=$(uname -m)
swift=$(swift --version 2>&1 | head -n 1)
built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
INFO

echo "==> Zip"
(
  cd "$OUTPUT_DIR"
  ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.app.zip"
  shasum -a 256 "$APP_NAME.app.zip" | tee "$APP_NAME.app.sha256"
)

echo "==> Package layout"
find "$APP_ROOT" -print | sed 's|^|  |'
cat "$OUTPUT_DIR/BUILD_INFO.txt"
echo "ZIP=$OUTPUT_DIR/$APP_NAME.app.zip"
echo "SHA256_FILE=$OUTPUT_DIR/$APP_NAME.app.sha256"
