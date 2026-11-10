#!/usr/bin/env bash
# Build a double-clickable macOS .app from the SwiftPM FSMonitor product.
# Intended for Apple Silicon macOS with Xcode/Swift. Does not notarize or Developer ID sign.
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
# Marketing version for Info.plist (CFBundleShortVersionString). Must NOT be a git tag string.
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo 0)}"
GIT_SHA="${GIT_SHA:-$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "package-macos-app.sh must run on macOS." >&2
  exit 1
fi

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "MARKETING_VERSION must look like 0.1.0 (got: $MARKETING_VERSION)" >&2
  exit 1
fi

echo "==> Environment"
sw_vers
xcodebuild -version
swift --version
uname -m

MACHINE="$(uname -m)"
if [[ "$MACHINE" != "arm64" ]]; then
  echo "This packaging path only supports Apple Silicon (arm64). Runner is: $MACHINE" >&2
  exit 1
fi

echo "==> Test"
swift test --parallel

echo "==> Build $CONFIGURATION product $PRODUCT_NAME (arm64)"
swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME" --arch arm64

BIN="$BUILD_DIR/arm64-apple-macosx/$CONFIGURATION/$PRODUCT_NAME"
if [[ ! -x "$BIN" ]]; then
  BIN="$BUILD_DIR/$CONFIGURATION/$PRODUCT_NAME"
fi
if [[ ! -x "$BIN" ]]; then
  BIN="$(find "$BUILD_DIR" -type f -path "*/$CONFIGURATION/$PRODUCT_NAME" -perm -111 | head -n 1 || true)"
fi
if [[ -z "${BIN}" || ! -x "$BIN" ]]; then
  echo "Built executable not found under $BUILD_DIR" >&2
  exit 1
fi

echo "Binary: $BIN"
file "$BIN"
ARCHS="$(lipo -archs "$BIN" 2>/dev/null || true)"
echo "lipo archs: $ARCHS"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "Refusing to package non-arm64-only binary (got: '$ARCHS')." >&2
  exit 1
fi

APP_ROOT="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_ROOT" "$OUTPUT_DIR/${APP_NAME}.app.zip" "$OUTPUT_DIR/${APP_NAME}.app.sha256"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"

ICONSET="$ROOT/Resources/AppIcon.iconset"
ICNS_OUT="$OUTPUT_DIR/AppIcon.icns"
if [[ ! -d "$ICONSET" ]]; then
  echo "Missing $ICONSET (D2 iconset)." >&2
  exit 1
fi
echo "==> Build AppIcon.icns from verified D2 iconset"
# Require the standard macOS iconset names before iconutil.
for required in \
  icon_16x16.png diana.k@example.org \
  icon_32x32.png ivan.p@example.net \
  icon_128x128.png wendy.h@example.net \
  icon_256x256.png wendy.h@example.net \
  icon_512x512.png walt.e@example.net
do
  test -f "$ICONSET/$required" || { echo "Missing iconset entry: $required" >&2; exit 1; }
done
# Re-check source asset hashes against handoff when present.
if [[ -f "$ROOT/Assets/icons/D2/TECHNICAL-HANDOFF.json" ]]; then
  python3 - <<'PY'
import hashlib, json
from pathlib import Path
root = Path("Assets/icons/D2")
hand = json.loads((root / "TECHNICAL-HANDOFF.json").read_text())
for entry in hand:
    path = root / entry["file"]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != entry["sha256"].lower():
        raise SystemExit(f"D2 hash mismatch for {entry['file']}: {digest}")
print("D2 asset hashes OK")
PY
fi
iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
test -f "$ICNS_OUT"

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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>${MARKETING_VERSION}</string>
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
cp "$ICNS_OUT" "$APP_ROOT/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc codesign (not Developer ID, not notarized)"
codesign --force --deep --sign - --timestamp=none "$APP_ROOT"
codesign --verify --verbose=2 "$APP_ROOT"
codesign -dv --verbose=4 "$APP_ROOT" 2>&1 | tee "$OUTPUT_DIR/codesign.txt" || true
spctl --assess --type execute -v "$APP_ROOT" 2>&1 | tee "$OUTPUT_DIR/spctl.txt" || true

cat > "$OUTPUT_DIR/BUILD_INFO.txt" <<INFO
product=$APP_NAME.app
bundle_id=$BUNDLE_ID
marketing_version=$MARKETING_VERSION
cfbundle_short_version_string=$MARKETING_VERSION
build_number=$BUILD_NUMBER
git_sha=$GIT_SHA
architectures=arm64
min_system=$MIN_SYSTEM
signing=ad-hoc
notarized=no
developer_id=no
spctl_assess=rejected_expected_for_adhoc
icon=D2_huluwa_nova_selected
icon_notes=16_32_eye_detail_weak;large_size_forward_bias;not_dock_validated;no_menubar_autohide_animation
runner_machine=$MACHINE
swift=$(swift --version 2>&1 | head -n 1)
built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
real_mac_interaction_verified=no
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
